`timescale 1ns/1ps

module tb_core_expansion_priv_wait;

    logic clk;
    logic rst;

    logic [63:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [63:0] dmem_rdata;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [63:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic [1:0]  dmem_size;

    logic        exp_valid;
    logic        exp_we;
    logic [63:0] exp_addr;
    logic [63:0] exp_wdata;
    logic [7:0]  exp_wstrb;
    logic [1:0]  exp_size;
    logic        exp_ready;
    logic [63:0] exp_rdata;
    logic        exp_error;

    integer scenario;

    // ---------------------------------------------------------
    // Señales de salida del DUT que no son relevantes para
    // esta prueba específica.
    //
    // Se consumen explícitamente para mantener limpio el lint
    // sin deshabilitar globalmente UNUSEDSIGNAL.
    // ---------------------------------------------------------
    wire _unused_ok = 1'b0 && &{
        1'b0,
        dmem_we,
        dmem_wstrb,
        dmem_addr,
        dmem_wdata,
        dmem_size,
        exp_we,
        exp_wdata,
        exp_wstrb,
        exp_size,
        1'b0
    };

    localparam integer SCENARIO_CSR  = 0;
    localparam integer SCENARIO_MRET = 1;

    // ---------------------------------------------------------
    // Clock
    // ---------------------------------------------------------
    initial clk = 1'b0;

    // Generador de reloj exclusivo del testbench.
    // La asignación bloqueante es intencional.
    // verilator lint_off BLKSEQ
    always #5 clk = ~clk;
    // verilator lint_on BLKSEQ

    // ---------------------------------------------------------
    // DUT
    // Región de expansión: 0x1000 - 0x1FFF
    // ---------------------------------------------------------
    core_top #(
        .RESET_PC   (64'h0000_0000_0000_0000),
        .TRAP_VECTOR(64'h0000_0000_0000_0100),
        .EXP_BASE   (64'h0000_0000_0000_1000),
        .EXP_MASK   (64'hFFFF_FFFF_FFFF_F000)
    ) dut (
        .clk        (clk),
        .rst        (rst),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_rdata (dmem_rdata),
        .dmem_we    (dmem_we),
        .dmem_wstrb (dmem_wstrb),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_size  (dmem_size),

        .exp_valid  (exp_valid),
        .exp_we     (exp_we),
        .exp_addr   (exp_addr),
        .exp_wdata  (exp_wdata),
        .exp_wstrb  (exp_wstrb),
        .exp_size   (exp_size),
        .exp_ready  (exp_ready),
        .exp_rdata  (exp_rdata),
        .exp_error  (exp_error)
    );

    // ---------------------------------------------------------
    // Programa
    //
    // 0x00: LUI     x1, 0x1
    //              x1 = 0x1000
    //
    // 0x04: LD      x2, 0(x1)
    //              acceso a región de expansión
    //
    // 0x08:
    //   escenario 0:
    //     CSRRWI x0, mstatus, 8
    //     -> intenta MIE=1 y MPIE=0
    //
    //   escenario 1:
    //     MRET
    //
    // 0x0C+: NOP
    // ---------------------------------------------------------
    always_comb begin
        imem_rdata = 32'h0000_0013; // NOP

        case (imem_addr)
            64'h0000_0000_0000_0000:
                imem_rdata = 32'h0000_10B7; // LUI x1, 0x1

            64'h0000_0000_0000_0004:
                imem_rdata = 32'h0000_B103; // LD x2, 0(x1)

            64'h0000_0000_0000_0008: begin
                if (scenario == SCENARIO_CSR)
                    imem_rdata = 32'h3004_5073; // CSRRWI x0, mstatus, 8
                else
                    imem_rdata = 32'h3020_0073; // MRET
            end

            default:
                imem_rdata = 32'h0000_0013;
        endcase
    end

    // ---------------------------------------------------------
    // Reset común
    // ---------------------------------------------------------
    task automatic apply_reset;
        begin
            rst       = 1'b1;
            exp_ready = 1'b0;
            exp_error = 1'b0;
            exp_rdata = 64'h1122_3344_5566_7788;
            dmem_rdata = 64'd0;

            repeat (3) @(posedge clk);

            rst = 1'b0;

            @(posedge clk);
            #1;
        end
    endtask

    // ---------------------------------------------------------
    // Test
    // ---------------------------------------------------------
    initial begin
        rst        = 1'b1;
        exp_ready  = 1'b0;
        exp_error  = 1'b0;
        exp_rdata  = 64'h1122_3344_5566_7788;
        dmem_rdata = 64'd0;
        scenario   = SCENARIO_CSR;

        // =====================================================
        // Escenario 1:
        // CSR más joven no debe escribir durante wait-state
        // =====================================================
        apply_reset();

        wait (exp_valid === 1'b1);

        if (exp_addr !== 64'h0000_0000_0000_1000) begin
            $fatal(
                1,
                "FAIL: dirección de expansión incorrecta. exp_addr=%h",
                exp_addr
            );
        end

        // Dejamos al menos un flanco con la instrucción CSR retenida
        // en EX y la instrucción LD retenida en MEM.
        @(posedge clk);
        #1;

        if (dut.u_csr_file.mstatus_mie_r !== 1'b0) begin
            $fatal(
                1,
                "FAIL: CSR modificó MIE durante mem_exp_wait_stall"
            );
        end

        if (dut.u_csr_file.mstatus_mpie_r !== 1'b1) begin
            $fatal(
                1,
                "FAIL: CSR modificó MPIE durante mem_exp_wait_stall"
            );
        end

        // Ahora el periférico termina el acceso.
        exp_ready = 1'b1;

        @(posedge clk);
        #1;

        // CSRRWI mstatus,8 debe ejecutarse ahora:
        // bit 3 MIE  = 1
        // bit 7 MPIE = 0
        if (dut.u_csr_file.mstatus_mie_r !== 1'b1) begin
            $fatal(
                1,
                "FAIL: CSR no actualizó MIE al liberar el wait-state"
            );
        end

        if (dut.u_csr_file.mstatus_mpie_r !== 1'b0) begin
            $fatal(
                1,
                "FAIL: CSR no actualizó MPIE al liberar el wait-state"
            );
        end

        // =====================================================
        // Escenario 2:
        // MRET más joven no debe modificar mstatus durante wait
        // =====================================================
        scenario = SCENARIO_MRET;
        apply_reset();

        wait (exp_valid === 1'b1);

        if (exp_addr !== 64'h0000_0000_0000_1000) begin
            $fatal(
                1,
                "FAIL: dirección de expansión incorrecta en MRET. exp_addr=%h",
                exp_addr
            );
        end

        @(posedge clk);
        #1;

        // Reset de csr_file:
        // MIE  = 0
        // MPIE = 1
        //
        // Un MRET prematuro cambiaría MIE a 1.
        if (dut.u_csr_file.mstatus_mie_r !== 1'b0) begin
            $fatal(
                1,
                "FAIL: MRET modificó MIE durante mem_exp_wait_stall"
            );
        end

        if (dut.u_csr_file.mstatus_mpie_r !== 1'b1) begin
            $fatal(
                1,
                "FAIL: MRET modificó MPIE durante mem_exp_wait_stall"
            );
        end

        // Liberamos la instrucción antigua.
        exp_ready = 1'b1;

        @(posedge clk);
        #1;

        // Ahora MRET sí debe ejecutarse.
        if (dut.u_csr_file.mstatus_mie_r !== 1'b1) begin
            $fatal(
                1,
                "FAIL: MRET no restauró MIE al liberar el wait-state"
            );
        end

        if (dut.u_csr_file.mstatus_mpie_r !== 1'b1) begin
            $fatal(
                1,
                "FAIL: MPIE incorrecto después de MRET"
            );
        end

        $display(
            "PASS: CSR y MRET preservan precisión durante wait-states"
        );

        $finish;
    end

endmodule
