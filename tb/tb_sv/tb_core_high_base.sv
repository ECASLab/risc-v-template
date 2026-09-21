`timescale 1ns/1ps

module tb_core_high_base;

    // =========================================================
    // Mapa de memoria de referencia para la plataforma final.
    //
    // RAM:
    //   0x0000_0000_8000_0000 ...
    //
    // Expansión:
    //   0x0000_0000_1000_0000 - 0x0000_0000_1000_0FFF
    //
    // Este test valida el nuevo mapa sin modificar todavía los
    // valores por defecto de core_top ni los tests históricos.
    // =========================================================

    localparam logic [63:0] RAM_BASE =
        64'h0000_0000_8000_0000;

    localparam logic [63:0] TRAP_VECTOR =
        RAM_BASE + 64'h0000_0000_0000_0100;

    localparam logic [63:0] EXP_BASE =
        64'h0000_0000_1000_0000;

    localparam logic [63:0] DATA_ADDR =
        RAM_BASE + 64'h0000_0000_0000_0200;

    localparam logic [63:0] RESULT_ADDR =
        RAM_BASE + 64'h0000_0000_0000_0208;

    localparam int unsigned IMEM_WORDS = 256;
    localparam int unsigned DMEM_WORDS = 256;

    // =========================================================
    // RISC-V constants
    // =========================================================

    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;

    localparam logic [2:0] F3_ADDI = 3'b000;
    localparam logic [2:0] F3_LD   = 3'b011;
    localparam logic [2:0] F3_SD   = 3'b011;
    localparam logic [2:0] F3_BEQ  = 3'b000;

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
    // IMEM
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
    // Expansión
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
    // =========================================================

    core_top #(
        .RESET_PC    (RAM_BASE),
        .TRAP_VECTOR (TRAP_VECTOR),
        .EXP_BASE    (EXP_BASE)
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
    // Memorias síncronas reales, ambas con base alta.
    // =========================================================

    imem_sync_model #(
        .MEM_WORDS  (IMEM_WORDS),
        .BASE_ADDR  (RAM_BASE),
        .GNT_DELAY  (1),
        .RESP_DELAY (2)
    ) u_imem (
        .clk      (clk),
        .rst      (rst),

        .req_i    (imem_req),
        .gnt_o    (imem_gnt),
        .addr_i   (imem_addr),

        .rvalid_o (imem_rvalid),
        .rdata_o  (imem_rdata)
    );

    dmem_sync_model #(
        .MEM_WORDS    (DMEM_WORDS),
        .BASE_ADDR    (RAM_BASE),
        .GNT_DELAY    (1),
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
    // Encoders mínimos
    // =========================================================

    function automatic logic [31:0] enc_u(
        input logic [19:0] imm20,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        begin
            enc_u = {
                imm20,
                rd,
                opcode
            };
        end
    endfunction

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

    function automatic logic [31:0] enc_b(
        input logic [12:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        begin
            enc_b = {
                imm[12],
                imm[10:5],
                rs2,
                rs1,
                funct3,
                imm[4:1],
                imm[11],
                OPCODE_BRANCH
            };
        end
    endfunction

    // =========================================================
    // Monitores del nuevo mapa
    // =========================================================

    integer imem_accept_count;
    integer dmem_accept_count;

    always @(posedge clk) begin
        if (rst) begin
            imem_accept_count <= 0;
            dmem_accept_count <= 0;
        end
        else begin
            if (exp_valid) begin
                $fatal(
                    1,
                    "FAIL: acceso RAM fue decodificado como expansión addr=0x%016h",
                    exp_addr
                );
            end

            if (imem_req && imem_gnt) begin
                if (
                    (imem_addr < RAM_BASE) ||
                    (imem_addr >= (RAM_BASE + 64'(IMEM_WORDS * 4)))
                ) begin
                    $fatal(
                        1,
                        "FAIL: fetch fuera de RAM alta addr=0x%016h",
                        imem_addr
                    );
                end

                if (
                    (imem_accept_count == 0) &&
                    (imem_addr !== RAM_BASE)
                ) begin
                    $fatal(
                        1,
                        "FAIL: primer fetch addr=0x%016h expected=0x%016h",
                        imem_addr,
                        RAM_BASE
                    );
                end

                imem_accept_count <= imem_accept_count + 1;
            end

            if (dmem_req && dmem_gnt) begin
                case (dmem_accept_count)
                    0: begin
                        if (
                            !dmem_we ||
                            (dmem_addr !== DATA_ADDR)
                        ) begin
                            $fatal(
                                1,
                                "FAIL: primer acceso DMEM inesperado we=%0b addr=0x%016h",
                                dmem_we,
                                dmem_addr
                            );
                        end
                    end

                    1: begin
                        if (
                            dmem_we ||
                            (dmem_addr !== DATA_ADDR)
                        ) begin
                            $fatal(
                                1,
                                "FAIL: segundo acceso DMEM inesperado we=%0b addr=0x%016h",
                                dmem_we,
                                dmem_addr
                            );
                        end
                    end

                    2: begin
                        if (
                            !dmem_we ||
                            (dmem_addr !== RESULT_ADDR)
                        ) begin
                            $fatal(
                                1,
                                "FAIL: tercer acceso DMEM inesperado we=%0b addr=0x%016h",
                                dmem_we,
                                dmem_addr
                            );
                        end
                    end

                    default: begin
                    end
                endcase

                dmem_accept_count <= dmem_accept_count + 1;
            end
        end
    end

    // =========================================================
    // Programa
    //
    // 8000_0000: auipc x1, 0       -> x1 = 0x8000_0000
    // 8000_0004: addi  x2, x0, 42
    // 8000_0008: sd    x2, 0x200(x1)
    // 8000_000c: ld    x3, 0x200(x1)
    // 8000_0010: beq   x3, x2, +8
    // 8000_0014: addi  x4, x0, 99  <- wrong path
    // 8000_0018: addi  x4, x0, 1
    // 8000_001c: sd    x4, 0x208(x1)
    // 8000_0020: addi  x31, x0, 1  <- sentinel
    // 8000_0024: jal   x0, 0
    //
    // Además del mapa alto, este programa conserva cobertura de:
    //   - AUIPC con PC alto
    //   - store/load síncronos
    //   - dependencia load-use hacia branch
    //   - redirect y eliminación de wrong-path
    // =========================================================

    integer i;
    integer timeout;

    initial begin
        $dumpfile("build/tb_core_high_base.vcd");
        $dumpvars(0, tb_core_high_base);

        rst = 1'b1;

        for (i = 0; i < IMEM_WORDS; i = i + 1) begin
            u_imem.mem[i] = 32'h0000_0013;
        end

        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            u_dmem.mem[i] = 64'd0;
        end

        u_imem.mem[0] = enc_u(
            20'h00000,
            5'd1,
            OPCODE_AUIPC
        );

        u_imem.mem[1] = enc_i(
            12'd42,
            5'd0,
            F3_ADDI,
            5'd2,
            OPCODE_OP_IMM
        );

        u_imem.mem[2] = enc_s(
            12'h200,
            5'd2,
            5'd1,
            F3_SD
        );

        u_imem.mem[3] = enc_i(
            12'h200,
            5'd1,
            F3_LD,
            5'd3,
            OPCODE_LOAD
        );

        u_imem.mem[4] = enc_b(
            13'd8,
            5'd2,
            5'd3,
            F3_BEQ
        );

        u_imem.mem[5] = enc_i(
            12'd99,
            5'd0,
            F3_ADDI,
            5'd4,
            OPCODE_OP_IMM
        );

        u_imem.mem[6] = enc_i(
            12'd1,
            5'd0,
            F3_ADDI,
            5'd4,
            OPCODE_OP_IMM
        );

        u_imem.mem[7] = enc_s(
            12'h208,
            5'd4,
            5'd1,
            F3_SD
        );

        u_imem.mem[8] = enc_i(
            12'd1,
            5'd0,
            F3_ADDI,
            5'd31,
            OPCODE_OP_IMM
        );

        u_imem.mem[9] = 32'h0000_006f; // jal x0, 0

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;
        #1;

        timeout = 0;

        while (
            (dut.u_regfile.regs[31] !== 64'd1) &&
            (timeout < 500)
        ) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        if (dut.u_regfile.regs[31] !== 64'd1) begin
            $fatal(
                1,
                "FAIL: timeout esperando sentinel con RAM_BASE=0x%016h",
                RAM_BASE
            );
        end

        if (dut.u_regfile.regs[1] !== RAM_BASE) begin
            $fatal(
                1,
                "FAIL: AUIPC x1=0x%016h expected=0x%016h",
                dut.u_regfile.regs[1],
                RAM_BASE
            );
        end

        if (dut.u_regfile.regs[3] !== 64'd42) begin
            $fatal(
                1,
                "FAIL: load x3=0x%016h expected=42",
                dut.u_regfile.regs[3]
            );
        end

        if (dut.u_regfile.regs[4] !== 64'd1) begin
            $fatal(
                1,
                "FAIL: branch/wrong-path x4=0x%016h expected=1",
                dut.u_regfile.regs[4]
            );
        end

        if (u_dmem.mem[64] !== 64'd42) begin
            $fatal(
                1,
                "FAIL: DATA_ADDR mem=0x%016h expected=42",
                u_dmem.mem[64]
            );
        end

        if (u_dmem.mem[65] !== 64'd1) begin
            $fatal(
                1,
                "FAIL: RESULT_ADDR mem=0x%016h expected=1",
                u_dmem.mem[65]
            );
        end

        if (dmem_accept_count != 3) begin
            $fatal(
                1,
                "FAIL: dmem_accept_count=%0d expected=3",
                dmem_accept_count
            );
        end

        $display("============================================================");
        $display("PASS: core_top ejecuta con RAM_BASE = 0x%016h", RAM_BASE);
        $display("      RESET_PC   = 0x%016h", RAM_BASE);
        $display("      TRAP_VECTOR= 0x%016h", TRAP_VECTOR);
        $display("      EXP_BASE   = 0x%016h", EXP_BASE);
        $display("      AUIPC/load/store/branch + wait-states verificados");
        $display("============================================================");

        $finish;
    end

endmodule
