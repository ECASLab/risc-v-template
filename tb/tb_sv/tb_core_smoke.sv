// Este test hace:
//
//   addi x1, x0, 5
//   addi x2, x0, 7
//   add  x3, x1, x2
//   sd   x3, 0(x0)
//   jal  x0, 0
//
// Al final verifica:
//   x1 = 5
//   x2 = 7
//   x3 = 12
//   memoria[0] = 12
//
// A diferencia de la versión legacy, la DMEM utiliza ahora
// el protocolo request / grant / response definitivo del core.

`timescale 1ns/1ps

module tb_core_smoke;

    // =========================================================
    // Configuración
    // =========================================================

    localparam int unsigned IMEM_WORDS = 64;
    localparam int unsigned DMEM_WORDS = 64;

    // =========================================================
    // Clock / reset
    // =========================================================

    logic clk;
    logic rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // IMEM síncrona
    // =========================================================

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    // =========================================================
    // Interfaz DMEM
    // =========================================================

    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;

    logic [63:0] dmem_rdata;

    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // =========================================================
    // Puerto de expansión no utilizado
    // =========================================================

    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    // =========================================================
    // Core
    //
    // Ya NO existe dmem_legacy_compat en este test.
    // =========================================================

        core_top #(
            .RESET_PC(64'd0)
        ) dut (
            .clk        (clk),
            .rst        (rst),

            .imem_req    (imem_req),
            .imem_addr   (imem_addr),
            .imem_gnt    (imem_gnt),
            .imem_rvalid (imem_rvalid),
            .imem_rdata  (imem_rdata),

            .dmem_req    (dmem_req),
            .dmem_gnt    (dmem_gnt),
            .dmem_rvalid (dmem_rvalid),
            .dmem_error  (dmem_error),

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
    // IMEM síncrona
    //
    // Configuración rápida:
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    //
    // El controlador y el modelo soportan turnover.
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
    // DMEM síncrona
    //
    // Smoke mínimo:
    //
    //   GNT_DELAY  = 0
    //       grant inmediato cuando la memoria está libre.
    //
    //   RESP_DELAY = 1
    //       la operación finaliza mediante rvalid en un ciclo
    //       posterior a la aceptación.
    //
    // Esto mantiene el smoke rápido y, al mismo tiempo, elimina
    // completamente la dependencia del adaptador legacy.
    // =========================================================

        dmem_sync_model #(
            .MEM_WORDS   (DMEM_WORDS),
            .GNT_DELAY   (0),
            .RESP_DELAY  (1),
            .FAULT_ENABLE(1'b0)
        ) u_dmem (
            .clk      (clk),
            .rst      (rst),

            .req_i    (dmem_req),
            .gnt_o    (dmem_gnt),

            .addr_i   (dmem_addr),
            .we_i     (dmem_we),
            .wdata_i  (dmem_wdata),
            .wstrb_i  (dmem_wstrb),
            .size_i   (dmem_size),

            .rvalid_o (dmem_rvalid),
            .rdata_o  (dmem_rdata),
            .error_o  (dmem_error)
        );

    // =========================================================
    // Monitor mínimo del protocolo
    //
    // El programa contiene exactamente una transacción DMEM:
    //
    //   SD x3, 0(x0)
    //
    // Por ello esperamos:
    //
    //   1 petición aceptada
    //   1 respuesta
    //
    // Además comprobamos los atributos en el único instante
    // arquitectónicamente válido de aceptación:
    //
    //   dmem_req && dmem_gnt
    // =========================================================

        integer accepted_count;
        integer response_count;

        always @(posedge clk) begin
            if (rst) begin
                accepted_count <= 0;
                response_count <= 0;
            end
            else begin

                if (dmem_req && dmem_gnt) begin
                    accepted_count <= accepted_count + 1;

                    if (dmem_we !== 1'b1) begin
                        $fatal(
                            1,
                            "FAIL: la transaccion smoke no es un store"
                        );
                    end

                    if (dmem_addr !== 64'd0) begin
                        $fatal(
                            1,
                            "FAIL: store addr=0x%016h esperado=0",
                            dmem_addr
                        );
                    end

                    if (dmem_wdata !== 64'd12) begin
                        $fatal(
                            1,
                            "FAIL: store wdata=%0d esperado=12",
                            dmem_wdata
                        );
                    end

                    if (dmem_wstrb !== 8'hFF) begin
                        $fatal(
                            1,
                            "FAIL: store wstrb=0x%02h esperado=0xff",
                            dmem_wstrb
                        );
                    end

                    if (dmem_size !== 2'b11) begin
                        $fatal(
                            1,
                            "FAIL: store size=%b esperado=11",
                            dmem_size
                        );
                    end

                    $display(
                        "[%0t] STORE ACCEPTED addr=%0d wdata=%0d wstrb=0x%02h size=%0d",
                        $time,
                        dmem_addr,
                        dmem_wdata,
                        dmem_wstrb,
                        dmem_size
                    );
                end

                if (dmem_rvalid) begin
                    response_count <= response_count + 1;

                    if (dmem_error) begin
                        $fatal(
                            1,
                            "FAIL: smoke store terminó con dmem_error"
                        );
                    end
                end
            end
        end

    // =========================================================
    // Inicialización y prueba
    // =========================================================

    integer i;
    integer timeout;

    initial begin

        $dumpfile("build/tb_core_smoke.vcd");
        $dumpvars(0, tb_core_smoke);

        rst = 1'b1;

        // -----------------------------------------------------
        // IMEM por defecto: NOP
        // -----------------------------------------------------

        for (i = 0; i < IMEM_WORDS; i = i + 1) begin
            u_imem.mem[i] = 32'h0000_0013;
        end

        // -----------------------------------------------------
        // Programa
        //
        // 0x00: addi x1, x0, 5
        // 0x04: addi x2, x0, 7
        // 0x08: add  x3, x1, x2
        // 0x0c: sd   x3, 0(x0)
        // 0x10: jal  x0, 0
        // -----------------------------------------------------

        u_imem.mem[0] = 32'h0050_0093;
        u_imem.mem[1] = 32'h0070_0113;
        u_imem.mem[2] = 32'h0020_81b3;
        u_imem.mem[3] = 32'h0030_3023;
        u_imem.mem[4] = 32'h0000_006f;

        // -----------------------------------------------------
        // Reset
        //
        // Se libera en negedge para evitar carreras entre TB
        // y lógica secuencial del DUT.
        // -----------------------------------------------------

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        // -----------------------------------------------------
        // Esperar la única respuesta DMEM.
        //
        // No dependemos de un número exacto de ciclos de la
        // memoria, aunque actualmente RESP_DELAY sea 1.
        // -----------------------------------------------------

        timeout = 0;

        while (
            (response_count < 1) &&
            (timeout < 100)
        ) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (response_count != 1) begin
            $fatal(
                1,
                "FAIL: timeout esperando respuesta DMEM"
            );
        end

        // Dejar avanzar unos ciclos para estabilizar el estado
        // arquitectural y alcanzar el jal x0, 0.
        repeat (5) @(posedge clk);

        // =====================================================
        // Checks finales
        // =====================================================

        if (dut.u_regfile.regs[1] !== 64'd5) begin
            $fatal(
                1,
                "FAIL: x1 != 5, valor=%0d",
                dut.u_regfile.regs[1]
            );
        end

        if (dut.u_regfile.regs[2] !== 64'd7) begin
            $fatal(
                1,
                "FAIL: x2 != 7, valor=%0d",
                dut.u_regfile.regs[2]
            );
        end

        if (dut.u_regfile.regs[3] !== 64'd12) begin
            $fatal(
                1,
                "FAIL: x3 != 12, valor=%0d",
                dut.u_regfile.regs[3]
            );
        end

        if (u_dmem.mem[0] !== 64'd12) begin
            $fatal(
                1,
                "FAIL: DMEM[0] != 12, valor=0x%016h",
                u_dmem.mem[0]
            );
        end

        if (accepted_count != 1) begin
            $fatal(
                1,
                "FAIL: accepted_count=%0d esperado=1",
                accepted_count
            );
        end

        if (response_count != 1) begin
            $fatal(
                1,
                "FAIL: response_count=%0d esperado=1",
                response_count
            );
        end

        $display("==============================================");
        $display("PASS: tb_core_smoke con DMEM síncrona");
        $display("      x1 = 5");
        $display("      x2 = 7");
        $display("      x3 = 12");
        $display("      SD aceptado exactamente una vez");
        $display("      response recibida exactamente una vez");
        $display("      DMEM[0] = 12");
        $display("      dmem_legacy_compat ya no utilizado");
        $display("==============================================");

        $finish;
    end

endmodule
