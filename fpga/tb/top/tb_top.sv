// ============================================================================
// tb_top.sv -- banco de placa entera de V9990TANG (Verilator 5.020, --timing).
//
// DUT: TNCART_BOARD_WT200B_TOP entero, con la lista de ficheros de
// fpga/build_common.tcl (filelist.py) de la configuracion y la variante que
// compile run.sh (v9990 / v9990_megaram / v9990_megaram_nextor, xtal / sync).
// Lo que Verilator no
// puede con lo de Gowin va en modelos del banco (gowin_models.sv: rPLL,
// CLKDIV, MULT18X18, DPB) y el DVI_TX cifrado en tb/video/sim/dvi_tx_stub.sv;
// el RTL no se toca (filelist.py hace copias con cuatro arreglos de sintaxis
// para Verilator, ver alli).
//
// Alrededor, la placa:
//   - cristal de 27 MHz (CLK_27M) y el CLOCK del slot a 3,579545 MHz (en sync
//     es la entrada del rPLL base; el modelo del rPLL saca 30 periodos por
//     periodo de entrada, enganchado en fase);
//   - la SDRAM embebida: modelo de tb/sdram (sdram_model_bl.v, el del MoonTANG
//     con rafagas), con el reloj de la SDRAM que saca el top (O_sdram_clk =
//     CLKOUTP del rPLL base, PSDA_SEL "1000": 180 grados);
//   - el multiplexor de la WonderTANG y el Z80 del banco del bus
//     (tb/bus/tb_bus.sv): tres 74LVC245 por CART_MUX_CS_n (4 ns de reloj a
//     pad, 6 de habilitacion con basura mientras conmuta, 4 de propagacion,
//     1,5 de pad a registro), el transceptor de datos, /WAIT e /INT por un NPN
//     (50 ns en entrar, 300 en soltar), y el Z80A con sus retardos maximos
//     (direccion a 110 ns del flanco, /IORQ a 70 y /RD o /WR a 75 del flanco
//     de T2 en E/S, /MREQ y /RD de memoria a 70/75 de la bajada de T1, /WAIT
//     muestreado en la bajada de TW con 70 ns de setup, dato en la bajada de
//     T3 con 50 ns) a +HZ (3,58 MHz por defecto; el CLOCK del slot sigue a
//     3,58 MHz, como en un MSX turbo). Instrucciones enteras: OUT (n),A e IN
//     A,(n) con su M1 y su operando, LD A,(nn) / LD (nn),A, M1 de NOP (el
//     HALT), el reconocimiento de interrupcion (M1 + /IORQ, IM 1) y su ISR.
//   - el /RESET del MSX (por el mux, grupo 2), /SLTSL decodificado de /MREQ y
//     la pagina (slot_sel: paginas cuyo slot primario es el cartucho), y la
//     memoria del MSX contestando en las demas.
//   - la flash SPI de la Tang (mspi_*): modelo de la orden 03h (lectura) con
//     una ROM de Nextor de prueba de 128 KB en 10_0000h ("AB" al principio) y
//     FFh en el resto; y la microSD (TF_*) en modo SPI: CMD0, CMD8, CMD55,
//     ACMD41 y CMD17 (bloque de 512 bytes con patron), R1 tras un byte de
//     Ncr. Sin Nextor, los pines de las dos tienen que quedarse en reposo.
//
// Comprobaciones siempre activas: el FPGA no conduce D0-D7 sin una lectura
// legitima, ni 30 ns despues de subir /RD, ni a la vez que el Z80 o la
// memoria del MSX; WAIT_TIMEOUT a 0; cero ranuras de VRAM perdidas (asercion
// de t9990_ram.sv); cero errores del modelo de la SDRAM, cero capturas de
// lectura fuera de su ventana de dato valido, nunca DQ con dos conductores y
// solo NOP en sus pines con el controlador en reset; el Z80 nunca retenido
// mas de 3000 TW fuera del arranque.
//
// Fases (+SCEN=full, por defecto; cualquier otro nombre, p. ej. +SCEN=io, sin
// los cuadros de video ni PAL y con una sola /INT: la pasada a 5,37 MHz;
// +SCEN=nomsx, xtal o sync sin MSX: solo LED y pines en reposo):
//   A arranque: POR, rPLL, SDRAM, BUS_OK, guardia (BOOT_HOLD retiene el primer
//     ciclo del Z80 hasta que el sistema esta listo), LED (codigos 0 -> 1 ->
//     5); en MegaRAM, el borrado de 32 KB
//   B puertos: estado P#5, P#8-P#15 a FFh, un puerto ajeno (nadie conduce)
//   C VRAM por P#0 (escritura y lectura, y la SDRAM por la puerta de atras)
//   D paleta por P#1 (escritura y lectura de R, G y B)
//   E LMMV del blitter (pantalla entera y un rectangulo), CE en P#5, y el
//     resultado leido por P#0
//   F /INT del V9990 (VBlank, R#9): INTA + ISR (P#6) en un bucle de HALT
//   G video: B1 BD8 con borde de paleta; NTSC 855 x 524 con DE 720 x 480 y,
//     con R#7 PAL, 855 x 626 con DE 720 x 576; colores en la imagen
//   N Nextor (solo v9990_megaram_nextor): la copia de la flash a la SDRAM
//     (en A, por la puerta de atras), registro FFFFh del slot expandido con
//     Nextor en la subranura 2 de la pagina 1 y la megaROM en la 0 de la
//     pagina 2, "AB" de Nextor (lo que busca la BIOS), sus bancos de 8 KB
//     (6000h, 6800h), proteccion contra escritura y, en full, el SPI de la
//     microSD por el banco 40h (CMD0, CMD8, CMD55 + ACMD41 hasta salir de
//     idle, CMD17 y los 512 bytes del bloque)
//   H MegaRAM (MegaRAM y Nextor): SCC-I RAM al arrancar, tncrom
//     (desbloqueo, ASCII16, bancos por 8000h, lectura de vuelta, proteccion),
//     PLAIN0 (M1 en 0000h-BFFFh, escrituras ignoradas, /RESET lo borra) y el
//     /WAIT de memoria (cada lectura de la ventana espera al dato)
//   R /RESET del MSX en medio de una lectura de P#0 con el V9990 pidiendo
//     /WAIT: el Z80 no se queda colgado y el V9990 vuelve a contestar
//
// Salida: lineas "FALLA ..." y, al final, "RESULTADO ..." y "BANCO: PASA" o
// "BANCO: FALLA". Las lecturas de memoria de la megaROM a mas de 3,58 MHz se
// cuentan pero no hacen fallar el banco (+STRICTMEM=0 por defecto a mas de
// 3,6 MHz: a 5,37 MHz ningun pre-WAIT llega, docs/notas/megaram.md).
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_top;
    localparam bit MEGA = (CONFIG::ENABLE_MEGAROM != CONFIG::DISABLE);
    localparam bit NEXTOR = (CONFIG::ENABLE_NEXTOR != CONFIG::DISABLE);
    localparam string CFGNAME = NEXTOR ? "v9990_megaram_nextor" : MEGA ? "v9990_megaram" : "v9990";
    localparam bit SYNC = (CONFIG_BOARD::SYNC_CPU_CLK != 0);
    localparam [7:0] V99 = 8'h60;

    // retardos de la placa (ns), los de tb/bus/tb_bus.sv
    localparam real T_FPGA_CO = 4.0;
    localparam real T_BUF_EN  = 6.0;
    localparam real T_BUF_PD  = 4.0;
    localparam real T_FPGA_IN = 1.5;
    localparam real T_NPN_ON  = 50.0;
    localparam real T_NPN_OFF = 300.0;
    // retardos del Z80A (ns)
    localparam real T_AD   = 110.0;
    localparam real T_AGL  = 20.0;
    localparam real T_IORQ = 70.0;
    localparam real T_STB  = 75.0;
    localparam real T_MREQ = 70.0;
    localparam real T_SLT  = 15.0;      // /SLTSL tras /MREQ (85 ns de la bajada de T1)
    localparam real T_DOUT = 100.0;
    localparam real T_OFF  = 80.0;
    localparam real T_DHLD = 60.0;
    localparam real T_SU_W = 70.0;
    localparam real T_SU_D = 50.0;

    // ------------------------------------------------------------------
    //  Relojes
    // ------------------------------------------------------------------
    reg clk27 = 1'b0;
    always #(1000.0 / 27.0 / 2.0) clk27 = ~clk27;
    reg slot_run = 1'b0;
    reg slot_clk = 1'b0;
    localparam real T_SLOTCLK = 1000.0 / 3.579545;
    always begin
        #(T_SLOTCLK / 2.0);
        if (slot_run) slot_clk = ~slot_clk;
        else          slot_clk = 1'b0;
    end

    // ------------------------------------------------------------------
    //  Lado MSX
    // ------------------------------------------------------------------
    reg [15:0] s_a       = 16'hFFFF;
    reg        s_mreq_n  = 1'b1;
    reg        s_iorq_n  = 1'b1;
    reg        s_rd_n    = 1'b1;
    reg        s_wr_n    = 1'b1;
    reg        s_m1_n    = 1'b1;
    reg        s_rfsh_n  = 1'b1;
    reg        s_reset_n = 1'b0;
    reg        z_drv     = 1'b0;
    reg [7:0]  z_val     = 8'h00;
    reg        m_drv     = 1'b0;
    reg [7:0]  m_val     = 8'h00;
    reg [3:0]  slot_sel  = 4'b0000;     // paginas cuyo slot primario es el cartucho
    reg [7:0]  z_i       = 8'h3F;       // registro I (direccion de refresco)
    // /SLTSL: el decodificador de slots del MSX, con /MREQ (refresco incluido)
    wire       sltsl_raw = !(!s_mreq_n && slot_sel[s_a[15:14]]);
    reg        s_sltsl_n = 1'b1;
    always @(sltsl_raw) s_sltsl_n <= #(T_SLT) sltsl_raw;
    wire s_cs1_n  = !(!s_sltsl_n && !s_mreq_n && !s_rd_n && s_a[15:14] == 2'b01);
    wire s_cs2_n  = !(!s_sltsl_n && !s_mreq_n && !s_rd_n && s_a[15:14] == 2'b10);
    wire s_cs12_n = s_cs1_n && s_cs2_n;

    // ------------------------------------------------------------------
    //  DUT
    // ------------------------------------------------------------------
    wire        sd_clk, sd_cke, sd_cs_n, sd_cas_n, sd_ras_n, sd_we_n;
    wire [31:0] sd_dq;
    wire [10:0] sd_a;
    wire [1:0]  sd_ba;
    wire [3:0]  sd_dqm;
    wire        cart_busdir_n, cart_int_n, cart_wait_n, cart_data_dir;
    wire [2:0]  cart_mux_cs_n;
    wire [7:0]  cart_mux_sig;
    wire [7:0]  cart_data;
    wire        cart_sltsl_n, cart_rd_n, cart_wr_n, cart_clock;
    wire        dac_bclk, dac_lrclk, dac_din, dac_sdmode_n, led;
    wire        tmds_clk_p, tmds_clk_n;
    wire [2:0]  tmds_data_p, tmds_data_n;
    wire        mspi_cs, mspi_sclk, mspi_mosi, mspi_hold;
    wire        tf_sclk, tf_cmd, tf_dat1, tf_dat2, tf_dat3, uart_tx;
    reg         fl_miso = 1'b1;     // modelo de la flash
    reg         sd_miso = 1'b1;     // modelo de la microSD

    TNCART_BOARD_WT200B_TOP dut (
        .CLK_27M        (clk27),
        .O_sdram_clk    (sd_clk),
        .O_sdram_cke    (sd_cke),
        .O_sdram_cs_n   (sd_cs_n),
        .O_sdram_cas_n  (sd_cas_n),
        .O_sdram_ras_n  (sd_ras_n),
        .O_sdram_wen_n  (sd_we_n),
        .IO_sdram_dq    (sd_dq),
        .O_sdram_addr   (sd_a),
        .O_sdram_ba     (sd_ba),
        .O_sdram_dqm    (sd_dqm),
        .CART_BUSDIR_n  (cart_busdir_n),
        .CART_INT_n     (cart_int_n),
        .CART_WAIT_n    (cart_wait_n),
        .CART_SLTSL_n   (cart_sltsl_n),
        .CART_RD_n      (cart_rd_n),
        .CART_WR_n      (cart_wr_n),
        .CART_CLOCK     (cart_clock),
        .CART_MUX_SIG   (cart_mux_sig),
        .CART_MUX_CS_n  (cart_mux_cs_n),
        .CART_DATA_SIG  (cart_data),
        .CART_DATA_DIR  (cart_data_dir),
        .DAC_BCLK       (dac_bclk),
        .DAC_LRCLK      (dac_lrclk),
        .DAC_DIN        (dac_din),
        .DAC_SDMODE_n   (dac_sdmode_n),
        .LED            (led),
        .tmds_clk_p     (tmds_clk_p),
        .tmds_clk_n     (tmds_clk_n),
        .tmds_data_p    (tmds_data_p),
        .tmds_data_n    (tmds_data_n),
        .mspi_cs        (mspi_cs),
        .mspi_sclk      (mspi_sclk),
        .mspi_miso      (fl_miso),
        .mspi_mosi      (mspi_mosi),
        .mspi_hold      (mspi_hold),
        .TF_SCLK        (tf_sclk),
        .TF_CMD         (tf_cmd),
        .TF_DAT0        (sd_miso),
        .TF_DAT1        (tf_dat1),
        .TF_DAT2        (tf_dat2),
        .TF_DAT3        (tf_dat3),
        .UART_RX        (1'b1),
        .UART_TX        (uart_tx)
    );

    // SDRAM embebida (el reloj es el que saca el top: CLKOUTP, 180 grados)
    sdram_model u_mem (
        .clk    (sd_clk),
        .cke    (sd_cke),
        .cs_n   (sd_cs_n),
        .ras_n  (sd_ras_n),
        .cas_n  (sd_cas_n),
        .we_n   (sd_we_n),
        .addr   (sd_a),
        .ba     (sd_ba),
        .dqm    (sd_dqm),
        .dq     (sd_dq)
    );

    // ------------------------------------------------------------------
    //  Placa: pines directos, multiplexor (3 x 74LVC245), datos, NPN
    //  (tb/bus/tb_bus.sv; retardos de transporte con "always @(x) y <= #d x")
    // ------------------------------------------------------------------
    reg cart_rd_r = 1'b1, cart_wr_r = 1'b1, cart_sltsl_r = 1'b1, cart_clock_r = 1'b0;
    always @(s_rd_n)    cart_rd_r    <= #(T_FPGA_IN) s_rd_n;
    always @(s_wr_n)    cart_wr_r    <= #(T_FPGA_IN) s_wr_n;
    always @(s_sltsl_n) cart_sltsl_r <= #(T_FPGA_IN) s_sltsl_n;
    always @(slot_clk)  cart_clock_r <= #(T_FPGA_IN) slot_clk;
    assign cart_rd_n    = cart_rd_r;
    assign cart_wr_n    = cart_wr_r;
    assign cart_sltsl_n = cart_sltsl_r;
    assign cart_clock   = cart_clock_r;

    reg  [2:0]  msel_a = 3'b110, msel_b = 3'b110;
    always @(cart_mux_cs_n) msel_a <= #(T_FPGA_CO) cart_mux_cs_n;
    always @(msel_a)        msel_b <= #(T_BUF_EN)  msel_a;
    reg  [15:0] a_b   = 16'hFFFF;
    reg  [7:0]  ctl_b = 8'hFF;
    wire [7:0]  ctl_s = {s_m1_n, s_cs12_n, s_rfsh_n, s_reset_n, s_cs2_n, s_cs1_n, s_iorq_n, s_mreq_n};
    always @(s_a)   a_b   <= #(T_BUF_PD) s_a;
    always @(ctl_s) ctl_b <= #(T_BUF_PD) ctl_s;
    reg  [7:0]  mux_val = 8'hFF;
    always @(msel_a or msel_b or a_b or ctl_b) begin
        if (msel_a != msel_b) mux_val = 8'($urandom);            // el buffer conmuta: basura
        else case (msel_b)
            3'b110:  mux_val = a_b[15:8];
            3'b101:  mux_val = a_b[7:0];
            3'b011:  mux_val = ctl_b;
            default: mux_val = 8'($urandom);
        endcase
    end
    reg  [7:0]  mux_pin = 8'hFF;
    always @(mux_val) mux_pin <= #(T_FPGA_IN) mux_val;
    assign cart_mux_sig = mux_pin;

    // datos: lo que la FPGA saca por CART_DATA_SIG con CART_DATA_DIR = 0 cruza el
    // transceptor hacia el slot; con CART_DATA_DIR = 1 el slot entra en la FPGA
    reg        dir_d = 1'b1;
    always @(cart_data_dir) dir_d <= #(T_FPGA_CO + T_BUF_EN) cart_data_dir;
    wire [7:0] fpga_out = cart_data_dir ? 8'hFF : cart_data;
    reg  [7:0] fpga_d = 8'hFF;
    always @(fpga_out) fpga_d <= #(T_FPGA_CO + T_BUF_PD) fpga_out;
    wire buf_drv = !dir_d;
    wire [7:0] s_d = buf_drv ? fpga_d : (z_drv ? z_val : (m_drv ? m_val : 8'hFF));
    reg  [7:0] s_d_in = 8'hFF;
    always @(s_d) s_d_in <= #(T_BUF_PD + T_FPGA_IN) s_d;
    assign cart_data = cart_data_dir ? s_d_in : 8'bzzzz_zzzz;

    // NPN de /WAIT y de /INT (colector abierto)
    reg w_on_d = 1'b0, w_off_d = 1'b0, npn_w = 1'b0;
    always @(cart_wait_n) begin
        w_on_d  <= #(T_FPGA_CO + T_NPN_ON)  cart_wait_n;
        w_off_d <= #(T_FPGA_CO + T_NPN_OFF) cart_wait_n;
    end
    always @(posedge w_on_d) npn_w = 1'b1;
    always @(negedge w_off_d) if (!w_on_d) npn_w = 1'b0;
    reg i_on_d = 1'b0, i_off_d = 1'b0, npn_i = 1'b0;     // npn_i = 1: /INT bajo en el slot
    always @(cart_int_n) begin
        i_on_d  <= #(T_FPGA_CO + T_NPN_ON)  cart_int_n;
        i_off_d <= #(T_FPGA_CO + T_NPN_OFF) cart_int_n;
    end
    always @(posedge i_on_d) npn_i = 1'b1;
    always @(negedge i_off_d) if (!i_on_d) npn_i = 1'b0;

    // ------------------------------------------------------------------
    //  Flash SPI de la Tang: orden 03h (READ) con direccion de 24 bits, modo 0
    //  (el SPI de tnCart saca MOSI en la bajada de SCLK y muestrea MISO en la
    //  subida). ROM de Nextor de prueba (nx_img) en 10_0000h-11_FFFFh; FFh en
    //  el resto
    // ------------------------------------------------------------------
    localparam int unsigned NX_SIZE = 131072;
    localparam int unsigned NX_FLASH = 32'h10_0000;
    function automatic [7:0] nx_img(input int unsigned a);
        if (a == 0) return 8'h41;
        if (a == 1) return 8'h42;
        return 8'((a * 7) ^ (a >> 8) ^ ((a >> 13) * 29) ^ 8'h3C);
    endfunction
    function automatic [7:0] flash_byte(input int unsigned a);
        if (a >= NX_FLASH && a < NX_FLASH + NX_SIZE) return nx_img(a - NX_FLASH);
        return 8'hFF;
    endfunction
    int unsigned fl_bits = 0, fl_dbits = 0;
    reg [31:0] fl_sh = 32'd0;
    reg [7:0]  fl_cmd = 8'h00;
    reg [23:0] fl_addr = 24'h0;
    int n_fl_cs = 0, n_fl_bytes = 0, n_fl_badcmd = 0;
    reg [7:0]  fl_cmd_first = 8'h00;
    reg [23:0] fl_addr_first = 24'h0;
    always @(negedge mspi_cs) begin
        fl_bits = 0; fl_dbits = 0; n_fl_cs++;
    end
    always @(posedge mspi_sclk) if (!mspi_cs) begin
        if (fl_bits < 32) begin
            fl_sh = {fl_sh[30:0], mspi_mosi};
            fl_bits++;
            if (fl_bits == 32) begin
                fl_cmd = fl_sh[31:24]; fl_addr = fl_sh[23:0];
                if (n_fl_cs == 1) begin fl_cmd_first = fl_cmd; fl_addr_first = fl_addr; end
                if (fl_cmd != 8'h03) n_fl_badcmd++;
            end
        end
        else begin
            fl_dbits++;
            if (fl_dbits % 8 == 0) n_fl_bytes++;
        end
    end
    always @(negedge mspi_sclk) if (!mspi_cs && fl_bits == 32) begin
        reg [7:0] b;
        b = flash_byte(fl_addr + fl_dbits / 8);
        fl_miso = b[7 - (fl_dbits % 8)];
    end

    // ------------------------------------------------------------------
    //  microSD en modo SPI (TF_DAT3 = /CS, TF_SCLK, TF_CMD = MOSI, TF_DAT0 =
    //  MISO), modo 0. Una orden son 6 bytes que empiezan por 01xxxxxx; la
    //  respuesta sale tras un byte de Ncr (FFh). CMD0 -> R1 01h; CMD8 -> R7
    //  (01h 00h 00h 01h AAh); CMD55 -> R1; ACMD41 -> 01h la primera vez y 00h
    //  despues (sale de idle); CMD17 -> R1 00h, un FFh, el testigo FEh, 512
    //  bytes (sd_img del bloque) y 2 de CRC; cualquier otra, R1 05h (orden
    //  ilegal)
    // ------------------------------------------------------------------
    function automatic [7:0] sd_img(input int unsigned blk, input int unsigned i);
        return 8'((blk * 13) ^ i ^ (i >> 8) * 91 ^ 8'hA5);
    endfunction
    int unsigned sd_bits = 0;
    reg [7:0] sd_rx = 8'hFF, sd_tx = 8'hFF;
    reg [7:0] sd_cmd [0:5];
    int sd_n = 0;
    byte unsigned sd_q [$];
    bit sd_idle = 1'b1, sd_app = 1'b0;
    int sd_acmd41 = 0;
    int sd_log [$];
    int unsigned sd_blk = 0;
    int n_sd_cs = 0;
    always @(negedge tf_dat3) begin
        sd_bits = 0; sd_n = 0; n_sd_cs++;
        sd_tx = (sd_q.size() > 0) ? sd_q.pop_front() : 8'hFF;
        sd_miso = sd_tx[7];
    end
    always @(posedge tf_sclk) if (!tf_dat3) begin
        sd_rx = {sd_rx[6:0], tf_cmd};
        sd_bits++;
        if (sd_bits == 8) begin
            sd_bits = 0;
            if (sd_n == 0 && sd_rx[7:6] == 2'b01) begin
                sd_cmd[0] = sd_rx; sd_n = 1;
            end
            else if (sd_n > 0) begin
                sd_cmd[sd_n] = sd_rx; sd_n++;
                if (sd_n == 6) begin
                    int c;
                    c = sd_cmd[0][5:0];
                    sd_n = 0;
                    sd_log.push_back(sd_app ? 100 + c : c);
                    sd_q.push_back(8'hFF);                  // Ncr
                    if (sd_app && c == 41) begin
                        sd_acmd41++;
                        if (sd_acmd41 >= 2) sd_idle = 1'b0;
                        sd_q.push_back({7'd0, sd_idle});
                        sd_app = 1'b0;
                    end
                    else begin
                        sd_app = 1'b0;
                        case (c)
                            0:  begin sd_idle = 1'b1; sd_q.push_back(8'h01); end
                            8:  begin sd_q.push_back({7'd0, sd_idle}); sd_q.push_back(8'h00); sd_q.push_back(8'h00);
                                      sd_q.push_back(8'h01); sd_q.push_back(sd_cmd[4]); end
                            55: begin sd_app = 1'b1; sd_q.push_back({7'd0, sd_idle}); end
                            17: begin
                                sd_blk = {sd_cmd[1], sd_cmd[2], sd_cmd[3], sd_cmd[4]};
                                sd_q.push_back(8'h00); sd_q.push_back(8'hFF); sd_q.push_back(8'hFE);
                                for (int i = 0; i < 512; i++) sd_q.push_back(sd_img(sd_blk, i));
                                sd_q.push_back(8'h12); sd_q.push_back(8'h34);
                            end
                            default: sd_q.push_back(8'h05);
                        endcase
                    end
                end
            end
            sd_tx = (sd_q.size() > 0) ? sd_q.pop_front() : 8'hFF;
        end
    end
    always @(negedge tf_sclk) if (!tf_dat3) sd_miso = sd_tx[7 - sd_bits];

    // ------------------------------------------------------------------
    //  Contadores
    // ------------------------------------------------------------------
    int n_fail = 0, n_chk = 0;
    task automatic fail(input string s);
        n_fail++;
        if (n_fail <= 40) $display("FALLA  [%0.3f ms] %s", $realtime / 1.0e6, s);
    endtask
    task automatic check(input bit c, input string s);
        n_chk++;
        if (!c) fail(s);
    endtask
    int n_conflict = 0, n_bad_drive = 0, n_late_drive = 0, n_hang = 0;
    int n_io = 0, n_io_ours = 0, n_mrd_ours = 0, n_m1 = 0, n_inta = 0;
    int n_rd_bad = 0, n_mem_bad = 0, n_mem_nowait = 0;
    int tw_max_io = 0, tw_max_mem = 0;
    int mem_tw_hist [0:7];
    initial for (int i = 0; i < 8; i++) mem_tw_hist[i] = 0;
    bit strict_mem = 1'b1;
    bit boot_phase = 1'b1;              // primer ciclo tras el /RESET: BOOT_HOLD puede retenerlo ms

    // conduccion del bus de datos (tb_bus.sv)
    always @(buf_drv or z_drv or m_drv) if (buf_drv && (z_drv || m_drv)) begin
        n_conflict++;
        if (n_conflict <= 4) $display("FALLA  [%0.3f ms] choque en D0-D7: la placa y el %s conducen a la vez", $realtime / 1.0e6, z_drv ? "Z80" : "MSX");
    end
    localparam real T_DRV = T_FPGA_IN + T_FPGA_CO + T_BUF_EN;
    reg [15:0] s_a_dv = 16'hFFFF;
    reg s_rd_dv = 1'b1, s_iorq_dv = 1'b1, s_m1_dv = 1'b1, s_mreq_dv = 1'b1, s_sltsl_dv = 1'b1;
    always @(s_a)       s_a_dv     <= #(T_DRV) s_a;
    always @(s_rd_n)    s_rd_dv    <= #(T_DRV) s_rd_n;
    always @(s_iorq_n)  s_iorq_dv  <= #(T_DRV) s_iorq_n;
    always @(s_m1_n)    s_m1_dv    <= #(T_DRV) s_m1_n;
    always @(s_mreq_n)  s_mreq_dv  <= #(T_DRV) s_mreq_n;
    always @(s_sltsl_n) s_sltsl_dv <= #(T_DRV) s_sltsl_n;
    bit rd_ours = 1'b0, rd_ours_dv = 1'b0;
    always @(rd_ours) rd_ours_dv <= #(T_DRV) rd_ours;
    always @(posedge buf_drv) begin
        if (!( !s_rd_dv && (rd_ours_dv || (!s_iorq_dv && s_m1_dv && s_a_dv[7:4] == V99[7:4]) || (!s_sltsl_dv && !s_mreq_dv)) )) begin
            n_bad_drive++;
            if (n_bad_drive <= 4) $display("FALLA  [%0.3f ms] la placa conduce D0-D7 sin lectura legitima: A=%04h iorq=%b m1=%b rd=%b mreq=%b sltsl=%b",
                                           $realtime / 1.0e6, s_a_dv, s_iorq_dv, s_m1_dv, s_rd_dv, s_mreq_dv, s_sltsl_dv);
        end
    end
    real t_rd_chg = 0.0;
    always @(s_rd_n) t_rd_chg = $realtime;
    always @(posedge s_rd_n) fork begin
        #30.0;
        if (buf_drv && s_rd_n && ($realtime - t_rd_chg) >= 29.999) begin
            n_late_drive++;
            if (n_late_drive <= 4) $display("FALLA  [%0.3f ms] la placa sigue conduciendo D0-D7 30 ns despues de subir /RD", $realtime / 1.0e6);
        end
    end join_none

    // ------------------------------------------------------------------
    //  Sondas: arranque, guardia, LED, WAIT_TIMEOUT
    // ------------------------------------------------------------------
    wire       pll_ok     = dut.pll_ok;
    wire       base_ready = dut.base_ready;
    wire       sdram_rdy  = dut.sdram_ready;
    wire       rst_n_top  = dut.RESET_n;
    wire       sys_ready  = dut.sys_ready;
    wire       bus_ok     = dut.bus_ok;
    wire       drive_en   = dut.drive_en_27;
    wire       boot_hold  = dut.boot_hold_27;
    wire       wto        = dut.wait_timeout;
    wire [2:0] led_code   = dut.u_led.CODE;
    real t_pll_ok = -1.0, t_sdram = -1.0, t_rst = -1.0, t_sysrdy = -1.0, t_busok = -1.0, t_drive = -1.0;
    always @(posedge pll_ok)    if (t_pll_ok < 0.0) t_pll_ok = $realtime;
    always @(posedge sdram_rdy) if (t_sdram < 0.0)  t_sdram  = $realtime;
    always @(posedge rst_n_top) if (t_rst < 0.0)    t_rst    = $realtime;
    always @(posedge sys_ready) if (t_sysrdy < 0.0) t_sysrdy = $realtime;
    always @(posedge bus_ok)    if (t_busok < 0.0)  t_busok  = $realtime;
    always @(posedge drive_en)  if (t_drive < 0.0)  t_drive  = $realtime;
    // secuencia de codigos del LED (cambios)
    int  led_seq [0:15];
    int  led_n = 0;
    real led_t [0:15];
    reg [2:0] led_prev = 3'd7;
    always @(posedge clk27) begin
        if (led_code != led_prev) begin
            if (led_n < 16) begin led_seq[led_n] = int'(led_code); led_t[led_n] = $realtime; end
            led_n++;
            led_prev <= led_code;
        end
    end
    // LED apagado con el codigo 5 (listo: tiene que estar fijo)
    int n_led_off_ready = 0;
    always @(posedge clk27) if (led_code == 3'd5 && !led) n_led_off_ready++;
    int n_wto = 0;
    always @(posedge wto) n_wto++;
    // BOOT_HOLD visto en el pin durante el arranque
    bit boot_hold_seen = 1'b0;
    always @(posedge clk27) if (boot_hold && cart_wait_n) boot_hold_seen = 1'b1;

    // SDRAM: errores del modelo con el controlador en reset y despues (hasta
    // el arreglo de sdram.sv de este banco, SDRAM_CMD no tenia valor de reset:
    // los pines llevaban 0000 = MODE REGISTER SET con A = 0 en cada flanco
    // mientras el reloj corre antes de BASE_READY, 262 406 flancos en el
    // arranque); captura de las lecturas dentro de la ventana de dato valido
    // del modelo (como tb/sdram/tb_uma_sdram.sv: STATE_FETCH_RDATA_1/2 =
    // 38/39) y bus de datos sin dos conductores
    int n_sd_err_rst = 0;
    // (la cuenta se toma dos ciclos despues de BASE_READY: el flanco del reloj
    // de la SDRAM que cae medio ciclo despues aun ve el 0000 del reset)
    always @(posedge base_ready) begin
        repeat (2) @(posedge dut.CLK_MEM);
        n_sd_err_rst = u_mem.n_err;
    end
    int n_sd_win = 0, n_sd_cont = 0;
    // comandos en los pines de la SDRAM con su controlador en reset (cada
    // flanco del reloj de la SDRAM con RESET_n de sdram.sv a 0 y CS_n a 0 tiene
    // que ser NOP: CS_n = 0, RAS_n = CAS_n = WE_n = 1)
    int n_sd_rst_cmd = 0;
    reg [3:0] sd_rst_cmd_first = 4'hF;
    always @(posedge sd_clk) begin
        if (!dut.u_sdram.RESET_n && !sd_cs_n && {sd_ras_n, sd_cas_n, sd_we_n} != 3'b111) begin
            if (n_sd_rst_cmd == 0) sd_rst_cmd_first = {sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n};
            n_sd_rst_cmd++;
        end
    end
    always @(posedge dut.CLK_MEM) begin
        if (dut.u_sdram.cmd_is_read && dut.u_sdram.state == 7'd38 && u_mem.dq_mode != 2'd2 ||
            dut.u_sdram.cmd_is_read && dut.u_sdram.state == 7'd39 &&
            (dut.u_sdram.save_din_size == 3'b011 || dut.u_sdram.save_din_size == 3'b111) && u_mem.dq_mode != 2'd2) begin
            n_sd_win++;
            if (n_sd_win <= 4) $display("FALLA  [%0.6f ms] SDRAM: captura fuera de la ventana del dato (estado %0d, dq_mode %0d, %0d lecturas antes; ultimo flanco del reloj de la SDRAM hace %0.3f ns)",
                                        $realtime / 1.0e6, dut.u_sdram.state, u_mem.dq_mode, u_mem.n_rd, $realtime - t_sdclk);
        end
        if (u_mem.dq_mode != 2'd0 && dut.u_sdram.sdram_DQ_OUT_ENA_n == 1'b0) n_sd_cont++;
    end
    real t_sdclk = 0.0;
    always @(posedge sd_clk) t_sdclk = $realtime;

    // ------------------------------------------------------------------
    //  Video: lo que BOARD_REV1_TMDS_OUT entrega al DVI_TX (stub)
    // ------------------------------------------------------------------
    wire       vclk = dut.CLK_TMDS_P;
    wire       v_vs = dut.u_tmds.DVI_TX_Top_inst.I_rgb_vs;
    wire       v_hs = dut.u_tmds.DVI_TX_Top_inst.I_rgb_hs;
    wire       v_de = dut.u_tmds.DVI_TX_Top_inst.I_rgb_de;
    wire [7:0] v_r  = dut.u_tmds.DVI_TX_Top_inst.I_rgb_r;
    wire [7:0] v_g  = dut.u_tmds.DVI_TX_Top_inst.I_rgb_g;
    wire [7:0] v_b  = dut.u_tmds.DVI_TX_Top_inst.I_rgb_b;
    localparam int NFR = 64;
    int fr_n = 0;
    int fr_hmin [0:NFR-1], fr_hmax [0:NFR-1], fr_lines [0:NFR-1], fr_delines [0:NFR-1];
    int fr_demin [0:NFR-1], fr_demax [0:NFR-1], fr_red [0:NFR-1], fr_grn [0:NFR-1], fr_blu [0:NFR-1];
    real fr_t [0:NFR-1];
    int c_h = 0, c_hmin = 0, c_hmax = 0, c_lines = 0, c_delines = 0, c_de = 0, c_demin = 0, c_demax = 0;
    int c_red = 0, c_grn = 0, c_blu = 0;
    bit pv_vs = 1'b0, pv_hs = 1'b0, v_started = 1'b0;
    // +VDBG: los colores mas frecuentes dentro de DE en cada cuadro
    bit vdbg = 1'b0;
    initial vdbg = $test$plusargs("VDBG");
    int cmap [int];
    always @(posedge vclk) begin
        bit hs_rise;
        hs_rise = v_hs && !pv_hs;
        if (v_de) begin
            c_de++;
            if (v_r == 8'hFF && v_g == 8'h00 && v_b == 8'h00) c_red++;
            if (v_r == 8'h00 && v_g == 8'hFF && v_b == 8'h00) c_grn++;
            if (v_r == 8'h00 && v_g == 8'h00 && v_b == 8'hFF) c_blu++;
            if (vdbg) begin
                if (cmap.exists({v_r, v_g, v_b})) cmap[{v_r, v_g, v_b}]++;
                else cmap[{v_r, v_g, v_b}] = 1;
            end
        end
        if (hs_rise) begin
            if (c_lines > 0) begin
                if (c_lines == 1 || c_h < c_hmin) c_hmin = c_h;
                if (c_lines == 1 || c_h > c_hmax) c_hmax = c_h;
            end
            if (c_de > 0) begin
                if (c_delines == 0 || c_de < c_demin) c_demin = c_de;
                if (c_delines == 0 || c_de > c_demax) c_demax = c_de;
                c_delines++;
            end
            c_de = 0;
            c_h = 0;
            c_lines++;
        end
        c_h++;
        if (v_vs && !pv_vs) begin
            // VS y HS suben en el mismo flanco: esa linea ya es del cuadro nuevo
            if (v_started && fr_n < NFR) begin
                fr_hmin[fr_n] = c_hmin; fr_hmax[fr_n] = c_hmax; fr_lines[fr_n] = c_lines - (hs_rise ? 1 : 0);
                fr_delines[fr_n] = c_delines; fr_demin[fr_n] = c_demin; fr_demax[fr_n] = c_demax;
                fr_red[fr_n] = c_red; fr_grn[fr_n] = c_grn; fr_blu[fr_n] = c_blu; fr_t[fr_n] = $realtime;
            end
            if (vdbg && v_started) begin
                int k, best, bc;
                $write("  [VDBG] cuadro %0d, colores en DE:", fr_n);
                for (int r = 0; r < 6 && cmap.size() > 0; r++) begin
                    best = -1; bc = -1;
                    foreach (cmap[c]) if (cmap[c] > bc) begin bc = cmap[c]; best = c; end
                    $write(" %06h x%0d", best, bc);
                    cmap.delete(best);
                end
                $display("");
                cmap.delete();
            end
            if (v_started) fr_n++;
            v_started = 1'b1;
            c_lines = hs_rise ? 1 : 0; c_delines = 0; c_red = 0; c_grn = 0; c_blu = 0;
        end
        pv_vs = v_vs;
        pv_hs = v_hs;
    end

    // ------------------------------------------------------------------
    //  Z80
    // ------------------------------------------------------------------
    real TZ = 1.0e9 / 3579545.0;
    real zt = 0.0;
    reg [15:0] pc = 16'hC000;

    task automatic at(input real t);
        if (t > $realtime) #(t - $realtime);
    endtask
    task automatic idle(input int nt);
        zt = zt + nt * TZ;
    endtask

    task automatic addr_phase(input real t1, input [15:0] a);
        fork
            begin
                at(t1 + T_AGL);
                s_a = 16'($urandom);
                at(t1 + T_AD);
                s_a = a;
            end
        join_none
    endtask

    // /WAIT en la bajada de TW (o T2): camino pesimista si cambia dentro del setup
    task automatic wait_loop(inout real tf, output int ntw);
        bit we, wn;
        int lim;
        ntw = 0;
        lim = boot_phase ? (NEXTOR ? 1000000 : 400000) : 3000;
        forever begin
            at(tf - T_SU_W); we = npn_w;
            at(tf);          wn = npn_w;
            if (we != wn) wn = 1'b1;
            if (!wn || !s_reset_n) break;
            tf = tf + TZ;
            ntw = ntw + 1;
            if (ntw > lim) begin
                n_hang++;
                fail($sformatf("Z80 retenido mas de %0d TW", lim));
                break;
            end
        end
    endtask

    // ciclo de E/S (4 T + esperas)
    task automatic io_cycle(input bit wr, input [15:0] a, input [7:0] wd, output [7:0] rv, output int ntw);
        real t1, t2, tf, t3f, ts;
        t1 = zt;
        at(t1);
        addr_phase(t1, a);
        if (wr) fork begin at(t1 + TZ / 2.0 + T_DOUT); z_val = wd; z_drv = 1'b1; end join_none
        t2 = t1 + TZ;
        fork begin at(t2 + T_IORQ); s_iorq_n = 1'b0; end join_none
        ts = t2 + T_STB;
        fork
            begin
                at(ts);
                if (wr) s_wr_n = 1'b0; else s_rd_n = 1'b0;
                if (!wr && a[7:4] == V99[7:4]) rd_ours = 1'b1;
            end
        join_none
        tf = t2 + 1.5 * TZ;
        wait_loop(tf, ntw);
        t3f = tf + TZ;
        rv = 8'hFF;
        if (!wr) begin
            at(t3f - T_SU_D); rv = s_d;
            at(t3f);
            if (rv !== s_d) begin
                if (s_reset_n) fail($sformatf("IN %02h: dato inestable en la ventana de setup (%02h -> %02h)", a[7:0], rv, s_d));
            end
            rv = s_d;
        end
        fork begin at(t3f + T_OFF); s_rd_n = 1'b1; s_wr_n = 1'b1; s_iorq_n = 1'b1; rd_ours = 1'b0; end join_none
        if (wr) fork begin at(t3f + T_OFF + T_DHLD); z_drv = 1'b0; end join_none
        zt = t3f + TZ / 2.0;
        n_io++;
        if (a[7:4] == V99[7:4]) begin
            n_io_ours++;
            if (ntw > tw_max_io) tw_max_io = ntw;
        end
    endtask

    // M1 (+ refresco): ours = la pagina es del cartucho (el opcode lo da el
    // cartucho); si no, la memoria del MSX contesta op
    task automatic z_m1(input [15:0] a, input [7:0] op, input int extra_t, output [7:0] got, output int ntw);
        real t1, tf, t3r;
        bit ours;
        t1 = zt;
        at(t1);
        ours = slot_sel[a[15:14]];
        addr_phase(t1, a);
        fork begin at(t1 + 80.0); s_m1_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_STB); s_rd_n = 1'b0; end join_none
        if (!ours) fork begin at(t1 + TZ / 2.0 + T_STB + 60.0); m_val = op; m_drv = 1'b1; end join_none
        tf = t1 + 1.5 * TZ;
        wait_loop(tf, ntw);
        t3r = tf + TZ / 2.0;
        at(t3r - T_SU_D); got = s_d;
        at(t3r);
        if (ours && got !== s_d && s_reset_n) fail($sformatf("M1 %04h: opcode inestable en la ventana de setup", a));
        got = s_d;
        fork
            begin
                at(t3r + 20.0);  s_a = 16'($urandom);
                at(t3r + T_OFF); s_mreq_n = 1'b1; s_rd_n = 1'b1; s_m1_n = 1'b1; s_rfsh_n = 1'b0; s_a = {z_i, 8'($urandom)};
                at(t3r + T_OFF + 20.0); m_drv = 1'b0;
                at(t3r + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0;
                at(t3r + 1.5 * TZ + T_MREQ); s_mreq_n = 1'b1;
                at(t3r + 2.0 * TZ + 20.0); s_rfsh_n = 1'b1;
            end
        join_none
        zt = t3r + (2.0 + extra_t) * TZ;
        n_m1++;
    endtask

    // lectura de memoria (3 T)
    task automatic z_mrd(input [15:0] a, input [7:0] md, output [7:0] got, output int ntw);
        real t1, tf, t3f, ts;
        bit ours;
        t1 = zt;
        at(t1);
        ours = slot_sel[a[15:14]];
        addr_phase(t1, a);
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        ts = t1 + TZ / 2.0 + T_STB;
        fork begin at(ts); s_rd_n = 1'b0; end join_none
        if (!ours) fork begin at(ts + 60.0); m_val = md; m_drv = 1'b1; end join_none
        tf = t1 + 1.5 * TZ;
        wait_loop(tf, ntw);
        t3f = tf + TZ;
        at(t3f - T_SU_D); got = s_d;
        at(t3f);
        if (ours && got !== s_d && s_reset_n) begin
            if (strict_mem) fail($sformatf("lectura %04h: dato inestable en la ventana de setup", a));
            got = 8'hXX;
        end
        else got = s_d;
        fork
            begin
                at(t3f + T_OFF); s_mreq_n = 1'b1; s_rd_n = 1'b1;
                at(t3f + T_OFF + 20.0); m_drv = 1'b0;
            end
        join_none
        zt = t3f + TZ / 2.0;
    endtask

    // escritura de memoria (3 T)
    task automatic z_mwr(input [15:0] a, input [7:0] d);
        real t1, tf, t3f;
        int  ntw;
        t1 = zt;
        at(t1);
        addr_phase(t1, a);
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_DOUT); z_val = d; z_drv = 1'b1; end join_none
        fork begin at(t1 + 1.5 * TZ + T_STB); s_wr_n = 1'b0; end join_none
        tf = t1 + 1.5 * TZ;
        wait_loop(tf, ntw);
        t3f = tf + TZ;
        fork
            begin
                at(t3f + T_OFF); s_mreq_n = 1'b1; s_wr_n = 1'b1;
                at(t3f + T_OFF + T_DHLD); z_drv = 1'b0;
            end
        join_none
        zt = t3f + TZ / 2.0;
    endtask

    // reconocimiento de interrupcion (IM 1): M1 con dos esperas automaticas y
    // /IORQ en lugar de /MREQ; nadie tiene que conducir D0-D7 (en IM 1 el Z80
    // no lee el dato)
    task automatic z_inta(input [15:0] a);
        real t1, tf, t3r;
        int  ntw;
        t1 = zt;
        at(t1);
        addr_phase(t1, a);
        fork begin at(t1 + 80.0); s_m1_n = 1'b0; end join_none
        fork begin at(t1 + 2.5 * TZ + T_IORQ); s_iorq_n = 1'b0; end join_none
        tf = t1 + 3.5 * TZ;                 // bajada de TW*2
        wait_loop(tf, ntw);
        t3r = tf + TZ / 2.0;
        fork
            begin
                at(t3r + T_OFF); s_iorq_n = 1'b1; s_m1_n = 1'b1; s_rfsh_n = 1'b0; s_a = {z_i, 8'($urandom)};
                at(t3r + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0;
                at(t3r + 1.5 * TZ + T_MREQ); s_mreq_n = 1'b1;
                at(t3r + 2.0 * TZ + 20.0); s_rfsh_n = 1'b1;
            end
        join_none
        zt = t3r + 2.0 * TZ;
        n_inta++;
    endtask

    task automatic zt_now();
        if ($realtime + 10.0 > zt) zt = $realtime + 10.0;
    endtask

    // ------------------------------------------------------------------
    //  Instrucciones (cada una, una tarea llamada desde pocos sitios: Verilator
    //  expande cada llamada a una tarea con esperas en la corrutina que la hace)
    // ------------------------------------------------------------------
    reg [7:0] areg = 8'h00;
    function automatic [15:0] pc_next(input [15:0] p, input int n);
        pc_next = (p >= 16'hEFF0) ? 16'hC000 : p + 16'(n);
    endfunction
    // OUT (n),A
    task automatic ins_out(input [7:0] port, input [7:0] v);
        reg [7:0] dmy;
        int ntw;
        z_m1(pc, 8'hD3, 0, dmy, ntw);
        z_mrd(pc + 16'd1, port, dmy, ntw);
        pc = pc_next(pc, 2);
        io_cycle(1'b1, {areg, port}, v, dmy, ntw);
        areg = v;
    endtask
    // IN A,(n)
    task automatic ins_in(input [7:0] port, output [7:0] d);
        reg [7:0] dmy;
        int ntw;
        z_m1(pc, 8'hDB, 0, dmy, ntw);
        z_mrd(pc + 16'd1, port, dmy, ntw);
        pc = pc_next(pc, 2);
        io_cycle(1'b0, {areg, port}, 8'h00, d, ntw);
        areg = d;
    endtask

    // ------------------------------------------------------------------
    //  Programa: una cola de operaciones y un solo interprete
    // ------------------------------------------------------------------
    typedef enum int {
        OP_OUT, OP_IN, OP_MRD, OP_MWR, OP_FETCH, OP_POLL, OP_WAITINT, OP_FRAMES,
        OP_SLOT, OP_I, OP_RESET, OP_RESETWAIT, OP_CHK, OP_MPOLL, OP_LASTV
    } op_t;
    typedef struct {
        op_t        op;
        int         a;      // puerto o direccion
        int         v;      // dato (OUT/MWR), esperado (IN/MRD/FETCH/POLL), cuenta, id
        int         m;      // mascara de la comparacion (0 = no se compara)
        string      what;
    } zop_t;
    zop_t q [$];

    function automatic void p_op(input op_t op, input int a, input int v, input int m, input string what);
        zop_t o;
        o.op = op; o.a = a; o.v = v; o.m = m; o.what = what;
        q.push_back(o);
    endfunction
    function automatic void p_out(input [7:0] port, input [7:0] v);
        p_op(OP_OUT, int'(port), int'(v), 0, "");
    endfunction
    function automatic void p_in(input [7:0] port, input [7:0] e, input [7:0] m, input string what);
        p_op(OP_IN, int'(port), int'(e), int'(m), what);
    endfunction
    function automatic void p_mrd(input [15:0] a, input [7:0] e, input [7:0] m, input string what);
        p_op(OP_MRD, int'(a), int'(e), int'(m), what);
    endfunction
    function automatic void p_mwr(input [15:0] a, input [7:0] v);
        p_op(OP_MWR, int'(a), int'(v), 0, "");
    endfunction
    function automatic void p_fetch(input [15:0] a, input [7:0] e, input string what);
        p_op(OP_FETCH, int'(a), int'(e), 8'hFF, what);
    endfunction
    function automatic void p_chk(input int id, input string what);
        p_op(OP_CHK, 0, id, 0, what);
    endfunction
    function automatic [7:0] P(input int n);
        P = V99 + n[7:0];
    endfunction
    function automatic void p_wreg(input [5:0] n, input [7:0] v);
        p_out(P(4), {2'b00, n});
        p_out(P(3), v);
    endfunction
    function automatic void p_vram_w(input [18:0] a);
        p_out(P(4), 8'h00);
        p_out(P(3), a[7:0]); p_out(P(3), a[15:8]); p_out(P(3), {5'b00000, a[18:16]});
    endfunction
    function automatic void p_vram_r(input [18:0] a);
        p_out(P(4), 8'h03);
        p_out(P(3), a[7:0]); p_out(P(3), a[15:8]); p_out(P(3), {5'b00000, a[18:16]});
    endfunction
    // VRAM leida por P#0 en (x, y) de B1 (256 bytes por linea en BD8)
    function automatic void p_vram_chk(input int x, input int y, input [7:0] e, input string what);
        p_vram_r(19'(y * 256 + x));
        p_in(P(0), e, 8'hFF, what);
    endfunction
    // LMMV: R#32..R#52 por P#4 = 32 con autoincremento, y CE de P#5
    function automatic void p_lmmv(input int dx, input int dy, input int nx, input int ny, input [15:0] fc);
        reg [7:0] v [0:20];
        v[ 0] = 0; v[ 1] = 0; v[ 2] = 0; v[ 3] = 0;
        v[ 4] = 8'(dx); v[ 5] = 8'(dx >> 8); v[ 6] = 8'(dy); v[ 7] = 8'(dy >> 8);
        v[ 8] = 8'(nx); v[ 9] = 8'(nx >> 8); v[10] = 8'(ny); v[11] = 8'(ny >> 8);
        v[12] = 8'h00;  v[13] = 8'h0C;  v[14] = 8'hFF; v[15] = 8'hFF;
        v[16] = fc[7:0]; v[17] = fc[15:8]; v[18] = 8'h00; v[19] = 8'h00;
        v[20] = 8'h20;                  // LMMV
        p_out(P(4), 8'd32);
        for (int s = 0; s < 21; s++) p_out(P(3), v[s]);
        p_op(OP_POLL, int'(P(5)), 0, 8'h01, "CE de P#5 tras el LMMV");
    endfunction

    // MegaRAM: atributo, llave, imagen
    localparam [7:0] F_WP = 8'h01, F_BANK16 = 8'h02, F_SCC = 8'h10, F_SCC_I = 8'h20, F_CONT = 8'h40, F_ENABLE = 8'h80;
    function automatic void p_unlock();
        p_mwr(16'h0000, 8'hAB); p_mwr(16'h0001, 8'hCD); p_mwr(16'h0002, 8'h98); p_mwr(16'h0003, 8'h76);
    endfunction
    function automatic void p_lock();
        for (int i = 0; i < 4; i++) p_mwr(16'(i), 8'h00);
    endfunction
    function automatic void p_attr(input [7:0] flags, input [7:0] vmask, input [15:0] amask,
                                   input [15:0] b0, input [15:0] b1, input [15:0] b2, input [15:0] b3,
                                   input [7:0] i0, input [7:0] i1, input [7:0] i2, input [7:0] i3, input [7:0] mode);
        reg [7:0] v [0:19];
        v[0] = flags; v[1] = vmask; v[2] = amask[7:0]; v[3] = amask[15:8];
        v[4] = b0[7:0];  v[5] = b0[15:8];  v[6] = i0;  v[7] = 8'h00;
        v[8] = b1[7:0];  v[9] = b1[15:8];  v[10] = i1; v[11] = 8'h00;
        v[12] = b2[7:0]; v[13] = b2[15:8]; v[14] = i2; v[15] = 8'h00;
        v[16] = b3[7:0]; v[17] = b3[15:8]; v[18] = i3; v[19] = mode;
        for (int i = 0; i < 20; i++) p_mwr(16'h000C + 16'(i), v[i]);
    endfunction
    function automatic [7:0] img(input int unsigned bank, input int unsigned off);
        return 8'((bank * 8'd37) ^ (off >> 8) ^ off ^ 8'hC3);
    endfunction

    // ------------------------------------------------------------------
    //  SDRAM por la puerta de atras
    // ------------------------------------------------------------------
    function automatic [31:0] pat_word(input int unsigned w);
        pat_word = (w * 32'h9E37_79B9) ^ 32'h5A5A_C3C3;
    endfunction
    function automatic [7:0] sd_byte(input int unsigned a);
        reg [31:0] w;
        w = u_mem.mem[a >> 2];
        sd_byte = w[8 * (a & 3) +: 8];
    endfunction
    function automatic [7:0] pat_byte(input int unsigned a);
        reg [31:0] w;
        w = pat_word(a >> 2);
        pat_byte = w[8 * (a & 3) +: 8];
    endfunction
    // byte de la VRAM desde RAM_ADDR_VRAM, como lo coloca t9990_ram.sv: en P1
    // 2*A[17:0] + A[18] (tb/bus/tb_bus.sv), en los modos de mapa de bits (Bx)
    // la direccion tal cual
    function automatic [7:0] vram_peek(input [18:0] a);
        reg [18:0] b;
        b = {a[17:0], a[18]};
        vram_peek = sd_byte(CONFIG::RAM_ADDR_VRAM + b);
    endfunction
    function automatic [7:0] vram_peek_bx(input [18:0] a);
        vram_peek_bx = sd_byte(CONFIG::RAM_ADDR_VRAM + a);
    endfunction

    // ------------------------------------------------------------------
    //  Estado del programa y comprobaciones sin esperas (OP_CHK)
    // ------------------------------------------------------------------
    string scen = "full";
    int    hz = 3579545;
    reg [7:0] img_v [0:63];
    reg [7:0] pr [0:7], pgr [0:7], pb [0:7];
    int unsigned banks16 [5] = '{8'h00, 8'h01, 8'h7F, 8'h80, 8'hFF};
    int unsigned offs16  [3] = '{16'h0000, 16'h1234, 16'h3FFF};
    real   t_boot_m1 = -1.0;
    reg [7:0] last_v = 8'h00;
    int    poll_max = 0;
    int    f0 = 0;
    // interrupciones
    int  n_int = 0;
    real int_t [0:63];
    real t_int_rise = 0.0;
    always @(posedge npn_i) t_int_rise = $realtime;
    // /RESET con /WAIT (OP_RESETWAIT)
    real t_rw_reset = -1.0, t_rw_wait_drop = -1.0, t_rw_m1 = -1.0;
    bit  rw_armed = 1'b0;
    always @(posedge cart_wait_n) if (rw_armed && s_reset_n) begin
        // el V9990 (o el pre-WAIT) pide /WAIT en la lectura de P#0: /RESET
        // del MSX 50 ns despues, en medio del ciclo (el Z80 lo aborta: suelta
        // /RD, /WR, /IORQ y /MREQ)
        fork begin
            #50.0;
            if (rw_armed && s_reset_n && !s_rd_n && !s_iorq_n) begin
                rw_armed = 1'b0;
                s_reset_n = 1'b0;
                t_rw_reset = $realtime;
                s_rd_n = 1'b1; s_wr_n = 1'b1; s_iorq_n = 1'b1; s_mreq_n = 1'b1; s_m1_n = 1'b1; rd_ours = 1'b0;
            end
        end join_none
    end
    always @(negedge cart_wait_n) if (t_rw_reset >= 0.0 && t_rw_wait_drop < 0.0) t_rw_wait_drop = $realtime;

    localparam int CK_PRINT = 0, CK_VRAM = 1, CK_LMMV = 2, CK_NTSC = 3, CK_PAL = 4, CK_SCCI = 5,
                   CK_TNCROM = 6, CK_PROT = 7, CK_PLAIN = 8, CK_MEMSUM = 9, CK_RESET = 10, CK_SAVEF = 11,
                   CK_INT1 = 12, CK_NXPROT = 13, CK_SD = 14;

    function automatic void chk_frame(input int k, input int lines, input int delines, input string what);
        $display("  cuadro %0d (%s): %0d lineas de %0d..%0d puntos, DE en %0d lineas de %0d..%0d puntos, rojo %0d, verde %0d, azul %0d",
                 k, what, fr_lines[k], fr_hmin[k], fr_hmax[k], fr_delines[k], fr_demin[k], fr_demax[k], fr_red[k], fr_grn[k], fr_blu[k]);
        check(fr_hmin[k] == 855 && fr_hmax[k] == 855, $sformatf("%s: linea de %0d..%0d puntos, esperados 855", what, fr_hmin[k], fr_hmax[k]));
        check(fr_lines[k] == lines, $sformatf("%s: %0d lineas, esperadas %0d", what, fr_lines[k], lines));
        check(fr_delines[k] == delines, $sformatf("%s: DE en %0d lineas, esperadas %0d", what, fr_delines[k], delines));
        check(fr_demin[k] == 720 && fr_demax[k] == 720, $sformatf("%s: DE de %0d..%0d puntos, esperados 720", what, fr_demin[k], fr_demax[k]));
    endfunction
    function automatic void chk_int_period(input real lo, input real hi, input string what);
        real per;
        if (n_int < 3) begin
            fail($sformatf("/INT %s: solo %0d atendidas", what, n_int));
            return;
        end
        per = int_t[n_int - 1] - int_t[n_int - 2];
        $display("  /INT: %0d atendidas, periodo %0.3f ms", n_int, per / 1.0e6);
        check(per > lo && per < hi, $sformatf("/INT %s: periodo %0.3f ms, esperado de %0.1f a %0.1f", what, per / 1.0e6, lo / 1.0e6, hi / 1.0e6));
    endfunction

    int red_ntsc = 0;
    function automatic void chk_img(input int k, input string what);
        if (CONFIG::UPSCAN_BLEND != 0) begin
            check(fr_grn[k] == 159 * 64, $sformatf("%s: %0d puntos verdes (rectangulo), esperados 10 176", what, fr_grn[k]));
            check(fr_blu[k] == 640 * 424 - 160 * 64 - 424 - 64, $sformatf("%s: %0d puntos azules (imagen), esperados 260 632", what, fr_blu[k]));
        end
        else begin
            // BLEND = 0 (punto mas cercano): sin mezclas; sin comprobar en esta
            // version del banco, con un margen
            check(fr_grn[k] >= 159 * 64 && fr_grn[k] <= 161 * 64, $sformatf("%s: %0d puntos verdes, esperados ~10 240", what, fr_grn[k]));
            check(fr_blu[k] >= 260000 && fr_blu[k] <= 261500, $sformatf("%s: %0d puntos azules, esperados ~261 120", what, fr_blu[k]));
        end
    endfunction
    function automatic void chkpt(input int id, input string what);
        int bad, k;
        bad = 0;
        case (id)
            CK_PRINT: $display("-- %s (%0.3f ms)", what, $realtime / 1.0e6);
            CK_SAVEF: f0 = fr_n;
            CK_VRAM: begin
                for (int i = 0; i < 64; i++) if (vram_peek(19'h1_2340 + 19'(i)) !== img_v[i]) bad++;
                check(bad == 0, $sformatf("VRAM: %0d de 64 bytes mal en la SDRAM", bad));
            end
            CK_LMMV: begin
                $display("  LMMV: CE bajo tras %0d lecturas de P#5 (la mas larga)", poll_max);
                for (int y = 90; y < 122; y++) for (int x = 96; x < 160; x++) if (vram_peek_bx(19'(y * 256 + x)) !== 8'hE0) bad++;
                for (int x = 0; x < 256; x++) if (vram_peek_bx(19'(89 * 256 + x)) !== 8'h03) bad++;
                check(bad == 0, $sformatf("LMMV: %0d bytes mal en la SDRAM", bad));
            end
            CK_INT1: begin
                $display("  /INT: %0d atendidas", n_int);
                check(n_int >= 1, "/INT: ninguna atendida");
            end
            CK_NTSC: begin
                // B1 de 256 x 212 -> 640 x 424 puntos de salida (2,5 x 2): el
                // rectangulo verde de 64 x 32 ocupa 160 x 64 y el fondo azul el
                // resto de los 640 x 424; con BLEND = 1 la columna de salida en la
                // que empieza cada color mezcla los dos (una por linea a la
                // izquierda de la imagen, 424, y del rectangulo, 64): verde puro
                // 159 x 64 = 10 176, azul puro 261 120 - 424 - 64 = 260 632. El
                // borde rojo (paleta 5) es el resto de las 480 lineas de DE salvo
                // las columnas fuera de la zona de borde del V9990 (negras)
                k = f0 + 2;
                chk_frame(k, 524, 480, "NTSC");
                chk_img(k, "NTSC");
                check(fr_red[k] > 55000 && fr_red[k] < 75000, $sformatf("NTSC: %0d puntos rojos (borde de la paleta 5), esperados ~62 000", fr_red[k]));
                red_ntsc = fr_red[k];
                chk_int_period(16.0e6, 17.4e6, "NTSC");
            end
            CK_PAL: begin
                // la misma imagen en 576 lineas de DE: el borde crece
                k = f0 + 2;
                chk_frame(k, 626, 576, "PAL");
                chk_img(k, "PAL");
                check(fr_red[k] > red_ntsc + 50000, $sformatf("PAL: %0d puntos rojos (borde), %0d en NTSC: el borde no crece", fr_red[k], red_ntsc));
                chk_int_period(19.2e6, 20.6e6, "PAL");
            end
            CK_SCCI:
                check(sd_byte(32'h1FE000) == 8'h11 && sd_byte(32'h1FFFFF) == 8'h12 && sd_byte(32'h100123) == 8'h22,
                      "SCC-I: las escrituras no llegaron a la SDRAM (bancos FFh y 80h)");
            CK_TNCROM: begin
                foreach (banks16[i]) foreach (offs16[j])
                    if (sd_byte(banks16[i] * 16384 + offs16[j]) !== img(banks16[i], offs16[j])) bad++;
                check(bad == 0, $sformatf("tncrom: %0d bytes de los bancos no llegaron a la SDRAM", bad));
            end
            CK_PROT:  check(sd_byte(32'h3FC000) == img(8'hFF, 0), "ASCII16 protegido: la escritura llego a la SDRAM");
            CK_PLAIN: check(sd_byte(32'h38) == img(0, 16'h38), "PLAIN0: la escritura llego a la SDRAM");
            CK_MEMSUM:
                $display("  /WAIT de memoria: %0d lecturas del slot, TW por lectura: 0:%0d 1:%0d 2:%0d 3:%0d 4+:%0d; %0d mal leidas",
                         n_mrd_ours, mem_tw_hist[0], mem_tw_hist[1], mem_tw_hist[2], mem_tw_hist[3],
                         mem_tw_hist[4] + mem_tw_hist[5] + mem_tw_hist[6] + mem_tw_hist[7], n_mem_bad);
            CK_NXPROT:
                check(sd_byte(CONFIG::RAM_ADDR_BIOS_NEXTOR + 5 * 8192) == nx_img(5 * 8192) &&
                      sd_byte(CONFIG::RAM_ADDR_BIOS_NEXTOR + 15 * 8192 + 16'h1FFF) == nx_img(15 * 8192 + 16'h1FFF),
                      "Nextor: una escritura en la ROM llego a la SDRAM");
            CK_SD: begin
                string l;
                l = "";
                foreach (sd_log[i]) l = {l, $sformatf(" %s%0d", sd_log[i] >= 100 ? "A" : "", sd_log[i] % 100)};
                $display("  microSD: ordenes recibidas:%s; /CS bajo %0d veces; ACMD41 %0d", l, n_sd_cs, sd_acmd41);
                check(sd_log.size() == 7 && sd_log[0] == 0 && sd_log[1] == 8 && sd_log[2] == 55 && sd_log[3] == 141 &&
                      sd_log[4] == 55 && sd_log[5] == 141 && sd_log[6] == 17, $sformatf("microSD: ordenes recibidas:%s, esperadas 0 8 55 A41 55 A41 17", l));
                check(!sd_idle, "microSD: sigue en idle tras ACMD41");
                check(sd_blk == 3, $sformatf("microSD: CMD17 del bloque %0d, esperado 3", sd_blk));
            end
            CK_RESET: begin
                $display("  /RESET a %0.3f ms; el /WAIT del pin bajo a %0.3f ms; primer M1 de despues acabado a %0.3f ms",
                         t_rw_reset / 1.0e6, t_rw_wait_drop / 1.0e6, t_rw_m1 / 1.0e6);
                check(t_rw_reset >= 0.0, "/RESET con /WAIT: el /WAIT de la lectura de P#0 no llego a subir");
                check(!boot_hold && drive_en && bus_ok, "tras el /RESET: guardia sin soltar");
            end
            default: ;
        endcase
    endfunction

    // ------------------------------------------------------------------
    //  Interprete (un solo sitio por tipo de ciclo)
    // ------------------------------------------------------------------
    task automatic run_q();
        zop_t o;
        reg [7:0] d, dmy;
        int ntw, ntw2, k;
        real t0;
        zt_now();
        while (q.size() > 0) begin
            o = q.pop_front();
            case (o.op)
                OP_OUT: ins_out(8'(o.a), 8'(o.v));
                OP_IN, OP_POLL: begin
                    // POLL: IN A,(n) / AND m / JR NZ,-4 hasta (v & m) == esperado
                    k = 0;
                    forever begin
                        ins_in(8'(o.a), d);
                        last_v = d;
                        k++;
                        if (o.op == OP_IN) break;
                        if ((d & 8'(o.m)) == (8'(o.v) & 8'(o.m)) || k >= 200000) break;
                        z_m1(pc, 8'hE6, 0, dmy, ntw);
                        z_mrd(pc + 16'd1, 8'(o.m), dmy, ntw);
                        z_m1(pc + 16'd2, 8'h20, 5, dmy, ntw);
                        z_mrd(pc + 16'd3, 8'hFA, dmy, ntw);
                    end
                    if (o.op == OP_POLL) begin
                        if (k > poll_max) poll_max = k;
                        check(k < 200000, $sformatf("%s: no llega tras %0d lecturas", o.what, k));
                    end
                    else if (o.m != 0 && s_reset_n) begin
                        n_chk++;
                        if ((d & 8'(o.m)) !== (8'(o.v) & 8'(o.m))) begin
                            n_rd_bad++;
                            fail($sformatf("IN %02h (%s): leido %02h, esperado %02h (mascara %02h)", o.a, o.what, d, o.v, o.m));
                        end
                    end
                end
                OP_MRD, OP_FETCH: begin
                    if (o.op == OP_MRD) begin
                        z_m1(pc, 8'h3A, 0, dmy, ntw);
                        z_mrd(pc + 16'd1, 8'(o.a), dmy, ntw);
                        z_mrd(pc + 16'd2, 8'(o.a >> 8), dmy, ntw);
                        pc = pc_next(pc, 3);
                        z_mrd(16'(o.a), 8'hFF, d, ntw2);
                    end
                    else z_m1(16'(o.a), 8'hFF, 0, d, ntw2);
                    last_v = d; areg = d;
                    if (slot_sel[o.a[15:14]]) begin
                        n_mrd_ours++;
                        if (ntw2 > tw_max_mem) tw_max_mem = ntw2;
                        mem_tw_hist[(ntw2 > 7) ? 7 : ntw2]++;
                    end
                    if (o.m != 0) begin
                        n_chk++;
                        if ((d & 8'(o.m)) !== (8'(o.v) & 8'(o.m))) begin
                            n_mem_bad++;
                            if (strict_mem) fail($sformatf("%s %04h (%s): leido %02h, esperado %02h", o.op == OP_MRD ? "LD A,(nn)" : "M1", o.a, o.what, d, o.v));
                        end
                    end
                end
                OP_MWR: begin
                    z_m1(pc, 8'h32, 0, dmy, ntw);
                    z_mrd(pc + 16'd1, 8'(o.a), dmy, ntw);
                    z_mrd(pc + 16'd2, 8'(o.a >> 8), dmy, ntw);
                    pc = pc_next(pc, 3);
                    z_mwr(16'(o.a), 8'(o.v));
                end
                OP_WAITINT, OP_FRAMES: begin
                    // bucle de HALT (M1 de NOP) hasta /INT; INTA e ISR: IN A,(66h)
                    // (VI tiene que estar), OUT (66h),A (lo borra). WAITINT: o.v
                    // interrupciones; FRAMES: hasta o.v cuadros de salida nuevos
                    int f_start, n_done;
                    f_start = fr_n;
                    n_done = 0;
                    while ((o.op == OP_WAITINT) ? (n_done < o.v) : (fr_n < f_start + o.v)) begin
                        t0 = $realtime;
                        k = 0;
                        while (!npn_i && k < 400000) begin
                            z_m1(pc, 8'h76, 0, dmy, ntw);
                            k++;
                        end
                        if (!npn_i) begin
                            fail($sformatf("no llega /INT en %0.1f ms", ($realtime - t0) / 1.0e6));
                            break;
                        end
                        if (n_int < 64) int_t[n_int] = t_int_rise;
                        n_int++;
                        n_done++;
                        z_inta(pc);
                        ins_in(P(6), d);
                        check(d[0], $sformatf("ISR: P#6 = %02h sin VI", d));
                        ins_out(P(6), d);
                        idle(4); at(zt);
                        #(400.0);
                        check(!npn_i, "/INT sigue bajo tras borrar VI en P#6");
                        zt_now();
                    end
                end
                OP_MPOLL: begin
                    // LD A,(nn) hasta (d & m) == (v & m), 64 veces como mucho
                    k = 0;
                    forever begin
                        z_m1(pc, 8'h3A, 0, dmy, ntw);
                        z_mrd(pc + 16'd1, 8'(o.a), dmy, ntw);
                        z_mrd(pc + 16'd2, 8'(o.a >> 8), dmy, ntw);
                        pc = pc_next(pc, 3);
                        z_mrd(16'(o.a), 8'hFF, d, ntw2);
                        k++;
                        if ((d & 8'(o.m)) == (8'(o.v) & 8'(o.m)) || k >= 64) break;
                    end
                    last_v = d; areg = d;
                    check(k < 64 || (d & 8'(o.m)) == (8'(o.v) & 8'(o.m)), $sformatf("%s: no llega tras %0d lecturas (ultima %02h)", o.what, k, d));
                end
                OP_LASTV: begin
                    n_chk++;
                    if (last_v !== 8'(o.v)) fail($sformatf("%s: %02h, esperado %02h", o.what, last_v, o.v));
                end
                OP_SLOT: slot_sel = 4'(o.v);
                OP_I:    z_i = 8'(o.v);
                OP_RESET, OP_RESETWAIT: begin
                    if (o.op == OP_RESETWAIT) begin
                        // IN A,(60h) con el /RESET armado: baja en cuanto sube /WAIT
                        rw_armed = 1'b1;
                        ins_in(P(0), d);
                        rw_armed = 1'b0;
                        if (t_rw_reset < 0.0) s_reset_n = 1'b0;
                    end
                    else begin
                        at(zt);
                        s_reset_n = 1'b0;
                    end
                    #(o.v * 1000.0);
                    s_reset_n = 1'b1;
                    // el primer M1 tras el /RESET, de la ROM del MSX en 0000h
                    boot_phase = 1'b1;
                    zt_now();
                    z_m1(16'h0000, 8'hF3, 0, dmy, ntw);
                    boot_phase = 1'b0;
                    if (o.op == OP_RESETWAIT) t_rw_m1 = $realtime;
                    pc = 16'hC000;
                end
                OP_CHK: begin
                    // que acabe el ultimo ciclo del Z80 y, si es una escritura,
                    // que llegue a la SDRAM (las tareas del Z80 vuelven antes
                    // de soltar sus strobes)
                    if (o.v != CK_PRINT && o.v != CK_SAVEF) begin
                        at(zt);
                        #(2000.0);
                        zt_now();
                    end
                    chkpt(o.v, o.what);
                end
                default: ;
            endcase
        end
        at(zt);
    endtask

    // ------------------------------------------------------------------
    //  Programa
    // ------------------------------------------------------------------
    int lost = 0;
    int stm = 0;
    int n_sd_ff_bad = 0, n_sd_pat_bad = 0;
    initial begin
        reg [7:0] dmy;
        int ntw;
        if (!$value$plusargs("SCEN=%s", scen)) scen = "full";
        if (!$value$plusargs("HZ=%d", hz)) hz = 3579545;
        TZ = 1.0e9 / real'(hz);
        if (!$value$plusargs("STRICTMEM=%d", stm)) stm = (hz <= 3600000) ? 1 : 0;
        strict_mem = (stm != 0);
        $display("tb_top: configuracion %s, variante %s, Z80 a %0.3f MHz, escenario %s, lecturas de la megaROM %s",
                 CFGNAME, SYNC ? "sync" : "xtal", real'(hz) / 1.0e6, scen,
                 strict_mem ? "estrictas" : "contadas (no estrictas)");

        // SDRAM con un patron (contenido de encendido)
        for (int unsigned w = 0; w < (1 << 21); w++) u_mem.mem[w] = pat_word(w);

        if (scen == "nomsx") begin
            // ---------------- sin MSX: el slot sin reloj ni /RESET ----------------
            #(12.0e6);
            $display("-- sin MSX: 12 ms");
            check(!bus_ok, "sin MSX: BUS_OK a 1");
            check(!drive_en, "sin MSX: DRIVE_EN a 1");
            check(!cart_int_n && cart_data_dir && cart_busdir_n, "sin MSX: /INT, datos o BUSDIR conducidos");
            check(led_code == (SYNC ? 3'd0 : 3'd2), $sformatf("sin MSX: LED en el codigo %0d, esperado %0d", led_code, SYNC ? 0 : 2));
        end
        else begin
            // ---------------- A: arranque ----------------
            // la FPGA arranca configurada (t = 0); el MSX se enciende a 0,1 ms con
            // /RESET bajo 1 ms (el CLOCK del slot ya corre)
            #(0.1e6);
            slot_run = 1'b1;
            #(1.0e6);
            s_reset_n = 1'b1;
            // el Z80 empieza en 0000h (ROM del MSX, pagina 0): su primer M1 se
            // queda en /WAIT (BOOT_HOLD) hasta que el sistema esta listo
            zt_now();
            z_m1(16'h0000, 8'hF3, 0, dmy, ntw);
            t_boot_m1 = $realtime;
            boot_phase = 1'b0;
            $display("-- A arranque: primer M1 del Z80 acabado a %0.3f ms (%0d TW)", t_boot_m1 / 1.0e6, ntw);
            $display("  PLL_OK %0.3f ms, SDRAM lista %0.3f ms, RESET_n %0.3f ms, SYS_READY %0.3f ms, BUS_OK %0.3f ms, DRIVE_EN %0.3f ms",
                     t_pll_ok / 1.0e6, t_sdram / 1.0e6, t_rst / 1.0e6, t_sysrdy / 1.0e6, t_busok / 1.0e6, t_drive / 1.0e6);
            check(t_pll_ok > 0.0 && t_sdram > t_pll_ok && t_rst >= t_sdram && t_sysrdy >= t_rst, "arranque: PLL_OK, SDRAM, RESET_n y SYS_READY fuera de orden o sin llegar");
            check(t_busok > 0.0 && t_drive >= t_busok && t_drive >= t_sysrdy, "arranque: DRIVE_EN antes que BUS_OK y SYS_READY");
            check(boot_hold_seen, "arranque: BOOT_HOLD nunca subio el /WAIT del pin");
            check(t_boot_m1 > t_drive, $sformatf("arranque: el primer M1 acabo (%0.3f ms) antes de DRIVE_EN (%0.3f ms): BOOT_HOLD no lo retuvo", t_boot_m1 / 1.0e6, t_drive / 1.0e6));
            if (NEXTOR) check(t_boot_m1 < 120.0e6, "arranque: el primer M1 tardo mas de 120 ms");
            else        check(t_boot_m1 < 60.0e6, "arranque: el primer M1 tardo mas de 60 ms");
            check(!boot_hold && drive_en && bus_ok, "arranque: guardia sin soltar");
            if (MEGA) begin
                for (int unsigned a = 0; a < 32768; a++) if (sd_byte(a) !== 8'hFF) n_sd_ff_bad++;
                for (int unsigned a = 32768; a < 32768 + 4096; a++) if (sd_byte(a) !== pat_byte(a)) n_sd_pat_bad++;
                check(n_sd_ff_bad == 0, $sformatf("MegaRAM: %0d bytes de los 32 KB borrados no son FFh", n_sd_ff_bad));
                check(n_sd_pat_bad == 0, $sformatf("MegaRAM: el borrado se paso de los 32 KB (%0d bytes)", n_sd_pat_bad));
                $display("  MegaRAM: borrado de 32 KB comprobado en la SDRAM (%0d bytes mal)", n_sd_ff_bad + n_sd_pat_bad);
            end
            if (NEXTOR) begin
                int bad_nx, bad_after;
                bad_nx = 0; bad_after = 0;
                for (int unsigned a = 0; a < NX_SIZE; a++) if (sd_byte(CONFIG::RAM_ADDR_BIOS_NEXTOR + a) !== nx_img(a)) bad_nx++;
                for (int unsigned a = NX_SIZE; a < NX_SIZE + 4096; a++) if (sd_byte(CONFIG::RAM_ADDR_BIOS_NEXTOR + a) !== pat_byte(CONFIG::RAM_ADDR_BIOS_NEXTOR + a)) bad_after++;
                $display("  Nextor: copia de la flash: /CS bajo %0d vez, orden %02h en %06h, %0d bytes leidos; %0d de %0d bytes mal en la SDRAM, %0d fuera de la ROM tocados",
                         n_fl_cs, fl_cmd_first, fl_addr_first, n_fl_bytes, bad_nx, NX_SIZE, bad_after);
                check(n_fl_cs == 1 && fl_cmd_first == 8'h03 && fl_addr_first == 24'(NX_FLASH) && n_fl_badcmd == 0,
                      "Nextor: la flash no se leyo con una sola orden 03h en 10_0000h");
                check(n_fl_bytes == NX_SIZE, $sformatf("Nextor: %0d bytes leidos de la flash, esperados %0d", n_fl_bytes, NX_SIZE));
                check(bad_nx == 0, $sformatf("Nextor: %0d bytes de la ROM mal copiados a la SDRAM", bad_nx));
                check(bad_after == 0, $sformatf("Nextor: la copia toco %0d bytes fuera de su sitio", bad_after));
                check(mspi_cs, "Nextor: la flash sigue seleccionada tras la copia");
            end

            // ---------------- B: puertos ----------------
            p_chk(CK_PRINT, "B puertos");
            p_in(P(5), 8'h00, 8'h01, "P#5: CE a 0 en reposo");
            for (int p = 8; p < 16; p++) p_in(P(p), 8'hFF, 8'hFF, $sformatf("P#%0d", p));
            p_in(8'h70, 8'hFF, 8'hFF, "puerto 70h (nadie contesta)");
            p_wreg(6'd16, 8'h5A);
            p_out(P(4), 8'h50);             // R#16, lectura sin incremento
            p_in(P(3), 8'h5A, 8'hFF, "R#16 leido por P#3");

            // ---------------- C: VRAM por P#0 ----------------
            p_chk(CK_PRINT, "C VRAM por P#0");
            for (int i = 0; i < 64; i++) img_v[i] = 8'($urandom);
            p_vram_w(19'h1_2340);
            for (int i = 0; i < 64; i++) p_out(P(0), img_v[i]);
            p_vram_r(19'h1_2340);
            for (int i = 0; i < 64; i++) p_in(P(0), img_v[i], 8'hFF, $sformatf("VRAM[%05h] por P#0", 19'h1_2340 + i));
            p_chk(CK_VRAM, "");

            // ---------------- D: paleta por P#1 ----------------
            p_chk(CK_PRINT, "D paleta por P#1");
            for (int e = 0; e < 8; e++) begin
                pr[e]  = {1'($urandom), 2'b00, 5'($urandom)};
                pgr[e] = {3'b000, 5'($urandom)};
                pb[e]  = {3'b000, 5'($urandom)};
            end
            pr[5] = 8'h1F; pgr[5] = 8'h00; pb[5] = 8'h00;   // entrada 5: rojo (el borde)
            p_wreg(6'd14, 8'h00);
            for (int e = 0; e < 8; e++) begin p_out(P(1), pr[e]); p_out(P(1), pgr[e]); p_out(P(1), pb[e]); end
            p_wreg(6'd14, 8'h00);
            for (int e = 0; e < 8; e++) begin
                p_in(P(1), pr[e],  8'hFF, $sformatf("paleta %0d R", e));
                p_in(P(1), pgr[e], 8'hFF, $sformatf("paleta %0d G", e));
                p_in(P(1), pb[e],  8'hFF, $sformatf("paleta %0d B", e));
            end

            // ---------------- E: LMMV ----------------
            p_chk(CK_PRINT, "E LMMV del blitter");
            p_out(P(7), 8'h00);             // MCS = 0
            p_wreg(6'd6, 8'h82);            // B1, 256 puntos, 8 bits por punto
            p_wreg(6'd7, 8'h00);            // NTSC
            p_wreg(6'd13, 8'h40);           // PLTM = 01: BD8 (color directo GRB 332; con 00 seria BP6, de paleta)
            p_wreg(6'd15, 8'h05);           // borde: paleta 5
            for (int r = 17; r <= 20; r++) p_wreg(6'(r), 8'h00);
            p_in(P(5), 8'h00, 8'h01, "P#5: CE a 0 antes del LMMV");
            p_lmmv(0, 0, 256, (scen == "full") ? 212 : 140, 16'h0303);     // fondo azul
            p_lmmv(96, 90, 64, 32, 16'hE0E0);                               // rectangulo verde
            p_vram_chk(96, 90, 8'hE0, "LMMV: esquina superior izquierda");
            p_vram_chk(159, 121, 8'hE0, "LMMV: esquina inferior derecha");
            p_vram_chk(95, 90, 8'h03, "LMMV: a la izquierda del rectangulo");
            p_vram_chk(160, 100, 8'h03, "LMMV: a la derecha");
            p_vram_chk(100, 122, 8'h03, "LMMV: debajo");
            p_vram_chk(0, 0, 8'h03, "LMMV: (0,0) del fondo");
            p_vram_chk(255, 139, 8'h03, "LMMV: (255,139) del fondo");
            p_chk(CK_LMMV, "");

            // ---------------- F/G: /INT y video ----------------
            p_chk(CK_PRINT, "F /INT del V9990 y G video");
            p_wreg(6'd8, 8'h80);            // DISP
            p_wreg(6'd9, 8'h01);            // IEV
            p_out(P(6), 8'h07);             // borra lo pendiente
            if (scen == "full") begin
                p_chk(CK_SAVEF, "");
                p_op(OP_FRAMES, 0, 3, 0, "");
                p_chk(CK_NTSC, "");
                p_wreg(6'd7, 8'h08);        // PAL
                p_chk(CK_SAVEF, "");
                p_op(OP_FRAMES, 0, 3, 0, "");
                p_chk(CK_PAL, "");
                p_wreg(6'd7, 8'h00);
            end
            else begin
                p_op(OP_WAITINT, 0, 1, 0, "");
                p_chk(CK_INT1, "");
            end
            p_wreg(6'd9, 8'h00);

            // ---------------- N: Nextor ----------------
            if (NEXTOR) begin
                p_chk(CK_PRINT, "N Nextor: subranura 2 y AB");
                // FFFFh del slot expandido (pagina 3 del cartucho): pagina 1 a
                // la subranura 2 (Nextor), las demas a la 0 (megaROM)
                p_op(OP_SLOT, 0, 4'b1000, 0, "");
                p_mwr(16'hFFFF, 8'h08);
                p_mrd(16'hFFFF, 8'hF7, 8'hFF, "FFFFh se lee invertido");
                p_op(OP_SLOT, 0, 4'b0110, 0, "");
                p_mrd(16'h4000, 8'h41, 8'hFF, "Nextor 4000h 'A'");
                p_mrd(16'h4001, 8'h42, 8'hFF, "Nextor 4001h 'B'");
                p_mrd(16'h8000, 8'hFF, 8'hFF, "megaROM (subranura 0) en 8000h a la vez");
                p_mrd(16'h5FFF, nx_img(16'h1FFF), 8'hFF, "Nextor 5FFFh, banco 0");
                p_mrd(16'h6002, nx_img(2), 8'hFF, "Nextor 6002h, banco 1 = 0 al arrancar");
                if (scen == "full") begin
                    p_mwr(16'h6000, 8'h05);
                    p_mwr(16'h6800, 8'h0F);
                    p_mrd(16'h4000, nx_img(5 * 8192), 8'hFF, "Nextor banco 5 en 4000h");
                    p_mrd(16'h5ABC, nx_img(5 * 8192 + 16'h1ABC), 8'hFF, "Nextor banco 5 en 5ABCh");
                    p_mrd(16'h7FFF, nx_img(15 * 8192 + 16'h1FFF), 8'hFF, "Nextor banco 15 en 7FFFh");
                    p_mrd(16'hA000, 8'hFF, 8'hFF, "megaROM en A000h entre lecturas de Nextor");
                    p_mrd(16'h6000, nx_img(15 * 8192), 8'hFF, "Nextor banco 15 en 6000h");
                    p_mwr(16'h4000, 8'h55);         // ROM protegida
                    p_mwr(16'h7FFF, 8'hAA);
                    p_mrd(16'h4000, nx_img(5 * 8192), 8'hFF, "Nextor banco 5 tras escribir");
                    p_chk(CK_NXPROT, "");

                    p_chk(CK_PRINT, "N Nextor: SPI de la microSD (banco 40h)");
                    p_mwr(16'h6000, 8'h40);
                    // 10 bytes con /CS alto (5000h: A12 = 1)
                    for (int i = 0; i < 10; i++) p_mwr(16'h5000, 8'hFF);
                    // CMD0
                    p_mwr(16'h4000, 8'h40); for (int i = 0; i < 4; i++) p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h95);
                    p_op(OP_MPOLL, 16'h4000, 8'h00, 8'h80, "CMD0: R1");
                    p_op(OP_LASTV, 0, 8'h01, 0, "CMD0: R1");
                    // CMD8 (2,7-3,6 V, patron AAh)
                    p_mwr(16'h4000, 8'h48); p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h01);
                    p_mwr(16'h4000, 8'hAA); p_mwr(16'h4000, 8'h87);
                    p_op(OP_MPOLL, 16'h4000, 8'h00, 8'h80, "CMD8: R1");
                    p_op(OP_LASTV, 0, 8'h01, 0, "CMD8: R1");
                    p_mrd(16'h4000, 8'h00, 8'hFF, "CMD8: R7 1");
                    p_mrd(16'h4000, 8'h00, 8'hFF, "CMD8: R7 2");
                    p_mrd(16'h4000, 8'h01, 8'hFF, "CMD8: R7 3 (tension)");
                    p_mrd(16'h4000, 8'hAA, 8'hFF, "CMD8: R7 4 (patron)");
                    // CMD55 + ACMD41 (HCS) dos veces
                    for (int r = 0; r < 2; r++) begin
                        p_mwr(16'h4000, 8'h77); for (int i = 0; i < 4; i++) p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h65);
                        p_op(OP_MPOLL, 16'h4000, 8'h00, 8'h80, "CMD55: R1");
                        p_op(OP_LASTV, 0, (r == 0) ? 8'h01 : 8'h01, 0, "CMD55: R1");
                        p_mwr(16'h4000, 8'h69); p_mwr(16'h4000, 8'h40); for (int i = 0; i < 3; i++) p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h77);
                        p_op(OP_MPOLL, 16'h4000, 8'h00, 8'h80, "ACMD41: R1");
                        p_op(OP_LASTV, 0, (r == 0) ? 8'h01 : 8'h00, 0, "ACMD41: R1");
                    end
                    // CMD17 del bloque 3: R1, testigo FEh y 512 bytes
                    p_mwr(16'h4000, 8'h51); p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h00); p_mwr(16'h4000, 8'h00);
                    p_mwr(16'h4000, 8'h03); p_mwr(16'h4000, 8'hFF);
                    p_op(OP_MPOLL, 16'h4000, 8'h00, 8'h80, "CMD17: R1");
                    p_op(OP_LASTV, 0, 8'h00, 0, "CMD17: R1");
                    p_op(OP_MPOLL, 16'h4000, 8'hFE, 8'hFF, "CMD17: testigo FEh");
                    for (int i = 0; i < 512; i++) p_mrd(16'h4000 + 16'(i % 2048), sd_img(3, i), 8'hFF, $sformatf("CMD17: byte %0d del bloque", i));
                    p_mrd(16'h4000, 8'h12, 8'hFF, "CMD17: CRC 1");
                    p_mrd(16'h4000, 8'h34, 8'hFF, "CMD17: CRC 2");
                    p_mrd(16'h5000, 8'hFF, 8'h00, "");      // /CS alto
                    p_chk(CK_SD, "");
                    p_mwr(16'h6000, 8'h00);
                    p_mwr(16'h6800, 8'h00);
                    p_mrd(16'h4000, 8'h41, 8'hFF, "Nextor 4000h 'A' tras la microSD");
                end
                // FFFFh otra vez a 0 (todas las paginas a la subranura 0)
                p_op(OP_SLOT, 0, 4'b1000, 0, "");
                p_mwr(16'hFFFF, 8'h00);
                p_op(OP_SLOT, 0, 4'b0000, 0, "");
            end

            // ---------------- H: MegaRAM ----------------
            if (MEGA) begin
                p_chk(CK_PRINT, "H MegaRAM: SCC-I RAM al arrancar");
                p_op(OP_SLOT, 0, 4'b0110, 0, "");
                p_mrd(16'h4000, 8'hFF, 8'hFF, "SCC-I: 4000h borrado (sin AB)");
                p_mrd(16'hBFFF, 8'hFF, 8'hFF, "SCC-I: BFFFh");
                p_mwr(16'h5000, 8'hFF); p_mwr(16'h4000, 8'h11); p_mwr(16'h5FFF, 8'h12);
                p_mwr(16'h7000, 8'h80); p_mwr(16'h6123, 8'h22);
                p_mrd(16'h4000, 8'h11, 8'hFF, "SCC-I: banco FFh");
                p_mrd(16'h5FFF, 8'h12, 8'hFF, "SCC-I: banco FFh, ultimo byte");
                p_mrd(16'h6123, 8'h22, 8'hFF, "SCC-I: banco 80h");
                p_chk(CK_SCCI, "");

                p_chk(CK_PRINT, "H MegaRAM: tncrom");
                p_op(OP_SLOT, 0, 4'b0111, 0, "");
                p_mwr(16'h0000, 8'hAA);
                p_mrd(16'h0000, 8'hFF, 8'hFF, "llave cerrada: 0000h no contesta");
                p_unlock();
                p_mrd(16'h0000, 8'hAB, 8'hFF, "llave 0");  p_mrd(16'h0001, 8'hCD, 8'hFF, "llave 1");
                p_mrd(16'h0002, 8'h98, 8'hFF, "llave 2");  p_mrd(16'h0003, 8'h76, 8'hFF, "llave 3");
                p_mrd(16'h003E, 8'h00, 8'hFF, "3Eh: ventana de 4 MB");
                p_mrd(16'h001F, 8'h00, 8'hFF, "1Fh: modo al encender");
                p_lock();
                p_mrd(16'h0003, 8'hFF, 8'hFF, "llave cerrada otra vez");
                // ASCII16 sin proteccion, banco 0 al ultimo, datos por 8000h
                p_unlock();
                p_attr(F_ENABLE | F_BANK16, 8'hFF, 16'hF800, 16'h6000, 16'h7000, 16'hFFFF, 16'hFFFF, 0, 0, 0, 0, 8'h00);
                p_lock();
                p_mwr(16'h6000, 8'hFF);
                foreach (banks16[i]) begin
                    p_mwr(16'h7000, 8'(banks16[i]));
                    foreach (offs16[j]) p_mwr(16'h8000 + 16'(offs16[j]), img(banks16[i], offs16[j]));
                end
                p_chk(CK_TNCROM, "");
                // atributo final (ASCII16 protegido), ENABLE + CONTINUOUS
                p_unlock();
                p_attr(F_WP | F_BANK16, 8'hFF, 16'hF800, 16'h6000, 16'h7000, 16'hFFFF, 16'hFFFF, 0, 0, 0, 0, 8'h00);
                p_mwr(16'h000C, F_WP | F_BANK16 | F_ENABLE | F_CONT);
                p_lock();
                foreach (banks16[i]) begin
                    p_mwr(16'h7000, 8'(banks16[i]));
                    p_mwr(16'h6000, 8'(banks16[i]));
                    foreach (offs16[j]) begin
                        p_mrd(16'h8000 + 16'(offs16[j]), img(banks16[i], offs16[j]), 8'hFF, $sformatf("ASCII16 pag. 2 banco %02xh", banks16[i]));
                        p_mrd(16'h4000 + 16'(offs16[j]), img(banks16[i], offs16[j]), 8'hFF, $sformatf("ASCII16 pag. 1 banco %02xh", banks16[i]));
                    end
                end
                p_mwr(16'h7000, 8'hFF);
                p_mwr(16'h8000, 8'h5A);         // protegida: no se escribe
                p_chk(CK_PROT, "");

                p_chk(CK_PRINT, "H MegaRAM: PLAIN0");
                // imagen: banco b de 16 KB en b * 4000h; "AB" en 4000h
                p_unlock();
                p_attr(F_ENABLE | F_BANK16, 8'hFF, 16'hF800, 16'h6000, 16'h7000, 16'hFFFF, 16'hFFFF, 0, 0, 0, 0, 8'h00);
                p_lock();
                for (int bk = 0; bk < 3; bk++) begin
                    p_mwr(16'h7000, 8'(bk));
                    p_mwr(16'h8000, (bk == 1) ? 8'h41 : img(bk, 0));
                    p_mwr(16'h8001, (bk == 1) ? 8'h42 : img(bk, 1));
                    p_mwr(16'h8038, img(bk, 16'h38));
                    for (int i = 1; i < 8; i++) p_mwr(16'h8038 + 16'(i), img(bk, 16'h38 + i));
                    p_mwr(16'hBFFF, img(bk, 16'h3FFF));
                end
                // atributo de tncrom -T PLAIN0 (16 KB, sin registros de banco,
                // bancos 0/1/2, 1Fh.b0 = 1)
                p_unlock();
                p_attr(F_WP | F_BANK16 | F_ENABLE | F_CONT, 8'hFF, 16'hF800, 16'hFFFF, 16'hFFFF, 16'hFFFF, 16'hFFFF, 0, 1, 2, 0, 8'h01);
                p_mrd(16'h001F, 8'h01, 8'hFF, "PLAIN0 con la llave abierta: 1Fh");
                p_lock();
                p_fetch(16'h0000, img(0, 0), "PLAIN0 M1 en 0000h");
                p_fetch(16'h0038, img(0, 16'h38), "PLAIN0 M1 en 0038h (ISR)");
                p_mrd(16'h0001, img(0, 1), 8'hFF, "PLAIN0 0001h");
                p_fetch(16'h4000, 8'h41, "PLAIN0 M1 en 4000h 'A'");
                p_mrd(16'h4001, 8'h42, 8'hFF, "PLAIN0 4001h 'B'");
                p_mrd(16'h8000, img(2, 0), 8'hFF, "PLAIN0 8000h");
                p_mrd(16'hBFFF, img(2, 16'h3FFF), 8'hFF, "PLAIN0 BFFFh");
                p_op(OP_I, 0, 8'h00, 0, "");     // refrescos en la pagina 0 (I = 00h): no son lecturas
                for (int i = 0; i < 8; i++) p_fetch(16'h0038 + 16'(i), img(0, 16'h38 + i), "PLAIN0 M1 con I = 00h");
                p_op(OP_I, 0, 8'h3F, 0, "");
                p_mwr(16'h0038, 8'h99);         // escrituras ignoradas
                p_mwr(16'h0000, 8'hAB);         // la llave tambien
                p_mrd(16'h0038, img(0, 16'h38), 8'hFF, "PLAIN0 0038h tras escribir");
                p_chk(CK_PLAIN, "");
                // el /RESET del MSX borra PLAIN0 y ENABLE: el cartucho queda mudo
                p_op(OP_SLOT, 0, 4'b0000, 0, "");
                p_op(OP_RESET, 0, 1000, 0, "");
                p_op(OP_SLOT, 0, 4'b0111, 0, "");
                p_mrd(16'h4000, 8'hFF, 8'hFF, "tras /RESET de PLAIN0: 4000h no contesta");
                p_mrd(16'h0038, 8'hFF, 8'hFF, "tras /RESET de PLAIN0: 0038h no contesta");
                p_unlock();
                p_mrd(16'h001F, 8'h00, 8'hFF, "1Fh tras /RESET");
                p_lock();
                p_op(OP_SLOT, 0, 4'b0000, 0, "");
                p_chk(CK_MEMSUM, "");
            end

            // ---------------- R: /RESET del MSX con el V9990 pidiendo /WAIT ----------------
            p_chk(CK_PRINT, "R /RESET del MSX en una lectura de P#0 con /WAIT");
            p_vram_r(19'h1_2340);
            p_op(OP_RESETWAIT, 0, 1000, 0, "");
            p_chk(CK_RESET, "");
            // el V9990 vuelve a contestar
            p_in(P(5), 8'h00, 8'h01, "tras el /RESET: P#5 CE a 0");
            p_vram_r(19'h1_2340);
            for (int i = 0; i < 8; i++) p_in(P(0), img_v[i], 8'hFF, "tras el /RESET: VRAM por P#0");

            run_q();
        end

        // ---------------- final ----------------
        #(20000.0);
        $display("-- final (%0.3f ms)", $realtime / 1.0e6);
        lost = dut.u_main.genblk2.u_v9990.u_vdp.u_ram.lost_slots;
        check(lost == 0, $sformatf("%0d ranuras de VRAM perdidas", lost));
        check(u_mem.n_err == n_sd_err_rst, $sformatf("%0d errores del modelo de la SDRAM con el controlador fuera de reset", u_mem.n_err - n_sd_err_rst));
        check(n_sd_win == 0, $sformatf("%0d capturas de la SDRAM fuera de la ventana del dato", n_sd_win));
        check(n_sd_cont == 0, $sformatf("%0d ciclos con la SDRAM y el controlador conduciendo DQ a la vez", n_sd_cont));
        check(n_sd_rst_cmd == 0, $sformatf("SDRAM: %0d flancos con un comando que no es NOP (el primero %b) con el controlador en reset; %0d errores del modelo antes de BASE_READY",
                                           n_sd_rst_cmd, sd_rst_cmd_first, n_sd_err_rst));
        check(n_wto == 0 && !wto, "WAIT_TIMEOUT");
        check(n_conflict == 0, $sformatf("%0d choques en D0-D7", n_conflict));
        check(n_bad_drive == 0, $sformatf("%0d conducciones de D0-D7 sin lectura legitima", n_bad_drive));
        check(n_late_drive == 0, $sformatf("%0d conducciones de D0-D7 tardias", n_late_drive));
        check(n_hang == 0, "Z80 colgado");
        if (!NEXTOR) begin
            check(n_fl_cs == 0 && mspi_cs && !mspi_sclk, $sformatf("sin Nextor: la flash se ha seleccionado %0d veces", n_fl_cs));
            check(n_sd_cs == 0 && tf_dat3 && !tf_sclk && tf_cmd, $sformatf("sin Nextor: la microSD se ha seleccionado %0d veces", n_sd_cs));
        end
        check(mspi_hold, "/HOLD de la flash bajo");
        if (scen != "nomsx") begin
            check(led_code == 3'd5, $sformatf("LED en el codigo %0d al final, esperado 5 (listo)", led_code));
            check(n_led_off_ready == 0, $sformatf("LED apagado %0d ciclos con el codigo 5", n_led_off_ready));
        end
        $write("  LED (codigo@ms):");
        for (int i = 0; i < led_n && i < 16; i++) $write(" %0d@%0.2f", led_seq[i], led_t[i] / 1.0e6);
        $display("");
        $display("RESULTADO %s_%s %0.2fMHz %s: %0d comprobaciones, %0d fallos; E/S %0d (%0d al V9990, TW max %0d), M1 %0d, INTA %0d, lecturas del slot %0d (TW max %0d, %0d mal), /INT %0d, cuadros %0d, ranuras perdidas %0d, errores SDRAM tras el reset %0d",
                 CFGNAME, SYNC ? "sync" : "xtal", real'(hz) / 1.0e6, scen, n_chk, n_fail,
                 n_io, n_io_ours, tw_max_io, n_m1, n_inta, n_mrd_ours, tw_max_mem, n_mem_bad, n_int, fr_n, lost, u_mem.n_err - n_sd_err_rst);
        if (n_fail == 0) $display("BANCO: PASA");
        else             $display("BANCO: FALLA");
        $finish;
    end

    // tope de tiempo (+STOPMS=<ms> para depurar: para antes)
    real stop_ms = 400.0;
    initial begin
        if (!$value$plusargs("STOPMS=%f", stop_ms)) stop_ms = 400.0;
        #(stop_ms * 1.0e6);
        $display("  parada a %0.3f ms: ranuras perdidas %0d, errores SDRAM %0d (%0d en reset), capturas fuera de ventana %0d",
                 $realtime / 1.0e6, dut.u_main.genblk2.u_v9990.u_vdp.u_ram.lost_slots, u_mem.n_err, n_sd_err_rst, n_sd_win);
        $display("FALLA  tope de 400 ms de simulacion");
        $display("BANCO: FALLA");
        $finish;
    end
endmodule

`default_nettype wire
