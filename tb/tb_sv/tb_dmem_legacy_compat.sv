`timescale 1ns/1ps

module tb_dmem_legacy_compat;

    logic clk;
    logic rst;

    logic req;
    logic gnt;
    logic rvalid;
    logic error;

    integer checks;

    dmem_legacy_compat dut (
        .clk      (clk),
        .rst      (rst),

        .req_i    (req),

        .gnt_o    (gnt),
        .rvalid_o (rvalid),
        .error_o  (error)
    );

    // ========================================================
    // Clock
    // ========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ========================================================
    // Helpers
    // ========================================================
    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_bit(
        input string name,
        input logic got,
        input logic expected
    );
        begin
            checks = checks + 1;

            if (got !== expected) begin
                $display(
                    "FAIL: %-28s got=%0b expected=%0b",
                    name,
                    got,
                    expected
                );
                $fatal(1);
            end
            else begin
                $display(
                    "PASS: %-28s = %0b",
                    name,
                    got
                );
            end
        end
    endtask

    // ========================================================
    // Test
    // ========================================================
    initial begin
        $dumpfile("build/tb_dmem_legacy_compat.vcd");
        $dumpvars(0, tb_dmem_legacy_compat);

        checks = 0;

        rst = 1'b1;
        req = 1'b0;

        repeat (3) tick();

        rst = 1'b0;
        #1;

        // ----------------------------------------------------
        // Caso 0:
        // memoria siempre preparada, pero sin request.
        // ----------------------------------------------------
        $display("");
        $display("==============================================");
        $display("CASO 0: idle");
        $display("==============================================");

        check_bit("gnt siempre disponible", gnt,    1'b1);
        check_bit("rvalid idle",            rvalid, 1'b0);
        check_bit("error siempre cero",     error,  1'b0);

        // ----------------------------------------------------
        // Caso 1:
        // request aceptado inmediatamente.
        // rvalid NO debe estar todavía activo.
        // ----------------------------------------------------
        $display("");
        $display("==============================================");
        $display("CASO 1: request");
        $display("==============================================");

        req = 1'b1;
        #1;

        check_bit("request obtiene grant", gnt,    1'b1);
        check_bit("rvalid mismo ciclo",    rvalid, 1'b0);
        check_bit("sin error",             error,  1'b0);

        // Capturar request en el flanco.
        tick();

        // El master correcto retira req después del grant.
        req = 1'b0;
        #1;

        // ----------------------------------------------------
        // Caso 2:
        // respuesta exactamente un ciclo después.
        // ----------------------------------------------------
        $display("");
        $display("==============================================");
        $display("CASO 2: response");
        $display("==============================================");

        check_bit("rvalid ciclo siguiente", rvalid, 1'b1);
        check_bit("gnt sigue disponible",   gnt,    1'b1);
        check_bit("response sin error",      error,  1'b0);

        tick();

        #1;

        check_bit("rvalid vuelve a cero", rvalid, 1'b0);

        // ----------------------------------------------------
        // Caso 3:
        // segunda transacción independiente.
        // ----------------------------------------------------
        $display("");
        $display("==============================================");
        $display("CASO 3: segunda transacción");
        $display("==============================================");

        req = 1'b1;
        #1;

        check_bit("segundo grant",  gnt,    1'b1);
        check_bit("sin rvalid aún", rvalid, 1'b0);

        tick();

        req = 1'b0;
        #1;

        check_bit("segundo rvalid", rvalid, 1'b1);
        check_bit("segundo error",  error,  1'b0);

        tick();

        #1;

        check_bit("idle final rvalid", rvalid, 1'b0);
        check_bit("idle final gnt",    gnt,    1'b1);
        check_bit("idle final error",  error,  1'b0);

        // ----------------------------------------------------
        // Resultado
        // ----------------------------------------------------
        $display("");
        $display("==============================================");
        $display("PASS: tb_dmem_legacy_compat");
        $display("      checks = %0d", checks);
        $display("      grant inmediato");
        $display("      response un ciclo después");
        $display("      error permanentemente desactivado");
        $display("==============================================");

        $finish;
    end

    initial begin
        #2000;
        $display("FAIL: timeout tb_dmem_legacy_compat");
        $fatal(1);
    end

endmodule
