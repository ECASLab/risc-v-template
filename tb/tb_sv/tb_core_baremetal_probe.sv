
`timescale 1ns/1ps

module tb_core_baremetal_probe;

    // =========================================================
    // Mapa de memoria
    // =========================================================

    localparam logic [63:0] RAM_BASE =
        64'h0000_0000_8000_0000;

    localparam logic [63:0] TRAP_VECTOR =
        RAM_BASE + 64'h0000_0000_0000_0100;

    localparam logic [63:0] EXP_BASE =
        64'h0000_0000_1000_0000;

    localparam int unsigned IMEM_WORDS = 256;
    localparam int unsigned DMEM_WORDS = 256;
    localparam int unsigned PROBE_IMEM_WORDS = 12;
    localparam int unsigned PROBE_DMEM_WORDS = 6;

    localparam logic [63:0] DATA_ADDR =
        64'h0000_0000_8000_0020;

    localparam logic [63:0] RESULT_ADDR =
        64'h0000_0000_8000_0028;

    localparam logic [63:0] EXPECTED_DATA =
        64'h1122_3344_5566_7788;

    // =========================================================
    // Archivos de imagen
    // =========================================================

    string imem_hex_file;
    string dmem_hex_file;

    // =========================================================
    // Clock / reset
    // =========================================================

    logic clk;
    logic rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // IMEM
    // =========================================================

    logic        imem_req;
    logic        imem_gnt;
    logic        imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    // =========================================================
    // DMEM
    // =========================================================

    logic        dmem_req;
    logic        dmem_gnt;
    logic        dmem_rvalid;
    logic        dmem_error;
    logic [63:0] dmem_rdata;

    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    // =========================================================
    // Expansión
    // =========================================================

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;

    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b0;

    // =========================================================
    // DUT
    // =========================================================

    core_top #(
        .RESET_PC    (RAM_BASE),
        .TRAP_VECTOR (TRAP_VECTOR),
        .EXP_BASE    (EXP_BASE)
    ) dut (
        .clk         (clk),
        .rst         (rst),

        .imem_req    (imem_req),
        .imem_addr   (imem_addr),
        .imem_gnt    (imem_gnt),
        .imem_rvalid (imem_rvalid),
        .imem_rdata  (imem_rdata),

        .dmem_req    (dmem_req),
        .dmem_gnt    (dmem_gnt),
        .dmem_rvalid (dmem_rvalid),
        .dmem_error  (dmem_error),
        .dmem_rdata  (dmem_rdata),

        .dmem_we     (dmem_we),
        .dmem_wstrb  (dmem_wstrb),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_size   (dmem_size),

        .exp_valid   (exp_valid),
        .exp_we      (exp_we),
        .exp_addr    (exp_addr),
        .exp_wdata   (exp_wdata),
        .exp_wstrb   (exp_wstrb),
        .exp_size    (exp_size),

        .exp_ready   (exp_ready),
        .exp_rdata   (exp_rdata),
        .exp_error   (exp_error)
    );

    // =========================================================
    // Memorias síncronas
    // =========================================================

    imem_sync_model #(
        .MEM_WORDS  (IMEM_WORDS),
        .BASE_ADDR  (RAM_BASE),
        .GNT_DELAY  (1),
        .RESP_DELAY (2)
    ) u_imem (
        .clk      (clk),
        .rst      (rst),
        .req_i    (imem_req),
        .gnt_o    (imem_gnt),
        .addr_i   (imem_addr),
        .rvalid_o (imem_rvalid),
        .rdata_o  (imem_rdata)
    );

    dmem_sync_model #(
        .MEM_WORDS    (DMEM_WORDS),
        .BASE_ADDR    (RAM_BASE),
        .GNT_DELAY    (1),
        .RESP_DELAY   (2),
        .FAULT_ENABLE (1'b0)
    ) u_dmem (
        .clk      (clk),
        .rst      (rst),

        .req_i    (dmem_req),
        .gnt_o    (dmem_gnt),

        .addr_i   (dmem_addr),
        .we_i     (dmem_we),
        .wdata_i  (dmem_wdata),
        .wstrb_i  (dmem_wstrb),
        .size_i   (dmem_size),

        .rvalid_o (dmem_rvalid),
        .rdata_o  (dmem_rdata),
        .error_o  (dmem_error)
    );

    // =========================================================
    // Monitores
    // =========================================================

    integer imem_accept_count;
    integer loop_fetch_count;
    integer dmem_accept_count;
    integer dmem_response_count;

    always @(posedge clk) begin
        if (rst) begin
            imem_accept_count <= 0;
            loop_fetch_count  <= 0;
            dmem_accept_count <= 0;
            dmem_response_count <= 0;
        end
        else begin
            if (exp_valid) begin
                $fatal(
                    1,
                    "FAIL: acceso inesperado a expansión addr=0x%016h",
                    exp_addr
                );
            end

            if (imem_req && imem_gnt) begin
                if (
                    (imem_addr < RAM_BASE) ||
                    (imem_addr >=
                     (RAM_BASE + (IMEM_WORDS * 64'd4)))
                ) begin
                    $fatal(
                        1,
                        "FAIL: fetch fuera de RAM addr=0x%016h",
                        imem_addr
                    );
                end

                if (
                    (imem_accept_count == 0) &&
                    (imem_addr !== RAM_BASE)
                ) begin
                    $fatal(
                        1,
                        "FAIL: primer fetch addr=0x%016h expected=0x%016h",
                        imem_addr,
                        RAM_BASE
                    );
                end

                if (imem_addr == (RAM_BASE + 64'h18))
                    loop_fetch_count <= loop_fetch_count + 1;

                imem_accept_count <= imem_accept_count + 1;
            end

            // ========================================================
            // DMEM monitor
            // ========================================================
            if (dmem_req && dmem_gnt) begin
                case (dmem_accept_count)

                    // LD t3, 0(t2)
                    0: begin
                        if (dmem_we)
                            $fatal(1, "FAIL: primer acceso DMEM debía ser load");

                        if (dmem_addr !== DATA_ADDR) begin
                            $fatal(
                                1,
                                "FAIL: LD addr=0x%016h expected=0x%016h",
                                dmem_addr,
                                DATA_ADDR
                            );
                        end

                        if (dmem_size !== 2'b11) begin
                            $fatal(
                                1,
                                "FAIL: LD size=%b expected=11",
                                dmem_size
                            );
                        end

                        if (dmem_wstrb !== 8'h00) begin
                            $fatal(
                                1,
                                "FAIL: LD wstrb=%02h expected=00",
                                dmem_wstrb
                            );
                        end
                    end

                    // SD t3, 8(t2)
                    1: begin
                        if (!dmem_we)
                            $fatal(1, "FAIL: segundo acceso DMEM debía ser store");

                        if (dmem_addr !== RESULT_ADDR) begin
                            $fatal(
                                1,
                                "FAIL: SD addr=0x%016h expected=0x%016h",
                                dmem_addr,
                                RESULT_ADDR
                            );
                        end

                        if (dmem_size !== 2'b11) begin
                            $fatal(
                                1,
                                "FAIL: SD size=%b expected=11",
                                dmem_size
                            );
                        end

                        if (dmem_wstrb !== 8'hff) begin
                            $fatal(
                                1,
                                "FAIL: SD wstrb=%02h expected=ff",
                                dmem_wstrb
                            );
                        end

                        if (dmem_wdata !== EXPECTED_DATA) begin
                            $fatal(
                                1,
                                "FAIL: SD wdata=0x%016h expected=0x%016h",
                                dmem_wdata,
                                EXPECTED_DATA
                            );
                        end
                    end

                    default: begin
                        $fatal(
                            1,
                            "FAIL: acceso DMEM extra #%0d addr=0x%016h",
                            dmem_accept_count,
                            dmem_addr
                        );
                    end
                endcase

                dmem_accept_count <= dmem_accept_count + 1;
            end

            if (dmem_rvalid) begin
                if (dmem_error)
                    $fatal(1, "FAIL: respuesta DMEM reportó error");

                dmem_response_count <= dmem_response_count + 1;
            end
        end
    end

    // =========================================================
    // Ejecución
    // =========================================================

    integer i;
    integer timeout;

    initial begin
        rst = 1'b1;

        if (!$value$plusargs("IMEM_HEX=%s", imem_hex_file)) begin
            $fatal(
                1,
                "FAIL: falta +IMEM_HEX=<archivo>"
            );
        end

        if (!$value$plusargs("DMEM_HEX=%s", dmem_hex_file)) begin
            $fatal(
                1,
                "FAIL: falta +DMEM_HEX=<archivo>"
            );
        end

        $display("IMEM image: %s", imem_hex_file);
        $display("DMEM image: %s", dmem_hex_file);

        // Estado inicial conocido.
        for (i = 0; i < IMEM_WORDS; i = i + 1)
            u_imem.mem[i] = 32'h0000_0013;

        for (i = 0; i < DMEM_WORDS; i = i + 1)
            u_dmem.mem[i] = 64'd0;

        $readmemh(
            imem_hex_file,
            u_imem.mem,
            0,
            PROBE_IMEM_WORDS - 1
        );

        $readmemh(
            dmem_hex_file,
            u_dmem.mem,
            0,
            PROBE_DMEM_WORDS - 1
        );

       if (u_dmem.mem[4] !== EXPECTED_DATA) begin
            $fatal(
                1,
                "FAIL: probe_data inicial=0x%016h expected=0x%016h",
                u_dmem.mem[4],
                EXPECTED_DATA
            );
        end

        if (u_dmem.mem[5] !== 64'd0) begin
            $fatal(
                1,
                "FAIL: probe_result inicial=0x%016h expected=0",
                u_dmem.mem[5]
            );
        end

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;
        #1;

        timeout = 0;

        while (
            (
                (dmem_response_count < 2) ||
                (loop_fetch_count < 2)
            ) &&
            (timeout < 500)
        ) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        if (dut.u_regfile.regs[5] !== 64'd1) begin
            $fatal(
                1,
                "FAIL: t0/x5=0x%016h expected=1",
                dut.u_regfile.regs[5]
            );
        end

        if (dut.u_regfile.regs[6] !== 64'd3) begin
            $fatal(
                1,
                "FAIL: t1/x6=0x%016h expected=3",
                dut.u_regfile.regs[6]
            );
        end

        if (loop_fetch_count < 2) begin
            $fatal(
                1,
                "FAIL: JAL loop no observado, fetch_count=%0d",
                loop_fetch_count
            );
        end

        if (dmem_accept_count != 2) begin
            $fatal(
                1,
                "FAIL: dmem_accept_count=%0d expected=2",
                dmem_accept_count
            );
        end

        if (dmem_response_count != 2) begin
            $fatal(
                1,
                "FAIL: dmem_response_count=%0d expected=2",
                dmem_response_count
            );
        end

        if (u_dmem.mem[4] !== EXPECTED_DATA) begin
            $fatal(
                1,
                "FAIL: probe_data cambió=0x%016h expected=0x%016h",
                u_dmem.mem[4],
                EXPECTED_DATA
            );
        end

        if (u_dmem.mem[5] !== EXPECTED_DATA) begin
            $fatal(
                1,
                "FAIL: probe_result=0x%016h expected=0x%016h",
                u_dmem.mem[5],
                EXPECTED_DATA
            );
        end

        if (dut.u_regfile.regs[7] !== DATA_ADDR) begin
            $fatal(
                1,
                "FAIL: t2/x7=0x%016h expected=0x%016h",
                dut.u_regfile.regs[7],
                DATA_ADDR
            );
        end

        if (dut.u_regfile.regs[28] !== EXPECTED_DATA) begin
            $fatal(
                1,
                "FAIL: t3/x28=0x%016h expected=0x%016h",
                dut.u_regfile.regs[28],
                EXPECTED_DATA
            );
        end

        $display("============================================================");
        $display("PASS: ELF bare-metal compilado ejecutado por core_top");
        $display("      RESET_PC       = 0x%016h", RAM_BASE);
        $display("      LD addr         = 0x%016h", DATA_ADDR);
        $display("      LD value        = 0x%016h", dut.u_regfile.regs[28]);
        $display("      SD addr         = 0x%016h", RESULT_ADDR);
        $display("      SD final value  = 0x%016h", u_dmem.mem[5]);
        $display("      DMEM requests   = %0d", dmem_accept_count);
        $display("      DMEM responses  = %0d", dmem_response_count);
        $display("      JAL loop fetch  = %0d", loop_fetch_count);
        $display("============================================================");

        $finish;
    end

endmodule
