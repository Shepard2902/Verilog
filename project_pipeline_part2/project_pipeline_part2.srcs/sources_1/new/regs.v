`include "macros.vh"

module regs(
    input   clk,
    input    reset,
    input    [2:0] dest,
    input    [2:0]src0,
    input [2:0] src1,
    input [2:0] src2,
    input write_en,
    input   [`D_SIZE - 1:0] result,
    output  [`D_SIZE - 1:0] op0_data,
    output  [`D_SIZE - 1:0] op1_data,
    output  [`D_SIZE - 1:0] op2_data
);

    reg [`D_SIZE - 1:0]registru[0:7];
    integer  i;
    always @(posedge clk) begin
        if (!reset)
         for ( i = 0; i < 8; i = i + 1) 
        begin
            registru[i] <= 0;
        end
        else
        if(write_en)
             registru[dest] <= result;
    end

    assign op0_data = registru[src0];
    assign op1_data = registru[src1];
    assign op2_data = registru[src2];

endmodule