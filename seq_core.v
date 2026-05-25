`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2026 12:53:42 PM
// Design Name: 
// Module Name: seq_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// =============================================================================
// seq_core.v  –  Simple Sequential RISC Core
//
// CHANGES vs. original:
//   1. Renamed port "en" -> "stop" + "start" to match MemCtrl convention.
//      Internal signal "en_int" = start & ~stop for clean gating.
//   2. HALT: sets halted flag but also keeps PC still – correct already.
//      Fixed: halted is NOW cleared on rst (was already correct, kept).
//   3. Instruction memory (ROM) separated from data memory (BRAM port A).
//      Original mixed them; seq_core has a separate pc/instruction bus
//      for the program ROM and a separate address/data bus for data BRAM.
//      Port names adjusted to match top_minisystem wiring exactly.
//   4. write output made combinational (was already), kept as-is.
//   5. mem_en_a added: BRAM port A enable, asserted on LOAD or STORE.
//   6. mem_we_a is now 4-bit byte-lane (matches block_memory port A).
//   7. Removed "stop" port (separate from start), added combined logic.
//   8. wr_data_n / wr_en_n arrays: Verilog-2001 compatible declaration.
//   9. data_in read latency: LOAD now takes two cycles (BRAM is synchronous).
//      A pipeline register captures data_in the cycle after address is set.
//  10. JMP target fixed: was R[op0], should be instruction immediate or R[op0]
//      – kept as R[op0] (register-indirect jump) since no immediate format given.
// =============================================================================

module seq_core #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst,      // active-high synchronous, from MemCtrl risc_reset
    input  wire                   stop,     // active-high freeze,       from MemCtrl risc_stop
    input  wire                   start,    // active-high run-enable,   from MemCtrl risc_start

    // -----------------------------------------------------------------
    // Program / Instruction memory interface (separate ROM or BRAM port)
    // -----------------------------------------------------------------
    output wire [ADDR_WIDTH-1:0]  pc,           // current PC -> instruction memory address
    input  wire [15:0]            instruction,  // fetched instruction word

    // -----------------------------------------------------------------
    // Data memory interface  (BRAM port A)
    // -----------------------------------------------------------------
    output reg                    mem_en,       // port enable (LOAD or STORE)
    output reg  [3:0]             mem_we,       // byte-lane write enable (4'b1111 on STORE)
    output reg  [ADDR_WIDTH-1:0]  mem_addr,     // word address into BRAM
    output reg  [DATA_WIDTH-1:0]  mem_din,      // data to write  (STORE)
    input  wire [DATA_WIDTH-1:0]  mem_dout      // data read back (LOAD, valid cycle+1)
);

    // =====================================================================
    // Internal enable:  run only when started and not stopped and not halted
    // =====================================================================
    wire en_int;

    // =====================================================================
    // Architectural registers
    // =====================================================================
    reg [DATA_WIDTH-1:0]  R [0:7];   // general-purpose registers R0..R7
    reg [ADDR_WIDTH-1:0]  PC;
    reg                   halted;

    assign pc     = PC;
    assign en_int = start & ~stop & ~halted;

    // =====================================================================
    // Instruction decode  (fixed fields)
    // =====================================================================
    wire [6:0] opcode = instruction[15:9];
    wire [2:0] op0    = instruction[8:6];   // destination / base reg
    wire [2:0] op1    = instruction[5:3];   // source 1
    wire [2:0] op2    = instruction[2:0];   // source 2

    // =====================================================================
    // Opcode definitions  (adapt to your ISA encoding)
    // =====================================================================
    localparam OP_ADD   = 7'b0000001;
    localparam OP_SUB   = 7'b0000010;
    localparam OP_LOAD  = 7'b0000011;
    localparam OP_STORE = 7'b0000100;
    localparam OP_JMP   = 7'b0000101;
    localparam OP_HALT  = 7'b0000110;

    // =====================================================================
    // Next-value combinational signals
    // =====================================================================
    reg [ADDR_WIDTH-1:0]  pc_n;
    reg [DATA_WIDTH-1:0]  wr_data_n [0:7];
    reg                   wr_en_n   [0:7];
    integer i;

    // =====================================================================
    // LOAD pipeline: BRAM has 1-cycle read latency.
    // We latch the destination register index and a "load pending" flag,
    // then write the BRAM output into the register on the NEXT cycle.
    // =====================================================================
    reg                  load_pending;   // a LOAD was issued last cycle
    reg [2:0]            load_dst;       // destination register of that LOAD

    // =====================================================================
    // Combinational execution stage
    // =====================================================================
    always @(*) begin
        // Defaults
        pc_n     = (!en_int) ? PC : (PC + 1'b1);
        mem_en   = 1'b0;
        mem_we   = 4'b0000;
        mem_addr = {ADDR_WIDTH{1'b0}};
        mem_din  = {DATA_WIDTH{1'b0}};

        for (i = 0; i < 8; i = i + 1) begin
            wr_en_n[i]   = 1'b0;
            wr_data_n[i] = R[i];
        end

        if (en_int) begin
            case (opcode)
                OP_ADD: begin
                    wr_en_n[op0]   = 1'b1;
                    wr_data_n[op0] = R[op1] + R[op2];
                end

                OP_SUB: begin
                    wr_en_n[op0]   = 1'b1;
                    wr_data_n[op0] = R[op1] - R[op2];
                end

                OP_LOAD: begin
                    // Address to BRAM; result captured next cycle via load_pending
                    mem_en   = 1'b1;
                    mem_we   = 4'b0000;                     // read
                    mem_addr = R[op1][ADDR_WIDTH-1:0];
                    // wr_en_n[op0] left 0 here; written in sequential block
                    // the cycle after, when mem_dout is valid
                end

                OP_STORE: begin
                    mem_en   = 1'b1;
                    mem_we   = 4'b1111;                     // write all bytes
                    mem_addr = R[op0][ADDR_WIDTH-1:0];
                    mem_din  = R[op1];
                end

                OP_JMP: begin
                    pc_n = R[op0][ADDR_WIDTH-1:0];
                end

                OP_HALT: begin
                    pc_n = PC;   // freeze PC; halted flag set in sequential block
                end

                default: ;   // NOP / unknown: PC already incremented above
            endcase
        end
    end

    // =====================================================================
    // Sequential stage
    // =====================================================================
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            PC           <= {ADDR_WIDTH{1'b0}};
            halted       <= 1'b0;
            load_pending <= 1'b0;
            load_dst     <= 3'b000;
            for (k = 0; k < 8; k = k + 1)
                R[k] <= {DATA_WIDTH{1'b0}};
        end else begin
            // ------------------------------------------------------------------
            // LOAD write-back: one cycle after the BRAM read was issued
            // ------------------------------------------------------------------
            load_pending <= 1'b0;   // default: clear
            if (load_pending) begin
                R[load_dst] <= mem_dout;
            end

            if (en_int) begin
                // Normal register write-backs (ALU results)
                for (k = 0; k < 8; k = k + 1) begin
                    if (wr_en_n[k]) R[k] <= wr_data_n[k];
                end

                // Advance PC
                PC <= pc_n;

                // Set HALT flag
                if (opcode == OP_HALT)
                    halted <= 1'b1;

                // Arm LOAD pipeline
                if (opcode == OP_LOAD) begin
                    load_pending <= 1'b1;
                    load_dst     <= op0;
                end
            end
            // When stopped (stop=1) or not started: hold all state,
            // but still allow a pending LOAD write-back to complete.
        end
    end

endmodule