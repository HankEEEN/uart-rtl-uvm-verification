module uart_top_tick (
    input  logic        clk,
    input  logic        rst,
    input  logic        tx_start,
    input  logic        rx_start,
    input  logic [7:0]  tx_data,
    input  logic [16:0] baud,
    input  logic [3:0]  length,
    input  logic        parity_type,
    input  logic        parity_en,
    input  logic        stop2,
    input  logic        rx,
    output logic        tx,
    output logic        tx_done,
    output logic        rx_done,
    output logic        tx_err,
    output logic        rx_err,
    output logic [7:0]  rx_out
);

    logic tx_tick;
    logic rx_tick;

    uart_clk_gen_tick clk_dut (
        .clk    (clk),
        .rst    (rst),
        .baud   (baud),
        .tx_tick(tx_tick),
        .rx_tick(rx_tick)
    );

    uart_tx_tick tx_dut (
        .clk        (clk),
        .tx_tick    (tx_tick),
        .tx_start   (tx_start),
        .rst        (rst),
        .tx_data    (tx_data),
        .length     (length),
        .parity_type(parity_type),
        .parity_en  (parity_en),
        .stop2      (stop2),
        .tx         (tx),
        .tx_done    (tx_done),
        .tx_err     (tx_err)
    );

    uart_rx_tick rx_dut (
        .clk        (clk),
        .rx_tick    (rx_tick),
        .rx_start   (rx_start),
        .rst        (rst),
        .rx         (rx),
        .length     (length),
        .parity_type(parity_type),
        .parity_en  (parity_en),
        .stop2      (stop2),
        .rx_out     (rx_out),
        .rx_done    (rx_done),
        .rx_error   (rx_err)
    );

endmodule
