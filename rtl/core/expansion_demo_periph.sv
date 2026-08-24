`timescale 1ns/1ps

module expansion_demo_periph #(
    parameter logic [63:0] ID_VALUE      = 64'h0000_0000_4558_5030, // ASCII parcial: "EXP0"
    parameter logic [63:0] VERSION_VALUE = 64'h0000_0000_0000_0001
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        exp_valid_i,
    input  logic        exp_we_i,
    input  logic [63:0] exp_addr_i,
    input  logic [63:0] exp_wdata_i,
    input  logic [7:0]  exp_wstrb_i,
    input  logic [1:0]  exp_size_i,

    output logic        exp_ready_o,
    output logic [63:0] exp_rdata_o,
    output logic        exp_error_o
);

    localparam logic [11:0] REG_ID        = 12'h000;
    localparam logic [11:0] REG_VERSION   = 12'h008;
    localparam logic [11:0] REG_CONTROL   = 12'h010;
    localparam logic [11:0] REG_STATUS    = 12'h018;
    localparam logic [11:0] REG_OPERAND_A = 12'h020;
    localparam logic [11:0] REG_OPERAND_B = 12'h028;
    localparam logic [11:0] REG_RESULT    = 12'h030;

    logic [11:0] reg_offset;

    logic [63:0] control_r;
    logic [63:0] operand_a_r;
    logic [63:0] operand_b_r;
    logic [63:0] result_r;
    logic        done_r;

    logic [63:0] status_value;
    logic        known_reg;
    logic        write_to_read_only;

    logic [63:0] control_write_value;
    logic        status_w1c_done;
    logic [63:0] operand_a_write_value;
    logic [63:0] operand_b_write_value;

    // El mapa interno es de registros de 64 bits alineados a 8 bytes.
    assign reg_offset = {exp_addr_i[11:3], 3'b000};

    function automatic logic [63:0] apply_wstrb;
        input logic [63:0] old_value;
        input logic [63:0] new_value;
        input logic [7:0]  byte_en;
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < 8; i = i + 1) begin
                if (byte_en[i]) begin
                    apply_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
        end
    endfunction

    assign control_write_value   = apply_wstrb(control_r,   exp_wdata_i, exp_wstrb_i);
    assign status_w1c_done = exp_wstrb_i[0] && exp_wdata_i[1];
    assign operand_a_write_value = apply_wstrb(operand_a_r, exp_wdata_i, exp_wstrb_i);
    assign operand_b_write_value = apply_wstrb(operand_b_r, exp_wdata_i, exp_wstrb_i);

    // STATUS[0] = busy, STATUS[1] = done, STATUS[2] = error.
    // Esta primera versión responde en un ciclo y nunca queda busy.
    assign status_value = {61'd0, 1'b0, done_r, 1'b0};

    always_comb begin
        known_reg = 1'b1;

        case (reg_offset)
            REG_ID,
            REG_VERSION,
            REG_CONTROL,
            REG_STATUS,
            REG_OPERAND_A,
            REG_OPERAND_B,
            REG_RESULT: begin
                known_reg = 1'b1;
            end

            default: begin
                known_reg = 1'b0;
            end
        endcase
    end

    always_comb begin
        write_to_read_only = 1'b0;

        if (exp_we_i) begin
            case (reg_offset)
                REG_ID,
                REG_VERSION,
                REG_RESULT: begin
                    write_to_read_only = 1'b1;
                end

                default: begin
                    write_to_read_only = 1'b0;
                end
            endcase
        end
    end

    // Contrato de temporización inicial:
    // - exp_ready_o siempre en 1: no se insertan esperas todavía.
    // - exp_rdata_o es combinacional para lecturas.
    // - exp_error_o indica acceso inválido o escritura a registro read-only.
    assign exp_ready_o = 1'b1;
    assign exp_error_o = exp_valid_i && (!known_reg || write_to_read_only);

    always_comb begin
        case (reg_offset)
            REG_ID:        exp_rdata_o = ID_VALUE;
            REG_VERSION:   exp_rdata_o = VERSION_VALUE;
            REG_CONTROL:   exp_rdata_o = control_r;
            REG_STATUS:    exp_rdata_o = status_value;
            REG_OPERAND_A: exp_rdata_o = operand_a_r;
            REG_OPERAND_B: exp_rdata_o = operand_b_r;
            REG_RESULT:    exp_rdata_o = result_r;
            default:       exp_rdata_o = 64'd0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            control_r   <= 64'd0;
            operand_a_r <= 64'd0;
            operand_b_r <= 64'd0;
            result_r    <= 64'd0;
            done_r      <= 1'b0;
        end
        else if (exp_valid_i && exp_ready_o && exp_we_i && !exp_error_o) begin
            case (reg_offset)
                REG_CONTROL: begin
                    // CONTROL[0] = start. Se auto-limpia.
                    // CONTROL[1] = clear_done. Se auto-limpia.
                    control_r <= 64'd0;

                    if (control_write_value[1]) begin
                        done_r <= 1'b0;
                    end

                    if (control_write_value[0]) begin
                        result_r <= operand_a_r + operand_b_r;
                        done_r   <= 1'b1;
                    end
                end

                REG_STATUS: begin
                    // STATUS[1] funciona como W1C para limpiar done.
                    // No se debe limpiar done si el byte que contiene STATUS[1] no fue escrito.
                    if (status_w1c_done) begin
                        done_r <= 1'b0;
                    end
                end

                REG_OPERAND_A: begin
                    operand_a_r <= operand_a_write_value;
                end

                REG_OPERAND_B: begin
                    operand_b_r <= operand_b_write_value;
                end

                default: begin
                    // Registros read-only o direcciones inválidas no llegan aquí
                    // porque exp_error_o bloquea la escritura.
                end
            endcase
        end
    end

    wire _unused_ok = 1'b0 && &{
        1'b0,
        exp_addr_i[63:12],
        exp_addr_i[2:0],
        exp_size_i,
        1'b0
    };

endmodule
