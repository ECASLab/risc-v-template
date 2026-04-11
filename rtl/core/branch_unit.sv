// branch_unit.sv: Unidad de control de branch y jump
// Determina si se debe tomar un salto o no, basado en las señales de control y los datos de rs1 y rs2
`timescale 1ns/1ps

module branch_unit (
    input  logic        branch,
    input  logic [2:0]  branch_op,
    input  logic        jump,

    input  logic [63:0] rs1_data,
    input  logic [63:0] rs2_data,

    output logic        take_pc_redirect        // Señal que indica si se debe tomar el redirect del PC (ya sea por branch o jump)
);

    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_EQ   = 3'b001;
    localparam logic [2:0] BR_NE   = 3'b010;
    localparam logic [2:0] BR_LT   = 3'b011;
    localparam logic [2:0] BR_GE   = 3'b100;
    localparam logic [2:0] BR_LTU  = 3'b101;
    localparam logic [2:0] BR_GEU  = 3'b110;

    // Lógica combinacional para determinar si se toma el PC redirect
    always_comb begin
        take_pc_redirect = 1'b0;

        if (jump) begin                 // Para instrucciones de salto incondicional, siempre tomamos el redirect
            take_pc_redirect = 1'b1;
        end
        else if (branch) begin          // Para instrucciones de branch, la decisión depende de la operación de branch y los datos de rs1 y rs2
            case (branch_op)
                BR_NONE: take_pc_redirect = 1'b0; // No es un branch válido, no tomamos redirect
                BR_EQ:  take_pc_redirect = (rs1_data == rs2_data);
                BR_NE:  take_pc_redirect = (rs1_data != rs2_data);
                BR_LT:  take_pc_redirect = ($signed(rs1_data) <  $signed(rs2_data));
                BR_GE:  take_pc_redirect = ($signed(rs1_data) >= $signed(rs2_data));
                BR_LTU: take_pc_redirect = (rs1_data < rs2_data);
                BR_GEU: take_pc_redirect = (rs1_data >= rs2_data);
                default: take_pc_redirect = 1'b0;
            endcase
        end
    end

endmodule

