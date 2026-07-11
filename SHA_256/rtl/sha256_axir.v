module sha256_axir (
    //从cfg 传来的数据
    cfg_blk_base, //起始地址
    cfg_blk_len,  // 长度
    cfg_blk_sof,   //启动sha程序

    //ibuf 状态
    ibuf_we,
    ibuf_waddr,
    ibuf_wdata,
    sha_blk_end,
    axi_bulk_end,

    //axi 读地址通道
    arid,
    araddr,
    arburst,
    arcache,
    arlen,
    arsize,
    arprot,
    arready,
    arvalid,
    arlock,

    //axi 读数据通道
    rid,
    rdata,
    rready,
    rlast,
    rvalid,
    rresp,

    clk,
    rstn
);
input wire clk,rstn;

input wire [31:0] cfg_blk_base; //这次 计算的起始地址
input wire [31:0] cfg_blk_len;  //这次计算的总beat 数 必须为64的整数倍 因为一个数据块为512bit
input wire  cfg_blk_sof;  //在32位寄存器里 只取最低位 1 T Pulse 

output wire ibuf_we; //给ibuf 开始存数值的指示
output wire [31:0] ibuf_wdata; //little endian 32 bit 存进内存时 MSB 存进较高地址 
output reg [3:0] ibuf_waddr; //ibuf 深度为16 正好可以存512 bit 数据

input wire  sha_blk_end;  // 1T pusle 表示 sha 模块 完成了一个 512 bit 的block 的计算 ，
output wire axi_bulk_end; // 1T pulse 表示全部数据已经读了 并交给sha core 计算了 

output  wire  [3:0]   arid      ;  //0
output  wire  [31:0]  araddr    ; //告诉bus 我要读哪里的数据
output  wire  [3:0]   arlen     ; //一个burst 的长度 beat 数 
output  wire  [2:0]   arsize    ; //告诉大小
output  wire  [1:0]   arburst   ; // burst的类型
output  wire  [1:0]   arlock    ; // 锁类型
output  wire  [3:0]   arcache   ; //缓存类型 
output  wire  [2:0]   arprot    ; //保护类型
output  wire          arvalid   ; //读地址有效信号
input   wire          arready   ; //读地址 准备信号 由从设备发出 表示可以接收读地址

input   wire  [3:0]   rid       ; //与上方id 对应
input   wire  [31:0]  rdata     ; //bus在对应的地址 返回数据给 axi
input   wire  [1:0]   rresp     ; //读相应 ok/exok/slverr/decerr
input   wire          rlast     ; //表示burst 的最后一个数据
input   wire          rvalid    ; //表示数据有效
output  wire          rready    ; //master 发出 表示准备好接收读到的数据

//  1. bulk data fetch change to AXI burst transfer

reg [1:0] sta ;
parameter  [1:0]  s_idle = 0, s_judge = 1, s_cmd0 = 2, s_cmd1 =3; //判断有没有超过 4KB 边界 如果有 要分成2次 burst
                                                                  //一次judge 最多只能做一次block 512bit

wire           axi_cmd_ack;   //表示axi 可以进行读
reg     [31:0] axi_addr;
reg     [31:0] blk_len;
wire    [32:0] nxt_blk_len ;
reg     [1:0]  blk_osd_cmd;  //axi burst outstanding cmd num
wire           axi_bt_go;     //start to read a 16*32 bit blk

//进行4kb边界判断
wire    [12:0]  addr_add_low ;  //有可能已经跨了4kb boundary 所以一共13bit
wire            cross_4kb_w ;
wire    [3:0]   cmd0_len_w; //一次burst 最多16拍 可传递64byte 512bit
wire    [3:0]   cmd1_len_w;
reg     [3:0]   cmd0_len;
reg     [3:0]   cmd1_len;      //cnt from 
reg     [19:0]  cmd1_addr_h;   //must begin from 4kb boundary  //低12未地址 全部未为0 是4kb boundary的对齐点
reg             cross_4kb;
wire    [3:0]   cur_len;        //cnt from 0

