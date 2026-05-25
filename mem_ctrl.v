`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2026 12:52:23 PM
// Design Name: 
// Module Name: mem_ctrl
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
// mem_ctrl.v
// Memory Controller FSM
//
// Packet format (host -> MemCtrl, all fields 1 byte unless noted):
//
//  CMD_RESET  : [ 0x01 ]
//  CMD_STOP   : [ 0x02 ]
//  CMD_START  : [ 0x03 ]
//  CMD_WRITE  : [ 0x04 | ADDR(4B, MSB first) | LEN(2B, MSB first) | DATA(LEN*4B) ]
//  CMD_READ   : [ 0x05 | ADDR(4B, MSB first) | LEN(2B, MSB first) ]
//
// Response (MemCtrl -> host):
//  CMD_WRITE  : [ 0xAA ]                  (ACK byte)
//  CMD_READ   : [ DATA(LEN*4B) ] [ 0xAA ] (data words, MSB first, then ACK)
//  CMD_RESET/STOP/START : [ 0xAA ]
//
// AXI Uartlite register offsets (byte addresses from UART base):
//   0x00  RX_FIFO
//   0x04  TX_FIFO
//   0x08  STAT_REG  [0]=RX valid  [3]=TX full
//   0x0C  CTRL_REG
//
// =============================================================================

module mem_ctrl #(
    parameter MEM_DEPTH  = 1024,
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH),
    parameter UART_BASE  = 32'h4060_0000    // AXI base address of UART IP
)(
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // AXI4-Lite master ports (routed to axi4_lite_master instance)
    // -------------------------------------------------------------------------
    output wire        axi_cmd_valid,
    output wire        axi_cmd_wr,
    output wire [31:0] axi_cmd_addr,
    output wire [31:0] axi_cmd_wdata,
    input  wire        axi_cmd_ready,
    input  wire        axi_rsp_valid,
    input  wire [31:0] axi_rsp_rdata,

    // -------------------------------------------------------------------------
    // BRAM port B interface (MemCtrl side)
    // -------------------------------------------------------------------------
    output reg                    mem_en,
    output reg  [3:0]             mem_we,
    output reg  [ADDR_WIDTH-1:0]  mem_addr,
    output reg  [31:0]            mem_din,
    input  wire [31:0]            mem_dout,

    // -------------------------------------------------------------------------
    // RISC core control
    // -------------------------------------------------------------------------
    output reg        risc_reset,    // active-high, held asserted while reset
    output reg        risc_stop,     // active-high freeze (PC stops)
    output reg        risc_start     // active-high run enable
);

    // =========================================================================
    // UART register addresses (absolute byte addresses)
    // =========================================================================
    localparam UART_RX_FIFO  = UART_BASE + 32'h00;
    localparam UART_TX_FIFO  = UART_BASE + 32'h04;
    localparam UART_STAT_REG = UART_BASE + 32'h08;
    localparam UART_CTRL_REG = UART_BASE + 32'h0C;

    // STAT_REG bit positions
    localparam STAT_RX_VALID = 0;   // bit 0: RX FIFO has data
    localparam STAT_TX_FULL  = 3;   // bit 3: TX FIFO full

    // =========================================================================
    // Command codes
    // =========================================================================
    localparam CMD_RESET = 8'h01;
    localparam CMD_STOP  = 8'h02;
    localparam CMD_START = 8'h03;
    localparam CMD_WRITE = 8'h04;
    localparam CMD_READ  = 8'h05;
    localparam ACK_BYTE  = 8'hAA;

    // =========================================================================
    // FSM state encoding
    // =========================================================================
    localparam [5:0]
        // --- Idle / read UART status ---
        S_IDLE            = 6'd0,
        S_READ_STAT       = 6'd1,   // issue AXI read of STAT_REG
        S_WAIT_STAT       = 6'd2,   // wait for AXI read response
        S_READ_RX         = 6'd3,   // issue AXI read of RX_FIFO
        S_WAIT_RX         = 6'd4,   // wait for byte from UART

        // --- Dispatch on received command byte ---
        S_DISPATCH        = 6'd5,

        // --- RESET / STOP / START (simple 1-byte commands) ---
        S_DO_CTRL         = 6'd6,   // apply RISC control signals
        S_SEND_ACK        = 6'd7,   // check TX not full
        S_WAIT_TX_RDY     = 6'd8,
        S_WRITE_TX        = 6'd9,   // write ACK to TX_FIFO
        S_WAIT_TX_DONE    = 6'd10,

        // --- Receive 4-byte address field ---
        S_RX_ADDR_STAT    = 6'd11,
        S_RX_ADDR_WAIT    = 6'd12,
        S_RX_ADDR_RX      = 6'd13,
        S_RX_ADDR_WAIT_RX = 6'd14,
        S_RX_ADDR_STORE   = 6'd15,

        // --- Receive 2-byte length field ---
        S_RX_LEN_STAT     = 6'd16,
        S_RX_LEN_WAIT     = 6'd17,
        S_RX_LEN_RX       = 6'd18,
        S_RX_LEN_WAIT_RX  = 6'd19,
        S_RX_LEN_STORE    = 6'd20,

        // --- WRITE command: receive data bytes, assemble words, write mem ---
        S_WR_BYTE_STAT    = 6'd21,
        S_WR_BYTE_WAIT    = 6'd22,
        S_WR_BYTE_RX      = 6'd23,
        S_WR_BYTE_WAIT_RX = 6'd24,
        S_WR_BYTE_STORE   = 6'd25,
        S_WR_MEM          = 6'd26,  // write assembled word to BRAM
        S_WR_MEM_DONE     = 6'd27,

        // --- READ command: read mem word, split into bytes, send via UART ---
        S_RD_MEM          = 6'd28,
        S_RD_MEM_WAIT     = 6'd29,  // BRAM read latency = 1 cycle
        S_RD_TX_STAT      = 6'd30,
        S_RD_TX_WAIT      = 6'd31,
        S_RD_TX_BYTE      = 6'd32,
        S_RD_TX_WAIT_DONE = 6'd33;

    reg [5:0] state, next_state;

    // =========================================================================
    // Data path registers
    // =========================================================================
    reg [7:0]  rx_byte;           // last byte received from UART
    reg [7:0]  cmd_reg;           // captured command byte

    reg [31:0] pkt_addr;          // packet start address (byte-addressed host)
    reg [1:0]  addr_cnt;          // 0..3, counting received address bytes

    reg [15:0] pkt_len;           // number of 32-bit words
    reg [0:0]  len_cnt;           // 0..1, counting received length bytes

    reg [31:0] word_buf;          // byte assembly buffer for incoming data
    reg [1:0]  byte_cnt;          // 0..3, byte position inside current word
    reg [15:0] word_cnt;          // counts words processed

    reg [31:0] mem_word;          // word read from BRAM for TX
    reg [1:0]  tx_byte_cnt;       // 0..3, byte being transmitted

    // =========================================================================
    // AXI command interface (registered outputs)
    // =========================================================================
    reg        r_axi_cmd_valid;
    reg        r_axi_cmd_wr;
    reg [31:0] r_axi_cmd_addr;
    reg [31:0] r_axi_cmd_wdata;

    assign axi_cmd_valid = r_axi_cmd_valid;
    assign axi_cmd_wr    = r_axi_cmd_wr;
    assign axi_cmd_addr  = r_axi_cmd_addr;
    assign axi_cmd_wdata = r_axi_cmd_wdata;

    // Helper: extract one TX byte from mem_word (MSB first = byte 3..0)
    wire [7:0] tx_byte_sel = (tx_byte_cnt == 2'd0) ? mem_word[31:24] :
                             (tx_byte_cnt == 2'd1) ? mem_word[23:16] :
                             (tx_byte_cnt == 2'd2) ? mem_word[15: 8] :
                                                     mem_word[ 7: 0];

    // Memory word address derived from packet byte address + word index
    wire [ADDR_WIDTH-1:0] cur_mem_addr =
        pkt_addr[ADDR_WIDTH+1:2] + word_cnt[ADDR_WIDTH-1:0];

    // =========================================================================
    // State register
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // =========================================================================
    // Main FSM � next-state + output logic (Mealy style, registered outputs)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            next_state       <= S_IDLE;
            r_axi_cmd_valid  <= 1'b0;
            r_axi_cmd_wr     <= 1'b0;
            r_axi_cmd_addr   <= 32'h0;
            r_axi_cmd_wdata  <= 32'h0;
            mem_en           <= 1'b0;
            mem_we           <= 4'b0000;
            mem_addr         <= {ADDR_WIDTH{1'b0}};
            mem_din          <= 32'h0;
            risc_reset       <= 1'b0;
            risc_stop        <= 1'b0;
            risc_start       <= 1'b0;
            rx_byte          <= 8'h0;
            cmd_reg          <= 8'h0;
            pkt_addr         <= 32'h0;
            addr_cnt         <= 2'b00;
            pkt_len          <= 16'h0;
            len_cnt          <= 1'b0;
            word_buf         <= 32'h0;
            byte_cnt         <= 2'b00;
            word_cnt         <= 16'h0;
            mem_word         <= 32'h0;
            tx_byte_cnt      <= 2'b00;
        end else begin
            // Default: deassert strobes
            r_axi_cmd_valid <= 1'b0;
            mem_en          <= 1'b0;
            mem_we          <= 4'b0000;

            case (state)
                // =============================================================
                // IDLE � begin polling UART status
                // =============================================================
                S_IDLE: begin
                    next_state <= S_READ_STAT;
                end

                // =============================================================
                // Poll UART STAT_REG for RX data available
                // =============================================================
                S_READ_STAT: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_WAIT_STAT;
                    end
                end

                S_WAIT_STAT: begin
                    if (axi_rsp_valid) begin
                        if (axi_rsp_rdata[STAT_RX_VALID])
                            next_state <= S_READ_RX;
                        else
                            next_state <= S_READ_STAT;  // poll again
                    end
                end

                // =============================================================
                // Read one byte from RX_FIFO
                // =============================================================
                S_READ_RX: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_RX_FIFO;
                        next_state      <= S_WAIT_RX;
                    end
                end

                S_WAIT_RX: begin
                    if (axi_rsp_valid) begin
                        rx_byte    <= axi_rsp_rdata[7:0];
                        next_state <= S_DISPATCH;
                    end
                end

                // =============================================================
                // Decode command byte
                // =============================================================
                S_DISPATCH: begin
                    cmd_reg    <= rx_byte;
                    addr_cnt   <= 2'd0;
                    len_cnt    <= 1'd0;
                    word_cnt   <= 16'd0;
                    byte_cnt   <= 2'd0;
                    case (rx_byte)
                        CMD_RESET,
                        CMD_STOP,
                        CMD_START:  next_state <= S_DO_CTRL;
                        CMD_WRITE,
                        CMD_READ:   next_state <= S_RX_ADDR_STAT;
                        default:    next_state <= S_IDLE;  // unknown, ignore
                    endcase
                end

                // =============================================================
                // Apply RISC core control
                // =============================================================
                S_DO_CTRL: begin
                    case (cmd_reg)
                        CMD_RESET: begin
                            risc_reset <= 1'b1;
                            risc_stop  <= 1'b1;
                            risc_start <= 1'b0;
                        end
                        CMD_STOP: begin
                            risc_reset <= 1'b0;
                            risc_stop  <= 1'b1;
                            risc_start <= 1'b0;
                        end
                        CMD_START: begin
                            risc_reset <= 1'b0;
                            risc_stop  <= 1'b0;
                            risc_start <= 1'b1;
                        end
                        default: ;
                    endcase
                    next_state <= S_SEND_ACK;
                end

                // =============================================================
                // Send ACK byte back to host
                // =============================================================
                S_SEND_ACK: begin
                    // Release reset after exactly one cycle (the S_DO_CTRL cycle)
                    if (cmd_reg == CMD_RESET)
                        risc_reset <= 1'b0;
                    next_state <= S_WAIT_TX_RDY;
                end

                S_WAIT_TX_RDY: begin
                    // Read STAT_REG to check TX not full
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_WRITE_TX;
                    end
                end

                S_WRITE_TX: begin
                    if (axi_rsp_valid) begin
                        if (!axi_rsp_rdata[STAT_TX_FULL]) begin
                            // TX FIFO has space, write the byte
                            r_axi_cmd_valid <= 1'b1;
                            r_axi_cmd_wr    <= 1'b1;
                            r_axi_cmd_addr  <= UART_TX_FIFO;
                            r_axi_cmd_wdata <= {24'b0, ACK_BYTE};
                            next_state      <= S_WAIT_TX_DONE;
                        end else begin
                            next_state <= S_WAIT_TX_RDY;  // retry
                        end
                    end
                end

                S_WAIT_TX_DONE: begin
                    if (axi_cmd_ready)
                        next_state <= S_IDLE;
                end

                // =============================================================
                // Receive 4-byte address field (MSB first)
                // =============================================================
                S_RX_ADDR_STAT: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_RX_ADDR_WAIT;
                    end
                end

                S_RX_ADDR_WAIT: begin
                    if (axi_rsp_valid) begin
                        if (axi_rsp_rdata[STAT_RX_VALID])
                            next_state <= S_RX_ADDR_RX;
                        else
                            next_state <= S_RX_ADDR_STAT;
                    end
                end

                S_RX_ADDR_RX: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_RX_FIFO;
                        next_state      <= S_RX_ADDR_WAIT_RX;
                    end
                end

                S_RX_ADDR_WAIT_RX: begin
                    if (axi_rsp_valid) begin
                        rx_byte    <= axi_rsp_rdata[7:0];
                        next_state <= S_RX_ADDR_STORE;
                    end
                end

                S_RX_ADDR_STORE: begin
                    // Shift in MSB first
                    pkt_addr <= {pkt_addr[23:0], rx_byte};
                    addr_cnt <= addr_cnt + 1'b1;
                    if (addr_cnt == 2'd3)
                        next_state <= S_RX_LEN_STAT;
                    else
                        next_state <= S_RX_ADDR_STAT;
                end

                // =============================================================
                // Receive 2-byte length field (MSB first)
                // =============================================================
                S_RX_LEN_STAT: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_RX_LEN_WAIT;
                    end
                end

                S_RX_LEN_WAIT: begin
                    if (axi_rsp_valid) begin
                        if (axi_rsp_rdata[STAT_RX_VALID])
                            next_state <= S_RX_LEN_RX;
                        else
                            next_state <= S_RX_LEN_STAT;
                    end
                end

                S_RX_LEN_RX: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_RX_FIFO;
                        next_state      <= S_RX_LEN_WAIT_RX;
                    end
                end

                S_RX_LEN_WAIT_RX: begin
                    if (axi_rsp_valid) begin
                        rx_byte    <= axi_rsp_rdata[7:0];
                        next_state <= S_RX_LEN_STORE;
                    end
                end

                S_RX_LEN_STORE: begin
                    pkt_len <= {pkt_len[7:0], rx_byte};
                    len_cnt <= len_cnt + 1'b1;
                    if (len_cnt == 1'd1) begin
                        // Both length bytes received
                        if (cmd_reg == CMD_WRITE)
                            next_state <= S_WR_BYTE_STAT;
                        else
                            next_state <= S_RD_MEM;
                    end else begin
                        next_state <= S_RX_LEN_STAT;
                    end
                end

                // =============================================================
                // WRITE: receive bytes, assemble 32-bit words, write to BRAM
                // =============================================================
                S_WR_BYTE_STAT: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_WR_BYTE_WAIT;
                    end
                end

                S_WR_BYTE_WAIT: begin
                    if (axi_rsp_valid) begin
                        if (axi_rsp_rdata[STAT_RX_VALID])
                            next_state <= S_WR_BYTE_RX;
                        else
                            next_state <= S_WR_BYTE_STAT;
                    end
                end

                S_WR_BYTE_RX: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_RX_FIFO;
                        next_state      <= S_WR_BYTE_WAIT_RX;
                    end
                end

                S_WR_BYTE_WAIT_RX: begin
                    if (axi_rsp_valid) begin
                        rx_byte    <= axi_rsp_rdata[7:0];
                        next_state <= S_WR_BYTE_STORE;
                    end
                end

                S_WR_BYTE_STORE: begin
                    // Assemble MSB-first into word_buf
                    word_buf  <= {word_buf[23:0], rx_byte};
                    byte_cnt  <= byte_cnt + 1'b1;
                    if (byte_cnt == 2'd3)
                        next_state <= S_WR_MEM;
                    else
                        next_state <= S_WR_BYTE_STAT;
                end

                S_WR_MEM: begin
                    // Write assembled word to BRAM; word_buf holds all 4 bytes
                    mem_en   <= 1'b1;
                    mem_we   <= 4'b1111;
                    mem_addr <= cur_mem_addr;
                    mem_din  <= word_buf;
                    next_state <= S_WR_MEM_DONE;
                end

                S_WR_MEM_DONE: begin
                    word_cnt   <= word_cnt + 1'b1;
                    byte_cnt   <= 2'd0;
                    if (word_cnt + 1 == pkt_len)
                        next_state <= S_SEND_ACK;    // done, send ACK
                    else
                        next_state <= S_WR_BYTE_STAT;
                end

                // =============================================================
                // READ: read word from BRAM, transmit 4 bytes MSB first
                // =============================================================
                S_RD_MEM: begin
                    mem_en     <= 1'b1;
                    mem_we     <= 4'b0000;
                    mem_addr   <= cur_mem_addr;
                    next_state <= S_RD_MEM_WAIT;
                end

                S_RD_MEM_WAIT: begin
                    // Latch BRAM output after 1 read latency cycle
                    mem_word    <= mem_dout;
                    tx_byte_cnt <= 2'd0;
                    next_state  <= S_RD_TX_STAT;
                end

                S_RD_TX_STAT: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b0;
                        r_axi_cmd_addr  <= UART_STAT_REG;
                        next_state      <= S_RD_TX_WAIT;
                    end
                end

                S_RD_TX_WAIT: begin
                    if (axi_rsp_valid) begin
                        if (!axi_rsp_rdata[STAT_TX_FULL])
                            next_state <= S_RD_TX_BYTE;
                        else
                            next_state <= S_RD_TX_STAT;  // wait for space
                    end
                end

                S_RD_TX_BYTE: begin
                    if (axi_cmd_ready) begin
                        r_axi_cmd_valid <= 1'b1;
                        r_axi_cmd_wr    <= 1'b1;
                        r_axi_cmd_addr  <= UART_TX_FIFO;
                        r_axi_cmd_wdata <= {24'b0, tx_byte_sel};
                        next_state      <= S_RD_TX_WAIT_DONE;
                    end
                end

                S_RD_TX_WAIT_DONE: begin
                    if (axi_cmd_ready) begin
                        tx_byte_cnt <= tx_byte_cnt + 1'b1;
                        if (tx_byte_cnt == 2'd3) begin
                            // All 4 bytes of this word sent
                            word_cnt <= word_cnt + 1'b1;
                            if (word_cnt + 1 == pkt_len)
                                next_state <= S_SEND_ACK;
                            else
                                next_state <= S_RD_MEM;
                        end else begin
                            next_state <= S_RD_TX_STAT;
                        end
                    end
                end

                default: next_state <= S_IDLE;
            endcase
        end
    end

endmodule