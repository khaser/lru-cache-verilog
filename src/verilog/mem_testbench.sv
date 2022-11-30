`include "mem.sv"

module MemoryTestbench;

    logic reset = 0, m_dump = 0, clk;
    wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_w;
    wire[data2_bus_size*BITS_IN_BYTE-1:0] data_w;
    wire[1:0] cmd_w;
    logic[1:0] cmd = C2_NOP;
    logic[addr2_bus_size*BITS_IN_BYTE-1:0] addr;
    logic[data2_bus_size*BITS_IN_BYTE-1:0] data;
    bit owner = 1;
    longint clk_time;

    Clock clock(clk, clk_time);
    Memory #(64) mem(clk, reset, m_dump, addr_w, data_w, cmd_w);

    assign addr_w = addr;
    assign data_w = owner ? data : {data2_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_w = owner ? cmd : 2'bzz;

    integer i;

    task run_read(input int addr_, output logic[cache_line_size*BITS_IN_BYTE-1:0] data_, output longint timing);
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
        @(posedge clk);
        timing = clk_time + 1;
        owner <= 1;
        cmd <= C2_WRITE_LINE;
        addr <= addr_;
        for (i = 0; i < cache_line_size / data2_bus_size; i += 1) begin
            data <= data_[i * data2_bus_size * BITS_IN_BYTE +: data2_bus_size * BITS_IN_BYTE];
            @(posedge clk);
        end
        owner <= 0;
        wait(cmd_w == C2_RESPONSE);
        timing = clk_time - timing;
        cmd <= C2_NOP;
        owner <= 1;
    endtask

    logic[cache_line_size * BITS_IN_BYTE - 1 : 0] buff_a, buff_b;
    longint timing = 100;
    integer test_addr = 5;
    logic[cache_line_size * BITS_IN_BYTE - 1 : 0] test_payload = {cache_line_size{$random()}};

    always @(timing)
        if (timing != mem_feedback_time)
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
        $finish;
    end
endmodule
