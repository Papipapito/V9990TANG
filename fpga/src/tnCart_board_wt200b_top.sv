//
// tnCart_board_wt200b_top.sv
//
// BSD 3-Clause License
//
// Copyright (c) 2024, Albert Herranz
//
// Based on tnCart_board_rev1_top.sv
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
// V9990TANG (hitos 3 y 6 del estudio). Frente al top de tnCartWonder d3a54f1:
//  - fuera la flash (FLASH_SPI y su SPI), el SPI de la TF y el LED de tnCart:
//    sus pines quedan en reposo (abajo, "Pines sin uso")
//  - BOARD_WT200B_GUARD (CLK_27M): POR, gestor del rPLL base (sin RESET_n
//    constante ni lock pegajoso), detector de perdida de enganche y guardia
//    de lock (DRIVE_EN_27, BOOT_HOLD_27)
//  - SYSTEM_RESET (CLK_BASE): PLL_OK sincronizado (BASE_READY, que tambien
//    resetea la SDRAM: antes era el LOCK crudo) y reset_n
//  - BOARD_REV1_BUS (hito/bus) con las guardias en los pines: DRIVE_EN_27 y
//    BOOT_HOLD_27 de la guardia de lock, BUS_OK (reloj del slot vivo y
//    /RESET del slot suelto) y el timeout fail-open del /WAIT
//    (WAIT_TIMEOUT, al LED). Fusion: sustituye a BOARD_WT200B_BUS_GUARD
//  - STATUS_LED (CLK_27M): error de reloj / arrancando / listo, con
//    WAIT_TIMEOUT pegajoso
//  - palancas por configuracion (fpga/config/<cfg>.sv): BLEND del upscan
//    (CONFIG::UPSCAN_BLEND) y pre-WAIT de memoria del bus
//    (CONFIG::BUS_PREWAIT_MEM_EN, solo con la MegaRAM de ENABLE_MEM_WAIT)
//  - el reset del DAC I2S pasa por dos FF en CLK_DAC
//  - xtal o sync: lo decide el board_wt200b_config_*.sv que compile cada
//    build_*.tcl (CONFIG_BOARD::SYNC_CPU_CLK)
//  - v9990_megaram_nextor: la flash y la TF vuelven a usarse (los pines los
//    conduce MAIN) y el tope de BOOT_HOLD pasa a 200 ms
//

