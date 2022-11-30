`ifndef CLOCK_GUARD
`define CLOCK_GUARD

module Clock(output logic clk, output longint timing);

always #1 clk = ~clk;

always #2 timing++;

initial begin
    timing = 0;
    clk = 0;
end

endmodule 

`endif 
