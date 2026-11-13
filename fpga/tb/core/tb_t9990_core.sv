// tb_t9990_core.sv -- banco del core T9990 (fpga/v9990/tiny9990) con los
// enables y la VRAM de la WonderTANG: el UMA real de tnCart a DIV = 30 (21,6 /
// 14,4 / 25,2 MHz y una ranura de VRAM cada 20 ciclos, 2 ciclos despues del
// enable de 21 MHz) y un modelo ciclo a ciclo de sdram.sv (tb_vram_uma.sv).
// Derivado de tb_t9990_timing.sv del MSXimus Z (mismo autor): se sustituyen el
// generador de enables de la Zynq (/4, /6, /16) y su VRAM de mentira, se quitan
// la cache AXI y el stall, y se anaden las pruebas del hito 2/7 del V9990TANG.
//
// Pruebas (plusargs; se corren con run_t9990_core.sh):
//   (siempre)  geometria medida en DCLK_EN como la muestrea el upscan: puntos
//              y ciclos de CLK por linea, lineas y ciclos por cuadro, anchos de
//              HS/VS, ventana de DE (HD && VD registrado en DCLK_EN, como el
//              selector), PAL, EO/IL, fase de DCLK_EN, latencia de la VRAM y
//              ranuras perdidas (cuenta de la asercion de t9990_ram.sv).
//              +R6= +R7= +MCS=1 +R16= (hex) +FRAMES=
//              +VIDDUMP=f vuelca la salida de video de los cuadros medidos
//              (prueba hito1: compilado con +define+CORE_HITO1 el banco
//              instancia el core del hito 1, sin PAL ni parametros)
//   +BLIT=1    motor de comandos en B1 8 bpp (LMMV/LMMM/LMMC/PSET/LINE/POINT/
//              LMCM + coherencia P#0) -> BLIT_OK
//   +PORTS=1   lecturas de P#4, P#7, P#8-P#11 (ROM kanji) y P#12-P#15 -> FFh
//              como openMSX -> PORTS_OK
//   +EOR=1     cursores sobre un fondo conocido, semantica de openMSX: B1 BD16
//              (EOR, CC, solapes, oculto, R#28, fuera de pantalla, Y con vuelta
//              por arriba), B1 BD16 entrelazado (los dos campos), B1 BP4 y el
//              overscan B2 BP4 en NTSC y PAL -> EOR_OK
//   +HPOS=1    diagnostico (no falla): que punto del bitmap sale en el primer
//              punto de la imagen con el scroll a 0
//   +R16T=1    R#16: desplazamiento de la imagen (ventana) frente al
//              sincronismo en B1/B3/B2/B4, NTSC y PAL -> R16_OK
//   +R16CHG=1  R#16 cambiado en marcha (cruzando el limite del cuadro de
//              sincronismo) en B1 entrelazado, B4 PAL entrelazado y B5: el
//              sincronismo no cambia nunca (cuadros y lineas exactos), la
//              ventana se reajusta en su borrado -> R16CHG_OK
//   +PALT=1    cuadro PAL de 313 lineas en B1 y B2 y vuelta a NTSC -> PALT_OK
//   +BDBP=1    puntos transparentes (indice 0) de BP4 desde el reset y despues
//              de BD16: color de fondo (R#15) -> BDBP_OK
//   +CMMC=1    CMMC a 2/4/8/16 bpp (8 pixeles por byte de P#2, bits seguidos entre
//              filas, sobrantes tirados, ningun byte de mas) contra el modelo del
//              manual y de openMSX; con +P2NOTR=1 los bytes se mandan sin mirar TR
//              (SymbOS G9K) y ademas un LMMC 16x2 seguido y R#6 -> comando/P#0
//              inmediato -> CMMC_OK (y P2NOTR_OK)
//   +CMMM=1    CMMM a 2/4/8/16 bpp (bytes de la VRAM lineal desde SA, SA en las 4
//              posiciones de la palabra, lecturas contadas) -> CMMM_OK
//   +ORDEN=1   orden de los bytes del color a 16 bpp (R#48 = byte bajo = direccion
//              par) en LMMV/LMMC/PSET/LINE/LMCM/SRCH/CMMC y CMMM con SA = 7FFFEh
//              a 8 bpp (vuelta de 512 KB) -> ORDEN_OK
//   +YCC=1     YJK y YUV en B1 contra el modelo de openMSX (grupo de 4 pixeles de
//              la VRAM), con el desfase calibrado con BD8 -> YCC_OK
//   +REPLAY=f  traza de openMSX (mk_replay.py) con +VRAMOUT=f volcado de la VRAM
//   +CH0=1     carga en el canal 0 del UMA (lecturas en todas sus ranuras)
//   +ACKDLY=n  retrasa n ciclos el ACK de la VRAM: la asercion tiene que saltar
//
// Solo Verilator (Icarus no traga los interfaces/modports del core).
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
`timescale 1ns/1ps
module tb_t9990_core;
    parameter ENABLE_PAL        = 1;
    parameter ENABLE_CURSOR_EOR = 1;
    parameter ENABLE_R16        = 1;

    // ------------------------------------------------------------------
    // reloj (108 MHz: el periodo no importa, todo se mide en ciclos)
    // ------------------------------------------------------------------
    reg clk = 0; always #4.63 clk = ~clk;
    reg rst_n = 0;
    integer ackdly = 0;
    reg ch0 = 0;

    // ------------------------------------------------------------------
    // core + VRAM por el UMA
    // ------------------------------------------------------------------
    reg csr_n = 1, csw_n = 1; reg [3:0] mode = 4'd0; reg [7:0] cd_in = 8'd0;
    wire [7:0] cd_out; wire wait_n, int0_n, int1_n, dreq_n, vmreq_n;
    wire ram_oe_n, ram_we_n, ram_rfsh_n; wire [18:0] ram_addr; wire [31:0] ram_din; wire [2:0] ram_din_size;
    wire [31:0] ram_dout; wire ram_ack_n, ram_req;
    wire clk21_en, clk14_en, clk25_en;
    wire hs, vs, dclk_en, il, eo, ys, hscn, pal; wire [4:0] r, g, b; wire [2:0] reso;

    TB_VRAM_UMA u_vram (
        .RESET_n(rst_n), .CLK(clk), .CH0_LOAD(ch0), .ACK_DELAY(ackdly),
        .CLK21M_EN(clk21_en), .CLK14M_EN(clk14_en), .CLK25M_EN(clk25_en),
        .RAM_REQ(ram_req), .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size),
        .RAM_DOUT(ram_dout), .RAM_ACK_n(ram_ack_n));

`ifndef CORE_HITO1
    T9990 #(
        .ENABLE_PAL(ENABLE_PAL), .ENABLE_CURSOR_EOR(ENABLE_CURSOR_EOR), .ENABLE_R16(ENABLE_R16)
    ) dut (
        .RESET_n(rst_n), .CLK(clk),
        .CLK_21M_EN(clk21_en), .CLK_14M_EN(clk14_en), .CLK_25M_EN(clk25_en),
        .CSR_n(csr_n), .CSW_n(csw_n), .MODE(mode), .CD_IN(cd_in), .CD_OUT(cd_out),
        .WAIT_n(wait_n), .INT0_n(int0_n), .INT1_n(int1_n), .DREQ_n(dreq_n), .VMREQ_n(vmreq_n),
        .RAM_REQ(ram_req), .RAM_ACK_n(ram_ack_n),
        .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size), .RAM_DOUT(ram_dout),
        .HS(hs), .VS(vs), .R(r), .G(g), .B(b), .Ys(ys), .DCLK_EN(dclk_en),
        .RESO(reso), .HSCN(hscn), .IL(il), .EO(eo), .PAL(pal));
`else
    // +define+CORE_HITO1: el core del hito 1 (tiny9990 de tnCart sin parches, con char -> chr para que
    // compile aqui), sin la salida PAL ni los parametros: solo para la prueba hito1 de run_t9990_core.sh
    T9990 dut (
        .RESET_n(rst_n), .CLK(clk),
        .CLK_21M_EN(clk21_en), .CLK_14M_EN(clk14_en), .CLK_25M_EN(clk25_en),
        .CSR_n(csr_n), .CSW_n(csw_n), .MODE(mode), .CD_IN(cd_in), .CD_OUT(cd_out),
        .WAIT_n(wait_n), .INT0_n(int0_n), .INT1_n(int1_n), .DREQ_n(dreq_n), .VMREQ_n(vmreq_n),
        .RAM_REQ(ram_req), .RAM_ACK_n(ram_ack_n),
        .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size), .RAM_DOUT(ram_dout),
        .HS(hs), .VS(vs), .R(r), .G(g), .B(b), .Ys(ys), .DCLK_EN(dclk_en),
        .RESO(reso), .HSCN(hscn), .IL(il), .EO(eo));
    assign pal = 1'b0;
`endif

    // DE como lo usa el selector (HD && VD registrado en DCLK_EN): alineado con R/G/B/HS/VS
    reg de = 0;
    always @(posedge clk) if (dclk_en) de <= dut.HD && dut.VD;
    // DA como lo usa el selector (!VR && !HR registrado en DCLK_EN): la imagen sin bordes
    reg da = 0;
    always @(posedge clk) if (dclk_en) da <= !dut.STATUS.VR && !dut.STATUS.HR;

    // ------------------------------------------------------------------
    // medidas (muestreo en posedge clk con dclk_en = 1, valores previos al flanco)
    // ------------------------------------------------------------------
    integer clk_cnt = 0;
    always @(posedge clk) clk_cnt <= clk_cnt + 1;

    reg  hs_p = 0, vs_p = 0, de_p = 0, pal_p = 0, eo_p = 0;
    integer dot = 0, line = 0;
    reg  line_valid = 0, frame_valid = 0, meas = 0;
    integer frames_done = 0;
    integer c21_line = 0, clk_line0 = 0, clk_frame0 = 0, hs_in_vs = 0;
    // por linea / cuadro
    integer l_dots_min, l_dots_max, l_clk_min, l_clk_max, l_c21_min, l_c21_max, hsw_min, hsw_max, hsw_cur;
    integer f_lines_min, f_lines_max, f_clk_min, f_clk_max, vsw_min, vsw_max;
    integer de_rise_min, de_rise_max, de_fall_min, de_fall_max, de_first_min, de_first_max, de_last_min, de_last_max;
    integer de_lines_min, de_lines_max, de_lines, de_first, de_last, de_in_line;
    // subidas de DE por cuadro: con R#16 a +8 el borde derecho acaba justo en el fin de linea y DE (que
    // aqui se mide un punto tarde respecto a HS) invade un punto la linea siguiente, que entonces cuenta
    // en de_lines; el numero de subidas no depende de eso
    integer de_nrise, de_nrise_min, de_nrise_max;
    integer vs_hs_coinc, vs_rises, pal_min, pal_max, pal_chg_bad, eo_min, eo_max, il_min, il_max;
    integer gap, gap_min, gap_max;
    integer tmp;
    // posicion del VS en coordenadas de la ventana del generador (h_cnt/v_cnt de T9990_TIMING)
    integer vs_wh_min, vs_wh_max, vs_wv_min, vs_wv_max;
    // inicio de la tanda de lineas con DE, en lineas desde VS, con vuelta (el borde puede cruzar el VS)
    reg     de_line [0:1023];
    integer de_run_min, de_run_max, de_runs_min, de_runs_max;
    // lo mismo con DA: bordes superior e inferior = distancia entre la tanda de DA y la de DE
    reg     da_line [0:1023];
    integer da_in_line, da_lines, da_lines_min, da_lines_max, da_run_min, da_run_max;
    integer btop_min, btop_max, bbot_min, bbot_max;
    // FIELD (EO): solo cambia con VS; con entrelazado cambia en cada cuadro y coincide con el EO de la
    // ventana (STATUS.EO, el que usa BG_Y) en todas las lineas con DE
    integer eo_chg_bad, eo_notoggle, eo_win_bad, eo_prev_frame;
    // cuadros de la ventana (h_cnt/v_cnt de T9990_TIMING): puntos entre dos v_rst (con R#16 cambiado en
    // marcha la irregularidad va aqui y no en el sincronismo); wf_ref = el del regimen estable
    integer wf_dots = 0, wf_min, wf_max, wf_irr, wf_n, wf_ref = -1;
    reg     wf_valid = 0;
    // posicion del VS en la ventana en la ultima subida de VS
    integer vs_wh_last = -1, vs_wv_last = -1;

    task stats_reset;
        begin
            l_dots_min = 1<<30; l_dots_max = -1; l_clk_min = 1<<30; l_clk_max = -1; l_c21_min = 1<<30; l_c21_max = -1;
            hsw_min = 1<<30; hsw_max = -1;
            f_lines_min = 1<<30; f_lines_max = -1; f_clk_min = 1<<30; f_clk_max = -1; vsw_min = 1<<30; vsw_max = -1;
            de_rise_min = 1<<30; de_rise_max = -1; de_fall_min = 1<<30; de_fall_max = -1;
            de_first_min = 1<<30; de_first_max = -1; de_last_min = 1<<30; de_last_max = -1; de_lines_min = 1<<30; de_lines_max = -1;
            de_nrise_min = 1<<30; de_nrise_max = -1;
            vs_hs_coinc = 0; vs_rises = 0; pal_min = 1<<30; pal_max = -1; pal_chg_bad = 0;
            eo_min = 1<<30; eo_max = -1; il_min = 1<<30; il_max = -1;
            gap_min = 1<<30; gap_max = -1;
            vs_wh_min = 1<<30; vs_wh_max = -1; vs_wv_min = 1<<30; vs_wv_max = -1;
            de_run_min = 1<<30; de_run_max = -1; de_runs_min = 1<<30; de_runs_max = -1;
            da_lines_min = 1<<30; da_lines_max = -1; da_run_min = 1<<30; da_run_max = -1;
            btop_min = 1<<30; btop_max = -1; bbot_min = 1<<30; bbot_max = -1;
            eo_chg_bad = 0; eo_notoggle = 0; eo_win_bad = 0; eo_prev_frame = -1;
            wf_min = 1<<30; wf_max = -1; wf_irr = 0; wf_n = 0; wf_valid = 0; wf_dots = 0;
            frames_done = 0;
        end
    endtask
    always @(posedge clk) if (dclk_en) begin
        if (meas) begin
            wf_dots = wf_dots + 1;
            if (dut.u_tg.v_rst) begin
                if (wf_valid) begin
                    if (wf_dots < wf_min) wf_min = wf_dots;
                    if (wf_dots > wf_max) wf_max = wf_dots;
                    if (wf_dots != wf_ref) wf_irr = wf_irr + 1;
                    wf_n = wf_n + 1;
                end
                wf_valid = 1; wf_dots = 0;
            end
        end
    end
    initial begin stats_reset; de_nrise = 0; de_lines = 0; de_first = -1; de_last = -1; de_in_line = 0; hsw_cur = -1; gap = 0; da_in_line = 0; da_lines = 0; end

    always @(posedge clk) begin
        if (clk21_en) c21_line = c21_line + 1;
        if (dclk_en && meas) begin
            if (gap > 0 && gap < gap_min) gap_min = gap;
            if (gap > gap_max) gap_max = gap;
        end
        gap = dclk_en ? 1 : gap + 1;
    end

    // captura de un cuadro (para +EOR): fb[linea desde VS][punto desde HS] = {G,R,B}
    reg [14:0] fb [0:319][0:1023];
    reg        fb_da [0:319][0:1023];      // DA (imagen sin bordes) de cada punto capturado
    reg cap_arm = 0, cap_on = 0, cap_done = 0;
    reg cap_eo = 0;                         // FIELD (EO) del cuadro capturado

    reg hs_rise, vs_rise, hs_fall, vs_fall, de_rise, de_fall;
    always @(posedge clk) if (dclk_en) begin
        hs_rise = hs && !hs_p; hs_fall = !hs && hs_p;
        vs_rise = vs && !vs_p; vs_fall = !vs && vs_p;
        de_rise = de && !de_p; de_fall = !de && de_p;
        // ---- fin de linea ----
        if (hs_rise) begin
            if (meas && line_valid) begin
                if (dot + 1 < l_dots_min) l_dots_min = dot + 1;
                if (dot + 1 > l_dots_max) l_dots_max = dot + 1;
                if (clk_cnt - clk_line0 < l_clk_min) l_clk_min = clk_cnt - clk_line0;
                if (clk_cnt - clk_line0 > l_clk_max) l_clk_max = clk_cnt - clk_line0;
                if (c21_line < l_c21_min) l_c21_min = c21_line;
                if (c21_line > l_c21_max) l_c21_max = c21_line;
                if (hsw_cur >= 0) begin if (hsw_cur < hsw_min) hsw_min = hsw_cur; if (hsw_cur > hsw_max) hsw_max = hsw_cur; end
                if (line < 1024) begin de_line[line] = de_in_line; da_line[line] = da_in_line; end
                if (da_in_line) da_lines = da_lines + 1;
                if (de_in_line) begin
                    de_lines = de_lines + 1;
                    if (de_first < 0) de_first = line;
                    de_last = line;
                end
            end
            line_valid = 1; clk_line0 = clk_cnt; c21_line = 0;
            if (vs) hs_in_vs = hs_in_vs + 1;
        end
        // ---- fin de cuadro ----
        if (vs_rise) begin
            if (meas && frame_valid) begin
                if (line + 1 < f_lines_min) f_lines_min = line + 1;
                if (line + 1 > f_lines_max) f_lines_max = line + 1;
                if (clk_cnt - clk_frame0 < f_clk_min) f_clk_min = clk_cnt - clk_frame0;
                if (clk_cnt - clk_frame0 > f_clk_max) f_clk_max = clk_cnt - clk_frame0;
                if (de_first < de_first_min) de_first_min = de_first;
                if (de_first > de_first_max) de_first_max = de_first;
                if (de_last < de_last_min) de_last_min = de_last;
                if (de_last > de_last_max) de_last_max = de_last;
                if (de_lines < de_lines_min) de_lines_min = de_lines;
                if (de_nrise < de_nrise_min) de_nrise_min = de_nrise;
                if (de_nrise > de_nrise_max) de_nrise_max = de_nrise;
                if (de_lines > de_lines_max) de_lines_max = de_lines;
                begin : de_run_scan
                    integer l, n, runs, st, sa, bt, bb;
                    n = line + 1; runs = 0; st = -1; sa = -1;
                    for (l = 0; l < n && l < 1024; l = l + 1) begin
                        if (de_line[l] && !de_line[(l + n - 1) % n]) begin runs = runs + 1; if (st < 0) st = l; end
                        if (da_line[l] && !da_line[(l + n - 1) % n] && sa < 0) sa = l;
                    end
                    if (st < de_run_min) de_run_min = st;
                    if (st > de_run_max) de_run_max = st;
                    if (runs < de_runs_min) de_runs_min = runs;
                    if (runs > de_runs_max) de_runs_max = runs;
                    if (sa < da_run_min) da_run_min = sa;
                    if (sa > da_run_max) da_run_max = sa;
                    if (da_lines < da_lines_min) da_lines_min = da_lines;
                    if (da_lines > da_lines_max) da_lines_max = da_lines;
                    // bordes (con vuelta): de st (DE) a sa (DA) y del fin de DA al fin de DE
                    bt = (sa >= 0 && st >= 0) ? ((sa - st + n) % n) : -1;
                    bb = (bt >= 0) ? (de_lines - da_lines - bt) : -1;
                    if (bt < btop_min) btop_min = bt;
                    if (bt > btop_max) btop_max = bt;
                    if (bb < bbot_min) bbot_min = bb;
                    if (bb > bbot_max) bbot_max = bb;
                end
                frames_done = frames_done + 1;
            end
            if (meas) begin
                tmp = dut.u_tg.h_cnt; if (tmp < vs_wh_min) vs_wh_min = tmp; if (tmp > vs_wh_max) vs_wh_max = tmp; vs_wh_last = tmp;
                tmp = dut.u_tg.v_cnt; if (tmp < vs_wv_min) vs_wv_min = tmp; if (tmp > vs_wv_max) vs_wv_max = tmp; vs_wv_last = tmp;
                tmp = eo; if (il && eo_prev_frame >= 0 && tmp == eo_prev_frame) eo_notoggle = eo_notoggle + 1;
                eo_prev_frame = tmp;
            end
            frame_valid = 1; clk_frame0 = clk_cnt;
            de_first = -1; de_last = -1; de_lines = 0; da_lines = 0; de_nrise = 0;
            if (meas) begin vs_rises = vs_rises + 1; if (hs_rise) vs_hs_coinc = vs_hs_coinc + 1; end
            hs_in_vs = hs_rise ? 1 : 0;     // la subida de HS que coincide con la de VS es la primera linea del VS
            if (cap_on) begin cap_on = 0; cap_done = 1; end
            else if (cap_arm) begin cap_arm = 0; cap_on = 1; cap_eo = eo; end
        end
        if (vs_fall && meas) begin
            if (hs_in_vs < vsw_min) vsw_min = hs_in_vs;
            if (hs_in_vs > vsw_max) vsw_max = hs_in_vs;
        end
        // PAL solo cambia en la subida de VS
        if (meas && (pal != pal_p) && !vs_rise) pal_chg_bad = pal_chg_bad + 1;
        if (meas && (eo != eo_p) && !vs_rise) eo_chg_bad = eo_chg_bad + 1;
        // lineas de imagen (sin bordes) del cuadro de sincronismo de su ventana: con R#16 de +5 a +8 lineas en
        // PAL con overscan (B2/B4, 290 lineas) las ultimas 3-4 lineas de la ventana caen despues del VS
        // siguiente (en el cuadro de sincronismo de despues: v_cnt muy por encima de las lineas desde VS) y
        // ahi FIELD ya es el del campo nuevo; no se cuentan. La muestra de la subida de VS es la linea 0 del
        // cuadro nuevo (line aun no se ha puesto a 0): con R#16 = x8h en B4 el VS sube con DE todavia alto en
        // la ultima linea de la ventana (borde derecho) y FIELD ya ha cambiado
        if (meas && de && dut.MUX_VDE && il && (eo != dut.STATUS.EO) && !(dut.u_tg.v_cnt > (vs_rise ? 0 : line) + 100)) eo_win_bad = eo_win_bad + 1;
        // ---- contadores ----
        if (vs_rise) line = 0; else if (hs_rise) line = line + 1;
        if (hs_rise) begin dot = 0; de_in_line = 0; da_in_line = 0; hsw_cur = -1; end else dot = dot + 1;
        if (meas && line_valid) begin
            if (hs_fall) hsw_cur = dot;
            if (de_rise) begin if (dot < de_rise_min) de_rise_min = dot; if (dot > de_rise_max) de_rise_max = dot; de_nrise = de_nrise + 1; end
            if (de_fall) begin if (dot < de_fall_min) de_fall_min = dot; if (dot > de_fall_max) de_fall_max = dot; end
            if (de) de_in_line = 1;
            if (da) da_in_line = 1;
            tmp = pal; if (tmp < pal_min) pal_min = tmp; if (tmp > pal_max) pal_max = tmp;
            tmp = eo;  if (tmp < eo_min) eo_min = tmp;   if (tmp > eo_max) eo_max = tmp;
            tmp = il;  if (tmp < il_min) il_min = tmp;   if (tmp > il_max) il_max = tmp;
        end
        if (cap_on && line < 320 && dot < 1024) begin fb[line][dot] = {g, r, b}; fb_da[line][dot] = da; end
        hs_p <= hs; vs_p <= vs; de_p <= de; pal_p <= pal; eo_p <= eo;
    end

