`timescale 1ns / 1ps
parameter BUAD_RATE = 9600; // 1초에 9600bit 전송
parameter BAUD_DELAY = (100_000_000 / BUAD_RATE) * 10 * 10; // start bit부터 stop bit까지 걸리는 시간
parameter CLOCK_PERIOD_NS = 10; // 한클락당 주기
parameter BIT_PER_CLOCK = 10416; // 100MHz / 9600bps : 한 비트당 들어가는 시스템 클락 수
parameter BIT_PERIOD = BIT_PER_CLOCK * CLOCK_PERIOD_NS; // 클락 수 * 한클락 당 주기 = 1bit 당 걸리는 시간


interface uart_interface;
    logic clk;
    logic rst;
    logic rx;
    logic tx;
    logic [7:0] ran_data;
    logic [7:0] received_data;
endinterface

class transaction;
    rand bit [7:0] ran_data;
    bit [7:0] received_data;
    bit tx;
        task display(string name_s);
        $display("%t, [%s] ran_data = %d, received_data = %d, tx = %d", $time, name_s, received_data, ran_data, tx);
    endtask 
endclass

class generator;
    transaction tr;
    mailbox#(transaction) gen2drv_mbox;
    event gen_next_event;

    int total_count = 0;

    function new(mailbox#(transaction)gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int count);
        repeat(count)begin
            total_count ++;
            tr = new;
            assert (tr.randomize())
            else $display("[GEN] tr.randomize() error!!!");
            gen2drv_mbox.put(tr);
            tr.display("[GEN]");
            @(gen_next_event);
        end
    endtask 
endclass

class driver;
    transaction tr;
    mailbox#(transaction) gen2drv_mbox;
    virtual uart_interface uart_intf;
    event mon_next_event;

    function new(mailbox#(transaction)gen2drv_mbox, virtual uart_interface uart_intf, event mon_next_event);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uart_intf = uart_intf;
        this.mon_next_event = mon_next_event;
    endfunction 

    task reset ();
        uart_intf.clk = 0;
        uart_intf.rst = 1;
        uart_intf.rx = 1;
        // uart_intf.tx = 1;
        uart_intf.ran_data = 0;
        @(posedge uart_intf.clk)
        uart_intf.rst = 0;
        $display("[DRV] : reset done!!!");
    endtask 

    task run();
            forever begin
            gen2drv_mbox.get(tr);
            uart_intf.ran_data = tr.ran_data;
            uart_intf.rx = 1;
            #(BIT_PERIOD);
            uart_intf.rx = 0;
            #(BIT_PERIOD);

            for (int i = 0; i < 8; i++) begin
                uart_intf.rx = tr.ran_data[i];
                #(BIT_PERIOD);
            end
            uart_intf.rx = 1;
            tr.display("[DRV]");
            ->mon_next_event; // 
            // #(BIT_PERIOD);
            @(posedge uart_intf.clk); // 5
        end
        
    endtask
endclass

class monitor;
    transaction tr;
    virtual uart_interface uart_intf;
    mailbox #(transaction)mon2scb_mbox;
    event mon_next_event;

    function new(mailbox#(transaction)mon2scb_mbox, virtual uart_interface uart_intf, event mon_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.uart_intf = uart_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task run();
            tr = new;
        forever begin
            @(negedge uart_intf.tx);
            #(BIT_PERIOD / 2);
            for(int bit_count = 0; bit_count < 8; bit_count = bit_count + 1) begin
                #(BIT_PERIOD);
                tr.ran_data[bit_count] = uart_intf.tx;
            end
            #(BIT_PERIOD);
            tr.display("[MON]");
            tr.received_data = uart_intf.ran_data;
            mon2scb_mbox.put(tr);
        end
        
    endtask 
endclass

class scoreboard;
    transaction tr;
    virtual uart_interface uart_intf;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    int pass_count = 0,fail_count = 0;

    function new(mailbox#(transaction)mon2scb_mbox, virtual uart_interface uart_intf, event gen_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run ();
        forever begin
            mon2scb_mbox.get(tr);
            if(tr.received_data == tr.ran_data) begin
                pass_count++;
                $display ("[SCB] PASS : received = %d, send_data = %d",tr.received_data , tr.ran_data);
            end else begin
                fail_count++;
                $display ("[SCB] FAIL : received = %d, send_data = %d", tr.received_data, tr.ran_data);
            end
            ->gen_next_event;
        end
        
    endtask //run
endclass 

class environment;
    mailbox#(transaction)gen2drv_mbox;
    mailbox#(transaction)mon2scb_mbox;
    generator gen;
    monitor mon;
    driver drv;
    scoreboard scb;
    event gen_next_event;
    event mon_next_event;

    function new(virtual uart_interface uart_intf);
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(gen2drv_mbox, uart_intf, mon_next_event);
        mon = new(mon2scb_mbox, uart_intf, mon_next_event);
        scb = new(mon2scb_mbox, uart_intf, gen_next_event);
    endfunction 

    task report();
        $display("===========================");
        $display("======= Test Report ========");
        $display("===========================");
        $display("== Total Test : %d ==", gen.total_count);
        $display("== Pass Test : %d ==", scb.pass_count);
        $display("== Fail Test : %d ==", scb.fail_count);
        $display("===========================");
        $display("== Test bench is finished ==");
        $display("===========================");
    endtask

    task reset();
        drv.reset();
    endtask 

    task run();
        fork
            gen.run(20);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $display("finished");
        report();
        $stop;
    endtask 
endclass

module tb_uart_top();
    environment env;
    uart_interface uart_intf_tb();

    UART_TOP dut(
    .clk(uart_intf_tb.clk),
    .rst(uart_intf_tb.rst),
    .rx(uart_intf_tb.rx),
    .tx(uart_intf_tb.tx)
);

always #5 uart_intf_tb.clk = ~uart_intf_tb.clk;

initial begin
    uart_intf_tb.clk = 0;
    env = new(uart_intf_tb);
    env.reset();
    env.run();
end
endmodule
