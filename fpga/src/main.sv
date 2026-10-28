//
// main.sv
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
// V9990TANG: recorte de la carcasa (hito 3 del estudio). Frente al main.sv de
// tnCartWonder d3a54f1:
//  - fuera el BOOTLOADER (y con el la flash, sus SPI y la TF): SYS_RESET_n ya
//    no lo retiene BOOT_n sino RESET_n (PLL base enganchado y SDRAM lista, ver
//    system/system_reset.sv) y, en la configuracion MegaRAM, el borrado de 32 KB
//    de la ventana de la megaROM (MEGAROM_CLEAR); MAIN lo saca por SYS_READY
//    hacia la guardia de lock del top. Ya no baja con el /RESET del MSX (el
//    bootloader lo bajaba): cada cartucho ve Bus.RESET_n por su cuenta
//  - fuera FM, Nextor, mapper y PSG (sus modulos no estan en ninguna build);
//    si una configuracion los activa, la elaboracion falla a proposito
//  - configuracion v9990 (sin megaROM): el V9990 va directo al bus, sin
//    EXPANSION_SLOT, como un GFX9000 (solo los puertos 60h-6Fh; el slot no
//    tiene registro FFFFh ni subranuras). Con megaROM se mantiene el slot
//    expandido de tnCart: megaROM en la subranura 0 y el V9990 como puerto
//    solo de E/S (Secondary[5], SLTSL_n fijo a 1)
//  - el slot expandido recibe en WAIT_n el DONE del borrado (antes el
//    BOOT_WAIT_n del bootloader); como SYS_RESET_n tambien espera a DONE, en
//    la practica vale 1. El /WAIT de arranque que ve el MSX lo saca la
//    guardia del top (BOOT_HOLD_27); el que EXPANSION_SLOT pone en reset
//    (Primary.WAIT_n <= 0) no llega al pin porque DRIVE_EN_27 sigue a 0
//    hasta que SYS_RESET_n sube
//  - la megaROM sigue recibiendo un XFER_IF (sus ordenes de flash, que
//    servia el bootloader) con el lado del dispositivo fijo
//    (system/megarom_xfer_tie.sv: Busy = 0 y RData = FFh). Las ordenes de
//    flash de tncrom acaban al instante sin hacer nada. XFER_IF y su paquete
//    viven en bootloader.sv, que la configuracion MegaRAM compila solo por
//    eso (build_common.tcl)
//  - en la configuracion v9990 todo lo de la MegaRAM queda en ramas de
//    generate muertas que solo nombran modulos e interfaces sin definir (sin
//    referencias con punto), y la build v9990 no compila bootloader.sv: asi
//    elabora en GowinSynthesis (builds v9990_xtal y v9990_sync) y no rompe
//    Verilator 5.020, que tolera modulos sin definir en una rama muerta pero
//    no referencias con punto a una interfaz sin definir (comprobado con un
//    caso minimo; el top entero no pasa por Verilator por las referencias con
//    punto en constantes de tnCart, p. ej. $bits(SoundExternal[0].Signal))
//
// MEGAROM_CLEAR (hito/megaram, megarom_clear.sv: RESET_n, CLK, RAM_IF.HOST
// Ram, output DONE) va tras HAVE_MEGAROM_CLEAR, conectado a
// ExpRam[RAM_BOOTLOADER] (canal 0 del UMA, base 0), el mismo canal que usaba
// el borrado del bootloader. Desde la fusion de las areas la macro esta
// activa: DONE retiene SYS_RESET_n (y con el SYS_READY hacia la guardia del
// top, asi que BOOT_HOLD cubre el borrado, unos 7 ms frente al tope de 50) y
// va a la entrada WAIT_n de EXPANSION_SLOT. Tras una perdida de enganche
// los 32 KB se vuelven a borrar. Necesita SYNC_CPU_UMA = 0 (las dos
// variantes). Sin la macro, la configuracion MegaRAM no elabora (un modulo
// MEGAROM_CLEAR_FALTA_HASTA_LA_FUSION que no existe) y build_common.tcl se
// para antes.
//
`define HAVE_MEGAROM_CLEAR
//
// Configuracion v9990_megaram_nextor (CONFIG::ENABLE_NEXTOR, solo con la
// megaROM: necesita el slot expandido). Vuelven, solo en esa configuracion
// (rama de generate dentro de la de la megaROM, para no mover los nombres
// genblk de las otras), el cartucho Nextor de tnCart (CARTRIDGE_NEXTOR, con
// su TF_CONTROLLER, en la subranura 2), el SPI de la TF y la copia de la ROM
// de Nextor de la flash a la SDRAM (NEXTOR_LOADER, con FLASH_SPI y su SPI, en
// lugar del BOOTLOADER de tnCart: ver system/nextor_loader.sv). Los pines de
// la flash y de la TF salen de MAIN como hilos sueltos (TF_*, FLASH_*): en
// las otras configuraciones MAIN los deja en el reposo que antes ponia el
// top. Secuencia de arranque: RESET_n -> MEGAROM_CLEAR (32 KB) -> copia de
// Nextor (128 KB, ~70 ms) -> SYS_RESET_n; el canal 0 del UMA lo usan por
// turnos (EXPANSION_RAM hace OR de los clientes). Ver docs/notas/nextor.md.
//

`default_nettype none

