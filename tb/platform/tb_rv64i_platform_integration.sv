`timescale 1ns/1ps

module tb_rv64i_platform_integration;
    localparam logic [63:0] RAM_BASE = 64'h0000_0000_8000_0000;
    localparam logic [63:0] EXP_BASE = 64'h0000_0000_1000_0000;
    localparam logic [63:0] RESULT_ADDR = RAM_BASE + 64'h300;
    localparam logic [63:0] OPERAND_A = 64'h1122_3344_5566_7788;
    localparam logic [63:0] OPERAND_B = 64'h22;
    localparam logic [63:0] EXPECTED = 64'h1122_3344_5566_77aa;
    localparam int unsigned MAX_IMAGE_WORDS = 256;
    `include "image_words.svh"

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1;
    logic run_i = 0;
    logic boot_req_i = 0, boot_we_i = 0;
    logic [63:0] boot_addr_i = RAM_BASE, boot_wdata_i = 0;
    logic [7:0] boot_wstrb_i = 0;
    wire boot_gnt_o, boot_rvalid_o, boot_error_o;
    wire [63:0] boot_rdata_o;

    // Simulacion sobre la RAM real pero con capacidad de 64 KiB;
    // el top por defecto conserva 1 MiB para la sintesis.
    rv64i_platform_top #(.RAM_BYTES(65536)) dut (
        .clk(clk), .rst(rst), .run_i(run_i),
        .boot_req_i(boot_req_i), .boot_we_i(boot_we_i),
        .boot_addr_i(boot_addr_i), .boot_wdata_i(boot_wdata_i),
        .boot_wstrb_i(boot_wstrb_i),
        .boot_gnt_o(boot_gnt_o), .boot_rvalid_o(boot_rvalid_o),
        .boot_rdata_o(boot_rdata_o), .boot_error_o(boot_error_o)
    );

    logic [63:0] program_words [0:MAX_IMAGE_WORDS-1];
    int mmio_count = 0, mmio_reads = 0, mmio_writes = 0;
    int dmem_count = 0, dmem_responses = 0, status_reads = 0;
    logic [6:0] observed_steps = '0;

    // Misma secuencia MMIO de la regresion baremetal-accelerator.
    always @(posedge clk) begin
        if (!rst && run_i) begin
            if (dut.exp_valid) begin
                if (dut.exp_error || !dut.exp_ready)
                    $fatal(1,"FAIL: expansion sin ready o con error");
                if (dut.exp_size !== 2'b11)
                    $fatal(1,"FAIL: tamano MMIO incorrecto");
                case (dut.exp_addr)
                    EXP_BASE + 'h20: begin
                        if (!dut.exp_we || dut.exp_wstrb !== 8'hff ||
                            dut.exp_wdata !== OPERAND_A)
                            $fatal(1,"FAIL: operando A");
                        observed_steps[0] <= 1;
                    end
                    EXP_BASE + 'h28: begin
                        if (!dut.exp_we || dut.exp_wstrb !== 8'hff ||
                            dut.exp_wdata !== OPERAND_B)
                            $fatal(1,"FAIL: operando B");
                        observed_steps[1] <= 1;
                    end
                    EXP_BASE + 'h10: begin
                        if (!dut.exp_we || dut.exp_wstrb !== 8'hff ||
                            dut.exp_wdata !== 64'd1)
                            $fatal(1,"FAIL: start");
                        observed_steps[2] <= 1;
                    end
                    EXP_BASE + 'h18: begin
                        if (dut.exp_we) begin
                            if (dut.exp_wstrb !== 8'hff || dut.exp_wdata !== 64'd2)
                                $fatal(1,"FAIL: STATUS W1C");
                            observed_steps[5] <= 1;
                        end else begin
                            if (status_reads == 0) begin
                                if (dut.exp_rdata !== 64'd2) $fatal(1,"FAIL: STATUS done");
                                observed_steps[3] <= 1;
                            end else if (status_reads == 1) begin
                                if (dut.exp_rdata !== 64'd0) $fatal(1,"FAIL: STATUS clear");
                                observed_steps[6] <= 1;
                            end else $fatal(1,"FAIL: lecturas STATUS extra");
                            status_reads <= status_reads + 1;
                        end
                    end
                    EXP_BASE + 'h30: begin
                        if (dut.exp_we || dut.exp_rdata !== EXPECTED)
                            $fatal(1,"FAIL: RESULT MMIO");
                        observed_steps[4] <= 1;
                    end
                    default: $fatal(1,"FAIL: direccion MMIO %h",dut.exp_addr);
                endcase
                mmio_count <= mmio_count + 1;
                if (dut.exp_we) mmio_writes <= mmio_writes + 1;
                else mmio_reads <= mmio_reads + 1;
            end
            if (dut.dmem_req && dut.dmem_gnt) begin
                if (!dut.dmem_we || dut.dmem_addr !== RESULT_ADDR ||
                    dut.dmem_wstrb !== 8'hff || dut.dmem_size !== 2'b11)
                    $fatal(1,"FAIL: DMEM inesperado %h",dut.dmem_addr);
                if (dut.dmem_wdata !== 64'd1)
                    $fatal(1,"FAIL: programa registro FAIL=%h",dut.dmem_wdata);
                dmem_count <= dmem_count + 1;
            end
            if (dut.dmem_rvalid) begin
                if (dut.dmem_error) $fatal(1,"FAIL: DMEM error");
                dmem_responses <= dmem_responses + 1;
            end
        end
    end

    task automatic boot_write(input logic [63:0] a, d);
        @(negedge clk);
        boot_req_i = 1; boot_we_i = 1;
        boot_addr_i = a; boot_wdata_i = d; boot_wstrb_i = 8'hff;
        #1;
        if (!boot_gnt_o) $fatal(1,"FAIL: boot sin grant");
        @(posedge clk); #1;
        if (!boot_rvalid_o || boot_error_o) $fatal(1,"FAIL: boot write");
        @(negedge clk); boot_req_i = 0; boot_we_i = 0; boot_wstrb_i = 0;
    endtask

    task automatic boot_read_check(input logic [63:0] a, expected);
        @(negedge clk);
        boot_req_i = 1; boot_we_i = 0; boot_addr_i = a;
        #1;
        if (!boot_gnt_o) $fatal(1,"FAIL: boot read sin grant");
        @(posedge clk); #1;
        if (!boot_rvalid_o || boot_error_o || boot_rdata_o !== expected)
            $fatal(1,"FAIL: marcador direccion=%h recibido=%h esperado=%h",
                   a,boot_rdata_o,expected);
        @(negedge clk); boot_req_i = 0;
    endtask

    initial begin : scenario
        int cycles;
        if (IMAGE_WORDS < 1 || IMAGE_WORDS > MAX_IMAGE_WORDS)
            $fatal(1,"FAIL: imagen fuera de capacidad de TB");
        $readmemh("integration_dmem.hex", program_words, 0, IMAGE_WORDS-1);

        repeat (4) @(negedge clk);
        rst = 0;
        // Carga binaria sobre interfaz boot real (sin forzar arrays internos).
        for (int i=0; i<IMAGE_WORDS; i++)
            boot_write(RAM_BASE + 64'(i*8), program_words[i]);
        boot_read_check(RAM_BASE, program_words[0]);
        boot_read_check(RESULT_ADDR, 64'd0);

        @(negedge clk);
        run_i = 1;
        cycles = 0;
        while (dmem_responses == 0 && cycles < 2500) begin
            @(posedge clk); #1;
            cycles++;
        end
        if (dmem_responses != 1)
            $fatal(1,"FAIL: no finalizo el programa en 2500 ciclos");
        repeat (20) @(posedge clk);
        #1;
        if (observed_steps !== 7'h7f || mmio_count != 7 ||
            mmio_writes != 4 || mmio_reads != 3 || status_reads != 2 ||
            dmem_count != 1 || dmem_responses != 1)
            $fatal(1,"FAIL: MMIO pasos=%b MMIO=%0d W=%0d R=%0d DMEM=%0d/%0d",
                   observed_steps,mmio_count,mmio_writes,mmio_reads,
                   dmem_count,dmem_responses);

        @(negedge clk);
        run_i = 0;
        boot_read_check(RESULT_ADDR, 64'd1);
        $display("PASS: P2.6.2 RV64I + UltraRAM XPM + MMIO bare-metal");
        $display("      result_flag = 1; mmio=%0d; dmem=%0d/%0d; cycles=%0d",
                 mmio_count,dmem_count,dmem_responses,cycles);
        $finish;
    end
endmodule
