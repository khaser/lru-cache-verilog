`include "mem.sv"

module MemoryTestbench;

    logic reset = 0, m_dump = 0, clk;
    wire[addr2_bus_size*BITS_IN_BYTE-1:0] addr_w;
    wire[data2_bus_size*BITS_IN_BYTE-1:0] data_w;
    wire[1:0] cmd_w;
    longint clk_time;

    Clock clock(clk, clk_time);
    Memory #(64) mem(clk, reset, m_dump, addr_w, data_w, cmd_w);
    MemoryDriver driver(clk, clk_time, reset, m_dump, addr_w, data_w, cmd_w);

    integer i;

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
            driver.run_read(0, buff_a, timing);
            driver.run_write(0, test_payload, timing);
            driver.run_read(0, buff_b, timing);
            if (buff_b != test_payload) 
                $display("Memory correctness unit test failed, real: %b expected: %b", buff_b, test_payload);
        end

        begin : CHECK_CUSTOM_ADDR
            driver.run_write(test_addr, buff_a, timing);
            driver.run_read(test_addr, buff_b, timing);
            if (buff_a != buff_b) 
                $display("Memory correctness unit test failed, real: %b expected: %b", buff_b, buff_a);
        end

        $display("Finish memory testing");
        $finish;
    end
endmodule
