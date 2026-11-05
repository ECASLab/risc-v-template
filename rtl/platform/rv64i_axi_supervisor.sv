`timescale 1ns/1ps
// TFG P2.7.1 - AXI4-Lite slave, 32-bit, mismo reloj que la plataforma.
// AW y W se aceptan independientemente. Una lectura y una escritura AXI
// pueden tener respuestas pendientes al mismo tiempo.
// Solo una operacion nativa boot a la vez; se completa ANTES del BRESP.
module rv64i_axi_supervisor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [11:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [11:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,
    output logic        run_o,
    input  logic [1:0]  result_code_i,
    output logic        boot_req_o,
    output logic        boot_we_o,
    output logic [63:0] boot_addr_o,
    output logic [63:0] boot_wdata_o,
    output logic [7:0]  boot_wstrb_o,
    input  logic        boot_gnt_i,
    input  logic        boot_rvalid_i,
    input  logic [63:0] boot_rdata_i,
    input  logic        boot_error_i
);
    // Registro por desplazamiento de byte en el espacio AXI4-Lite (4 KiB).
    // 00 CONTROL bit0 run, 04 STATUS bit0 run, bits [9:8] result_code.
    // 08/0C BOOT_ADDR_LO/HI, 10/14 BOOT_WDATA_LO/HI,
    // 18 BOOT_WSTRB[7:0], 1C BOOT_CMD (1=write, 2=read).
    // 20/24 BOOT_RDATA_LO/HI, 28 BOOT_STATUS (bit0 last_done, bit1 error).
    // BOOT_CMD devuelve BRESP solo cuando la transaccion nativa termino.
    localparam logic [1:0] OKAY=2'b00, SLVERR=2'b10;
    localparam logic [1:0] IDLE=2'd0, WAIT_GNT=2'd1, WAIT_RESP=2'd2;
    logic [1:0] boot_state_q;
    logic [63:0] addr_q, data_q, rdata_q;
    logic [7:0]  strb_q;
    logic last_done_q, last_error_q;
    logic cmd_we_q;
    logic [63:0] cmd_addr_q, cmd_data_q;
    logic [7:0] cmd_strb_q;
    logic aw_hold_q, w_hold_q;
    logic [11:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0] wstrb_q;

    function automatic logic [31:0] masked_write(
        input logic [31:0] old_data,
        input logic [31:0] new_data,
        input logic [3:0] mask
    );
        logic [31:0] tmp;
        tmp = old_data;
        for (int k=0; k<4; k++)
            if (mask[k]) tmp[k*8 +: 8] = new_data[k*8 +: 8];
        return tmp;
    endfunction

    assign s_axi_awready = !aw_hold_q && !s_axi_bvalid && (boot_state_q == IDLE);
    assign s_axi_wready  = !w_hold_q && !s_axi_bvalid && (boot_state_q == IDLE);
    assign s_axi_arready = !s_axi_rvalid;
    assign boot_req_o = (boot_state_q == WAIT_GNT);
    assign boot_we_o = cmd_we_q;
    assign boot_addr_o = cmd_addr_q;
    assign boot_wdata_o = cmd_data_q;
    assign boot_wstrb_o = cmd_strb_q;
    // AWPROT/ARPROT no modifican privilegios en este supervisor minimo.
    wire unused_prot = ^{s_axi_awprot, s_axi_arprot};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            aw_hold_q <= 0; w_hold_q <= 0; awaddr_q <= '0;
            wdata_q <= '0; wstrb_q <= '0;
            s_axi_bvalid <= 0; s_axi_bresp <= OKAY;
            s_axi_rvalid <= 0; s_axi_rresp <= OKAY; s_axi_rdata <= 0;
            boot_state_q <= IDLE;
            run_o <= 0;
            addr_q <= 0; data_q <= 0; rdata_q <= 0;
            strb_q <= 8'hff;
            cmd_we_q <= 0; cmd_addr_q <= 0; cmd_data_q <= 0; cmd_strb_q <= 0;
            last_done_q <= 0; last_error_q <= 0;
        end else begin
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_awvalid && s_axi_awready) begin
                aw_hold_q <= 1;
                awaddr_q <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_hold_q <= 1;
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
            end

            if (boot_state_q == WAIT_GNT && boot_gnt_i)
                boot_state_q <= WAIT_RESP;
            if (boot_state_q == WAIT_RESP && boot_rvalid_i) begin
                boot_state_q <= IDLE;
                last_done_q <= 1;
                last_error_q <= boot_error_i;
                if (!cmd_we_q && !boot_error_i)
                    rdata_q <= boot_rdata_i;
                s_axi_bvalid <= 1;
                s_axi_bresp <= boot_error_i ? SLVERR : OKAY;
            end

            if (aw_hold_q && w_hold_q && !s_axi_bvalid && boot_state_q == IDLE) begin
                aw_hold_q <= 0;
                w_hold_q <= 0;
                // Todo registro requiere direccion alineada a palabra de 32 bits.
                if (awaddr_q[1:0] != 2'b00) begin
                    s_axi_bresp <= SLVERR;
                    s_axi_bvalid <= 1;
                end else begin
                    case (awaddr_q)
                        12'h000: begin
                            if (wstrb_q[0] && (wdata_q & 32'hffff_fffe) == 0) begin
                                run_o <= wdata_q[0];
                                s_axi_bresp <= OKAY;
                            end else s_axi_bresp <= SLVERR;
                            s_axi_bvalid <= 1;
                        end
                        12'h008: begin
                            addr_q[31:0] <= masked_write(addr_q[31:0],wdata_q,wstrb_q);
                            s_axi_bresp <= OKAY; s_axi_bvalid <= 1;
                        end
                        12'h00c: begin
                            addr_q[63:32] <= masked_write(addr_q[63:32],wdata_q,wstrb_q);
                            s_axi_bresp <= OKAY; s_axi_bvalid <= 1;
                        end
                        12'h010: begin
                            data_q[31:0] <= masked_write(data_q[31:0],wdata_q,wstrb_q);
                            s_axi_bresp <= OKAY; s_axi_bvalid <= 1;
                        end
                        12'h014: begin
                            data_q[63:32] <= masked_write(data_q[63:32],wdata_q,wstrb_q);
                            s_axi_bresp <= OKAY; s_axi_bvalid <= 1;
                        end
                        12'h018: begin
                            if (wstrb_q[0]) strb_q <= wdata_q[7:0];
                            s_axi_bresp <= OKAY; s_axi_bvalid <= 1;
                        end
                        12'h01c: begin
                            if (!run_o && wstrb_q[0] &&
                                (wdata_q == 32'd1 || wdata_q == 32'd2)) begin
                                cmd_we_q <= (wdata_q == 32'd1);
                                cmd_addr_q <= addr_q;
                                cmd_data_q <= data_q;
                                cmd_strb_q <= strb_q;
                                last_done_q <= 0;
                                last_error_q <= 0;
                                boot_state_q <= WAIT_GNT;
                                // BRESP despues del handshake y la respuesta boot.
                            end else begin
                                s_axi_bresp <= SLVERR;
                                s_axi_bvalid <= 1;
                            end
                        end
                        default: begin
                            s_axi_bresp <= SLVERR; s_axi_bvalid <= 1;
                        end
                    endcase
                end
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= OKAY;
                s_axi_rdata <= 0;
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rresp <= SLVERR;
                end else begin
                    case (s_axi_araddr)
                        12'h000: s_axi_rdata <= {31'd0,run_o};
                        12'h004: s_axi_rdata <= {22'd0,result_code_i,7'd0,run_o};
                        12'h008: s_axi_rdata <= addr_q[31:0];
                        12'h00c: s_axi_rdata <= addr_q[63:32];
                        12'h010: s_axi_rdata <= data_q[31:0];
                        12'h014: s_axi_rdata <= data_q[63:32];
                        12'h018: s_axi_rdata <= {24'd0,strb_q};
                        12'h01c: s_axi_rdata <= 0;
                        12'h020: s_axi_rdata <= rdata_q[31:0];
                        12'h024: s_axi_rdata <= rdata_q[63:32];
                        12'h028: s_axi_rdata <= {30'd0,last_error_q,last_done_q};
                        default: s_axi_rresp <= SLVERR;
                    endcase
                end
            end
        end
    end
endmodule
