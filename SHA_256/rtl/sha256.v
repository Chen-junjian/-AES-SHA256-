module sha256(
	//--- APB configure inf
	psel			,
	penable			,
	paddr			,
	pwrite			,
	pwdata			,
	pready			,
	prdata			,

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

    intr            ,

    clk             ,
    rstn                 
);


input   wire            clk, rstn       ;
//--- APB configure inf
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

output  wire            intr            ;

wire            cfg_blk_sof     ;   //1T pulse start sha of a block (should be N*512bit)
wire    [31:0]  cfg_blk_base    ;   //must be 4B aligned, bit[1:0] == 'd0, cnt from 0
wire    [31:0]  cfg_blk_len     ;   //must be Nx64B size, cnt from 0
wire    [31:0]  h0, h1, h2, h3  ;   //hash result
wire    [31:0]  h4, h5, h6, h7  ;   

wire            ibuf_we         ;
wire    [31:0]  ibuf_wdata      ;   //little endian
wire    [3:0]   ibuf_waddr      ;
wire            sha_blk_end     ;   //1T pusle: sha cal end a 512bit blk
wire            axi_bulk_end    ;   //all the bulk data has been read back, high level active
wire            ibuf_empty      ;
wire            ibuf_pop        ;
wire    [31:0]  ibuf_rdata      ;   //valid same cycle as ibuf_pop

wire            bulk_fir_ini    ;   //1T pulse start 1st 512b blk sha cal of a bulk data
                                    //align with 1st msg_vld
wire            bulk_nxt_ini    ;   //1T pulse start 2nd~Nth 512b blk sha cal 
                                    //align with 1st msg_vld
wire            msg_vld         ;   //message data valid
wire    [31:0]  msg_data        ;
wire    [3:0]   msg_dcnt        ;   //0~15

sha256_cfg u_sha256_cfg(
	//--- APB configure inf
	.psel			(psel			),
	.penable		(penable		),
	.paddr			(paddr			),
	.pwrite			(pwrite			),
	.pwdata			(pwdata			),
	.pready			(pready			),
	.prdata			(prdata			),

	//--- cfg regs
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_blk_base   (cfg_blk_base   ),
    .cfg_blk_len    (cfg_blk_len    ),
                                    
    .axi_bulk_end   (axi_bulk_end   ),
    .h0             (h0             ),
    .h1             (h1             ),
    .h2             (h2             ),
    .h3             (h3             ),
    .h4             (h4             ),
    .h5             (h5             ),
    .h6             (h6             ),
    .h7             (h7             ),
                                    
    .intr           (intr           ),
    .clk            (clk            ),
    .rstn           (rstn           ) 
);

sha256_axir u_sha256_axir(
    //--- cfg regs
    .cfg_blk_sof    (cfg_blk_sof    ),
    .cfg_blk_base   (cfg_blk_base   ),
    .cfg_blk_len    (cfg_blk_len    ),

    //--- buffer status
    .ibuf_we        (ibuf_we        ),
    .ibuf_wdata     (ibuf_wdata     ),
    .ibuf_waddr     (ibuf_waddr     ),
    .sha_blk_end    (sha_blk_end    ),
    .axi_bulk_end   (axi_bulk_end   ),
                                    
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

sync_fifo #(.FIFO_WIDTH(32), .FIFO_DEPTH(16), .FIFO_ADDR_BIT(4)) u_sync_fifo(
    .fifo_wr        (ibuf_we        ),
    .fifo_rd        (ibuf_pop       ),
    .fifo_din       (ibuf_wdata     ),
    .fifo_do        (ibuf_rdata     ),
    .fifo_ful       (   ),              //no use, sha256_axir will make sure the fifo will never overflow
    .fifo_empty     (ibuf_empty     ), 
    .clk            (clk            ),
    .rstn           (rstn           )
);

sha256_flow_ctl u_sha256_flow_ctl(
    .cfg_blk_sof    (cfg_blk_sof    ),
    .axi_bulk_end   (axi_bulk_end   ),

    //--ibuf read
    .ibuf_empty     (ibuf_empty     ),
    .ibuf_pop       (ibuf_pop       ),
    .ibuf_rdata     (ibuf_rdata     ),

    //--sha256 core ctrl and send message input
    .bulk_fir_ini   (bulk_fir_ini   ),
    .bulk_nxt_ini   (bulk_nxt_ini   ),
    .msg_vld        (msg_vld        ),
    .msg_data       (msg_data       ),
    .msg_dcnt       (msg_dcnt       ),
                                    
    .sha_blk_end    (sha_blk_end    ),
                                    
    .clk            (clk            ),
    .rstn           (rstn           ) 
);

sha256_core u_sha256_core(
    .bulk_fir_ini   (bulk_fir_ini   ),
    .bulk_nxt_ini   (bulk_nxt_ini   ),
    .msg_vld        (msg_vld        ),
    .msg_data       (msg_data       ),
    .msg_dcnt       (msg_dcnt       ),
                                    
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

