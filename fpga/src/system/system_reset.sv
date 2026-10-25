//
// system_reset.sv -- V9990TANG
//
// BSD 3-Clause License
//
// Copyright (c) 2026, Papipapito
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

//
// Cadena de reset en CLK_BASE. Sustituye al gateo de tnCart, en el que el
// BOOT_n del bootloader retenia SYS_RESET_n:
//
//   PLL_OK (guardia, CLK_27M) --2 FF--> BASE_READY  (reset de la SDRAM y del rPLL TMDS)
//   BASE_READY y READY de la SDRAM ----> RESET_n     (reset de la carcasa: reset_n)
//   RESET_n y !HOLD (main.sv) ---------> SYS_RESET_n (reset de los cartuchos)
//
// Todas las afirmaciones son asincronas (funcionan con CLK_BASE parado) y
// todas las sueltas, sincronas a CLK_BASE. SYS_RESET_n se suelta como pronto un
// ciclo despues que RESET_n: en el flanco en que sube RESET_n los cartuchos
// siguen en reset (el V9990 con DCLK_EN a 0), que es lo que hace seguro el
// false path de reset_n hacia DCLK del .sdc.
//

`default_nettype none

module SYSTEM_RESET (
    input  wire     CLK,            // CLK_BASE
    input  wire     PLL_OK,         // rPLL base enganchado (BOARD_WT200B_GUARD, dominio CLK_27M)
    input  wire     SDRAM_READY,    // READY de sdram.sv (CLK_BASE)
    output wire     BASE_READY,     // PLL_OK en CLK_BASE
    output wire     RESET_n         // reset de la carcasa
);
    reg [1:0] base_ff = 2'b00;
    always_ff @(posedge CLK or negedge PLL_OK) begin
        if(!PLL_OK) base_ff <= 2'b00;
        else        base_ff <= { base_ff[0], 1'b1 };
    end
    assign BASE_READY = base_ff[1];

    // el nombre reset_n se conserva: el .sdc lo nombra (reset_n_s0)
    reg reset_n = 1'b0;
    always_ff @(posedge CLK or negedge BASE_READY or negedge SDRAM_READY) begin
        if(!BASE_READY)       reset_n <= 1'b0;   // PLL sin enganchar
        else if(!SDRAM_READY) reset_n <= 1'b0;   // SDRAM iniciandose
        else                  reset_n <= 1'b1;
    end
    assign RESET_n = reset_n;
endmodule

/***************************************************************
 * SYS_RESET_n: RESET_n retenido mientras HOLD
 ***************************************************************/
module SYSTEM_RESET_HOLD (
    input  wire     CLK,
    input  wire     RESET_n,
    input  wire     HOLD,           // 1 = retener (p. ej. el borrado de la megaROM sin acabar)
    output reg      SYS_RESET_n
);
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) SYS_RESET_n <= 1'b0;
        else         SYS_RESET_n <= !HOLD;
    end
endmodule

`default_nettype wire
