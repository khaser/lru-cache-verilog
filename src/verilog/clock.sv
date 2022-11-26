`ifndef CLOCK_GUARD
`define CLOCK_GUARD

module Clock(output logic clk);
initial begin
    clk <= 0;
    forever begin
        #1;
        clk <= ~clk;
    end
end
endmodule 

`endif 
