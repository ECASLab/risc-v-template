`timescale 1ns/1ps

module tb_core_dmem_sync;

    // =========================================================
    // Configuración
    // =========================================================

        localparam int unsigned IMEM_WORDS = 256;
        localparam int unsigned DMEM_WORDS = 1024;

        localparam logic [63:0] DATA_BASE =
            64'h0000_0000_0000_0100;

        localparam logic [63:0] ADDR_SOURCE =
            64'h0000_0000_0000_0100;

        localparam logic [63:0] ADDR_INTERMEDIATE =
            64'h0000_0000_0000_0108;

        localparam logic [63:0] ADDR_RESULT =
            64'h0000_0000_0000_0110;

        localparam logic [63:0] INITIAL_VALUE =
            64'h1020_3040_5060_7080;

        localparam logic [63:0] EXPECTED_INTERMEDIATE =
            64'h1020_3040_5060_7081;

        localparam logic [63:0] EXPECTED_RESULT =
            64'h1020_3040_5060_7083;

    // =========================================================
    // Opcodes / funct3 mínimos
    // =========================================================

        localparam logic [6:0] OPCODE_OP_IMM =
            7'b0010011;

        localparam logic [6:0] OPCODE_LOAD =
            7'b0000011;

        localparam logic [6:0] OPCODE_STORE =
            7'b0100011;

        localparam logic [2:0] F3_ADDI = 3'b000;
        localparam logic [2:0] F3_LD   = 3'b011;
        localparam logic [2:0] F3_SD   = 3'b011;

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
    // Puerto de expansión
    //
    // Esta prueba no utiliza MMIO.
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
    // DUT
    //
    // IMPORTANTE:
    //
    // Aquí NO existe dmem_legacy_compat.
    // =========================================================

        core_top #(
            .RESET_PC   (64'h0000_0000_0000_0000),
            .TRAP_VECTOR(64'h0000_0000_0000_0200)
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

            .exp_valid  (exp_valid),
            .exp_we     (exp_we),
            .exp_addr   (exp_addr),
            .exp_wdata  (exp_wdata),
            .exp_wstrb  (exp_wstrb),
            .exp_size   (exp_size),

            .exp_ready  (exp_ready),
            .exp_rdata  (exp_rdata),
            .exp_error  (exp_error)
        );

    // =========================================================
    // IMEM síncrona real
    //
    // Configuración rápida ya validada:
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
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
    // Se fuerza deliberadamente:
    //
    //   2 ciclos de espera antes del grant
    //   3 ciclos de latencia hasta response
    //
    // Esto obliga al core a ejercer realmente:
    //
    //   WAIT_GNT
    //   WAIT_RESP
    //
    // =========================================================

        dmem_sync_model #(
            .MEM_WORDS  (DMEM_WORDS),
            .GNT_DELAY  (2),
            .RESP_DELAY (3),

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
    // Encoders mínimos RV64I
    // =========================================================

        function automatic logic [31:0] enc_i(
            input logic [11:0] imm,
            input logic [4:0]  rs1,
            input logic [2:0]  funct3,
            input logic [4:0]  rd,
            input logic [6:0]  opcode
        );
            begin
                enc_i = {
                    imm,
                    rs1,
                    funct3,
                    rd,
                    opcode
                };
            end
        endfunction

        function automatic logic [31:0] enc_s(
            input logic [11:0] imm,
            input logic [4:0]  rs2,
            input logic [4:0]  rs1,
            input logic [2:0]  funct3
        );
            begin
                enc_s = {
                    imm[11:5],
                    rs2,
                    rs1,
                    funct3,
                    imm[4:0],
                    OPCODE_STORE
                };
            end
        endfunction

        function automatic logic [31:0] enc_nop();
            begin
                enc_nop = 32'h0000_0013;
            end
        endfunction

        function automatic logic [31:0] enc_halt();
            begin
                // jal x0, 0
                enc_halt = 32'h0000_006f;
            end
        endfunction

    // =========================================================
    // Checks
    // =========================================================

    // ---------------------------------------------------------
    // Las asignaciones bloqueantes al contador "errors" son
    // intencionales.
    //
    // "errors" pertenece exclusivamente al scoreboard del
    // testbench y no representa estado RTL sintetizable.
    // Se utiliza actualización inmediata para permitir que
    // múltiples comprobaciones realizadas en un mismo ciclo
    // acumulen correctamente sus errores.
    //
    // La supresión se limita a esta región de verificación;
    // no se deshabilita BLKSEQ globalmente para el RTL.
    // ---------------------------------------------------------

    // verilator lint_save
    // verilator lint_off BLKSEQ

        integer errors;

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
    // Monitores de protocolo
    // =========================================================

        integer accepted_count;
        integer response_count;

        integer request_wait_cycles;
        integer response_wait_cycles;
        integer pipeline_wait_cycles;

        logic transaction_outstanding;

    // ---------------------------------------------------------
    // Comprobación de secuencia de transacciones.
    //
    // Programa esperado:
    //
    //   0: LD  0x100
    //   1: SD  0x108
    //   2: LD  0x108
    //   3: SD  0x110
    // ---------------------------------------------------------

        always @(posedge clk) begin
            if (rst) begin
                accepted_count          <= 0;
                response_count          <= 0;
                request_wait_cycles     <= 0;
                response_wait_cycles    <= 0;
                transaction_outstanding <= 1'b0;
            end
            else begin

                // ---------------------------------------------
                // El grant está siendo retrasado.
                // ---------------------------------------------
                    if (dmem_req && !dmem_gnt) begin
                        request_wait_cycles <=
                            request_wait_cycles + 1;
                    end

                // ---------------------------------------------
                // Existe una operación aceptada esperando
                // respuesta.
                // ---------------------------------------------
                    if (
                        transaction_outstanding &&
                        !dmem_rvalid
                    ) begin
                        response_wait_cycles <=
                            response_wait_cycles + 1;
                    end

                // ---------------------------------------------
                // Aceptación.
                // ---------------------------------------------
                    if (dmem_req && dmem_gnt) begin

                        if (transaction_outstanding) begin
                            $display(
                                "ERROR: se aceptó una segunda transacción mientras había una outstanding"
                            );

                            errors = errors + 1;
                        end

                        case (accepted_count)

                            // =====================================
                            // 0: LD x2, 0(x1)
                            // =====================================
                                0: begin
                                    check64(
                                        "TX0 address",
                                        dmem_addr,
                                        ADDR_SOURCE
                                    );

                                    if (dmem_we !== 1'b0) begin
                                        $display(
                                            "ERROR: TX0 debería ser LOAD"
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_wstrb !== 8'h00) begin
                                        $display(
                                            "ERROR: TX0 load wstrb=0x%02h expected=00",
                                            dmem_wstrb
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_size !== 2'b11) begin
                                        $display(
                                            "ERROR: TX0 size=%b expected=11 (LD)",
                                            dmem_size
                                        );
                                        errors = errors + 1;
                                    end
                                end

                            // =====================================
                            // 1: SD x3, 8(x1)
                            // =====================================
                                1: begin
                                    check64(
                                        "TX1 address",
                                        dmem_addr,
                                        ADDR_INTERMEDIATE
                                    );

                                    if (dmem_we !== 1'b1) begin
                                        $display(
                                            "ERROR: TX1 debería ser STORE"
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_wstrb !== 8'hFF) begin
                                        $display(
                                            "ERROR: TX1 wstrb=0x%02h expected=FF",
                                            dmem_wstrb
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_size !== 2'b11) begin
                                        $display(
                                            "ERROR: TX1 size=%b expected=11 (SD)",
                                            dmem_size
                                        );
                                        errors = errors + 1;
                                    end

                                    check64(
                                        "TX1 wdata",
                                        dmem_wdata,
                                        EXPECTED_INTERMEDIATE
                                    );
                                end

                            // =====================================
                            // 2: LD x4, 8(x1)
                            // =====================================
                                2: begin
                                    check64(
                                        "TX2 address",
                                        dmem_addr,
                                        ADDR_INTERMEDIATE
                                    );

                                    if (dmem_we !== 1'b0) begin
                                        $display(
                                            "ERROR: TX2 debería ser LOAD"
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_wstrb !== 8'h00) begin
                                        $display(
                                            "ERROR: TX2 load wstrb=0x%02h expected=00",
                                            dmem_wstrb
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_size !== 2'b11) begin
                                        $display(
                                            "ERROR: TX2 size=%b expected=11 (LD)",
                                            dmem_size
                                        );
                                        errors = errors + 1;
                                    end
                                end

                            // =====================================
                            // 3: SD x5, 16(x1)
                            // =====================================
                                3: begin
                                    check64(
                                        "TX3 address",
                                        dmem_addr,
                                        ADDR_RESULT
                                    );

                                    if (dmem_we !== 1'b1) begin
                                        $display(
                                            "ERROR: TX3 debería ser STORE"
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_wstrb !== 8'hFF) begin
                                        $display(
                                            "ERROR: TX3 wstrb=0x%02h expected=FF",
                                            dmem_wstrb
                                        );
                                        errors = errors + 1;
                                    end

                                    if (dmem_size !== 2'b11) begin
                                        $display(
                                            "ERROR: TX3 size=%b expected=11 (SD)",
                                            dmem_size
                                        );
                                        errors = errors + 1;
                                    end

                                    check64(
                                        "TX3 wdata",
                                        dmem_wdata,
                                        EXPECTED_RESULT
                                    );
                                end

                                default: begin
                                    $display(
                                        "ERROR: transacción DMEM inesperada #%0d addr=0x%016h we=%0b",
                                        accepted_count,
                                        dmem_addr,
                                        dmem_we
                                    );

                                    errors = errors + 1;
                                end

                        endcase

                        accepted_count <= accepted_count + 1;

                        transaction_outstanding <= 1'b1;
                    end

                // ---------------------------------------------
                // Respuesta.
                //
                // Debe corresponder siempre a una transacción
                // previamente aceptada.
                // ---------------------------------------------
                    if (dmem_rvalid) begin

                        if (!transaction_outstanding) begin
                            $display(
                                "ERROR: dmem_rvalid sin transacción outstanding"
                            );

                            errors = errors + 1;
                        end

                        if (dmem_error) begin
                            $display(
                                "ERROR: dmem_error inesperado"
                            );

                            errors = errors + 1;
                        end

                        response_count <= response_count + 1;

                        transaction_outstanding <= 1'b0;
                    end
            end
        end

    // =========================================================
    // Comprobación de stall real del pipeline
    // =========================================================

        logic [63:0] previous_pc;
        logic        previous_wait;

        always @(negedge clk) begin
            if (rst) begin
                previous_pc         <= 64'd0;
                previous_wait       <= 1'b0;
                pipeline_wait_cycles <= 0;
            end
            else begin

                if (dut.mem_dmem_wait_stall) begin
                    pipeline_wait_cycles <=
                        pipeline_wait_cycles + 1;
                end

                // Si seguimos en wait durante dos muestras
                // consecutivas, el PC no debe avanzar.
                if (
                    previous_wait &&
                    dut.mem_dmem_wait_stall
                ) begin
                    if (imem_addr !== previous_pc) begin
                        $display(
                            "ERROR: PC cambió durante DMEM stall: old=0x%016h new=0x%016h",
                            previous_pc,
                            imem_addr
                        );

                        errors = errors + 1;
                    end
                end

                previous_pc   <= imem_addr;
                previous_wait <= dut.mem_dmem_wait_stall;
            end
        end

    // =========================================================
    // MMIO no debe utilizarse
    // =========================================================

        always @(posedge clk) begin
            if (!rst && exp_valid) begin
                $display(
                    "ERROR: acceso inesperado a región MMIO addr=0x%016h",
                    exp_addr
                );

                errors = errors + 1;
            end
        end

    // verilator lint_restore

    // =========================================================
    // Programa
    // =========================================================

        integer i;

        initial begin

            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                u_imem.mem[i] = enc_nop();
            end

            // -----------------------------------------------------
            // Programa:
            //
            // x1 = 0x100
            //
            // LD x2, 0(x1)
            //     x2 = INITIAL_VALUE
            //
            // ADDI x3, x2, 1
            //     valida load-use después de memoria con wait-state
            //
            // SD x3, 8(x1)
            //
            // LD x4, 8(x1)
            //
            // ADDI x5, x4, 2
            //     segundo load-use
            //
            // SD x5, 16(x1)
            //
            // loop
            // -----------------------------------------------------

            u_imem.mem[0] =
                enc_i(
                    12'h100,
                    5'd0,
                    F3_ADDI,
                    5'd1,
                    OPCODE_OP_IMM
                );

            // Evitamos mezclar en esta prueba la generación de la
            // dirección base con hazards adicionales.
            u_imem.mem[1] = enc_nop();
            u_imem.mem[2] = enc_nop();

            // LD x2, 0(x1)
            u_imem.mem[3] =
                enc_i(
                    12'h000,
                    5'd1,
                    F3_LD,
                    5'd2,
                    OPCODE_LOAD
                );

            // ADDI x3, x2, 1
            //
            // Intencionalmente inmediatamente después del LD.
            u_imem.mem[4] =
                enc_i(
                    12'h001,
                    5'd2,
                    F3_ADDI,
                    5'd3,
                    OPCODE_OP_IMM
                );

            u_imem.mem[5] = enc_nop();
            u_imem.mem[6] = enc_nop();

            // SD x3, 8(x1)
            u_imem.mem[7] =
                enc_s(
                    12'h008,
                    5'd3,
                    5'd1,
                    F3_SD
                );

            // LD x4, 8(x1)
            u_imem.mem[8] =
                enc_i(
                    12'h008,
                    5'd1,
                    F3_LD,
                    5'd4,
                    OPCODE_LOAD
                );

            // ADDI x5, x4, 2
            u_imem.mem[9] =
                enc_i(
                    12'h002,
                    5'd4,
                    F3_ADDI,
                    5'd5,
                    OPCODE_OP_IMM
                );

            u_imem.mem[10] = enc_nop();
            u_imem.mem[11] = enc_nop();

            // SD x5, 16(x1)
            u_imem.mem[12] =
                enc_s(
                    12'h010,
                    5'd5,
                    5'd1,
                    F3_SD
                );

            u_imem.mem[13] = enc_halt();
        end

    // =========================================================
    // Test principal
    // =========================================================

        integer cycles;

        initial begin

            $dumpfile(
                "build/tb_core_dmem_sync.vcd"
            );

            $dumpvars(
                0,
                tb_core_dmem_sync
            );

            errors = 0;

            rst = 1'b1;

            // -----------------------------------------------------
            // Precarga de DMEM.
            //
            // No se realiza durante reset.
            // El modelo conserva contenido a través de reset.
            // -----------------------------------------------------

            u_dmem.mem[ADDR_SOURCE[12:3]] =
                INITIAL_VALUE;

            u_dmem.mem[ADDR_INTERMEDIATE[12:3]] =
                64'd0;

            u_dmem.mem[ADDR_RESULT[12:3]] =
                64'd0;

            // -----------------------------------------------------
            // Reset
            // -----------------------------------------------------

            repeat (5) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            // -----------------------------------------------------
            // Esperar cuatro respuestas DMEM.
            //
            // No terminamos simplemente al observar el último store,
            // porque queremos comprobar también que el core recibió
            // su respuesta de finalización.
            // -----------------------------------------------------

            cycles = 0;

            while (
                (response_count < 4) &&
                (cycles < 500)
            ) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            // Dejar terminar WB y alcanzar el loop.
            repeat (10) @(posedge clk);
            #1;

            $display("");
            $display("==============================================");
            $display("CORE + DMEM SYNC INTEGRATION");
            $display("==============================================");

            // -----------------------------------------------------
            // Transacciones
            // -----------------------------------------------------

            check_int(
                "transacciones aceptadas",
                accepted_count,
                4
            );

            check_int(
                "respuestas recibidas",
                response_count,
                4
            );

            // -----------------------------------------------------
            // Debemos haber ejercitado de verdad ambos tipos de
            // wait-state.
            // -----------------------------------------------------

            if (request_wait_cycles <= 0) begin
                $display(
                    "ERROR: no se observaron ciclos WAIT_GNT"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : WAIT_GNT observado durante %0d ciclos",
                    request_wait_cycles
                );
            end

            if (response_wait_cycles <= 0) begin
                $display(
                    "ERROR: no se observaron ciclos WAIT_RESP"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : WAIT_RESP observado durante %0d ciclos",
                    response_wait_cycles
                );
            end

            if (pipeline_wait_cycles <= 0) begin
                $display(
                    "ERROR: no se observó mem_dmem_wait_stall"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : pipeline detenido durante %0d muestras",
                    pipeline_wait_cycles
                );
            end

            // -----------------------------------------------------
            // Estado de registros
            // -----------------------------------------------------

            check64(
                "x1 base DMEM",
                dut.u_regfile.regs[1],
                DATA_BASE
            );

            check64(
                "x2 load inicial",
                dut.u_regfile.regs[2],
                INITIAL_VALUE
            );

            check64(
                "x3 load-use + 1",
                dut.u_regfile.regs[3],
                EXPECTED_INTERMEDIATE
            );

            check64(
                "x4 reload",
                dut.u_regfile.regs[4],
                EXPECTED_INTERMEDIATE
            );

            check64(
                "x5 segundo load-use + 2",
                dut.u_regfile.regs[5],
                EXPECTED_RESULT
            );

            // -----------------------------------------------------
            // Estado de memoria
            // -----------------------------------------------------

            check64(
                "DMEM source intacto",
                u_dmem.mem[ADDR_SOURCE[12:3]],
                INITIAL_VALUE
            );

            check64(
                "DMEM intermediate",
                u_dmem.mem[ADDR_INTERMEDIATE[12:3]],
                EXPECTED_INTERMEDIATE
            );

            check64(
                "DMEM result",
                u_dmem.mem[ADDR_RESULT[12:3]],
                EXPECTED_RESULT
            );

            // -----------------------------------------------------
            // No debe quedar nada outstanding.
            // -----------------------------------------------------

            if (transaction_outstanding !== 1'b0) begin
                $display(
                    "ERROR: quedó una transacción outstanding"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : no quedan transacciones outstanding"
                );
            end

            // -----------------------------------------------------
            // Resultado
            // -----------------------------------------------------

            $display("==============================================");

            if (errors == 0) begin
                $display(
                    "PASS: core_top + dmem_sync_model funcionando"
                );
            end
            else begin
                $display(
                    "FAIL: core_top + dmem_sync_model errors=%0d",
                    errors
                );
            end

            $display("==============================================");

            if (errors != 0) begin
                $fatal(
                    1,
                    "tb_core_dmem_sync falló"
                );
            end

            $finish;
        end

    // =========================================================
    // Timeout global
    // =========================================================

        initial begin
            #20000;

            $fatal(
                1,
                "TIMEOUT: tb_core_dmem_sync no terminó"
            );
        end

    // =========================================================
    // Salidas no utilizadas explícitamente por este TB.
    //
    // Se consumen para facilitar lint.
    // =========================================================

        wire _unused_ok = 1'b0 && &{
            1'b0,
            exp_we,
            exp_wdata,
            exp_wstrb,
            exp_size,
            1'b0
        };

endmodule
