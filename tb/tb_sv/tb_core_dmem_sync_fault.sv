`timescale 1ns/1ps

module tb_core_dmem_sync_fault;

    // =========================================================
    // Configuración
    // =========================================================

        localparam int unsigned IMEM_WORDS = 256;
        localparam int unsigned DMEM_WORDS = 256;

        localparam logic [63:0] RESET_PC =
            64'h0000_0000_0000_0000;

        localparam logic [63:0] TRAP_VECTOR =
            64'h0000_0000_0000_0100;

        localparam logic [63:0] FAULT_ADDR =
            64'h0000_0000_0000_0080;

    // ---------------------------------------------------------
    // Memoria donde el programa guarda evidencia después
    // de regresar del trap.
    // ---------------------------------------------------------

        localparam logic [63:0] ADDR_MCAUSE =
            64'h0000_0000_0000_0100;

        localparam logic [63:0] ADDR_MEPC =
            64'h0000_0000_0000_0108;

        localparam logic [63:0] ADDR_MTVAL =
            64'h0000_0000_0000_0110;

        localparam logic [63:0] ADDR_POST_VALUE =
            64'h0000_0000_0000_0118;

        localparam logic [63:0] ADDR_SENTINEL =
            64'h0000_0000_0000_0120;

        // La instrucción que causa el fault está en PC=0x08
        // en ambos escenarios.
        localparam logic [63:0] EXPECTED_MEPC =
            64'h0000_0000_0000_0008;

        localparam logic [63:0] MCAUSE_LOAD_ACCESS_FAULT =
            64'd5;

        localparam logic [63:0] MCAUSE_STORE_ACCESS_FAULT =
            64'd7;

        localparam logic [63:0] LOAD_OLD_VALUE =
            64'h0000_0000_0000_0055;

        localparam logic [63:0] STORE_VALUE =
            64'h0000_0000_0000_005A;

        localparam logic [63:0] FAULT_LOCATION_INITIAL =
            64'h1122_3344_5566_7788;

        localparam logic [63:0] LOAD_SENTINEL =
            64'h0000_0000_0000_006A;

        localparam logic [63:0] STORE_SENTINEL =
            64'h0000_0000_0000_006B;

        localparam int SCENARIO_LOAD  = 0;
        localparam int SCENARIO_STORE = 1;

    // =========================================================
    // RISC-V constants
    // =========================================================

        localparam logic [6:0] OPCODE_OP_IMM =
            7'b0010011;

        localparam logic [6:0] OPCODE_LOAD =
            7'b0000011;

        localparam logic [6:0] OPCODE_STORE =
            7'b0100011;

        localparam logic [6:0] OPCODE_SYSTEM =
            7'b1110011;

        localparam logic [2:0] F3_ADDI =
            3'b000;

        localparam logic [2:0] F3_LD =
            3'b011;

        localparam logic [2:0] F3_SD =
            3'b011;

        localparam logic [2:0] F3_CSRRW =
            3'b001;

        localparam logic [2:0] F3_CSRRS =
            3'b010;

        localparam logic [11:0] CSR_MEPC =
            12'h341;

        localparam logic [11:0] CSR_MCAUSE =
            12'h342;

        localparam logic [11:0] CSR_MTVAL =
            12'h343;

        localparam logic [31:0] INSTR_MRET =
            32'h3020_0073;

        localparam logic [31:0] INSTR_HALT =
            32'h0000_006F;

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
    // Expansión no utilizada
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
    // Core
    // =========================================================

        core_top #(
            .RESET_PC   (RESET_PC),
            .TRAP_VECTOR(TRAP_VECTOR)
        ) dut (
            .clk         (clk),
            .rst         (rst),

            .imem_req    (imem_req),
            .imem_addr   (imem_addr),
            .imem_gnt    (imem_gnt),
            .imem_rvalid (imem_rvalid),
            .imem_rdata  (imem_rdata),

            .dmem_rdata  (dmem_rdata),

            .dmem_req    (dmem_req),
            .dmem_gnt    (dmem_gnt),
            .dmem_rvalid (dmem_rvalid),
            .dmem_error  (dmem_error),

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
    // El fault se inyecta exactamente en 0x80.
    //
    // 2 ciclos esperando grant.
    // 3 ciclos esperando response.
    // =========================================================

        dmem_sync_model #(
            .MEM_WORDS    (DMEM_WORDS),

            .GNT_DELAY    (2),
            .RESP_DELAY   (3),

            .FAULT_ENABLE (1'b1),
            .FAULT_ADDR   (FAULT_ADDR),
            .FAULT_MASK   (64'hFFFF_FFFF_FFFF_FFFF)
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
    // Encoders
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

        function automatic logic [31:0] enc_csr(
            input logic [11:0] csr,
            input logic [4:0]  rs1,
            input logic [2:0]  funct3,
            input logic [4:0]  rd
        );
            begin
                enc_csr = {
                    csr,
                    rs1,
                    funct3,
                    rd,
                    OPCODE_SYSTEM
                };
            end
        endfunction

        function automatic logic [31:0] enc_nop();
            begin
                enc_nop =
                    32'h0000_0013;
            end
        endfunction

    // =========================================================
    // Checks
    // =========================================================

     integer errors;

    // =========================================================
    // Scoreboard de errores del testbench
    //
    // La asignación bloqueante es intencional:
    //
    //   - errors no modela hardware.
    //   - permite acumular más de un error dentro del mismo
    //     timestep sin perder incrementos.
    //
    // Se limita la excepción BLKSEQ únicamente a esta operación
    // de bookkeeping del testbench.
    // =========================================================

        // verilator lint_off BLKSEQ
        task automatic record_error;
            begin
                errors = errors + 1;
            end
        endtask
        // verilator lint_on BLKSEQ

        task automatic check64(
            input string       name,
            input logic [63:0] got,
            input logic [63:0] expected
        );
            begin
                if (got !== expected) begin
                    $display(
                        "ERROR: %-42s got=0x%016h expected=0x%016h",
                        name,
                        got,
                        expected
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : %-42s = 0x%016h",
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
                        "ERROR: %-42s got=%0d expected=%0d",
                        name,
                        got,
                        expected
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : %-42s = %0d",
                        name,
                        got
                    );
                end
            end
        endtask

    // =========================================================
    // Estado del escenario actual
    // =========================================================

        integer scenario;

        integer fault_accept_count;
        integer fault_error_response_count;

        integer mcause_store_count;
        integer mepc_store_count;
        integer mtval_store_count;
        integer post_store_count;
        integer sentinel_store_count;

        integer fault_request_wait_cycles;
        integer fault_response_wait_cycles;

        logic fault_outstanding;

    // =========================================================
    // Monitor DMEM
    // =========================================================

        always @(posedge clk) begin
            if (rst) begin
                fault_accept_count          <= 0;
                fault_error_response_count  <= 0;

                mcause_store_count          <= 0;
                mepc_store_count            <= 0;
                mtval_store_count           <= 0;
                post_store_count            <= 0;
                sentinel_store_count        <= 0;

                fault_request_wait_cycles   <= 0;
                fault_response_wait_cycles  <= 0;

                fault_outstanding           <= 1'b0;
            end
            else begin

                // -------------------------------------------------
                // Wait antes del grant de la operación causante.
                // -------------------------------------------------

                    if (
                        dmem_req &&
                        !dmem_gnt &&
                        (dmem_addr == FAULT_ADDR)
                    ) begin
                        fault_request_wait_cycles <=
                            fault_request_wait_cycles + 1;
                    end

                // -------------------------------------------------
                // Espera posterior al grant de la operación fault.
                // -------------------------------------------------

                    if (
                        fault_outstanding &&
                        !dmem_rvalid
                    ) begin
                        fault_response_wait_cycles <=
                            fault_response_wait_cycles + 1;
                    end

                // -------------------------------------------------
                // Aceptación.
                // -------------------------------------------------

                    if (dmem_req && dmem_gnt) begin

                        if (dmem_addr == FAULT_ADDR) begin

                            fault_accept_count <=
                                fault_accept_count + 1;

                            if (scenario == SCENARIO_LOAD) begin

                                if (dmem_we !== 1'b0) begin
                                    $display(
                                        "ERROR: fault LOAD presentado como store"
                                    );

                                    record_error(); 
                                end

                                if (dmem_size !== 2'b11) begin
                                    $display(
                                        "ERROR: fault LOAD size=%b expected=11",
                                        dmem_size
                                    );

                                    record_error();
                                end
                            end
                            else begin

                                if (dmem_we !== 1'b1) begin
                                    $display(
                                        "ERROR: fault STORE presentado como load"
                                    );

                                    record_error();
                                end

                                if (dmem_size !== 2'b11) begin
                                    $display(
                                        "ERROR: fault STORE size=%b expected=11",
                                        dmem_size
                                    );

                                    record_error();
                                end

                                if (dmem_wstrb !== 8'hFF) begin
                                    $display(
                                        "ERROR: fault STORE wstrb=0x%02h expected=FF",
                                        dmem_wstrb
                                    );

                                    record_error();
                                end

                                check64(
                                    "fault STORE wdata",
                                    dmem_wdata,
                                    STORE_VALUE
                                );
                            end

                            if (fault_outstanding) begin
                                $display(
                                    "ERROR: segunda operación fault aceptada antes de completar la anterior"
                                );

                                record_error();
                            end

                            fault_outstanding <= 1'b1;
                        end

                        // ---------------------------------------------
                        // Efectos posteriores al trap.
                        //
                        // Deben ocurrir exactamente una vez.
                        // Si una instrucción más joven escapara durante
                        // WAIT_RESP y luego se repitiera tras MRET,
                        // alguno de estos contadores sería > 1.
                        // ---------------------------------------------

                            if (dmem_we) begin
                                case (dmem_addr)

                                    ADDR_MCAUSE:
                                        mcause_store_count <=
                                            mcause_store_count + 1;

                                    ADDR_MEPC:
                                        mepc_store_count <=
                                            mepc_store_count + 1;

                                    ADDR_MTVAL:
                                        mtval_store_count <=
                                            mtval_store_count + 1;

                                    ADDR_POST_VALUE:
                                        post_store_count <=
                                            post_store_count + 1;

                                    ADDR_SENTINEL:
                                        sentinel_store_count <=
                                            sentinel_store_count + 1;

                                    default: begin
                                    end
                                endcase
                            end
                    end

                // -------------------------------------------------
                // Respuesta de la transacción fault.
                // -------------------------------------------------

                    if (
                        fault_outstanding &&
                        dmem_rvalid
                    ) begin

                        if (!dmem_error) begin
                            $display(
                                "ERROR: la petición fault terminó sin dmem_error"
                            );

                            record_error();
                        end
                        else begin
                            fault_error_response_count <=
                                fault_error_response_count + 1;
                        end

                        fault_outstanding <= 1'b0;
                    end

                // Ninguna otra transacción debe producir error.
                if (
                    dmem_rvalid &&
                    dmem_error &&
                    !fault_outstanding
                ) begin
                    $display(
                        "ERROR: dmem_error sin fault outstanding conocido"
                    );

                    record_error();
                end
            end
        end

    // =========================================================
    // MMIO nunca debe utilizarse
    // =========================================================

        always @(posedge clk) begin
            if (!rst && exp_valid) begin
                $display(
                    "ERROR: acceso MMIO inesperado addr=0x%016h",
                    exp_addr
                );

                record_error();
            end
        end

    // =========================================================
    // Handler común
    //
    // 0x100:
    //
    // x20 = mcause
    // x21 = mepc
    // x22 = mtval
    // x23 = mepc + 4
    // mepc = x23
    // MRET
    //
    // Este patrón ya es utilizado por las pruebas de traps
    // existentes.
    // =========================================================

        task automatic load_handler;
            begin

                // CSRRS x20, mcause, x0
                u_imem.mem[64] =
                    enc_csr(
                        CSR_MCAUSE,
                        5'd0,
                        F3_CSRRS,
                        5'd20
                    );

                // CSRRS x21, mepc, x0
                u_imem.mem[65] =
                    enc_csr(
                        CSR_MEPC,
                        5'd0,
                        F3_CSRRS,
                        5'd21
                    );

                // CSRRS x22, mtval, x0
                u_imem.mem[66] =
                    enc_csr(
                        CSR_MTVAL,
                        5'd0,
                        F3_CSRRS,
                        5'd22
                    );

                // ADDI x23, x21, 4
                u_imem.mem[67] =
                    enc_i(
                        12'h004,
                        5'd21,
                        F3_ADDI,
                        5'd23,
                        OPCODE_OP_IMM
                    );

                // CSRRW x0, mepc, x23
                u_imem.mem[68] =
                    enc_csr(
                        CSR_MEPC,
                        5'd23,
                        F3_CSRRW,
                        5'd0
                    );

                // MRET
                u_imem.mem[69] =
                    INSTR_MRET;
            end
        endtask

    // =========================================================
    // Programa de cada escenario
    // =========================================================

        integer i;

        task automatic load_program(
            input integer selected_scenario
        );
            begin

                for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                    u_imem.mem[i] = enc_nop();
                end

                // ---------------------------------------------
                // 0x00
                // x1 = dirección fault = 0x80
                // ---------------------------------------------

                u_imem.mem[0] =
                    enc_i(
                        12'h080,
                        5'd0,
                        F3_ADDI,
                        5'd1,
                        OPCODE_OP_IMM
                    );

                // ---------------------------------------------
                // 0x04
                // Preparar x5.
                // ---------------------------------------------

                if (selected_scenario == SCENARIO_LOAD) begin

                    u_imem.mem[1] =
                        enc_i(
                            12'h055,
                            5'd0,
                            F3_ADDI,
                            5'd5,
                            OPCODE_OP_IMM
                        );
                end
                else begin

                    u_imem.mem[1] =
                        enc_i(
                            12'h05A,
                            5'd0,
                            F3_ADDI,
                            5'd5,
                            OPCODE_OP_IMM
                        );
                end

                // ---------------------------------------------
                // 0x08
                // Instrucción causante.
                // ---------------------------------------------

                if (selected_scenario == SCENARIO_LOAD) begin

                    // LD x5, 0(x1)
                    //
                    // x5 NO debe recibir rdata porque la respuesta
                    // termina con error.
                    u_imem.mem[2] =
                        enc_i(
                            12'h000,
                            5'd1,
                            F3_LD,
                            5'd5,
                            OPCODE_LOAD
                        );
                end
                else begin

                    // SD x5, 0(x1)
                    u_imem.mem[2] =
                        enc_s(
                            12'h000,
                            5'd5,
                            5'd1,
                            F3_SD
                        );
                end

                // ---------------------------------------------
                // Después del MRET:
                //
                // Guardar la evidencia capturada por el handler.
                // ---------------------------------------------

                // 0x0C
                u_imem.mem[3] =
                    enc_s(
                        ADDR_MCAUSE[11:0],
                        5'd20,
                        5'd0,
                        F3_SD
                    );

                // 0x10
                u_imem.mem[4] =
                    enc_s(
                        ADDR_MEPC[11:0],
                        5'd21,
                        5'd0,
                        F3_SD
                    );

                // 0x14
                u_imem.mem[5] =
                    enc_s(
                        ADDR_MTVAL[11:0],
                        5'd22,
                        5'd0,
                        F3_SD
                    );

                // 0x18
                //
                // En LOAD comprueba que x5 conserva 0x55.
                // En STORE demuestra continuidad tras el trap.
                u_imem.mem[6] =
                    enc_s(
                        ADDR_POST_VALUE[11:0],
                        5'd5,
                        5'd0,
                        F3_SD
                    );

                // ---------------------------------------------
                // Sentinel
                // ---------------------------------------------

                if (selected_scenario == SCENARIO_LOAD) begin

                    // 0x1C
                    u_imem.mem[7] =
                        enc_i(
                            12'h06A,
                            5'd0,
                            F3_ADDI,
                            5'd6,
                            OPCODE_OP_IMM
                        );
                end
                else begin

                    // 0x1C
                    u_imem.mem[7] =
                        enc_i(
                            12'h06B,
                            5'd0,
                            F3_ADDI,
                            5'd6,
                            OPCODE_OP_IMM
                        );
                end

                // 0x20
                u_imem.mem[8] =
                    enc_s(
                        ADDR_SENTINEL[11:0],
                        5'd6,
                        5'd0,
                        F3_SD
                    );

                // 0x24
                u_imem.mem[9] =
                    INSTR_HALT;

                load_handler();
            end
        endtask

    // =========================================================
    // Inicialización de las posiciones de DMEM relevantes
    // =========================================================

        task automatic initialize_dmem;
            begin

                u_dmem.mem[FAULT_ADDR[10:3]] =
                    FAULT_LOCATION_INITIAL;

                u_dmem.mem[ADDR_MCAUSE[10:3]] =
                    64'd0;

                u_dmem.mem[ADDR_MEPC[10:3]] =
                    64'd0;

                u_dmem.mem[ADDR_MTVAL[10:3]] =
                    64'd0;

                u_dmem.mem[ADDR_POST_VALUE[10:3]] =
                    64'd0;

                u_dmem.mem[ADDR_SENTINEL[10:3]] =
                    64'd0;
            end
        endtask

    // =========================================================
    // Esperar finalización de escenario
    // =========================================================

        task automatic wait_for_sentinel(
            input logic [63:0] expected
        );
            integer cycles;
            begin
                cycles = 0;

                while (
                    (u_dmem.mem[ADDR_SENTINEL[10:3]] !== expected) &&
                    (cycles < 600)
                ) begin
                    @(posedge clk);
                    #1;
                    cycles = cycles + 1;
                end

                if (
                    u_dmem.mem[ADDR_SENTINEL[10:3]] !== expected
                ) begin
                    $fatal(
                        1,
                        "TIMEOUT esperando sentinel 0x%016h",
                        expected
                    );
                end
            end
        endtask

    // =========================================================
    // Checks comunes de protocolo
    // =========================================================

        task automatic check_protocol_counts;
            begin

                check_int(
                    "fault aceptado exactamente una vez",
                    fault_accept_count,
                    1
                );

                check_int(
                    "una response con dmem_error",
                    fault_error_response_count,
                    1
                );

                check_int(
                    "store mcause exactamente una vez",
                    mcause_store_count,
                    1
                );

                check_int(
                    "store mepc exactamente una vez",
                    mepc_store_count,
                    1
                );

                check_int(
                    "store mtval exactamente una vez",
                    mtval_store_count,
                    1
                );

                check_int(
                    "store post-value exactamente una vez",
                    post_store_count,
                    1
                );

                check_int(
                    "store sentinel exactamente una vez",
                    sentinel_store_count,
                    1
                );

                if (fault_request_wait_cycles <= 0) begin
                    $display(
                        "ERROR: no se ejercitó WAIT_GNT en fault"
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : fault WAIT_GNT observado durante %0d ciclos",
                        fault_request_wait_cycles
                    );
                end

                if (fault_response_wait_cycles <= 0) begin
                    $display(
                        "ERROR: no se ejercitó WAIT_RESP en fault"
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : fault WAIT_RESP observado durante %0d ciclos",
                        fault_response_wait_cycles
                    );
                end

                if (fault_outstanding !== 1'b0) begin
                    $display(
                        "ERROR: quedó fault outstanding"
                    );

                    record_error();
                end
                else begin
                    $display(
                        "PASS : no queda fault outstanding"
                    );
                end
            end
        endtask

    // =========================================================
    // Checks LOAD fault
    // =========================================================

        task automatic check_load_scenario;
            begin

                $display("");
                $display(
                    "=============================================="
                );

                $display(
                    "SCENARIO LOAD ACCESS FAULT"
                );

                $display(
                    "=============================================="
                );

                check64(
                    "LOAD fault mcause",
                    u_dmem.mem[ADDR_MCAUSE[10:3]],
                    MCAUSE_LOAD_ACCESS_FAULT
                );

                check64(
                    "LOAD fault mepc",
                    u_dmem.mem[ADDR_MEPC[10:3]],
                    EXPECTED_MEPC
                );

                check64(
                    "LOAD fault mtval",
                    u_dmem.mem[ADDR_MTVAL[10:3]],
                    FAULT_ADDR
                );

                check64(
                    "LOAD destino x5 preservado",
                    dut.u_regfile.regs[5],
                    LOAD_OLD_VALUE
                );

                check64(
                    "LOAD post-value almacenado",
                    u_dmem.mem[ADDR_POST_VALUE[10:3]],
                    LOAD_OLD_VALUE
                );

                check64(
                    "LOAD fault location intacta",
                    u_dmem.mem[FAULT_ADDR[10:3]],
                    FAULT_LOCATION_INITIAL
                );

                check64(
                    "LOAD sentinel",
                    u_dmem.mem[ADDR_SENTINEL[10:3]],
                    LOAD_SENTINEL
                );

                check_protocol_counts();
            end
        endtask

    // =========================================================
    // Checks STORE fault
    // =========================================================

        task automatic check_store_scenario;
            begin

                $display("");
                $display(
                    "=============================================="
                );

                $display(
                    "SCENARIO STORE ACCESS FAULT"
                );

                $display(
                    "=============================================="
                );

                check64(
                    "STORE fault mcause",
                    u_dmem.mem[ADDR_MCAUSE[10:3]],
                    MCAUSE_STORE_ACCESS_FAULT
                );

                check64(
                    "STORE fault mepc",
                    u_dmem.mem[ADDR_MEPC[10:3]],
                    EXPECTED_MEPC
                );

                check64(
                    "STORE fault mtval",
                    u_dmem.mem[ADDR_MTVAL[10:3]],
                    FAULT_ADDR
                );

                check64(
                    "STORE x5 preservado",
                    dut.u_regfile.regs[5],
                    STORE_VALUE
                );

                // Esta es una comprobación muy importante:
                // el modelo define que un store con fault no produce
                // el efecto lateral de escritura.
                check64(
                    "STORE fault no modificó target",
                    u_dmem.mem[FAULT_ADDR[10:3]],
                    FAULT_LOCATION_INITIAL
                );

                check64(
                    "STORE post-value almacenado",
                    u_dmem.mem[ADDR_POST_VALUE[10:3]],
                    STORE_VALUE
                );

                check64(
                    "STORE sentinel",
                    u_dmem.mem[ADDR_SENTINEL[10:3]],
                    STORE_SENTINEL
                );

                check_protocol_counts();
            end
        endtask

    // =========================================================
    // Test principal
    // =========================================================

        initial begin

            $dumpfile(
                "build/tb_core_dmem_sync_fault.vcd"
            );

            $dumpvars(
                0,
                tb_core_dmem_sync_fault
            );

            errors   = 0;
            rst      = 1'b1;
            scenario = SCENARIO_LOAD;

            // =====================================================
            // ESCENARIO 1: LOAD ACCESS FAULT
            // =====================================================

            load_program(
                SCENARIO_LOAD
            );

            initialize_dmem();

            repeat (5) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            wait_for_sentinel(
                LOAD_SENTINEL
            );

            repeat (5) @(posedge clk);
            #1;

            check_load_scenario();

            // =====================================================
            // Reset entre escenarios
            // =====================================================

            @(negedge clk);

            rst      = 1'b1;
            scenario = SCENARIO_STORE;

            load_program(
                SCENARIO_STORE
            );

            initialize_dmem();

            repeat (5) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            // =====================================================
            // ESCENARIO 2: STORE ACCESS FAULT
            // =====================================================

            wait_for_sentinel(
                STORE_SENTINEL
            );

            repeat (5) @(posedge clk);
            #1;

            check_store_scenario();

            // =====================================================
            // Resultado
            // =====================================================

            $display("");
            $display(
                "=============================================="
            );

            if (errors == 0) begin
                $display(
                    "PASS: DMEM synchronous access faults funcionando"
                );

                $display(
                    "      load  -> mcause=5, mepc/mtval precisos"
                );

                $display(
                    "      store -> mcause=7, mepc/mtval precisos"
                );

                $display(
                    "      traps ocurren después de response error"
                );

                $display(
                    "      sin efectos laterales indebidos"
                );
            end
            else begin
                $display(
                    "FAIL: tb_core_dmem_sync_fault errors=%0d",
                    errors
                );
            end

            $display(
                "=============================================="
            );

            if (errors != 0) begin
                $fatal(
                    1,
                    "tb_core_dmem_sync_fault falló"
                );
            end

            $finish;
        end

    // =========================================================
    // Timeout
    // =========================================================

        initial begin
            #30000;

            $fatal(
                1,
                "TIMEOUT global tb_core_dmem_sync_fault"
            );
        end

    // =========================================================
    // Señales no relevantes directamente
    // =========================================================

        wire _unused_ok = 1'b0 && &{
            1'b0,
            imem_addr[1:0],
            exp_we,
            exp_wdata,
            exp_wstrb,
            exp_size,
            1'b0
        };

endmodule
