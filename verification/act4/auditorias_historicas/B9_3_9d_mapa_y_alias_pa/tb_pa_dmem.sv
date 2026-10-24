`timescale 1ns/1ps
// B.9.3.9d: prueba dirigida del modelo DMEM, NO del core_top ni de la FPGA.
// Verifica que no haya alias de direcciones que difieren en bits altos.
module tb_pa_dmem;
    localparam logic [63:0] BASE = 64'h0000_0000_8000_0000;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst;
    logic req;
    logic gnt;
    logic [63:0] addr;
    logic we;
    logic [63:0] wdata;
    logic [7:0] wstrb;
    logic [1:0] size;
    logic rvalid;
    logic [63:0] rdata;
    logic error;
    integer cases_done;

    dmem_sync_model #(
        .MEM_WORDS(4),
        .BASE_ADDR(BASE),
        .GNT_DELAY(0),
        .RESP_DELAY(1)
    ) u_dmem (
        .clk(clk), .rst(rst),
        .req_i(req), .gnt_o(gnt),
        .addr_i(addr), .we_i(we),
        .wdata_i(wdata), .wstrb_i(wstrb), .size_i(size),
        .rvalid_o(rvalid), .rdata_o(rdata), .error_o(error)
    );

    task automatic transaction(
        input logic [63:0] a,
        input bit write_req,
        input bit expect_error,
        input logic [63:0] expect_data,
        input string description
    );
        begin
            @(negedge clk);
            addr = a;
            req = 1'b1;
            we = write_req;
            wdata = 64'hFFFF_FFFF_FFFF_FFFF;
            wstrb = 8'hFF;
            size = 2'd3;
            #1;
            if (gnt !== 1'b1)
                $fatal(1, "No grant: %s", description);
            @(posedge clk);
            #1;
            if (rvalid !== 1'b1 || error !== expect_error)
                $fatal(1, "Respuesta inesperada %s: rvalid=%b error=%b", description, rvalid, error);
            if (!write_req && !expect_error && rdata !== expect_data)
                $fatal(1, "Dato incorrecto %s: dato=%h esperado=%h", description, rdata, expect_data);
            cases_done = cases_done + 1;
            $display("PASS: %s addr=%016h error=%0d", description, a, error);
            @(negedge clk);
            req = 1'b0;
            we = 1'b0;
            @(posedge clk);
            #1;
            if (rvalid !== 1'b0)
                $fatal(1, "No termino respuesta: %s", description);
        end
    endtask

    initial begin
        rst = 1'b1;
        req = 1'b0;
        addr = 64'd0;
        we = 1'b0;
        wdata = 64'd0;
        wstrb = 8'd0;
        size = 2'd3;
        cases_done = 0;
        u_dmem.mem[0] = 64'h0123_4567_89AB_CDEF;
        u_dmem.mem[1] = 64'hF0E1_D2C3_B4A5_9687;
        u_dmem.mem[2] = 64'h7777_7777_7777_7777;
        u_dmem.mem[3] = 64'h8888_8888_8888_8888;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        transaction(64'h0000_0000_8000_0000, 0, 0, 64'h0123_4567_89AB_CDEF, "RAM base valida");
        transaction(64'h0000_0000_8000_0008, 0, 0, 64'hF0E1_D2C3_B4A5_9687, "RAM base+8 valida");
        transaction(64'h0000_0000_8000_0018, 0, 0, 64'h8888_8888_8888_8888, "RAM ultima palabra valida");
        transaction(64'h0000_0001_8000_0000, 0, 1, 64'd0, "Sin alias al sumar 2^32");
        transaction(64'h0080_0000_8000_0000, 0, 1, 64'd0, "Sin alias al sumar 2^55");
        transaction(64'h0100_0000_8000_0000, 0, 1, 64'd0, "Sin alias al sumar 2^56");
        transaction(64'h0000_0000_7FFF_FFF8, 0, 1, 64'd0, "Rechazo por debajo de RAM");
        transaction(64'h0000_0000_8000_0020, 0, 1, 64'd0, "Rechazo en fin exclusivo de RAM");
        transaction(64'h0000_0001_8000_0000, 1, 1, 64'd0, "Store fuera de RAM no permitido");
        if (u_dmem.mem[0] !== 64'h0123_4567_89AB_CDEF)
            $fatal(1, "Store fuera de rango corrompio RAM base");
        $display("PASS: direccion elevada no modifica RAM base");
        $display("PASS: B.9.3.9d DMEM: %0d transacciones dirigidas verificadas", cases_done);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: prueba DMEM no termino");
    end
endmodule
