`timescale 1ns/1ps

module tb_core_dmem_sync_subword;

    // =========================================================
    // Configuración
    // =========================================================

        localparam int unsigned IMEM_WORDS = 256;
        localparam int unsigned DMEM_WORDS = 1024;

        localparam logic [63:0] SOURCE_ADDR =
            64'h0000_0000_0000_0100;

        localparam logic [63:0] SOURCE_VALUE =
            64'h80F1_8001_FFFF_7F81;

        localparam logic [63:0] STORE_INITIAL =
            64'h1122_3344_5566_7788;

        localparam logic [63:0] SB_LINE_ADDR =
            64'h0000_0000_0000_0120;

        localparam logic [63:0] SH_LINE_ADDR =
            64'h0000_0000_0000_0128;

        localparam logic [63:0] SW_LINE_ADDR =
            64'h0000_0000_0000_0130;

        localparam logic [63:0] SD_LINE_ADDR =
            64'h0000_0000_0000_0138;

    // =========================================================
    // Resultados esperados de loads
    // =========================================================

        localparam logic [63:0] EXPECT_LB =
            64'hFFFF_FFFF_FFFF_FF80;

        localparam logic [63:0] EXPECT_LBU =
            64'h0000_0000_0000_00F1;

        localparam logic [63:0] EXPECT_LH =
            64'hFFFF_FFFF_FFFF_80F1;

        localparam logic [63:0] EXPECT_LHU =
            64'h0000_0000_0000_8001;

        localparam logic [63:0] EXPECT_LW =
            64'hFFFF_FFFF_80F1_8001;

        localparam logic [63:0] EXPECT_LWU =
            64'h0000_0000_FFFF_7F81;

        localparam logic [63:0] EXPECT_LD =
            SOURCE_VALUE;

    // =========================================================
    // Datos de store
    // =========================================================

        localparam logic [63:0] SB_SOURCE =
            64'h0000_0000_0000_00AA;

        localparam logic [63:0] SH_SOURCE =
            64'h0000_0000_0000_02BC;

        localparam logic [63:0] SW_SOURCE =
            64'h0000_0000_0000_0345;

    // =========================================================
    // Líneas finales esperadas
    // =========================================================

        localparam logic [63:0] EXPECT_SB_LINE =
            64'hAA22_3344_5566_7788;

        localparam logic [63:0] EXPECT_SH_LINE =
            64'h02BC_3344_5566_7788;

        localparam logic [63:0] EXPECT_SW_LINE =
            64'h0000_0345_5566_7788;

        localparam logic [63:0] EXPECT_SD_LINE =
            SOURCE_VALUE;

    // =========================================================
    // Opcodes
    // =========================================================

        localparam logic [6:0] OPCODE_OP_IMM =
            7'b0010011;

        localparam logic [6:0] OPCODE_LOAD =
            7'b0000011;

        localparam logic [6:0] OPCODE_STORE =
            7'b0100011;

        localparam logic [2:0] F3_ADDI = 3'b000;

        localparam logic [2:0] F3_LB  = 3'b000;
        localparam logic [2:0] F3_LH  = 3'b001;
        localparam logic [2:0] F3_LW  = 3'b010;
        localparam logic [2:0] F3_LD  = 3'b011;
        localparam logic [2:0] F3_LBU = 3'b100;
        localparam logic [2:0] F3_LHU = 3'b101;
        localparam logic [2:0] F3_LWU = 3'b110;

        localparam logic [2:0] F3_SB = 3'b000;
        localparam logic [2:0] F3_SH = 3'b001;
        localparam logic [2:0] F3_SW = 3'b010;
        localparam logic [2:0] F3_SD = 3'b011;

    // =========================================================
    // Clock / reset
    // =========================================================

        logic clk;
        logic rst;

        initial begin
            clk = 1'b0;
            forever #5 clk = ~clk;
        end

    // =========================================================
    // IMEM síncrona
    // =========================================================

        logic        imem_req;
        logic        imem_gnt;
        logic        imem_rvalid;
        logic [63:0] imem_addr;
        logic [31:0] imem_rdata;

    // =========================================================
    // DMEM
    // =========================================================

        logic        dmem_req;
        logic        dmem_gnt;
        logic        dmem_rvalid;
        logic        dmem_error;

        logic [63:0] dmem_rdata;

        logic        dmem_we;
        logic [7:0]  dmem_wstrb;
        logic [63:0] dmem_addr;
        logic [63:0] dmem_wdata;
        logic [1:0]  dmem_size;

    // =========================================================
    // Expansión no utilizada
    // =========================================================

        logic        exp_valid;
        logic        exp_we;
        logic [63:0] exp_addr;
        logic [63:0] exp_wdata;
        logic [7:0]  exp_wstrb;
        logic [1:0]  exp_size;

        logic        exp_ready;
        logic [63:0] exp_rdata;
        logic        exp_error;

        assign exp_ready = 1'b1;
        assign exp_rdata = 64'd0;
        assign exp_error = 1'b0;

    // =========================================================
    // Core
    // =========================================================

        core_top #(
            .RESET_PC(
                64'h0000_0000_0000_0000
            ),
            .TRAP_VECTOR(
                64'h0000_0000_0000_0200
            )
        ) dut (
            .clk         (clk),
            .rst         (rst),

            .imem_req    (imem_req),
            .imem_addr   (imem_addr),
            .imem_gnt    (imem_gnt),
            .imem_rvalid (imem_rvalid),
            .imem_rdata  (imem_rdata),

            .dmem_rdata  (dmem_rdata),

            .dmem_req    (dmem_req),
            .dmem_gnt    (dmem_gnt),
            .dmem_rvalid (dmem_rvalid),
            .dmem_error  (dmem_error),

            .dmem_we     (dmem_we),
            .dmem_wstrb  (dmem_wstrb),
            .dmem_addr   (dmem_addr),
            .dmem_wdata  (dmem_wdata),
            .dmem_size   (dmem_size),

            .exp_valid   (exp_valid),
            .exp_we      (exp_we),
            .exp_addr    (exp_addr),
            .exp_wdata   (exp_wdata),
            .exp_wstrb   (exp_wstrb),
            .exp_size    (exp_size),

            .exp_ready   (exp_ready),
            .exp_rdata   (exp_rdata),
            .exp_error   (exp_error)
        );

    // =========================================================
    // IMEM síncrona real
    //
    // Configuración rápida ya validada:
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    // =========================================================

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

    // =========================================================
    // DMEM síncrona
    //
    // Mantenemos latencia real para asegurarnos de que los
    // accesos subword funcionan también a través del handshake.
    // =========================================================

        dmem_sync_model #(
            .MEM_WORDS   (DMEM_WORDS),
            .GNT_DELAY   (2),
            .RESP_DELAY  (3),
            .FAULT_ENABLE(1'b0)
        ) u_dmem (
            .clk      (clk),
            .rst      (rst),

            .req_i    (dmem_req),
            .gnt_o    (dmem_gnt),

            .addr_i   (dmem_addr),
            .we_i     (dmem_we),
            .wdata_i  (dmem_wdata),
            .wstrb_i  (dmem_wstrb),
            .size_i   (dmem_size),

            .rvalid_o (dmem_rvalid),
            .rdata_o  (dmem_rdata),
            .error_o  (dmem_error)
        );

    // =========================================================
    // Encoders
    // =========================================================

        function automatic logic [31:0] enc_i(
            input logic [11:0] imm,
            input logic [4:0]  rs1,
            input logic [2:0]  funct3,
            input logic [4:0]  rd,
            input logic [6:0]  opcode
        );
            begin
                enc_i = {
                    imm,
                    rs1,
                    funct3,
                    rd,
                    opcode
                };
            end
        endfunction

        function automatic logic [31:0] enc_s(
            input logic [11:0] imm,
            input logic [4:0]  rs2,
            input logic [4:0]  rs1,
            input logic [2:0]  funct3
        );
            begin
                enc_s = {
                    imm[11:5],
                    rs2,
                    rs1,
                    funct3,
                    imm[4:0],
                    OPCODE_STORE
                };
            end
        endfunction

        function automatic logic [31:0] enc_nop();
            begin
                enc_nop = 32'h0000_0013;
            end
        endfunction

        function automatic logic [31:0] enc_halt();
            begin
                enc_halt = 32'h0000_006F;
            end
        endfunction

    // =========================================================
    // Checks
    // =========================================================

        integer errors;

    // =========================================================
    // Registro de errores del scoreboard
    //
    // Esta variable pertenece exclusivamente al testbench.
    // La actualización es deliberadamente bloqueante para que
    // varias comprobaciones fallidas en un mismo ciclo puedan
    // acumularse inmediatamente sin perder incrementos.
    //
    // BLKSEQ se deshabilita únicamente para esta operación de
    // scoreboard; no se deshabilita para el RTL ni globalmente.
    // =========================================================

        task automatic record_error;
            begin
                // verilator lint_off BLKSEQ
                errors = errors + 1;
                // verilator lint_on BLKSEQ
            end
        endtask
    
        task automatic check64(
            input string       name,
            input logic [63:0] got,
            input logic [63:0] expected
        );
            begin
                if (got !== expected) begin
                    $display(
                        "ERROR: %-42s got=0x%016h expected=0x%016h",
                        name,
                        got,
                        expected
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : %-42s = 0x%016h",
                        name,
                        got
                    );
                end
            end
        endtask

        task automatic check_int(
            input string  name,
            input integer got,
            input integer expected
        );
            begin
                if (got != expected) begin
                    $display(
                        "ERROR: %-42s got=%0d expected=%0d",
                        name,
                        got,
                        expected
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : %-42s = %0d",
                        name,
                        got
                    );
                end
            end
        endtask

        task automatic check_load_request(
            input string       name,
            input logic [63:0] expected_addr,
            input logic [1:0]  expected_size
        );
            begin

                check64(
                    {name, " address"},
                    dmem_addr,
                    expected_addr
                );

                if (dmem_we !== 1'b0) begin
                    $display(
                        "ERROR: %s debería ser LOAD",
                        name
                    );

                    record_error();
                end

                if (dmem_wstrb !== 8'h00) begin
                    $display(
                        "ERROR: %s wstrb=0x%02h expected=00",
                        name,
                        dmem_wstrb
                    );

                    record_error();
                end

                if (dmem_size !== expected_size) begin
                    $display(
                        "ERROR: %s size=%b expected=%b",
                        name,
                        dmem_size,
                        expected_size
                    );

                    record_error();
                end
            end
        endtask

        task automatic check_store_request(
            input string       name,
            input logic [63:0] expected_addr,
            input logic [1:0]  expected_size,
            input logic [7:0]  expected_wstrb,
            input logic [63:0] expected_wdata
        );
            begin

                check64(
                    {name, " address"},
                    dmem_addr,
                    expected_addr
                );

                if (dmem_we !== 1'b1) begin
                    $display(
                        "ERROR: %s debería ser STORE",
                        name
                    );

                    record_error();
                end

                if (dmem_size !== expected_size) begin
                    $display(
                        "ERROR: %s size=%b expected=%b",
                        name,
                        dmem_size,
                        expected_size
                    );

                    record_error();
                end

                if (dmem_wstrb !== expected_wstrb) begin
                    $display(
                        "ERROR: %s wstrb=0x%02h expected=0x%02h",
                        name,
                        dmem_wstrb,
                        expected_wstrb
                    );

                    record_error();
                end

                check64(
                    {name, " wdata"},
                    dmem_wdata,
                    expected_wdata
                );
            end
        endtask

    // =========================================================
    // Monitor de protocolo
    // =========================================================

        integer accepted_count;
        integer response_count;

        integer request_wait_cycles;
        integer response_wait_cycles;

        logic transaction_outstanding;

        always @(posedge clk) begin
            if (rst) begin
                accepted_count          <= 0;
                response_count          <= 0;
                request_wait_cycles     <= 0;
                response_wait_cycles    <= 0;
                transaction_outstanding <= 1'b0;
            end
            else begin

                if (dmem_req && !dmem_gnt) begin
                    request_wait_cycles <=
                        request_wait_cycles + 1;
                end

                if (
                    transaction_outstanding &&
                    !dmem_rvalid
                ) begin
                    response_wait_cycles <=
                        response_wait_cycles + 1;
                end

                // =================================================
                // Request aceptado
                // =================================================

                if (dmem_req && dmem_gnt) begin

                    if (transaction_outstanding) begin
                        $display(
                            "ERROR: segunda transacción aceptada mientras existe otra outstanding"
                        );

                        record_error();
                    end

                    case (accepted_count)

                        // -----------------------------------------
                        // Loads
                        // -----------------------------------------

                        0: begin
                            check_load_request(
                                "TX0 LB",
                                64'h0000_0000_0000_0107,
                                2'b00
                            );
                        end

                        1: begin
                            check_load_request(
                                "TX1 LBU",
                                64'h0000_0000_0000_0106,
                                2'b00
                            );
                        end

                        2: begin
                            check_load_request(
                                "TX2 LH",
                                64'h0000_0000_0000_0106,
                                2'b01
                            );
                        end

                        3: begin
                            check_load_request(
                                "TX3 LHU",
                                64'h0000_0000_0000_0104,
                                2'b01
                            );
                        end

                        4: begin
                            check_load_request(
                                "TX4 LW",
                                64'h0000_0000_0000_0104,
                                2'b10
                            );
                        end

                        5: begin
                            check_load_request(
                                "TX5 LWU",
                                64'h0000_0000_0000_0100,
                                2'b10
                            );
                        end

                        6: begin
                            check_load_request(
                                "TX6 LD",
                                64'h0000_0000_0000_0100,
                                2'b11
                            );
                        end

                        // -----------------------------------------
                        // Stores
                        // -----------------------------------------

                        7: begin
                            check_store_request(
                                "TX7 SB",
                                64'h0000_0000_0000_0127,
                                2'b00,
                                8'h80,
                                64'hAA00_0000_0000_0000
                            );
                        end

                        8: begin
                            check_store_request(
                                "TX8 SH",
                                64'h0000_0000_0000_012E,
                                2'b01,
                                8'hC0,
                                64'h02BC_0000_0000_0000
                            );
                        end

                        9: begin
                            check_store_request(
                                "TX9 SW",
                                64'h0000_0000_0000_0134,
                                2'b10,
                                8'hF0,
                                64'h0000_0345_0000_0000
                            );
                        end

                        10: begin
                            check_store_request(
                                "TX10 SD",
                                64'h0000_0000_0000_0138,
                                2'b11,
                                8'hFF,
                                SOURCE_VALUE
                            );
                        end

                        default: begin
                            $display(
                                "ERROR: transacción DMEM inesperada #%0d addr=0x%016h",
                                accepted_count,
                                dmem_addr
                            );

                            record_error();
                        end

                    endcase

                    accepted_count <=
                        accepted_count + 1;

                    transaction_outstanding <=
                        1'b1;
                end

                // =================================================
                // Response
                // =================================================

                if (dmem_rvalid) begin

                    if (!transaction_outstanding) begin
                        $display(
                            "ERROR: dmem_rvalid sin transacción outstanding"
                        );

                        record_error();
                    end

                    if (dmem_error) begin
                        $display(
                            "ERROR: dmem_error inesperado"
                        );

                        record_error();
                    end

                    response_count <=
                        response_count + 1;

                    transaction_outstanding <=
                        1'b0;
                end
            end
        end

    // =========================================================
    // MMIO no debe aparecer
    // =========================================================

        always @(posedge clk) begin
            if (!rst && exp_valid) begin
                $display(
                    "ERROR: acceso MMIO inesperado addr=0x%016h",
                    exp_addr
                );

                record_error();
            end
        end

    // =========================================================
    // Programa
    // =========================================================

        integer i;

        initial begin

            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                u_imem.mem[i] = enc_nop();
            end

            // -----------------------------------------------------
            // x1 = 0x100
            // -----------------------------------------------------

                u_imem.mem[0] =
                    enc_i(
                        12'h100,
                        5'd0,
                        F3_ADDI,
                        5'd1,
                        OPCODE_OP_IMM
                    );

                u_imem.mem[1] = enc_nop();
                u_imem.mem[2] = enc_nop();

            // -----------------------------------------------------
            // Todos los loads RV64I base
            // -----------------------------------------------------

                // LB x2, 7(x1)
                u_imem.mem[3] =
                    enc_i(
                        12'h007,
                        5'd1,
                        F3_LB,
                        5'd2,
                        OPCODE_LOAD
                    );

                // LBU x3, 6(x1)
                u_imem.mem[4] =
                    enc_i(
                        12'h006,
                        5'd1,
                        F3_LBU,
                        5'd3,
                        OPCODE_LOAD
                    );

                // LH x4, 6(x1)
                u_imem.mem[5] =
                    enc_i(
                        12'h006,
                        5'd1,
                        F3_LH,
                        5'd4,
                        OPCODE_LOAD
                    );

                // LHU x5, 4(x1)
                u_imem.mem[6] =
                    enc_i(
                        12'h004,
                        5'd1,
                        F3_LHU,
                        5'd5,
                        OPCODE_LOAD
                    );

                // LW x6, 4(x1)
                u_imem.mem[7] =
                    enc_i(
                        12'h004,
                        5'd1,
                        F3_LW,
                        5'd6,
                        OPCODE_LOAD
                    );

                // LWU x7, 0(x1)
                u_imem.mem[8] =
                    enc_i(
                        12'h000,
                        5'd1,
                        F3_LWU,
                        5'd7,
                        OPCODE_LOAD
                    );

                // LD x8, 0(x1)
                u_imem.mem[9] =
                    enc_i(
                        12'h000,
                        5'd1,
                        F3_LD,
                        5'd8,
                        OPCODE_LOAD
                    );

            // -----------------------------------------------------
            // Datos para stores
            // -----------------------------------------------------

                // x9 = 0xAA
                u_imem.mem[10] =
                    enc_i(
                        12'h0AA,
                        5'd0,
                        F3_ADDI,
                        5'd9,
                        OPCODE_OP_IMM
                    );

                // x10 = 0x02BC
                u_imem.mem[11] =
                    enc_i(
                        12'h2BC,
                        5'd0,
                        F3_ADDI,
                        5'd10,
                        OPCODE_OP_IMM
                    );

                // x11 = 0x0345
                u_imem.mem[12] =
                    enc_i(
                        12'h345,
                        5'd0,
                        F3_ADDI,
                        5'd11,
                        OPCODE_OP_IMM
                    );

            // -----------------------------------------------------
            // Stores
            // -----------------------------------------------------

                // SB x9, 0x27(x1)
                //
                // Dirección = 0x127
                // lane       = 7
                u_imem.mem[13] =
                    enc_s(
                        12'h027,
                        5'd9,
                        5'd1,
                        F3_SB
                    );

                // SH x10, 0x2E(x1)
                //
                // Dirección = 0x12E
                // lanes      = 6,7
                u_imem.mem[14] =
                    enc_s(
                        12'h02E,
                        5'd10,
                        5'd1,
                        F3_SH
                    );

                // SW x11, 0x34(x1)
                //
                // Dirección = 0x134
                // lanes      = 4..7
                u_imem.mem[15] =
                    enc_s(
                        12'h034,
                        5'd11,
                        5'd1,
                        F3_SW
                    );

                // SD x8, 0x38(x1)
                u_imem.mem[16] =
                    enc_s(
                        12'h038,
                        5'd8,
                        5'd1,
                        F3_SD
                    );

                u_imem.mem[17] =
                    enc_halt();
        end

    // =========================================================
    // Test principal
    // =========================================================

        integer cycles;

        initial begin

            $dumpfile(
                "build/tb_core_dmem_sync_subword.vcd"
            );

            $dumpvars(
                0,
                tb_core_dmem_sync_subword
            );

            errors = 0;
            rst    = 1'b1;

            // -----------------------------------------------------
            // Precarga de memoria
            // -----------------------------------------------------

            u_dmem.mem[SOURCE_ADDR[12:3]] =
                SOURCE_VALUE;

            u_dmem.mem[SB_LINE_ADDR[12:3]] =
                STORE_INITIAL;

            u_dmem.mem[SH_LINE_ADDR[12:3]] =
                STORE_INITIAL;

            u_dmem.mem[SW_LINE_ADDR[12:3]] =
                STORE_INITIAL;

            u_dmem.mem[SD_LINE_ADDR[12:3]] =
                STORE_INITIAL;

            // -----------------------------------------------------
            // Reset
            // -----------------------------------------------------

            repeat (5) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            // -----------------------------------------------------
            // Esperamos:
            //
            //   7 loads
            // + 4 stores
            // ----------
            //  11 responses
            // -----------------------------------------------------

            cycles = 0;

            while (
                (response_count < 11) &&
                (cycles < 800)
            ) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            repeat (10) @(posedge clk);
            #1;

            $display("");
            $display(
                "=============================================="
            );

            $display(
                "CORE + SYNCHRONOUS DMEM SUBWORD ACCESS"
            );

            $display(
                "=============================================="
            );

            // =====================================================
            // Protocolo
            // =====================================================

            check_int(
                "transacciones aceptadas",
                accepted_count,
                11
            );

            check_int(
                "respuestas recibidas",
                response_count,
                11
            );

            if (request_wait_cycles <= 0) begin
                $display(
                    "ERROR: no se ejercitó WAIT_GNT"
                );

                record_error();
            end
            else begin
                $display(
                    "PASS : WAIT_GNT observado durante %0d ciclos",
                    request_wait_cycles
                );
            end

            if (response_wait_cycles <= 0) begin
                $display(
                    "ERROR: no se ejercitó WAIT_RESP"
                );

                record_error();
            end
            else begin
                $display(
                    "PASS : WAIT_RESP observado durante %0d ciclos",
                    response_wait_cycles
                );
            end

            // =====================================================
            // Loads
            // =====================================================

            check64(
                "x2 LB sign-extension",
                dut.u_regfile.regs[2],
                EXPECT_LB
            );

            check64(
                "x3 LBU zero-extension",
                dut.u_regfile.regs[3],
                EXPECT_LBU
            );

            check64(
                "x4 LH sign-extension",
                dut.u_regfile.regs[4],
                EXPECT_LH
            );

            check64(
                "x5 LHU zero-extension",
                dut.u_regfile.regs[5],
                EXPECT_LHU
            );

            check64(
                "x6 LW sign-extension",
                dut.u_regfile.regs[6],
                EXPECT_LW
            );

            check64(
                "x7 LWU zero-extension",
                dut.u_regfile.regs[7],
                EXPECT_LWU
            );

            check64(
                "x8 LD",
                dut.u_regfile.regs[8],
                EXPECT_LD
            );

            // =====================================================
            // Fuentes de stores
            // =====================================================

            check64(
                "x9 fuente SB",
                dut.u_regfile.regs[9],
                SB_SOURCE
            );

            check64(
                "x10 fuente SH",
                dut.u_regfile.regs[10],
                SH_SOURCE
            );

            check64(
                "x11 fuente SW",
                dut.u_regfile.regs[11],
                SW_SOURCE
            );

            // =====================================================
            // Memoria final
            // =====================================================

            check64(
                "source line intacta",
                u_dmem.mem[SOURCE_ADDR[12:3]],
                SOURCE_VALUE
            );

            check64(
                "SB lane 7",
                u_dmem.mem[SB_LINE_ADDR[12:3]],
                EXPECT_SB_LINE
            );

            check64(
                "SH lanes 6-7",
                u_dmem.mem[SH_LINE_ADDR[12:3]],
                EXPECT_SH_LINE
            );

            check64(
                "SW lanes 4-7",
                u_dmem.mem[SW_LINE_ADDR[12:3]],
                EXPECT_SW_LINE
            );

            check64(
                "SD línea completa",
                u_dmem.mem[SD_LINE_ADDR[12:3]],
                EXPECT_SD_LINE
            );

            if (transaction_outstanding !== 1'b0) begin
                $display(
                    "ERROR: quedó una transacción outstanding"
                );

                record_error();
            end
            else begin
                $display(
                    "PASS : no quedan transacciones outstanding"
                );
            end

            // =====================================================
            // Resultado
            // =====================================================

            $display(
                "=============================================="
            );

            if (errors == 0) begin

                $display(
                    "PASS: todos los tamaños DMEM RV64I funcionan"
                );

                $display(
                    "      LB/LBU/LH/LHU/LW/LWU/LD"
                );

                $display(
                    "      SB/SH/SW/SD"
                );

                $display(
                    "      sign/zero extension correcta"
                );

                $display(
                    "      offset + wstrb + wdata correctos"
                );

            end
            else begin

                $display(
                    "FAIL: tb_core_dmem_sync_subword errors=%0d",
                    errors
                );

            end

            $display(
                "=============================================="
            );

            if (errors != 0) begin
                $fatal(
                    1,
                    "tb_core_dmem_sync_subword falló"
                );
            end

            $finish;
        end

    // =========================================================
    // Timeout
    // =========================================================

        initial begin
            #40000;

            $fatal(
                1,
                "TIMEOUT global tb_core_dmem_sync_subword"
            );
        end

    // =========================================================
    // Señales no utilizadas directamente
    // =========================================================

        wire _unused_ok = 1'b0 && &{
            1'b0,

            // RV64I base usa instrucciones de 32 bits (IALIGN=32).
            // La IMEM se indexa con imem_addr[9:2], por lo que los
            // dos bits inferiores no participan en este modelo.
            imem_addr[1:0],

            exp_we,
            exp_wdata,
            exp_wstrb,
            exp_size,

            1'b0
        };

endmodule
