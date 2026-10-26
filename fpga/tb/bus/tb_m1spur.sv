// ============================================================================
// tb_m1spur.sv -- banco dirigido: pre-WAIT espurio en el M1 que sigue a un
// ciclo que si lo pide (hallazgo de la revision del hito 5).
//
// SRC = 0: ciclo de E/S a 60h (IN u OUT, alternos); SRC = 1: lectura de
// memoria de nuestra ranura con PREWAIT_MEM_EN = 1. Al acabar, /RD o /WR sube
// en A, /IORQ (o /SLTSL) en A + DIORQ, y el /RD de un M1 de la memoria del
// MSX (con /MREQ y /M1, sin /SLTSL) baja en A + GAP. Se barren GAP (30 a
// 135 ns; con cifras maximas de Z80A el hueco es T - 5 ns: 88 a 10,74 MHz) y
// la fase respecto a los 108 MHz (400 casos por hueco). La placa es la del
// banco grande (74LVC245 multiplexados, 1,5 ns de pad); Bus.WAIT_n queda a 1,
// asi que el pre-WAIT se suelta por K o por RD/WR en reposo.
// Cuenta los pre-WAIT que suben durante el ciclo bueno (tienen que ser todos)
// y durante el M1 (tienen que ser 0). Veredicto M1SPUR_OK / M1SPUR_FAIL.
// Plusargs: +DIORQ=<ns> (0 por defecto), +SEED=<n>.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none
module tb_m1spur;
    parameter int SRC = 0;
    localparam real CLKP = 1000.0 / 108.0;
    reg clk = 1'b0; always #(CLKP / 2.0) clk = ~clk;
    reg rst_n = 1'b0;
    reg cart_clk = 1'b0; always #(1000.0 / 3.579545 / 2.0) cart_clk = ~cart_clk;

    reg [15:0] s_a = 16'h0000;
    reg s_mreq_n = 1'b1, s_iorq_n = 1'b1, s_rd_n = 1'b1, s_wr_n = 1'b1, s_m1_n = 1'b1, s_sltsl_n = 1'b1, s_reset_n = 1'b0;
    // grupo 2: M1, CS12, RFSH, RESET, CS2, CS1, IORQ, MERQ
    wire [7:0] ctl_s = {s_m1_n, 1'b1, 1'b1, s_reset_n, 1'b1, 1'b1, s_iorq_n, s_mreq_n};
    wire [2:0] cs_n;
    wire [7:0] mux_sig;
    wire [7:0] data;
    // multiplexor como en tb_bus.sv: 4 ns de reloj a pad, 6 de habilitacion
    // con basura, 4 de propagacion, 1,5 de pad
    reg [2:0] msel_a = 3'b110, msel_b = 3'b110;
    always @(cs_n)   msel_a <= #4.0 cs_n;
    always @(msel_a) msel_b <= #6.0 msel_a;
    reg [15:0] a_b = 16'h0000;
    reg [7:0]  ctl_b = 8'hFF;
    always @(s_a)   a_b   <= #4.0 s_a;
    always @(ctl_s) ctl_b <= #4.0 ctl_s;
    reg [7:0] mux_val = 8'hFF;
    always @(msel_a or msel_b or a_b or ctl_b) begin
        if (msel_a != msel_b) mux_val = 8'($urandom);
        else case (msel_b)
            3'b110:  mux_val = a_b[15:8];
            3'b101:  mux_val = a_b[7:0];
            3'b011:  mux_val = ctl_b;
            default: mux_val = 8'($urandom);
        endcase
    end
    reg [7:0] mux_pin = 8'hFF;
    always @(mux_val) mux_pin <= #1.5 mux_val;
    assign mux_sig = mux_pin;
    reg rd_p = 1'b1, wr_p = 1'b1, slt_p = 1'b1, ck_p = 1'b0;
    always @(s_rd_n)    rd_p  <= #1.5 s_rd_n;
    always @(s_wr_n)    wr_p  <= #1.5 s_wr_n;
    always @(s_sltsl_n) slt_p <= #1.5 s_sltsl_n;
    always @(cart_clk)  ck_p  <= #1.5 cart_clk;

    wire busdir_n, int_n, wait_n, ddir, wtmo, busok;
    BUS_IF Bus();
    assign Bus.DOUT     = 8'h00;
    assign Bus.BUSDIR_n = 1'b1;
    assign Bus.INT_n    = 1'b1;
    assign Bus.WAIT_n   = 1'b1;
    BOARD_REV1_BUS #(.PREWAIT_MEM_EN(SRC == 1)) u_bus (
        .RESET_n(rst_n), .CLK(clk), .CLK_21M(1'b0), .DRIVE_EN(1'b1), .BOOT_HOLD(1'b0),
        .WAIT_TIMEOUT(wtmo), .BUS_OK(busok), .CART_BUSDIR_n(busdir_n), .CART_INT_n(int_n), .CART_WAIT_n(wait_n),
        .CART_SLTSL_n(slt_p), .CART_RD_n(rd_p), .CART_WR_n(wr_p), .CART_CLOCK(ck_p), .CART_MUX_SIG(mux_sig),
        .CART_MUX_CS_n(cs_n), .CART_DATA_SIG(data), .CART_DATA_DIR(ddir), .Bus(Bus));

    int  in_m1 = 0, spur = 0, tot = 0, good_fire = 0;
    reg  pw_q = 1'b0;
    bit  fired = 1'b0;
    always @(posedge clk) begin
        pw_q <= u_bus.pw_hold;
        if (u_bus.pw_hold && !pw_q) begin
            if (in_m1) spur++;
            else if (!fired) begin fired = 1'b1; good_fire++; end
        end
    end

    real GAPS [0:5];
    int  hist [0:5];
    real DIORQ;
    initial begin
        int wr, s0, seed, fail;
        if (!$value$plusargs("DIORQ=%f", DIORQ)) DIORQ = 0.0;
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        void'($urandom(seed));
        GAPS[0] = 30.0; GAPS[1] = 50.0; GAPS[2] = 70.0; GAPS[3] = 88.0; GAPS[4] = 110.0; GAPS[5] = 135.0;
        #50 rst_n = 1'b1;
        #2000 s_reset_n = 1'b1;
        wait (u_bus.bus_ok);
        for (int g = 0; g < 6; g++) begin
            s0 = spur;
            for (int k = 0; k < 400; k++) begin
                wr = (SRC == 0) ? k % 2 : 0;
                #(500.0 + ($urandom % 1000) / 10.0);
                fired = 1'b0;
                if (SRC == 0) begin                      // E/S a 60h
                    s_a = {8'($urandom), 8'h60};
                    #100.0; s_iorq_n = 1'b0; #5.0;
                    if (wr) s_wr_n = 1'b0; else s_rd_n = 1'b0;
                end
                else begin                               // lectura de nuestra ranura
                    s_a = 16'h4000 + (16'($urandom) & 16'h7FFF);
                    #100.0; s_mreq_n = 1'b0; #5.0; s_rd_n = 1'b0;
                    fork begin #10.0; s_sltsl_n = 1'b0; end join_none
                end
                tot++;
                #250.0;
                if (wr) s_wr_n = 1'b1; else s_rd_n = 1'b1;
                if (SRC == 0) fork begin #(DIORQ); s_iorq_n = 1'b1; end join_none
                else begin
                    s_mreq_n = 1'b1;
                    fork begin #(DIORQ + 10.0); s_sltsl_n = 1'b1; end join_none
                end
                #(GAPS[g] / 2.0); s_a = 16'($urandom);  // direccion del M1 (memoria del MSX)
                #(GAPS[g] / 2.0 - 5.0); s_mreq_n = 1'b0; s_m1_n = 1'b0; #5.0;
                in_m1 = 1; s_rd_n = 1'b0;
                #200.0; s_rd_n = 1'b1; s_mreq_n = 1'b1; s_m1_n = 1'b1;
                #200.0; in_m1 = 0;
            end
            hist[g] = spur - s0;
        end
        fail = (spur != 0) || (good_fire != tot);
        if (SRC == 0) $display("SRC=0 (E/S a 60h) DIORQ=%0.1f ns: ciclos buenos con pre-WAIT %0d de %0d", DIORQ, good_fire, tot);
        else          $display("SRC=1 (lectura de nuestra ranura, PREWAIT_MEM_EN) DIORQ=%0.1f ns: ciclos buenos con pre-WAIT %0d de %0d", DIORQ, good_fire, tot);
        for (int g = 0; g < 6; g++)
            $display("  hueco /RD-/WR arriba -> /RD del M1 = %3.0f ns: pre-WAIT espurio en el M1 en %0d de 400", GAPS[g], hist[g]);
        $display("%s", fail ? "M1SPUR_FAIL" : "M1SPUR_OK");
        $finish;
    end
    initial begin #50.0e6; $display("TB_TIMEOUT"); $finish; end
endmodule
`default_nettype wire
