`timescale 1ns/1ps


module imm_gen (
    
    input  logic [31:0] instr,
    input  logic [2:0]  imm_sel,
    output logic [63:0] imm
);

    // Definición de los tipos de inmediato según el formato de instrucción RISC-V
    localparam logic [2:0] IMM_NONE = 3'b000;
    localparam logic [2:0] IMM_I    = 3'b001;
    localparam logic [2:0] IMM_B    = 3'b010;
    localparam logic [2:0] IMM_U    = 3'b011;
    localparam logic [2:0] IMM_S    = 3'b100;
    localparam logic [2:0] IMM_J    = 3'b101;

    // Generación del inmediato basado en el formato seleccionado y la instrucción de entrada 
    assign imm = 
        (imm_sel == IMM_NONE) ? 64'd0 :
        (imm_sel == IMM_I)    ? {{52{instr[31]}}, instr[31:20]} :                    // I-type
        (imm_sel == IMM_B)    ? {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0} : // B-type
        (imm_sel == IMM_U)    ? {{32{instr[31]}}, instr[31:12], 12'b0} :              // U-type
        (imm_sel == IMM_S)    ? {{52{instr[31]}}, instr[31:25], instr[11:7]} :        // S-type
        (imm_sel == IMM_J)    ? {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0} : // J-type
                                64'd0;  // default (instrucción ilegal o IMM_NONE)

endmodule
