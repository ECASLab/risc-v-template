//Este test hace esto:

    //addi x1, x0, 5
    //addi x2, x0, 7
    //add x3, x1, x2
    //sd x3, 0(x0)
    //jal x0, 0 para quedarse en loop

//Al final verifica que x3 = 12 y que en memoria de datos en la dirección 0 se haya escrito 12

//COMPILAR:
    //iverilog -g2012 -Wall \
    //-s tb_core_smoke \
    //-o build/tb_core_smoke.vvp \
    //-c tb/tb_sv/core_smoke.f
//CORRER:
    //vvp build/tb_core_smoke.vvp

`timescale 1ns/1ps

// Test de humo básico para verificar que el core puede ejecutar un programa simple sin errores. El programa hace algunas operaciones aritméticas básicas y una store, y luego se verifica que los resultados sean correctos. Es un buen punto de partida para asegurarse de que el core está funcionando en lo más básico antes de pasar a tests más complejos.

module tb_core_smoke;

    logic clk;
    logic rst;

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // Memorias simples del testbench
    logic [31:0] imem [0:63];
    logic [63:0] dmem [0:63];

    // ------------------------------------------------------------
    // Señales dummy para puerto de expansión.
    // Estos testbenches no usan MMIO, por eso el puerto se deja
    // en estado inactivo/seguro para evitar entradas flotantes.
    // ------------------------------------------------------------
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    integer i;
    integer b;

    // DUT
    core_top #(
        .RESET_PC(64'd0)
    ) dut (
        .clk        (clk),
        .rst        (rst),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_wstrb (dmem_wstrb),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_size  (dmem_size),

        .exp_valid  (),
        .exp_we     (),
        .exp_addr   (),
        .exp_wdata  (),
        .exp_wstrb  (),
        .exp_size   (),
        .exp_ready  (exp_ready),
        .exp_rdata  (exp_rdata),
        .exp_error  (exp_error)
    );

    // Clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Lectura combinacional de memoria de instrucciones
    assign imem_rdata = imem[imem_addr[7:2]];

    // Lectura combinacional de memoria de datos
    // El core asume línea de 64 bits alineada a 8 bytes
    assign dmem_rdata = dmem[dmem_addr[8:3]];

    // Escritura síncrona de memoria de datos con byte enables
    always @(posedge clk) begin
        if (dmem_we) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb[b]) begin
                    dmem[dmem_addr[8:3]][8*b +: 8] <= dmem_wdata[8*b +: 8];
                end
            end
            $display("[%0t] STORE addr=%0d wdata=%0d wstrb=0x%02h size=%0d",
                     $time, dmem_addr, dmem_wdata, dmem_wstrb, dmem_size);
        end
    end

    // Inicialización
    initial begin
        $dumpfile("build/tb_core_smoke.vcd");
        $dumpvars(0, tb_core_smoke);

        // Valores por defecto
        rst = 1'b1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013; // NOP = addi x0,x0,0
            dmem[i] = 64'd0;
        end

        // Programa:
        // 0x00: addi x1, x0, 5
        // 0x04: addi x2, x0, 7
        // 0x08: add  x3, x1, x2
        // 0x0C: sd   x3, 0(x0)
        // 0x10: jal  x0, 0
        imem[0] = 32'h00500093;
        imem[1] = 32'h00700113;
        imem[2] = 32'h002081b3;
        imem[3] = 32'h00303023;
        imem[4] = 32'h0000006f;

        // Reset síncrono por 3 ciclos
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // Esperar suficiente para que el programa pase por el pipeline
        repeat (40) @(posedge clk);

        // Checks finales
        if (dut.u_regfile.regs[1] !== 64'd5) begin
            $fatal(1, "FAIL: x1 != 5, valor=%0d", dut.u_regfile.regs[1]);
        end

        if (dut.u_regfile.regs[2] !== 64'd7) begin
            $fatal(1, "FAIL: x2 != 7, valor=%0d", dut.u_regfile.regs[2]);
        end

        if (dut.u_regfile.regs[3] !== 64'd12) begin
            $fatal(1, "FAIL: x3 != 12, valor=%0d", dut.u_regfile.regs[3]);
        end

        if (dmem[0] !== 64'd12) begin
            $fatal(1, "FAIL: dmem[0] != 12, valor=%0d", dmem[0]);
        end

        $display("PASS: smoke test OK");
        $finish;
    end

endmodule
