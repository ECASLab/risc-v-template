`timescale 1ns/1ps

module alu (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [3:0]  alu_op,
    output logic [63:0] result
);

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

    localparam logic [3:0] ALU_ADDW   = 4'd11;
    localparam logic [3:0] ALU_SUBW   = 4'd12;
    localparam logic [3:0] ALU_SLLW   = 4'd13;
    localparam logic [3:0] ALU_SRLW   = 4'd14;
    localparam logic [3:0] ALU_SRAW   = 4'd15;

    logic [5:0]  shamt64;
    logic [4:0]  shamt32;
    logic [31:0] a_word;
    logic [31:0] b_word;

    logic [31:0] addw_word;
    logic [31:0] subw_word;
    logic [31:0] sllw_word;
    logic [31:0] srlw_word;
    logic [31:0] sraw_word;

    logic [63:0] addw_result;
    logic [63:0] subw_result;
    logic [63:0] sllw_result;
    logic [63:0] srlw_result;
    logic [63:0] sraw_result;

    assign shamt64 = b[5:0];
    assign shamt32 = b[4:0];
    assign a_word  = a[31:0];
    assign b_word  = b[31:0];

    assign addw_word = a_word + b_word;
    assign subw_word = a_word - b_word;
    assign sllw_word = a_word << shamt32;
    assign srlw_word = a_word >> shamt32;
    assign sraw_word = $signed(a_word) >>> shamt32;

    assign addw_result = {{32{addw_word[31]}}, addw_word};
    assign subw_result = {{32{subw_word[31]}}, subw_word};
    assign sllw_result = {{32{sllw_word[31]}}, sllw_word};
    assign srlw_result = {{32{srlw_word[31]}}, srlw_word};
    assign sraw_result = {{32{sraw_word[31]}}, sraw_word};

    always_comb begin
        result = 64'd0;

        case (alu_op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_SLL:    result = a << shamt64;
            ALU_SRL:    result = a >> shamt64;
            ALU_SRA:    result = $signed(a) >>> shamt64;
            ALU_PASS_B: result = b;
            ALU_SLT:    result = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            ALU_SLTU:   result = (a < b) ? 64'd1 : 64'd0;

            ALU_ADDW:   result = addw_result;
            ALU_SUBW:   result = subw_result;
            ALU_SLLW:   result = sllw_result;
            ALU_SRLW:   result = srlw_result;
            ALU_SRAW:   result = sraw_result;

            default:    result = 64'd0;
        endcase
    end

endmodule