`ifndef CORE_HITO1
    function integer lost_slots; lost_slots = dut.u_ram.lost_slots; endfunction
    // cursor: T9990_SPRITE compara la linea (CUR_VCNT = cur_line_q, registrada en t9990.sv) en los ACK
    // de sus lecturas de VRAM y en el ciclo siguiente (STATE_CUR_PAT_START). En esos ciclos la linea
    // registrada tiene que ser la combinacional (cur_line - 1, - 2 con entrelazado); si no, el registro
    // se veria (cur_race)
    integer cur_race = 0, cur_acks = 0;
    reg sp_ack_d = 0;
    always @(posedge clk) begin
        if (ENABLE_CURSOR_EOR != 0 && (dut.SP_MEM.ACK || sp_ack_d)) begin
            cur_acks = cur_acks + 1;
            if (dut.cur_line_q !== 9'(dut.cur_line - (dut.REG.ILM ? 9'd2 : 9'd1))) cur_race = cur_race + 1;
        end
        sp_ack_d <= dut.SP_MEM.ACK;
    end
`else
    integer cur_race = 0, cur_acks = 0;
    function integer lost_slots; lost_slots = 0; endfunction       // el core del hito 1 no tiene la asercion
`endif

    // +VIDDUMP=<fichero>: la salida de video del core muestreada en cada DCLK_EN durante la medida
    // (una palabra de 32 bits por punto: {12'b0, DE, EO, IL, VS, HS, R, G, B}). La prueba hito1 compara
    // byte a byte este fichero entre el core de trabajo y el del hito 1.
    integer vid_fh = 0, vid_n = 0;
    always @(posedge clk) if (dclk_en && meas && vid_fh != 0) begin
        $fwrite(vid_fh, "%u", {12'd0, de, eo, il, vs, hs, r, g, b});
        vid_n = vid_n + 1;
    end

    task print_json(input string tag);
        begin
            $display("%0s {\"frames\":%0d, \"dots_per_line\":[%0d,%0d], \"clk_per_line\":[%0d,%0d], \"clk21_en_per_line\":[%0d,%0d], \"hs_width_dots\":[%0d,%0d],",
                tag, frames_done, l_dots_min, l_dots_max, l_clk_min, l_clk_max, l_c21_min, l_c21_max, hsw_min, hsw_max);
            $display("  \"lines_per_frame\":[%0d,%0d], \"clk_per_frame\":[%0d,%0d], \"vs_width_lines\":[%0d,%0d], \"vs_rises\":%0d, \"vs_hs_coincident\":%0d,",
                f_lines_min, f_lines_max, f_clk_min, f_clk_max, vsw_min, vsw_max, vs_rises, vs_hs_coinc);
            $display("  \"de_rise_dot\":[%0d,%0d], \"de_fall_dot\":[%0d,%0d], \"de_first_line\":[%0d,%0d], \"de_last_line\":[%0d,%0d], \"de_lines\":[%0d,%0d],",
                de_rise_min, de_rise_max, de_fall_min, de_fall_max, de_first_min, de_first_max, de_last_min, de_last_max, de_lines_min, de_lines_max);
            $display("  \"de_run_start_line\":[%0d,%0d], \"de_runs\":[%0d,%0d], \"vs_at_window_dot\":[%0d,%0d], \"vs_at_window_line\":[%0d,%0d],",
                de_run_min, de_run_max, de_runs_min, de_runs_max, vs_wh_min, vs_wh_max, vs_wv_min, vs_wv_max);
            $display("  \"da_lines\":[%0d,%0d], \"da_run_start_line\":[%0d,%0d], \"border_top_lines\":[%0d,%0d], \"border_bottom_lines\":[%0d,%0d],",
                da_lines_min, da_lines_max, da_run_min, da_run_max, btop_min, btop_max, bbot_min, bbot_max);
            $display("  \"pal\":[%0d,%0d], \"pal_changes_off_vs\":%0d, \"eo\":[%0d,%0d], \"eo_changes_off_vs\":%0d, \"eo_not_toggled\":%0d, \"eo_vs_window_bad\":%0d, \"il\":[%0d,%0d], \"reso\":%0d, \"clk_gap_between_dclk\":[%0d,%0d],",
                pal_min, pal_max, pal_chg_bad, eo_min, eo_max, eo_chg_bad, eo_notoggle, eo_win_bad, il_min, il_max, reso, gap_min, gap_max);
            $display("  \"vram_ack_latency_clk\":[%0d,%0d], \"vram_latency_not_13\":%0d, \"vram_access_off_slot\":%0d, \"vram_reads\":%0d, \"vram_writes\":%0d, \"vram_rfsh\":%0d, \"ch0_reads\":%0d, \"lost_slots\":%0d }",
                u_vram.lat_min, u_vram.lat_max, u_vram.n_lat_odd, u_vram.n_acc_off, u_vram.n_rd, u_vram.n_wr, u_vram.n_rf, u_vram.ch0_reads, lost_slots());
        end
    endtask

    // espera n subidas de VS (muestreadas en DCLK_EN)
    task wait_vs(input integer n);
        integer k, w;
        begin
            for (k = 0; k < n; k = k + 1) begin
                w = 0;
                @(posedge clk); while (!(dclk_en && vs && !vs_p) && w < 8000000) begin @(posedge clk); w = w + 1; end
                if (w >= 8000000) begin $display("ERROR: no llega VS"); $finish; end
            end
        end
    endtask
    // mide n cuadros completos desde la siguiente subida de VS
    task measure(input integer n);
        begin
            wait_vs(1);
            @(negedge clk);     // despues del flanco de la subida de VS: el bloque de medida ya la ha procesado sin medir
            stats_reset; meas = 1;
            while (frames_done < n) @(posedge clk);
            meas = 0;
        end
    endtask

    // ------------------------------------------------------------------
    // puerto CPU (CSW_n/CSR_n de nivel con flanco de bajada, MODE = P#n)
    // ------------------------------------------------------------------
    task wr_port(input [3:0] p, input [7:0] d);
        begin
            @(posedge clk); mode <= p; cd_in <= d; csw_n <= 1'b0;
            repeat (3) @(posedge clk);
            while (!wait_n) @(posedge clk);
            csw_n <= 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask
    // Cada llamada a una tarea con esperas se expande en la corrutina del initial (asi lo compila el simulador): las
    // secuencias de puertos van en bucles (una sola expansion de wr_port) para que esa funcion no crezca
    // a cientos de miles de lineas (la compilacion pasaba de 15 minutos).
    task wr_reg(input [5:0] n, input [7:0] d);
        integer s;
        begin for (s = 0; s < 2; s = s + 1) wr_port(s ? 4'd3 : 4'd4, s ? d : {2'b00, n}); end
    endtask
    task rd_port(input [3:0] p, output [7:0] d);
        begin
            @(posedge clk); mode <= p; csr_n <= 1'b0;
            repeat (3) @(posedge clk);
            while (!wait_n) @(posedge clk);
            @(posedge clk); d = cd_out;
            csr_n <= 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask
    task pal_set(input [5:0] e, input [4:0] rr, input [4:0] gg, input [4:0] bb);
        integer s;
        begin
            wr_reg(6'd14, {e, 2'b00});
            for (s = 0; s < 3; s = s + 1) wr_port(4'd1, {3'b000, (s == 0) ? rr : ((s == 1) ? gg : bb)});
        end
    endtask

    integer nerr = 0, nln = 0;
    reg [7:0] rb;
    task chk(input [18:0] a, input [7:0] exp, input [8*12-1:0] what);
        begin
            if (u_vram.mem[a] !== exp) begin $display("ERROR %0s: vram[%05h] = %02h, esperado %02h", what, a, u_vram.mem[a], exp); nerr = nerr + 1; end
        end
    endtask
    task chk8(input [7:0] got, input [7:0] exp, input [8*12-1:0] what);
        begin
            if (got !== exp) begin $display("ERROR %0s: leido %02h, esperado %02h", what, got, exp); nerr = nerr + 1; end
        end
    endtask

    // ------------------------------------------------------------------
    // +BLIT=1: motor de comandos en B1 256x212 8 bpp (de tb_t9990_timing.sv)
    // ------------------------------------------------------------------
    task wr_cmd(input [15:0] sx, input [15:0] sy, input [15:0] dx, input [15:0] dy,
                input [15:0] nx, input [15:0] ny, input [7:0] arg, input [7:0] lop,
                input [15:0] wm, input [15:0] fc, input [15:0] bc, input [7:0] op);
        reg [7:0] v [0:20];
        integer s;
        begin
            v[ 0] = sx[7:0]; v[ 1] = sx[15:8]; v[ 2] = sy[7:0]; v[ 3] = sy[15:8];
            v[ 4] = dx[7:0]; v[ 5] = dx[15:8]; v[ 6] = dy[7:0]; v[ 7] = dy[15:8];
            v[ 8] = nx[7:0]; v[ 9] = nx[15:8]; v[10] = ny[7:0]; v[11] = ny[15:8];
            v[12] = arg;     v[13] = lop;      v[14] = wm[7:0]; v[15] = wm[15:8];
            v[16] = fc[7:0]; v[17] = fc[15:8]; v[18] = bc[7:0]; v[19] = bc[15:8];
            v[20] = op;
            for (s = 0; s < 21; s = s + 1) wr_reg(6'd32 + s[5:0], v[s]);     // R#32..R#52 (R#52 arranca)
            repeat (40) @(posedge clk);
        end
    endtask
    task wait_ce(input [8*8-1:0] what);
        integer w;
        begin
            w = 0; while (dut.STATUS.CE && w < 4000000) begin @(posedge clk); w = w + 1; end
            if (dut.STATUS.CE) begin $display("ERROR %0s: CE no baja", what); nerr = nerr + 1; end
            else $display("  %0s: CE bajo tras %0d ciclos", what, w);
        end
    endtask
    task wait_tr(input [8*8-1:0] what);
        integer w;
        begin
            w = 0; while (!dut.STATUS.TR && w < 400000) begin @(posedge clk); w = w + 1; end
            if (!dut.STATUS.TR) begin $display("ERROR %0s: TR no sube", what); nerr = nerr + 1; end
        end
    endtask
    task rd_p0(input [18:0] a, output [7:0] d);
        integer s;
        begin
            for (s = 0; s < 3; s = s + 1) wr_reg(6'd3 + s[5:0], (s == 0) ? a[7:0] : ((s == 1) ? a[15:8] : {5'd0, a[18:16]}));
            rd_port(4'd0, d);
        end
    endtask
    task wr_p0(input [18:0] a, input [7:0] d);
        integer s;
        begin
            for (s = 0; s < 3; s = s + 1) wr_reg(6'd0 + s[5:0], (s == 0) ? a[7:0] : ((s == 1) ? a[15:8] : {5'd0, a[18:16]}));
            wr_port(4'd0, d);
        end
    endtask
    task blit_test;
        integer x, y;
        begin
            $display("---- BLIT: B1 256x212 8bpp (R#6=82h), LOP=0Ch, scroll 0 ----");
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            wr_cmd(0, 0, 0, 0, 256, 16, 0, 8'h0C, 16'hFFFF, 16'h0000, 0, 8'h20); wait_ce("LMMV0");
            chk(19'h0000, 8'h00, "fondo"); chk(19'h0777, 8'h00, "fondo"); chk(19'h0FFF, 8'h00, "fondo");
            wr_cmd(0, 0, 4, 1, 8, 2, 0, 8'h0C, 16'hFFFF, 16'h3333, 0, 8'h20); wait_ce("LMMV");
            for (x = 4; x < 12; x = x + 1) begin chk(19'h100 + x, 8'h33, "LMMV f1"); chk(19'h200 + x, 8'h33, "LMMV f2"); end
            chk(19'h103, 8'h00, "LMMV izq"); chk(19'h10C, 8'h00, "LMMV der"); chk(19'h304, 8'h00, "LMMV abajo"); chk(19'h004, 8'h00, "LMMV arriba");
            wr_cmd(4, 1, 100, 10, 8, 2, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h40); wait_ce("LMMM");
            for (x = 100; x < 108; x = x + 1) begin chk(19'hA00 + x, 8'h33, "LMMM f1"); chk(19'hB00 + x, 8'h33, "LMMM f2"); end
            chk(19'hA63, 8'h00, "LMMM izq"); chk(19'hA6C, 8'h00, "LMMM der");
            wr_cmd(0, 0, 0, 12, 4, 1, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h10);
            wait_tr("LMMC"); wr_port(4'd2, 8'hA1);
            wait_tr("LMMC"); wr_port(4'd2, 8'hA2);
            wait_tr("LMMC"); wr_port(4'd2, 8'hA3);
            wait_tr("LMMC"); wr_port(4'd2, 8'hA4);
            wait_ce("LMMC");
            chk(19'hC00, 8'hA1, "LMMC"); chk(19'hC01, 8'hA2, "LMMC"); chk(19'hC02, 8'hA3, "LMMC"); chk(19'hC03, 8'hA4, "LMMC"); chk(19'hC04, 8'h00, "LMMC der");
            wr_cmd(0, 0, 200, 14, 0, 0, 0, 8'h0C, 16'hFFFF, 16'h5555, 0, 8'hE0); wait_ce("PSET");
            chk(19'hEC8, 8'h55, "PSET"); chk(19'hEC7, 8'h00, "PSET izq"); chk(19'hEC9, 8'h00, "PSET der");
            wr_cmd(0, 0, 10, 3, 20, 5, 0, 8'h0C, 16'hFFFF, 16'h7777, 0, 8'hB0); wait_ce("LINE");
            nln = 0; for (y = 0; y < 16; y = y + 1) for (x = 0; x < 256; x = x + 1) if (u_vram.mem[y*256 + x] == 8'h77) nln = nln + 1;
            chk(19'h30A, 8'h77, "LINE ini");
            if (nln < 20 || nln > 21) begin $display("ERROR LINE: %0d puntos de color 77h, esperados 20", nln); nerr = nerr + 1; end
            else $display("  LINE: %0d puntos", nln);
            wr_cmd(5, 1, 0, 0, 0, 0, 0, 8'h0C, 16'hFFFF, 0, 0, 8'hD0);
            wait_tr("POINT"); rd_port(4'd2, rb); chk8(rb, 8'h33, "POINT"); wait_ce("POINT");
            wr_cmd(4, 1, 0, 0, 4, 1, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h30);
            wait_tr("LMCM"); rd_port(4'd2, rb); chk8(rb, 8'h33, "LMCM 0");
            wait_tr("LMCM"); rd_port(4'd2, rb); chk8(rb, 8'h33, "LMCM 1");
            wait_tr("LMCM"); rd_port(4'd2, rb); chk8(rb, 8'h33, "LMCM 2");
            wait_tr("LMCM"); rd_port(4'd2, rb); chk8(rb, 8'h33, "LMCM 3");
            wait_ce("LMCM");
            // LMCM / POINT por carril (parche del MSXimus Z): 4 pixeles distintos
            wr_p0(19'h0D00, 8'h11); wr_p0(19'h0D01, 8'h22); wr_p0(19'h0D02, 8'h44); wr_p0(19'h0D03, 8'h88);
            wr_cmd(0, 13, 0, 0, 4, 1, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h30);
            wait_tr("LMCMc"); rd_port(4'd2, rb); chk8(rb, 8'h11, "LMCM c0");
            wait_tr("LMCMc"); rd_port(4'd2, rb); chk8(rb, 8'h22, "LMCM c1");
            wait_tr("LMCMc"); rd_port(4'd2, rb); chk8(rb, 8'h44, "LMCM c2");
            wait_tr("LMCMc"); rd_port(4'd2, rb); chk8(rb, 8'h88, "LMCM c3");
            wait_ce("LMCMc");
            wr_cmd(2, 13, 0, 0, 0, 0, 0, 8'h0C, 16'hFFFF, 0, 0, 8'hD0);
            wait_tr("POINTc"); rd_port(4'd2, rb); chk8(rb, 8'h44, "POINT c2"); wait_ce("POINTc");
            rd_p0(19'h104, rb); chk8(rb, 8'h33, "P0 LMMV");
            rd_p0(19'hA64, rb); chk8(rb, 8'h33, "P0 LMMM");
            rd_p0(19'hC01, rb); chk8(rb, 8'hA2, "P0 LMMC");
            rd_p0(19'hEC8, rb); chk8(rb, 8'h55, "P0 PSET");
            wr_p0(19'hC06, 8'h99); repeat (40) @(posedge clk);
            chk(19'hC06, 8'h99, "P0 wr");
            wr_cmd(6, 12, 0, 0, 0, 0, 0, 8'h0C, 16'hFFFF, 0, 0, 8'hD0);
            wait_tr("POINT2"); rd_port(4'd2, rb); chk8(rb, 8'h99, "POINT P0"); wait_ce("POINT2");
            wr_cmd(0, 0, 4, 1, 8, 1, 0, 8'h00, 16'hFFFF, 16'h3333, 0, 8'h20); wait_ce("LMMV lop0");
            chk(19'h104, 8'h00, "LOP0"); chk(19'h204, 8'h33, "LOP0 f2");
            if (nerr == 0) $display("BLIT_OK"); else $display("BLIT_ERRORS %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +CMMC=1: CMMC (R#52 = 50h) en B, XIMM 512, a 2/4/8/16 bpp (R#6 = 84h..87h) contra un
    // modelo de la semantica del V9990 (manual de aplicacion y openMSX V9990CmdEngine::executeCMMC):
    // cada byte de P#2 son 8 pixeles, bit 7 primero; 1 -> FC (R#48/49), 0 -> BC (R#50/51). Los
    // bits siguen de una fila a la siguiente (NX no multiplo de 8) y los que sobran del ultimo
    // byte se tiran: la orden pide ceil(NX*NY/8) bytes. A 2/4/8 bpp el manual pide FC/BC repetidos
    // en todo el registro; a 16 bpp R#48/R#50 son el byte bajo del pixel (direccion par, VRAM0).
    // Con TP (LOP 1Ch) el pixel de color 0 no se escribe. Casos por modo: DX 144..147 con NX 8 y
    // 12 (NY 8), NX 5 x NY 3 (15 bits -> 2 bytes), NX 1 x NY 10 (2 bytes), NX 33 x NY 3 (99 bits ->
    // 13 bytes), 1 x 1 (sobran 7 bits) seguido de DX 155 (a 2 bpp, 11 pixeles dentro de la palabra),
    // DIX=1 y TP con BC = 0. Espera TR antes de cada
    // byte; CE tiene que bajar justo tras el ultimo, sin pedir ninguno de mas, y fuera del
    // rectangulo no se toca nada. Chase H.Q. (DiHalt) dibuja el marcador con CMMC 8x8 a 8 bpp.
    // ------------------------------------------------------------------
    integer cmmc_arg = 0, p2notr = 0;
    reg [7:0] cmmc_pat [0:15];
    function integer cmmc_px(input integer bpp, input integer x, input integer y);   // pixel (x,y), 512 px de ancho
        integer a;
        begin
            case (bpp)
                2:  begin a = y * 128 + x / 4; cmmc_px = (u_vram.mem[a] >> (6 - 2 * (x % 4))) & 3; end
                4:  begin a = y * 256 + x / 2; cmmc_px = (x & 1) ? (u_vram.mem[a] & 8'h0F) : (u_vram.mem[a] >> 4); end
                8:  cmmc_px = u_vram.mem[y * 512 + x];
                default: begin a = y * 1024 + 2 * x; cmmc_px = {u_vram.mem[a + 1], u_vram.mem[a]}; end
            endcase
        end
    endfunction
    task cmmc_wait_ce(input integer tmo, output integer ok);
        integer w;
        begin
            w = 0; while (dut.STATUS.CE && w < tmo) begin @(posedge clk); w = w + 1; end
            ok = !dut.STATUS.CE;
        end
    endtask
    // un caso: fondo bgr (LMMV 256x32), CMMC de NX x NY en (DX, 8); fail = 1 si algo no cuadra
    task cmmc_one(input integer bpp, input integer dx, input integer nx, input integer ny, input integer dix, input integer tp,
                  input [15:0] fcr, input [15:0] bcr, input [15:0] bgr, input integer fcp, input integer bcp, input integer bgp,
                  output integer fail);
        integer y, x, k, w, ok, nbytes, lost, extra, bad, outb, got, col, expv, lo, hi;
        begin
            nbytes = (nx * ny + 7) / 8;
            wr_cmd(0, 0, 0, 0, 256, 32, 0, 8'h0C, 16'hFFFF, bgr, 0, 8'h20); cmmc_wait_ce(4000000, ok);
            wr_cmd(0, 0, dx, 8, nx, ny, dix ? 8'h04 : 8'h00, tp ? 8'h1C : 8'h0C, 16'hFFFF, fcr, bcr, 8'h50);
            lost = 0;
            for (k = 0; k < nbytes; k = k + 1) begin
                if (p2notr) wr_port(4'd2, cmmc_pat[k]);     // +P2NOTR=1: sin mirar TR (SymbOS G9K); el puerto retiene
                else begin
                w = 0; while (!dut.STATUS.TR && dut.STATUS.CE && w < 400000) begin @(posedge clk); w = w + 1; end
                if (dut.STATUS.TR) wr_port(4'd2, cmmc_pat[k]);
                else lost = lost + 1;                       // CE bajo antes de tiempo o TR no sube
                end
            end
            cmmc_wait_ce(200000, ok);
            extra = 0;                                      // bytes que el motor pide de mas (se le dan ceros)
            while (!ok && extra < 40) begin
                w = 0; while (!dut.STATUS.TR && w < 200000) begin @(posedge clk); w = w + 1; end
                if (!dut.STATUS.TR) extra = 99;
                else begin wr_port(4'd2, 8'h00); extra = extra + 1; cmmc_wait_ce(20000, ok); end
            end
            if (!ok) begin wr_reg(6'd52, 8'h00); repeat (200) @(posedge clk); end      // STOP
            bad = 0;
            for (y = 0; y < ny; y = y + 1) for (x = 0; x < nx; x = x + 1) begin
                k = y * nx + x;
                col = cmmc_pat[k / 8][7 - (k % 8)] ? fcp : bcp;
                expv = (tp && col == 0) ? bgp : col;
                got = cmmc_px(bpp, dix ? dx - x : dx + x, 8 + y);
                if (got != expv) bad = bad + 1;
            end
            // alrededor del rectangulo (una columna y una fila a cada lado) sigue el fondo
            lo = dix ? dx - nx + 1 : dx; hi = dix ? dx : dx + nx - 1;
            outb = 0;
            for (y = 7; y <= 8 + ny; y = y + 1) for (x = lo - 1; x <= hi + 1; x = x + 1)
                if ((y == 7 || y == 8 + ny || x == lo - 1 || x == hi + 1) && cmmc_px(bpp, x, y) != bgp) outb = outb + 1;
            fail = (lost != 0 || extra != 0 || !ok || bad != 0 || outb != 0);
            $display("  %2d bpp DX=%0d NX=%0d NY=%0d DIX=%0d TP=%0d: %0d bytes, CE %0s; bytes de mas=%0d; sin TR=%0d; pixeles mal=%0d; fuera=%0d%0s",
                     bpp, dx, nx, ny, dix, tp, nbytes, ok ? "baja" : "NO baja", extra, lost, bad, outb, fail ? "  <-- MAL" : "");
            if (fail) for (y = 0; y < 2 && y < ny; y = y + 1) begin
                $write("     fila %0d (leido):  ", y);
                for (x = 0; x < nx; x = x + 1) $write(" %0h", cmmc_px(bpp, dix ? dx - x : dx + x, 8 + y));
                $write("\n     fila %0d (modelo): ", y);
                for (x = 0; x < nx; x = x + 1) begin
                    k = y * nx + x; col = cmmc_pat[k / 8][7 - (k % 8)] ? fcp : bcp;
                    $write(" %0h", (tp && col == 0) ? bgp : col);
                end
                $write("\n");
            end
        end
    endtask
    task cmmc_test;
        integer c, bpp, d, n, f, nfail, ncase, fcp, bcp, tbg;
        reg [15:0] fcr, bcr, tbgr;
        begin
            cmmc_pat[0] = 8'hF0; cmmc_pat[1] = 8'h0F; cmmc_pat[2] = 8'hAA; cmmc_pat[3] = 8'h55;
            cmmc_pat[4] = 8'hFF; cmmc_pat[5] = 8'h00; cmmc_pat[6] = 8'h81; cmmc_pat[7] = 8'h7E;
            cmmc_pat[8] = 8'hC3; cmmc_pat[9] = 8'h3C; cmmc_pat[10] = 8'h96; cmmc_pat[11] = 8'h69;
            cmmc_pat[12] = 8'h12; cmmc_pat[13] = 8'h34; cmmc_pat[14] = 8'h56; cmmc_pat[15] = 8'h78;
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            nfail = 0; ncase = 0;
            for (c = 0; c < 4; c = c + 1) begin
                case (c)
                    0: begin bpp = 2;  fcr = 16'hAAAA; bcr = 16'h5555; fcp = 2;       bcp = 1;       tbgr = 16'hFFFF; tbg = 3; end
                    1: begin bpp = 4;  fcr = 16'hDDDD; bcr = 16'h2222; fcp = 4'hD;    bcp = 2;       tbgr = 16'h7777; tbg = 7; end
                    2: begin bpp = 8;  fcr = 16'h2F2F; bcr = 16'h2020; fcp = 8'h2F;   bcp = 8'h20;   tbgr = 16'h5A5A; tbg = 8'h5A; end
                    default: begin bpp = 16; fcr = 16'hABCD; bcr = 16'h1234; fcp = 16'hABCD; bcp = 16'h1234; tbgr = 16'h5AC3; tbg = 16'h5AC3; end
                endcase
                wr_reg(6'd6, 8'h84 | c[7:0]);              // B, XIMM 512, CLRM = c
                $display("---- CMMC %0d bpp (R#6=%02h) ----", bpp, 8'h84 | c[7:0]);
                for (n = 8; n <= 12; n = n + 4)
                    for (d = 144; d <= 147; d = d + 1) begin
                        cmmc_one(bpp, d, n, 8, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                    end
                cmmc_one(bpp, 145, 5, 3, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 147, 1, 10, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 141, 33, 3, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 150, 1, 1, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 155, 12, 8, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 150, 12, 8, 1, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmc_one(bpp, 146, 12, 8, 0, 1, fcr, 16'h0000, tbgr, fcp, 0, tbg, f); nfail = nfail + f; ncase = ncase + 1;
            end
            $display("CMMC: %0d casos, %0d mal", ncase, nfail);
            if (nfail == 0) $display("CMMC_OK"); else $display("CMMC_FAIL %0d", nfail);
        end
    endtask
    // ------------------------------------------------------------------
    // +P2NOTR=1 (con +CMMC=1): rampa069/v9990 a3ee809. SymbOS G9K manda los bytes del CMMC/LMMC sin
    // mirar TR y escribe R#6 justo antes de lanzar un comando. (1) El CMMC de arriba sin sondear TR y un
    // LMMC 16x2 a 8 bpp de 32 bytes seguidos: el puerto tiene que retener (WAIT_n) el P#2 hasta que el
    // motor lo pueda tomar, sin perder ni pisar bytes. (2) R#6 -> comando / P#0 enseguida: el mapeo de
    // VRAM y el modo del motor siguen a R#6 al instante (P1 <-> bitmap, con desfases distintos respecto
    // a la linea de pantalla). Imprime P2NOTR_OK.
    // ------------------------------------------------------------------
    task p2notr_extra;
        integer i, j, x, y, k, bad, ok, ph, bad_lmmc, bad_map, bad_cmd;
        reg [18:0] a;
        begin
            bad_lmmc = 0; bad_map = 0; bad_cmd = 0;
            wr_reg(6'd6, 8'h86);                           // B, XIMM 512, 8 bpp
            wr_cmd(0, 0, 100, 100, 16, 2, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h10);   // LMMC 16x2
            for (k = 0; k < 32; k = k + 1) wr_port(4'd2, 8'h40 + k[7:0]);     // sin mirar TR
            cmmc_wait_ce(200000, ok);
            if (!ok) begin wr_reg(6'd52, 8'h00); repeat (200) @(posedge clk); end      // STOP: que no contagie al resto
            for (y = 0; y < 2; y = y + 1) for (x = 0; x < 16; x = x + 1)
                if (u_vram.mem[(100 + y) * 512 + 100 + x] !== (8'h40 + y * 16 + x)) bad_lmmc = bad_lmmc + 1;
            $display("  LMMC 16x2 sin TR: CE %0s, pixeles mal=%0d%0s", ok ? "baja" : "NO baja", bad_lmmc, (bad_lmmc != 0 || !ok) ? "  <-- MAL" : "");
            for (i = 0; i < 24; i = i + 1) begin
                repeat (i * 137) @(posedge clk);
                a = 19'h01000 + i * 19'h111;
                wr_reg(6'd6, 8'h00);                       // P1
                wr_reg(6'd0, a[7:0]); wr_reg(6'd1, a[15:8]); wr_reg(6'd2, {5'd0, a[18:16]});
                wr_port(4'd0, 8'hA0 + i[7:0]); repeat (60) @(posedge clk);
                ph = (a & 19'h3FFFF) * 2 + a[18];          // mapa P1 de t9990_ram.sv
                if (u_vram.mem[ph] !== 8'hA0 + i[7:0]) bad_map = bad_map + 1;
                wr_reg(6'd6, 8'h86);                       // bitmap, y el comando enseguida
                wr_cmd(0, 0, i * 8, 40 + i, 8, 1, 0, 8'h0C, 16'hFFFF, 16'h5A5A, 0, 8'h20); cmmc_wait_ce(200000, ok);
                for (j = 0; j < 8; j = j + 1) if (u_vram.mem[(40 + i) * 512 + i * 8 + j] !== 8'h5A) bad_cmd = bad_cmd + 1;
                wr_reg(6'd0, a[7:0]); wr_reg(6'd1, a[15:8]); wr_reg(6'd2, {5'd0, a[18:16]});
                wr_port(4'd0, 8'hC0 + i[7:0]); repeat (60) @(posedge clk);
                if (u_vram.mem[a] !== 8'hC0 + i[7:0]) bad_map = bad_map + 1;
            end
            $display("  R#6 inmediato: mapeo P#0 mal=%0d, comando mal=%0d", bad_map, bad_cmd);
            if (bad_lmmc == 0 && bad_map == 0 && bad_cmd == 0 && ok) $display("P2NOTR_OK"); else $display("P2NOTR_FAIL");
        end
    endtask
    // ------------------------------------------------------------------
    // +CMMM=1: CMMM (R#52 = 70h) en B, XIMM 512, a 2/4/8/16 bpp (R#6 = 84h..87h) contra un modelo de
    // la semantica del V9990 (manual de aplicacion y openMSX V9990CmdEngine::executeCMMM): igual que el
    // CMMC, pero los bytes salen de la VRAM lineal desde SA (R#32, R#34, R#35[2:0]; R#33 no cuenta), uno
    // detras de otro: 8 pixeles por byte, bit 7 primero, los bits siguen de una fila a la siguiente y
    // los que sobran del ultimo byte se tiran. La fuente (80 bytes en 60000h) se escribe por P#0 una
    // sola vez. Casos por modo: NX 8 x NY 7 (el marcador de Chase H.Q.) y NX 12 x NY 5 con SA en las
    // 4 posiciones dentro de la palabra de 32 bits y DX 144..147, 5x3, 1x10, 33x3, 32x12 (el retrato),
    // 1x1, DIX=1 y TP con BC = 0. Ademas de los pixeles y del borde, cuenta las lecturas del motor en
    // 60000h-6FFFFh: tienen que ser justo las palabras que cubren los ceil(NX*NY/8) bytes.
    // ------------------------------------------------------------------
    integer cmmm_arg = 0, cmmm_rd = 0;
    reg     cmmm_mon = 0, cm_oe_q = 1;
    reg [7:0] cmmm_src [0:79];
    localparam [18:0] CMMM_BASE = 19'h60000;
    always @(posedge clk) begin
        cm_oe_q <= dut.CMD_MEM.OE_n;
        if (cmmm_mon && cm_oe_q && !dut.CMD_MEM.OE_n && dut.CMD_MEM.ADDR[18:16] == 3'd6) cmmm_rd = cmmm_rd + 1;
    end
    task cmmm_one(input integer bpp, input integer sa, input integer dx, input integer nx, input integer ny, input integer dix,
                  input integer tp, input [15:0] fcr, input [15:0] bcr, input [15:0] bgr, input integer fcp, input integer bcp,
                  input integer bgp, output integer fail);
        integer y, x, k, ok, nbytes, nwords, bad, outb, got, col, expv, lo, hi, a0;
        begin
            nbytes = (nx * ny + 7) / 8;
            a0 = sa - CMMM_BASE;
            nwords = ((sa + nbytes - 1) >> 2) - (sa >> 2) + 1;
            wr_cmd(0, 0, 0, 0, 256, 32, 0, 8'h0C, 16'hFFFF, bgr, 0, 8'h20); cmmc_wait_ce(4000000, ok);
            cmmm_rd = 0; cmmm_mon = 1;
            // SX alto (R#33) = 5: el CMMM no lo usa
            wr_cmd({8'h05, sa[7:0]}, {5'd0, sa[18:8]}, dx, 8, nx, ny, dix ? 8'h04 : 8'h00, tp ? 8'h1C : 8'h0C, 16'hFFFF, fcr, bcr, 8'h70);
            cmmc_wait_ce(400000, ok);
            cmmm_mon = 0;
            if (!ok) begin wr_reg(6'd52, 8'h00); repeat (200) @(posedge clk); end      // STOP
            bad = 0;
            for (y = 0; y < ny; y = y + 1) for (x = 0; x < nx; x = x + 1) begin
                k = y * nx + x;
                col = cmmm_src[a0 + k / 8][7 - (k % 8)] ? fcp : bcp;
                expv = (tp && col == 0) ? bgp : col;
                got = cmmc_px(bpp, dix ? dx - x : dx + x, 8 + y);
                if (got != expv) bad = bad + 1;
            end
            lo = dix ? dx - nx + 1 : dx; hi = dix ? dx : dx + nx - 1;
            outb = 0;
            for (y = 7; y <= 8 + ny; y = y + 1) for (x = lo - 1; x <= hi + 1; x = x + 1)
                if ((y == 7 || y == 8 + ny || x == lo - 1 || x == hi + 1) && cmmc_px(bpp, x, y) != bgp) outb = outb + 1;
            fail = (!ok || bad != 0 || outb != 0 || cmmm_rd != nwords);
            $display("  %2d bpp SA=%05h DX=%0d NX=%0d NY=%0d DIX=%0d TP=%0d: %0d bytes, CE %0s; lecturas=%0d (esperadas %0d); pixeles mal=%0d; fuera=%0d%0s",
                     bpp, sa, dx, nx, ny, dix, tp, nbytes, ok ? "baja" : "NO baja", cmmm_rd, nwords, bad, outb, fail ? "  <-- MAL" : "");
            if (fail) for (y = 0; y < 2 && y < ny; y = y + 1) begin
                $write("     fila %0d (leido):  ", y);
                for (x = 0; x < nx; x = x + 1) $write(" %0h", cmmc_px(bpp, dix ? dx - x : dx + x, 8 + y));
                $write("\n     fila %0d (modelo): ", y);
                for (x = 0; x < nx; x = x + 1) begin
                    k = y * nx + x; col = cmmm_src[a0 + k / 8][7 - (k % 8)] ? fcp : bcp;
                    $write(" %0h", (tp && col == 0) ? bgp : col);
                end
                $write("\n");
            end
        end
    endtask
    task cmmm_test;
        integer c, bpp, d, n, f, nfail, ncase, fcp, bcp, tbg, j;
        reg [15:0] fcr, bcr, tbgr;
        begin
            for (j = 0; j < 80; j = j + 1) cmmm_src[j] = ((j * 73) ^ (j >> 1) ^ 8'hA5) & 8'hFF;
            cmmm_src[5] = 8'h00; cmmm_src[6] = 8'hFF; cmmm_src[21] = 8'h80; cmmm_src[22] = 8'h01;
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            wr_reg(6'd0, CMMM_BASE[7:0]); wr_reg(6'd1, CMMM_BASE[15:8]); wr_reg(6'd2, {5'd0, CMMM_BASE[18:16]});
            for (j = 0; j < 80; j = j + 1) wr_port(4'd0, cmmm_src[j]);
            nfail = 0; ncase = 0;
            for (c = 0; c < 4; c = c + 1) begin
                case (c)
                    0: begin bpp = 2;  fcr = 16'hAAAA; bcr = 16'h5555; fcp = 2;       bcp = 1;       tbgr = 16'hFFFF; tbg = 3; end
                    1: begin bpp = 4;  fcr = 16'hDDDD; bcr = 16'h2222; fcp = 4'hD;    bcp = 2;       tbgr = 16'h7777; tbg = 7; end
                    2: begin bpp = 8;  fcr = 16'h2323; bcr = 16'h2121; fcp = 8'h23;   bcp = 8'h21;   tbgr = 16'h5A5A; tbg = 8'h5A; end
                    default: begin bpp = 16; fcr = 16'hABCD; bcr = 16'h1234; fcp = 16'hABCD; bcp = 16'h1234; tbgr = 16'h5AC3; tbg = 16'h5AC3; end
                endcase
                wr_reg(6'd6, 8'h84 | c[7:0]);              // B, XIMM 512, CLRM = c
                $display("---- CMMM %0d bpp (R#6=%02h) ----", bpp, 8'h84 | c[7:0]);
                for (n = 8; n <= 12; n = n + 4)
                    for (d = 0; d < 4; d = d + 1) begin       // SA % 4 = 0, 1, 2, 3 (d*5) con DX 144..147
                        cmmm_one(bpp, CMMM_BASE + d * 5 + (n == 12 ? 20 : 0), 144 + d, n, n == 8 ? 7 : 5, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f);
                        nfail = nfail + f; ncase = ncase + 1;
                    end
                cmmm_one(bpp, CMMM_BASE + 3,  145, 5, 3, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 2,  147, 1, 10, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 9,  141, 33, 3, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 28, 176, 32, 12, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 7,  150, 1, 1, 0, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 6,  150, 12, 8, 1, 0, fcr, bcr, 16'h0000, fcp, bcp, 0, f); nfail = nfail + f; ncase = ncase + 1;
                cmmm_one(bpp, CMMM_BASE + 1,  146, 12, 8, 0, 1, fcr, 16'h0000, tbgr, fcp, 0, tbg, f); nfail = nfail + f; ncase = ncase + 1;
            end
            $display("CMMM: %0d casos, %0d mal", ncase, nfail);
            if (nfail == 0) $display("CMMM_OK"); else $display("CMMM_FAIL %0d", nfail);
        end
    endtask

    // ------------------------------------------------------------------
    // +ORDEN=1 (R#6 = 87h y 86h): orden de los bytes del color contra el manual y openMSX
    // (V9990CmdEngine Bpp16::psetColor, executeLMMC/LMCM): a 16 bpp R#48 es el byte bajo del pixel y va a
    // la direccion par (VRAM0), igual que lee la pantalla BD16. LMMV con fondo asimetrico (5AC3h) y WM
    // 00FFh, LMMC (1er byte = bajo), PSET, LINE, LMCM (byte bajo primero), SRCH (encuentra 1234h y no
    // 3412h) y CMMC. A 8 bpp: CMMM con SA = 7FFFEh (los bytes siguen en 00000h, vuelta de 512 KB) y NX*NY
    // = 40, y un diagnostico de CMMC con R#48 != R#49 (el manual pide repetirlos; no cuenta como error).
    // ------------------------------------------------------------------
    integer orden_arg = 0;
    task orden_px16(input integer x, input integer y, input [15:0] exp, input [8*12-1:0] what);
        begin
            if (cmmc_px(16, x, y) != exp) begin
                $display("ERROR %0s: (%0d,%0d) = %04h (par %02h, impar %02h), esperado %04h", what, x, y,
                         cmmc_px(16, x, y), u_vram.mem[y * 1024 + 2 * x], u_vram.mem[y * 1024 + 2 * x + 1], exp);
                nerr = nerr + 1;
            end
        end
    endtask
    task orden_test;
        integer x, y, k, ok, bad, n0;
        reg [7:0] b0, b1;
        reg [7:0] osrc [0:4];
        begin
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            wr_reg(6'd6, 8'h87);
            $display("---- ORDEN 16 bpp (R#6=87h): R#48 = byte bajo = direccion par ----");
            wr_cmd(0, 0, 0, 40, 64, 8, 0, 8'h0C, 16'hFFFF, 16'h5AC3, 0, 8'h20); wait_ce("LMMV bg");
            n0 = nerr;
            bad = 0;
            for (y = 40; y < 48; y = y + 1) for (x = 0; x < 64; x = x + 1) if (cmmc_px(16, x, y) != 16'h5AC3) bad = bad + 1;
            if (bad) begin $display("ERROR LMMV fondo 64x8 FC=5AC3h: %0d pixeles mal", bad); nerr = nerr + 1; end
            chk(19'd40960, 8'hC3, "LMMV par"); chk(19'd40961, 8'h5A, "LMMV impar");
            // WM = 00FFh: solo el byte bajo (direccion par)
            wr_cmd(0, 0, 4, 41, 3, 1, 0, 8'h0C, 16'h00FF, 16'h1234, 0, 8'h20); wait_ce("LMMV wm");
            for (x = 4; x < 7; x = x + 1) orden_px16(x, 41, 16'h5A34, "LMMV wm");
            orden_px16(3, 41, 16'h5AC3, "LMMV wm izq"); orden_px16(7, 41, 16'h5AC3, "LMMV wm der");
            // LMMC 2x1: 34 12 78 56 -> 1234h 5678h
            wr_cmd(0, 0, 8, 42, 2, 1, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h10);
            wait_tr("LMMC16"); wr_port(4'd2, 8'h34); wait_tr("LMMC16"); wr_port(4'd2, 8'h12);
            wait_tr("LMMC16"); wr_port(4'd2, 8'h78); wait_tr("LMMC16"); wr_port(4'd2, 8'h56);
            wait_ce("LMMC16");
            orden_px16(8, 42, 16'h1234, "LMMC16"); orden_px16(9, 42, 16'h5678, "LMMC16");
            orden_px16(7, 42, 16'h5AC3, "LMMC16 izq"); orden_px16(10, 42, 16'h5AC3, "LMMC16 der");
            // PSET
            wr_cmd(0, 0, 20, 43, 0, 0, 0, 8'h0C, 16'hFFFF, 16'hABCD, 0, 8'hE0); wait_ce("PSET16");
            orden_px16(20, 43, 16'hABCD, "PSET16"); orden_px16(21, 43, 16'h5AC3, "PSET16 der");
            // LINE horizontal desde (24,44), NX = 4
            wr_cmd(0, 0, 24, 44, 4, 0, 0, 8'h0C, 16'hFFFF, 16'hBEEF, 0, 8'hB0); wait_ce("LINE16");
            for (x = 24; x < 28; x = x + 1) orden_px16(x, 44, 16'hBEEF, "LINE16");
            // LMCM 1 pixel desde (8,42) = 1234h: P#2 da 34h y luego 12h
            wr_cmd(8, 42, 0, 0, 1, 1, 0, 8'h0C, 16'hFFFF, 0, 0, 8'h30);
            wait_tr("LMCM16"); rd_port(4'd2, b0); wait_tr("LMCM16"); rd_port(4'd2, b1); wait_ce("LMCM16");
            chk8(b0, 8'h34, "LMCM16 1o"); chk8(b1, 8'h12, "LMCM16 2o");
            // SRCH desde (30,45) a la derecha: 1234h esta en (40,45); 3412h no esta
            wr_p0(19'd46160, 8'h34); wr_p0(19'd46161, 8'h12);     // (40,45) = 1234h por P#0, sin pasar por el motor
            wr_cmd(30, 45, 0, 0, 0, 0, 8'h00, 8'h0C, 16'hFFFF, 16'h1234, 0, 8'hC0); wait_ce("SRCH16");
            if (!dut.STATUS.BD || dut.STATUS.BX != 11'd40) begin
                $display("ERROR SRCH16 1234h: BD=%0d BX=%0d, esperado BD=1 BX=40", dut.STATUS.BD, dut.STATUS.BX); nerr = nerr + 1;
            end
            wr_cmd(30, 45, 0, 0, 0, 0, 8'h00, 8'h0C, 16'hFFFF, 16'h3412, 0, 8'hC0); wait_ce("SRCH16x");
            if (dut.STATUS.BD) begin
                $display("ERROR SRCH16 3412h: BD=1 BX=%0d (bytes cruzados)", dut.STATUS.BX); nerr = nerr + 1;
            end
            // CMMC 8x1 con un byte A5h: FC = ABCDh, BC = 1357h
            wr_cmd(0, 0, 32, 46, 8, 1, 0, 8'h0C, 16'hFFFF, 16'hABCD, 16'h1357, 8'h50);
            wait_tr("CMMC16"); wr_port(4'd2, 8'hA5); wait_ce("CMMC16");
            for (x = 0; x < 8; x = x + 1) orden_px16(32 + x, 46, (8'hA5 >> (7 - x)) & 1 ? 16'hABCD : 16'h1357, "CMMC16");
            orden_px16(31, 46, 16'h5AC3, "CMMC16 izq"); orden_px16(40, 46, 16'h5AC3, "CMMC16 der");

            wr_reg(6'd6, 8'h86);
            $display("---- ORDEN 8 bpp (R#6=86h): CMMM con SA = 7FFFEh ----");
            osrc[0] = 8'hAA; osrc[1] = 8'h55; osrc[2] = 8'hF0; osrc[3] = 8'h0F; osrc[4] = 8'h3C;
            wr_p0(19'h7FFFE, osrc[0]); wr_p0(19'h7FFFF, osrc[1]);
            wr_p0(19'h00000, osrc[2]); wr_p0(19'h00001, osrc[3]); wr_p0(19'h00002, osrc[4]);
            wr_cmd(0, 0, 190, 50, 40, 10, 0, 8'h0C, 16'hFFFF, 16'h5A5A, 0, 8'h20); wait_ce("LMMV bg8");
            wr_cmd({8'h00, 8'hFE}, 16'h07FF, 200, 52, 8, 5, 0, 8'h0C, 16'hFFFF, 16'h2323, 16'h2121, 8'h70);
            cmmc_wait_ce(400000, ok);
            if (!ok) begin $display("ERROR CMMM 7FFFEh: CE no baja"); nerr = nerr + 1; wr_reg(6'd52, 8'h00); repeat (200) @(posedge clk); end
            bad = 0;
            for (y = 0; y < 5; y = y + 1) for (x = 0; x < 8; x = x + 1)
                if (cmmc_px(8, 200 + x, 52 + y) != (osrc[y][7 - x] ? 8'h23 : 8'h21)) bad = bad + 1;
            for (x = 198; x < 210; x = x + 1) begin
                if (cmmc_px(8, x, 51) != 8'h5A) bad = bad + 1;
                if (cmmc_px(8, x, 57) != 8'h5A) bad = bad + 1;
            end
            for (y = 52; y < 57; y = y + 1) begin
                if (cmmc_px(8, 199, y) != 8'h5A) bad = bad + 1;
                if (cmmc_px(8, 208, y) != 8'h5A) bad = bad + 1;
            end
            $display("  CMMM SA=7FFFEh 8x5 (40 bits por la vuelta de 512 KB): CE %0s, pixeles mal %0d", ok ? "baja" : "NO baja", bad);
            if (bad) nerr = nerr + 1;
            // diagnostico (no cuenta): CMMC FC = 1234h, BC = 0, DX = 0, NX = 5, NY = 2, bytes FFh FFh.
            // openMSX elige el byte por la paridad de la direccion (X par -> R#48 = 34h)
            wr_cmd(0, 0, 0, 60, 5, 2, 0, 8'h0C, 16'hFFFF, 16'h1234, 0, 8'h50);
            wait_tr("CMMC8d"); wr_port(4'd2, 8'hFF); wait_tr("CMMC8d"); wr_port(4'd2, 8'hFF); wait_ce("CMMC8d");
            for (y = 0; y < 2; y = y + 1) begin
                $write("  INFO CMMC 8 bpp FC=1234h fila %0d:", y);
                for (x = 0; x < 5; x = x + 1) $write(" %02h", cmmc_px(8, x, 60 + y));
                $write("   (openMSX: 34 12 34 12 34)\n");
            end
            if (nerr == 0) $display("ORDEN_OK"); else $display("ORDEN_FAIL %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +PORTS=1: puertos sin uso (openMSX V9990.cc peekIO)
    // ------------------------------------------------------------------
    task ports_test;
        integer p, perr;
        reg [7:0] st;
        begin
            perr = 0;
            $display("---- PORTS: P#4, P#7 (solo escritura), P#8-P#11 (ROM kanji), P#12-P#15 ----");
            for (p = 4; p < 16; p = p + 1) if (p == 4 || p == 7 || p >= 8) begin
                rd_port(4'd5, st);      // P#5 (estado) deja en CD_OUT un valor que no es FFh
                rd_port(p[3:0], rb);
                $display("  P#%0d -> %02h (P#5 antes = %02h)", p, rb, st);
                if (rb !== 8'hFF) perr = perr + 1;
            end
            if (perr == 0) $display("PORTS_OK"); else begin $display("PORTS_ERRORS %0d", perr); nerr = nerr + perr; end
        end
    endtask

    // ------------------------------------------------------------------
    // +EOR=1: cursores sobre un fondo conocido. Semantica de openMSX
    // (V9990BitmapConverter.cc, CursorInfo y convertLine; V9990SDLRasterizer.cc
    // drawBxMode; V9990.hh getCursorYOffset): cursorLine = (cursorY - (Y + 1))
    // & 511 (Y + 2 con entrelazado, en lineas del cuadro), atributo bit 4 =
    // oculto, (CC,EOR) = (0,0) invisible, CC = 0 con EOR -> fondo ^ 7FFFh,
    // CC != 0 -> paleta[R#28*4 + CC] (^ 7FFFh con EOR), el cursor 0 tapa al 1.
    // ------------------------------------------------------------------
    localparam [18:0] CUR_ATR0 = 19'h7FE00, CUR_ATR1 = 19'h7FE08, CUR_PAT0 = 19'h7FF00, CUR_PAT1 = 19'h7FF80;
    reg [14:0] palc [0:63];
    integer cx [0:1], cy [0:1], ca [0:1];
    reg [31:0] cpat [0:1][0:31];
    function [14:0] bgc(input integer x, input integer y); bgc = {y[6:0], x[7:0]}; endfunction
    // BP4 (+EOR, caso de paleta): indice 1..15 del punto (x, y) del bitmap (sin el 0, que es transparente)
    integer e_bp = 0;
    function integer bpidx(input integer x, input integer y); bpidx = ((x + 5 * y) % 15) + 1; endfunction
    function [14:0] bgcol(input integer x, input integer y); bgcol = e_bp ? palc[bpidx(x, y)] : bgc(x, y); endfunction
    task cur_load;
        integer c, rr;
        reg [18:0] a, pa;
        begin
            for (c = 0; c < 2; c = c + 1) begin
                a = c ? CUR_ATR1 : CUR_ATR0; pa = c ? CUR_PAT1 : CUR_PAT0;
                u_vram.mem[a + 0] = cy[c] & 8'hFF; u_vram.mem[a + 2] = (cy[c] >> 8) & 1;
                u_vram.mem[a + 4] = cx[c] & 8'hFF; u_vram.mem[a + 6] = ca[c] | ((cx[c] >> 8) & 3);
                for (rr = 0; rr < 32; rr = rr + 1) begin
                    u_vram.mem[pa + 4*rr + 0] = cpat[c][rr][31:24]; u_vram.mem[pa + 4*rr + 1] = cpat[c][rr][23:16];
                    u_vram.mem[pa + 4*rr + 2] = cpat[c][rr][15: 8]; u_vram.mem[pa + 4*rr + 3] = cpat[c][rr][ 7: 0];
                end
            end
        end
    endtask
    // pixel esperado (openMSX) en (x, y) del display con un desfase vertical voff y horizontal hoff del
    // cursor; el fondo es el pixel x + boff del bitmap (boff: lo que el tiny9990 adelanta el bitmap
    // respecto a la ventana de la imagen, medido en calibrate; en openMSX es 0)
    //   e_w x e_h: imagen (256 x 212 en B1, 384 x 240 en B2); e_il: entrelazado con EO (R#7 = 06h), el
    //   campo e_f (FIELD/EO del cuadro capturado) muestra las lineas 2y + e_f del bitmap; e_ofs: en
    //   overscan (B2/B4) la Y del cursor cuenta desde la linea e_ofs de la imagen (openMSX V9990.hh
    //   getCursorYOffset: 14 en NTSC, 41 en PAL); voff: el +1 (+2 con entrelazado) del atributo (openMSX
    //   CursorInfo). La linea del cursor es (Yb - e_ofs - (Y + voff)) & 511, como cursorLine en openMSX
    //   (V9990SDLRasterizer.cc drawBxMode: cursorY = displayY - getCursorYOffset(), de 2 en 2 con EO)
    integer boff = 0;
    integer e_w = 256, e_h = 212, e_il = 0, e_f = 0, e_ofs = 0, e_adj = 1;
    // e_hx: X del cursor frente a la imagen (DA). 0 en los modos de color directo (openMSX); -1 en
    // BP2/BP4/BP6, donde la capa de paleta (bitmap y cursor juntos) sale un punto adelantada en el
    // tiny9990 (T9990_PALETTE) y el cursor va con el bitmap (boff = 1); por ese mismo adelanto el
    // ultimo punto de la imagen sale en BP con el color de fondo (R#15 = 0: palc[0]), ya en el hito 1
    integer e_hx = 0;
    function integer bline(input integer y); bline = e_il ? (2 * y + e_f) : y; endfunction
    function [14:0] exp_px(input integer x, input integer y, input integer voff, input integer hoff);
        integer c, cl, cxx, yb;
        reg [14:0] v;
        reg done;
        begin
            yb = bline(y);
            v = bgcol(x + boff, yb); done = 0;
            for (c = 0; c < 2; c = c + 1) if (!done) begin
                cl = (yb - e_ofs - (cy[c] + voff)) & 511; cxx = x - (cx[c] + hoff);
                if (cl >= 0 && cl < 32 && cxx >= 0 && cxx < 32 && !(ca[c] & 8'h10) && (ca[c] & 8'hE0) != 0 && cpat[c][cl][31 - cxx]) begin
                    done = 1;
                    if ((ca[c] & 8'hE0) == 8'h20) v = bgcol(x + boff, yb) ^ 15'h7FFF;
                    else begin v = palc[(dut.REG.CSP << 2) + (ca[c] >> 6)]; if (ca[c] & 8'h20) v = v ^ 15'h7FFF; end
                end
            end
            if (e_bp && x == e_w - 1) v = palc[0];
            exp_px = v;
        end
    endfunction
    integer d0, l0;
    task capture_frame;
        begin
            cap_done = 0; cap_arm = 1;
            while (!cap_done) @(posedge clk);
        end
    endtask
    // origen de la imagen en el cuadro capturado: primer punto con DA de la primera linea con DA (el
    // (0,0) del display de openMSX), y que pixel del bitmap sale ahi (boff; los cursores de las pruebas
    // no tocan los 16 primeros puntos de la linea 0)
    task calibrate(output integer dd, output integer ll);
        integer li, di, x, ok, o;
        begin
            dd = -1; ll = -1; boff = -1;
            for (li = 0; li < 320 && ll < 0; li = li + 1)
                for (di = 0; di < 1024 && ll < 0; di = di + 1) if (fb_da[li][di]) begin dd = di; ll = li; end
            if (ll >= 0) for (o = 0; o < 16 && boff < 0; o = o + 1) begin
                ok = 1;
                for (x = 0; x < 16; x = x + 1) if (fb[ll][dd + x] !== bgcol(x + o, bline(0))) ok = 0;
                if (ok) boff = o;
            end
            if (boff < 0) ll = -1;
        end
    endtask
    // compara el cuadro capturado con el modelo; devuelve los pixeles malos
    function integer frame_errs(input integer voff, input integer hoff, input integer verbose);
        integer x, y, e;
        begin
            e = 0;
            for (y = 0; y < e_h; y = y + 1) for (x = 0; x < e_w; x = x + 1)
                if (fb[l0 + y][d0 + x] !== exp_px(x, y, voff, hoff)) begin
                    e = e + 1;
                    if (verbose && e <= 10) $display("    (%0d,%0d): sale %04h, esperado %04h (fondo %04h; cursor 0 en (%0d,%0d), 1 en (%0d,%0d))", x, y,
                                                     fb[l0 + y][d0 + x], exp_px(x, y, voff, hoff), bgcol(x + boff, bline(y)),
                                                     x - (cx[0] + hoff), ((bline(y) - e_ofs - (cy[0] + voff)) & 511),
                                                     x - (cx[1] + hoff), ((bline(y) - e_ofs - (cy[1] + voff)) & 511));
                end
            frame_errs = e;
        end
    endfunction
    // want_f: campo que se quiere comparar (0/1) o -1 (el que salga)
    task eor_case(input string what, input integer want_f);
        integer vo, ho, e, t, best, bvo, bho;
        begin
            cur_load;
            wait_vs(2);
            capture_frame;
            if (want_f >= 0 && cap_eo != want_f) begin wait_vs(1); capture_frame; end
            e_f = cap_eo;
            calibrate(d0, l0);
            if (l0 < 0) begin
                $display("ERROR EOR %0s: no encuentro el bitmap en el cuadro; lineas 28..36, puntos 56..71:", what);
                for (vo = 28; vo < 37; vo = vo + 1)
                    $display("    l%0d: %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h %04h", vo,
                             fb[vo][56], fb[vo][57], fb[vo][58], fb[vo][59], fb[vo][60], fb[vo][61], fb[vo][62], fb[vo][63],
                             fb[vo][64], fb[vo][65], fb[vo][66], fb[vo][67], fb[vo][68], fb[vo][69], fb[vo][70], fb[vo][71]);
                nerr = nerr + 1;
            end
            else begin
                // la referencia es openMSX (cursor e_adj lineas por debajo de su Y, X igual); el mejor ajuste
                // entre Y+0..Y+3 y X-4..X+4 solo se da como diagnostico
                e = frame_errs(e_adj, e_hx, 0);
                best = 1 << 30; bvo = 0; bho = 0;
                for (vo = 0; vo <= 3; vo = vo + 1) for (ho = -4; ho <= 4; ho = ho + 1) begin
                    t = frame_errs(vo, ho, 0);
                    if (t < best) begin best = t; bvo = vo; bho = ho; end
                end
                $display("  EOR %0s: campo %0d, imagen %0dx%0d desde el punto %0d linea %0d (primer punto = X %0d del bitmap); con el cursor en Y+%0d X%0s%0d: %0d pixeles distintos; mejor ajuste Y+%0d X%0s%0d: %0d",
                         what, e_f, e_w, e_h, d0, l0, boff, e_adj, e_hx < 0 ? "" : "+", e_hx, e, bvo, bho < 0 ? "" : "+", bho, best);
                if (e != 0) begin
                    $display("ERROR EOR %0s: no coincide con openMSX (cursor en Y+%0d, X%0s%0d); primeros pixeles distintos:", what, e_adj, e_hx < 0 ? "" : "+", e_hx);
                    e = frame_errs(e_adj, e_hx, 1);
                    if (best != e) begin
                        $display("    con el mejor ajuste (Y+%0d X%0s%0d):", bvo, bho < 0 ? "" : "+", bho);
                        e = frame_errs(bvo, bho, 1);
                    end
                    nerr = nerr + 1;
                end
            end
        end
    endtask
    // BD16 de fondo conocido: el punto (x, y) del bitmap vale bgc(x, y); bpl bytes por linea
    task bg_fill(input integer w, input integer lines, input integer bpl);
        integer x, y;
        begin
            for (y = 0; y < lines; y = y + 1) for (x = 0; x < w; x = x + 1) begin
                u_vram.mem[y*bpl + 2*x]     = bgc(x, y) & 8'hFF;
                u_vram.mem[y*bpl + 2*x + 1] = (bgc(x, y) >> 8) & 8'h7F;
            end
        end
    endtask
    // BP4 de fondo conocido (256 puntos, 128 bytes por linea): indice bpidx(x, y), nibble alto = punto par
    task bp_fill(input integer w, input integer lines);
        integer x, y;
        begin
            for (y = 0; y < lines; y = y + 1) for (x = 0; x < w; x = x + 2)
                u_vram.mem[y*(w/2) + x/2] = {4'(bpidx(x, y)), 4'(bpidx(x + 1, y))};
        end
    endtask
    task eor_test;
        integer k, rr;
        begin
            $display("---- EOR: B1 256x212 BD16 (R#6=83h) con cursores ----");
            bg_fill(256, 512, 512);
            // paleta: 0 = fondo de borde, 1..3 colores de cursor, 4..7 con R#28 = 1
            for (k = 0; k < 16; k = k + 1) begin
                palc[k] = {5'((k * 7 + 3) & 31), 5'((k * 11 + 5) & 31), 5'((k * 13 + 1) & 31)};   // {G, R, B}
                pal_set(k[5:0], palc[k][9:5], palc[k][14:10], palc[k][4:0]);
            end
            wr_reg(6'd13, 8'h00);
            wr_reg(6'd15, 8'h00); wr_reg(6'd28, 8'h00);
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            wr_reg(6'd6, 8'h83); wr_reg(6'd7, 8'h00); wr_reg(6'd8, 8'h80);      // B1 16 bpp, DISP, cursores activos
            e_w = 256; e_h = 212; e_il = 0; e_ofs = 0; e_adj = 1;
            for (rr = 0; rr < 32; rr = rr + 1) begin
                cpat[0][rr] = {8'hF0 ^ rr[7:0], 8'h0F, 8'hAA, 8'h81 ^ (rr[7:0] * 8'd3)};
                cpat[1][rr] = 32'hFFFF_FFFF ^ (32'h1 << rr);
            end
            // 1) cursor 0: CC = 0 y EOR (fondo invertido); cursor 1: CC = 1, sin EOR
            cx[0] = 40;  cy[0] = 50; ca[0] = 8'h20;
            cx[1] = 120; cy[1] = 60; ca[1] = 8'h40;
            eor_case("CC0+EOR / CC1", -1);
            // 2) cursor 0: CC = 2 con EOR (color de paleta invertido)
            ca[0] = 8'hA0;
            eor_case("CC2+EOR / CC1", -1);
            // 3) solapados: cursor 0 (CC = 0, EOR) encima del cursor 1 (CC = 3)
            cx[0] = 100; cy[0] = 80; ca[0] = 8'h20;
            cx[1] = 110; cy[1] = 85; ca[1] = 8'hC0;
            eor_case("solape CC0+EOR sobre CC3", -1);
            // 4) cursor 0 oculto (bit 4) encima del cursor 1: se ve el 1 entero
            cx[0] = 100; cy[0] = 80; ca[0] = 8'h50;
            cx[1] = 100; cy[1] = 80; ca[1] = 8'h80;
            eor_case("cursor 0 oculto", -1);
            // 5) cursor 0 invisible (CC = 0, sin EOR) encima del cursor 1
            ca[0] = 8'h00; ca[1] = 8'hE0;
            eor_case("cursor 0 invisible / CC3+EOR", -1);
            // 6) R#28 = 1: paleta 4..7
            wr_reg(6'd28, 8'h01);
            cx[0] = 200; cy[0] = 150; ca[0] = 8'h60;   // CC = 1, EOR
            cx[1] = 10;  cy[1] = 170; ca[1] = 8'h80;   // CC = 2
            eor_case("R#28 = 1", -1);
            wr_reg(6'd28, 8'h00);
            // 7) X por encima de 255 y por debajo de la pantalla: no se ven
            cx[0] = 300; cy[0] = 20; ca[0] = 8'h20;
            cx[1] = 50;  cy[1] = 230; ca[1] = 8'h40;
            eor_case("fuera de pantalla", -1);
            // 8) Y cerca de 511: el cursor entra por arriba (cursorLine & 511)
            cx[0] = 60;  cy[0] = 500; ca[0] = 8'h20;
            cx[1] = 150; cy[1] = 0;   ca[1] = 8'h40;
            eor_case("Y = 500 y Y = 0", -1);
            // 9) entrelazado con EO (R#7 = 06h, 424 lineas): la Y del cursor va en lineas del cuadro y sale
            //    dos lineas por debajo (Y+2); cada campo muestra las lineas pares o impares de los dos
            wr_reg(6'd7, 8'h06);
            e_il = 1; e_adj = 2;
            cx[0] = 40;  cy[0] = 101; ca[0] = 8'h20;
            cx[1] = 120; cy[1] = 220; ca[1] = 8'h40;
            eor_case("entrelazado campo 0", 0);
            eor_case("entrelazado campo 1", 1);
            wr_reg(6'd7, 8'h00);
            e_il = 0; e_adj = 1;
            // 10) BP4 (R#6 = 81h, paleta): el cursor va en la misma capa que el bitmap; CC = 0 con EOR
            //     invierte el color de paleta del bitmap, CC != 0 con EOR el del cursor
            $display("---- EOR: B1 256x212 BP4 (R#6=81h) ----");
            bp_fill(256, 212);
            wr_reg(6'd6, 8'h81);
            e_bp = 1; e_hx = -1;
            cx[0] = 40;  cy[0] = 50; ca[0] = 8'h20;
            cx[1] = 120; cy[1] = 60; ca[1] = 8'hE0;
            eor_case("BP4 CC0+EOR / CC3+EOR", -1);
            cx[0] = 100; cy[0] = 80; ca[0] = 8'h40;
            cx[1] = 110; cy[1] = 85; ca[1] = 8'h20;
            eor_case("BP4 solape CC1 sobre CC0+EOR", -1);
            e_bp = 0; e_hx = 0;
            wr_reg(6'd6, 8'h83);
            // 11) overscan B2 384x240 (P#7 = 01h): la Y del cursor cuenta desde la linea 14 de la imagen
            //     (41 en PAL), openMSX getCursorYOffset. Se usa BP4 (R#6 = 95h, 512 puntos de imagen): en
            //     B2 a 16 bpp el tiny9990 repite cada pareja de puntos (lo mismo sale en la prueba +HPOS;
            //     ya era asi antes de este hito y no es del cursor)
            $display("---- EOR: B2 384x240 BP4 (R#6=95h, MCS=1) ----");
            bp_fill(512, 300);
            wr_port(4'd7, 8'h01); wr_reg(6'd6, 8'h95);
            e_bp = 1; e_hx = -1;
            e_w = 384; e_h = 240; e_ofs = 14;
            cx[0] = 40;  cy[0] = 20;  ca[0] = 8'h20;
            cx[1] = 330; cy[1] = 500; ca[1] = 8'h40;    // -12: entra por arriba (lineas 3..34)
            eor_case("B2", -1);
            if (ENABLE_PAL != 0) begin
                wr_reg(6'd7, 8'h08);
                e_h = 290; e_ofs = 41;
                cx[0] = 40;  cy[0] = 20;  ca[0] = 8'h20;
                cx[1] = 300; cy[1] = 230; ca[1] = 8'hA0;
                eor_case("B2 PAL", -1);
            end
            wr_reg(6'd7, 8'h00); wr_port(4'd7, 8'h00); wr_reg(6'd6, 8'h83);
            e_bp = 0; e_hx = 0;
            e_w = 256; e_h = 212; e_ofs = 0;
            // 12) la linea registrada del cursor (cur_line_q) frente a la combinacional en cada ACK del
            //     sprite, tambien en los modos que no se comparan punto a punto (B3, B4, PAL, entrelazado)
            cx[0] = 40;  cy[0] = 20;  ca[0] = 8'h20;
            cx[1] = 120; cy[1] = 200; ca[1] = 8'h40;
            cur_load;
            for (k = 0; k < 6; k = k + 1) begin
                wr_port(4'd7, (k >= 3) ? 8'h01 : 8'h00);
                wr_reg(6'd6, (k == 0) ? 8'h97 : ((k == 1) ? 8'h95 : ((k == 2) ? 8'h83 : ((k == 3) ? 8'hA9 : ((k == 4) ? 8'hAB : 8'h97)))));
                wr_reg(6'd7, (k == 2 || k == 5) ? 8'h06 : ((k == 4 && ENABLE_PAL != 0) ? 8'h0E : 8'h00));
                wait_vs(3);
            end
            wr_reg(6'd7, 8'h00); wr_port(4'd7, 8'h00); wr_reg(6'd6, 8'h83);
            $display("  cursor: %0d ACK del sprite (y ciclos siguientes) en todos los casos; cur_line_q distinta de la linea combinacional en %0d", cur_acks, cur_race);
            if (ENABLE_CURSOR_EOR != 0 && (cur_race != 0 || cur_acks == 0)) nerr = nerr + 1;
            if (nerr == 0) $display("EOR_OK"); else $display("EOR_ERRORS %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +BDBP=1: los puntos transparentes de un modo de paleta despues de un modo
    // de color directo. En BP4 el indice 0 es transparente (T9990_BITMAP: PRI) y
    // el selector saca ahi la salida de T9990_COLOR_DECODE si su bit 15 es 0, si
    // no la de la paleta (el fondo). Fuera de BD8/BD16/YJK/YUV la salida de
    // T9990_COLOR_DECODE se quedaba como estaba (OUT <= OUT): tras un BD16 (bit 15
    // a 0) los puntos de indice 0 salian con un color fijo de basura hasta el
    // siguiente reset (revision del area). Desde el reset (OUT = 8000h) salen con
    // el color de fondo, R#15. Se mide el cuadro de BP4 desde el reset y despues
    // de unos cuadros de BD16: los dos tienen que dar el color de fondo.
    // ------------------------------------------------------------------
    function integer bdbp_errs(input integer bdc, input integer verbose);
        integer x, y, e;
        begin
            e = 0;
            for (y = 20; y < 200; y = y + 1) for (x = 8; x < 248; x = x + 1)
                if (fb[l0 + y][d0 + x] !== palc[bdc]) begin
                    e = e + 1;
                    if (verbose && e <= 4) $display("    (%0d,%0d): sale %04h, fondo (paleta %0d) %04h", x, y, fb[l0 + y][d0 + x], bdc, palc[bdc]);
                end
            bdbp_errs = e;
        end
    endfunction
    task bdbp_frame(input string what, output integer e);
        begin
            wait_vs(2);
            capture_frame;
            e_f = cap_eo;
            calibrate(d0, l0);
            if (l0 < 0) begin $display("ERROR BDBP %0s: no encuentro el bitmap", what); e = -1; end
            else begin
                e = bdbp_errs(5, 1);
                $display("  BDBP %0s: imagen desde el punto %0d linea %0d; %0d puntos de indice 0 (de 43200) distintos del fondo (R#15 = 5: %04h)",
                         what, d0, l0, e, palc[5]);
            end
        end
    endtask
    task bdbp_test;
        integer k, x, y, e1, e2;
        begin
            $display("---- BDBP: B1 BP4 (R#6=81h) desde el reset y despues de B1 BD16 (R#6=83h) ----");
            for (k = 0; k < 16; k = k + 1) begin
                palc[k] = {5'((k * 7 + 3) & 31), 5'((k * 11 + 5) & 31), 5'((k * 13 + 1) & 31)};   // {G, R, B}
                pal_set(k[5:0], palc[k][9:5], palc[k][14:10], palc[k][4:0]);
            end
            // BP4: lineas 0..15 con indices 1..15 (para calibrate), el resto indice 0 (transparente). En
            // BD16 se leen 512 bytes por linea: mas alla de estos 32 KB queda el patron de partida de la
            // VRAM, que da colores distintos de 0
            for (y = 0; y < 256; y = y + 1) for (x = 0; x < 256; x = x + 2)
                u_vram.mem[y*128 + x/2] = (y < 16) ? {4'(bpidx(x, y)), 4'(bpidx(x + 1, y))} : 8'h00;
            wr_reg(6'd13, 8'h00); wr_reg(6'd15, 8'h05); wr_reg(6'd28, 8'h00);
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            e_bp = 1; e_il = 0; e_ofs = 0; e_w = 256; e_h = 212;
            wr_reg(6'd7, 8'h00); wr_reg(6'd8, 8'hC0);
            wr_reg(6'd6, 8'h81);
            bdbp_frame("desde el reset   ", e1);
            wr_reg(6'd6, 8'h83);
            wait_vs(3);
            wr_reg(6'd6, 8'h81);
            bdbp_frame("despues de BD16  ", e2);
            e_bp = 0;
            if (e1 == 0 && e2 == 0) $display("BDBP_OK"); else begin nerr = nerr + 1; $display("BDBP_ERRORS %0d %0d", e1, e2); end
        end
    endtask

    // ------------------------------------------------------------------
    // +HPOS=1: que pixel del bitmap sale en el primer y el ultimo punto de la
    // imagen (DA) con el scroll a 0. BD16: el color de 15 bits lleva la X;
    // BP4: la paleta 0..15 lleva el indice (X mod 16). Diagnostico, no falla.
    // ------------------------------------------------------------------
    // indice de paleta (0..15) cuyo color es c, o -1
    function integer pal_idx(input [14:0] c);
        integer k;
        begin pal_idx = -1; for (k = 15; k >= 0; k = k - 1) if (palc[k] === c) pal_idx = k; end
    endfunction
    task hpos_case(input string what, input [7:0] r6, input integer bd16, input integer w);
        integer x, y, li, di, d_first, d_last, l_first, nda, v [0:3];
        begin
            for (y = 0; y < 4; y = y + 1) for (x = 0; x < w; x = x + 1) begin
                if (bd16) begin
                    u_vram.mem[y*w*2 + 2*x] = x & 8'hFF; u_vram.mem[y*w*2 + 2*x + 1] = ((x >> 8) & 3) | (y << 2);
                end else if (x % 2 == 0)
                    u_vram.mem[y*w/2 + x/2] = {x[3:0], 4'(x + 1)};
            end
            wr_reg(6'd6, r6); wr_reg(6'd7, 8'h00); wr_reg(6'd8, 8'hC0);
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            wait_vs(2);
            for (li = 0; li < 320; li = li + 1) for (di = 0; di < 1024; di = di + 1) begin fb[li][di] = 15'h0; fb_da[li][di] = 1'b0; end
            capture_frame;
            l_first = -1;
            for (li = 0; li < 320 && l_first < 0; li = li + 1) for (di = 0; di < 1024; di = di + 1) if (fb_da[li][di] && l_first < 0) l_first = li;
            d_first = -1; d_last = -1; nda = 0;
            for (di = 0; di < 1024; di = di + 1) if (fb_da[l_first][di]) begin if (d_first < 0) d_first = di; d_last = di; nda = nda + 1; end
            for (x = 0; x < 4; x = x + 1) v[x] = bd16 ? (fb[l_first][d_first + x] & 10'h3FF) : pal_idx(fb[l_first][d_first + x]);
            $display("  HPOS %0s: imagen desde el punto %0d (%0d puntos) linea %0d; los cuatro primeros puntos son %0s %0d %0d %0d %0d, el ultimo %0d",
                     what, d_first, nda, l_first, bd16 ? "X" : "el indice (X mod 16)", v[0], v[1], v[2], v[3],
                     bd16 ? (fb[l_first][d_last] & 10'h3FF) : pal_idx(fb[l_first][d_last]));
        end
    endtask
    task hpos_test;
        integer k;
        begin
            $display("---- HPOS: alineacion del bitmap con la imagen (scroll 0) ----");
            for (k = 0; k < 16; k = k + 1) begin
                palc[k] = {5'((k * 7 + 3) & 31), 5'((k * 11 + 5) & 31), 5'((k * 13 + 1) & 31)};
                pal_set(k[5:0], palc[k][9:5], palc[k][14:10], palc[k][4:0]);
            end
            wr_reg(6'd13, 8'h00); wr_reg(6'd15, 8'h00);
            hpos_case("B1 BD16", 8'h83, 1, 256);
            hpos_case("B3 BD16", 8'h97, 1, 512);
            hpos_case("B1 BP4 ", 8'h81, 0, 256);
            hpos_case("B3 BP4 ", 8'h95, 0, 512);
            wr_port(4'd7, 8'h01);
            hpos_case("B2 BP4 ", 8'h95, 0, 512);
            hpos_case("B2 BD16", 8'h97, 1, 512);
            hpos_case("B4 BP4 ", 8'hA9, 0, 1024);
            wr_port(4'd7, 8'h00);
            $display("HPOS_DONE");
        end
    endtask

    // ------------------------------------------------------------------
    // +R16T=1: R#16 (ajuste de posicion). Mueve el sincronismo frente a la
    // ventana del generador. Se mide de tres maneras independientes:
    //   - VS en la ventana: h_cnt/v_cnt de T9990_TIMING en la subida de VS
    //     (exacto: posicion lineal = -(dv * puntos + dh) modulo el cuadro);
    //   - DE frente a HS: punto de subida de DE contado desde la subida de HS;
    //   - DE frente a VS: linea de inicio de la tanda de DE contada desde VS
    //     (con vuelta: con +5..+8 lineas el borde inferior cruza el VS).
    // Desplazamiento esperado: k = (n ^ 7) - 7 pasos (0 = estandar, 1..7 arriba /
    // izquierda, Fh..8 abajo / derecha), como openMSX (getLeftBorder/getTopBorder
    // menos su valor con R#16 = 00h) y la tabla de R#16 del manual (pag. 84); paso
    // horizontal del manual: 1 punto en P1/B1, 2 en P2/B2/B3, 4 en B4.
    // ------------------------------------------------------------------
    function integer exp_dh(input integer md, input integer t);    // md: 0=B1/P1 1=B3/P2 2=B2 3=B4
        begin
            case (md)
                0: exp_dh = t - 7;
                1, 2: exp_dh = 2 * (t - 7);
                default: exp_dh = 4 * (t - 7);
            endcase
        end
    endfunction
    integer base_rise, base_run, base_lines, base_dots, base_delines;
    task r16_mode(input string what, input integer md, input [7:0] r6, input mcs, input [7:0] r7);
        integer i, t, dh, dv, ok, lin, exp_lin, exp_wh, exp_wv, n_tot;
        reg [7:0] v;
        reg [7:0] vals [0:9];
        begin
            vals = '{8'h00, 8'h0F, 8'h08, 8'h07, 8'h01, 8'hF0, 8'h80, 8'h70, 8'h87, 8'h78};
            wr_port(4'd7, {7'd0, mcs});
            wr_reg(6'd6, r6); wr_reg(6'd7, r7); wr_reg(6'd8, 8'hC0);
            for (i = 0; i < 10; i = i + 1) begin
                v = vals[i];
                wr_reg(6'd16, v);
                wait_vs(2);
                measure(r7[1] ? 2 : 1);    // con entrelazado, dos campos
                if (i == 0) begin base_rise = de_rise_min; base_run = de_run_min; base_lines = f_lines_min; base_dots = l_dots_min; base_delines = de_nrise_min; end
                t = v[3:0] ^ 4'd7; dh = (ENABLE_R16 != 0) ? exp_dh(md, t) : 0;
                t = v[7:4] ^ 4'd7; dv = (ENABLE_R16 != 0) ? (t - 7) : 0;
                // VS en la ventana: el cuadro de sincronismo empieza dv lineas y dh puntos antes que la ventana
                n_tot = base_lines * base_dots;
                exp_lin = ((-(dv * base_dots + dh)) % n_tot + n_tot) % n_tot;
                exp_wh = exp_lin % base_dots; exp_wv = exp_lin / base_dots;
                ok = (vs_wh_min == exp_wh) && (vs_wh_max == exp_wh) && (vs_wv_min == exp_wv) && (vs_wv_max == exp_wv) &&
                     (de_rise_min == de_rise_max) && (de_rise_min == base_rise + dh) &&
                     (de_run_min == de_run_max) && (de_run_min == (base_run + dv + base_lines) % base_lines) && (de_runs_max == 1) &&
                     (de_nrise_min == base_delines) && (de_nrise_max == base_delines) &&
                     (f_lines_min == base_lines) && (f_lines_max == base_lines) && (l_dots_min == base_dots) && (l_dots_max == base_dots) &&
                     (vs_hs_coinc == vs_rises) && (vsw_min == 3) && (vsw_max == 3) && (pal_chg_bad == 0) && (eo_chg_bad == 0) &&
                     (eo_notoggle == 0) && (eo_win_bad == 0) && (lost_slots() == 0);
                $display("  %0s R#16=%02h: VS en la ventana (%0d,%0d) [esperado (%0d,%0d)], DE sube en el punto %0d (%0d; esperado %0d), DE empieza en la linea %0d (%0d; esperado %0d), %0d lineas x %0d puntos, VS %0d lineas, EO fuera de VS %0d / sin alternar %0d / distinto de la ventana %0d -> %0s",
                         what, v, vs_wh_min, vs_wv_min, exp_wh, exp_wv, de_rise_min, de_rise_min - base_rise, dh,
                         de_run_min, de_run_min - base_run, dv, f_lines_min, l_dots_min, vsw_min, eo_chg_bad, eo_notoggle, eo_win_bad, ok ? "ok" : "MAL");
                if (!ok) begin nerr = nerr + 1; print_json("RESULT_R16"); end
            end
            wr_reg(6'd16, 8'h00);
        end
    endtask
    task r16_test;
        begin
            $display("---- R16: ajuste de posicion (manual pag. 84; openMSX getLeftBorder/getTopBorder) ----");
            r16_mode("B1     ", 0, 8'h82, 1'b0, 8'h00);
            r16_mode("P1     ", 0, 8'h00, 1'b0, 8'h00);
            r16_mode("B3     ", 1, 8'h96, 1'b0, 8'h00);
            r16_mode("P2     ", 1, 8'h50, 1'b0, 8'h00);
            r16_mode("B2     ", 2, 8'h96, 1'b1, 8'h00);
            r16_mode("B4     ", 3, 8'hAA, 1'b1, 8'h00);
            r16_mode("B1 IL  ", 0, 8'h82, 1'b0, 8'h06);  // entrelazado (IL + EO): FIELD alineado con VS
            if (ENABLE_PAL) r16_mode("B1 PAL ", 0, 8'h82, 1'b0, 8'h08);
            if (ENABLE_PAL) r16_mode("B4 PAL ", 3, 8'hAA, 1'b1, 8'h0E);  // PAL entrelazado
            wr_port(4'd7, 8'h00);
            wr_reg(6'd7, 8'h00);
            if (nerr == 0) $display("R16_OK"); else $display("R16_ERRORS %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +R16CHG=1: R#16 cambiado en marcha, en sitios distintos del cuadro, con
    // cambios que cruzan el limite del cuadro de sincronismo (F0h -> 10h, 10h ->
    // 80h, 80h -> 70h, 0Fh -> 01h, 08h -> 07h, 88h -> 77h...). Como en openMSX
    // (V9990.cc frameStart: el VSYNC cada getUCTicksPerFrame, el principio de la
    // imagen en getTopBorder) el SINCRONISMO no cambia nunca: todos los cuadros
    // de VS a VS y todas las lineas de HS a HS iguales al regimen con R#16 = 00h,
    // el HS siempre del mismo ancho, el VS siempre del ancho del modo y con la
    // subida de HS, FIELD alterna en cada VS (entrelazado) y solo cambia con el.
    // La irregularidad de cada cambio va a la VENTANA de T9990_TIMING (el cuadro
    // de imagen: puntos entre dos v_rst): como mucho 2 cuadros irregulares por
    // cambio y de +- (15 lineas + 60 puntos). Tres VS despues de cada cambio, el
    // VS cae en el sitio de la ventana que toca al valor nuevo (el de la prueba
    // r16). Al volver a 00h, VS en el (0,0) de la ventana. (Con el reajuste del
    // sincronismo de antes, cada cambio sacaba un cuadro de VS a VS de +- 16
    // lineas y una linea de HS a HS de +- 60 puntos: revision del area.)
    // ------------------------------------------------------------------
    task r16chg_case(input string what, input integer md, input [7:0] r6, input mcs, input [7:0] r7, input integer vsw);
        integer i, ok, tot, dots, fclk, hsw, t, edh, edv, n_tot, exp_lin, posbad, wmar;
        reg [7:0] vals [0:12];
        begin
            vals = '{8'h00, 8'hF0, 8'h10, 8'h80, 8'h70, 8'h80, 8'h0F, 8'h01, 8'h08, 8'h07, 8'h88, 8'h77, 8'h00};
            wr_port(4'd7, {7'd0, mcs});
            wr_reg(6'd6, r6); wr_reg(6'd7, r7); wr_reg(6'd8, 8'hC0); wr_reg(6'd16, 8'h00);
            wait_vs(2);
            measure(1);                         // regimen estable con R#16 = 00h
            tot = f_lines_min; dots = l_dots_min; fclk = f_clk_min; hsw = hsw_min;
            n_tot = tot * dots; wf_ref = n_tot;
            wait_vs(1);
            @(negedge clk); stats_reset; meas = 1; posbad = 0;
            for (i = 1; i < 13; i = i + 1) begin
                repeat (fclk / 3 + i * 7919) @(posedge clk);    // cada escritura en otro sitio del cuadro
                wr_reg(6'd16, vals[i]);
                wait_vs(3);                                     // la ventana se reajusta en menos de 1 cuadro + 31 lineas
                @(negedge clk);
                t = vals[i][3:0] ^ 4'd7; edh = (ENABLE_R16 != 0) ? exp_dh(md, t) : 0;
                t = vals[i][7:4] ^ 4'd7; edv = (ENABLE_R16 != 0) ? (t - 7) : 0;
                exp_lin = ((-(edv * dots + edh)) % n_tot + n_tot) % n_tot;
                if (vs_wh_last != exp_lin % dots || vs_wv_last != exp_lin / dots) begin
                    posbad = posbad + 1;
                    $display("    R#16=%02h: VS en la ventana (%0d,%0d), esperado (%0d,%0d)", vals[i], vs_wh_last, vs_wv_last, exp_lin % dots, exp_lin / dots);
                end
            end
            meas = 0;
            wmar = (ENABLE_R16 != 0) ? (15 * dots + 60) : 0;
            ok = (frames_done >= 36) && (f_lines_min == tot) && (f_lines_max == tot) && (f_clk_min == fclk) && (f_clk_max == fclk) &&
                 (l_dots_min == dots) && (l_dots_max == dots) && (hsw_min == hsw) && (hsw_max == hsw) &&
                 (vsw_min == vsw) && (vsw_max == vsw) && (vs_hs_coinc == vs_rises) &&
                 (eo_chg_bad == 0) && (eo_notoggle == 0) && (eo_win_bad == 0) && (pal_chg_bad == 0) && (posbad == 0) &&
                 (wf_n >= 30) && (wf_min >= n_tot - wmar) && (wf_max <= n_tot + wmar) && (wf_irr <= 24) && (lost_slots() == 0);
            $display("  %0s: %0d cuadros con 12 cambios de R#16: sincronismo %0d..%0d lineas (estable %0d), %0d..%0d puntos por linea (estable %0d), HS %0d..%0d puntos, VS %0d..%0d lineas, VS con HS %0d de %0d, EO fuera de VS %0d / sin alternar %0d / distinto de la ventana %0d; ventana: %0d cuadros, %0d irregulares, de %0d a %0d puntos (estable %0d, margen %0d); VS fuera de su sitio tras el cambio %0d -> %0s",
                     what, frames_done, f_lines_min, f_lines_max, tot, l_dots_min, l_dots_max, dots, hsw_min, hsw_max,
                     vsw_min, vsw_max, vs_hs_coinc, vs_rises, eo_chg_bad, eo_notoggle, eo_win_bad,
                     wf_n, wf_irr, wf_min, wf_max, n_tot, wmar, posbad, ok ? "ok" : "MAL");
            if (!ok) begin nerr = nerr + 1; print_json("RESULT_R16CHG"); end
            // de vuelta en 00h: regimen estable exacto, VS en el (0,0) de la ventana y ventana regular
            measure(2);
            ok = (f_lines_min == tot) && (f_lines_max == tot) && (l_dots_min == dots) && (l_dots_max == dots) &&
                 (vs_wh_min == 0) && (vs_wh_max == 0) && (vs_wv_min == 0) && (vs_wv_max == 0) && (eo_notoggle == 0) &&
                 (wf_irr == 0) && (wf_n >= 1) && (lost_slots() == 0);
            $display("  %0s: R#16 = 00h otra vez: %0d lineas x %0d puntos, VS en la ventana (%0d,%0d), cuadros de la ventana irregulares %0d de %0d -> %0s",
                     what, f_lines_min, l_dots_min, vs_wh_min, vs_wv_min, wf_irr, wf_n, ok ? "ok" : "MAL");
            if (!ok) begin nerr = nerr + 1; print_json("RESULT_R16CHG_FIN"); end
            wf_ref = -1;
        end
    endtask
    task r16chg_test;
        begin
            $display("---- R16CHG: cambios de R#16 en marcha ----");
            r16chg_case("B1 IL     ", 0, 8'h82, 1'b0, 8'h06, 3);
            if (ENABLE_PAL) r16chg_case("B4 PAL IL ", 3, 8'hAA, 1'b1, 8'h0E, 3);
            else            r16chg_case("B4 IL     ", 3, 8'hAA, 1'b1, 8'h06, 3);
            // B5 (HSCN, tabla de 440 lineas con VS de 8): con el reajuste del sincronismo de antes, el de la
            // linea 12 caia dentro del VS con adj_v <= -5 (revision del area)
            r16chg_case("B5        ", 3, 8'hA6, 1'b0, 8'h01, 8);
            wr_port(4'd7, 8'h00);
            wr_reg(6'd7, 8'h00);
            if (nerr == 0) $display("R16CHG_OK"); else $display("R16CHG_ERRORS %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +PALT=1: cuadro PAL de 313 lineas
    // ------------------------------------------------------------------
    // lines: lineas por cuadro; de/da: lineas con DE (con bordes) y con DA (imagen); bt/bb: bordes
    // superior e inferior en lineas; vsw: lineas de VS; lclk: ciclos de CLK por linea (-1 = no se mira)
    task pal_case(input string what, input [7:0] r6, input mcs, input [7:0] r7, input integer lines, input integer delines,
                  input integer dalines, input integer bt, input integer bb, input integer p, input integer vsw, input integer lclk);
        integer ok;
        begin
            wr_port(4'd7, {7'd0, mcs});
            wr_reg(6'd6, r6); wr_reg(6'd7, r7); wr_reg(6'd8, 8'hC0);
            wait_vs(2);
            measure(2);
            ok = (f_lines_min == lines) && (f_lines_max == lines) && (de_lines_min == delines) && (de_lines_max == delines) &&
                 (da_lines_min == dalines) && (da_lines_max == dalines) && (btop_min == bt) && (btop_max == bt) &&
                 (bbot_min == bb) && (bbot_max == bb) &&
                 (pal_min == p) && (pal_max == p) && (pal_chg_bad == 0) && (vsw_min == vsw) && (vsw_max == vsw) && (vs_hs_coinc == vs_rises) &&
                 (lost_slots() == 0) &&
                 (lclk < 0 || (l_clk_min == lclk && l_clk_max == lclk && f_clk_min == lines * lclk && f_clk_max == lines * lclk &&
                               l_c21_min == lclk / 5 && l_c21_max == lclk / 5));
            $display("  %0s: %0d lineas, %0d ciclos/linea, %0d ciclos/cuadro, DE %0d lineas desde la %0d, imagen %0d lineas, bordes %0d/%0d, PAL=%0d, VS %0d lineas -> %0s", what,
                     f_lines_min, l_clk_min, f_clk_min, de_lines_min, de_run_min, da_lines_min, btop_min, bbot_min, pal_min, vsw_min, ok ? "ok" : "MAL");
            print_json("RESULT_PAL");
            if (!ok) nerr = nerr + 1;
        end
    endtask
    task palt_test;
        integer pl, pd;
        begin
            $display("---- PALT: cuadro PAL (R#7 bit 3; openMSX displayPAL_MCLK/XTAL) ----");
            pl = (ENABLE_PAL != 0);
            //       modo       R#6    MCS   R#7    lineas         DE              imagen  bordes                      PAL VS  ciclos/linea
            pal_case("B1 NTSC", 8'h82, 1'b0, 8'h00, 262,           240,            212,    14,           14,           0,  3,  6840);
            pal_case("B1 PAL ", 8'h82, 1'b0, 8'h08, pl ? 313 : 262, pl ? 290 : 240, 212,    pl ? 41 : 14, pl ? 37 : 14, pl, 3,  6840);
            pal_case("B3 PAL ", 8'h96, 1'b0, 8'h08, pl ? 313 : 262, pl ? 290 : 240, 212,    pl ? 41 : 14, pl ? 37 : 14, pl, 3,  6840);
            pal_case("B2 PAL ", 8'h96, 1'b1, 8'h08, pl ? 313 : 262, pl ? 290 : 240, pl ? 290 : 240, 0,  0,            pl, 3,  6840);
            pal_case("B2 NTSC", 8'h96, 1'b1, 8'h00, 262,           240,            240,    0,            0,            0,  3,  6840);
            pal_case("B4 PAL ", 8'hAA, 1'b1, 8'h08, pl ? 313 : 262, pl ? 290 : 240, pl ? 290 : 240, 0,  0,            pl, 3,  6840);
            pal_case("P1 PAL ", 8'h00, 1'b0, 8'h08, pl ? 313 : 262, pl ? 290 : 240, 212,    pl ? 41 : 14, pl ? 37 : 14, pl, 3,  6840);
            pal_case("P2 PAL ", 8'h50, 1'b0, 8'h08, pl ? 313 : 262, pl ? 290 : 240, 212,    pl ? 41 : 14, pl ? 37 : 14, pl, 3,  6840);
            pal_case("B1 PAL IL", 8'h82, 1'b0, 8'h0E, pl ? 313 : 262, pl ? 290 : 240, 212, pl ? 41 : 14, pl ? 37 : 14, pl, 3,  6840);
            // HSCN + PAL: el manual (R#7, pag. 81) dice que PAL no vale en B5/B6; las 440/525 lineas no cambian
            pal_case("B5 PAL ", 8'hA6, 1'b0, 8'h09, 440,           400,            400,    0,            0,            0,  8,  4240);
            // B6 (C25M + HSCN, 525 lineas) no se mide: en el tiny9990 v_cnt es de 9 bits y nunca llega a
            // V480_TOTAL - 1 = 524, asi que B6 no genera VS (ya era asi en el hito 1; B6 no esta soportado)
            pal_case("B1 NTSC", 8'h82, 1'b0, 8'h00, 262,           240,            212,    14,           14,           0,  3,  6840);
            wr_port(4'd7, 8'h00);
            if (nerr == 0) $display("PALT_OK"); else $display("PALT_ERRORS %0d", nerr);
        end
    endtask

    // ------------------------------------------------------------------
    // +REPLAY=<fichero>: traza de E/S de openMSX (mk_replay.py: "W pp vv ms" /
    // "R pp 00 ms"). Antes de tocar la VRAM por P#0 o R#0-5/R#32-52 espera CE=0
    // y antes de P#2 espera TR=1 (sin los tiempos del Z80 el replay va mas
    // deprisa que un comando).
    // ------------------------------------------------------------------
    integer rp_fh, rp_n, rp_sel = 0, rp_inc = 1, rp_w, rp_cmds = 0, rp_ms;
    string  rp_line, rp_file, vram_out;
    reg [7:0] rp_d;
    task replay_run(input string fname);
        integer port, val, rc;
        begin
            rp_fh = $fopen(fname, "r");
            if (rp_fh == 0) begin $display("ERROR: no puedo abrir el replay %s", fname); $finish; end
            rp_n = 0;
            while (!$feof(rp_fh)) begin
                rc = $fgets(rp_line, rp_fh);
                if (rc > 0) begin
                    rc = $sscanf(rp_line, "W %h %h %d", port, val, rp_ms);
                    if (rc >= 2) begin
                        rp_n = rp_n + 1;
                        if (port == 8'h64) begin rp_sel = val & 63; rp_inc = !(val & 8'h80); end
                        if (port == 8'h60 || (port == 8'h63 && (rp_sel <= 5 || (rp_sel >= 32 && rp_sel <= 52)))) begin
                            rp_w = 0; while (dut.STATUS.CE && rp_w < 40000000) begin @(posedge clk); rp_w = rp_w + 1; end
                            if (dut.STATUS.CE) $display("AVISO: CE no baja antes de R#%0d (evento %0d)", rp_sel, rp_n);
                            if (port == 8'h63 && rp_sel == 52) rp_cmds = rp_cmds + 1;
                        end
                        if (port == 8'h62) begin
                            rp_w = 0; while (!dut.STATUS.TR && rp_w < 4000000) begin @(posedge clk); rp_w = rp_w + 1; end
                            if (!dut.STATUS.TR) $display("AVISO: TR no sube antes de P#2 (evento %0d)", rp_n);
                        end
                        wr_port(port[3:0], val[7:0]);
                        if (port == 8'h63 && rp_inc) rp_sel = (rp_sel + 1) & 63;
                    end else begin
                        rc = $sscanf(rp_line, "R %h %h %d", port, val, rp_ms);
                        if (rc >= 1) begin
                            rp_n = rp_n + 1;
                            if (port == 8'h62) begin
                                rp_w = 0; while (!dut.STATUS.TR && rp_w < 4000000) begin @(posedge clk); rp_w = rp_w + 1; end
                            end
                            rd_port(port[3:0], rp_d);
                        end
                    end
                end
            end
            $fclose(rp_fh);
            rp_w = 0; while (dut.STATUS.CE && rp_w < 40000000) begin @(posedge clk); rp_w = rp_w + 1; end
            repeat (2000) @(posedge clk);
            $display("replay: %0d eventos, %0d comandos", rp_n, rp_cmds);
        end
    endtask
    task vram_dump(input string fname);
        integer fh, a, nz;
        reg [31:0] w32;
        begin
            fh = $fopen(fname, "wb");
            nz = 0;
            for (a = 0; a < 524288; a = a + 4) begin
                w32 = {u_vram.mem[a+3], u_vram.mem[a+2], u_vram.mem[a+1], u_vram.mem[a]};
                if (w32 != 32'd0) nz = nz + 1;
                $fwrite(fh, "%u", w32);          // 4 bytes, little-endian
            end
            $fclose(fh);
            $display("VRAM volcada en %0s: %0d palabras no nulas", fname, nz);
        end
    endtask


    // ------------------------------------------------------------------
    // +YCC=1 (tnCart #31): YJK y YUV: color de los bitmaps YJK / YUV en B1
    // (256 px, 8 bpp, R#6 = 82h; PLTM = R#13[7:6]) contra el modelo de openMSX V9990BitmapConverter
    // (draw_YJK_YUV_PAL): cada grupo de 4 bytes comparte K/V = {byte1[2:0], byte0[2:0]} (pixeles 0,1) y
    // J/U = {byte3[2:0], byte2[2:0]} (pixeles 2,3), con signo de 6 bits; Y = byte[7:3]. YUV: R = Y+U,
    // G = (5Y-2U-V)/4, B = Y+V; YJK = lo mismo con G y B cambiados. Se captura la salida RGB en DE
    // (4 lineas del cuadro, columnas 40..229) y se compara con la VRAM. El desfase (dx, dy) entre la
    // salida (con bordes) y la VRAM se calibra con BD8 (modelo de t9990_color_decode.sv, sin grupos de 4);
    // YJK y YUV tienen que dar 0 pixeles mal con ese mismo desfase. Imprime YCC_OK / YCC_FAIL.
    // ------------------------------------------------------------------
    integer ycc_arg = 0;       // 1 = YJK, 2 = YUV, 3 = BD8: el test los corre los tres (BD8 calibra el desfase)
    localparam YCC_W = 320, YCC_H = 48;
    reg [14:0] ycc_cap [0:YCC_W*YCC_H-1];
    reg        ycc_en = 0;
    integer    ycc_y = -1, ycc_x = 0;
    always @(posedge clk) if (dclk_en && ycc_en) begin
        if (vs && !vs_p) ycc_y = -1;
        if (de && !de_p) begin ycc_y = ycc_y + 1; ycc_x = 0; end
        else if (de) ycc_x = ycc_x + 1;
        if (de && ycc_y >= 0 && ycc_y < YCC_H && ycc_x < YCC_W) ycc_cap[ycc_y * YCC_W + ycc_x] = {g, r, b};
    end
    function integer ycc_clamp(input integer v);
        begin ycc_clamp = (v < 0) ? 0 : ((v > 31) ? 31 : v); end
    endfunction
    function [14:0] ycc_model(input integer kind, input integer a);   // a = direccion del pixel en B1
        integer gb, i, u, v, y, rr, gg, bb;
        reg [7:0] d0, d1, d2, d3, dd;
        begin
            gb = a & ~3; i = a & 3;
            d0 = u_vram.mem[gb]; d1 = u_vram.mem[gb + 1]; d2 = u_vram.mem[gb + 2]; d3 = u_vram.mem[gb + 3]; dd = u_vram.mem[a];
            u = (d2 & 7) + ((d3 & 3) << 3) - ((d3 & 4) << 3);
            v = (d0 & 7) + ((d1 & 3) << 3) - ((d1 & 4) << 3);
            y = (dd & 8'hF8) >> 3;
            rr = ycc_clamp(y + u); gg = ycc_clamp((5 * y - 2 * u - v) / 4); bb = ycc_clamp(y + v);
            if (kind == 1) begin i = gg; gg = bb; bb = i; end            // YJK: G y B cambiados
            if (kind == 3) begin                                         // BD8 como t9990_color_decode.sv
                gg = {dd[7], dd[6], dd[5], dd[7], dd[6]}; rr = {dd[4], dd[3], dd[2], dd[4], dd[3]};
                bb = {dd[1], dd[0], dd[1], dd[0], dd[1] | dd[0]};
            end
            ycc_model = {gg[4:0], rr[4:0], bb[4:0]};
        end
    endfunction
    // pixeles malos de 4 lineas (cy0..cy0+3) x columnas 40..229 de la captura contra el modelo desplazado (dx, dy)
    function integer ycc_bad(input integer kind, input integer cy0, input integer dx, input integer dy);
        integer cy, cx, n;
        begin
            n = 0;
            for (cy = cy0; cy < cy0 + 4; cy = cy + 1) for (cx = 40; cx < 230; cx = cx + 1)
                if (!(kind == 3 && u_vram.mem[(cy + dy) * 256 + cx + dx] == 8'h00) && ycc_cap[cy * YCC_W + cx] !== ycc_model(kind, (cy + dy) * 256 + cx + dx)) n = n + 1;   // BD8: el color 0 es transparente
            ycc_bad = n;
        end
    endfunction
    task ycc_one(input integer kind, input integer calib, inout integer cdx, inout integer cdy, output integer nbad);
        integer dx, dy, best, bdx, bdy, nb0, cx;
        begin
            @(posedge clk); while (!(dclk_en && vs && !vs_p)) @(posedge clk);
            ycc_y = -1; ycc_en = 1;
            @(posedge clk); while (!(dclk_en && vs && !vs_p)) @(posedge clk);       // un cuadro completo
            @(posedge clk); ycc_en = 0;
            best = 1 << 30; bdx = 0; bdy = 0;
            if (calib) begin
                for (dy = -30; dy <= 0; dy = dy + 1) for (dx = -40; dx <= 8; dx = dx + 1) begin
                    nb0 = ycc_bad(kind, 24, dx, dy);
                    if (nb0 < best) begin best = nb0; bdx = dx; bdy = dy; end
                end
                cdx = bdx; cdy = bdy;
            end
            else begin
                nbad = ycc_bad(kind, 24, cdx, cdy);
                // y su mejor desfase propio (cerca del de calibracion), solo informativo
                for (dy = cdy - 1; dy <= cdy + 1; dy = dy + 1) for (dx = cdx - 6; dx <= cdx + 6; dx = dx + 1) begin
                    nb0 = ycc_bad(kind, 24, dx, dy);
                    if (nb0 < best) begin best = nb0; bdx = dx; bdy = dy; end
                end
            end
            if (calib) nbad = best;
            $display("  %0s: desfase de calibracion dx=%0d dy=%0d -> pixeles mal=%0d de %0d (mejor propio dx=%0d dy=%0d: %0d)",
                     (kind == 1) ? "YJK" : ((kind == 2) ? "YUV" : "BD8"), cdx, cdy, nbad, 4 * 190, bdx, bdy, best);
            if (nbad != 0) for (cx = 40; cx < 52; cx = cx + 1)
                $display("     cx=%0d vram=%02h leido GRB=%04h modelo=%04h", cx, u_vram.mem[(24 + cdy) * 256 + cx + cdx], ycc_cap[24 * YCC_W + cx], ycc_model(kind, (24 + cdy) * 256 + cx + cdx));
        end
    endtask
    task ycc_test;
        integer kk, h, cdx, cdy, nb, tot;
        begin
            for (kk = 0; kk < 64 * 256 + 16; kk = kk + 1) begin
                h = kk * 32'h9E3779B1; h = h ^ (h >>> 15); h = h * 32'h85EBCA6B; h = h ^ (h >>> 13);
                u_vram.mem[kk] = h[23:16];
            end
            wr_reg(6'd17, 8'h00); wr_reg(6'd18, 8'h00); wr_reg(6'd19, 8'h00); wr_reg(6'd20, 8'h00);
            tot = 0; cdx = 0; cdy = 0;
            wr_reg(6'd13, 8'h40); ycc_one(3, 1, cdx, cdy, nb); tot = tot + nb;      // PLTM = RGB 256 (BD8): calibra
            wr_reg(6'd13, 8'h80); ycc_one(1, 0, cdx, cdy, nb); tot = tot + nb;      // PLTM = YJK
            wr_reg(6'd13, 8'hC0); ycc_one(2, 0, cdx, cdy, nb); tot = tot + nb;      // PLTM = YUV
            if (tot == 0) $display("YCC_OK"); else $display("YCC_FAIL %0d", tot);
        end
    endtask

    // ------------------------------------------------------------------
    // secuencia
    // ------------------------------------------------------------------
    integer r6 = 0, r7 = 0, r16 = 0, mcs_arg = 0, nframes = 3, k, wd, gdh, gdv, gtot, glin;
    integer blit_arg = 0, ports_arg = 0, eor_arg = 0, r16t_arg = 0, palt_arg = 0, replay_arg = 0, ch0_arg = 0, slots, hpos_arg = 0, r16chg_arg = 0, bdbp_arg = 0;
    string  vid_name;
    initial begin
        $timeformat(-9, 1, " ns", 0);      // el instante de la asercion de t9990_ram.sv sale en ns
        if (!$value$plusargs("R6=%d", r6)) r6 = 0;
        if (!$value$plusargs("R7=%d", r7)) r7 = 0;
        if (!$value$plusargs("R16=%h", r16)) r16 = 0;
        if (!$value$plusargs("MCS=%d", mcs_arg)) mcs_arg = 0;
        if (!$value$plusargs("FRAMES=%d", nframes)) nframes = 3;
        if (!$value$plusargs("BLIT=%d", blit_arg)) blit_arg = 0;
        if (!$value$plusargs("PORTS=%d", ports_arg)) ports_arg = 0;
        if (!$value$plusargs("EOR=%d", eor_arg)) eor_arg = 0;
        if (!$value$plusargs("R16T=%d", r16t_arg)) r16t_arg = 0;
        if (!$value$plusargs("R16CHG=%d", r16chg_arg)) r16chg_arg = 0;
        if (!$value$plusargs("PALT=%d", palt_arg)) palt_arg = 0;
        if (!$value$plusargs("HPOS=%d", hpos_arg)) hpos_arg = 0;
        if (!$value$plusargs("BDBP=%d", bdbp_arg)) bdbp_arg = 0;
        if (!$value$plusargs("CMMC=%d", cmmc_arg)) cmmc_arg = 0;
        if (!$value$plusargs("CMMM=%d", cmmm_arg)) cmmm_arg = 0;
        if (!$value$plusargs("ORDEN=%d", orden_arg)) orden_arg = 0;
        if (!$value$plusargs("P2NOTR=%d", p2notr)) p2notr = 0;      // 1 = P#2 sin sondear TR (con +CMMC=1)
        if (!$value$plusargs("YCC=%d", ycc_arg)) ycc_arg = 0;        // 1 = YJK, 2 = YUV, 3 = BD8 (calibracion) en B1
        if (!$value$plusargs("CH0=%d", ch0_arg)) ch0_arg = 0;
        if (!$value$plusargs("ACKDLY=%d", ackdly)) ackdly = 0;
        if ($value$plusargs("REPLAY=%s", rp_file)) replay_arg = 1;
        if (!$value$plusargs("VRAMOUT=%s", vram_out)) vram_out = "";
        ch0 = (ch0_arg != 0);
        if (blit_arg) r6 = 130;
        if (ycc_arg) r6 = 130;
        if (cmmc_arg || cmmm_arg || orden_arg) r6 = 132;   // 84h: B, XIMM 512, 2 bpp (el test cambia CLRM)
        // VRAM de partida: patron (como el banco de la Zynq) salvo en el replay (openMSX arranca a 0)
        if (!replay_arg && !eor_arg && !hpos_arg) for (k = 0; k < 524288; k = k + 1) u_vram.mem[k] = (k * 7 + (k >> 8) * 13 + 5) & 8'hFF;
        $display("tb_t9990_core: ENABLE_PAL=%0d ENABLE_CURSOR_EOR=%0d ENABLE_R16=%0d R#6=%02h R#7=%02h R#16=%02h MCS=%0d frames=%0d ch0=%0d ackdly=%0d",
                 ENABLE_PAL, ENABLE_CURSOR_EOR, ENABLE_R16, r6[7:0], r7[7:0], r16[7:0], mcs_arg, nframes, ch0, ackdly);
        repeat (8) @(posedge clk); rst_n <= 1; repeat (80) @(posedge clk);
        wr_reg(6'd13, 8'h00);
        wr_reg(6'd14, 8'h00);
        for (k = 0; k < 16; k = k + 1) begin
            wr_port(4'd1, (k * 2) & 8'h1F);
            wr_port(4'd1, (31 - k * 2) & 8'h1F);
            wr_port(4'd1, k & 8'h1F);
        end
        if (mcs_arg) wr_port(4'd7, 8'h01);
        wr_reg(6'd6, r6[7:0]);
        wr_reg(6'd7, r7[7:0]);
        wr_reg(6'd16, r16[7:0]);
        wr_reg(6'd25, 8'h06);
        wr_reg(6'd8, 8'hC0);
        wd = 0; while (!dut.u_clk.TG_EN && wd < 100000) begin @(posedge clk); wd = wd + 1; end
        if (!dut.u_clk.TG_EN) begin $display("ERROR: TG_EN nunca sube"); $finish; end
        $display("TG_EN alto tras %0d ciclos; RESO=%0d", wd, reso);
        if (blit_arg)  blit_test;
        if (ports_arg) ports_test;
        if (eor_arg)   eor_test;
        if (r16t_arg)  r16_test;
        if (r16chg_arg) r16chg_test;
        if (palt_arg)  palt_test;
        if (hpos_arg)  hpos_test;
        if (bdbp_arg)  bdbp_test;
        if (cmmc_arg)  begin cmmc_test; if (p2notr) p2notr_extra; end
        if (cmmm_arg)  cmmm_test;
        if (orden_arg) orden_test;
        if (ycc_arg)   ycc_test;
        if (replay_arg) begin
            replay_run(rp_file);
            $display("registros tras el replay: R#6=%02h R#7=%02h R#8=%02h R#13=%02h RESO=%0d", dut.u_port.vdp_reg[6], dut.u_port.vdp_reg[7], dut.u_port.vdp_reg[8], dut.u_port.vdp_reg[13], reso);
            if (vram_out != "") vram_dump(vram_out);
        end
        if (!blit_arg && !ports_arg && !eor_arg && !r16t_arg && !r16chg_arg && !palt_arg && !replay_arg && !hpos_arg && !bdbp_arg
            && !cmmc_arg && !cmmm_arg && !orden_arg && !ycc_arg) begin
            if ($value$plusargs("VIDDUMP=%s", vid_name)) begin
                vid_fh = $fopen(vid_name, "wb");
                if (vid_fh == 0) begin $display("ERROR: no puedo crear %0s", vid_name); $finish; end
            end
            measure(nframes);
            if (vid_fh != 0) begin $fclose(vid_fh); vid_fh = 0; $display("VIDDUMP %0s: %0d puntos", vid_name, vid_n); end
            print_json("RESULT");
            // geometria: 1368 ciclos del maestro de 21 MHz (6840 de CLK) por linea, 262 lineas (313 con PAL)
            k = ((r7 & 8'h09) == 8'h08 && ENABLE_PAL != 0) ? 313 : 262;
            // VS en la ventana del generador con R#16 (paso horizontal del manual: x1 / x2 / x4 segun DCKM)
            gdh = (ENABLE_R16 != 0) ? (((r16 & 15) ^ 7) - 7) * (((r6 >> 4) & 3) == 0 ? 1 : (((r6 >> 4) & 3) == 1 ? 2 : 4)) : 0;
            gdv = (ENABLE_R16 != 0) ? ((((r16 >> 4) & 15) ^ 7) - 7) : 0;
            gtot = k * l_dots_min;
            glin = ((-(gdv * l_dots_min + gdh)) % gtot + gtot) % gtot;
            if ((r7 & 8'h01) == 0 &&
                l_clk_min == 6840 && l_clk_max == 6840 && l_c21_min == 1368 && l_c21_max == 1368 &&
                f_lines_min == k && f_lines_max == k && f_clk_min == k * 6840 && f_clk_max == k * 6840 &&
                vsw_min == 3 && vsw_max == 3 && vs_hs_coinc == vs_rises && l_dots_min == l_dots_max && pal_chg_bad == 0 &&
                pal_min == ((k == 313) ? 1 : 0) && pal_max == pal_min && eo_chg_bad == 0 && de_runs_max == 1 &&
                vs_wh_min == glin % l_dots_min && vs_wh_max == vs_wh_min && vs_wv_min == glin / l_dots_min && vs_wv_max == vs_wv_min &&
                u_vram.n_lat_odd == 0 && u_vram.n_acc_off == 0 && u_vram.lat_max <= 13 &&
                lost_slots() == 0)
                $display("GEOM_OK 1368 x %0d", k);
            else begin $display("GEOM_FAIL"); nerr = nerr + 1; end
        end
        slots = lost_slots();
        $display("LOST_SLOTS=%0d (latencia de la VRAM hasta el ACK: %0d..%0d ciclos de CLK desde TIMING)", slots, u_vram.lat_min, u_vram.lat_max);
        if (ackdly > 0) begin
            if (slots > 0) $display("ASSERT_SELFTEST_OK: con el ACK %0d ciclos tarde la asercion salta %0d veces", ackdly, slots);
            else           $display("ASSERT_SELFTEST_FAIL: con el ACK %0d ciclos tarde la asercion no salta", ackdly);
        end
        $display("TB_DONE errores=%0d", nerr);
        $finish;
    end
    initial begin #4000000000; #4000000000; #4000000000; #4000000000; #4000000000; $display("TB_TIMEOUT"); $finish; end
endmodule
