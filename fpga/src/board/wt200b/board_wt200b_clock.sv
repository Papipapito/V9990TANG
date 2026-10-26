//
// board_wt200b_clock.sv
//
// BSD 3-Clause License
//
// Copyright (c) 2024, Albert Herranz
//
// Based on board_rev1_clock.sv
// Copyright (c) 2024, Shinobu Hashimoto
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

`default_nettype none

/***********************************************************************
 *
 ***********************************************************************/
// V9990TANG: el rPLL base deja de tener RESET_n = 1'b1 constante y, en sync,
// lock pegajoso en un flop de CLK_IN. Su RESET lo da PLL_RESET y su LOCK sale
// crudo por CLK_BASE_LOCK: el POR, el filtro del LOCK, el detector de perdida
// de enganche y los reintentos estan en BOARD_WT200B_GUARD (dominio CLK_27M),
// que entrega PLL_OK; SYSTEM_RESET lo pasa a CLK_BASE como BASE_READY, que
// vuelve aqui como reset del rPLL TMDS y del CLKDIV de 21 MHz. Los CLKDIV del
// DAC cuelgan del cristal y siguen sin reset (antes RESET_n = 1).
module BOARD_WT200B_CLOCK /* synthesis syn_preserve=1 */ (
    input wire      PLL_RESET,          // reset del rPLL base (BOARD_WT200B_GUARD, CLK_27M)
    input wire      BASE_READY,         // CLK_BASE estable (SYSTEM_RESET, CLK_BASE)
    input wire      CLK_IN,
    input wire      CLK_27M,

    output wire     CLK_BASE,
    output wire     CLK_21M,
    output wire     CLK_DAC,
    output wire     CLK_BASE_LOCK,      // LOCK crudo del rPLL base

    output wire     CLK_MEM,
    output wire     CLK_MEM_P,

    output wire     CLK_TMDS_S,
    output wire     CLK_TMDS_P,
    output wire     CLK_TMDS_READY
);
    /***************************************************************
     * 基本クロック
     ***************************************************************/
    assign CLK_BASE = CLK_MEM;

    /***************************************************************
     * 107.4MHz * 44 / 35 = 134.25MHz
     ***************************************************************/
    assign CLK_TMDS_READY = BASE_READY && lock_135m;
    wire lock_135m;
    rPLL u_pll_tmds (
        .CLKOUT(CLK_TMDS_S),
        .LOCK(lock_135m),
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(!BASE_READY),
        .RESET_P(1'b0),
        .CLKIN(CLK_MEM),
        .CLKFB(1'b0),
        .FBDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .IDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .ODSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .PSDA({1'b0,1'b0,1'b0,1'b0}),
        .DUTYDA({1'b0,1'b0,1'b0,1'b0}),
        .FDLY({1'b0,1'b0,1'b0,1'b0})
    );

    defparam u_pll_tmds.FCLKIN = "107.4";
    defparam u_pll_tmds.DYN_IDIV_SEL = "false";
    defparam u_pll_tmds.IDIV_SEL = 3;
    defparam u_pll_tmds.DYN_FBDIV_SEL = "false";
    defparam u_pll_tmds.FBDIV_SEL = 4;
    defparam u_pll_tmds.DYN_ODIV_SEL = "false";
    defparam u_pll_tmds.ODIV_SEL = 4;
    defparam u_pll_tmds.PSDA_SEL = "0000";
    defparam u_pll_tmds.DYN_DA_EN = "true";
    defparam u_pll_tmds.DUTYDA_SEL = "1000";
    defparam u_pll_tmds.CLKOUT_FT_DIR = 1'b1;
    defparam u_pll_tmds.CLKOUTP_FT_DIR = 1'b1;
    defparam u_pll_tmds.CLKOUT_DLY_STEP = 0;
    defparam u_pll_tmds.CLKOUTP_DLY_STEP = 0;
    defparam u_pll_tmds.CLKFB_SEL = "internal";
    defparam u_pll_tmds.CLKOUT_BYPASS = "false";
    defparam u_pll_tmds.CLKOUTP_BYPASS = "false";
    defparam u_pll_tmds.CLKOUTD_BYPASS = "false";
    defparam u_pll_tmds.DYN_SDIV_SEL = 2;
    defparam u_pll_tmds.CLKOUTD_SRC = "CLKOUT";
    defparam u_pll_tmds.CLKOUTD3_SRC = "CLKOUT";
    defparam u_pll_tmds.DEVICE = "GW2AR-18C";

    /***************************************************************
     * 134.25MHz /5 = 26.85MHz
     ***************************************************************/
    CLKDIV u_div_tmds (
        .CLKOUT(CLK_TMDS_P),
        .HCLKIN(CLK_TMDS_S),
        .RESETN(CLK_TMDS_READY),
        .CALIB(1'b0)
    );
    defparam u_div_tmds.DIV_MODE = "5";
    defparam u_div_tmds.GSREN = "false";

    /***************************************************************
     * 3.58MHz * 30 = 107.4MHz
     ***************************************************************/
    // FCLKIN 3,58, IDIV_SEL 0 (/1), FBDIV_SEL 29 (x30), ODIV_SEL 8:
    // CLKOUT = 3,579545 x 30 = 107,386 MHz, PFD = 3,58 MHz, VCO = CLKOUT x 8
    // = 859 MHz. Limites del GW2AR-18 C8/I7, DS226-2.7E (31/07/2026), tabla
    // 3-20 (los mismos que en la 1.9.1, tabla 4-18): FIN y PFD 3-500 MHz, VCO
    // 500-1250 MHz, CLKOUT 3,906-625 MHz, TLOCKMAX 1 ms; UG286-2.0.2E, tabla
    // 5-3: FCLKIN "3" a "500". Con x30 y ODIV 8 el reloj del slot vale entre
    // 3,0 y 5,2 MHz para el rPLL (el PFD a 3,58 queda un 19 % sobre el
    // minimo); BOARD_WT200B_GUARD solo lo suelta con 3,579545 MHz +-1,5 %.
    // UG286-2.0.2E (nota a la tabla 5-2): si el reloj de entrada cambia o es
    // inestable, el rPLL se resetea cuando vuelva a ser estable (lo hace la
    // guardia). Entrada (misma tabla 3-20): jitter de periodo menor del 20 %
    // del periodo o 1 ns como maximo (a 3,58 MHz manda el 1 ns) y ciclo de
    // trabajo de al menos el 25 % (3-49 MHz). El reloj del slot llega por el
    // pin 76 (GCLKC_1) con enrutado generico (PR1014): los dos limites son
    // criterios de placa del hito 6, sin medir en ninguna maquina.
if(CONFIG_BOARD::SYNC_CPU_CLK) begin
    rPLL u_pll_base (
        .CLKOUT(CLK_MEM),
        .LOCK(CLK_BASE_LOCK),
        .CLKOUTP(CLK_MEM_P),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(PLL_RESET),
        .RESET_P(1'b0),
        .CLKIN(CLK_IN),
        .CLKFB(1'b0),
        .FBDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .IDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .ODSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .PSDA({1'b0,1'b0,1'b0,1'b0}),
        .DUTYDA({1'b0,1'b0,1'b0,1'b0}),
        .FDLY({1'b1,1'b1,1'b1,1'b1})
    );

    defparam u_pll_base.FCLKIN = "3.58";
    defparam u_pll_base.DYN_IDIV_SEL = "false";
    defparam u_pll_base.IDIV_SEL = 0;
    defparam u_pll_base.DYN_FBDIV_SEL = "false";
    defparam u_pll_base.FBDIV_SEL = 29;
    defparam u_pll_base.DYN_ODIV_SEL = "false";
    defparam u_pll_base.ODIV_SEL = 8;
    defparam u_pll_base.PSDA_SEL = "1000";
    defparam u_pll_base.DYN_DA_EN = "false";
    defparam u_pll_base.DUTYDA_SEL = "1000";
    defparam u_pll_base.CLKOUT_FT_DIR = 1'b1;
    defparam u_pll_base.CLKOUTP_FT_DIR = 1'b1;
    defparam u_pll_base.CLKOUT_DLY_STEP = 0;
    defparam u_pll_base.CLKOUTP_DLY_STEP = 0;
    defparam u_pll_base.CLKFB_SEL = "internal";
    defparam u_pll_base.CLKOUT_BYPASS = "false";
    defparam u_pll_base.CLKOUTP_BYPASS = "false";
    defparam u_pll_base.CLKOUTD_BYPASS = "false";
    defparam u_pll_base.DYN_SDIV_SEL = 2;
    defparam u_pll_base.CLKOUTD_SRC = "CLKOUT";
    defparam u_pll_base.CLKOUTD3_SRC = "CLKOUT";
    defparam u_pll_base.DEVICE = "GW2AR-18C";
end
else begin
    // 27 MHz x 4 = 108 MHz: PFD 27 MHz, VCO 864 MHz
    rPLL u_pll_base (
        .CLKOUT(CLK_MEM),
        .LOCK(CLK_BASE_LOCK),
        .CLKOUTP(CLK_MEM_P),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(PLL_RESET),
        .RESET_P(1'b0),
        .CLKIN(CLK_IN),
        .CLKFB(1'b0),
        .FBDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .IDSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .ODSEL({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .PSDA({1'b0,1'b0,1'b0,1'b0}),
        .DUTYDA({1'b0,1'b0,1'b0,1'b0}),
        .FDLY({1'b1,1'b1,1'b1,1'b1})
    );

    defparam u_pll_base.FCLKIN = "27";
    defparam u_pll_base.DYN_IDIV_SEL = "false";
    defparam u_pll_base.IDIV_SEL = 0;
    defparam u_pll_base.DYN_FBDIV_SEL = "false";
    defparam u_pll_base.FBDIV_SEL = 3;
    defparam u_pll_base.DYN_ODIV_SEL = "false";
    defparam u_pll_base.ODIV_SEL = 8;
    defparam u_pll_base.PSDA_SEL = "1000";
    defparam u_pll_base.DYN_DA_EN = "false";
    defparam u_pll_base.DUTYDA_SEL = "1000";
    defparam u_pll_base.CLKOUT_FT_DIR = 1'b1;
    defparam u_pll_base.CLKOUTP_FT_DIR = 1'b1;
    defparam u_pll_base.CLKOUT_DLY_STEP = 0;
    defparam u_pll_base.CLKOUTP_DLY_STEP = 0;
    defparam u_pll_base.CLKFB_SEL = "internal";
    defparam u_pll_base.CLKOUT_BYPASS = "false";
    defparam u_pll_base.CLKOUTP_BYPASS = "false";
    defparam u_pll_base.CLKOUTD_BYPASS = "false";
    defparam u_pll_base.DYN_SDIV_SEL = 2;
    defparam u_pll_base.CLKOUTD_SRC = "CLKOUT";
    defparam u_pll_base.CLKOUTD3_SRC = "CLKOUT";
    defparam u_pll_base.DEVICE = "GW2AR-18C";
end

    /***************************************************************
     * 107.4MHz / 5 = 21.48MHz
     ***************************************************************/
    CLKDIV u_div_21m (
        .CLKOUT(CLK_21M),
        .HCLKIN(CLK_BASE),
        .RESETN(BASE_READY),
        .CALIB(1'b0)
    );
    defparam u_div_21m.DIV_MODE = "5";
    defparam u_div_21m.GSREN = "false";

    /***************************************************************
     * 27MHz / 5 = 5.4MHz
     ***************************************************************/
    wire CLK_5_4M;
    CLKDIV u_div_5p4m (
        .CLKOUT(CLK_5_4M),
        .HCLKIN(CLK_27M),
        .RESETN(1'b1),
        .CALIB(1'b0)
    );
    defparam u_div_5p4m.DIV_MODE = "5";
    defparam u_div_5p4m.GSREN = "false";

    /***************************************************************
     * 5.4MHz / 3.5 = 1542KHz ~ 48KHz * 32 = 1536KHz
     ***************************************************************/
    CLKDIV u_div_dac (
        .CLKOUT(CLK_DAC),
        .HCLKIN(CLK_5_4M),
        .RESETN(1'b1),
        .CALIB(1'b0)
    );
    defparam u_div_dac.DIV_MODE = "3.5";
    defparam u_div_dac.GSREN = "false";

endmodule

`default_nettype wire
