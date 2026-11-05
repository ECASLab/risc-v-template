`timescale 1ns/1ps
module tb_rv64i_axi_integration;
    localparam logic [63:0] RAM_BASE = 64'h8000_0000;
    localparam logic [63:0] RESULT_ADDR = RAM_BASE + 64'h300;
    localparam logic [63:0] OPERAND_A = 64'h1122_3344_5566_7788;
    localparam logic [63:0] OPERAND_B = 64'h22;
    localparam logic [63:0] EXPECTED = 64'h1122_3344_5566_77aa;
    localparam int unsigned MAX_IMAGE_WORDS=256;
    `include "image_words.svh"
    logic clk=0;
    always #5 clk=~clk;
    logic rstn=0;
    logic [11:0] awaddr=0,araddr=0;
    logic [2:0] awprot=0,arprot=0;
    logic awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0;
    logic [31:0] wdata=0;
    logic [3:0] wstrb=0;
    wire awready,wready,arready,bvalid,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    rv64i_soc_axi_top #(.RAM_BYTES(65536)) dut (
        .s_axi_aclk(clk),.s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );
    logic [63:0] program_words [0:MAX_IMAGE_WORDS-1];
    int mmio_count=0, dmem_count=0, dmem_responses=0;
    logic [6:0] observed_steps='0;
    int status_reads=0;
    always @(posedge clk) begin
        if (rstn && dut.run) begin
            if (dut.u_platform.exp_valid) begin
                if (dut.u_platform.exp_error || !dut.u_platform.exp_ready ||
                    dut.u_platform.exp_size !== 2'b11)
                    $fatal(1,"FAIL: protocolo expansion");
                case (dut.u_platform.exp_addr)
                    64'h1000_0020: begin
                        if (!dut.u_platform.exp_we || dut.u_platform.exp_wstrb !== 8'hff ||
                            dut.u_platform.exp_wdata !== OPERAND_A)
                            $fatal(1,"FAIL: operando A");
                        observed_steps[0] <= 1;
                    end
                    64'h1000_0028: begin
                        if (!dut.u_platform.exp_we || dut.u_platform.exp_wstrb !== 8'hff ||
                            dut.u_platform.exp_wdata !== OPERAND_B)
                            $fatal(1,"FAIL: operando B");
                        observed_steps[1] <= 1;
                    end
                    64'h1000_0010: begin
                        if (!dut.u_platform.exp_we || dut.u_platform.exp_wdata !== 64'd1)
                            $fatal(1,"FAIL: start");
                        observed_steps[2] <= 1;
                    end
                    64'h1000_0018: begin
                        if (dut.u_platform.exp_we) begin
                            if (dut.u_platform.exp_wdata !== 64'd2)
                                $fatal(1,"FAIL: W1C");
                            observed_steps[5] <= 1;
                        end else begin
                            if ((status_reads==0 && dut.u_platform.exp_rdata !== 64'd2) ||
                                (status_reads==1 && dut.u_platform.exp_rdata !== 64'd0))
                                $fatal(1,"FAIL: estado acelerador");
                            if (status_reads==0) observed_steps[3] <= 1;
                            else observed_steps[6] <= 1;
                            status_reads <= status_reads+1;
                        end
                    end
                    64'h1000_0030: begin
                        if (dut.u_platform.exp_we || dut.u_platform.exp_rdata !== EXPECTED)
                            $fatal(1,"FAIL: resultado acelerador");
                        observed_steps[4] <= 1;
                    end
                    default: $fatal(1,"FAIL: acceso MMIO no esperado");
                endcase
                mmio_count <= mmio_count+1;
            end
            if (dut.u_platform.dmem_req && dut.u_platform.dmem_gnt) begin
                if (!dut.u_platform.dmem_we || dut.u_platform.dmem_addr !== RESULT_ADDR ||
                    dut.u_platform.dmem_wdata !== 64'd1)
                    $fatal(1,"FAIL: escritura DMEM resultado");
                dmem_count <= dmem_count+1;
            end
            if (dut.u_platform.dmem_rvalid) begin
                if (dut.u_platform.dmem_error) $fatal(1,"FAIL: DMEM error");
                dmem_responses <= dmem_responses+1;
            end
        end
    end

    task automatic send_aw(input logic [11:0] a);
        @(negedge clk); awaddr=a; awvalid=1;
        do @(posedge clk); while (!awready);
        @(negedge clk); awvalid=0;
    endtask
    task automatic send_w(input logic [31:0] d,input logic [3:0] st);
        @(negedge clk); wdata=d; wstrb=st; wvalid=1;
        do @(posedge clk); while (!wready);
        @(negedge clk); wvalid=0;
    endtask
    task automatic axi_write(input logic [11:0] a,
                             input logic [31:0] d,
                             input logic [3:0] st,
                             input logic [1:0] expected_resp,
                             input integer order);
        case (order)
            1: begin send_w(d,st); send_aw(a); end
            2: begin send_aw(a); send_w(d,st); end
            default: fork
                send_aw(a);
                send_w(d,st);
            join
        endcase
        do @(posedge clk); while (!bvalid);
        if (bresp !== expected_resp) $fatal(1,"FAIL: BRESP addr=%h got=%b exp=%b",a,bresp,expected_resp);
        repeat (2) begin
            @(posedge clk);
            if (!bvalid || bresp !== expected_resp)
                $fatal(1,"FAIL: BRESP no estable con BREADY=0");
        end
        @(negedge clk); bready=1;
        @(posedge clk);
        @(negedge clk); bready=0;
    endtask
    task automatic axi_read(input logic [11:0] a,
                            output logic [31:0] d,
                            input logic [1:0] expected_resp);
        @(negedge clk); araddr=a; arvalid=1;
        do @(posedge clk); while (!arready);
        @(negedge clk); arvalid=0;
        do @(posedge clk); while (!rvalid);
        d=rdata;
        if (rresp !== expected_resp)
            $fatal(1,"FAIL: RRESP addr=%h got=%b",a,rresp);
        repeat (2) begin
            @(posedge clk);
            if (!rvalid || rdata !== d || rresp !== expected_resp)
                $fatal(1,"FAIL: RDATA inestable con RREADY=0");
        end
        @(negedge clk); rready=1;
        @(posedge clk);
        @(negedge clk); rready=0;
    endtask
    task automatic boot_write64(input logic [63:0] a, input logic [63:0] d);
        axi_write(12'h008,a[31:0],4'hf,2'b00,0);
        axi_write(12'h00c,a[63:32],4'hf,2'b00,1);
        axi_write(12'h010,d[31:0],4'hf,2'b00,2);
        axi_write(12'h014,d[63:32],4'hf,2'b00,0);
        axi_write(12'h01c,32'd1,4'hf,2'b00,0);
    endtask
    task automatic boot_read64_check(input logic [63:0] a,input logic [63:0] expected);
        logic [31:0] lo,hi;
        axi_write(12'h008,a[31:0],4'hf,2'b00,0);
        axi_write(12'h00c,a[63:32],4'hf,2'b00,0);
        axi_write(12'h01c,32'd2,4'hf,2'b00,0);
        axi_read(12'h020,lo,2'b00);
        axi_read(12'h024,hi,2'b00);
        if ({hi,lo} !== expected) $fatal(1,"FAIL: lectura boot addr=%h got=%h expected=%h",a,{hi,lo},expected);
    endtask

    initial begin : test
        logic [31:0] rd;
        int polls;
        if (IMAGE_WORDS <= 0 || IMAGE_WORDS > MAX_IMAGE_WORDS)
            $fatal(1,"FAIL: numero palabras imagen");
        $readmemh("integration_dmem.hex",program_words,0,IMAGE_WORDS-1);
        repeat (5) @(negedge clk);
        rstn=1;
        axi_read(12'h004,rd,2'b00);
        if (rd!==0) $fatal(1,"FAIL: estado inicial");
        axi_read(12'h02c,rd,2'b10);  // direccion de registro invalida
        axi_write(12'h018,32'hff,4'h1,2'b00,1);
        for (int i=0;i<IMAGE_WORDS;i++)
            boot_write64(RAM_BASE + 64'(i*8),program_words[i]);
        boot_read64_check(RAM_BASE,program_words[0]);
        boot_read64_check(RESULT_ADDR,64'd0);
        axi_write(12'h000,32'd1,4'hf,2'b00,0);
        axi_write(12'h01c,32'd2,4'hf,2'b10,0); // comando prohibido en run
        polls=0;
        do begin
            axi_read(12'h004,rd,2'b00);
            polls++;
            if (rd[9:8]==2) $fatal(1,"FAIL: programa marco FAIL");
        end while (rd[9:8] != 1 && polls < 400);
        if (rd[9:8] != 1) $fatal(1,"FAIL: no se observo PASS en 400 lecturas AXI");
        if (mmio_count != 7 || observed_steps !== 7'h7f ||
            dmem_count != 1 || dmem_responses != 1)
            $fatal(1,"FAIL: conteos MMIO=%0d DMEM=%0d/%0d etapas=%b",
                   mmio_count,dmem_count,dmem_responses,observed_steps);
        axi_write(12'h000,32'd0,4'hf,2'b00,0);
        boot_read64_check(RESULT_ADDR,64'd1);
        axi_read(12'h028,rd,2'b00);
        if (rd !== 32'd1) $fatal(1,"FAIL: BOOT_STATUS=%h",rd);
        $display("PASS: P2.7.1 AXI4-Lite + RV64I + UltraRAM + MMIO");
        $display("      result_flag=1 mmio=%0d dmem=%0d/%0d polls=%0d",mmio_count,dmem_count,dmem_responses,polls);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"FAIL: timeout global testbench");
    end
endmodule
