`timescale 1ns/1ps

module axi4lite_expansion_demo_periph (
    input  logic        clk,
    input  logic        rst,

    // AXI4-Lite slave: write address channel
    input  logic [63:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // AXI4-Lite slave: write data channel
    input  logic [63:0] s_axi_wdata,
    input  logic [7:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // AXI4-Lite slave: write response channel
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // AXI4-Lite slave: read address channel
    input  logic [63:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // AXI4-Lite slave: read data channel
    output logic [63:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WRITE_ISSUE,
        ST_WRITE_RESP,
        ST_READ_ISSUE,
        ST_READ_RESP
    } state_e;

    state_e state_q;

    logic        aw_seen_q;
    logic        w_seen_q;

    logic [63:0] awaddr_q;
    logic [63:0] wdata_q;
    logic [7:0]  wstrb_q;
    logic [63:0] araddr_q;

    logic        aw_fire;
    logic        w_fire;
    logic        ar_fire;
    logic        write_ready_to_issue;

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign s_axi_awready = (state_q == ST_IDLE) && !aw_seen_q;
    assign s_axi_wready  = (state_q == ST_IDLE) && !w_seen_q;

    // Primera versión simple: no acepta una lectura si hay una escritura parcial o completa pendiente.
    assign s_axi_arready = (state_q == ST_IDLE) &&
                           !aw_seen_q &&
                           !w_seen_q &&
                           !s_axi_awvalid &&
                           !s_axi_wvalid;

    assign aw_fire = s_axi_awvalid && s_axi_awready;
    assign w_fire  = s_axi_wvalid  && s_axi_wready;
    assign ar_fire = s_axi_arvalid && s_axi_arready;

    assign write_ready_to_issue = (aw_seen_q || aw_fire) && (w_seen_q || w_fire);

    assign exp_valid = (state_q == ST_WRITE_ISSUE) || (state_q == ST_READ_ISSUE);
    assign exp_we    = (state_q == ST_WRITE_ISSUE);
    assign exp_addr  = (state_q == ST_WRITE_ISSUE) ? awaddr_q : araddr_q;
    assign exp_wdata = wdata_q;
    assign exp_wstrb = wstrb_q;
    assign exp_size  = 2'b11; // acceso de 64 bits

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

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q      <= ST_IDLE;

            aw_seen_q    <= 1'b0;
            w_seen_q     <= 1'b0;

            awaddr_q     <= 64'd0;
            wdata_q      <= 64'd0;
            wstrb_q      <= 8'd0;
            araddr_q     <= 64'd0;

            s_axi_bresp  <= AXI_RESP_OKAY;
            s_axi_bvalid <= 1'b0;

            s_axi_rdata  <= 64'd0;
            s_axi_rresp  <= AXI_RESP_OKAY;
            s_axi_rvalid <= 1'b0;
        end
        else begin
            case (state_q)
                ST_IDLE: begin
                    if (aw_fire) begin
                        awaddr_q  <= s_axi_awaddr;
                        aw_seen_q <= 1'b1;
                    end

                    if (w_fire) begin
                        wdata_q  <= s_axi_wdata;
                        wstrb_q  <= s_axi_wstrb;
                        w_seen_q <= 1'b1;
                    end

                    if (ar_fire) begin
                        araddr_q <= s_axi_araddr;
                        state_q  <= ST_READ_ISSUE;
                    end
                    else if (write_ready_to_issue) begin
                        state_q <= ST_WRITE_ISSUE;
                    end
                end

                ST_WRITE_ISSUE: begin
                    if (exp_ready) begin
                        s_axi_bresp  <= exp_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                        s_axi_bvalid <= 1'b1;
                        state_q      <= ST_WRITE_RESP;
                    end
                end

                ST_WRITE_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        s_axi_bresp  <= AXI_RESP_OKAY;

                        aw_seen_q    <= 1'b0;
                        w_seen_q     <= 1'b0;

                        state_q      <= ST_IDLE;
                    end
                end

                ST_READ_ISSUE: begin
                    if (exp_ready) begin
                        s_axi_rdata  <= exp_rdata;
                        s_axi_rresp  <= exp_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                        s_axi_rvalid <= 1'b1;
                        state_q      <= ST_READ_RESP;
                    end
                end

                ST_READ_RESP: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rdata  <= 64'd0;
                        s_axi_rresp  <= AXI_RESP_OKAY;
                        state_q      <= ST_IDLE;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

    wire _unused_ok = 1'b0 && &{
        1'b0,
        s_axi_awprot,
        s_axi_arprot,
        1'b0
    };

endmodule
