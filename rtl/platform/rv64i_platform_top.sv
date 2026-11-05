`timescale 1ns/1ps

// TFG P2.6.2 - Integracion sintetizable del RV64I y RAM XPM UltraRAM.
// El ARM no esta conectado aun: el puerto boot_* sera el punto de entrada
// del futuro supervisor AXI. 'run_i' debe mantenerse bajo mientras se carga.
module rv64i_platform_top #(
    parameter logic [63:0] RAM_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] EXP_BASE = 64'h0000_0000_1000_0000,
    parameter int unsigned RAM_BYTES = 1048576
)(
    input  logic clk,
    input  logic rst,
    input  logic run_i,

    input  logic        boot_req_i,
    input  logic        boot_we_i,
    input  logic [63:0] boot_addr_i,
    input  logic [63:0] boot_wdata_i,
    input  logic [7:0]  boot_wstrb_i,
    output logic        boot_gnt_o,
    output logic        boot_rvalid_o,
    output logic [63:0] boot_rdata_o,
    output logic        boot_error_o,

    // Marcador de demostracion visible en ejecucion: 0=sin resultado, 1=PASS, 2=FAIL.
    output logic [1:0]  result_code_o
);
    logic core_rst;
    assign core_rst = rst || !run_i;

    logic        imem_req, imem_gnt, imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic        dmem_req, dmem_gnt, dmem_rvalid, dmem_error, dmem_we;
    logic [63:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [7:0]  dmem_wstrb;
    logic [1:0]  dmem_size;

    logic        exp_valid, exp_we, exp_ready, exp_error;
    logic [63:0] exp_addr, exp_wdata, exp_rdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;

    core_top #(
        .RESET_PC(RAM_BASE),
        .TRAP_VECTOR(RAM_BASE + 64'h100),
        .EXP_BASE(EXP_BASE),
        .EXP_MASK(64'hFFFF_FFFF_FFFF_F000)
    ) u_core (
        .clk(clk), .rst(core_rst),
        .imem_req(imem_req), .imem_addr(imem_addr),
        .imem_gnt(imem_gnt), .imem_rvalid(imem_rvalid), .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_gnt(dmem_gnt),
        .dmem_rvalid(dmem_rvalid), .dmem_error(dmem_error),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_size(dmem_size),
        .exp_valid(exp_valid), .exp_we(exp_we),
        .exp_addr(exp_addr), .exp_wdata(exp_wdata),
        .exp_wstrb(exp_wstrb), .exp_size(exp_size),
        .exp_ready(exp_ready), .exp_rdata(exp_rdata), .exp_error(exp_error)
    );

    rv64i_platform_ram #(
        .BASE_ADDR(RAM_BASE), .RAM_BYTES(RAM_BYTES)
    ) u_ram (
        .clk(clk), .rst(rst), .run_i(run_i),
        .imem_req_i(imem_req), .imem_addr_i(imem_addr),
        .imem_gnt_o(imem_gnt), .imem_rvalid_o(imem_rvalid),
        .imem_rdata_o(imem_rdata),
        .dmem_req_i(dmem_req), .dmem_addr_i(dmem_addr),
        .dmem_we_i(dmem_we), .dmem_wdata_i(dmem_wdata),
        .dmem_wstrb_i(dmem_wstrb),
        .dmem_gnt_o(dmem_gnt), .dmem_rvalid_o(dmem_rvalid),
        .dmem_rdata_o(dmem_rdata), .dmem_error_o(dmem_error),
        .boot_req_i(boot_req_i), .boot_we_i(boot_we_i),
        .boot_addr_i(boot_addr_i), .boot_wdata_i(boot_wdata_i),
        .boot_wstrb_i(boot_wstrb_i),
        .boot_gnt_o(boot_gnt_o), .boot_rvalid_o(boot_rvalid_o),
        .boot_rdata_o(boot_rdata_o), .boot_error_o(boot_error_o)
    );

    expansion_demo_periph u_accel (
        .clk(clk), .rst(core_rst),
        .exp_valid_i(exp_valid), .exp_we_i(exp_we),
        .exp_addr_i(exp_addr), .exp_wdata_i(exp_wdata),
        .exp_wstrb_i(exp_wstrb), .exp_size_i(exp_size),
        .exp_ready_o(exp_ready), .exp_rdata_o(exp_rdata),
        .exp_error_o(exp_error)
    );

    // Monitor pasivo del marcador definido por sw/baremetal/accelerator/start.S.
    // Solo considera escrituras confirmadas (respuesta DMEM sin error).
    // No altera el datapath ni la interfaz de memoria del nucleo.
    localparam logic [63:0] RESULT_ADDR = RAM_BASE + 64'h300;
    logic result_pending_q;
    logic [1:0] pending_code_q;
    always_ff @(posedge clk) begin
        if (rst || !run_i) begin
            result_pending_q <= 1'b0;
            pending_code_q <= 2'b00;
            result_code_o <= 2'b00;
        end else begin
            if (dmem_rvalid) begin
                if (result_pending_q && !dmem_error)
                    result_code_o <= pending_code_q;
                result_pending_q <= 1'b0;
            end
            if (dmem_req && dmem_gnt && dmem_we &&
                dmem_addr == RESULT_ADDR && dmem_wstrb == 8'hff) begin
                result_pending_q <= 1'b1;
                pending_code_q <= (dmem_wdata == 64'd1) ? 2'd1 :
                                  (dmem_wdata == 64'd2) ? 2'd2 : 2'd0;
            end
        end
    end

    // Interfaz dmem_size se usa internamente por core_top; la RAM
    // utiliza el strobe byte-wide generado por core para la escritura.
endmodule
