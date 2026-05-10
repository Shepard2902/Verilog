`include "macros.vh"

module Program_Memory(
    input  [`A_SIZE - 1:0] addr,
    output [`INSTRSIZE - 1:0] instruction
);

    reg [`INSTRSIZE - 1:0] memory [0:2 ** `A_SIZE - 1];

    assign instruction = memory[addr];

    initial begin
        memory[00] = {`NOP, 9'b0};
        memory[01] = {`LOADC, `R1, 8'd150};
        memory[02] = {`LOADC, `R2, 8'd100};
        memory[03] = {`ADD, `R0, `R1, `R2};
        memory[04] = {`SUB, `R4, `R3, `R2};
        memory[05] = {`AND, `R1, `R2, `R3};
        memory[06] = {`OR, `R2, `R3, `R4};
        memory[07] = {`NAND, `R3, `R4, `R5};
        memory[08] = {`XOR, `R4, `R0, `R3};
        memory[09] = {`NOR, `R5, `R4, `R4};
        
        memory[10] = {`NXOR, `R6, `R5, `R0};
        memory[11] = {`SHIFTR, `R0, 6'd5};
        memory[12] = {`LOADC, `R7, 8'd128};
        memory[13] = {`SHIFTL, `R7, 6'd24};
        memory[14] = {`SHIFTRA, `R7, 6'd5};
        memory[15] = {`LOADC, `R0, 8'd15};
        memory[16] = {`LOADC, `R1, 8'd1};
        memory[17] = {`STORE, `R0, 5'd0, `R2};
        memory[18] = {`JMPR, 6'd0, 6'd5};
        memory[19] = {`AND, `R1, `R2, `R6};
   
        memory[20] = {`OR, `R7, `R5, `R4};
        memory[21] = {`LOAD, `R3, 5'd0, `R0};
        memory[22] = {`SUB, `R6, `R6, `R6};
        memory[23] = {`LOADC, `R6, 8'd82};
        memory[24] = {`SHIFTR, `R3, 6'd25};
        memory[25] = {`SHIFTR, `R2, 6'd26};
        memory[26] = {`NAND, `R1, `R2, `R7};
        memory[27] = {`JMPcond, `NN, `R6, 3'b0, `R6};
        memory[28] = {`SHIFTRA, `R2, 6'd5};
        memory[29] = {`JMPcond, `NN, `R7, 3'b0, `R0};
        memory[30] = {`STORE, `R2, 5'd0, `R2};
        memory[31] = {`JMPcond, `Z, `R0, 3'b0, `R3};
        memory[32] = {`LOAD, `R4, 5'd0, `R2};
        memory[33] = {`JMPcond, `Z, `R2, 3'b0, `R7};
        memory[34] = {`JMPcond, `NZ, `R5, 3'b0, `R5};
        memory[35] = {`SUBF, `R2, `R3, `R7};
        memory[36] = {`JMPcond, `NZ, `R0, 3'b0, `R1};
        memory[37] = {`ADDF, `R6, `R7, `R5};
        memory[38] = {`JMPRcond, `N, `R1, 6'd27};
        memory[39] = {`OR, `R5, `R0, `R7};
        
        memory[45] = {`HALT, 12'b0};
        memory[54] = {`JMPRcond, `N, `R0, 6'd63};
        memory[90] = {`SHIFTR, `R7, 6'd12};
        memory[93] = {`JMPRcond, `NN, `R2, 6'd31};
        
        memory[120] = {`AND, `R4, `R5, `R6};
        memory[121] = {`JMPRcond, `NN, `R5, 6'd2};
        memory[122] = {`JMPRcond, `Z, `R0, 6'd17};
        memory[123] = {`NOR, `R3, `R2, `R1};
        memory[124] = {`JMPRcond, `Z, `R3, 6'd6};
        memory[128] = {`NXOR, `R7, `R6, `R4};
        memory[129] = {`JMPRcond, `NZ, `R6, 6'd24};
        memory[131] = {`LOADC, `R2, 8'd21};
        memory[142] = {`JMPRcond, `NZ, `R0, 6'd49};
        memory[156] = {`HALT, 12'b0};
    end

endmodule