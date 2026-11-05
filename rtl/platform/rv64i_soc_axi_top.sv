`timescale 1ns/1ps
// TFG P2.7.1 - SoC PL: un unico dominio de reloj para PS->AXI y RV64I.
// El PS debe aportar s_axi_aclk y reset sincronizado activo bajo.
module rv64i_soc_axi_top #(
    parameter int unsigned RAM_BYTES = 1048576
)(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [11:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [11:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);
    logic run;
    logic [1:0] result_code;
    logic boot_req, boot_we;
    logic [63:0] boot_addr, boot_wdata, boot_rdata;
    logic [7:0] boot_wstrb;
    logic boot_gnt, boot_rvalid, boot_error;
    rv64i_axi_supervisor u_supervisor (
        .clk(s_axi_aclk), .rst_n(s_axi_aresetn),
        .s_axi_awaddr, .s_axi_awprot, .s_axi_awvalid, .s_axi_awready,
        .s_axi_wdata, .s_axi_wstrb, .s_axi_wvalid, .s_axi_wready,
        .s_axi_bresp, .s_axi_bvalid, .s_axi_bready,
        .s_axi_araddr, .s_axi_arprot, .s_axi_arvalid, .s_axi_arready,
        .s_axi_rdata, .s_axi_rresp, .s_axi_rvalid, .s_axi_rready,
        .run_o(run), .result_code_i(result_code),
        .boot_req_o(boot_req), .boot_we_o(boot_we),
        .boot_addr_o(boot_addr), .boot_wdata_o(boot_wdata),
        .boot_wstrb_o(boot_wstrb), .boot_gnt_i(boot_gnt),
        .boot_rvalid_i(boot_rvalid), .boot_rdata_i(boot_rdata),
        .boot_error_i(boot_error)
    );
    rv64i_platform_top #(.RAM_BYTES(RAM_BYTES)) u_platform (
        .clk(s_axi_aclk), .rst(!s_axi_aresetn), .run_i(run),
        .boot_req_i(boot_req), .boot_we_i(boot_we),
        .boot_addr_i(boot_addr), .boot_wdata_i(boot_wdata),
        .boot_wstrb_i(boot_wstrb), .boot_gnt_o(boot_gnt),
        .boot_rvalid_o(boot_rvalid), .boot_rdata_o(boot_rdata),
        .boot_error_o(boot_error), .result_code_o(result_code)
    );
endmodule
