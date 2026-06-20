`timescale 1ns/1ps

module exp_axi4lite_master_bridge (
    input  logic        clk,
    input  logic        rst,

    // Lado simple tipo exp_* usado por el core
    input  logic        exp_valid_i,
    input  logic        exp_we_i,
    input  logic [63:0] exp_addr_i,
    input  logic [63:0] exp_wdata_i,
    input  logic [7:0]  exp_wstrb_i,
    input  logic [1:0]  exp_size_i,

    output logic        exp_ready_o,
    output logic [63:0] exp_rdata_o,
    output logic        exp_error_o,

    // AXI4-Lite master: write address channel
    output logic [63:0] m_axi_awaddr,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // AXI4-Lite master: write data channel
    output logic [63:0] m_axi_wdata,
    output logic [7:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // AXI4-Lite master: write response channel
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // AXI4-Lite master: read address channel
    output logic [63:0] m_axi_araddr,
    output logic [2:0]  m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // AXI4-Lite master: read data channel
    input  logic [63:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WRITE_ADDR_DATA,
        ST_WRITE_RESP,
        ST_READ_ADDR,
        ST_READ_DATA,
        ST_DONE
    } state_e;

    state_e state_q;

    logic        req_we_q;
    logic [63:0] req_addr_q;
    logic [63:0] req_wdata_q;
    logic [7:0]  req_wstrb_q;
    logic [1:0]  req_size_q;

    logic        aw_done_q;
    logic        w_done_q;

    logic [63:0] rdata_q;
    logic        error_q;

    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic ar_fire;
    logic r_fire;

    assign aw_fire = m_axi_awvalid && m_axi_awready;
    assign w_fire  = m_axi_wvalid  && m_axi_wready;
    assign b_fire  = m_axi_bvalid  && m_axi_bready;
    assign ar_fire = m_axi_arvalid && m_axi_arready;
    assign r_fire  = m_axi_rvalid  && m_axi_rready;

    assign m_axi_awaddr = req_addr_q;
    assign m_axi_awprot = 3'b000;

    assign m_axi_wdata  = req_wdata_q;
    assign m_axi_wstrb  = req_wstrb_q;

    assign m_axi_araddr = req_addr_q;
    assign m_axi_arprot = 3'b000;

    assign m_axi_awvalid = (state_q == ST_WRITE_ADDR_DATA) && !aw_done_q;
    assign m_axi_wvalid  = (state_q == ST_WRITE_ADDR_DATA) && !w_done_q;
    assign m_axi_bready  = (state_q == ST_WRITE_RESP);

    assign m_axi_arvalid = (state_q == ST_READ_ADDR);
    assign m_axi_rready  = (state_q == ST_READ_DATA);

    // Pulso de finalización hacia el lado exp_*.
    // El dato/error son válidos cuando exp_ready_o=1.
    assign exp_ready_o = (state_q == ST_DONE);
    assign exp_rdata_o = rdata_q;
    assign exp_error_o = error_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q     <= ST_IDLE;

            req_we_q    <= 1'b0;
            req_addr_q  <= 64'd0;
            req_wdata_q <= 64'd0;
            req_wstrb_q <= 8'd0;
            req_size_q  <= 2'd0;

            aw_done_q   <= 1'b0;
            w_done_q    <= 1'b0;

            rdata_q     <= 64'd0;
            error_q     <= 1'b0;
        end
        else begin
            case (state_q)
                ST_IDLE: begin
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                    rdata_q   <= 64'd0;
                    error_q   <= 1'b0;

                    if (exp_valid_i) begin
                        req_we_q    <= exp_we_i;
                        req_addr_q  <= exp_addr_i;
                        req_wdata_q <= exp_wdata_i;
                        req_wstrb_q <= exp_we_i ? exp_wstrb_i : 8'd0;
                        req_size_q  <= exp_size_i;

                        if (exp_we_i) begin
                            state_q <= ST_WRITE_ADDR_DATA;
                        end
                        else begin
                            state_q <= ST_READ_ADDR;
                        end
                    end
                end

                ST_WRITE_ADDR_DATA: begin
                    if (aw_fire) begin
                        aw_done_q <= 1'b1;
                    end

                    if (w_fire) begin
                        w_done_q <= 1'b1;
                    end

                    if ((aw_done_q || aw_fire) && (w_done_q || w_fire)) begin
                        state_q <= ST_WRITE_RESP;
                    end
                end

                ST_WRITE_RESP: begin
                    if (b_fire) begin
                        error_q <= (m_axi_bresp != AXI_RESP_OKAY);
                        rdata_q <= 64'd0;
                        state_q <= ST_DONE;
                    end
                end

                ST_READ_ADDR: begin
                    if (ar_fire) begin
                        state_q <= ST_READ_DATA;
                    end
                end

                ST_READ_DATA: begin
                    if (r_fire) begin
                        rdata_q <= m_axi_rdata;
                        error_q <= (m_axi_rresp != AXI_RESP_OKAY);
                        state_q <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state_q <= ST_IDLE;
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

    wire _unused_ok = 1'b0 && &{
        1'b0,
        req_we_q,
        req_size_q,
        1'b0
    };

endmodule
