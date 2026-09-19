`timescale 1ns/1ps

module tb_imem_handshake_ctrl;

    logic clk;
    logic rst;

    logic        start;
    logic [63:0] addr;

    logic        ready;
    logic        busy;

    logic        cancel;

    logic        resp_valid;
    logic        resp_ready;
    logic [63:0] resp_addr;
    logic [31:0] resp_data;

    logic        imem_req;
    logic [63:0] imem_addr;

    logic        imem_gnt;

    logic        imem_rvalid;
    logic [31:0] imem_rdata;

    // =========================================================
    // DUT
    // =========================================================

        imem_handshake_ctrl dut (
            .clk          (clk),
            .rst          (rst),

            .start_i      (start),
            .addr_i       (addr),

            .ready_o      (ready),
            .busy_o       (busy),

            .cancel_i     (cancel),

            .resp_valid_o (resp_valid),
            .resp_ready_i (resp_ready),
            .resp_addr_o  (resp_addr),
            .resp_data_o  (resp_data),

            .imem_req_o   (imem_req),
            .imem_addr_o  (imem_addr),

            .imem_gnt_i   (imem_gnt),

            .imem_rvalid_i(imem_rvalid),
            .imem_rdata_i (imem_rdata)
        );

    // =========================================================
    // Clock
    // =========================================================

        initial begin
            clk = 1'b0;
            forever #5 clk = ~clk;
        end

    // =========================================================
    // Checks
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
                    "PASS : %-40s = %b",
                    name,
                    got
                );
            end
        endtask

        task automatic check64(
            input string       name,
            input logic [63:0] got,
            input logic [63:0] exp
        );
            begin
                if (got !== exp) begin
                    $display(
                        "FAIL: %s got=0x%016h expected=0x%016h",
                        name,
                        got,
                        exp
                    );
                    $fatal(1);
                end

                $display(
                    "PASS : %-40s = 0x%016h",
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
                    "PASS : %-40s = 0x%08h",
                    name,
                    got
                );
            end
        endtask

    // =========================================================
    // Helpers
    // =========================================================

        task automatic issue_request(
            input logic [63:0] request_addr
        );
            begin

                if (!ready) begin
                    $fatal(
                        1,
                        "issue_request llamado mientras ready=0"
                    );
                end

                @(negedge clk);

                addr  = request_addr;
                start = 1'b1;

                @(posedge clk);
                @(negedge clk);

                start = 1'b0;

                check1(
                    "busy después de start",
                    busy,
                    1'b1
                );

                check1(
                    "imem_req esperando grant",
                    imem_req,
                    1'b1
                );

                check64(
                    "dirección latcheada",
                    imem_addr,
                    request_addr
                );
            end
        endtask

        task automatic grant_request;
            begin
                @(negedge clk);

                imem_gnt = 1'b1;

                @(posedge clk);
                @(negedge clk);

                imem_gnt = 1'b0;

                check1(
                    "req retirado después de grant",
                    imem_req,
                    1'b0
                );

                check1(
                    "busy esperando response",
                    busy,
                    1'b1
                );
            end
        endtask

        task automatic return_response(
            input logic [31:0] data
        );
            begin
                @(negedge clk);

                imem_rdata  = data;
                imem_rvalid = 1'b1;

                @(posedge clk);
                @(negedge clk);

                imem_rvalid = 1'b0;
                imem_rdata  = 32'd0;
            end
        endtask

        task automatic consume_response;
            begin
                @(negedge clk);

                resp_ready = 1'b1;

                @(posedge clk);
                @(negedge clk);

                resp_ready = 1'b0;

                check1(
                    "ready después de consumir",
                    ready,
                    1'b1
                );

                check1(
                    "busy después de consumir",
                    busy,
                    1'b0
                );
            end
        endtask

    // =========================================================
    // Test
    // =========================================================

        initial begin

            $dumpfile(
                "build/tb_imem_handshake_ctrl.vcd"
            );

            $dumpvars(
                0,
                tb_imem_handshake_ctrl
            );

            start       = 1'b0;
            addr        = 64'd0;

            cancel      = 1'b0;

            resp_ready  = 1'b0;

            imem_gnt    = 1'b0;

            imem_rvalid = 1'b0;
            imem_rdata  = 32'd0;

            rst = 1'b1;

            repeat (4) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            // =====================================================
            // Estado inicial
            // =====================================================

                check1("ready inicial", ready, 1'b1);
                check1("busy inicial",  busy,  1'b0);

            // =====================================================
            // Caso 1:
            // request -> grant -> response -> hold -> consume
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 1: NORMAL FETCH");
                $display("==============================================");

                issue_request(
                    64'h0000_0000_0000_0100
                );

                grant_request();

                return_response(
                    32'h1234_5678
                );

                check1(
                    "response válida",
                    resp_valid,
                    1'b1
                );

                check64(
                    "response address",
                    resp_addr,
                    64'h0000_0000_0000_0100
                );

                check32(
                    "response data",
                    resp_data,
                    32'h1234_5678
                );

                // Debe permanecer estable si no se consume.
                repeat (2) begin
                    @(posedge clk);
                    @(negedge clk);

                    check1(
                        "response permanece válida",
                        resp_valid,
                        1'b1
                    );

                    check64(
                        "response address estable",
                        resp_addr,
                        64'h0000_0000_0000_0100
                    );

                    check32(
                        "response data estable",
                        resp_data,
                        32'h1234_5678
                    );
                end

                consume_response();

            // =====================================================
            // Caso 2:
            // WAIT_GNT y estabilidad de dirección
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 2: WAIT_GNT");
                $display("==============================================");

                issue_request(
                    64'h0000_0000_0000_0200
                );

                // Cambiar addr_i NO puede modificar la request latcheada.
                @(negedge clk);
                addr = 64'hDEAD_BEEF_DEAD_BEEF;

                repeat (3) begin
                    @(posedge clk);
                    @(negedge clk);

                    check1(
                        "req permanece durante WAIT_GNT",
                        imem_req,
                        1'b1
                    );

                    check64(
                        "addr permanece estable",
                        imem_addr,
                        64'h0000_0000_0000_0200
                    );
                end

                grant_request();

                return_response(
                    32'hCAFE_BABE
                );

                check1(
                    "response WAIT_GNT válida",
                    resp_valid,
                    1'b1
                );

                check64(
                    "response WAIT_GNT address",
                    resp_addr,
                    64'h0000_0000_0000_0200
                );

                check32(
                    "response WAIT_GNT data",
                    resp_data,
                    32'hCAFE_BABE
                );

                consume_response();

            // =====================================================
            // Caso 3:
            // cancel mientras espera grant
            //
            // El request NO desaparece. La respuesta posterior debe
            // descartarse.
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 3: CANCEL BEFORE GRANT");
                $display("==============================================");

                issue_request(
                    64'h0000_0000_0000_0300
                );

                @(negedge clk);
                cancel = 1'b1;

                @(posedge clk);
                @(negedge clk);

                cancel = 1'b0;

                check1(
                    "req sigue activo después de cancel",
                    imem_req,
                    1'b1
                );

                check64(
                    "addr cancelada sigue estable",
                    imem_addr,
                    64'h0000_0000_0000_0300
                );

                grant_request();

                return_response(
                    32'hAAAA_5555
                );

                check1(
                    "respuesta cancelada no se publica",
                    resp_valid,
                    1'b0
                );

                check1(
                    "ready tras drenar cancelada",
                    ready,
                    1'b1
                );

            // =====================================================
            // Caso 4:
            // cancel después de grant y antes de response
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 4: CANCEL WAIT_RESP");
                $display("==============================================");

                issue_request(
                    64'h0000_0000_0000_0400
                );

                grant_request();

                @(negedge clk);
                cancel = 1'b1;

                @(posedge clk);
                @(negedge clk);

                cancel = 1'b0;

                return_response(
                    32'h0BAD_F00D
                );

                check1(
                    "WAIT_RESP cancelada no se publica",
                    resp_valid,
                    1'b0
                );

                check1(
                    "ready después de respuesta descartada",
                    ready,
                    1'b1
                );

            // =====================================================
            // Caso 5:
            // cancel de una response ya almacenada
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 5: CANCEL BUFFERED RESPONSE");
                $display("==============================================");

                issue_request(
                    64'h0000_0000_0000_0500
                );

                grant_request();

                return_response(
                    32'hFEED_FACE
                );

                check1(
                    "response buffered válida",
                    resp_valid,
                    1'b1
                );

                @(negedge clk);
                cancel = 1'b1;

                @(posedge clk);
                @(negedge clk);

                cancel = 1'b0;

                check1(
                    "buffered response descartada",
                    resp_valid,
                    1'b0
                );

                check1(
                    "ready después de cancelar buffered",
                    ready,
                    1'b1
                );

            // =====================================================
            // Caso 6:
            // turnover response + siguiente request
            //
            // Una respuesta consumida puede coincidir con la
            // aceptación de la siguiente dirección de fetch.
            //
            // Esto permite throughput de un fetch por ciclo cuando
            // la memoria concede inmediatamente y responde con
            // latencia de un ciclo.
            // =====================================================

                $display("");
                $display("==============================================");
                $display("SCENARIO 6: RESPONSE + NEXT REQUEST");
                $display("==============================================");

                // -----------------------------------------------------
                // Primera petición con grant inmediato.
                // -----------------------------------------------------

                @(negedge clk);

                addr       = 64'h0000_0000_0000_0600;
                start      = 1'b1;
                imem_gnt   = 1'b1;
                resp_ready = 1'b0;

                #1;

                check1(
                    "ready para request inmediata",
                    ready,
                    1'b1
                );

                check1(
                    "request inmediata visible",
                    imem_req,
                    1'b1
                );

                check64(
                    "request inmediata address",
                    imem_addr,
                    64'h0000_0000_0000_0600
                );

                @(posedge clk);
                @(negedge clk);

                start    = 1'b0;
                imem_gnt = 1'b0;

                // -----------------------------------------------------
                // Respuesta de la primera petición y, en el mismo ciclo,
                // siguiente petición con grant inmediato.
                // -----------------------------------------------------

                imem_rvalid = 1'b1;
                imem_rdata  = 32'h1111_2222;

                resp_ready = 1'b1;

                addr     = 64'h0000_0000_0000_0604;
                start    = 1'b1;
                imem_gnt = 1'b1;

                #1;

                check1(
                    "respuesta directa válida",
                    resp_valid,
                    1'b1
                );

                check64(
                    "respuesta directa address",
                    resp_addr,
                    64'h0000_0000_0000_0600
                );

                check32(
                    "respuesta directa data",
                    resp_data,
                    32'h1111_2222
                );

                check1(
                    "ready durante turnover",
                    ready,
                    1'b1
                );

                check1(
                    "siguiente request visible",
                    imem_req,
                    1'b1
                );

                check64(
                    "siguiente request address",
                    imem_addr,
                    64'h0000_0000_0000_0604
                );

                // En este flanco:
                //
                //   - se consume la respuesta de 0x600
                //   - se acepta la petición de 0x604
                //
                @(posedge clk);
                @(negedge clk);

                imem_rvalid = 1'b0;
                imem_rdata  = 32'd0;

                start    = 1'b0;
                imem_gnt = 1'b0;

                resp_ready = 1'b0;

                // -----------------------------------------------------
                // Respuesta de la segunda petición.
                // Esta vez introducimos backpressure para comprobar que
                // continúa funcionando HOLD_RESP.
                // -----------------------------------------------------

                imem_rvalid = 1'b1;
                imem_rdata  = 32'h3333_4444;

                #1;

                check1(
                    "segunda response directa válida",
                    resp_valid,
                    1'b1
                );

                check64(
                    "segunda response address",
                    resp_addr,
                    64'h0000_0000_0000_0604
                );

                check32(
                    "segunda response data",
                    resp_data,
                    32'h3333_4444
                );

                @(posedge clk);
                @(negedge clk);

                imem_rvalid = 1'b0;
                imem_rdata  = 32'd0;

                #1;

                check1(
                    "segunda response quedó buffered",
                    resp_valid,
                    1'b1
                );

                check64(
                    "segunda buffered address",
                    resp_addr,
                    64'h0000_0000_0000_0604
                );

                check32(
                    "segunda buffered data",
                    resp_data,
                    32'h3333_4444
                );

                consume_response();

            // =====================================================
            // PASS
            // =====================================================

            $display("");
            $display("==============================================");
            $display("PASS: imem_handshake_ctrl funcionando");
            $display("      request/grant");
            $display("      WAIT_GNT + estabilidad");
            $display("      response buffering");
            $display("      backpressure resp_ready");
            $display("      cancel antes de grant");
            $display("      cancel esperando response");
            $display("      cancel de response almacenada");
            $display("      máximo una transacción outstanding");
            $display("      response + next-request turnover");
            $display("==============================================");

            $finish;
        end

    // =========================================================
    // Timeout
    // =========================================================

        initial begin
            #100000;

            $display(
                "FAIL: timeout global en tb_imem_handshake_ctrl"
            );

            $fatal(1);
        end

endmodule
