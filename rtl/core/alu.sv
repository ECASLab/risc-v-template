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

    // Operaciones RV64I tipo *W
    localparam logic [3:0] ALU_ADDW   = 4'd11;
    localparam logic [3:0] ALU_SUBW   = 4'd12;
    localparam logic [3:0] ALU_SLLW   = 4'd13;
    localparam logic [3:0] ALU_SRLW   = 4'd14;
    localparam logic [3:0] ALU_SRAW   = 4'd15;

    logic [31:0] word_result;

    always_comb begin
        result      = 64'd0;
        word_result = 32'd0;

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

            // RV64I: shifts de 64 bits usan 6 bits de desplazamiento
            ALU_SLL: begin
                result = a << b[5:0];
            end

            ALU_SRL: begin
                result = a >> b[5:0];
            end

            ALU_SRA: begin
                result = $signed(a) >>> b[5:0];
            end

            ALU_PASS_B: begin
                result = b;
            end

            ALU_SLT: begin
                result = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            end

            ALU_SLTU: begin
                result = (a < b) ? 64'd1 : 64'd0;
            end

            // =========================================
            // RV64I tipo *W:
            // operan sobre 32 bits y sign-extienden a 64
            // =========================================
            ALU_ADDW: begin
                word_result = a[31:0] + b[31:0];
                result      = {{32{word_result[31]}}, word_result};
            end

            ALU_SUBW: begin
                word_result = a[31:0] - b[31:0];
                result      = {{32{word_result[31]}}, word_result};
            end

            ALU_SLLW: begin
                word_result = a[31:0] << b[4:0];
                result      = {{32{word_result[31]}}, word_result};
            end

            ALU_SRLW: begin
                word_result = a[31:0] >> b[4:0];
                result      = {{32{word_result[31]}}, word_result};
            end

            ALU_SRAW: begin
                word_result = $signed(a[31:0]) >>> b[4:0];
                result      = {{32{word_result[31]}}, word_result};
            end

            default: begin
                result = 64'd0;
            end
        endcase
    end

endmodule

