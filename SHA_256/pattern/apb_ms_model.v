`include "aes_sim_def.v"
`timescale 1ns / 10ps
module apb_ms_model(
	//--- APB configure inf
	psel			,
	penable			,
	paddr			,
	pwrite			,
	pwdata			,
	pready			,
	prdata			,

    intr            ,

    clk				,
    rstn			 
);

parameter   IFNAME    = "./sim_case/aes_enc_128b_ecb_trc.bin";
parameter   AES_CFG_BASE = 'd0;


input   wire			clk, rstn		;


//--- APB configure inf
output	reg				psel			;
output	reg				penable			;
output	reg		[31:0]	paddr			;	//byte addr
output	reg				pwrite			;
output	reg		[31:0]	pwdata			;
input	wire			pready			;
input	wire	[31:0]	prdata			;

input   wire            intr            ;

//--- 1: apb w/r task

task apb_write;
input	[31:0]	addr	;
input	[31:0]	wdata	;
begin
	@(posedge clk); #1;
	psel = 1; pwrite = 1; paddr = addr; pwdata = wdata;
	@(posedge clk); #1;
	penable = 1;
	
	@(negedge clk);
	while(!pready) begin
		@(negedge clk);
	end

	@(posedge clk); #1;
	psel = 0; penable = 0;
end
endtask

task apb_read;
input	[31:0]	addr	;
output	[31:0]	rdata	;
begin	
	@(posedge clk); #1;
	psel = 1; pwrite = 0; paddr = addr;
	@(posedge clk); #1;
	penable = 1;
	
	@(negedge clk);
	while(!pready) begin
		@(negedge clk);
	end
	rdata = prdata;

	@(posedge clk); #1;
	psel = 0; penable = 0;
end
endtask


//--- 2: AES cfg initial ctrl ---//

task fget_32b;
input   [31:0]  fp      ;
output  [31:0]  rdata   ;
begin
    rdata[0*8 +: 8]  = $fgetc(fp);
    rdata[1*8 +: 8]  = $fgetc(fp);
    rdata[2*8 +: 8]  = $fgetc(fp);
    rdata[3*8 +: 8]  = $fgetc(fp);
end
endtask

integer             in_fp       ;
reg     [31:0]      tmp32       ;
reg     [7:0]       tmp8        ;

reg     [1:0]       blk_mode    ;
reg                 enc_dec     ;   //1:enc; 0:dec
reg     [1:0]       key_len     ;   //0:128b; 2:256b
reg     [7:0]       key_bsize   ;
reg     [31:0]      in_base, out_base;
reg     [31:0]      in_byte_len ;   //cnt from 1
reg     [31:0]      bulk_num    ;
reg     [31:0]      bulk_cnt    ;

reg     [31:0]      i, j        ;

initial begin

    in_fp = $fopen(IFNAME, "rb");
    if(in_fp == 0) begin
        $display("Sim Erro: File %s doesn't exist. Which is needed by %m .", IFNAME);
        $finish();
    end

	psel		= 0;
	penable		= 0;
	paddr		= 0;
	pwrite		= 0;
	pwdata		= 0;
    #10;

	@(posedge rstn);
    repeat(10) @(posedge clk);

    //--- get head info
    enc_dec     = $fgetc(in_fp);    //read and discard this byte
    if(`ENC_DEC_MODE == 1)
        enc_dec = 1;
    else
        enc_dec = 0;

    blk_mode    = $fgetc(in_fp);
    key_len     = $fgetc(in_fp);
    fget_32b(in_fp, bulk_num);

    //--- write in key
    if(key_len == 2)    key_bsize = 32;
    else                key_bsize = 16;

    for(i=0; i<(key_bsize / 4); i=i+1) begin
        fget_32b(in_fp, tmp32);
        apb_write(AES_CFG_BASE + 4*(16+i), tmp32);
    end

    //--- write in IV
    if(blk_mode != 0) begin
        for(i=0; i<(16 / 4); i=i+1) begin
            fget_32b(in_fp, tmp32);
            apb_write(AES_CFG_BASE + 4*(8+i), tmp32);
        end        
    end
    
    tmp32 = (key_len << 8) | (blk_mode << 4) | (enc_dec);
    apb_write(AES_CFG_BASE + 4*1, tmp32);

    apb_write(AES_CFG_BASE + 4*4, `IN_DATA_BASE);
    apb_write(AES_CFG_BASE + 4*5, `OUT_DATA_BASE);
    //--- start key expansion
    apb_write(AES_CFG_BASE + 4*0, (1<<4));

    //--- print sim case info
    $display("Info: sim case info:");
    if(enc_dec)
        $display("Encrypt case.");
    else
        $display("Decrypt case.");

    if(key_len == 2)
        $display("256 bit key length");
    else
        $display("128 bit key length");

    case(blk_mode)
    'd0:    $display("ECB mode in a bulk data");
    'd1:    $display("CBC mode in a bulk data");
    'd2:    $display("CFB mode in a bulk data");
    'd3:    $display("OFB mode in a bulk data");
    endcase

    $display("Total test bulk number: %8h.", bulk_num);
    $display("");
    //--- encrypt/decrypt of each bulk
    for(i=0; i<bulk_num; i=i+1) begin
        fget_32b(in_fp, in_byte_len);
        apb_write(AES_CFG_BASE + 4*6, (in_byte_len-1));

        //--- write input test/code to sys_mem
        if(!enc_dec)    //decrypt mode
            $fseek(in_fp, in_byte_len, 1);      //go to code position

        for(j=0; j<in_byte_len; j=j+1) begin
            tmp8 = $fgetc(in_fp);
            `SYS_MEM_PATH[`IN_DATA_BASE+j] = tmp8;
        end

        //--- start the cal of a bulk
        apb_write(AES_CFG_BASE + 4*0, 32'h1);

        //--- wait cal end and check result
        @(posedge intr);
        apb_write(AES_CFG_BASE + 4*3, 32'h0);

        repeat(2) @(posedge clk);

        if(!enc_dec)
            $fseek(in_fp, ('sd0 - 2*in_byte_len), 1);   //go to text position of this bulk

        for(j=0; j<in_byte_len; j=j+1) begin
            tmp8 = $fgetc(in_fp);
            if(tmp8 !== `SYS_MEM_PATH[`OUT_DATA_BASE+j]) begin
                $display("Error: sim fail.");
                $display("Fail at test bulk of %8x, byte location %8x .", i, j);
                $display("Ref is %2x, DUT out is %2x .", tmp8, `SYS_MEM_PATH[`OUT_DATA_BASE+j]);
                $finish();
            end
        end

        if(!enc_dec)
            $fseek(in_fp, in_byte_len, 1);              //go to blk_len position of next bulk
    end

    repeat(10) @(posedge clk); #1;
    $display("OK: sim pass.");
    $finish();

end

endmodule

