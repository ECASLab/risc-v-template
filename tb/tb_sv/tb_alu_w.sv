`timescale 1ns/1ps

// Testbench para verificar la implementación de las operaciones tipo *W en la ALU (ADDW, SUBW, SLLW, SRLW, SRAW)
// Estas operaciones operan sobre los 32 bits bajos de los operandos, realizan la operación correspondiente, y luego sign-extienden el resultado a 64 bits.
// Este testbench verifica casos básicos de cada operación tipo *W, incluyendo casos de overflow y comportamiento de los shifts. Para pruebas
module tb_alu_w;

    logic [63:0] a;
    logic [63:0] b;
    logic [3:0]  alu_op;
    logic [63:0] result;

    // Instancia del DUT
    alu dut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .result(result)
    );

    // Códigos de operación: deben coincidir con alu.sv
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

    task automatic check_result(
        input [255:0] test_name,
        input [63:0]  exp
    );
    begin
        #1;
        if (result !== exp) begin
            $display("ERROR: %s", test_name);
            $display("  a        = 0x%016h", a);
            $display("  b        = 0x%016h", b);
            $display("  alu_op   = %0d", alu_op);
            $display("  esperado = 0x%016h", exp);
            $display("  obtenido = 0x%016h", result);
            $fatal(1);
        end else begin
            $display("OK: %s -> 0x%016h", test_name, result);
        end
    end
    endtask

    initial begin
        $display("==== Iniciando pruebas ALU tipo *W ====");

        // 1) ADDIW equivalente en ALU: usa ALU_ADDW con b=imm sign-extended
        // rs1 = 0x00000000ffffffff
        // imm = 1
        // 0xffffffff + 1 = 0x00000000 -> sign-extended = 0x0000000000000000
        a      = 64'h00000000ffffffff;
        b      = 64'h0000000000000001;
        alu_op = ALU_ADDW;
        check_result("ADDIW / ADDW wrap a 32 bits", 64'h0000000000000000);

        // 2) SLLIW / SLLW
        // 0xffffffff << 1 = 0xfffffffe -> sign-extended = 0xfffffffffffffffe
        a      = 64'h00000000ffffffff;
        b      = 64'h0000000000000001; // shamt = 1
        alu_op = ALU_SLLW;
        check_result("SLLIW / SLLW", 64'hfffffffffffffffe);

        // 3) SRLIW / SRLW
        // low32(0xfffffffffffffffe) = 0xfffffffe
        // 0xfffffffe >> 1 = 0x7fffffff -> sign-extended = 0x000000007fffffff
        a      = 64'hfffffffffffffffe;
        b      = 64'h0000000000000001;
        alu_op = ALU_SRLW;
        check_result("SRLIW / SRLW", 64'h000000007fffffff);

        // 4) SRAIW / SRAW
        // signed low32(0xfffffffe) = -2
        // -2 >>> 1 = -1 = 0xffffffff -> sign-extended = 0xffffffffffffffff
        a      = 64'hfffffffffffffffe;
        b      = 64'h0000000000000001;
        alu_op = ALU_SRAW;
        check_result("SRAIW / SRAW", 64'hffffffffffffffff);

        // 5) ADDW adicional
        a      = 64'h00000000ffffffff;
        b      = 64'h0000000000000001;
        alu_op = ALU_ADDW;
        check_result("ADDW", 64'h0000000000000000);

        // 6) SUBW adicional
        // 0x00000000 - 0x00000001 = 0xffffffff -> sign-extended negativo
        a      = 64'h0000000000000000;
        b      = 64'h0000000000000001;
        alu_op = ALU_SUBW;
        check_result("SUBW", 64'hffffffffffffffff);

        // 7) prueba de shamt en 5 bits para W
        // 32 decimal = 6'b100000, pero en W debe usar b[4:0], o sea 0
        a      = 64'h0000000012345678;
        b      = 64'h0000000000000020;
        alu_op = ALU_SLLW;
        check_result("SLLW usa solo b[4:0]", 64'h0000000012345678);

        $display("==== Todas las pruebas ALU tipo *W pasaron ====");
        $finish;
    end

endmodule
