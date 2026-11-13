// tb_t9990_vscroll.sv -- reinicio del scroll vertical a mitad de pantalla, con los enables y la VRAM
// de la WonderTANG (UMA real de tnCart a DIV = 30 + modelo de sdram.sv, tb_vram_uma.sv). Derivado
// de tb_t9990_vscroll.sv del MSXimus Z (mismo autor): se sustituyen el generador de enables de la
// Zynq y su RAM ideal por TB_VRAM_UMA y se quita +STALLP (parada de la cache AXI de la Zynq).
// Escribe R#17 (o R#21) en una linea y posicion dadas con la pantalla encendida, como el split de
// Xybots-V9990 (R#18 = 3, R#17 = 95/212 en la linea 95, R#17 = 0 en el VI), y apunta que linea de la
// VRAM pide el core en cada linea de pantalla. Lo compara con openMSX (V9990PixelRenderer::
// updateScrollAYLow: verticalOffsetA = linea actual): antes de la linea de la escritura, 768+L; en esa
// linea, lo viejo hasta el punto de escritura y 768+V desde ahi; despues, 768+V+(L-linea).
// Pasa con VSCROLL_OK.
// Plusargs: +WLINE=<linea> +WH=<h_cnt> +FRAMES=n +R18AT=<linea> (R#18=4 ahi y 3 en el VI)
//           +R6=<dec> (130 = 82h B1 8 bpp) +R7=<dec> (8 = PAL) +VAL0/+VAL1 (R#17 en cuadros pares/impares)
//           +PLANE=3 bitmap | 4 plano A de P1 | 5 plano B de P1 (R#21)  +NOVI=1 (sin R#17=0 en el VI;
//           el modelo de arriba no lo contempla y da 96 lineas distintas, como debe)
// Solo Verilator. V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
`timescale 1ns/1ps
module tb_t9990_vscroll;
    reg clk = 0; always #4.63 clk = ~clk;
    reg rst_n = 0;

    reg csr_n = 1, csw_n = 1; reg [3:0] mode = 0; reg [7:0] cd_in = 0;
    wire [7:0] cd_out; wire wait_n, int0_n, int1_n, dreq_n, vmreq_n;
    wire ram_oe_n, ram_we_n, ram_rfsh_n; wire [18:0] ram_addr; wire [31:0] ram_din; wire [2:0] ram_din_size;
    wire [31:0] ram_dout; wire ram_ack_n, ram_req;
    wire clk21_en, clk14_en, clk25_en;
    wire hs, vs, dclk_en, il, eo, ys, hscn, pal; wire [4:0] r, g, b; wire [2:0] reso;

    TB_VRAM_UMA u_vram (
        .RESET_n(rst_n), .CLK(clk), .CH0_LOAD(1'b0), .ACK_DELAY(0),
        .CLK21M_EN(clk21_en), .CLK14M_EN(clk14_en), .CLK25M_EN(clk25_en),
        .RAM_REQ(ram_req), .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size),
        .RAM_DOUT(ram_dout), .RAM_ACK_n(ram_ack_n));

    T9990 dut (
        .RESET_n(rst_n), .CLK(clk),
        .CLK_21M_EN(clk21_en), .CLK_14M_EN(clk14_en), .CLK_25M_EN(clk25_en),
        .CSR_n(csr_n), .CSW_n(csw_n), .MODE(mode), .CD_IN(cd_in), .CD_OUT(cd_out),
        .WAIT_n(wait_n), .INT0_n(int0_n), .INT1_n(int1_n), .DREQ_n(dreq_n), .VMREQ_n(vmreq_n),
        .RAM_REQ(ram_req), .RAM_ACK_n(ram_ack_n),
        .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size), .RAM_DOUT(ram_dout),
        .HS(hs), .VS(vs), .R(r), .G(g), .B(b), .Ys(ys), .DCLK_EN(dclk_en),
        .RESO(reso), .HSCN(hscn), .IL(il), .EO(eo), .PAL(pal));

    // lectura de VRAM del core: flanco de bajada de RAM_OE_n (el modelo de VRAM contesta con el ACK)
    reg oe_q = 1;
    always @(posedge clk) oe_q <= ram_oe_n;
    wire det_rd = oe_q && !ram_oe_n;

    // CPU port
    task wr_port(input [3:0] p, input [7:0] d);
        begin
            @(posedge clk); mode <= p; cd_in <= d; csw_n <= 1'b0;
            repeat (3) @(posedge clk);
            while (!wait_n) @(posedge clk);
            csw_n <= 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask
    task wr_reg(input [5:0] n, input [7:0] d);
        begin wr_port(4'd4, {2'b00, n}); wr_port(4'd3, d); end
    endtask

    // write log (seen by the port: det_w on P#3)
    integer frame = 0;
    always @(posedge clk) if (dut.u_port.det_w && mode == 4'h3)
        $display("  [f%0d] P#3 write R#%0d=%0d at disp_line=%0d h_cnt=%0d VR=%0d HR=%0d BG_Y=%0d",
                 frame, dut.u_port.port4_regnum[5:0], cd_in, dut.u_tg.disp_line, dut.u_tg.h_cnt,
                 dut.STATUS.VR, dut.STATUS.HR, dut.BG_Y);

    // BP fetch monitor: per display line (raster disp_line) first/last fetched VRAM line and h_cnt
    integer fy_first [0:511], fy_last [0:511], fh_first [0:511], fh_last [0:511], fn [0:511], fbg [0:511];
    integer ftr_h [0:511], ftr_y [0:511];   // first fetch whose Y differs from the line's first Y
    integer k, L, Y, H;
    // (h_cnt >= 25: skips the stale fetches of display line 0 issued before tbl_init, see report; was 24 until
    //  28/10/2026, when COLOR_DECODE_DELAY went from 5 to 4 and the bitmap start moved one dot later)
    integer junk = 0;
    always @(posedge clk) if (det_rd && dut.u_ram.timing_state == 3'd3 && dut.u_tg.h_cnt < 25) junk = junk + 1;
    integer plane = 3, wreg = 17, ybase = 768, ymask = 'h1FFF, ny = 0;
    always @(posedge clk) if (det_rd && dut.u_ram.timing_state == plane[2:0] && plane != 3 && ram_addr[18:14] == ((plane == 5) ? 5'b11111 : 5'b11110)) ny = ram_addr[13:8];
    always @(posedge clk) if (det_rd && dut.u_ram.timing_state == plane[2:0] && dut.u_tg.h_cnt >= 25
                              && !(plane != 3 && ram_addr[18:14] == ((plane == 5) ? 5'b11111 : 5'b11110))) begin
        L = dut.u_tg.disp_line; H = dut.u_tg.h_cnt;
        if (plane != 3) Y = ny * 8 + ram_addr[10:8];        // P1: name fetch gives Y[8:3], pattern fetch Y[2:0]
        else Y = (dut.REG.CLRM == 2'b10 && dut.REG.XIMM == 2'b00) ? ram_addr[18:8] : ram_addr[18:9];
        if (L >= 0 && L < 512) begin
            if (fn[L] == 0) begin fy_first[L] = Y; fh_first[L] = H; fbg[L] = dut.BG_Y; ftr_h[L] = -1; ftr_y[L] = -1; end
            else if (Y != fy_first[L] && ftr_h[L] < 0) begin ftr_h[L] = H; ftr_y[L] = Y; end
            fy_last[L] = Y; fh_last[L] = H; fn[L] = fn[L] + 1;
        end
    end
    task clear_lines; begin for (k = 0; k < 512; k = k + 1) fn[k] = 0; end endtask

    // expected (openMSX semantics, Xybots split): R#18=3, R#17=0 at frame start; R#17=V written at
    // (WLINE, WH) while the display is on -> line L < WLINE: 768+L; line WLINE: 768+WLINE before the
    // write point, 768+V after it; lines > WLINE: 768+V+(L-WLINE).
    integer wline = 95, wh = 90, nframes = 4, novi = 0, r18at = -1, r6 = 130, r7 = 0, val0 = 95, val1 = 212;
    integer V, bad, badl, nlines, r18v, show = -10, badtot = 0;
    task check_frame(input integer v);
        integer exp_first, exp_last;
        begin
            bad = 0; nlines = 0;
            for (L = 0; L < 212; L = L + 1) if (fn[L] > 0) begin
                nlines = nlines + 1;
                if (L < wline) begin exp_first = ybase + L; exp_last = ybase + L; end
                else if (L == wline) begin
                    exp_first = (wh < 25) ? ybase + v : ybase + L;        // write before the line's first fetch
                    exp_last  = (wh > 300) ? ybase + L : ybase + v;       // write after the line's last fetch
                end
                else begin exp_first = ybase + v + (L - wline); exp_last = exp_first; end
                exp_first = exp_first & ymask; exp_last = exp_last & ymask;
                if (fy_first[L] != exp_first || fy_last[L] != exp_last) begin
                    bad = bad + 1;
                    if (bad <= 4) $display("    MISMATCH line %0d: fetched %0d..%0d, expected (openMSX) %0d..%0d", L, fy_first[L], fy_last[L], exp_first, exp_last);
                end
            end
        end
    endtask

    integer wd;
    initial begin
        if ($value$plusargs("WLINE=%d", wline)) ; if ($value$plusargs("WH=%d", wh)) ;
        if ($value$plusargs("FRAMES=%d", nframes)) ; if ($value$plusargs("NOVI=%d", novi)) ;
        if ($value$plusargs("R18AT=%d", r18at)) ;
        if ($value$plusargs("R6=%d", r6)) ; if ($value$plusargs("R7=%d", r7)) ;
        if ($value$plusargs("VAL0=%d", val0)) ; if ($value$plusargs("VAL1=%d", val1)) ;
        if ($value$plusargs("PLANE=%d", plane)) ;           // 3 = bitmap, 4 = P1 plane A, 5 = P1 plane B
        if (plane == 4) begin ybase = 768; ymask = 'h1FF; end
        if (plane == 5) begin wreg = 21; ybase = 0; ymask = 'h1FF; end
        $display("tb_vscroll: R#6=%02h R#7=%02h WLINE=%0d WH=%0d frames=%0d r18at=%0d", r6, r7, wline, wh, nframes, r18at);
        repeat (8) @(posedge clk); rst_n <= 1; repeat (40) @(posedge clk);
        wr_reg(6'd6, r6[7:0]);
        wr_reg(6'd7, r7[7:0]);
        wr_reg(6'd17, 8'd0);
        if (!$value$plusargs("R18V=%d", r18v)) r18v = 3;
        if ($value$plusargs("SHOW=%d", show)) ;
        wr_reg(6'd18, r18v[7:0]);    // default 3: VR_HUD at 768, no roll (Xybots hk_runtime.asm)
        wr_reg(6'd8, 8'hC0);         // DISP on, cursors off
        wd = 0; while (!dut.u_clk.TG_EN && wd < 100000) begin @(posedge clk); wd = wd + 1; end
        // align to a frame start (v_cnt = 0)
        while (!(dut.u_tg.v_cnt == 0 && dut.u_tg.h_cnt == 0)) @(posedge clk);
        while (dut.u_tg.v_cnt == 0) @(posedge clk);
        for (frame = 0; frame < nframes; frame = frame + 1) begin
            V = (frame & 1) ? val1 : val0;
            clear_lines;
            // wait for display line 0
            while (!(dut.u_tg.disp_line == 0 && !dut.STATUS.VR)) @(posedge clk);
            if (r18at >= 0) begin
                while (!(dut.u_tg.disp_line == r18at && dut.u_tg.h_cnt == 100)) @(posedge clk);
                wr_reg(6'd18, 8'd4);       // high byte change in mid-frame
            end
            // select R#17 one line before, then the data write exactly at (WLINE, WH)
            while (!(dut.u_tg.disp_line == wline - 1 && dut.u_tg.h_cnt == 200)) @(posedge clk);
            wr_port(4'd4, wreg[7:0]);
            while (!(dut.u_tg.disp_line == wline && dut.u_tg.h_cnt == wh)) @(posedge clk);
            wr_port(4'd3, V[7:0]);
            // end of the display area (VI): R#17 = 0 as the Xybots VI handler does
            while (!dut.STATUS.VR) @(posedge clk);
            if (!novi) wr_reg(wreg[5:0], 8'd0);
            if (r18at >= 0) wr_reg(6'd18, 8'd3);
            // report
            $display("frame %0d (R#17=%0d at line %0d h_cnt %0d):", frame, V, wline, wh);
            for (L = 0; L < 212; L = L + 1)
                if (L <= 1 || (L >= wline - 2 && L <= wline + 2) || L == 191 || L == 211 || (r18at >= 0 && L >= r18at - 1 && L <= r18at + 1) || (L >= show - 1 && L <= show + 1))
                    $display("  line %3d: n=%0d BG_Y@first=%0d fetch h_cnt %0d..%0d  Y %0d..%0d%s", L, fn[L], fbg[L], fh_first[L], fh_last[L], fy_first[L], fy_last[L],
                             (ftr_h[L] >= 0) ? $sformatf("  (Y changes to %0d at h_cnt %0d)", ftr_y[L], ftr_h[L]) : "");
            check_frame(V);
            $display("  CHECK frame %0d: %0d of %0d lines differ from the openMSX expectation", frame, bad, nlines);
            badtot = badtot + bad + ((nlines == 212) ? 0 : 1);
            while (dut.STATUS.VR) @(posedge clk);  // next frame display start
            frame = frame;   // (loop increments)
            // (we already are at display line 0 of the next frame)
        end
        $display("junk BP fetches before tbl_init (h_cnt<24): %0d", junk);
        if (badtot == 0) $display("VSCROLL_OK"); else $display("VSCROLL_FAIL (%0d)", badtot);
        $display("TB_DONE");
        $finish;
    end
    initial begin #4000000000; #4000000000; $display("TB_TIMEOUT"); $finish; end
endmodule
