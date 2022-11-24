parameter BITS_IN_BYTE = 8;

parameter data_block_size = 16;
parameter data_bus_size = 2;   
parameter addr_bus_size = 2;    
parameter _SEED = 225526;

logic clk = 0;
task automatic tick(int times = 1);
    while (times > 0) begin
        clk <= ~clk;
        #1;
        times -= 1;
    end
endtask


typedef enum logic[1:0] {
   C2_NOP=2'b00,
   C2_RESPONSE=2'b01,
   C2_READ_LINE=2'b10,
   C2_WRITE_LINE=2'b11
} command_codes;

module memory
    #(
        parameter mem_amount = 512 * 1024 // 512 Kbyte
    )
    (
        input wire clk, reset, m_dump,
        input wire[addr_bus_size*BITS_IN_BYTE-1:0] addr,
        inout wire[data_bus_size*BITS_IN_BYTE-1:0] data_w,
        inout wire[1:0] cmd_w
    );

    logic[BITS_IN_BYTE-1:0] heap[0:mem_amount-1];
    integer SEED = _SEED;
    integer i = 0;

    bit owner = 0;
    logic[1:0] cmd;
    logic[data_bus_size*BITS_IN_BYTE-1:0] data;

    assign cmd_w = owner ? cmd : 2'bzz;
    assign data_w = owner ? data : {data_bus_size*BITS_IN_BYTE{1'bz}};

    always @(posedge reset) begin
        if (reset) begin
            for (i = 0; i < mem_amount; i += 1) begin
                heap[i] <= $random(SEED)>>16;  
            end
        end
    end

    always @(posedge m_dump) begin
        $display("---Begin Memory dump---");
        for (i = 0; i < mem_amount; i += 1) begin
            $display("[%d] %d", i, heap[i]);  
        end
        $display("---End Memory dump---");
    end


    integer it, byte_in_bus;

    always @(negedge clk) begin
        if (cmd_w == C2_WRITE_LINE) begin
            for (it = addr * data_block_size; it < addr * data_block_size + data_block_size; it += data_bus_size) begin
                for (byte_in_bus = 0; byte_in_bus < data_bus_size; byte_in_bus += 1) begin
                    heap[it + byte_in_bus] <= data_w[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE];
                end
                @(negedge clk);
            end
        end
    end

    always @(negedge clk) begin
        if (cmd_w == C2_READ_LINE) begin
            cmd <= C2_RESPONSE;
            owner <= 1;
            for (it = addr * data_block_size; it < addr * data_block_size + data_block_size; it += data_bus_size) begin
                @(negedge clk);
                for (byte_in_bus = 0; byte_in_bus < data_bus_size; byte_in_bus += 1) begin
                    data[byte_in_bus * BITS_IN_BYTE +: BITS_IN_BYTE] <= heap[it + byte_in_bus];
                end
            end
            @(negedge clk);
            owner <= 0;
        end
    end

endmodule

module mem_testbanch;

    logic reset = 0, m_dump = 0;
    wire[addr_bus_size*BITS_IN_BYTE-1:0] addr_w;
    wire[data_bus_size*BITS_IN_BYTE-1:0] data_w;
    wire[1:0] cmd_w;
    logic[1:0] cmd = C2_NOP;
    logic[addr_bus_size*BITS_IN_BYTE-1:0] addr;
    logic[data_bus_size*BITS_IN_BYTE-1:0] data;
    bit owner = 1;

    memory #(64) mem (clk, reset, m_dump, addr_w, data_w, cmd_w);

    assign addr_w = addr;
    assign data_w = owner ? data : {data_bus_size*BITS_IN_BYTE{1'bz}};
    assign cmd_w = owner ? cmd : 2'bzz;

    integer it;

    task run_read(input int addr_, output logic[data_block_size*BITS_IN_BYTE:0] data_);
        @(posedge clk);
        owner <= 1;
        cmd <= C2_READ_LINE;
        addr <= addr_;
        @(posedge clk);
        owner <= 0;
        wait(cmd_w == C2_RESPONSE);
        for (it = 0; it < data_block_size; it += data_bus_size) begin
            @(posedge clk);
            data_[it * BITS_IN_BYTE +: data_bus_size * BITS_IN_BYTE] <= data_w;
        end
        @(posedge clk);
        owner <= 1;
        cmd <= C2_NOP;
        $display("READ FINISHED");
    endtask

    task run_write(input int addr_, input logic[data_block_size*BITS_IN_BYTE:0] data_);
        @(negedge clk);
        owner <= 1;
        cmd <= C2_WRITE_LINE;
        addr <= addr_;
        for (it = 0; it <= data_block_size / data_bus_size; it += 1) begin
            @(posedge clk);
            data <= data_[it * data_bus_size * BITS_IN_BYTE +: data_bus_size * BITS_IN_BYTE];
        end
        owner <= 1;
        cmd <= C2_NOP;
        $display("WRITE FINISHED");
    endtask

    logic[0 :+ data_block_size * BITS_IN_BYTE] buff;

    initial begin
    fork 
        forever tick();
    begin
        $display("Start memory testing");
        reset <= 1;
        tick();
        reset <= 0;
        tick();
        run_write(0, 1 << 16 + 1 << 8);
        tick();
        run_read(0, buff);
        tick();
        run_write(3, buff);
        tick();
        m_dump <= 1;
        tick();
        m_dump <= 0;
        $display("Finish memory testing");
        $finish;
    end
    join
    end
endmodule
