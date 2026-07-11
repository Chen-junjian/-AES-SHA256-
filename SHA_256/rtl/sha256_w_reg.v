module sha256_w_reg (
    clk,
    rstn,
    msg_data,
    msg_dcnt,
    msg_vld,
    cal_en,
    loop_cnt,
    w
);

    input wire clk, rstn;
    input wire [31:0] msg_data;
    input wire [3:0] msg_dcnt;
    input wire msg_vld;
    input wire cal_en;
    input wire [5:0] loop_cnt;

    output wire [31:0] w;

    reg [31:0] w_mem [0:15]; //存16个 w 以便进行运算 输出下一个w

    wire [31:0] w0,w1,w9,w14,w_new,r0,r1;

    assign w0 = w_mem[0];
    assign w1 = w_mem[1];
    assign w9 = w_mem[9];
    assign w14 = w_mem[14];

    assign r0 = {w1[6:0],w1[31:7]} ^ {w1[17:0],w1[31:18]} ^ {3'b000,w1[31:3]};
    assign r1 = {w14[16:0],w14[31:17]} ^ {w14[18:0],w14[31:19]} ^ {10'h0,w14[31:10]};

    assign w_new = r0 + r1 + w9 + w0;

    generate
        genvar i;
        for (i =0 ; i<16 ;i=i+1) begin :gen_w_mem
            always @(posedge clk ) begin
                if (msg_vld || cal_en) begin
                    if (i == 15) begin
                        if (msg_vld)
                            w_mem [i] <= msg_data;
                        else 
                            w_mem [i] <= w_new;
                    end

                    else 
                            w_mem [i] <= w_mem[i+1];

                end
            end
        end
    endgenerate

    assign w = w_mem [15];
endmodule 