module uart_tx (
    input clk,
    input rst,
    input tx_start,
    input [7:0] tx_data,
    input b_tick,
    output tx_busy,
    output tx
);
    localparam [1:0] IDLE = 2'b00, TX_START = 2'b01, TX_DATA =2'b10, TX_STOP = 2'b11;

    reg [1:0] state_reg, next_state;
    reg tx_busy_reg, tx_busy_next;
    reg tx_reg, tx_next;
    reg [7:0] data_buf_reg, data_buf_next;
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    reg [2:0] bit_cnt_reg, bit_cnt_next;


    assign tx_busy = tx_busy_reg;
    assign tx = tx_reg;
    
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
            tx_busy_reg <= 1'b0;
            tx_reg <= 1'b1;
            data_buf_reg <= 8'h00;
            b_tick_cnt_reg <= 4'b0000;
            bit_cnt_reg <= 3'b000;
        end
        else begin
            state_reg <= next_state;
            tx_busy_reg <= tx_busy_next;
            tx_reg <= tx_next;
            data_buf_reg <= data_buf_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg <= bit_cnt_next;
        end
    end
    
    always @(*) begin
        next_state = state_reg;
        tx_busy_next = tx_busy_reg;
        tx_next = tx_reg;
        data_buf_next = data_buf_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next = bit_cnt_reg;
        case (state_reg)
            IDLE:begin
                tx_next = 1'b1;
                tx_busy_next = 1'b0;
                if(tx_start)begin
                    b_tick_cnt_next = 0;
                    data_buf_next = tx_data;
                    next_state = TX_START;
                end
            end
            TX_START:begin
                tx_next = 1'b0;
                tx_busy_next = 1'b1;
                if(b_tick)begin
                    if(b_tick_cnt_reg == 15)begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next = 0;
                        next_state = TX_DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            TX_DATA: begin
                tx_next = data_buf_reg[0];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;
                            next_state = TX_STOP;
                        end else begin
                            b_tick_cnt_next = 0;
                            bit_cnt_next = bit_cnt_reg + 1;
                            data_buf_next = data_buf_reg >> 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            TX_STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        next_state = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
    
endmodule


module baud_tick_gen (
    input       clk,
    input       rst,
    output      o_b_tick
);

    parameter BAUD_COUNT = (100_000_000 / (9600 * 16)) - 1; //100M % 9600 % 16 = 651.041666
    reg [$clog2(BAUD_COUNT) - 1:0] tick_counter; 
    reg r_tick;

    assign o_b_tick = r_tick; //b_rick을 module 출력으로 연결

    always @(posedge clk, posedge rst) begin
        if (rst) begin //rst가 posedge일 때
            tick_counter <= 0;
            r_tick       <= 0;
        end else begin //clk와 posedge일 때
            if (tick_counter == BAUD_COUNT) begin
                tick_counter <= 0;
                r_tick <= 1'b1;
            end else begin
                tick_counter <= tick_counter + 1;
                r_tick <= 1'b0;
            end
        end
    end

endmodule