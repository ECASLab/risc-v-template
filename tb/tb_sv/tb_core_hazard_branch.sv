//Este programa hace:

    //addi x4, x0, 9
    //sd x4, 0(x0) → memoria[0] = 9
    //ld x1, 0(x0) → x1 = 9
    //add x2, x1, x1 → debe dar 18 aunque depende inmediatamente del ld
    //addi x6, x0, 18
    //beq x2, x6, +8 → branch tomado
    //addi x3, x0, 99 → debe ser flush
    //addi x3, x0, 42 → debe ejecutarse
    //jal x0, 0

//Al final verifica que x2 = 18, que x3 = 42 y que en memoria de datos en la dirección 0 se haya escrito 9

//COMPILAR:
    //iverilog -g2012 -Wall \
    //-s tb_core_hazard_branch \
    //-o build/tb_core_hazard_branch.vvp \
    //-c tb/tb_sv/core_hazard_branch.f

//CORRER:
    //vvp build/tb_core_hazard_branch.vvp


`timescale 1ns/1ps

// Test de hazard de datos + branch flush. Verifica que el core maneja correctamente un caso donde una instrucción depende del resultado de una load previa, y que si hay un branch tomado, las instrucciones que estaban en el pipeline detrás del branch se flushean correctamente.
// El programa hace un store de un valor, luego un load de ese mismo valor, luego una operación que depende del load, luego un branch que depende de esa operación, y luego dos instrucciones que están en el delay slot del branch (una que debería ser flush y otra que no).
// Al final se verifica que el valor cargado es correcto, que la operación que depende del load se ejecutó correctamente, y que el flush del branch funcionó correctamente.

module tb_core_hazard_branch;

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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[8:3]];

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

    initial begin
        $dumpfile("build/tb_core_hazard_branch.vcd");
        $dumpvars(0, tb_core_hazard_branch);

        rst = 1'b1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013; // nop
            dmem[i] = 64'd0;
        end

        // Programa:
        // 0x00: addi x4, x0, 9
        // 0x04: sd   x4, 0(x0)
        // 0x08: ld   x1, 0(x0)
        // 0x0C: add  x2, x1, x1
        // 0x10: addi x6, x0, 18
        // 0x14: beq  x2, x6, +8
        // 0x18: addi x3, x0, 99   ; debe ser flush
        // 0x1C: addi x3, x0, 42   ; debe ejecutarse
        // 0x20: jal  x0, 0

        imem[0] = 32'h00900213; // addi x4, x0, 9
        imem[1] = 32'h00403023; // sd   x4, 0(x0)
        imem[2] = 32'h00003083; // ld   x1, 0(x0)
        imem[3] = 32'h00108133; // add  x2, x1, x1
        imem[4] = 32'h01200313; // addi x6, x0, 18
        imem[5] = 32'h00610463; // beq  x2, x6, +8
        imem[6] = 32'h06300193; // addi x3, x0, 99
        imem[7] = 32'h02a00193; // addi x3, x0, 42
        imem[8] = 32'h0000006f; // jal  x0, 0

        repeat (3) @(posedge clk);
        rst = 1'b0;

        repeat (60) @(posedge clk);

        // Checks finales
        if (dmem[0] !== 64'd9) begin
            $fatal(1, "FAIL: dmem[0] != 9, valor=%0d", dmem[0]);
        end

        if (dut.u_regfile.regs[1] !== 64'd9) begin
            $fatal(1, "FAIL: x1 != 9, valor=%0d", dut.u_regfile.regs[1]);
        end

        if (dut.u_regfile.regs[2] !== 64'd18) begin
            $fatal(1, "FAIL: x2 != 18, valor=%0d", dut.u_regfile.regs[2]);
        end

        if (dut.u_regfile.regs[6] !== 64'd18) begin
            $fatal(1, "FAIL: x6 != 18, valor=%0d", dut.u_regfile.regs[6]);
        end

        if (dut.u_regfile.regs[3] !== 64'd42) begin
            $fatal(1, "FAIL: x3 != 42, branch flush incorrecto, valor=%0d", dut.u_regfile.regs[3]);
        end

        $display("PASS: hazard + branch flush test OK");
        $finish;
    end

endmodule
