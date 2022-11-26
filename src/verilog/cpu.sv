`ifndef CPU_GUARD
`define CPU_GUARD
`include "clock.sv"

module cpu;

wire clk = 1'bz;
Clock cloker(clk);

initial begin
    $monitor("clk: %d", clk);
    #10;
    $finish;
end

endmodule
`endif 
