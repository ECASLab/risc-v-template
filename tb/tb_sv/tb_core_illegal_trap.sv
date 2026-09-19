//COMPILAR: 
//rm -f build/tb_core_illegal_trap.out
//iverilog -g2012 -o build/tb_core_illegal_trap.out -c tb/tb_sv/core_illegal_trap.f && \
//vvp build/tb_core_illegal_trap.out

`timescale 1ns/1ps

module tb_core_illegal_trap;

    logic        clk;
    logic        rst;

    // =========================================================
    // IMEM síncrona
    // =========================================================

    localparam int unsigned IMEM_WORDS = 256;

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // Handshake de memoria de datos.
    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;


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
    // =========================================================
    // Adaptador temporal para los modelos combinacionales
    // de memoria usados por este testbench.
    //
    // El core utiliza el handshake definitivo, mientras este
    // adaptador proporciona grant inmediato y rvalid +1 ciclo.
    // =========================================================
        dmem_legacy_compat u_dmem_legacy_compat (
            .clk      (clk),
            .rst      (rst),
            .req_i    (dmem_req),
            .gnt_o    (dmem_gnt),
            .rvalid_o (dmem_rvalid),
            .error_o  (dmem_error)
        );

        core_top #(
            .RESET_PC    (64'd0),
            .TRAP_VECTOR (64'h0000_0000_0000_0100)
        ) dut (
            .clk        (clk),
            .rst        (rst),

            .imem_req    (imem_req),
            .imem_addr   (imem_addr),
            .imem_gnt    (imem_gnt),
            .imem_rvalid (imem_rvalid),
            .imem_rdata  (imem_rdata),

            .dmem_rdata (dmem_rdata),

            .dmem_req    (dmem_req),
            .dmem_gnt    (dmem_gnt),
            .dmem_rvalid (dmem_rvalid),
            .dmem_error  (dmem_error),
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
    // IMEM síncrona real
    //
    // Configuración rápida ya validada en los TB migrados.
    // Permite turnover y mantiene un fetch/ciclo después
    // del llenado inicial.
    // =========================================================

        imem_sync_model #(
            .MEM_WORDS  (IMEM_WORDS),
            .GNT_DELAY  (0),
            .RESP_DELAY (1)
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
    // DMEM no usada
    // =========================================================
        assign dmem_rdata = 64'd0;

    // =========================================================
    // Programa de prueba
    //
    // 0x000: addi  x7,  x0, 256        ; x7 = 0x100
    // 0x004: csrrw x0,  mtvec, x7      ; mtvec = 0x100
    // 0x008: csrrs x5,  misa,  x0      ; lectura válida de CSR
    // 0x00C: csrrs x13, 0x7B0, x0      ; CSR no implementado -> illegal instruction
    // 0x010: csrrs x10, mepc,  x0      ; después del retorno debe ser 0x10
    // 0x014: addi  x11, x0, 1          ; PASS flag
    // 0x018: jal   x0,  0
    //
    // Handler @ 0x100
    // 0x100: csrrs x20, mcause, x0     ; debe leer 2
    // 0x104: csrrs x21, mepc,   x0     ; debe leer 0x0C
    // 0x108: addi  x21, x21, 4         ; mepc = 0x10
    // 0x10C: csrrw x0,  mepc,   x21
    // 0x110: mret
    // =========================================================
    initial begin
        $dumpfile("tb_core_illegal_trap.vcd");
        $dumpvars(0, tb_core_illegal_trap);

        for (i = 0; i < 256; i = i + 1)
            u_imem.mem[i] = 32'h00000013;

        // -------------------------
        // Main
        // -------------------------
        u_imem.mem[0] = 32'h10000393; // addi  x7,  x0, 256
        u_imem.mem[1] = 32'h30539073; // csrrw x0,  mtvec, x7
        u_imem.mem[2] = 32'h301022f3; // csrrs x5,  misa,  x0
        u_imem.mem[3] = 32'h7b0026f3; // csrrs x13, 0x7B0, x0   -> illegal CSR access
        u_imem.mem[4] = 32'h34102573; // csrrs x10, mepc,  x0
        u_imem.mem[5] = 32'h00100593; // addi  x11, x0, 1
        u_imem.mem[6] = 32'h0000006f; // jal   x0, 0

        // -------------------------
        // Trap handler @ 0x100
        // 0x100 / 4 = 64
        // -------------------------
        u_imem.mem[64] = 32'h34202a73; // csrrs x20, mcause, x0
        u_imem.mem[65] = 32'h34102af3; // csrrs x21, mepc,   x0
        u_imem.mem[66] = 32'h004a8a93; // addi  x21, x21,    4
        u_imem.mem[67] = 32'h341a9073; // csrrw x0,  mepc,   x21
        u_imem.mem[68] = 32'h30200073; // mret

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
                // misa leído correctamente
                if (dut.u_regfile.regs[5] !== 64'h8000_0000_0000_0100) begin
                    $display("FAIL: x5 (misa) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[5], 64'h8000_0000_0000_0100);
                    $finish;
                end

                // mcause = 2 -> illegal instruction
                if (dut.u_regfile.regs[20] !== 64'd2) begin
                    $display("FAIL: x20 (mcause) incorrecto. got=%h exp=%h",
                             dut.u_regfile.regs[20], 64'd2);
                    $finish;
                end

                // mepc leído en handler antes del ajuste = 0x0C
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

                $display("PASS: illegal instruction + trap a mtvec funcionando correctamente.");
                $display("      x5  (misa)   = %h", dut.u_regfile.regs[5]);
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
