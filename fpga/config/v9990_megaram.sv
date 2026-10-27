//
// config.sv
//
// BSD 3-Clause License
// 
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
// V9990TANG: configuracion v9990_megaram (hito 8 del estudio): la de
// config/v9990.sv mas la megaROM de tnCart arrancando como Konami SCC-I RAM
// (ENABLE_MEGA_SCC_I) con su SCC, ventana de 4 MB en 00_0000h de la SDRAM,
// modo plano en 0000h y /WAIT en las lecturas de memoria (ENABLE_MEM_WAIT).
// Cambios frente a config/v9990.sv:
//   - RAM_ADDR_MEGAROM 40_0000h -> 00_0000h y RAM_SIZE_MEGAROM 3 MB -> 4 MB
//     (00_0000h-3F_FFFFh; la VRAM sigue en 78_0000h).
//   - RAM_ADDR_RAM 00_0000h -> 40_0000h: el mapper esta desactivado, pero el
//     BOOTLOADER de tnCart borra 64 KB en RAM_ADDR_RAM al arrancar; asi ese
//     borrado (si alguien compila esta configuracion con el bootloader) no
//     pisa los 32 KB de FFh del principio de la ventana de la megaROM.
//   - ENABLE_MEGAROM = ENABLE_MEGA_SCC_I, ENABLE_SCC = ENABLE.
//   - ENABLE_MEM_WAIT = 1 (nuevo; lo lee cartridge_megarom.sv).
// Ver docs/notas/megaram.md.
//

