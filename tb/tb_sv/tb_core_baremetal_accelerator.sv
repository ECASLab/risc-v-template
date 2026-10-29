`timescale 1ns/1ps

module tb_core_baremetal_accelerator;
    localparam logic [63:0] RAM_BASE    = 64'h0000_0000_8000_0000;
    localparam logic [63:0] EXP_BASE    = 64'h0000_0000_1000_0000;
    localparam logic [63:0] TRAP_VECTOR = RAM_BASE + 64'h100;
    localparam logic [63:0] RESULT_ADDR = RAM_BASE + 64'h300;
    localparam logic [63:0] OPERAND_A   = 64'h1122_3344_5566_7788;
    localparam logic [63:0] OPERAND_B   = 64'h0000_0000_0000_0022;
    localparam logic [63:0] EXPECTED    = 64'h1122_3344_5566_77aa;

    localparam int unsigned IMEM_WORDS = 256;
    localparam int unsigned DMEM_WORDS = 256;
    localparam int unsigned RESULT_INDEX = 'h300 / 8;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    string imem_file;
    string dmem_file;
    integer image_bytes;
    integer image_iwords;
    integer image_dwords;

    logic        imem_req, imem_gnt, imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic        dmem_req, dmem_gnt, dmem_rvalid, dmem_error;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [1:0]  dmem_size;

    logic        exp_valid, exp_we, exp_ready, exp_error;
    logic [63:0] exp_addr, exp_wdata, exp_rdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;

    core_top #(
        .RESET_PC(RAM_BASE),
        .TRAP_VECTOR(TRAP_VECTOR),
        .EXP_BASE(EXP_BASE)
    ) dut (
        .clk(clk), .rst(rst),
        .imem_req(imem_req), .imem_addr(imem_addr),
        .imem_gnt(imem_gnt), .imem_rvalid(imem_rvalid),
        .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_gnt(dmem_gnt),
        .dmem_rvalid(dmem_rvalid), .dmem_error(dmem_error),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_size(dmem_size),
        .exp_valid(exp_valid), .exp_we(exp_we),
        .exp_addr(exp_addr), .exp_wdata(exp_wdata),
        .exp_wstrb(exp_wstrb), .exp_size(exp_size),
        .exp_ready(exp_ready), .exp_rdata(exp_rdata),
        .exp_error(exp_error)
    );

    imem_sync_model #(
        .MEM_WORDS(IMEM_WORDS),
        .BASE_ADDR(RAM_BASE),
        .GNT_DELAY(1),
        .RESP_DELAY(2)
    ) u_imem (
        .clk(clk), .rst(rst),
        .req_i(imem_req), .gnt_o(imem_gnt),
        .addr_i(imem_addr), .rvalid_o(imem_rvalid),
        .rdata_o(imem_rdata)
    );

    dmem_sync_model #(
        .MEM_WORDS(DMEM_WORDS),
        .BASE_ADDR(RAM_BASE),
        .GNT_DELAY(1),
        .RESP_DELAY(2),
        .FAULT_ENABLE(1'b0)
    ) u_dmem (
        .clk(clk), .rst(rst),
        .req_i(dmem_req), .gnt_o(dmem_gnt),
        .addr_i(dmem_addr), .we_i(dmem_we),
        .wdata_i(dmem_wdata), .wstrb_i(dmem_wstrb),
        .size_i(dmem_size), .rvalid_o(dmem_rvalid),
        .rdata_o(dmem_rdata), .error_o(dmem_error)
    );

    expansion_demo_periph u_accel (
        .clk(clk), .rst(rst),
        .exp_valid_i(exp_valid), .exp_we_i(exp_we),
        .exp_addr_i(exp_addr), .exp_wdata_i(exp_wdata),
        .exp_wstrb_i(exp_wstrb), .exp_size_i(exp_size),
        .exp_ready_o(exp_ready), .exp_rdata_o(exp_rdata),
        .exp_error_o(exp_error)
    );

    integer mmio_count = 0;
    integer mmio_reads = 0;
    integer mmio_writes = 0;
    integer dmem_count = 0;
    integer dmem_responses = 0;
    integer status_reads = 0;
    logic [6:0] observed_steps = '0;

    always @(posedge clk) begin
        if (!rst) begin
            if (exp_valid) begin
                if (exp_error || !exp_ready)
                    $fatal(1, "FAIL: expansión reportó error o no estaba ready");
                if (exp_size !== 2'b11)
                    $fatal(1, "FAIL: acceso MMIO no es de 64 bits");

                case (exp_addr)
                    EXP_BASE + 64'h020: begin
                        if (!exp_we || exp_wstrb !== 8'hff || exp_wdata !== OPERAND_A)
                            $fatal(1, "FAIL: operando A incorrecto");
                        observed_steps[0] <= 1'b1;
                    end
                    EXP_BASE + 64'h028: begin
                        if (!exp_we || exp_wstrb !== 8'hff || exp_wdata !== OPERAND_B)
                            $fatal(1, "FAIL: operando B incorrecto");
                        observed_steps[1] <= 1'b1;
                    end
                    EXP_BASE + 64'h010: begin
                        if (!exp_we || exp_wstrb !== 8'hff || exp_wdata !== 64'd1)
                            $fatal(1, "FAIL: CONTROL.start incorrecto");
                        observed_steps[2] <= 1'b1;
                    end
                    EXP_BASE + 64'h018: begin
                        if (exp_we) begin
                            if (exp_wstrb !== 8'hff || exp_wdata !== 64'd2)
                                $fatal(1, "FAIL: W1C STATUS incorrecto");
                            observed_steps[5] <= 1'b1;
                        end else begin
                            if (status_reads == 0) begin
                                if (exp_rdata !== 64'd2)
                                    $fatal(1, "FAIL: STATUS.done esperado=2, actual=%h", exp_rdata);
                                observed_steps[3] <= 1'b1;
                            end else if (status_reads == 1) begin
                                if (exp_rdata !== 64'd0)
                                    $fatal(1, "FAIL: STATUS tras W1C esperado=0, actual=%h", exp_rdata);
                                observed_steps[6] <= 1'b1;
                            end else begin
                                $fatal(1, "FAIL: lectura STATUS adicional inesperada");
                            end
                            status_reads <= status_reads + 1;
                        end
                    end
                    EXP_BASE + 64'h030: begin
                        if (exp_we || exp_rdata !== EXPECTED)
                            $fatal(1, "FAIL: lectura RESULT incorrecta=%h", exp_rdata);
                        observed_steps[4] <= 1'b1;
                    end
                    default: $fatal(1, "FAIL: dirección MMIO inesperada=%h", exp_addr);
                endcase
                if (exp_we) mmio_writes <= mmio_writes + 1;
                else mmio_reads <= mmio_reads + 1;
                mmio_count <= mmio_count + 1;
            end

            if (dmem_req && dmem_gnt) begin
                if (!dmem_we || dmem_addr !== RESULT_ADDR ||
                    dmem_wstrb !== 8'hff || dmem_size !== 2'b11)
                    $fatal(1, "FAIL: transacción DMEM inesperada en %h", dmem_addr);
                if (dmem_wdata !== 64'd1)
                    $fatal(1, "FAIL: software señaló FAIL, dato=%h", dmem_wdata);
                dmem_count <= dmem_count + 1;
            end
            if (dmem_rvalid) begin
                if (dmem_error) $fatal(1, "FAIL: respuesta DMEM con error");
                dmem_responses <= dmem_responses + 1;
            end
        end
    end

    integer i;
    integer cycles;
    initial begin
        if (!$value$plusargs("IMEM_HEX=%s", imem_file) ||
            !$value$plusargs("DMEM_HEX=%s", dmem_file) ||
            !$value$plusargs("IMAGE_BYTES=%d", image_bytes))
            $fatal(1, "FAIL: indicar +IMEM_HEX, +DMEM_HEX y +IMAGE_BYTES");

        image_iwords = (image_bytes + 3) / 4;
        image_dwords = (image_bytes + 7) / 8;
        if (image_bytes < 1 || image_iwords > IMEM_WORDS ||
            image_dwords > DMEM_WORDS)
            $fatal(1, "FAIL: imagen fuera de la capacidad del testbench");

        for (i = 0; i < IMEM_WORDS; i = i + 1)
            u_imem.mem[i] = 32'h00000013;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            u_dmem.mem[i] = 64'd0;

        $readmemh(imem_file, u_imem.mem, 0, image_iwords - 1);
        $readmemh(dmem_file, u_dmem.mem, 0, image_dwords - 1);
        if (u_dmem.mem[RESULT_INDEX] !== 64'd0)
            $fatal(1, "FAIL: marcador resultado no inicializa en cero");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        cycles = 0;
        while (u_dmem.mem[RESULT_INDEX] === 64'd0 && cycles < 1500) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end
        if (u_dmem.mem[RESULT_INDEX] !== 64'd1)
            $fatal(1, "FAIL: resultado de software no es PASS (valor=%h, ciclos=%0d)",
                   u_dmem.mem[RESULT_INDEX], cycles);

        /* Garantizar terminación del handshake y detectar accesos duplicados. */
        repeat (20) @(posedge clk);
        #1;
        if (observed_steps !== 7'h7f || mmio_count != 7 ||
            mmio_writes != 4 || mmio_reads != 3 || status_reads != 2 ||
            dmem_count != 1 || dmem_responses != 1)
            $fatal(1, "FAIL: cobertura pasos=%b MMIO=%0d (W=%0d R=%0d) DMEM=%0d/%0d",
                   observed_steps, mmio_count, mmio_writes, mmio_reads,
                   dmem_count, dmem_responses);

        $display("PASS: bare-metal accelerator MMIO");
        $display("      RESULT = 0x%016h", EXPECTED);
        $display("      MMIO transactions = %0d (writes=%0d, reads=%0d)",
                 mmio_count, mmio_writes, mmio_reads);
        $display("      DMEM accepted/responses = %0d/%0d", dmem_count, dmem_responses);
        $display("      cycles = %0d", cycles);
        $finish;
    end
endmodule
