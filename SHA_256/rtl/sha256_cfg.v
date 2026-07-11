module sha256_cfg (
        //他是作为apb-slave连接的一组寄存器  用于存放总线给的配置信息 和sha256计算得到的结果
        psel,
        penable,
        paddr,
        pwrite,
        pwdata,
        pready,
        prdata,

        // 它内部的寄存器  16*32bit
        cfg_blk_sof,   //SW写入1 时 代表 开启处理 当计算开始时 改回0
        cfg_blk_base,  //sha256开始读取数据的起始地址 byte为单位 且32bit 对齐 【1：0】==2‘b00
        cfg_blk_len,   //sha256 处理数据块的大小 单位为byte 必须是64byte 的整数倍 （64 处理1block 128 处理2block）

        axi_bulk_end,
        h0,
        h1,
        h2,
        h3,
        h4,
        h5,
        h6,
        h7,

        intr,       //sha256 core 告诉cpu 已经彻底结束对cfg_blk_len的处理  
        clk,
        rstn
);
input wire rstn,clk;

// APB configure inf
input wire psel;
input wire penable;
input wire pwrite;
input wire [7:0] paddr; //byte addr
input wire [31:0] pwdata;
output reg [31:0] prdata;
output wire pready;

output reg cfg_blk_sof ; //1 T pulse : start
output reg [31:0] cfg_blk_base; 
output reg [31:0] cfg_blk_len;

input wire axi_bulk_end; // 高有效 表示sha256 完成计算 from （cfg_blk_len）

input wire [31:0] h0,h1,h2,h3,h4,h5,h6,h7;
output reg intr ; 

//apb inf

wire apb_write ;
wire apb_read;
wire [3:0]apb_addr; //有16个 寄存器
wire clr_intr;
wire set_bulk_end;
reg axi_bulk_end_d;

assign apb_write = psel && penable && pwrite;
assign apb_read  = psel  && (!pwrite); //可以不需要penable 因为不涉及改变数据 时序要求相对宽松
assign apb_addr  = paddr [2 +:4];  //因为是 32 bit的寄存器 每次覆盖4 byte字节地址
assign pready = 1; //一直可以接收 来自bus的读写信号
assign clr_intr = apb_write && penable && (apb_addr == 'd3) && (!pwdata[0]); //bus 发出写操作 且写的地址是0011 写入0 表示结束数据块处理 把intr变为1
//其实在bus读走数据后 就会发起clr—intr 发起后对应寄存器的incr为0

assign set_bulk_end = (~axi_bulk_end_d) && axi_bulk_end;  //axi 完成计算 1 T pluse


always @(posedge clk or negedge rstn)
    if (!rstn) 
        cfg_blk_sof  <= 0;
    else if (apb_write && (apb_addr == 'd0)&& pwdata[0])  //sw写1 表示开始
        cfg_blk_sof  <= 1;
    else 
        cfg_blk_sof  <= 0;

always @(posedge clk  or negedge rstn) begin
    if (!rstn) begin
        cfg_blk_base <=0;
        cfg_blk_len <=0;
    end
    else if (apb_write)begin 
        if(apb_addr == 'd1)
            cfg_blk_base <= pwdata;
        if (apb_addr == 'd2)
            cfg_blk_len <= pwdata;
end
end

always @(posedge clk  or negedge rstn) begin
    if (!rstn)
        axi_bulk_end_d <=1;
    else
        axi_bulk_end_d <= axi_bulk_end; //axi完成之后 会把结果输出到这个模块
end

always @(posedge clk  or negedge rstn) begin
    if (!rstn)
        intr <= 0;
    else if (set_bulk_end)
        intr <= 1;
    else if (clr_intr) //清除这个完成信号 
        intr <=0;
end

//apb read 
always @(posedge clk or negedge rstn) begin
    if (!rstn)
    prdata <= 0;
    else if (apb_read) begin
        case (apb_addr) 
        'd0: prdata <= 'd0;
        'd1: prdata <= cfg_blk_base;
        'd2: prdata <= cfg_blk_len;
        'd3: prdata <= {31'h0,intr};
        'd4: prdata <= 'd0;
        'd5: prdata <= 'd0;
        'd6: prdata <= 'd0;
        'd7: prdata <= 'd0;
        'd8: prdata <= h0;
        'd9: prdata <= h1;
        'd10: prdata <= h2;
        'd11: prdata <= h3;
        'd12: prdata <= h4;
        'd13: prdata <= h5;
        'd14: prdata <= h6;
        'd15: prdata <= h7;

        default : prdata <= 0;
        endcase

    end
end

endmodule