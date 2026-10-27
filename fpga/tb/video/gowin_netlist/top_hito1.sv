//
// top_hito1.sv -- un VIDEO_UPSCAN_STRETCH_BUFFER del hito 1 (sin parametro BLEND) con todos sus puertos a
// pines, para sintetizarlo con Gowin y simular su netlist frente al RTL.
//
`default_nettype none
module NL_TOP (
    input  wire       RESET_n,
    input  wire [2:0] IN_RESOLUTION,
    input  wire       IN_CLK,
    input  wire       IN_EN,
    input  wire       IN_START,
    input  wire [1:0] IN_LINE,
    input  wire [7:0] IN,
    input  wire       OUT_CLK,
    input  wire       OUT_EN,
    input  wire       OUT_START,
    input  wire [1:0] OUT_LINE,
    output wire [7:0] OUT
);
    VIDEO_UPSCAN_STRETCH_BUFFER #(.ROW_COUNT(3)) u_buf (
        .RESET_n, .CLEAR(1'b0),
        .IN_RESOLUTION(VIDEO::RESOLUTION_t'(IN_RESOLUTION)),
        .IN_CLK, .IN_EN, .IN_START, .IN_LINE, .IN,
        .OUT_CLK, .OUT_EN, .OUT_START, .OUT_LINE, .OUT
    );
endmodule
`default_nettype wire
