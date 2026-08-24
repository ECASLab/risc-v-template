`timescale 1ns/1ps

module csr_file #(
    parameter logic [63:0] RESET_MTVEC = 64'h0000_0000_0000_0100
) (
    input  logic        clk,
    input  logic        rst,

    // Acceso CSR desde EX
    input  logic        access_valid,
    input  logic [11:0] access_addr,
    input  logic        access_read_en,
    input  logic        access_write_en,
    input  logic [1:0]  access_cmd,
    input  logic [63:0] access_wdata,

    output logic [63:0] access_rdata,
    output logic        access_illegal,

    // Eventos especiales
    input  logic        trap_valid,
    input  logic [63:0] trap_pc,
    input  logic [63:0] trap_cause,
    input  logic [63:0] trap_value,

    input  logic        mret_valid,

    // Salidas útiles para el core
    output logic [63:0] mtvec_o,
    output logic [63:0] mepc_o,
    output logic [63:0] mcause_o,
    output logic [63:0] mtval_o
);

    // ---------------------------------------------------------
    // Direcciones CSR mínimas que vamos a soportar en esta iteración
    // ---------------------------------------------------------
    localparam logic [11:0] CSR_MSTATUS = 12'h300;
    localparam logic [11:0] CSR_MISA    = 12'h301;
    localparam logic [11:0] CSR_MTVEC   = 12'h305;
    localparam logic [11:0] CSR_MEPC    = 12'h341;
    localparam logic [11:0] CSR_MCAUSE  = 12'h342;
    localparam logic [11:0] CSR_MTVAL   = 12'h343;

    // CSRs de identificación de máquina.
    // Se exponen como lectura válida para mejorar compatibilidad con pruebas
    // arquitecturales y software bare-metal mínimo.
    localparam logic [11:0] CSR_MVENDORID = 12'hF11;
    localparam logic [11:0] CSR_MARCHID   = 12'hF12;
    localparam logic [11:0] CSR_MIMPID    = 12'hF13;
    localparam logic [11:0] CSR_MHARTID   = 12'hF14;

    // ---------------------------------------------------------
    // Comandos CSR
    // 00 = none
    // 01 = RW
    // 10 = RS
    // 11 = RC
    // ---------------------------------------------------------
    localparam logic [1:0] CSR_CMD_RW   = 2'b01;
    localparam logic [1:0] CSR_CMD_RS   = 2'b10;
    localparam logic [1:0] CSR_CMD_RC   = 2'b11;

    // ---------------------------------------------------------
    // misa fija de esta implementación
    // MXL = 2 -> RV64
    // I = bit 8
    // ---------------------------------------------------------
    localparam logic [63:0] MISA_RESET_VALUE =
        (64'h2 << 62) |
        (64'h1 << 8);

    // ---------------------------------------------------------
    // Registros internos
    // ---------------------------------------------------------
    logic        mstatus_mie_r;
    logic        mstatus_mpie_r;
    logic [1:0]  mstatus_mpp_r;

    logic [63:0] misa_r;
    logic [63:0] mtvec_r;
    logic [63:0] mepc_r;
    logic [63:0] mcause_r;
    logic [63:0] mtval_r;

    logic [63:0] selected_csr_value;
    logic        selected_csr_exists;
    logic [63:0] write_value;

    // ---------------------------------------------------------
    // Empaque mínimo de mstatus para RV64
    // Solo implementamos MIE, MPIE y MPP en esta iteración.
    // ---------------------------------------------------------
    function automatic logic [63:0] pack_mstatus(
        input logic mie,
        input logic mpie,
        input logic [1:0] mpp
    );
        logic [63:0] tmp;
        begin
            tmp = 64'd0;
            tmp[3]     = mie;
            tmp[7]     = mpie;
            tmp[12:11] = mpp;
            pack_mstatus = tmp;
        end
    endfunction

    // ---------------------------------------------------------
    // Selección CSR actual
    // ---------------------------------------------------------
    always_comb begin
        selected_csr_value  = 64'd0;
        selected_csr_exists = 1'b1;

        case (access_addr)
            CSR_MSTATUS: selected_csr_value = pack_mstatus(mstatus_mie_r, mstatus_mpie_r, mstatus_mpp_r);
            CSR_MISA:    selected_csr_value = misa_r;
            CSR_MTVEC:   selected_csr_value = mtvec_r;
            CSR_MEPC:    selected_csr_value = mepc_r;
            CSR_MCAUSE:  selected_csr_value = mcause_r;
            CSR_MTVAL:   selected_csr_value = mtval_r;

            // CSRs de identificación.
            // Valores mínimos válidos para un núcleo académico de un solo hart.
            CSR_MVENDORID: selected_csr_value = 64'd0;
            CSR_MARCHID:   selected_csr_value = 64'd0;
            CSR_MIMPID:    selected_csr_value = 64'd0;
            CSR_MHARTID:   selected_csr_value = 64'd0;
            default: begin
                selected_csr_value  = 64'd0;
                selected_csr_exists = 1'b0;
            end
        endcase
    end

    // ---------------------------------------------------------
    // Lectura / detección de acceso ilegal
    // ---------------------------------------------------------
    always_comb begin
        access_rdata   = selected_csr_value;
        access_illegal = 1'b0;

        if (access_valid && (access_read_en || access_write_en) && !selected_csr_exists) begin
            access_illegal = 1'b1;
        end

        // CSRs de identificación: lectura permitida, escritura ilegal.
        // Esto evita que CSRRW/CSRRWI modifiquen registros que deben comportarse
        // como read-only en esta implementación mínima.
        if (access_valid && access_write_en) begin
            case (access_addr)
                CSR_MVENDORID,
                CSR_MARCHID,
                CSR_MIMPID,
                CSR_MHARTID: begin
                    access_illegal = 1'b1;
                end

                default: begin
                    // Sin cambio.
                end
            endcase
        end
    end

    // ---------------------------------------------------------
    // Cálculo del valor a escribir
    // ---------------------------------------------------------
    always_comb begin
        case (access_cmd)
            CSR_CMD_RW:   write_value = access_wdata;
            CSR_CMD_RS:   write_value = selected_csr_value | access_wdata;
            CSR_CMD_RC:   write_value = selected_csr_value & ~access_wdata;
            default:      write_value = selected_csr_value;
        endcase
    end

    // ---------------------------------------------------------
    // Estado secuencial CSR
    // Prioridad:
    //   1) reset
    //   2) trap
    //   3) mret
    //   4) escritura CSR explícita
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus_mie_r  <= 1'b0;
            mstatus_mpie_r <= 1'b1;
            mstatus_mpp_r  <= 2'b11;

            misa_r         <= MISA_RESET_VALUE;
            mtvec_r        <= {RESET_MTVEC[63:2], 2'b00}; // Direct mode
            mepc_r         <= 64'd0;
            mcause_r       <= 64'd0;
            mtval_r        <= 64'd0;
        end
        else if (trap_valid) begin
            mepc_r         <= {trap_pc[63:2], 2'b00};
            mcause_r       <= trap_cause;
            mtval_r        <= trap_value;

            mstatus_mpie_r <= mstatus_mie_r;
            mstatus_mie_r  <= 1'b0;
            mstatus_mpp_r  <= 2'b11; // solo M-mode implementado
        end
        else if (mret_valid) begin
            mstatus_mie_r  <= mstatus_mpie_r;
            mstatus_mpie_r <= 1'b1;
            mstatus_mpp_r  <= 2'b11; // solo M-mode implementado
        end
        else if (access_valid && access_write_en && !access_illegal) begin
            case (access_addr)
                CSR_MSTATUS: begin
                    mstatus_mie_r  <= write_value[3];
                    mstatus_mpie_r <= write_value[7];

                    // Implementación mínima solo M-mode.
                    // No permitimos que software escriba U/S/H en MPP.
                    mstatus_mpp_r  <= 2'b11;
                end

                CSR_MISA: begin
                    // WARL simplificado:
                    // esta implementación anuncia una ISA fija.
                    misa_r <= MISA_RESET_VALUE;
                end

                CSR_MTVEC: begin
                    // Se fuerza Direct mode y alineación a 4 bytes
                    mtvec_r <= {write_value[63:2], 2'b00};
                end

                CSR_MEPC: begin
                    mepc_r <= {write_value[63:2], 2'b00};
                end

                CSR_MCAUSE: begin
                    mcause_r <= write_value;
                end

                CSR_MTVAL: begin
                    mtval_r <= write_value;
                end

                default: begin
                    // Nada: ya quedó marcado como ilegal combinacionalmente.
                end
            endcase
        end
    end

    assign mtvec_o  = mtvec_r;
    assign mepc_o   = mepc_r;
    assign mcause_o = mcause_r;
    assign mtval_o  = mtval_r;

    wire _unused_ok = 1'b0 && &{
        1'b0,
        trap_pc[1:0],
        1'b0
    };

endmodule
