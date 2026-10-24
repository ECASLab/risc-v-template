`timescale 1ns/1ps

// TFG B.9.3.8c — testbench parametrizado para casos ACT4 RV64I.
// Utiliza los modelos sincronicos REALES del proyecto.
// NO altera el RTL ni implementa soporte arquitectural privilegiado adicional.
module tb_core_act4_generic;
    localparam logic [63:0] RAM_BASE    = 64'h0000_0000_8000_0000;
    localparam logic [63:0] RAM_BYTES   = 64'h0000_0000_0010_0000;
    localparam logic [63:0] TRAP_VECTOR = RAM_BASE + 64'h100;
    localparam logic [63:0] EXP_BASE    = 64'h0000_0000_1000_0000;
    localparam int unsigned IMEM_WORDS = 262144;
    localparam int unsigned DMEM_WORDS = 131072;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic imem_req, imem_gnt, imem_rvalid;
    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic dmem_req, dmem_gnt, dmem_rvalid, dmem_error;
    logic dmem_we;
    logic [7:0] dmem_wstrb;
    logic [63:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [1:0] dmem_size;

    logic exp_valid, exp_we, exp_ready, exp_error;
    logic [63:0] exp_addr, exp_wdata, exp_rdata;
    logic [7:0] exp_wstrb;
    logic [1:0] exp_size;

    assign exp_ready = 1'b1;
    assign exp_rdata = 64'd0;
    assign exp_error = 1'b1;  // MMIO no usado por pruebas ACT4 de enteros en RAM.

    core_top #(
        .RESET_PC(RAM_BASE), .TRAP_VECTOR(TRAP_VECTOR), .EXP_BASE(EXP_BASE)
    ) dut (
        .clk(clk), .rst(rst),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_gnt(imem_gnt),
        .imem_rvalid(imem_rvalid), .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_gnt(dmem_gnt),
        .dmem_rvalid(dmem_rvalid), .dmem_error(dmem_error), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_wstrb(dmem_wstrb),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_size(dmem_size),
        .exp_valid(exp_valid), .exp_we(exp_we), .exp_addr(exp_addr),
        .exp_wdata(exp_wdata), .exp_wstrb(exp_wstrb), .exp_size(exp_size),
        .exp_ready(exp_ready), .exp_rdata(exp_rdata), .exp_error(exp_error)
    );

    imem_sync_model #(
        .MEM_WORDS(IMEM_WORDS), .BASE_ADDR(RAM_BASE),
        .GNT_DELAY(1), .RESP_DELAY(2)
    ) u_imem (
        .clk(clk), .rst(rst), .req_i(imem_req), .gnt_o(imem_gnt),
        .addr_i(imem_addr), .rvalid_o(imem_rvalid), .rdata_o(imem_rdata)
    );

    dmem_sync_model #(
        .MEM_WORDS(DMEM_WORDS), .BASE_ADDR(RAM_BASE),
        .GNT_DELAY(1), .RESP_DELAY(2), .FAULT_ENABLE(1'b0)
    ) u_dmem (
        .clk(clk), .rst(rst), .req_i(dmem_req), .gnt_o(dmem_gnt),
        .addr_i(dmem_addr), .we_i(dmem_we), .wdata_i(dmem_wdata),
        .wstrb_i(dmem_wstrb), .size_i(dmem_size),
        .rvalid_o(dmem_rvalid), .rdata_o(dmem_rdata), .error_o(dmem_error)
    );

    string imem_hex, dmem_hex, case_name;
    logic [63:0] entry_addr = RAM_BASE;
    logic [63:0] high_text_addr = RAM_BASE;
    int unsigned high_word_index = 0;
    logic [63:0] tohost_addr = 64'd0;
    int unsigned tohost_index = 0;
    integer max_cycles = 500000;
    integer cycle_count = 0;
    integer accepted_imem = 0;
    integer accepted_dmem = 0;
    integer completed_dmem = 0;
    logic [63:0] last_fetch_addr = 64'd0;
    logic [63:0] last_data_addr = 64'd0;
    bit term_seen = 0;
    logic [63:0] term_value = 64'd0;

    initial begin
        if (!$value$plusargs("IMEM_HEX=%s", imem_hex))
            $fatal(1, "ERROR: falta +IMEM_HEX");
        if (!$value$plusargs("DMEM_HEX=%s", dmem_hex))
            $fatal(1, "ERROR: falta +DMEM_HEX");
        if (!$value$plusargs("CASE_NAME=%s", case_name))
            $fatal(1, "ERROR: falta +CASE_NAME");
        if (!$value$plusargs("ENTRY_HEX=%h", entry_addr))
            $fatal(1, "ERROR: falta +ENTRY_HEX");
        if (!$value$plusargs("HIGH_TEXT_HEX=%h", high_text_addr))
            $fatal(1, "ERROR: falta +HIGH_TEXT_HEX");
        if (!$value$plusargs("TOHOST_HEX=%h", tohost_addr))
            $fatal(1, "ERROR: falta +TOHOST_HEX");
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            if (max_cycles < 100)
                $fatal(1, "ERROR: MAX_CYCLES demasiado pequeno");
        end
        if ((tohost_addr < RAM_BASE) ||
            (tohost_addr > RAM_BASE + RAM_BYTES - 8) ||
            (tohost_addr[2:0] != 3'b000))
            $fatal(1, "ERROR: tohost invalido: %016h", tohost_addr);
        if (entry_addr != RAM_BASE)
            $fatal(1, "ERROR: entry distinto del RESET_PC 0x%016h", RAM_BASE);
        if (high_text_addr < RAM_BASE ||
            high_text_addr > RAM_BASE + RAM_BYTES - 4 ||
            high_text_addr[1:0] != 2'b00)
            $fatal(1, "ERROR: HIGH_TEXT_HEX invalido: %016h", high_text_addr);
        tohost_index = (tohost_addr - RAM_BASE) >> 3;
        high_word_index = (high_text_addr - RAM_BASE) >> 2;

        $display("ACT4 DUT: core_top | %s | RAM=1 MiB", case_name);
        $display("IMEM=%s", imem_hex);
        $display("DMEM=%s", dmem_hex);
        $display("tohost=0x%016h idx=%0d", tohost_addr, tohost_index);
        $readmemh(imem_hex, u_imem.mem);
        $readmemh(dmem_hex, u_dmem.mem);
        if (u_imem.mem[0] === 32'hxxxx_xxxx)
            $fatal(1, "FAIL: IMEM sin inicializar en reset PC");
        if (u_imem.mem[high_word_index] === 32'h0000_0000 ||
            (^u_imem.mem[high_word_index] === 1'bx))
            $fatal(1, "FAIL: .text.rvmodel no cargada en 0x%016h", high_text_addr);
        if (u_dmem.mem[tohost_index] !== 64'd0)
            $fatal(1, "FAIL: tohost inicial no cero: %016h", u_dmem.mem[tohost_index]);
        $display("PASS: imagenes cargadas (incluida IMEM alta)");

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        $display("INFO: reset liberado. Max ciclos=%0d", max_cycles);
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;
            if (cycle_count % 100000 == 0)
                $display("INFO: ciclos=%0d fetch=%0d dmem=%0d rvalid=%0d",
                         cycle_count, accepted_imem, accepted_dmem, completed_dmem);
            if (cycle_count >= max_cycles)
                $fatal(1, "FAIL: TIMEOUT ciclos=%0d fetch=%0d dmem=%0d respuestas=%0d ultimo_fetch=%016h ultima_dmem=%016h",
                       cycle_count, accepted_imem, accepted_dmem, completed_dmem,
                       last_fetch_addr, last_data_addr);
            if (exp_valid)
                $fatal(1, "FAIL: acceso MMIO inesperado en %s, addr=%016h", case_name, exp_addr);
            if (imem_req && imem_gnt) begin
                if (imem_addr < RAM_BASE || imem_addr >= RAM_BASE + RAM_BYTES)
                    $fatal(1, "FAIL: fetch fuera RAM: %016h", imem_addr);
                if (accepted_imem == 0 && imem_addr !== entry_addr)
                    $fatal(1, "FAIL: primer fetch no coincide con entry: %016h", imem_addr);
                if (accepted_imem < 20)
                    $display("TRACE: FETCH#%0d pc=%016h", accepted_imem, imem_addr);
                last_fetch_addr = imem_addr;
                accepted_imem = accepted_imem + 1;
            end
            if (dmem_req && dmem_gnt) begin
                if (dmem_addr < RAM_BASE || dmem_addr >= RAM_BASE + RAM_BYTES)
                    $fatal(1, "FAIL: acceso DMEM fuera de RAM: %016h", dmem_addr);
                if (accepted_dmem < 15)
                    $display("TRACE: DMEM#%0d addr=%016h we=%b wstrb=%02h data=%016h",
                             accepted_dmem, dmem_addr, dmem_we, dmem_wstrb, dmem_wdata);
                last_data_addr = dmem_addr;
                accepted_dmem = accepted_dmem + 1;
                if (dmem_we && dmem_addr == tohost_addr) begin
                    if (term_seen)
                        $fatal(1, "FAIL: multiples escrituras a tohost");
                    if (dmem_size !== 2'b11 || dmem_wstrb !== 8'hff)
                        $fatal(1, "FAIL: tohost no escrito mediante SD 64b: size=%b strb=%02h",
                               dmem_size, dmem_wstrb);
                    term_seen = 1'b1;
                    term_value = dmem_wdata;
                    $display("INFO: store tohost aceptado: 0x%016h ciclo=%0d",
                             term_value, cycle_count);
                end
            end
            if (dmem_rvalid) begin
                completed_dmem = completed_dmem + 1;
                if (dmem_error)
                    $fatal(1, "FAIL: dmem_error en ciclo=%0d", cycle_count);
                if (term_seen) begin
                    // Actualizacion de mem en flanco de aceptacion ya terminada.
                    #1;
                    if (u_dmem.mem[tohost_index] !== term_value)
                        $fatal(1, "FAIL: memoria tohost=%016h != bus=%016h",
                               u_dmem.mem[tohost_index], term_value);
                    if (term_value === 64'd1) begin
                        $display("PASS: ACT4 %s ejecutado en core_top (tohost=1)", case_name);
                        $display("      ciclos=%0d fetch=%0d dmem=%0d respuestas=%0d",
                                 cycle_count, accepted_imem, accepted_dmem, completed_dmem);
                        $finish;
                    end else if (term_value === 64'd3) begin
                        $fatal(1, "FAIL: ACT4 %s informa fallo (tohost=3)", case_name);
                    end else begin
                        $fatal(1, "FAIL: tohost inesperado=0x%016h", term_value);
                    end
                end
            end
        end
    end
endmodule
