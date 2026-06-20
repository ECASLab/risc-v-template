`timescale 1ns/1ps

module tb_axi4lite_expansion_demo_periph;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    localparam logic [63:0] REG_ID        = 64'h000;
    localparam logic [63:0] REG_VERSION   = 64'h008;
    localparam logic [63:0] REG_CONTROL   = 64'h010;
    localparam logic [63:0] REG_STATUS    = 64'h018;
    localparam logic [63:0] REG_OPERAND_A = 64'h020;
    localparam logic [63:0] REG_OPERAND_B = 64'h028;
    localparam logic [63:0] REG_RESULT    = 64'h030;
    localparam logic [63:0] REG_INVALID   = 64'h040;

    logic clk;
    logic rst;

    logic [63:0] s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;

    logic [63:0] s_axi_wdata;
    logic [7:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;

    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    logic [63:0] s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;

    logic [63:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    logic [63:0] rd_data;
    logic [1:0]  resp;

    axi4lite_expansion_demo_periph dut (
        .clk(clk),
        .rst(rst),

        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );

    always #5 clk = ~clk;

    initial begin
        #1000000;
        $display("FAIL: timeout global en tb_axi4lite_expansion_demo_periph");
        $fatal(1);
    end

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

    task automatic check_resp;
        input string name;
        input logic [1:0] got;
        input logic [1:0] exp;
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

    task automatic axi_write64;
        input  logic [63:0] addr;
        input  logic [63:0] data;
        input  logic [7:0]  strb;
        output logic [1:0]  out_resp;

        integer timeout;
        logic aw_done;
        logic w_done;

        begin
            aw_done = 1'b0;
            w_done  = 1'b0;
            timeout = 0;

            // Manejar señales desde negedge evita carreras con el DUT en posedge.
            @(negedge clk);
            s_axi_awaddr  = addr;
            s_axi_awprot  = 3'b000;
            s_axi_awvalid = 1'b1;

            s_axi_wdata   = data;
            s_axi_wstrb   = strb;
            s_axi_wvalid  = 1'b1;

            s_axi_bready  = 1'b1;

            while (!aw_done || !w_done) begin
                @(posedge clk);

                if (s_axi_awvalid && s_axi_awready) begin
                    aw_done = 1'b1;
                end

                if (s_axi_wvalid && s_axi_wready) begin
                    w_done = 1'b1;
                end

                @(negedge clk);

                if (aw_done) begin
                    s_axi_awvalid = 1'b0;
                end

                if (w_done) begin
                    s_axi_wvalid = 1'b0;
                end

                timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("FAIL: timeout esperando handshake AXI write addr=0x%016h", addr);
                    $fatal(1);
                end
            end

            timeout = 0;
            while (!(s_axi_bvalid && s_axi_bready)) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("FAIL: timeout esperando BVALID addr=0x%016h", addr);
                    $fatal(1);
                end
            end

            out_resp = s_axi_bresp;

            @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    task automatic axi_read64;
        input  logic [63:0] addr;
        output logic [63:0] out_data;
        output logic [1:0]  out_resp;

        integer timeout;

        begin
            timeout = 0;

            @(negedge clk);
            s_axi_araddr  = addr;
            s_axi_arprot  = 3'b000;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;

            while (!(s_axi_arvalid && s_axi_arready)) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("FAIL: timeout esperando ARREADY addr=0x%016h", addr);
                    $fatal(1);
                end
            end

            @(negedge clk);
            s_axi_arvalid = 1'b0;

            timeout = 0;
            while (!(s_axi_rvalid && s_axi_rready)) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) begin
                    $display("FAIL: timeout esperando RVALID addr=0x%016h", addr);
                    $fatal(1);
                end
            end

            out_data = s_axi_rdata;
            out_resp = s_axi_rresp;

            @(negedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        s_axi_awaddr  = 64'd0;
        s_axi_awprot  = 3'd0;
        s_axi_awvalid = 1'b0;

        s_axi_wdata   = 64'd0;
        s_axi_wstrb   = 8'd0;
        s_axi_wvalid  = 1'b0;

        s_axi_bready  = 1'b0;

        s_axi_araddr  = 64'd0;
        s_axi_arprot  = 3'd0;
        s_axi_arvalid = 1'b0;

        s_axi_rready  = 1'b0;

        $dumpfile("build/tb_axi4lite_expansion_demo_periph.vcd");
        $dumpvars(0, tb_axi4lite_expansion_demo_periph);

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("==============================================");
        $display("TB AXI4-Lite expansion demo peripheral");
        $display("==============================================");

        axi_read64(REG_ID, rd_data, resp);
        check_resp("ID read response", resp, AXI_RESP_OKAY);
        check64("ID", rd_data, 64'h0000_0000_4558_5030);

        axi_read64(REG_VERSION, rd_data, resp);
        check_resp("VERSION read response", resp, AXI_RESP_OKAY);
        check64("VERSION", rd_data, 64'h0000_0000_0000_0001);

        axi_write64(REG_OPERAND_A, 64'h0000_0000_0000_0011, 8'hff, resp);
        check_resp("OPERAND_A write response", resp, AXI_RESP_OKAY);

        axi_write64(REG_OPERAND_B, 64'h0000_0000_0000_0022, 8'hff, resp);
        check_resp("OPERAND_B write response", resp, AXI_RESP_OKAY);

        axi_write64(REG_CONTROL, 64'h0000_0000_0000_0001, 8'hff, resp);
        check_resp("CONTROL.start write response", resp, AXI_RESP_OKAY);

        axi_read64(REG_RESULT, rd_data, resp);
        check_resp("RESULT read response", resp, AXI_RESP_OKAY);
        check64("RESULT", rd_data, 64'h0000_0000_0000_0033);

        axi_read64(REG_STATUS, rd_data, resp);
        check_resp("STATUS read response", resp, AXI_RESP_OKAY);
        check64("STATUS done", rd_data, 64'h0000_0000_0000_0002);

        axi_write64(REG_STATUS, 64'h0000_0000_0000_0002, 8'hff, resp);
        check_resp("STATUS W1C write response", resp, AXI_RESP_OKAY);

        axi_read64(REG_STATUS, rd_data, resp);
        check_resp("STATUS after W1C read response", resp, AXI_RESP_OKAY);
        check64("STATUS after W1C", rd_data, 64'h0000_0000_0000_0000);

        axi_write64(REG_OPERAND_A, 64'h1122_3344_5566_7788, 8'hff, resp);
        check_resp("OPERAND_A full write response", resp, AXI_RESP_OKAY);

        axi_write64(REG_OPERAND_A, 64'h0000_0000_0000_00aa, 8'h01, resp);
        check_resp("OPERAND_A partial write response", resp, AXI_RESP_OKAY);

        axi_read64(REG_OPERAND_A, rd_data, resp);
        check_resp("OPERAND_A partial read response", resp, AXI_RESP_OKAY);
        check64("OPERAND_A partial", rd_data, 64'h1122_3344_5566_77aa);

        axi_write64(REG_RESULT, 64'hffff_ffff_ffff_ffff, 8'hff, resp);
        check_resp("RESULT illegal write response", resp, AXI_RESP_SLVERR);

        axi_read64(REG_INVALID, rd_data, resp);
        check_resp("INVALID read response", resp, AXI_RESP_SLVERR);
        check64("INVALID read data", rd_data, 64'h0000_0000_0000_0000);

        axi_write64(REG_INVALID, 64'h1234, 8'hff, resp);
        check_resp("INVALID write response", resp, AXI_RESP_SLVERR);

        $display("==============================================");
        $display("PASS: tb_axi4lite_expansion_demo_periph");
        $display("==============================================");
        $finish;
    end

endmodule
