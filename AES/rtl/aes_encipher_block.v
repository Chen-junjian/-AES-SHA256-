//======================================================================
//
// aes_encipher_block.v
// --------------------

//byte in a 4x4 block 
//b0  b4  b8  b12
//b1  b5  b9  b13
//b2  b6  b10 b14
//b3  b7  b11 b15

module aes_encipher_block(
    input wire            clk       ,
    input wire            reset_n   ,
    
    input wire            next      ,   //1T pulse start a 128b blk encrypt
    
    input wire            keylen    ,   //0:128b, 1:256b
    output wire [3 : 0]   round     ,   //round cnt
    input wire [127 : 0]  round_key ,   //{b0, b1, ..., b15}
    
    output wire [127 : 0] sboxw     ,   //subbyte input
    input wire  [127 : 0] new_sboxw ,   //subbyte output
    
    input wire [127 : 0]  block     ,   //{b0, b1, ..., b15}
    output wire [127 : 0] new_block ,   //{b0, b1, ..., b15}
    output wire           ready         //high level, a 128bit block ended
);


  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam AES_128_BIT_KEY = 1'h0;
  localparam AES_256_BIT_KEY = 1'h1;

  localparam AES128_ROUNDS = 4'ha; //10 轮
  localparam AES256_ROUNDS = 4'he; //15 轮

  localparam NO_UPDATE    = 2'h0; //未开始
  localparam INIT_UPDATE  = 2'h1; //初始化
  localparam MAIN_UPDATE  = 2'h2; //主循环
  localparam FINAL_UPDATE = 2'h3; //最后一轮

  localparam CTRL_IDLE  = 2'h0;
  localparam CTRL_INIT  = 2'h1;
  localparam CTRL_MAIN  = 2'h3;


  //----------------------------------------------------------------
  // Round functions with sub functions.
  //----------------------------------------------------------------
  //有限域乘2
  function [7 : 0] gm2(input [7 : 0] op);
    begin
      gm2 = {op[6 : 0], 1'b0} ^ (8'h1b & {8{op[7]}});
    end
  endfunction // gm2

  //有限域乘3
  function [7 : 0] gm3(input [7 : 0] op);
    begin
      gm3 = gm2(op) ^ op;
    end
  endfunction // gm3

  function [31 : 0] mixw(input [31 : 0] w);
    reg [7 : 0] b0, b1, b2, b3; //每一word 分为4 byte 进行计算
    reg [7 : 0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31 : 24];
      b1 = w[23 : 16];
      b2 = w[15 : 08];
      b3 = w[07 : 00];

      mb0 = gm2(b0) ^ gm3(b1) ^ b2      ^ b3;
      mb1 = b0      ^ gm2(b1) ^ gm3(b2) ^ b3;
      mb2 = b0      ^ b1      ^ gm2(b2) ^ gm3(b3);
      mb3 = gm3(b0) ^ b1      ^ b2      ^ gm2(b3);

      mixw = {mb0, mb1, mb2, mb3}; //一列进行mixcolumn 矩阵运算
    end
  endfunction // mixw

  function [127 : 0] mixcolumns(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = mixw(w0);
      ws1 = mixw(w1);
      ws2 = mixw(w2);
      ws3 = mixw(w3);

      mixcolumns = {ws0, ws1, ws2, ws3};
    end
  endfunction // mixcolumns

  function [127 : 0] shiftrows(input [127 : 0] data);
    reg [31 : 0] w0, w1, w2, w3;
    reg [31 : 0] ws0, ws1, ws2, ws3;
    begin                   // a 4x4 aes blk
      w0 = data[127 : 096]; // w0[b3] w1[b3] w2[b3] w3[b3] 
      w1 = data[095 : 064]; // w0[b2] w1[b2] w2[b2] w3[b2] 
      w2 = data[063 : 032]; // w0[b1] w1[b1] w2[b1] w3[b1] 
      w3 = data[031 : 000]; // w0[b0] w1[b0] w2[b0] w3[b0] 
                                                                    //shift result
      ws0 = {w0[31 : 24], w1[23 : 16], w2[15 : 08], w3[07 : 00]};   // ws0[b3] ws1[b3] ws2[b3] ws3[b3]
      ws1 = {w1[31 : 24], w2[23 : 16], w3[15 : 08], w0[07 : 00]};   // ws0[b2] ws1[b2] ws2[b2] ws3[b2]
      ws2 = {w2[31 : 24], w3[23 : 16], w0[15 : 08], w1[07 : 00]};   // ws0[b1] ws1[b1] ws2[b1] ws3[b1]
      ws3 = {w3[31 : 24], w0[23 : 16], w1[15 : 08], w2[07 : 00]};   // ws0[b0] ws1[b0] ws2[b0] ws3[b0]

      shiftrows = {ws0, ws1, ws2, ws3}; //128bit 每一行进行位移
    end
  endfunction // shiftrows

  function [127 : 0] addroundkey(input [127 : 0] data, input [127 : 0] rkey);
    begin
      addroundkey = data ^ rkey;
    end
  endfunction // addroundkey

  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  reg [3 : 0]   round_ctr_reg;  //DFF, round counter
  wire[3 : 0]   round_ctr_new;  //combination
  wire          round_ctr_we;   //reg write enable
  reg           round_ctr_rst;  //reg reset
  reg           round_ctr_inc;  //round_ctr_reg + 1

  reg [127 : 0] block_new;
  reg [31 : 0]  block_w0_reg;   //first column of 4 bytes, store status of each loop
  reg [31 : 0]  block_w1_reg;   //second column of 4 bytes
  reg [31 : 0]  block_w2_reg;
  reg [31 : 0]  block_w3_reg;   //4th column of 4 bytes
  reg           block_w0_we;    //now, each cycle finish a loop round, block_w0/1/2/3_we
  reg           block_w1_we;    //are all 1'b1 for 11/15 continous cycles.
  reg           block_w2_we;
  reg           block_w3_we;

  reg           ready_reg;      //DFF
  reg           ready_new;      //combination
  reg           ready_we;       //write enable

  reg [1 : 0]   enc_ctrl_reg;   //FSM DFF
  reg [1 : 0]   enc_ctrl_new;
  reg           enc_ctrl_we;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg [1 : 0]   update_type;
  reg [127 : 0] muxed_sboxw;    //subbyte input


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign round     = round_ctr_reg;
  assign sboxw     = muxed_sboxw;
  assign new_block = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
  assign ready     = ready_reg;


  //----------------------------------------------------------------
  // reg_update
  //
  // Update functionality for all registers in the core.
  // All registers are positive edge triggered with asynchronous
  // active low reset. All registers have write enable.
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          block_w0_reg  <= 32'h0;
          block_w1_reg  <= 32'h0;
          block_w2_reg  <= 32'h0;
          block_w3_reg  <= 32'h0;
          round_ctr_reg <= 4'h0;
          ready_reg     <= 1'b1;
          enc_ctrl_reg  <= CTRL_IDLE;
        end
      else
        begin
          if (block_w0_we)
            block_w0_reg <= block_new[127 : 096];

          if (block_w1_we)
            block_w1_reg <= block_new[095 : 064];

          if (block_w2_we)
            block_w2_reg <= block_new[063 : 032];

          if (block_w3_we)
            block_w3_reg <= block_new[031 : 000];

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (enc_ctrl_we)
            enc_ctrl_reg <= enc_ctrl_new;
        end
    end // reg_update


  //----------------------------------------------------------------
  // round_logic
  //
  // The logic needed to implement init, main and final rounds.
  //----------------------------------------------------------------
  always @(*)
    begin : round_logic
      reg [127 : 0] shiftrows_block, mixcolumns_block;
      reg [127 : 0] addkey_init_block, addkey_main_block, addkey_final_block;

      block_new   = 128'h0;
      block_w0_we = 1'b0;
      block_w1_we = 1'b0;
      block_w2_we = 1'b0;
      block_w3_we = 1'b0;

      muxed_sboxw = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
      shiftrows_block    = shiftrows(new_sboxw);
      mixcolumns_block   = mixcolumns(shiftrows_block);
      addkey_init_block  = addroundkey(block, round_key); //首轮直接加轮密钥 不需要subbyte shiftrow mixcolumn
      addkey_main_block  = addroundkey(mixcolumns_block, round_key); // main round 需要先subbyte再shiftrow再mixcolumn 最后加轮密钥
      addkey_final_block = addroundkey(shiftrows_block, round_key); // final round 不需要mixcolumn 直接subbyte shiftrow 加轮密钥

      case (update_type)
        INIT_UPDATE:
          begin
            block_new    = addkey_init_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        MAIN_UPDATE:
          begin
            block_new    = addkey_main_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        FINAL_UPDATE:
          begin
            block_new    = addkey_final_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
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
  
  assign    round_ctr_we = round_ctr_rst | round_ctr_inc;
  assign    round_ctr_new= (round_ctr_rst)? 'd0 : (round_ctr_reg + 1'b1);

  //----------------------------------------------------------------
  // encipher_ctrl
  //
  // The FSM that controls the encipher operations.
  //----------------------------------------------------------------
  always @(*)
    begin: encipher_ctrl
      reg [3 : 0] num_rounds;

      // Default assignments.
      round_ctr_inc = 1'b0;
      round_ctr_rst = 1'b0;
      ready_new     = 1'b0;
      ready_we      = 1'b0;
      update_type   = NO_UPDATE;
      enc_ctrl_new  = CTRL_IDLE;
      enc_ctrl_we   = 1'b0;

      if (keylen == AES_256_BIT_KEY)
        begin
          num_rounds = AES256_ROUNDS;
        end
      else
        begin
          num_rounds = AES128_ROUNDS;
        end

      case(enc_ctrl_reg)
        CTRL_IDLE:
          begin
            if (next)
              begin
                round_ctr_rst = 1'b1;
                ready_new     = 1'b0;
                ready_we      = 1'b1;
                enc_ctrl_new  = CTRL_INIT;
                enc_ctrl_we   = 1'b1;
              end
          end

        CTRL_INIT:
          begin
            round_ctr_inc = 1'b1;
            update_type   = INIT_UPDATE;
            enc_ctrl_new  = CTRL_MAIN;
            enc_ctrl_we   = 1'b1;
          end

        CTRL_MAIN:
          begin
            round_ctr_inc = 1'b1;
            if (round_ctr_reg != num_rounds)
              begin
                update_type   = MAIN_UPDATE;
                enc_ctrl_new  = CTRL_MAIN;
                enc_ctrl_we   = 1'b1;
              end
            else
              begin
                update_type  = FINAL_UPDATE;
                ready_new    = 1'b1;
                ready_we     = 1'b1;
                enc_ctrl_new = CTRL_IDLE;
                enc_ctrl_we  = 1'b1;
              end
          end

        default:
          begin
            // Empty. Just here to make the synthesis tool happy.
          end
      endcase // case (enc_ctrl_reg)
    end // encipher_ctrl

endmodule // aes_encipher_block

//======================================================================
// EOF aes_encipher_block.v
//======================================================================
