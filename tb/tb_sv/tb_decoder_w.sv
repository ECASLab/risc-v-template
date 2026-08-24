`timescale 1ns/1ps

// Testbench para verificar la decodificación de instrucciones tipo *W (ADDIW, SLLIW, SRLIW, SRAIW, ADDW, SUBW, SLLW, SRLW, SRAW)
// Solo se verifica que se genere la señal alu_op correcta y que se reconozca como instrucción legal.
// No se verifica el resto de señales de control para estas instrucciones porque el core no las implementa completamente (por ejemplo, no implementa loads tipo *W, ni el uso de rs2 para las instrucciones tipo R-W).
// Para pruebas más completas de estas instrucciones, se recomienda usar el testbench tb_core_directed.sv con programas que usen estas instrucciones y verificar el comportamiento completo del core.

module tb_decoder_w;

    logic [31:0] instr;

    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;

    logic [2:0]  imm_sel;

    logic        reg_write;
    logic        mem_write;
    logic [1:0]  store_size;

    logic        mem_read;
    logic [1:0]  load_size;
    logic        load_unsigned;
    logic        wb_sel_mem;

    logic        rs1_used;
    logic        rs2_used;

    logic        wb_sel_pc4;

    logic [1:0]  alu_src_a_sel;
    logic        alu_src_b_sel;
    logic [3:0]  alu_op;

    logic        branch;
    logic [2:0]  branch_op;
    logic        jump;

    logic        illegal_instr;

    decoder dut (
        .instr(instr),

        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),

        .imm_sel(imm_sel),

        .reg_write(reg_write),
        .mem_write(mem_write),
        .store_size(store_size),

        .mem_read(mem_read),
        .load_size(load_size),
        .load_unsigned(load_unsigned),
        .wb_sel_mem(wb_sel_mem),

        .csr_en(),
        .csr_cmd(),
        .csr_use_imm(),
        .csr_read(),
        .csr_write(),

        .rs1_used(rs1_used),
        .rs2_used(rs2_used),

        .wb_sel_pc4(wb_sel_pc4),

        .alu_src_a_sel(alu_src_a_sel),
        .alu_src_b_sel(alu_src_b_sel),
        .alu_op(alu_op),

        .branch(branch),
        .branch_op(branch_op),
        .jump(jump),

        .illegal_instr(illegal_instr),

        .sys_ecall(),
        .sys_ebreak(),
        .sys_mret()
    );

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_ADDW = 4'd11;
    localparam logic [3:0] ALU_SUBW = 4'd12;
    localparam logic [3:0] ALU_SLLW = 4'd13;
    localparam logic [3:0] ALU_SRLW = 4'd14;
    localparam logic [3:0] ALU_SRAW = 4'd15;

    task automatic check_decode(
        input [255:0] test_name,
        input [3:0]   exp_alu_op,
        input         exp_reg_write,
        input         exp_illegal
    );
    begin
        #1;
        if ((illegal_instr !== exp_illegal) ||
            (reg_write !== exp_reg_write) ||
            ((exp_illegal == 1'b0) && (alu_op !== exp_alu_op))) begin

            $display("ERROR: %s", test_name);
            $display("  instr         = 0x%08h", instr);
            $display("  alu_op        = %0d", alu_op);
            $display("  reg_write     = %0d", reg_write);
            $display("  illegal_instr = %0d", illegal_instr);
            if (exp_illegal == 1'b0)
                $display("  esperado alu_op = %0d", exp_alu_op);
            $display("  esperado reg_write = %0d", exp_reg_write);
            $display("  esperado illegal   = %0d", exp_illegal);
            $fatal(1);
        end
        else begin
            $display("OK: %s", test_name);
        end
    end
    endtask

    initial begin
        $display("==== Iniciando pruebas decoder OP-IMM-32 / OP-32 ====");

        // ADDIW x1, x2, 1
        instr = 32'b000000000001_00010_000_00001_0011011;
        check_decode("ADDIW", ALU_ADDW, 1'b1, 1'b0);

        // SLLIW x1, x2, 3
        instr = 32'b0000000_00011_00010_001_00001_0011011;
        check_decode("SLLIW", ALU_SLLW, 1'b1, 1'b0);

        // SRLIW x1, x2, 4
        instr = 32'b0000000_00100_00010_101_00001_0011011;
        check_decode("SRLIW", ALU_SRLW, 1'b1, 1'b0);

        // SRAIW x1, x2, 4
        instr = 32'b0100000_00100_00010_101_00001_0011011;
        check_decode("SRAIW", ALU_SRAW, 1'b1, 1'b0);

        // ADDW x1, x2, x3
        instr = 32'b0000000_00011_00010_000_00001_0111011;
        check_decode("ADDW", ALU_ADDW, 1'b1, 1'b0);

        // SUBW x1, x2, x3
        instr = 32'b0100000_00011_00010_000_00001_0111011;
        check_decode("SUBW", ALU_SUBW, 1'b1, 1'b0);

        // SLLW x1, x2, x3
        instr = 32'b0000000_00011_00010_001_00001_0111011;
        check_decode("SLLW", ALU_SLLW, 1'b1, 1'b0);

        // SRLW x1, x2, x3
        instr = 32'b0000000_00011_00010_101_00001_0111011;
        check_decode("SRLW", ALU_SRLW, 1'b1, 1'b0);

        // SRAW x1, x2, x3
        instr = 32'b0100000_00011_00010_101_00001_0111011;
        check_decode("SRAW", ALU_SRAW, 1'b1, 1'b0);

        // Caso ilegal: SLLIW con funct7 inválido
        // En caso ilegal no fuerzo alu_op esperado porque depende de cómo dejes defaults
        instr = 32'b0100000_00011_00010_001_00001_0011011;
        check_decode("SLLIW ilegal", ALU_ADD, 1'b1, 1'b1);

        $display("==== Todas las pruebas del decoder pasaron ====");
        $finish;
    end

endmodule
