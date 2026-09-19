// Este programa hará esto:
//
// 0x00: jal  x1, +8        ; x1 = 0x04, salta a 0x08
// 0x04: addi x2, x0, 99    ; debe ser saltada
// 0x08: addi x3, x0, 32    ; x3 = 0x20
// 0x0C: jalr x5, 0(x3)     ; x5 = 0x10, salta a 0x20
// 0x10: addi x6, x0, 55    ; debe ser saltada
// 0x14: nop
// 0x18: nop
// 0x1C: nop
// 0x20: addi x7, x0, 77    ; destino final
// 0x24: jal  x0, 0         ; loop
//
// Checks esperados:
//
// x1 = 4
// x2 = 0 porque su instrucción fue saltada por JAL
// x3 = 32
// x5 = 16
// x6 = 0 porque su instrucción fue saltada por JALR
// x7 = 77
//
// PASS: jal + jalr test OK

`timescale 1ns/1ps

module tb_core_jump;

    localparam int unsigned IMEM_WORDS = 64;

    logic clk;
    logic rst;

    // =========================================================
    // IMEM síncrona
    // =========================================================

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    // =========================================================
    // DMEM
    //
    // Este test no ejecuta accesos de datos. Se conserva el
    // adaptador legacy para no mezclar esta migración IMEM con
    // cambios innecesarios en DMEM.
    // =========================================================

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;

    logic [63:0] dmem [0:63];

    // =========================================================
    // Expansión
    // =========================================================

    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    integer i;
    integer b;

    // =========================================================
    // Adaptador legacy DMEM
    //
    // Se conserva deliberadamente: este test verifica JAL/JALR,
    // no latencia de memoria de datos.
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
    // Core
    // =========================================================

    core_top #(
        .RESET_PC(64'd0)
    ) dut (
        .clk         (clk),
        .rst         (rst),

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

        .dmem_we     (dmem_we),
        .dmem_wstrb  (dmem_wstrb),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_size   (dmem_size),

        .exp_valid   (),
        .exp_we      (),
        .exp_addr    (),
        .exp_wdata   (),
        .exp_wstrb   (),
        .exp_size    (),

        .exp_ready   (exp_ready),
        .exp_rdata   (exp_rdata),
        .exp_error   (exp_error)
    );

    // =========================================================
    // IMEM síncrona real
    //
    // Configuración rápida:
    //
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    //
    // El modelo y el controlador ya soportan turnover:
    //
    //   response actual + siguiente request
    //
    // Esto permite un fetch por ciclo después del llenado
    // inicial y fuerza a JAL/JALR a convivir con actividad IMEM
    // del camino secuencial.
    // =========================================================

    imem_sync_model #(
        .MEM_WORDS (IMEM_WORDS),
        .GNT_DELAY (0),
        .RESP_DELAY(1)
    ) u_imem (
        .clk      (clk),
        .rst      (rst),

        .req_i    (imem_req),
        .gnt_o    (imem_gnt),

        .addr_i   (imem_addr),

        .rvalid_o (imem_rvalid),
        .rdata_o  (imem_rdata)
    );

    // =========================================================
    // Clock
    // =========================================================

    initial begin
        clk = 1'b0;
    end

    always #5 clk = ~clk;

    // =========================================================
    // DMEM combinacional legacy
    // =========================================================

    assign dmem_rdata = dmem[dmem_addr[8:3]];

    always @(posedge clk) begin
        if (dmem_we) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb[b]) begin
                    dmem[dmem_addr[8:3]][8*b +: 8]
                        <= dmem_wdata[8*b +: 8];
                end
            end

            $display(
                "[%0t] STORE addr=%0d wdata=%0d wstrb=0x%02h size=%0d",
                $time,
                dmem_addr,
                dmem_wdata,
                dmem_wstrb,
                dmem_size
            );
        end
    end

    // =========================================================
    // Test
    // =========================================================

    initial begin
        $dumpfile("build/tb_core_jump.vcd");
        $dumpvars(0, tb_core_jump);

        rst = 1'b1;

        // -----------------------------------------------------
        // Inicialización
        // -----------------------------------------------------

        for (i = 0; i < IMEM_WORDS; i = i + 1) begin
            u_imem.mem[i] = 32'h0000_0013; // NOP
            dmem[i]       = 64'd0;
        end

        // -----------------------------------------------------
        // Programa
        // -----------------------------------------------------

        u_imem.mem[0] = 32'h0080_00ef; // jal  x1, +8
        u_imem.mem[1] = 32'h0630_0113; // addi x2, x0, 99
        u_imem.mem[2] = 32'h0200_0193; // addi x3, x0, 32
        u_imem.mem[3] = 32'h0001_82e7; // jalr x5, 0(x3)

        u_imem.mem[4] = 32'h0370_0313; // addi x6, x0, 55
        u_imem.mem[5] = 32'h0000_0013; // nop
        u_imem.mem[6] = 32'h0000_0013; // nop
        u_imem.mem[7] = 32'h0000_0013; // nop

        u_imem.mem[8] = 32'h04d0_0393; // addi x7, x0, 77
        u_imem.mem[9] = 32'h0000_006f; // jal x0, 0

        // -----------------------------------------------------
        // Reset
        //
        // Se retira fuera del posedge para evitar carreras entre
        // DUT y modelos síncronos del testbench.
        // -----------------------------------------------------

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;
        #1;

        // Suficiente tiempo para ejecutar ambos redirects y
        // alcanzar el loop final.
        repeat (60) @(posedge clk);

        // =====================================================
        // Checks arquitecturales históricos
        // =====================================================

        if (dut.u_regfile.regs[1] !== 64'd4) begin
            $fatal(
                1,
                "FAIL: x1 != 4, valor=%0d",
                dut.u_regfile.regs[1]
            );
        end

        if (dut.u_regfile.regs[2] !== 64'd0) begin
            $fatal(
                1,
                "FAIL: x2 != 0, JAL no salto correctamente, valor=%0d",
                dut.u_regfile.regs[2]
            );
        end

        if (dut.u_regfile.regs[3] !== 64'd32) begin
            $fatal(
                1,
                "FAIL: x3 != 32, valor=%0d",
                dut.u_regfile.regs[3]
            );
        end

        if (dut.u_regfile.regs[5] !== 64'd16) begin
            $fatal(
                1,
                "FAIL: x5 != 16, JALR link incorrecto, valor=%0d",
                dut.u_regfile.regs[5]
            );
        end

        if (dut.u_regfile.regs[6] !== 64'd0) begin
            $fatal(
                1,
                "FAIL: x6 != 0, JALR no salto correctamente, valor=%0d",
                dut.u_regfile.regs[6]
            );
        end

        if (dut.u_regfile.regs[7] !== 64'd77) begin
            $fatal(
                1,
                "FAIL: x7 != 77, destino final incorrecto, valor=%0d",
                dut.u_regfile.regs[7]
            );
        end

        // Este programa no debe generar ningún acceso DMEM.
        if (dmem_req !== 1'b0) begin
            $fatal(
                1,
                "FAIL: dmem_req activo inesperadamente al final del test"
            );
        end

        $display("==============================================");
        $display("PASS: JAL + JALR con IMEM síncrona");
        $display("      x1 = %0d", dut.u_regfile.regs[1]);
        $display("      x2 = %0d", dut.u_regfile.regs[2]);
        $display("      x3 = %0d", dut.u_regfile.regs[3]);
        $display("      x5 = %0d", dut.u_regfile.regs[5]);
        $display("      x6 = %0d", dut.u_regfile.regs[6]);
        $display("      x7 = %0d", dut.u_regfile.regs[7]);
        $display("      JAL wrong-path x2=99 descartado");
        $display("      JALR wrong-path x6=55 descartado");
        $display("==============================================");

        $finish;
    end

endmodule
