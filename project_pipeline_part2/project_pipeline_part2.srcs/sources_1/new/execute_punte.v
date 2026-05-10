`include "macros.vh"

module EXECUTE_Pipeline(
    input                             clk,
    input                             reset,
    input                             halt_en,
    input             [`INSTRSIZE - 1:0] instruction_in,
    input             [2:0]           dest_in,
    input      [`D_SIZE - 1:0] result_in,
    output reg  [`INSTRSIZE - 1:0] instruction_out,
    output reg        [2:0]dest_out,
    output reg [`D_SIZE - 1:0] result_out
);

    always @(posedge clk) begin
        if (!reset) begin
            instruction_out <= 0;
            dest_out <= 0;
            result_out <= 0;
        end
        else if (halt_en) begin
            dest_out <= dest_out;
            result_out <= result_out;
             instruction_out <= instruction_out;
        end
        else begin
            instruction_out <= instruction_in;                                                
            dest_out <= dest_in;
            result_out <= result_in;
        end
    end

endmodule