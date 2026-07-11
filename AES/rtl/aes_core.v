
module aes_core(
                input wire            clk       ,
                input wire            reset_n   ,

                input wire            encdec    ,   //1:enc, 0:dec
                input wire [127:0]    iv        ,   //initial vector
                input wire            init      ,   //1T pulse start the generation of round key
                input wire            next      ,   //1T pulse start the encipher or decipher, must wait for key_ready=1
                input wire            first_blk ,   //high level: first blk of a bulk data
                input wire [1:0]      blk_mode  ,   //0:ECB; 1:CBC
                input wire            blk_end   ,   //1T pulse indicate the end of encrypt or decrypt of a 128bit
                output wire           key_ready ,   //high level: generation of round key ended
                input wire [255 : 0]  key       ,   //input 128/256bit key
                input wire            keylen    ,   //0:128b, 1:256b

                input wire [127 : 0]  block     ,   //keep valid between the time : next=1 to blk_end=1
                output wire [127 : 0] result    ,   //encipher/decipher result
                output wire           result_valid  //high level: encipher/deciper result valid
               );

  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  wire           init_state     ;   //1: in key expansion state
  reg            init_state_reg ;
  wire [127 : 0] round_key      ;   //128bit key of a loop round

  reg            enc_next       ;   //1T pulse start encipher of a 128bit block
  reg [127:0]    enc_block_in   ;   //input of encipher
  wire [3 : 0]   enc_round_nr   ;   //loop round cnt of a blk
  wire [127 : 0] enc_new_block  ;   //encipher output
  wire           enc_ready      ;   //high level: encipher end a block
  wire [127 : 0] enc_sboxw      ;   //subbyte input of encipher

  reg            dec_next       ;   //1T pulse start decipher of a 128bit block
  wire [3 : 0]   dec_round_nr   ;   //loop round cnt of a blk
  reg  [127:0]   dec_cbc_mem    ;   //registered state for CBC mode decipher
  wire [127 : 0] dec_new_block_pre; //output from decipher
  wire [127 : 0] dec_new_block  ;   //decipher final plaintext result
  wire           dec_ready      ;   //high level: decipher end a block

  reg [127 : 0]  muxed_new_block;   //enc/dec MUXed result
  reg [3 : 0]    muxed_round_nr ;   //enc/dec MUXed loop cnt
  reg            muxed_ready    ;   //enc/dec MUXed blk ready
  wire [31 : 0]  keymem_sboxw   ;   //subbyte input of key expansion
  reg [127 : 0]  muxed_sboxw    ;   //subbyte input of 16B
  wire [127 : 0] new_sboxw      ;   //subbyte output of 16B

//先选择CBC 或者 ECB 模式进行加密
  always @(*) begin
    case(blk_mode)
    'd0:    enc_block_in   = block;     //ECB mode
    'd1:    begin                       //CBC mode
                if(first_blk)
                    enc_block_in   = block ^ iv;
                else
                    enc_block_in   = block ^ enc_new_block;
            end
    default:enc_block_in   = block;
    endcase
  end

  always @(posedge clk)
  if((!encdec) && dec_next && first_blk && (blk_mode == 'd1))
    dec_cbc_mem <= iv;
  else if((!encdec) && blk_end && (blk_mode == 'd1))
    dec_cbc_mem <= block;

  //----------------------------------------------------------------
  // Instantiations.
  //----------------------------------------------------------------
  aes_encipher_block enc_block(
        .clk        (clk            ),
        .reset_n    (reset_n        ),
        
        .next       (enc_next       ),
        .keylen     (keylen         ),
        .round      (enc_round_nr   ),
        .round_key  (round_key      ),
        .sboxw      (enc_sboxw      ),
        .new_sboxw  (new_sboxw      ),        
        .block      (enc_block_in   ),

        .new_block  (enc_new_block  ),
        .ready      (enc_ready      )
  );


  //aes_decipher_block dec_block(
  aes_decipher_block_fast dec_block(
        .clk        (clk            ),
        .reset_n    (reset_n        ),
        
        .next       (dec_next       ),
        .keylen     (keylen         ),
        .round      (dec_round_nr   ),
        .round_key  (round_key      ),
        .block      (block          ),

        .new_block  (dec_new_block_pre),
        .ready      (dec_ready      )
  );

  //key expansion and store
  aes_key_mem keymem(
        .clk        (clk            ),
        .reset_n    (reset_n        ),

        .key        (key            ),
        .keylen     (keylen         ),
        .init       (init           ),
        .ready      (key_ready      ),

        .round      (muxed_round_nr ),
        .round_key  (round_key      ),

        .sboxw      (keymem_sboxw   ),
        .new_sboxw  (new_sboxw[31:0])
  );


  //subbyte
  aes_sbox_lut sbox_inst(.sboxw(muxed_sboxw), .new_sboxw(new_sboxw));


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  
  //----------------------------------------------------------------
  assign result       = muxed_new_block;
  assign result_valid = muxed_ready;

  //----------------------------------------------------------------
  // sbox_mux
  //
  // Controls which of the encipher datapath or the key memory
  // that gets access to the sbox.
  //----------------------------------------------------------------
  always @*
    begin : sbox_mux
      if (init_state) //做轮密钥扩展的阶段
        begin
          muxed_sboxw = {96'h0, keymem_sboxw};
        end
      else
        begin
          muxed_sboxw = enc_sboxw;
        end
    end // sbox_mux


  //----------------------------------------------------------------
  // encdex_mux
  //
  // Controls which of the datapaths that get the next signal, have
  // access to the memory as well as the block processing result.
  //----------------------------------------------------------------

  assign dec_new_block = (blk_mode == 'd1)? (dec_new_block_pre ^ dec_cbc_mem) : dec_new_block_pre;

  always @*
    begin : encdec_mux
      enc_next = 1'b0;
      dec_next = 1'b0;

      if (encdec)
        begin
          // Encipher operations
          enc_next        = next;
          muxed_round_nr  = enc_round_nr;
          muxed_new_block = enc_new_block;
          muxed_ready     = enc_ready;
        end
      else
        begin
          // Decipher operations
          dec_next        = next;
          muxed_round_nr  = dec_round_nr;
          muxed_new_block = dec_new_block;
          muxed_ready     = dec_ready;
        end
    end // encdec_mux


  //----------------------------------------------------------------
  // init_state: key expansion period; when init_state=1, can't do 
  // encipher/decipher.
  //----------------------------------------------------------------

  assign    init_state = init_state_reg;

  always @(posedge clk or negedge reset_n)
  if(!reset_n)
    init_state_reg  <= 1'b1;
  else if(init)
    init_state_reg  <= 1'b1;
  else if(key_ready)
    init_state_reg  <= 1'b0;

endmodule // aes_core

//======================================================================
// EOF aes_core.v
//======================================================================
