//
// dpb_sim.sv -- modelo de simulacion del primitivo DPB de Gowin (GW2A)
//
// Solo el subconjunto que usa VIDEO_UPSCAN_BUFFER: puerto A de lectura y
// puerto B de escritura, READ_MODE = 0 (bypass: DOA es el registro de salida
// cargado en el flanco de CLKA con la palabra de ADA), WRITE_MODE = 0,
// BIT_WIDTH 4 u 8 iguales en los dos puertos, BLKSEL = 0, sin reset de salida.
// Comportamiento sacado de simlib/gw2a/prim_sim.v de Gowin 1.9.12.03
// (module DPB); tb_dpb_vs_gowin.v lo compara con ese modelo en Icarus.
// Solo para simulacion: no forma parte de ninguna build.
//
`default_nettype none
module DPB #(
    parameter READ_MODE0  = 1'b0,
    parameter READ_MODE1  = 1'b0,
    parameter WRITE_MODE0 = 2'b00,
    parameter WRITE_MODE1 = 2'b00,
    parameter BIT_WIDTH_0 = 16,
    parameter BIT_WIDTH_1 = 16,
    parameter BLK_SEL_0   = 3'b000,
    parameter BLK_SEL_1   = 3'b000,
    parameter RESET_MODE  = "SYNC"
) (
    output wire [15:0] DOA,
    output wire [15:0] DOB,
    input  wire [15:0] DIA,
    input  wire [15:0] DIB,
    input  wire [2:0]  BLKSELA,
    input  wire [2:0]  BLKSELB,
    input  wire [13:0] ADA,
    input  wire [13:0] ADB,
    input  wire        WREA,
    input  wire        WREB,
    input  wire        CLKA,
    input  wire        CLKB,
    input  wire        CEA,
    input  wire        CEB,
    input  wire        OCEA,
    input  wire        OCEB,
    input  wire        RESETA,
    input  wire        RESETB
);
    localparam W  = BIT_WIDTH_0;
    localparam AW = (W == 8) ? 11 : (W == 4) ? 12 : (W == 2) ? 13 : (W == 1) ? 14 : 10;
    localparam LSB = 14 - AW;

    logic [W-1:0] mem [0:(1<<AW)-1];
    logic [W-1:0] doa;

    initial begin
        for (int i = 0; i < (1<<AW); i++) mem[i] = '0;
        doa = '0;
    end

    // puerto B: escritura
    always @(posedge CLKB) begin
        if (CEB && (BLKSELB == BLK_SEL_1) && WREB)
            mem[ADB[13:LSB]] <= DIB[W-1:0];
    end

    // puerto A: lectura en bypass (un ciclo de latencia)
    always @(posedge CLKA) begin
        if (CEA && (BLKSELA == BLK_SEL_0) && !WREA)
            doa <= mem[ADA[13:LSB]];
    end

    assign DOA = {{(16-W){1'b0}}, doa};
    assign DOB = '0;

    initial begin
        if (READ_MODE0 != 1'b0 || WRITE_MODE1 != 2'b00 || BIT_WIDTH_0 != BIT_WIDTH_1 || !(W == 4 || W == 8))
            $fatal(1, "dpb_sim: configuracion no modelada");
    end
endmodule
`default_nettype wire
