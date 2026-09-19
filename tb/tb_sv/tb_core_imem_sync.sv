`timescale 1ns/1ps

module tb_core_imem_sync;

    localparam int unsigned IMEM_WORDS = 256;

    logic clk;
    logic rst;

    // =========================================================
    // IMEM handshake
    // =========================================================

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    // =========================================================
    // DMEM
    //
    // Este test no ejecuta loads/stores.
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

    assign dmem_gnt    = 1'b1;
    assign dmem_rvalid = 1'b0;
    assign dmem_error  = 1'b0;
    assign dmem_rdata  = 64'd0;

    // =========================================================
    // Expansión
    //
    // Tampoco se utiliza en este test.
    // =========================================================

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;

    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    // =========================================================
    // Clock
    // =========================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // Core
    // =========================================================

    core_top #(
        .RESET_PC(64'd0)
    ) dut (
        .clk         (clk),
        .rst         (rst),

        .imem_req    (imem_req),
        .imem_addr   (imem_addr),
        .imem_gnt    (imem_gnt),
        .imem_rvalid (imem_rvalid),
        .imem_rdata  (imem_rdata),

        .dmem_req    (dmem_req),
        .dmem_gnt    (dmem_gnt),
        .dmem_rvalid (dmem_rvalid),
        .dmem_error  (dmem_error),
        .dmem_rdata  (dmem_rdata),

        .dmem_we     (dmem_we),
        .dmem_wstrb  (dmem_wstrb),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_size   (dmem_size),

        .exp_valid   (exp_valid),
        .exp_we      (exp_we),
        .exp_addr    (exp_addr),
        .exp_wdata   (exp_wdata),
        .exp_wstrb   (exp_wstrb),
        .exp_size    (exp_size),

        .exp_ready   (exp_ready),
        .exp_rdata   (exp_rdata),
        .exp_error   (exp_error)
    );

    // =========================================================
    // IMEM síncrona real
    //
    // GNT_DELAY=2:
    //   obliga a observar WAIT_GNT.
    //
    // RESP_DELAY=3:
    //   obliga a observar WAIT_RESP y burbujas de frontend.
    // =========================================================

    imem_sync_model #(
        .MEM_WORDS (IMEM_WORDS),
        .GNT_DELAY (2),
        .RESP_DELAY(3)
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
    // Monitores
    // =========================================================

    integer accepted_count;
    integer response_count;
    integer wait_gnt_cycles;
    integer wait_resp_cycles;
    integer bubble_cycles;

    logic        outstanding_q;
    logic [63:0] accepted_addr_q;

    always @(posedge clk) begin
        if (rst) begin
            accepted_count   <= 0;
            response_count   <= 0;
            wait_gnt_cycles  <= 0;
            wait_resp_cycles <= 0;
            bubble_cycles    <= 0;

            outstanding_q   <= 1'b0;
            accepted_addr_q <= 64'd0;
        end
        else begin

            // -------------------------------------------------
            // WAIT_GNT
            // -------------------------------------------------

            if (imem_req && !imem_gnt) begin
                wait_gnt_cycles <= wait_gnt_cycles + 1;
            end

            // -------------------------------------------------
            // WAIT_RESP
            // -------------------------------------------------

            if (outstanding_q && !imem_rvalid) begin
                wait_resp_cycles <= wait_resp_cycles + 1;

                // Con la IMEM esperando respuesta y sin una
                // instrucción válida en IF/ID observamos una
                // burbuja real del frontend, no un stall global.
                if (!dut.id_valid_out) begin
                    bubble_cycles <= bubble_cycles + 1;
                end
            end

            // -------------------------------------------------
            // No debe existir actividad DMEM o expansión.
            // -------------------------------------------------

            if (dmem_req) begin
                $fatal(
                    1,
                    "FAIL: el programa IMEM generó dmem_req"
                );
            end

            if (exp_valid) begin
                $fatal(
                    1,
                    "FAIL: el programa IMEM generó exp_valid"
                );
            end

            // -------------------------------------------------
            // Aceptación IMEM
            // -------------------------------------------------

            if (imem_req && imem_gnt) begin

                if (outstanding_q) begin
                    $fatal(
                        1,
                        "FAIL: más de una transacción IMEM outstanding"
                    );
                end

                // Los primeros fetches deben ser estrictamente
                // secuenciales.
                case (accepted_count)
                    0: if (imem_addr !== 64'h0000_0000_0000_0000)
                        $fatal(1, "FAIL: fetch 0 addr=0x%016h", imem_addr);

                    1: if (imem_addr !== 64'h0000_0000_0000_0004)
                        $fatal(1, "FAIL: fetch 1 addr=0x%016h", imem_addr);

                    2: if (imem_addr !== 64'h0000_0000_0000_0008)
                        $fatal(1, "FAIL: fetch 2 addr=0x%016h", imem_addr);

                    3: if (imem_addr !== 64'h0000_0000_0000_000c)
                        $fatal(1, "FAIL: fetch 3 addr=0x%016h", imem_addr);

                    4: if (imem_addr !== 64'h0000_0000_0000_0010)
                        $fatal(1, "FAIL: fetch 4 addr=0x%016h", imem_addr);

                    5: if (imem_addr !== 64'h0000_0000_0000_0014)
                        $fatal(1, "FAIL: fetch 5 addr=0x%016h", imem_addr);

                    default: begin
                    end
                endcase

                outstanding_q   <= 1'b1;
                accepted_addr_q <= imem_addr;
                accepted_count  <= accepted_count + 1;
            end

            // Este modelo garantiza que grant y response no
            // corresponden a la misma transacción en el mismo
            // ciclo.
            if (
                (imem_req && imem_gnt) &&
                imem_rvalid
            ) begin
                $fatal(
                    1,
                    "FAIL: grant+rvalid inesperados en el mismo ciclo"
                );
            end

            // -------------------------------------------------
            // Respuesta IMEM
            // -------------------------------------------------

            if (imem_rvalid) begin

                if (!outstanding_q) begin
                    $fatal(
                        1,
                        "FAIL: respuesta IMEM sin transacción outstanding"
                    );
                end

                // Como este programa no contiene redirects ni
                // stalls, toda response debe ser consumible
                // inmediatamente por el frontend.
                if (!dut.imem_resp_valid) begin
                    $fatal(
                        1,
                        "FAIL: rvalid externo no llegó al frontend"
                    );
                end

                if (!dut.imem_resp_ready) begin
                    $fatal(
                        1,
                        "FAIL: frontend inesperadamente no listo"
                    );
                end

                // Verifica que el PC asociado a la respuesta
                // sea exactamente el de la petición aceptada.
                if (dut.imem_resp_addr !== accepted_addr_q) begin
                    $fatal(
                        1,
                        "FAIL: resp_addr=0x%016h esperado=0x%016h",
                        dut.imem_resp_addr,
                        accepted_addr_q
                    );
                end

                // Verifica asociación dirección/dato.
                if (
                    imem_rdata !==
                    u_imem.mem[accepted_addr_q[9:2]]
                ) begin
                    $fatal(
                        1,
                        "FAIL: rdata=0x%08h esperado=0x%08h addr=0x%016h",
                        imem_rdata,
                        u_imem.mem[accepted_addr_q[9:2]],
                        accepted_addr_q
                    );
                end

                outstanding_q <= 1'b0;
                response_count <= response_count + 1;
            end
        end
    end

    // =========================================================
    // Programa y prueba
    // =========================================================

    integer i;
    integer timeout;

    initial begin

        $dumpfile("build/tb_core_imem_sync.vcd");
        $dumpvars(0, tb_core_imem_sync);

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
        // 0x00: addi x1,  x0, 5
        // 0x04: addi x2,  x0, 7
        // 0x08: add  x3,  x1, x2
        // 0x0c: addi x4,  x3, 1
        // 0x10: add  x5,  x4, x1
        // 0x14: addi x31, x0, 1   <- sentinel
        // -----------------------------------------------------

        u_imem.mem[0] = 32'h0050_0093;
        u_imem.mem[1] = 32'h0070_0113;
        u_imem.mem[2] = 32'h0020_81b3;
        u_imem.mem[3] = 32'h0011_8213;
        u_imem.mem[4] = 32'h0012_02b3;
        u_imem.mem[5] = 32'h0010_0f93;

        // -----------------------------------------------------
        // Reset
        // -----------------------------------------------------

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;
        #1;

        // -----------------------------------------------------
        // Esperar sentinel arquitectural.
        // -----------------------------------------------------

        timeout = 0;

        while (
            (dut.u_regfile.regs[31] !== 64'd1) &&
            (timeout < 300)
        ) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        if (dut.u_regfile.regs[31] !== 64'd1) begin
            $fatal(
                1,
                "FAIL: timeout esperando ejecución del programa"
            );
        end

        // =====================================================
        // Estado arquitectural
        // =====================================================

        if (dut.u_regfile.regs[1] !== 64'd5)
            $fatal(1, "FAIL: x1=%0d esperado=5",
                   dut.u_regfile.regs[1]);

        if (dut.u_regfile.regs[2] !== 64'd7)
            $fatal(1, "FAIL: x2=%0d esperado=7",
                   dut.u_regfile.regs[2]);

        if (dut.u_regfile.regs[3] !== 64'd12)
            $fatal(1, "FAIL: x3=%0d esperado=12",
                   dut.u_regfile.regs[3]);

        if (dut.u_regfile.regs[4] !== 64'd13)
            $fatal(1, "FAIL: x4=%0d esperado=13",
                   dut.u_regfile.regs[4]);

        if (dut.u_regfile.regs[5] !== 64'd18)
            $fatal(1, "FAIL: x5=%0d esperado=18",
                   dut.u_regfile.regs[5]);

        // =====================================================
        // Evidencia de protocolo
        // =====================================================

        if (accepted_count < 6) begin
            $fatal(
                1,
                "FAIL: accepted_count=%0d esperado>=6",
                accepted_count
            );
        end

        if (response_count < 6) begin
            $fatal(
                1,
                "FAIL: response_count=%0d esperado>=6",
                response_count
            );
        end

        if (wait_gnt_cycles == 0) begin
            $fatal(
                1,
                "FAIL: nunca se observó WAIT_GNT"
            );
        end

        if (wait_resp_cycles == 0) begin
            $fatal(
                1,
                "FAIL: nunca se observó WAIT_RESP"
            );
        end

        if (bubble_cycles == 0) begin
            $fatal(
                1,
                "FAIL: no se observaron burbujas por espera IMEM"
            );
        end

        $display("================================================");
        $display("PASS: tb_core_imem_sync");
        $display("      core_top + imem_sync_model");
        $display("      x1  = 5");
        $display("      x2  = 7");
        $display("      x3  = 12");
        $display("      x4  = 13");
        $display("      x5  = 18");
        $display("      x31 = 1");
        $display("      accepted      = %0d", accepted_count);
        $display("      responses     = %0d", response_count);
        $display("      WAIT_GNT      = %0d ciclos", wait_gnt_cycles);
        $display("      WAIT_RESP     = %0d ciclos", wait_resp_cycles);
        $display("      bubble cycles = %0d", bubble_cycles);
        $display("================================================");

        $finish;
    end

endmodule
