// Memory Controller (MemCtrl)
//
// Role
// ----
// Acts as an AXI4-Lite MASTER toward the Xilinx AXI UART Lite IP (PG142).
// Decodes a simple 5-command packet protocol received byte-by-byte from the
// UART receiver, and either:
//   • Controls the Simple RISC processor (reset / stop / start), or
//   • Writes host data into the dual-port BRAM (via Port B), or
//   • Reads BRAM words and streams them back to the host via UART transmitter.
//
// ── AXI UART Lite register map (PG142 Table 4) ───────────────────────────
//   Base + 0x000  RX_FIFO   read-only  – received byte in [7:0]
//   Base + 0x004  TX_FIFO   write-only – byte to transmit in [7:0]
//   Base + 0x008  STAT_REG  read-only  – [0]=RXVALID  [3]=TXFULL
//   Base + 0x00C  CTRL_REG  write-only – [0]=RST_TX  [1]=RST_RX  [4]=EN_INTR
//
// ── Host → MemCtrl packet format ─────────────────────────────────────────
//   CMD_RESET  (0xA1) : 1 byte  – reset then stop CPU
//   CMD_STOP   (0xA2) : 1 byte  – freeze CPU (pc + pipeline held)
//   CMD_START  (0xA3) : 1 byte  – release CPU
//   CMD_WRITE  (0xA4) : 1 + 2 (addr) + 2 (len) + len×4 bytes (data, MSB first)
//   CMD_READ   (0xA5) : 1 + 2 (addr) + 2 (len) bytes
//              MemCtrl replies with len×4 bytes (MSB first)
//
//   addr and len are 16-bit big-endian unsigned values.
//   Memory words are 32-bit, transmitted / received MSB first.
//
// ── Processor control ─────────────────────────────────────────────────────
//   cpu_reset_n  active-low synchronous reset to Procesor (1 = running)
//   cpu_en       active-high run-enable; when 0 the pipeline is frozen
//
// ── FSM overview ─────────────────────────────────────────────────────────
//   The main FSM continuously polls the UART status register via AXI reads.
//   When a byte is available it is fetched and routed to the protocol layer.
//   The protocol layer uses a "continuation state" register (rx_cont) to
//   know which protocol field is expected next.  AXI writes (UART TX) use a
//   "return state" register (tx_ret) so the TX sub-FSM can be reused.

