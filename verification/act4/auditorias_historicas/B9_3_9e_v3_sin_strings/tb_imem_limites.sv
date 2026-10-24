`timescale 1ns/1ps
// B.9.3.9e-v3: ensayo aislado del MODELO de IMEM, usando ID numérico.
// Elimina case(string), no soportado fiablemente por Icarus Verilog 12.
// No usa core_top. Los fallos $fatal esperados NO son traps arquitecturales.
module tb_imem_limites;
    localparam logic [63:0] BASE = 64'h0000_0000_8000_0000;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst, req;
    logic gnt, rvalid;
    logic [63:0] addr;
    logic [31:0] rdata;
    integer caso_id;
    logic [63:0] objetivo;
    logic [31:0] esperado;
    bit debe_ser_valido;

    imem_sync_model #(
        .MEM_WORDS(4),
        .BASE_ADDR(BASE),
        .GNT_DELAY(0),
        .RESP_DELAY(1)
    ) u_imem (
        .clk(clk), .rst(rst),
        .req_i(req), .gnt_o(gnt), .addr_i(addr),
        .rvalid_o(rvalid), .rdata_o(rdata)
    );

    initial begin
        rst = 1'b1;
        req = 1'b0;
        addr = BASE;
        if (!$value$plusargs("ID=%d", caso_id))
            $fatal(1, "Falta +ID=<entero>");

        debe_ser_valido = 1'b0;
        objetivo = 64'hFFFF_FFFF_FFFF_FFFC;
        esperado = 32'h0000_0013;
        case (caso_id)
            1: begin
                debe_ser_valido = 1'b1;
                objetivo = BASE;
                esperado = 32'h0000_0013;
            end
            2: begin
                debe_ser_valido = 1'b1;
                objetivo = BASE + 64'd12;
                esperado = 32'h0040_006f;
            end
            3: objetivo = BASE + 64'd16;
            4: objetivo = BASE - 64'd4;
            5: objetivo = BASE + 64'h0000_0001_0000_0000;
            6: objetivo = BASE + 64'h0080_0000_0000_0000;
            7: objetivo = BASE + 64'h0100_0000_0000_0000;
            8: objetivo = BASE + 64'd2;
            default: $fatal(1, "ID desconocido: %0d", caso_id);
        endcase

        u_imem.mem[0] = 32'h0000_0013;
        u_imem.mem[1] = 32'h0010_0093;
        u_imem.mem[2] = 32'h0020_0113;
        u_imem.mem[3] = 32'h0040_006f;

        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        req = 1'b1;
        addr = objetivo;
        #1;
        if (gnt !== 1'b1)
            $fatal(1, "Sin grant: ID=%0d", caso_id);
        @(posedge clk);
        #1;
        if (debe_ser_valido) begin
            if (rvalid !== 1'b1 || rdata !== esperado)
                $fatal(1, "IMEM valida incorrecta ID=%0d rvalid=%b rdata=%h esperado=%h", caso_id, rvalid, rdata, esperado);
            $display("PASS_VALIDO: ID=%0d addr=0x%016h rdata=0x%08h", caso_id, objetivo, rdata);
            $finish;
        end
        // Para casos invalidos, el modelo DEBE hacer $fatal antes de llegar aqui.
        $display("FAIL: modelo acepto direccion invalida ID=%0d addr=0x%016h", caso_id, objetivo);
        $finish;
    end
    initial begin
        #1000;
        $fatal(1, "TIMEOUT del testbench IMEM");
    end
endmodule
