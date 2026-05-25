`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2026 01:23:02 PM
// Design Name: 
// Module Name: block_memory
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
// block_memory.v
// Simple dual-port BRAM following Xilinx recommended template.
//
// Port A : RISC core (read/write, synchronous)
// Port B : MemCtrl   (read/write, synchronous)
//
// Width  : 32 bits
// Depth  : configurable via MEM_DEPTH parameter (default 1024 words = 4 KB)
//
// Xilinx synthesis will infer this as a RAMB36/RAMB18 block memory.
// =============================================================================

module block_memory #(
    parameter MEM_DEPTH = 1024,                          // number of 32-bit words
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH)
)(
    // -------------------------------------------------------------------------
    // Port A  �  RISC core
    // -------------------------------------------------------------------------
    input  wire                   clk_a,
    input  wire                   en_a,       // port enable
    input  wire [3:0]             we_a,       // byte-lane write enable
    input  wire [ADDR_WIDTH-1:0]  addr_a,
    input  wire [31:0]            din_a,
    output reg  [31:0]            dout_a,

    // -------------------------------------------------------------------------
    // Port B  �  Memory Controller
    // -------------------------------------------------------------------------
    input  wire                   clk_b,
    input  wire                   en_b,
    input  wire [3:0]             we_b,
    input  wire [ADDR_WIDTH-1:0]  addr_b,
    input  wire [31:0]            din_b,
    output reg  [31:0]            dout_b
);

    // -------------------------------------------------------------------------
    // Memory array
    // Xilinx template: (* ram_style = "block" *) forces BRAM inference
    // -------------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [31:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------------------------
    // Port A � synchronous read / byte-lane write
    // -------------------------------------------------------------------------
    always @(posedge clk_a) begin
        if (en_a) begin
            if (we_a[0]) mem[addr_a][ 7: 0] <= din_a[ 7: 0];
            if (we_a[1]) mem[addr_a][15: 8] <= din_a[15: 8];
            if (we_a[2]) mem[addr_a][23:16] <= din_a[23:16];
            if (we_a[3]) mem[addr_a][31:24] <= din_a[31:24];
            dout_a <= mem[addr_a];
        end
    end

    // -------------------------------------------------------------------------
    // Port B � synchronous read / byte-lane write
    // -------------------------------------------------------------------------
    always @(posedge clk_b) begin
        if (en_b) begin
            if (we_b[0]) mem[addr_b][ 7: 0] <= din_b[ 7: 0];
            if (we_b[1]) mem[addr_b][15: 8] <= din_b[15: 8];
            if (we_b[2]) mem[addr_b][23:16] <= din_b[23:16];
            if (we_b[3]) mem[addr_b][31:24] <= din_b[31:24];
            dout_b <= mem[addr_b];
        end
    end

endmodule