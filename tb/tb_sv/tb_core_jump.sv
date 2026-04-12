//Este programa hará esto
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

//Checks esperados:

        //x1 = 4
        //x2 = 0 porque su instrucción fue saltada por jal
        //x5 = 16
        //x6 = 0 porque su instrucción fue saltada por jalr
        //x7 = 77

        //PASS: jal + jalr test OK

//COMPILAR:
        //iverilog -g2012 -s tb_core_jump -o build/tb_core_jump.vvp -c tb/tb_sv/core_jump.f

//CORRER:
        //vvp build/tb_core_jump.vvp

`timescale 1ns/1ps

// Testbench para verificar las instrucciones de salto (jal y jalr) en el core RISC-V.
// Este testbench carga un programa simple en la memoria de instrucciones que utiliza jal y jalr para saltar a diferentes partes del código. Luego verifica que los registros afectados por estas instrucciones tengan los valores esperados.
module tb_core_jump;

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

    integer i;
    integer b;

    core_top #(
        .RESET_PC(64'd0)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .imem_addr (imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_rdata(dmem_rdata),
        .dmem_we   (dmem_we),
        .dmem_wstrb(dmem_wstrb),
        .dmem_addr (dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_size (dmem_size)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[8:3]];

    always_ff @(posedge clk) begin
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
        $dumpfile("build/tb_core_jump.vcd");
        $dumpvars(0, tb_core_jump);

        rst = 1'b1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013; // nop
            dmem[i] = 64'd0;
        end

        imem[0] = 32'h008000ef; // jal  x1, +8
        imem[1] = 32'h06300113; // addi x2, x0, 99
        imem[2] = 32'h02000193; // addi x3, x0, 32
        imem[3] = 32'h000182e7; // jalr x5, 0(x3)
        imem[4] = 32'h03700313; // addi x6, x0, 55
        imem[5] = 32'h00000013; // nop
        imem[6] = 32'h00000013; // nop
        imem[7] = 32'h00000013; // nop
        imem[8] = 32'h04d00393; // addi x7, x0, 77
        imem[9] = 32'h0000006f; // jal  x0, 0

        repeat (3) @(posedge clk);
        rst = 1'b0;

        repeat (60) @(posedge clk);

        if (dut.u_regfile.regs[1] !== 64'd4) begin
            $fatal(1, "FAIL: x1 != 4, valor=%0d", dut.u_regfile.regs[1]);
        end

        if (dut.u_regfile.regs[2] !== 64'd0) begin
            $fatal(1, "FAIL: x2 != 0, jal no salto correctamente, valor=%0d", dut.u_regfile.regs[2]);
        end

        if (dut.u_regfile.regs[3] !== 64'd32) begin
            $fatal(1, "FAIL: x3 != 32, valor=%0d", dut.u_regfile.regs[3]);
        end

        if (dut.u_regfile.regs[5] !== 64'd16) begin
            $fatal(1, "FAIL: x5 != 16, jalr link incorrecto, valor=%0d", dut.u_regfile.regs[5]);
        end

        if (dut.u_regfile.regs[6] !== 64'd0) begin
            $fatal(1, "FAIL: x6 != 0, jalr no salto correctamente, valor=%0d", dut.u_regfile.regs[6]);
        end

        if (dut.u_regfile.regs[7] !== 64'd77) begin
            $fatal(1, "FAIL: x7 != 77, destino final incorrecto, valor=%0d", dut.u_regfile.regs[7]);
        end

        $display("PASS: jal + jalr test OK");
        $finish;
    end

endmodule
