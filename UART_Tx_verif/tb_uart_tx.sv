`timescale 1ns / 1ps

parameter BUAD_RATE = 9600;  
parameter BAUD_DELAY = (100_000_000 / BUAD_RATE) * 10 * 10; 
parameter CLOCK_PERIOD_NS = 10;  
parameter BIT_PER_CLOCK = 10416; 
parameter BIT_PERIOD = BIT_PER_CLOCK * CLOCK_PERIOD_NS; 

// UART TX 인터페이스
interface uart_tx_interface;
    logic       clk;
    logic       rst;
    logic       tx_start;
    logic [7:0] tx_data;
    logic [7:0] received_data;
    logic       b_tick;
    logic       tx_busy;
    logic       tx;
endinterface

// UART Tx 트랜잭션 정의
class transaction;
    rand logic [7:0] tx_data;
    logic [7:0] received_data;

    task display(string name_s);
        $display("%t, [%s] , random_tx_data = %h, received_data = %h", $time, name_s, tx_data, received_data);
    endtask


endclass

// 트랜잭션 생성기 (Generator)
class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_event;

    int total_count = 0;
    int used_numbers[int];

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    // task run(int count);
    //     repeat (count) begin
    //         total_count++;
    //         $display("==================================%3drd Run=====================================",total_count);
    //         tr = new;
    //         assert (tr.randomize())
    //         else $display("[GEN] tr.randomize() error!");

    //         gen2drv_mbox.put(tr);
    //         tr.display("[GEN]");

    //         @(gen_next_event);
    //     end
    // endtask

    task run(int count);
        // 8비트 데이터는 256개의 중복 없는 값만 생성할 수 있습니다.
        if (count > 256) begin
            $error("[GEN] 8비트 데이터는 256개의 중복 없는 값만 생성할 수 있습니다.");
            return;
        end

        repeat (count) begin
            int new_val;
            
            // 중복되지 않는 랜덤 값 찾기
            do begin
                new_val = $urandom_range(0, 255);
            end while (used_numbers.exists(new_val));

            // 찾은 값을 used_numbers에 추가하여 '사용됨'으로 표시
            used_numbers[new_val] = 1;
            
            total_count++;
            $display("==================================%3drd Run=====================================",total_count);
            tr = new;
            
            // 트랜잭션의 tx_data에 중복 없는 랜덤 값 할당
            tr.tx_data = new_val;
            
            gen2drv_mbox.put(tr);
            tr.display("[GEN]");

            @(gen_next_event);
        end
    endtask
endclass

// 드라이버 (Driver)
class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_tx_interface uart_intf;
    event mon_next_event;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_tx_interface uart_intf, event mon_next_event);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uart_intf = uart_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task reset();
        uart_intf.rst = 1;
        uart_intf.tx_start = 0;
        uart_intf.tx_data = 8'h00;
        uart_intf.b_tick = 0;
        repeat (2) @(posedge uart_intf.clk);
        uart_intf.rst = 0;
        $display("%t, [DRV] Reset done!", $time);
        repeat (2) @(posedge uart_intf.clk);
    endtask

    task run();
        forever begin
            gen2drv_mbox.get(tr);

            $display("%t, [[DRV]] Sending data: %h(%b)", $time, tr.tx_data, tr.tx_data);
            uart_intf.tx_start = 1'b1;
            uart_intf.tx_data = tr.tx_data;
            tr.display("[DRV]");
            @(posedge uart_intf.clk);
            uart_intf.tx_start = 1'b0;

            wait (uart_intf.tx_busy);
            ->mon_next_event; 
            wait (!uart_intf.tx_busy);


        end
    endtask
endclass

// 모니터 (Monitor)
class monitor;
    transaction tr;
    virtual uart_tx_interface uart_intf;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_event;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_tx_interface uart_intf, event mon_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.uart_intf = uart_intf;
        this.mon_next_event = mon_next_event;
    endfunction

    task run();
        forever begin

            @(mon_next_event);
            tr = new;

            #(BIT_PERIOD/2);

            if (!uart_intf.tx) begin
                $display("%t, [[MON]] Start bit detection", $time);
            end

            for (int bit_count = 0; bit_count < 8; bit_count = bit_count + 1) begin
                #(BIT_PERIOD);
                tr.received_data[bit_count] = uart_intf.tx;
                $display("%t, [[MON]] tx = %d", $time, uart_intf.tx); 
            end

            #(BIT_PERIOD);

            if (uart_intf.tx) begin
                $display("%t, [[MON]] STOP bit detection", $time);
            end

            $display("%t, [[MON]] Recieved data: %h(%b)", $time, tr.received_data, tr.received_data);

            tr.tx_data = uart_intf.tx_data;

            tr.display("[MON]");

            mon2scb_mbox.put(tr);

        end
    endtask
endclass

// 스코어보드 (Scoreboard)
class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    int pass_count = 0, fail_count = 0;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.display("[SCB]");
            if (tr.tx_data == tr.received_data) begin
                $display("%t, [[SCB]] PASS: Data match. Sent: %h(%b), Received: %h(%b)",
                         $time, tr.tx_data, tr.tx_data, tr.received_data, tr.received_data);
                pass_count++;
            end else begin
                $display("%t, [[SCB]] FAIL: Data mismatch. Sent: %h(%b), Received: %h(%b)",
                          $time, tr.tx_data, tr.tx_data, tr.received_data, tr.received_data);
                fail_count++;
            end

            $display("---------------------------");
            ->gen_next_event;
        end
    endtask
endclass

// 환경 (Environment)
class environment;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;
    event gen_next_event;
    event mon_next_event;

    function new(virtual uart_tx_interface uart_intf);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(gen2drv_mbox, uart_intf, mon_next_event);
        mon = new(mon2scb_mbox, uart_intf, mon_next_event);
        scb = new(mon2scb_mbox, gen_next_event);
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
            gen.run(10);  
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

// 최상위 모듈 (Top Module)
module tb_uart_tx_top ();
    environment env;
    uart_tx_interface uart_if_tb ();

    uart_tx dut (
        .clk(uart_if_tb.clk),
        .rst(uart_if_tb.rst),
        .tx_start(uart_if_tb.tx_start),
        .tx_data(uart_if_tb.tx_data),
        .b_tick(uart_if_tb.b_tick),
        .tx_busy(uart_if_tb.tx_busy),
        .tx(uart_if_tb.tx)
    );

    baud_tick_gen bgen (
        .clk(uart_if_tb.clk),
        .rst(uart_if_tb.rst),
        .o_b_tick(uart_if_tb.b_tick)
    );

    always #5 uart_if_tb.clk = ~uart_if_tb.clk;

    initial begin
        uart_if_tb.clk = 0;
        env = new(uart_if_tb);
        env.reset();
        env.run();
    end
endmodule


// `timescale 1ns / 1ps

