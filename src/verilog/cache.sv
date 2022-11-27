`ifndef CACHE_GUARD
`define CACHE_GUARD

`include "parameters.sv"
`include "mem.sv"
`include "clock.sv"

module Cache (
        input  wire                                  clk, reset, dump,
        input  wire[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu_w,
        inout  wire[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu_w,
        inout  wire[2:0]                             cmd_cpu_w,
        output wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_mem_w,
        inout  wire[data2_bus_size*BITS_IN_BYTE-1:0] data_mem_w,
        inout  wire[1:0]                             cmd_mem_w,
        output integer total_hits = 0,
        output integer total_misses = 0
    );

    localparam cache_sets_count = 1 << cache_set_size;

    bit owner_cpu = 0;
    logic[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu;
    logic[2:0] cmd_cpu;
    assign data_cpu_w = owner_cpu ? data_cpu : {data1_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_cpu_w = owner_cpu ? cmd_cpu : 3'bzzz;

    bit owner_mem = 1;
    logic[addr2_bus_size*BITS_IN_BYTE-1:0] addr_mem;
    logic[data2_bus_size*BITS_IN_BYTE-1:0] data_mem;
    logic[1:0] cmd_mem = C2_NOP;
    assign addr_mem_w = addr_mem;
    assign data_mem_w = owner_mem ? cmd_mem : {data2_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_mem_w = owner_mem ? cmd_mem : 2'bzz;

    typedef struct packed { 
        logic valid;
        logic dirty;
        logic[8 * BITS_IN_BYTE-1:0] last_update;
        logic[cache_tag_size-1:0] tag;
        logic[cache_line_size*BITS_IN_BYTE-1:0] data;
    } cacheLine;

    typedef struct packed { 
        logic[cache_tag_size-1:0] tag;
        logic[cache_set_size-1:0] set;
        logic[cache_offset_size-1:0] offset;
    } cacheAddr;

    cacheLine[cache_way * cache_sets_count-1:0] lines;

    function int bytes_cnt_from_cmd(logic[2:0] cmd);
        case (cmd & 3'b011) 
            3'b001 : begin
                return 1;
            end
            3'b010 : begin
                return 2;
            end
            3'b011 : begin
                return 4;
            end
        endcase
    endfunction

    always @(posedge reset) begin
        $display("RESET");
        for (i = 0; i < cache_way * cache_sets_count; i += 1) begin
            lines[i] <= 0;
        end
    end

    integer action_word, it, i, j;
    logic[cache_line_size * BITS_IN_BYTE-1:0] buff_a, buff_b;
    cacheAddr curAddr;

    always @(negedge clk) begin
        if (owner_cpu == 0 && (cmd_cpu_w == C1_WRITE8 || cmd_cpu_w == C1_WRITE16 || cmd_cpu_w == C1_WRITE32)) begin
            // READ 1-ST
            action_word <= bytes_cnt_from_cmd(cmd_cpu_w);
            {curAddr.tag, curAddr.set} <= addr_cpu_w;
            // READ 2-ND
            @(negedge clk);
            curAddr.offset = addr_cpu_w;

            // Read data
            for (j = 0; j < action_word; j += data1_bus_size) begin
                for (i = 0; i + j < action_word && i < data1_bus_size; i++) begin
                    buff_a[(curAddr.offset + j + i) * BITS_IN_BYTE +: BITS_IN_BYTE] <= data_cpu_w[i * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end
            owner_cpu <= 1;
            cmd_cpu <= C1_NOP;

            // Searching line
            it = search_by_addr_or_empty(curAddr, lines);
            // Uploading from memory if needed
            if (it == -1 || !lines[it].valid || lines[it].tag != curAddr.tag) begin
                total_misses++;
                run_mem_read({curAddr.tag, curAddr.set}, buff_b);
            end else begin
                total_hits++;
                buff_b <= lines[it];
            end

            // Merging buffers
            for (i = 0; i < action_word; i++) begin
                buff_b[(curAddr.offset + i) * BITS_IN_BYTE +: BITS_IN_BYTE] = buff_a[(curAddr.offset + i) * BITS_IN_BYTE +: BITS_IN_BYTE];
            end

            // Purge if needed
            if (it == -1) begin
                it = find_lru(curAddr.set, lines);
                if (lines[it].dirty)
                    run_mem_write({lines[it].tag, curAddr.set}, lines[it]);
            end 

            lines[it] <= {1'b1, 1'b1, $time, curAddr.tag, buff_b};

            owner_cpu <= 1;
            cmd_cpu <= C1_RESPONSE;
            @(negedge clk);
            owner_cpu <= 0;
        end
    end

    function int search_by_addr_or_empty(
            input cacheAddr addr,
            input cacheLine[cache_way * cache_sets_count-1:0] lines
        );
        it = -1;
        for (i = addr.set * cache_way; i < addr.set * cache_way + cache_way; ++i) begin
            if (lines[i].valid && lines[i].tag == addr.tag)
                it = i;
            if (!lines[i].valid && it == -1) 
                it = i;
        end
        return it;
    endfunction

    function int find_lru(input logic[cache_set_size-1:0] set, input cacheLine[cache_way * cache_sets_count-1:0] lines);
        integer it_time;
        it_time = INF;
        it = -1;
        for (i = set * cache_way; i < set * cache_way + cache_way; ++i) begin
            if (it_time > lines[i].last_update) begin
                it = i;
                it_time = lines[i].last_update;
            end
        end
        return it;
    endfunction

    task run_mem_write(input logic[cache_set_size + cache_tag_size-1:0] addr_, input logic[cache_line_size*BITS_IN_BYTE-1:0] data_);
        @(posedge clk);
        owner_mem <= 1;
        cmd_mem <= C2_WRITE_LINE;
        addr_mem <= addr_;
        for (i = 0; i <= cache_line_size / data2_bus_size; i += 1) begin
            data_mem <= data_[i * data2_bus_size * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE];
            @(posedge clk);
        end
        owner_mem <= 1;
        wait(cmd_mem_w == C2_RESPONSE);
        @(posedge clk);
        cmd_mem <= C2_NOP;
        owner_mem <= 1;
    endtask

    logic[cache_line_size * BITS_IN_BYTE-1:0] buff;
    always @(negedge clk) begin
        if (owner_cpu == 0 && (cmd_cpu_w == C1_READ8 || cmd_cpu_w == C1_READ16 || cmd_cpu_w == C1_READ32)) begin
            // READ 1-ST
            action_word <= bytes_cnt_from_cmd(cmd_cpu_w);
            {curAddr.tag, curAddr.set} <= addr_cpu_w;
            // READ 2-ND
            @(negedge clk);
            curAddr.offset = addr_cpu_w;

            it = search_by_addr_or_empty(curAddr, lines);

            if (it == -1) begin
                it = find_lru(curAddr.set, lines);
            end
            if (!lines[it].valid || lines[it].tag != curAddr.tag) begin
                total_misses++;
                run_mem_read({curAddr.tag, curAddr.set}, buff);
                lines[it] <= {1'b1, 1'b0, $time, curAddr.tag, buff};
            end else begin
                total_hits++;
                #3;
                buff = lines[it].data;
                lines[it] <= {lines[it].valid, lines[it].dirty, $time, lines[it].tag, buff};
            end

            owner_cpu <= 1;
            cmd_cpu <= C1_RESPONSE;
            for (j = 0; j < action_word; j += data1_bus_size) begin
                for (i = 0; i + j < action_word && i < data1_bus_size; i++) begin
                    data_cpu[i * BITS_IN_BYTE +: BITS_IN_BYTE] <= buff[(curAddr.offset + j + i) * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end

            owner_cpu <= 0;
        end
    end

    task run_mem_read(input logic[cache_set_size + cache_tag_size-1:0] addr_, output logic[cache_line_size*BITS_IN_BYTE-1:0] data_);
        /* $monitor("time: %t %b %b %b", $time, cmd_mem, addr_mem, data_mem_w); */
        @(negedge clk);
        owner_mem <= 1;
        cmd_mem <= C2_READ_LINE;
        addr_mem <= addr_;
        @(negedge clk);
        owner_mem <= 0;
        wait(cmd_mem_w == C2_RESPONSE);
        @(negedge clk);
        for (i = 0; i < cache_line_size; i += data2_bus_size) begin
            data_[i * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE] <= data_mem_w;
            @(negedge clk);
        end
        owner_mem <= 1;
        cmd_mem <= C2_NOP;
    endtask
    
endmodule

`endif
