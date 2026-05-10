`include "macros.vh"

module IR_float (
    input    clk,
    input    reset,
    input    [`INSTRSIZE - 1:0] instruction_in [3:0],
    input     load_en,
    input     halt_en,
    input     jmp_en,
    input     jmpr_en,
    input     jmp_ok,
    output   reg  [`INSTRSIZE - 1:0] instruction_out
);
integer i;
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
        
        for (i=0; i<4;i=i+1) begin
            if(instruction_in[i]!=`NOP)
            instruction_out <= instruction_in[i];
         end
         end
            
        end
    

   
endmodule
