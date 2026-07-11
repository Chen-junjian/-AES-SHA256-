
module aes_top(
	//--- APB configure inf
	psel			,
	penable			,
	paddr			,
	pwrite			,
	pwdata			,
	pready			,
	prdata			,

    //--- axi inf
	arid          	,
	araddr        	,
	arlen         	,
	arsize        	,
	arburst       	,
	arlock        	,
	arcache       	,
	arprot        	,
	arvalid       	,
	arready       	,
	
	rid           	,
	rdata         	,
	rresp         	,
	rlast         	,
	rvalid        	,
	rready        	,

	awid			,
	awaddr        	,
	awlen         	,
	awsize        	,
	awburst       	,
	awlock        	,
	awcache       	,
	awprot        	,
	awvalid       	,
	awready       	,
	
	wid           	,
	wdata         	,
	wstrb         	,
	wlast         	,
	wvalid        	,
	wready        	,
	bid           	,
	bresp         	,
	bvalid        	,
	bready        	,

    intr            ,
    clk             ,
    rstn             
);

input   wire            clk, rstn       ;
output  wire            intr            ;

input	wire			psel			;
input	wire			penable			;
input	wire	[7:0]	paddr			;	//byte addr
input	wire			pwrite			;
input	wire	[31:0]	pwdata			;
output	wire			pready			;
output	wire	[31:0]	prdata			;

output  wire    [3:0]   arid      		;	//0
output  wire    [31:0]  araddr    		;
output  wire    [3:0]   arlen     		;
output  wire    [2:0]   arsize    		;
output  wire    [1:0]   arburst   		;
output  wire    [1:0]   arlock    		;
output  wire    [3:0]   arcache   		;
output  wire    [2:0]   arprot    		;
output  wire            arvalid   		;
input   wire            arready   		;
input   wire    [3:0]   rid       		;
input   wire    [31:0]  rdata     		;
input   wire    [1:0]   rresp     		;
input   wire            rlast     		;
input   wire            rvalid    		;
output  wire            rready    		;

output  wire    [3:0]   awid			;	//fixed at 0
output  wire    [31:0]  awaddr    		;	//byte addr
output  wire    [3:0]   awlen     		;
output  wire    [2:0]   awsize    		;
output  wire    [1:0]   awburst   		;
output  wire    [1:0]   awlock    		;
output  wire    [3:0]   awcache   		;
output  wire    [2:0]   awprot    		;
output  wire            awvalid   		;
input   wire            awready   		;
output  wire    [3:0]   wid       		;	//fixed at 0
output  wire    [31:0]  wdata     		;
output  wire    [3:0]   wstrb     		;
output  wire            wlast     		;
output  wire            wvalid    		;
input   wire            wready    		;
input   wire    [3:0]   bid       		;
input   wire    [1:0]   bresp     		;
input   wire            bvalid    		;
output  wire            bready    		;


wire            cfg_key_gen     ;   //1T pulse start the key expansion process
wire            cfg_blk_sof     ;   //1T pulse start the enc/dec of a bulk data block
wire    [31:0]  cfg_blk_base    ;   //must be 16B aligned, bit[3:0] == 'd0, cnt from 1
wire    [31:0]  cfg_blk_len     ;   //must be Nx16B size, cnt from 0
wire    [31:0]  cfg_code_base   ;
wire            cfg_enc_dec     ;   //1: enc; 0: dec
wire    [1:0]   cfg_blk_mode    ;   //0: ECB; 1: CBC; 2: CFB; 3: OFB
wire    [1:0]   cfg_key_len     ;   //0:128b; 2: 256bit
wire    [255:0] cfg_key         ;   //big-endian; when 128bit key len, just bit[255:128] is valid
wire    [127:0] cfg_iv          ;   //big-endian
wire            set_blk_end     ;

wire    [2:0]   ibuf_rptr       ;
wire    [2:0]   ibuf_wptr       ;   //max buf 4 blk of 4x32bit
wire            ibuf_we         ;
wire    [3:0]   ibuf_wbe        ;   //32bit write enable
wire    [127:0] ibuf_wdata      ;   //little endian
wire    [1:0]   ibuf_waddr      ;
wire    [1:0]   ibuf_raddr      ;
wire    [127:0] ibuf_rdata      ;
wire            ibuf_rd         ;

wire    [2:0]   obuf_rptr       ;
wire            obuf_empty      ;
wire            obuf_we         ;
wire    [1:0]   obuf_waddr      ;
wire    [127:0] obuf_wdata      ;
wire    [1:0]   obuf_raddr      ;
wire    [127:0] obuf_rdata      ;
wire            obuf_rd         ;

wire            key_ready       ;
wire            enc_sof         ;   //1T pulse start the encrypt of a 4x32b blk
wire    [127:0] enc_text        ;   //text before encrypt 
wire            enc_ready       ;   //1T pulse, end encrypt of a 4x32b blk
wire    [127:0] enc_code        ;   //code after encipher
wire            first_blk       ;
wire            blk_end         ;

aes_cfg u_aes_cfg(
	//--- APB configure inf
	.psel			(psel			),
	.penable		(penable		),
	.paddr			(paddr			),
	.pwrite			(pwrite			),
	.pwdata			(pwdata			),
	.pready			(pready			),
	.prdata			(prdata			),

	//--- cfg regs
    .cfg_key_gen    (cfg_key_gen    ),
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_blk_base   (cfg_blk_base   ),
    .cfg_blk_len    (cfg_blk_len    ),
    .cfg_code_base  (cfg_code_base  ),
    .cfg_enc_dec    (cfg_enc_dec    ),
    .cfg_blk_mode   (cfg_blk_mode   ),
    .cfg_key_len    (cfg_key_len    ),
    .cfg_key        (cfg_key        ),
    .cfg_iv         (cfg_iv         ),
                                    
    .set_blk_end    (set_blk_end    ),
    .intr           (intr           ),
    .clk            (clk            ),
    .rstn           (rstn           ) 
);

