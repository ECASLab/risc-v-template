`timescale 1ns/1ps

//ROBAR
    //mkdir -p build

    //iverilog -g2012 \
    //  -o build/tb_expansion_demo_periph.vvp \
    //  rtl/core/expansion_demo_periph.sv \
    //  tb/tb_sv/tb_expansion_demo_periph.sv

    //vvp build/tb_expansion_demo_periph.vvp


module tb_expansion_demo_periph;

    localparam logic [63:0] BASE_ADDR = 64'h0000_0000_8000_0000;

    localparam logic [63:0] REG_ID        = 64'h000;
    localparam logic [63:0] REG_VERSION   = 64'h008;
    localparam logic [63:0] REG_CONTROL   = 64'h010;
    localparam logic [63:0] REG_STATUS    = 64'h018;
    localparam logic [63:0] REG_OPERAND_A = 64'h020;
    localparam logic [63:0] REG_OPERAND_B = 64'h028;
    localparam logic [63:0] REG_RESULT    = 64'h030;
    localparam logic [63:0] REG_INVALID   = 64'h040;

    localparam logic [1:0] SIZE_BYTE  = 2'b00;
    localparam logic [1:0] SIZE_HALF  = 2'b01;
    localparam logic [1:0] SIZE_WORD  = 2'b10;
    localparam logic [1:0] SIZE_DWORD = 2'b11;

    logic        clk;
    logic        rst;

    logic        exp_valid_i;
    logic        exp_we_i;
    logic [63:0] exp_addr_i;
    logic [63:0] exp_wdata_i;
    logic [7:0]  exp_wstrb_i;
    logic [1:0]  exp_size_i;

    logic        exp_ready_o;
    logic [63:0] exp_rdata_o;
    logic        exp_error_o;

    integer failures;

    logic [63:0] rdata;
    logic        err;

    expansion_demo_periph dut (
        .clk         (clk),
        .rst         (rst),

        .exp_valid_i (exp_valid_i),
        .exp_we_i    (exp_we_i),
        .exp_addr_i  (exp_addr_i),
        .exp_wdata_i (exp_wdata_i),
        .exp_wstrb_i (exp_wstrb_i),
        .exp_size_i  (exp_size_i),

        .exp_ready_o (exp_ready_o),
        .exp_rdata_o (exp_rdata_o),
        .exp_error_o (exp_error_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic init_bus;
        begin
            exp_valid_i = 1'b0;
            exp_we_i    = 1'b0;
            exp_addr_i  = 64'd0;
            exp_wdata_i = 64'd0;
            exp_wstrb_i = 8'd0;
            exp_size_i  = SIZE_DWORD;
        end
    endtask

    task automatic reset_dut;
        begin
            rst = 1'b1;
            init_bus();

            repeat (3) @(posedge clk);
            #1;

            rst = 1'b0;

            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    task automatic check64;
        input [8*80-1:0] name;
        input logic [63:0] got;
        input logic [63:0] expected;
        begin
            if (got !== expected) begin
                $display("ERROR: %0s: got=0x%016h expected=0x%016h",
                         name, got, expected);
                failures = failures + 1;
            end
            else begin
                $display("PASS : %0s = 0x%016h", name, got);
            end
        end
    endtask

    task automatic check1;
        input [8*80-1:0] name;
        input logic got;
        input logic expected;
        begin
            if (got !== expected) begin
                $display("ERROR: %0s: got=%0b expected=%0b",
                         name, got, expected);
                failures = failures + 1;
            end
            else begin
                $display("PASS : %0s = %0b", name, got);
            end
        end
    endtask

    task automatic mmio_read;
        input  logic [63:0] addr;
        output logic [63:0] data;
        output logic        error;
        begin
            @(negedge clk);

            exp_valid_i = 1'b1;
            exp_we_i    = 1'b0;
            exp_addr_i  = addr;
            exp_wdata_i = 64'd0;
            exp_wstrb_i = 8'd0;
            exp_size_i  = SIZE_DWORD;

            #1;

            if (exp_ready_o !== 1'b1) begin
                $display("ERROR: exp_ready_o no está en 1 durante lectura");
                failures = failures + 1;
            end

            data  = exp_rdata_o;
            error = exp_error_o;

            @(posedge clk);
            #1;

            init_bus();
        end
    endtask

    task automatic mmio_write;
        input  logic [63:0] addr;
        input  logic [63:0] data;
        input  logic [7:0]  wstrb;
        output logic        error;
        begin
            @(negedge clk);

            exp_valid_i = 1'b1;
            exp_we_i    = 1'b1;
            exp_addr_i  = addr;
            exp_wdata_i = data;
            exp_wstrb_i = wstrb;
            exp_size_i  = SIZE_DWORD;

            #1;

            if (exp_ready_o !== 1'b1) begin
                $display("ERROR: exp_ready_o no está en 1 durante escritura");
                failures = failures + 1;
            end

            error = exp_error_o;

            @(posedge clk);
            #1;

            init_bus();
        end
    endtask

    initial begin
        failures = 0;
        rst      = 1'b0;
        init_bus();

        $display("==============================================");
        $display("TB expansion_demo_periph");
        $display("==============================================");

        reset_dut();

        // -----------------------------------------------------
        // 1. Lectura de registros read-only básicos
        // -----------------------------------------------------
        mmio_read(BASE_ADDR + REG_ID, rdata, err);
        check1 ("ID read error", err, 1'b0);
        check64("ID", rdata, 64'h0000_0000_4558_5030);

        mmio_read(BASE_ADDR + REG_VERSION, rdata, err);
        check1 ("VERSION read error", err, 1'b0);
        check64("VERSION", rdata, 64'h0000_0000_0000_0001);

        mmio_read(BASE_ADDR + REG_STATUS, rdata, err);
        check1 ("STATUS reset read error", err, 1'b0);
        check64("STATUS reset", rdata, 64'h0000_0000_0000_0000);

        // -----------------------------------------------------
        // 2. Escritura y lectura de operandos
        // -----------------------------------------------------
        mmio_write(BASE_ADDR + REG_OPERAND_A, 64'h0000_0000_0000_0011, 8'hFF, err);
        check1("OPERAND_A write error", err, 1'b0);

        mmio_write(BASE_ADDR + REG_OPERAND_B, 64'h0000_0000_0000_0022, 8'hFF, err);
        check1("OPERAND_B write error", err, 1'b0);

        mmio_read(BASE_ADDR + REG_OPERAND_A, rdata, err);
        check1 ("OPERAND_A read error", err, 1'b0);
        check64("OPERAND_A", rdata, 64'h0000_0000_0000_0011);

        mmio_read(BASE_ADDR + REG_OPERAND_B, rdata, err);
        check1 ("OPERAND_B read error", err, 1'b0);
        check64("OPERAND_B", rdata, 64'h0000_0000_0000_0022);

        // -----------------------------------------------------
        // 3. Start: RESULT = OPERAND_A + OPERAND_B
        // -----------------------------------------------------
        mmio_write(BASE_ADDR + REG_CONTROL, 64'h0000_0000_0000_0001, 8'hFF, err);
        check1("CONTROL start write error", err, 1'b0);

        mmio_read(BASE_ADDR + REG_RESULT, rdata, err);
        check1 ("RESULT read error", err, 1'b0);
        check64("RESULT", rdata, 64'h0000_0000_0000_0033);

        mmio_read(BASE_ADDR + REG_STATUS, rdata, err);
        check1 ("STATUS done read error", err, 1'b0);
        check64("STATUS done", rdata, 64'h0000_0000_0000_0002);

        // -----------------------------------------------------
        // 4. Limpieza de done mediante STATUS W1C
        // -----------------------------------------------------
        mmio_write(BASE_ADDR + REG_STATUS, 64'h0000_0000_0000_0002, 8'hFF, err);
        check1("STATUS W1C write error", err, 1'b0);

        mmio_read(BASE_ADDR + REG_STATUS, rdata, err);
        check1 ("STATUS after W1C read error", err, 1'b0);
        check64("STATUS after W1C", rdata, 64'h0000_0000_0000_0000);

        // -----------------------------------------------------
        // 5. Escritura parcial por byte enable
        // -----------------------------------------------------
        mmio_write(BASE_ADDR + REG_OPERAND_A, 64'h1122_3344_5566_7788, 8'hFF, err);
        check1("OPERAND_A full write error", err, 1'b0);

        mmio_write(BASE_ADDR + REG_OPERAND_A, 64'h0000_0000_0000_00AA, 8'b0000_0001, err);
        check1("OPERAND_A byte write error", err, 1'b0);

        mmio_read(BASE_ADDR + REG_OPERAND_A, rdata, err);
        check1 ("OPERAND_A partial read error", err, 1'b0);
        check64("OPERAND_A partial", rdata, 64'h1122_3344_5566_77AA);

        // -----------------------------------------------------
        // 6. Escritura ilegal a registro read-only
        // -----------------------------------------------------
        mmio_read(BASE_ADDR + REG_RESULT, rdata, err);
        check1("RESULT pre-illegal read error", err, 1'b0);

        mmio_write(BASE_ADDR + REG_RESULT, 64'hFFFF_FFFF_FFFF_FFFF, 8'hFF, err);
        check1("RESULT illegal write error", err, 1'b1);

        mmio_read(BASE_ADDR + REG_RESULT, rdata, err);
        check1 ("RESULT post-illegal read error", err, 1'b0);
        check64("RESULT unchanged after illegal write", rdata, 64'h0000_0000_0000_0033);

        // -----------------------------------------------------
        // 7. Dirección inválida
        // -----------------------------------------------------
        mmio_read(BASE_ADDR + REG_INVALID, rdata, err);
        check1 ("INVALID read error", err, 1'b1);
        check64("INVALID read data", rdata, 64'h0000_0000_0000_0000);

        mmio_write(BASE_ADDR + REG_INVALID, 64'h1234_5678_9ABC_DEF0, 8'hFF, err);
        check1("INVALID write error", err, 1'b1);

        // -----------------------------------------------------
        // Resultado final
        // -----------------------------------------------------
        if (failures == 0) begin
            $display("==============================================");
            $display("PASS: tb_expansion_demo_periph");
            $display("==============================================");
            $finish;
        end
        else begin
            $display("==============================================");
            $display("FAIL: tb_expansion_demo_periph failures=%0d", failures);
            $display("==============================================");
            $finish(1);
        end
    end

endmodule
