`timescale 1ns / 1ps

interface fifo_interface;
    logic       clk;
    logic       rst;
    logic       wr;
    logic       rd;
    logic [7:0] wdata;
    logic       full;
    logic       empty;
    logic [7:0] rdata;
endinterface

class transaction;
    rand logic wr; 
    rand logic rd;
    rand logic [7:0] wdata;
    logic [7:0] rdata;
    logic full;
    logic empty;

    constraint push_dist {
        wr dist{
            0 :/ 40,
            1 :/ 60
        };
    }

    constraint pop_dist {
        rd dist{
            0 :/ 60,
            1 :/ 40
        };
    }

    task display(string name_s);
        $display(
            "%t, [%s] wr = %d, rd = %d, wdata = %d, rdata = %d, full = %d, empty = %d",
            $time, name_s, wr, rd, wdata, rdata, full, empty);
    endtask
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    // event를 받기 위한 
    event gen_next_event;

    virtual fifo_interface fifo_intf;
    int total_count = 0;

    function new(mailbox#(transaction) gen2drv_mbox, virtual fifo_interface fifo_intf, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.fifo_intf = fifo_intf;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int count);
        repeat (count) begin
            total_count++;
            tr = new;
            assert (tr.randomize()) 
            else $display("[GEN] tr.randomize() error!!!!!");
            tr.display("[GEN]");
            gen2drv_mbox.put(tr);
            
            @(gen_next_event);
            //@(posedge fifo_intf.clk);
        end
    endtask
endclass

// drive for interface
class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual fifo_interface fifo_intf;
    event mon_next_event;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual fifo_interface fifo_intf, event mon_next_event);
        this.gen2drv_mbox = gen2drv_mbox;
        this.fifo_intf = fifo_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task reset();
        fifo_intf.clk = 0;
        fifo_intf.rst = 1;
        fifo_intf.wr = 0;
        fifo_intf.rd = 0;
        fifo_intf.wdata = 0;
        repeat (2) @(posedge fifo_intf.clk);
        fifo_intf.rst = 0;
        repeat (2) @(posedge fifo_intf.clk);
        $display("[DRV] reset done!");
    endtask

    task run();
        forever begin
            #1;
            gen2drv_mbox.get(tr);
            fifo_intf.wr = tr.wr;
            fifo_intf.rd = tr.rd;
            fifo_intf.wdata = tr.wdata;
            #1;
            tr.display("[DRV]");
            #17;
            ->mon_next_event;
            @(posedge fifo_intf.clk);
        end
    endtask
endclass

class monitor;
    transaction tr;
    virtual fifo_interface fifo_intf;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_event;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual fifo_interface fifo_intf, event mon_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.fifo_intf = fifo_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task run (); 
        forever begin
            @(mon_next_event);
            tr = new;
            tr.wr = fifo_intf.wr;
            tr.rd = fifo_intf.rd;
            tr.wdata = fifo_intf.wdata;
        
            tr.full = fifo_intf.full;
            tr.empty = fifo_intf.empty;
            tr.rdata = fifo_intf.rdata;
        
            mon2scb_mbox.put(tr);
            tr.display("[MON]");  
            @(posedge fifo_intf.clk);
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
 
    event gen_next_event;

    int pass_count = 0, fail_count = 0;

    // Queue 
    logic [7:0] fifo_queue [$:7]; 
    logic [7:0] expected_data;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.display("[SCB]"); 

            // tr.wr == 1 : push
            if(tr.wr) begin
                if(!tr.full)begin
                    fifo_queue.push_back(tr.wdata);
                    $display("[SCB] : Data store in Queue: data:%d, size:%d", tr.wdata, fifo_queue.size());
                end else begin
                    $display("[SCB] : Queue is full : %d", fifo_queue.size());
                end
            end

            // tr.rd == 1 : pop
            if(tr.rd)begin
                if(!tr.empty)begin
                    expected_data = fifo_queue.pop_front();
                    if(tr.rdata == expected_data)begin
                        $display("[SCB] : Data matched : %d ", tr.rdata); 
                        $display("-> Pass | expected data = %d == received data = %d", expected_data, tr.rdata); 
                        pass_count++; 
                    end else begin
                        $display("[SCB] : Data mismatched : %d , %d ", tr.rdata, expected_data);
                        $display("-> Fail | expected data = %d == received data = %d", expected_data, tr.rdata);
                        fail_count++;
                    end
                end else begin
                    $display("[SCB] FIFO is Empty");
                end
            end
            $display("---------------------------");
            $display("%p", fifo_queue); 
            $display("---------------------------");
            ->gen_next_event;
            @(posedge fifo_intf.clk);
        end
    endtask
endclass

class environment;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    event                  gen_next_event;
    event                  mon_next_event;

    function new(virtual fifo_interface fifo_intf);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, fifo_intf, gen_next_event);
        drv = new(gen2drv_mbox, fifo_intf, mon_next_event);
        mon = new(mon2scb_mbox, fifo_intf, mon_next_event);
        scb = new(mon2scb_mbox, gen_next_event);
    endfunction

    task report();
        $display("===========================");
        $display("=======test report ========");
        $display("===========================");
        $display("==  Total Test : %d  ==", gen.total_count);
        $display("==  Pass Test : %d   ==", scb.pass_count);
        $display("==  Fail Test : %d   ==", scb.fail_count);
        $display("===========================");
        $display("==  Test bench is finish ==");
        $display("===========================");
    endtask  

    task reset();
        drv.reset();
    endtask 

    task run();
        fork
            gen.run(50);
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

module tb_fifo_top ();
    environment env;
    fifo_interface fifo_if_tb ();

    fifo dut (
        .clk(fifo_if_tb.clk),
        .rst(fifo_if_tb.rst),
        .rd(fifo_if_tb.rd),
        .wr(fifo_if_tb.wr),
        .wdata(fifo_if_tb.wdata),
        .rdata(fifo_if_tb.rdata),
        .full(fifo_if_tb.full),
        .empty(fifo_if_tb.empty)
    );

    always #5 fifo_if_tb.clk = ~fifo_if_tb.clk;

    initial begin
        fifo_if_tb.clk = 0;
        env = new(fifo_if_tb);
        env.reset();
        env.run();
    end
endmodule
