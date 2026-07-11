module aes_axir (
    //把cfg 里地址的数据通过AXI 读出来 写进ibuf ， ibuf的数据被读出来 被core使用 
    cfg_blk_base,
    cfg_blk_len,
    cfg_blk_sof,

    ibuf_wptr,
    ibuf_rptr,
    ibuf_we,
    ibuf_wbe,
    ibuf_wdata,
    ibuf_waddr,

    arid,
    araddr,
    arlen,
    arsize,
    arburst,
    arlock,
    arcache,
    arprot,
    arvalid,
    arready,

    rid,
    rdata,
    rresp,
    rlast,
    rready,
    rvalid,

    clk,
    rstn
);

    input  wire                         clk ,rstn                  ;
    input  wire                         cfg_blk_sof                ;
    input  wire        [  31:0]         cfg_blk_len                ;//must n*16byte cnt from 0
    input  wire        [  31:0]         cfg_blk_base               ;
    input  wire        [   2:0]         ibuf_rptr                  ; //ibuf 的 读指针是flow ctrl 输入来的 

    output wire        [   2:0]         ibuf_wptr                  ; //告诉flow ctrl 写指针 让它知道什么时候ibuf 满了
    output wire                         ibuf_we                    ;
    output reg         [   3:0]         ibuf_wbe                   ;
    output wire        [ 127:0]         ibuf_wdata                 ;
    output wire        [   1:0]         ibuf_waddr                 ;

    //读地址通道 输出到总线 请求读
    output wire        [   3:0]         arid                       ;
    output wire        [  31:0]         araddr                     ;
    output wire        [   3:0]         arlen                      ;
    output wire        [   2:0]         arsize                     ;
    output wire        [   1:0]         arlock                     ;
    output wire        [   1:0]         arburst                    ;
    output wire        [   3:0]         arcache                    ;
    output wire        [   2:0]         arprot                     ;
    output wire                         arvalid                    ;
    input  wire                         arready                    ;

    //读数据通道 //总线上读到的数据 输入进来存到ibuf 里
    input  wire        [   3:0]         rid                        ;
    input  wire        [  31:0]         rdata                      ;
    input  wire        [   1:0]         rresp                      ;
    input  wire                         rlast                      ;
    input  wire                         rvalid                     ;//向总线发起读 但不知道什么时候可以读到 ，只有读到了才准备写入ibuf
    output wire                         rready                     ;

// dma req change to AXI burst transfer

reg                                     axi_sta                    ;
parameter                           axi_idle = 0, axi_cmd = 1  ;

wire                                    axi_cmd_ack                ;
reg                    [  31:0]         axi_addr                   ;
reg                    [   2:0]         ibuf_wptr_cmd               ;//align with AXI read cmd phase 目前正在写的地址指针 用来和ibuf 的读指针对比 判断ibuf 是否满了
wire                                    ibuf_full_cmd               ;//ibuf full, align with AXI read cmd phase
reg                    [  31:0]         blk_len                    ;//trace the remain data len with this encipher operation
wire                   [  32:0]         nxt_blk_len                ;

//wptr_cmd 领先于 wptr ，wptr 要 读四个周期才会加1 
// 假设总线响应速度极快，且 arready 一直为 1，T1, T2, T3, T4：你连续发送了 4 个地址请求（axi_cmd_ack 连响 4 声），而数据返回可能要持续到 T25

    assign ibuf_full_cmd = (ibuf_wptr_cmd [2] != ibuf_rptr[2]) && (ibuf_wptr_cmd [1:0] == ibuf_rptr[1:0]);//ibuf 满了暂停写 注意这里是用wptr_cmd
    assign axi_cmd_ack  = arready && arvalid;
    assign nxt_blk_len  = {1'b0,blk_len} - 'd16;  //each burst read 16B //每次read burst 均为4 * 32bit

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            axi_sta <= axi_idle;
        else begin
            case (axi_sta)
            axi_idle : begin
                if (cfg_blk_sof)
                    axi_sta <= axi_cmd; 
            end

            axi_cmd : 
                if (axi_cmd_ack) //发出读命令了
                begin //进一次cmd 就读了16 byte
                if (nxt_blk_len[32])// 已经把len 都读完了 
                    axi_sta <= axi_idle;
                else
                    axi_sta <= axi_cmd; //还有剩下的block 没有读完
            end

            default : axi_sta <= axi_idle;
            endcase
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            ibuf_wptr_cmd <= 0;
        else if (cfg_blk_sof && (axi_sta == axi_idle))
            ibuf_wptr_cmd <= 0;
        else if (axi_cmd_ack)// 这个是可以发cmd 的前提
            ibuf_wptr_cmd <= ibuf_wptr_cmd +1'd1; //这个wptr 是指发一次就加一次
    end

    always @(posedge clk ) begin
        if (cfg_blk_sof && (axi_sta == axi_idle)) begin
            blk_len <= cfg_blk_len;
            axi_addr <= {cfg_blk_base[31:4],4'h0}; //16B 对齐
        end
        else if (axi_cmd_ack) begin
            blk_len <= nxt_blk_len;     //decrease afer  16B read
            axi_addr <= axi_addr +'d16; //increase after 16B read, never cross 4KB boundary
        end

    end

    assign arid = 0; //串行数据流 一直为同一个id即可
    assign araddr = axi_addr;
    assign arsize = 3'h2 ; // fix 32 bit 
    assign arlen  = 'd3; //fix 4 beat burst
    assign arburst = 2'b01;
    assign arlock = 'b00;
    assign arcache = 4'b0011;
    assign arprot  = 3'b000;
    assign arvalid = (axi_sta == axi_cmd) && (!ibuf_full_cmd); //maximal outstanding 4 *4*32bit  read cmd//不能接收了

    assign rready = 1;

    //writr AXI read data to ibuf
    reg [4:0] dcnt; //receive data cnt
    wire recv_data;

    assign recv_data = rvalid && rready;    //rvalid 表示读到数据 有数据来 每个32 bit 

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            dcnt <=0;
        else if ((axi_sta == axi_idle) && cfg_blk_sof)
            dcnt <=0;
        else if (recv_data)//每周期都会读到32bit 4个周期才会读到128bit
            dcnt <= dcnt +1;
    end

    assign ibuf_wptr = dcnt [4:2]; //每接收四个数据（读完了才加1） 就加1 注意这里是用dcnt 来算wptr， 因为dcnt 是每接收4个数据就加4 刚好对应ibuf 的一个地址
    assign ibuf_we   = recv_data;
    assign ibuf_waddr = dcnt [3:2]; //ibuf的深度是 4 
    assign ibuf_wdata = {4{rdata[7:0],rdata[15:8],rdata[23:16],rdata[31:24]}}; //change to big endian 算法规定 要做endian 转化

    always @(*) begin
        case (dcnt[1:0])        //change to big endian within 16B
        'd3: ibuf_wbe = 4'b0001; 
        'd2: ibuf_wbe = 4'b0010;
        'd1: ibuf_wbe = 4'b0100;
        'd0: ibuf_wbe = 4'b1000;
        endcase
    end

endmodule