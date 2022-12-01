`include "cpu.sv"
`include "clock.sv"

module Testbench;

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

    integer total_hits, total_misses;
    longint timing;
    logic clk, reset = 0, c_dump = 0, m_dump = 0;

    Clock cloker(clk, timing);
    Cpu cpu(clk, reset, c_dump, m_dump, total_hits, total_misses);

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
                pb = b_addr; skip(); // init pb
                s = 0; skip(); // init s
                skip(); // k init;
                for (k = 0; k < K; k++) begin skip(); // loop
                    // s += pa[k] * pb[x] begin
                    cpu.run_read(pa + k, C1_READ8, wbuff);
                    cpu.run_read(pb + x * 2, C1_READ16, dbuff);
                    qbuff = wbuff * dbuff; skip(5); // (*)
                    s = s + qbuff; skip(); // (+)
                    // s += pa[k] * pb[x] end
                    pb = pb + N * 2; skip(); // (+)
                end
                cpu.run_write(pc + x * 4, C1_WRITE32, s);
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
