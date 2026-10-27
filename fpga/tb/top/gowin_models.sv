// ============================================================================
// gowin_models.sv -- modelos de comportamiento de las primitivas de Gowin que
// usa el top de V9990TANG, para el banco de placa entera (tb_top, Verilator
// 5.020 con --timing). Solo simulacion: no entra en ninguna build ni cambia
// el RTL (el RTL instancia rPLL, CLKDIV y DPB como en Gowin; el banco compila
// estos modulos en lugar del prim_sim.v de Gowin, que Verilator no admite).
//
//   rPLL   multiplicador enganchado en fase: cada (IDIV_SEL + 1) flancos de
//          subida de CLKIN mide el tramo y saca (FBDIV_SEL + 1) periodos de
//          CLKOUT repartidos en el; CLKOUTP, el mismo tren retrasado PSDA_SEL/16
//          de periodo (PSDA_SEL "1000" = 180 grados, el reloj de la SDRAM; con
//          un "<= #retardo" variable Verilator 5.020 no retrasa nada). LOCK
//          sube LOCK_BEATS tramos despues de soltar RESET con el periodo de
//          entrada estable (+-1 %) y cae con RESET, con un salto de periodo o
//          si CLKIN se para (y CLKOUT se para con el: el VCO real seguiria
//          libre, pero sin LOCK nadie lo usa). ODIV_SEL, FDLY, DUTYDA y los
//          divisores dinamicos no se modelan (los del top son estaticos).
//   CLKDIV divisor por DIV_MODE ("2", "3.5", "4", "5", "8") contando medios
//          periodos de HCLKIN (por eso admite 3,5); RESETN a 0 lo para a 0.
//   DPB    BSRAM de doble puerto de 16 kbit, anchuras 4, 8 y 16 (iguales en
//          los dos puertos, como en el core, el SCC y el upscan), lectura en
//          bypass (READ_MODE 0: el dato sale en el flanco siguiente), escritura
//          normal (WRITE_MODE 00: DO no cambia en un ciclo de escritura),
//          reset sincrono del registro de salida, x16 con AD[1:0] de
//          habilitacion de bytes (Gowin UG285). Une los modelos de
//          tb/bus/dpb_sim.sv, tb/core/tb_dpb_model.v, tb/megaram/dpb_model.sv
//          y tb/video/sim/dpb_sim.sv (este, comparado con el prim_sim.v de
//          Gowin 1.9.12.03).
//
// El DVI_TX_Top cifrado se sustituye por tb/video/sim/dvi_tx_stub.sv: el banco
// mira lo que BOARD_REV1_TMDS_OUT le entrega.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module rPLL #(
    parameter FCLKIN            = "100.0",
    parameter DYN_IDIV_SEL      = "false",
    parameter IDIV_SEL          = 0,
    parameter DYN_FBDIV_SEL     = "false",
    parameter FBDIV_SEL         = 0,
    parameter DYN_ODIV_SEL      = "false",
    parameter ODIV_SEL          = 8,
    parameter PSDA_SEL          = "0000",
    parameter DYN_DA_EN         = "false",
    parameter DUTYDA_SEL        = "1000",
    parameter CLKOUT_FT_DIR     = 1'b1,
    parameter CLKOUTP_FT_DIR    = 1'b1,
    parameter CLKOUT_DLY_STEP   = 0,
    parameter CLKOUTP_DLY_STEP  = 0,
    parameter CLKFB_SEL         = "internal",
    parameter CLKOUT_BYPASS     = "false",
    parameter CLKOUTP_BYPASS    = "false",
    parameter CLKOUTD_BYPASS    = "false",
    parameter DYN_SDIV_SEL      = 2,
    parameter CLKOUTD_SRC       = "CLKOUT",
    parameter CLKOUTD3_SRC      = "CLKOUT",
    parameter DEVICE            = "GW2A-18",
    parameter LOCK_BEATS        = 64            // tramos estables hasta LOCK (solo del modelo)
) (
    output reg          CLKOUT,
    output reg          LOCK,
    output reg          CLKOUTP,
    output wire         CLKOUTD,
    output wire         CLKOUTD3,
    input  wire         RESET,
    input  wire         RESET_P,
    input  wire         CLKIN,
    input  wire         CLKFB,
    input  wire [5:0]   FBDSEL,
    input  wire [5:0]   IDSEL,
    input  wire [5:0]   ODSEL,
    input  wire [3:0]   PSDA,
    input  wire [3:0]   DUTYDA,
    input  wire [3:0]   FDLY
);
    localparam int MUL  = FBDIV_SEL + 1;
    localparam int DIVI = IDIV_SEL + 1;
    // PSDA_SEL es una cadena de cuatro '0'/'1': bit = bit 0 de cada caracter
    localparam int PSDA_V = {PSDA_SEL[24], PSDA_SEL[16], PSDA_SEL[8], PSDA_SEL[0]};

    assign CLKOUTD  = 1'b0;
    assign CLKOUTD3 = 1'b0;

    initial begin
        CLKOUT  = 1'b0;
        CLKOUTP = 1'b0;
        LOCK    = 1'b0;
    end

    realtime t_beat = 0.0, t_edge = 0.0;
    realtime span = 0.0, span_prev = 0.0;
    int      n_in = 0;          // flancos de CLKIN en el tramo
    int      n_stable = 0;      // tramos seguidos con el periodo estable
    int      gen = 0;           // generacion del tren de salida en curso
    bit      have_beat = 1'b0;
    real     tout = 0.0;        // periodo de salida

    // tren de MUL periodos de salida en un tramo de duracion sp, que empieza
    // off despues del flanco de entrada (CLKOUTP: la fase de PSDA_SEL). Antes de
    // cada flanco de subida mira si sigue siendo el tren en curso (g == gen);
    // la bajada la da siempre, para no dejar la salida a 1 si el tramo
    // siguiente llega un poco antes
    task automatic burst(input int g, input realtime sp, input bit p, input realtime off);
        realtime h;
        h = sp / (2.0 * MUL);
        if (off > 0.0) #(off);
        for (int i = 0; i < MUL; i++) begin
            if (g != gen || RESET) return;
            if (p) CLKOUTP = 1'b1; else CLKOUT = 1'b1;
            #(h);
            if (p) CLKOUTP = 1'b0; else CLKOUT = 1'b0;
            #(h);
        end
    endtask

    always @(posedge CLKIN or posedge RESET) begin
        if (RESET) begin
            LOCK = 1'b0;
            gen = gen + 1;
            CLKOUT = 1'b0;
            CLKOUTP = 1'b0;
            n_in = 0; n_stable = 0; have_beat = 1'b0;
        end
        else begin
            t_edge = $realtime;
            if (!have_beat) begin
                have_beat = 1'b1;
                t_beat = $realtime;
                n_in = 0;
            end
            else begin
                n_in = n_in + 1;
                if (n_in == DIVI) begin
                    span_prev = span;
                    span = $realtime - t_beat;
                    t_beat = $realtime;
                    n_in = 0;
                    if (span_prev > 0.0 && (span > span_prev * 1.01 || span < span_prev * 0.99)) begin
                        n_stable = 0;
                        LOCK = 1'b0;
                    end
                    else if (n_stable < LOCK_BEATS) n_stable = n_stable + 1;
                    else LOCK = 1'b1;
                    tout = span / MUL;
                    gen = gen + 1;
                    fork
                        burst(gen, span, 1'b0, 0.0);
                        burst(gen, span, 1'b1, (PSDA_V == 0) ? 0.0 : span / MUL * PSDA_V / 16.0);
                    join_none
                end
            end
        end
    end

    // CLKIN parado: sin LOCK y sin salida
    initial begin
        forever begin
            #(50.0);
            if (have_beat && span > 0.0 && ($realtime - t_edge) > 3.0 * span / DIVI) begin
                LOCK = 1'b0;
                n_stable = 0;
                have_beat = 1'b0;
                span = 0.0;
                gen = gen + 1;
                CLKOUT = 1'b0;
                CLKOUTP = 1'b0;
            end
        end
    end

endmodule

module CLKDIV #(
    parameter DIV_MODE  = "2",
    parameter GSREN     = "false"
) (
    output reg          CLKOUT,
    input  wire         HCLKIN,
    input  wire         RESETN,
    input  wire         CALIB
);
    // medios periodos de HCLKIN por periodo de salida
    localparam int HALVES = (DIV_MODE == "2")   ? 4  :
                            (DIV_MODE == "3.5") ? 7  :
                            (DIV_MODE == "4")   ? 8  :
                            (DIV_MODE == "5")   ? 10 :
                            (DIV_MODE == "8")   ? 16 : 0;
    initial begin
        CLKOUT = 1'b0;
        if (HALVES == 0) $fatal(1, "CLKDIV: DIV_MODE no modelado");
    end
    int hc = 0;
    always @(HCLKIN or negedge RESETN) begin
        if (!RESETN) begin
            hc = 0;
            CLKOUT = 1'b0;
        end
        else if (HCLKIN) begin
            // la salida sube con un flanco de subida de HCLKIN
            if (hc == 0) CLKOUT = 1'b1;
            if (hc == HALVES / 2) CLKOUT = 1'b0;
            hc = (hc + 1) % HALVES;
        end
        else begin
            if (hc == HALVES / 2) CLKOUT = 1'b0;
            hc = (hc + 1) % HALVES;
        end
    end
endmodule

// MULT18X18 (DSP): solo lo que usa ATT_CONST de attenuator.sv: registros de
// entrada (AREG/BREG) y de salida (OUT_REG), sin PIPE_REG, signo fijo por los
// puertos ASIGN/BSIGN, reset sincrono, SOA/SOB/SIA/SIB/ASEL/BSEL sin uso
module MULT18X18 #(
    parameter AREG            = 1'b0,
    parameter BREG            = 1'b0,
    parameter OUT_REG         = 1'b0,
    parameter PIPE_REG        = 1'b0,
    parameter ASIGN_REG       = 1'b0,
    parameter BSIGN_REG       = 1'b0,
    parameter SOA_REG         = 1'b0,
    parameter MULT_RESET_MODE = "SYNC"
) (
    output wire [35:0]  DOUT,
    output wire [17:0]  SOA,
    output wire [17:0]  SOB,
    input  wire [17:0]  A,
    input  wire [17:0]  B,
    input  wire         ASIGN,
    input  wire         BSIGN,
    input  wire [17:0]  SIA,
    input  wire [17:0]  SIB,
    input  wire         CE,
    input  wire         CLK,
    input  wire         RESET,
    input  wire         ASEL,
    input  wire         BSEL
);
    initial if (PIPE_REG != 1'b0) $fatal(1, "MULT18X18 (modelo del banco): PIPE_REG no modelado");
    logic [17:0] a_r = '0, b_r = '0;
    logic [35:0] o_r = '0;
    always @(posedge CLK) begin
        if (RESET) begin a_r <= '0; b_r <= '0; end
        else if (CE) begin a_r <= A; b_r <= B; end
    end
    wire [17:0] a_v = AREG ? a_r : A;
    wire [17:0] b_v = BREG ? b_r : B;
    wire signed [18:0] a_s = ASIGN ? {a_v[17], a_v} : {1'b0, a_v};
    wire signed [18:0] b_s = BSIGN ? {b_v[17], b_v} : {1'b0, b_v};
    wire signed [37:0] prod = a_s * b_s;
    always @(posedge CLK) begin
        if (RESET) o_r <= '0;
        else if (CE) o_r <= prod[35:0];
    end
    assign DOUT = OUT_REG ? o_r : prod[35:0];
    assign SOA = 18'd0;
    assign SOB = 18'd0;
endmodule

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
    output reg  [15:0]  DOA,
    output reg  [15:0]  DOB,
    input  wire         CLKA,
    input  wire         OCEA,
    input  wire         CEA,
    input  wire         RESETA,
    input  wire         WREA,
    input  wire         CLKB,
    input  wire         OCEB,
    input  wire         CEB,
    input  wire         RESETB,
    input  wire         WREB,
    input  wire [2:0]   BLKSELA,
    input  wire [2:0]   BLKSELB,
    input  wire [13:0]  ADA,
    input  wire [15:0]  DIA,
    input  wire [13:0]  ADB,
    input  wire [15:0]  DIB
);
    // 16 kbit en 4096 cuartetos: x4 -> AD[13:2], x8 -> AD[13:3] (2 cuartetos),
    // x16 -> AD[13:4] (4 cuartetos, AD[0]/AD[1] habilitan el byte bajo/alto)
    reg [3:0] mem [0:4095];
    initial begin
        for (int i = 0; i < 4096; i++) mem[i] = 4'h0;
        DOA = 16'h0000;
        DOB = 16'h0000;
        if (BIT_WIDTH_0 != BIT_WIDTH_1 || !(BIT_WIDTH_0 == 4 || BIT_WIDTH_0 == 8 || BIT_WIDTH_0 == 16) ||
            READ_MODE0 != 1'b0 || READ_MODE1 != 1'b0 || WRITE_MODE0 != 2'b00 || WRITE_MODE1 != 2'b00)
            $fatal(1, "DPB (modelo del banco): configuracion no modelada");
    end
    localparam int W = BIT_WIDTH_0;

    function automatic [11:0] base(input [13:0] ad);
        if (W == 16)     base = {ad[13:4], 2'b00};
        else if (W == 8) base = {ad[13:3], 1'b0};
        else             base = ad[13:2];
    endfunction
    function automatic [15:0] rd(input [13:0] ad);
        logic [11:0] b;
        b = base(ad);
        if (W == 16)     rd = {mem[b + 3], mem[b + 2], mem[b + 1], mem[b]};
        else if (W == 8) rd = {8'h00, mem[b + 1], mem[b]};
        else             rd = {12'h000, mem[b]};
    endfunction

    always @(posedge CLKA) begin
        if (CEA && BLKSELA == BLK_SEL_0 && WREA) begin
            if (W == 16) begin
                if (ADA[0]) begin mem[base(ADA)] <= DIA[3:0];  mem[base(ADA) + 1] <= DIA[7:4];   end
                if (ADA[1]) begin mem[base(ADA) + 2] <= DIA[11:8]; mem[base(ADA) + 3] <= DIA[15:12]; end
            end
            else if (W == 8) begin mem[base(ADA)] <= DIA[3:0]; mem[base(ADA) + 1] <= DIA[7:4]; end
            else mem[base(ADA)] <= DIA[3:0];
        end
        if (RESETA) DOA <= 16'h0000;
        else if (CEA && BLKSELA == BLK_SEL_0 && !WREA) DOA <= rd(ADA);
    end

    always @(posedge CLKB) begin
        if (CEB && BLKSELB == BLK_SEL_1 && WREB) begin
            if (W == 16) begin
                if (ADB[0]) begin mem[base(ADB)] <= DIB[3:0];  mem[base(ADB) + 1] <= DIB[7:4];   end
                if (ADB[1]) begin mem[base(ADB) + 2] <= DIB[11:8]; mem[base(ADB) + 3] <= DIB[15:12]; end
            end
            else if (W == 8) begin mem[base(ADB)] <= DIB[3:0]; mem[base(ADB) + 1] <= DIB[7:4]; end
            else mem[base(ADB)] <= DIB[3:0];
        end
        if (RESETB) DOB <= 16'h0000;
        else if (CEB && BLKSELB == BLK_SEL_1 && !WREB) DOB <= rd(ADB);
    end
endmodule

// Subranura vacia del EXPANSION_SLOT de main.sv: lo mismo que
// BUS_IF.connect_dummy(), que Verilator 5.020 no resuelve sobre ExpBus[n]
// dentro de una rama de generate (filelist.py cambia esas llamadas por este
// modulo en la copia de main.sv; tb/bus/tb_bus.sv hace lo mismo)
module TBTOP_BUS_DUMMY (BUS_IF.CARTRIDGE Bus);
    assign Bus.DOUT     = 8'h00;
    assign Bus.BUSDIR_n = 1'b1;
    assign Bus.INT_n    = 1'b1;
    assign Bus.WAIT_n   = 1'b1;
endmodule

`default_nettype wire