module MAIN #(
    parameter               EXT_SOUND_CH_COUNT  = 1
) (
    input   wire            RESET_n,
    input   wire            CLK,
    BUS_IF.CARTRIDGE        Bus,                // BUS I/F
    RAM_IF.HOST             Ram,                // RAM I/F
    RAM_IF                  VideoRam,           // VRAM I/F
    UMA_IF.CLK              UmaClock,           // UMA クロック
    VIDEO_IF                Video,              // ビデオ出力
    SOUND_IF.OUT            SoundExternal[0:EXT_SOUND_CH_COUNT-1],  // 外部サウンド出力
    SOUND_IF.OUT            SoundInternal,      // カートリッジサウンド出力
    output  wire            SYS_READY,          // V9990TANG: SYS_RESET_n (sistema listo), hacia la guardia del top
    // V9990TANG: pines de la TF (SPI de la SD) y de la flash (solo los usa
    // la configuracion v9990_megaram_nextor; en las otras, en reposo)
    output  wire            TF_SCLK,
    output  wire            TF_MOSI,
    input   wire            TF_MISO,
    output  wire            TF_CS_n,
    output  wire            FLASH_SCLK,
    output  wire            FLASH_MOSI,
    input   wire            FLASH_MISO,
    output  wire            FLASH_CS_n
);
    /***************************************************************
     * V9990TANG: configuraciones soportadas
     ***************************************************************/
    if(CONFIG::ENABLE_FM || (CONFIG::ENABLE_NEXTOR && !CONFIG::ENABLE_MEGAROM) || CONFIG::ENABLE_RAM || CONFIG::ENABLE_PSG || !CONFIG::ENABLE_V9990) begin
        // FM, mapper y PSG no estan en V9990TANG; Nextor solo con la megaROM
        // (v9990_megaram_nextor); el V9990 es obligatorio
        MAIN_CONFIGURACION_NO_SOPORTADA_EN_V9990TANG u_config_no_soportada ();
    end

    /***************************************************************
     * サウンド信号格納用
     ***************************************************************/
    localparam SOUND_MEGAROM = 0;
    localparam SOUND_FM_INT  = 1;
    localparam SOUND_FM_EXT  = 2;
    localparam SOUND_PSG     = 3;
    localparam SOUND_COUNT   = 4;
    SOUND_IF #(.BIT_WIDTH(CONFIG::SOUND_BIT_WIDTH)) Sound[0:SOUND_COUNT-1]();
    always_comb Sound[SOUND_FM_INT].connect_dummy();
    always_comb Sound[SOUND_FM_EXT].connect_dummy();
    always_comb Sound[SOUND_PSG].connect_dummy();

    /***************************************************************
     * RAM I/F を複数に拡張
     ***************************************************************/
    localparam RAM_MEGAROM    = 0;
    localparam RAM_BOOTLOADER = 1;      // V9990TANG: el canal del borrado de la megaROM (antes del bootloader)
    localparam RAM_NEXTOR     = 2;      // V9990TANG: solo con Nextor
    localparam RAM_LOADER     = 3;      // V9990TANG: copia de Nextor (NEXTOR_LOADER), solo con Nextor
    localparam RAM_COUNT      = CONFIG::ENABLE_NEXTOR ? 4 : 2;
    RAM_IF ExpRam[0:RAM_COUNT-1]();
    EXPANSION_RAM #(
        .COUNT          (RAM_COUNT),
        .USE_FF         (CONFIG::RAM_IF_EXPANSION_USES_FF)
    ) u_expram (
        .RESET_n,
        .CLK,
        .Primary        (Ram),
        .Secondary      (ExpRam)
    );

    /***************************************************************
     * V9990TANG: reset de los cartuchos (POR en lugar del bootloader)
     ***************************************************************/
    logic SYS_RESET_n;
    logic clear_done;
    logic boot_done;        // V9990TANG: clear_done y, con Nextor, la copia de su ROM

    SYSTEM_RESET_HOLD u_sysrst (
        .CLK,
        .RESET_n,
        .HOLD           (!boot_done),
        .SYS_RESET_n
    );
    assign SYS_READY = SYS_RESET_n;

    if(CONFIG::ENABLE_MEGAROM) begin
        /***********************************************************
         * MegaRAM: borrado de 32 KB de la ventana de la megaROM
         * (arranca habilitada: sin el borrado la BIOS buscaria "AB"
         * en lo que hubiera en la SDRAM)
         ***********************************************************/
