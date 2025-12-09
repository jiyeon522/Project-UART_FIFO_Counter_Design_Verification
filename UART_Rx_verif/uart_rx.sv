
module uart_rx (
    input           clk,
    input           rst,
    input           b_tick,
    input           rx,
    output [7:0]    rx_data,
    output          rx_busy,
    output          rx_done
);

    localparam [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    reg [1:0] c_state, n_state;
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next; //16까지 tick count
    reg [2:0] bit_cnt_reg,  bit_cnt_next;
    reg [7:0] rx_data_reg, rx_data_next;
    reg rx_done_reg, rx_done_next;
    reg rx_busy_reg, rx_busy_next;

    //ouput connecting
    assign rx_data = rx_data_reg;
    assign rx_busy = rx_busy_reg;
    assign rx_done = rx_done_reg;
    

    //state register -> 매 CLK 마다 next state 값 current state에 저장 =>순차논리
    always @(posedge clk, posedge rst) begin
        if (rst)begin
            c_state         <= IDLE; 
            b_tick_cnt_reg  <= 0;
            bit_cnt_reg     <= 0;
            rx_data_reg     <= 0;
            rx_done_reg     <= 0;
            rx_busy_reg     <= 0;
        end else begin
            c_state         <= n_state;
            b_tick_cnt_reg  <= b_tick_cnt_next;
            bit_cnt_reg     <= bit_cnt_next;
            rx_data_reg     <= rx_data_next;
            rx_done_reg     <= rx_done_next;
            rx_busy_reg     <= rx_busy_next;
        end
    end
    
    //next combiational logic => 조합논리
    always @(*) begin
        n_state         = c_state;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        rx_data_next    = rx_data_reg;
        rx_done_next    = rx_done_reg;
        rx_busy_next    = rx_busy_reg;
        case (c_state)
            IDLE: begin
                rx_done_next = 1'b0;
                rx_data_next[0]=0;
                        rx_data_next[1]=0;
                        rx_data_next[2]=0;
                        rx_data_next[3]=0;
                        rx_data_next[4]=0;
                        rx_data_next[5]=0;
                        rx_data_next[6]=0;
                        rx_data_next[7]=0;
                if (b_tick) begin
                    if (~rx) begin
                        b_tick_cnt_next = 1'b0;
                        bit_cnt_next = 1'b0;
                        rx_busy_next = 1'b1;
                        n_state = START;
                    end 
                end
            end
            START: begin 
                if (b_tick) begin
                    if (b_tick_cnt_reg == 7) begin
                        n_state = DATA;
                        b_tick_cnt_next = 0;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                    
                end
            end
            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        rx_data_next = {rx, rx_data_reg[7:1]};
                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else bit_cnt_next = bit_cnt_reg + 1;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP : begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        rx_busy_next = 1'b0;
                        rx_done_next = 1'b1;
                        n_state = IDLE;
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
    output      b_tick
);

    parameter BAUD_COUNT = (100_000_000 / (9600 * 16)) - 1; //100M % 9600 % 16 = 651.041666
    reg [$clog2(BAUD_COUNT) - 1:0] tick_counter; 
    reg r_tick;

    assign b_tick = r_tick; //b_rick을 module 출력으로 연결

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

