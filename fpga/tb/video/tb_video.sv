//
// tb_video.sv -- banco del upscan y de la salida TMDS de V9990TANG (Verilator 5.020)
//
// Fuente sintetica con la temporizacion del V9990 en tnCart: CLK_BASE de
// 108 MHz, enables del UMA (21,6 MHz cada 5 ciclos, 14,4 MHz a 0/7/15/22 de
// cada 30), divisor de t9990_clock.sv (B1 21M/4, B2 14M/2, B3 21M/2, B4
// 14M/1), Video.DCLK = OR de dclk_en retrasado 1 y 2 ciclos (cartridge_v9990.sv),
// linea de 1368 puntos de 21,6 MHz = 6840 ciclos de CLK_BASE (342/456/684/912
// puntos), HS de 25/34/50/68 puntos, VS de 3 lineas, cuadro de 262 o 313
// lineas, INTERLACE/FIELD y un patron conocido.
//
// Salida: CLK_TMDS_P de 27 MHz (= 108 x 5/4 / 5, como el rPLL TMDS y el CLKDIV
// de board_wt200b_clock.sv), mesocrono de CLK_BASE con la fase +PHASE.
//
// Instancias, todas con la misma entrada:
//   orig : VIDEO_UPSCAN_ORIG + BOARD_REV1_TMDS_OUT_ORIG (copia del hito 1, ref/)
//   b1   : VIDEO_UPSCAN #(BLEND=1) + BOARD_REV1_TMDS_OUT (nuevos)
//   b0   : VIDEO_UPSCAN #(BLEND=0) + BOARD_REV1_TMDS_OUT (nuevos)
// Se mira lo que BOARD_REV1_TMDS_OUT entrega al DVI_TX (vs, hs, de, r, g, b).
//
// Unidades de tiempo: 1 = 1/10,8 GHz (CLK_BASE = 100, 135 MHz = 80, 27 MHz = 400).
//
// Plusargs: +MODE=1..4 (B1..B4) +PAL=0/1 +IL=0/1 +PAT=0/1/2 +PHASE=n
//           +FRAMES=n (cuadros comprobados) +SEQ=1 (secuencia de cambios de
//           modo, PAL e INTERLACE) +SEQ=2 (PAL cambia de cuadro a cuadro con
//           +MODE e +IL fijos) +PALLAG=n (ciclos de CLK_BASE: con n > 0 IN.PAL
//           cambia n ciclos despues del flanco de bajada de VS_n que abre el
//           cuadro; con n < 0, |n| ciclos antes, al final del cuadro anterior;
//           0 = en el mismo flanco de DCLK que VS_n)
//
`timescale 1ns/1ps
`default_nettype none

