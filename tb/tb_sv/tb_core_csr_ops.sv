`timescale 1ns/1ps

module tb_core_csr_ops;

    // ============================================================
    // Señales del DUT
    // ============================================================

    logic        clk;
    logic        rst;

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // ------------------------------------------------------------
    // Señales dummy para puerto de expansión.
    // Estos testbenches no usan MMIO, por eso el puerto se deja
    // en estado inactivo/seguro para evitar entradas flotantes.
    // ------------------------------------------------------------
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    // ============================================================
    // Memoria de instrucciones mínima
    // ============================================================

    logic [31:0] imem [0:255];

    assign imem_rdata = imem[imem_addr[9:2]];
    assign dmem_rdata = 64'd0;

    // ============================================================
    // DUT
    // ============================================================

    core_top dut (
        .clk        (clk),
        .rst        (rst),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_wstrb (dmem_wstrb),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_size  (dmem_size),

        .exp_valid  (),
        .exp_we     (),
        .exp_addr   (),
        .exp_wdata  (),
        .exp_wstrb  (),
        .exp_size   (),
        .exp_ready  (exp_ready),
        .exp_rdata  (exp_rdata),
        .exp_error  (exp_error)
    );

    // ============================================================
    // Clock
    // ============================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Encoders RISC-V mínimos
    // ============================================================

    localparam logic [11:0] CSR_MSTATUS = 12'h300;
    localparam logic [11:0] CSR_MCAUSE  = 12'h342;

    localparam logic [2:0] F3_CSRRW  = 3'b001;
    localparam logic [2:0] F3_CSRRS  = 3'b010;
    localparam logic [2:0] F3_CSRRC  = 3'b011;
    localparam logic [2:0] F3_CSRRWI = 3'b101;
    localparam logic [2:0] F3_CSRRSI = 3'b110;
    localparam logic [2:0] F3_CSRRCI = 3'b111;

    function automatic logic [31:0] enc_addi(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        enc_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] enc_csr(
        input logic [11:0] csr,
        input logic [4:0]  rs1_or_uimm,
        input logic [2:0]  funct3,
        input logic [4:0]  rd
    );
        enc_csr = {csr, rs1_or_uimm, funct3, rd, 7'b1110011};
    endfunction

    function automatic logic [31:0] enc_nop();
        enc_nop = enc_addi(5'd0, 5'd0, 12'd0);
    endfunction

    // ============================================================
    // Programa
    //
    // Objetivo:
    //   - Validar CSRRWI
    //   - Validar CSRRSI
    //   - Validar CSRRCI
    //   - Validar CSRRS con rs1=x0 como lectura pura
    //   - Validar CSRRS con máscara desde registro
    //   - Validar CSRRC con máscara desde registro
    //   - Validar CSRRW sobre mcause
    //
    // mstatus implementado:
    //   bit 3     = MIE
    //   bit 7     = MPIE
    //   bits 12:11 = MPP
    //
    // En esta implementación mínima solo M-mode:
    //   MPP debe permanecer como 2'b11.
    // ============================================================

    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = enc_nop();
        end

        // Estado esperado al salir de reset:
        // mstatus = 0x1880
        //   MIE  = 0
        //   MPIE = 1
        //   MPP  = 3

        // x1 = old mstatus = 0x1880
        // mstatus <- 0, pero el hardware mínimo debe conservar MPP=3:
        // mstatus esperado después = 0x1800
        imem[0]  = enc_csr(CSR_MSTATUS, 5'd0, F3_CSRRWI, 5'd1);

        imem[1]  = enc_nop();

        // Setear MIE con CSRRSI uimm=8.
        // mstatus esperado después = 0x1808
        imem[2]  = enc_csr(CSR_MSTATUS, 5'd8, F3_CSRRSI, 5'd0);

        imem[3]  = enc_nop();

        // Lectura pura con CSRRS rs1=x0.
        // x2 = 0x1808
        imem[4]  = enc_csr(CSR_MSTATUS, 5'd0, F3_CSRRS, 5'd2);

        // Limpiar MIE con CSRRCI uimm=8.
        // x3 = old mstatus = 0x1808
        // mstatus esperado después = 0x1800
        imem[5]  = enc_csr(CSR_MSTATUS, 5'd8, F3_CSRRCI, 5'd3);

        imem[6]  = enc_nop();

        // Lectura pura.
        // x4 = 0x1800
        imem[7]  = enc_csr(CSR_MSTATUS, 5'd0, F3_CSRRS, 5'd4);

        // x6 = 0x80, máscara para MPIE.
        imem[8]  = enc_addi(5'd6, 5'd0, 12'h080);

        imem[9]  = enc_nop();

        // Setear MPIE con CSRRS usando máscara en x6.
        // x5 = old mstatus = 0x1800
        // mstatus esperado después = 0x1880
        imem[10] = enc_csr(CSR_MSTATUS, 5'd6, F3_CSRRS, 5'd5);

        imem[11] = enc_nop();

        // Limpiar MPIE con CSRRC usando máscara en x6.
        // x7 = old mstatus = 0x1880
        // mstatus esperado después = 0x1800
        imem[12] = enc_csr(CSR_MSTATUS, 5'd6, F3_CSRRC, 5'd7);

        imem[13] = enc_nop();

        // Lectura final de mstatus.
        // x8 = 0x1800
        imem[14] = enc_csr(CSR_MSTATUS, 5'd0, F3_CSRRS, 5'd8);

        // x9 = 0x55
        imem[15] = enc_addi(5'd9, 5'd0, 12'h055);

        imem[16] = enc_nop();

        // Escribir mcause con CSRRW.
        // x10 = old mcause = 0
        // mcause esperado después = 0x55
        imem[17] = enc_csr(CSR_MCAUSE, 5'd9, F3_CSRRW, 5'd10);

        imem[18] = enc_nop();

        // Leer mcause con CSRRS rs1=x0.
        // x11 = 0x55
        imem[19] = enc_csr(CSR_MCAUSE, 5'd0, F3_CSRRS, 5'd11);
    end

    // ============================================================
    // Chequeos
    // ============================================================

    int errors;

    task automatic check_reg(
        input int unsigned idx,
        input logic [63:0] expected,
        input string name
    );
        logic [63:0] got;
        begin
            got = dut.u_regfile.regs[idx];

            if (got !== expected) begin
                $display("ERROR: %s incorrecto. x%0d got=0x%016h exp=0x%016h",
                         name, idx, got, expected);
                errors++;
            end
            else begin
                $display("OK: %-24s x%0d = 0x%016h", name, idx, got);
            end
        end
    endtask

    // ============================================================
    // Secuencia principal
    // ============================================================

    initial begin
        $dumpfile("build/tb_core_csr_ops.vcd");
        $dumpvars(0, tb_core_csr_ops);

        errors = 0;

        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        repeat (100) @(posedge clk);

        $display("---- INICIO CHECK CSR OPS ----");

        check_reg(1,  64'h0000_0000_0000_1880, "CSRRWI old mstatus");
        check_reg(2,  64'h0000_0000_0000_1808, "CSRRS read mstatus");
        check_reg(3,  64'h0000_0000_0000_1808, "CSRRCI old mstatus");
        check_reg(4,  64'h0000_0000_0000_1800, "CSRRS read cleared MIE");
        check_reg(5,  64'h0000_0000_0000_1800, "CSRRS old before MPIE");
        check_reg(6,  64'h0000_0000_0000_0080, "ADDI mask MPIE");
        check_reg(7,  64'h0000_0000_0000_1880, "CSRRC old before clear");
        check_reg(8,  64'h0000_0000_0000_1800, "CSRRS final mstatus");
        check_reg(9,  64'h0000_0000_0000_0055, "ADDI mcause data");
        check_reg(10, 64'h0000_0000_0000_0000, "CSRRW old mcause");
        check_reg(11, 64'h0000_0000_0000_0055, "CSRRS read mcause");

        if (errors == 0) begin
            $display("==========================================");
            $display("PASS: operaciones CSR completas funcionando");
            $display("==========================================");
        end
        else begin
            $display("==========================================");
            $display("ERROR: tb_core_csr_ops falló con %0d errores", errors);
            $display("==========================================");
        end

        $finish;
    end

endmodule


