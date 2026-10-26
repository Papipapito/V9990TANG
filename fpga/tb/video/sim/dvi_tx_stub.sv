//
// dvi_tx_stub.sv -- sustituto de simulacion del IP cifrado DVI_TX_Top de Gowin
//
// dvi_tx.v viene cifrado (pragma protect) y no se puede simular: el banco
// mira lo que BOARD_REV1_TMDS_OUT le entrega (I_rgb_*), que es lo que
// serializa el IP. Las salidas TMDS quedan a 0.
//
`default_nettype none
module DVI_TX_Top (
    input  wire       I_rst_n,
    input  wire       I_serial_clk,
    input  wire       I_rgb_clk,
    input  wire       I_rgb_vs,
    input  wire       I_rgb_hs,
    input  wire       I_rgb_de,
    input  wire [7:0] I_rgb_r,
    input  wire [7:0] I_rgb_g,
    input  wire [7:0] I_rgb_b,
    output wire       O_tmds_clk_p,
    output wire       O_tmds_clk_n,
    output wire [2:0] O_tmds_data_p,
    output wire [2:0] O_tmds_data_n
);
    assign O_tmds_clk_p  = 1'b0;
    assign O_tmds_clk_n  = 1'b1;
    assign O_tmds_data_p = 3'b000;
    assign O_tmds_data_n = 3'b111;
endmodule
`default_nettype wire
