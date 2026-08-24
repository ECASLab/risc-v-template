`timescale 1ns/1ps

module tb_core_mem_misaligned_trap;

    // =========================================================
    // Configuración
    // =========================================================

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

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

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
    // Memorias del testbench
    // =========================================================

    logic [31:0] instr_mem [0:255];
    logic [63:0] data_mem  [0:255];

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
    logic bad_misaligned_store_seen;
    logic unexpected_exp_seen;

    integer errors;
    integer cycles;
    integer i;
    integer lane;

    // =========================================================
    // DUT
    // =========================================================

    core_top #(
        .RESET_PC    (RESET_PC),
        .TRAP_VECTOR (TRAP_VECTOR)
    ) dut (
        .clk         (clk),
        .rst         (rst),

        .imem_addr   (imem_addr),
        .imem_rdata  (imem_rdata),

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
    // Interfaces de memoria
    //
    // Instruction memory:
    //   256 x 32 bits
    //
    // Data memory:
    //   256 x 64 bits
    //
    // dmem_addr[2:0] selecciona byte lane dentro de una palabra
    // de 64 bits. El índice de memoria usa la dirección alineada.
    // =========================================================

    assign imem_rdata =
        instr_mem[imem_addr[9:2]];

    assign dmem_rdata =
        data_mem[dmem_addr[10:3]];

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
            instr_mem[prog_pc[9:2]] = instr;
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
            got = data_mem[addr[10:3]];

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
    // Modelo de escritura de memoria + monitores
    // =========================================================

    always @(posedge clk) begin
        if (rst) begin
            seen_done                  <= 1'b0;
            bad_misaligned_store_seen <= 1'b0;
            unexpected_exp_seen        <= 1'b0;
        end
        else begin

            // -------------------------------------------------
            // Cualquier acceso al puerto de expansión sería
            // inesperado en este test.
            // -------------------------------------------------

            if (exp_valid) begin
                unexpected_exp_seen <= 1'b1;

                $display(
                    "ERROR: acceso inesperado a expansión addr=0x%016h",
                    exp_addr
                );
            end

            // -------------------------------------------------
            // Aplicar stores válidos a data_mem.
            // -------------------------------------------------

            if (dmem_we) begin

                for (lane = 0; lane < 8; lane = lane + 1) begin
                    if (dmem_wstrb[lane]) begin
                        data_mem[dmem_addr[10:3]][(lane*8) +: 8]
                            <= dmem_wdata[(lane*8) +: 8];
                    end
                end

                // ---------------------------------------------
                // Estos tres stores DEBEN atrapar antes de
                // convertirse en una escritura válida.
                // ---------------------------------------------

                if (
                    (dmem_addr == 64'h0000_0000_0000_0181) ||
                    (dmem_addr == 64'h0000_0000_0000_0182) ||
                    (dmem_addr == 64'h0000_0000_0000_0184)
                ) begin
                    bad_misaligned_store_seen <= 1'b1;

                    $display(
                        "ERROR: store desalineado produjo dmem_we addr=0x%016h",
                        dmem_addr
                    );
                end

                // ---------------------------------------------
                // Marca final del programa.
                // ---------------------------------------------

                if (dmem_addr == DONE_ADDR) begin
                    seen_done <= 1'b1;
                end
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

        for (i = 0; i < 256; i = i + 1) begin
            // NOP = ADDI x0, x0, 0
            instr_mem[i] = 32'h0000_0013;
            data_mem[i]  = 64'd0;
        end

        // Datos que podrían ser leídos incorrectamente por
        // los loads desalineados.
        //
        // 0x100 ... 0x107
        data_mem[8'h20] = LOAD_SOURCE_VALUE;

        // Zona que los stores desalineados intentarán modificar.
        //
        // 0x180 ... 0x187
        data_mem[8'h30] = STORE_SENTINEL_0;

        // 0x188 ... 0x18F
        data_mem[8'h31] = STORE_SENTINEL_1;

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
        instr_mem[8'h40] =
            enc_csr(
                12'h342,
                5'd0,
                3'b010,
                5'd20
            );

        // 0x104:
        // CSRRS x21, mepc, x0
        instr_mem[8'h41] =
            enc_csr(
                12'h341,
                5'd0,
                3'b010,
                5'd21
            );

        // 0x108:
        // ADDI x22, x21, 4
        instr_mem[8'h42] =
            enc_i(
                12'h004,
                5'd21,
                3'b000,
                5'd22,
                OPCODE_OP_IMM
            );

        // 0x10C:
        // CSRRW x0, mepc, x22
        instr_mem[8'h43] =
            enc_csr(
                12'h341,
                5'd22,
                3'b001,
                5'd0
            );

        // 0x110:
        // MRET
        instr_mem[8'h44] = 32'h3020_0073;

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

        if (bad_misaligned_store_seen) begin
            $display(
                "FAIL : un store desalineado activó dmem_we"
            );
            errors = errors + 1;
        end
        else begin
            $display(
                "PASS : stores desalineados nunca activaron dmem_we"
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
            $display("==============================================");
        end

        $finish;
    end

endmodule
