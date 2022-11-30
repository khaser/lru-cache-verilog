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
    longint timing;
    
    Clock cloker(clk, timing);
    Memory mem(clk, reset, m_dump, addr_mem_w, data_mem_w, cmd_mem_w);
    Cache cache(clk, reset, c_dump, addr_cpu_w, data_cpu_w, cmd_cpu_w, addr_mem_w, data_mem_w, cmd_mem_w, total_hits, total_misses);

    task run_read(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        output logic[BITS_IN_BYTE*cache_line_size-1:0] data
    );
        logic[BITS_IN_BYTE*data1_bus_size-1:0] local_buff;

        @(negedge clk);
        cmd_cpu <= cmd;
        addr_cpu <= addr[cache_offset_size +: cache_set_size + cache_tag_size];
        @(negedge clk);
        addr_cpu <= addr[0 +: cache_offset_size];
        @(posedge clk);
        owner_cpu <= 0;
        wait(cmd_cpu_w == C1_RESPONSE); // response on posedge!
        case (cmd) 
            C1_READ8, C1_READ16 : begin
                data = data_cpu_w;
            end
            C1_READ32 : begin
                local_buff <= data_cpu_w;
                @(posedge clk);
                data = {data_cpu_w[0 +: data1_bus_size*BITS_IN_BYTE], local_buff[0 +: data1_bus_size*BITS_IN_BYTE]};
            end
            default : begin
                $display("Incorrect run_read cmd: %d", cmd);
                $finish;
            end
        endcase
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
        @(negedge clk);
    endtask

    task run_write(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        input logic[BITS_IN_BYTE*cache_line_size - 1:0] data
    );
        /* $monitor("time: %t, owner: %b, clk: %b cmd_w: %b addr_w: %b data_w: %b", clk_time, owner_cpu, clk, cmd_cpu_w, addr_cpu_w, data_cpu_w); */
        @(negedge clk);
        cmd_cpu <= cmd;
        addr_cpu <= addr[cache_offset_size +: cache_set_size + cache_tag_size];
        @(negedge clk);
        addr_cpu <= addr[0 +: cache_offset_size];

        case (cmd) 
            C1_WRITE8, C1_WRITE16 : begin
                data_cpu <= data;
            end
            C1_WRITE32 : begin
                data_cpu <= data[0 +: data1_bus_size * BITS_IN_BYTE];
                @(negedge clk);
                data_cpu <= data[data1_bus_size*BITS_IN_BYTE +: data1_bus_size*BITS_IN_BYTE];
            end
            default : begin
                $display("Incorrect run_write cmd: %d", cmd);
                $finish;
            end
        endcase
        @(posedge clk);
        owner_cpu <= 0;
        @(negedge clk); // ???
        wait(cmd_cpu_w == C1_RESPONSE);
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
    endtask

    integer skipped_time = 0;
    task automatic skip(input longint ticks = 1);
        logic enter_clk = clk;
        skipped_time += ticks;
        while (ticks > 0) begin
            wait(clk != enter_clk);
            wait(clk == enter_clk);
            ticks--;
        end
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
        skip();
        reset <= 0;
        skip();

        pa = a_addr; skip(); // init pa
        pc = c_addr; skip(); // init pc

        skip(); // y init;
        for (y = 0; y < M; y++) begin skip(); // loop
            skip(); // x init;
            for (x = 0; x < N; x++) begin skip(); // loop
                pb =b_addr; skip(); // init pb
                s = 0; skip(); // init s
                skip(); // k init;
                for (k = 0; k < K; k++) begin skip(); // loop
                    // s += pa[k] * pb[x] begin
                    run_read(pa + k, C1_READ8, wbuff);
                    run_read(pb + x * 2, C1_READ16, dbuff);
                    qbuff = wbuff * dbuff; skip(5); // (*)
                    s = s + qbuff; skip(); // (+)
                    // s += pa[k] * pb[x] end
                    pb = pb + N * 2; skip(); // (+)
                end
                run_write(pc + x * 4, C1_WRITE32, s);
            end
            pa = pa + K; skip(); // (+)
            pc = pc + N * 4; skip(); // (+)
            $display("time: %d %t", y, timing);
            $fflush;
        end
        skip(); // function exit
        $display("Finish cpu run");
        $display("Time: %t", timing);
        $display("Cache time: %t", timing - skipped_time);
        $display("Alu time: %t", skipped_time);
        $display("Total hits: %d", total_hits);
        $display("Total misses: %d", total_misses);
        $finish;

        /* Finish cpu run */
        /* Time:              5272742 */
        /* Cache time         4274080 */
        /* Alu time            998662 */
        /* Total hits:         228080 */
        /* Total misses:        21520 */

    end
endmodule
`endif 
