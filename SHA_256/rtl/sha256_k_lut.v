module sha256_k_lut(
    cal_en      ,
    loop_cnt    ,
    k_lut       ,

    clk         ,
    rstn         
);


input   wire            clk, rstn       ;
input   wire            cal_en          ;
input   wire    [5:0]   loop_cnt        ;
output  reg     [31:0]  k_lut           ;   //1T delay of cal_en/loop_cnt


always @(posedge clk)   // or negedge rstn)
if(cal_en) begin
    case(loop_cnt)
      'd00: k_lut <= 32'h428a2f98;
      'd01: k_lut <= 32'h71374491;
      'd02: k_lut <= 32'hb5c0fbcf;
      'd03: k_lut <= 32'he9b5dba5;
      'd04: k_lut <= 32'h3956c25b;
      'd05: k_lut <= 32'h59f111f1;
      'd06: k_lut <= 32'h923f82a4;
      'd07: k_lut <= 32'hab1c5ed5;
      'd08: k_lut <= 32'hd807aa98;
      'd09: k_lut <= 32'h12835b01;
      'd10: k_lut <= 32'h243185be;
      'd11: k_lut <= 32'h550c7dc3;
      'd12: k_lut <= 32'h72be5d74;
      'd13: k_lut <= 32'h80deb1fe;
      'd14: k_lut <= 32'h9bdc06a7;
      'd15: k_lut <= 32'hc19bf174;
      'd16: k_lut <= 32'he49b69c1;
      'd17: k_lut <= 32'hefbe4786;
      'd18: k_lut <= 32'h0fc19dc6;
      'd19: k_lut <= 32'h240ca1cc;
      'd20: k_lut <= 32'h2de92c6f;
      'd21: k_lut <= 32'h4a7484aa;
      'd22: k_lut <= 32'h5cb0a9dc;
      'd23: k_lut <= 32'h76f988da;
      'd24: k_lut <= 32'h983e5152;
      'd25: k_lut <= 32'ha831c66d;
      'd26: k_lut <= 32'hb00327c8;
      'd27: k_lut <= 32'hbf597fc7;
      'd28: k_lut <= 32'hc6e00bf3;
      'd29: k_lut <= 32'hd5a79147;
      'd30: k_lut <= 32'h06ca6351;
      'd31: k_lut <= 32'h14292967;
      'd32: k_lut <= 32'h27b70a85;
      'd33: k_lut <= 32'h2e1b2138;
      'd34: k_lut <= 32'h4d2c6dfc;
      'd35: k_lut <= 32'h53380d13;
      'd36: k_lut <= 32'h650a7354;
      'd37: k_lut <= 32'h766a0abb;
      'd38: k_lut <= 32'h81c2c92e;
      'd39: k_lut <= 32'h92722c85;
      'd40: k_lut <= 32'ha2bfe8a1;
      'd41: k_lut <= 32'ha81a664b;
      'd42: k_lut <= 32'hc24b8b70;
      'd43: k_lut <= 32'hc76c51a3;
      'd44: k_lut <= 32'hd192e819;
      'd45: k_lut <= 32'hd6990624;
      'd46: k_lut <= 32'hf40e3585;
      'd47: k_lut <= 32'h106aa070;
      'd48: k_lut <= 32'h19a4c116;
      'd49: k_lut <= 32'h1e376c08;
      'd50: k_lut <= 32'h2748774c;
      'd51: k_lut <= 32'h34b0bcb5;
      'd52: k_lut <= 32'h391c0cb3;
      'd53: k_lut <= 32'h4ed8aa4a;
      'd54: k_lut <= 32'h5b9cca4f;
      'd55: k_lut <= 32'h682e6ff3;
      'd56: k_lut <= 32'h748f82ee;
      'd57: k_lut <= 32'h78a5636f;
      'd58: k_lut <= 32'h84c87814;
      'd59: k_lut <= 32'h8cc70208;
      'd60: k_lut <= 32'h90befffa;
      'd61: k_lut <= 32'ha4506ceb;
      'd62: k_lut <= 32'hbef9a3f7;
      'd63: k_lut <= 32'hc67178f2;
    endcase
end

endmodule

