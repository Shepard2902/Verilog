`include "macros.vh"

// Top-level module
//
// Integration
// ───────────
//  • Procesor      – 5-stage pipelined Simple RISC CPU
//  • Program_Memory – read-only instruction memory (ROM, unchanged)
//  • DataBRAM       – dual-port block RAM for data memory
//                     Port A  → Processor  (existing interface)
//                     Port B  → MemCtrl    (host read/write via UART)
//  • MemCtrl        – AXI4-Lite master to AXI UART Lite; host protocol FSM
//
// AXI UART Lite connection
// ────────────────────────
// The AXI4-Lite master signals (m_axi_*) are exposed as top-level ports so
// that the module can be connected to a Xilinx AXI UART Lite IP instance
// in a Vivado block design or at a higher-level wrapper.
//
// Reset scheme
// ────────────
// rst_n (active-low) resets MemCtrl.  MemCtrl drives cpu_reset_n and cpu_en
// to the processor; the CPU is held in reset/stop until the host issues
// CMD_START.  This allows the host to load a program into data BRAM before
// releasing the CPU.
//
// Memory access gating
// ────────────────────
// Processor BRAM Port A reads/writes are gated by cpu_en so that a stalled
// execute stage cannot produce spurious memory transactions while the CPU
// is stopped.

module Top #(
    parameter [31:0] UART_BASE      = 32'h4060_0000,
    parameter        MEM_ADDR_WIDTH = `A_SIZE          // 10
)(
    input  wire clk,
    input  wire rst_n,    // active-low system reset (from board)

    // ── AXI4-Lite Master port (connect to AXI UART Lite S_AXI) ──────────
    // Write Address Channel
    output wire [31:0] m_axi_awaddr,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    // Write Data Channel
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    // Write Response Channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    // Read Address Channel
    output wire [31:0] m_axi_araddr,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    // Read Data Channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);

    // ── CPU control wires (driven by MemCtrl) ────────────────────────────
    wire cpu_reset_n;   // active-low synchronous reset to Procesor
    wire cpu_en;        // active-high run-enable

    // ── Processor ↔ memories wires ───────────────────────────────────────
    wire [`INSTRSIZE-1:0] instruction;
    wire [`A_SIZE-1:0]    instr_addr;
    wire [`A_SIZE-1:0]    data_addr;
    wire [`D_SIZE-1:0]    proc_data_out;  // processor → BRAM
    wire [`D_SIZE-1:0]    proc_data_in;   // BRAM → processor
    wire                  proc_read;
    wire                  proc_write;

    // Gate memory enables with cpu_en so a frozen execute stage cannot
    // issue spurious reads or writes to Port A.
    wire bram_a_en = (proc_read | proc_write) & cpu_en;
    wire bram_a_we = proc_write & cpu_en;

    // ── BRAM Port B wires (MemCtrl side) ─────────────────────────────────
    wire                       mc_bram_en;
    wire                       mc_bram_we;
    wire [MEM_ADDR_WIDTH-1:0]  mc_bram_addr;
    wire [31:0]                mc_bram_din;
    wire [31:0]                mc_bram_dout;

    // ── Processor instance ───────────────────────────────────────────────
    Procesor processor(
        .clk(clk),
        .reset(cpu_reset_n),   // MemCtrl manages reset
        .cpu_en(cpu_en),
        .instruction(instruction),
        .data_in(proc_data_in),
        .read(proc_read),
        .write(proc_write),
        .pc(instr_addr),
        .addr(data_addr),
        .data_out(proc_data_out)
    );

    // ── Instruction memory (ROM – unchanged) ─────────────────────────────
    Program_Memory program_memory(
        .addr(instr_addr),
        .instruction(instruction)
    );

    // ── Data memory: True Dual-Port BRAM ─────────────────────────────────
    DataBRAM #(
        .DATA_WIDTH(`D_SIZE),
        .ADDR_WIDTH(MEM_ADDR_WIDTH),
        .DEPTH(2**MEM_ADDR_WIDTH)
    ) data_bram (
        // Port A – Processor
        .clka(clk),
        .ena(bram_a_en),
        .wea(bram_a_we),
        .addra(data_addr),
        .dina(proc_data_out),
        .douta(proc_data_in),
        // Port B – MemCtrl
        .clkb(clk),
        .enb(mc_bram_en),
        .web(mc_bram_we),
        .addrb(mc_bram_addr),
        .dinb(mc_bram_din),
        .doutb(mc_bram_dout)
    );

    // ── Memory Controller ─────────────────────────────────────────────────
    MemCtrl #(
        .UART_BASE(UART_BASE),
        .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) mem_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        // AXI4-Lite Master
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        // BRAM Port B
        .bram_en(mc_bram_en),
        .bram_we(mc_bram_we),
        .bram_addr(mc_bram_addr),
        .bram_din(mc_bram_din),
        .bram_dout(mc_bram_dout),
        // CPU control
        .cpu_reset_n(cpu_reset_n),
        .cpu_en(cpu_en)
    );

endmodule
