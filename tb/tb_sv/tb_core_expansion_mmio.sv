`timescale 1ns/1ps

module tb_core_expansion_mmio;

    localparam logic [63:0] EXP_BASE = 64'h0000_0000_8000_0000;
    localparam logic [63:0] EXP_MASK = 64'hFFFF_FFFF_FFFF_F000;

    localparam logic [63:0] REG_CONTROL   = 64'h010;
    localparam logic [63:0] REG_OPERAND_A = 64'h020;
    localparam logic [63:0] REG_OPERAND_B = 64'h028;
    localparam logic [63:0] REG_RESULT    = 64'h030;

    localparam logic [63:0] RESULT_MEM_ADDR = 64'h0000_0000_0000_0200;
    localparam logic [63:0] EXPECTED_RESULT = 64'h0000_0000_0000_0033;

    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_WORDS = 1024;

    // Número de bits necesarios para indexar las 256 palabras
    // de la memoria de instrucciones.
    localparam integer IMEM_INDEX_BITS = $clog2(IMEM_WORDS);

    // Opcodes RISC-V usados por el programa dirigido
    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;

    // funct3
    localparam logic [2:0] F3_ADDI = 3'b000;
    localparam logic [2:0] F3_SLLI = 3'b001;
    localparam logic [2:0] F3_LD   = 3'b011;
    localparam logic [2:0] F3_SD   = 3'b011;

    logic clk;
    logic rst;

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    logic [31:0] instr_mem [0:IMEM_WORDS-1];
    logic [63:0] data_mem  [0:DMEM_WORDS-1];

    logic [9:0] imem_index;
    logic [9:0] dmem_index;


    integer i;
    integer b;
    integer cycles;
    integer failures;

    logic seen_operand_a_write;
    logic seen_operand_b_write;
    logic seen_control_start;
    logic seen_result_read;
    logic seen_result_store;
    logic seen_bad_dmem_exp_write;

    logic [63:0] captured_result_store;

    // =========================================================
    // Ensambladores mínimos para instrucciones usadas por el TB
    // =========================================================

    function automatic [31:0] enc_lui;
        input [4:0]  rd;
        input [19:0] imm20;
        begin
            enc_lui = {imm20, rd, OPCODE_LUI};
        end
    endfunction

    function automatic [31:0] enc_i;
        input [11:0] imm12;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            enc_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm12;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        begin
            enc_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], OPCODE_STORE};
        end
    endfunction

    function automatic [31:0] enc_jal;
        input [4:0]  rd;
        input [20:0] imm21;
        begin
            enc_jal = {
                imm21[20],
                imm21[10:1],
                imm21[11],
                imm21[19:12],
                rd,
                OPCODE_JAL
            };
        end
    endfunction

    function automatic is_exp_region;
        input [63:0] addr;
        begin
            is_exp_region = ((addr & EXP_MASK) == (EXP_BASE & EXP_MASK));
        end
    endfunction

    // =========================================================
    // DUT: core + periférico de expansión
    // =========================================================

    core_top #(
        .RESET_PC    (64'd0),
        .TRAP_VECTOR (64'h0000_0000_0000_0100),
        .EXP_BASE    (EXP_BASE),
        .EXP_MASK    (EXP_MASK)
    ) dut (
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

        .exp_valid  (exp_valid),
        .exp_we     (exp_we),
        .exp_addr   (exp_addr),
        .exp_wdata  (exp_wdata),
        .exp_wstrb  (exp_wstrb),
        .exp_size   (exp_size),
        .exp_ready  (exp_ready),
        .exp_rdata  (exp_rdata),
        .exp_error  (exp_error)
    );

    expansion_demo_periph u_expansion_demo_periph (
        .clk         (clk),
        .rst         (rst),

        .exp_valid_i (exp_valid),
        .exp_we_i    (exp_we),
        .exp_addr_i  (exp_addr),
        .exp_wdata_i (exp_wdata),
        .exp_wstrb_i (exp_wstrb),
        .exp_size_i  (exp_size),

        .exp_ready_o (exp_ready),
        .exp_rdata_o (exp_rdata),
        .exp_error_o (exp_error)
    );

    // =========================================================
    // Reloj
    // =========================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // Memoria de instrucciones combinacional
    // =========================================================

    assign imem_index = imem_addr[11:2];

    always @* begin
        if (imem_index < 10'(IMEM_WORDS)) begin
            imem_rdata = instr_mem[
                imem_index[IMEM_INDEX_BITS-1:0]
            ];
        end
        else begin
            imem_rdata = 32'h0000_0013; // NOP = addi x0, x0, 0
        end
    end

    // =========================================================
    // Memoria de datos simple
    // =========================================================

    assign dmem_index = dmem_addr[12:3];

    always @* begin
        dmem_rdata = data_mem[dmem_index];
    end

    always @(posedge clk) begin
        if (!rst && dmem_we) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb[b]) begin
                    data_mem[dmem_addr[12:3]][b*8 +: 8] <= dmem_wdata[b*8 +: 8];
                end
            end
        end
    end

    // =========================================================
    // Programa dirigido en RV64I
    // =========================================================

    task automatic load_program;
        begin
            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                instr_mem[i] = 32'h0000_0013; // NOP
            end

            for (i = 0; i < DMEM_WORDS; i = i + 1) begin
                data_mem[i] = 64'd0;
            end

            // Programa:
            //
            // x10 = 0x0000_0000_8000_0000
            // x11 = 0x11
            // *(uint64_t *)(x10 + 0x20) = x11  -> OPERAND_A
            // x12 = 0x22
            // *(uint64_t *)(x10 + 0x28) = x12  -> OPERAND_B
            // x13 = 1
            // *(uint64_t *)(x10 + 0x10) = x13  -> CONTROL.start
            // x14 = *(uint64_t *)(x10 + 0x30)  -> RESULT
            // x15 = 0x200
            // *(uint64_t *)(x15 + 0x00) = x14  -> memoria normal
            // loop: jal x0, 0
            //
            // Nota RV64I:
            // LUI con 0x80000 sign-extendería a 0xFFFF_FFFF_8000_0000.
            // Por eso se forma 0x8000_0000 como:
            //   lui  x10, 0x40000
            //   slli x10, x10, 1

            instr_mem[0]  = enc_lui(5'd10, 20'h40000);                         // lui  x10, 0x40000
            instr_mem[1]  = enc_i  (12'h001, 5'd10, F3_SLLI, 5'd10, OPCODE_OP_IMM); // slli x10, x10, 1

            instr_mem[2]  = enc_i  (12'h011, 5'd0,  F3_ADDI, 5'd11, OPCODE_OP_IMM); // addi x11, x0, 0x11
            instr_mem[3]  = enc_s  (12'h020, 5'd11, 5'd10, F3_SD);                  // sd   x11, 0x20(x10)

            instr_mem[4]  = enc_i  (12'h022, 5'd0,  F3_ADDI, 5'd12, OPCODE_OP_IMM); // addi x12, x0, 0x22
            instr_mem[5]  = enc_s  (12'h028, 5'd12, 5'd10, F3_SD);                  // sd   x12, 0x28(x10)

            instr_mem[6]  = enc_i  (12'h001, 5'd0,  F3_ADDI, 5'd13, OPCODE_OP_IMM); // addi x13, x0, 1
            instr_mem[7]  = enc_s  (12'h010, 5'd13, 5'd10, F3_SD);                  // sd   x13, 0x10(x10)

            instr_mem[8]  = enc_i  (12'h030, 5'd10, F3_LD,   5'd14, OPCODE_LOAD);   // ld   x14, 0x30(x10)

            instr_mem[9]  = enc_i  (12'h200, 5'd0,  F3_ADDI, 5'd15, OPCODE_OP_IMM); // addi x15, x0, 0x200
            instr_mem[10] = enc_s  (12'h000, 5'd14, 5'd15, F3_SD);                  // sd   x14, 0(x15)

            instr_mem[11] = enc_jal(5'd0, 21'd0);                                   // jal  x0, 0
        end
    endtask

    // =========================================================
    // Checks
    // =========================================================

    task automatic check1;
        input [8*80-1:0] name;
        input logic got;
        input logic expected;
        begin
            if (got !== expected) begin
                $display("ERROR: %0s: got=%0b expected=%0b", name, got, expected);
                failures = failures + 1;
            end
            else begin
                $display("PASS : %0s = %0b", name, got);
            end
        end
    endtask

    task automatic check64;
        input [8*80-1:0] name;
        input logic [63:0] got;
        input logic [63:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR: %0s: got=0x%016h expected=0x%016h", name, got, expected);
                failures = failures + 1;
            end
            else begin
                $display("PASS : %0s = 0x%016h", name, got);
            end
        end
    endtask

    // =========================================================
    // Monitor de transacciones
    // =========================================================

    always @(posedge clk) begin
        if (rst) begin
            seen_operand_a_write    <= 1'b0;
            seen_operand_b_write    <= 1'b0;
            seen_control_start      <= 1'b0;
            seen_result_read        <= 1'b0;
            seen_result_store       <= 1'b0;
            seen_bad_dmem_exp_write <= 1'b0;
            captured_result_store   <= 64'd0;
        end
        else begin
            // La región de expansión no debe activar escritura hacia dmem.
            if (dmem_we && is_exp_region(dmem_addr)) begin
                $display("ERROR: escritura MMIO llegó incorrectamente a dmem: addr=0x%016h data=0x%016h",
                         dmem_addr, dmem_wdata);
                seen_bad_dmem_exp_write <= 1'b1;
                failures = failures + 1;
            end

            // Stores hacia el periférico.
            if (exp_valid && exp_ready && exp_we) begin
                case (exp_addr)
                    EXP_BASE + REG_OPERAND_A: begin
                        if ((exp_wdata == 64'h0000_0000_0000_0011) && (exp_wstrb == 8'hFF)) begin
                            seen_operand_a_write <= 1'b1;
                            $display("INFO : MMIO write OPERAND_A = 0x%016h", exp_wdata);
                        end
                        else begin
                            $display("ERROR: OPERAND_A write inesperado: data=0x%016h wstrb=0x%02h",
                                     exp_wdata, exp_wstrb);
                            failures = failures + 1;
                        end
                    end

                    EXP_BASE + REG_OPERAND_B: begin
                        if ((exp_wdata == 64'h0000_0000_0000_0022) && (exp_wstrb == 8'hFF)) begin
                            seen_operand_b_write <= 1'b1;
                            $display("INFO : MMIO write OPERAND_B = 0x%016h", exp_wdata);
                        end
                        else begin
                            $display("ERROR: OPERAND_B write inesperado: data=0x%016h wstrb=0x%02h",
                                     exp_wdata, exp_wstrb);
                            failures = failures + 1;
                        end
                    end

                    EXP_BASE + REG_CONTROL: begin
                        if ((exp_wdata == 64'h0000_0000_0000_0001) && (exp_wstrb == 8'hFF)) begin
                            seen_control_start <= 1'b1;
                            $display("INFO : MMIO write CONTROL.start = 1");
                        end
                        else begin
                            $display("ERROR: CONTROL write inesperado: data=0x%016h wstrb=0x%02h",
                                     exp_wdata, exp_wstrb);
                            failures = failures + 1;
                        end
                    end

                    default: begin
                        $display("ERROR: MMIO write inesperado: addr=0x%016h data=0x%016h",
                                 exp_addr, exp_wdata);
                        failures = failures + 1;
                    end
                endcase
            end

            // Load desde RESULT.
            if (exp_valid && exp_ready && !exp_we) begin
                if (exp_addr == (EXP_BASE + REG_RESULT)) begin
                    seen_result_read <= 1'b1;
                    $display("INFO : MMIO read RESULT, exp_rdata=0x%016h", exp_rdata);
                end
                else begin
                    $display("ERROR: MMIO read inesperado: addr=0x%016h", exp_addr);
                    failures = failures + 1;
                end
            end

            // Store final hacia memoria normal, usado como observable del programa.
            if (dmem_we && (dmem_addr == RESULT_MEM_ADDR)) begin
                seen_result_store     <= 1'b1;
                captured_result_store <= dmem_wdata;

                $display("INFO : dmem result store addr=0x%016h data=0x%016h wstrb=0x%02h",
                         dmem_addr, dmem_wdata, dmem_wstrb);

                if (dmem_wstrb !== 8'hFF) begin
                    $display("ERROR: store final no es SD completo: wstrb=0x%02h", dmem_wstrb);
                    failures = failures + 1;
                end

                if (dmem_wdata !== EXPECTED_RESULT) begin
                    $display("ERROR: store final incorrecto: got=0x%016h expected=0x%016h",
                             dmem_wdata, EXPECTED_RESULT);
                    failures = failures + 1;
                end
            end
        end
    end

    // =========================================================
    // Secuencia principal
    // =========================================================

    initial begin
        $display("==============================================");
        $display("TB core expansion MMIO");
        $display("==============================================");

        failures = 0;
        rst      = 1'b1;

        load_program();

        repeat (5) @(posedge clk);
        #1;
        rst = 1'b0;

        cycles = 0;
        while (!seen_result_store && (cycles < 250)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        repeat (3) @(posedge clk);
        #1;

        if (!seen_result_store) begin
            $display("ERROR: timeout esperando store final en dmem");
            failures = failures + 1;
        end

        check1 ("seen_operand_a_write",    seen_operand_a_write,    1'b1);
        check1 ("seen_operand_b_write",    seen_operand_b_write,    1'b1);
        check1 ("seen_control_start",      seen_control_start,      1'b1);
        check1 ("seen_result_read",        seen_result_read,        1'b1);
        check1 ("seen_result_store",       seen_result_store,       1'b1);
        check1 ("seen_bad_dmem_exp_write", seen_bad_dmem_exp_write, 1'b0);

        check64("captured_result_store", captured_result_store, EXPECTED_RESULT);
        check64("data_mem[0x200]", data_mem[RESULT_MEM_ADDR[12:3]], EXPECTED_RESULT);

        if (failures == 0) begin
            $display("==============================================");
            $display("PASS: tb_core_expansion_mmio cycles=%0d", cycles);
            $display("==============================================");
            $finish;
        end
        else begin
            $display("==============================================");
            $display("FAIL: tb_core_expansion_mmio failures=%0d", failures);
            $display("==============================================");
            $finish(1);
        end
    end

endmodule
