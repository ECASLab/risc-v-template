`timescale 1ns/1ps

module alu (
    //Entradas y salida
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [3:0]  alu_op,
    output logic [63:0] result
);

    // Códigos de operación: Deben coincidir con decoder.sv
    localparam logic [3:0] ALU_ADD    = 4'd0;
    localparam logic [3:0] ALU_SUB    = 4'd1;
    localparam logic [3:0] ALU_AND    = 4'd2;
    localparam logic [3:0] ALU_OR     = 4'd3;
    localparam logic [3:0] ALU_XOR    = 4'd4;
    localparam logic [3:0] ALU_SLL    = 4'd5;
    localparam logic [3:0] ALU_SRL    = 4'd6;
    localparam logic [3:0] ALU_SRA    = 4'd7;
    localparam logic [3:0] ALU_PASS_B = 4'd8;
    localparam logic [3:0] ALU_SLT    = 4'd9;
    localparam logic [3:0] ALU_SLTU   = 4'd10;

    always @(*) begin
        case (alu_op)
            ALU_ADD: begin
                result = a + b;
            end

            ALU_SUB: begin
                result = a - b;
            end

            ALU_AND: begin
                result = a & b;
            end

            ALU_OR: begin
                result = a | b;
            end

            ALU_XOR: begin
                result = a ^ b;
            end

            // En RV64I, shifts usan solo los 6 bits bajos del desplazamiento
            // Para SLL/SRL/SRA, b viene de rs2
            // Para SLLI/SRLI/SRAI, b viene del inmediato sign-extended, pero los 6 bits bajos siguen siendo el shamt
            
            // SLR/SLL: Mete ceros por la derecha/izquierda
            // SRA: Copia el bit de signo
            ALU_SLL: begin
                result = a << b[5:0];
            end

            ALU_SRL: begin
                result = a >> b[5:0];
            end

            ALU_SRA: begin
                result = $signed(a) >>> b[5:0];
            end

            // Útil para LUI: resultado = inmediato (Podría implementarse como suma con cero)
            ALU_PASS_B: begin
                result = b;
            end

            // SLT/SLTU: resultado es 1 si a < b, 0 en caso contrario. Para SLT se compara como signed, para SLTU como unsigned
            ALU_SLT: begin
                result = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            end

            ALU_SLTU: begin
                result = (a < b) ? 64'd1 : 64'd0;
            end

            default: begin
                result = 64'd0;
            end
        endcase
    end

endmodule

