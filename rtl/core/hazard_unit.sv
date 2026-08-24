// Hazard Unit for RISC-V Pipeline
// This module detects data hazards and determines if forwarding is possible from the MEM or WB stages.
// It takes the source register addresses from the EX stage and the destination register information from the MEM and WB stages.
// The unit outputs control signals to select the appropriate forwarding paths for the source registers.
`timescale 1ns/1ps

module hazard_unit (
    input  logic [4:0] ex_rs1_addr,         // Source register 1 address from EX stage
    input  logic [4:0] ex_rs2_addr,         // Source register 2 address from EX stage

    input  logic       mem_valid,           // Indicates if the MEM stage has a valid instruction
    input  logic       mem_reg_write,       // Indicates if the MEM stage instruction writes to a register
    input  logic [4:0] mem_rd_addr,         // Destination register address from MEM stage
    input  logic       mem_illegal_instr,   // Indicates if the MEM stage instruction is illegal
    input  logic       mem_wb_sel_mem,      // Indicates if the MEM stage instruction is a load (used to prevent forwarding from MEM if it's a load)

    input  logic       wb_valid,            // Indicates if the WB stage has a valid instruction
    input  logic       wb_reg_write,        // Indicates if the WB stage instruction writes to a register
    input  logic [4:0] wb_rd_addr,          // Destination register address from WB stage
    input  logic       wb_illegal_instr,    // Indicates if the WB stage instruction is illegal

    output logic [1:0] fwd_rs1_sel,         // Forwarding control for source register 1: 00 = no forwarding, 01 = forward from MEM, 10 = forward from WB
    output logic [1:0] fwd_rs2_sel          // Forwarding control for source register 2: 00 = no forwarding, 01 = forward from MEM, 10 = forward from WB
);

    // Forwarding selection encoding
    localparam logic [1:0] FWD_NONE = 2'b00;
    localparam logic [1:0] FWD_MEM  = 2'b01;
    localparam logic [1:0] FWD_WB   = 2'b10;

    // Determine if forwarding is possible from MEM and WB stages
    logic mem_can_forward;
    logic wb_can_forward;

    // Combinational logic to determine forwarding paths based on the validity and register write conditions of MEM and WB stages
    always_comb begin
        mem_can_forward = mem_valid && mem_reg_write && !mem_illegal_instr && !mem_wb_sel_mem && (mem_rd_addr != 5'd0);   // Avoid forwarding from x0 register and from MEM if it's a load instruction
        wb_can_forward  = wb_valid  && wb_reg_write  && !wb_illegal_instr  && (wb_rd_addr  != 5'd0);    // Avoid forwarding from x0 register

        fwd_rs1_sel = FWD_NONE; // Default to no forwarding
        fwd_rs2_sel = FWD_NONE; 

        // Prioridad: MEM sobre WB
        if (mem_can_forward && (mem_rd_addr == ex_rs1_addr))        // Forwarding for source register 1 from MEM stage
            fwd_rs1_sel = FWD_MEM;
        else if (wb_can_forward && (wb_rd_addr == ex_rs1_addr))     // Forwarding for source register 1 from WB stage
            fwd_rs1_sel = FWD_WB;

        if (mem_can_forward && (mem_rd_addr == ex_rs2_addr))        // Forwarding for source register 2 from MEM stage
            fwd_rs2_sel = FWD_MEM;
        else if (wb_can_forward && (wb_rd_addr == ex_rs2_addr))     // Forwarding for source register 2 from WB stage
            fwd_rs2_sel = FWD_WB;
    end

endmodule

