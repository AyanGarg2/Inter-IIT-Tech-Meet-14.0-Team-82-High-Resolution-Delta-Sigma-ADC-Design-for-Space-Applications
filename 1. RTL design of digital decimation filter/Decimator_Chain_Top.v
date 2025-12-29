module Decimator_Chain_Top (
    input  wire clk, reset, clk_enable,
    input  wire [1:0] filter_in,
    output wire [21:0] filter_out, ce_out
);

  wire [57:0] w_cic_out; wire w_cic_ce;
  wire [21:0] w_cic_scaled;
  wire [21:0] w_hb1_out; wire w_hb1_ce;
  wire [21:0] w_hb2_out; wire w_hb2_ce;
  wire [21:0] w_hb3_out; wire w_hb3_ce;

  Stage1_CIC u_cic (.clk(clk), .reset(reset), .clk_enable(clk_enable), .filter_in(filter_in), .filter_out(w_cic_out), .ce_out(w_cic_ce));
  assign w_cic_scaled = w_cic_out[57:36]; // Shift for 22-bit

  Stage2_HB1 u_hb1 (.clk(clk), .reset(reset), .clk_enable(w_cic_ce), .filter_in(w_cic_scaled), .filter_out(w_hb1_out), .ce_out(w_hb1_ce));
  Stage3_HB2 u_hb2 (.clk(clk), .reset(reset), .clk_enable(w_hb1_ce), .filter_in(w_hb1_out), .filter_out(w_hb2_out), .ce_out(w_hb2_ce));
  Stage4_HB3 u_hb3 (.clk(clk), .reset(reset), .clk_enable(w_hb2_ce), .filter_in(w_hb2_out), .filter_out(w_hb3_out), .ce_out(w_hb3_ce));
  Stage5_FIR u_fir (.clk(clk), .reset(reset), .clk_enable(w_hb3_ce), .filter_in(w_hb3_out), .filter_out(filter_out), .ce_out(ce_out));
endmodule
