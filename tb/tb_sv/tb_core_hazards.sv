// COMPILACIÓN PRINCIPAL:
//   make tb_core_hazards
//
// Objetivo:
//
//   - forwarding ALU -> ALU
//   - forwarding combinado
//   - store hacia DMEM
//   - load desde DMEM síncrona
//   - load-use stall
//   - forwarding posterior al load
//
// La DMEM utiliza el protocolo definitivo:
//
//   request -> grant -> response
//
// y deliberadamente introduce latencia tanto antes del grant
// como antes de la respuesta.

`timescale 1ns/1ps

module tb_core_hazards;

    // =========================================================
    // Configuración
    // =========================================================

    localparam int unsigned IMEM_WORDS = 256;
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
    // DMEM
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
    // =========================================================

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
    // IMEM síncrona real
    //
    // Configuración rápida ya validada:
    //
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    //
    // El controlador y el modelo soportan turnover, por lo que
    // después del llenado inicial puede mantenerse un fetch/ciclo.
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
    // DMEM síncrona real
    //
    // Se utilizan wait-states deliberadamente:
    //
    // GNT_DELAY = 2
    //   La petición debe permanecer estable mientras espera grant.
    //
    // RESP_DELAY = 2
    //   Después del grant existe además espera de respuesta.
    //
    // Esto permite verificar la interacción:
    //
    //   MEM wait-state + load-use + forwarding
    //
    // sin modificar el RTL.
    // =========================================================

        dmem_sync_model #(
            .MEM_WORDS    (DMEM_WORDS),
            .GNT_DELAY    (2),
            .RESP_DELAY   (2),
            .FAULT_ENABLE (1'b0)
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
    // Monitores
    // =========================================================

        integer hazard_count;

        integer accepted_count;
        integer response_count;

        integer store_accept_count;
        integer load_accept_count;

        integer wait_gnt_cycles;
        integer wait_resp_cycles;

    // ---------------------------------------------------------
    // La diferencia fundamental respecto al TB legacy:
    //
    // NO contamos un store mediante:
    //
    //     if (dmem_we)
    //
    // porque dmem_we es un atributo de la petición y puede
    // permanecer activo durante WAIT_GNT.
    //
    // Una operación existe arquitectónicamente solo cuando:
    //
    //     dmem_req && dmem_gnt
    // ---------------------------------------------------------

        always @(posedge clk) begin
            if (rst) begin
                accepted_count     <= 0;
                response_count     <= 0;

                store_accept_count <= 0;
                load_accept_count  <= 0;

                wait_gnt_cycles    <= 0;
                wait_resp_cycles   <= 0;
            end
            else begin

                // -------------------------------------------------
                // Request esperando grant
                // -------------------------------------------------

                if (dmem_req && !dmem_gnt)
                    wait_gnt_cycles <= wait_gnt_cycles + 1;

                // -------------------------------------------------
                // Espera posterior al grant
                //
                // El controlador ya retiró req, pero MEM continúa
                // detenida esperando rvalid.
                // -------------------------------------------------

                if (
                    dut.mem_dmem_wait_stall &&
                    !dmem_req &&
                    !dmem_rvalid
                )
                    wait_resp_cycles <= wait_resp_cycles + 1;

                // -------------------------------------------------
                // Petición aceptada
                // -------------------------------------------------

                if (dmem_req && dmem_gnt) begin

                    accepted_count <= accepted_count + 1;

                    // Todo acceso de este programa es a addr 0.
                    if (dmem_addr !== 64'd0) begin
                        $fatal(
                            1,
                            "FAIL: acceso DMEM addr=0x%016h esperado=0",
                            dmem_addr
                        );
                    end

                    // Todos los accesos son de 64 bits.
                    if (dmem_size !== 2'b11) begin
                        $fatal(
                            1,
                            "FAIL: dmem_size=%b esperado=11",
                            dmem_size
                        );
                    end

                    if (dmem_we) begin

                        store_accept_count <=
                            store_accept_count + 1;

                        if (dmem_wdata !== 64'd29) begin
                            $fatal(
                                1,
                                "FAIL: store wdata=%0d esperado=29",
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

                        $display(
                            "[%0t] STORE ACCEPTED addr=%0d data=%0d",
                            $time,
                            dmem_addr,
                            dmem_wdata
                        );
                    end
                    else begin
                        load_accept_count <=
                            load_accept_count + 1;

                        if (dmem_wstrb !== 8'h00) begin
                            $fatal(
                                1,
                                "FAIL: load con wstrb distinto de cero: 0x%02h",
                                dmem_wstrb
                            );
                        end

                        $display(
                            "[%0t] LOAD ACCEPTED addr=%0d",
                            $time,
                            dmem_addr
                        );
                    end
                end

                // -------------------------------------------------
                // Respuesta
                // -------------------------------------------------

                if (dmem_rvalid) begin

                    response_count <= response_count + 1;

                    if (dmem_error) begin
                        $fatal(
                            1,
                            "FAIL: transaccion DMEM terminó con error"
                        );
                    end
                end
            end
        end

    // =========================================================
    // Programa de prueba
    //
    // 0x000: addi x1,  x0, 5
    // 0x004: addi x2,  x0, 7
    // 0x008: add  x3,  x1, x2      -> 12
    // 0x00C: add  x4,  x3, x1      -> 17
    // 0x010: add  x5,  x4, x3      -> 29
    //
    // 0x014: sd   x5,  0(x0)       -> mem[0] = 29
    //
    // 0x018: ld   x6,  0(x0)       -> 29
    // 0x01C: addi x7,  x6, 1       -> 30
    //          ^ load-use #1
    //
    // 0x020: add  x8,  x7, x6      -> 59
    //
    // 0x024: ld   x9,  0(x0)       -> 29
    // 0x028: add  x10, x8, x9      -> 88
    //          ^ load-use #2
    //
    // 0x02C: addi x11, x0, 1       -> PASS flag
    // 0x030: jal  x0,  0
    // =========================================================

        integer i;
        integer cycle;

        initial begin

            $dumpfile("build/tb_core_hazards.vcd");
            $dumpvars(0, tb_core_hazards);

            // -----------------------------------------------------
            // Inicialización
            // -----------------------------------------------------

            for (i = 0; i < IMEM_WORDS; i = i + 1)
                u_imem.mem[i] = 32'h0000_0013;

            // Estado inicial determinista de la línea utilizada.
            //
            // dmem_sync_model deliberadamente no borra memoria con
            // reset, por lo que la inicializamos desde el TB.
            u_dmem.mem[0] = 64'd0;

            hazard_count = 0;

            accepted_count     = 0;
            response_count     = 0;

            store_accept_count = 0;
            load_accept_count  = 0;

            wait_gnt_cycles    = 0;
            wait_resp_cycles   = 0;

            // -----------------------------------------------------
            // Programa
            // -----------------------------------------------------

            u_imem.mem[0]  = 32'h0050_0093; // addi x1,  x0, 5
            u_imem.mem[1]  = 32'h0070_0113; // addi x2,  x0, 7
            u_imem.mem[2]  = 32'h0020_81b3; // add  x3,  x1, x2
            u_imem.mem[3]  = 32'h0011_8233; // add  x4,  x3, x1
            u_imem.mem[4]  = 32'h0032_02b3; // add  x5,  x4, x3

            u_imem.mem[5]  = 32'h0050_3023; // sd   x5, 0(x0)

            u_imem.mem[6]  = 32'h0000_3303; // ld   x6, 0(x0)
            u_imem.mem[7]  = 32'h0013_0393; // addi x7, x6, 1

            u_imem.mem[8]  = 32'h0063_8433; // add  x8, x7, x6

            u_imem.mem[9]  = 32'h0000_3483; // ld   x9, 0(x0)
            u_imem.mem[10] = 32'h0094_0533; // add  x10, x8, x9

            u_imem.mem[11] = 32'h0010_0593; // addi x11, x0, 1
            u_imem.mem[12] = 32'h0000_006f; // jal  x0, 0

            // -----------------------------------------------------
            // Reset
            // -----------------------------------------------------

            rst = 1'b1;

            repeat (5) @(posedge clk);

            // Evitar carrera TB/DUT al retirar reset.
            @(negedge clk);
            rst = 1'b0;

            // -----------------------------------------------------
            // Ejecución
            //
            // Se aumenta el límite respecto de la versión legacy
            // porque ahora las tres transacciones de memoria tienen
            // WAIT_GNT y WAIT_RESP reales.
            // -----------------------------------------------------

            for (
                cycle = 0;
                cycle < 240;
                cycle = cycle + 1
            ) begin

                @(posedge clk);

                // -------------------------------------------------
                // Contar únicamente el stall load-use EFECTIVO.
                //
                // load_use_hazard puede permanecer verdadero mientras
                // una operación más antigua mantiene MEM congelada.
                //
                // data_hazard_stall, en cambio, es la inserción real
                // de una burbuja por load-use.
                // -------------------------------------------------

                if (dut.data_hazard_stall)
                    hazard_count = hazard_count + 1;

                // -------------------------------------------------
                // PASS flag
                // -------------------------------------------------

                if (dut.u_regfile.regs[11] == 64'd1) begin

                    // =============================================
                    // Forwarding previo a memoria
                    // =============================================

                    if (dut.u_regfile.regs[3] !== 64'd12) begin
                        $fatal(
                            1,
                            "FAIL: x3 got=%0d exp=12",
                            dut.u_regfile.regs[3]
                        );
                    end

                    if (dut.u_regfile.regs[4] !== 64'd17) begin
                        $fatal(
                            1,
                            "FAIL: x4 got=%0d exp=17",
                            dut.u_regfile.regs[4]
                        );
                    end

                    if (dut.u_regfile.regs[5] !== 64'd29) begin
                        $fatal(
                            1,
                            "FAIL: x5 got=%0d exp=29",
                            dut.u_regfile.regs[5]
                        );
                    end

                    // =============================================
                    // Store físico
                    // =============================================

                    if (u_dmem.mem[0] !== 64'd29) begin
                        $fatal(
                            1,
                            "FAIL: DMEM[0] got=%0d exp=29",
                            u_dmem.mem[0]
                        );
                    end

                    // =============================================
                    // Primer load-use
                    // =============================================

                    if (dut.u_regfile.regs[6] !== 64'd29) begin
                        $fatal(
                            1,
                            "FAIL: x6 got=%0d exp=29",
                            dut.u_regfile.regs[6]
                        );
                    end

                    if (dut.u_regfile.regs[7] !== 64'd30) begin
                        $fatal(
                            1,
                            "FAIL: x7 got=%0d exp=30",
                            dut.u_regfile.regs[7]
                        );
                    end

                    if (dut.u_regfile.regs[8] !== 64'd59) begin
                        $fatal(
                            1,
                            "FAIL: x8 got=%0d exp=59",
                            dut.u_regfile.regs[8]
                        );
                    end

                    // =============================================
                    // Segundo load-use
                    // =============================================

                    if (dut.u_regfile.regs[9] !== 64'd29) begin
                        $fatal(
                            1,
                            "FAIL: x9 got=%0d exp=29",
                            dut.u_regfile.regs[9]
                        );
                    end

                    if (dut.u_regfile.regs[10] !== 64'd88) begin
                        $fatal(
                            1,
                            "FAIL: x10 got=%0d exp=88",
                            dut.u_regfile.regs[10]
                        );
                    end

                    // =============================================
                    // Protocolo DMEM
                    //
                    // Exactamente:
                    //
                    //   SD
                    //   LD
                    //   LD
                    //
                    // = 3 transacciones.
                    // =============================================

                    if (accepted_count !== 3) begin
                        $fatal(
                            1,
                            "FAIL: accepted_count=%0d exp=3",
                            accepted_count
                        );
                    end

                    if (response_count !== 3) begin
                        $fatal(
                            1,
                            "FAIL: response_count=%0d exp=3",
                            response_count
                        );
                    end

                    if (store_accept_count !== 1) begin
                        $fatal(
                            1,
                            "FAIL: store_accept_count=%0d exp=1",
                            store_accept_count
                        );
                    end

                    if (load_accept_count !== 2) begin
                        $fatal(
                            1,
                            "FAIL: load_accept_count=%0d exp=2",
                            load_accept_count
                        );
                    end

                    // =============================================
                    // Load-use
                    //
                    // Debe haber exactamente dos inserciones reales
                    // de burbuja, aunque load_use_hazard pueda estar
                    // visible durante un wait-state más antiguo.
                    // =============================================

                    if (hazard_count !== 2) begin
                        $fatal(
                            1,
                            "FAIL: hazard_count=%0d exp=2",
                            hazard_count
                        );
                    end

                    // =============================================
                    // Confirmar que la prueba realmente ejerció
                    // ambas clases de espera.
                    // =============================================

                    if (wait_gnt_cycles == 0) begin
                        $fatal(
                            1,
                            "FAIL: no se observó WAIT_GNT"
                        );
                    end

                    if (wait_resp_cycles == 0) begin
                        $fatal(
                            1,
                            "FAIL: no se observó WAIT_RESP"
                        );
                    end

                    // =============================================
                    // Resultado
                    // =============================================

                    $display("");
                    $display("==============================================");
                    $display("PASS: hazards + DMEM síncrona funcionando");
                    $display("==============================================");

                    $display(
                        "      x3  = %0d",
                        dut.u_regfile.regs[3]
                    );

                    $display(
                        "      x4  = %0d",
                        dut.u_regfile.regs[4]
                    );

                    $display(
                        "      x5  = %0d",
                        dut.u_regfile.regs[5]
                    );

                    $display(
                        "      x6  = %0d",
                        dut.u_regfile.regs[6]
                    );

                    $display(
                        "      x7  = %0d",
                        dut.u_regfile.regs[7]
                    );

                    $display(
                        "      x8  = %0d",
                        dut.u_regfile.regs[8]
                    );

                    $display(
                        "      x9  = %0d",
                        dut.u_regfile.regs[9]
                    );

                    $display(
                        "      x10 = %0d",
                        dut.u_regfile.regs[10]
                    );

                    $display(
                        "      DMEM[0] = %0d",
                        u_dmem.mem[0]
                    );

                    $display(
                        "      accepted = %0d",
                        accepted_count
                    );

                    $display(
                        "      responses = %0d",
                        response_count
                    );

                    $display(
                        "      stores = %0d",
                        store_accept_count
                    );

                    $display(
                        "      loads = %0d",
                        load_accept_count
                    );

                    $display(
                        "      hazard_count = %0d",
                        hazard_count
                    );

                    $display(
                        "      WAIT_GNT cycles = %0d",
                        wait_gnt_cycles
                    );

                    $display(
                        "      WAIT_RESP cycles = %0d",
                        wait_resp_cycles
                    );

                    $display(
                        "      dmem_legacy_compat ya no utilizado"
                    );

                    $display("==============================================");

                    $finish;
                end
            end

            $fatal(
                1,
                "FAIL: timeout. El programa no alcanzó x11=1"
            );
        end

endmodule
