`include "macros.vh"

module Data_Memory(
    input       clk,
    input       read,
    input       write,
    input       [`A_SIZE - 1:0] addr,
    input       [`D_SIZE - 1:0] data_in,
    output reg  [`D_SIZE - 1:0] data_out
);

    reg  [`D_SIZE - 1:0] memory [0:2**`A_SIZE -1];

    always @(posedge clk) begin
        if (read)
            data_out <= memory[addr];
        else 
        if (write)
            memory[addr] <= data_in;
    end

endmodule