`ifdef HAVE_MEGAROM_CLEAR
        // la ventana empieza en CONFIG::RAM_ADDR_MEGAROM y el canal 0 del
        // UMA tiene base 0 (Uma.ADDR[0] = 0 en el top); 32 KB como el
        // MEGAROM_CLEAR_SIZE del bootloader
        MEGAROM_CLEAR #(
            .CLEAR_ADDR     (CONFIG::RAM_ADDR_MEGAROM),
            .CLEAR_SIZE     (24'd32768)
        ) u_megarom_clear (
            .RESET_n,
            .CLK,
            .Ram            (ExpRam[RAM_BOOTLOADER]),
            .DONE           (clear_done)
        );
`else
        MEGAROM_CLEAR_FALTA_HASTA_LA_FUSION u_megarom_clear_falta ();
        assign clear_done = 1'b0;
        always_comb ExpRam[RAM_BOOTLOADER].connect_dummy();
`endif

        /***********************************************************
         * スロットの拡張 (como en tnCart)
         ***********************************************************/
        localparam BUS_MEGAROM = 0;
        localparam BUS_FM      = 1;
        localparam BUS_NEXTOR  = 2;
        localparam BUS_RAM     = 3;
        localparam BUS_PSG     = 4;     // SLTSL_n 信号なし(I/Oのみ)
        localparam BUS_V9990   = 5;     // SLTSL_n 信号なし(I/Oのみ)
        localparam BUS_COUNT   = 6;
        BUS_IF  ExpBus[0:BUS_COUNT-1]();
        EXPANSION_SLOT #(
            .COUNT          (BUS_COUNT),
            .USE_FF         (CONFIG::SLOT_EXPANSION_USES_FF)
        ) u_sltexp (
            .RESET_n        (SYS_RESET_n),
            .CLK,
            .Primary        (Bus),
            .Secondary      (ExpBus),
            .WAIT_n         (boot_done)     // V9990TANG: antes BOOT_WAIT_n del bootloader
        );
        always_comb ExpBus[BUS_FM].connect_dummy();
        always_comb ExpBus[BUS_RAM].connect_dummy();
        always_comb ExpBus[BUS_PSG].connect_dummy();

        /***********************************************************
         * V9990TANG: NEXTOR カートリッジ (v9990_megaram_nextor)
         *  subranura 2; ROM de 128 KB copiada de la flash (10_0000h)
         *  a CONFIG::RAM_ADDR_BIOS_NEXTOR por NEXTOR_LOADER tras el
         *  borrado de la megaROM
         ***********************************************************/
        if(CONFIG::ENABLE_NEXTOR) begin
            logic load_done;
            assign boot_done = clear_done && load_done;

            // SPI de la TF (como en el top de tnCart)
            SPI_IF TF();
            SPI #(
                .CLK_DIV        (CONFIG_BOARD::TF_CLK_DIV)
            ) u_tf_spi (
                .CLK,
                .RESET_n,
                .SCLK           (TF_SCLK),
                .MOSI           (TF_MOSI),
                .MISO           (TF_MISO),
                .CS_n           (TF_CS_n),
                .SPI_Interface  (TF)
            );

            LED_IF LedNextor();     // sin lector: el LED de la placa es STATUS_LED
            CARTRIDGE_NEXTOR #(
                .RAM_ADDR       (CONFIG::RAM_ADDR_BIOS_NEXTOR)
            ) u_nextor (
                .RESET_n        (SYS_RESET_n),
                .CLK,
                .Bus            (ExpBus[BUS_NEXTOR]),
                .Ram            (ExpRam[RAM_NEXTOR]),
                .TF,
                .Led            (LedNextor)
            );

            // flash (como en el top de tnCart) y la copia de Nextor
            FLASH_IF Flash();
            SPI_IF #(
                .MOSI_BIT_WIDTH (24 + 8)    // Flash.ADDR_WIDTH + orden
            ) Flash_SPI();
            SPI #(
                .CLK_DIV        (CONFIG_BOARD::FLASH_CLK_DIV)
            ) u_flash_spi (
                .CLK,
                .RESET_n,
                .SCLK           (FLASH_SCLK),
                .MOSI           (FLASH_MOSI),
                .MISO           (FLASH_MISO),
                .CS_n           (FLASH_CS_n),
                .SPI_Interface  (Flash_SPI)
            );
            FLASH_SPI u_flash (
                .CLK,
                .RESET_n,
                .SPI            (Flash_SPI),
                .Flash          (Flash)
            );
            NEXTOR_LOADER #(
                .SRC_ADDR       (CONFIG::FLASH_ADDR_BIOS),
                .DST_ADDR       (CONFIG::RAM_ADDR_BIOS_NEXTOR),
                .SIZE           (CONFIG::FLASH_SIZE_BIOS_NEXTOR)
            ) u_loader (
                .RESET_n,
                .CLK,
                .START          (clear_done),
                .Flash          (Flash),
                .Ram            (ExpRam[RAM_LOADER]),
                .DONE           (load_done)
            );
        end
        else begin
            assign boot_done = clear_done;
            always_comb ExpBus[BUS_NEXTOR].connect_dummy();
            // pines en reposo (los que ponia el top hasta la 0.1beta)
            assign TF_CS_n    = 1'b1;
            assign TF_SCLK    = 1'b0;
            assign TF_MOSI    = 1'b1;
            assign FLASH_CS_n = 1'b1;
            assign FLASH_SCLK = 1'b0;
            assign FLASH_MOSI = 1'b0;
        end

        /***********************************************************
         * MEGAROM カートリッジ
         ***********************************************************/
        localparam [7:0]     DEFAULT_BANK_REG_INIT_0     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 0        : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 0        : 0;
        localparam [7:0]     DEFAULT_BANK_REG_INIT_1     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1        : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1        : 0;
        localparam [7:0]     DEFAULT_BANK_REG_INIT_2     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 2        : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 2        : 0;
        localparam [7:0]     DEFAULT_BANK_REG_INIT_3     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 3        : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 3        : 0;
        localparam [15:0]    DEFAULT_BANK_REG_ADDR_0     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 16'h5000 : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 16'h5000 : 16'hFFFF;
        localparam [15:0]    DEFAULT_BANK_REG_ADDR_1     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 16'h7000 : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 16'h7000 : 16'hFFFF;
        localparam [15:0]    DEFAULT_BANK_REG_ADDR_2     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 16'h9000 : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 16'h9000 : 16'hFFFF;
        localparam [15:0]    DEFAULT_BANK_REG_ADDR_3     = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 16'hB000 : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 16'hB000 : 16'hFFFF;
        localparam [15:0]    DEFAULT_BANK_REG_ADDR_MASK  = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 16'hF800 : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 16'hF800 : 16'h0000;
        localparam [7:0]     DEFAULT_BANK_REG_MASK       = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 8'hFF    : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 8'h3F    : 8'h00;
        localparam [0:0]     DEFAULT_WRITE_PROTECT       = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b0     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b1     : 1'b1;
        localparam [0:0]     DEFAULT_IS_16K_BANK         = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b0     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b0     : 1'b1;
        localparam [0:0]     DEFAULT_CS1_MASK            = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b0     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b0     : 1'b1;
        localparam [0:0]     DEFAULT_CS2_MASK            = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b0     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b0     : 1'b1;
        localparam [0:0]     DEFAULT_SCC_ENA             = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b1     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b1     : 1'b0;
        localparam [0:0]     DEFAULT_SCC_I_ENA           = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b1     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b0     : 1'b0;
        localparam [0:0]     DEFAULT_ENABLE_CONTINUOUS   = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b1     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b1     : 1'b0;
        localparam [0:0]     DEFAULT_ENABLE              = (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC_I) ? 1'b1     : (CONFIG::ENABLE_MEGAROM == CONFIG::ENABLE_MEGA_SCC) ? 1'b1     : 1'b0;
        // V9990TANG: el XFER_IF era la transferencia flash <-> SDRAM que
        // servia el bootloader. Sin bootloader, el lado del dispositivo queda
        // fijo (MEGAROM_XFER_TIE: ninguna orden de flash esta nunca ocupada;
        // se leen FFh). Si hito/megaram quita el puerto Xfer de
        // CARTRIDGE_MEGAROM, quitar tambien este XFER_IF, MEGAROM_XFER_TIE y
        // bootloader.sv, flash.sv y spi.sv de la lista MegaRAM
        // (build_common.tcl).
        XFER_IF Xfer();
        MEGAROM_XFER_TIE u_xfer_tie (
            .Xfer           (Xfer)
        );
        CARTRIDGE_MEGAROM #(
            .FLASH_FS_ADDR          (0),
            .FLASH_FS_SIZE          (24'h10_0000),
            .FLASH_MEGAROM_ADDR     (CONFIG::FLASH_ADDR_MEGAROM),
            .FLASH_MEGAROM_SIZE     (CONFIG::FLASH_SIZE_MEGAROM),
            .FLASH_NEXTOR_ADDR      (CONFIG::FLASH_ADDR_BIOS),
            .FLASH_NEXTOR_SIZE      (CONFIG::FLASH_SIZE_BIOS_NEXTOR),
            .FLASH_FM_ADDR          (CONFIG::FLASH_ADDR_BIOS + CONFIG::FLASH_SIZE_BIOS_NEXTOR),
            .FLASH_FM_SIZE          (CONFIG::FLASH_SIZE_BIOS_FM),
            .FLASH_PAC_ADDR         (CONFIG::FLASH_ADDR_PAC),
            .FLASH_PAC_SIZE         (CONFIG::FLASH_SIZE_PAC),
            .RAM_ADDR               (CONFIG::RAM_ADDR_MEGAROM),
            .RAM_SIZE               (CONFIG::RAM_SIZE_MEGAROM),
            .DEFAULT_BANK_REG_INIT_0(DEFAULT_BANK_REG_INIT_0),
            .DEFAULT_BANK_REG_INIT_1(DEFAULT_BANK_REG_INIT_1),
            .DEFAULT_BANK_REG_INIT_2(DEFAULT_BANK_REG_INIT_2),
            .DEFAULT_BANK_REG_INIT_3(DEFAULT_BANK_REG_INIT_3),
            .DEFAULT_BANK_REG_ADDR_0(DEFAULT_BANK_REG_ADDR_0),
            .DEFAULT_BANK_REG_ADDR_1(DEFAULT_BANK_REG_ADDR_1),
            .DEFAULT_BANK_REG_ADDR_2(DEFAULT_BANK_REG_ADDR_2),
            .DEFAULT_BANK_REG_ADDR_3(DEFAULT_BANK_REG_ADDR_3),
            .DEFAULT_BANK_REG_ADDR_MASK(DEFAULT_BANK_REG_ADDR_MASK),
            .DEFAULT_BANK_REG_MASK(DEFAULT_BANK_REG_MASK),
            .DEFAULT_WRITE_PROTECT(DEFAULT_WRITE_PROTECT),
            .DEFAULT_IS_16K_BANK(DEFAULT_IS_16K_BANK),
            .DEFAULT_CS1_MASK(DEFAULT_CS1_MASK),
            .DEFAULT_CS2_MASK(DEFAULT_CS2_MASK),
            .DEFAULT_SCC_ENA(DEFAULT_SCC_ENA),
            .DEFAULT_SCC_I_ENA(DEFAULT_SCC_I_ENA),
            .DEFAULT_ENABLE_CONTINUOUS(DEFAULT_ENABLE_CONTINUOUS),
            .DEFAULT_ENABLE(DEFAULT_ENABLE)
        ) u_megarom (
            .RESET_n        (SYS_RESET_n),
            .CLK,
            .Bus            (ExpBus[BUS_MEGAROM]),
            .Ram            (ExpRam[RAM_MEGAROM]),
            .Xfer           (Xfer),
            .Sound          (Sound[SOUND_MEGAROM])
        );

        /***********************************************************
         * V9990 カートリッジ (puerto solo de E/S del slot expandido)
         ***********************************************************/
        CARTRIDGE_V9990 u_v9990 (
            .RESET_n        (SYS_RESET_n),
            .CLK,
            .Bus            (ExpBus[BUS_V9990]),
            .Ram            (VideoRam),
            .UmaClock,
            .Video          (Video)
        );
    end
    else begin
        assign clear_done = 1'b1;
        assign boot_done  = 1'b1;
        // pines de la TF y de la flash en reposo (los que ponia el top)
        assign TF_CS_n    = 1'b1;
        assign TF_SCLK    = 1'b0;
        assign TF_MOSI    = 1'b1;
        assign FLASH_CS_n = 1'b1;
        assign FLASH_SCLK = 1'b0;
        assign FLASH_MOSI = 1'b0;
        always_comb ExpRam[RAM_MEGAROM].connect_dummy();
        always_comb ExpRam[RAM_BOOTLOADER].connect_dummy();
        always_comb Sound[SOUND_MEGAROM].connect_dummy();

        /***********************************************************
         * V9990 カートリッジ: directo al bus, sin slot expandido
         * (solo puertos 60h-6Fh, como un GFX9000)
         ***********************************************************/
        CARTRIDGE_V9990 u_v9990 (
            .RESET_n        (SYS_RESET_n),
            .CLK,
            .Bus            (Bus),
            .Ram            (VideoRam),
            .UmaClock,
            .Video          (Video)
        );
    end

    /***************************************************************
     * 外部サウンド出力ミキサー
     ***************************************************************/
    localparam SOUND_EXT_MEGAROM = 0;
    localparam SOUND_EXT_FM      = 1;
    localparam SOUND_EXT_PSG     = 2;
    localparam SOUND_EXT_COUNT   = 3;
    SOUND_IF #(.BIT_WIDTH($bits(Sound[0].Signal))) AttOutExt[0:SOUND_EXT_COUNT-1]();

    if(CONFIG::ENABLE_MEGAROM) begin
        SOUND_ATTENUATOR #(
            .MUL(CONFIG::ATT_EXT_MEGAROM_MUL),
            .DIV(CONFIG::ATT_EXT_MEGAROM_DIV)
        ) u_att_ext_megarom (
            .RESET_n,
            .CLK,
            .IN(Sound[SOUND_MEGAROM]),
            .OUT(AttOutExt[SOUND_EXT_MEGAROM])
        );
    end
    else begin
        always_comb AttOutExt[SOUND_EXT_MEGAROM].connect_dummy();
    end

    if(CONFIG::ENABLE_FM) begin
        SOUND_ATTENUATOR #(
            .MUL(CONFIG::ATT_EXT_FM_MUL),
            .DIV(CONFIG::ATT_EXT_FM_DIV)
        ) u_att_ext_fm (
            .RESET_n,
            .CLK,
            .IN(Sound[SOUND_FM_EXT]),
            .OUT(AttOutExt[SOUND_EXT_FM])
        );
    end
    else begin
        always_comb AttOutExt[SOUND_EXT_FM].connect_dummy();
    end

    if(CONFIG::ENABLE_PSG) begin
        SOUND_ATTENUATOR #(
            .MUL(CONFIG::ATT_EXT_PSG_MUL),
            .DIV(CONFIG::ATT_EXT_PSG_DIV)
        ) u_att_ext_psg (
            .RESET_n,
            .CLK,
            .IN(Sound[SOUND_PSG]),
            .OUT(AttOutExt[SOUND_EXT_PSG])
        );
    end
    else begin
        always_comb AttOutExt[SOUND_EXT_PSG].connect_dummy();
    end

    SOUND_IF #(.BIT_WIDTH($bits(AttOutExt[0].Signal))) mix_ext();

    SOUND_MIXER #(
        .COUNT          (SOUND_EXT_COUNT)
    ) u_mixer_ext (
        .RESET_n,
        .CLK,
        .IN             (AttOutExt),
        .OUT            (mix_ext)
    );

    if($bits(SoundExternal[0].Signal) == $bits(mix_ext.Signal)) begin
        assign SoundExternal[0].Signal = mix_ext.Signal;
    end
    else begin
        wire [$bits(mix_ext.Signal)+16-1:0] mix_ext_ex = { mix_ext.Signal, 16'd0 };
        assign SoundExternal[0].Signal = mix_ext_ex[$bits(mix_ext_ex)-1:$bits(mix_ext_ex)-$bits(SoundExternal[0].Signal)];
    end

    generate
        genvar ext_ch;
        if(EXT_SOUND_CH_COUNT >= 2) begin
            for(ext_ch = 1; ext_ch < EXT_SOUND_CH_COUNT; ext_ch = ext_ch + 1) begin: ch
                assign SoundExternal[ext_ch].Signal = 0;
            end
        end
    endgenerate

    /***************************************************************
     * カートリッジサウンド出力ミキサー
     ***************************************************************/
    localparam SOUND_INT_MEGAROM = 0;
    localparam SOUND_INT_FM      = 1;
    localparam SOUND_INT_COUNT   = 2;
    SOUND_IF #(.BIT_WIDTH($bits(Sound[0].Signal))) AttOutInt[0:SOUND_INT_COUNT-1]();

    if(CONFIG::ENABLE_MEGAROM) begin
        SOUND_ATTENUATOR #(
            .MUL(CONFIG::ATT_INT_MEGAROM_MUL),
            .DIV(CONFIG::ATT_INT_MEGAROM_DIV)
        ) u_att_int_megarom (
            .RESET_n,
            .CLK,
            .IN(Sound[SOUND_MEGAROM]),
            .OUT(AttOutInt[SOUND_INT_MEGAROM])
        );
    end
    else begin
        always_comb AttOutInt[SOUND_INT_MEGAROM].connect_dummy();
    end

    if(CONFIG::ENABLE_FM) begin
        SOUND_ATTENUATOR #(
            .MUL(CONFIG::ATT_INT_FM_MUL),
            .DIV(CONFIG::ATT_INT_FM_DIV)
        ) u_att_int_fm (
            .RESET_n,
            .CLK,
            .IN(Sound[SOUND_FM_INT]),
            .OUT(AttOutInt[SOUND_INT_FM])
        );
    end
    else begin
        always_comb AttOutInt[SOUND_INT_FM].connect_dummy();
    end

    SOUND_IF #(.BIT_WIDTH($bits(AttOutInt[0].Signal))) mix_int();

    SOUND_MIXER #(
        .COUNT          (SOUND_INT_COUNT)
    ) u_mixer_int (
        .RESET_n,
        .CLK,
        .IN             (AttOutInt),
        .OUT            (mix_int)
    );

    if($bits(SoundInternal.Signal) == $bits(mix_int.Signal)) begin
        assign SoundInternal.Signal = mix_int.Signal;
    end
    else begin
        wire [$bits(mix_int.Signal)+16-1:0] mix_int_ex = { mix_int.Signal, 16'd0 };
        assign SoundInternal.Signal = mix_int_ex[$bits(mix_int_ex)-1:$bits(mix_int_ex)-$bits(SoundInternal.Signal)];
    end

endmodule


`default_nettype wire
