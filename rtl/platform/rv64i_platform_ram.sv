`timescale 1ns/1ps

// TFG - P2.6.1 / RAM física unificada para RV64I (K26).
// RAM unificada organizada en bancos XPM UltraRAM, dos puertos síncronos:
//   A: lectura de instrucción (32 bits, fetch sobre palabra de 64 bits).
//   B: lectura/escritura de datos del RV64I, o carga/lectura por supervisor.
// Todos los puertos comparten 'clk'. No hay inicialización por bitstream.
// El supervisor DEBE completar la carga antes de activar run_i.
// Memoria 64 bits little-endian y escrituras con wstrb[7:0].
// NO_CHANGE en escritura. No acceso simultáneo IMEM/DMEM a la
// misma palabra cuando DMEM escribe (el grant IMEM se retiene).
// El core actual no ofrece imem_error: accesos IF fuera de rango
// responden 0x00000000 (instrucción ilegal), NO instruction access fault.
module rv64i_platform_ram #(
    parameter logic [63:0] BASE_ADDR = 64'h0000_0000_8000_0000,
    parameter int unsigned RAM_BYTES = 1048576
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        run_i,

    // IMEM (core_top)
    input  logic        imem_req_i,
    input  logic [63:0] imem_addr_i,
    output logic        imem_gnt_o,
    output logic        imem_rvalid_o,
    output logic [31:0] imem_rdata_o,

    // DMEM (core_top)
    input  logic        dmem_req_i,
    input  logic [63:0] dmem_addr_i,
    input  logic        dmem_we_i,
    input  logic [63:0] dmem_wdata_i,
    input  logic [7:0]  dmem_wstrb_i,
    output logic        dmem_gnt_o,
    output logic        dmem_rvalid_o,
    output logic [63:0] dmem_rdata_o,
    output logic        dmem_error_o,

    // Puerto nativo del supervisor en el MISMO dominio clk;
    // un futuro adaptador AXI debe cumplir este contrato.
    // Dirección de palabra alineada a 8 bytes (no offset de byte).
    input  logic        boot_req_i,
    input  logic        boot_we_i,
    input  logic [63:0] boot_addr_i,
    input  logic [63:0] boot_wdata_i,
    input  logic [7:0]  boot_wstrb_i,
    output logic        boot_gnt_o,
    output logic        boot_rvalid_o,
    output logic [63:0] boot_rdata_o,
    output logic        boot_error_o
);
    localparam int unsigned RAM_WORDS = RAM_BYTES / 8;
    localparam int unsigned INDEX_W = $clog2(RAM_WORDS);

    // Cada bloque UltraRAM de K26 tiene 4096 posiciones de 72 bits.
    // Bancos de 4096 x 64 evitan una cascada fisica de 32 niveles
    // y conservan una respuesta de lectura de un ciclo.
    // Para el TB de capacidad reducida se utiliza un banco menor.
    localparam int unsigned BANK_ADDR_W = (RAM_WORDS < 4096) ? INDEX_W : 12;
    localparam int unsigned BANK_DEPTH = 1 << BANK_ADDR_W;
    localparam int unsigned BANK_COUNT = RAM_WORDS / BANK_DEPTH;
    localparam int unsigned BANK_SEL_W = (BANK_COUNT > 1) ? $clog2(BANK_COUNT) : 1;

    logic [BANK_SEL_W-1:0] i_bank, port_b_bank;
    logic [BANK_SEL_W-1:0] i_bank_q, port_b_bank_q;
    logic [BANK_ADDR_W-1:0] i_local_idx, port_b_local_idx;
    wire [63:0] i_bank_data [0:BANK_COUNT-1];
    wire [63:0] b_bank_data [0:BANK_COUNT-1];

    logic [63:0] i_off, d_off, b_off;
    logic i_range, d_range, b_range;
    logic i_aligned, b_aligned;
    logic [INDEX_W-1:0] i_idx, d_idx, b_idx;

    assign i_off = imem_addr_i - BASE_ADDR;
    assign d_off = dmem_addr_i - BASE_ADDR;
    assign b_off = boot_addr_i - BASE_ADDR;
    assign i_range = (imem_addr_i >= BASE_ADDR) &&
                     (i_off < 64'(RAM_BYTES));
    assign d_range = (dmem_addr_i >= BASE_ADDR) &&
                     (d_off < 64'(RAM_BYTES));
    assign b_range = (boot_addr_i >= BASE_ADDR) &&
                     (b_off < 64'(RAM_BYTES));
    assign i_aligned = (imem_addr_i[1:0] == 2'b00);
    assign b_aligned = (boot_addr_i[2:0] == 3'b000);
    assign i_idx = i_off[INDEX_W+2:3];
    assign d_idx = d_off[INDEX_W+2:3];
    assign b_idx = b_off[INDEX_W+2:3];

    logic if_store_collision;
    assign if_store_collision = dmem_req_i && dmem_we_i && d_range &&
                                i_range && (d_idx == i_idx);

    assign imem_gnt_o = run_i && !rst && !if_store_collision;
    assign dmem_gnt_o = run_i && !rst;
    assign boot_gnt_o = !run_i && !rst;

    logic i_accept, d_accept, b_accept;
    assign i_accept = imem_req_i && imem_gnt_o;
    assign d_accept = dmem_req_i && dmem_gnt_o;
    assign b_accept = boot_req_i && boot_gnt_o;

    // Banco de lectura IF; port A siempre es solo lectura.
    logic [63:0] i_word;
    logic i_read;
    assign i_read = i_accept && i_range && i_aligned;
    assign i_bank = BANK_SEL_W'(i_idx >> BANK_ADDR_W);
    assign i_local_idx = i_idx[BANK_ADDR_W-1:0];

    // Puerto B físico, multiplexado en modo de arranque.
    logic b_read, b_write;
    logic [INDEX_W-1:0] port_b_idx;
    logic [63:0] port_b_wdata;
    logic [7:0] port_b_wstrb;
    logic [63:0] port_b_word;
    assign b_read = run_i ? (d_accept && !dmem_we_i && d_range) :
                              (b_accept && !boot_we_i && b_range && b_aligned);
    assign b_write = run_i ? (d_accept && dmem_we_i && d_range) :
                               (b_accept && boot_we_i && b_range && b_aligned);
    assign port_b_idx = run_i ? d_idx : b_idx;
    assign port_b_wdata = run_i ? dmem_wdata_i : boot_wdata_i;
    assign port_b_wstrb = run_i ? dmem_wstrb_i : boot_wstrb_i;
    assign port_b_bank = BANK_SEL_W'(port_b_idx >> BANK_ADDR_W);
    assign port_b_local_idx = port_b_idx[BANK_ADDR_W-1:0];

    // P2.6.1c: memoria fisica mediante macro XPM oficial de AMD.
    // Una XPM de 4096 x 64 por banco (32 bancos para RAM_BYTES=1 MiB).
    // Port A: solo lectura IF. Port B: lectura DMEM/boot o escritura byte-wide.
    // Ambos puertos usan el mismo reloj; NO_CHANGE nativo de UltraRAM.
    // Latencia de lectura de 1 ciclo, preservando el contrato anterior.
    for (genvar bank = 0; bank < BANK_COUNT; bank++) begin : g_uram_bank
        wire [63:0] read_a_q;
        wire [63:0] read_b_q;
        wire bank_a_en = i_read && (i_bank == BANK_SEL_W'(bank));
        wire bank_b_read = b_read && (port_b_bank == BANK_SEL_W'(bank));
        wire bank_b_write = b_write && (port_b_bank == BANK_SEL_W'(bank));
        wire bank_b_en = bank_b_read || bank_b_write;
        wire [7:0] bank_b_we = bank_b_write ? port_b_wstrb : 8'h00;

        xpm_memory_tdpram #(
            .ADDR_WIDTH_A(BANK_ADDR_W),
            .ADDR_WIDTH_B(BANK_ADDR_W),
            .AUTO_SLEEP_TIME(0),
            .BYTE_WRITE_WIDTH_A(8),
            .BYTE_WRITE_WIDTH_B(8),
            .CASCADE_HEIGHT(0),
            .CLOCKING_MODE("common_clock"),
            .ECC_MODE("no_ecc"),
            .MEMORY_INIT_FILE("none"),
            .MEMORY_INIT_PARAM("0"),
            .MEMORY_OPTIMIZATION("true"),
            .MEMORY_PRIMITIVE("ultra"),
            .MEMORY_SIZE(BANK_DEPTH * 64),
            .MESSAGE_CONTROL(0),
            .READ_DATA_WIDTH_A(64),
            .READ_DATA_WIDTH_B(64),
            .READ_LATENCY_A(1),
            .READ_LATENCY_B(1),
            .READ_RESET_VALUE_A("0"),
            .READ_RESET_VALUE_B("0"),
            .RST_MODE_A("SYNC"),
            .RST_MODE_B("SYNC"),
            .SIM_ASSERT_CHK(1),
            .USE_MEM_INIT(0),
            .WAKEUP_TIME("disable_sleep"),
            .WRITE_DATA_WIDTH_A(64),
            .WRITE_DATA_WIDTH_B(64),
            .WRITE_MODE_A("no_change"),
            .WRITE_MODE_B("no_change"),
            .WRITE_PROTECT(1)
        ) u_mem (
            .clka(clk),
            .clkb(clk),
            .addra(i_local_idx),
            .addrb(port_b_local_idx),
            .dina(64'b0),
            .dinb(port_b_wdata),
            .ena(bank_a_en),
            .enb(bank_b_en),
            .wea(8'b0),
            .web(bank_b_we),
            .douta(read_a_q),
            .doutb(read_b_q),
            .rsta(1'b0),
            .rstb(1'b0),
            .regcea(1'b1),
            .regceb(1'b1),
            .sleep(1'b0),
            .injectsbiterra(1'b0),
            .injectdbiterra(1'b0),
            .injectsbiterrb(1'b0),
            .injectdbiterrb(1'b0),
            .sbiterra(),
            .dbiterra(),
            .sbiterrb(),
            .dbiterrb()
        );

        assign i_bank_data[bank] = read_a_q;
        assign b_bank_data[bank] = read_b_q;
    end

    // La seleccion del banco se registra en el mismo flanco
    // que la lectura: las respuestas siguen siendo de un ciclo.
    always_ff @(posedge clk) begin
        if (i_read) i_bank_q <= i_bank;
        if (b_read) port_b_bank_q <= port_b_bank;
    end
    assign i_word = i_bank_data[i_bank_q];
    assign port_b_word = b_bank_data[port_b_bank_q];

    logic i_valid_q, i_bad_q, i_half_q;
    logic d_valid_q, d_bad_q, d_was_write_q;
    logic b_valid_q, b_bad_q, b_was_write_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            i_valid_q <= 1'b0;
            i_bad_q <= 1'b0;
            i_half_q <= 1'b0;
            d_valid_q <= 1'b0;
            d_bad_q <= 1'b0;
            d_was_write_q <= 1'b0;
            b_valid_q <= 1'b0;
            b_bad_q <= 1'b0;
            b_was_write_q <= 1'b0;
        end else begin
            i_valid_q <= i_accept;
            i_bad_q <= !i_range || !i_aligned;
            if (i_accept) i_half_q <= imem_addr_i[2];
            d_valid_q <= d_accept;
            if (d_accept) begin
                d_bad_q <= !d_range;
                d_was_write_q <= dmem_we_i;
            end
            b_valid_q <= b_accept;
            if (b_accept) begin
                b_bad_q <= !b_range || !b_aligned;
                b_was_write_q <= boot_we_i;
            end
        end
    end

    assign imem_rvalid_o = i_valid_q;
    assign imem_rdata_o = (!i_valid_q || i_bad_q) ? 32'h0000_0000 :
                           (i_half_q ? i_word[63:32] : i_word[31:0]);
    assign dmem_rvalid_o = d_valid_q;
    assign dmem_error_o = d_valid_q && d_bad_q;
    assign dmem_rdata_o = (!d_valid_q || d_bad_q || d_was_write_q) ? 64'd0 : port_b_word;
    assign boot_rvalid_o = b_valid_q;
    assign boot_error_o = b_valid_q && b_bad_q;
    assign boot_rdata_o = (!b_valid_q || b_bad_q || b_was_write_q) ? 64'd0 : port_b_word;
endmodule
