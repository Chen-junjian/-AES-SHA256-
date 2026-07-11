//======================================================================
//
// aes_decipher_block.v
// 
//======================================================================

//byte in a 4x4 block 
//b0  b4  b8  b12
//b1  b5  b9  b13
//b2  b6  b10 b14
//b3  b7  b11 b15

module aes_decipher_block_fast(
    input wire            clk       ,
    input wire            reset_n   ,
    
    input wire            next      ,   //1T pulse start a 128b blk encrypt
    
    input wire            keylen    ,   //0:128b, 1:256b
    output wire [3 : 0]   round     ,   //round cnt
    input wire [127 : 0]  round_key ,
    
    input wire [127 : 0]  block     ,   //{b0, b1, ..., b15}, codeword
    output reg [127 : 0]  new_block ,   //{b0, b1, ..., b15}, plaintext
    output wire           ready         //high level, a 128bit block ended
);


  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam AES_128_BIT_KEY = 1'h0;
  localparam AES_256_BIT_KEY = 1'h1;

  localparam AES128_ROUNDS = 4'ha;
  localparam AES256_ROUNDS = 4'he;

  localparam NO_UPDATE    = 2'h0;
  localparam INIT_UPDATE  = 2'h1;
  localparam MAIN_UPDATE  = 2'h2;
  localparam FINAL_UPDATE = 2'h3;

  localparam CTRL_IDLE  = 2'h0;
  localparam CTRL_INIT  = 2'h1;
  localparam CTRL_MAIN  = 2'h3;


  //----------------------------------------------------------------
  // Gaolis multiplication functions for Inverse MixColumn.
  //----------------------------------------------------------------
  function [7 : 0] gm2(input [7 : 0] op);
    begin
      gm2 = {op[6 : 0], 1'b0} ^ (8'h1b & {8{op[7]}});
    end
  endfunction // gm2

  function [7 : 0] gm3(input [7 : 0] op);
    begin
      gm3 = gm2(op) ^ op;
    end
  endfunction // gm3

  function [7 : 0] gm4(input [7 : 0] op);
    begin
      gm4 = gm2(gm2(op));
    end
  endfunction // gm4

  function [7 : 0] gm8(input [7 : 0] op);
    begin
      gm8 = gm2(gm4(op));
    end
  endfunction // gm8

  function [7 : 0] gm09(input [7 : 0] op);
    begin
      gm09 = gm8(op) ^ op;
    end
  endfunction // gm09

  function [7 : 0] gm11(input [7 : 0] op);
    begin
      gm11 = gm8(op) ^ gm2(op) ^ op;
    end
  endfunction // gm11

  function [7 : 0] gm13(input [7 : 0] op);
    begin
      gm13 = gm8(op) ^ gm4(op) ^ op;
    end
  endfunction // gm13

  function [7 : 0] gm14(input [7 : 0] op);
    begin
      gm14 = gm8(op) ^ gm4(op) ^ gm2(op);
    end
  endfunction // gm14

  function [31 : 0] inv_mixw(input [31 : 0] w);
    reg [7 : 0] b0, b1, b2, b3;
    reg [7 : 0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31 : 24];
      b1 = w[23 : 16];
      b2 = w[15 : 08];
      b3 = w[07 : 00];

      mb0 = gm14(b0) ^ gm11(b1) ^ gm13(b2) ^ gm09(b3);
      mb1 = gm09(b0) ^ gm14(b1) ^ gm11(b2) ^ gm13(b3);
      mb2 = gm13(b0) ^ gm09(b1) ^ gm14(b2) ^ gm11(b3);
      mb3 = gm11(b0) ^ gm13(b1) ^ gm09(b2) ^ gm14(b3);

      inv_mixw = {mb0, mb1, mb2, mb3};
    end
  endfunction // mixw

  function [127 : 0] inv_mixcolumns(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = inv_mixw(w0);
      ws1 = inv_mixw(w1);
      ws2 = inv_mixw(w2);
      ws3 = inv_mixw(w3);

      inv_mixcolumns = {ws0, ws1, ws2, ws3};
    end
  endfunction // inv_mixcolumns

  function [127 : 0] inv_shiftrows(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = {w0[31 : 24], w3[23 : 16], w2[15 : 08], w1[07 : 00]};
      ws1 = {w1[31 : 24], w0[23 : 16], w3[15 : 08], w2[07 : 00]};
      ws2 = {w2[31 : 24], w1[23 : 16], w0[15 : 08], w3[07 : 00]};
      ws3 = {w3[31 : 24], w2[23 : 16], w1[15 : 08], w0[07 : 00]};

      inv_shiftrows = {ws0, ws1, ws2, ws3};
    end
  endfunction // inv_shiftrows

  function [127 : 0] addroundkey(input [127 : 0] data, input [127 : 0] rkey);
    begin
      addroundkey = data ^ rkey;
    end
  endfunction // addroundkey

  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  reg [3 : 0]   round_ctr_reg   ;   //DFF, loop round cnt
  reg [3 : 0]   round_ctr_new   ;   //combination, next loop round cnt
  wire          round_ctr_we    ;   //DFF write enable
  reg           round_ctr_set   ;
  reg           round_ctr_dec   ;

  reg [127 : 0] block_new       ;   //updated state after each loop
  reg           block_we        ;   //continous high level for 11/15 cycles

  reg           ready_reg       ;
  reg           ready_new       ;
  reg           ready_we        ;

  reg [1 : 0]   dec_ctrl_reg    ;   //DFF, FSM
  reg [1 : 0]   dec_ctrl_new    ;   //combination, next state of FSM
  reg           dec_ctrl_we     ;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  wire [127 : 0] tmp_sboxw      ;   //invsubbyte input
  wire [127 : 0] new_sboxw      ;   //invsubbyte output
  reg [1 : 0]   update_type     ;
  reg [127 : 0] inv_shiftrows_block, inv_mixcolumns_block;
  reg [127 : 0] addkey_block    ;


  //----------------------------------------------------------------
  // Instantiations invsubbyte look up table
  //----------------------------------------------------------------
  assign    tmp_sboxw = inv_shiftrows_block;

  aes_inv_sbox_fast inv_sbox_inst(.sboxw(tmp_sboxw), .new_sboxw(new_sboxw));

  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign round     = round_ctr_reg;
  assign ready     = ready_reg;

  //----------------------------------------------------------------
  // reg_update
  //
  // Update functionality for all registers in the core.
  // All registers are positive edge triggered with synchronous
  // active low reset. All registers have write enable.
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          round_ctr_reg <= 4'h0;
          ready_reg     <= 1'b1;
          dec_ctrl_reg  <= CTRL_IDLE;
        end
      else
        begin
          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (dec_ctrl_we)
            dec_ctrl_reg <= dec_ctrl_new;
        end
    end // reg_update

  always @(posedge clk)
  if(block_we)
    new_block <= block_new;

  //----------------------------------------------------------------
  // round_logic
  //
  // The logic needed to implement init, main and final rounds.
  //----------------------------------------------------------------
  always @(*)
    begin : round_logic
      inv_shiftrows_block  = 128'h0;
      inv_mixcolumns_block = 128'h0;
      addkey_block         = 128'h0;
      block_new            = 128'h0;
      block_we             = 1'b0;

      // Update based on update type.
      case (update_type)
        // InitRound
        INIT_UPDATE:    //XOR KEY -> invshiftrow -> invsubbyte
          begin
            addkey_block        = addroundkey(block, round_key);
            inv_shiftrows_block = inv_shiftrows(addkey_block);
            block_new           = new_sboxw;
            block_we             = 1'b1;
          end

        MAIN_UPDATE:    //XOR KEY -> invmixcolumn -> invshiftrow -> invsubbyte
          begin
            addkey_block         = addroundkey(new_block, round_key);
            inv_mixcolumns_block = inv_mixcolumns(addkey_block);
            inv_shiftrows_block  = inv_shiftrows(inv_mixcolumns_block);
            block_new            = new_sboxw;
            block_we             = 1'b1;
          end

        FINAL_UPDATE:   //XOR KEY
          begin
            block_new    = addroundkey(new_block, round_key);
            block_we     = 1'b1;
          end

        default:
          begin
          end
      endcase // case (update_type)
    end // round_logic

  //----------------------------------------------------------------
  // round_ctr
  //
  // The round counter with reset and increase logic.
  //----------------------------------------------------------------
    
  assign    round_ctr_we = round_ctr_set | round_ctr_dec;

  always @(*) begin
    if(round_ctr_set) begin
      if(keylen == AES_256_BIT_KEY)
          round_ctr_new = AES256_ROUNDS;
      else
          round_ctr_new = AES128_ROUNDS;
    end else begin
      round_ctr_new = round_ctr_reg - 1'b1;
    end
  end

  //----------------------------------------------------------------
  // decipher_ctrl
  //
  // The FSM that controls the decipher operations.
  //----------------------------------------------------------------
  always @(*)
    begin: decipher_ctrl
      round_ctr_dec = 1'b0;
      round_ctr_set = 1'b0;
      ready_new     = 1'b0;
      ready_we      = 1'b0;
      update_type   = NO_UPDATE;
      dec_ctrl_new  = CTRL_IDLE;
      dec_ctrl_we   = 1'b0;

      case(dec_ctrl_reg)
        CTRL_IDLE:
          begin
            if (next)
              begin
                round_ctr_set = 1'b1;
                ready_new     = 1'b0;
                ready_we      = 1'b1;
                dec_ctrl_new  = CTRL_INIT;
                dec_ctrl_we   = 1'b1;
              end
          end

        CTRL_INIT:
          begin
            round_ctr_dec = 1'b1;
            update_type   = INIT_UPDATE;
            dec_ctrl_new  = CTRL_MAIN;
            dec_ctrl_we   = 1'b1;
          end

        CTRL_MAIN:
          begin
            round_ctr_dec = 1'b1;

            if (round_ctr_reg != 0)
              begin
                update_type   = MAIN_UPDATE;
                dec_ctrl_new  = CTRL_MAIN;
                dec_ctrl_we   = 1'b1;
              end
            else
              begin
                update_type  = FINAL_UPDATE;
                ready_new    = 1'b1;
                ready_we     = 1'b1;
                dec_ctrl_new = CTRL_IDLE;
                dec_ctrl_we  = 1'b1;
              end
          end

        default:
          begin
            // Empty. Just here to make the synthesis tool happy.
          end
      endcase // case (dec_ctrl_reg)
    end // decipher_ctrl

endmodule // aes_decipher_block

//======================================================================
// EOF aes_decipher_block.v
//======================================================================
