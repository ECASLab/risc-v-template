`timescale 1ns/1ps

module tb_core_mem_misaligned_trap;

    // =========================================================
    // Configuración
    // =========================================================
    localparam int unsigned DMEM_WORDS = 256;
    localparam int unsigned IMEM_WORDS = 256;

    localparam logic [63:0] RESET_PC    = 64'h0000_0000_0000_0000;
    localparam logic [63:0] TRAP_VECTOR = 64'h0000_0000_0000_0100;

    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    localparam logic [63:0] MCAUSE_LOAD_ADDR_MISALIGNED  = 64'd4;
    localparam logic [63:0] MCAUSE_STORE_ADDR_MISALIGNED = 64'd6;

    localparam logic [63:0] OUTPUT_BASE = 64'h0000_0000_0000_0300;
    localparam logic [63:0] DONE_ADDR   = 64'h0000_0000_0000_0378;

    localparam logic [63:0] LOAD_SOURCE_VALUE =
        64'hDEAD_BEEF_CAFE_BABE;

    localparam logic [63:0] STORE_SENTINEL_0 =
        64'h1122_3344_5566_7788;

    localparam logic [63:0] STORE_SENTINEL_1 =
        64'h99AA_BBCC_DDEE_FF00;

    // =========================================================
    // Señales del DUT
    // =========================================================

    logic clk;
    logic rst;

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // Handshake de memoria de datos.
    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;

    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

   

    // =========================================================
    // Variables de comprobación
    // =========================================================

    logic [63:0] prog_pc;

    logic [63:0] expected_mepc_lh;
    logic [63:0] expected_mepc_lw;
    logic [63:0] expected_mepc_ld;
    logic [63:0] expected_mepc_sh;
    logic [63:0] expected_mepc_sw;
    logic [63:0] expected_mepc_sd;

    logic seen_done;
    logic bad_misaligned_req_seen;
    logic unexpected_exp_seen;

    // Transacción DMEM actualmente outstanding.
    logic        pending_valid;
    logic [63:0] pending_addr;

    integer accepted_count;
    integer response_count;
    integer store_accept_count;

    integer wait_gnt_cycles;
    integer wait_resp_cycles;

    integer errors;
    integer cycles;
    integer i;

    // =========================================================
    // DUT
    // =========================================================

    // =========================================================
    // IMEM síncrona real
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
    // En este test las instrucciones desalineadas NO deben
    // generar una petición hacia esta memoria.
    //
    // Las escrituras alineadas utilizadas por el programa para
    // guardar mcause/mepc/resultados sí atraviesan el handshake
    // real y ejercen WAIT_GNT + WAIT_RESP.
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

        core_top #(
            .RESET_PC    (RESET_PC),
            .TRAP_VECTOR (TRAP_VECTOR)
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
    // Generadores de instrucciones
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
            input logic [2:0]  funct3,
            input logic [6:0]  opcode
        );
            begin
                enc_s = {
                    imm[11:5],
                    rs2,
                    rs1,
                    funct3,
                    imm[4:0],
                    opcode
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

    // ---------------------------------------------------------
    // Inserta una instrucción en prog_pc y avanza 4 bytes.
    // ---------------------------------------------------------

        task automatic emit(
            input logic [31:0] instr
        );
            begin
                u_imem.mem[prog_pc[9:2]] = instr;
                prog_pc = prog_pc + 64'd4;
            end
        endtask

    // =========================================================
    // Helper de comprobación de memoria
    // =========================================================

        task automatic check_mem64(
            input logic [63:0] addr,
            input logic [63:0] expected,
            input string       label_text
        );
            logic [63:0] got;

            begin
                got = u_dmem.mem[addr[10:3]];

                if (got !== expected) begin
                    $display(
                        "FAIL : %-38s got=0x%016h expected=0x%016h",
                        label_text,
                        got,
                        expected
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : %-38s = 0x%016h",
                        label_text,
                        got
                    );
                end
            end
        endtask

    // =========================================================
    // Clock
    // =========================================================

        initial begin
            clk = 1'b0;

            forever begin
                #5 clk = ~clk;
            end
        end

    // =========================================================
    // Monitores del protocolo DMEM
    //
    // El test contiene:
    //
    //   - 3 loads deliberadamente desalineados:
    //       LH / LW / LD
    //
    //   - 3 stores deliberadamente desalineados:
    //       SH / SW / SD
    //
    // Ninguno de esos seis accesos debe generar dmem_req.
    //
    // El programa también realiza stores SD alineados para
    // guardar evidencia de cada trap y el marcador final.
    // Esos stores sí deben utilizar el handshake real.
    // =========================================================

        always @(posedge clk) begin
            if (rst) begin

                seen_done              <= 1'b0;
                bad_misaligned_req_seen <= 1'b0;
                unexpected_exp_seen     <= 1'b0;

                pending_valid <= 1'b0;
                pending_addr  <= 64'd0;

                accepted_count     <= 0;
                response_count     <= 0;
                store_accept_count <= 0;

                wait_gnt_cycles  <= 0;
                wait_resp_cycles <= 0;
            end
            else begin

                // -------------------------------------------------
                // Ningún acceso de este test pertenece a expansión.
                // -------------------------------------------------

                if (exp_valid) begin
                    unexpected_exp_seen <= 1'b1;

                    $display(
                        "ERROR: acceso inesperado a expansión addr=0x%016h",
                        exp_addr
                    );
                end

                // -------------------------------------------------
                // Propiedad fundamental que queremos demostrar:
                //
                // Una instrucción que el core ya clasificó como
                // misaligned NO debe iniciar tráfico DMEM.
                //
                // Es más fuerte que comprobar solamente dmem_we.
                // También cubre LH/LW/LD.
                // -------------------------------------------------

                if (
                    dut.mem_addr_misaligned &&
                    dmem_req
                ) begin
                    bad_misaligned_req_seen <= 1'b1;

                    $display(
                        "ERROR: acceso desalineado produjo dmem_req addr=0x%016h",
                        dmem_addr
                    );
                end

                // -------------------------------------------------
                // WAIT_GNT
                // -------------------------------------------------

                if (dmem_req && !dmem_gnt) begin
                    wait_gnt_cycles <= wait_gnt_cycles + 1;
                end

                // -------------------------------------------------
                // WAIT_RESP
                // -------------------------------------------------

                if (
                    dut.mem_dmem_wait_stall &&
                    !dmem_req &&
                    !dmem_rvalid
                ) begin
                    wait_resp_cycles <= wait_resp_cycles + 1;
                end

                // -------------------------------------------------
                // Petición aceptada
                //
                // El programa no contiene ningún load alineado.
                // Por tanto TODA petición aceptada debe ser un SD
                // alineado que guarda evidencia.
                // -------------------------------------------------

                if (dmem_req && dmem_gnt) begin

                    accepted_count <= accepted_count + 1;

                    if (!dmem_we) begin
                        $fatal(
                            1,
                            "FAIL: se aceptó un load DMEM inesperado addr=0x%016h",
                            dmem_addr
                        );
                    end

                    store_accept_count <=
                        store_accept_count + 1;

                    if (dmem_size !== 2'b11) begin
                        $fatal(
                            1,
                            "FAIL: store de evidencia size=%b esperado=11",
                            dmem_size
                        );
                    end

                    if (dmem_addr[2:0] !== 3'b000) begin
                        $fatal(
                            1,
                            "FAIL: se aceptó store no alineado addr=0x%016h",
                            dmem_addr
                        );
                    end

                    if (dmem_wstrb !== 8'hFF) begin
                        $fatal(
                            1,
                            "FAIL: store de evidencia wstrb=0x%02h esperado=0xff",
                            dmem_wstrb
                        );
                    end

                    // Solo una transacción outstanding.
                    if (pending_valid) begin
                        $fatal(
                            1,
                            "FAIL: se aceptó una segunda transacción DMEM outstanding"
                        );
                    end

                    pending_valid <= 1'b1;
                    pending_addr  <= dmem_addr;
                end

                // -------------------------------------------------
                // Respuesta
                // -------------------------------------------------

                if (dmem_rvalid) begin

                    response_count <= response_count + 1;

                    if (dmem_error) begin
                        $fatal(
                            1,
                            "FAIL: store de evidencia terminó con dmem_error"
                        );
                    end

                    if (!pending_valid) begin
                        $fatal(
                            1,
                            "FAIL: dmem_rvalid sin transacción pending"
                        );
                    end

                    // El test se considera terminado solamente
                    // cuando el store del marcador final RESPONDE,
                    // no simplemente cuando fue presentado.
                    if (pending_addr == DONE_ADDR) begin
                        seen_done <= 1'b1;
                    end

                    pending_valid <= 1'b0;
                    pending_addr  <= 64'd0;
                end
            end
        end

    // =========================================================
    // Programa + comprobaciones
    // =========================================================

        initial begin

            rst       = 1'b1;

            exp_ready = 1'b1;
            exp_rdata = 64'd0;
            exp_error = 1'b0;

            errors = 0;
            cycles = 0;

            // -----------------------------------------------------
            // Estado inicial de memorias
            // -----------------------------------------------------

            for (i = 0; i < IMEM_WORDS; i = i + 1) begin
                // NOP = ADDI x0, x0, 0
                u_imem.mem[i] = 32'h0000_0013;

                // dmem_sync_model deliberadamente no borra su
                // memoria durante reset.
                u_dmem.mem[i] = 64'd0;
            end
            // Datos que podrían ser leídos incorrectamente por
            // los loads desalineados.
            //
            // 0x100 ... 0x107
            u_dmem.mem[8'h20] = LOAD_SOURCE_VALUE;

            // Zona que los stores desalineados intentarían modificar
            // si llegaran incorrectamente hasta la memoria.
            //
            // 0x180 ... 0x187
            u_dmem.mem[8'h30] = STORE_SENTINEL_0;

            // 0x188 ... 0x18F
            u_dmem.mem[8'h31] = STORE_SENTINEL_1;

            // =====================================================
            // Programa principal
            // =====================================================

            prog_pc = 64'd0;

            // -----------------------------------------------------
            // x10 = 0x300
            //
            // Área donde el programa guarda evidencia de cada trap.
            // -----------------------------------------------------

            emit(
                enc_i(
                    12'h300,
                    5'd0,
                    3'b000,
                    5'd10,
                    OPCODE_OP_IMM
                )
            );

            // =====================================================
            // CASO 1: LH desde 0x101
            //
            // Halfword requiere múltiplo de 2.
            // 0x101 es desalineado.
            //
            // x5 empieza en 0x51 y debe conservar ese valor.
            // =====================================================

                // x1 = 0x101
                emit(
                    enc_i(
                        12'h101,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x5 = 0x51
                emit(
                    enc_i(
                        12'h051,
                        5'd0,
                        3'b000,
                        5'd5,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_lh = prog_pc;

                // LH x5, 0(x1)
                emit(
                    enc_i(
                        12'h000,
                        5'd1,
                        3'b001,
                        5'd5,
                        OPCODE_LOAD
                    )
                );

                // [0x300] = mcause
                emit(
                    enc_s(
                        12'h000,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x308] = mepc
                emit(
                    enc_s(
                        12'h008,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x310] = x5
                emit(
                    enc_s(
                        12'h010,
                        5'd5,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // CASO 2: LW desde 0x102
            //
            // Word requiere múltiplo de 4.
            // =====================================================

                // x1 = 0x102
                emit(
                    enc_i(
                        12'h102,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x5 = 0x52
                emit(
                    enc_i(
                        12'h052,
                        5'd0,
                        3'b000,
                        5'd5,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_lw = prog_pc;

                // LW x5, 0(x1)
                emit(
                    enc_i(
                        12'h000,
                        5'd1,
                        3'b010,
                        5'd5,
                        OPCODE_LOAD
                    )
                );

                // [0x318] = mcause
                emit(
                    enc_s(
                        12'h018,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x320] = mepc
                emit(
                    enc_s(
                        12'h020,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x328] = x5
                emit(
                    enc_s(
                        12'h028,
                        5'd5,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // CASO 3: LD desde 0x104
            //
            // Doubleword requiere múltiplo de 8.
            // =====================================================

                // x1 = 0x104
                emit(
                    enc_i(
                        12'h104,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x5 = 0x53
                emit(
                    enc_i(
                        12'h053,
                        5'd0,
                        3'b000,
                        5'd5,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_ld = prog_pc;

                // LD x5, 0(x1)
                emit(
                    enc_i(
                        12'h000,
                        5'd1,
                        3'b011,
                        5'd5,
                        OPCODE_LOAD
                    )
                );

                // [0x330] = mcause
                emit(
                    enc_s(
                        12'h030,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x338] = mepc
                emit(
                    enc_s(
                        12'h038,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x340] = x5
                emit(
                    enc_s(
                        12'h040,
                        5'd5,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // CASO 4: SH hacia 0x181
            // =====================================================

                // x1 = 0x181
                emit(
                    enc_i(
                        12'h181,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x2 = 0x61
                emit(
                    enc_i(
                        12'h061,
                        5'd0,
                        3'b000,
                        5'd2,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_sh = prog_pc;

                // SH x2, 0(x1)
                emit(
                    enc_s(
                        12'h000,
                        5'd2,
                        5'd1,
                        3'b001,
                        OPCODE_STORE
                    )
                );

                // [0x348] = mcause
                emit(
                    enc_s(
                        12'h048,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x350] = mepc
                emit(
                    enc_s(
                        12'h050,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // CASO 5: SW hacia 0x182
            // =====================================================

                // x1 = 0x182
                emit(
                    enc_i(
                        12'h182,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x2 = 0x62
                emit(
                    enc_i(
                        12'h062,
                        5'd0,
                        3'b000,
                        5'd2,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_sw = prog_pc;

                // SW x2, 0(x1)
                emit(
                    enc_s(
                        12'h000,
                        5'd2,
                        5'd1,
                        3'b010,
                        OPCODE_STORE
                    )
                );

                // [0x358] = mcause
                emit(
                    enc_s(
                        12'h058,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x360] = mepc
                emit(
                    enc_s(
                        12'h060,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // CASO 6: SD hacia 0x184
            // =====================================================

                // x1 = 0x184
                emit(
                    enc_i(
                        12'h184,
                        5'd0,
                        3'b000,
                        5'd1,
                        OPCODE_OP_IMM
                    )
                );

                // x2 = 0x63
                emit(
                    enc_i(
                        12'h063,
                        5'd0,
                        3'b000,
                        5'd2,
                        OPCODE_OP_IMM
                    )
                );

                expected_mepc_sd = prog_pc;

                // SD x2, 0(x1)
                emit(
                    enc_s(
                        12'h000,
                        5'd2,
                        5'd1,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x368] = mcause
                emit(
                    enc_s(
                        12'h068,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // [0x370] = mepc
                emit(
                    enc_s(
                        12'h070,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

            // =====================================================
            // Marcador final
            // =====================================================

                // x2 = 0x7F
                emit(
                    enc_i(
                        12'h07F,
                        5'd0,
                        3'b000,
                        5'd2,
                        OPCODE_OP_IMM
                    )
                );

                // SD x2, 0x78(x10)
                // -> dirección 0x378
                emit(
                    enc_s(
                        12'h078,
                        5'd2,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                // JAL x0, 0
                // Loop infinito después del marcador.
                emit(32'h0000_006F);

            // =====================================================
            // Handler de traps en 0x100
            //
            // x20 <- mcause
            // x21 <- mepc original
            // x22 <- mepc + 4
            // mepc <- x22
            // MRET
            // =====================================================

                // 0x100:
                // CSRRS x20, mcause, x0
                u_imem.mem[8'h40] =
                    enc_csr(
                        12'h342,
                        5'd0,
                        3'b010,
                        5'd20
                    );

                // 0x104:
                // CSRRS x21, mepc, x0
                u_imem.mem[8'h41] =
                    enc_csr(
                        12'h341,
                        5'd0,
                        3'b010,
                        5'd21
                    );

                // 0x108:
                // ADDI x22, x21, 4
                u_imem.mem[8'h42] =
                    enc_i(
                        12'h004,
                        5'd21,
                        3'b000,
                        5'd22,
                        OPCODE_OP_IMM
                    );

                // 0x10C:
                // CSRRW x0, mepc, x22
                u_imem.mem[8'h43] =
                    enc_csr(
                        12'h341,
                        5'd22,
                        3'b001,
                        5'd0
                    );

                // 0x110:
                // MRET
                u_imem.mem[8'h44] = 32'h3020_0073;

            // =====================================================
            // VCD
            // =====================================================

            $dumpfile("build/tb_core_mem_misaligned_trap.vcd");
            $dumpvars(0, tb_core_mem_misaligned_trap);

            // =====================================================
            // Reset síncrono
            // =====================================================

            repeat (4) @(posedge clk);

            // Se libera en flanco negativo para evitar carrera con
            // la lógica secuencial del DUT.
            @(negedge clk);
            rst = 1'b0;

            // =====================================================
            // Esperar terminación
            // =====================================================

                while ((!seen_done) && (cycles < 1000)) begin
                    @(posedge clk);
                    cycles = cycles + 1;
                end

                if (!seen_done) begin
                    $display("==============================================");
                    $display("FAIL: timeout esperando marcador final");
                    $display("cycles = %0d", cycles);
                    $display("==============================================");
                    $fatal(1);
                end

                // Permitir que las últimas escrituras se estabilicen.
                repeat (4) @(posedge clk);

                $display("");
                $display("==============================================");
                $display("TB core load/store misaligned traps");
                $display("==============================================");

            // =====================================================
            // LOADS
            // =====================================================

                check_mem64(
                    64'h0000_0000_0000_0300,
                    MCAUSE_LOAD_ADDR_MISALIGNED,
                    "LH mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0308,
                    expected_mepc_lh,
                    "LH mepc"
                );

                check_mem64(
                    64'h0000_0000_0000_0310,
                    64'h0000_0000_0000_0051,
                    "LH no modifica rd"
                );

                check_mem64(
                    64'h0000_0000_0000_0318,
                    MCAUSE_LOAD_ADDR_MISALIGNED,
                    "LW mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0320,
                    expected_mepc_lw,
                    "LW mepc"
                );

                check_mem64(
                    64'h0000_0000_0000_0328,
                    64'h0000_0000_0000_0052,
                    "LW no modifica rd"
                );

                check_mem64(
                    64'h0000_0000_0000_0330,
                    MCAUSE_LOAD_ADDR_MISALIGNED,
                    "LD mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0338,
                    expected_mepc_ld,
                    "LD mepc"
                );

                check_mem64(
                    64'h0000_0000_0000_0340,
                    64'h0000_0000_0000_0053,
                    "LD no modifica rd"
                );

            // =====================================================
            // STORES
            // =====================================================

                check_mem64(
                    64'h0000_0000_0000_0348,
                    MCAUSE_STORE_ADDR_MISALIGNED,
                    "SH mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0350,
                    expected_mepc_sh,
                    "SH mepc"
                );

                check_mem64(
                    64'h0000_0000_0000_0358,
                    MCAUSE_STORE_ADDR_MISALIGNED,
                    "SW mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0360,
                    expected_mepc_sw,
                    "SW mepc"
                );

                check_mem64(
                    64'h0000_0000_0000_0368,
                    MCAUSE_STORE_ADDR_MISALIGNED,
                    "SD mcause"
                );

                check_mem64(
                    64'h0000_0000_0000_0370,
                    expected_mepc_sd,
                    "SD mepc"
                );

            // =====================================================
            // Ausencia de efectos laterales
            // =====================================================

                check_mem64(
                    64'h0000_0000_0000_0180,
                    STORE_SENTINEL_0,
                    "memoria 0x180 sin modificar"
                );

                check_mem64(
                    64'h0000_0000_0000_0188,
                    STORE_SENTINEL_1,
                    "memoria 0x188 sin modificar"
                );

                check_mem64(
                    DONE_ADDR,
                    64'h0000_0000_0000_007F,
                    "marcador final"
                );

                if (bad_misaligned_req_seen) begin
                    $display(
                        "FAIL : un acceso desalineado generó dmem_req"
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : ningún load/store desalineado generó dmem_req"
                    );
                end

                if (unexpected_exp_seen) begin
                    $display(
                        "FAIL : hubo tráfico inesperado hacia exp_*"
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : ningún acceso fue enviado al puerto exp_*"
                    );
                end

            // =====================================================
            // Tráfico DMEM esperado
            //
            // Stores alineados de evidencia:
            //
            // LH -> mcause, mepc, x5 : 3
            // LW -> mcause, mepc, x5 : 3
            // LD -> mcause, mepc, x5 : 3
            // SH -> mcause, mepc     : 2
            // SW -> mcause, mepc     : 2
            // SD -> mcause, mepc     : 2
            // marcador final         : 1
            //
            // Total = 16.
            //
            // Las 6 instrucciones desalineadas NO deben aparecer
            // entre estas transacciones.
            // =====================================================

                if (accepted_count != 16) begin
                    $display(
                        "FAIL : accepted_count=%0d esperado=16",
                        accepted_count
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : transacciones DMEM aceptadas = %0d",
                        accepted_count
                    );
                end

                if (response_count != 16) begin
                    $display(
                        "FAIL : response_count=%0d esperado=16",
                        response_count
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : respuestas DMEM recibidas = %0d",
                        response_count
                    );
                end

                if (store_accept_count != 16) begin
                    $display(
                        "FAIL : store_accept_count=%0d esperado=16",
                        store_accept_count
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : stores alineados aceptados = %0d",
                        store_accept_count
                    );
                end

                if (pending_valid) begin
                    $display(
                        "FAIL : queda una transacción DMEM outstanding"
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : no quedan transacciones DMEM outstanding"
                    );
                end

                if (wait_gnt_cycles == 0) begin
                    $display(
                        "FAIL : no se ejerció WAIT_GNT"
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : WAIT_GNT observado durante %0d ciclos",
                        wait_gnt_cycles
                    );
                end

                if (wait_resp_cycles == 0) begin
                    $display(
                        "FAIL : no se ejerció WAIT_RESP"
                    );
                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : WAIT_RESP observado durante %0d ciclos",
                        wait_resp_cycles
                    );
                end

            // =====================================================
            // Resultado
            // =====================================================

                $display("==============================================");

                if (errors != 0) begin
                    $display(
                        "FAIL: tb_core_mem_misaligned_trap errors=%0d",
                        errors
                    );
                    $display("==============================================");
                    $fatal(1);
                end
                else begin
                    $display(
                        "PASS: load/store misaligned traps funcionando"
                    );
                    $display(
                        "      LH/LW/LD -> mcause=4"
                    );
                    $display(
                        "      SH/SW/SD -> mcause=6"
                    );
                    $display(
                        "      mepc preciso"
                    );
                    $display(
                        "      sin efectos laterales de memoria"
                    );
                    $display(
                        "      accesos desalineados no generan dmem_req"
                    );
                    $display(
                        "      stores de evidencia usan handshake síncrono"
                    );
                    $display("==============================================");
                end

                $finish;
        end

endmodule
