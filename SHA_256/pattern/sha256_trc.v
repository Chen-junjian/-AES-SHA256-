`define sha256_path tb.u_sha256

module sha256_trc(
    clk         ,
    rstn         
);


input   wire            clk, rstn       ;

reg     [31:0]  bulk_cnt    ;
reg     [31:0]  blk_cnt     ;
reg     [5:0]   round       ;

wire            cfg_blk_sof ;
wire            axi_bulk_end;
wire            bulk_fir_ini;
wire            bulk_nxt_ini;
wire            cal_en_d    ;
wire    [31:0]  w           ;
wire    [31:0]  a, b, c, d  ;
wire    [31:0]  e, f, g, h  ;

assign  cfg_blk_sof = `sha256_path.u_sha256_cfg.cfg_blk_sof;
assign  axi_bulk_end= `sha256_path.u_sha256_cfg.axi_bulk_end;
assign  w           = `sha256_path.u_sha256_core.u_loop.w[31:0];
assign  a           = `sha256_path.u_sha256_core.u_loop.a;
assign  b           = `sha256_path.u_sha256_core.u_loop.b;
assign  c           = `sha256_path.u_sha256_core.u_loop.c;
assign  d           = `sha256_path.u_sha256_core.u_loop.d;
assign  e           = `sha256_path.u_sha256_core.u_loop.e;
assign  f           = `sha256_path.u_sha256_core.u_loop.f;
assign  g           = `sha256_path.u_sha256_core.u_loop.g;
assign  h           = `sha256_path.u_sha256_core.u_loop.h;

assign  bulk_fir_ini= `sha256_path.u_sha256_core.u_loop.bulk_fir_ini;
assign  bulk_nxt_ini= `sha256_path.u_sha256_core.u_loop.bulk_nxt_ini;
assign  cal_en_d    = `sha256_path.u_sha256_core.u_loop.cal_en_d[0];

integer     fp  ;

initial begin
    fp  = $fopen("./sta_sha256.log", "w");
    bulk_cnt = 0;
    blk_cnt = 0;
    round   = 0;
end


always @(posedge clk or negedge rstn) begin
    if(rstn && cfg_blk_sof) begin
        $fdisplay(fp, "Test package number: %4x", bulk_cnt);
        bulk_cnt    <= bulk_cnt + 1;
        blk_cnt     <= 'd0;
    end
    
    if(rstn && (bulk_fir_ini || bulk_nxt_ini)) begin
        $fdisplay(fp, "block number: %8x", blk_cnt);
        blk_cnt <= blk_cnt + 'd1;
        round   <= 'd0;
    end

    if(rstn && cal_en_d) begin
        $fdisplay(fp, "round: %4x", round);
        $fdisplay(fp, "w: %8x", w);
        $fdisplay(fp, "a: %8x", a);
        $fdisplay(fp, "b: %8x", b);
        $fdisplay(fp, "c: %8x", c);
        $fdisplay(fp, "d: %8x", d);
        $fdisplay(fp, "e: %8x", e);
        $fdisplay(fp, "f: %8x", f);
        $fdisplay(fp, "g: %8x", g);
        $fdisplay(fp, "h: %8x", h);

        round   <= round + 'd1;
    end

end

endmodule

