`timescale 1ns/1ps

module ex_mem_reg (
    input  logic        clk,
    input  logic        rst,

    input  logic        stall,
    input  logic        flush,

    // -----------------------------
    // Entradas desde EX
    // -----------------------------
    input  logic        ex_valid_in,
    input  logic [63:0] ex_pc_in,
    input  logic [31:0] ex_instr_in,

    input  logic [4:0]  ex_rd_addr_in,

    input  logic [63:0] ex_alu_result_in,
    input  logic [63:0] ex_store_data_in,
    input  logic [63:0] ex_pc_plus4_in,

    input  logic        ex_reg_write_in,
    input  logic        ex_mem_write_in,
    input  logic [1:0]  ex_store_size_in,
    input  logic        ex_wb_sel_pc4_in,

    input  logic        ex_illegal_instr_in,

    input  logic        ex_mem_read_in,
    input  logic [1:0]  ex_load_size_in,
    input  logic        ex_load_unsigned_in,
    input  logic        ex_wb_sel_mem_in,

    // -----------------------------
    // Salidas hacia MEM
    // -----------------------------
    output logic        mem_valid_out,
    output logic [63:0] mem_pc_out,
    output logic [31:0] mem_instr_out,

    output logic [4:0]  mem_rd_addr_out,

    output logic [63:0] mem_alu_result_out,
    output logic [63:0] mem_store_data_out,
    output logic [63:0] mem_pc_plus4_out,

    output logic        mem_reg_write_out,
    output logic        mem_mem_write_out,
    output logic [1:0]  mem_store_size_out,
    output logic        mem_wb_sel_pc4_out,

    output logic        mem_illegal_instr_out,
    
    output logic        mem_mem_read_out,
    output logic [1:0]  mem_load_size_out,
    output logic        mem_load_unsigned_out,
    output logic        mem_wb_sel_mem_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_valid_out         <= 1'b0;
            mem_pc_out            <= 64'd0;
            mem_instr_out         <= 32'd0;

            mem_rd_addr_out       <= 5'd0;

            mem_alu_result_out    <= 64'd0;
            mem_store_data_out    <= 64'd0;
            mem_pc_plus4_out      <= 64'd0;

            mem_reg_write_out     <= 1'b0;
            mem_mem_write_out     <= 1'b0;
            mem_store_size_out    <= 2'b00;
            mem_wb_sel_pc4_out    <= 1'b0;

            mem_illegal_instr_out <= 1'b0;

            mem_mem_read_out      <= 1'b0;
            mem_load_size_out     <= 2'b00;
            mem_load_unsigned_out <= 1'b0;
            mem_wb_sel_mem_out    <= 1'b0;
        end
        else if (flush) begin
            // Inserta burbuja hacia MEM
            mem_valid_out         <= 1'b0;
            mem_pc_out            <= 64'd0;
            mem_instr_out         <= 32'd0;

            mem_rd_addr_out       <= 5'd0;

            mem_alu_result_out    <= 64'd0;
            mem_store_data_out    <= 64'd0;
            mem_pc_plus4_out      <= 64'd0;

            mem_reg_write_out     <= 1'b0;
            mem_mem_write_out     <= 1'b0;
            mem_store_size_out    <= 2'b00;
            mem_wb_sel_pc4_out    <= 1'b0;

            mem_illegal_instr_out <= 1'b0;

            mem_mem_read_out      <= 1'b0;
            mem_load_size_out     <= 2'b00;
            mem_load_unsigned_out <= 1'b0;
            mem_wb_sel_mem_out    <= 1'b0;
        end
        else if (stall) begin
            // Mantener el contenido actual
        end
        else begin
            mem_valid_out         <= ex_valid_in;
            mem_pc_out            <= ex_pc_in;
            mem_instr_out         <= ex_instr_in;

            mem_rd_addr_out       <= ex_rd_addr_in;

            mem_alu_result_out    <= ex_alu_result_in;
            mem_store_data_out    <= ex_store_data_in;
            mem_pc_plus4_out      <= ex_pc_plus4_in;

            mem_reg_write_out     <= ex_reg_write_in;
            mem_mem_write_out     <= ex_mem_write_in;
            mem_store_size_out    <= ex_store_size_in;
            mem_wb_sel_pc4_out    <= ex_wb_sel_pc4_in;

            mem_illegal_instr_out <= ex_illegal_instr_in;

            mem_mem_read_out      <= ex_mem_read_in;
            mem_load_size_out     <= ex_load_size_in;
            mem_load_unsigned_out <= ex_load_unsigned_in;
            mem_wb_sel_mem_out    <= ex_wb_sel_mem_in;
        end
    end

endmodule
