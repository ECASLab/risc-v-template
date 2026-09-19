`timescale 1ns/1ps

module tb_dmem_handshake_ctrl;

    logic clk;
    logic rst;

    logic access_valid;

    logic gnt;
    logic rvalid;
    logic error;

    logic req;
    logic wait_stall;
    logic response_done;
    logic access_fault;

    integer checks;

    // =========================================================
    // DUT
    // =========================================================
    dmem_handshake_ctrl dut (
        .clk             (clk),
        .rst             (rst),

        .access_valid_i  (access_valid),

        .gnt_i           (gnt),
        .rvalid_i        (rvalid),
        .error_i         (error),

        .req_o           (req),

        .wait_stall_o    (wait_stall),
        .response_done_o (response_done),
        .access_fault_o  (access_fault)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // Helpers
    // =========================================================
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

    // =========================================================
    // Test
    // =========================================================
    initial begin
        $dumpfile("build/tb_dmem_handshake_ctrl.vcd");
        $dumpvars(0, tb_dmem_handshake_ctrl);

        checks       = 0;

        rst          = 1'b1;
        access_valid = 1'b0;
        gnt          = 1'b0;
        rvalid       = 1'b0;
        error        = 1'b0;

        repeat (3) tick();

        rst = 1'b0;
        #1;

        // =====================================================
        // CASO 0
        //
        // rvalid espurio sin ninguna transacción pendiente.
        //
        // No debe completar nada.
        // =====================================================
        $display("");
        $display("==============================================");
        $display("CASO 0: rvalid sin transacción outstanding");
        $display("==============================================");

        rvalid = 1'b1;
        #1;

        check_bit("req idle",          req,           1'b0);
        check_bit("response ignored",  response_done, 1'b0);
        check_bit("fault ignored",     access_fault,  1'b0);
        check_bit("stall idle",        wait_stall,    1'b0);

        tick();

        rvalid = 1'b0;


        // =====================================================
        // CASO 1
        //
        // Load/store normal con grant retrasado y respuesta
        // retrasada.
        //
        // Debemos comprobar:
        // - req permanece activo hasta gnt
        // - stall permanece activo
        // - req desaparece después de gnt
        // - no aparece otro req mientras esperamos rvalid
        // - rvalid libera el stall
        // =====================================================
        $display("");
        $display("==============================================");
        $display("CASO 1: grant y response retrasados");
        $display("==============================================");

        access_valid = 1'b1;
        gnt          = 1'b0;
        rvalid       = 1'b0;
        error        = 1'b0;

        #1;

        check_bit("req inicial",       req,        1'b1);
        check_bit("stall inicial",     wait_stall, 1'b1);

        // Ciclo 1 sin grant.
        tick();

        check_bit("req hold ciclo 1",  req,        1'b1);
        check_bit("stall ciclo 1",     wait_stall, 1'b1);

        // Ciclo 2 sin grant.
        tick();

        check_bit("req hold ciclo 2",  req,        1'b1);
        check_bit("stall ciclo 2",     wait_stall, 1'b1);

        // Ahora concedemos la solicitud.
        gnt = 1'b1;
        #1;

        check_bit("req antes de grant", req, 1'b1);

        tick();

        // Ya estamos en WAIT_RESP.
        gnt = 1'b0;
        #1;

        check_bit("req tras grant",       req,           1'b0);
        check_bit("stall esperando resp", wait_stall,    1'b1);
        check_bit("response todavía 0",   response_done, 1'b0);

        // Dos ciclos de respuesta lenta.
        tick();

        check_bit("sin nuevo req 1",   req,        1'b0);
        check_bit("stall resp ciclo 1", wait_stall, 1'b1);

        tick();

        check_bit("sin nuevo req 2",   req,        1'b0);
        check_bit("stall resp ciclo 2", wait_stall, 1'b1);

        // Respuesta correcta.
        rvalid = 1'b1;
        error  = 1'b0;
        #1;

        check_bit("response done", response_done, 1'b1);
        check_bit("stall liberado", wait_stall,   1'b0);
        check_bit("sin fault",       access_fault, 1'b0);

        tick();

        access_valid = 1'b0;
        rvalid       = 1'b0;
        #1;

        check_bit("req vuelve idle",   req,        1'b0);
        check_bit("stall vuelve idle", wait_stall, 1'b0);


        // =====================================================
        // CASO 2
        //
        // Error antes de rvalid NO debe generar access fault.
        // El mismo error junto con rvalid SÍ debe hacerlo.
        // =====================================================
        $display("");
        $display("==============================================");
        $display("CASO 2: error válido solamente con rvalid");
        $display("==============================================");

        access_valid = 1'b1;
        gnt          = 1'b1;
        rvalid       = 1'b0;
        error        = 1'b0;

        #1;

        check_bit("req transacción 2", req,        1'b1);
        check_bit("stall transacción 2", wait_stall, 1'b1);

        // Grant inmediato.
        tick();

        gnt   = 1'b0;
        error = 1'b1;
        #1;

        // error=1 pero todavía sin rvalid.
        check_bit("req esperando error", req,           1'b0);
        check_bit("error sin rvalid",     access_fault, 1'b0);
        check_bit("stall con error solo", wait_stall,   1'b1);

        tick();

        // Ahora llega la respuesta errónea.
        rvalid = 1'b1;
        #1;

        check_bit("response error done", response_done, 1'b1);
        check_bit("access fault",        access_fault,  1'b1);
        check_bit("stall fault libera",  wait_stall,    1'b0);

        tick();

        access_valid = 1'b0;
        rvalid       = 1'b0;
        error        = 1'b0;
        #1;

        check_bit("idle final req",   req,        1'b0);
        check_bit("idle final stall", wait_stall, 1'b0);
        check_bit("idle final fault", access_fault, 1'b0);


        // =====================================================
        // Resultado
        // =====================================================
        $display("");
        $display("==============================================");
        $display("PASS: tb_dmem_handshake_ctrl");
        $display("      checks = %0d", checks);
        $display("      req sostenido hasta grant");
        $display("      una sola transacción outstanding");
        $display("      respuesta retrasada soportada");
        $display("      error solo válido junto con rvalid");
        $display("==============================================");

        $finish;
    end

    // Timeout de seguridad.
    initial begin
        #5000;
        $display("FAIL: timeout tb_dmem_handshake_ctrl");
        $fatal(1);
    end

endmodule
