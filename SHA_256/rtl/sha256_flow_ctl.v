module sha256_flow_ctl (
    cfg_blk_sof,
    axi_bulk_end,

    ibuf_empty,
    ibuf_pop,
    ibuf_rdata,

    //sha256 core 的控制 并将数据传输进去
    bulk_fir_ini,
    bulk_nxt_ini,
    msg_data,
    msg_vld,
    msg_dcnt,

    sha_blk_end,

    clk,
    rstn
);

input wire clk, rstn;
input wire cfg_blk_sof;
input wire axi_bulk_end; //high level active axi读取的数据结束

input wire ibuf_empty;
input wire [31:0] ibuf_rdata; //从ibuf_fifo 读出来的 
output wire ibuf_pop;         //ibuf 输出数据到sha core

output wire bulk_fir_ini;  //1T pulse 开始第一个 512bit block 
output wire bulk_nxt_ini;  //1T pulse 开始第二到n个 512bit block 

output wire msg_vld; //告诉 sha core 可以读数据
output wire [31:0] msg_data; // 告诉sha core 这个数据是什么
output reg [3:0] msg_dcnt; //0-15

input wire sha_blk_end ; // 1T pulse 表示512 bit 结束

reg sta;
reg fir_blk;

parameter s_msg ='d0 , s_cal = 'd1;

always @ (posedge clk or negedge rstn)
    if (!rstn)
        sta <= s_msg ;
    else begin
        case (sta)
        s_msg : begin     //数据从ibuf 传到sha-core
            if (msg_vld && msg_dcnt == 'd15)
                sta <= s_cal;
        end

        s_cal : begin    //等到这个512 bit 计算完 回到s_msg 准备处理下一个块
            if (sha_blk_end)
                sta <= s_msg;
        end
        endcase
    end

assign ibuf_pop =  (~ibuf_empty) & (sta == s_msg); //不为空 且在传数据给core 的阶段
assign msg_vld  = ibuf_pop;  
assign msg_data = ibuf_rdata;
assign bulk_fir_ini = msg_vld & fir_blk; //用来通知core 初始化哈希常数
assign bulk_nxt_ini = msg_vld & (~fir_blk) & (msg_dcnt == 'd0);//用来通知core 用上一次的结果作为基础继续运算

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        msg_dcnt <= 0;
    else if (cfg_blk_sof)
        msg_dcnt <= 0;
    else if (msg_vld)
        msg_dcnt <= msg_dcnt +1;
end
 
always @(posedge clk or negedge rstn) begin
    if (!rstn)
        fir_blk <= 1;
    else if (cfg_blk_sof) //开始进行sha-256 运算
        fir_blk <=1;
    else if (msg_vld)
        fir_blk <=0;
end
endmodule