// parameter BUAD_RATE = 9600;   
// parameter BAUD_DELAY = (100_000_000 / BUAD_RATE) * 10 * 10; 
// parameter CLOCK_PERIOD_NS = 10;   
// parameter BIT_PER_CLOCK = 10416; 
// parameter BIT_PERIOD = BIT_PER_CLOCK * CLOCK_PERIOD_NS; 

// // UART TX 인터페이스
// interface uart_tx_interface;
//     logic       clk;
//     logic       rst;
//     logic       tx_start;
//     logic [7:0] tx_data;
//     logic [7:0] received_data;
//     logic       b_tick;
//     logic       tx_busy;
//     logic       tx;
// endinterface

// // UART Tx 트랜잭션 정의
// class transaction;
//     rand logic [7:0] tx_data;
//     logic [7:0] received_data;

//     task display(string name_s);
//         $display("%t, [%s] , random_tx_data = %h, received_data = %h", $time, name_s, tx_data, received_data);
//     endtask
// endclass

// // 트랜잭션 생성기 (Generator)
// class generator;
//     transaction tr;
//     mailbox #(transaction) gen2drv_mbox;
//     event gen_next_event;

//     int total_count = 0;
//     // 이미 생성된 값을 추적하는 연관 배열
//     int used_numbers[int];

