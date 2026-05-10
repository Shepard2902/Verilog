`include "macros.vh"

module EXECUTE(
    input             [`INSTRSIZE-1:0] instruction,
    input      [`D_SIZE-1:0] op0_din,
    input      [`D_SIZE-1:0] op1_din,
    input      [`D_SIZE-1:0] op2_din,
    input      [`valoare]    val_in,
    input      [`constanta]  cons_in,
    input      [`offset] offset_in,
    input             [2:0]   cond_in,
    output reg        [`INSTRSIZE-1:0] instruction_out,
    output reg    write,
    output reg    load_en,
    output reg    halt_en,
    output reg    jmp_en,
    output reg    jmpr_en,
    output reg    jmp_ok,
    output reg        [`A_SIZE-1:0]   addr,
    output reg  [`D_SIZE-1:0]   data_out,
    output reg  [2:0]           dest,
    output reg  [`D_SIZE-1:0]   result,
    output reg  [`A_SIZE-1:0]   new_pc
);

    always  @ (*) begin
        instruction_out = instruction;
        write = 0;
        addr = 0;
        data_out = 0;
        dest = 0;
        result = 0;
        load_en = 0;
        halt_en = 0;
        jmp_en = 0;
        jmpr_en = 0;
        jmp_ok = 0;
        new_pc = 0;

        casez(instruction[`OPCODEFIELD])
            `NOP: ;
            `ADD: begin
                dest = instruction[`op0];
                result = op1_din + op2_din;
            end
            `SUB: begin
                dest = instruction[`op0];
                result = op1_din - op2_din;
            end
            `AND: begin
                dest = instruction[`op0];
                result = op1_din & op2_din;
            end
            `OR: begin
                dest = instruction[`op0];
                result = op1_din | op2_din;
            end
            `XOR: begin
                 dest = instruction[`op0];
                result = op1_din ^ op2_din;
            end
            `NAND: begin
                 dest = instruction[`op0];
                result = ~(op1_din & op2_din);
            end
            `NOR: begin
                 dest = instruction[`op0];
                result = ~(op1_din | op2_din);
            end
            `NXOR: begin
                 dest = instruction[`op0];
                result = ~(op1_din ^ op2_din);
            end
            `SHIFTR: begin
                 dest = instruction[`op0];
                result = op0_din >> val_in;
            end
            `SHIFTRA: begin
                 dest = instruction[`op0];
                result = op0_din >>> val_in;
            end
            `SHIFTL: begin
                 dest = instruction[`op0];
                result = op0_din << val_in;
            end
            `LOAD1: begin
                load_en = 1;
                dest = instruction[`opcode0_load];
                addr = op1_din[`A_SIZE-1:0];
            end
            `LOADC1: begin
                dest = instruction[`opcode0_load];
                result = {op0_din[`D_SIZE-1:8], cons_in};
            end
            `STORE1: begin
                write = 1;
                addr = op0_din[`A_SIZE-1:0];
                data_out = op1_din;
            end
            `JMP1: begin
                jmp_en = 1;
                jmp_ok = 1;
                new_pc = op0_din;
            end
            `JMPR1: begin
                jmpr_en = 1;
                jmp_ok = 1;
                new_pc = offset_in - 2;
            end
            `JMPcond: begin
                jmp_en = 1;
                case(cond_in)
                    `N:  if (op0_din < 0) begin jmp_ok = 1; new_pc = op1_din; end
                    `NN: if (op0_din >= 0) begin jmp_ok = 1; new_pc = op1_din; end
                    `Z:  if (op0_din == 0) begin jmp_ok = 1; new_pc = op1_din; end
                    `NZ: if (op0_din != 0) begin jmp_ok = 1; new_pc = op1_din; end
                    default: jmp_ok = 0;
                endcase
            end
            `JMPRcond: begin
                jmpr_en = 1;
                case(cond_in)
                    `N:  if (op0_din < 0) begin jmp_ok = 1; new_pc = offset_in - 2; end
                    `NN: if (op0_din >= 0) begin jmp_ok = 1; new_pc = offset_in - 2; end
                    `Z:  if (op0_din == 0) begin jmp_ok = 1; new_pc = offset_in - 2; end
                    `NZ: if (op0_din != 0) begin jmp_ok = 1; new_pc = offset_in - 2; end
                    default: jmp_ok = 0;
                endcase
            end
            `HALT: halt_en = 1;
            default: ;
        endcase
    end

endmodule
