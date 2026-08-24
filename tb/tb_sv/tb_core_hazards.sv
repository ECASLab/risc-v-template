//COMPILAR: rm -f build/tb_core_hazards.out
//iverilog -g2012 -o build/tb_core_hazards.out -c tb/tb_sv/core_hazards.f && \
//vvp build/tb_core_hazards.out

`timescale 1ns/1ps

module tb_core_hazards;

    logic        clk;
    logic        rst;

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    logic [31:0] imem [0:255];
    logic [63:0] dmem_line0;

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
    integer cycle;
    integer b;
    integer hazard_count;
    integer store_count;

    // =========================================================
    // DUT
    // =========================================================
    core_top #(
        .RESET_PC    (64'd0),
        .TRAP_VECTOR (64'h0000_0000_0000_0100)
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

    // =========================================================
    // Clock
    // =========================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =========================================================
    // IMEM simple
    // =========================================================
    always_comb begin
        if (imem_addr[63:10] != 0)
            imem_rdata = 32'h00000013; // NOP fuera de rango
        else
            imem_rdata = imem[imem_addr[9:2]];
    end

    // =========================================================
    // DMEM simple: una sola línea alineada de 64 bits en addr 0x0
    // La convención de tu core es que dmem_rdata entrega la línea
    // alineada de 64 bits y el core hace el shift/extensión interna.
    // =========================================================
    assign dmem_rdata = (dmem_addr[63:3] == 0) ? dmem_line0 : 64'd0;

    always @(posedge clk) begin
        if (rst) begin
            dmem_line0 <= 64'd0;
        end
        else if (dmem_we) begin
            if (dmem_addr[63:3] != 0) begin
                $display("FAIL: store fuera del rango modelado. dmem_addr=%h", dmem_addr);
                $finish;
            end

            for (b = 0; b < 8; b = b + 1) begin
                if (dmem_wstrb[b])
                    dmem_line0[b*8 +: 8] <= dmem_wdata[b*8 +: 8];
            end
        end
    end

    // =========================================================
    // Programa de prueba
    //
    // 0x000: addi x1,  x0, 5
    // 0x004: addi x2,  x0, 7
    // 0x008: add  x3,  x1, x2      ; x3 = 12
    // 0x00C: add  x4,  x3, x1      ; forwarding MEM->EX, x4 = 17
    // 0x010: add  x5,  x4, x3      ; forwarding combinado, x5 = 29
    // 0x014: sd   x5,  0(x0)       ; mem[0] = 29
    // 0x018: ld   x6,  0(x0)       ; x6 = 29
    // 0x01C: addi x7,  x6, 1       ; load-use stall, x7 = 30
    // 0x020: add  x8,  x7, x6      ; x8 = 59
    // 0x024: ld   x9,  0(x0)       ; x9 = 29
    // 0x028: add  x10, x8, x9      ; load-use stall, x10 = 88
    // 0x02C: addi x11, x0, 1       ; PASS flag
    // 0x030: jal  x0,  0
    // =========================================================
    initial begin
        $dumpfile("tb_core_hazards.vcd");
        $dumpvars(0, tb_core_hazards);

        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'h00000013;

        dmem_line0   = 64'd0;
        hazard_count = 0;
        store_count  = 0;

        // Main program
        imem[0]  = 32'h00500093; // addi x1,  x0, 5
        imem[1]  = 32'h00700113; // addi x2,  x0, 7
        imem[2]  = 32'h002081b3; // add  x3,  x1, x2
        imem[3]  = 32'h00118233; // add  x4,  x3, x1
        imem[4]  = 32'h003202b3; // add  x5,  x4, x3
        imem[5]  = 32'h00503023; // sd   x5,  0(x0)
        imem[6]  = 32'h00003303; // ld   x6,  0(x0)
        imem[7]  = 32'h00130393; // addi x7,  x6, 1
        imem[8]  = 32'h00638433; // add  x8,  x7, x6
        imem[9]  = 32'h00003483; // ld   x9,  0(x0)
        imem[10] = 32'h00940533; // add  x10, x8, x9
        imem[11] = 32'h00100593; // addi x11, x0, 1
        imem[12] = 32'h0000006f; // jal  x0,  0

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 160; cycle = cycle + 1) begin
            @(posedge clk);

            if (dut.load_use_hazard)
                hazard_count = hazard_count + 1;

            if (dmem_we)
                store_count = store_count + 1;

            if (dut.u_regfile.regs[11] == 64'd1) begin
                if (dut.u_regfile.regs[3] !== 64'd12) begin
                    $display("FAIL: x3 incorrecto. got=%h exp=%h", dut.u_regfile.regs[3], 64'd12);
                    $finish;
                end

                if (dut.u_regfile.regs[4] !== 64'd17) begin
                    $display("FAIL: x4 incorrecto. got=%h exp=%h", dut.u_regfile.regs[4], 64'd17);
                    $finish;
                end

                if (dut.u_regfile.regs[5] !== 64'd29) begin
                    $display("FAIL: x5 incorrecto. got=%h exp=%h", dut.u_regfile.regs[5], 64'd29);
                    $finish;
                end

                if (dmem_line0 !== 64'd29) begin
                    $display("FAIL: dmem_line0 incorrecto. got=%h exp=%h", dmem_line0, 64'd29);
                    $finish;
                end

                if (dut.u_regfile.regs[6] !== 64'd29) begin
                    $display("FAIL: x6 incorrecto. got=%h exp=%h", dut.u_regfile.regs[6], 64'd29);
                    $finish;
                end

                if (dut.u_regfile.regs[7] !== 64'd30) begin
                    $display("FAIL: x7 incorrecto. got=%h exp=%h", dut.u_regfile.regs[7], 64'd30);
                    $finish;
                end

                if (dut.u_regfile.regs[8] !== 64'd59) begin
                    $display("FAIL: x8 incorrecto. got=%h exp=%h", dut.u_regfile.regs[8], 64'd59);
                    $finish;
                end

                if (dut.u_regfile.regs[9] !== 64'd29) begin
                    $display("FAIL: x9 incorrecto. got=%h exp=%h", dut.u_regfile.regs[9], 64'd29);
                    $finish;
                end

                if (dut.u_regfile.regs[10] !== 64'd88) begin
                    $display("FAIL: x10 incorrecto. got=%h exp=%h", dut.u_regfile.regs[10], 64'd88);
                    $finish;
                end

                if (store_count !== 1) begin
                    $display("FAIL: store_count incorrecto. got=%0d exp=%0d", store_count, 1);
                    $finish;
                end

                if (hazard_count !== 2) begin
                    $display("FAIL: hazard_count incorrecto. got=%0d exp=%0d", hazard_count, 2);
                    $finish;
                end

                $display("PASS: forwarding + load-use stall funcionando correctamente.");
                $display("      x3  = %0d", dut.u_regfile.regs[3]);
                $display("      x4  = %0d", dut.u_regfile.regs[4]);
                $display("      x5  = %0d", dut.u_regfile.regs[5]);
                $display("      x6  = %0d", dut.u_regfile.regs[6]);
                $display("      x7  = %0d", dut.u_regfile.regs[7]);
                $display("      x8  = %0d", dut.u_regfile.regs[8]);
                $display("      x9  = %0d", dut.u_regfile.regs[9]);
                $display("      x10 = %0d", dut.u_regfile.regs[10]);
                $display("      mem[0] = %0d", dmem_line0);
                $display("      hazard_count = %0d", hazard_count);
                $finish;
            end
        end

        $display("FAIL: timeout. El programa no alcanzó x11=1.");
        $finish;
    end

endmodule