aes_axir u_aes_axir(
    //--- cfg regs
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_blk_base   (cfg_blk_base   ),
    .cfg_blk_len    (cfg_blk_len    ),

    //--- buffer status
    .ibuf_rptr      (ibuf_rptr      ),
    .ibuf_wptr      (ibuf_wptr      ),
    .ibuf_we        (ibuf_we        ),
    .ibuf_wbe       (ibuf_wbe       ),
    .ibuf_wdata     (ibuf_wdata     ),
    .ibuf_waddr     (ibuf_waddr     ),
                                    
	.arid          	(arid          	),
	.araddr        	(araddr        	),
	.arlen         	(arlen         	),
	.arsize        	(arsize        	),
	.arburst       	(arburst       	),
	.arlock        	(arlock        	),
	.arcache       	(arcache       	),
	.arprot        	(arprot        	),
	.arvalid       	(arvalid       	),
	.arready       	(arready       	),
	.rid           	(rid           	),
	.rdata         	(rdata         	),
	.rresp         	(rresp         	),
	.rlast         	(rlast         	),
	.rvalid        	(rvalid        	),
	.rready        	(rready        	),
                                    
    .clk            (clk            ),
    .rstn           (rstn           )  
);

aes_flow_ctrl u_aes_flow_ctrl(
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_blk_len    (cfg_blk_len    ),
    .set_blk_end    (set_blk_end    ),

    //---ibuf status
    .ibuf_wptr      (ibuf_wptr      ),
    .ibuf_rptr      (ibuf_rptr      ),
    .ibuf_rd        (ibuf_rd        ),
    .ibuf_raddr     (ibuf_raddr     ),
    .ibuf_rdata     (ibuf_rdata     ),

    //---obuf status
    .obuf_rptr      (obuf_rptr      ),
    .obuf_empty     (obuf_empty     ),
    .obuf_we        (obuf_we        ),
    .obuf_waddr     (obuf_waddr     ),
    .obuf_wdata     (obuf_wdata     ),

    //--- encipher ctrl
    .key_ready      (key_ready      ),
    .enc_sof        (enc_sof        ),
    .enc_text       (enc_text       ),
    .enc_ready      (enc_ready      ),
    .enc_code       (enc_code       ),
    .first_blk      (first_blk      ),
    .blk_end        (blk_end        ),
                                    
    .clk            (clk            ),
    .rstn           (rstn           ) 
);

aes_core u_aes_core(
    .clk            (clk            ),
    .reset_n        (rstn           ),
    .encdec         (cfg_enc_dec    ),  //1:enc, 0:dec
    .iv             (cfg_iv         ),  
    .blk_mode       (cfg_blk_mode   ),
    .init           (cfg_key_gen    ),  //1T pulse start the generation of round key
    .key_ready      (key_ready      ),
    .key            (cfg_key        ),
    .keylen         (cfg_key_len[1] ),  //0:128b, 1:256b
    .next           (enc_sof        ),  //1T pulse start the encipher or decipher
    .blk_end        (blk_end        ),
    .block          (enc_text       ),
    .first_blk      (first_blk      ),  //1: first blk of a bulk data
    .result         (enc_code       ),
    .result_valid   (enc_ready      )   //high level: encipher/deciper data valid
);

reg_file_wbe #(.ADDR_BITS(2), .ADDR_AMOUNT(4), .DATA_BITS(128), .WBE_BITS(4)) u_ibuf(
    .clk            (clk            ),
    .we             (ibuf_we        ),
    .wbe            (ibuf_wbe       ),
    .waddr          (ibuf_waddr     ),
    .din            (ibuf_wdata     ),
    .raddr          (ibuf_raddr     ),
    .dout           (ibuf_rdata     ) 
);    

reg_file_wbe #(.ADDR_BITS(2), .ADDR_AMOUNT(4), .DATA_BITS(128), .WBE_BITS(4)) u_obuf(
    .clk            (clk            ),
    .we             (obuf_we        ),
    .wbe            (4'hf   ),
    .waddr          (obuf_waddr     ),
    .din            (obuf_wdata     ),
    .raddr          (obuf_raddr     ),
    .dout           (obuf_rdata     ) 
);    

aes_axiw u_aes_axiw(
    //--- cfg regs
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_code_base  (cfg_code_base  ),
    //--- obuf status
    .obuf_rd        (obuf_rd        ),
    .obuf_raddr     (obuf_raddr     ),
    .obuf_rdata     (obuf_rdata     ),
    .obuf_rptr      (obuf_rptr      ),
    .obuf_empty     (obuf_empty     ),

	//--- AXI master inf
	.awid			(awid			),
	.awaddr        	(awaddr        	),
	.awlen         	(awlen         	),
	.awsize        	(awsize        	),
	.awburst       	(awburst       	),
	.awlock        	(awlock        	),
	.awcache       	(awcache       	),
	.awprot        	(awprot        	),
	.awvalid       	(awvalid       	),
	.awready       	(awready       	),
	.wid           	(wid           	),
	.wdata         	(wdata         	),
	.wstrb         	(wstrb         	),
	.wlast         	(wlast         	),
	.wvalid        	(wvalid        	),
	.wready        	(wready        	),
	.bid           	(bid           	),
	.bresp         	(bresp         	),
	.bvalid        	(bvalid        	),
	.bready        	(bready        	),
                                    
    .clk            (clk            ),
    .rstn           (rstn           )
);

endmodule

