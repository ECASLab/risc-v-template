`timescale 1ns/1ps

module tb_core_expansion_axi4lite_wait;

    localparam logic [63:0] EXP_BASE = 64'h0000_0000_8000_0000;
    localparam int unsigned IMEM_WORDS = 256;

    localparam logic [63:0] ADDR_RESULT   = 64'h0000_0000_0000_0200;
    localparam logic [63:0] ADDR_SENTINEL = 64'h0000_0000_0000_0208;

    localparam logic [63:0] EXPECTED_RESULT   = 64'h0000_0000_0000_0033;
    localparam logic [63:0] EXPECTED_SENTINEL = 64'h0000_0000_0000_007b;

    logic clk;
    logic rst;

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

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    logic [63:0] axi_awaddr;
    logic [2:0]  axi_awprot;
    logic        axi_awvalid;
    logic        axi_awready;

    logic [63:0] axi_wdata;
    logic [7:0]  axi_wstrb;
    logic        axi_wvalid;
    logic        axi_wready;

    logic [1:0]  axi_bresp;
    logic        axi_bvalid;
    logic        axi_bready;

    logic [63:0] axi_araddr;
    logic [2:0]  axi_arprot;
    logic        axi_arvalid;
    logic        axi_arready;

    logic [63:0] axi_rdata;
    logic [1:0]  axi_rresp;
    logic        axi_rvalid;
    logic        axi_rready;
 
    logic [63:0] data_mem  [0:1023];

    logic        seen_result_store;
    logic        seen_sentinel_store;
    logic        seen_bad_dmem_exp_write;

    logic [63:0] captured_result;
    logic [63:0] captured_sentinel;

    integer i;
    integer cycle;
    integer exp_wait_cycles;

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

    task automatic check0;
        input string name;
        input logic  value;
        begin
            if (value) begin
                $display("FAIL: %s = 1", name);
                $fatal(1);
            end
            else begin
                $display("PASS : %s = 0", name);
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

    // =========================================================
    // IMEM síncrona real
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

    core_top #(
        .RESET_PC(64'h0000_0000_0000_0000),
        .TRAP_VECTOR(64'h0000_0000_0000_0100),
        .EXP_BASE(EXP_BASE),
        .EXP_MASK(64'hFFFF_FFFF_FFFF_F000)
    ) u_core (
        .clk(clk),
        .rst(rst),

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

    exp_axi4lite_master_bridge u_bridge (
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
        .exp_error_o(exp_error),

        .m_axi_awaddr(axi_awaddr),
        .m_axi_awprot(axi_awprot),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),

        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),

        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),

        .m_axi_araddr(axi_araddr),
        .m_axi_arprot(axi_arprot),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),

        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );

    axi4lite_expansion_demo_periph u_axi_periph (
        .clk(clk),
        .rst(rst),

        .s_axi_awaddr(axi_awaddr),
        .s_axi_awprot(axi_awprot),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),

        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),

        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),

        .s_axi_araddr(axi_araddr),
        .s_axi_arprot(axi_arprot),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),

        .s_axi_rdata(axi_rdata),
        .s_axi_rresp(axi_rresp),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );

    always #5 clk = ~clk;

    always @(*) begin 

        if (dmem_addr[63:13] != 51'd0) begin
            dmem_rdata = 64'd0;
        end
        else begin
            dmem_rdata = data_mem[dmem_addr[12:3]];
        end
    end

    always @(posedge clk) begin
        if (exp_valid && !exp_ready) begin
            exp_wait_cycles <= exp_wait_cycles + 1;
        end

        if (dmem_we) begin
            if ((dmem_addr & 64'hFFFF_FFFF_FFFF_F000) == EXP_BASE) begin
                seen_bad_dmem_exp_write <= 1'b1;
                $display("INFO : ERROR dmem_we hacia region EXP addr=0x%016h", dmem_addr);
            end
            else begin
                data_mem[dmem_addr[12:3]] <= apply_wstrb(
                    data_mem[dmem_addr[12:3]],
                    dmem_wdata,
                    dmem_wstrb
                );

                if (dmem_addr == ADDR_RESULT) begin
                    seen_result_store <= 1'b1;
                    captured_result   <= dmem_wdata;
                    $display("INFO : result store addr=0x%016h data=0x%016h", dmem_addr, dmem_wdata);
                end

                if (dmem_addr == ADDR_SENTINEL) begin
                    seen_sentinel_store <= 1'b1;
                    captured_sentinel   <= dmem_wdata;
                    $display("INFO : sentinel store addr=0x%016h data=0x%016h", dmem_addr, dmem_wdata);
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        seen_result_store       = 1'b0;
        seen_sentinel_store     = 1'b0;
        seen_bad_dmem_exp_write = 1'b0;

        captured_result   = 64'd0;
        captured_sentinel = 64'd0;

        exp_wait_cycles = 0;

        for (i = 0; i < IMEM_WORDS; i = i + 1) begin
            u_imem.mem[i] = 32'h0000_0013;
        end

        for (i = 0; i < 1024; i = i + 1) begin
            data_mem[i] = 64'd0;
        end

        // x10 = 0x80000000
        u_imem.mem[0]  = enc_i(12'h001, 5'd0,  3'b000, 5'd10, 7'b0010011); // addi x10, x0, 1
        u_imem.mem[1]  = enc_i(12'd31,  5'd10, 3'b001, 5'd10, 7'b0010011); // slli x10, x10, 31

        // OPERAND_A = 0x11
        u_imem.mem[2]  = enc_i(12'h011, 5'd0,  3'b000, 5'd1,  7'b0010011); // addi x1, x0, 0x11
        u_imem.mem[3]  = enc_s(12'h020, 5'd1,  5'd10, 3'b011, 7'b0100011); // sd x1, 0x20(x10)

        // OPERAND_B = 0x22
        u_imem.mem[4]  = enc_i(12'h022, 5'd0,  3'b000, 5'd2,  7'b0010011); // addi x2, x0, 0x22
        u_imem.mem[5]  = enc_s(12'h028, 5'd2,  5'd10, 3'b011, 7'b0100011); // sd x2, 0x28(x10)

        // CONTROL.start = 1
        u_imem.mem[6]  = enc_i(12'h001, 5'd0,  3'b000, 5'd3,  7'b0010011); // addi x3, x0, 1
        u_imem.mem[7]  = enc_s(12'h010, 5'd3,  5'd10, 3'b011, 7'b0100011); // sd x3, 0x10(x10)

        // Leer RESULT y almacenarlo en memoria normal.
        // El store inmediatamente posterior usa x4, por lo que también valida load-use.
        u_imem.mem[8]  = enc_i(12'h030, 5'd10, 3'b011, 5'd4,  7'b0000011); // ld x4, 0x30(x10)
        u_imem.mem[9]  = enc_s(12'h200, 5'd4,  5'd0,  3'b011, 7'b0100011); // sd x4, 0x200(x0)

        // Centinela de continuidad
        u_imem.mem[10] = enc_i(12'h07b, 5'd0,  3'b000, 5'd5,  7'b0010011); // addi x5, x0, 0x7b
        u_imem.mem[11] = enc_s(12'h208, 5'd5,  5'd0,  3'b011, 7'b0100011); // sd x5, 0x208(x0)
        u_imem.mem[12] = enc_jal_zero();

        $dumpfile("build/tb_core_expansion_axi4lite_wait.vcd");
        $dumpvars(0, tb_core_expansion_axi4lite_wait);

        repeat (5) @(posedge clk);
        rst = 1'b0;

        cycle = 0;
        while ((cycle < 500) && !seen_sentinel_store) begin
            @(posedge clk);
            cycle = cycle + 1;
        end

        $display("==============================================");
        $display("TB core expansion AXI4-Lite wait-state");
        $display("==============================================");

        check1 ("seen_result_store",       seen_result_store);
        check1 ("seen_sentinel_store",     seen_sentinel_store);
        check0 ("seen_bad_dmem_exp_write", seen_bad_dmem_exp_write);

        if (exp_wait_cycles <= 0) begin
            $display("FAIL: exp_wait_cycles = %0d, no se observó espera por exp_ready", exp_wait_cycles);
            $fatal(1);
        end
        else begin
            $display("PASS : exp_wait_cycles = %0d", exp_wait_cycles);
        end

        check64("captured_result",   captured_result,   EXPECTED_RESULT);
        check64("captured_sentinel", captured_sentinel, EXPECTED_SENTINEL);
        check64("data_mem[result]",  data_mem[ADDR_RESULT[12:3]],   EXPECTED_RESULT);
        check64("data_mem[sentinel]", data_mem[ADDR_SENTINEL[12:3]], EXPECTED_SENTINEL);

        $display("==============================================");
        $display("PASS: tb_core_expansion_axi4lite_wait cycles=%0d", cycle);
        $display("==============================================");
        $finish;
    end

    wire _unused_ok = 1'b0 && &{
        1'b0,
        dmem_size,
        axi_awprot,
        axi_arprot,
        1'b0
    };

endmodule
