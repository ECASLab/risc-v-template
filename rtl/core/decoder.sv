`timescale 1ns/1ps

// Decoder de instrucciones RISC-V
// Toma una instrucción de 32 bits y genera las señales de control necesarias para ejecutar
module decoder (
    input  logic [31:0] instr,

    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic [4:0]  rd_addr,

    output logic [2:0]  imm_sel,

    output logic        reg_write,
    output logic        mem_write,
    output logic [1:0]  store_size,

    output logic        mem_read,
    output logic [1:0]  load_size,
    output logic        load_unsigned,
    output logic        wb_sel_mem,

    output logic        csr_en,
    output logic [1:0]  csr_cmd,
    output logic        csr_use_imm,
    output logic        csr_read,
    output logic        csr_write,

    output logic        rs1_used,
    output logic        rs2_used,

    output logic        wb_sel_pc4,

    output logic [1:0]  alu_src_a_sel,
    output logic        alu_src_b_sel,
    output logic [3:0]  alu_op,

    output logic        branch,
    output logic [2:0]  branch_op,
    output logic        jump,

    output logic        illegal_instr,

    // Señales para instrucciones de sistema (ECALL, EBREAK, MRET)
    output logic        sys_ecall,
    output logic        sys_ebreak,
    output logic        sys_mret
);

    // -----------------------------
    // Campos de la instrucción (Extrae los campos fijos de la instrucción)
    // -----------------------------
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [5:0] funct6;

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];
    assign funct6   = instr[31:26];   // útil para shifts inmediatos RV64I

    // -----------------------------
    // Códigos de imm_sel
    // Deben coincidir con imm_gen.sv
    // -----------------------------
    localparam logic [2:0] IMM_NONE = 3'b000;
    localparam logic [2:0] IMM_I    = 3'b001;
    localparam logic [2:0] IMM_B    = 3'b010;
    localparam logic [2:0] IMM_U    = 3'b011;
    localparam logic [2:0] IMM_S    = 3'b100;
    localparam logic [2:0] IMM_J    = 3'b101;

    // -----------------------------
    // Selectores de ALU
    // -----------------------------
    localparam logic [1:0] ALU_SRC_A_RS1  = 2'b00;
    localparam logic [1:0] ALU_SRC_A_PC   = 2'b01;
    localparam logic [1:0] ALU_SRC_A_ZERO = 2'b10;

    localparam logic       ALU_SRC_B_RS2  = 1'b0;
    localparam logic       ALU_SRC_B_IMM  = 1'b1;

    // -----------------------------
    // Operaciones de ALU
    // -----------------------------
    localparam logic [3:0] ALU_ADD    = 4'd0;
    localparam logic [3:0] ALU_SUB    = 4'd1;
    localparam logic [3:0] ALU_AND    = 4'd2;
    localparam logic [3:0] ALU_OR     = 4'd3;
    localparam logic [3:0] ALU_XOR    = 4'd4;
    localparam logic [3:0] ALU_SLL    = 4'd5;
    localparam logic [3:0] ALU_SRL    = 4'd6;
    localparam logic [3:0] ALU_SRA    = 4'd7;
    localparam logic [3:0] ALU_PASS_B = 4'd8;
    localparam logic [3:0] ALU_SLT    = 4'd9;
    localparam logic [3:0] ALU_SLTU   = 4'd10;

    // Operaciones RV64I de palabra (32 bits con sign-extension a 64 bits)
    localparam logic [3:0] ALU_ADDW   = 4'd11;
    localparam logic [3:0] ALU_SUBW   = 4'd12;
    localparam logic [3:0] ALU_SLLW   = 4'd13;
    localparam logic [3:0] ALU_SRLW   = 4'd14;
    localparam logic [3:0] ALU_SRAW   = 4'd15;

    // -----------------------------
    // Tipos de branch (para controlar la lógica de decisión de las instrucciones de salto condicional)
    // -----------------------------
    localparam logic [2:0] BR_NONE = 3'b000;
    localparam logic [2:0] BR_EQ   = 3'b001;
    localparam logic [2:0] BR_NE   = 3'b010;
    localparam logic [2:0] BR_LT   = 3'b011;
    localparam logic [2:0] BR_GE   = 3'b100;
    localparam logic [2:0] BR_LTU  = 3'b101;
    localparam logic [2:0] BR_GEU  = 3'b110;

    // -----------------------------
    // Tamaños de load/store (para controlar el acceso a memoria y el manejo de datos)
    // -----------------------------
    localparam logic [1:0] STORE_B = 2'b00;
    localparam logic [1:0] STORE_H = 2'b01;
    localparam logic [1:0] STORE_W = 2'b10;
    localparam logic [1:0] STORE_D = 2'b11;

    // -----------------------------
    // Opcodes usados en esta etapa
    // -----------------------------
    localparam logic [6:0] OPCODE_LUI       = 7'b0110111;
    localparam logic [6:0] OPCODE_AUIPC     = 7'b0010111;
    localparam logic [6:0] OPCODE_JAL       = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR      = 7'b1100111;
    localparam logic [6:0] OPCODE_OP_IMM    = 7'b0010011;
    localparam logic [6:0] OPCODE_OP_IMM_32 = 7'b0011011;   // RV64I: ADDIW/SLLIW/SRLIW/SRAIW
    localparam logic [6:0] OPCODE_OP        = 7'b0110011;
    localparam logic [6:0] OPCODE_OP_32     = 7'b0111011;   // RV64I: ADDW/SUBW/SLLW/SRLW/SRAW
    localparam logic [6:0] OPCODE_BRANCH    = 7'b1100011;
    localparam logic [6:0] OPCODE_STORE     = 7'b0100011;
    localparam logic [6:0] OPCODE_LOAD      = 7'b0000011;
    localparam logic [6:0] OPCODE_MISC_MEM  = 7'b0001111;   // No se decodifican instrucciones de esta categoría, pero se podría usar para FENCE/FENCE.I
    localparam logic [6:0] OPCODE_SYSTEM    = 7'b1110011;   // ECALL, EBREAK, MRET, etc.

    // -----------------------------
    // Comandos CSR
    // 00 = none
    // 01 = RW
    // 10 = RS
    // 11 = RC
    // -----------------------------    
    localparam logic [1:0] CSR_CMD_NONE = 2'b00;
    localparam logic [1:0] CSR_CMD_RW   = 2'b01;
    localparam logic [1:0] CSR_CMD_RS   = 2'b10;
    localparam logic [1:0] CSR_CMD_RC   = 2'b11;

    always_comb begin
        // -------------------------
        // Valores por defecto
        // -------------------------
        imm_sel       = IMM_NONE;
 
        reg_write     = 1'b0;       // por defecto no se escribe en el registro de destino
        mem_write     = 1'b0;       // por defecto no se realiza una operación de store
        store_size    = STORE_W;    // valor por defecto inofensivo
        wb_sel_pc4    = 1'b0;       // por defecto no se selecciona pc+4 para escribir en rd

        mem_read      = 1'b0;       // por defecto no se realiza una operación de load
        load_size     = STORE_W;
        load_unsigned = 1'b0;
        wb_sel_mem    = 1'b0;

        rs1_used      = 1'b0;
        rs2_used      = 1'b0;

        alu_src_a_sel = ALU_SRC_A_RS1;
        alu_src_b_sel = ALU_SRC_B_RS2;
        alu_op        = ALU_ADD;

        branch        = 1'b0;
        branch_op     = BR_NONE;
        jump          = 1'b0;

        illegal_instr = 1'b0;

        // Por defecto, no se decodifican instrucciones de sistema
        sys_ecall    = 1'b0;
        sys_ebreak   = 1'b0;
        sys_mret     = 1'b0;

        // Por defecto, no se decodifican instrucciones CSR
        csr_en        = 1'b0;
        csr_cmd       = CSR_CMD_NONE;
        csr_use_imm   = 1'b0;
        csr_read      = 1'b0;
        csr_write     = 1'b0;

        case (opcode) // Se decodifica el opcode para determinar el tipo de instrucción y configurar las señales de control correspondientes

            // ---------------------------------
            // LUI
            // rd = U-immediate
            // ---------------------------------
            OPCODE_LUI: begin
                imm_sel       = IMM_U;
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_ZERO;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_PASS_B;
            end

            // ---------------------------------
            // AUIPC
            // rd = pc + U-immediate
            // ---------------------------------
            OPCODE_AUIPC: begin
                imm_sel       = IMM_U;
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_PC;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_ADD;
            end

            // ---------------------------------
            // JAL
            // target = pc + J-immediate
            // rd = pc + 4
            // ---------------------------------
            OPCODE_JAL: begin
                imm_sel       = IMM_J;
                reg_write     = 1'b1;
                wb_sel_pc4    = 1'b1;
                jump          = 1'b1;
                alu_src_a_sel = ALU_SRC_A_PC;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_ADD;
            end

            // ---------------------------------
            // JALR
            // target = (rs1 + I-immediate) con bit 0 forzado a 0
            // rd = pc + 4
            // funct3 debe ser 000
            // ---------------------------------
            OPCODE_JALR: begin
                imm_sel       = IMM_I;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_ADD;

                rs1_used = 1'b1;

                if (funct3 == 3'b000) begin
                    reg_write  = 1'b1;
                    wb_sel_pc4 = 1'b1;
                    jump       = 1'b1;
                end
                else begin
                    illegal_instr = 1'b1;
                end
            end

            // ---------------------------------
            // OP-IMM
            // ADDI, XORI, ORI, ANDI, SLLI, SRLI, SRAI
            // ---------------------------------
            OPCODE_OP_IMM: begin
                imm_sel       = IMM_I;
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_IMM;

                rs1_used = 1'b1;

                case (funct3)
                    3'b000: alu_op = ALU_ADD;   // ADDI
                    3'b010: alu_op = ALU_SLT;   // SLTI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    3'b100: alu_op = ALU_XOR;   // XORI
                    3'b110: alu_op = ALU_OR;    // ORI
                    3'b111: alu_op = ALU_AND;   // ANDI

                    // SLLI en RV64I
                    3'b001: begin
                        if (funct6 == 6'b000000)
                            alu_op = ALU_SLL;
                        else
                            illegal_instr = 1'b1;
                    end

                    // SRLI / SRAI en RV64I
                    3'b101: begin
                        if (funct6 == 6'b000000)
                            alu_op = ALU_SRL;
                        else if (funct6 == 6'b010000)
                            alu_op = ALU_SRA;
                        else
                            illegal_instr = 1'b1;
                    end

                    default: begin
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            OPCODE_OP_32: begin
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_RS2;

                rs1_used = 1'b1;
                rs2_used = 1'b1;

                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_ADDW;  // ADDW
                        else if (funct7 == 7'b0100000)
                            alu_op = ALU_SUBW;  // SUBW
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b001: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SLLW;  // SLLW
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SRLW;  // SRLW
                        else if (funct7 == 7'b0100000)
                            alu_op = ALU_SRAW;  // SRAW
                        else
                            illegal_instr = 1'b1;
                    end

                    default: begin
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            // ---------------------------------
            // OP-IMM-32 (RV64I)
            // ADDIW, SLLIW, SRLIW, SRAIW
            // Resultado de 32 bits sign-extended a 64 bits
            // ---------------------------------
            OPCODE_OP_IMM_32: begin
                imm_sel       = IMM_I;
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_IMM;

                rs1_used = 1'b1;

                case (funct3)
                    3'b000: begin
                        // ADDIW
                        alu_op = ALU_ADDW;
                    end

                    3'b001: begin
                        // SLLIW: funct7 debe ser 0000000
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SLLW;
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b101: begin
                        // SRLIW / SRAIW
                        // SRLIW: funct7 = 0000000
                        // SRAIW: funct7 = 0100000
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SRLW;
                        else if (funct7 == 7'b0100000)
                            alu_op = ALU_SRAW;
                        else
                            illegal_instr = 1'b1;
                    end

                    default: begin
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            // ---------------------------------
            // OP
            // ADD, SUB, SLL, XOR, SRL, SRA, OR, AND
            // ---------------------------------
            OPCODE_OP: begin
                reg_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_RS2;

                rs1_used = 1'b1;
                rs2_used = 1'b1;

                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_ADD;  // ADD
                        else if (funct7 == 7'b0100000)
                            alu_op = ALU_SUB;  // SUB
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b001: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SLL;  // SLL
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b010: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SLT;  // SLT
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b011: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SLTU; // SLTU
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b100: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_XOR;  // XOR
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_SRL;  // SRL
                        else if (funct7 == 7'b0100000)
                            alu_op = ALU_SRA;  // SRA
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b110: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_OR;   // OR
                        else
                            illegal_instr = 1'b1;
                    end

                    3'b111: begin
                        if (funct7 == 7'b0000000)
                            alu_op = ALU_AND;  // AND
                        else
                            illegal_instr = 1'b1;
                    end

                    default: begin
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            // ---------------------------------
            // BRANCH
            // BEQ, BNE
            // target = pc + B-immediate (se calcula luego)
            // ---------------------------------
            OPCODE_BRANCH: begin
                imm_sel       = IMM_B;
                reg_write     = 1'b0;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_RS2;
                branch        = 1'b1;

                rs1_used = 1'b1;
                rs2_used = 1'b1;

                case (funct3)
                    3'b000: branch_op = BR_EQ;   // BEQ
                    3'b001: branch_op = BR_NE;   // BNE
                    3'b100: branch_op = BR_LT;   // BLT
                    3'b101: branch_op = BR_GE;   // BGE
                    3'b110: branch_op = BR_LTU;  // BLTU
                    3'b111: branch_op = BR_GEU;  // BGEU
                    default: begin
                        branch_op     = BR_NONE;
                        illegal_instr = 1'b1;
                        branch        = 1'b0;
                    end
                endcase
            end

            // ---------------------------------
            // LOAD
            // addr = rs1 + I-immediate
            // rd = dato leído de memoria
            // ---------------------------------
            OPCODE_LOAD: begin
                imm_sel       = IMM_I;
                reg_write     = 1'b1;
                mem_read      = 1'b1;
                wb_sel_mem    = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_ADD;
                rs1_used      = 1'b1;

                case (funct3)
                    3'b000: begin load_size = STORE_B; load_unsigned = 1'b0; end // LB
                    3'b001: begin load_size = STORE_H; load_unsigned = 1'b0; end // LH
                    3'b010: begin load_size = STORE_W; load_unsigned = 1'b0; end // LW
                    3'b011: begin load_size = STORE_D; load_unsigned = 1'b0; end // LD
                    3'b100: begin load_size = STORE_B; load_unsigned = 1'b1; end // LBU
                    3'b101: begin load_size = STORE_H; load_unsigned = 1'b1; end // LHU
                    3'b110: begin load_size = STORE_W; load_unsigned = 1'b1; end // LWU
                    default: begin
                        reg_write     = 1'b0;
                        mem_read      = 1'b0;
                        wb_sel_mem    = 1'b0;
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            // ---------------------------------
            // STORE
            // addr = rs1 + S-immediate
            // data = rs2
            // ---------------------------------
            OPCODE_STORE: begin
                imm_sel       = IMM_S;
                mem_write     = 1'b1;
                alu_src_a_sel = ALU_SRC_A_RS1;
                alu_src_b_sel = ALU_SRC_B_IMM;
                alu_op        = ALU_ADD;

                rs1_used = 1'b1;
                rs2_used = 1'b1;

                case (funct3)
                    3'b000: store_size = STORE_B; // SB
                    3'b001: store_size = STORE_H; // SH
                    3'b010: store_size = STORE_W; // SW
                    3'b011: store_size = STORE_D; // SD (RV64I)
                    default: begin
                        mem_write     = 1'b0;
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            // ---------------------------------
            // MISC-MEM
            // Por ahora solo aceptamos FENCE base como no-op.
            // FENCE.I se deja fuera en esta iteración.
            // ---------------------------------
            OPCODE_MISC_MEM: begin
                if (funct3 == 3'b000) begin
                    // FENCE base: implementación mínima = no-op arquitectónico
                end
                else begin
                    // FENCE.I y otros no soportados en esta iteración
                    illegal_instr = 1'b1;
                end
            end

            // ---------------------------------
            // SYSTEM
            // Soporta:
            //   ECALL, EBREAK, MRET
            //   CSRRW / CSRRS / CSRRC
            //   CSRRWI / CSRRSI / CSRRCI
            // ---------------------------------
            OPCODE_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    if (instr == 32'h00000073) begin
                        sys_ecall = 1'b1;   // ECALL
                    end
                    else if (instr == 32'h00100073) begin
                        sys_ebreak = 1'b1;  // EBREAK
                    end
                    else if (instr == 32'h30200073) begin
                        sys_mret = 1'b1;    // MRET
                    end
                    else begin
                        illegal_instr = 1'b1;
                    end
                end
                else begin
                    csr_en = 1'b1;

                    // Para CSR, el resultado que va a rd será el valor viejo del CSR
                    // si y solo si rd != x0.
                    reg_write = (rd_addr != 5'd0);

                    case (funct3)
                        3'b001: begin
                            // CSRRW
                            csr_cmd     = CSR_CMD_RW;
                            csr_use_imm = 1'b0;
                            csr_read    = (rd_addr != 5'd0);
                            csr_write   = 1'b1;
                            rs1_used    = (rs1_addr != 5'd0);
                        end

                        3'b010: begin
                            // CSRRS
                            csr_cmd     = CSR_CMD_RS;
                            csr_use_imm = 1'b0;
                            csr_read    = 1'b1;
                            csr_write   = (rs1_addr != 5'd0);
                            rs1_used    = (rs1_addr != 5'd0);
                        end

                        3'b011: begin
                            // CSRRC
                            csr_cmd     = CSR_CMD_RC;
                            csr_use_imm = 1'b0;
                            csr_read    = 1'b1;
                            csr_write   = (rs1_addr != 5'd0);
                            rs1_used    = (rs1_addr != 5'd0);
                        end

                        3'b101: begin
                            // CSRRWI
                            csr_cmd     = CSR_CMD_RW;
                            csr_use_imm = 1'b1;
                            csr_read    = (rd_addr != 5'd0);
                            csr_write   = 1'b1;
                            rs1_used    = 1'b0; // rs1 field es uimm
                        end

                        3'b110: begin
                            // CSRRSI
                            csr_cmd     = CSR_CMD_RS;
                            csr_use_imm = 1'b1;
                            csr_read    = 1'b1;
                            csr_write   = (rs1_addr != 5'd0); // uimm != 0
                            rs1_used    = 1'b0;
                        end

                        3'b111: begin
                            // CSRRCI
                            csr_cmd     = CSR_CMD_RC;
                            csr_use_imm = 1'b1;
                            csr_read    = 1'b1;
                            csr_write   = (rs1_addr != 5'd0); // uimm != 0
                            rs1_used    = 1'b0;
                        end

                        default: begin
                            csr_en        = 1'b0;
                            reg_write     = 1'b0;
                            csr_cmd       = CSR_CMD_NONE;
                            csr_use_imm   = 1'b0;
                            csr_read      = 1'b0;
                            csr_write     = 1'b0;
                            illegal_instr = 1'b1;
                        end
                    endcase
                end
            end

            default: begin
                illegal_instr = 1'b1;
            end
        endcase
    end

endmodule


