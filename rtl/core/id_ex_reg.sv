`timescale 1ns/1ps


module id_ex_reg (
    input  logic        clk,
    input  logic        rst,

    input  logic        stall,
    input  logic        flush,

    // -----------------------------
    // Entradas desde ID
    // -----------------------------
    input  logic        id_valid_in,
    input  logic [63:0] id_pc_in,
    input  logic [31:0] id_instr_in,

    input  logic [4:0]  id_rs1_addr_in,
    input  logic [4:0]  id_rs2_addr_in,
    input  logic [4:0]  id_rd_addr_in,

    input  logic [63:0] id_rs1_data_in,
    input  logic [63:0] id_rs2_data_in,
    input  logic [63:0] id_imm_in,

    input  logic        id_reg_write_in,
    input  logic        id_mem_write_in,
    input  logic [1:0]  id_store_size_in,
    input  logic        id_wb_sel_pc4_in,

    input  logic [1:0]  id_alu_src_a_sel_in,
    input  logic        id_alu_src_b_sel_in,
    input  logic [3:0]  id_alu_op_in,

    input  logic        id_branch_in,
    input  logic [2:0]  id_branch_op_in,
    input  logic        id_jump_in,

    input  logic        id_illegal_instr_in,

    input  logic        id_mem_read_in,
    input  logic [1:0]  id_load_size_in,
    input  logic        id_load_unsigned_in,
    input  logic        id_wb_sel_mem_in,

    input  logic        id_csr_en_in,
    input  logic [1:0]  id_csr_cmd_in,
    input  logic        id_csr_use_imm_in,
    input  logic        id_csr_read_in,
    input  logic        id_csr_write_in,

    input  logic        id_sys_ecall_in,
    input  logic        id_sys_ebreak_in,
    input  logic        id_sys_mret_in,

    // -----------------------------
    // Salidas hacia EX
    // -----------------------------
    output logic        ex_valid_out,
    output logic [63:0] ex_pc_out,
    output logic [31:0] ex_instr_out,

    output logic [4:0]  ex_rs1_addr_out,
    output logic [4:0]  ex_rs2_addr_out,
    output logic [4:0]  ex_rd_addr_out,

    output logic [63:0] ex_rs1_data_out,
    output logic [63:0] ex_rs2_data_out,
    output logic [63:0] ex_imm_out,

    output logic        ex_reg_write_out,
    output logic        ex_mem_write_out,
    output logic [1:0]  ex_store_size_out,
    output logic        ex_wb_sel_pc4_out,

    output logic [1:0]  ex_alu_src_a_sel_out,
    output logic        ex_alu_src_b_sel_out,
    output logic [3:0]  ex_alu_op_out,

    output logic        ex_branch_out,
    output logic [2:0]  ex_branch_op_out,
    output logic        ex_jump_out,

    output logic        ex_illegal_instr_out, 

    output logic        ex_mem_read_out,
    output logic [1:0]  ex_load_size_out,
    output logic        ex_load_unsigned_out,
    output logic        ex_wb_sel_mem_out,

    output logic        ex_csr_en_out,
    output logic [1:0]  ex_csr_cmd_out,
    output logic        ex_csr_use_imm_out,
    output logic        ex_csr_read_out,
    output logic        ex_csr_write_out,

    output logic        ex_sys_ecall_out,
    output logic        ex_sys_ebreak_out,
    output logic        ex_sys_mret_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            ex_valid_out         <= 1'b0;
            ex_pc_out            <= 64'd0;
            ex_instr_out         <= 32'd0;

            ex_rs1_addr_out      <= 5'd0;
            ex_rs2_addr_out      <= 5'd0;
            ex_rd_addr_out       <= 5'd0;

            ex_rs1_data_out      <= 64'd0;
            ex_rs2_data_out      <= 64'd0;
            ex_imm_out           <= 64'd0;

            ex_reg_write_out     <= 1'b0;
            ex_mem_write_out     <= 1'b0;
            ex_store_size_out    <= 2'b00;
            ex_wb_sel_pc4_out    <= 1'b0;

            ex_alu_src_a_sel_out <= 2'b00;
            ex_alu_src_b_sel_out <= 1'b0;
            ex_alu_op_out        <= 4'd0;

            ex_branch_out        <= 1'b0;
            ex_branch_op_out     <= 3'b000;
            ex_jump_out          <= 1'b0;

            ex_illegal_instr_out <= 1'b0;

            ex_mem_read_out      <= 1'b0;
            ex_load_size_out     <= 2'b00;
            ex_load_unsigned_out <= 1'b0;
            ex_wb_sel_mem_out    <= 1'b0;

            ex_csr_en_out       <= 1'b0;
            ex_csr_cmd_out      <= 2'b00;
            ex_csr_use_imm_out  <= 1'b0;
            ex_csr_read_out     <= 1'b0;
            ex_csr_write_out    <= 1'b0;

            ex_sys_ecall_out    <= 1'b0;
            ex_sys_ebreak_out   <= 1'b0;
            ex_sys_mret_out     <= 1'b0;
        end
        else if (flush) begin
            // Inserta burbuja hacia EX
            ex_valid_out         <= 1'b0;
            ex_pc_out            <= 64'd0;
            ex_instr_out         <= 32'd0;

            ex_rs1_addr_out      <= 5'd0;
            ex_rs2_addr_out      <= 5'd0;
            ex_rd_addr_out       <= 5'd0;

            ex_rs1_data_out      <= 64'd0;
            ex_rs2_data_out      <= 64'd0;
            ex_imm_out           <= 64'd0;

            ex_reg_write_out     <= 1'b0;
            ex_mem_write_out     <= 1'b0;
            ex_store_size_out    <= 2'b00;
            ex_wb_sel_pc4_out    <= 1'b0;

            ex_alu_src_a_sel_out <= 2'b00;
            ex_alu_src_b_sel_out <= 1'b0;
            ex_alu_op_out        <= 4'd0;

            ex_branch_out        <= 1'b0;
            ex_branch_op_out     <= 3'b000;
            ex_jump_out          <= 1'b0;

            ex_illegal_instr_out <= 1'b0;

            ex_mem_read_out      <= 1'b0;
            ex_load_size_out     <= 2'b00;
            ex_load_unsigned_out <= 1'b0;
            ex_wb_sel_mem_out    <= 1'b0;

            ex_csr_en_out       <= 1'b0;
            ex_csr_cmd_out      <= 2'b00;
            ex_csr_use_imm_out  <= 1'b0;
            ex_csr_read_out     <= 1'b0;
            ex_csr_write_out    <= 1'b0;

            ex_sys_ecall_out    <= 1'b0;
            ex_sys_ebreak_out   <= 1'b0;
            ex_sys_mret_out     <= 1'b0;
        end
        else if (stall) begin
            // Mantener el contenido actual
        end
        else begin
            ex_valid_out         <= id_valid_in;
            ex_pc_out            <= id_pc_in;
            ex_instr_out         <= id_instr_in;

            ex_rs1_addr_out      <= id_rs1_addr_in;
            ex_rs2_addr_out      <= id_rs2_addr_in;
            ex_rd_addr_out       <= id_rd_addr_in;

            ex_rs1_data_out      <= id_rs1_data_in;
            ex_rs2_data_out      <= id_rs2_data_in;
            ex_imm_out           <= id_imm_in;

            ex_reg_write_out     <= id_reg_write_in;
            ex_mem_write_out     <= id_mem_write_in;
            ex_store_size_out    <= id_store_size_in;
            ex_wb_sel_pc4_out    <= id_wb_sel_pc4_in;

            ex_alu_src_a_sel_out <= id_alu_src_a_sel_in;
            ex_alu_src_b_sel_out <= id_alu_src_b_sel_in;
            ex_alu_op_out        <= id_alu_op_in;

            ex_branch_out        <= id_branch_in;
            ex_branch_op_out     <= id_branch_op_in;
            ex_jump_out          <= id_jump_in;

            ex_illegal_instr_out <= id_illegal_instr_in;

            ex_mem_read_out      <= id_mem_read_in;
            ex_load_size_out     <= id_load_size_in;
            ex_load_unsigned_out <= id_load_unsigned_in;
            ex_wb_sel_mem_out    <= id_wb_sel_mem_in;

            ex_csr_en_out       <= id_csr_en_in;
            ex_csr_cmd_out      <= id_csr_cmd_in;
            ex_csr_use_imm_out  <= id_csr_use_imm_in;
            ex_csr_read_out     <= id_csr_read_in;
            ex_csr_write_out    <= id_csr_write_in;

            ex_sys_ecall_out    <= id_sys_ecall_in;
            ex_sys_ebreak_out   <= id_sys_ebreak_in;
            ex_sys_mret_out     <= id_sys_mret_in;
        end
    end

endmodule
