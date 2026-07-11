module reg_file_wbe (
          clk       ,
          we        ,
          wbe       ,
          waddr     ,
          din       ,
          raddr     ,
          dout       
        );    

parameter ADDR_BITS = 2;
parameter ADDR_AMOUNT = 4;
parameter DATA_BITS = 128;
parameter WBE_BITS  = 4;
parameter WBE_MASK_DBITS = DATA_BITS / WBE_BITS; //每个wbe bit对应的数据位宽为32bits

input wire                      clk     ;
input wire                      we      ;
input wire  [WBE_BITS -1 : 0]   wbe     ;
input wire  [ADDR_BITS-1:0]     raddr, waddr;
input wire  [DATA_BITS-1:0]     din     ;
output reg  [DATA_BITS-1:0]     dout    ;

reg [DATA_BITS-1:0]mem[0 : ADDR_AMOUNT-1];

generate
genvar  i;
for(i=0; i<WBE_BITS; i=i+1) begin : gen_write
    always@(posedge clk)
    begin
        if(we && wbe[i])
       	    mem[waddr][i*WBE_MASK_DBITS +: WBE_MASK_DBITS] <= din[i*WBE_MASK_DBITS +: WBE_MASK_DBITS]; 
    end
end
endgenerate

always @(*) begin
    dout = mem[raddr];
end


endmodule

