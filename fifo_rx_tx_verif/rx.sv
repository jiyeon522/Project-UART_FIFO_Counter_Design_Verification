
module uart_rx (
    input logic clk,
    input logic rst,
    input logic b_tick,
    input logic rx,
    output logic [7:0] rx_data,
    output logic rx_done
);

    localparam [1:0] RX_IDLE = 2'b00, RX_START = 2'b01, RX_DATA = 2'b10, RX_STOP = 2'b11;

    logic [1:0] c_state, n_state;
    logic [4:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] rx_buf_reg, rx_buf_next;
    logic rx_done_reg, rx_done_next;

    assign rx_data = rx_buf_reg;
    assign rx_done = rx_done_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state <= RX_IDLE;
            b_tick_cnt_reg <= 0;
            bit_cnt_reg <= 0;
            rx_buf_reg <= 0;
            rx_done_reg <= 0;
        end else begin
            c_state <= n_state;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg <= bit_cnt_next;
            rx_buf_reg <= rx_buf_next;
            rx_done_reg <= rx_done_next;
        end
    end

    always_comb begin
        n_state = c_state;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next = bit_cnt_reg;
        rx_buf_next = rx_buf_reg;
        rx_done_next = rx_done_reg;
        case (c_state)
            RX_IDLE: begin
                rx_done_next = 0;
                if (!rx) begin
                    b_tick_cnt_next = 0;
                    bit_cnt_next = 0;
                    n_state = RX_START;
                end
            end
            RX_START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 23) begin
                        n_state = RX_DATA;
                        bit_cnt_next = 0;
                        b_tick_cnt_next = 0;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            RX_DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 0) begin
                        rx_buf_next[7] = rx;
                    end
                    if (b_tick_cnt_reg == 15) begin
                        if (bit_cnt_reg == 7) begin
                            n_state = RX_STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                            rx_buf_next = rx_buf_reg >> 1;
                            b_tick_cnt_next = 0;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end

            end
            RX_STOP: begin
                if (b_tick) begin
                        rx_done_next = 1;
                        n_state = RX_IDLE;
                    end
            end
        endcase
    end
endmodule

module baud_tick_generator (
    input  logic clk,
    input  logic rst,
    output logic b_tick
);

    parameter BAUDRATE = 9600 * 16;
    localparam BAUD_COUNT = 100_000_000 / BAUDRATE;

    logic [$clog2(BAUD_COUNT)-1:0] counter_reg;
    logic b_tick_reg;

    assign b_tick = b_tick_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick_reg  <= 0;
        end else begin
            if (counter_reg == BAUD_COUNT - 1) begin
                counter_reg <= 0;
                b_tick_reg  <= 1'b1;
            end else begin
                counter_reg <= counter_reg + 1;
                b_tick_reg  <= 1'b0;
            end
        end
    end
endmodule
