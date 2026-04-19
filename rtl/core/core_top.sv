`timescale 1ns/1ps

module core_top #(
    parameter logic [63:0] RESET_PC = 64'd0,
    parameter logic [63:0] TRAP_VECTOR = 64'h0000_0000_0000_0100
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
    output logic [1:0]  dmem_size   // tamaño de la operación de memoria (00=byte, 01=halfword, 10=word, 11=doubleword)
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
    localparam logic [63:0] MCAUSE_ECALL_M               = 64'd11;


    // =========================================================
    // CSRs mínimos internos para traps
    // =========================================================
    logic [63:0] csr_mtvec;
    logic [63:0] csr_mepc;
    logic [63:0] csr_mcause;

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

    assign if_id_stall  = load_use_hazard;      // Si hay un hazard de tipo load-use, se hace stall hacia IF/ID para esperar a que el dato cargado esté disponible en EX/MEM
    assign id_ex_stall  = 1'b0;
    assign ex_mem_stall = 1'b0;
    assign mem_wb_stall = 1'b0;

    assign mem_wb_flush = 1'b0; // El flush hacia MEM/WB se controla desde ID/EX (por ahora no hay flushes específicos para MEM/WB)



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

        .access_valid   (ex_valid_out && ex_csr_en_out && !ex_illegal_instr_out),
        .access_addr    (ex_csr_addr),
        .access_read_en (ex_csr_read_out),
        .access_write_en(ex_csr_write_out),
        .access_cmd     (ex_csr_cmd_out),
        .access_wdata   (ex_csr_wdata),

        .access_rdata   (ex_csr_rdata),
        .access_illegal (ex_csr_illegal_access),

        .trap_valid     (ex_sync_trap),
        .trap_pc        (ex_pc_out),
        .trap_cause     (ex_trap_cause),

        .mret_valid     (ex_mret_redirect),

        .mtvec_o        (csr_mtvec),
        .mepc_o         (csr_mepc),
        .mcause_o       (csr_mcause)
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
    assign if_id_flush =
        ex_sync_trap ||
        ex_mret_redirect ||
        ex_take_pc_redirect;

    assign id_ex_flush =
        ex_sync_trap ||
        ex_mret_redirect ||
        ex_take_pc_redirect ||
        load_use_hazard;

    // En trap o MRET no queremos que la instrucción actual llegue a MEM/WB
    assign ex_mem_flush =
        ex_sync_trap ||
        ex_mret_redirect;   // Si se toma la redirección de PC, se hace flush hacia ID/EX para eliminar la instrucción que se haya podido decodificar incorrectamente; además, si hay un hazard de tipo load-use, también se hace flush hacia ID/EX para eliminar la instrucción que está causando el hazard y que no debería ejecutarse

    // =========================================================
    // PC register con lógica de actualización basada en redirección de PC desde EX y cálculo de PC + 4 en IF 
    // =========================================================
    always_comb begin
        if (ex_sync_trap)
            pc_next = {csr_mtvec[63:2], 2'b00};
        else if (ex_mret_redirect)
            pc_next = {csr_mepc[63:2], 2'b00};
        else if (ex_take_pc_redirect)
            pc_next = ex_redirect_target;
        else
            pc_next = pc_plus4_if;
    end

    // Registro de PC que se actualiza en cada ciclo de reloj con el valor calculado en la lógica combinacional anterior, y que también se resetea al valor de RESET_PC cuando se activa el reset
    always_ff @(posedge clk) begin
        if (rst)                    // Si se activa el reset, el PC se resetea al valor de RESET_PC
            pc_reg <= RESET_PC;
        else if (!load_use_hazard)
            pc_reg <= pc_next;      // En cada ciclo de reloj, el PC se actualiza con el valor calculado en la lógica combinacional anterior
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
    // - por ahora asumimos accesos naturalmente alineados
    // =========================================================
    logic [63:0] mem_rdata_shifted;
    logic [63:0] mem_load_data;
    logic [63:0] mem_store_wdata_aligned;
    logic [7:0]  mem_store_wstrb;

    assign mem_rdata_shifted = dmem_rdata >> (8 * mem_alu_result_out[2:0]);

    always_comb begin
        case (mem_store_size_out)
            2'b00: mem_store_wstrb = 8'b00000001 << mem_alu_result_out[2:0];
            2'b01: mem_store_wstrb = 8'b00000011 << mem_alu_result_out[2:0];
            2'b10: mem_store_wstrb = 8'b00001111 << mem_alu_result_out[2:0];
            default: mem_store_wstrb = 8'b11111111;
        endcase

        case (mem_store_size_out)
            2'b00: mem_store_wdata_aligned = ({56'd0, mem_store_data_out[7:0]})   << (8 * mem_alu_result_out[2:0]);
            2'b01: mem_store_wdata_aligned = ({48'd0, mem_store_data_out[15:0]})  << (8 * mem_alu_result_out[2:0]);
            2'b10: mem_store_wdata_aligned = ({32'd0, mem_store_data_out[31:0]})  << (8 * mem_alu_result_out[2:0]);
            default: mem_store_wdata_aligned = mem_store_data_out;
        endcase

        case (mem_load_size_out)
            2'b00: mem_load_data = mem_load_unsigned_out
                                   ? {56'd0, mem_rdata_shifted[7:0]}
                                   : {{56{mem_rdata_shifted[7]}}, mem_rdata_shifted[7:0]};

            2'b01: mem_load_data = mem_load_unsigned_out
                                   ? {48'd0, mem_rdata_shifted[15:0]}
                                   : {{48{mem_rdata_shifted[15]}}, mem_rdata_shifted[15:0]};

            2'b10: mem_load_data = mem_load_unsigned_out
                                   ? {32'd0, mem_rdata_shifted[31:0]}
                                   : {{32{mem_rdata_shifted[31]}}, mem_rdata_shifted[31:0]};

            default: mem_load_data = mem_rdata_shifted; // LD
        endcase
    end

    assign dmem_we    = mem_valid_out && mem_mem_write_out && !mem_illegal_instr_out;
    assign dmem_addr  = mem_alu_result_out;
    assign dmem_wdata = mem_store_wdata_aligned;
    assign dmem_wstrb = dmem_we ? mem_store_wstrb : 8'b0;
    assign dmem_size  = mem_mem_write_out ? mem_store_size_out :
                        mem_mem_read_out  ? mem_load_size_out  : 2'b00;


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
        csr_mtvec[1:0],
        csr_mepc[1:0],
        1'b0
    };

endmodule