`default_nettype none

/***********************************************************************************
 * メイン設定
 ***********************************************************************************/
package CONFIG;
    /***************************************************************
     * 機能に指定する定数
     ***************************************************************/
    localparam DISABLE          = 0;            // 機能の無効
    localparam ENABLE           = 1;            // 機能の有効
    localparam ENABLE_VM2413    = 1;            // 機能の有効(VM2413)
    localparam ENABLE_IKAOPLL   = 2;            // 機能の有効(IKAOPLL)
    localparam ENABLE_IKASCC    = 2;            // 機能の有効(IKASCC)
    localparam ENABLE_MEGA_SCC  = 2;            // 機能の有効(電源ON で SCC を有効)
    localparam ENABLE_MEGA_SCC_I= 3;            // 機能の有効(電源ON で SCC-I を有効)

    /***************************************************************
     * フラッシュメモリマップ
     *  00_0000 +-------------------+
     *          | bit stream(1MB)   |
     *  10_0000 +-------------------+
     *          | NEXTOR(128KB)     |
     *  12_0000 +-------------------+
     *          | FM-BIOS(16KB)     |
     *  12_4000 +-------------------+
     *          | (816KB)           |
     *  1F_0000 +-------------------+
     *          | PAC(64KB)         | (予定)
     *  20_0000 +-------------------+
     *          | MEGA ROM (2MB)    | (FLASHからMEGAROMをブートするときに使う予定)
     *  40_0000 +-------------------+
     ***************************************************************/
    localparam [23:0]   FLASH_ADDR_MEGAROM      = 24'h20_0000;
    localparam [23:0]   FLASH_SIZE_MEGAROM      = 24'h20_0000;
    localparam [23:0]   FLASH_ADDR_BIOS         = 24'h10_0000;
    localparam [23:0]   FLASH_SIZE_BIOS         = (FLASH_SIZE_BIOS_NEXTOR + FLASH_SIZE_BIOS_FM);
    localparam [23:0]   FLASH_SIZE_BIOS_NEXTOR  = 24'h02_0000;
    localparam [23:0]   FLASH_SIZE_BIOS_FM      = 24'h00_4000;
    localparam [23:0]   FLASH_ADDR_PAC          = 24'h1F_0000;
    localparam [23:0]   FLASH_SIZE_PAC          = 24'h01_0000;

    /***************************************************************
     * SD-RAM メモリマップ (V9990TANG v9990_megaram)
     *  00_0000 +-------------------+
     *          | MEGA ROM(4MB)     | 16K x 256 bancos / 8K x 256 = 2 MB
     *  40_0000 +-------------------+
     *          | (MEM MAPPER: sin  | RAM_ADDR_RAM (mapper desactivado)
     *          |  usar, 3MB)       |
     *  70_0000 +-------------------+
     *          | NEXTOR(128KB)     |
     *  72_0000 +-------------------+
     *          | FM-BIOS(16KB)     |
     *  72_4000 +-------------------+
     *          | (360KB)           |
     *  77_E000 +-------------------+
     *          | PAC(8KB)          |
     *  78_0000 +-------------------+
     *          | VRAM(512KB)       |
     *  80_0000 +-------------------+
     ***************************************************************/
    localparam [23:0]   RAM_ADDR_RAM            = 24'h40_0000;
    localparam [23:0]   RAM_SIZE_RAM            = 24'h30_0000;
    localparam [23:0]   RAM_ADDR_MEGAROM        = 24'h00_0000;
    localparam [23:0]   RAM_SIZE_MEGAROM        = 24'h40_0000;
    localparam [23:0]   RAM_ADDR_BIOS           = 24'h70_0000;
    localparam [23:0]   RAM_ADDR_BIOS_NEXTOR    = RAM_ADDR_BIOS;
    localparam [23:0]   RAM_ADDR_BIOS_FM        = (RAM_ADDR_BIOS_NEXTOR + FLASH_SIZE_BIOS_NEXTOR);
    localparam [23:0]   RAM_ADDR_PAC            = 24'h77_E000;
    localparam [23:0]   RAM_ADDR_VRAM           = 24'h78_0000;

    /***************************************************************
     * アッテネータ
     ***************************************************************/
    // 3.5mm ジャック
    localparam          ATT_EXT_PSG_MUL         = 1;
    localparam          ATT_EXT_PSG_DIV         = 1;
    localparam          ATT_EXT_FM_MUL          = 1;
    localparam          ATT_EXT_FM_DIV          = 1;
    localparam          ATT_EXT_MEGAROM_MUL     = 1;
    localparam          ATT_EXT_MEGAROM_DIV     = 1;

    // MSX 本体側
    localparam          ATT_INT_FM_MUL          = 9;
    localparam          ATT_INT_FM_DIV          = 4;
    localparam          ATT_INT_MEGAROM_MUL     = 9;
    localparam          ATT_INT_MEGAROM_DIV     = 4;

    /***************************************************************
     * 機能
     ***************************************************************/
    localparam          ENABLE_MEGAROM          = ENABLE_MEGA_SCC_I;         // メガロムカートリッジを有効にするか(DISABLE/ENABLE/ENABLE_MEGA_SCC/ENABLE_MEGA_SCC_I)
    localparam          ENABLE_FM               = DISABLE;          // FM 音源カートリッジを有効にするか(DISABLE/ENABLE_VM2413/ENABLE_IKAOPLL)
    localparam          ENABLE_NEXTOR           = DISABLE;           // NEXTOR カートリッジを有効にするか(DISABLE/ENABLE)
    localparam          ENABLE_RAM              = DISABLE;           // 拡張 RAM カートリッジを有効にするか(DISABLE/ENABLE)
    localparam          ENABLE_PSG              = DISABLE;           // PSG を有効にするか(DISABLE/ENABLE)
    localparam          ENABLE_SCC              = ENABLE;            // SCC を有効にするか(DISABLE/ENABLE/ENABLE_IKASCC)
    localparam          ENABLE_V9990            = ENABLE;           // V9990 を有効にするか(DISABLE/ENABLE)
    localparam          ENABLE_V9990_CMD        = ENABLE;           // V9990 の VDP コマンドを有効(V9990のVDPコマンドを有効にすると回路の規模が大きくなるので、他の大きな機能と同時使用はできない)
    localparam          ENABLE_PAC_WRITE        = DISABLE;           // PAC データを FLASH に保存するか(DISABLE/ENABLE)
    localparam          ENABLE_SCANLINE         = DISABLE;          // 200ラインモード時に走査線の隙間を空ける

    localparam          ENABLE_DAC_I2S          = DISABLE;          // I2S DAC を使用するか(DISABLE/ENABLE)
    localparam          ENABLE_DAC_STEREO       = DISABLE;          // ステレオ出力を有効にするか(DISABLE/ENABLE)

    // V9990TANG: /WAIT en las lecturas de memoria de la megaROM (hito 8b).
    // 1 = megarom_controller.sv baja Bus.WAIT_n en cada lectura de la ventana
    // hasta que Bus.DOUT tiene el dato de la SDRAM (contrato con el pre-WAIT
    // del bus en docs/notas/megaram.md). 0 = como tnCart (sin WAIT).
    localparam          ENABLE_MEM_WAIT         = 1;

    // V9990TANG (fusion de las areas): palancas de cada configuracion.
    // Pre-WAIT de memoria de BOARD_REV1_BUS (hito/bus): obligatorio con
    // ENABLE_MEM_WAIT = 1 (PREWAIT_MEM_K = 7 por defecto); sin el, a 3,58 MHz
    // fallan 71 de 253 lecturas de la megaROM (docs/notas/megaram.md). El top
    // no elabora si no casa con ENABLE_MEM_WAIT. Con ENABLE_MEM_WAIT = 1,
    // RAM_IF_EXPANSION_USES_FF (abajo) tiene que seguir a 0.
    localparam          BUS_PREWAIT_MEM_EN      = 1;
    // Core T9990 (hito/core): cuadro PAL de 313 lineas con R#7 bit 3, cursor
    // EOR de openMSX y ajuste de posicion de R#16. Con los tres a 0 el core
    // es el del hito 1 con los parches 1-3, 8 y 9 (docs/notas/core.md).
    // ENABLE_R16 y ENABLE_CURSOR_EOR son las dos primeras palancas del
    // estudio si esta configuracion no cabe en la puerta.
    localparam          V9990_ENABLE_PAL        = 1;
    localparam          V9990_ENABLE_CURSOR_EOR = 1;
    localparam          V9990_ENABLE_R16        = 1;
    // Upscan (hito/video): 1 = mezcla de puntos de tnCart, 0 = el punto mas
    // cercano (tercera palanca).
    localparam          UPSCAN_BLEND            = 1;

    /***************************************************************
     * other(ここを変更すると動作しなくなる可能性があります)
     ***************************************************************/
    localparam          RAM_IF_EXPANSION_USES_FF= 0;                // RAM I/F 拡張動作に FF を使用(0=使用しない/1=使用する)
    localparam          SLOT_EXPANSION_USES_FF  = 1;                // SLOT 拡張に FF を使用(0=使用しない/1=使用する)
    localparam          SOUND_BIT_WIDTH         = 10;               // サウンド生成の量子化幅(bits)
endpackage

`default_nettype wire