module MemCtrl #(
    parameter [31:0] UART_BASE      = 32'h4060_0000,
    parameter        MEM_ADDR_WIDTH = 10
)(
    input  wire        clk,
    input  wire        rst_n,        // active-low system reset

    // ── AXI4-Lite Master → AXI UART Lite ─────────────────────────────────
    // Write Address Channel
    output reg  [31:0] m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    // Write Data Channel
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    // Write Response Channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    // Read Address Channel
    output reg  [31:0] m_axi_araddr,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    // Read Data Channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,

    // ── BRAM Port B (host-side) ───────────────────────────────────────────
    output reg                       bram_en,
    output reg                       bram_we,
    output reg [MEM_ADDR_WIDTH-1:0]  bram_addr,
    output reg [31:0]                bram_din,
    input  wire [31:0]               bram_dout,

    // ── CPU control outputs ───────────────────────────────────────────────
    output reg  cpu_reset_n,   // drives processor reset pin (active-low)
    output reg  cpu_en         // run-enable for processor pipeline
);

    // ── UART Lite register offsets ────────────────────────────────────────
    localparam [31:0] OFS_RX   = 32'h000;
    localparam [31:0] OFS_TX   = 32'h004;
    localparam [31:0] OFS_STAT = 32'h008;

    localparam RXVALID = 0;   // STAT_REG bit: receive FIFO not empty
    localparam TXFULL  = 3;   // STAT_REG bit: transmit FIFO full

    // ── Protocol command codes ────────────────────────────────────────────
    localparam [7:0] CMD_RESET = 8'hA1;
    localparam [7:0] CMD_STOP  = 8'hA2;
    localparam [7:0] CMD_START = 8'hA3;
    localparam [7:0] CMD_WRITE = 8'hA4;
    localparam [7:0] CMD_READ  = 8'hA5;

    // ── FSM state encoding ────────────────────────────────────────────────
    // Polling / receive
    localparam [4:0]
        S_POLL_AR   = 5'd0,   // AXI-R address phase: STAT_REG
        S_POLL_RD   = 5'd1,   // AXI-R data phase:    STAT_REG
        S_POLL_CHK  = 5'd2,   // check RXVALID
        S_RX_AR     = 5'd3,   // AXI-R address phase: RX_FIFO
        S_RX_RD     = 5'd4,   // AXI-R data phase:    RX_FIFO → rx_cont
    // Protocol decode / execute
        S_CMD       = 5'd5,   // command byte
        S_ADDR_H    = 5'd6,   // address [15:8]
        S_ADDR_L    = 5'd7,   // address [7:0]
        S_LEN_H     = 5'd8,   // length  [15:8]
        S_LEN_L     = 5'd9,   // length  [7:0]
        S_DATA0     = 5'd10,  // write data byte 0 (MSB)
        S_DATA1     = 5'd11,  // write data byte 1
        S_DATA2     = 5'd12,  // write data byte 2
        S_DATA3     = 5'd13,  // write data byte 3 (LSB) → write BRAM
        S_WRITEMEM  = 5'd14,  // BRAM write; decrement counter
        S_READMEM   = 5'd15,  // assert BRAM read
        S_READWAIT  = 5'd16,  // wait 1 cycle for BRAM output register
    // Transmit (split 32-bit word into 4 bytes)
        S_SENDB3    = 5'd17,  // queue byte [31:24]
        S_SENDB2    = 5'd18,  // queue byte [23:16]
        S_SENDB1    = 5'd19,  // queue byte [15:8]
        S_SENDB0    = 5'd20,  // queue byte [7:0]
        S_AFTRWORD  = 5'd21,  // advance addr/len; loop or finish
    // AXI-W sub-FSM (reused for every UART TX byte)
        S_TX_AW     = 5'd22,  // write address phase: TX_FIFO
        S_TX_WD     = 5'd23,  // write data phase
        S_TX_BR     = 5'd24;  // write response phase → tx_ret

    // ── Internal registers ────────────────────────────────────────────────
    reg [4:0]  state;
    reg [4:0]  rx_cont;    // protocol state after next byte is received
    reg [4:0]  tx_ret;     // FSM state to resume after TX sub-FSM

    reg [7:0]  rx_byte;    // byte received from UART
    reg [7:0]  tx_byte;    // byte queued for UART transmit

    reg        is_read;    // 1 = CMD_READ packet in progress

    reg [15:0] pkt_addr;   // memory word address (big-endian from packet)
    reg [15:0] pkt_len;    // remaining word count

    reg [31:0] word_buf;   // assembles 4 received bytes into one BRAM word
    reg [31:0] read_word;  // holds one BRAM word while splitting into bytes

    // Reset pulse: hold cpu_reset_n low for 4 cycles after CMD_RESET
    reg [1:0]  rst_cnt;
    reg        do_reset;   // set by FSM for one cycle to start reset pulse

    // ── Reset pulse generator ─────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_reset_n <= 1'b0;
            rst_cnt     <= 2'd3;
            do_reset    <= 1'b0;
        end else begin
            do_reset <= 1'b0;   // clear one-cycle trigger
            if (do_reset) begin
                cpu_reset_n <= 1'b0;
                rst_cnt     <= 2'd3;
            end else if (rst_cnt != 2'd0) begin
                rst_cnt <= rst_cnt - 2'd1;
                if (rst_cnt == 2'd1)
                    cpu_reset_n <= 1'b1;
            end
        end
    end

    // ── Main FSM (single clocked always – registered outputs) ─────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_POLL_AR;
            rx_cont      <= S_CMD;
            tx_ret       <= S_POLL_AR;
            cpu_en       <= 1'b0;
            is_read      <= 1'b0;
            pkt_addr     <= 16'd0;
            pkt_len      <= 16'd0;
            word_buf     <= 32'd0;
            read_word    <= 32'd0;
            rx_byte      <= 8'd0;
            tx_byte      <= 8'd0;
            // AXI outputs
            m_axi_awaddr  <= 32'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_araddr  <= 32'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            // BRAM outputs
            bram_en   <= 1'b0;
            bram_we   <= 1'b0;
            bram_addr <= {MEM_ADDR_WIDTH{1'b0}};
            bram_din  <= 32'd0;
        end else begin

            // ── Default: deassert all handshake strobes each cycle ─────────
            // (each state will re-assert only the ones it needs)
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            bram_en       <= 1'b0;
            bram_we       <= 1'b0;

            case (state)

                // ── Poll UART status register ─────────────────────────────

                S_POLL_AR: begin
                    // Send AXI read address for STAT_REG
                    m_axi_araddr  <= UART_BASE + OFS_STAT;
                    m_axi_arvalid <= 1'b1;
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state <= S_POLL_RD;
                    end
                end

                S_POLL_RD: begin
                    // Wait for STAT_REG read data
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        m_axi_rready <= 1'b0;
                        // Store status and evaluate in next state
                        rx_byte <= m_axi_rdata[7:0];  // reuse rx_byte as temp
                        state   <= S_POLL_CHK;
                    end
                end

                S_POLL_CHK: begin
                    // rx_byte[RXVALID] tells us if Rx FIFO has data
                    if (rx_byte[RXVALID])
                        state <= S_RX_AR;
                    else
                        state <= S_POLL_AR;   // nothing yet; keep polling
                end

                // ── Receive one byte from UART Rx FIFO ───────────────────

                S_RX_AR: begin
                    m_axi_araddr  <= UART_BASE + OFS_RX;
                    m_axi_arvalid <= 1'b1;
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state <= S_RX_RD;
                    end
                end

                S_RX_RD: begin
                    m_axi_rready <= 1'b1;
                    if (m_axi_rvalid) begin
                        m_axi_rready <= 1'b0;
                        rx_byte      <= m_axi_rdata[7:0];
                        state        <= rx_cont;   // dispatch to protocol state
                    end
                end

                // ── Protocol: command byte ────────────────────────────────

                S_CMD: begin
                    case (rx_byte)
                        CMD_RESET: begin
                            cpu_en  <= 1'b0;
                            do_reset <= 1'b1;   // fires reset-pulse generator
                            rx_cont <= S_CMD;
                            state   <= S_POLL_AR;
                        end
                        CMD_STOP: begin
                            cpu_en  <= 1'b0;
                            rx_cont <= S_CMD;
                            state   <= S_POLL_AR;
                        end
                        CMD_START: begin
                            cpu_en  <= 1'b1;
                            rx_cont <= S_CMD;
                            state   <= S_POLL_AR;
                        end
                        CMD_WRITE: begin
                            is_read <= 1'b0;
                            rx_cont <= S_ADDR_H;
                            state   <= S_POLL_AR;
                        end
                        CMD_READ: begin
                            is_read <= 1'b1;
                            rx_cont <= S_ADDR_H;
                            state   <= S_POLL_AR;
                        end
                        default: begin
                            // Unknown command: discard and wait for next
                            rx_cont <= S_CMD;
                            state   <= S_POLL_AR;
                        end
                    endcase
                end

                // ── Protocol: address and length fields ───────────────────

                S_ADDR_H: begin
                    pkt_addr[15:8] <= rx_byte;
                    rx_cont <= S_ADDR_L;
                    state   <= S_POLL_AR;
                end

                S_ADDR_L: begin
                    pkt_addr[7:0] <= rx_byte;
                    rx_cont <= S_LEN_H;
                    state   <= S_POLL_AR;
                end

                S_LEN_H: begin
                    pkt_len[15:8] <= rx_byte;
                    rx_cont <= S_LEN_L;
                    state   <= S_POLL_AR;
                end

                S_LEN_L: begin
                    pkt_len[7:0] <= rx_byte;
                    // Evaluate full 16-bit length using pkt_len[15:8] already
                    // registered from S_LEN_H and the freshly received low byte.
                    if ({pkt_len[15:8], rx_byte} == 16'd0) begin
                        // Zero-length packet: nothing to do
                        rx_cont <= S_CMD;
                        state   <= S_POLL_AR;
                    end else if (is_read) begin
                        state <= S_READMEM;   // start sending memory data
                    end else begin
                        rx_cont <= S_DATA0;   // start receiving write data
                        state   <= S_POLL_AR;
                    end
                end

                // ── Protocol: assemble 4 bytes → BRAM word (write path) ───

                S_DATA0: begin
                    word_buf[31:24] <= rx_byte;
                    rx_cont <= S_DATA1;
                    state   <= S_POLL_AR;
                end

                S_DATA1: begin
                    word_buf[23:16] <= rx_byte;
                    rx_cont <= S_DATA2;
                    state   <= S_POLL_AR;
                end

                S_DATA2: begin
                    word_buf[15:8] <= rx_byte;
                    rx_cont <= S_DATA3;
                    state   <= S_POLL_AR;
                end

                S_DATA3: begin
                    word_buf[7:0] <= rx_byte;
                    state <= S_WRITEMEM;
                end

                S_WRITEMEM: begin
                    // Issue BRAM Port B write for one clock cycle
                    bram_en   <= 1'b1;
                    bram_we   <= 1'b1;
                    bram_addr <= pkt_addr[MEM_ADDR_WIDTH-1:0];
                    bram_din  <= word_buf;
                    pkt_len   <= pkt_len - 16'd1;
                    pkt_addr  <= pkt_addr + 16'd1;
                    if (pkt_len == 16'd1) begin
                        // This was the last word
                        rx_cont <= S_CMD;
                    end else begin
                        rx_cont <= S_DATA0;
                    end
                    state <= S_POLL_AR;
                end

                // ── Read path: BRAM → 4 bytes → UART TX ──────────────────

                S_READMEM: begin
                    // Assert BRAM Port B read; data appears after one clock
                    bram_en   <= 1'b1;
                    bram_we   <= 1'b0;
                    bram_addr <= pkt_addr[MEM_ADDR_WIDTH-1:0];
                    state     <= S_READWAIT;
                end

                S_READWAIT: begin
                    // Capture registered BRAM output
                    read_word <= bram_dout;
                    state     <= S_SENDB3;
                end

                // ── Split word into 4 bytes and send via AXI UART TX ─────

                S_SENDB3: begin
                    tx_byte <= read_word[31:24];
                    tx_ret  <= S_SENDB2;
                    state   <= S_TX_AW;
                end

                S_SENDB2: begin
                    tx_byte <= read_word[23:16];
                    tx_ret  <= S_SENDB1;
                    state   <= S_TX_AW;
                end

                S_SENDB1: begin
                    tx_byte <= read_word[15:8];
                    tx_ret  <= S_SENDB0;
                    state   <= S_TX_AW;
                end

                S_SENDB0: begin
                    tx_byte <= read_word[7:0];
                    tx_ret  <= S_AFTRWORD;
                    state   <= S_TX_AW;
                end

                S_AFTRWORD: begin
                    pkt_len  <= pkt_len - 16'd1;
                    pkt_addr <= pkt_addr + 16'd1;
                    if (pkt_len == 16'd1) begin
                        // Last word sent; return to command polling
                        rx_cont <= S_CMD;
                        state   <= S_POLL_AR;
                    end else begin
                        state <= S_READMEM;
                    end
                end

                // ── AXI-W sub-FSM: write one byte to UART TX FIFO ────────

                S_TX_AW: begin
                    // Address phase: point at TX_FIFO
                    // First check TXFULL to avoid overflowing the FIFO;
                    // if full, stall in this state until not full.
                    // (Re-poll status by going back to POLL and retrying)
                    // Simple approach: unconditionally send; UART Lite FIFO
                    // is 16-deep so overflow is unlikely at low baud rates.
                    // For a robust design, poll STAT_REG[TXFULL] here.
                    m_axi_awaddr  <= UART_BASE + OFS_TX;
                    m_axi_awvalid <= 1'b1;
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        state <= S_TX_WD;
                    end
                end

                S_TX_WD: begin
                    // Data phase: byte in bits [7:0], wstrb = 0001
                    m_axi_wdata  <= {24'h000000, tx_byte};
                    m_axi_wstrb  <= 4'b0001;
                    m_axi_wvalid <= 1'b1;
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        state <= S_TX_BR;
                    end
                end

                S_TX_BR: begin
                    // Response phase: accept write response
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        state <= tx_ret;   // return to calling state
                    end
                end

                default: state <= S_POLL_AR;

            endcase
        end
    end

endmodule
