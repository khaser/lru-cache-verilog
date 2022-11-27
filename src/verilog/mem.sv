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
`endif 
