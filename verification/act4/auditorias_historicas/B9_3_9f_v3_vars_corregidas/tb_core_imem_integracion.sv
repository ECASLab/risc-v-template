`timescale 1ns/1ps
// B.9.3.9f: comportamiento de fetch en core_top + IMEM original.
// + TEST_ID se pasa como macro de COMPILACION (-DTEST_ID=...).
// 1 = fetch valido; 2..5 = reset PC fuera de RAM -> fatal esperado del MODELO.
// NO acredita instruction access fault ni modifica RTL.
`ifndef TEST_ID
`define TEST_ID 1
`endif
module tb_core_imem_integracion;
  localparam integer CASE_ID = `TEST_ID;
  localparam logic [63:0] BASE = 64'h0000_0000_8000_0000;
  localparam logic [63:0] BYTES = 64'd256;
  localparam logic [63:0] START_PC =
      (CASE_ID == 1) ? BASE :
      (CASE_ID == 2) ? BASE + BYTES :
      (CASE_ID == 3) ? BASE - 64'd4 :
      (CASE_ID == 4) ? BASE + 64'h0000_0001_0000_0000 :
      (CASE_ID == 5) ? BASE + 64'h0100_0000_0000_0000 :
                       64'hFFFF_FFFF_FFFF_FFFF;
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;
  wire imem_req, imem_gnt, imem_rvalid;
  wire [63:0] imem_addr;
  wire [31:0] imem_rdata;
  wire dmem_req, dmem_we;
  wire [7:0] dmem_wstrb;
  wire [63:0] dmem_addr, dmem_wdata;
  wire [1:0] dmem_size;
  wire exp_valid, exp_we;
  wire [63:0] exp_addr, exp_wdata;
  wire [7:0] exp_wstrb;
  wire [1:0] exp_size;
  integer i;
  integer observed_req = 0;
  integer observed_valid = 0;

  core_top #(
    .RESET_PC(START_PC),
    .TRAP_VECTOR(BASE + 64'h100),
    .EXP_BASE(64'h0000_0000_1000_0000)
  ) dut (
    .clk(clk), .rst(rst),
    .imem_req(imem_req), .imem_addr(imem_addr),
    .imem_gnt(imem_gnt), .imem_rvalid(imem_rvalid), .imem_rdata(imem_rdata),
    .dmem_req(dmem_req), .dmem_gnt(1'b1),
    .dmem_rvalid(1'b0), .dmem_error(1'b0), .dmem_rdata(64'd0),
    .dmem_we(dmem_we), .dmem_wstrb(dmem_wstrb),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_size(dmem_size),
    .exp_valid(exp_valid), .exp_we(exp_we), .exp_addr(exp_addr),
    .exp_wdata(exp_wdata), .exp_wstrb(exp_wstrb), .exp_size(exp_size),
    .exp_ready(1'b1), .exp_rdata(64'd0), .exp_error(1'b0)
  );

  imem_sync_model #(
    .MEM_WORDS(64), .BASE_ADDR(BASE),
    .GNT_DELAY(1), .RESP_DELAY(2)
  ) u_imem (
    .clk(clk), .rst(rst),
    .req_i(imem_req), .gnt_o(imem_gnt), .addr_i(imem_addr),
    .rvalid_o(imem_rvalid), .rdata_o(imem_rdata)
  );

  initial begin
    if (CASE_ID < 1 || CASE_ID > 5)
      $fatal(1, "FAIL_CASE_ID: %0d", CASE_ID);
    for (i=0; i<64; i=i+1)
      u_imem.mem[i] = 32'h0000_0013; // ADDI x0,x0,0 = NOP
    u_imem.mem[0] = 32'h0000_006f; // JAL x0, 0; solo validar el primer fetch
    repeat (5) @(negedge clk);
    rst = 1'b0;
    $display("INFO_CORE_CASE: ID=%0d reset_pc=0x%016h", CASE_ID, START_PC);
  end

  // Comprobacion temprana de la direccion solicitada (antes del grant fatal).
  always @(negedge clk) begin
    if (!rst && imem_req && observed_req == 0) begin
      if (imem_addr !== START_PC)
        $fatal(1, "FAIL_FIRST_FETCH: observado=0x%016h esperado=0x%016h", imem_addr, START_PC);
      observed_req = 1;
      $display("TB_CORE_REQUEST: addr=0x%016h", imem_addr);
    end
  end

  always @(posedge clk) begin
    if (!rst) begin
      if (dut.trap_taken_valid === 1'b1)
        $fatal(1, "FAIL_UNEXPECTED_TRAP: code=0x%016h", dut.trap_taken_cause);
      if (imem_rvalid && CASE_ID != 1)
        $fatal(1, "FAIL_INVALID_PC_RESPONSE: addr=0x%016h", START_PC);
      if (CASE_ID == 1 && dut.imem_resp_valid && observed_valid == 0) begin
        if (dut.imem_resp_addr !== BASE || dut.imem_resp_data !== 32'h0000_006f)
          $fatal(1, "FAIL_VALID_FETCH: addr=0x%016h data=0x%08h", dut.imem_resp_addr, dut.imem_resp_data);
        observed_valid = 1;
        $display("PASS_CORE_VALID_FETCH: addr=0x%016h data=0x%08h", dut.imem_resp_addr, dut.imem_resp_data);
        $finish;
      end
    end
  end
  initial begin
    #5000;
    $fatal(1, "FAIL_TIMEOUT: case=%0d observed_req=%0d", CASE_ID, observed_req);
  end
endmodule
