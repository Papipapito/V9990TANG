//
// board_wt200b_config_sync.sv
//
// BSD 3-Clause License
//
// Copyright (c) 2024, Albert Herranz
//
// Based on board_wt102d_config.sv
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

//
// V9990TANG: variante sync (CLK_BASE = reloj del slot x 30 = 107,386 MHz; el
// rPLL base engancha al CART_CLOCK del MSX, como en las placas rev1/rev2 de
// tnCart). Igual que board_wt200b_config_xtal.sv salvo SYNC_CPU_CLK = 1; la
// variante xtal es board_wt200b_config_xtal.sv. Cada build_*.tcl
// compila uno de los dos con su .sdc (fpga/constraints/).
//
// SYNC_CPU_UMA = 0 en las dos variantes, como en la rev1 de buppu3: el UMA
// corre libre con DIV = 30. La alternativa 2 de uma.sv ("最初に同期": se
// engancha a Bus.CLK_EN una sola vez, en el primer flanco del reloj del slot
// tras el reset, y despues corre libre) fijaria la fase entre el Z80 y las
// ranuras de la SDRAM en cada arranque; solo tiene sentido en sync (en xtal la
// fase deriva igual) y queda para cuando se mida la MegaRAM sin WAIT con
// osciloscopio (estudio, seccion 10). La 1 reinicia la cuenta en cada flanco
// del reloj del slot (Bus.CLK_EN, que sale del PIN_FILTER con su jitter de un
// ciclo); en xtal la recortaria o la pararia en cada ciclo del Z80. No se usa.
//

`default_nettype none

package CONFIG_BOARD;
    localparam          BOARD_ID                = BOARD_ID::WonderTANG_200b;

    localparam          SYNC_CPU_CLK            = 1;                // 動作クロックを CPU クロックと同期するか(1=同期/0=非同期)
    localparam          SYNC_CPU_UMA            = 0;                // UMA 動作を CPU クロックと同期するか(1=同期/0=非同期)
    localparam          DAC_BIT_WIDTH           = 10;               // DAC 出力の量子化ビット数
    localparam          DAC_FREQ_DIV            = 5;                // DAC 標本化周波数の分周比
    localparam          TF_CLK_DIV              = 2;                // TF 通信クロック分周比
    localparam          FLASH_CLK_DIV           = 2;                // フラッシュ 通信クロック分周比
    localparam          ENABLE_UART_MODULE      = 0;                // UART モジュールを有効(0=無効/1=有効)
endpackage

`default_nettype wire
