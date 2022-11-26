`ifndef PARAMETERS_GUARD
`define PARAMETERS_GUARD
parameter BITS_IN_BYTE = 8;
parameter INF = 1000000000;

parameter cache_line_size = 16;

parameter addr1_bus_size = 2; 
parameter data1_bus_size = 2;   

parameter data2_bus_size = 2;  
parameter addr2_bus_size = 2; 

parameter _SEED = 225526;

typedef enum logic[1:0] {
   C2_NOP=2'b00,
   C2_RESPONSE=2'b01,
   C2_READ_LINE=2'b10,
   C2_WRITE_LINE=2'b11
} mem_command_codes;

typedef enum logic[2:0] {
    C1_NOP=3'b000,
    C1_READ8=3'b001,
    C1_READ16=3'b010,
    C1_READ32=3'b011,
    C1_INVALIDATE_LINE=3'b100,
    C1_WRITE8=3'b101,
    C1_WRITE16=3'b110,
    C1_WRITE32=3'b111
} cpu_cache_command_codes;

typedef enum logic[2:0] {
    C1_RESPONSE=3'b111
} cache_cpu_command_codes;
`endif
