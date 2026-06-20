`timescale 1ns/1ps

module tb_core_system_trap;

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

    // Memoria de instrucciones simple: 256 palabras de 32 bits
    logic [31:0] imem [0:255];

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
    // Instruction memory model
    // =========================================================
    always_comb begin
        if (imem_addr[63:10] != 0)
            imem_rdata = 32'h00000013; // NOP si sale del rango modelado
        else
            imem_rdata = imem[imem_addr[9:2]];
    end

    // =========================================================
    // Data memory model (no se usa en esta prueba)
    // =========================================================
    assign dmem_rdata = 64'd0;

    // =========================================================
    // Programa de prueba
    //
    // Main @ 0x000
    //   0x000: csrrs x5,  misa,    x0   ; leer misa
    //   0x004: lui   x7,  0x1           ; x7 = 0x100
    //   0x008: csrrw x0,  mtvec,   x7   ; mtvec = 0x100
    //   0x00C: addi  x6,  x0,      8    ; x6 = bit MIE
    //   0x010: csrrw x0,  mstatus, x6   ; mstatus = 0x8
    //   0x014: ecall                    ; trap a 0x100
    //   0x018: csrrs x10, mepc,    x0   ; debe leer 0x14
    //   0x01C: csrrs x12, mstatus, x0   ; debe leer 0x1888 en esta implementación
    //   0x020: addi  x11, x0,      1    ; bandera de PASS
    //   0x024: jal   x0,  0             ; loop
    //
    // Handler @ 0x100
    //   0x100: csrrs x20, mcause,  x0   ; debe leer 11
    //   0x104: csrrs x21, mepc,    x0   ; debe leer 0x14
    //   0x108: addi  x22, x0,      11   ; referencia local
    //   0x10C: mret
    // =========================================================
    initial begin
        $dumpfile("tb_core_system_trap.vcd");
        $dumpvars(0, tb_core_system_trap);

        // Inicializar IMEM a NOPs
        for (i = 0; i < 256; i = i + 1)
            imem[i] = 32'h00000013; // addi x0, x0, 0

        // -------------------------
        // Main program
        // -------------------------
        imem[0]  = 32'h301022f3; // csrrs x5,  misa,    x0
        imem[1]  = 32'h10000393; // lui   x7,  0x1
        imem[2]  = 32'h30539073; // csrrw x0,  mtvec,   x7
        imem[3]  = 32'h00800313; // addi  x6,  x0,      8
        imem[4]  = 32'h30031073; // csrrw x0,  mstatus, x6
        imem[5]  = 32'h00000073; // ecall
        imem[6]  = 32'h34102573; // csrrs x10, mepc,    x0
        imem[7]  = 32'h30002673; // csrrs x12, mstatus, x0
        imem[8]  = 32'h00100593; // addi  x11, x0,      1
        imem[9]  = 32'h0000006f; // jal   x0,  0

        // -------------------------
        // Trap handler @ 0x100
        // 0x100 / 4 = 64
        //
        // Lee mcause y mepc, incrementa mepc en 4
        // para saltar la ECALL, y retorna con MRET.
        // -------------------------
        imem[64] = 32'h34202a73; // csrrs x20, mcause,  x0
        imem[65] = 32'h34102af3; // csrrs x21, mepc,    x0
        imem[66] = 32'h004a8a93; // addi  x21, x21,     4
        imem[67] = 32'h341a9073; // csrrw x0,  mepc,    x21
        imem[68] = 32'h00b00b13; // addi  x22, x0,      11
        imem[69] = 32'h30200073; // mret

        // Reset síncrono
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // Esperar ejecución
        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);

            // Esta prueba no debería tocar memoria de datos
            if (dmem_we !== 1'b0) begin
                $display("FAIL: dmem_we se activó inesperadamente en ciclo %0d", cycle);
                $finish;
            end

            // Termina cuando el software pone x11 = 1
            if (dut.u_regfile.regs[11] == 64'd1) begin
                // x5 <- misa
                if (dut.u_regfile.regs[5] !== 64'h8000_0000_0000_0100) begin
                    $display("FAIL: x5 (misa) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[5], 64'h8000_0000_0000_0100);
                    $finish;
                end

                // En el handler: mcause debe ser 11 (ECALL desde M-mode)
                if (dut.u_regfile.regs[20] !== 64'd11) begin
                    $display("FAIL: x20 (mcause) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[20], 64'd11);
                    $finish;
                end

                // En el handler x21 ya fue incrementado en +4, así que queda en 0x18
                if (dut.u_regfile.regs[21] !== 64'h0000_0000_0000_0018) begin
                    $display("FAIL: x21 (mepc ajustado dentro del handler) incorrecto. got=%h exp=%h",
                            dut.u_regfile.regs[21], 64'h0000_0000_0000_0018);
                    $finish;
                end

                // Después de volver: el handler actualizó mepc a 0x18
                if (dut.u_regfile.regs[10] !== 64'h0000_0000_0000_0018) begin
                    $display("FAIL: x10 (mepc después de mret) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[10], 64'h0000_0000_0000_0018);
                    $finish;
                end

                // Después de mret, con tu csr_file actual:
                // MIE=1, MPIE=1, MPP=11 => 0x1888
                if (dut.u_regfile.regs[12] !== 64'h0000_0000_0000_1888) begin
                    $display("FAIL: x12 (mstatus después de mret) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[12], 64'h0000_0000_0000_1888);
                    $finish;
                end

                // Referencia local del handler
                if (dut.u_regfile.regs[22] !== 64'd11) begin
                    $display("FAIL: x22 incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[22], 64'd11);
                    $finish;
                end

                $display("PASS: CSR + ECALL + MRET funcionando correctamente.");
                $display("      x5  (misa)    = %h", dut.u_regfile.regs[5]);
                $display("      x20 (mcause)  = %h", dut.u_regfile.regs[20]);
                $display("      x21 (mepc H)  = %h", dut.u_regfile.regs[21]);
                $display("      x10 (mepc R)  = %h", dut.u_regfile.regs[10]);
                $display("      x12 (mstatus) = %h", dut.u_regfile.regs[12]);
                $finish;
            end
        end

        $display("FAIL: timeout. El programa no alcanzó x11=1.");
        $finish;
    end

endmodule