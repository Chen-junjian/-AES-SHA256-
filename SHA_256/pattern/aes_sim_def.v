`ifndef _AES_SIM_DEFINE_
`define _AES_SIM_DEFINE_

`define     EN_AXI_LATENCY
`define     SYS_MEM_PATH    tb.sys_mem

`define     ENC_DEC_MODE    0   //1:encrypt; 0: decrypt

`define     IN_DATA_BASE    32'h10_0000
`define     OUT_DATA_BASE   32'h80_0000

//--- test case select
`define     IF_NAME         "./sim_case/aes_enc_128b_ecb_trc.bin"
//`define     IF_NAME         "../sim_case/aes_enc_256b_ecb_trc.bin"

//`define     IF_NAME         "../sim_case/aes_enc_128b_cbc_trc.bin"
//`define     IF_NAME         "../sim_case/aes_enc_256b_cbc_trc.bin"

`endif

