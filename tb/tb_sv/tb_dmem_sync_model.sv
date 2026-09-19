`timescale 1ns/1ps

module tb_dmem_sync_model;

    // =========================================================
    // Configuración
    // =========================================================

    localparam int unsigned MEM_WORDS = 16;

    localparam logic [63:0] FAULT_ADDR =
        64'h0000_0000_0000_0030;

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
    // DUT FAST
    //
    // Grant inmediato/preasertado.
    // Respuesta en el primer ciclo posterior.
    // =========================================================

    logic        fast_req;
    logic        fast_gnt;
    logic [63:0] fast_addr;
    logic        fast_we;
    logic [63:0] fast_wdata;
    logic [7:0]  fast_wstrb;
    logic [1:0]  fast_size;

    logic        fast_rvalid;
    logic [63:0] fast_rdata;
    logic        fast_error;

    dmem_sync_model #(
        .MEM_WORDS  (MEM_WORDS),
        .GNT_DELAY  (0),
        .RESP_DELAY (1)
    ) u_dmem_fast (
        .clk      (clk),
        .rst      (rst),

        .req_i    (fast_req),
        .gnt_o    (fast_gnt),

        .addr_i   (fast_addr),
        .we_i     (fast_we),
        .wdata_i  (fast_wdata),
        .wstrb_i  (fast_wstrb),
        .size_i   (fast_size),

        .rvalid_o (fast_rvalid),
        .rdata_o  (fast_rdata),
        .error_o  (fast_error)
    );

    // =========================================================
    // DUT SLOW
    //
    // Grant retrasado dos ciclos completos.
    // Respuesta con latencia de tres ciclos.
    // =========================================================

    logic        slow_req;
    logic        slow_gnt;
    logic [63:0] slow_addr;
    logic        slow_we;
    logic [63:0] slow_wdata;
    logic [7:0]  slow_wstrb;
    logic [1:0]  slow_size;

    logic        slow_rvalid;
    logic [63:0] slow_rdata;
    logic        slow_error;

    dmem_sync_model #(
        .MEM_WORDS  (MEM_WORDS),
        .GNT_DELAY  (2),
        .RESP_DELAY (3)
    ) u_dmem_slow (
        .clk      (clk),
        .rst      (rst),

        .req_i    (slow_req),
        .gnt_o    (slow_gnt),

        .addr_i   (slow_addr),
        .we_i     (slow_we),
        .wdata_i  (slow_wdata),
        .wstrb_i  (slow_wstrb),
        .size_i   (slow_size),

        .rvalid_o (slow_rvalid),
        .rdata_o  (slow_rdata),
        .error_o  (slow_error)
    );

    // =========================================================
    // DUT FAULT
    //
    // Además de comprobar faults explícitos, este modelo se
    // utilizará para comprobar accesos fuera de rango.
    // =========================================================

    logic        fault_req;
    logic        fault_gnt;
    logic [63:0] fault_addr;
    logic        fault_we;
    logic [63:0] fault_wdata;
    logic [7:0]  fault_wstrb;
    logic [1:0]  fault_size;

    logic        fault_rvalid;
    logic [63:0] fault_rdata;
    logic        fault_error;

    dmem_sync_model #(
        .MEM_WORDS    (MEM_WORDS),
        .GNT_DELAY    (1),
        .RESP_DELAY   (2),

        .FAULT_ENABLE (1'b1),
        .FAULT_ADDR   (FAULT_ADDR),
        .FAULT_MASK   (64'hFFFF_FFFF_FFFF_FFFF)
    ) u_dmem_fault (
        .clk      (clk),
        .rst      (rst),

        .req_i    (fault_req),
        .gnt_o    (fault_gnt),

        .addr_i   (fault_addr),
        .we_i     (fault_we),
        .wdata_i  (fault_wdata),
        .wstrb_i  (fault_wstrb),
        .size_i   (fault_size),

        .rvalid_o (fault_rvalid),
        .rdata_o  (fault_rdata),
        .error_o  (fault_error)
    );

    // =========================================================
    // Contadores de aceptación
    //
    // Sirven para comprobar que un request que permanece
    // activo varios ciclos esperando grant produce una sola
    // aceptación.
    // =========================================================

    integer fast_accept_count;
    integer slow_accept_count;
    integer fault_accept_count;

    always @(posedge clk) begin
        if (rst) begin
            fast_accept_count  <= 0;
            slow_accept_count  <= 0;
            fault_accept_count <= 0;
        end
        else begin
            if (fast_req && fast_gnt) begin
                fast_accept_count <= fast_accept_count + 1;
            end

            if (slow_req && slow_gnt) begin
                slow_accept_count <= slow_accept_count + 1;
            end

            if (fault_req && fault_gnt) begin
                fault_accept_count <= fault_accept_count + 1;
            end
        end
    end

    // =========================================================
    // Checks
    // =========================================================

    integer errors;

    task automatic check1(
        input string name,
        input logic got,
        input logic expected
    );
        begin
            if (got !== expected) begin
                $display(
                    "ERROR: %-40s got=%0b expected=%0b",
                    name,
                    got,
                    expected
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : %-40s = %0b",
                    name,
                    got
                );
            end
        end
    endtask

    task automatic check64(
        input string       name,
        input logic [63:0] got,
        input logic [63:0] expected
    );
        begin
            if (got !== expected) begin
                $display(
                    "ERROR: %-40s got=0x%016h expected=0x%016h",
                    name,
                    got,
                    expected
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : %-40s = 0x%016h",
                    name,
                    got
                );
            end
        end
    endtask

    task automatic check_int(
        input string  name,
        input integer got,
        input integer expected
    );
        begin
            if (got != expected) begin
                $display(
                    "ERROR: %-40s got=%0d expected=%0d",
                    name,
                    got,
                    expected
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : %-40s = %0d",
                    name,
                    got
                );
            end
        end
    endtask

    // =========================================================
    // Inicialización común de interfaces
    // =========================================================

    task automatic clear_requests;
        begin
            fast_req   = 1'b0;
            fast_addr  = 64'd0;
            fast_we    = 1'b0;
            fast_wdata = 64'd0;
            fast_wstrb = 8'd0;
            fast_size  = 2'd0;

            slow_req   = 1'b0;
            slow_addr  = 64'd0;
            slow_we    = 1'b0;
            slow_wdata = 64'd0;
            slow_wstrb = 8'd0;
            slow_size  = 2'd0;

            fault_req   = 1'b0;
            fault_addr  = 64'd0;
            fault_we    = 1'b0;
            fault_wdata = 64'd0;
            fault_wstrb = 8'd0;
            fault_size  = 2'd0;
        end
    endtask

    // =========================================================
    // Secuencia principal
    // =========================================================

    initial begin

        $dumpfile("build/tb_dmem_sync_model.vcd");
        $dumpvars(0, tb_dmem_sync_model);

        errors = 0;

        rst = 1'b1;

        clear_requests();

        // -----------------------------------------------------
        // Reset
        // -----------------------------------------------------

        repeat (4) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        #1;

        $display("");
        $display("==============================================");
        $display("TEST 1: estado posterior a reset");
        $display("==============================================");

        // El modelo rápido permite grant preasertado.
        check1(
            "FAST gnt preasertado",
            fast_gnt,
            1'b1
        );

        check1(
            "FAST rvalid inactivo",
            fast_rvalid,
            1'b0
        );

        check1(
            "SLOW gnt inactivo sin request",
            slow_gnt,
            1'b0
        );

        check1(
            "FAULT gnt inactivo sin request",
            fault_gnt,
            1'b0
        );

        // =====================================================
        // TEST 2
        // Store completo con grant inmediato
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 2: FAST store SD completo");
        $display("==============================================");

        @(negedge clk);

        fast_addr  = 64'h0000_0000_0000_0010;
        fast_we    = 1'b1;
        fast_wdata = 64'h0123_4567_89AB_CDEF;
        fast_wstrb = 8'hFF;
        fast_size  = 2'b11;
        fast_req   = 1'b1;

        #1;

        check1(
            "FAST grant inmediato",
            fast_gnt,
            1'b1
        );

        // El próximo flanco acepta la transacción.
        @(posedge clk);
        #1;

        check_int(
            "FAST aceptaciones después de SD",
            fast_accept_count,
            1
        );

        check1(
            "FAST store rvalid",
            fast_rvalid,
            1'b1
        );

        check1(
            "FAST store error",
            fast_error,
            1'b0
        );

        check64(
            "FAST memoria después de SD",
            u_dmem_fast.mem[2],
            64'h0123_4567_89AB_CDEF
        );

        // Retirar request después de que fue aceptado.
        @(negedge clk);
        fast_req   = 1'b0;
        fast_we    = 1'b0;
        fast_wstrb = 8'd0;

        // Consumir respuesta.
        @(posedge clk);
        #1;

        check1(
            "FAST rvalid vuelve a cero",
            fast_rvalid,
            1'b0
        );

        check1(
            "FAST vuelve a aceptar requests",
            fast_gnt,
            1'b1
        );

        // =====================================================
        // TEST 3
        // Load completo
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 3: FAST load LD");
        $display("==============================================");

        @(negedge clk);

        fast_addr  = 64'h0000_0000_0000_0010;
        fast_we    = 1'b0;
        fast_wdata = 64'd0;
        fast_wstrb = 8'd0;
        fast_size  = 2'b11;
        fast_req   = 1'b1;

        @(posedge clk);
        #1;

        check_int(
            "FAST aceptaciones después de LD",
            fast_accept_count,
            2
        );

        check1(
            "FAST load rvalid",
            fast_rvalid,
            1'b1
        );

        check1(
            "FAST load error",
            fast_error,
            1'b0
        );

        check64(
            "FAST load rdata",
            fast_rdata,
            64'h0123_4567_89AB_CDEF
        );

        @(negedge clk);
        fast_req = 1'b0;

        @(posedge clk);
        #1;

        // =====================================================
        // TEST 4
        // Byte enables
        //
        // Línea inicial:
        //
        // 11 22 33 44 55 66 77 88
        //
        // Queremos modificar únicamente lanes 2 y 3:
        //
        // wstrb = 0000_1100
        //
        // Resultado:
        //
        // 11 22 33 44 BB AA 77 88
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 4: FAST byte write enables");
        $display("==============================================");

        u_dmem_fast.mem[3] =
            64'h1122_3344_5566_7788;

        @(negedge clk);

        fast_addr  = 64'h0000_0000_0000_0018;
        fast_we    = 1'b1;
        fast_wdata = 64'h0000_0000_BBAA_0000;
        fast_wstrb = 8'b0000_1100;
        fast_size  = 2'b01;
        fast_req   = 1'b1;

        @(posedge clk);
        #1;

        check_int(
            "FAST aceptaciones después de SH",
            fast_accept_count,
            3
        );

        check64(
            "FAST resultado byte enables",
            u_dmem_fast.mem[3],
            64'h1122_3344_BBAA_7788
        );

        @(negedge clk);

        fast_req   = 1'b0;
        fast_we    = 1'b0;
        fast_wstrb = 8'd0;

        @(posedge clk);
        #1;

        // =====================================================
        // TEST 5
        // Grant retrasado + respuesta retrasada
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 5: SLOW delayed grant + delayed response");
        $display("==============================================");

        u_dmem_slow.mem[4] =
            64'hCAFE_BABE_DEAD_BEEF;

        @(negedge clk);

        slow_addr  = 64'h0000_0000_0000_0020;
        slow_we    = 1'b0;
        slow_wdata = 64'd0;
        slow_wstrb = 8'd0;
        slow_size  = 2'b11;
        slow_req   = 1'b1;

        #1;

        // Antes del primer ciclo de espera.
        check1(
            "SLOW gnt inicialmente bajo",
            slow_gnt,
            1'b0
        );

        // Primer ciclo completo de espera.
        @(posedge clk);
        #1;

        check1(
            "SLOW gnt después wait cycle 1",
            slow_gnt,
            1'b0
        );

        check_int(
            "SLOW todavía sin aceptación",
            slow_accept_count,
            0
        );

        // Después del segundo ciclo el grant se presenta
        // para ser aceptado en el siguiente flanco.
        @(posedge clk);
        #1;

        check1(
            "SLOW gnt después wait cycle 2",
            slow_gnt,
            1'b1
        );

        check_int(
            "SLOW todavía sin aceptación antes del flanco",
            slow_accept_count,
            0
        );

        // La petición se acepta aquí.
        @(posedge clk);
        #1;

        check_int(
            "SLOW una aceptación",
            slow_accept_count,
            1
        );

        check1(
            "SLOW gnt baja durante response",
            slow_gnt,
            1'b0
        );

        check1(
            "SLOW rvalid response cycle 1",
            slow_rvalid,
            1'b0
        );

        // Req puede retirarse porque ya hubo grant.
        @(negedge clk);
        slow_req = 1'b0;

        // Response cycle 2.
        @(posedge clk);
        #1;

        check1(
            "SLOW rvalid response cycle 2",
            slow_rvalid,
            1'b0
        );

        // Response cycle 3.
        @(posedge clk);
        #1;

        check1(
            "SLOW rvalid response cycle 3",
            slow_rvalid,
            1'b1
        );

        check1(
            "SLOW load sin error",
            slow_error,
            1'b0
        );

        check64(
            "SLOW load data",
            slow_rdata,
            64'hCAFE_BABE_DEAD_BEEF
        );

        // Consumir respuesta.
        @(posedge clk);
        #1;

        check1(
            "SLOW rvalid finaliza",
            slow_rvalid,
            1'b0
        );

        // =====================================================
        // TEST 6
        // Store con grant retrasado.
        //
        // Debe haber una sola aceptación aun cuando req/we se
        // mantengan varios ciclos.
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 6: SLOW store sin duplicación");
        $display("==============================================");

        u_dmem_slow.mem[5] = 64'd0;

        @(negedge clk);

        slow_addr  = 64'h0000_0000_0000_0028;
        slow_we    = 1'b1;
        slow_wdata = 64'hA5A5_5A5A_1234_5678;
        slow_wstrb = 8'hFF;
        slow_size  = 2'b11;
        slow_req   = 1'b1;

        // Esperar hasta que el modelo presente grant.
        wait (slow_gnt === 1'b1);

        // La petición todavía no ha sido aceptada hasta
        // el siguiente flanco.
        check_int(
            "SLOW store aceptaciones antes del grant edge",
            slow_accept_count,
            1
        );

        @(posedge clk);
        #1;

        check_int(
            "SLOW store una nueva aceptación",
            slow_accept_count,
            2
        );

        check64(
            "SLOW store actualizó memoria",
            u_dmem_slow.mem[5],
            64'hA5A5_5A5A_1234_5678
        );

        @(negedge clk);
        slow_req   = 1'b0;
        slow_we    = 1'b0;
        slow_wstrb = 8'd0;

        // Esperar la respuesta completa.
        wait (slow_rvalid === 1'b1);
        #1;

        check1(
            "SLOW store response sin error",
            slow_error,
            1'b0
        );

        check_int(
            "SLOW store no fue aceptado dos veces",
            slow_accept_count,
            2
        );

        check64(
            "SLOW memoria permanece correcta",
            u_dmem_slow.mem[5],
            64'hA5A5_5A5A_1234_5678
        );

        @(posedge clk);
        #1;

        // =====================================================
        // TEST 7
        // Load access fault explícito
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 7: injected load access fault");
        $display("==============================================");

        @(negedge clk);

        fault_addr  = FAULT_ADDR;
        fault_we    = 1'b0;
        fault_wdata = 64'd0;
        fault_wstrb = 8'd0;
        fault_size  = 2'b11;
        fault_req   = 1'b1;

        wait (fault_gnt === 1'b1);

        @(posedge clk);
        #1;

        check_int(
            "FAULT load aceptado una vez",
            fault_accept_count,
            1
        );

        check1(
            "FAULT load aún sin rvalid inmediato",
            fault_rvalid,
            1'b0
        );

        @(negedge clk);
        fault_req = 1'b0;

        wait (fault_rvalid === 1'b1);
        #1;

        check1(
            "FAULT load rvalid",
            fault_rvalid,
            1'b1
        );

        check1(
            "FAULT load error",
            fault_error,
            1'b1
        );

        check64(
            "FAULT load rdata don't-care normalizado",
            fault_rdata,
            64'd0
        );

        @(posedge clk);
        #1;

        // =====================================================
        // TEST 8
        // Store access fault sin efectos laterales
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 8: injected store fault sin write");
        $display("==============================================");

        // FAULT_ADDR = 0x30 -> índice 6.
        u_dmem_fault.mem[6] =
            64'hFACE_CAFE_0123_4567;

        @(negedge clk);

        fault_addr  = FAULT_ADDR;
        fault_we    = 1'b1;
        fault_wdata = 64'hFFFF_FFFF_FFFF_FFFF;
        fault_wstrb = 8'hFF;
        fault_size  = 2'b11;
        fault_req   = 1'b1;

        wait (fault_gnt === 1'b1);

        @(posedge clk);
        #1;

        check_int(
            "FAULT store aceptación",
            fault_accept_count,
            2
        );

        // El store fault NO debe modificar memoria ni siquiera
        // en el instante de aceptación.
        check64(
            "FAULT store no modificó memoria",
            u_dmem_fault.mem[6],
            64'hFACE_CAFE_0123_4567
        );

        @(negedge clk);

        fault_req   = 1'b0;
        fault_we    = 1'b0;
        fault_wstrb = 8'd0;

        wait (fault_rvalid === 1'b1);
        #1;

        check1(
            "FAULT store rvalid",
            fault_rvalid,
            1'b1
        );

        check1(
            "FAULT store error",
            fault_error,
            1'b1
        );

        check64(
            "FAULT memoria sigue intacta",
            u_dmem_fault.mem[6],
            64'hFACE_CAFE_0123_4567
        );

        @(posedge clk);
        #1;

        // =====================================================
        // TEST 9
        // Acceso fuera de rango
        //
        // MEM_WORDS = 16
        // 16 * 8 = 128 bytes = 0x80.
        //
        // Por tanto 0x80 es la primera línea fuera de rango.
        // =====================================================

        $display("");
        $display("==============================================");
        $display("TEST 9: address out of range");
        $display("==============================================");

        @(negedge clk);

        fault_addr  = 64'h0000_0000_0000_0080;
        fault_we    = 1'b0;
        fault_wdata = 64'd0;
        fault_wstrb = 8'd0;
        fault_size  = 2'b11;
        fault_req   = 1'b1;

        wait (fault_gnt === 1'b1);

        @(posedge clk);
        #1;

        check_int(
            "FAULT out-of-range aceptación",
            fault_accept_count,
            3
        );

        @(negedge clk);
        fault_req = 1'b0;

        wait (fault_rvalid === 1'b1);
        #1;

        check1(
            "FAULT out-of-range rvalid",
            fault_rvalid,
            1'b1
        );

        check1(
            "FAULT out-of-range error",
            fault_error,
            1'b1
        );

        @(posedge clk);
        #1;

        // =====================================================
        // Resultado
        // =====================================================

        $display("");
        $display("==============================================");

        if (errors == 0) begin
            $display(
                "PASS: tb_dmem_sync_model completado sin errores"
            );
        end
        else begin
            $display(
                "FAIL: tb_dmem_sync_model encontró %0d errores",
                errors
            );
        end

        $display("==============================================");

        if (errors != 0) begin
            $fatal(
                1,
                "tb_dmem_sync_model falló"
            );
        end

        $finish;
    end

    // =========================================================
    // Timeout
    // =========================================================

    initial begin
        #10000;

        $fatal(
            1,
            "TIMEOUT: tb_dmem_sync_model no terminó"
        );
    end

endmodule