//     function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
//         this.gen2drv_mbox   = gen2drv_mbox;
//         this.gen_next_event = gen_next_event;
//     endfunction

//     task run(int count);
//         // 8비트 데이터는 256개의 중복 없는 값만 생성할 수 있습니다.
//         if (count > 256) begin
//             $error("[GEN] 8비트 데이터는 256개의 중복 없는 값만 생성할 수 있습니다.");
//             return;
//         end

//         repeat (count) begin
//             int new_val;
            
//             // 중복되지 않는 랜덤 값 찾기
//             do begin
//                 new_val = $urandom_range(0, 255);
//             end while (used_numbers.exists(new_val));

//             // 찾은 값을 used_numbers에 추가하여 '사용됨'으로 표시
//             used_numbers[new_val] = 1;
            
//             total_count++;
//             $display("==================================%3drd Run=====================================",total_count);
//             tr = new;
            
//             // 트랜잭션의 tx_data에 중복 없는 랜덤 값 할당
//             tr.tx_data = new_val;
            
//             gen2drv_mbox.put(tr);
//             tr.display("[GEN]");

//             @(gen_next_event);
//         end
//     endtask
// endclass

// // 드라이버 (Driver)
// class driver;
//     transaction tr;
//     mailbox #(transaction) gen2drv_mbox;
//     virtual uart_tx_interface uart_intf;
//     event mon_next_event;

//     function new(mailbox#(transaction) gen2drv_mbox,
//                  virtual uart_tx_interface uart_intf, event mon_next_event);
//         this.gen2drv_mbox = gen2drv_mbox;
//         this.uart_intf = uart_intf;
//         this.mon_next_event = mon_next_event;
//     endfunction

//     task reset();
//         uart_intf.rst = 1;
//         uart_intf.tx_start = 0;
//         uart_intf.tx_data = 8'h00;
//         uart_intf.b_tick = 0;
//         repeat (2) @(posedge uart_intf.clk);
//         uart_intf.rst = 0;
//         repeat (2) @(posedge uart_intf.clk);
//         $display("[DRV] Reset done!");
//     endtask

//     task run();
//         forever begin
//             gen2drv_mbox.get(tr);

//             $display("[DRV] Sending data: %h(%b)", tr.tx_data, tr.tx_data);
//             uart_intf.tx_start = 1'b1;
//             uart_intf.tx_data = tr.tx_data;
//             tr.display("[DRV]");
//             @(posedge uart_intf.clk);
//             uart_intf.tx_start = 1'b0;

//             wait (uart_intf.tx_busy);
//             ->mon_next_event; 
//             wait (!uart_intf.tx_busy);
//         end
//     endtask
// endclass

// // 모니터 (Monitor)
// class monitor;
//     transaction tr;
//     virtual uart_tx_interface uart_intf;
//     mailbox #(transaction) mon2scb_mbox;
//     event mon_next_event;

//     function new(mailbox#(transaction) mon2scb_mbox,
//                  virtual uart_tx_interface uart_intf, event mon_next_event);
//         this.mon2scb_mbox = mon2scb_mbox;
//         this.uart_intf = uart_intf;
//         this.mon_next_event = mon_next_event;
//     endfunction

//     task run();
//         forever begin
//             @(mon_next_event);
//             tr = new;

//             // start bit 수신
//             @(negedge uart_intf.tx);
            
