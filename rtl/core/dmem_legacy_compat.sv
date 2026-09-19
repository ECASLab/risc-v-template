`timescale 1ns/1ps

// ============================================================
// dmem_legacy_compat
//
// Adaptador temporal entre la interfaz request/grant/response
// del core y los modelos de memoria combinacionales utilizados
// por los testbenches existentes.
//
// Semántica:
//
//   - gnt_o está siempre activo:
//       toda solicitud es aceptada inmediatamente.
//
//   - rvalid_o aparece exactamente un ciclo después de una
//     solicitud aceptada.
//
//   - error_o permanece en cero.
//
// Este módulo NO almacena dirección, datos ni atributos.
// El modelo legacy debe mantener dmem_rdata correspondiente
// a la dirección presentada por el core.
//
// Su propósito es facilitar la migración progresiva de los TB.
// ============================================================

module dmem_legacy_compat (
    input  logic clk,
    input  logic rst,

    // Request generado por el core.
    input  logic req_i,

    // Respuesta hacia el core.
    output logic gnt_o,
    output logic rvalid_o,
    output logic error_o
);

    logic response_pending_q;

    // ---------------------------------------------------------
    // Grant inmediato.
    //
    // Es legal mantener grant activo aunque todavía no exista
    // request. La transferencia solamente se acepta cuando
    // req_i && gnt_o son simultáneamente verdaderos.
    // ---------------------------------------------------------
    assign gnt_o = 1'b1;

    // Este adaptador nunca genera errores.
    assign error_o = 1'b0;

    // ---------------------------------------------------------
    // Respuesta un ciclo después del handshake de request.
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            response_pending_q <= 1'b0;
        end
        else begin
            response_pending_q <= req_i && gnt_o;
        end
    end

    assign rvalid_o = response_pending_q;

endmodule
