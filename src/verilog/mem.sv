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

    always @(posedge dump) begin
        $display("---Begin Memory dump---");
        for (i = 0; i < mem_size; i += 1) begin
            $display("[%d] %d", i, heap[i]);  
        end
        $display("---End Memory dump---");
    end


    integer it, byte_in_bus;

    always @(negedge clk) begin
        if (cmd_w == C2_WRITE_LINE) begin
            for (it = addr * cache_line_size; it < addr * cache_line_size + cache_line_size; it += data2_bus_size) begin
                for (byte_in_bus = 0; byte_in_bus < data2_bus_size; byte_in_bus += 1) begin
                    heap[it + byte_in_bus] <= data_w[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end
            #(mem_feedback_time - 2 * cache_line_size / data2_bus_size);
            @(negedge clk);
            cmd <= C2_RESPONSE;
            owner <= 1;
            @(negedge clk);
            owner <= 0;
        end
    end

    always @(posedge clk) begin
        if (cmd_w == C2_READ_LINE) begin
            #(mem_feedback_time);
            @(posedge clk)
            cmd <= C2_RESPONSE;
            owner <= 1;
            for (it = addr * cache_line_size; it < addr * cache_line_size + cache_line_size; it += data2_bus_size) begin
                for (byte_in_bus = 0; byte_in_bus < data2_bus_size; byte_in_bus += 1) begin
                    data[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE] <= heap[it + byte_in_bus];
                end
                @(posedge clk);
            end
            owner <= 0;
        end
    end

endmodule

module MemoryTestbench;

    logic reset = 0, m_dump = 0, clk;
    wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_w;
    wire[data2_bus_size*BITS_IN_BYTE-1:0] data_w;
    wire[1:0] cmd_w;
    logic[1:0] cmd = C2_NOP;
    logic[addr2_bus_size*BITS_IN_BYTE-1:0] addr;
    logic[data2_bus_size*BITS_IN_BYTE-1:0] data;
    bit owner = 1;

    Clock clock(clk);
    Memory #(64) mem(clk, reset, m_dump, addr_w, data_w, cmd_w);

    assign addr_w = addr;
    assign data_w = owner ? data : {data2_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_w = owner ? cmd : 2'bzz;

    integer it;

    task run_read(input int addr_, output logic[cache_line_size*BITS_IN_BYTE-1:0] data_, output longint timing);
        longint first_request;
        @(negedge clk);
        first_request <= $time + 1;
        owner <= 1;
        cmd <= C2_READ_LINE;
        addr <= addr_;
        @(negedge clk);
        owner <= 0;
        wait(cmd_w == C2_RESPONSE);
        timing <= $time - first_request;
        @(negedge clk);
        for (it = 0; it < cache_line_size; it += data2_bus_size) begin
            data_[it * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE] <= data_w;
            @(negedge clk);
        end
        owner <= 1;
        cmd <= C2_NOP;
    endtask

    task run_write(input int addr_, input logic[cache_line_size*BITS_IN_BYTE-1:0] data_, output longint timing);
        longint first_request;
        @(posedge clk);
        first_request <= $time + 1;
        owner <= 1;
        cmd <= C2_WRITE_LINE;
        addr <= addr_;
        for (it = 0; it < cache_line_size / data2_bus_size; it += 1) begin
            data <= data_[it * data2_bus_size * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE];
            @(posedge clk);
        end
        owner <= 0;
        wait(cmd_w == C2_RESPONSE);
        timing <= $time - first_request;
        @(posedge clk);
        cmd <= C2_NOP;
        owner <= 1;
    endtask

    logic[cache_line_size * BITS_IN_BYTE - 1 : 0] buff_a, buff_b;
    longint timing = 100;
    int test_addr = 5;
    logic[cache_line_size * BITS_IN_BYTE - 1 : 0] test_payload = (1 << 16) + (1 << 8) + 1;

    always @(timing)
        if (timing != 100)
            $display("Memory timing error! Expected: %d, Real %d", mem_feedback_time, timing);

    initial begin
        reset <= 1;
        #1;
        reset <= 0;
        #1;

        begin : TEST_ZERO_ADDR
            run_read(0, buff_a, timing);
            run_write(0, test_payload, timing);
            run_read(0, buff_b, timing);
            if (buff_b != test_payload) 
                $display("Memory correctness unit test failed, real: %b expected: %b", buff_b, test_payload);
        end

        begin : CHECK_CUSTOM_ADDR
            run_write(test_addr, buff_a, timing);
            run_read(test_addr, buff_b, timing);
            if (buff_a != buff_b) 
                $display("Memory correctness unit test failed, real: %b expected: %b", buff_b, buff_a);
        end

        $display("Finish memory testing");
    end
endmodule
`endif 
