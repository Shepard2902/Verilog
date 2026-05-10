`include "macros.vh"

module READ(
    input [`INSTRSIZE - 1:0] instruction_in,
    input [`D_SIZE - 1:0] op0_dreg,
    input [`D_SIZE - 1:0] op1_dreg,
    input [`D_SIZE - 1:0] op2_dreg,
    input [2:0]           dest_ex,
    input [`D_SIZE - 1:0] result_ex,
   input [2:0]           dest_ex_float,
    input [`D_SIZE - 1:0] result_ex_float,
    input [2:0]           dest,
    input [`D_SIZE - 1:0] result,
    output reg   [`INSTRSIZE - 1:0] instruction_out,
    output reg   [2:0]           op0,
    output reg   [2:0]           op1,
    output reg   [2:0]           op2,
    output reg [`D_SIZE - 1:0] op0_dout,
    output reg [`D_SIZE - 1:0] op1_dout,
    output reg [`D_SIZE - 1:0] op2_dout,
    output reg [`valoare]    val,
    output reg [`constanta]  cons,
    output reg [`offset] offset,
    output reg [2:0]     cond
);

    always @(*) begin
        instruction_out = instruction_in;
        op0 = 0;
        op1 = 0;
        op2 = 0;
        val = 0;
        cons = 0;
        offset = 0;
        cond = 0;

        casez (instruction_in[`OPCODEFIELD])
            `NOP,
            {`HALT, 3'b???}: ;

            `ADD, `SUB, `AND, `OR, `XOR, `NAND, `NOR, `NXOR,`ADDF,`SUBF: begin
                op0 = instruction_in[`op0];
                op1 = instruction_in[`op1];
                op2 = instruction_in[`op2];
            end

            `SHIFTR, `SHIFTRA, `SHIFTL: begin
                op0 = instruction_in[`op0];
                val = instruction_in[`valoare];
            end

            `LOAD1, `STORE1: begin
                op0 = instruction_in[`opcode0_load];
                op1 = instruction_in[`opcode1_load];
            end

            `LOADC1: begin
                op0 = instruction_in[`opcode0_load];
                cons = instruction_in[`constanta];
            end

            `JMP1: op0 = instruction_in[`op2];
            `JMPR1: offset = instruction_in[`offset];
            `JMPcond: begin
                cond = instruction_in[`cond];
                op0 = instruction_in[`op0];
                op1 = instruction_in[`op2];
            end
            `JMPRcond: begin
                cond = instruction_in[`cond];
                op0 = instruction_in[`op0];
                offset = instruction_in[`offset];
            end
            default: ;
        endcase
           if (instruction_in[`OPCODEFIELD] != `NOP && op0 == dest_ex_float)
            op0_dout = result_ex_float;
        if (instruction_in[`OPCODEFIELD] != `NOP && op0 == dest_ex)
            op0_dout = result_ex;
        else if (instruction_in[`OPCODEFIELD] != `NOP && op0 == dest)
            op0_dout = result;
        else
            op0_dout = op0_dreg;
    
         if (instruction_in[`OPCODEFIELD] != `NOP && op1 == dest_ex_float)
            op1_dout = result_ex_float;   
        if (instruction_in[`OPCODEFIELD] != `NOP && op1 == dest_ex)
            op1_dout = result_ex;
        else if (instruction_in[`OPCODEFIELD] != `NOP && op1 == dest)
            op1_dout = result;
        else
            op1_dout = op1_dreg;
        
         if (instruction_in[`OPCODEFIELD] != `NOP && op2 == dest_ex_float)
            op2_dout = result_ex_float;
        if (instruction_in[`OPCODEFIELD] != `NOP && op2 == dest_ex)
            op2_dout = result_ex;
        else if (instruction_in[`OPCODEFIELD] != `NOP && op2 == dest)
            op2_dout = result;
        else
            op2_dout = op2_dreg;
    end

endmodule