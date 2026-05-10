`include "macros.vh"

module IR (
    input    clk,
    input    reset,
    input    [`INSTRSIZE - 1:0] instruction_in,
    input     load_en,
    input     halt_en,
    input     jmp_en,
    input     jmpr_en,
    input     jmp_ok,
    output   reg  [`INSTRSIZE - 1:0] instruction_out
);

    always @(posedge clk) begin
        if (!reset) begin
            instruction_out <= `NOP;
        end
        else if (load_en || halt_en) begin
            instruction_out <= instruction_out;
        end
            else if (jmp_ok && (jmp_en || jmpr_en)) begin
            instruction_out <= `NOP;
            end
        else 
        begin
            instruction_out <= instruction_in;
        end
    end

   
endmodule
