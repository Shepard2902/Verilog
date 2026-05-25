`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2026 01:24:28 PM
// Design Name: 
// Module Name: axi4_lite_master
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
// axi4_lite_master.v
// AXI4-Lite Master Interface for MemCtrl <-> Xilinx UART LogiCORE
//
// The UART LogiCORE is the AXI4-Lite slave.
// MemCtrl (this module's user) drives read/write requests; results come back
// one clock later (registered slave, latency = 2 AXI cycles).
//
// Xilinx AXI UART16550 / AXI Uartlite register map (byte addresses):
//   AXI Uartlite:
//     0x00  RX FIFO  (read)
//     0x04  TX FIFO  (write)
//     0x08  STAT REG (read)
//     0x0C  CTRL REG (read/write)
//
// Only the lowest byte of each 32-bit word carries data.
// =============================================================================


module axi4_lite_master #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32
)(
    // -------------------------------------------------------------------------
    // System
    // -------------------------------------------------------------------------
    input  wire                   clk,
    input  wire                   rst_n,          // active-low synchronous reset

    // -------------------------------------------------------------------------
    // Simple command interface (from MemCtrl FSM)
    // -------------------------------------------------------------------------
    input  wire                   cmd_valid,      // pulse: start a transaction
    input  wire                   cmd_wr,         // 1=write, 0=read
    input  wire [ADDR_WIDTH-1:0]  cmd_addr,       // AXI byte address
    input  wire [DATA_WIDTH-1:0]  cmd_wdata,      // write data (only [7:0] used)
    output reg                    cmd_ready,      // FSM may issue next command

    output reg                    rsp_valid,      // read data valid
    output reg  [DATA_WIDTH-1:0]  rsp_rdata,      // read data from slave

    // -------------------------------------------------------------------------
    // AXI4-Lite Master ports (connect to UART LogiCORE S_AXI_* slave port)
    // -------------------------------------------------------------------------
    // Write Address Channel
    output reg  [ADDR_WIDTH-1:0]  M_AXI_AWADDR,
    output reg                    M_AXI_AWVALID,
    input  wire                   M_AXI_AWREADY,

    // Write Data Channel
    output reg  [DATA_WIDTH-1:0]  M_AXI_WDATA,
    output reg  [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output reg                    M_AXI_WVALID,
    input  wire                   M_AXI_WREADY,

    // Write Response Channel
    input  wire [1:0]             M_AXI_BRESP,
    input  wire                   M_AXI_BVALID,
    output reg                    M_AXI_BREADY,

    // Read Address Channel
    output reg  [ADDR_WIDTH-1:0]  M_AXI_ARADDR,
    output reg                    M_AXI_ARVALID,
    input  wire                   M_AXI_ARREADY,

    // Read Data Channel
    input  wire [DATA_WIDTH-1:0]  M_AXI_RDATA,
    input  wire [1:0]             M_AXI_RRESP,
    input  wire                   M_AXI_RVALID,
    output reg                    M_AXI_RREADY
);

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_WR_ADDR   = 3'd1,   // drive AW + W channels simultaneously
        S_WR_RESP   = 3'd2,   // wait for BVALID
        S_RD_ADDR   = 3'd3,   // drive AR channel
        S_RD_DATA   = 3'd4;   // wait for RVALID

    reg [2:0] state, next;

    // Track which write channels have been accepted (AXI4 compliance)
    reg aw_done, w_done;

    // -------------------------------------------------------------------------
    // Latch command on acceptance
    // -------------------------------------------------------------------------
    reg                   lat_wr;
    reg [ADDR_WIDTH-1:0]  lat_addr;
    reg [DATA_WIDTH-1:0]  lat_wdata;

    always @(posedge clk) begin
        if (!rst_n) begin
            lat_wr    <= 1'b0;
            lat_addr  <= {ADDR_WIDTH{1'b0}};
            lat_wdata <= {DATA_WIDTH{1'b0}};
        end else if (cmd_valid && cmd_ready) begin
            lat_wr    <= cmd_wr;
            lat_addr  <= cmd_addr;
            lat_wdata <= cmd_wdata;
        end
    end

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next;
    end

    // -------------------------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next = state;
        case (state)
            S_IDLE:
                if (cmd_valid)
                    next = cmd_wr ? S_WR_ADDR : S_RD_ADDR;

            S_WR_ADDR:
                // Both channels must be accepted before proceeding
                if ((M_AXI_AWREADY || aw_done) && (M_AXI_WREADY || w_done))
                    next = S_WR_RESP;
                else
                    next = S_WR_ADDR;

            S_WR_RESP:
                if (M_AXI_BVALID)
                    next = S_IDLE;

            S_RD_ADDR:
                if (M_AXI_ARREADY)
                    next = S_RD_DATA;

            S_RD_DATA:
                if (M_AXI_RVALID)
                    next = S_IDLE;

            default: next = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            cmd_ready      <= 1'b1;
            rsp_valid      <= 1'b0;
            rsp_rdata      <= {DATA_WIDTH{1'b0}};
            aw_done        <= 1'b0;
            w_done         <= 1'b0;

            M_AXI_AWADDR   <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWVALID  <= 1'b0;
            M_AXI_WDATA    <= {DATA_WIDTH{1'b0}};
            M_AXI_WSTRB    <= 4'b0001;   // only byte 0
            M_AXI_WVALID   <= 1'b0;
            M_AXI_BREADY   <= 1'b1;      // always ready to accept response
            M_AXI_ARADDR   <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARVALID  <= 1'b0;
            M_AXI_RREADY   <= 1'b1;      // always ready to accept read data
        end else begin
            // defaults
            rsp_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_ready     <= 1'b1;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_ARVALID <= 1'b0;

                    if (cmd_valid && cmd_ready) begin
                        cmd_ready <= 1'b0;   // busy
                        aw_done   <= 1'b0;
                        w_done    <= 1'b0;
                        if (cmd_wr) begin
                            M_AXI_AWADDR  <= cmd_addr;
                            M_AXI_AWVALID <= 1'b1;
                            M_AXI_WDATA   <= {24'b0, cmd_wdata[7:0]};
                            M_AXI_WSTRB   <= 4'b0001;
                            M_AXI_WVALID  <= 1'b1;
                        end else begin
                            M_AXI_ARADDR  <= cmd_addr;
                            M_AXI_ARVALID <= 1'b1;
                        end
                    end
                end

                S_WR_ADDR: begin
                    // Deassert each channel once accepted; track with flags
                    if (M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (M_AXI_WREADY) begin
                        M_AXI_WVALID  <= 1'b0;
                        w_done        <= 1'b1;
                    end
                end

                S_WR_RESP: begin
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    if (M_AXI_BVALID) begin
                        cmd_ready <= 1'b1;   // ready for next command
                    end
                end

                S_RD_ADDR: begin
                    if (M_AXI_ARREADY) M_AXI_ARVALID <= 1'b0;
                end

                S_RD_DATA: begin
                    M_AXI_ARVALID <= 1'b0;
                    if (M_AXI_RVALID) begin
                        rsp_valid <= 1'b1;
                        rsp_rdata <= M_AXI_RDATA;
                        cmd_ready <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
