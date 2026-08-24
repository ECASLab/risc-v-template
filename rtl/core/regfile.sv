`timescale 1ns/1ps


module regfile(
    input logic clk,                            //Sincronizar
    input logic rst,                            //Arrancar en un estado conocido

    //Puerto de escritura
    input logic we,                             //Habilita la escritura (write enable)
    input logic [4:0]   rd_addr,                //Numero del registro destino
    input logic [63:0]  rd_data,                //Valor del dato

    //Puerto de lectura 1
    input logic     [4:0]   rs1_addr,
    output logic    [63:0]  rs1_data,

    //Purto de lectura 2
    input logic     [4:0]   rs2_addr,
    output logic    [63:0]  rs2_data
);
    //Memoria interna del banco
    logic [63:0] regs [31:0];                   //Arreglo de 32 posiciones, cada una de 64 bits

    integer i;

    //Escritura sincronica
    always_ff @(posedge clk) begin
        if (rst) begin
            //Inicializar a cero
            for (i = 0; i < 32; i = i + 1)begin
                regs[i] <= 64'd0;               //Asegurar todo a cero cuando se activa reset
            end             
        end else begin
            //Nunca escribir x0
            if (we && (rd_addr != 5'd0)) begin
                regs[rd_addr] <= rd_data;       //Si  se intenta escribir en cero, no ocurre nada
            end

            regs[0] <= 64'd0;                   //Por si acaso se contaminara cero en algun punto
        end
    end

        //Lectura combinacional puerto 1
    always_comb begin
        if (rs1_addr == 5'd0)
            rs1_data = 64'd0;
        else if (we && (rd_addr != 5'd0) && (rd_addr == rs1_addr))
            rs1_data = rd_data;   // bypass write-first WB->ID
        else
            rs1_data = regs[rs1_addr];
    end

    always_comb begin
        if (rs2_addr == 5'd0)
            rs2_data = 64'd0;
        else if (we && (rd_addr != 5'd0) && (rd_addr == rs2_addr))
            rs2_data = rd_data;   // bypass write-first WB->ID
        else
            rs2_data = regs[rs2_addr];
    end

    `ifdef COCOTB_SIM
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, regfile);
    end
    `endif

endmodule

