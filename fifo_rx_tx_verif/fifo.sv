`timescale 1ns / 1ps
module fifo_top (
    input  logic       clk,
    input  logic       rst,
    input  logic       wr,
    input  logic       rd,
    input  logic [7:0] wdata,
    output logic       full,
    output logic       empty,
    output logic [7:0] rdata
);

    logic [2:0] wptr;
    logic [2:0] rptr;
    logic wr_en;

    assign wr_en = wr & ~full;

    register_file U_REG_FILE (
        .*,
        .wr(wr_en)
    );
    fifo_cu U_FIFO_CU (.*);

endmodule

module register_file #(
    parameter AWIDTH = 3
) (
    input logic clk,
    input logic wr,
    input logic [(AWIDTH)-1:0] wptr,
    input logic [(AWIDTH)-1:0] rptr,
    input logic [7:0] wdata,
    output logic [7:0] rdata
);

    logic [7:0] ram[0:2**AWIDTH -1];

    assign rdata = ram[rptr];
    always_ff @(posedge clk) begin
        if (wr) begin
            ram[wptr] <= wdata;
        end
    end
endmodule

module fifo_cu #(
    parameter AWIDTH = 3
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                wr,    // push
    input  logic                rd,    // pop
    output logic [AWIDTH-1 : 0] wptr,
    output logic [AWIDTH-1 : 0] rptr,
    output logic                full,
    output logic                empty
);


    //output
    logic [AWIDTH-1:0] wptr_reg, wptr_next;
    logic [AWIDTH-1:0] rptr_reg, rptr_next;
    logic full_reg, full_next;
    logic empty_reg, empty_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            full_reg  <= 0;
            empty_reg <= 1;
        end else begin
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    always_comb begin
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        full_next  = full_reg;
        empty_next = empty_reg;
        case ({
            wr, rd
        })
            2'b01: begin
                //pop
                full_next = 1'b0;
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (rptr_next == wptr_reg) begin
                        //하나 증가시킬애랑 현재 wptr이랑 같냐
                        empty_next = 1'b1;
                    end
                end
            end
            2'b10: begin
                //push
                empty_next = 1'b0;
                if (!full_reg) begin
                    wptr_next = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_reg) begin
                        // 하나 증가시킬애랑 현재 rptr이랑 같냐
                        full_next = 1'b1;
                    end
                end
            end
            2'b11: begin
                if (empty_reg == 1'b1) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else if (full_reg == 1'b1) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else begin
                    //not be full, empty
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end

            end
        endcase
    end
endmodule


