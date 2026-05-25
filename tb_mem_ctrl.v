`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/23/2026 11:29:05 PM
// Design Name: 
// Module Name: tb_mem_ctrl
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


module tb_mem_ctrl();
// =============================================================================
// tb_mem_ctrl_system.v
// Testbench for the MemCtrl + AXI4-Lite Master + Block Memory subsystem
//
// Strategy: replace the real AXI Uartlite with a behavioural model that:
//   - accepts AXI4-Lite writes  (TX path: MemCtrl -> host)
//   - returns AXI4-Lite reads   (RX path: host   -> MemCtrl)
//
// The UART model has two task-driven FIFOs:
//   uart_push_rx(byte) : inject a byte the MemCtrl will "receive"
//   uart_pop_tx(byte)  : capture a byte the MemCtrl "transmitted"
//
// Test sequence:
//   TC1 - CMD_RESET  : send 0x01, check risc_reset pulse + ACK
//   TC2 - CMD_STOP   : send 0x02, check risc_stop asserted + ACK
//   TC3 - CMD_START  : send 0x03, check risc_start asserted + ACK
//   TC4 - CMD_WRITE  : write 3 words to address 0x00000010
//   TC5 - CMD_READ   : read back those 3 words, verify data
//   TC6 - CMD_WRITE  : write 1 word, CMD_READ back, check roundtrip
// =============================================================================
 
 
    // =========================================================================
    // Parameters — must match DUT parameters
    // =========================================================================
    parameter MEM_DEPTH  = 1024;
    parameter ADDR_WIDTH = 10;          // $clog2(1024)
    parameter UART_BASE  = 32'h4060_0000;
    parameter CLK_PERIOD = 10;          // 100 MHz
 
    // UART register absolute addresses
    parameter UART_RX_FIFO  = UART_BASE + 32'h00;
    parameter UART_TX_FIFO  = UART_BASE + 32'h04;
    parameter UART_STAT_REG = UART_BASE + 32'h08;
 
    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
 
    always #(CLK_PERIOD/2) clk = ~clk;
 
    // =========================================================================
    // AXI4-Lite bus wires (between axi4_lite_master and UART model)
    // =========================================================================
    wire [31:0] m_awaddr;
    wire        m_awvalid, m_awready;
    wire [31:0] m_wdata;
    wire  [3:0] m_wstrb;
    wire        m_wvalid,  m_wready;
    wire  [1:0] m_bresp;
    wire        m_bvalid,  m_bready;
    wire [31:0] m_araddr;
    wire        m_arvalid, m_arready;
    wire [31:0] m_rdata;
    wire  [1:0] m_rresp;
    wire        m_rvalid,  m_rready;
 
    // =========================================================================
    // cmd/rsp interface (mem_ctrl <-> axi4_lite_master)
    // =========================================================================
    wire        axi_cmd_valid;
    wire        axi_cmd_wr;
    wire [31:0] axi_cmd_addr;
    wire [31:0] axi_cmd_wdata;
    wire        axi_cmd_ready;
    wire        axi_rsp_valid;
    wire [31:0] axi_rsp_rdata;
 
    // =========================================================================
    // BRAM port B (mem_ctrl side)
    // =========================================================================
    wire               mem_en_b;
    wire  [3:0]        mem_we_b;
    wire [ADDR_WIDTH-1:0] mem_addr_b;
    wire  [31:0]       mem_din_b;
    wire  [31:0]       mem_dout_b;
 
    // BRAM port A (tied off — seq_core not instantiated in this TB)
    reg               mem_en_a   = 1'b0;
    reg  [3:0]        mem_we_a   = 4'b0000;
    reg [ADDR_WIDTH-1:0] mem_addr_a = {ADDR_WIDTH{1'b0}};
    reg  [31:0]       mem_din_a  = 32'h0;
    wire [31:0]       mem_dout_a;
 
    // =========================================================================
    // RISC control outputs
    // =========================================================================
    wire risc_reset;
    wire risc_stop;
    wire risc_start;
 
    // =========================================================================
    // DUT 1: mem_ctrl
    // =========================================================================
    mem_ctrl #(
        .MEM_DEPTH (MEM_DEPTH),
        .UART_BASE (UART_BASE)
    ) u_mem_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),
        .axi_cmd_valid (axi_cmd_valid),
        .axi_cmd_wr    (axi_cmd_wr),
        .axi_cmd_addr  (axi_cmd_addr),
        .axi_cmd_wdata (axi_cmd_wdata),
        .axi_cmd_ready (axi_cmd_ready),
        .axi_rsp_valid (axi_rsp_valid),
        .axi_rsp_rdata (axi_rsp_rdata),
        .mem_en        (mem_en_b),
        .mem_we        (mem_we_b),
        .mem_addr      (mem_addr_b),
        .mem_din       (mem_din_b),
        .mem_dout      (mem_dout_b),
        .risc_reset    (risc_reset),
        .risc_stop     (risc_stop),
        .risc_start    (risc_start)
    );
 
    // =========================================================================
    // DUT 2: axi4_lite_master
    // =========================================================================
    axi4_lite_master #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (32)
    ) u_axi_master (
        .clk           (clk),
        .rst_n         (rst_n),
        .cmd_valid     (axi_cmd_valid),
        .cmd_wr        (axi_cmd_wr),
        .cmd_addr      (axi_cmd_addr),
        .cmd_wdata     (axi_cmd_wdata),
        .cmd_ready     (axi_cmd_ready),
        .rsp_valid     (axi_rsp_valid),
        .rsp_rdata     (axi_rsp_rdata),
        .M_AXI_AWADDR  (m_awaddr),
        .M_AXI_AWVALID (m_awvalid),
        .M_AXI_AWREADY (m_awready),
        .M_AXI_WDATA   (m_wdata),
        .M_AXI_WSTRB   (m_wstrb),
        .M_AXI_WVALID  (m_wvalid),
        .M_AXI_WREADY  (m_wready),
        .M_AXI_BRESP   (m_bresp),
        .M_AXI_BVALID  (m_bvalid),
        .M_AXI_BREADY  (m_bready),
        .M_AXI_ARADDR  (m_araddr),
        .M_AXI_ARVALID (m_arvalid),
        .M_AXI_ARREADY (m_arready),
        .M_AXI_RDATA   (m_rdata),
        .M_AXI_RRESP   (m_rresp),
        .M_AXI_RVALID  (m_rvalid),
        .M_AXI_RREADY  (m_rready)
    );
 
    // =========================================================================
    // DUT 3: block_memory
    // =========================================================================
    block_memory #(
        .MEM_DEPTH (MEM_DEPTH)
    ) u_bram (
        .clk_a  (clk),
        .en_a   (mem_en_a),
        .we_a   (mem_we_a),
        .addr_a (mem_addr_a),
        .din_a  (mem_din_a),
        .dout_a (mem_dout_a),
        .clk_b  (clk),
        .en_b   (mem_en_b),
        .we_b   (mem_we_b),
        .addr_b (mem_addr_b),
        .din_b  (mem_din_b),
        .dout_b (mem_dout_b)
    );
 
    // =========================================================================
    // Behavioural UART Model
    // =========================================================================
    // RX FIFO: bytes waiting to be READ by MemCtrl (injected by testbench)
    reg  [7:0] rx_fifo [0:255];
    integer    rx_wr_ptr = 0;
    integer    rx_rd_ptr = 0;
    wire       rx_has_data = (rx_wr_ptr != rx_rd_ptr);
 
    // TX FIFO: bytes written by MemCtrl (captured for testbench checking)
    reg  [7:0] tx_fifo [0:255];
    integer    tx_wr_ptr = 0;
    integer    tx_rd_ptr = 0;
    wire       tx_full   = ((tx_wr_ptr + 1) % 256 == tx_rd_ptr);
 
    // ------------------------------------------------------------------
    // AXI4-Lite slave response registers
    // ------------------------------------------------------------------
    reg        r_awready = 1'b0;
    reg        r_wready  = 1'b0;
    reg        r_bvalid  = 1'b0;
    reg  [1:0] r_bresp   = 2'b00;
    reg        r_arready = 1'b0;
    reg        r_rvalid  = 1'b0;
    reg [31:0] r_rdata   = 32'h0;
    reg  [1:0] r_rresp   = 2'b00;
 
    assign m_awready = r_awready;
    assign m_wready  = r_wready;
    assign m_bvalid  = r_bvalid;
    assign m_bresp   = r_bresp;
    assign m_arready = r_arready;
    assign m_rvalid  = r_rvalid;
    assign m_rdata   = r_rdata;
    assign m_rresp   = r_rresp;
 
    // ------------------------------------------------------------------
    // WRITE channel handler:
    //   Accept AW+W, decode address, push byte to tx_fifo if TX_FIFO write
    // ------------------------------------------------------------------
    reg [31:0] wr_addr_lat;
 
    always @(posedge clk) begin
        // AW handshake
        if (m_awvalid && !r_awready) begin
            r_awready  <= 1'b1;
            wr_addr_lat <= m_awaddr;
        end else begin
            r_awready <= 1'b0;
        end
 
        // W handshake + data capture
        if (m_wvalid && !r_wready) begin
            r_wready <= 1'b1;
            // If the write targets TX_FIFO, push the byte
            if (m_awvalid || r_awready) begin   // address known
                if ((m_awvalid ? m_awaddr : wr_addr_lat) == UART_TX_FIFO) begin
                    if (!tx_full) begin
                        tx_fifo[tx_wr_ptr] <= m_wdata[7:0];
                        tx_wr_ptr          <= (tx_wr_ptr + 1) % 256;
                    end
                end
            end
        end else begin
            r_wready <= 1'b0;
        end
 
        // B response: issue one cycle after both AW and W accepted
        if (r_awready && r_wready) begin
            r_bvalid <= 1'b1;
            r_bresp  <= 2'b00;
        end else if (m_bready && r_bvalid) begin
            r_bvalid <= 1'b0;
        end
 
        if (!rst_n) begin
            r_awready  <= 1'b0;
            r_wready   <= 1'b0;
            r_bvalid   <= 1'b0;
        end
    end
 
    // ------------------------------------------------------------------
    // READ channel handler:
    //   Accept AR, return appropriate data based on address
    //     UART_STAT_REG: bit[0]=rx_has_data, bit[3]=tx_full
    //     UART_RX_FIFO:  pop one byte from rx_fifo
    // ------------------------------------------------------------------
    reg [31:0] rd_addr_lat;
    reg        rd_pending = 1'b0;
 
    always @(posedge clk) begin
        if (!rst_n) begin
            r_arready  <= 1'b0;
            r_rvalid   <= 1'b0;
            r_rdata    <= 32'h0;
            rd_pending <= 1'b0;
        end else begin
            // AR handshake
            r_arready <= 1'b0;
            if (m_arvalid && !rd_pending && !r_rvalid) begin
                r_arready  <= 1'b1;
                rd_addr_lat <= m_araddr;
                rd_pending <= 1'b1;
            end
 
            // Return read data one cycle after AR accepted
            if (rd_pending && !r_rvalid) begin
                rd_pending <= 1'b0;
                r_rvalid   <= 1'b1;
                r_rresp    <= 2'b00;
 
                if (rd_addr_lat == UART_STAT_REG) begin
                    // bit 0: RX has data, bit 3: TX full
                    r_rdata <= {28'h0,
                                tx_full,       // bit 3: TX full
                                3'b0,
                                rx_has_data};  // bit 0: RX valid
                end else if (rd_addr_lat == UART_RX_FIFO) begin
                    if (rx_has_data) begin
                        r_rdata   <= {24'h0, rx_fifo[rx_rd_ptr]};
                        rx_rd_ptr <= (rx_rd_ptr + 1) % 256;
                    end else begin
                        r_rdata <= 32'h0;
                    end
                end else begin
                    r_rdata <= 32'hDEAD_BEEF;  // unexpected address
                end
            end
 
            // Deassert rvalid once master accepts
            if (r_rvalid && m_rready) begin
                r_rvalid <= 1'b0;
            end
        end
    end
 
    // =========================================================================
    // Helper tasks
    // =========================================================================
 
    // Push a byte into the UART RX FIFO (MemCtrl will read it)
    task uart_push_rx;
        input [7:0] byte_in;
        begin
            rx_fifo[rx_wr_ptr] = byte_in;
            rx_wr_ptr = (rx_wr_ptr + 1) % 256;
        end
    endtask
 
    // Pop a byte from UART TX FIFO (check what MemCtrl transmitted)
    task uart_pop_tx;
        output [7:0] byte_out;
        integer timeout;
        begin
            timeout = 0;
            while (tx_wr_ptr == tx_rd_ptr && timeout < 50000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 50000) begin
                $display("ERROR: uart_pop_tx timeout — no byte transmitted");
                byte_out = 8'hFF;
            end else begin
                byte_out  = tx_fifo[tx_rd_ptr];
                tx_rd_ptr = (tx_rd_ptr + 1) % 256;
            end
        end
    endtask
 
    // Wait N clock cycles
    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask
 
    // Wait until MemCtrl transmits an ACK byte (0xAA), with timeout
    task expect_ack;
        reg [7:0] b;
        begin
            uart_pop_tx(b);
            if (b === 8'hAA)
                $display("  [OK]  ACK received: 0x%02X", b);
            else
                $display("  [FAIL] Expected ACK 0xAA, got 0x%02X", b);
        end
    endtask
 
    // Send a full CMD_WRITE packet into the RX FIFO
    // addr: 32-bit byte address, len: word count, data array via repeated calls
    task send_write_cmd;
        input [31:0] addr;
        input [15:0] len;
        input [31:0] word0, word1, word2;   // up to 3 words for this TB
        integer i;
        begin
            // Command byte
            uart_push_rx(8'h04);
            // Address (4 bytes, MSB first)
            uart_push_rx(addr[31:24]);
            uart_push_rx(addr[23:16]);
            uart_push_rx(addr[15: 8]);
            uart_push_rx(addr[ 7: 0]);
            // Length (2 bytes, MSB first)
            uart_push_rx(len[15:8]);
            uart_push_rx(len[ 7:0]);
            // Data words (MSB first per word)
            if (len >= 1) begin
                uart_push_rx(word0[31:24]);
                uart_push_rx(word0[23:16]);
                uart_push_rx(word0[15: 8]);
                uart_push_rx(word0[ 7: 0]);
            end
            if (len >= 2) begin
                uart_push_rx(word1[31:24]);
                uart_push_rx(word1[23:16]);
                uart_push_rx(word1[15: 8]);
                uart_push_rx(word1[ 7: 0]);
            end
            if (len >= 3) begin
                uart_push_rx(word2[31:24]);
                uart_push_rx(word2[23:16]);
                uart_push_rx(word2[15: 8]);
                uart_push_rx(word2[ 7: 0]);
            end
        end
    endtask
 
    // Send a CMD_READ packet into the RX FIFO
    task send_read_cmd;
        input [31:0] addr;
        input [15:0] len;
        begin
            uart_push_rx(8'h05);
            uart_push_rx(addr[31:24]);
            uart_push_rx(addr[23:16]);
            uart_push_rx(addr[15: 8]);
            uart_push_rx(addr[ 7: 0]);
            uart_push_rx(len[15:8]);
            uart_push_rx(len[ 7:0]);
        end
    endtask
 
    // Receive one 32-bit word from TX FIFO (4 bytes, MSB first)
    task recv_word;
        output [31:0] word_out;
        reg [7:0] b0, b1, b2, b3;
        begin
            uart_pop_tx(b0);
            uart_pop_tx(b1);
            uart_pop_tx(b2);
            uart_pop_tx(b3);
            word_out = {b0, b1, b2, b3};
        end
    endtask
 
    // Check a received word matches expected value
    task check_word;
        input [31:0] got;
        input [31:0] expected;
        input [63:0] label;      // 8-char ASCII tag for display
        begin
            if (got === expected)
                $display("  [OK]  %s = 0x%08X", label, got);
            else
                $display("  [FAIL] %s: expected 0x%08X, got 0x%08X",
                         label, expected, got);
        end
    endtask
 
    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #2_000_000;
        $display("FATAL: Simulation timeout — possible FSM deadlock");
        $finish;
    end
 
    // =========================================================================
    // Test stimulus
    // =========================================================================
    integer tc;
    reg [7:0]  rx_b;
    reg [31:0] rx_w0, rx_w1, rx_w2;
 
    initial begin
        $display("================================================");
        $display(" MemCtrl System Testbench");
        $display("================================================");
 
        // -- Reset --
        rst_n = 1'b0;
        wait_clk(10);
        rst_n = 1'b1;
        wait_clk(5);
 
        // =================================================================
        // TC1: CMD_RESET (0x01) — expect risc_reset pulse + ACK 0xAA
        // =================================================================
        $display("\n--- TC1: CMD_RESET ---");
        uart_push_rx(8'h01);
 
        // Wait for risc_reset to assert
        wait_clk(1);
        fork
            begin : watch_reset
                integer t;
                t = 0;
                while (!risc_reset && t < 10000) begin
                    @(posedge clk); t = t + 1;
                end
                if (risc_reset)
                    $display("  [OK]  risc_reset asserted");
                else
                    $display("  [FAIL] risc_reset never asserted");
                disable watch_reset;
            end
        join
 
        // Also check risc_stop follows
        wait_clk(2);
        if (risc_stop)
            $display("  [OK]  risc_stop asserted after RESET");
        else
            $display("  [FAIL] risc_stop not asserted after RESET");
 
        expect_ack;     // wait for 0xAA response
        wait_clk(5);
 
        // =================================================================
        // TC2: CMD_STOP (0x02) — expect risc_stop held, no reset, ACK
        // =================================================================
        $display("\n--- TC2: CMD_STOP ---");
        uart_push_rx(8'h02);
 
        begin : wait_stop
            integer t;
            t = 0;
            while (t < 10000) begin
                @(posedge clk);
                if (risc_stop && !risc_reset && !risc_start) begin
                    $display("  [OK]  risc_stop=1, risc_reset=0, risc_start=0");
                    t = 10000; // exit
                end
                t = t + 1;
            end
        end
 
        expect_ack;
        wait_clk(5);
 
        // =================================================================
        // TC3: CMD_START (0x03) — expect risc_start=1, stop=0, ACK
        // =================================================================
        $display("\n--- TC3: CMD_START ---");
        uart_push_rx(8'h03);
 
        begin : wait_start
            integer t;
            t = 0;
            while (t < 10000) begin
                @(posedge clk);
                if (risc_start && !risc_stop && !risc_reset) begin
                    $display("  [OK]  risc_start=1, risc_stop=0, risc_reset=0");
                    t = 10000;
                end
                t = t + 1;
            end
        end
 
        expect_ack;
        wait_clk(10);
 
        // =================================================================
        // TC4: CMD_WRITE — 3 words to address 0x00000040 (word addr 0x10)
        //   word[0] = 0xDEADBEEF
        //   word[1] = 0xCAFEBABE
        //   word[2] = 0x12345678
        // =================================================================
        $display("\n--- TC4: CMD_WRITE  3 words @ addr 0x00000040 ---");
        send_write_cmd(
            32'h0000_0040,   // byte address 0x40 = word address 0x10
            16'h0003,
            32'hDEAD_BEEF,
            32'hCAFE_BABE,
            32'h1234_5678
        );
 
        expect_ack;
        wait_clk(10);
 
        // =================================================================
        // TC5: CMD_READ — read back those 3 words
        // =================================================================
        $display("\n--- TC5: CMD_READ   3 words @ addr 0x00000040 ---");
        send_read_cmd(32'h0000_0040, 16'h0003);
 
        recv_word(rx_w0);
        recv_word(rx_w1);
        recv_word(rx_w2);
        expect_ack;
 
        check_word(rx_w0, 32'hDEAD_BEEF, "word[0]");
        check_word(rx_w1, 32'hCAFE_BABE, "word[1]");
        check_word(rx_w2, 32'h1234_5678, "word[2]");
        wait_clk(10);
 
        // =================================================================
        // TC6: Roundtrip — write 1 word, read it back
        // =================================================================
        $display("\n--- TC6: Roundtrip  1 word  @ addr 0x00000100 ---");
        send_write_cmd(
            32'h0000_0100,   // byte address 0x100 = word address 0x40
            16'h0001,
            32'hA5A5_5A5A,
            32'h0, 32'h0
        );
        expect_ack;
        wait_clk(5);
 
        send_read_cmd(32'h0000_0100, 16'h0001);
        recv_word(rx_w0);
        expect_ack;
        check_word(rx_w0, 32'hA5A5_5A5A, "rtrip  ");
        wait_clk(10);
 
        // =================================================================
        // TC7: Boundary — write to last valid word address (1023)
        //   byte address = 1023 * 4 = 0x00000FFC
        // =================================================================
        $display("\n--- TC7: Boundary write/read @ last word (addr 0xFFC) ---");
        send_write_cmd(
            32'h0000_0FFC,
            16'h0001,
            32'hFFFF_FFFF,
            32'h0, 32'h0
        );
        expect_ack;
        wait_clk(5);
 
        send_read_cmd(32'h0000_0FFC, 16'h0001);
        recv_word(rx_w0);
        expect_ack;
        check_word(rx_w0, 32'hFFFF_FFFF, "last   ");
        wait_clk(10);
 
        // =================================================================
        // Done
        // =================================================================
        $display("\n================================================");
        $display(" Simulation complete.");
        $display("================================================");
        $finish;
    end
 
    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("tb_mem_ctrl.vcd");
        $dumpvars(0, tb_mem_ctrl);
    end
 
    // =========================================================================
    // Monitor — print every FSM state transition of mem_ctrl
    // =========================================================================
    reg [5:0] prev_state;
    always @(posedge clk) begin
        if (rst_n && u_mem_ctrl.state !== prev_state) begin
            $display("  t=%0t  FSM: state %0d -> %0d",
                     $time, prev_state, u_mem_ctrl.state);
            prev_state = u_mem_ctrl.state;
        end
    end
 
endmodule
