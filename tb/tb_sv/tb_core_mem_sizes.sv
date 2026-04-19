//La idea aquí es comprobar que tu ruta MEM hace bien estas operaciones:

        //lb / lbu
        //lh / lhu
        //lw / lwu
        //ld
        //sb / sh / sw / sd

//Qué va a probar este test
    //Vamos a precargar una línea de memoria con este valor: 64'h89ABCDEF80FF7F81
    //En little-endian, eso deja estos bytes en direcciones 0..7:
        //addr 0: 0x81
        //addr 1: 0x7F
        //addr 2: 0xFF
        //addr 3: 0x80
        //addr 4: 0xEF
        //addr 5: 0xCD
        //addr 6: 0xAB
        //addr 7: 0x89

    //Entonces esperamos:

        //lb 0(x10) → 0xFFFFFFFFFFFFFF81
        //lbu 0(x10) → 0x0000000000000081
        //lh 2(x10) → 0xFFFFFFFFFFFF80FF
        //lhu 2(x10) → 0x00000000000080FF
        //lw 4(x10) → 0xFFFFFFFF89ABCDEF
        //lwu 4(x10) → 0x0000000089ABCDEF
        //ld 0(x10) → 0x89ABCDEF80FF7F81

    //Luego vamos a hacer stores de -1 (64'hFFFF_FFFF_FFFF_FFFF) para revisar strobes y escritura parcial:

        //sb en addr 8
        //sh en addr 10
        //sw en addr 12
        //sd en addr 16

    //Entonces esperamos que después de los stores:
        //dmem[1] = 64'hFFFFFFFFFFFF00FF (porque sb y sh escriben FF en bytes 8 y 10, pero sw no escribe nada porque su strobe es 0)
        //dmem[2] = 64'hFFFFFFFFFFFFFFFF (porque sd escribe FFFF_FFFF_FFFF_FFFF en bytes 16..23)

//COMPILAR:
        //iverilog -g2012 -s tb_core_mem_sizes -o build/tb_core_mem_sizes.vvp -c tb/tb_sv/core_mem_sizes.f

//CORRER:
        //vvp build/tb_core_mem_sizes.vvp

`timescale 1ns/1ps

module tb_core_mem_sizes;

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
            $display("[%0t] STORE addr=%0d wdata=0x%016h wstrb=0x%02h size=%0d",
                     $time, dmem_addr, dmem_wdata, dmem_wstrb, dmem_size);
        end
    end

    initial begin
        $dumpfile("build/tb_core_mem_sizes.vcd");
        $dumpvars(0, tb_core_mem_sizes);

        rst = 1'b1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013; // nop
            dmem[i] = 64'd0;
        end

        // Precarga para pruebas de load
        // Bytes en addr 0..7 = 81 7F FF 80 EF CD AB 89
        dmem[0] = 64'h89ABCDEF80FF7F81;

        // Programa:
        // x10 = base 0
        // loads desde dmem[0]
        // x11 = -1
        // stores hacia dmem[1] y dmem[2]
        // loop final

        imem[0]  = 32'h00000513; // addi x10, x0, 0

        imem[1]  = 32'h00050083; // lb   x1, 0(x10)
        imem[2]  = 32'h00054103; // lbu  x2, 0(x10)
        imem[3]  = 32'h00251183; // lh   x3, 2(x10)
        imem[4]  = 32'h00255203; // lhu  x4, 2(x10)
        imem[5]  = 32'h00452283; // lw   x5, 4(x10)
        imem[6]  = 32'h00456303; // lwu  x6, 4(x10)
        imem[7]  = 32'h00053383; // ld   x7, 0(x10)

        imem[8]  = 32'hfff00593; // addi x11, x0, -1

        imem[9]  = 32'h00b00423; // sb   x11, 8(x0)
        imem[10] = 32'h00b01523; // sh   x11, 10(x0)
        imem[11] = 32'h00b02623; // sw   x11, 12(x0)
        imem[12] = 32'h00b03823; // sd   x11, 16(x0)

        imem[13] = 32'h0000006f; // jal  x0, 0

        repeat (3) @(posedge clk);
        rst = 1'b0;

        repeat (80) @(posedge clk);

        // Checks de loads
        if (dut.u_regfile.regs[1] !== 64'hFFFFFFFFFFFFFF81) begin
            $fatal(1, "FAIL: lb incorrecto, x1=0x%016h", dut.u_regfile.regs[1]);
        end

        if (dut.u_regfile.regs[2] !== 64'h0000000000000081) begin
            $fatal(1, "FAIL: lbu incorrecto, x2=0x%016h", dut.u_regfile.regs[2]);
        end

        if (dut.u_regfile.regs[3] !== 64'hFFFFFFFFFFFF80FF) begin
            $fatal(1, "FAIL: lh incorrecto, x3=0x%016h", dut.u_regfile.regs[3]);
        end

        if (dut.u_regfile.regs[4] !== 64'h00000000000080FF) begin
            $fatal(1, "FAIL: lhu incorrecto, x4=0x%016h", dut.u_regfile.regs[4]);
        end

        if (dut.u_regfile.regs[5] !== 64'hFFFFFFFF89ABCDEF) begin
            $fatal(1, "FAIL: lw incorrecto, x5=0x%016h", dut.u_regfile.regs[5]);
        end

        if (dut.u_regfile.regs[6] !== 64'h0000000089ABCDEF) begin
            $fatal(1, "FAIL: lwu incorrecto, x6=0x%016h", dut.u_regfile.regs[6]);
        end

        if (dut.u_regfile.regs[7] !== 64'h89ABCDEF80FF7F81) begin
            $fatal(1, "FAIL: ld incorrecto, x7=0x%016h", dut.u_regfile.regs[7]);
        end

        // Checks de stores
        if (dmem[1] !== 64'hFFFFFFFFFFFF00FF) begin
            $fatal(1, "FAIL: stores parciales incorrectos, dmem[1]=0x%016h", dmem[1]);
        end

        if (dmem[2] !== 64'hFFFFFFFFFFFFFFFF) begin
            $fatal(1, "FAIL: sd incorrecto, dmem[2]=0x%016h", dmem[2]);
        end

        // Verificación adicional: la línea original de load no se corrompió
        if (dmem[0] !== 64'h89ABCDEF80FF7F81) begin
            $fatal(1, "FAIL: dmem[0] cambio inesperadamente, dmem[0]=0x%016h", dmem[0]);
        end

        $display("PASS: load/store sizes test OK");
        $finish;
    end

endmodule
