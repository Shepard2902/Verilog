`include "macros.vh"

module READ_Pipeline(
    input                             clk,
    input                             reset,
    input                             load_en,
    input                             halt_en,
    input                             jmp_en,
    input                             jmpr_en,
    input                             jmp_ok,
    input       [`INSTRSIZE - 1:0] instruction_in,
    input       [`D_SIZE - 1:0] op0_din,
    input       [`D_SIZE - 1:0] op1_din,
    input       [`D_SIZE - 1:0] op2_din,
    input       [`valoare]      val_in,
    input       [`constanta]    cons_in,
    input       [`offset]   offset_in,
    input             [2:0]           cond_in,
    output reg        [`INSTRSIZE - 1:0] instruction_out,
    output reg  [`D_SIZE - 1:0] op0_dout,
    output reg  [`D_SIZE - 1:0] op1_dout,
    output reg  [`D_SIZE - 1:0] op2_dout,
    output reg  [`valoare]      val,
    output reg  [`constanta]    cons,
    output reg  [`offset]   offset,
    output reg        [2:0]           cond
);

    always @(posedge clk) begin
        if (!reset || load_en || (jmp_ok && (jmp_en || jmpr_en))) begin
            instruction_out <= `NOP;
            op0_dout <= 0;
            op1_dout <= 0;
            op2_dout <= 0;
            val <= 0;
            cons <= 0;
            offset <= 0;
            cond <= 0;
        end
       else if (halt_en) begin
            instruction_out <= instruction_out;
            op0_dout <= op0_dout;
            op1_dout <= op1_dout;
            op2_dout <= op2_dout;
            val <= val;
            cons <= cons;
            offset <= offset;
            cond  <= cond;
        end
        else begin
            instruction_out <= instruction_in;
            op0_dout <= op0_din;
            op1_dout <= op1_din;
            op2_dout <= op2_din;
            val <= val_in;
            cons <= cons_in;
            offset <= offset_in;
            cond  <= cond_in;
        end
    end

endmodule
