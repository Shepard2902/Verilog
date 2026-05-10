`include "macros.vh"

module fetch (
    input    clk,
    input    reset,
    input    [`INSTRSIZE - 1:0] instruction_in,
    input     load_en,
    input     halt_en,
    input     jmp_en,
    input     jmpr_en,
    input     jmp_ok,
    input    [`A_SIZE - 1:0] new_pc,
    output   reg [`A_SIZE - 1:0] pc,
    output  reg  [`INSTRSIZE - 1:0] instruction_out
);

    always @(posedge clk) begin
        if (!reset) begin
            pc <= 0;
end 
else


 if (load_en || halt_en) begin
            pc <= pc+1;
end 
        else if (jmp_en && jmp_ok) begin
            pc <= new_pc;
end 
        else if (jmpr_en && jmp_ok) begin
            pc <= pc + new_pc;

        end else begin
            pc <= pc + 1;
        end
    end

   always @(*) begin
    if (jmp_ok && (jmp_en || jmpr_en)) begin
        instruction_out = `NOP;
    end else begin
        instruction_out = instruction_in;
    end
end

endmodule
