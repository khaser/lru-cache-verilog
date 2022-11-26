`ifndef CACHE_GUARD
`define CACHE_GUARD

`include "parameters.sv"
`include "mem.sv"
`include "clock.sv"

module Cache 
    #(
        parameter cache_way = 2,
        parameter cache_tag_size = 10,
        parameter cache_set_size = 5, 
        parameter cache_offset_size = 4
    ) 
    (
        input  wire                                  clk, reset, dump,
        input  wire[addr1_bus_size*BITS_IN_BYTE-1:0] addr_cpu_w,
        inout  wire[data1_bus_size*BITS_IN_BYTE-1:0] data_cpu_w,
        inout  wire[2:0]                             cmd_cpu_w,
        output wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_mem_w,
        inout  wire[data2_bus_size*BITS_IN_BYTE-1:0] data_mem_w,
        inout  wire[1:0]                             cmd_mem_w
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

    function int bytesCntFromCmd(logic[2:0] cmd);
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
    logic[cache_line_size * BITS_IN_BYTE-1:0] buff;
    cacheAddr curAddr;

    always @(negedge clk) begin
        if (owner_cpu == 0 && (cmd_cpu_w == C1_WRITE8 || cmd_cpu_w == C1_WRITE16 || cmd_cpu_w == C1_WRITE32)) begin
            // READ 1-ST
            action_word <= bytesCntFromCmd(cmd_cpu_w);
            {curAddr.tag, curAddr.set} <= addr_cpu_w;
            // READ 2-ND
            @(negedge clk);
            curAddr.offset = addr_cpu_w;
            $display("write tag %d set %d offset %d", curAddr.tag, curAddr.set, curAddr.offset);

            // SEARCHING LINE
            it = search_by_addr_or_empty(curAddr, lines);
            buff <= (it != -1) ? lines[it] : 0;

            // READ DATA
            for (j = 0; j < action_word; j += data1_bus_size) begin
                for (i = 0; i + j < action_word && i < data1_bus_size; i++) begin
                    buff[(curAddr.offset + j + i) * BITS_IN_BYTE +: BITS_IN_BYTE] <= data_cpu_w[i * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end

            /* $display("BEFORE\nvalid: %d, dirty: %d, tag: %d it %d", lines[it].valid, lines[it].dirty, lines[it].tag, it); */
            /* $display("data: %b", lines[it].data); */

            if (it == -1) begin
                it = find_lru(curAddr.set, lines);
                if (lines[it].dirty)
                    run_mem_write({lines[it].tag, curAddr.set}, lines[it]);
            end 

            lines[it] <= {1'b1, 1'b1, $time, curAddr.tag, buff};

            /* tick(); */
            /* $display("AFTER\n time: %t, valid: %d, dirty: %d, tag: %d", $time, lines[it].valid, lines[it].dirty, lines[it].tag); */
            /* $display("data: %b", lines[it].data); */
        end
    end

    function int search_by_addr_or_empty(
            input cacheAddr addr,
            input cacheLine[cache_way * cache_sets_count-1:0] lines
        );
        it = -1;
        for (i = addr.set * cache_way; i < addr.set * cache_way + cache_way; ++i) begin
            /* $display("search: %d %b", i, lines[i]); */
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
            if (it_time > lines[i].last_update)
                it = i;
        end
        return it;
    endfunction

    task run_mem_write(input logic[cache_set_size + cache_tag_size-1:0] addr_, input logic[cache_line_size*BITS_IN_BYTE-1:0] data_);
        @(negedge clk);
        cmd_mem <= C2_WRITE_LINE;
        addr_mem <= addr_;
        for (i = 0; i <= cache_line_size / data2_bus_size; i += 1) begin
            @(posedge clk);
            data_mem <= data_[i * data2_bus_size * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE];
        end
        cmd_mem <= C2_NOP;
    endtask

    always @(negedge clk) begin
        if (owner_cpu == 0 && (cmd_cpu_w == C1_READ8 || cmd_cpu_w == C1_READ16 || cmd_cpu_w == C1_READ32)) begin
            // READ 1-ST
            action_word <= bytesCntFromCmd(cmd_cpu_w);
            {curAddr.tag, curAddr.set} <= addr_cpu_w;
            // READ 2-ND
            @(negedge clk);
            curAddr.offset = addr_cpu_w;
            $display("read tag %d set %d offset %d", curAddr.tag, curAddr.set, curAddr.offset);

            it = search_by_addr_or_empty(curAddr, lines);

            if (it == -1) begin
                it = find_lru(curAddr.set, lines);
            end
            if (!lines[it].valid || lines[it].tag != curAddr.tag) begin
                run_read({curAddr.tag, curAddr.set}, lines[it]);
            end
            lines[it] <= {lines[it].valid, lines[it].dirty, $time, lines[it].tag, lines[it].data};

            $display("readed: %b\n", lines[it].data);
            owner_cpu <= 1;
            cmd_cpu <= C1_RESPONSE;
            buff = lines[it];
            @(negedge clk);
            for (j = 0; j < action_word; j += data1_bus_size) begin
                for (i = 0; i + j < action_word && i < data1_bus_size; i++) begin
                    data_cpu[i * BITS_IN_BYTE +: BITS_IN_BYTE] <= buff[(curAddr.offset + j + i) * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end
            owner_cpu <= 0;
        end
    end

    task run_read(input logic[cache_set_size + cache_tag_size-1:0] addr_, output logic[cache_line_size*BITS_IN_BYTE-1:0] data_);
        @(posedge clk);
        cmd_mem <= C2_READ_LINE;
        addr_mem <= addr_;
        @(posedge clk);
        owner_mem <= 0;
        wait(cmd_mem_w == C2_RESPONSE);
        for (it = 0; it < cache_line_size; it += data2_bus_size) begin
            @(posedge clk);
            data_[it * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE] <= data_mem_w;
        end
        @(posedge clk);
        owner_mem <= 1;
        cmd_mem <= C2_NOP;
    endtask

endmodule

module CacheTestbench;
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
    
    Clock cloker(clk);
    Memory mem(clk, reset, m_dump, addr_mem_w, data_mem_w, cmd_mem_w);
    Cache cache(clk, reset, c_dump, addr_cpu_w, data_cpu_w, cmd_cpu_w, addr_mem_w, data_mem_w, cmd_mem_w);

    initial begin
        $display("Start cache testing");
        /* $monitor("%t, cpu=%d, mem=%d", $time, cmd_cpu_w, cmd_mem_w); */
        #10;
        reset <= 1;
        #10;

        @(posedge clk);
        addr_cpu <= 16'b0000000110011011;
        cmd_cpu <= C1_WRITE32;
        @(posedge clk);
        addr_cpu <= 4'b0010;
        data_cpu <= 16'b1010101010101010;
        @(posedge clk);
        data_cpu <= 16'b1111111100000000;
        @(posedge clk);
        cmd_cpu <= C1_NOP;

        @(posedge clk);
        addr_cpu <= 16'b0100000110011011;
        cmd_cpu <= C1_WRITE8;
        @(posedge clk);
        addr_cpu <= 4'b0000;
        data_cpu <= 8'b10011001;
        @(posedge clk);
        cmd_cpu <= C1_NOP;

        @(posedge clk);
        addr_cpu <= 16'b0110000110011011;
        cmd_cpu <= C1_WRITE8;
        @(posedge clk);
        addr_cpu <= 4'b0000;
        data_cpu <= 8'b11100111;
        @(posedge clk);
        cmd_cpu <= C1_NOP;

        #100;

        @(posedge clk);
        cmd_cpu <= C1_READ32;
        addr_cpu <= 16'b0000000000000000;
        @(posedge clk);
        addr_cpu <= 4'b0000;
        @(posedge clk);
        owner_cpu <= 0;
        $monitor("data mon: %b", data_cpu_w);
        #200;
        $display("Finish cache testing");
        $finish;
    end
endmodule
`endif
