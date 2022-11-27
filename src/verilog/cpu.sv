`ifndef CPU_GUARD
`define CPU_GUARD

`include "clock.sv"
`include "cache.sv"
`include "mem.sv"

module CpuEmulator;

    logic                                 clk, reset=0, c_dump=0, m_dump=0;
    wire[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu_w;
    wire[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu_w;
    wire[2:0]                             cmd_cpu_w ;
    wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_mem_w;
    wire[data2_bus_size*BITS_IN_BYTE-1:0] data_mem_w;
    wire[1:0]                             cmd_mem_w ;

    bit owner_cpu = 1;
    logic[2:0] cmd_cpu = C1_NOP;
    logic[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu;
    logic[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu;
    assign addr_cpu_w = addr_cpu;
    assign data_cpu_w = owner_cpu ? data_cpu : {data1_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_cpu_w = owner_cpu ? cmd_cpu : 3'bzzz;

    integer total_hits, total_misses;
    
    Clock cloker(clk);
    Memory mem(clk, reset, m_dump, addr_mem_w, data_mem_w, cmd_mem_w);
    Cache cache(clk, reset, c_dump, addr_cpu_w, data_cpu_w, cmd_cpu_w, addr_mem_w, data_mem_w, cmd_mem_w, total_hits, total_misses);

    task run_read(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        output logic[BITS_IN_BYTE*cache_line_size-1:0] data
    );
        logic[BITS_IN_BYTE*data1_bus_size-1:0] local_buff;

        @(posedge clk);
        cmd_cpu <= cmd;
        addr_cpu <= addr[cache_offset_size +: cache_set_size + cache_tag_size];
        @(posedge clk);
        addr_cpu <= addr[0 +: cache_offset_size];
        @(posedge clk);
        owner_cpu <= 0;
        wait(cmd_cpu_w == C1_RESPONSE);

        case (cmd) 
            C1_READ8, C1_READ16 : begin
                data <= data_cpu_w;
            end
            C1_READ32 : begin
                local_buff <= data_cpu_w;
                @(posedge clk);
                data <= {data_cpu_w[0 +: data1_bus_size*BITS_IN_BYTE], local_buff[0 +: data1_bus_size*BITS_IN_BYTE]};
            end
            default : begin
                $display("Incorrect run_read cmd: %d", cmd);
                $finish;
            end
        endcase
        @(posedge clk);
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
    endtask

    task run_write(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        input logic[BITS_IN_BYTE*cache_line_size - 1:0] data
    );
        @(posedge clk);
        cmd_cpu <= cmd;
        addr_cpu <= addr[cache_offset_size +: cache_set_size + cache_tag_size];
        @(posedge clk);
        addr_cpu <= addr[0 +: cache_offset_size];

        case (cmd) 
            C1_WRITE8, C1_WRITE16 : begin
                data_cpu <= data;
            end
            C1_WRITE32 : begin
                data_cpu <= data[0 +: data1_bus_size * BITS_IN_BYTE];
                @(posedge clk);
                data_cpu <= data[data1_bus_size*BITS_IN_BYTE +: data1_bus_size*BITS_IN_BYTE];
            end
            default : begin
                $display("Incorrect run_read cmd: %d", cmd);
                $finish;
            end
        endcase
        @(posedge clk);
        owner_cpu <= 0;
        @(posedge clk);
        wait(cmd_cpu_w == C1_RESPONSE);
        @(posedge clk);
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
    endtask

    localparam M = 64;
    localparam N = 60;
    localparam K = 32;
    integer a_addr = 0;
    integer b_addr = a_addr + M * K;
    integer c_addr = b_addr + K * N * 2;

    integer y, x, k;
    integer pa, pb, pc;
    integer s;

    logic[BITS_IN_BYTE-1:0] wbuff;
    logic[2 * BITS_IN_BYTE-1:0] dbuff;
    logic[4 * BITS_IN_BYTE-1:0] qbuff;


    initial begin
        reset <= 1;
        pa = a_addr; #1; // init pa
        reset <= 0;
        pc = c_addr; #1; // init pc

        #1; // y init;
        for (y = 0; y < M; y++) begin //#1; // loop
            #1; // x init;
            for (x = 0; x < N; x++) begin #1; // loop
                pb =#1 b_addr; // init pb
                s =#1 0; // init s
                #1; // k init;
                for (k = 0; k < K; k++) begin #1; // loop
                    // s += pa[k] * pb[x] begin
                    run_read(pa + k, C1_READ8, wbuff);
                    run_read(pb + x * 2, C1_READ16, dbuff);
                    qbuff =#5 wbuff * dbuff; // (*)
                    s =#1 s + qbuff; // (+)
                    // s += pa[k] * pb[x] end
                    pb =#1 pb + N * 2; // (+)
                end
                run_write(pc + x * 4, C1_WRITE32, s);
            end
            pa =#1 pa + K; // (+)
            pc =#1 pc + N * 4; // (+)
            $display("time: %d %t", y, $time);
            $fflush;
        end
        #1; // function exit
        $display("Finish cpu run\n Time: %t\nTotal hits: %d\nTotal misses: %d", $time, total_hits, total_misses);
        $finish;
        /* Time:        5756380 */
        /* Total hits:   228080 */
        /* Total misses:  21520 */
    end
endmodule
`endif 
