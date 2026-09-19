`timescale 1ns/1ps

module dmem_handshake_ctrl (
    input  logic clk,
    input  logic rst,

    // ---------------------------------------------------------
    // Solicitud procedente de la etapa MEM.
    //
    // Debe permanecer activa mientras la instrucción de memoria
    // esté retenida en MEM.
    // ---------------------------------------------------------
    input  logic access_valid_i,

    // ---------------------------------------------------------
    // Canal externo request/grant/response.
    // ---------------------------------------------------------
    input  logic gnt_i,
    input  logic rvalid_i,
    input  logic error_i,

    output logic req_o,

    // ---------------------------------------------------------
    // Control hacia el pipeline.
    // ---------------------------------------------------------
    output logic wait_stall_o,
    output logic response_done_o,
    output logic access_fault_o
);

    // =========================================================
    // Estados
    //
    // IDLE:
    //   no existe una transacción pendiente.
    //
    // WAIT_GNT:
    //   req ya fue emitido, pero todavía no fue aceptado.
    //
    // WAIT_RESP:
    //   la solicitud ya fue aceptada y se espera su respuesta.
    //
    // Solo se permite una transacción outstanding.
    // =========================================================
    typedef enum logic [1:0] {
        DMEM_IDLE,
        DMEM_WAIT_GNT,
        DMEM_WAIT_RESP
    } dmem_state_t;

    dmem_state_t state_q;

    // =========================================================
    // Request
    //
    // req_o aparece cuando existe un acceso válido en IDLE y
    // permanece activo durante WAIT_GNT.
    //
    // Una vez recibido el grant, req_o deja de estar activo
    // mientras esperamos rvalid.
    // =========================================================
    assign req_o =
        access_valid_i &&
        (
            (state_q == DMEM_IDLE) ||
            (state_q == DMEM_WAIT_GNT)
        );

    // =========================================================
    // Final de respuesta
    //
    // rvalid_i solo tiene significado una vez que la solicitud
    // fue aceptada.
    // =========================================================
    assign response_done_o =
        (state_q == DMEM_WAIT_RESP) &&
        rvalid_i;

    // =========================================================
    // Stall
    //
    // Una operación válida mantiene detenido MEM hasta recibir
    // la respuesta correspondiente.
    //
    // En el mismo ciclo en que response_done_o=1 el stall se
    // libera para permitir el avance del pipeline en el flanco
    // siguiente.
    // =========================================================
    assign wait_stall_o =
        access_valid_i &&
        !response_done_o;

    // =========================================================
    // Access fault
    //
    // error_i solo se interpreta junto con una respuesta válida.
    // =========================================================
    assign access_fault_o =
        access_valid_i &&
        response_done_o &&
        error_i;

    // =========================================================
    // FSM
    // =========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= DMEM_IDLE;
        end
        else begin
            case (state_q)

                DMEM_IDLE: begin
                    if (access_valid_i) begin
                        if (gnt_i)
                            state_q <= DMEM_WAIT_RESP;
                        else
                            state_q <= DMEM_WAIT_GNT;
                    end
                end

                DMEM_WAIT_GNT: begin
                    if (gnt_i)
                        state_q <= DMEM_WAIT_RESP;
                end

                DMEM_WAIT_RESP: begin
                    if (rvalid_i)
                        state_q <= DMEM_IDLE;
                end

                default: begin
                    state_q <= DMEM_IDLE;
                end

            endcase
        end
    end

endmodule
