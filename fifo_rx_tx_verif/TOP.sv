module UART_TOP (
    input  logic clk,
    input  logic rst,
    input  logic rx,
    output logic tx
);

    logic w_tick;
    logic [7:0] w_rx_data, w_tx_data, w_uart_data;
    logic w_done;
    logic w_tx_busy,w_tx_empty,w_rx_empty,w_tx_full;

    baud_tick_generator U_BAUD_TICK_GEN (
        .clk(clk),
        .rst(rst),
        .b_tick(w_tick)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_data(w_uart_data),
        .tx_start(~w_tx_empty),
        .b_tick(w_tick),
        .tx_busy(w_tx_busy),
        .tx(tx)
    );

    uart_rx U_UART_RX (
        .clk(clk),
        .rst(rst),
        .b_tick(w_tick),
        .rx(rx),
        .rx_data(w_rx_data),
        .rx_done(w_done)
    );

    fifo_top U_FIFO_RX (
        .clk(clk),
        .rst(rst),
        .wdata(w_rx_data),
        .wr(w_done),
        .rd(~w_tx_full),
        .rdata(w_tx_data),
        .full(),
        .empty(w_rx_empty)
    );

    fifo_top U_FIFO_TX (
        .clk(clk),
        .rst(rst),
        .wdata(w_tx_data),
        .wr(~w_rx_empty),
        .rd(~w_tx_busy),
        .rdata(w_uart_data),
        .full(w_tx_full),
        .empty(w_tx_empty)
    );

endmodule