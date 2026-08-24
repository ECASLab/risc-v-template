`timescale 1ns/1ps

module tb_core_expansion_store_fault_trap;

    localparam logic [63:0] EXP_BASE   = 64'h0000_0000_8000_0000;
    localparam logic [63:0] EXP_RESULT = 64'h0000_0000_8000_0030;

    localparam logic [63:0] ADDR_MCAUSE_STORE   = 64'h0000_0000_0000_0100;
    localparam logic [63:0] ADDR_MEPC_STORE     = 64'h0000_0000_0000_0108;
    localparam logic [63:0] ADDR_X12_AFTER_TRAP = 64'h0000_0000_0000_0208;
    localparam logic [63:0] ADDR_SENTINEL       = 64'h0000_0000_0000_0210;

    localparam logic [63:0] EXPECTED_CAUSE    = 64'd7;
    localparam logic [63:0] EXPECTED_MEPC     = 64'h0000_0000_0000_0014;
    localparam logic [63:0] EXPECTED_X12      = 64'h0000_0000_0000_005a;
    localparam logic [63:0] EXPECTED_SENTINEL = 64'h0000_0000_0000_006e;

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

    logic [31:0] instr_mem [0:255];
    logic [63:0] data_mem  [0:1023];

    logic        seen_invalid_mmio_store;
    logic        seen_bad_dmem_exp_write;
    logic        seen_cause_store;
    logic        seen_mepc_store;
    logic        seen_x12_store;
    logic        seen_sentinel_store;

    logic [63:0] captured_exp_wdata;
    logic [7:0]  captured_exp_wstrb;
    logic [63:0] captured_cause;
    logic [63:0] captured_mepc;
    logic [63:0] captured_x12;
    logic [63:0] captured_sentinel;

    integer i;
    integer cycle;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            enc_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [6:0]  opcode;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
        end
    endfunction

    function automatic [31:0] enc_jal_zero;
        begin
            enc_jal_zero = 32'h0000_006f; // jal x0, 0
        end
    endfunction

    function automatic [63:0] apply_wstrb;
        input [63:0] old_value;
        input [63:0] new_value;
        input [7:0]  byte_en;
        integer b;
        begin
            apply_wstrb = old_value;
            for (b = 0; b < 8; b = b + 1) begin
                if (byte_en[b]) begin
                    apply_wstrb[b*8 +: 8] = new_value[b*8 +: 8];
                end
            end
        end
    endfunction

    task automatic check1;
        input string name;
        input logic  value;
        begin
            if (!value) begin
                $display("FAIL: %s = 0", name);
                $fatal(1);
            end
            else begin
                $display("PASS : %s = 1", name);
            end
        end
    endtask

    task automatic check64;
        input string name;
        input logic [63:0] got;
        input logic [63:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %s got=0x%016h expected=0x%016h", name, got, exp);
                $fatal(1);
            end
            else begin
                $display("PASS : %s = 0x%016h", name, got);
            end
        end
    endtask

    task automatic check8;
        input string name;
        input logic [7:0] got;
        input logic [7:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %s got=0x%02h expected=0x%02h", name, got, exp);
                $fatal(1);
            end
            else begin
                $display("PASS : %s = 0x%02h", name, got);
            end
        end
    endtask

    core_top #(
        .RESET_PC(64'h0000_0000_0000_0000),
        .TRAP_VECTOR(64'h0000_0000_0000_0100),
        .EXP_BASE(EXP_BASE),
        .EXP_MASK(64'hFFFF_FFFF_FFFF_F000)
    ) dut (
        .clk(clk),
        .rst(rst),

        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_rdata(dmem_rdata),

        .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_size(dmem_size),

        .exp_valid(exp_valid),
        .exp_we(exp_we),
        .exp_addr(exp_addr),
        .exp_wdata(exp_wdata),
        .exp_wstrb(exp_wstrb),
        .exp_size(exp_size),
        .exp_ready(exp_ready),
        .exp_rdata(exp_rdata),
        .exp_error(exp_error)
    );

    expansion_demo_periph u_expansion_demo_periph (
        .clk(clk),
        .rst(rst),
        .exp_valid_i(exp_valid),
        .exp_we_i(exp_we),
        .exp_addr_i(exp_addr),
        .exp_wdata_i(exp_wdata),
        .exp_wstrb_i(exp_wstrb),
        .exp_size_i(exp_size),
        .exp_ready_o(exp_ready),
        .exp_rdata_o(exp_rdata),
        .exp_error_o(exp_error)
    );

    always #5 clk = ~clk;

    always @(*) begin
        if (imem_addr[63:10] != 54'd0) begin
            imem_rdata = 32'h0000_0013; // nop
        end
        else begin
            imem_rdata = instr_mem[imem_addr[9:2]];
        end

        if (dmem_addr[63:13] != 51'd0) begin
            dmem_rdata = 64'd0;
        end
        else begin
            dmem_rdata = data_mem[dmem_addr[12:3]];
        end
    end

    always @(posedge clk) begin
        if (dmem_we) begin
            if ((dmem_addr & 64'hFFFF_FFFF_FFFF_F000) == EXP_BASE) begin
                seen_bad_dmem_exp_write <= 1'b1;
                $display("INFO : dmem_we erroneo en region EXP addr=0x%016h", dmem_addr);
            end
            else begin
                data_mem[dmem_addr[12:3]] <= apply_wstrb(
                    data_mem[dmem_addr[12:3]],
                    dmem_wdata,
                    dmem_wstrb
                );

                if (dmem_addr == ADDR_MCAUSE_STORE) begin
                    seen_cause_store <= 1'b1;
                    captured_cause   <= dmem_wdata;
                    $display("INFO : handler stored mcause = 0x%016h", dmem_wdata);
                end

                if (dmem_addr == ADDR_MEPC_STORE) begin
                    seen_mepc_store <= 1'b1;
                    captured_mepc   <= dmem_wdata;
                    $display("INFO : handler stored mepc = 0x%016h", dmem_wdata);
                end

                if (dmem_addr == ADDR_X12_AFTER_TRAP) begin
                    seen_x12_store <= 1'b1;
                    captured_x12   <= dmem_wdata;
                    $display("INFO : post-trap stored x12 = 0x%016h", dmem_wdata);
                end

                if (dmem_addr == ADDR_SENTINEL) begin
                    seen_sentinel_store <= 1'b1;
                    captured_sentinel   <= dmem_wdata;
                    $display("INFO : post-trap sentinel store = 0x%016h", dmem_wdata);
                end
            end
        end

        if (exp_valid && exp_we && (exp_addr == EXP_RESULT) && exp_error) begin
            seen_invalid_mmio_store <= 1'b1;
            captured_exp_wdata      <= exp_wdata;
            captured_exp_wstrb      <= exp_wstrb;
            $display("INFO : invalid MMIO store addr=0x%016h wdata=0x%016h wstrb=0x%02h exp_error=%0d",
                     exp_addr, exp_wdata, exp_wstrb, exp_error);
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        seen_invalid_mmio_store = 1'b0;
        seen_bad_dmem_exp_write = 1'b0;
        seen_cause_store        = 1'b0;
        seen_mepc_store         = 1'b0;
        seen_x12_store          = 1'b0;
        seen_sentinel_store     = 1'b0;

        captured_exp_wdata  = 64'd0;
        captured_exp_wstrb  = 8'd0;
        captured_cause      = 64'd0;
        captured_mepc       = 64'd0;
        captured_x12        = 64'd0;
        captured_sentinel   = 64'd0;

        for (i = 0; i < 256; i = i + 1) begin
            instr_mem[i] = 32'h0000_0013; // nop
        end

        for (i = 0; i < 1024; i = i + 1) begin
            data_mem[i] = 64'd0;
        end

        // Programa principal
        instr_mem[0] = enc_i(12'h040, 5'd0, 3'b000, 5'd1,  7'b0010011); // addi  x1,  x0, 0x40
        instr_mem[1] = enc_i(12'h305, 5'd1, 3'b001, 5'd0,  7'b1110011); // csrrw x0,  mtvec, x1
        instr_mem[2] = enc_i(12'h001, 5'd0, 3'b000, 5'd10, 7'b0010011); // addi  x10, x0, 1
        instr_mem[3] = enc_i(12'd31,  5'd10,3'b001, 5'd10, 7'b0010011); // slli  x10, x10, 31 => 0x80000000
        instr_mem[4] = enc_i(12'h05a, 5'd0, 3'b000, 5'd12, 7'b0010011); // addi  x12, x0, 0x5a
        instr_mem[5] = enc_s(12'h030, 5'd12,5'd10,3'b011, 7'b0100011); // sd    x12, 0x30(x10) -> RESULT RO => trap
        instr_mem[6] = enc_s(12'h208, 5'd12,5'd0, 3'b011, 7'b0100011); // sd    x12, 0x208(x0)
        instr_mem[7] = enc_i(12'h06e, 5'd0, 3'b000, 5'd13, 7'b0010011); // addi  x13, x0, 0x6e
        instr_mem[8] = enc_s(12'h210, 5'd13,5'd0, 3'b011, 7'b0100011); // sd    x13, 0x210(x0)
        instr_mem[9] = enc_jal_zero();                                  // loop

        // Handler en mtvec = 0x40. Índice 0x40 >> 2 = 16.
        instr_mem[16] = enc_i(12'h342, 5'd0,  3'b010, 5'd20, 7'b1110011); // csrrs x20, mcause, x0
        instr_mem[17] = enc_i(12'h341, 5'd0,  3'b010, 5'd21, 7'b1110011); // csrrs x21, mepc,   x0
        instr_mem[18] = enc_s(12'h100, 5'd20, 5'd0,  3'b011, 7'b0100011); // sd    x20, 0x100(x0)
        instr_mem[19] = enc_s(12'h108, 5'd21, 5'd0,  3'b011, 7'b0100011); // sd    x21, 0x108(x0)
        instr_mem[20] = enc_i(12'h004, 5'd21, 3'b000, 5'd21, 7'b0010011); // addi  x21, x21, 4
        instr_mem[21] = enc_i(12'h341, 5'd21, 3'b001, 5'd0,  7'b1110011); // csrrw x0,  mepc, x21
        instr_mem[22] = 32'h3020_0073;                                    // mret

        $dumpfile("build/tb_core_expansion_store_fault_trap.vcd");
        $dumpvars(0, tb_core_expansion_store_fault_trap);

        repeat (5) @(posedge clk);
        rst = 1'b0;

        cycle = 0;
        while ((cycle < 300) && !seen_sentinel_store) begin
            @(posedge clk);
            cycle = cycle + 1;
        end

        $display("==============================================");
        $display("TB core expansion store fault trap");
        $display("==============================================");

        check1 ("seen_invalid_mmio_store", seen_invalid_mmio_store);
        check1 ("seen_cause_store",        seen_cause_store);
        check1 ("seen_mepc_store",         seen_mepc_store);
        check1 ("seen_x12_store",          seen_x12_store);
        check1 ("seen_sentinel_store",     seen_sentinel_store);

        if (seen_bad_dmem_exp_write) begin
            $display("FAIL: dmem_we se activó para una dirección MMIO de expansión");
            $fatal(1);
        end
        else begin
            $display("PASS : seen_bad_dmem_exp_write = 0");
        end

        check64("captured_exp_wdata",  captured_exp_wdata,  EXPECTED_X12);
        check8 ("captured_exp_wstrb",  captured_exp_wstrb,  8'hff);
        check64("captured_cause",      captured_cause,      EXPECTED_CAUSE);
        check64("captured_mepc",       captured_mepc,       EXPECTED_MEPC);
        check64("captured_x12",        captured_x12,        EXPECTED_X12);
        check64("captured_sentinel",   captured_sentinel,   EXPECTED_SENTINEL);

        check64("data_mem[mcause]",    data_mem[ADDR_MCAUSE_STORE[12:3]],   EXPECTED_CAUSE);
        check64("data_mem[mepc]",      data_mem[ADDR_MEPC_STORE[12:3]],     EXPECTED_MEPC);
        check64("data_mem[x12]",       data_mem[ADDR_X12_AFTER_TRAP[12:3]], EXPECTED_X12);
        check64("data_mem[sentinel]",  data_mem[ADDR_SENTINEL[12:3]],       EXPECTED_SENTINEL);

        $display("==============================================");
        $display("PASS: tb_core_expansion_store_fault_trap cycles=%0d", cycle);
        $display("==============================================");
        $finish;
    end

    wire _unused_ok = 1'b0 && &{
        1'b0,
        dmem_size,
        exp_ready,
        exp_rdata,
        exp_size,
        1'b0
    };

endmodule