module tb_video;
    localparam int T_BASE = 100;
    localparam int T_SER  = 80;
    localparam int T_PIX  = 400;

    int mode_arg   = 1;
    int pal_arg    = 0;
    int il_arg     = 0;
    int pat_arg    = 0;
    int phase_arg  = 37;
    int frames_arg = 4;
    int seq_arg    = 0;
    int pallag_arg = 0;

    /***************************************************************
     * relojes y reset
     ***************************************************************/
    logic clk_base = 0;
    logic clk_ser  = 0;
    logic clk_pix  = 0;
    logic rst_n    = 0;
    logic tmds_ready = 0;

    always #(T_BASE/2) clk_base = ~clk_base;

    initial begin
        void'($value$plusargs("MODE=%d",   mode_arg));
        void'($value$plusargs("PAL=%d",    pal_arg));
        void'($value$plusargs("IL=%d",     il_arg));
        void'($value$plusargs("PAT=%d",    pat_arg));
        void'($value$plusargs("PHASE=%d",  phase_arg));
        void'($value$plusargs("FRAMES=%d", frames_arg));
        void'($value$plusargs("SEQ=%d",    seq_arg));
        void'($value$plusargs("PALLAG=%d", pallag_arg));
        if (pallag_arg < -2000000 || pallag_arg > 2000000) $fatal(1, "PALLAG fuera de +-2000000");
        $display("CONFIG MODE=B%0d PAL=%0d IL=%0d PAT=%0d PHASE=%0d FRAMES=%0d SEQ=%0d PALLAG=%0d",
                 mode_arg, pal_arg, il_arg, pat_arg, phase_arg, frames_arg, seq_arg, pallag_arg);
        src_init();     // aqui y no en otro initial: la fuente tiene que ver ya los plusargs
        // (Verilator 5.020 se cae con un #0 aqui: los retrasos nulos se saltan)
        if (phase_arg % T_SER != 0) #(phase_arg % T_SER);
        fork
            forever #(T_SER/2) clk_ser = ~clk_ser;
            begin
                if (phase_arg - (phase_arg % T_SER) != 0) #(phase_arg - (phase_arg % T_SER));
                forever #(T_PIX/2) clk_pix = ~clk_pix;
            end
        join
    end

    initial begin
        #(20*T_BASE + 3);
        rst_n = 1;
        tmds_ready = 1;
    end

    /***************************************************************
     * fuente V9990 (dominio CLK_BASE)
     ***************************************************************/
    typedef struct { int mode; int pal; int il; int n; } fcfg_t;
    fcfg_t seq[$];
    int    seq_pos = 0;
    int    seq_left = 0;

    function automatic fcfg_t mk(int m, int p, int i, int n);
        fcfg_t c;
        c.mode = m; c.pal = p; c.il = i; c.n = n;
        return c;
    endfunction

    task automatic seq_init();
        // modo, PAL, INTERLACE, cuadros
        seq.delete();
        seq.push_back(mk(1, 0, 0, 2));
        seq.push_back(mk(1, 1, 0, 2));
        seq.push_back(mk(3, 1, 1, 3));
        seq.push_back(mk(3, 0, 1, 2));
        seq.push_back(mk(2, 1, 0, 2));
        seq.push_back(mk(4, 0, 0, 2));
        seq.push_back(mk(4, 1, 1, 3));
        seq.push_back(mk(2, 0, 1, 2));
        seq.push_back(mk(1, 0, 0, 2));
    endtask

    // SEQ=2: PAL de cada cuadro (se repite), con +MODE e +IL fijos
    int seq2_pal [0:7] = '{1, 1, 0, 1, 0, 0, 1, 0};

    function automatic int htot_of(int m);
        case (m) 1: return 342; 2: return 456; 3: return 684; default: return 912; endcase
    endfunction
    function automatic int hsync_of(int m);
        case (m) 1: return 25; 2: return 34; 3: return 50; default: return 68; endcase
    endfunction
    function automatic VIDEO::RESOLUTION_t reso_of(int m);
        case (m) 1: return VIDEO::RESOLUTION_B1; 2: return VIDEO::RESOLUTION_B2;
                 3: return VIDEO::RESOLUTION_B3; default: return VIDEO::RESOLUTION_B4; endcase
    endfunction
    function automatic logic [7:0] hash8(int h, int v, int f, int salt);
        int unsigned x;
        x = (h * 32'h9E3779B1) ^ (v * 32'h85EBCA77) ^ (f * 32'hC2B2AE3D) ^ (salt * 32'h27D4EB2F);
        x = x ^ (x >> 15);
        x = x * 32'h2C1B3C6D;
        x = x ^ (x >> 12);
        return x[7:0];
    endfunction

    // UMA: enables de 21,6 y 14,4 MHz (uma.sv, DIV = 30)
    int   uma_cnt;
    logic en21, en14;
    always @(posedge clk_base) begin
        if (!rst_n) begin
            uma_cnt <= 0; en21 <= 0; en14 <= 0;
        end else begin
            uma_cnt <= (uma_cnt == 29) ? 0 : uma_cnt + 1;
            en21    <= (uma_cnt % 5) == 0;
            en14    <= (uma_cnt == 0) || (uma_cnt == 7) || (uma_cnt == 15) || (uma_cnt == 22);
        end
    end

    // divisor de t9990_clock.sv y DCLK de cartridge_v9990.sv
    int         cur_mode;
    int         cur_pal;
    fcfg_t      nxt;            // configuracion del cuadro siguiente (se calcula un cuadro antes, para +PALLAG < 0)
    int         prev_pal;       // PAL del cuadro anterior (para +PALLAG > 0)
    longint     t_fb = 0;       // instante del ultimo cambio de cuadro de la fuente
    int         cur_il;
    logic       field;
    int         frame_id;
    logic [2:0] dcnt;
    logic       dclk_en;
    wire        master = (cur_mode == 2 || cur_mode == 4) ? en14 : en21;
    wire  [2:0] ddiv   = (cur_mode == 1) ? 3'd3 : (cur_mode == 4) ? 3'd0 : 3'd1;
    always @(posedge clk_base) begin
        if (!rst_n) begin
            dcnt <= 0; dclk_en <= 0;
        end else if (master) begin
            if (dcnt == 0) begin dcnt <= ddiv; dclk_en <= 1; end
            else           begin dcnt <= dcnt - 1'd1; dclk_en <= 0; end
        end else begin
            dclk_en <= 0;
        end
    end
    logic dff1 = 0, dff0 = 0;
    always @(posedge clk_base) begin
        dff1 <= dclk_en;
        dff0 <= dff1;
    end
    wire dclk = dff1 | dff0;

    // generador de puntos (en el flanco de Video.DCLK, como video_* en cartridge_v9990.sv)
    int   ph, pv;
    logic [7:0] s_r, s_g, s_b;
    logic s_hs_n, s_vs_n;
    VIDEO::RESOLUTION_t s_reso;
    longint in_frames = 0;

    function automatic fcfg_t next_cfg();
        fcfg_t c;
        if (seq_arg == 0) begin
            c = mk(mode_arg, pal_arg, il_arg, 1);
        end else if (seq_arg == 2) begin
            seq_pos = (seq_pos + 1) % 8;
            c = mk(mode_arg, seq2_pal[seq_pos], il_arg, 1);
        end else begin
            if (seq_left == 0) begin
                seq_pos  = (seq_pos + 1) % seq.size();
                seq_left = seq[seq_pos].n;
            end
            c = seq[seq_pos];
            seq_left = seq_left - 1;
        end
        return c;
    endfunction

    task automatic src_init();
        seq_init();
        cur_mode = mode_arg; cur_pal = pal_arg; cur_il = il_arg;
        if (seq_arg == 1) begin cur_mode = 1; cur_pal = 0; cur_il = 0; seq_pos = -1; seq_left = 0; end
        if (seq_arg == 2) begin cur_pal = 0; seq_pos = -1; end
        prev_pal = cur_pal;
        nxt = next_cfg();
        field = 0; frame_id = 0;
        ph = 0; pv = 0;
    endtask

    always @(posedge dclk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= htot_of(cur_mode) - 1;
            pv <= (cur_pal ? 313 : 262) - 1;
            s_r <= 0; s_g <= 0; s_b <= 0; s_hs_n <= 1; s_vs_n <= 1;
            s_reso <= reso_of(cur_mode);
        end else begin
            int nh, nv, m, p, il, fid;
            logic fl;
            nh = ph + 1; nv = pv;
            m = cur_mode; p = cur_pal; il = cur_il; fl = field; fid = frame_id;
            if (nh == htot_of(cur_mode)) begin
                nh = 0;
                nv = pv + 1;
                if (nv == (cur_pal ? 313 : 262)) begin
                    fcfg_t c;
                    nv = 0;
                    c  = nxt;
                    nxt = next_cfg();
                    m  = c.mode; p = c.pal; il = c.il;
                    fl = c.il ? !field : 1'b0;
                    fid = frame_id + 1;
                    cur_mode <= m; cur_pal <= p; cur_il <= il; field <= fl; frame_id <= fid;
                    prev_pal <= cur_pal; t_fb <= $time;
                    in_frames <= in_frames + 1;
                end
            end
            ph <= nh; pv <= nv;
            s_hs_n <= !(nh < hsync_of(m));
            s_vs_n <= !(nv < 3);
            s_reso <= reso_of(m);
            s_b    <= nv[7:0];
            case (pat_arg)
                1: begin
                    s_r <= nh[0] ? 8'hFF : 8'h00;
                    s_g <= nh[1] ? 8'hFF : 8'h00;
                end
                2: begin
                    s_r <= hash8(nh, nv, fid, 1);
                    s_g <= hash8(nh, nv, fid, 2);
                end
                default: begin
                    s_r <= nh[7:0];
                    s_g <= {nv[8], fid[2:0], fl, 3'b011};
                end
            endcase
        end
    end

    VIDEO_IF vin();
    assign vin.R          = s_r;
    assign vin.G          = s_g;
    assign vin.B          = s_b;
    assign vin.HS_n       = s_hs_n;
    assign vin.VS_n       = s_vs_n;
    assign vin.DCLK       = dclk;
    assign vin.RESOLUTION = s_reso;
    assign vin.HSCAN      = 1'b0;
    assign vin.INTERLACE  = cur_il[0];
    assign vin.FIELD      = field;
    // PAL desplazado +PALLAG ciclos de CLK_BASE respecto del cambio de cuadro de la fuente (el
    // flanco de DCLK en el que baja VS_n). El T9990 lo fijaria en su v_rst, como STATUS.EO: un
    // ciclo de CLK_BASE antes de que Video.VS_n baje; la integracion puede llevarlo directo o
    // registrado. Con n > 0 vale el del cuadro anterior durante n ciclos; con n < 0 pasa al del
    // cuadro siguiente |n| ciclos antes del cambio de cuadro.
    logic pal_shift = 0;
    always @(posedge clk_base) begin
        longint dt, flen;
        dt   = $time - t_fb;
        flen = longint'(cur_pal ? 313 : 262) * 6840 * T_BASE;
        if (pallag_arg > 0) pal_shift <= (dt < longint'(pallag_arg) * T_BASE) ? prev_pal[0] : cur_pal[0];
        else                pal_shift <= (flen - dt <= longint'(-pallag_arg) * T_BASE) ? nxt.pal[0] : cur_pal[0];
    end
    assign vin.PAL        = (pallag_arg == 0) ? cur_pal[0] : pal_shift;

    /***************************************************************
     * DUT: original del hito 1, BLEND = 1 y BLEND = 0
     ***************************************************************/
    VIDEO_IF vo_orig();
    VIDEO_IF vo_b1();
    VIDEO_IF vo_b0();

    VIDEO_UPSCAN_ORIG          u_orig (.RESET_n(rst_n), .DCLK(clk_pix), .IN(vin), .OUT(vo_orig));
    VIDEO_UPSCAN #(.BLEND(1))  u_b1   (.RESET_n(rst_n), .DCLK(clk_pix), .IN(vin), .OUT(vo_b1));
    VIDEO_UPSCAN #(.BLEND(0))  u_b0   (.RESET_n(rst_n), .DCLK(clk_pix), .IN(vin), .OUT(vo_b0));

    BOARD_REV1_TMDS_OUT_ORIG t_orig (.RESET_n(rst_n), .IN(vo_orig), .TMDS_READY(tmds_ready), .CLK_S(clk_ser), .CLK_P(clk_pix),
                                     .TMDS_CLKP(), .TMDS_CLKN(), .TMDS_DATAP(), .TMDS_DATAN());
    BOARD_REV1_TMDS_OUT      t_b1   (.RESET_n(rst_n), .IN(vo_b1),   .TMDS_READY(tmds_ready), .CLK_S(clk_ser), .CLK_P(clk_pix),
                                     .TMDS_CLKP(), .TMDS_CLKN(), .TMDS_DATAP(), .TMDS_DATAN());
    BOARD_REV1_TMDS_OUT      t_b0   (.RESET_n(rst_n), .IN(vo_b0),   .TMDS_READY(tmds_ready), .CLK_S(clk_ser), .CLK_P(clk_pix),
                                     .TMDS_CLKP(), .TMDS_CLKN(), .TMDS_DATAP(), .TMDS_DATAN());

    // lo que llega al DVI_TX
    wire       o_vs = t_orig.DVI_TX_Top_inst.I_rgb_vs, o_hs = t_orig.DVI_TX_Top_inst.I_rgb_hs, o_de = t_orig.DVI_TX_Top_inst.I_rgb_de;
    wire [7:0] o_r  = t_orig.DVI_TX_Top_inst.I_rgb_r,  o_g  = t_orig.DVI_TX_Top_inst.I_rgb_g,  o_b  = t_orig.DVI_TX_Top_inst.I_rgb_b;
    wire       a_vs = t_b1.DVI_TX_Top_inst.I_rgb_vs,   a_hs = t_b1.DVI_TX_Top_inst.I_rgb_hs,   a_de = t_b1.DVI_TX_Top_inst.I_rgb_de;
    wire [7:0] a_r  = t_b1.DVI_TX_Top_inst.I_rgb_r,    a_g  = t_b1.DVI_TX_Top_inst.I_rgb_g,    a_b  = t_b1.DVI_TX_Top_inst.I_rgb_b;
    wire       z_vs = t_b0.DVI_TX_Top_inst.I_rgb_vs,   z_hs = t_b0.DVI_TX_Top_inst.I_rgb_hs,   z_de = t_b0.DVI_TX_Top_inst.I_rgb_de;
    wire [7:0] z_r  = t_b0.DVI_TX_Top_inst.I_rgb_r,    z_g  = t_b0.DVI_TX_Top_inst.I_rgb_g,    z_b  = t_b0.DVI_TX_Top_inst.I_rgb_b;

    /***************************************************************
     * comprobadores de la salida (b1 y b0)
     ***************************************************************/
    dvi_check #(.NAME("b1"), .IS_B0(0)) chk_b1 (
        .clk(clk_pix), .en(tmds_ready), .vs(a_vs), .hs(a_hs), .de(a_de), .r(a_r), .g(a_g), .b(a_b),
        .f_pal(cur_pal), .f_il(cur_il), .f_field(int'(field)), .f_frame(frame_id), .f_mode(cur_mode), .pat(pat_arg));
    dvi_check #(.NAME("b0"), .IS_B0(1)) chk_b0 (
        .clk(clk_pix), .en(tmds_ready), .vs(z_vs), .hs(z_hs), .de(z_de), .r(z_r), .g(z_g), .b(z_b),
        .f_pal(cur_pal), .f_il(cur_il), .f_field(int'(field)), .f_frame(frame_id), .f_mode(cur_mode), .pat(pat_arg));

    /***************************************************************
     * igualdad con el original y entre BLEND = 1 y BLEND = 0
     ***************************************************************/
    longint cmp_cycles = 0, cmp_ntsc_de_cycles = 0;
    int     err_orig = 0, err_orig_de = 0, err_b0_sync = 0;
    int     orig_de_pal_diff = 0;
    always @(posedge clk_pix) begin
        if (rst_n && tmds_ready) begin
            cmp_cycles <= cmp_cycles + 1;
            if ({o_vs, o_hs, o_r, o_g, o_b} !== {a_vs, a_hs, a_r, a_g, a_b}) begin
                if (err_orig < 10) $display("ERROR orig!=b1 t=%0t vs %b/%b hs %b/%b rgb %h%h%h/%h%h%h", $time, o_vs, a_vs, o_hs, a_hs, o_r, o_g, o_b, a_r, a_g, a_b);
                err_orig <= err_orig + 1;
            end
            if (!t_b1.frame_pal) begin
                cmp_ntsc_de_cycles <= cmp_ntsc_de_cycles + 1;
                if (o_de !== a_de) begin
                    if (err_orig_de < 10) $display("ERROR orig!=b1 (DE, cuadro NTSC) t=%0t de %b/%b", $time, o_de, a_de);
                    err_orig_de <= err_orig_de + 1;
                end
            end else if (o_de !== a_de) begin
                orig_de_pal_diff <= orig_de_pal_diff + 1;
            end
            if ({a_vs, a_hs, a_de} !== {z_vs, z_hs, z_de}) begin
                if (err_b0_sync < 10) $display("ERROR b1!=b0 en sincronismos t=%0t", $time);
                err_b0_sync <= err_b0_sync + 1;
            end
        end
    end

    /***************************************************************
     * caja blanca: registro OUT de los buffers frente a la tabla de pesos
     *  - BLEND = 1: OUT = ((2^k - wc) * P + wc * C) >> k  (la mezcla de tnCart)
     *  - BLEND = 0: OUT = (2 * wc >= 2^k) ? C : P        (el de mas peso; empate -> C)
     *  - las dos instancias tienen el mismo estado (R_ADDR, out_state...) en cada ciclo
     ***************************************************************/
    // kind: 0 = OUT <= 0, 1 = OUT se mantiene, 2 = mezcla (wc, k)
    function automatic void wtab(input int reso, input int st, output int kind, output int wc, output int k);
        kind = 2; wc = 1; k = 0;
        case (reso)
            0: begin k = 1; case (st) 0,1,3,4: wc = 2; 2: wc = 1; default: kind = 0; endcase end
            1: begin k = 3; case (st) 0,2,4,6,8,10,12,14: wc = 8; 1: wc = 1; 3: wc = 2; 5: wc = 3; 7: wc = 4;
                                      9: wc = 5; 11: wc = 6; 13: wc = 7; default: kind = 0; endcase end
            2: begin k = 2; case (st) 0,4: wc = 4; 1: wc = 3; 2: wc = 2; 3: wc = 1; default: kind = 0; endcase end
            3: begin k = 4; case (st) 0: wc = 16; 1: wc = 2; 2: wc = 3; 3: wc = 4; 4: wc = 5; 5: wc = 6; 6: wc = 7;
                                      7: wc = 8; 8: wc = 9; 9: wc = 10; 10: wc = 11; 11: wc = 12; 12: wc = 13;
                                      13: wc = 14; 14: wc = 15; default: kind = 1; endcase end
            4, 5: begin k = 3; case (st) 0,8: wc = 8; 1: wc = 7; 2: wc = 6; 3: wc = 5; 4: wc = 4; 5: wc = 3;
                                         6: wc = 2; 7: wc = 1; default: kind = 0; endcase end
            default: begin k = 0; wc = 1; end
        endcase
    endfunction

    int     wb_err_b1 = 0, wb_err_b0 = 0, wb_err_state = 0;
    longint wb_checks = 0, wb_blend_checks = 0, wb_take_p = 0;
    logic [7:0] exp_b1_r, exp_b0_r, exp_b1_g, exp_b0_g;
    logic       exp_valid = 0;
    int     b4_first_step = -1;
    int     wb_err_b0_addr = 0;
    logic   b4_mark = 0;
    int     b4_cnt = 0;
    logic [11:0] b0_addr;
    logic        b0_addr_valid = 0;
    always @(posedge clk_pix) begin
        if (rst_n) begin
            int kind, wc, k, st, reso;
            logic [7:0] p_r, c_r, p_g, c_g;
            if (exp_valid) begin
                wb_checks <= wb_checks + 1;
                if (u_b1.u_buff_r.OUT !== exp_b1_r || u_b1.u_buff_g.OUT !== exp_b1_g) begin
                    if (wb_err_b1 < 10) $display("ERROR caja blanca BLEND=1 t=%0t OUT %h/%h esperado %h/%h", $time, u_b1.u_buff_r.OUT, u_b1.u_buff_g.OUT, exp_b1_r, exp_b1_g);
                    wb_err_b1 <= wb_err_b1 + 1;
                end
                if (u_b0.u_buff_r.OUT !== exp_b0_r || u_b0.u_buff_g.OUT !== exp_b0_g) begin
                    if (wb_err_b0 < 10) $display("ERROR caja blanca BLEND=0 t=%0t OUT %h/%h esperado %h/%h", $time, u_b0.u_buff_r.OUT, u_b0.u_buff_g.OUT, exp_b0_r, exp_b0_g);
                    wb_err_b0 <= wb_err_b0 + 1;
                end
            end
            // mismos estados en BLEND = 1 y 0; mismas lecturas salvo en B4, donde BLEND = 0 tiene su R_ADDR
            // (y hasta que un OUT_START las reinicia tras salir de B4)
            if (u_b1.u_buff_r.IN_RESOLUTION == VIDEO::RESOLUTION_B4) begin b4_mark <= 1; b4_cnt <= 0; end
            else if (b4_mark && u_b1.u_buff_r.OUT_START)          begin b4_mark <= 0; b4_cnt <= 2; end
            else if (b4_cnt > 0)                                  b4_cnt <= b4_cnt - 1;
            if ({u_b1.u_buff_r.out_state, u_b1.u_buff_r.out_state_delay, u_b1.u_buff_r.out_count,
                 u_b1.OUT_EN, u_b1.OUT_START, u_b1.OUT_LINE} !==
                {u_b0.u_buff_r.out_state, u_b0.u_buff_r.out_state_delay, u_b0.u_buff_r.out_count,
                 u_b0.OUT_EN, u_b0.OUT_START, u_b0.OUT_LINE} ||
                (u_b1.u_buff_r.IN_RESOLUTION != VIDEO::RESOLUTION_B4 && !b4_mark && b4_cnt == 0 &&
                 {u_b1.u_buff_r.R_ADDR, u_b1.u_buff_r.R_DATA_P, u_b1.u_buff_r.R_DATA} !==
                 {u_b0.u_buff_r.R_ADDR, u_b0.u_buff_r.R_DATA_P, u_b0.u_buff_r.R_DATA})) begin
                if (wb_err_state < 10) $display("ERROR estado distinto entre BLEND=1 y BLEND=0 t=%0t", $time);
                wb_err_state <= wb_err_state + 1;
            end
            // B4, BLEND = 0: R_ADDR = fila + 0..7, 9..15 de cada grupo de 16 (modelo propio)
            if (b0_addr_valid && u_b0.u_buff_r.IN_RESOLUTION == VIDEO::RESOLUTION_B4 && u_b0.u_buff_r.R_ADDR !== b0_addr) begin
                if (wb_err_b0_addr < 10) $display("ERROR caja blanca BLEND=0 B4 t=%0t R_ADDR %0d esperado %0d", $time, u_b0.u_buff_r.R_ADDR, b0_addr);
                wb_err_b0_addr <= wb_err_b0_addr + 1;
            end
            b0_addr_valid <= (u_b0.u_buff_r.IN_RESOLUTION == VIDEO::RESOLUTION_B4);   // prediccion hecha en B4
            if (u_b0.u_buff_r.OUT_START)
                b0_addr <= 12'(int'(u_b0.u_buff_r.OUT_LINE) * 768);
            else if (u_b0.u_buff_r.OUT_EN && u_b0.u_buff_r.out_count != 10'd720)
                b0_addr <= u_b0.u_buff_r.R_ADDR + ((u_b0.u_buff_r.out_state == 4'h7) ? 12'd2 : 12'd1);
            else
                b0_addr <= u_b0.u_buff_r.R_ADDR;
            // prediccion para el flanco siguiente
            st   = int'(u_b1.u_buff_r.out_state_delay);
            reso = int'(u_b1.u_buff_r.IN_RESOLUTION);
            p_r = u_b1.u_buff_r.R_DATA_P; c_r = u_b1.u_buff_r.R_DATA;
            p_g = u_b1.u_buff_g.R_DATA_P; c_g = u_b1.u_buff_g.R_DATA;
            exp_valid <= 1;
            if (u_b1.u_buff_r.OUT_START) begin
                exp_b1_r <= 0; exp_b0_r <= 0; exp_b1_g <= 0; exp_b0_g <= 0;
            end else if (u_b1.u_buff_r.OUT_EN && u_b1.u_buff_r.out_count != 10'd720) begin
                wtab(reso, st, kind, wc, k);
                if (kind == 0) begin
                    exp_b1_r <= 0; exp_b0_r <= 0; exp_b1_g <= 0; exp_b0_g <= 0;
                end else if (kind == 1) begin
                    exp_b1_r <= u_b1.u_buff_r.OUT; exp_b0_r <= u_b0.u_buff_r.OUT;
                    exp_b1_g <= u_b1.u_buff_g.OUT; exp_b0_g <= u_b0.u_buff_g.OUT;
                    // B4, primer ciclo tras OUT_START: R_ADDR tiene dos drivers (ver la nota)
                    if (reso == 3 && b4_first_step < 0) b4_first_step <= -2;
                end else begin
                    exp_b1_r <= 8'((((1 << k) - wc) * int'(p_r) + wc * int'(c_r)) >> k);
                    exp_b1_g <= 8'((((1 << k) - wc) * int'(p_g) + wc * int'(c_g)) >> k);
                    if (reso == 3) begin    // B4, BLEND = 0: siempre el punto leido (su propio R_DATA)
                        exp_b0_r <= u_b0.u_buff_r.R_DATA;
                        exp_b0_g <= u_b0.u_buff_g.R_DATA;
                    end else begin
                        exp_b0_r <= (2 * wc >= (1 << k)) ? c_r : p_r;
                        exp_b0_g <= (2 * wc >= (1 << k)) ? c_g : p_g;
                    end
                    if (wc != (1 << k) && k != 0) wb_blend_checks <= wb_blend_checks + 1;
                    if (2 * wc < (1 << k)) wb_take_p <= wb_take_p + 1;
                end
            end else begin
                exp_b1_r <= u_b1.u_buff_r.OUT; exp_b0_r <= u_b0.u_buff_r.OUT;
                exp_b1_g <= u_b1.u_buff_g.OUT; exp_b0_g <= u_b0.u_buff_g.OUT;
            end
        end
    end

    // B4: cuanto avanza R_ADDR en el primer ciclo de OUT_EN (estado 0 pide +2; el default del
    // registro OUT pide mantener): se anota lo que hace el simulador
    logic [11:0] b4_addr_at_start;
    logic        b4_watch = 0;
    always @(posedge clk_pix) begin
        if (b4_first_step == -2 && !b4_watch && u_b1.u_buff_r.OUT_EN && u_b1.u_buff_r.out_state_delay == 4'hF) begin
            b4_addr_at_start <= u_b1.u_buff_r.R_ADDR;
            b4_watch <= 1;
        end else if (b4_watch) begin
            b4_first_step <= int'(u_b1.u_buff_r.R_ADDR) - int'(b4_addr_at_start);
            b4_watch <= 0;
        end
    end

    /***************************************************************
     * margen entre la ultima lectura util de una direccion del buffer
     * y su reescritura (u_b1, canal R), por FIELD
     ***************************************************************/
    longint last_rd [0:2303];
    bit     rd_since_wr [0:2303];
    longint min_margin [0:1];
    longint margin_samples = 0;
    initial begin
        for (int i = 0; i < 2304; i++) begin last_rd[i] = 0; rd_since_wr[i] = 0; end
        min_margin[0] = 64'h7FFFFFFFFFFFFFFF; min_margin[1] = 64'h7FFFFFFFFFFFFFFF;
    end
    always @(posedge clk_pix) begin
        if (rst_n && u_b1.u_buff_r.OUT_EN && u_b1.u_buff_r.out_count != 10'd720 && !u_b1.u_buff_r.OUT_START) begin
            last_rd[u_b1.u_buff_r.R_ADDR] = $time;
            rd_since_wr[u_b1.u_buff_r.R_ADDR] = 1;
        end
    end
    always @(posedge dclk) begin
        if (rst_n && u_b1.u_buff_r.W_EN && chk_b1.frames_seen >= 3) begin
            int a; longint m;
            a = int'(u_b1.u_buff_r.W_ADDR);
            if (rd_since_wr[a]) begin
                m = $time - last_rd[a];
                if (m < min_margin[int'(field)]) min_margin[int'(field)] = m;
                margin_samples = margin_samples + 1;
            end
            rd_since_wr[a] = 0;
        end
    end


    // traza de depuracion (+TRACE=1): filas escritas y leidas al principio del cuadro 1
    int trace_arg = 0;
    initial void'($value$plusargs("TRACE=%d", trace_arg));
    always @(posedge dclk) if (trace_arg != 0 && in_frames == 2 && pv < 8 && u_b1.IN_START)
        $display("TRACE t=%0t in: linea %0d -> fila %0d (in_h_cnt %0d)", $time, pv, u_b1.IN_LINE, u_b1.in_h_cnt);
    always @(posedge clk_pix) if (trace_arg != 0 && in_frames == 2 && u_b1.out_v_cnt < 16 && u_b1.OUT_START)
        $display("TRACE t=%0t out: linea %0d lee fila %0d (src pv %0d ph %0d)", $time, u_b1.out_v_cnt, u_b1.OUT_LINE, pv, ph);

    /***************************************************************
     * fin
     ***************************************************************/
    initial begin
        longint limit;
        limit = longint'(frames_arg + 3) * 313 * 6840 * T_BASE;
        if (seq_arg == 1) limit = longint'(30) * 313 * 6840 * T_BASE;
        fork
            begin
                wait (chk_b1.checked_frames >= ((seq_arg == 1) ? 22 : frames_arg));
                @(posedge clk_pix);
            end
            begin
                #(limit);
                $display("ERROR timeout: %0d cuadros comprobados", chk_b1.checked_frames);
            end
        join_any
        report();
        $finish;
    end

    task automatic report();
        int fails;
        fails = err_orig + err_orig_de + err_b0_sync + wb_err_b1 + wb_err_b0 + wb_err_state + wb_err_b0_addr
              + chk_b1.errors + chk_b0.errors
              + ((chk_b1.checked_frames < ((seq_arg == 1) ? 22 : frames_arg)) ? 1 : 0);
        $display("SUMMARY cuadros_entrada=%0d cuadros_comprobados b1=%0d b0=%0d", in_frames, chk_b1.checked_frames, chk_b0.checked_frames);
        $display("SUMMARY orig==b1 (vs,hs,rgb): %0d ciclos, %0d diferencias; DE en cuadros NTSC: %0d ciclos, %0d diferencias; DE distinto en cuadros PAL (esperado): %0d ciclos",
                 cmp_cycles, err_orig, cmp_ntsc_de_cycles, err_orig_de, orig_de_pal_diff);
        $display("SUMMARY b1==b0 (vs,hs,de): %0d diferencias; estado interno distinto: %0d", err_b0_sync, wb_err_state);
        $display("SUMMARY caja blanca: %0d ciclos, %0d en estados de mezcla, %0d con P; errores BLEND=1 %0d, BLEND=0 %0d, R_ADDR de BLEND=0 en B4 %0d",
                 wb_checks, wb_blend_checks, wb_take_p, wb_err_b1, wb_err_b0, wb_err_b0_addr);
        chk_b1.print_stats();
        chk_b0.print_stats();
        if (b4_first_step >= 0) $display("SUMMARY B4: R_ADDR avanza %0d en el primer ciclo de OUT_EN tras OUT_START", b4_first_step);
        $display("SUMMARY margen lectura->reescritura del buffer (ciclos de 27 MHz): FIELD=0 %0d, FIELD=1 %0d (%0d muestras)",
                 (min_margin[0] == 64'h7FFFFFFFFFFFFFFF) ? -1 : min_margin[0] / T_PIX,
                 (min_margin[1] == 64'h7FFFFFFFFFFFFFFF) ? -1 : min_margin[1] / T_PIX, margin_samples);
        if (fails == 0) $display("RESULT PASS");
        else            $display("RESULT FAIL (%0d)", fails);
    endtask
endmodule

/***********************************************************************
 * comprobador de lo que llega al DVI_TX
 ***********************************************************************/
module dvi_check #(
    parameter string NAME  = "",
    parameter bit    IS_B0 = 0
) (
    input wire       clk,
    input wire       en,
    input wire       vs,
    input wire       hs,
    input wire       de,
    input wire [7:0] r,
    input wire [7:0] g,
    input wire [7:0] b,
    input wire [31:0] f_pal,
    input wire [31:0] f_il,
    input wire [31:0] f_field,
    input wire [31:0] f_frame,
    input wire [31:0] f_mode,
    input wire [31:0] pat
);
    int frames_seen = 0;
    int verbose = 0;
    int last_len = 0;
    initial void'($value$plusargs("VERBOSE=%d", verbose));
    int checked_frames = 0;
    int errors = 0;

    // cuadro en curso
    int fr_pal, fr_il, fr_F, fr_id, fr_mode = 0;
    bit fr_mode_changed = 0;
    int realign_lines = 0;
    int n, lines_in_frame, de_lines, first_de_line, last_de_line;
    // linea en curso
    int hpos, de_i, de_hstart, de_hstart_ref = -1;
    int prev_r, run_len, run_start;
    logic pvs = 0, phs = 0, pde = 0;

    // estadisticas
    int ntsc_frames = 0, pal_frames = 0;
    int line_len_err = 0, frame_len_err = 0, de_err = 0, id_err = 0, prop_err = 0;
    int px0_nonzero = 0, px0_count = 0;
    int mid_values = 0;
    int runs [0:8];
    int max_step = 0;
    int line_skips = 0, skips_min = 1 << 30, skips_max = -1;
    int first_lines [$];
    int lmin [0:1] = '{1 << 30, 1 << 30}, lmax [0:1] = '{-1, -1};   // lineas de entrada vistas en DE (FIELD = 0), NTSC/PAL

    initial for (int i = 0; i < 9; i++) runs[i] = 0;

    function automatic logic [7:0] dimv(logic [7:0] v, bit dim);
        return dim ? {1'b0, v[7:1]} : v;
    endfunction

    task automatic err(string what);
        if (errors < 20) $display("ERROR %s: %s (cuadro %0d linea %0d px %0d)", NAME, what, frames_seen, n, de_i);
        errors++;
    endtask

    always @(posedge clk) begin
        if (en) begin
            bit vs_rise, hs_rise, full;
            vs_rise = vs && !pvs;
            hs_rise = hs && !phs;
            full    = (frames_seen >= 3);   // vs 1: reset de BOARD_REV1_TMDS_OUT; vs 2: primer VSYNC de entrada (realinea h): se comprueba desde el 3

            if (hs_rise) begin
                // un cambio de modo en la fuente mueve la rejilla de DCLK: el VSYNC que lo trae pasa el
                // flop de entrada del upscan con el primer periodo de DCLK del modo nuevo (la ultima
                // linea del cuadro que acaba sale con un ciclo de mas o de menos) y el cuadro siguiente
                // empieza fuera de la rejilla vieja (lo mismo al acabar). Se cuenta aparte, no es error,
                // solo en el VSYNC que trae un modo nuevo o al final del primer cuadro del modo nuevo.
                if (full && hpos + 1 != 855) begin
                    if ((fr_mode_changed || f_mode != fr_mode) && vs && !pvs && (hpos + 1 >= 852) && (hpos + 1 <= 858)) realign_lines++;
                    else begin line_len_err++; err($sformatf("linea de %0d ciclos", hpos + 1)); end
                end
                last_len = hpos + 1;
                hpos = 0;
            end else begin
                hpos++;
            end

            if (vs_rise) begin
                if (full) begin
                    int vt, dl, d0;
                    vt = fr_pal ? 626 : 524; dl = fr_pal ? 576 : 480; d0 = fr_pal ? 42 : 35;
                    if (lines_in_frame != vt) begin frame_len_err++; err($sformatf("cuadro de %0d lineas (esperadas %0d)", lines_in_frame, vt)); end
                    if (de_lines != dl || first_de_line != d0 || last_de_line != d0 + dl - 1) begin
                        de_err++; err($sformatf("DE en %0d lineas, de la %0d a la %0d (esperado %0d desde %0d)", de_lines, first_de_line, last_de_line, dl, d0));
                    end
                    if (fr_pal) pal_frames++; else ntsc_frames++;
                    checked_frames++;
                end
                if (verbose && !IS_B0) $display("FRAME %s %0d empieza: modo B%0d PAL %0d IL %0d FIELD %0d; el anterior: %0d lineas, la ultima de %0d ciclos (t=%0t)",
                                                NAME, frames_seen, f_mode, f_pal, f_il, f_field, lines_in_frame, last_len, $time);
                frames_seen++;
                fr_mode_changed = (frames_seen > 1) && (f_mode != fr_mode);
                fr_pal = f_pal; fr_il = f_il; fr_F = f_field; fr_id = f_frame; fr_mode = f_mode;
                n = 0; lines_in_frame = 1; de_lines = 0; first_de_line = -1; last_de_line = -1;
            end else if (hs_rise) begin
                n++; lines_in_frame++;
            end

            if (de && !pde) begin
                de_i = 0;
                line_skips = 0;
                de_hstart = hpos;
                if (full) begin
                    if (de_hstart_ref < 0) de_hstart_ref = de_hstart;
                    else if (de_hstart != de_hstart_ref) begin de_err++; err($sformatf("DE empieza en %0d (antes en %0d)", de_hstart, de_hstart_ref)); end
                end
                if (first_de_line < 0) first_de_line = n;
                last_de_line = n;
                de_lines++;
            end

            if (de && full) begin
                int L;
                bit dim;
                logic [7:0] eb, eg;
                L   = ((n + fr_F) >>> 1) - 2 - fr_F;
                dim = (fr_il != 0) && (((n + fr_F) & 1) != 0);
                eb  = dimv(8'(L), dim);
                if (fr_F == 0) begin
                    if (L < lmin[fr_pal != 0]) lmin[fr_pal != 0] = L;
                    if (L > lmax[fr_pal != 0]) lmax[fr_pal != 0] = L;
                end
                eg  = dimv({1'(L >> 8), 3'(fr_id), 1'(fr_F), 3'b011}, dim);
                if (de_i == 0) begin
                    px0_count++;
                    if ({r, g, b} != 0) px0_nonzero++;
                end
                begin
                    if (b != eb) begin id_err++; err($sformatf("B=%h, esperado linea %0d -> %h", b, L, eb)); end
                    if (pat == 0 && g != eg) begin id_err++; err($sformatf("G=%h, esperado %h (linea %0d, cuadro %0d)", g, eg, L, fr_id)); end
                    if (IS_B0 && pat == 1) begin
                        if (dim ? !(r == 8'h00 || r == 8'h7F) || !(g == 8'h00 || g == 8'h7F)
                                : !(r == 8'h00 || r == 8'hFF) || !(g == 8'h00 || g == 8'hFF)) begin
                            prop_err++; err($sformatf("BLEND=0 con valor mezclado R=%h G=%h", r, g));
                        end
                    end
                    if (!IS_B0 && pat == 1 && !dim && !(r == 8'h00 || r == 8'hFF)) mid_values++;
                    if (IS_B0 && pat == 0 && !dim) begin
                        if (de_i >= 1) begin
                            int step;
                            step = (int'(r) - prev_r + 256) % 256;
                            if (step > max_step) max_step = step;
                            if (step == 0) run_len++;
                            else begin
                                if (run_start > 0) begin  // tramo completo (no el primero de la linea)
                                    int rmin, rmax;
                                    runs[(run_len > 8) ? 8 : run_len]++;
                                    // punto mas cercano: x2,5 -> 2 o 3 veces; x1,875 y x1,25 -> 1 o 2; x0,9375 -> 1
                                    case (fr_mode) 1: begin rmin = 2; rmax = 3; end 4: begin rmin = 1; rmax = 1; end default: begin rmin = 1; rmax = 2; end endcase
                                    if (run_len < rmin || run_len > rmax) begin prop_err++; err($sformatf("BLEND=0: punto repetido %0d veces (B%0d)", run_len, fr_mode)); end
                                end
                                if (step == 2) line_skips++;
                                run_len = 1;
                                run_start = de_i;
                            end
                            if (step > ((fr_mode == 4) ? 2 : 1)) begin prop_err++; err($sformatf("BLEND=0: salto de %0d puntos en la rampa", step)); end
                        end else begin
                            run_len = 1;
                            run_start = 0;
                        end
                        prev_r = int'(r);
                    end
                end
                de_i++;
            end

            if (!de && pde && full) begin
                if (de_i != 720) begin de_err++; err($sformatf("linea con %0d puntos de DE", de_i)); end
                if (IS_B0 && pat == 0 && fr_mode == 4 && !((fr_il != 0) && (((n + fr_F) & 1) != 0))) begin
                    if (line_skips < skips_min) skips_min = line_skips;
                    if (line_skips > skips_max) skips_max = line_skips;
                end
            end

            pvs <= vs; phs <= hs; pde <= de;
        end
    end

    task automatic print_stats();
        $display("SUMMARY %s: %0d cuadros (%0d NTSC 855x524 / %0d PAL 855x626); errores: linea %0d, cuadro %0d, DE %0d, identidad %0d, propiedad %0d; DE desde el ciclo %0d de la linea",
                 NAME, checked_frames, ntsc_frames, pal_frames, line_len_err, frame_len_err, de_err, id_err, prop_err, de_hstart_ref);
        $display("SUMMARY %s: primer punto de DE distinto de 0 en %0d de %0d lineas; lineas realineadas tras un cambio de modo: %0d", NAME, px0_nonzero, px0_count, realign_lines);
        $display("SUMMARY %s: lineas de entrada en DE (FIELD = 0): NTSC %0d-%0d, PAL %0d-%0d", NAME, lmin[0], lmax[0], lmin[1], lmax[1]);
        if (!IS_B0 && pat == 1) $display("SUMMARY %s: %0d puntos intermedios (mezcla) en lineas sin atenuar", NAME, mid_values);
        if (IS_B0 && pat == 0)  $display("SUMMARY %s: rampa: salto maximo %0d; tramos de 1/2/3/4+ puntos: %0d/%0d/%0d/%0d",
                                         NAME, max_step, runs[1], runs[2], runs[3], runs[4]+runs[5]+runs[6]+runs[7]+runs[8]);
        if (IS_B0 && pat == 0 && skips_max >= 0)
                                $display("SUMMARY %s: B4: puntos saltados por linea (saltos de 2 en la rampa): de %0d a %0d", NAME, skips_min, skips_max);
    endtask
endmodule

`default_nettype wire
