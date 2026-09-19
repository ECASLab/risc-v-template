`timescale 1ns/1ps

module tb_imem_sync_model;

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
    // Modelo A:
    //
    // grant inmediato
    // response +1 ciclo
    // =========================================================

        logic        req_fast;
        logic        gnt_fast;
        logic [63:0] addr_fast;

        logic        rvalid_fast;
        logic [31:0] rdata_fast;

        imem_sync_model #(
            .MEM_WORDS  (64),
            .GNT_DELAY  (0),
            .RESP_DELAY (1)
        ) u_fast (
            .clk      (clk),
            .rst      (rst),

            .req_i    (req_fast),
            .gnt_o    (gnt_fast),

            .addr_i   (addr_fast),

            .rvalid_o (rvalid_fast),
            .rdata_o  (rdata_fast)
        );

    // =========================================================
    // Modelo B:
    //
    // WAIT_GNT real
    // WAIT_RESP real
    // =========================================================

        logic        req_slow;
        logic        gnt_slow;
        logic [63:0] addr_slow;

        logic        rvalid_slow;
        logic [31:0] rdata_slow;

        imem_sync_model #(
            .MEM_WORDS  (64),
            .GNT_DELAY  (2),
            .RESP_DELAY (3)
        ) u_slow (
            .clk      (clk),
            .rst      (rst),

            .req_i    (req_slow),
            .gnt_o    (gnt_slow),

            .addr_i   (addr_slow),

            .rvalid_o (rvalid_slow),
            .rdata_o  (rdata_slow)
        );

    // =========================================================
    // Helpers
    // =========================================================

        task automatic check1(
            input string name,
            input logic  got,
            input logic  exp
        );
            begin

                if (got !== exp) begin
                    $display(
                        "FAIL: %s got=%b expected=%b",
                        name,
                        got,
                        exp
                    );
                    $fatal(1);
                end

                $display(
                    "PASS : %-42s = %b",
                    name,
                    got
                );
            end
        endtask

        task automatic check32(
            input string       name,
            input logic [31:0] got,
            input logic [31:0] exp
        );
            begin

                if (got !== exp) begin
                    $display(
                        "FAIL: %s got=0x%08h expected=0x%08h",
                        name,
                        got,
                        exp
                    );
                    $fatal(1);
                end

                $display(
                    "PASS : %-42s = 0x%08h",
                    name,
                    got
                );
            end
        endtask

    // =========================================================
    // Test
    // =========================================================

        integer wait_gnt_cycles;
        integer wait_resp_cycles;

        initial begin

            $dumpfile("build/tb_imem_sync_model.vcd");
            $dumpvars(0, tb_imem_sync_model);

            req_fast  = 1'b0;
            addr_fast = 64'd0;

            req_slow  = 1'b0;
            addr_slow = 64'd0;

            wait_gnt_cycles  = 0;
            wait_resp_cycles = 0;

            // -----------------------------------------------------
            // Contenido de memoria
            // -----------------------------------------------------

            u_fast.mem[0] = 32'h0050_0093;
            u_fast.mem[1] = 32'h0070_0113;

            u_fast.mem[2] = 32'h1111_2222;
            u_fast.mem[3] = 32'h3333_4444;

            u_slow.mem[4] = 32'h1234_5678;
            u_slow.mem[5] = 32'hCAFE_BABE;

            // -----------------------------------------------------
            // Reset
            // -----------------------------------------------------

            rst = 1'b1;

            repeat (4) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            // Permitir que la lógica combinacional del modelo
            // reaccione a la liberación de reset antes de comprobar
            // las salidas.
            #1;

            // =====================================================
            // SCENARIO 1
            //
            // GNT_DELAY=0
            // RESP_DELAY=1
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 1: IMMEDIATE GRANT");
                $display("==============================================");

                // Memoria libre -> grant preasertado.
                check1(
                    "grant preasertado",
                    gnt_fast,
                    1'b1
                );

                @(negedge clk);

                addr_fast = 64'h0000_0000_0000_0000;
                req_fast  = 1'b1;

                // La petición se acepta en el siguiente posedge.
                @(posedge clk);

                @(negedge clk);
                req_fast = 1'b0;

                // RESP_DELAY=1:
                // rvalid debe estar visible en este primer ciclo
                // posterior a la aceptación.
                check1(
                    "rvalid inmediato +1 ciclo",
                    rvalid_fast,
                    1'b1
                );

                check32(
                    "fetch addr 0x00",
                    rdata_fast,
                    32'h0050_0093
                );

                @(posedge clk);
                @(negedge clk);

                check1(
                    "rvalid vuelve a cero",
                    rvalid_fast,
                    1'b0
                );

                // Segundo fetch inmediato.

                addr_fast = 64'h0000_0000_0000_0004;
                req_fast  = 1'b1;

                @(posedge clk);

                @(negedge clk);
                req_fast = 1'b0;

                check1(
                    "segundo rvalid inmediato",
                    rvalid_fast,
                    1'b1
                );

                check32(
                    "fetch addr 0x04",
                    rdata_fast,
                    32'h0070_0113
                );

                @(posedge clk);
                @(negedge clk);

            
            // =====================================================
            // SCENARIO 1B
            //
            // RESPONSE + NEXT REQUEST TURNOVER
            //
            // GNT_DELAY=0
            // RESP_DELAY=1
            //
            // La memoria debe poder entregar una respuesta y
            // aceptar la petición siguiente en el mismo ciclo.
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 1B: RESPONSE + NEXT REQUEST");
                $display("==============================================");

                // -----------------------------------------------------
                // Primera petición.
                // -----------------------------------------------------

                @(negedge clk);

                addr_fast = 64'h0000_0000_0000_0008;
                req_fast  = 1'b1;

                check1(
                    "grant turnover primera request",
                    gnt_fast,
                    1'b1
                );

                // Aceptación de addr 0x08.
                @(posedge clk);

                @(negedge clk);

                // La primera respuesta ya está disponible.
                check1(
                    "rvalid primera response turnover",
                    rvalid_fast,
                    1'b1
                );

                check32(
                    "turnover fetch addr 0x08",
                    rdata_fast,
                    32'h1111_2222
                );

                // -----------------------------------------------------
                // Mientras la response anterior sigue válida,
                // presentamos inmediatamente la siguiente dirección.
                // -----------------------------------------------------

                addr_fast = 64'h0000_0000_0000_000c;
                req_fast  = 1'b1;

                #1;

                // Debe existir grant simultáneamente con rvalid.
                check1(
                    "grant simultaneo con response",
                    gnt_fast,
                    1'b1
                );

                check1(
                    "response sigue valida durante turnover",
                    rvalid_fast,
                    1'b1
                );

                // En el siguiente posedge:
                //
                // - finaliza response de 0x08
                // - se acepta request de 0x0c
                @(posedge clk);

                @(negedge clk);

                // RESP_DELAY=1: la segunda response debe aparecer
                // inmediatamente en el ciclo siguiente, sin burbuja.
                check1(
                    "rvalid consecutivo turnover",
                    rvalid_fast,
                    1'b1
                );

                check32(
                    "turnover fetch addr 0x0c",
                    rdata_fast,
                    32'h3333_4444
                );

                // No solicitamos una tercera transacción.
                req_fast = 1'b0;

                @(posedge clk);
                @(negedge clk);

                check1(
                    "rvalid turnover vuelve a cero",
                    rvalid_fast,
                    1'b0
                );

            // =====================================================
            // SCENARIO 2
            //
            // GNT_DELAY=2
            // RESP_DELAY=3
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 2: WAIT_GNT + WAIT_RESP");
                $display("==============================================");

                addr_slow = 64'h0000_0000_0000_0010;
                req_slow  = 1'b1;

                wait_gnt_cycles = 0;

                while (!gnt_slow) begin

                    check1(
                        "req estable durante WAIT_GNT",
                        req_slow,
                        1'b1
                    );

                    if (
                        addr_slow !==
                        64'h0000_0000_0000_0010
                    ) begin
                        $fatal(
                            1,
                            "FAIL: dirección cambió durante WAIT_GNT"
                        );
                    end

                    @(posedge clk);
                    wait_gnt_cycles = wait_gnt_cycles + 1;

                    @(negedge clk);
                end

                if (wait_gnt_cycles != 2) begin
                    $fatal(
                        1,
                        "FAIL: WAIT_GNT cycles=%0d esperado=2",
                        wait_gnt_cycles
                    );
                end

                $display(
                    "PASS : WAIT_GNT observado durante %0d ciclos",
                    wait_gnt_cycles
                );

                // Grant visible: aceptación en el siguiente posedge.

                @(posedge clk);

                @(negedge clk);
                req_slow = 1'b0;

                // -----------------------------------------------------
                // Esperar response.
                // -----------------------------------------------------

                wait_resp_cycles = 0;

                while (!rvalid_slow) begin

                    @(posedge clk);
                    wait_resp_cycles = wait_resp_cycles + 1;

                    @(negedge clk);
                end

                // RESP_DELAY=3 produce dos ciclos completos sin rvalid
                // después del ciclo de aceptación.
                if (wait_resp_cycles != 2) begin
                    $fatal(
                        1,
                        "FAIL: WAIT_RESP cycles=%0d esperado=2",
                        wait_resp_cycles
                    );
                end

                $display(
                    "PASS : WAIT_RESP observado durante %0d ciclos",
                    wait_resp_cycles
                );

                check32(
                    "fetch lento addr 0x10",
                    rdata_slow,
                    32'h1234_5678
                );

                @(posedge clk);
                @(negedge clk);

                check1(
                    "rvalid lento vuelve a cero",
                    rvalid_slow,
                    1'b0
                );

            // =====================================================
            // SCENARIO 3
            //
            // Nueva transacción después de completar la anterior.
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 3: SECOND SLOW FETCH");
                $display("==============================================");

                addr_slow = 64'h0000_0000_0000_0014;
                req_slow  = 1'b1;

                while (!gnt_slow) begin
                    @(posedge clk);
                    @(negedge clk);
                end

                @(posedge clk);

                @(negedge clk);
                req_slow = 1'b0;

                while (!rvalid_slow) begin
                    @(posedge clk);
                    @(negedge clk);
                end

                check32(
                    "fetch lento addr 0x14",
                    rdata_slow,
                    32'hCAFE_BABE
                );

                @(posedge clk);
                @(negedge clk);

                // =====================================================
                // PASS
                // =====================================================

                $display("");
                $display("==============================================");
                $display("PASS: imem_sync_model funcionando");
                $display("      grant inmediato");
                $display("      respuesta síncrona +1");
                $display("      WAIT_GNT");
                $display("      estabilidad de dirección");
                $display("      WAIT_RESP");
                $display("      direccionamiento por palabra de 32 bits");
                $display("      una sola transacción outstanding");
                $display("==============================================");

                $finish;
        end

    // =========================================================
    // Timeout
    // =========================================================

    initial begin

        #1000000;

        $display(
            "FAIL: timeout global en tb_imem_sync_model"
        );

        $fatal(1);
    end

endmodule