`default_nettype none

module TNCART_BOARD_WT200B_TOP (
    input   wire            CLK_27M,

    // SDRAM
    output  wire            O_sdram_clk,
    output  wire            O_sdram_cke,
    output  wire            O_sdram_cs_n,
    output  wire            O_sdram_cas_n,
    output  wire            O_sdram_ras_n,
    output  wire            O_sdram_wen_n,
    inout   wire    [31:0]  IO_sdram_dq,
    output  wire    [10:0]  O_sdram_addr,
    output  wire    [1:0]   O_sdram_ba,
    output  wire    [3:0]   O_sdram_dqm,

    // BUS
    output  wire            CART_BUSDIR_n,
    output  wire            CART_INT_n,
    output  wire            CART_WAIT_n,
    input   wire            CART_SLTSL_n,
    input   wire            CART_RD_n,
    input   wire            CART_WR_n,
    input   wire            CART_CLOCK,
    input   wire    [7:0]   CART_MUX_SIG,
    output  wire    [2:0]   CART_MUX_CS_n,
    inout   wire    [7:0]   CART_DATA_SIG,
    output  wire            CART_DATA_DIR,

    // DAC
    output  wire            DAC_BCLK,
    output  wire            DAC_LRCLK,
    output  wire            DAC_DIN,
    output  wire            DAC_SDMODE_n,


    // LED
    output  wire            LED,

    // TMDS
    output wire             tmds_clk_p,
    output wire             tmds_clk_n,
    output wire    [2:0]    tmds_data_p,
    output wire    [2:0]    tmds_data_n,

    // SPI FLASH (solo la usa v9990_megaram_nextor; en las demas, en reposo)
    output  wire            mspi_cs,
    output  wire            mspi_sclk,
    input   wire            mspi_miso,
    output  wire            mspi_mosi,
    output  wire            mspi_hold,

    // TF (solo la usa v9990_megaram_nextor; en las demas, en reposo)
    output  wire            TF_SCLK,    // SCLK
    output  wire            TF_CMD,     // MOSI
    input   wire            TF_DAT0,    // MISO
    inout   wire            TF_DAT1,    // NC
    inout   wire            TF_DAT2,    // NC
    inout   wire            TF_DAT3,    // CS_n

    // UART
    input   wire            UART_RX,
    output  wire            UART_TX
);

    // UMA を有効
    localparam          ENABLE_UMA              = 1;//CONFIG::ENABLE_V9990;

    /***************************************************************
     * CLOCK
     ***************************************************************/
    logic CLK_BASE/* synthesis syn_keep=1 */;
    logic CLK_BASE_LOCK;
    logic CLK_MEM;
    logic CLK_MEM_P;
    logic CLK_TMDS_S/* synthesis syn_keep=1 */;
    logic CLK_TMDS_P/* synthesis syn_keep=1 */;
    logic CLK_TMDS_READY;
    logic CLK_21M/* synthesis syn_keep=1 */;
    logic CLK_DAC/* synthesis syn_keep=1 */;
    logic pll_reset;
    logic base_ready;
    BOARD_WT200B_CLOCK u_clk (
        .PLL_RESET      (pll_reset),
        .BASE_READY     (base_ready),
        .CLK_IN         (CONFIG_BOARD::SYNC_CPU_CLK ? CART_CLOCK : CLK_27M),
        .CLK_27M,
        .CLK_BASE,
        .CLK_21M,
        .CLK_DAC,
        .CLK_BASE_LOCK,
        .CLK_MEM,
        .CLK_MEM_P,
        .CLK_TMDS_S,
        .CLK_TMDS_P,
        .CLK_TMDS_READY
    );

    /***************************************************************
     * V9990TANG: POR, gestor del rPLL base y guardia de lock (CLK_27M)
     ***************************************************************/
    logic pll_ok;
    logic drive_en_27;
    logic boot_hold_27;
    logic sys_ready;            // SYS_RESET_n de MAIN (CLK_BASE)
    logic sys_bus_ready;        // sys_ready && bus_ok, registrado en CLK_BASE
    logic sys_ready_27;
    logic slot_present;
    logic relocked;
    logic wait_timeout_27;

    // WAIT_TIMEOUT: error pegajoso del timeout fail-open del /WAIT, que saca
    // u_bus en CLK_BASE (la guardia lo sincroniza con wto_ff y lo lleva al
    // LED). BUS_OK: flop de CLK_BASE de u_bus, reloj del slot vivo (>= 64
    // flancos en 2^18 ciclos, asi que sube 2,43-4,86 ms despues de RESET_n)
    // y /RESET del slot suelto; sin el, u_bus no saca datos, /INT ni el
    // /WAIT del V9990. Por eso la guardia recibe SYS_READY = sys_ready &&
    // bus_ok: BOOT_HOLD retiene al MSX tambien esa ventana (si no, correria
    // 2,43 ms con el cartucho mudo; docs/notas/integ.md, seccion 8) y el LED
    // ve BUS_OK a 0 como "arrancando" (con el /RESET del MSX pulsado, o con
    // el reloj del slot parado; en xtal, sin reloj del slot, sale antes el
    // codigo 2 de STATUS_LED). La AND se registra en CLK_BASE
    // (sys_bus_ready, abajo) antes de cruzar a CLK_27M: ready_ff sincroniza
    // un flop, no la AND combinacional de dos flops (un ciclo mas de 108 MHz).
    logic wait_timeout;
    logic bus_ok;

    // Tope de BOOT_HOLD_27 por arranque (fail-open): 50 ms (el valor por
    // defecto de la guardia) salvo con Nextor, cuya copia de la flash a la
    // SDRAM tarda ~70 ms: 200 ms (5 400 000 ciclos de 27 MHz) en
    // v9990_megaram_nextor (docs/notas/nextor.md)
    localparam int BOOT_HOLD_CYCLES = (CONFIG::ENABLE_NEXTOR != CONFIG::DISABLE) ? 5_400_000 : 1_350_000;

    BOARD_WT200B_GUARD #(
        .SYNC           (CONFIG_BOARD::SYNC_CPU_CLK),
        .HOLD_CYCLES    (BOOT_HOLD_CYCLES)
    ) u_guard (
        .CLK_27M,
        .PLL_LOCK       (CLK_BASE_LOCK),
        .SLOT_CLK       (CART_CLOCK),
        .SYS_READY      (sys_bus_ready),
        .WAIT_TIMEOUT   (wait_timeout),
        .PLL_RESET      (pll_reset),
        .PLL_OK         (pll_ok),
        .DRIVE_EN_27    (drive_en_27),
        .BOOT_HOLD_27   (boot_hold_27),
        .POR_DONE       (),
        .SLOT_OK        (),
        .SLOT_PRESENT   (slot_present),
        .SYS_READY_27   (sys_ready_27),
        .HOLD_EXPIRED   (),
        .RELOCKED       (relocked),
        .WAIT_TIMEOUT_27(wait_timeout_27)
    );

    /***************************************************************
     * UART
     ***************************************************************/
    // V9990TANG: sin modulo UART (CONFIG_BOARD::ENABLE_UART_MODULE = 0 y
    // uart.sv fuera del repositorio); UART_TX en reposo, UART_RX sin carga
    assign UART_TX = 1'b1;

    /***************************************************************
     * MSX バス
     ***************************************************************/
    wire RESET_n;
    wire CLK = CLK_BASE;

    // リセット信号処理 (V9990TANG: system/system_reset.sv)
    logic sdram_ready;
    SYSTEM_RESET u_rst (
        .CLK            (CLK_BASE),
        .PLL_OK         (pll_ok),
        .SDRAM_READY    (sdram_ready),
        .BASE_READY     (base_ready),
        .RESET_n
    );

    // SYS_READY de la guardia: SYS_RESET_n && BUS_OK en un flop de CLK_BASE
    // (los dos bajan en el acto con RESET_n, que resetea el flop tambien)
    always_ff @(posedge CLK_BASE or negedge RESET_n) begin
        if(!RESET_n) sys_bus_ready <= 1'b0;
        else         sys_bus_ready <= sys_ready && bus_ok;
    end

    // バス信号処理
    //  Las guardias van dentro de BOARD_REV1_BUS, en los pines y de forma
    //  combinacional (CART_WAIT_n = 1 activa el transistor que baja el /WAIT
    //  del slot):
    //   /WAIT = BOOT_HOLD || (BUS_OK && DRIVE_EN && wait && !timeout)
    //   /INT  = BUS_OK && DRIVE_EN && int          (CART_INT_n = 0 en reposo, 2.00b)
    //   datos = solo con BUS_OK && DRIVE_EN, /RD del pin a 0 y una lectura
    //           que empezo con Bus.BUSDIR_n en reposo (si no, CART_DATA_DIR =
    //           1, CART_BUSDIR_n = 1 y CART_DATA_SIG en alta impedancia)
    //  DRIVE_EN_27 y BOOT_HOLD_27 son flops de CLK_27M: en los pines entran
    //  directos y, para el contador del timeout, por dos FF de CLK_BASE
    //  (drive_en_s/boot_hold_s de u_bus; el set_clock_groups del .sdc corta
    //  el cruce). DRIVE_EN puede bajar y volver sin reset (LOCK bajo menos de
    //  152 us): u_bus no lo toma como un reset.
    //  PREWAIT_MEM_EN = 1 solo con una megaROM que baje Bus.WAIT_n en sus
    //  lecturas (la de hito/megaram con ENABLE_MEM_WAIT = 1): lo fija cada
    //  configuracion (CONFIG::BUS_PREWAIT_MEM_EN, comprobado abajo). El resto
    //  de parametros, los de hito/bus por defecto (docs/notas/bus.md).
    BUS_IF Bus();
    BOARD_REV1_BUS #(
        .PREWAIT_MEM_EN (CONFIG::BUS_PREWAIT_MEM_EN)
    ) u_bus (
        .RESET_n,
        .CLK,
        .CLK_21M,
        .DRIVE_EN       (drive_en_27),
        .BOOT_HOLD      (boot_hold_27),
        .WAIT_TIMEOUT   (wait_timeout),
        .BUS_OK         (bus_ok),
        .CART_BUSDIR_n,
        .CART_INT_n,
        .CART_WAIT_n,
        .CART_SLTSL_n,
        .CART_RD_n,
        .CART_WR_n,
        .CART_CLOCK,
        .CART_MUX_SIG,
        .CART_MUX_CS_n,
        .CART_DATA_SIG,
        .CART_DATA_DIR,
        .Bus
    );

    // El pre-WAIT de memoria pide una megaROM con /WAIT en sus lecturas, y
    // esa megaROM lo necesita (sin el, a 3,58 MHz fallan 71 de 253 lecturas:
    // docs/notas/megaram.md). Una configuracion que los separe no elabora.
    if(CONFIG::BUS_PREWAIT_MEM_EN != ((CONFIG::ENABLE_MEGAROM != CONFIG::DISABLE) && (CONFIG::ENABLE_MEM_WAIT != 0))) begin
        TOP_BUS_PREWAIT_MEM_EN_NO_CASA_CON_ENABLE_MEM_WAIT u_prewait_mem_no_casa ();
    end

    /***************************************************************
     * SDRAM
     ***************************************************************/
    RAM_IF Ram();
    SDRAM #(
        .SDRAM_A_WIDTH      (11),
        .SDRAM_BA_WIDTH     (2),
        .SDRAM_COL_WIDTH    (8),
        .SDRAM_ROW_WIDTH    (11),
        .SDRAM_DQ_WIDTH     (32)
    ) u_sdram (
        .CLK                (CLK_MEM),
        .CLK_PS             (CLK_MEM_P),
        .RESET_n            (base_ready),       // V9990TANG: antes el LOCK crudo del rPLL

        .READY              (sdram_ready),

        .SDRAM_CLK          (O_sdram_clk),
        .SDRAM_CKE          (O_sdram_cke),
        .SDRAM_CS_n         (O_sdram_cs_n),
        .SDRAM_RAS_n        (O_sdram_ras_n),
        .SDRAM_CAS_n        (O_sdram_cas_n),
        .SDRAM_WE_n         (O_sdram_wen_n),
        .SDRAM_A            (O_sdram_addr),
        .SDRAM_BA           (O_sdram_ba),
        .SDRAM_DQM          (O_sdram_dqm),
        .SDRAM_DQ           (IO_sdram_dq),

        .Ram
    );

    /***************************************************************
     * UMA
     ***************************************************************/
    UMA_IF Uma();
    assign Uma.ADDR[0] = 0;                         // Uma[0] の SDRAM 先頭アドレス
    assign Uma.ADDR[1] = CONFIG::RAM_ADDR_VRAM;     // Uma[1] の SDRAM 先頭アドレス

    RAM_IF UmaRam[0:Uma.COUNT-1]();

    if(ENABLE_UMA) begin
        UMA #(
            .COUNT      (Uma.COUNT),
            .SYNC_CLK_EN(CONFIG_BOARD::SYNC_CPU_UMA),
            .DIV        (30)                        // 108MHz/3.58MHz = 30
        ) u_uma (
            .RESET_n,
            .CLK,
            .CLK_EN     (Bus.CLK_EN),
            .Primary    (Ram),
            .Secondary  (UmaRam),
            .Uma
        );
    end
    else begin
        // UMA を使わない時
        BYPASS_RAM u_bypass_uma (
            .Primary    (Ram),
            .Secondary  (UmaRam[0])
        );
        assign UmaRam[1].DOUT = 0;
        assign UmaRam[1].ACK_n = 1;
        assign UmaRam[1].TIMING = 0;
        assign Uma.CLK14M_EN = 0;
        assign Uma.CLK21M_EN = 0;
        assign Uma.CLK25M_EN = 0;
    end

    /***************************************************************
     * V9990TANG: pines sin uso, en reposo
     ***************************************************************/
    // Flash SPI de la Tang (mspi_*, la del bitstream; -use_mspi_as_gpio) y
    // TF: desde la configuracion v9990_megaram_nextor los conduce MAIN (la
    // flash para copiar Nextor, la TF por el SPI de CARTRIDGE_NEXTOR); en las
    // demas MAIN los deja en el reposo de siempre: flash con /CS alto
    // (deseleccionada), SCLK y MOSI a 0; TF con CS_n (DAT3) alto, SCLK a 0 y
    // CMD (MOSI) a 1 (reposo del bus SPI de la SD), y TF_DAT0 y mspi_miso sin
    // carga. /HOLD de la flash alto (inactivo) siempre; DAT1 y DAT2 de la TF
    // en alta impedancia con el pull-up del .cst.
    assign mspi_hold = 1'b1;
    assign TF_DAT1 = 1'bZ;
    assign TF_DAT2 = 1'bZ;

    /***************************************************************
     * LED (V9990TANG: estado, en CLK_27M)
     ***************************************************************/
    STATUS_LED #(
        .SYNC           (CONFIG_BOARD::SYNC_CPU_CLK)
    ) u_led (
        .CLK            (CLK_27M),
        .PLL_OK         (pll_ok),
        .SYS_READY      (sys_ready_27),
        .SLOT_PRESENT   (slot_present),
        .WAIT_TIMEOUT   (wait_timeout_27),
        .RELOCKED       (relocked),
        .LED            (LED),
        .CODE           ()
    );

    /***************************************************************
     * DAC
     ***************************************************************/

    /*
     * The WonderTANG! 2.0b DAC output is directed to both SOUNDIN
     * and the audio jack output, so we cannot differentiate between
     * internal and external sound.
     * We use the external sound samples which include all audio.
     *
     * The DAC clock works at 32 x 48KHz.
     */

    // V9990TANG: el reset del I2S, sincronizado a CLK_DAC (afirmacion
    // asincrona, suelta sincrona); antes RESET_n de CLK_BASE directo
    reg [1:0] dac_reset_ff = 2'b00;
    always_ff @(posedge CLK_DAC or negedge RESET_n) begin
        if(!RESET_n) dac_reset_ff <= 2'b00;
        else         dac_reset_ff <= { dac_reset_ff[0], 1'b1 };
    end
    wire dac_reset_n = dac_reset_ff[1];

    // Despite the name, this is both the internal/external sound out
    SOUND_IF #(.BIT_WIDTH(CONFIG_BOARD::DAC_BIT_WIDTH)) SoundExternal[0:0]();
    DAC_16BIT u_dac_ext (
        .CLK_DAC,
        .RESET_n        (dac_reset_n),
        .IN             (SoundExternal[0]),
        .DAC_BCLK,
        .DAC_LRCLK,
        .DAC_DIN
     );

    // Dummy definition, will get optimized out by the synthesis tool.
    SOUND_IF #(.BIT_WIDTH(CONFIG_BOARD::DAC_BIT_WIDTH)) SoundInternal();

    // unmute the DAC
    assign DAC_SDMODE_n = RESET_n;


    /***************************************************************
     * VIDEO
     ***************************************************************/
    VIDEO_IF Video();
    VIDEO_IF VideoTmds();
    // BLEND (hito/video): 1 = la mezcla de puntos de tnCart, 0 = el punto
    // mas cercano (menos logica y otra colocacion; ultima palanca del
    // estudio para la Fmax). Lo fija cada configuracion.
    VIDEO_UPSCAN #(
        .ENABLE_SCANLINE(CONFIG::ENABLE_SCANLINE),
        .BLEND          (CONFIG::UPSCAN_BLEND)
    ) u_upscan (
        .RESET_n,
        .DCLK           (CLK_TMDS_P),
        .IN             (Video),
        .OUT            (VideoTmds)
    );

    BOARD_REV1_TMDS_OUT u_tmds (
        .RESET_n,
        .IN             (VideoTmds),
        .TMDS_READY     (CLK_TMDS_READY),
        .CLK_S          (CLK_TMDS_S),
        .CLK_P          (CLK_TMDS_P),
        .TMDS_CLKP      (tmds_clk_p),
        .TMDS_CLKN      (tmds_clk_n),
        .TMDS_DATAP     (tmds_data_p),
        .TMDS_DATAN     (tmds_data_n)
    );

    /***************************************************************
     * MAIN
     ***************************************************************/
    MAIN u_main (
        .RESET_n,
        .CLK,
        .Bus,
        .Ram            (UmaRam[0]),
        .VideoRam       (UmaRam[1]),
        .UmaClock       (Uma),
        .Video,
        .SoundInternal,
        .SoundExternal,
        .SYS_READY      (sys_ready),
        .TF_SCLK        (TF_SCLK),
        .TF_MOSI        (TF_CMD),
        .TF_MISO        (TF_DAT0),
        .TF_CS_n        (TF_DAT3),
        .FLASH_SCLK     (mspi_sclk),
        .FLASH_MOSI     (mspi_mosi),
        .FLASH_MISO     (mspi_miso),
        .FLASH_CS_n     (mspi_cs)
    );

endmodule


`default_nettype wire
