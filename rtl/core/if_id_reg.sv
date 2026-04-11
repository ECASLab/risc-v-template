`timescale 1ns/1ps


module if_id_reg (
    input  logic        clk,
    input  logic        rst,

    input  logic        stall,
    input  logic        flush,

    input  logic        if_valid_in,
    input  logic [63:0] if_pc_in,           // Guardar el pc de la instrucción fetchada.
    input  logic [31:0] if_instr_in,

    output logic        id_valid_out,       // Indica si el contenido del registro IF/ID representa una instrucción real o una burbuja.
    output logic [63:0] id_pc_out,
    output logic [31:0] id_instr_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            id_valid_out <= 1'b0;
            id_pc_out    <= 64'd0;
            id_instr_out <= 32'd0;
        end
        else if (flush) begin
            // Inserta burbuja hacia ID
            id_valid_out <= 1'b0;
            id_pc_out    <= 64'd0;
            id_instr_out <= 32'd0;
        end
        else if (stall) begin
            // Mantiene el contenido actual
            id_valid_out <= id_valid_out;
            id_pc_out    <= id_pc_out;
            id_instr_out <= id_instr_out;
        end
        else begin
            // Avance normal del pipeline
            id_valid_out <= if_valid_in;
            id_pc_out    <= if_pc_in;
            id_instr_out <= if_instr_in;
        end
    end

endmodule

