`timescale 1ns/1ps

module tb_core_ebreak_trap;

    // ============================================================
    // Señales del DUT
    // ============================================================

    logic        clk;
    logic        rst;

    // ============================================================
    // IMEM síncrona
    // ============================================================

    localparam int unsigned IMEM_WORDS = 256;

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // Handshake de memoria de datos.
    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;

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
    // Memoria de instrucciones
    // ============================================================
        assign dmem_rdata = 64'd0;

    // ============================================================
    // IMEM síncrona real
    //
    // Configuración rápida ya validada:
    //
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    //
    // Permite turnover y mantiene un fetch/ciclo después
    // del llenado inicial.
    // ============================================================

        imem_sync_model #(
            .MEM_WORDS  (IMEM_WORDS),
            .GNT_DELAY  (0),
            .RESP_DELAY (1)
        ) u_imem (
            .clk      (clk),
            .rst      (rst),

            .req_i    (imem_req),
            .gnt_o    (imem_gnt),
            .addr_i   (imem_addr),

            .rvalid_o (imem_rvalid),
            .rdata_o  (imem_rdata)
        );

    // ============================================================
    // DUT
    // ============================================================

    // =========================================================
    // Adaptador temporal para los modelos combinacionales
    // de memoria usados por este testbench.
    //
    // El core utiliza el handshake definitivo, mientras este
    // adaptador proporciona grant inmediato y rvalid +1 ciclo.
    // =========================================================
        dmem_legacy_compat u_dmem_legacy_compat (
            .clk      (clk),
            .rst      (rst),
            .req_i    (dmem_req),
            .gnt_o    (dmem_gnt),
            .rvalid_o (dmem_rvalid),
            .error_o  (dmem_error)
        );

        core_top dut (
            .clk        (clk),
            .rst        (rst),

            .imem_req    (imem_req),
            .imem_addr   (imem_addr),
            .imem_gnt    (imem_gnt),
            .imem_rvalid (imem_rvalid),
            .imem_rdata  (imem_rdata),

            .dmem_rdata (dmem_rdata),

            .dmem_req    (dmem_req),
            .dmem_gnt    (dmem_gnt),
            .dmem_rvalid (dmem_rvalid),
            .dmem_error  (dmem_error),
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
    // Encoders mínimos
    // ============================================================

        localparam logic [11:0] CSR_MTVEC  = 12'h305;
        localparam logic [11:0] CSR_MEPC   = 12'h341;
        localparam logic [11:0] CSR_MCAUSE = 12'h342;

        localparam logic [2:0] F3_CSRRW = 3'b001;
        localparam logic [2:0] F3_CSRRS = 3'b010;

        localparam logic [31:0] INSTR_EBREAK = 32'h0010_0073;
        localparam logic [31:0] INSTR_MRET   = 32'h3020_0073;
        localparam logic [31:0] INSTR_HALT_LOOP = 32'h0000_006f; // jal x0, 0

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
    // Main:
    //   0x00: x1 = 0x40
    //   0x04: mtvec = x1
    //   0x10: EBREAK
    //   0x14: x5 = 0x123   <- debe ejecutarse después de MRET
    //   0x18: x6 = 0x456   <- debe ejecutarse después de MRET
    //
    // Handler en 0x40:
    //   x20 = mcause       <- debe ser 3, breakpoint
    //   x21 = mepc         <- debe ser 0x10, dirección del EBREAK
    //   x22 = mepc + 4     <- 0x14
    //   mepc = x22
    //   MRET
    // ============================================================

        integer i;

        initial begin
            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                u_imem.mem[i] = enc_nop();
            end

            // ----------------------------
            // Programa principal
            // ----------------------------

            u_imem.mem[0] = enc_addi(5'd1, 5'd0, 12'h040);                    // x1 = 0x40
            u_imem.mem[1] = enc_csr(CSR_MTVEC, 5'd1, F3_CSRRW, 5'd0);         // mtvec = x1
            u_imem.mem[2] = enc_nop();
            u_imem.mem[3] = enc_nop();

            u_imem.mem[4] = INSTR_EBREAK;                                     // PC = 0x10

            u_imem.mem[5] = enc_addi(5'd5, 5'd0, 12'h123);                    // x5 = 0x123
            u_imem.mem[6] = enc_addi(5'd6, 5'd0, 12'h456);                    // x6 = 0x456
            u_imem.mem[7] = INSTR_HALT_LOOP;                                  // detener aquí: jal x0, 0

            // ----------------------------
            // Handler en mtvec = 0x40
            // índice = 0x40 / 4 = 16
            // ----------------------------

            u_imem.mem[16] = enc_csr(CSR_MCAUSE, 5'd0, F3_CSRRS, 5'd20);      // x20 = mcause
            u_imem.mem[17] = enc_csr(CSR_MEPC,   5'd0, F3_CSRRS, 5'd21);      // x21 = mepc

            u_imem.mem[18] = enc_nop();
            u_imem.mem[19] = enc_nop();

            u_imem.mem[20] = enc_addi(5'd22, 5'd21, 12'd4);                   // x22 = mepc + 4

            u_imem.mem[21] = enc_nop();
            u_imem.mem[22] = enc_nop();

            u_imem.mem[23] = enc_csr(CSR_MEPC, 5'd22, F3_CSRRW, 5'd0);        // mepc = x22

            u_imem.mem[24] = enc_nop();
            u_imem.mem[25] = enc_nop();

            u_imem.mem[26] = INSTR_MRET;                                      // return to 0x14
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
            $dumpfile("build/tb_core_ebreak_trap.vcd");
            $dumpvars(0, tb_core_ebreak_trap);

            errors = 0;

            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;

            repeat (120) @(posedge clk);

            $display("---- INICIO CHECK EBREAK TRAP ----");

            check_reg(1,  64'h0000_0000_0000_0040, "mtvec base en x1");
            check_reg(20, 64'h0000_0000_0000_0003, "mcause breakpoint");
            check_reg(21, 64'h0000_0000_0000_0010, "mepc apunta a EBREAK");
            check_reg(22, 64'h0000_0000_0000_0014, "mepc ajustado");
            check_reg(5,  64'h0000_0000_0000_0123, "retorno post-EBREAK x5");
            check_reg(6,  64'h0000_0000_0000_0456, "retorno post-EBREAK x6");

            if (errors == 0) begin
                $display("==========================================");
                $display("PASS: EBREAK + trap breakpoint + MRET funcionando");
                $display("==========================================");
            end
            else begin
                $display("==========================================");
                $display("ERROR: tb_core_ebreak_trap falló con %0d errores", errors);
                $display("==========================================");
            end

            $finish;
        end

endmodule