assign axi_bt_go = (sta == s_judge) && (!blk_osd_cmd[1]); // 发burst  条件 在准备状态 且 outstanding 只能是 0 /1 可以发起burst
assign addr_add_low = {axi_addr[11:2],2'h0} + 'd63 ;  //在 4KB 边界里 先把addr 做4byte 对齐， 再加64byte （512bit） 看看最后的地址有没有超过边界
assign cross_4kb_w = addr_add_low[12]; //看看有没有到达4 kb 边界
                                       //注意 len 数等于 拍数-1 。eg len ==0 则有1拍
assign cmd1_len_w = addr_add_low[5:2]; // 如果超过了4kb 边界 就要把一次burst 分成两次burst 看看在新的burst 要多少拍 4byte （0~16）
                                       // 因为新的boundary 一定是从0000开始 且最多16 拍 每排 4byte 所以看【5：2】就知道有多少拍 
assign cmd0_len_w = (cross_4kb_w)?  (5'd16 -'d1 - {1'd0,cmd1_len_w} -'d1 )  : 'd15 ;// 看没超边界的burst 有多少拍
assign cur_len  = (sta == s_cmd0)? cmd0_len : cmd1_len;  //当前的len 是多少

assign axi_cmd_ack  =  arready && arvalid; // 1 T pulse 主设备把地址准备好 从设备也准备好接收地址 开始读bus的标志
assign nxt_blk_len = {1'd0,blk_len} - {1'b0,cur_len,2'h0} - 'd4; //剩余字节数 当最高位为1时 是表示所有的数据已经发送完毕 状态机回到idle
assign axi_bulk_end = (sta == s_idle) && (blk_osd_cmd == 0); //全部数据都搬运完毕了 可能不止512 bit

always @(posedge clk or negedge rstn ) begin
    if (!rstn)
        sta <= s_idle;
    else  begin
        case (sta)
        s_idle: begin
            if (cfg_blk_sof)
                sta <=s_judge;
        end
        s_judge : begin  //一次进入judge 只有16 beat 如果数据是32beat的 就要进入两次judge
            if (!blk_osd_cmd[1]) //outstanding 不大于1 进行第一个边界条件下的读
                sta <= s_cmd0;
        end
        s_cmd0 : begin
            if (axi_cmd_ack) begin //可以进行读的标志
                if (nxt_blk_len[32]) // 表示 cfg_blk_len 全部读完 回到idle
                    sta <= s_idle;
                else if (cross_4kb)  //表示超过了边界 要进行下一次burst
                    sta <= s_cmd1;
                else 
                    sta <= s_judge; //表示 cfg_blk_len 还没读完 （可能是128byte） 回到judge 看outstand 满没有
            end
        end  
        s_cmd1 : begin
            if (axi_cmd_ack) begin
                if (nxt_blk_len [32])// 表示 cfg_blk_len 全部读完 回到idle
                    sta <= s_idle;
                else
                    sta <= s_judge;
            end
        end   
        default : sta <= s_idle;
        endcase
    end
end

always @(posedge clk ) begin
    if ((sta == s_idle) && cfg_blk_sof) begin //接收最初始地址
        blk_len <= cfg_blk_len;  //长度是 （64 beat）整数倍
        axi_addr <= {cfg_blk_base[31:2],2'h0};
    end else if (axi_cmd_ack) begin //发生了传播之后 才会有新的地址
        axi_addr <= {axi_addr[31:2],2'h0} + {cur_len,2'h0} + 'd4;
        blk_len <= nxt_blk_len;//如果64byte 则为-1 如果128byte 或者 超4kb 则为剩下的byte
    end
end

always @(posedge clk ) begin  //这三个信号要寄存的 当在judge阶段之后就不会改变 
    if ((sta == s_judge) && (!blk_osd_cmd[1]))begin
        cmd0_len <= cmd0_len_w;
        cmd1_len <= cmd1_len_w;
        cross_4kb <= cross_4kb_w;
    end
end

assign arid = 0;
assign araddr = axi_addr;
assign arlen = cur_len;
assign arsize = 3'h2;
assign arburst = 2'b01;
assign arlock = 2'b00;
assign arcache = 4'b0011;
assign arprot = 3'b000;
assign arvalid = (sta == s_cmd0) || (sta == s_cmd1) ;

assign rready =1;

always @ (posedge clk or negedge rstn) // blk_osd_cmd  表示正在进行的事务数量 不可以超过1 
if (!rstn)
    blk_osd_cmd <= 0;
else if (cfg_blk_sof) //有一个 block 过来 可能64 byte 可能 128byte 。。。
    blk_osd_cmd <= 0;
else if ((axi_bt_go) || sha_blk_end)
    blk_osd_cmd <= blk_osd_cmd + {1'b0,axi_bt_go} - {sha_blk_end};

// write AXI DATA to ibuf

assign ibuf_we = rvalid && rready;
assign ibuf_wdata = {rdata [0*8 +:8],rdata [1*8 +:8],rdata [2*8 +:8],rdata [3*8 +:8]};//32bit low endian to high endian

always @(posedge clk or negedge rstn)
    if (!rstn)
        ibuf_waddr <= 0;
    else if (cfg_blk_sof) //一次新的 运算 ibuf 会重新读入数据
        ibuf_waddr <= 'd0;
    else if (ibuf_we) //读到一个数据 ibuf内部地址加1 
        ibuf_waddr <= ibuf_waddr +1'd1;

endmodule