//COMPILAR: rm -f build/tb_core_jalr_misaligned_trap.out
//iverilog -g2012 -o build/tb_core_jalr_misaligned_trap.out -c tb/tb_sv/core_jalr_misaligned_trap.f && \
//vvp build/tb_core_jalr_misaligned_trap.out

`timescale 1ns/1ps

module tb_core_jalr_misaligned_trap;

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

    integer i;
    integer cycle;

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
        .dmem_size  (dmem_size)
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
    // DMEM no usada
    // =========================================================
    assign dmem_rdata = 64'd0;

    // =========================================================
    // Programa de prueba
    //
    // 0x000: addi  x7,  x0, 256        ; x7 = 0x100
    // 0x004: csrrw x0,  mtvec, x7      ; mtvec = 0x100
    // 0x008: addi  x6,  x0, 103        ; x6 = 0x67
    // 0x00C: jalr  x0,  0(x6)          ; target bruto = 0x67, target efectivo = 0x66
    //                                  ; bit0 se limpia, pero 0x66 sigue no alineado a 4
    //                                  ; => instruction-address-misaligned
    // 0x010: csrrs x10, mepc,  x0      ; después del retorno debe ser 0x10
    // 0x014: addi  x11, x0, 1          ; PASS flag
    // 0x018: jal   x0,  0
    //
    // Handler @ 0x100
    // 0x100: csrrs x20, mcause, x0     ; debe leer 0
    // 0x104: csrrs x21, mepc,   x0     ; debe leer 0x0C
    // 0x108: addi  x21, x21,    4      ; mepc = 0x10
    // 0x10C: csrrw x0,  mepc,   x21
    // 0x110: mret
    // =========================================================
    initial begin
        $dumpfile("tb_core_jalr_misaligned_trap.vcd");
        $dumpvars(0, tb_core_jalr_misaligned_trap);

        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'h00000013;

        // -------------------------
        // Main
        // -------------------------
        imem[0] = 32'h10000393; // addi  x7,  x0, 256
        imem[1] = 32'h30539073; // csrrw x0,  mtvec, x7
        imem[2] = 32'h06700313; // addi  x6,  x0, 103
        imem[3] = 32'h00030067; // jalr  x0,  0(x6)
        imem[4] = 32'h34102573; // csrrs x10, mepc,  x0
        imem[5] = 32'h00100593; // addi  x11, x0, 1
        imem[6] = 32'h0000006f; // jal   x0, 0

        // -------------------------
        // Trap handler @ 0x100
        // 0x100 / 4 = 64
        // -------------------------
        imem[64] = 32'h34202a73; // csrrs x20, mcause, x0
        imem[65] = 32'h34102af3; // csrrs x21, mepc,   x0
        imem[66] = 32'h004a8a93; // addi  x21, x21,    4
        imem[67] = 32'h341a9073; // csrrw x0,  mepc,   x21
        imem[68] = 32'h30200073; // mret

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);

            if (dmem_we !== 1'b0) begin
                $display("FAIL: dmem_we se activó inesperadamente en ciclo %0d", cycle);
                $finish;
            end

            if (dut.u_regfile.regs[11] == 64'd1) begin
                // mcause = 0 -> instruction address misaligned
                if (dut.u_regfile.regs[20] !== 64'd0) begin
                    $display("FAIL: x20 (mcause) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[20], 64'd0);
                    $finish;
                end

                // x21 fue ajustado en el handler a 0x10
                if (dut.u_regfile.regs[21] !== 64'h0000_0000_0000_0010) begin
                    $display("FAIL: x21 (mepc ajustado en handler) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[21], 64'h0000_0000_0000_0010);
                    $finish;
                end

                // después del retorno, mepc visible = 0x10
                if (dut.u_regfile.regs[10] !== 64'h0000_0000_0000_0010) begin
                    $display("FAIL: x10 (mepc después de mret) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[10], 64'h0000_0000_0000_0010);
                    $finish;
                end

                $display("PASS: JALR misaligned + trap a mtvec funcionando correctamente.");
                $display("      x20 (mcause) = %h", dut.u_regfile.regs[20]);
                $display("      x21 (mepc H) = %h", dut.u_regfile.regs[21]);
                $display("      x10 (mepc R) = %h", dut.u_regfile.regs[10]);
                $finish;
            end
        end

        $display("FAIL: timeout. El programa no alcanzó x11=1.");
        $finish;
    end

endmodule
