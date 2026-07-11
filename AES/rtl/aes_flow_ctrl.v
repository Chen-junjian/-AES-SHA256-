
`timescale 1ns / 10ps
module aes_flow_ctrl (
    //控制ibuf 的read 以及 obuf 的 write
    cfg_blk_sof,
    cfg_blk_len,
    set_blk_end, //告诉cfg blk 做完了 发中断

    //ibuf state
    ibuf_wptr, 
    ibuf_rptr,
    ibuf_rd,
    ibuf_raddr,
    ibuf_rdata,

    //obuf state
    obuf_rptr,
    obuf_empty,  //没有空 才可以输出
    obuf_we,
    obuf_waddr,
    obuf_wdata,

    //encipher strl
    key_ready,
    enc_sof,
    enc_text,
    enc_ready,
    enc_code,
    first_blk,
    blk_end,

    clk,
    rstn
);

    input wire clk, rstn;
    input wire [31:0] cfg_blk_len;
    input wire  cfg_blk_sof;
    output wire set_blk_end; // 1T pulse the process of a blk data (cfg_blk_len +1 byte) has been ended

    input wire [2:0] ibuf_wptr; //外面写进来的数据的指针
    output reg [2:0] ibuf_rptr; //读到AES core 的指针
    output wire ibuf_rd;
    output wire [1:0] ibuf_raddr;
    input wire [127:0] ibuf_rdata; //combination output, align with ibuf_rd/raddr //向ibuf 读到的数据

    input wire [2:0] obuf_rptr; //output buffer read pointer 
    output wire obuf_empty;
    output wire obuf_we;
    output wire [1:0] obuf_waddr; //从0开始 循环写入
    output wire [127:0] obuf_wdata; //从AES core 读到的数据 写入obuf

// 需要等轮密钥扩展完成了才能开始加密
    input wire key_ready; //high level indicate that key expansion ended
    output wire enc_sof ; //1T high pulse start the encrypt/ decrypt of a 4*32bit block //给 core

    // 把ibuf 里面的数据读出来 送到 core 进行加密 
    output wire [127:0] enc_text;//encrypt：明文

    //读AES core 的输出 （密文） 以及加密完成的信号，发送给obuf
    input wire enc_ready;
    input wire [127:0] enc_code; //decrypt：密文 //加密结束后把密文写入obuf

    output reg first_blk;//1:first 128bit of a bulk data
    output wire blk_end; //1T pulse:encrypt of a 128bit blk ended

     //1. encrypt ctrl 
     reg [1:0] sta ;
     parameter [1:0] s_idle = 'd0, s_start = 'd1, s_enc_end = 'd2, s_w_end = 'd3;

     reg [27:0] bulk_len ; //cfg_blk_len is N*16 byte
     wire ibuf_empty;
     wire obuf_full;
     wire enc_blk_end; //1T high Pulse process a 128bit blk ended 

     assign enc_blk_end = (sta == s_enc_end) && enc_ready; //完成一个128bit 加密 拉高
     assign blk_end = enc_blk_end;
     assign ibuf_raddr = ibuf_rptr[1:0];
     assign ibuf_empty = (ibuf_rptr == ibuf_wptr)? 1:0;
     assign ibuf_rd = enc_blk_end; // read at end enc, easy the ctrl for CFB/OFB mode //一块做完加密之后 再到指向下一块
     assign enc_text = ibuf_rdata; //从ibuf中读到明文
     assign enc_sof = (sta == s_start) & key_ready & (!obuf_full) &(!ibuf_empty);
     assign set_blk_end = (sta==s_w_end) & obuf_empty; // 全部block 做完了 obuf读空了 可以发中断了

     always @(posedge clk or negedge rstn) begin
        if (!rstn)
            sta <= s_idle;
        else begin
            case (sta)
            s_idle: if (cfg_blk_sof) 
                sta <= #1 s_start;
            
            // start encrypt of a 4*32 bit blk
            s_start: if (key_ready && (!obuf_full)&& (!ibuf_empty))
                sta <= #1 s_enc_end;

            //wait encrypt end
            s_enc_end: begin
                if (enc_ready) //这个128 bit的block 做完
                    if (bulk_len==0) //已经做完 加密
                        sta <= #1 s_w_end;
                    else 
                        sta <= #1 s_start; 
            end

            //wait dma write out end
            s_w_end: //要把整个obuf 都输出出去了 再发中断 回到idle
                if (obuf_empty)
                    sta <= #1 s_idle;
            endcase
        end
     end

    //ibuf 被读了 代表准备开始进行 encryption 
     always @(posedge clk or negedge rstn) begin
        if (!rstn)
            ibuf_rptr <=0;
        else if (cfg_blk_sof &&(sta == s_idle))
            ibuf_rptr <=0;
        else if (ibuf_rd)
            ibuf_rptr <= ibuf_rptr +1;
     end

    always @(posedge clk)
        if (cfg_blk_sof &&(sta == s_idle)) //bulk-len 是128 bit 对齐的 
            bulk_len <= cfg_blk_len[31:4]; //单位是16 byte 的block
        else if (ibuf_rd) //每次read 是128 bit 
            bulk_len <= bulk_len -1;

    always @(posedge clk ) begin
        if (cfg_blk_sof && (sta == s_idle))
            first_blk <= 1;
        else if (enc_blk_end)
            first_blk <= 0;
    end

    //write encrypt code to output buffer 在这里判断obuf 是否空满 

    reg [2:0] obuf_wptr;

    assign obuf_full = (obuf_wptr[2] != obuf_rptr[2]) && (obuf_wptr[1:0] == obuf_rptr[1:0]);
    assign obuf_empty = (obuf_wptr == obuf_rptr)? 1:0;
    assign obuf_we = enc_blk_end; //一个blk 加密结束了 可以写入obuf
    assign obuf_wdata = enc_code;
    assign obuf_waddr = obuf_wptr[1:0];


// 当 AES core 加密完成一个128 bit的blk 就把obuf_wptr 加1 指向下一个地址 写入下一个blk 的密文
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            obuf_wptr <= 0;
        else if (cfg_blk_sof && (sta == s_idle))
            obuf_wptr <= 0;
        else if (enc_blk_end) //完成一个128 bit wptr 加1
            obuf_wptr <= obuf_wptr +1;
    end

endmodule

