`define D_SIZE 32
`define INSTRSIZE 16
`define OPCODESIZE 7
`define A_SIZE 10

`define OPCODEFIELD `INSTRSIZE-1:`INSTRSIZE-`OPCODESIZE 
`define OPCODEFIELD1 `INSTRSIZE-1:`INSTRSIZE-`OPCODESIZE+2
`define OPCODEFIELD2 `INSTRSIZE-1:`INSTRSIZE-`OPCODESIZE+3

`define R0 3'd0
`define R1 3'd1
`define R2 3'd2
`define R3 3'd3
`define R4 3'd4
`define R5 3'd5
`define R6 3'd6
`define R7 3'd7

`define     NOP         7'b0000000
`define     ADD         7'b0000001
`define     ADDF        7'b0000010
`define     SUB         7'b0000011
`define     SUBF        7'b0000100
`define     AND         7'b0000101
`define     OR          7'b0000110
`define     XOR         7'b0000111
`define     NAND        7'b0001000
`define     NOR         7'b0001001
`define     NXOR        7'b0001010
`define     SHIFTR      7'b0001011   
`define     SHIFTRA     7'b0001100
`define     SHIFTL      7'b0001101

`define     LOAD        5'b01000
`define     LOAD1       {`LOAD, 2'b??}
`define     LOADC       5'b01001
`define     LOADC1      {`LOADC, 2'b??}
`define     STORE       5'b01010
`define     STORE1      {`STORE, 2'b??}

`define     JMP         4'b1000
`define     JMP1        {`JMP, 3'b???}
`define     JMPR        4'b1001
`define     JMPR1       {`JMP1, 3'b???}
`define     JMPcond     4'b1010
`define     JMPRcond    4'b1011
`define     HALT        4'b1111



`define op0  8:6
`define op1  5:3
`define op2  2:0 
`define opcode1_load  2:0
`define opcode0_load  10:8
`define constanta 7 : 0
`define valoare 5 : 0

`define     offset 5 : 0


`define     cond    11 : 9
`define     N       3'b000          
`define     NN      3'b001         
`define     Z       3'b010          
`define     NZ      3'b011          