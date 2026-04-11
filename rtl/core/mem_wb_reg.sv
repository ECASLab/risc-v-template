`timescale 1ns/1ps


module mem_wb_reg (
    input  logic        clk,
    input  logic        rst,

    input  logic        stall,
    input  logic        flush,

    // -----------------------------
    // Entradas desde MEM
    // -----------------------------
    input  logic        mem_valid_in,
    input  logic [63:0] mem_pc_in,
    input  logic [31:0] mem_instr_in,

    input  logic [4:0]  mem_rd_addr_in,

    input  logic [63:0] mem_alu_result_in,
    input  logic [63:0] mem_pc_plus4_in,

    input  logic        mem_reg_write_in,
    input  logic        mem_wb_sel_pc4_in,

    input  logic        mem_illegal_instr_in,

    input  logic [63:0] mem_load_data_in,
    input  logic        mem_wb_sel_mem_in,

    // -----------------------------
    // Salidas hacia WB
    // -----------------------------
    output logic        wb_valid_out,
    output logic [63:0] wb_pc_out,
    output logic [31:0] wb_instr_out,

    output logic [4:0]  wb_rd_addr_out,

    output logic [63:0] wb_alu_result_out,
    output logic [63:0] wb_pc_plus4_out,

    output logic        wb_reg_write_out,
    output logic        wb_wb_sel_pc4_out,

    output logic        wb_illegal_instr_out,

    output logic [63:0] wb_load_data_out,
    output logic        wb_wb_sel_mem_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            wb_valid_out         <= 1'b0;
            wb_pc_out            <= 64'd0;
            wb_instr_out         <= 32'd0;

            wb_rd_addr_out       <= 5'd0;

            wb_alu_result_out    <= 64'd0;
            wb_pc_plus4_out      <= 64'd0;

            wb_reg_write_out     <= 1'b0;
            wb_wb_sel_pc4_out    <= 1'b0;

            wb_illegal_instr_out <= 1'b0;

            wb_load_data_out      <= 64'd0;
            wb_wb_sel_mem_out     <= 1'b0;
        end
        else if (flush) begin
            // Inserta burbuja hacia WB
            wb_valid_out         <= 1'b0;
            wb_pc_out            <= 64'd0;
            wb_instr_out         <= 32'd0;

            wb_rd_addr_out       <= 5'd0;

            wb_alu_result_out    <= 64'd0;
            wb_pc_plus4_out      <= 64'd0;

            wb_reg_write_out     <= 1'b0;
            wb_wb_sel_pc4_out    <= 1'b0;

            wb_illegal_instr_out <= 1'b0;

            wb_load_data_out      <= 64'd0;
            wb_wb_sel_mem_out     <= 1'b0;
        end
        else if (stall) begin
            // Mantener el contenido actual
        end
        else begin
            wb_valid_out         <= mem_valid_in;
            wb_pc_out            <= mem_pc_in;
            wb_instr_out         <= mem_instr_in;

            wb_rd_addr_out       <= mem_rd_addr_in;

            wb_alu_result_out    <= mem_alu_result_in;
            wb_pc_plus4_out      <= mem_pc_plus4_in;

            wb_reg_write_out     <= mem_reg_write_in;
            wb_wb_sel_pc4_out    <= mem_wb_sel_pc4_in;

            wb_illegal_instr_out <= mem_illegal_instr_in;

            wb_load_data_out      <= mem_load_data_in;
            wb_wb_sel_mem_out     <= mem_wb_sel_mem_in;
        end
    end

endmodule
