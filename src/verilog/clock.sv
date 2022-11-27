`ifndef CLOCK_GUARD
`define CLOCK_GUARD

module Clock(output logic clk);

always #1 clk = ~clk;

initial begin
    clk <= 0;
end

endmodule 

`endif 