//             // 데이터 비트 수신
//             for (int bit_count = 0; bit_count < 8; bit_count = bit_count + 1) begin
//                 @(posedge uart_intf.b_tick);
//                 tr.received_data[bit_count] = uart_intf.tx;
//             end

//             // stop bit 수신
//             @(posedge uart_intf.b_tick);

//             $display("[MON] Received data: %h(%b)", tr.received_data, tr.received_data);

//             tr.tx_data = uart_intf.tx_data;

//             tr.display("[MON]");
//             mon2scb_mbox.put(tr);

//         end
//     endtask
// endclass

// // 스코어보드 (Scoreboard)
// class scoreboard;
//     transaction tr;
//     mailbox #(transaction) mon2scb_mbox;
//     event gen_next_event;

//     int pass_count = 0, fail_count = 0;

//     function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
//         this.mon2scb_mbox = mon2scb_mbox;
//         this.gen_next_event = gen_next_event;
//     endfunction

//     task run();
//         forever begin
//             mon2scb_mbox.get(tr);
//             tr.display("[SCB]");
//             if (tr.tx_data == tr.received_data) begin
//                 $display("[SCB] PASS: Data match. Sent: %h(%b), Received: %h(%b)",
//                          tr.tx_data, tr.tx_data, tr.received_data, tr.received_data);
//                 pass_count++;
//             end else begin
//                 $display("[SCB] FAIL: Data mismatch. Sent: %h(%b), Received: %h(%b)",
//                          tr.tx_data, tr.tx_data, tr.received_data, tr.received_data);
//                 fail_count++;
//             end

//             $display("---------------------------");
//             ->gen_next_event;
//         end
//     endtask
// endclass

// // 환경 (Environment)
// class environment;
//     mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;
//     generator gen;
//     driver drv;
//     monitor mon;
//     scoreboard scb;
//     event gen_next_event;
//     event mon_next_event;

//     function new(virtual uart_tx_interface uart_intf);
//         gen2drv_mbox = new;
//         mon2scb_mbox = new;
//         gen = new(gen2drv_mbox, gen_next_event);
//         drv = new(gen2drv_mbox, uart_intf, mon_next_event);
//         mon = new(mon2scb_mbox, uart_intf, mon_next_event);
//         scb = new(mon2scb_mbox, gen_next_event);
//     endfunction

//     task report();
//         $display("===========================");
//         $display("======= Test Report ========");
//         $display("===========================");
//         $display("== Total Test : %d ==", gen.total_count);
//         $display("== Pass Test : %d ==", scb.pass_count);
//         $display("== Fail Test : %d ==", scb.fail_count);
//         $display("===========================");
//         $display("== Test bench is finished ==");
//         $display("===========================");
//     endtask

//     task reset();
//         drv.reset();
//     endtask

//     task run();
//         fork
//             gen.run(256);   
//             drv.run();
//             mon.run();
//             scb.run();
//         join_any
//         #10;
//         $display("finished");
//         report();
//         $stop;
//     endtask
// endclass

// // 최상위 모듈 (Top Module)
// module tb_uart_tx_top ();
//     environment env;
//     uart_tx_interface uart_if_tb ();

//     uart_tx dut (
//         .clk(uart_if_tb.clk),
//         .rst(uart_if_tb.rst),
//         .tx_start(uart_if_tb.tx_start),
//         .tx_data(uart_if_tb.tx_data),
//         .b_tick(uart_if_tb.b_tick),
//         .tx_busy(uart_if_tb.tx_busy),
//         .tx(uart_if_tb.tx)
//     );

//     baud_tick_gen bgen (
//         .clk(uart_if_tb.clk),
//         .rst(uart_if_tb.rst),
//         .o_b_tick(uart_if_tb.b_tick)
//     );

//     always #5 uart_if_tb.clk = ~uart_if_tb.clk;

//     initial begin
//         uart_if_tb.clk = 0;
//         env = new(uart_if_tb);
//         env.reset();
//         env.run();
//     end
// endmodule