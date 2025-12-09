`timescale 1ns / 1ps

parameter BAUD_RATE = 9000;
parameter CLOCK_PERIOD_NS = 10; 
parameter BITPERCLOCK = 100_000_000 / BAUD_RATE; 
parameter BIT_PERIOD = BITPERCLOCK * CLOCK_PERIOD_NS; 

// UART RX 인터페이스
interface rx_interface;
    logic       clk;
    logic       rst;
    logic       rx;
    logic [7:0] random_data;
    logic [7:0] rx_data;
    logic       rx_done;
endinterface

// UART Rx 트랜잭션 정의
class transaction;
    rand logic [7:0] random_data;
    logic [7:0] rx_data;

    task display(string name_s);
        $display("[%s] (%t) random_data_input = %h, rx_data_output = %h",
                 name_s, $time, random_data, rx_data);
    endtask
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_event;

    int total_count = 0;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int count);
        repeat (count) begin
            total_count++;
            $display("==================================%3drd Run =====================================",total_count);
            tr = new;
            assert (tr.randomize())
            else $display("[GEN] tr.randomize() error!!!");
            gen2drv_mbox.put(tr);
            tr.display("GEN");
            @(gen_next_event);
        end

    endtask
endclass

class driver;

    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual rx_interface rx_intf;
    event mon_next_event;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual rx_interface rx_intf, event mon_next_event);
        this.gen2drv_mbox = gen2drv_mbox;
        this.rx_intf = rx_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task reset();
        rx_intf.clk = 0;
        rx_intf.rst = 1;
        rx_intf.rx = 1;
        rx_intf.random_data = 0;
        @(posedge rx_intf.clk) rx_intf.rst = 0;
        $display("[DRV] reset done!"); 
    endtask



    task run();
        forever begin
            gen2drv_mbox.get(tr);

            rx_intf.rx = 1;
            rx_intf.random_data = tr.random_data;
            #(BIT_PERIOD);
            rx_intf.rx = 0;

            if(rx_intf.rx) begin
                $display("[DRV] Start bit detection failed"); 
            end else $display("[DRV] Start transmission Rx : input random data = %h(%b)",
            tr.random_data, tr.random_data ); 

            for (int i = 0; i < 8; i++) begin
                #(BIT_PERIOD);
                rx_intf.rx = tr.random_data[i];
                $display("[DRV] rx = %d", rx_intf.rx); 
            end

            #(BIT_PERIOD);
            rx_intf.rx = 1;

            if(!rx_intf.rx) begin
                $display("[DRV] STOP bit detection failed"); 
            end else $display("[DRV] Rx transmission finished"); 
            
            tr.display("DRV");
            //->mon_next_event; 

            @(posedge rx_intf.clk); 
        end
    endtask
endclass

class monitor;
    transaction tr;
    virtual rx_interface rx_intf;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_event;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual rx_interface rx_intf, event mon_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.rx_intf = rx_intf;
        this.mon_next_event = mon_next_event;
    endfunction


    task run();
        forever begin
            #(BIT_PERIOD*10);
            //@(mon_next_event);
            tr = new;
            tr.random_data = rx_intf.random_data;
            tr.rx_data = rx_intf.rx_data;
            tr.display("MON");
            mon2scb_mbox.put(tr);
            @(posedge rx_intf.clk);
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    int pass_count = 0, fail_count = 0;


    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.display("SCB");
            if (tr.rx_data == tr.random_data) begin
                pass_count++;
                $display("[SCB] PASS: expected_data = %h(%b) == rx_data = %h(%b)",
                tr.random_data, tr.random_data, tr.rx_data, tr.rx_data);
                $display("");
            end else begin
                fail_count++;
                $display("[SCB] FAIL: expected_data = %h(%b) != rx_data = %h(%b)",
                tr.random_data, tr.random_data, tr.rx_data, tr.rx_data);
                $display("");
            end
            ->gen_next_event;
        end

    endtask 
endclass

class environment;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    generator gen;
    driver drv;
    event gen_next_event;
    event mon_next_event;
    monitor mon;
    scoreboard scb;

    function new(virtual rx_interface rx_intf);
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(gen2drv_mbox, rx_intf, mon_next_event);
        mon = new(mon2scb_mbox, rx_intf, mon_next_event);
        scb = new(mon2scb_mbox, gen_next_event);
    endfunction

    task report();
        $display("===============================");
        $display("=========test report ==========");
        $display("===============================");
        $display("==     Total Test : %3d     ==", gen.total_count);
        $display("==     Pass Test : %3d      ==", scb.pass_count);
        $display("==     Fail Test : %3d      ==", scb.fail_count);
        $display("===============================");
        $display("==  Test bench is finish ==");
        $display("===============================");

    endtask 

    task reset();
        drv.reset();
    endtask

    task run();
        fork
            gen.run(256);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        report();
        $display("finished");
        $stop;
    endtask
endclass

module tb_uart_rx ();
    environment env;
    rx_interface rx_intf_tb ();

    logic w_b_tick;

    uart_rx dut (
        .clk    (rx_intf_tb.clk),
        .rst    (rx_intf_tb.rst),
        .b_tick (w_b_tick),
        .rx     (rx_intf_tb.rx),
        .rx_data(rx_intf_tb.rx_data),
        .rx_done(rx_intf_tb.rx_done)
    );

    baud_tick_gen dut1 (
        .clk(rx_intf_tb.clk),
        .rst(rx_intf_tb.rst),
        .b_tick(w_b_tick)
    );

    always #5 rx_intf_tb.clk = ~rx_intf_tb.clk;

    initial begin
        rx_intf_tb.clk = 0;
        env = new(rx_intf_tb);
        env.reset();
        env.run();
    end
endmodule
