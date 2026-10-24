`timescale 1ns/1ps
// B.9.3.9h: orden observable de accesos MMIO sobre core_top real.
// Ejecutar dos variantes: CASE_ID=1 incluye FENCE IORW,IORW;
// CASE_ID=2 reemplaza ambos FENCE por NOP para establecer contraste.
// El test verifica SOLO la ruta in-order/single outstanding de la plataforma actual.
// No demuestra RVWMO completo ni el comportamiento de perifericos externos arbitrarios.
`ifndef CASE_ID
`define CASE_ID 1
`endif
module tb_b9h_fence_mmio;
  localparam integer CASE_NUM = `CASE_ID;
  localparam logic [63:0] BASE = 64'h0000_0000_8000_0000;
  localparam logic [63:0] EXP_BASE = 64'h0000_0000_1000_0000;
  localparam logic [31:0] FENCE_IORW_IORW = 32'h0ff0_000f;
  localparam logic [31:0] NOP = 32'h0000_0013;
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
  wire exp_ready;
  integer wait_cycles = 0;
  integer done_count = 0;
  integer hold_count = 0;
  integer target_delay;
  integer i;

  // Las tres operaciones MMIO esperan una latencia distinta: 6, 4, 7 ciclos.
  // El objetivo es detectar si una operacion posterior se hace observable
  // antes de terminar su antecesora, no inferir orden desde el PC especulativo.
  always_comb begin
    case (done_count)
      0: target_delay = 6;
      1: target_delay = 4;
      default: target_delay = 7;
    endcase
  end
  assign exp_ready = exp_valid && (wait_cycles >= target_delay);

  core_top #(
    .RESET_PC(BASE),
    .TRAP_VECTOR(BASE + 64'h100),
    .EXP_BASE(EXP_BASE)
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
    .exp_ready(exp_ready), .exp_rdata(64'h0000_0000_0000_0055), .exp_error(1'b0)
  );

  imem_sync_model #(
    .MEM_WORDS(64), .BASE_ADDR(BASE), .GNT_DELAY(1), .RESP_DELAY(2)
  ) u_imem (
    .clk(clk), .rst(rst),
    .req_i(imem_req), .gnt_o(imem_gnt), .addr_i(imem_addr),
    .rvalid_o(imem_rvalid), .rdata_o(imem_rdata)
  );

  initial begin
    if (CASE_NUM != 1 && CASE_NUM != 2)
      $fatal(1,"FAIL_CASE_NUM: %0d", CASE_NUM);
    for (i = 0; i < 64; i = i + 1)
      u_imem.mem[i] = NOP;
    // LUI x1,0x10000          -> x1=0x10000000 (periferico MMIO)
    // ADDI x2,x0,0x55        -> valor a escribir
    // SW x2,0(x1)            -> primera transaccion MMIO con latencia
    // FENCE IORW,IORW        -> ordenamiento previo/siguiente (caso 1)
    // LW x3,0(x1)            -> lectura MMIO con retorno de 0x55
    // FENCE IORW,IORW        -> segundo ordenamiento (caso 1)
    // SW x3,8(x1)            -> tercera transaccion; comprueba valor leido
    // JAL x0,0              -> evita seguir mas alla del programa
    u_imem.mem[0] = 32'h1000_00b7;
    u_imem.mem[1] = 32'h0550_0113;
    u_imem.mem[2] = 32'h0020_a023;
    u_imem.mem[3] = (CASE_NUM == 1) ? FENCE_IORW_IORW : NOP;
    u_imem.mem[4] = 32'h0000_a183;
    u_imem.mem[5] = (CASE_NUM == 1) ? FENCE_IORW_IORW : NOP;
    u_imem.mem[6] = 32'h0030_a423;
    u_imem.mem[7] = 32'h0000_006f;
    repeat (5) @(negedge clk);
    rst = 1'b0;
    $display("TB_B9H_START: case=%0d fence=%0d",CASE_NUM,CASE_NUM==1);
  end

  // Una unica fuente de actualizacion de contadores evita carreras de scheduling.
  always @(posedge clk) begin
    if (rst) begin
      wait_cycles <= 0;
      done_count <= 0;
      hold_count <= 0;
    end else begin
      if (dut.trap_taken_valid === 1'b1)
        $fatal(1,"FAIL_TRAP: cause=%0d",dut.trap_taken_cause);
      if (dmem_req === 1'b1)
        $fatal(1,"FAIL_DMEM_UNEXPECTED: addr=%016h",dmem_addr);
      if (exp_valid) begin
        // Mientras una transaccion no termine, sus atributos NO pueden variar.
        if (done_count == 0 || done_count == 1) begin
          if (exp_addr !== EXP_BASE)
            $fatal(1,"FAIL_MMIO_ORDER: etapa=%0d addr=%016h",done_count,exp_addr);
        end else if (done_count == 2) begin
          if (exp_addr !== EXP_BASE + 64'd8)
            $fatal(1,"FAIL_MMIO_ORDER: etapa=%0d addr=%016h",done_count,exp_addr);
        end else begin
          $fatal(1,"FAIL_EXTRA_MMIO: addr=%016h",exp_addr);
        end
        if (exp_we !== (done_count != 1))
          $fatal(1,"FAIL_MMIO_TYPE: etapa=%0d exp_we=%b",done_count,exp_we);
        if (exp_size !== 2'b10)
          $fatal(1,"FAIL_MMIO_SIZE: etapa=%0d size=%b",done_count,exp_size);
        if (done_count != 1) begin
          if (exp_wstrb !== 8'h0f || exp_wdata[31:0] !== 32'h55)
            $fatal(1,"FAIL_MMIO_DATA: etapa=%0d wstrb=%h wdata=%016h",done_count,exp_wstrb,exp_wdata);
        end
        if (exp_ready) begin
          $display("TB_B9H_COMPLETE: idx=%0d we=%0d addr=0x%016h data=0x%08h wait=%0d",
                   done_count,exp_we,exp_addr,exp_wdata[31:0],wait_cycles);
          done_count <= done_count + 1;
          wait_cycles <= 0;
          if (done_count == 2) begin
            if (hold_count < 10)
              $fatal(1,"FAIL_NO_WAIT_STRESS: observed=%0d",hold_count);
            $display("PASS_B9H_MMIO: case=%0d completed=3 hold_cycles=%0d",CASE_NUM,hold_count);
            #1 $finish;
          end
        end else begin
          wait_cycles <= wait_cycles + 1;
          hold_count <= hold_count + 1;
          if (dut.mem_exp_wait_stall !== 1'b1 || dut.pipeline_stall !== 1'b1)
            $fatal(1,"FAIL_STALL: idx=%0d stall=%b pipeline=%b",
                   done_count,dut.mem_exp_wait_stall,dut.pipeline_stall);
        end
      end else begin
        wait_cycles <= 0;
      end
    end
  end
  initial begin
    #200000;
    $fatal(1,"FAIL_TIMEOUT: case=%0d completed=%0d",CASE_NUM,done_count);
  end
endmodule
