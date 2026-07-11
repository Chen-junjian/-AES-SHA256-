module aes_axiw (
    //cfg 要将obuf 里的数据读出来 再写进cfg_code_base的地址上
    cfg_blk_sof,
    cfg_code_base,
    
    // obuf state
    obuf_rd,
    obuf_raddr,
    obuf_rdata,
    obuf_rptr,
    obuf_empty,

    //axi master inf
    awid,
    awaddr,
    awlen,
    awsize,
    awburst,
    awlock,
    awprot,
    awcache,
    awvalid,
    awready,

    wid,
    wdata,
    wstrb,
    wlast,
    wvalid,
    wready,

    bid,
    bresp,
    bvalid,
    bready,

    clk,
    rstn
);

    input wire clk, rstn;
    input wire cfg_blk_sof; 
    input wire [31:0] cfg_code_base; //cfg_code_base 是一个地址 代表了要写入的地址的起始位置

    output wire obuf_rd;  //要读obuf  
    output wire [1:0] obuf_raddr; 
    output wire [2:0] obuf_rptr; 
    input wire [127:0] obuf_rdata; //得到obuf 里面的数据
    input wire obuf_empty;

    //axi master inf 写地址通道
    output wire [3:0] awid;
    output wire [31:0] awaddr;
    output wire [3:0] awlen;
    output wire [2:0] awsize;
    output wire [1:0] awburst;
    output wire [1:0] awlock;
    output wire [3:0] awcache;
    output wire [2:0] awprot;
    output wire awvalid;
    input wire  awready;

    //写数据通道
    output wire [3:0] wid;
    output reg [31:0] wdata;
    output wire [3:0] wstrb;
    output wire wlast;
    output wire wvalid;
    input wire wready;

    //写响应通道
    input wire [3:0] bid;
    input wire [1:0] bresp;
    input wire bvalid;
    output wire bready;

    // axi write fsm
    reg [1:0] axi_sta;
    parameter [1:0] axi_idle = 'd0, axi_cmd ='d1, axi_wd = 'd2;

    reg [4:0] rd_dcnt;
    reg [31:0] axi_addr;
    wire axi_d_send;
    wire axi_dend; //data write end of a 4 beat burst
    wire [127:0] obuf_rdata_reverse; //change to litter endian

    assign awvalid = (axi_sta == axi_cmd)? 1'b1 : 1'b0;
    assign wvalid  = (axi_sta == axi_wd)? 1'd1 : 1'd0;
    assign axi_d_send = wvalid & wready; //写一次 32bit 要写4次才完成一个blk 128 bit //写32bit 成功的握手
    assign axi_dend = wvalid & wready & wlast; //一个blk 128bit 写入总线的结束

    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            axi_sta <= axi_idle;
        else begin
            case(axi_sta)
            axi_idle: 
                if (!obuf_empty) //obuf 有数据了 说明一个blk 已经完成 可以让axi进行读操作了
                    axi_sta <= axi_cmd;

            axi_cmd: //地址握手
                if (awvalid && awready) // axi可以进行写入了 
                    axi_sta <= axi_wd;

            axi_wd://会持续4个周期，等待128bit写入，再回到idle 进行判断是否还需要写入
                if (axi_dend)  //查看是不是已经写完了
                    axi_sta <= axi_idle;
                else 
                    axi_sta <= axi_wd;

            default: axi_sta <= axi_idle;
            endcase 
        end
    end

    always @(posedge clk ) begin
        if (cfg_blk_sof)
            axi_addr <= {cfg_code_base[31:4],4'h0};
        else if (awvalid && awready) //每写一次 地址加16 B 128 bits 地址握手一次 增加16
            axi_addr <= axi_addr +'d16;
    end

    always @ (posedge clk or negedge rstn) begin
        if (!rstn)
            rd_dcnt <=0;
        else if (cfg_blk_sof)
            rd_dcnt <=0;
        else if (axi_d_send)
            rd_dcnt <= rd_dcnt +1;
    end

    assign awid =0;
    assign awaddr = axi_addr;
    assign awlen = 4'h3;
    assign awsize = 3'h2;
    assign awburst = 2'b01;
    assign awlock = 2'b00;
    assign awcache = 4'b0011;
    assign awprot = 3'b000;

    assign wid =0;
    assign wstrb = 4'hf;
    assign wlast = (rd_dcnt [1:0] =='d3)? 1:0;

    generate
        genvar i;
        for(i =0; i<= 15; i=i+1) begin : gen_endian //按字节读 且做endian
            assign obuf_rdata_reverse [(i*8) +: 8] = obuf_rdata [((15-i)*8) +: 8];
        end
    endgenerate

    always @(*) begin // 写进axi 
        case(rd_dcnt[1:0]) 
        'd0: wdata = obuf_rdata_reverse [0*32 +: 32];
        'd1: wdata = obuf_rdata_reverse [1*32 +: 32];
        'd2: wdata = obuf_rdata_reverse [2*32 +: 32];
        'd3: wdata = obuf_rdata_reverse [3*32 +: 32];
        endcase
    end

    assign bready = 1;

    assign obuf_raddr = rd_dcnt[3:2];// 读obuf 的地址
    assign obuf_rptr  = rd_dcnt[4:2];// obuf 的读指针
    assign obuf_rd    = axi_dend;

endmodule

