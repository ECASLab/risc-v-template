`timescale 1ns/1ps

module tb_core_directed;

    logic        clk;
    logic        rst;

    logic [63:0] imem_addr; //Direccion de instruccion a IMEM (64 bits para soportar direccionamiento completo, aunque solo se usen 8 bits)
    logic [31:0] imem_rdata;//Dato de instruccion leida desde IMEM (32 bits)
    logic [63:0] dmem_rdata;//Señales para DMEM

    logic        dmem_we;   //Habilitacion de escritura a DMEM
    logic [7:0]  dmem_wstrb;//Máscara de escritura para DMEM
    logic [63:0] dmem_addr;//Direccion de acceso a DMEM
    logic [63:0] dmem_wdata;//Dato a escribir en DMEM
    logic [1:0]  dmem_size;//Tamaño de la operación de memoria

    // ------------------------------------------------------------
    // Señales dummy para puerto de expansión.
    // Estos testbenches no usan MMIO, por eso el puerto se deja
    // en estado inactivo/seguro para evitar entradas flotantes.
    // ------------------------------------------------------------
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    core_top #(
        .RESET_PC(64'd0)
    ) dut (
        .clk        (clk),
        .rst        (rst),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_wstrb (dmem_wstrb),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_size  (dmem_size),

        .exp_valid  (),
        .exp_we     (),
        .exp_addr   (),
        .exp_wdata  (),
        .exp_wstrb  (),
        .exp_size   (),
        .exp_ready  (exp_ready),
        .exp_rdata  (exp_rdata),
        .exp_error  (exp_error)
    );

    // -------------------------------------------------
    // IMEM simple: 256 palabras de 32 bits
    // -------------------------------------------------
    logic [31:0] imem [0:255];

    // Programa combinacionalmente leído
    assign imem_rdata = imem[imem_addr[63:2]];

    // En esta prueba no usamos loads reales
    assign dmem_rdata = 64'd0;

    // Clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------
    // Task de chequeo
    // ---------------------------------------------
    task automatic check_reg;
        input integer reg_idx;
        input logic [63:0] expected;
        begin
            if (dut.u_regfile.regs[reg_idx] !== expected) begin
                $display("ERROR: x%0d = 0x%016h, esperado = 0x%016h",
                         reg_idx, dut.u_regfile.regs[reg_idx], expected);
                $fatal;
            end
            else begin
                $display("OK: x%0d = 0x%016h", reg_idx, dut.u_regfile.regs[reg_idx]);
            end
        end
    endtask

    integer i;

    initial begin
        // Inicialización por defecto con NOP = addi x0, x0, 0
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;
        end

        // ---------------------------------------------------------
        // Programa dirigido para probar:
        // SLTI, SLTIU, SLT, SLTU, BLT, BGE, BLTU, BGEU
        // ---------------------------------------------------------
        imem[ 0] = 32'h00500093; // addi  x1,  x0, 5
        imem[ 1] = 32'hfff00113; // addi  x2,  x0, -1
        imem[ 2] = 32'h0060a193; // slti  x3,  x1, 6    -> 1
        imem[ 3] = 32'h0050a213; // slti  x4,  x1, 5    -> 0
        imem[ 4] = 32'h0060b293; // sltiu x5,  x1, 6    -> 1
        imem[ 5] = 32'h00113313; // sltiu x6,  x2, 1    -> 0
        imem[ 6] = 32'h001123b3; // slt   x7,  x2, x1   -> 1
        imem[ 7] = 32'h00113433; // sltu  x8,  x2, x1   -> 0

        // Branches que DEBEN tomarse
        imem[ 8] = 32'h00000493; // addi  x9,  x0, 0
        imem[ 9] = 32'h00114463; // blt   x2,  x1, +8
        imem[10] = 32'h00100493; // addi  x9,  x0, 1   (debe saltarse)
        imem[11] = 32'h0020d463; // bge   x1,  x2, +8
        imem[12] = 32'h00200493; // addi  x9,  x0, 2   (debe saltarse)
        imem[13] = 32'h0020e463; // bltu  x1,  x2, +8
        imem[14] = 32'h00300493; // addi  x9,  x0, 3   (debe saltarse)
        imem[15] = 32'h00117463; // bgeu  x2,  x1, +8
        imem[16] = 32'h00400493; // addi  x9,  x0, 4   (debe saltarse)

        imem[17] = 32'h00f00513; // addi  x10, x0, 15

        // Branches que NO deben tomarse
        imem[18] = 32'h00000593; // addi  x11, x0, 0
        imem[19] = 32'h0020c463; // blt   x1,  x2, +8   (NO tomado)
        imem[20] = 32'h00158593; // addi  x11, x11, 1
        imem[21] = 32'h00115463; // bge   x2,  x1, +8   (NO tomado)
        imem[22] = 32'h00258593; // addi  x11, x11, 2
        imem[23] = 32'h00116463; // bltu  x2,  x1, +8   (NO tomado)
        imem[24] = 32'h00458593; // addi  x11, x11, 4
        imem[25] = 32'h0020f463; // bgeu  x1,  x2, +8   (NO tomado)
        imem[26] = 32'h00858593; // addi  x11, x11, 8

        imem[27] = 32'h0000006f; // jal x0, 0   loop infinito

        // Reset
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // Espera suficiente para que el pipeline complete el programa
        repeat (60) @(posedge clk);

        $display("---- INICIO DE CHEQUEOS ----");
        check_reg( 0, 64'd0);
        check_reg( 3, 64'd1);
        check_reg( 4, 64'd0);
        check_reg( 5, 64'd1);
        check_reg( 6, 64'd0);
        check_reg( 7, 64'd1);
        check_reg( 8, 64'd0);
        check_reg( 9, 64'd0);
        check_reg(10, 64'd15);
        check_reg(11, 64'd15);

        $display("==========================================");
        $display("PASS: prueba dirigida de SLT/SLTU y branches");
        $display("==========================================");
        $finish;
    end

    initial begin
        #2000;
        $display("TIMEOUT: la simulacion no termino como se esperaba");
        $fatal;
    end

endmodule