`timescale 1ns/1ps

// ============================================================
// imem_sync_model
//
// Modelo de memoria de instrucciones síncrona para verificación.
//
// Protocolo:
//
// REQUEST:
//   req_i
//   addr_i
//   gnt_o
//
// La petición se acepta únicamente cuando:
//
//   req_i && gnt_o
//
// Mientras req_i=1 y gnt_o=0:
//   - req_i no puede caer
//   - addr_i debe permanecer estable
//
// RESPONSE:
//
//   rvalid_o
//   rdata_o
//
// La respuesta aparece como mínimo un ciclo después del grant.
//
// Restricciones:
//   - solo lectura
//   - máximo una transacción outstanding
//   - direcciones alineadas a 4 bytes
//
// La memoria interna permanece visible jerárquicamente:
//
//   u_imem.mem[index] = 32'hXXXXXXXX;
//
// para permitir cargar programas desde los testbenches.
// ============================================================

module imem_sync_model #(
    parameter int unsigned MEM_WORDS = 1024,

    // ---------------------------------------------------------
    // Número de ciclos completos durante los cuales req puede
    // permanecer esperando antes del grant.
    //
    // GNT_DELAY = 0:
    //   grant preasertado cuando la memoria está libre.
    //
    // GNT_DELAY = N:
    //   existen N ciclos req=1/gnt=0 antes de aceptar.
    // ---------------------------------------------------------

    parameter int unsigned GNT_DELAY = 0,

    // ---------------------------------------------------------
    // Latencia desde aceptación hasta respuesta.
    //
    // RESP_DELAY = 1:
    //   rvalid aparece en el primer ciclo posterior al grant.
    //
    // Debe ser >= 1.
    // ---------------------------------------------------------

    parameter int unsigned RESP_DELAY = 1
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        req_i,
    output logic        gnt_o,

    input  logic [63:0] addr_i,

    output logic        rvalid_o,
    output logic [31:0] rdata_o
);

    // =========================================================
    // Memoria
    // =========================================================

    logic [31:0] mem [0:MEM_WORDS-1];

    // =========================================================
    // Índice
    // =========================================================

    localparam int unsigned MEM_INDEX_W =
        (MEM_WORDS > 1) ? $clog2(MEM_WORDS) : 1;

    logic [63:0]             word_index_full;
    logic [MEM_INDEX_W-1:0] word_index;

    logic addr_in_range;
    logic addr_aligned;

    assign word_index_full = addr_i >> 2;

    assign word_index =
        addr_i[MEM_INDEX_W + 1 : 2];

    assign addr_in_range =
        (word_index_full < 64'(MEM_WORDS));

    assign addr_aligned =
        (addr_i[1:0] == 2'b00);

    // =========================================================
    // Estado
    // =========================================================

    typedef enum logic {
        ST_REQUEST,
        ST_RESPONSE
    } state_t;

    state_t state_q;

    integer unsigned gnt_wait_q;
    integer unsigned resp_wait_q;

    logic [31:0] resp_rdata_q;

    // =========================================================
    // Monitor de estabilidad durante WAIT_GNT
    // =========================================================

    logic        hold_valid_q;
    logic [63:0] hold_addr_q;

    // =========================================================
    // Salidas
    //
    // Se mantienen separadas las dependencias combinacionales de
    // request/grant y response para evitar crear una dependencia
    // artificial de proceso entre req_i y rvalid_o.
    //
    // Semántica preservada:
    //
    // GNT_DELAY = 0:
    //   grant preasertado mientras el modelo está disponible.
    //
    // GNT_DELAY > 0:
    //   grant cuando la petición ha esperado los ciclos definidos.
    //
    // RESPONSE:
    //   rvalid aparece cuando finaliza RESP_DELAY.
    // =========================================================

        // Grant normal cuando el modelo está esperando una petición.
        //
        // Además, con GNT_DELAY=0, el modelo puede aceptar la petición
        // siguiente en el mismo ciclo en que entrega la respuesta de
        // la transacción anterior.
        //
        // Esto permite:
        //
        //   response actual + next request
        //
        // sin tener más de una transacción outstanding entre flancos.
        assign gnt_o =
            !rst &&
            (
                (
                    (state_q == ST_REQUEST) &&
                    (
                        (GNT_DELAY == 0) ||
                        (
                            req_i &&
                            (gnt_wait_q == GNT_DELAY)
                        )
                    )
                )
                ||
                (
                    (state_q == ST_RESPONSE) &&
                    (resp_wait_q == 0) &&
                    (GNT_DELAY == 0)
                )
            );

        assign rvalid_o =
            !rst &&
            (state_q == ST_RESPONSE) &&
            (resp_wait_q == 0);

        assign rdata_o =
            rvalid_o
                ? resp_rdata_q
                : 32'd0;

    // =========================================================
    // Máquina secuencial
    // =========================================================

        always_ff @(posedge clk) begin

            if (rst) begin

                state_q <= ST_REQUEST;

                gnt_wait_q  <= 0;
                resp_wait_q <= 0;

                resp_rdata_q <= 32'd0;

                hold_valid_q <= 1'b0;
                hold_addr_q  <= 64'd0;
            end
            else begin

                case (state_q)

                    // =================================================
                    // REQUEST
                    // =================================================

                    ST_REQUEST: begin

                        // ---------------------------------------------
                        // Una petición que comenzó a esperar grant
                        // no puede desaparecer.
                        // ---------------------------------------------

                        if (
                            hold_valid_q &&
                            !req_i
                        ) begin
                            $fatal(
                                1,
                                "IMEM protocol error: req_i cayó antes de gnt_o"
                            );
                        end

                        // ---------------------------------------------
                        // WAIT_GNT
                        // ---------------------------------------------

                        if (req_i && !gnt_o) begin

                            if (!hold_valid_q) begin

                                hold_valid_q <= 1'b1;
                                hold_addr_q  <= addr_i;
                            end
                            else begin

                                if (addr_i !== hold_addr_q) begin
                                    $fatal(
                                        1,
                                        "IMEM protocol error: addr_i cambió antes del grant"
                                    );
                                end
                            end

                            gnt_wait_q <= gnt_wait_q + 1;
                        end
                        else if (!req_i) begin
                            gnt_wait_q <= 0;
                        end

                        // ---------------------------------------------
                        // Aceptación
                        //
                        // ÚNICO punto donde comienza un fetch:
                        //
                        //   req_i && gnt_o
                        // ---------------------------------------------

                        if (req_i && gnt_o) begin

                            if (
                                hold_valid_q &&
                                (addr_i !== hold_addr_q)
                            ) begin
                                $fatal(
                                    1,
                                    "IMEM protocol error: addr_i cambió en el ciclo de grant"
                                );
                            end

                            // -----------------------------------------
                            // El frontend RV64I actual utiliza IALIGN=32.
                            // No debe solicitar fetches desalineados.
                            // -----------------------------------------

                            if (!addr_aligned) begin
                                $fatal(
                                    1,
                                    "IMEM protocol error: fetch desalineado addr=0x%016h",
                                    addr_i
                                );
                            end

                            // -----------------------------------------
                            // Este modelo no implementa todavía
                            // instruction access faults.
                            //
                            // Un acceso fuera del rango es un error de
                            // infraestructura de verificación.
                            // -----------------------------------------

                            if (!addr_in_range) begin
                                $fatal(
                                    1,
                                    "IMEM model error: dirección fuera de rango addr=0x%016h",
                                    addr_i
                                );
                            end

                            // -----------------------------------------
                            // Lectura síncrona:
                            //
                            // el dato se captura en el flanco donde
                            // la petición es aceptada.
                            // -----------------------------------------

                            resp_rdata_q <= mem[word_index];

                            if (RESP_DELAY > 0) begin
                                resp_wait_q <= RESP_DELAY - 1;
                            end
                            else begin
                                resp_wait_q <= 0;
                            end

                            state_q <= ST_RESPONSE;

                            gnt_wait_q  <= 0;
                            hold_valid_q <= 1'b0;
                        end
                    end

                    // =================================================
                    // RESPONSE
                    // =================================================

                    ST_RESPONSE: begin

                        if (resp_wait_q != 0) begin

                            resp_wait_q <= resp_wait_q - 1;
                        end
                        else begin

                            // -----------------------------------------------------
                            // rvalid_o está activo durante este ciclo.
                            //
                            // Si además existe una nueva petición aceptada:
                            //
                            //   req_i && gnt_o
                            //
                            // la respuesta actual termina en este flanco y la
                            // siguiente transacción comienza simultáneamente.
                            //
                            // De esta forma seguimos teniendo como máximo una
                            // transacción outstanding entre flancos.
                            // -----------------------------------------------------

                            if (req_i && gnt_o) begin

                                // -------------------------------------------------
                                // El frontend RV64I utiliza IALIGN=32.
                                // -------------------------------------------------

                                if (!addr_aligned) begin
                                    $fatal(
                                        1,
                                        "IMEM protocol error: fetch desalineado addr=0x%016h",
                                        addr_i
                                    );
                                end

                                // -------------------------------------------------
                                // Todavía no existen instruction access faults.
                                // Fuera de rango es error de infraestructura.
                                // -------------------------------------------------

                                if (!addr_in_range) begin
                                    $fatal(
                                        1,
                                        "IMEM model error: dirección fuera de rango addr=0x%016h",
                                        addr_i
                                    );
                                end

                                // -------------------------------------------------
                                // Captura síncrona de la siguiente instrucción.
                                // -------------------------------------------------

                                resp_rdata_q <= mem[word_index];

                                if (RESP_DELAY > 0) begin
                                    resp_wait_q <= RESP_DELAY - 1;
                                end
                                else begin
                                    resp_wait_q <= 0;
                                end

                                // Seguimos en RESPONSE porque ahora existe una
                                // nueva transacción pendiente.
                                state_q <= ST_RESPONSE;

                                gnt_wait_q   <= 0;
                                hold_valid_q <= 1'b0;
                            end
                            else begin

                                // No hubo siguiente petición simultánea.
                                // El modelo vuelve a quedar libre.
                                state_q <= ST_REQUEST;

                                resp_rdata_q <= 32'd0;

                                gnt_wait_q   <= 0;
                                hold_valid_q <= 1'b0;
                            end
                        end
                    end

                endcase
            end
        end

    // =========================================================
    // Parámetros
    // =========================================================

        initial begin

            if (MEM_WORDS == 0) begin
                $fatal(
                    1,
                    "imem_sync_model: MEM_WORDS debe ser mayor que cero"
                );
            end

            if (RESP_DELAY == 0) begin
                $fatal(
                    1,
                    "imem_sync_model: RESP_DELAY debe ser >= 1"
                );
            end
        end

endmodule
