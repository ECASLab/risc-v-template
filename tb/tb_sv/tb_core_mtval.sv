`timescale 1ns/1ps

module tb_core_mtval;

    // =========================================================
    // Configuración
    // =========================================================

    localparam logic [63:0] RESET_PC    =
        64'h0000_0000_0000_0000;

    localparam logic [63:0] TRAP_VECTOR =
        64'h0000_0000_0000_0100;

    localparam logic [63:0] RESULT_BASE =
        64'h0000_0000_0000_0300;

    localparam logic [63:0] DONE_ADDR =
        64'h0000_0000_0000_03C8;

    localparam logic [63:0] MMIO_LOAD_FAULT_ADDR =
        64'h0000_0000_8000_0040;

    localparam logic [63:0] MMIO_STORE_FAULT_ADDR =
        64'h0000_0000_8000_0030;

    localparam logic [63:0] STORE_SENTINEL =
        64'h1122_3344_5566_7788;

    // ---------------------------------------------------------
    // Causas arquitecturales
    // ---------------------------------------------------------

    localparam logic [63:0] MCAUSE_INSTR_ADDR_MISALIGNED =
        64'd0;

    localparam logic [63:0] MCAUSE_ILLEGAL_INSTR =
        64'd2;

    localparam logic [63:0] MCAUSE_BREAKPOINT =
        64'd3;

    localparam logic [63:0] MCAUSE_LOAD_ADDR_MISALIGNED =
        64'd4;

    localparam logic [63:0] MCAUSE_LOAD_ACCESS_FAULT =
        64'd5;

    localparam logic [63:0] MCAUSE_STORE_ADDR_MISALIGNED =
        64'd6;

    localparam logic [63:0] MCAUSE_STORE_ACCESS_FAULT =
        64'd7;

    localparam logic [63:0] MCAUSE_ECALL_M =
        64'd11;

    // ---------------------------------------------------------
    // Opcodes
    // ---------------------------------------------------------

    localparam logic [6:0] OPCODE_LOAD =
        7'b0000011;

    localparam logic [6:0] OPCODE_OP_IMM =
        7'b0010011;

    localparam logic [6:0] OPCODE_STORE =
        7'b0100011;

    localparam logic [6:0] OPCODE_JAL =
        7'b1101111;

    localparam logic [6:0] OPCODE_SYSTEM =
        7'b1110011;

    // =========================================================
    // DUT
    // =========================================================

    logic clk;
    logic rst;

    localparam int unsigned IMEM_WORDS = 256;

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
    // Adaptador temporal para los modelos combinacionales
    // de memoria usados por este testbench.
    //
    // El core utiliza el handshake definitivo, mientras este
    // adaptador proporciona grant inmediato y rvalid +1 ciclo.
    // =========================================================
    dmem_legacy_compat u_dmem_legacy_compat (
        .clk      (clk),
        .rst      (rst),
        .req_i    (dmem_req),
        .gnt_o    (dmem_gnt),
        .rvalid_o (dmem_rvalid),
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
    // Memorias
    // =========================================================

        logic [63:0] data_mem [0:255];

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

        assign dmem_rdata =
            data_mem[dmem_addr[10:3]];

    // =========================================================
    // Modelo de expansión
    //
    // Los dos accesos indicados se responden inmediatamente
    // con error para provocar load/store access fault.
    // =========================================================

        assign exp_ready = 1'b1;
        assign exp_rdata = 64'd0;

        assign exp_error =
            exp_valid &&
            (
                (exp_addr == MMIO_LOAD_FAULT_ADDR) ||
                (exp_addr == MMIO_STORE_FAULT_ADDR)
            );

    // =========================================================
    // Estado del testbench
    // =========================================================

        logic [63:0] prog_pc;

        logic [63:0] expected_mepc_lh;
        logic [63:0] expected_mepc_sh;
        logic [63:0] expected_mepc_mmio_load;
        logic [63:0] expected_mepc_mmio_store;
        logic [63:0] expected_mepc_jal;
        logic [63:0] expected_mepc_illegal;
        logic [63:0] expected_mepc_ecall;
        logic [63:0] expected_mepc_ebreak;

        logic [63:0] expected_jal_target;

        logic seen_done;
        logic seen_mmio_load_fault;
        logic seen_mmio_store_fault;
        logic bad_misaligned_store_seen;

        integer errors;
        integer cycles;
        integer i;
        integer lane;

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

        function automatic logic [31:0] enc_j(
            input logic [20:0] imm,
            input logic [4:0]  rd
        );
            begin
                enc_j = {
                    imm[20],
                    imm[10:1],
                    imm[11],
                    imm[19:12],
                    rd,
                    OPCODE_JAL
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

    // =========================================================
    // Emisión de programa
    // =========================================================

        task automatic emit(
            input logic [31:0] instr
        );
            begin
                u_imem.mem[prog_pc[9:2]] = instr;
                prog_pc = prog_pc + 64'd4;
            end
        endtask

        // Guarda:
        //
        // base + 0  -> mcause, x20
        // base + 8  -> mepc,   x21
        // base + 16 -> mtval,  x22
        //
        task automatic emit_trap_evidence(
            input logic [11:0] offset
        );
            begin
                emit(
                    enc_s(
                        offset,
                        5'd20,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                emit(
                    enc_s(
                        offset + 12'd8,
                        5'd21,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );

                emit(
                    enc_s(
                        offset + 12'd16,
                        5'd22,
                        5'd10,
                        3'b011,
                        OPCODE_STORE
                    )
                );
            end
        endtask

    // =========================================================
    // Checks
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
                        "FAIL : %-36s got=0x%016h expected=0x%016h",
                        label_text,
                        got,
                        expected
                    );

                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS : %-36s = 0x%016h",
                        label_text,
                        got
                    );
                end
            end
        endtask

        task automatic check_triplet(
            input logic [63:0] base,
            input logic [63:0] expected_cause,
            input logic [63:0] expected_mepc,
            input logic [63:0] expected_mtval,
            input string       label_text
        );
            begin
                check_mem64(
                    base,
                    expected_cause,
                    $sformatf("%s mcause", label_text)
                );

                check_mem64(
                    base + 64'd8,
                    expected_mepc,
                    $sformatf("%s mepc", label_text)
                );

                check_mem64(
                    base + 64'd16,
                    expected_mtval,
                    $sformatf("%s mtval", label_text)
                );
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
    // RAM de datos + monitores
    // =========================================================

        always @(posedge clk) begin
            if (rst) begin
                seen_done                  <= 1'b0;
                seen_mmio_load_fault       <= 1'b0;
                seen_mmio_store_fault      <= 1'b0;
                bad_misaligned_store_seen <= 1'b0;
            end
            else begin

                // -------------------------------------------------
                // Comprobación de los access faults MMIO
                // -------------------------------------------------

                if (
                    exp_valid &&
                    !exp_we &&
                    (exp_addr == MMIO_LOAD_FAULT_ADDR)
                ) begin
                    seen_mmio_load_fault <= 1'b1;
                end

                if (
                    exp_valid &&
                    exp_we &&
                    (exp_addr == MMIO_STORE_FAULT_ADDR)
                ) begin
                    seen_mmio_store_fault <= 1'b1;
                end

                // -------------------------------------------------
                // Stores normales a memoria
                // -------------------------------------------------

                if (dmem_we) begin

                    for (lane = 0; lane < 8; lane = lane + 1) begin
                        if (dmem_wstrb[lane]) begin
                            data_mem[dmem_addr[10:3]]
                                    [(lane*8) +: 8]
                                <= dmem_wdata[(lane*8) +: 8];
                        end
                    end

                    // El SH a 0x181 nunca debe convertirse
                    // en escritura real.
                    if (
                        dmem_addr ==
                        64'h0000_0000_0000_0181
                    ) begin
                        bad_misaligned_store_seen <= 1'b1;

                        $display(
                            "ERROR: SH desalineado activó dmem_we"
                        );
                    end

                    if (dmem_addr == DONE_ADDR) begin
                        seen_done <= 1'b1;
                    end
                end
            end
        end

    // =========================================================
    // Programa
    // =========================================================

    initial begin

        rst = 1'b1;

        errors = 0;
        cycles = 0;

        // -----------------------------------------------------
        // Limpiar memorias
        // -----------------------------------------------------

        for (i = 0; i < 256; i = i + 1) begin
            u_imem.mem[i] = 32'h0000_0013;
            data_mem[i]  = 64'd0;
        end

        // Valor que debe permanecer intacto ante SH misaligned.
        data_mem[8'h30] = STORE_SENTINEL;

        // =====================================================
        // Programa principal
        // =====================================================

            prog_pc = 64'd0;

            // -----------------------------------------------------
            // x10 = 0x300
            // Base de resultados.
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
        // PRUEBA 0:
        // mtval debe ser un CSR RW normal.
        //
        // x5 = 0x55
        // csrw mtval, x5
        // csrr x6, mtval
        // store x6 -> 0x300
        // =====================================================

            emit(
                enc_i(
                    12'h055,
                    5'd0,
                    3'b000,
                    5'd5,
                    OPCODE_OP_IMM
                )
            );

            // CSRRW x0, mtval(0x343), x5
            emit(
                enc_csr(
                    12'h343,
                    5'd5,
                    3'b001,
                    5'd0
                )
            );

            // CSRRS x6, mtval, x0
            emit(
                enc_csr(
                    12'h343,
                    5'd0,
                    3'b010,
                    5'd6
                )
            );

            // SD x6, 0(x10)
            emit(
                enc_s(
                    12'h000,
                    5'd6,
                    5'd10,
                    3'b011,
                    OPCODE_STORE
                )
            );

        // =====================================================
        // PRUEBA 1:
        // LH desalineado
        //
        // addr = 0x101
        // mcause = 4
        // mtval  = 0x101
        // =====================================================

            emit(
                enc_i(
                    12'h101,
                    5'd0,
                    3'b000,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

            expected_mepc_lh = prog_pc;

            emit(
                enc_i(
                    12'h000,
                    5'd1,
                    3'b001,
                    5'd5,
                    OPCODE_LOAD
                )
            );

            emit_trap_evidence(12'h008);

        // =====================================================
        // PRUEBA 2:
        // SH desalineado
        //
        // addr = 0x181
        // mcause = 6
        // mtval  = 0x181
        // =====================================================

            emit(
                enc_i(
                    12'h181,
                    5'd0,
                    3'b000,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

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

            emit(
                enc_s(
                    12'h000,
                    5'd2,
                    5'd1,
                    3'b001,
                    OPCODE_STORE
                )
            );

            emit_trap_evidence(12'h020);

        // =====================================================
        // PRUEBA 3:
        // Load access fault en expansión
        //
        // Construir:
        // x1 = 0x0000000080000040
        //
        // 1 << 31 = 0x80000000
        // + 0x40
        // =====================================================

            emit(
                enc_i(
                    12'h001,
                    5'd0,
                    3'b000,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

            // SLLI x1, x1, 31
            emit(
                enc_i(
                    12'h01F,
                    5'd1,
                    3'b001,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

            emit(
                enc_i(
                    12'h040,
                    5'd1,
                    3'b000,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

            expected_mepc_mmio_load = prog_pc;

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

            emit_trap_evidence(12'h038);

        // =====================================================
        // PRUEBA 4:
        // Store access fault en expansión
        //
        // 0x80000040 - 16 = 0x80000030
        // =====================================================

            // ADDI x1, x1, -16
            emit(
                enc_i(
                    12'hFF0,
                    5'd1,
                    3'b000,
                    5'd1,
                    OPCODE_OP_IMM
                )
            );

            emit(
                enc_i(
                    12'h05A,
                    5'd0,
                    3'b000,
                    5'd2,
                    OPCODE_OP_IMM
                )
            );

            expected_mepc_mmio_store = prog_pc;

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

            emit_trap_evidence(12'h050);

        // =====================================================
        // PRUEBA 5:
        // Instruction address misaligned.
        //
        // JAL x0, +2
        //
        // Con IALIGN=32 el target PC+2 es ilegal.
        // mepc  = PC del JAL
        // mtval = PC+2
        // =====================================================

            expected_mepc_jal =
                prog_pc;

            expected_jal_target =
                prog_pc + 64'd2;

            emit(
                enc_j(
                    21'd2,
                    5'd0
                )
            );

            emit_trap_evidence(12'h068);

        // =====================================================
        // PRUEBA 6:
        // Instrucción ilegal.
        //
        // Opcode 0x7F no implementado.
        //
        // mtval debe contener:
        // 0x000000000000007F
        // =====================================================

            expected_mepc_illegal =
                prog_pc;

            emit(
                32'h0000_007F
            );

            emit_trap_evidence(12'h080);

        // =====================================================
        // PRUEBA 7:
        // ECALL M-mode.
        //
        // mcause = 11
        // mtval  = 0
        // =====================================================

            expected_mepc_ecall =
                prog_pc;

            emit(
                32'h0000_0073
            );

            emit_trap_evidence(12'h098);

        // =====================================================
        // PRUEBA 8:
        // EBREAK.
        //
        // Elegimos la política:
        // mtval = 0
        // =====================================================

            expected_mepc_ebreak =
                prog_pc;

            emit(
                32'h0010_0073
            );

            emit_trap_evidence(12'h0B0);

        // =====================================================
        // Marcador final
        // =====================================================

            emit(
                enc_i(
                    12'h07F,
                    5'd0,
                    3'b000,
                    5'd2,
                    OPCODE_OP_IMM
                )
            );

            // SD x2, 0xC8(x10)
            emit(
                enc_s(
                    12'h0C8,
                    5'd2,
                    5'd10,
                    3'b011,
                    OPCODE_STORE
                )
            );

            // Loop infinito.
            emit(
                32'h0000_006F
            );

        // =====================================================
        // Handler @ 0x100
        //
        // x20 = mcause
        // x21 = mepc
        // x22 = mtval
        // x23 = mepc + 4
        //
        // Se actualiza mepc y se retorna.
        // =====================================================

            // CSRRS x20, mcause, x0
            u_imem.mem[8'h40] =
                enc_csr(
                    12'h342,
                    5'd0,
                    3'b010,
                    5'd20
                );

            // CSRRS x21, mepc, x0
            u_imem.mem[8'h41] =
                enc_csr(
                    12'h341,
                    5'd0,
                    3'b010,
                    5'd21
                );

            // CSRRS x22, mtval, x0
            u_imem.mem[8'h42] =
                enc_csr(
                    12'h343,
                    5'd0,
                    3'b010,
                    5'd22
                );

            // ADDI x23, x21, 4
            u_imem.mem[8'h43] =
                enc_i(
                    12'h004,
                    5'd21,
                    3'b000,
                    5'd23,
                    OPCODE_OP_IMM
                );

            // CSRRW x0, mepc, x23
            u_imem.mem[8'h44] =
                enc_csr(
                    12'h341,
                    5'd23,
                    3'b001,
                    5'd0
                );

            // MRET
            u_imem.mem[8'h45] =
                32'h3020_0073;

        // =====================================================
        // VCD
        // =====================================================

            $dumpfile(
                "build/tb_core_mtval.vcd"
            );

            $dumpvars(
                0,
                tb_core_mtval
            );

        // =====================================================
        // Reset
        // =====================================================

            repeat (4) @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

        // =====================================================
        // Esperar finalización
        // =====================================================

            while (
                (!seen_done) &&
                (cycles < 1500)
            ) begin

                @(posedge clk);
                cycles = cycles + 1;
            end

            if (!seen_done) begin
                $display(
                    "=============================================="
                );

                $display(
                    "FAIL: timeout en tb_core_mtval"
                );

                $display(
                    "cycles = %0d",
                    cycles
                );

                $display(
                    "=============================================="
                );

                $fatal(1);
            end

            repeat (4) @(posedge clk);

        // =====================================================
        // Resultados
        // =====================================================

            $display("");
            $display(
                "=============================================="
            );

            $display(
                "TB core mtval"
            );

            $display(
                "=============================================="
            );

            // -----------------------------------------------------
            // CSR RW
            // -----------------------------------------------------

            check_mem64(
                RESULT_BASE,
                64'h0000_0000_0000_0055,
                "mtval CSR read/write"
            );

        // -----------------------------------------------------
        // LH misaligned
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0308,
                MCAUSE_LOAD_ADDR_MISALIGNED,
                expected_mepc_lh,
                64'h0000_0000_0000_0101,
                "LH misaligned"
            );

        // -----------------------------------------------------
        // SH misaligned
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0320,
                MCAUSE_STORE_ADDR_MISALIGNED,
                expected_mepc_sh,
                64'h0000_0000_0000_0181,
                "SH misaligned"
            );

        // -----------------------------------------------------
        // MMIO load access fault
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0338,
                MCAUSE_LOAD_ACCESS_FAULT,
                expected_mepc_mmio_load,
                MMIO_LOAD_FAULT_ADDR,
                "MMIO load fault"
            );

        // -----------------------------------------------------
        // MMIO store access fault
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0350,
                MCAUSE_STORE_ACCESS_FAULT,
                expected_mepc_mmio_store,
                MMIO_STORE_FAULT_ADDR,
                "MMIO store fault"
            );

        // -----------------------------------------------------
        // Instruction address misaligned
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0368,
                MCAUSE_INSTR_ADDR_MISALIGNED,
                expected_mepc_jal,
                expected_jal_target,
                "JAL misaligned"
            );

        // -----------------------------------------------------
        // Illegal instruction
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0380,
                MCAUSE_ILLEGAL_INSTR,
                expected_mepc_illegal,
                64'h0000_0000_0000_007F,
                "illegal instruction"
            );

        // -----------------------------------------------------
        // ECALL
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_0398,
                MCAUSE_ECALL_M,
                expected_mepc_ecall,
                64'd0,
                "ECALL"
            );

        // -----------------------------------------------------
        // EBREAK
        // -----------------------------------------------------

            check_triplet(
                64'h0000_0000_0000_03B0,
                MCAUSE_BREAKPOINT,
                expected_mepc_ebreak,
                64'd0,
                "EBREAK"
            );

        // -----------------------------------------------------
        // Store misaligned sin efecto lateral
        // -----------------------------------------------------

            check_mem64(
                64'h0000_0000_0000_0180,
                STORE_SENTINEL,
                "SH no modifica memoria"
            );

        // -----------------------------------------------------
        // Marcador final
        // -----------------------------------------------------

            check_mem64(
                DONE_ADDR,
                64'h0000_0000_0000_007F,
                "marcador final"
            );

        // -----------------------------------------------------
        // Los access faults realmente tuvieron transacción
        // hacia expansión.
        // -----------------------------------------------------

            if (!seen_mmio_load_fault) begin
                $display(
                    "FAIL : no se observó MMIO load fault"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : MMIO load fault observado"
                );
            end

            if (!seen_mmio_store_fault) begin
                $display(
                    "FAIL : no se observó MMIO store fault"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : MMIO store fault observado"
                );
            end

            if (bad_misaligned_store_seen) begin
                $display(
                    "FAIL : SH desalineado produjo dmem_we"
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS : SH desalineado sin efecto lateral"
                );
            end

        // =====================================================
        // Resultado global
        // =====================================================

            $display(
                "=============================================="
            );

            if (errors != 0) begin

                $display(
                    "FAIL: tb_core_mtval errors=%0d",
                    errors
                );

                $display(
                    "=============================================="
                );

                $fatal(1);
            end
            else begin

                $display(
                    "PASS: mtval funcionando correctamente"
                );

                $display(
                    "      CSR 0x343 RW"
                );

                $display(
                    "      misaligned load/store"
                );

                $display(
                    "      MMIO access faults"
                );

                $display(
                    "      instruction misaligned"
                );

                $display(
                    "      illegal instruction"
                );

                $display(
                    "      ECALL / EBREAK"
                );

                $display(
                    "=============================================="
                );
            end

            $finish;
    end

    // =========================================================
    // Evitar warnings por señales observadas solo para interfaz
    // =========================================================

    wire _unused_ok = 1'b0 && &{
        1'b0,
        dmem_size,
        exp_wdata,
        exp_wstrb,
        exp_size,
        1'b0
    };

endmodule
