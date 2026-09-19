`timescale 1ns/1ps

// ============================================================
// tb_core_hazard_branch
//
// Verifica conjuntamente:
//
//   - store hacia DMEM síncrona
//   - load desde DMEM síncrona
//   - load-use hazard
//   - forwarding posterior al load
//   - forwarding hacia una comparación de branch
//   - branch tomado
//   - flush de instrucciones jóvenes del camino incorrecto
//
// Programa:
//
//   0x00: addi x4, x0, 9
//   0x04: sd   x4, 0(x0)
//   0x08: ld   x1, 0(x0)
//   0x0c: add  x2, x1, x1       -> 18
//   0x10: addi x6, x0, 18
//   0x14: beq  x2, x6, +8       -> tomado, target 0x1c
//   0x18: addi x3, x0, 99       -> debe ser eliminado
//   0x1c: addi x3, x0, 42       -> debe ejecutarse
//   0x20: jal  x0, 0
//
// RISC-V no posee branch delay slots. La instrucción de 0x18
// es simplemente una instrucción joven del camino secuencial
// que debe ser flusheada cuando el BEQ tomado redirige a 0x1c.
// ============================================================

module tb_core_hazard_branch;

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
    //
    // Se utiliza la configuración de menor latencia:
    //
    //   GNT_DELAY  = 0
    //   RESP_DELAY = 1
    //
    // Con el turnover del controlador y del modelo, después del
    // llenado inicial puede mantenerse un fetch por ciclo.
    //
    // Esto es importante para que la IMEM no introduzca burbujas
    // artificiales que oculten el load-use:
    //
    //   ld  x1, 0(x0)
    //   add x2, x1, x1
    //
    // El objetivo de este test sigue siendo observar exactamente
    // un hazard efectivo.
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
    // DUT
    // =========================================================

        // =========================================================
        // ORE TO
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
        // IMEM síncrona real
        //
        // Grant inmediato y respuesta de un ciclo.
        //
        // Gracias al turnover:
        //
        //   response actual + next request
        //
        // pueden ocurrir en el mismo ciclo, manteniendo un fetch
        // por ciclo después del llenado inicial.
        // =========================================================

            imem_sync_model #(
                .MEM_WORDS (IMEM_WORDS),
                .GNT_DELAY (0),
                .RESP_DELAY(1)
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
        // Existen exactamente dos transacciones:
        //
        //   1) SD
        //   2) LD
        //
        // GNT_DELAY=2 obliga al core a mantener estable la petición.
        //
        // RESP_DELAY=2 introduce además espera después de la
        // aceptación y antes de dmem_rvalid.
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

        integer accepted_count;
        integer response_count;

        integer store_accept_count;
        integer load_accept_count;

        integer wait_gnt_cycles;
        integer wait_resp_cycles;

        integer hazard_count;
        integer branch_taken_count;

        always @(posedge clk) begin
            if (rst) begin
                accepted_count     <= 0;
                response_count     <= 0;

                store_accept_count <= 0;
                load_accept_count  <= 0;

                wait_gnt_cycles    <= 0;
                wait_resp_cycles   <= 0;

                hazard_count       <= 0;
                branch_taken_count <= 0;
            end
            else begin

                // =================================================
                // Wait-state antes del grant
                // =================================================

                if (dmem_req && !dmem_gnt) begin
                    wait_gnt_cycles <= wait_gnt_cycles + 1;
                end

                // =================================================
                // Wait-state posterior al grant
                //
                // req ya desapareció, pero MEM todavía espera
                // dmem_rvalid.
                // =================================================

                if (
                    dut.mem_dmem_wait_stall &&
                    !dmem_req &&
                    !dmem_rvalid
                ) begin
                    wait_resp_cycles <= wait_resp_cycles + 1;
                end

                // =================================================
                // Petición DMEM aceptada
                // =================================================

                if (dmem_req && dmem_gnt) begin

                    accepted_count <= accepted_count + 1;

                    if (dmem_addr !== 64'd0) begin
                        $fatal(
                            1,
                            "FAIL: acceso DMEM addr=0x%016h esperado=0",
                            dmem_addr
                        );
                    end

                    if (dmem_size !== 2'b11) begin
                        $fatal(
                            1,
                            "FAIL: dmem_size=%b esperado=11",
                            dmem_size
                        );
                    end

                    // ---------------------------------------------
                    // STORE
                    // ---------------------------------------------

                    if (dmem_we) begin

                        store_accept_count <=
                            store_accept_count + 1;

                        if (dmem_wdata !== 64'd9) begin
                            $fatal(
                                1,
                                "FAIL: store wdata=%0d esperado=9",
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

                    // ---------------------------------------------
                    // LOAD
                    // ---------------------------------------------

                    else begin

                        load_accept_count <=
                            load_accept_count + 1;

                        if (dmem_wstrb !== 8'h00) begin
                            $fatal(
                                1,
                                "FAIL: load wstrb=0x%02h esperado=0",
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

                // =================================================
                // Respuesta DMEM
                // =================================================

                if (dmem_rvalid) begin

                    response_count <= response_count + 1;

                    if (dmem_error) begin
                        $fatal(
                            1,
                            "FAIL: transaccion DMEM terminó con error"
                        );
                    end
                end

                // =================================================
                // Load-use efectivo
                //
                // Contamos data_hazard_stall y no load_use_hazard
                // porque este último puede permanecer visible
                // mientras un stall MEM más antiguo domina.
                // =================================================

                if (dut.data_hazard_stall) begin
                    hazard_count <= hazard_count + 1;
                end

                // =================================================
                // Branch concreto de PC=0x14
                //
                // No contamos el JAL x0,0 final.
                // =================================================

                if (
                    dut.control_redirect &&
                    dut.ex_valid_out &&
                    (dut.ex_pc_out == 64'h0000_0000_0000_0014) &&
                    dut.ex_take_pc_redirect
                ) begin

                    branch_taken_count <=
                        branch_taken_count + 1;

                    if (
                        dut.ex_redirect_target !==
                        64'h0000_0000_0000_001c
                    ) begin
                        $fatal(
                            1,
                            "FAIL: branch target=0x%016h esperado=0x1c",
                            dut.ex_redirect_target
                        );
                    end

                    $display(
                        "[%0t] BRANCH TAKEN pc=0x%016h target=0x%016h",
                        $time,
                        dut.ex_pc_out,
                        dut.ex_redirect_target
                    );
                end

                // =================================================
                // Comprobación fuerte del flush
                //
                // El resultado final x3=42 no basta por sí solo:
                // x3=99 podría haberse escrito incorrectamente y
                // luego ser sobrescrito por 42.
                //
                // Si la instrucción de 0x18 alcanza WB, el test debe
                // fallar inmediatamente.
                // =================================================

                if (
                    dut.wb_commit_we &&
                    (dut.wb_commit_rd_addr == 5'd3) &&
                    (dut.wb_commit_rd_data == 64'd99)
                ) begin
                    $fatal(
                        1,
                        "FAIL: la instruccion joven x3=99 no fue flusheada"
                    );
                end
            end
        end

    // =========================================================
    // Programa / secuencia
    // =========================================================

        integer i;
        integer timeout;

        initial begin

            $dumpfile("build/tb_core_hazard_branch.vcd");
            $dumpvars(0, tb_core_hazard_branch);

            // -----------------------------------------------------
            // Inicialización
            // -----------------------------------------------------

            rst = 1'b1;

            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                u_imem.mem[i] = 32'h0000_0013;
            end

            // dmem_sync_model no borra memoria durante reset.
            u_dmem.mem[0] = 64'd0;

            // -----------------------------------------------------
            // Programa
            // -----------------------------------------------------

            u_imem.mem[0] = 32'h0090_0213; // addi x4, x0, 9
            u_imem.mem[1] = 32'h0040_3023; // sd   x4, 0(x0)
            u_imem.mem[2] = 32'h0000_3083; // ld   x1, 0(x0)
            u_imem.mem[3] = 32'h0010_8133; // add  x2, x1, x1
            u_imem.mem[4] = 32'h0120_0313; // addi x6, x0, 18
            u_imem.mem[5] = 32'h0061_0463; // beq  x2, x6, +8
            u_imem.mem[6] = 32'h0630_0193; // addi x3, x0, 99 (flush)
            u_imem.mem[7] = 32'h02a0_0193; // addi x3, x0, 42
            u_imem.mem[8] = 32'h0000_006f; // jal  x0, 0

            // -----------------------------------------------------
            // Reset
            // -----------------------------------------------------

            repeat (5) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;
            #1;

            // -----------------------------------------------------
            // Esperar a que el camino correcto escriba x3=42.
            // -----------------------------------------------------

            timeout = 0;

            while (
                (dut.u_regfile.regs[3] !== 64'd42) &&
                (timeout < 250)
            ) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (dut.u_regfile.regs[3] !== 64'd42) begin
                $fatal(
                    1,
                    "FAIL: timeout esperando x3=42"
                );
            end

            // Dejar estabilizar contadores y llegar al loop final.
            repeat (5) @(posedge clk);

            // =====================================================
            // Checks arquitecturales
            // =====================================================

            if (dut.u_regfile.regs[4] !== 64'd9) begin
                $fatal(
                    1,
                    "FAIL: x4=%0d esperado=9",
                    dut.u_regfile.regs[4]
                );
            end

            if (u_dmem.mem[0] !== 64'd9) begin
                $fatal(
                    1,
                    "FAIL: DMEM[0]=%0d esperado=9",
                    u_dmem.mem[0]
                );
            end

            if (dut.u_regfile.regs[1] !== 64'd9) begin
                $fatal(
                    1,
                    "FAIL: x1=%0d esperado=9",
                    dut.u_regfile.regs[1]
                );
            end

            if (dut.u_regfile.regs[2] !== 64'd18) begin
                $fatal(
                    1,
                    "FAIL: x2=%0d esperado=18",
                    dut.u_regfile.regs[2]
                );
            end

            if (dut.u_regfile.regs[6] !== 64'd18) begin
                $fatal(
                    1,
                    "FAIL: x6=%0d esperado=18",
                    dut.u_regfile.regs[6]
                );
            end

            if (dut.u_regfile.regs[3] !== 64'd42) begin
                $fatal(
                    1,
                    "FAIL: x3=%0d esperado=42",
                    dut.u_regfile.regs[3]
                );
            end

            // =====================================================
            // Checks del protocolo
            //
            // Programa:
            //
            //   1 SD
            //   1 LD
            //
            // = 2 transacciones.
            // =====================================================

            if (accepted_count !== 2) begin
                $fatal(
                    1,
                    "FAIL: accepted_count=%0d esperado=2",
                    accepted_count
                );
            end

            if (response_count !== 2) begin
                $fatal(
                    1,
                    "FAIL: response_count=%0d esperado=2",
                    response_count
                );
            end

            if (store_accept_count !== 1) begin
                $fatal(
                    1,
                    "FAIL: store_accept_count=%0d esperado=1",
                    store_accept_count
                );
            end

            if (load_accept_count !== 1) begin
                $fatal(
                    1,
                    "FAIL: load_accept_count=%0d esperado=1",
                    load_accept_count
                );
            end

            // =====================================================
            // Con GNT_DELAY=2 y dos transacciones:
            //
            //   2 ciclos WAIT_GNT por operación
            //   => 4 en total.
            //
            // Con RESP_DELAY=2 se observa un ciclo completo
            // WAIT_RESP sin rvalid por operación:
            //   => 2 en total.
            // =====================================================

            if (wait_gnt_cycles !== 4) begin
                $fatal(
                    1,
                    "FAIL: WAIT_GNT cycles=%0d esperado=4",
                    wait_gnt_cycles
                );
            end

            if (wait_resp_cycles !== 2) begin
                $fatal(
                    1,
                    "FAIL: WAIT_RESP cycles=%0d esperado=2",
                    wait_resp_cycles
                );
            end

            // =====================================================
            // Hay exactamente un load-use:
            //
            //   ld x1
            //   add x2, x1, x1
            //
            // =====================================================

            if (hazard_count !== 1) begin
                $fatal(
                    1,
                    "FAIL: hazard_count=%0d esperado=1",
                    hazard_count
                );
            end

            // =====================================================
            // El BEQ de 0x14 debe tomarse exactamente una vez.
            //
            // El JAL final no entra en este contador.
            // =====================================================

            if (branch_taken_count !== 1) begin
                $fatal(
                    1,
                    "FAIL: branch_taken_count=%0d esperado=1",
                    branch_taken_count
                );
            end

            // No debe quedar una transacción pendiente.
            if (dut.mem_dmem_wait_stall) begin
                $fatal(
                    1,
                    "FAIL: queda una transaccion DMEM pendiente"
                );
            end

            // =====================================================
            // PASS
            // =====================================================

            $display("");
            $display("==============================================");
            $display("PASS: hazard + branch + DMEM síncrona");
            $display("==============================================");
            $display("      DMEM[0] = %0d", u_dmem.mem[0]);
            $display("      x1 = %0d", dut.u_regfile.regs[1]);
            $display("      x2 = %0d", dut.u_regfile.regs[2]);
            $display("      x3 = %0d", dut.u_regfile.regs[3]);
            $display("      x4 = %0d", dut.u_regfile.regs[4]);
            $display("      x6 = %0d", dut.u_regfile.regs[6]);
            $display("      accepted = %0d", accepted_count);
            $display("      responses = %0d", response_count);
            $display("      stores = %0d", store_accept_count);
            $display("      loads = %0d", load_accept_count);
            $display("      hazard_count = %0d", hazard_count);
            $display("      branch_taken_count = %0d", branch_taken_count);
            $display("      WAIT_GNT cycles = %0d", wait_gnt_cycles);
            $display("      WAIT_RESP cycles = %0d", wait_resp_cycles);
            $display("      wrong-path x3=99 nunca alcanzó WB");
            $display("      dmem_legacy_compat ya no utilizado");
            $display("==============================================");

            $finish;
        end

endmodule
