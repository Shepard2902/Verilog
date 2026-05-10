`include "macros.vh"

module Procesor(
    input                         clk,
    input                         reset,
    input                         cpu_en,   // active-high run-enable from MemCtrl
    input         [`INSTRSIZE - 1:0] instruction,
    input   [`D_SIZE - 1:0] data_in,
    output                  read,
    output                  write,
    output  [`A_SIZE - 1:0] pc,
    output  [`A_SIZE - 1:0] addr,
    output  [`D_SIZE - 1:0] data_out
);

    wire                        load_en;
    wire                        halt_en;
    // halt_all: freeze all pipeline registers when halted OR when CPU is stopped
    wire                        halt_all = halt_en | ~cpu_en;
    wire                        jmp_en;
    wire                        jmpr_en;
    wire                        jmp_ok;
    wire signed [`A_SIZE - 1:0] new_pc;
    wire        [`INSTRSIZE - 1:0] instruction_out_fetch;

    assign read = load_en;

    fetch Fetch(
        .clk(clk),
        .reset(reset),
        .cpu_en(cpu_en),
        .instruction_in(instruction),
        .load_en(load_en),
        .halt_en(halt_all),
        .jmp_en(jmp_en),
        .jmpr_en(jmpr_en),
        .jmp_ok(jmp_ok),
        .new_pc(new_pc),
        .pc(pc),
        .instruction_out(instruction_out_fetch)
    );

    wire [`INSTRSIZE - 1:0] instruction_out_ir;

    IR ir(
        .clk(clk),
        .reset(reset),
        .load_en(load_en),
        .halt_en(halt_all),
        .jmp_en(jmp_en),
        .jmpr_en(jmpr_en),
        .jmp_ok(jmp_ok),
        .instruction_in(instruction_out_fetch),
        .instruction_out(instruction_out_ir)
    );

    wire  [`D_SIZE - 1:0] op0_data_regs;
    wire  [`D_SIZE - 1:0] op1_data_regs;
    wire  [`D_SIZE - 1:0] op2_data_regs;
    wire  [2:0]           dest_execute;
    wire  [`D_SIZE - 1:0] result_execute;
    wire  [2:0]           dest;
    wire  [`D_SIZE - 1:0] result;
    wire        [`INSTRSIZE - 1:0] instruction_out_read;
    wire        [2:0]           op0;
    wire        [2:0]           op1;
    wire        [2:0]           op2;
    wire  [`D_SIZE - 1:0] op0_data_out;
    wire  [`D_SIZE - 1:0] op1_data_out;
    wire  [`D_SIZE - 1:0] op2_data_out;
    wire  [`valoare]    val;
    wire  [`constanta]  cons;
    wire  [`offset ] offset;
    wire        [2:0]           cond;

    READ read_out(
        .instruction_in(instruction_out_ir),
        .op0_dreg(op0_data_regs),
        .op1_dreg(op1_data_regs),
        .op2_dreg(op2_data_regs),
        .dest_ex(dest_execute),
        .result_ex(result_execute),
        .dest(dest),
        .result(result),
        .instruction_out(instruction_out_read),
        .op0(op0),
        .op1(op1),
        .op2(op2),
        .op0_dout(op0_data_out),
        .op1_dout(op1_data_out),
        .op2_dout(op2_data_out),
        .val(val),
        .cons(cons),
        .offset(offset),
        .cond(cond)
    );
 wire write_en;
    regs Regs(                
        .clk(clk),
        .reset(reset),
        .dest(dest),
        .src0(op0),                                
        .src1(op1),
        .src2(op2),
        .result(result),
        .op0_data(op0_data_regs),
        .op1_data(op1_data_regs),
        .op2_data(op2_data_regs),
        .write_en(write_en)
    );

    wire        [`INSTRSIZE - 1:0] instruction_out_read_pipeline;
    wire  [`D_SIZE - 1:0] op0_dout_read_punte;
    wire  [`D_SIZE - 1:0] op1_dout_read_punte;
    wire  [`D_SIZE - 1:0] op2_dout_read_punte;
    wire  [`valoare]    val_read_punte;
    wire  [`constanta]  cons_out_read_punte;
    wire  [`offset] offset_out_read_pipeline;
    wire        [2:0]           cond_out_read_pipeline;

    READ_Pipeline read_pipeline(
        .clk(clk),
        .reset(reset),
        .load_en(load_en),
        .halt_en(halt_all),
        .jmp_en(jmp_en),
        .jmpr_en(jmpr_en),
        .jmp_ok(jmp_ok),
        .instruction_in(instruction_out_read),
        .op0_din(op0_data_out),
        .op1_din(op1_data_out),
        .op2_din(op2_data_out),
        .val_in(val),
        .cons_in(cons),
        .offset_in(offset),
        .cond_in(cond),
        .instruction_out(instruction_out_read_pipeline),
        .op0_dout(op0_dout_read_punte),
        .op1_dout(op1_dout_read_punte),
        .op2_dout(op2_dout_read_punte),
        .val(val_read_punte),
        .cons(cons_out_read_punte),
        .offset(offset_out_read_pipeline),
        .cond(cond_out_read_pipeline)
    );

    wire [`INSTRSIZE - 1:0] instruction_out_execute;

  EXECUTE execute(
    .instruction(instruction_out_read_pipeline),
    .op0_din(op0_dout_read_punte),
    .op1_din(op1_dout_read_punte),
    .op2_din(op2_dout_read_punte),
    .val_in(val_read_punte),
    .cons_in(cons_out_read_punte),
    .offset_in(offset_out_read_pipeline),
    .cond_in(cond_out_read_pipeline),
    .instruction_out(instruction_out_execute),
    .write(write),
    .load_en(load_en),
    .halt_en(halt_en),
    .jmp_en(jmp_en),
    .jmpr_en(jmpr_en),
    .jmp_ok(jmp_ok),
    .addr(addr),
    .data_out(data_out),
    .dest(dest_execute),
    .result(result_execute),
    .new_pc(new_pc)
);


    wire        [`INSTRSIZE - 1:0] instr_out_ex_punte;
    wire        [2:0]           dest_ex_puntee;
    wire signed [`D_SIZE - 1:0] result_ex_punte;
   

    EXECUTE_Pipeline execute_pipeline(
        .clk(clk),
        .reset(reset),
        .halt_en(halt_all),
        .instruction_in(instruction_out_execute),
        .dest_in(dest_execute),
        .result_in(result_execute),
        .instruction_out(instr_out_ex_punte),
        .dest_out(dest_ex_puntee),
        .result_out(result_ex_punte)
    );

    Write_back write_back(
        .instruction_in(instr_out_ex_punte),
        .dest_in(dest_ex_puntee),
        .result_in(result_ex_punte),
        .data_in(data_in),
        .dest_out(dest),
        .write_en(write_en),
        .result_out(result)
    );

endmodule
