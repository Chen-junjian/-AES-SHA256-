module sha256_loop(
//这个模块主要是接到开始的指令后，前16个周期接受固定的数据，后48个周期还有输出数据给下一次输入用

    clk,
    rstn,
    msg_vld,
    bulk_fir_ini,
    bulk_nxt_ini,
    h0,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    h7,
    loop_cnt,
    cal_en,
    sha_blk_end,
    k_lut,
    w
);

    input wire clk, rstn;
    input wire msg_vld;
    input wire bulk_fir_ini;
    input wire bulk_nxt_ini;
    output wire cal_en;
    output reg [31:0] h0,h1,h2,h3,h4,h5,h6,h7;
    output reg [5:0] loop_cnt;
    input wire [31:0] k_lut; //每轮的计算都不同
    input wire [31:0] w; //前16轮是block本身，后面有运算规则
    output wire sha_blk_end;

localparam SHA256_H0_0 = 32'h6a09e667;
localparam SHA256_H0_1 = 32'hbb67ae85;
localparam SHA256_H0_2 = 32'h3c6ef372;
localparam SHA256_H0_3 = 32'ha54ff53a;
localparam SHA256_H0_4 = 32'h510e527f;
localparam SHA256_H0_5 = 32'h9b05688c;
localparam SHA256_H0_6 = 32'h1f83d9ab;
localparam SHA256_H0_7 = 32'h5be0cd19;

reg [31:0] a,b,c,d,e,f,g,h;
reg cal_nxt_48;
reg [31:0] t1, t2;
wire load_blk_final;
reg [2:0] cal_en_d;

assign cal_en = cal_nxt_48 | msg_vld; 
assign load_blk_final = (!cal_en_d[0]) & cal_en_d [1]; //最后一个数据已经数据完毕，这个512bit 的block 结束
assign sha_blk_end =  load_blk_final;

// t1 cal:
always @(*) begin: t1cal
    reg [31:0] sum1;
    reg [31:0] ch;

    sum1 = {e [5:0],e[31:6]} ^
           {e [10:0],e[31:11]} ^
           {e [24:0],e[31:25]} ;
    
    ch = (e & f) ^ ((~e) & g);

    t1 = h + sum1 + ch + k_lut + w;

end

//t2 cal: 
always @(*) begin : t2cal
    reg [31:0] sum2;
    reg [31:0] maj;

    sum2 = {a [1:0],a[31:2]} ^
           {a [12:0],a[31:13]} ^
           {a [21:0],a[31:22]} ;

    maj = (a & b) ^ (a & c) ^ (c & b);

    t2 = sum2 + maj;
end


always @(posedge clk or negedge rstn) begin
    if (!rstn) 
        loop_cnt <=0;
    else if (bulk_fir_ini ||bulk_nxt_ini)
        loop_cnt <=1;
    else if (msg_vld || cal_nxt_48)
        loop_cnt <=loop_cnt +1 ;
end

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        cal_nxt_48 <=0;
    else if ((loop_cnt [3:0]== 'd15) && msg_vld)
        cal_nxt_48 <= 1;
    else if (loop_cnt == 'd63) 
        cal_nxt_48 <= 0;
end

always @(posedge clk or negedge rstn) begin
    if (!rstn)
        cal_en_d <= 3'b000;
    else 
        cal_en_d <= {cal_en_d[1:0],cal_en};
end

always @(posedge clk ) begin
    if (bulk_fir_ini) begin
        h0 <= SHA256_H0_0;
        h1 <= SHA256_H0_1;
        h2 <= SHA256_H0_2;
        h3 <= SHA256_H0_3;
        h4 <= SHA256_H0_4;
        h5 <= SHA256_H0_5;
        h6 <= SHA256_H0_6;
        h7 <= SHA256_H0_7;
    end
    else if (load_blk_final) begin
        h0 <= h0 +a;
        h1 <= h1 +b;
        h2 <= h2 +c;
        h3 <= h3 +d;
        h4 <= h4 +e;
        h5 <= h5 +f;
        h6 <= h6 +g;
        h7 <= h7 +h;
    end
end

always @(posedge clk ) begin
    if (bulk_fir_ini) begin
        a <= SHA256_H0_0;
        b <= SHA256_H0_1;
        c <= SHA256_H0_2;
        d <= SHA256_H0_3;
        e <= SHA256_H0_4;
        f <= SHA256_H0_5;
        g <= SHA256_H0_6;
        h <= SHA256_H0_7;
    end
    else if (bulk_nxt_ini) begin
        a <= h0;
        b <= h1;
        c <= h2;
        d <= h3;
        e <= h4;
        f <= h5;
        g <= h6;
        h <= h7;
    end
    else if (cal_en_d [0]) begin
        a <= t1+t2;
        b <= a;
        c <= b;
        d <= c;
        e <= d + t1;
        f <= e;
        g <= f;
        h <= g;
    end
end

endmodule