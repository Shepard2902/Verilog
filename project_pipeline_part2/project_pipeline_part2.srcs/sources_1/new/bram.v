`include "macros.vh"

// True Dual-Port Block RAM
// Follows Xilinx UG901 "True Dual-Port RAM, Read-First" template so Vivado
// infers a RAMB36 / RAMB18 primitive instead of LUT-based memory.
//
// Port A – Processor data memory (existing read/write interface)
// Port B – MemCtrl host-side access (load / inspect memory from UART host)
//
// Both ports share the same underlying array; simultaneous access to the same
// address from both ports is collision-undefined (by design: host only accesses
// memory while the CPU is stopped).

module DataBRAM #(
    parameter DATA_WIDTH = `D_SIZE,   // 32 bits
    parameter ADDR_WIDTH = `A_SIZE,   // 10 bits  → 1024 words
    parameter DEPTH      = 1024
)(
    // ── Port A : Processor ────────────────────────────────────────────────
    input                        clka,
    input                        ena,   // enable (read or write cycle)
    input                        wea,   // write enable
    input  [ADDR_WIDTH-1:0]      addra,
    input  [DATA_WIDTH-1:0]      dina,
    output reg [DATA_WIDTH-1:0]  douta,

    // ── Port B : MemCtrl ──────────────────────────────────────────────────
    input                        clkb,
    input                        enb,
    input                        web,
    input  [ADDR_WIDTH-1:0]      addrb,
    input  [DATA_WIDTH-1:0]      dinb,
    output reg [DATA_WIDTH-1:0]  doutb
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Port A – read-first (data at address is read before write takes effect)
    always @(posedge clka) begin
        if (ena) begin
            if (wea)
                mem[addra] <= dina;
            douta <= mem[addra];
        end
    end

    // Port B – read-first
    always @(posedge clkb) begin
        if (enb) begin
            if (web)
                mem[addrb] <= dinb;
            doutb <= mem[addrb];
        end
    end

endmodule
