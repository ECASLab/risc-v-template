`timescale 1ns/1ps

// ============================================================
// imem_handshake_ctrl
//
// Controlador de una única transacción outstanding para IMEM.
//
// Interfaz hacia el frontend:
//
//   start_i && ready_o
//       acepta una nueva dirección de fetch.
//
//   cancel_i
//       marca la transacción/respuesta actual como obsoleta.
//       Una petición que ya comenzó NO retira imem_req_o antes
//       del grant. Se drena correctamente y su respuesta se
//       descarta.
//
//   resp_valid_o && resp_ready_i
//       consume una instrucción retornada.
//
// Interfaz externa:
//
//   REQUEST:
//       imem_req_o
//       imem_addr_o
//       imem_gnt_i
//
//   RESPONSE:
//       imem_rvalid_i
//       imem_rdata_i
//
// Restricciones de esta primera versión:
//
//   - máximo una transacción outstanding
//   - respuesta mínimo un ciclo después del grant
//   - no existe respuesta combinacional grant+rvalid
//
// No modifica PC ni pipeline. Esa integración se realizará
// posteriormente en core_top.
// ============================================================

module imem_handshake_ctrl (
    input  logic        clk,
    input  logic        rst,

    // ---------------------------------------------------------
    // Solicitud desde el frontend
    // ---------------------------------------------------------
    input  logic        start_i,
    input  logic [63:0] addr_i,

    output logic        ready_o,
    output logic        busy_o,

    // Invalida la transacción/respuesta actual.
    input  logic        cancel_i,

    // ---------------------------------------------------------
    // Respuesta hacia el frontend
    // ---------------------------------------------------------
    output logic        resp_valid_o,
    input  logic        resp_ready_i,

    output logic [63:0] resp_addr_o,
    output logic [31:0] resp_data_o,

    // ---------------------------------------------------------
    // Puerto externo IMEM
    // ---------------------------------------------------------
    output logic        imem_req_o,
    output logic [63:0] imem_addr_o,

    input  logic        imem_gnt_i,

    input  logic        imem_rvalid_i,
    input  logic [31:0] imem_rdata_i
);

    // =========================================================
    // Estados
    // =========================================================

        typedef enum logic [1:0] {
            ST_IDLE,
            ST_WAIT_GNT,
            ST_WAIT_RESP,
            ST_HOLD_RESP
        } state_t;

        state_t state_q;

    // =========================================================
    // Estado capturado
    // =========================================================

        logic [63:0] req_addr_q;

        logic        drop_q;

        logic [63:0] resp_addr_q;
        logic [31:0] resp_data_q;

    // =========================================================
    // Salidas
    // =========================================================

        always_comb begin

            ready_o = 1'b0;
            busy_o  = 1'b1;

            imem_req_o  = 1'b0;
            imem_addr_o = req_addr_q;

            resp_valid_o = 1'b0;
            resp_addr_o  = resp_addr_q;
            resp_data_o  = resp_data_q;

            case (state_q)

                // =====================================================
                // IDLE
                //
                // Podemos presentar inmediatamente la nueva petición
                // hacia IMEM. Si gnt ya está preasertado, la aceptación
                // externa ocurre en el mismo flanco en que el frontend
                // entrega start_i.
                // =====================================================

                ST_IDLE: begin

                    ready_o = 1'b1;
                    busy_o  = 1'b0;

                    if (start_i && !cancel_i) begin
                        imem_req_o  = 1'b1;
                        imem_addr_o = addr_i;
                    end
                end

                // =====================================================
                // WAIT_GNT
                //
                // La dirección ya fue aceptada desde el frontend y debe
                // permanecer estable hasta que IMEM otorgue grant.
                // =====================================================

                ST_WAIT_GNT: begin

                    imem_req_o  = 1'b1;
                    imem_addr_o = req_addr_q;
                end

                // =====================================================
                // WAIT_RESP
                //
                // Si llega una respuesta válida y el frontend puede
                // consumirla inmediatamente, la publicamos directamente
                // sin obligarla a pasar por HOLD_RESP.
                //
                // En ese mismo ciclo el controlador puede aceptar la
                // siguiente dirección de fetch.
                // =====================================================

                ST_WAIT_RESP: begin

                    if (
                        imem_rvalid_i &&
                        !drop_q &&
                        !cancel_i
                    ) begin

                        resp_valid_o = 1'b1;
                        resp_addr_o  = req_addr_q;
                        resp_data_o  = imem_rdata_i;

                        if (resp_ready_i) begin

                            ready_o = 1'b1;
                            busy_o  = 1'b0;

                            if (start_i) begin
                                imem_req_o  = 1'b1;
                                imem_addr_o = addr_i;
                            end
                        end
                    end
                end

                // =====================================================
                // HOLD_RESP
                //
                // La respuesta tuvo que almacenarse porque el frontend
                // estaba detenido.
                //
                // Cuando finalmente se consume, también permitimos
                // aceptar la siguiente petición en el mismo ciclo.
                // =====================================================

                ST_HOLD_RESP: begin

                    resp_valid_o = !cancel_i;
                    resp_addr_o  = resp_addr_q;
                    resp_data_o  = resp_data_q;

                    if (
                        !cancel_i &&
                        resp_ready_i
                    ) begin

                        ready_o = 1'b1;
                        busy_o  = 1'b0;

                        if (start_i) begin
                            imem_req_o  = 1'b1;
                            imem_addr_o = addr_i;
                        end
                    end
                end

                default: begin

                    ready_o      = 1'b0;
                    busy_o       = 1'b1;

                    imem_req_o   = 1'b0;
                    imem_addr_o  = req_addr_q;

                    resp_valid_o = 1'b0;
                    resp_addr_o  = resp_addr_q;
                    resp_data_o  = resp_data_q;
                end

            endcase
        end

    // =========================================================
    // Máquina secuencial
    // =========================================================

        always_ff @(posedge clk) begin
            if (rst) begin

                state_q <= ST_IDLE;

                req_addr_q <= 64'd0;

                drop_q <= 1'b0;

                resp_addr_q <= 64'd0;
                resp_data_q <= 32'd0;
            end
            else begin

                case (state_q)

                    // =========================================================
                    // IDLE
                    // =========================================================

                        ST_IDLE: begin

                            drop_q <= 1'b0;

                            if (
                                start_i &&
                                !cancel_i
                            ) begin

                                req_addr_q <= addr_i;

                                // Si la memoria concede inmediatamente, la
                                // transacción ya quedó aceptada externamente.
                                if (imem_gnt_i) begin
                                    state_q <= ST_WAIT_RESP;
                                end
                                else begin
                                    state_q <= ST_WAIT_GNT;
                                end
                            end
                        end

                    // =========================================================
                    // WAIT_GNT
                    //
                    // Una petición iniciada no puede retirarse antes del grant.
                    // cancel_i únicamente marca la respuesta para descarte.
                    // =========================================================

                        ST_WAIT_GNT: begin

                            if (cancel_i) begin
                                drop_q <= 1'b1;
                            end

                            if (imem_gnt_i) begin
                                state_q <= ST_WAIT_RESP;
                            end
                        end

                    // =========================================================
                    // WAIT_RESP
                    // =========================================================

                        ST_WAIT_RESP: begin

                            if (cancel_i) begin
                                drop_q <= 1'b1;
                            end

                            if (imem_rvalid_i) begin

                                // -------------------------------------------------
                                // Fetch obsoleto por redirect.
                                // -------------------------------------------------

                                if (
                                    drop_q ||
                                    cancel_i
                                ) begin

                                    drop_q <= 1'b0;
                                    state_q <= ST_IDLE;
                                end

                                // -------------------------------------------------
                                // El frontend puede consumir directamente la
                                // respuesta en este ciclo.
                                // -------------------------------------------------

                                else if (resp_ready_i) begin

                                    resp_addr_q <= 64'd0;
                                    resp_data_q <= 32'd0;

                                    // Podemos comenzar inmediatamente el fetch
                                    // siguiente.
                                    if (start_i) begin

                                        req_addr_q <= addr_i;

                                        if (imem_gnt_i) begin
                                            // La nueva petición también quedó
                                            // aceptada en este mismo flanco.
                                            state_q <= ST_WAIT_RESP;
                                        end
                                        else begin
                                            // Dirección capturada; mantener request
                                            // hasta obtener grant.
                                            state_q <= ST_WAIT_GNT;
                                        end
                                    end
                                    else begin
                                        state_q <= ST_IDLE;
                                    end
                                end

                                // -------------------------------------------------
                                // El frontend no puede consumir la respuesta.
                                // Debemos almacenarla.
                                // -------------------------------------------------

                                else begin

                                    resp_addr_q <= req_addr_q;
                                    resp_data_q <= imem_rdata_i;

                                    state_q <= ST_HOLD_RESP;
                                end
                            end
                        end

                    // =========================================================
                    // HOLD_RESP
                    // =========================================================

                        ST_HOLD_RESP: begin

                            if (cancel_i) begin

                                resp_addr_q <= 64'd0;
                                resp_data_q <= 32'd0;

                                state_q <= ST_IDLE;
                            end
                            else if (resp_ready_i) begin

                                resp_addr_q <= 64'd0;
                                resp_data_q <= 32'd0;

                                // La respuesta almacenada se consume y podemos
                                // aceptar simultáneamente el siguiente fetch.
                                if (start_i) begin

                                    req_addr_q <= addr_i;

                                    if (imem_gnt_i) begin
                                        state_q <= ST_WAIT_RESP;
                                    end
                                    else begin
                                        state_q <= ST_WAIT_GNT;
                                    end
                                end
                                else begin
                                    state_q <= ST_IDLE;
                                end
                            end
                        end

                        default: begin

                            state_q <= ST_IDLE;

                            req_addr_q <= 64'd0;

                            drop_q <= 1'b0;

                            resp_addr_q <= 64'd0;
                            resp_data_q <= 32'd0;
                        end

                endcase
        end
    end

endmodule
