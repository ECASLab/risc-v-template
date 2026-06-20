`timescale 1ns/1ps

module tb_core_expansion_fault_trap;

    localparam logic [63:0] EXP_BASE = 64'h0000_0000_8000_0000;
    localparam logic [63:0] EXP_MASK = 64'hFFFF_FFFF_FFFF_F000;

    localparam logic [63:0] INVALID_MMIO_OFFSET = 64'h040;

    localparam logic [63:0] CAUSE_MEM_ADDR     = 64'h0000_0000_0000_0200;
    localparam logic [63:0] MEPC_MEM_ADDR      = 64'h0000_0000_0000_0208;
    localparam logic [63:0] X12_MEM_ADDR       = 64'h0000_0000_0000_0218;
    localparam logic [63:0] SENTINEL_MEM_ADDR  = 64'h0000_0000_0000_0210;

    localparam logic [63:0] EXPECTED_MCAUSE    = 64'd5;  // Load access fault
    localparam logic [63:0] EXPECTED_MEPC      = 64'h0000_0000_0000_000C;
    localparam logic [63:0] EXPECTED_X12       = 64'h0000_0000_0000_0077;
    localparam logic [63:0] EXPECTED_SENTINEL  = 64'h0000_0000_0000_006D;

    localparam integer IMEM_WORDS = 256;
    localparam integer DMEM_WORDS = 1024;

    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    localparam logic [2:0] F3_ADDI  = 3'b000;
    localparam logic [2:0] F3_SLLI  = 3'b001;
    localparam logic [2:0] F3_LD    = 3'b011;
    localparam logic [2:0] F3_SD    = 3'b011;
    localparam logic [2:0] F3_CSRRW = 3'b001;
    localparam logic [2:0] F3_CSRRS = 3'b010;

    localparam logic [11:0] CSR_MEPC   = 12'h341;
    localparam logic [11:0] CSR_MCAUSE = 12'h342;

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

    integer i;
    integer b;
    integer cycles;
    integer failures;

    logic seen_invalid_mmio_load;
    logic seen_cause_store;
    logic seen_mepc_store;
    logic seen_x12_store;
    logic seen_sentinel_store;

    logic [63:0] captured_cause;
    logic [63:0] captured_mepc;
    logic [63:0] captured_x12;
    logic [63:0] captured_sentinel;

    // =========================================================
    // Ensambladores mínimos
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

    function automatic [31:0] enc_csr;
        input [11:0] csr_addr;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        begin
            enc_csr = {csr_addr, rs1, funct3, rd, OPCODE_SYSTEM};
        end
    endfunction

    function automatic [31:0] enc_nop;
        begin
            enc_nop = 32'h0000_0013; // addi x0, x0, 0
        end
    endfunction

    // =========================================================
    // DUT
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
    // Memorias simples
    // =========================================================

    always_comb begin
        imem_rdata = enc_nop();

        if (imem_addr[11:2] < IMEM_WORDS) begin
            imem_rdata = instr_mem[imem_addr[11:2]];
        end
    end

    always_comb begin
        dmem_rdata = 64'd0;

        if (dmem_addr[12:3] < DMEM_WORDS) begin
            dmem_rdata = data_mem[dmem_addr[12:3]];
        end
    end

    always_ff @(posedge clk)  begin
        if (!rst && dmem_we) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb[b]) begin
                    data_mem[dmem_addr[12:3]][b*8 +: 8] <= dmem_wdata[b*8 +: 8];
                end
            end
        end
    end

    // =========================================================
    // Programa dirigido
    // =========================================================

    task automatic load_program;
        begin
            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                instr_mem[i] = enc_nop();
            end

            for (i = 0; i < DMEM_WORDS; i = i + 1) begin
                data_mem[i] = 64'd0;
            end

            // -------------------------------------------------
            // Programa principal
            // -------------------------------------------------
            //
            // 0x000: x10 = 0x0000_0000_8000_0000
            // 0x008: x12 = 0x77
            // 0x00C: ld x12, 0x040(x10)
            //
            // El offset 0x040 no está implementado en el periférico.
            // Por tanto, exp_error debe convertirse en Load access fault.
            //
            // Después del MRET:
            // 0x010: sd x12, 0x218(x0)
            // 0x014: x13 = 0x6D
            // 0x018: sd x13, 0x210(x0)
            // 0x01C: loop

            instr_mem[0] = enc_lui(5'd10, 20'h40000);                         // lui  x10, 0x40000
            instr_mem[1] = enc_i  (12'h001, 5'd10, F3_SLLI, 5'd10, OPCODE_OP_IMM); // slli x10, x10, 1

            instr_mem[2] = enc_i  (12'h077, 5'd0,  F3_ADDI, 5'd12, OPCODE_OP_IMM); // addi x12, x0, 0x77
            instr_mem[3] = enc_i  (12'h040, 5'd10, F3_LD,   5'd12, OPCODE_LOAD);   // ld   x12, 0x40(x10) -> fault

            instr_mem[4] = enc_s  (12'h218, 5'd12, 5'd0, F3_SD);                  // sd   x12, 0x218(x0)
            instr_mem[5] = enc_i  (12'h06D, 5'd0,  F3_ADDI, 5'd13, OPCODE_OP_IMM); // addi x13, x0, 0x6D
            instr_mem[6] = enc_s  (12'h210, 5'd13, 5'd0, F3_SD);                  // sd   x13, 0x210(x0)
            instr_mem[7] = enc_jal(5'd0, 21'd0);                                  // jal  x0, 0

            // -------------------------------------------------
            // Handler en mtvec = 0x100
            // -------------------------------------------------
            //
            // csrr x20, mcause
            // sd   x20, 0x200(x0)
            // csrr x21, mepc
            // sd   x21, 0x208(x0)
            // addi x21, x21, 4
            // csrw mepc, x21
            // mret
            //
            // Se insertan NOPs para evitar depender de forwarding
            // específico entre CSR/ALU/store/MRET.

            instr_mem[64] = enc_csr(CSR_MCAUSE, 5'd0,  F3_CSRRS, 5'd20); // csrr x20, mcause
            instr_mem[65] = enc_nop();
            instr_mem[66] = enc_nop();
            instr_mem[67] = enc_s  (12'h200, 5'd20, 5'd0, F3_SD);        // sd x20, 0x200(x0)

            instr_mem[68] = enc_csr(CSR_MEPC,   5'd0,  F3_CSRRS, 5'd21); // csrr x21, mepc
            instr_mem[69] = enc_nop();
            instr_mem[70] = enc_nop();
            instr_mem[71] = enc_s  (12'h208, 5'd21, 5'd0, F3_SD);        // sd x21, 0x208(x0)

            instr_mem[72] = enc_i  (12'h004, 5'd21, F3_ADDI, 5'd21, OPCODE_OP_IMM); // addi x21, x21, 4
            instr_mem[73] = enc_nop();
            instr_mem[74] = enc_nop();

            instr_mem[75] = enc_csr(CSR_MEPC, 5'd21, F3_CSRRW, 5'd0);    // csrw mepc, x21
            instr_mem[76] = enc_nop();
            instr_mem[77] = enc_nop();

            instr_mem[78] = 32'h3020_0073;                               // mret
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
    // Monitor
    // =========================================================

    always @(posedge clk) begin
        if (rst) begin
            seen_invalid_mmio_load <= 1'b0;
            seen_cause_store       <= 1'b0;
            seen_mepc_store        <= 1'b0;
            seen_x12_store         <= 1'b0;
            seen_sentinel_store    <= 1'b0;

            captured_cause         <= 64'd0;
            captured_mepc          <= 64'd0;
            captured_x12           <= 64'd0;
            captured_sentinel      <= 64'd0;
        end
        else begin
            if (exp_valid && exp_ready && !exp_we) begin
                if (exp_addr == (EXP_BASE + INVALID_MMIO_OFFSET)) begin
                    seen_invalid_mmio_load <= 1'b1;
                    $display("INFO : invalid MMIO load addr=0x%016h exp_error=%0b",
                             exp_addr, exp_error);

                    if (exp_error !== 1'b1) begin
                        $display("ERROR: invalid MMIO load no levantó exp_error");
                        failures = failures + 1;
                    end
                end
            end

            if (dmem_we && (dmem_addr == CAUSE_MEM_ADDR)) begin
                seen_cause_store <= 1'b1;
                captured_cause   <= dmem_wdata;
                $display("INFO : handler stored mcause = 0x%016h", dmem_wdata);
            end

            if (dmem_we && (dmem_addr == MEPC_MEM_ADDR)) begin
                seen_mepc_store <= 1'b1;
                captured_mepc   <= dmem_wdata;
                $display("INFO : handler stored mepc = 0x%016h", dmem_wdata);
            end

            if (dmem_we && (dmem_addr == X12_MEM_ADDR)) begin
                seen_x12_store <= 1'b1;
                captured_x12   <= dmem_wdata;
                $display("INFO : post-trap stored x12 = 0x%016h", dmem_wdata);
            end

            if (dmem_we && (dmem_addr == SENTINEL_MEM_ADDR)) begin
                seen_sentinel_store <= 1'b1;
                captured_sentinel   <= dmem_wdata;
                $display("INFO : post-trap sentinel store = 0x%016h", dmem_wdata);
            end
        end
    end

    // =========================================================
    // Secuencia principal
    // =========================================================

    initial begin
        $display("==============================================");
        $display("TB core expansion fault trap");
        $display("==============================================");

        failures = 0;
        rst      = 1'b1;

        load_program();

        repeat (5) @(posedge clk);
        #1;
        rst = 1'b0;

        cycles = 0;
        while (!seen_sentinel_store && (cycles < 400)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        repeat (5) @(posedge clk);
        #1;

        if (!seen_sentinel_store) begin
            $display("ERROR: timeout esperando retorno del trap y store centinela");
            failures = failures + 1;
        end

        check1 ("seen_invalid_mmio_load", seen_invalid_mmio_load, 1'b1);
        check1 ("seen_cause_store",       seen_cause_store,       1'b1);
        check1 ("seen_mepc_store",        seen_mepc_store,        1'b1);
        check1 ("seen_x12_store",         seen_x12_store,         1'b1);
        check1 ("seen_sentinel_store",    seen_sentinel_store,    1'b1);

        check64("captured_cause",    captured_cause,    EXPECTED_MCAUSE);
        check64("captured_mepc",     captured_mepc,     EXPECTED_MEPC);
        check64("captured_x12",      captured_x12,      EXPECTED_X12);
        check64("captured_sentinel", captured_sentinel, EXPECTED_SENTINEL);

        check64("data_mem[mcause]",   data_mem[CAUSE_MEM_ADDR[12:3]],    EXPECTED_MCAUSE);
        check64("data_mem[mepc]",     data_mem[MEPC_MEM_ADDR[12:3]],     EXPECTED_MEPC);
        check64("data_mem[x12]",      data_mem[X12_MEM_ADDR[12:3]],      EXPECTED_X12);
        check64("data_mem[sentinel]", data_mem[SENTINEL_MEM_ADDR[12:3]], EXPECTED_SENTINEL);

        if (failures == 0) begin
            $display("==============================================");
            $display("PASS: tb_core_expansion_fault_trap cycles=%0d", cycles);
            $display("==============================================");
            $finish;
        end
        else begin
            $display("==============================================");
            $display("FAIL: tb_core_expansion_fault_trap failures=%0d", failures);
            $display("==============================================");
            $finish(1);
        end
    end

endmodule
