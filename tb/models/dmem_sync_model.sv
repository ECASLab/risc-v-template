`timescale 1ns/1ps

module dmem_sync_model #(
    // Número de palabras de 64 bits.
    parameter int unsigned MEM_WORDS = 1024,

    // Número de ciclos completos durante los cuales req puede
    // permanecer esperando antes de recibir grant.
    //
    // GNT_DELAY = 0:
    //   gnt está preasertado mientras la memoria está libre.
    //
    // GNT_DELAY = N > 0:
    //   se observan N ciclos con req=1, gnt=0 antes del grant.
    parameter int unsigned GNT_DELAY = 0,

    // Latencia entre aceptación de la petición y respuesta.
    //
    // RESP_DELAY = 1:
    //   rvalid aparece en el primer ciclo posterior al grant.
    //
    // Debe ser >= 1.
    parameter int unsigned RESP_DELAY = 1,

    // Inyección opcional de access fault.
    parameter bit FAULT_ENABLE = 1'b0,

    // Una dirección produce error cuando:
    //
    // (addr & FAULT_MASK) == (FAULT_ADDR & FAULT_MASK)
    //
    // Con FAULT_MASK = 64'hFFFF_FFFF_FFFF_FFFF se selecciona
    // exactamente una dirección.
    parameter logic [63:0] FAULT_ADDR =
        64'h0000_0000_0000_0000,

    parameter logic [63:0] FAULT_MASK =
        64'hFFFF_FFFF_FFFF_FFFF
) (
    input  logic        clk,
    input  logic        rst,

    // ---------------------------------------------------------
    // Request
    // ---------------------------------------------------------
    input  logic        req_i,
    output logic        gnt_o,

    input  logic [63:0] addr_i,
    input  logic        we_i,
    input  logic [63:0] wdata_i,
    input  logic [7:0]  wstrb_i,
    input  logic [1:0]  size_i,

    // ---------------------------------------------------------
    // Response
    // ---------------------------------------------------------
    output logic        rvalid_o,
    output logic [63:0] rdata_o,
    output logic        error_o
);

    // =========================================================
    // Memoria
    //
    // Cada entrada representa una línea de 64 bits / 8 bytes.
    //
    // Se deja visible jerárquicamente para que los testbenches
    // puedan realizar, por ejemplo:
    //
    //   u_dmem.mem[0] = 64'h0123_4567_89ab_cdef;
    //
    // No se borra durante reset deliberadamente.
    // =========================================================

        logic [63:0] mem [0:MEM_WORDS-1];

    // =========================================================
    // Parámetros derivados
    // =========================================================

        localparam int unsigned MEM_INDEX_W =
            (MEM_WORDS > 1) ? $clog2(MEM_WORDS) : 1; 

    // =========================================================
    // Estado
    // =========================================================

        typedef enum logic {
            ST_REQUEST,
            ST_RESPONSE
        } state_t;

        state_t state_q;

        // Contadores de espera.
        int unsigned gnt_wait_q;
        int unsigned resp_wait_q;

        // Respuesta capturada.
        logic [63:0] resp_rdata_q;
        logic        resp_error_q;

    // =========================================================
    // Monitor de estabilidad de request
    //
    // Si el core está esperando grant, los atributos de la
    // petición deben permanecer estables.
    // =========================================================

        logic        hold_valid_q;
        logic [63:0] hold_addr_q;
        logic        hold_we_q;
        logic [63:0] hold_wdata_q;
        logic [7:0]  hold_wstrb_q;
        logic [1:0]  hold_size_q;

    // =========================================================
    // Decodificación de dirección
    // =========================================================

        logic [63:0]                  word_index_full;
        logic [MEM_INDEX_W-1:0]      word_index;
        logic                         addr_in_range;
        logic                         injected_fault;
        logic                         request_fault;

        assign word_index_full = addr_i >> 3;

        assign word_index =
            addr_i[MEM_INDEX_W + 2 : 3];

        assign addr_in_range =
            (word_index_full < 64'(MEM_WORDS));

        assign injected_fault =
            FAULT_ENABLE &&
            ((addr_i & FAULT_MASK) ==
            (FAULT_ADDR & FAULT_MASK));

        assign request_fault =
            !addr_in_range ||
            injected_fault;

    // =========================================================
    // Salidas combinacionales del protocolo
    // =========================================================

        always_comb begin
            gnt_o    = 1'b0;
            rvalid_o = 1'b0;
            rdata_o  = 64'd0;
            error_o  = 1'b0;

            if (!rst) begin
                case (state_q)

                    // ---------------------------------------------
                    // Fase request
                    // ---------------------------------------------
                    ST_REQUEST: begin

                        // Grant inmediato/preasertado.
                        if (GNT_DELAY == 0) begin
                            gnt_o = 1'b1;
                        end

                        // Grant retrasado.
                        else if (
                            req_i &&
                            (gnt_wait_q == GNT_DELAY)
                        ) begin
                            gnt_o = 1'b1;
                        end
                    end

                    // ---------------------------------------------
                    // Fase response
                    // ---------------------------------------------
                    ST_RESPONSE: begin
                        if (resp_wait_q == 0) begin
                            rvalid_o = 1'b1;
                            rdata_o  = resp_rdata_q;
                            error_o  = resp_error_q;
                        end
                    end

                    default: begin
                        gnt_o    = 1'b0;
                        rvalid_o = 1'b0;
                        rdata_o  = 64'd0;
                        error_o  = 1'b0;
                    end

                endcase
            end
        end

    // =========================================================
    // Máquina secuencial
    // =========================================================

        integer b;

        always_ff @(posedge clk) begin
            if (rst) begin
                state_q       <= ST_REQUEST;

                gnt_wait_q    <= 0;
                resp_wait_q   <= 0;

                resp_rdata_q  <= 64'd0;
                resp_error_q  <= 1'b0;

                hold_valid_q  <= 1'b0;
                hold_addr_q   <= 64'd0;
                hold_we_q     <= 1'b0;
                hold_wdata_q  <= 64'd0;
                hold_wstrb_q  <= 8'd0;
                hold_size_q   <= 2'd0;
            end
            else begin

                case (state_q)

                    // =============================================
                    // REQUEST
                    // =============================================
                    ST_REQUEST: begin

                        // -----------------------------------------
                        // El request no puede desaparecer antes
                        // del grant una vez que comenzó a esperar.
                        // -----------------------------------------
                        if (
                            hold_valid_q &&
                            !req_i
                        ) begin
                            $fatal(
                                1,
                                "DMEM protocol error: req_i cayó antes de gnt_o"
                            );
                        end

                        // -----------------------------------------
                        // Request esperando grant.
                        // -----------------------------------------
                        if (req_i && !gnt_o) begin

                            // Primera observación de la petición.
                            if (!hold_valid_q) begin
                                hold_valid_q <= 1'b1;

                                hold_addr_q  <= addr_i;
                                hold_we_q    <= we_i;
                                hold_wdata_q <= wdata_i;
                                hold_wstrb_q <= wstrb_i;
                                hold_size_q  <= size_i;
                            end

                            // En ciclos posteriores debe permanecer
                            // exactamente estable.
                            else begin
                                if (
                                    (addr_i  !== hold_addr_q)  ||
                                    (we_i    !== hold_we_q)    ||
                                    (wdata_i !== hold_wdata_q) ||
                                    (wstrb_i !== hold_wstrb_q) ||
                                    (size_i  !== hold_size_q)
                                ) begin
                                    $fatal(
                                        1,
                                        "DMEM protocol error: atributos cambiaron antes del grant"
                                    );
                                end
                            end

                            gnt_wait_q <= gnt_wait_q + 1;
                        end

                        // No hay petición pendiente.
                        else if (!req_i) begin
                            gnt_wait_q <= 0;
                        end

                        // -----------------------------------------
                        // Aceptación de la petición.
                        //
                        // ÚNICO punto donde una transacción comienza:
                        //
                        //   req_i && gnt_o
                        // -----------------------------------------
                        if (req_i && gnt_o) begin

                            // Si hubo espera previa, comprobar una
                            // última vez estabilidad hasta el grant.
                            if (hold_valid_q) begin
                                if (
                                    (addr_i  !== hold_addr_q)  ||
                                    (we_i    !== hold_we_q)    ||
                                    (wdata_i !== hold_wdata_q) ||
                                    (wstrb_i !== hold_wstrb_q) ||
                                    (size_i  !== hold_size_q)
                                ) begin
                                    $fatal(
                                        1,
                                        "DMEM protocol error: request cambió en el ciclo de grant"
                                    );
                                end
                            end

                            // -------------------------------------
                            // Preparar respuesta.
                            // -------------------------------------
                            resp_error_q <= request_fault;

                            // -------------------------------------
                            // LOAD válido
                            //
                            // Lectura síncrona:
                            // el dato se captura en el flanco donde
                            // la petición es aceptada.
                            // -------------------------------------
                            if (
                                !request_fault &&
                                !we_i
                            ) begin
                                resp_rdata_q <= mem[word_index];
                            end
                            else begin
                                resp_rdata_q <= 64'd0;
                            end

                            // -------------------------------------
                            // STORE válido
                            //
                            // El efecto físico ocurre UNA SOLA VEZ,
                            // exactamente en la aceptación.
                            //
                            // Un store que producirá error NO modifica
                            // la memoria.
                            // -------------------------------------
                            if (
                                !request_fault &&
                                we_i
                            ) begin
                                for (b = 0; b < 8; b = b + 1) begin
                                    if (wstrb_i[b]) begin
                                        mem[word_index][b*8 +: 8]
                                            <= wdata_i[b*8 +: 8];
                                    end
                                end
                            end

                            // RESP_DELAY=1 genera rvalid durante el
                            // primer ciclo posterior a este flanco.
                            if (RESP_DELAY > 0) begin
                                resp_wait_q <= RESP_DELAY - 1;
                            end
                            else begin
                                resp_wait_q <= 0;
                            end

                            state_q      <= ST_RESPONSE;
                            gnt_wait_q   <= 0;
                            hold_valid_q <= 1'b0;
                        end
                    end

                    // =============================================
                    // RESPONSE
                    // =============================================
                    ST_RESPONSE: begin

                        if (resp_wait_q != 0) begin
                            resp_wait_q <= resp_wait_q - 1;
                        end
                        else begin
                            // rvalid_o está activo durante este ciclo.
                            // En este flanco la respuesta se considera
                            // consumida y la memoria vuelve a aceptar
                            // una nueva petición.
                            state_q      <= ST_REQUEST;

                            resp_rdata_q <= 64'd0;
                            resp_error_q <= 1'b0;

                            gnt_wait_q   <= 0;
                            hold_valid_q <= 1'b0;
                        end
                    end

                    default: begin
                        state_q       <= ST_REQUEST;

                        gnt_wait_q    <= 0;
                        resp_wait_q   <= 0;

                        resp_rdata_q  <= 64'd0;
                        resp_error_q  <= 1'b0;

                        hold_valid_q  <= 1'b0;
                    end

                endcase
            end
        end

    // =========================================================
    // Validación de parámetros
    // =========================================================

        initial begin
            if (MEM_WORDS == 0) begin
                $fatal(
                    1,
                    "dmem_sync_model: MEM_WORDS debe ser mayor que cero"
                );
            end

            if (RESP_DELAY == 0) begin
                $fatal(
                    1,
                    "dmem_sync_model: RESP_DELAY debe ser >= 1"
                );
            end
        end

endmodule
