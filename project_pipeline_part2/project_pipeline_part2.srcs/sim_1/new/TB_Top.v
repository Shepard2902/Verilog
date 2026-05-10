`include "macros.vh"

`timescale 1ns / 1ps

module Top_TB();

   reg clk;
   reg reset;

    Top DUT(
        .clk(clk),
        .reset(reset)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;    
    end

    initial begin
        #1;
        reset = 1'b0;

        @(negedge clk);
        reset = 1'b1;

        repeat(90) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
 
        repeat(4) @(posedge clk);
        $finish;
    end

endmodule