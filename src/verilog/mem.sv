`ifndef MEMORY_GUARD
`define MEMORY_GUARD

`include "parameters.sv"
`include "clock.sv"

module Memory
    #(
        parameter mem_size = 512 * 1024
    )
    (
        input wire clk, reset, dump,
        input wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr,
        inout wire[data2_bus_size*BITS_IN_BYTE-1:0] data_w,
        inout wire[1:0] cmd_w
    );

    logic[BITS_IN_BYTE-1:0] heap[0:mem_size-1];
    integer SEED = _SEED;
    integer i = 0;

    bit owner = 0;
    logic[1:0] cmd;
    logic[data2_bus_size*BITS_IN_BYTE-1:0] data;

    assign cmd_w = owner ? cmd : 2'bzz;
    assign data_w = owner ? data : {data2_bus_size*BITS_IN_BYTE{1'bz}};

    always @(posedge reset) begin
        for (i = 0; i < mem_size; i += 1) begin
            heap[i] <= $random(SEED)>>16;  
        end
    end

    integer fd;
    always @(posedge dump) begin
        fd = $fopen("mem.dump", "w");
        for (i = 0; i < mem_size; i += 1) begin
            $fdisplay(fd, "[%d] %d", i, heap[i]);  
        end
        $display("Memory has dumped to mem.dump");
        $fclose(fd);
    end

    task automatic skip(input longint ticks = 1);
        logic enter_clk = clk;
        while (ticks > 0) begin
            wait(clk != enter_clk);
            wait(clk == enter_clk);
            ticks--;
        end
    endtask

    integer it, byte_in_bus;

    always @(posedge clk) begin
        if (cmd_w == C2_WRITE_LINE) begin
            for (it = addr * cache_line_size; it < addr * cache_line_size + cache_line_size; it += data2_bus_size) begin
                for (byte_in_bus = 0; byte_in_bus < data2_bus_size; byte_in_bus += 1) begin
                    heap[it + byte_in_bus] <= data_w[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(posedge clk);
            end
            skip(mem_feedback_time - cache_line_size / data2_bus_size - 1);
            @(negedge clk);
            cmd <= C2_RESPONSE;
            owner <= 1;
            @(posedge clk);
            owner <= 0;
        end
    end

    always @(posedge clk) begin
        if (cmd_w == C2_READ_LINE) begin
            cmd <= C2_NOP;
            owner <= 1;
            skip(mem_feedback_time - 1);
            @(negedge clk)
            cmd <= C2_RESPONSE;
            for (it = addr * cache_line_size; it < addr * cache_line_size + cache_line_size; it += data2_bus_size) begin
                for (byte_in_bus = 0; byte_in_bus < data2_bus_size; byte_in_bus += 1) begin
                    data[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE] <= heap[it + byte_in_bus];
                end
                if (it + data2_bus_size >= addr * cache_line_size + cache_line_size)
                    @(posedge clk);
                else
                    @(negedge clk);
            end
            owner <= 0;
        end
    end
endmodule

module MemoryDriver
    (
        input logic clk, 
        input longint clk_time, 
        input logic reset, 
        input logic m_dump,
        output logic[addr2_bus_size*BITS_IN_BYTE-1:0] addr_w,
        inout logic[data2_bus_size*BITS_IN_BYTE-1:0] data_w,
        inout logic[1:0] cmd_w
    );

    logic[1:0] cmd = C2_NOP;
    logic[addr2_bus_size*BITS_IN_BYTE-1:0] addr;
    logic[data2_bus_size*BITS_IN_BYTE-1:0] data;
    bit owner = 1;

    assign cmd_w = owner ? cmd : 2'bzz;
    assign addr_w = addr;
    assign data_w = owner ? data : {data2_bus_size*BITS_IN_BYTE{1'bz}};

    integer i;

    task run_read(input logic[cache_set_size + cache_tag_size-1:0] addr_, output logic[cache_line_size*BITS_IN_BYTE-1:0] data_, output longint timing);
        @(negedge clk);
        owner <= 1;
        cmd <= C2_READ_LINE;
        addr <= addr_;
        timing = clk_time;
        @(posedge clk);
        owner <= 0;
        wait(cmd_w == C2_RESPONSE); 
        @(posedge clk);
        timing = clk_time - timing;
        for (i = 0; i < cache_line_size; i += data2_bus_size) begin
            data_[i * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE] <= data_w;
            if (i + data2_bus_size >= cache_line_size)
                @(negedge clk);
            else
                @(posedge clk);
        end
        owner <= 1;
        cmd <= C2_NOP;
    endtask

    task run_write(input int addr_, input logic[cache_line_size*BITS_IN_BYTE-1:0] data_, output longint timing);
        @(negedge clk);
        timing = clk_time;
        owner <= 1;
        cmd <= C2_WRITE_LINE;
        addr <= addr_;
        for (i = 0; i < cache_line_size / data2_bus_size; i += 1) begin
            data <= data_[i * data2_bus_size * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE];
            @(negedge clk);
        end
        owner <= 0;
        wait(cmd_w == C2_RESPONSE);
        timing = clk_time - timing;
        cmd <= C2_NOP;
        owner <= 1;
    endtask

endmodule
`endif 
