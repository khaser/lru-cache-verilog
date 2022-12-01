`include "cache.sv"

module CacheTestbench;

    logic                                 clk, reset=0, c_dump=0, m_dump=0;
    wire[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu_w;
    wire[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu_w;
    wire[2:0]                             cmd_cpu_w ;
    wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_mem_w;
    wire[data2_bus_size*BITS_IN_BYTE-1:0] data_mem_w;
    wire[1:0]                             cmd_mem_w ;
    integer total_hits, total_misses;

    bit owner_cpu = 1;
    logic[2:0] cmd_cpu = C1_NOP;
    logic[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu;
    logic[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu;
    assign addr_cpu_w = addr_cpu;
    assign data_cpu_w = owner_cpu ? data_cpu : {data1_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_cpu_w = owner_cpu ? cmd_cpu : 3'bzzz;
    
    longint clk_time;
    Clock cloker(clk, clk_time);
    Memory mem(clk, reset, m_dump, addr_mem_w, data_mem_w, cmd_mem_w);
    Cache cache(clk, reset, c_dump, addr_cpu_w, data_cpu_w, cmd_cpu_w, addr_mem_w, data_mem_w, cmd_mem_w, total_hits, total_misses);

    task run_read(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        output logic[BITS_IN_BYTE*cache_line_size-1:0] data,
        output longint timing
    );
        logic[BITS_IN_BYTE*data1_bus_size-1:0] local_buff;

        @(negedge clk);
        cmd_cpu <= cmd;
        timing = clk_time;
        addr_cpu <= addr[cache_offset_size +: cache_set_size + cache_tag_size];
        @(negedge clk);
        addr_cpu <= addr[0 +: cache_offset_size];
        @(posedge clk);
        owner_cpu <= 0;
        wait(cmd_cpu_w == C1_RESPONSE); // response on posedge!
        timing = clk_time - timing;
        case (cmd) 
            C1_READ8, C1_READ16 : begin
                data = data_cpu_w;
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
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
        @(negedge clk);
    endtask

    task run_write(
        input logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] addr,
        input logic[2:0] cmd,
        input logic[BITS_IN_BYTE*cache_line_size - 1:0] data,
        output longint timing
    );
        /* $monitor("time: %t, owner: %b, clk: %b cmd_w: %b addr_w: %b data_w: %b", clk_time, owner_cpu, clk, cmd_cpu_w, addr_cpu_w, data_cpu_w); */
        @(negedge clk);
        timing = clk_time;
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
        timing = clk_time - timing;
        owner_cpu <= 1;
        cmd_cpu <= C1_NOP;
    endtask

    logic[cache_line_size * BITS_IN_BYTE - 1:0] buff;
    logic[cache_tag_size + cache_offset_size + cache_set_size - 1 : 0] test_addr = 19'b1111010101001001001;
    logic[4 * BITS_IN_BYTE:0] test_payload = $random();
    integer i;
    longint timing;

    task resetCache();
        reset <= 1;
        @(posedge clk);
        reset <= 0;
        @(negedge clk);
    endtask

    initial begin

        begin : TEST_CACHE_HITS
            resetCache();
            run_read(0, C1_READ8, buff, timing);
            if (timing != cache_miss_time) 
                $display("Cache read-miss timing error! Expected: %d, Real %d", cache_miss_time, timing);
            for (i = 1; i < 32; ++i) begin
                run_read(i, C1_READ8, buff, timing);
                if (i != 16 && timing != cache_hit_time) // i = 16 -- cache miss
                    $display("Cache read-hit timing error! Expected: %d, Real %d", cache_hit_time, timing);
            end
            if (total_hits != 30)
                $display("Wrong cache hits! Expected: 30, Found: %d", total_hits);
        end

        begin : TEST_SINGLE_READ_WRITE_32
            resetCache();
            run_write(test_addr, C1_WRITE32, test_payload, timing);
            if (timing != cache_miss_time)
                $display("Cache write-miss timing error! Expected: %d, Real %d", cache_miss_time, timing);
            run_read(test_addr, C1_READ32, buff, timing);
            if (buff[0 +: BITS_IN_BYTE * 4] != test_payload[0 +: BITS_IN_BYTE * 4]) begin
                $display("Cache correctness qword unit test failed, real: %b expected: %b",
                    buff[0 +: BITS_IN_BYTE * 4], test_payload[0 +: BITS_IN_BYTE * 4]);
            end
            run_write(test_addr, C1_WRITE32, test_payload, timing);
            if (timing != cache_hit_time)
                $display("Cache write-hit timing error! Expected: %d, Real %d", cache_hit_time, timing);
        end

        begin : TEST_SINGLE_READ_WRITE_16
            resetCache();
            run_write(test_addr, C1_WRITE16, test_payload, timing);
            if (timing != cache_miss_time) 
                $display("Cache write-miss timing error! Expected: %d, Real %d", cache_miss_time, timing);
            run_read(test_addr, C1_READ16, buff, timing);
            if (buff[0 +: BITS_IN_BYTE * 2] != test_payload[0 +: BITS_IN_BYTE * 2]) begin
                $display("Cache correctness dword unit test failed, real: %b expected: %b",
                    buff[0 +: BITS_IN_BYTE * 2], test_payload[0 +: BITS_IN_BYTE * 2]);
            end
            run_write(test_addr, C1_WRITE16, test_payload, timing);
            if (timing != cache_hit_time)
                $display("Cache write-hit timing error! Expected: %d, Real %d", cache_hit_time, timing);
        end

        begin : TEST_SINGLE_READ_WRITE_8
            resetCache();
            run_write(test_addr, C1_WRITE8, test_payload, timing);
            run_read(test_addr, C1_READ8, buff, timing);
            if (buff[0 +: BITS_IN_BYTE] != test_payload[0 +: BITS_IN_BYTE]) begin
                $display("Cache correctness word unit test failed, real: %b expected: %b",
                    buff[0 +: BITS_IN_BYTE], test_payload[0 +: BITS_IN_BYTE]);
            end
            run_write(test_addr, C1_WRITE8, test_payload, timing);
            if (timing != cache_hit_time)
                $display("Cache write-hit timing error! Expected: %d, Real %d", cache_hit_time, timing);
        end

        $display("Finish cache testing");
        $finish;
    end
endmodule
