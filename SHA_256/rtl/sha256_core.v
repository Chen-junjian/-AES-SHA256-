module sha256_core(
    bulk_fir_ini,
    bulk_nxt_ini,
    msg_vld     ,
    msg_data    ,
    msg_dcnt    ,

    sha_blk_end ,
    h0          ,
    h1          ,
    h2          ,
    h3          ,
    h4          ,
    h5          ,
    h6          ,
    h7          ,

    clk         ,
    rstn         
);


input   wire            clk, rstn       ;
input   wire            bulk_fir_ini    ;   //1T pulse start 1st 512b blk sha cal of a bulk data                                                 //align with 1st msg_vld
input   wire            bulk_nxt_ini    ;   //1T pulse start 2nd~Nth 512b blk sha cal 
                                            //align with 1st msg_vld
input   wire            msg_vld         ;   //message data valid
input   wire    [31:0]  msg_data        ;
input   wire    [3:0]   msg_dcnt        ;   //0~15
output  wire            sha_blk_end     ;   //1T high pulse
output  wire    [31:0]  h0, h1, h2, h3  ;   //hash result
output  wire    [31:0]  h4, h5, h6, h7  ; 

wire            cal_en      ;
wire    [5:0]   loop_cnt    ;
wire    [31:0]  k_lut       ;
wire    [31:0]  w           ;

sha256_k_lut u_k_lut(
    .cal_en     (cal_en     ),
    .loop_cnt   (loop_cnt   ),
    .k_lut      (k_lut      ),

    .clk        (clk        ),
    .rstn       (rstn       ) 
);

sha256_w_reg u_w_reg(
    .msg_vld    (msg_vld    ),
    .msg_data   (msg_data   ),
    .msg_dcnt   (msg_dcnt   ),
    .cal_en     (cal_en     ),
    .loop_cnt   (loop_cnt   ),
                            
    .w          (w          ),
    .clk        (clk        ),
    .rstn       (rstn       ) 
);

sha256_loop u_loop(
    .bulk_fir_ini   (bulk_fir_ini   ),
    .bulk_nxt_ini   (bulk_nxt_ini   ),
    .msg_vld        (msg_vld        ),
    .cal_en         (cal_en         ),
    .loop_cnt       (loop_cnt       ),
    .k_lut          (k_lut          ),
    .w              (w              ),
    .sha_blk_end    (sha_blk_end    ),
    .h0             (h0             ),
    .h1             (h1             ),
    .h2             (h2             ),
    .h3             (h3             ),
    .h4             (h4             ),
    .h5             (h5             ),
    .h6             (h6             ),
    .h7             (h7             ),
                                    
    .clk            (clk            ),
    .rstn           (rstn           ) 
);




endmodule

