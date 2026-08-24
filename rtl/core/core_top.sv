`timescale 1ns/1ps

module core_top #(
    parameter logic [63:0] RESET_PC = 64'd0,
    parameter logic [63:0] TRAP_VECTOR = 64'h0000_0000_0000_0100,

    // Región MMIO reservada para el puerto de expansión.
    // Por defecto: 0x0000_0000_8000_0000 - 0x0000_0000_8000_0FFF
    parameter logic [63:0] EXP_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] EXP_MASK = 64'hFFFF_FFFF_FFFF_F000
) (
    input  logic        clk,    // reloj del core
    input  logic        rst,    // reset síncrono del core

    // -----------------------------
    // Instruction memory interface
    // -----------------------------
    output logic [63:0] imem_addr, // dirección de la instrucción a fetchar
    input  logic [31:0] imem_rdata,// instrucción fetcheada
    input  logic [63:0] dmem_rdata,// dato leído desde memoria de datos (para operaciones de load)

    // -----------------------------
    // Data memory interface
    // -----------------------------
    output logic        dmem_we,    // habilitación de escritura (store)
    output logic [7:0]  dmem_wstrb,  // byte enables para la operación de store (calculados a partir de dmem_size y dmem_addr)
    output logic [63:0] dmem_addr,  // dirección de la operación de memoria (load/store)
    output logic [63:0] dmem_wdata, // dato a escribir en caso de store
    output logic [1:0]  dmem_size,   // tamaño de la operación de memoria (00=byte, 01=halfword, 10=word, 11=doubleword)

    // -----------------------------
    // Expansion MMIO interface
    // -----------------------------
    output logic        exp_valid,  // acceso válido hacia región de expansión
    output logic        exp_we,     // 1=store, 0=load
    output logic [63:0] exp_addr,   // dirección efectiva completa
    output logic [63:0] exp_wdata,  // dato de escritura alineado por byte lane
    output logic [7:0]  exp_wstrb,  // byte enables
    output logic [1:0]  exp_size,   // tamaño del acceso
    input  logic        exp_ready,  // reservado para wait-states futuros
    input  logic [63:0] exp_rdata,  // dato leído desde periférico/acelerador
    input  logic        exp_error   // reservado para traps de memoria futuros
);



    // =========================================================
    // Localparams compartidos
    // =========================================================
    localparam logic [2:0] IMM_NONE = 3'b000;       // No immediate

    localparam logic [1:0] ALU_SRC_A_RS1  = 2'b00;  // Operando A viene de rs1
    localparam logic [1:0] ALU_SRC_A_PC   = 2'b01;  // Operando A viene de pc
    localparam logic [1:0] ALU_SRC_A_ZERO = 2'b10;  // Operando A es cero

    localparam logic       ALU_SRC_B_RS2  = 1'b0;   // Operando B viene de rs2/inmediato
    localparam logic       ALU_SRC_B_IMM  = 1'b1;   // Operando B viene de inmediato


    // Opciones de redirección para el forwarding
    //localparam logic [1:0] FWD_NONE = 2'b00;
    localparam logic [1:0] FWD_MEM  = 2'b01;
    localparam logic [1:0] FWD_WB   = 2'b10;

    // Códigos de excepción para mcause (se pueden ampliar según necesidades, por ejemplo para incluir excepciones de memoria o de sistema)
    localparam logic [63:0] MCAUSE_INSTR_ADDR_MISALIGNED = 64'd0;
    localparam logic [63:0] MCAUSE_ILLEGAL_INSTR         = 64'd2;
    localparam logic [63:0] MCAUSE_BREAKPOINT            = 64'd3;
    localparam logic [63:0] MCAUSE_LOAD_ADDR_MISALIGNED  = 64'd4;
    localparam logic [63:0] MCAUSE_LOAD_ACCESS_FAULT     = 64'd5;
    localparam logic [63:0] MCAUSE_STORE_ADDR_MISALIGNED = 64'd6;
    localparam logic [63:0] MCAUSE_STORE_ACCESS_FAULT    = 64'd7;
    localparam logic [63:0] MCAUSE_ECALL_M               = 64'd11;


    // =========================================================
    // CSRs mínimos internos para traps
    // =========================================================
    logic [63:0] csr_mtvec;
    logic [63:0] csr_mepc;
    logic [63:0] csr_mcause;
    logic [63:0] csr_mtval;

    // =========================================================
    // PC / IF stage 
    // =========================================================
    logic [63:0] pc_reg;        // Registro de PC
    logic [63:0] pc_next;       // Valor siguiente del PC (lógica combinacional)
    logic [63:0] pc_plus4_if;   // PC + 4 calculado en IF stage
    logic        if_valid_in;   // Señal de valid para IF/ID (por ahora siempre válida)
    logic load_use_hazard;      // Señal que indica si hay un hazard de tipo load-use (instrucción en EX es un load y la siguiente instrucción en ID usa el registro cargado)

    assign pc_plus4_if = pc_reg + 64'd4;    // PC + 4 calculado en IF para usar en redirecciones y WB
    assign if_valid_in = 1'b1;              // Por ahora IF stage siempre válida (no hay stalls ni flushes en IF)
    assign imem_addr   = pc_reg;            // La dirección de instrucción a fetchar es el valor actual del PC



    // =========================================================
    // Señales de flush / stall
    // =========================================================
    logic if_id_stall;          // Stall hacia IF/ID
    logic if_id_flush;          // Flush hacia IF/ID

    logic id_ex_stall;
    logic id_ex_flush;

    logic ex_mem_stall;
    logic ex_mem_flush;

    logic mem_wb_stall;
    logic mem_wb_flush;

    // Redirección de control con prioridad sobre stalls de datos.
    // Incluye traps, MRET y branches/jumps tomados.
    logic control_redirect;

    // Stall efectivo por load-use.
    // Si hay redirección de control, no se debe congelar el PC.
    logic data_hazard_stall;
    logic mem_exp_wait_stall;
    logic pipeline_stall;

    // Una instrucción detenida en EX no puede modificar estado arquitectural.
    // Por ahora el único stall global de MEM es el wait-state del puerto
    // de expansión. Más adelante esta señal se generalizará cuando la
    // memoria principal también tenga handshake/latencia.
    logic ex_arch_side_effect_enable;

    // Trap detectado en etapa MEM.
    // Incluye:
    // - accesos load/store desalineados
    // - errores del puerto de expansión convertidos en access fault
    logic        mem_sync_trap;
    logic [63:0] mem_trap_cause;
    logic [63:0] mem_trap_value;

    // Trap finalmente tomado por el core.
    // MEM tiene prioridad sobre EX porque la instrucción en MEM es más antigua.
    logic        trap_taken_valid;
    logic [63:0] trap_taken_pc;
    logic [63:0] trap_taken_cause;
    logic [63:0] trap_taken_value;

    // Lógica de generación de señales de stall y flush (por ahora solo se implementa el hazard de tipo load-use con un stall hacia IF/ID, el resto de señales se dejan en 0 para no tener stalls ni flushes adicionales)
    assign load_use_hazard =
        id_valid_out &&
        ex_valid_out &&
        ex_mem_read_out &&
        !ex_illegal_instr_out &&
        (ex_rd_addr_out != 5'd0) &&
        (
            (id_rs1_used && (id_rs1_addr == ex_rd_addr_out)) ||
            (id_rs2_used && (id_rs2_addr == ex_rd_addr_out))
        );

    // data_hazard_stall conserva el caso clásico load-use.
    // Si MEM está esperando un periférico/AXI, el stall global tiene prioridad
    // y no se debe insertar una burbuja nueva en ID/EX.
    assign data_hazard_stall =
        load_use_hazard &&
        !control_redirect &&
        !mem_exp_wait_stall;

    // Stall global del pipeline.
    // Se activa por:
    // - load-use: congela PC e IF/ID, e inserta burbuja en ID/EX.
    // - espera MMIO/exp: congela todas las etapas hasta que exp_ready=1.
    assign pipeline_stall =
        mem_exp_wait_stall ||
        data_hazard_stall;

    assign ex_arch_side_effect_enable =
        !mem_exp_wait_stall;

    assign if_id_stall  = pipeline_stall;
    assign id_ex_stall  = mem_exp_wait_stall;
    assign ex_mem_stall = mem_exp_wait_stall;
    assign mem_wb_stall = mem_exp_wait_stall;

    // Si el trap se detecta en MEM, la instrucción causante no debe llegar a WB.
    assign mem_wb_flush = mem_sync_trap;

    // =========================================================
    // IF/ID
    // =========================================================
    logic        id_valid_out;  // Señal de valid para ID stage
    logic [63:0] id_pc_out;     // Salida de PC desde IF/ID (para usar en ID y también pasar a EX)
    logic [31:0] id_instr_out;  // Salida de instrucción desde IF/ID (para usar en ID y también pasar a EX)
    logic        id_sys_ecall;
    logic        id_sys_ebreak;
    logic        id_sys_mret;

    // Registros IF/ID con lógica de stall y flush 
    if_id_reg u_if_id_reg (
        .clk        (clk),
        .rst        (rst),
        .stall      (if_id_stall),
        .flush      (if_id_flush),
        .if_valid_in(if_valid_in),
        .if_pc_in   (pc_reg),
        .if_instr_in(imem_rdata),
        .id_valid_out(id_valid_out),
        .id_pc_out    (id_pc_out),
        .id_instr_out (id_instr_out)
    );


    // =========================================================
    // ID: decoder + imm_gen + regfile
    // =========================================================

    // Señales crudas desde el decoder (a ser "gateadas" por valid)
    logic [4:0] dec_rs1_addr_raw;   // Dirección rs1 decodificada
    logic [4:0] dec_rs2_addr_raw;   // Dirección rs2 decodificada
    logic [4:0] dec_rd_addr_raw;    // Dirección rd decodificada    

    logic [2:0] dec_imm_sel_raw;    // Seleccionador de inmediato

    logic       dec_reg_write_raw;  // Señal de control de escritura en registro decodificada
    logic       dec_mem_write_raw;  // Señal de control de escritura en memoria decodificada
    logic [1:0] dec_store_size_raw; // Tamaño de store decodificado (00=byte, 01=halfword, 10=word, 11=doubleword)
    logic       dec_wb_sel_pc4_raw; // Señal de control de selección de dato para writeback decodificada (0=ALU result, 1=PC+4)

    logic       dec_mem_read_raw;       // Señal de control de lectura de memoria decodificada
    logic [1:0] dec_load_size_raw;      // Tamaño de load decodificado (00=byte, 01=halfword, 10=word, 11=doubleword)
    logic       dec_load_unsigned_raw;  // Señal de control de load unsigned decodificada
    logic       dec_wb_sel_mem_raw;     // Señal de control de selección de dato para writeback decodificada (0=ALU result, 1=load data)
    logic       dec_rs1_used_raw;       // Señal que indica si rs1 es usado en la instrucción (para optimizar forwarding)
    logic       dec_rs2_used_raw;       // Señal que indica si rs2 es usado en la instrucción (para optimizar forwarding)

    logic [1:0] dec_alu_src_a_sel_raw;  // Seleccionador de fuente A para ALU decodificado (00=rs1, 01=pc, 10=cero)
    logic       dec_alu_src_b_sel_raw;  // Seleccionador de fuente B para ALU decodificado (0=rs2, 1=inmediato)
    logic [3:0] dec_alu_op_raw;     // Operación de ALU decodificada (ej. 0000=ADD, 0001=SUB, etc. - definir según necesidades)

    logic       dec_branch_raw;     // Señal de control de branch decodificada
    logic [2:0] dec_branch_op_raw;  // Operación de branch decodificada (ej. 00=BEQ, 01=BNE, etc. - definir según necesidades)
    logic       dec_jump_raw;       // Señal de control de jump decodificada

    logic       dec_illegal_instr_raw;      // Señal de instrucción ilegal decodificada

    // Señales decodificadas para instrucciones de memoria
    logic       dec_sys_ecall_raw;
    logic       dec_sys_ebreak_raw;
    logic       dec_sys_mret_raw;

    // Señales crudas desde el decoder para instrucciones CSR
    logic       dec_csr_en_raw;
    logic [1:0] dec_csr_cmd_raw;
    logic       dec_csr_use_imm_raw;
    logic       dec_csr_read_raw;
    logic       dec_csr_write_raw;

    // Módulo de decodificación de instrucciones 
    decoder u_decoder (
        .instr         (id_instr_out),      // Instrucción a decodificar
        .rs1_addr      (dec_rs1_addr_raw),  // Dirección rs1 decodificada
        .rs2_addr      (dec_rs2_addr_raw),  // Dirección rs2 decodificada
        .rd_addr       (dec_rd_addr_raw),   // Dirección rd decodificada
        .imm_sel       (dec_imm_sel_raw),   // Seleccionador de inmediato
        .reg_write     (dec_reg_write_raw), // Señal de control de escritura en registro
        .mem_write     (dec_mem_write_raw), // Señal de control de escritura en memoria
        .store_size    (dec_store_size_raw), // Tamaño de store decodificado
        .wb_sel_pc4    (dec_wb_sel_pc4_raw), // Señal de control de selección de dato para writeback
        .alu_src_a_sel (dec_alu_src_a_sel_raw), // Seleccionador de fuente A para ALU
        .alu_src_b_sel (dec_alu_src_b_sel_raw), // Seleccionador de fuente B para ALU
        .alu_op        (dec_alu_op_raw),     // Operación de ALU decodificada
        .branch        (dec_branch_raw),     // Señal de control de branch
        .branch_op     (dec_branch_op_raw),  // Operación de branch
        .jump          (dec_jump_raw),       // Señal de control de jump
        .illegal_instr (dec_illegal_instr_raw), // Señal de instrucción ilegal
        .mem_read      (dec_mem_read_raw),
        .load_size     (dec_load_size_raw),
        .load_unsigned (dec_load_unsigned_raw),
        .wb_sel_mem    (dec_wb_sel_mem_raw),
        .csr_en        (dec_csr_en_raw),
        .csr_cmd       (dec_csr_cmd_raw),
        .csr_use_imm   (dec_csr_use_imm_raw),
        .csr_read      (dec_csr_read_raw),
        .csr_write     (dec_csr_write_raw),
        .rs1_used      (dec_rs1_used_raw),
        .rs2_used      (dec_rs2_used_raw),
        .sys_ecall     (dec_sys_ecall_raw), // Señal de decodificación de ECALL
        .sys_ebreak    (dec_sys_ebreak_raw),// Señal de decodificación de EBREAK        
        .sys_mret      (dec_sys_mret_raw)   // Señal de decodificación de MRET
    );

    // Gateo de señales de control por valid (si no es válida, se ponen en valores que no hagan nada)
    logic [4:0] id_rs1_addr;        // Dirección rs1 "gateada" por valid        
    logic [4:0] id_rs2_addr;        // Dirección rs2 "gateada" por valid
    logic [4:0] id_rd_addr;         // Dirección rd "gateada" por valid

    logic [2:0] id_imm_sel;         // Señal de control de selección de inmediato "gateada" por valid

    logic       id_reg_write;       // Señal de control de escritura en registro "gateada" por valid
    logic       id_mem_write;       // Señal de control de escritura en memoria "gateada" por valid
    logic [1:0] id_store_size;      // Tamaño de store "gateado" por valid
    logic       id_wb_sel_pc4;      // Señal de control de selección de dato para writeback "gateada" por valid

    logic       id_mem_read;        // Señal de control de lectura de memoria "gateada" por valid
    logic [1:0] id_load_size;       // Tamaño de load "gateado" por valid
    logic       id_load_unsigned;   // Señal de control de load unsigned "gateada" por valid
    logic       id_wb_sel_mem;      // Señal de control de selección de dato para writeback "gateada" por valid (0=ALU result, 1=load data)
    logic       id_rs1_used;        // Señal que indica si rs1 es usado en la instrucción (para optimizar forwarding)
    logic       id_rs2_used;        // Señal que indica si rs2 es usado en la instrucción (para optimizar forwarding)

    logic [1:0] id_alu_src_a_sel;   // Señal de control de selección de fuente A para ALU "gateada" por valid
    logic       id_alu_src_b_sel;   // Señal de control de selección de fuente B para ALU "gateada" por valid
    logic [3:0] id_alu_op;          // Operación de ALU "gateada" por valid

    logic       id_branch;           // Señal de control de branch "gateada" por valid
    logic [2:0] id_branch_op;       // Operación de branch "gateada" por valid
    logic       id_jump;             // Señal de control de jump "gateada" por valid

    logic       id_illegal_instr;    // Señal de instrucción ilegal "gateada" por valid

    // Señales "gateadas" por valid para instrucciones de sistema
    logic       id_csr_en;
    logic [1:0] id_csr_cmd;
    logic       id_csr_use_imm;
    logic       id_csr_read;
    logic       id_csr_write;

    // Lógica combinacional para gatear las señales de control por valid
    always_comb begin
        // Por defecto, señales "gateadas" a valores que no hagan nada
        id_rs1_addr      = 5'd0;
        id_rs2_addr      = 5'd0;
        id_rd_addr       = 5'd0;

        id_imm_sel       = IMM_NONE;

        id_reg_write     = 1'b0;
        id_mem_write     = 1'b0;
        id_store_size    = 2'b00;
        id_wb_sel_pc4    = 1'b0;

        id_mem_read      = 1'b0;
        id_load_size     = 2'b00;
        id_load_unsigned = 1'b0;
        id_wb_sel_mem    = 1'b0;
        id_rs1_used      = 1'b0;
        id_rs2_used      = 1'b0;

        id_alu_src_a_sel = ALU_SRC_A_RS1;
        id_alu_src_b_sel = ALU_SRC_B_RS2;
        id_alu_op        = 4'd0;

        id_branch        = 1'b0;
        id_branch_op     = 3'b000;
        id_jump          = 1'b0;

        id_illegal_instr = 1'b0;

        id_sys_ecall    = 1'b0;
        id_sys_ebreak   = 1'b0;
        id_sys_mret     = 1'b0;

        id_csr_en       = 1'b0;
        id_csr_cmd      = 2'b00;
        id_csr_use_imm  = 1'b0;
        id_csr_read     = 1'b0;
        id_csr_write    = 1'b0;

        // Si la instrucción es válida, se pasan las señales decodificadas a través del "gateo" para que lleguen a ID/EX y el resto de la pipeline con los valores correctos 
        if (id_valid_out) begin
            id_rs1_addr      = dec_rs1_addr_raw;        // Dirección rs1 "gateada" por valid
            id_rs2_addr      = dec_rs2_addr_raw;        // Dirección rs2 "gateada" por valid
            id_rd_addr       = dec_rd_addr_raw;         // Dirección rd "gateada" por valid

            id_imm_sel       = dec_imm_sel_raw;         // Señal de control de selección de inmediato "gateada" por valid

            id_reg_write     = dec_reg_write_raw;       
            id_mem_write     = dec_mem_write_raw;
            id_store_size    = dec_store_size_raw;
            id_wb_sel_pc4    = dec_wb_sel_pc4_raw;

            id_alu_src_a_sel = dec_alu_src_a_sel_raw;
            id_alu_src_b_sel = dec_alu_src_b_sel_raw;
            id_alu_op        = dec_alu_op_raw;

            id_branch        = dec_branch_raw;
            id_branch_op     = dec_branch_op_raw;
            id_jump          = dec_jump_raw;

            id_illegal_instr = dec_illegal_instr_raw;

            id_mem_read      = dec_mem_read_raw;
            id_load_size     = dec_load_size_raw;
            id_load_unsigned = dec_load_unsigned_raw;
            id_wb_sel_mem    = dec_wb_sel_mem_raw;
            id_rs1_used      = dec_rs1_used_raw;
            id_rs2_used      = dec_rs2_used_raw;

            id_sys_ecall    = dec_sys_ecall_raw;
            id_sys_ebreak   = dec_sys_ebreak_raw;
            id_sys_mret     = dec_sys_mret_raw;

            id_csr_en       = dec_csr_en_raw;
            id_csr_cmd      = dec_csr_cmd_raw;
            id_csr_use_imm  = dec_csr_use_imm_raw;
            id_csr_read     = dec_csr_read_raw;
            id_csr_write    = dec_csr_write_raw;
        end
    end

    logic [63:0] id_imm;        // Inmediato generado por el módulo de generación de inmediatos

    // Módulo de generación de inmediatos que toma la instrucción y el tipo de inmediato a generar (decodificado) y produce el inmediato correspondiente 
    imm_gen u_imm_gen (
        .instr   (id_instr_out),    // Instrucción de la cual generar el inmediato
        .imm_sel (id_imm_sel),      // Tipo de inmediato a generar (decodificado)
        .imm     (id_imm)           // Inmediato generado
    );

    // Writeback hacia regfile 
    logic        wb_commit_we;      // Señal de control de escritura en regfile para la etapa de WB
    logic [4:0]  wb_commit_rd_addr; // Dirección de rd para la etapa de WB
    logic [63:0] wb_commit_rd_data; // Dato a escribir en rd para la etapa de WB (puede venir de ALU o de PC+4 dependiendo del tipo de instrucción, controlado por wb_sel_pc4)

    logic [63:0] id_rs1_data;       // Dato del registro rs1 "gateado" por valid
    logic [63:0] id_rs2_data;       // Dato del registro rs2 "gateado" por valid

    // Banco de registros con dos puertos de lectura (rs1 y rs2) y un puerto de escritura (rd) para la etapa de WB
    regfile u_regfile (
        .clk      (clk),
        .rst      (rst),

        .we       (wb_commit_we),
        .rd_addr  (wb_commit_rd_addr),
        .rd_data  (wb_commit_rd_data),

        .rs1_addr (id_rs1_addr),        // Dirección de rs1 "gateada" por valid
        .rs1_data (id_rs1_data),

        .rs2_addr (id_rs2_addr),
        .rs2_data (id_rs2_data)
    );




    // =========================================================
    // ID/EX registros con lógica de stall y flush 
    // =========================================================
    logic        ex_valid_out;      // Señal de valid para EX stage
    logic [63:0] ex_pc_out;         // Salida de PC desde ID/EX (para usar en EX y también pasar a MEM)
    logic [31:0] ex_instr_out;      // Salida de instrucción desde ID/EX (para usar en EX y también pasar a MEM)

    logic [4:0]  ex_rs1_addr_out;   // Dirección rs1 pasada a EX
    logic [4:0]  ex_rs2_addr_out;   // Dirección rs2 pasada a EX
    logic [4:0]  ex_rd_addr_out;    // Dirección rd pasada a EX

    logic [63:0] ex_rs1_data_out;   // Dato de rs1 pasado a EX
    logic [63:0] ex_rs2_data_out;   // Dato de rs2 pasado a EX
    logic [63:0] ex_imm_out;        // Inmediato pasado a EX

    logic        ex_reg_write_out;  // Señal de control de escritura en registro pasada a EX
    logic        ex_mem_write_out;  // Señal de control de escritura en memoria pasada a EX
    logic [1:0]  ex_store_size_out; // Tamaño de store pasado a EX
    logic        ex_wb_sel_pc4_out; // Señal de control de selección de dato para writeback pasada a EX

    logic        ex_mem_read_out;
    logic [1:0]  ex_load_size_out;
    logic        ex_load_unsigned_out;
    logic        ex_wb_sel_mem_out;

    logic [1:0]  ex_alu_src_a_sel_out;  // Señal de control de selección de fuente A para ALU pasada a EX
    logic        ex_alu_src_b_sel_out;  // Señal de control de selección de fuente B para ALU pasada a EX
    logic [3:0]  ex_alu_op_out;        // Señal de control de operación para ALU pasada a EX

    logic        ex_branch_out;     // Señal de control de branch pasada a EX
    logic [2:0]  ex_branch_op_out;  // Señal de control de operación de branch pasada a EX
    logic        ex_jump_out;       // Señal de control de jump pasada a EX

    logic        ex_illegal_instr_out;  // Señal de instrucción ilegal pasada a EX

    logic        ex_sys_ecall_out;
    logic        ex_sys_ebreak_out;
    logic        ex_sys_mret_out;

    logic        ex_csr_en_out;
    logic [1:0]  ex_csr_cmd_out;
    logic        ex_csr_use_imm_out;
    logic        ex_csr_read_out;
    logic        ex_csr_write_out;

    // Registros ID/EX con lógica de stall y flush que pasan las señales desde ID hacia EX (y también hacia MEM y WB para las señales que necesitan llegar hasta esas etapas)
    id_ex_reg u_id_ex_reg (
        .clk                 (clk),
        .rst                 (rst),
        .stall               (id_ex_stall),
        .flush               (id_ex_flush),

        .id_valid_in         (id_valid_out),
        .id_pc_in            (id_pc_out),
        .id_instr_in         (id_instr_out),

        .id_rs1_addr_in      (id_rs1_addr),
        .id_rs2_addr_in      (id_rs2_addr),
        .id_rd_addr_in       (id_rd_addr),

        .id_rs1_data_in      (id_rs1_data),
        .id_rs2_data_in      (id_rs2_data),
        .id_imm_in           (id_imm),

        .id_reg_write_in     (id_reg_write),
        .id_mem_write_in     (id_mem_write),
        .id_store_size_in    (id_store_size),
        .id_wb_sel_pc4_in    (id_wb_sel_pc4),

        .id_alu_src_a_sel_in (id_alu_src_a_sel),
        .id_alu_src_b_sel_in (id_alu_src_b_sel),
        .id_alu_op_in        (id_alu_op),

        .id_branch_in        (id_branch),
        .id_branch_op_in     (id_branch_op),
        .id_jump_in          (id_jump),

        .id_illegal_instr_in (id_illegal_instr),

        .id_mem_read_in     (id_mem_read),
        .id_load_size_in    (id_load_size),
        .id_load_unsigned_in(id_load_unsigned),
        .id_wb_sel_mem_in   (id_wb_sel_mem),

        .id_csr_en_in      (id_csr_en),
        .id_csr_cmd_in     (id_csr_cmd),
        .id_csr_use_imm_in (id_csr_use_imm),
        .id_csr_read_in    (id_csr_read),
        .id_csr_write_in   (id_csr_write),

        .id_sys_ecall_in    (id_sys_ecall),
        .id_sys_ebreak_in   (id_sys_ebreak),
        .id_sys_mret_in     (id_sys_mret),

        // Señales de control adicionales para load/store que se pasan desde ID hacia EX (y también hacia MEM y WB para las señales que necesitan llegar hasta esas etapas)
        .ex_valid_out        (ex_valid_out),
        .ex_pc_out           (ex_pc_out),
        .ex_instr_out        (ex_instr_out),

        .ex_rs1_addr_out     (ex_rs1_addr_out),
        .ex_rs2_addr_out     (ex_rs2_addr_out),
        .ex_rd_addr_out      (ex_rd_addr_out),

        .ex_rs1_data_out     (ex_rs1_data_out),
        .ex_rs2_data_out     (ex_rs2_data_out),
        .ex_imm_out          (ex_imm_out),

        .ex_reg_write_out    (ex_reg_write_out),
        .ex_mem_write_out    (ex_mem_write_out),
        .ex_store_size_out   (ex_store_size_out),
        .ex_wb_sel_pc4_out   (ex_wb_sel_pc4_out),

        .ex_alu_src_a_sel_out(ex_alu_src_a_sel_out),
        .ex_alu_src_b_sel_out(ex_alu_src_b_sel_out),
        .ex_alu_op_out       (ex_alu_op_out),

        .ex_branch_out       (ex_branch_out),
        .ex_branch_op_out    (ex_branch_op_out),
        .ex_jump_out         (ex_jump_out),

        .ex_illegal_instr_out(ex_illegal_instr_out),

        .ex_mem_read_out      (ex_mem_read_out),
        .ex_load_size_out     (ex_load_size_out),
        .ex_load_unsigned_out (ex_load_unsigned_out),
        .ex_wb_sel_mem_out    (ex_wb_sel_mem_out),

        .ex_csr_en_out       (ex_csr_en_out),
        .ex_csr_cmd_out      (ex_csr_cmd_out),
        .ex_csr_use_imm_out  (ex_csr_use_imm_out),
        .ex_csr_read_out     (ex_csr_read_out),
        .ex_csr_write_out    (ex_csr_write_out),

        .ex_sys_ecall_out   (ex_sys_ecall_out),
        .ex_sys_ebreak_out  (ex_sys_ebreak_out),
        .ex_sys_mret_out    (ex_sys_mret_out)
    );


 
    // =================================================================
    // EX: operand mux + ALU + branch_unit + lógica de redirección de PC 
    // =================================================================

    // Señales para lógica de forwarding en EX
    logic [1:0]  ex_fwd_rs1_sel;
    logic [1:0]  ex_fwd_rs2_sel;
    logic [63:0] ex_rs1_fwd_data;
    logic [63:0] ex_rs2_fwd_data;
    logic [63:0] mem_bypass_data;
    logic [63:0] wb_bypass_data;

    // Lógica de selección de datos para forwarding en EX (si se detecta que rs1 o rs2 necesitan ser forwardeados desde MEM o WB, se selecciona el dato correspondiente en lugar del dato leído desde regfile)
    logic [63:0] ex_alu_a;
    logic [63:0] ex_alu_b;
    logic [63:0] ex_alu_result;
    logic [63:0] ex_pc_plus4;
    logic [63:0] ex_redirect_target;
    logic        ex_take_pc_redirect;
    logic        ex_is_jalr;

    // Señales de control adicionales para traps y redirecciones desde EX
    logic        ex_target_misaligned;
    logic        ex_sync_trap;
    logic        ex_mret_redirect;
    logic [63:0] ex_trap_cause;
    logic [63:0] ex_trap_value;

    // Señales para operaciones con CSR en EX
    logic [11:0] ex_csr_addr;
    logic [63:0] ex_csr_wdata;
    logic [63:0] ex_csr_rdata;
    logic        ex_csr_illegal_access;
    logic        ex_effective_illegal_instr;
    logic [63:0] ex_result_to_pipe;

    // Mux para operando A de ALU (selecciona entre rs1, pc o cero)
    always_comb begin
        case (ex_alu_src_a_sel_out)                         // La selección de fuente A para ALU se controla por la señal decodificada ex_alu_src_a_sel_out, que puede indicar que el operando A viene de rs1, del PC, o es cero (dependiendo del tipo de instrucción)
            ALU_SRC_A_RS1:  ex_alu_a = ex_rs1_fwd_data;     // Operando A viene de rs1 (con posible forwarding)
            ALU_SRC_A_PC:   ex_alu_a = ex_pc_out;           // Operando A viene del PC (para instrucciones tipo AUIPC, JAL, etc.)
            ALU_SRC_A_ZERO: ex_alu_a = 64'd0;               // Operando A es cero (para instrucciones tipo LUI) 
            default:        ex_alu_a = 64'd0;               // Por defecto, se asigna cero para evitar latches (aunque idealmente no debería llegar un valor no válido a esta señal)
        endcase
    end

    // Mux para operando B de ALU (selecciona entre rs2 o inmediato)
    always_comb begin
        if (ex_alu_src_b_sel_out == ALU_SRC_B_IMM)  // Si la señal de selección de fuente B para ALU indica que el operando B es un inmediato, se selecciona el inmediato generado
            ex_alu_b = ex_imm_out;                  // Operando B viene de inmediato
        else
            ex_alu_b = ex_rs2_fwd_data;             // Operando B viene de rs2 (con posible forwarding)
    end

    // Módulo de ALU que toma los operandos A y B, la operación a realizar (decodificada) y produce el resultado de la operación (para operaciones aritméticas/lógicas)
    alu u_alu (
        .a      (ex_alu_a),         // Operando A para la ALU
        .b      (ex_alu_b),         // Operando B para la ALU
        .alu_op (ex_alu_op_out),    // Operación a realizar por la ALU (decodificada)
        .result (ex_alu_result)     // Resultado de la operación realizada por la ALU
    );

    // Módulo de branch unit que toma las señales de control de branch/jump, los datos de rs1 y rs2, y determina si se debe tomar la redirección de PC o no (para ramas condicionales) o si es un salto incondicional (JAL)
    branch_unit u_branch_unit (
        .branch           (ex_branch_out),      // Señal de control de branch
        .branch_op        (ex_branch_op_out),   // Operación de branch (ej. BEQ, BNE, etc.)
        .jump             (ex_jump_out),        // Señal de control de jump (JAL)
        .rs1_data         (ex_rs1_fwd_data),    // Datos de rs1
        .rs2_data         (ex_rs2_fwd_data),    // Datos de rs2
        .take_pc_redirect (ex_take_pc_redirect) // Señal de control para redirección de PC
    );

    // Cálculo de PC + 4 e target de redirección de PC para usar en caso de que se tome la redirección (branch tomado o salto)
    assign ex_pc_plus4       = ex_pc_out + 64'd4;
    assign ex_is_jalr        = 
        ex_jump_out &&
        (ex_alu_src_a_sel_out == ALU_SRC_A_RS1) &&  // Para identificar instrucciones JALR, que son las únicas instrucciones de salto que tienen como operando A el registro rs1 (en lugar del PC o cero como en otras instrucciones de salto)
        (ex_alu_src_b_sel_out == ALU_SRC_B_IMM) &&
        ex_wb_sel_pc4_out;                          // Para identificar instrucciones JALR, que son las únicas instrucciones de salto que tienen como target el resultado de la ALU en lugar de PC+4 (el target de JALR se calcula como rs1 + inmediato, mientras que el target de JAL se calcula como PC + inmediato)

    // JALR: target = rs1 + inmediato (con bit menos significativo forzado a cero)
    //JAL / branch: target = PC + inmediato
    assign ex_redirect_target = 
        ex_is_jalr ? {ex_alu_result[63:1], 1'b0} :   // Para instrucciones JALR, el target de redirección de PC se calcula como el resultado de la ALU (que corresponde a rs1 + inmediato), pero con el bit menos significativo forzado a cero para asegurar que la dirección sea par (requisito para instrucciones JALR)
                    ex_pc_out + ex_imm_out;           // Para instrucciones de branch y para JAL, el target de redirección de PC se calcula como PC + inmediato

    // IALIGN=32 en esta implementación: toda redirección tomada debe quedar alineada a 4 bytes
    assign ex_target_misaligned =
        ex_take_pc_redirect &&
        (ex_redirect_target[1:0] != 2'b00);

    assign ex_csr_addr  = ex_instr_out[31:20];
    assign ex_csr_wdata = ex_csr_use_imm_out ? {59'd0, ex_rs1_addr_out} : ex_rs1_fwd_data;

    // Módulo de archivo de registros de control (CSR) que maneja las instrucciones CSR, incluyendo lectura y escritura de CSRs, generación de traps síncronos para accesos ilegales a CSRs, y manejo de redirecciones de PC para traps y MRET
    // El módulo de CSR también expone las señales de salida de los CSRs relevantes (mtvec, mepc, mcause) para que puedan ser usados en la lógica de redirección de PC y en la generación de causa de trap en EX

    csr_file #(
        .RESET_MTVEC(TRAP_VECTOR)
    ) u_csr_file (
        .clk            (clk),
        .rst            (rst),

        .access_valid (
            ex_valid_out &&
            ex_csr_en_out &&
            !ex_illegal_instr_out &&
            ex_arch_side_effect_enable
        ),
        .access_addr    (ex_csr_addr),
        .access_read_en (ex_csr_read_out),
        .access_write_en(ex_csr_write_out),
        .access_cmd     (ex_csr_cmd_out),
        .access_wdata   (ex_csr_wdata),

        .access_rdata   (ex_csr_rdata),
        .access_illegal (ex_csr_illegal_access),

        .trap_valid     (trap_taken_valid),
        .trap_pc        (trap_taken_pc),
        .trap_cause     (trap_taken_cause),
        .trap_value     (trap_taken_value),

        // Si hay trap más antiguo en MEM, no permitimos que un MRET más joven
        // en EX modifique el estado de CSRs en el mismo ciclo.
        .mret_valid (
            ex_mret_redirect &&
            ex_arch_side_effect_enable &&
            !mem_sync_trap
        ),

        .mtvec_o        (csr_mtvec),
        .mepc_o         (csr_mepc),
        .mcause_o       (csr_mcause),
        .mtval_o        (csr_mtval)
    );
    // La señal de instrucción ilegal efectiva en EX se genera combinando la señal de instrucción ilegal decodificada (que indica que la instrucción no es reconocida por el decoder) con la señal de acceso ilegal a CSR (que indica que se ha intentado acceder a un CSR de manera no permitida, por ejemplo, escribiendo a un CSR de solo lectura o leyendo un CSR que no existe)
    assign ex_effective_illegal_instr =
        ex_illegal_instr_out ||
        (ex_valid_out && ex_csr_en_out && ex_csr_illegal_access);
    // El resultado que se pasa hacia MEM/WB desde EX para instrucciones que escriben en rd (ya sea el resultado de la ALU o el dato leído desde un CSR, dependiendo del tipo de instrucción) se selecciona entre el resultado de la ALU o el dato leído desde el CSR en función de si la instrucción es una instrucción CSR o no (controlado por ex_csr_en_out)
    assign ex_result_to_pipe =
        ex_csr_en_out ? ex_csr_rdata : ex_alu_result;
    
    // Cálculo de causa de trap en EX para instrucciones ilegales, redirecciones de PC con target no alineado, y ECALL/EBREAK válidos (que no sean ilegales)
    always_comb begin
        ex_trap_cause = 64'd0;

        if (ex_effective_illegal_instr)
            ex_trap_cause = MCAUSE_ILLEGAL_INSTR;
        else if (ex_target_misaligned)
            ex_trap_cause = MCAUSE_INSTR_ADDR_MISALIGNED;
        else if (ex_sys_ecall_out)
            ex_trap_cause = MCAUSE_ECALL_M;
        else if (ex_sys_ebreak_out)
            ex_trap_cause = MCAUSE_BREAKPOINT;
    end

    // ---------------------------------------------------------
    // Valor informativo para mtval en traps detectados en EX.
    //
    // Política implementada:
    // - illegal instruction:
    //     bits de la instrucción causante, zero-extended a XLEN
    //
    // - instruction address misaligned:
    //     target de control-flow desalineado
    //
    // - ECALL:
    //     mtval = 0
    //
    // - EBREAK:
    //     mtval = 0
    //     La especificación también permite usar el PC, pero
    //     elegimos cero porque mepc ya contiene esa dirección.
    // ---------------------------------------------------------
    always_comb begin
        ex_trap_value = 64'd0;

        if (ex_effective_illegal_instr) begin
            ex_trap_value = {32'd0, ex_instr_out};
        end
        else if (ex_target_misaligned) begin
            ex_trap_value = ex_redirect_target;
        end
        else if (ex_sys_ecall_out) begin
            ex_trap_value = 64'd0;
        end
        else if (ex_sys_ebreak_out) begin
            ex_trap_value = 64'd0;
        end
    end

    // Señal de trap síncrono que se genera en EX cuando se detecta una instrucción ilegal, una redirección de PC con target no alineado, o una instrucción ECALL/EBREAK válida (que no sea ilegal)
    assign ex_sync_trap =
        ex_valid_out &&
        (
            ex_effective_illegal_instr ||
            ex_target_misaligned ||
            ex_sys_ecall_out ||
            ex_sys_ebreak_out
        );

    // Señal de redirección de PC específica para MRET, que se genera en EX cuando se detecta una instrucción MRET válida (que no sea ilegal) y que se usa para indicar que el target de redirección de PC para MRET debe ser el valor de mepc (en lugar del target calculado para branches/jumps)
    assign ex_mret_redirect =
        ex_valid_out &&
        ex_sys_mret_out &&
        !ex_effective_illegal_instr;

    // Redirección de PC resuelta en EX (para ramas tomadas o saltos) que genera un flush hacia IF/ID e ID/EX para eliminar las instrucciones que se hayan podido fetchar o decodificar incorrectamente debido a la redirección de PC
    // Mientras una instrucción más antigua espera en MEM por exp_ready,
    // no se permite que una instrucción más joven en EX redirija el PC.
    assign control_redirect =
        trap_taken_valid ||
        (
            !mem_exp_wait_stall &&
            (
                ex_mret_redirect ||
                ex_take_pc_redirect
            )
        );

    assign if_id_flush = control_redirect;

    assign id_ex_flush =
        control_redirect ||
        data_hazard_stall;

    // Si el trap viene desde MEM, también hay que eliminar la instrucción
    // más joven que está en EX para que no avance a MEM.
    assign ex_mem_flush =
        trap_taken_valid ||
        (!mem_exp_wait_stall && ex_mret_redirect);

    // =========================================================
    // PC register con lógica de actualización basada en redirección de PC desde EX y cálculo de PC + 4 en IF 
    // =========================================================
    
    logic [63:0] csr_mtvec_aligned;
    logic [63:0] csr_mepc_aligned;

    assign csr_mtvec_aligned = {csr_mtvec[63:2], 2'b00};
    assign csr_mepc_aligned  = {csr_mepc[63:2],  2'b00};
    
    always_comb begin
        if (trap_taken_valid)
            pc_next = csr_mtvec_aligned;
        else if (ex_mret_redirect)
            pc_next = csr_mepc_aligned;
        else if (ex_take_pc_redirect)
            pc_next = ex_redirect_target;
        else
            pc_next = pc_plus4_if;
    end

    // Registro de PC que se actualiza en cada ciclo de reloj con el valor calculado en la lógica combinacional anterior, y que también se resetea al valor de RESET_PC cuando se activa el reset
    always_ff @(posedge clk) begin
        if (rst) begin
            pc_reg <= RESET_PC;
        end
        else if (!pipeline_stall) begin
            pc_reg <= pc_next;
        end
    end

    // =========================================================
    // EX/MEM registros con lógica de stall y flush 
    // =========================================================
    logic        mem_valid_out;
    logic [63:0] mem_pc_out;
    logic [31:0] mem_instr_out;

    logic [4:0]  mem_rd_addr_out;

    logic [63:0] mem_alu_result_out;
    logic [63:0] mem_store_data_out;
    logic [63:0] mem_pc_plus4_out;

    logic        mem_mem_read_out;
    logic [1:0]  mem_load_size_out;
    logic        mem_load_unsigned_out;
    logic        mem_wb_sel_mem_out;

    logic        mem_reg_write_out;
    logic        mem_mem_write_out;
    logic [1:0]  mem_store_size_out;
    logic        mem_wb_sel_pc4_out;

    logic        mem_illegal_instr_out;

    // Registros EX/MEM con lógica de stall y flush que pasan las señales desde EX hacia MEM (y también hacia WB para las señales que necesitan llegar hasta esa etapa)
    ex_mem_reg u_ex_mem_reg (
        .clk                 (clk),
        .rst                 (rst),
        .stall               (ex_mem_stall),
        .flush               (ex_mem_flush),

        .ex_valid_in         (ex_valid_out),
        .ex_pc_in            (ex_pc_out),
        .ex_instr_in         (ex_instr_out),

        .ex_rd_addr_in       (ex_rd_addr_out),

        .ex_alu_result_in    (ex_result_to_pipe),
        .ex_store_data_in    (ex_rs2_fwd_data),
        .ex_pc_plus4_in      (ex_pc_plus4),

        .ex_reg_write_in     (ex_reg_write_out),
        .ex_mem_write_in     (ex_mem_write_out),
        .ex_store_size_in    (ex_store_size_out),
        .ex_wb_sel_pc4_in    (ex_wb_sel_pc4_out),

        .ex_illegal_instr_in (ex_illegal_instr_out),

        .ex_mem_read_in      (ex_mem_read_out),
        .ex_load_size_in     (ex_load_size_out),
        .ex_load_unsigned_in (ex_load_unsigned_out),
        .ex_wb_sel_mem_in    (ex_wb_sel_mem_out),

        .mem_valid_out       (mem_valid_out),
        .mem_pc_out          (mem_pc_out),
        .mem_instr_out       (mem_instr_out),

        .mem_rd_addr_out     (mem_rd_addr_out),

        .mem_alu_result_out  (mem_alu_result_out),
        .mem_store_data_out  (mem_store_data_out),
        .mem_pc_plus4_out    (mem_pc_plus4_out),

        .mem_reg_write_out   (mem_reg_write_out),
        .mem_mem_write_out   (mem_mem_write_out),
        .mem_store_size_out  (mem_store_size_out),
        .mem_wb_sel_pc4_out  (mem_wb_sel_pc4_out),

        .mem_illegal_instr_out(mem_illegal_instr_out),

        .mem_mem_read_out      (mem_mem_read_out),
        .mem_load_size_out     (mem_load_size_out),
        .mem_load_unsigned_out (mem_load_unsigned_out),
        .mem_wb_sel_mem_out    (mem_wb_sel_mem_out)
    );


    // =========================================================
    // MEM: stores + loads
    // Convención de esta iteración:
    // - dmem_rdata devuelve la línea alineada de 64 bits que contiene dmem_addr
    // - el core selecciona byte/half/word usando dmem_addr[2:0]
    // - los accesos desalineados generan una excepción arquitectural en MEM
    // - un acceso desalineado no se envía al puerto de expansión ni escribe dmem
    // =========================================================
    logic [63:0] mem_rdata_shifted;
    logic [63:0] mem_load_data;
    logic [63:0] mem_store_wdata_aligned;
    logic [7:0]  mem_store_wstrb;

    logic        mem_access_active;
    logic        mem_is_exp_region;
    logic        mem_is_exp_access;
    logic        mem_is_dmem_access;
    logic [63:0] mem_selected_rdata;

    // Señales de control de trap y excepciones en MEM
    logic        mem_load_misaligned;
    logic        mem_store_misaligned;
    logic        mem_addr_misaligned;
    logic        mem_exp_access_fault;

    logic [2:0]  mem_addr_offset;
    logic [5:0]  mem_shift_bits;

    logic [7:0]  mem_load_byte;
    logic [15:0] mem_load_half;
    logic [31:0] mem_load_word;

    logic [63:0] mem_load_byte_unsigned_data;
    logic [63:0] mem_load_byte_signed_data;
    logic [63:0] mem_load_half_unsigned_data;
    logic [63:0] mem_load_half_signed_data;
    logic [63:0] mem_load_word_unsigned_data;
    logic [63:0] mem_load_word_signed_data;

    logic [7:0]  mem_store_byte_wstrb;
    logic [7:0]  mem_store_half_wstrb;
    logic [7:0]  mem_store_word_wstrb;

    logic [63:0] mem_store_byte_data_aligned;
    logic [63:0] mem_store_half_data_aligned;
    logic [63:0] mem_store_word_data_aligned;

    assign mem_addr_offset = mem_alu_result_out[2:0];
    assign mem_shift_bits  = {mem_addr_offset, 3'b000};

    // Decodificación de región de expansión.
    // mem_access_active solo se activa para loads/stores válidos que llegaron a MEM.
    assign mem_access_active =
        mem_valid_out &&
        (mem_mem_read_out || mem_mem_write_out) &&
        !mem_illegal_instr_out;

    // ---------------------------------------------------------
    // Comprobación de alineamiento natural.
    //
    // size = 00 -> byte       : cualquier dirección
    // size = 01 -> halfword   : addr[0]   debe ser 0
    // size = 10 -> word       : addr[1:0] debe ser 00
    // size = 11 -> doubleword : addr[2:0] debe ser 000
    // ---------------------------------------------------------
    always_comb begin
        mem_load_misaligned = 1'b0;

        if (mem_access_active && mem_mem_read_out) begin
            case (mem_load_size_out)
                2'b00:   mem_load_misaligned = 1'b0;
                2'b01:   mem_load_misaligned = mem_alu_result_out[0];
                2'b10:   mem_load_misaligned = |mem_alu_result_out[1:0];
                2'b11:   mem_load_misaligned = |mem_alu_result_out[2:0];
                default: mem_load_misaligned = 1'b0;
            endcase
        end
    end

    always_comb begin
        mem_store_misaligned = 1'b0;

        if (mem_access_active && mem_mem_write_out) begin
            case (mem_store_size_out)
                2'b00:   mem_store_misaligned = 1'b0;
                2'b01:   mem_store_misaligned = mem_alu_result_out[0];
                2'b10:   mem_store_misaligned = |mem_alu_result_out[1:0];
                2'b11:   mem_store_misaligned = |mem_alu_result_out[2:0];
                default: mem_store_misaligned = 1'b0;
            endcase
        end
    end

    assign mem_addr_misaligned =
        mem_load_misaligned ||
        mem_store_misaligned;

    assign mem_is_exp_region =
        ((mem_alu_result_out & EXP_MASK) == (EXP_BASE & EXP_MASK));

    assign mem_is_exp_access =
        mem_access_active &&
        !mem_addr_misaligned &&
        mem_is_exp_region;

    assign mem_is_dmem_access =
        mem_access_active &&
        !mem_addr_misaligned &&
        !mem_is_exp_region;

    // Un error reportado por el periférico de expansión se convierte en
    // excepción arquitectural. La instrucción causante está en MEM, por lo
    // que mepc debe recibir mem_pc_out.
    // Si el acceso MMIO todavía no terminó, exp_error/exp_rdata no se consideran válidos.
    assign mem_exp_wait_stall =
        mem_is_exp_access &&
        !exp_ready;

    assign mem_exp_access_fault =
        mem_is_exp_access &&
        exp_ready &&
        exp_error;

    assign mem_sync_trap =
        mem_addr_misaligned ||
        mem_exp_access_fault;

    always_comb begin
        mem_trap_cause = 64'd0;

        if (mem_load_misaligned) begin
            mem_trap_cause = MCAUSE_LOAD_ADDR_MISALIGNED;
        end
        else if (mem_store_misaligned) begin
            mem_trap_cause = MCAUSE_STORE_ADDR_MISALIGNED;
        end
        else if (mem_exp_access_fault && mem_mem_read_out) begin
            mem_trap_cause = MCAUSE_LOAD_ACCESS_FAULT;
        end
        else if (mem_exp_access_fault && mem_mem_write_out) begin
            mem_trap_cause = MCAUSE_STORE_ACCESS_FAULT;
        end
    end

    // ---------------------------------------------------------
    // Valor informativo para mtval en traps de memoria.
    //
    // Todos los traps que actualmente pueden originarse en MEM
    // están asociados con el acceso efectivo mem_alu_result_out:
    //
    // - load address misaligned
    // - store address misaligned
    // - load access fault desde expansión/MMIO
    // - store access fault desde expansión/MMIO
    // ---------------------------------------------------------
    always_comb begin
        mem_trap_value = 64'd0;

        if (mem_addr_misaligned) begin
            mem_trap_value = mem_alu_result_out;
        end
        else if (mem_exp_access_fault) begin
            mem_trap_value = mem_alu_result_out;
        end
    end

    // MEM tiene prioridad sobre EX. Además, mientras MEM espera exp_ready,
    // no se permite tomar traps más jóvenes desde EX.
    assign trap_taken_valid =
        mem_sync_trap ||
        (!mem_exp_wait_stall && ex_sync_trap);

    assign trap_taken_pc =
        mem_sync_trap ? mem_pc_out : ex_pc_out;

    assign trap_taken_cause =
        mem_sync_trap ? mem_trap_cause : ex_trap_cause;

    assign trap_taken_value =
        mem_sync_trap ? mem_trap_value : ex_trap_value;

    // Para loads, el dato puede venir de memoria normal o del puerto de expansión.
    assign mem_selected_rdata =
        mem_is_exp_access ? exp_rdata : dmem_rdata;

    assign mem_rdata_shifted = mem_selected_rdata >> mem_shift_bits;

    assign mem_load_byte = mem_rdata_shifted[7:0];
    assign mem_load_half = mem_rdata_shifted[15:0];
    assign mem_load_word = mem_rdata_shifted[31:0];

    assign mem_load_byte_unsigned_data = {56'd0, mem_load_byte};
    assign mem_load_byte_signed_data   = {{56{mem_load_byte[7]}}, mem_load_byte};

    assign mem_load_half_unsigned_data = {48'd0, mem_load_half};
    assign mem_load_half_signed_data   = {{48{mem_load_half[15]}}, mem_load_half};

    assign mem_load_word_unsigned_data = {32'd0, mem_load_word};
    assign mem_load_word_signed_data   = {{32{mem_load_word[31]}}, mem_load_word};

    assign mem_store_byte_wstrb = 8'b00000001 << mem_addr_offset;
    assign mem_store_half_wstrb = 8'b00000011 << mem_addr_offset;
    assign mem_store_word_wstrb = 8'b00001111 << mem_addr_offset;

    assign mem_store_byte_data_aligned = {56'd0, mem_store_data_out[7:0]}  << mem_shift_bits;
    assign mem_store_half_data_aligned = {48'd0, mem_store_data_out[15:0]} << mem_shift_bits;
    assign mem_store_word_data_aligned = {32'd0, mem_store_data_out[31:0]} << mem_shift_bits;

    always_comb begin
        case (mem_store_size_out)
            2'b00:   mem_store_wstrb = mem_store_byte_wstrb;
            2'b01:   mem_store_wstrb = mem_store_half_wstrb;
            2'b10:   mem_store_wstrb = mem_store_word_wstrb;
            default: mem_store_wstrb = 8'b11111111;
        endcase

        case (mem_store_size_out)
            2'b00:   mem_store_wdata_aligned = mem_store_byte_data_aligned;
            2'b01:   mem_store_wdata_aligned = mem_store_half_data_aligned;
            2'b10:   mem_store_wdata_aligned = mem_store_word_data_aligned;
            default: mem_store_wdata_aligned = mem_store_data_out;
        endcase

        case (mem_load_size_out)
            2'b00: begin
                mem_load_data = mem_load_unsigned_out
                                ? mem_load_byte_unsigned_data
                                : mem_load_byte_signed_data;
            end

            2'b01: begin
                mem_load_data = mem_load_unsigned_out
                                ? mem_load_half_unsigned_data
                                : mem_load_half_signed_data;
            end

            2'b10: begin
                mem_load_data = mem_load_unsigned_out
                                ? mem_load_word_unsigned_data
                                : mem_load_word_signed_data;
            end

            default: begin
                mem_load_data = mem_rdata_shifted;
            end
        endcase
    end

    assign dmem_we    = mem_is_dmem_access && mem_mem_write_out && !mem_sync_trap;
    assign dmem_addr  = mem_alu_result_out;
    assign dmem_wdata = mem_store_wdata_aligned;
    assign dmem_wstrb = dmem_we ? mem_store_wstrb : 8'b0;
    assign dmem_size  = mem_is_dmem_access
                        ? (mem_mem_write_out ? mem_store_size_out :
                        mem_mem_read_out  ? mem_load_size_out  : 2'b00)
                        : 2'b00;

    // Para MMIO mantenemos exp_valid/exp_we activos durante el ciclo del acceso,
    // incluso si exp_error sube. El periférico es quien reporta el error y debe
    // evitar efectos internos no permitidos. El core convierte ese error en trap.
    assign exp_valid = mem_is_exp_access;
    assign exp_we    = mem_is_exp_access && mem_mem_write_out;
    assign exp_addr  = mem_alu_result_out;
    assign exp_wdata = mem_store_wdata_aligned;
    assign exp_wstrb = exp_we ? mem_store_wstrb : 8'b0;
    assign exp_size  = mem_is_exp_access
                    ? (mem_mem_write_out ? mem_store_size_out :
                        mem_mem_read_out  ? mem_load_size_out  : 2'b00)
                    : 2'b00;


    // =========================================================
    // MEM/WB registros con lógica de stall y flush
    // =========================================================
    logic        wb_valid_out;
    logic [63:0] wb_pc_out;
    logic [31:0] wb_instr_out;

    logic [4:0]  wb_rd_addr_out;

    logic [63:0] wb_alu_result_out;
    logic [63:0] wb_pc_plus4_out;

    logic        wb_reg_write_out;
    logic        wb_wb_sel_pc4_out;

    logic [63:0] wb_load_data_out;
    logic        wb_wb_sel_mem_out;

    logic        wb_illegal_instr_out;

    mem_wb_reg u_mem_wb_reg (
        .clk                 (clk),
        .rst                 (rst),
        .stall               (mem_wb_stall),
        .flush               (mem_wb_flush),

        .mem_valid_in        (mem_valid_out),
        .mem_pc_in           (mem_pc_out),
        .mem_instr_in        (mem_instr_out),

        .mem_rd_addr_in      (mem_rd_addr_out),

        .mem_alu_result_in   (mem_alu_result_out),
        .mem_pc_plus4_in     (mem_pc_plus4_out),

        .mem_reg_write_in    (mem_reg_write_out),
        .mem_wb_sel_pc4_in   (mem_wb_sel_pc4_out),

        .mem_illegal_instr_in(mem_illegal_instr_out),

        .mem_load_data_in    (mem_load_data),
        .mem_wb_sel_mem_in   (mem_wb_sel_mem_out),

        .wb_valid_out        (wb_valid_out),
        .wb_pc_out           (wb_pc_out),
        .wb_instr_out        (wb_instr_out),

        .wb_rd_addr_out      (wb_rd_addr_out),

        .wb_alu_result_out   (wb_alu_result_out),
        .wb_pc_plus4_out     (wb_pc_plus4_out),

        .wb_reg_write_out    (wb_reg_write_out),
        .wb_wb_sel_pc4_out   (wb_wb_sel_pc4_out),

        .wb_illegal_instr_out(wb_illegal_instr_out),
        
        .wb_load_data_out    (wb_load_data_out),
        .wb_wb_sel_mem_out   (wb_wb_sel_mem_out)
    );



    // =========================================================
    // Hazard unit mínima: forwarding hacia EX
    // =========================================================

    // Lógica de selección de datos para forwarding en EX (si se detecta que rs1 o rs2 necesitan ser forwardeados desde MEM o WB, se selecciona el dato correspondiente en lugar del dato leído desde regfile)
    assign mem_bypass_data = mem_wb_sel_pc4_out ? mem_pc_plus4_out :
                             mem_wb_sel_mem_out ? mem_load_data    :
                                                  mem_alu_result_out;

    assign wb_bypass_data  = wb_wb_sel_pc4_out  ? wb_pc_plus4_out  :
                             wb_wb_sel_mem_out  ? wb_load_data_out :
                                                  wb_alu_result_out;

    hazard_unit u_hazard_unit (
        .ex_rs1_addr      (ex_rs1_addr_out),
        .ex_rs2_addr      (ex_rs2_addr_out),

        .mem_valid        (mem_valid_out),
        .mem_reg_write    (mem_reg_write_out),
        .mem_rd_addr      (mem_rd_addr_out),
        .mem_illegal_instr(mem_illegal_instr_out),

        .wb_valid         (wb_valid_out),
        .wb_reg_write     (wb_reg_write_out),
        .wb_rd_addr       (wb_rd_addr_out),
        .wb_illegal_instr (wb_illegal_instr_out),

        .fwd_rs1_sel      (ex_fwd_rs1_sel),
        .fwd_rs2_sel      (ex_fwd_rs2_sel),
        .mem_wb_sel_mem  (mem_wb_sel_mem_out)
    );

    always_comb begin
        case (ex_fwd_rs1_sel)
            FWD_MEM: ex_rs1_fwd_data = mem_bypass_data;
            FWD_WB:  ex_rs1_fwd_data = wb_bypass_data;
            default: ex_rs1_fwd_data = ex_rs1_data_out;
        endcase
    end

    always_comb begin
        case (ex_fwd_rs2_sel)
            FWD_MEM: ex_rs2_fwd_data = mem_bypass_data;
            FWD_WB:  ex_rs2_fwd_data = wb_bypass_data;
            default: ex_rs2_fwd_data = ex_rs2_data_out;
        endcase
    end



    // =========================================================
    // WB: lógica de selección de dato para writeback y generación de señales de control para regfile
    // =========================================================
    always_comb begin
        if (wb_wb_sel_pc4_out)
            wb_commit_rd_data = wb_pc_plus4_out;
        else if (wb_wb_sel_mem_out)
            wb_commit_rd_data = wb_load_data_out;
        else
            wb_commit_rd_data = wb_alu_result_out;
    end

    // La señal de control de escritura en regfile para la etapa de WB se activa cuando la instrucción es válida, es una instrucción que escribe en registro, y no es una instrucción ilegal
    assign wb_commit_we      = wb_valid_out && wb_reg_write_out && !wb_illegal_instr_out;
    assign wb_commit_rd_addr = wb_rd_addr_out;

    // ---------------------------------------------------------
    // Señales reservadas para debug / uso futuro.
    // Se agregan aquí para evitar warning UNUSEDSIGNAL.
    // ---------------------------------------------------------
    wire _unused_ok = 1'b0 && &{
        1'b0,
        wb_pc_out,
        wb_instr_out,
        csr_mcause,
        csr_mtval,
        csr_mtvec[1:0],
        csr_mepc[1:0],
        exp_ready,
        1'b0
    };

endmodule

