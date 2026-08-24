`timescale 1ns/1ps

module tb_exp_axi4lite_master_bridge;

    localparam logic [63:0] EXP_BASE      = 64'h0000_0000_8000_0000;
    localparam logic [63:0] REG_ID        = EXP_BASE + 64'h000;
    localparam logic [63:0] REG_VERSION   = EXP_BASE + 64'h008;
    localparam logic [63:0] REG_CONTROL   = EXP_BASE + 64'h010;
    localparam logic [63:0] REG_OPERAND_A = EXP_BASE + 64'h020;
    localparam logic [63:0] REG_OPERAND_B = EXP_BASE + 64'h028;
    localparam logic [63:0] REG_RESULT    = EXP_BASE + 64'h030;
    localparam logic [63:0] REG_INVALID   = EXP_BASE + 64'h040;

    logic clk;
    logic rst;

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

    logic [63:0] rd_data;
    logic        err;

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

    axi4lite_expansion_demo_periph u_axi_slave (
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

    task automatic check1;
        input string name;
        input logic got;
        input logic exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %s got=%0d expected=%0d", name, got, exp);
                $fatal(1);
            end
            else begin
                $display("PASS : %s = %0d", name, got);
            end
        end
    endtask

    task automatic exp_write64;
        input  logic [63:0] addr;
        input  logic [63:0] data;
        input  logic [7:0]  strb;
        output logic        error;
        begin
            // El TB conduce las entradas en el flanco opuesto al usado
            // por la lógica secuencial del DUT. Así quedan estables antes
            // del siguiente posedge y evitamos carreras de simulación.
            @(negedge clk);

            exp_addr  = addr;
            exp_wdata = data;
            exp_wstrb = strb;
            exp_size  = 2'b11;
            exp_we    = 1'b1;
            exp_valid = 1'b1;

            // El bridge mantiene exp_ready durante ST_DONE.
            wait (exp_ready === 1'b1);

            error = exp_error;

            // Retiramos la petición en negedge para que quede estable
            // antes del siguiente posedge.
            @(negedge clk);

            exp_valid = 1'b0;
            exp_we    = 1'b0;
            exp_wstrb = 8'd0;
        end
    endtask

    task automatic exp_read64;
        input  logic [63:0] addr;
        output logic [63:0] data;
        output logic        error;
        begin
            // Conducir en negedge evita competir con la lógica del DUT,
            // que captura las entradas en posedge.
            @(negedge clk);

            exp_addr  = addr;
            exp_wdata = 64'd0;
            exp_wstrb = 8'd0;
            exp_size  = 2'b11;
            exp_we    = 1'b0;
            exp_valid = 1'b1;

            wait (exp_ready === 1'b1);

            data  = exp_rdata;
            error = exp_error;

            @(negedge clk);

            exp_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        exp_valid = 1'b0;
        exp_we    = 1'b0;
        exp_addr  = 64'd0;
        exp_wdata = 64'd0;
        exp_wstrb = 8'd0;
        exp_size  = 2'd0;

        $dumpfile("build/tb_exp_axi4lite_master_bridge.vcd");
        $dumpvars(0, tb_exp_axi4lite_master_bridge);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("==============================================");
        $display("TB exp to AXI4-Lite master bridge");
        $display("==============================================");

        exp_read64(REG_ID, rd_data, err);
        check1 ("ID read error", err, 1'b0);
        check64("ID", rd_data, 64'h0000_0000_4558_5030);

        exp_read64(REG_VERSION, rd_data, err);
        check1 ("VERSION read error", err, 1'b0);
        check64("VERSION", rd_data, 64'h0000_0000_0000_0001);

        exp_write64(REG_OPERAND_A, 64'h0000_0000_0000_0011, 8'hff, err);
        check1("OPERAND_A write error", err, 1'b0);

        exp_write64(REG_OPERAND_B, 64'h0000_0000_0000_0022, 8'hff, err);
        check1("OPERAND_B write error", err, 1'b0);

        exp_write64(REG_CONTROL, 64'h0000_0000_0000_0001, 8'hff, err);
        check1("CONTROL.start write error", err, 1'b0);

        exp_read64(REG_RESULT, rd_data, err);
        check1 ("RESULT read error", err, 1'b0);
        check64("RESULT", rd_data, 64'h0000_0000_0000_0033);

        exp_write64(REG_OPERAND_A, 64'h1122_3344_5566_7788, 8'hff, err);
        check1("OPERAND_A full write error", err, 1'b0);

        exp_write64(REG_OPERAND_A, 64'h0000_0000_0000_00aa, 8'h01, err);
        check1("OPERAND_A partial write error", err, 1'b0);

        exp_read64(REG_OPERAND_A, rd_data, err);
        check1 ("OPERAND_A partial read error", err, 1'b0);
        check64("OPERAND_A partial", rd_data, 64'h1122_3344_5566_77aa);

        exp_write64(REG_RESULT, 64'hffff_ffff_ffff_ffff, 8'hff, err);
        check1("RESULT illegal write error", err, 1'b1);

        exp_read64(REG_INVALID, rd_data, err);
        check1 ("INVALID read error", err, 1'b1);
        check64("INVALID read data", rd_data, 64'h0000_0000_0000_0000);

        exp_write64(REG_INVALID, 64'h1234, 8'hff, err);
        check1("INVALID write error", err, 1'b1);

        $display("==============================================");
        $display("PASS: tb_exp_axi4lite_master_bridge");
        $display("==============================================");
        $finish;
    end

endmodule
