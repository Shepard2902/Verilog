`include "macros.vh"

module Write_back(
    input       [`INSTRSIZE - 1:0] instruction_in,
    input       [2:0]           dest_in,
    input       [`D_SIZE - 1:0] result_in,
    input       [`D_SIZE - 1:0] data_in,
    output reg        [2:0] dest_out,
    output reg  [`D_SIZE - 1:0] result_out,
    output reg  write_en 
);

    always @ (*) begin
        dest_out = 0;
        result_out = 0;
        write_en=1'b0;
        casez (instruction_in[`OPCODEFIELD])
            `ADD, `SUB, `AND, `OR, `XOR, `NAND, `NOR,
            `NXOR, `SHIFTR, `SHIFTRA, `SHIFTL, `LOADC1: begin
                write_en=1'b1;
                dest_out = dest_in;
                result_out = result_in;
            end 
            `LOAD1: begin
                 write_en=1'b1;
                dest_out = dest_in;
                result_out = data_in;
            end
            default: ;
        endcase
    end

endmodule