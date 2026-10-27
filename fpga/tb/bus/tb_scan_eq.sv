// ============================================================================
// tb_scan_eq.sv -- equivalencia ciclo a ciclo de BOARD_REV1_BUS (hito 5) con el
// de main (hito 1, el que funciona en placa) donde el hito 5 no cambia nada a
// proposito.
//
// Dos DUT con el mismo estimulo al azar en los pines del slot y en el lado del
// cartucho de su BUS_IF: el BOARD_REV1_BUS de este arbol y el de main
// (renombrado a BOARD_REV1_BUS_MAIN por run_eq.sh). Cada flanco de CLK compara
// CART_MUX_CS_n y todas las salidas de Bus (ADDR, DIN, RD_n, WR_n, IORQ_n,
// MERQ_n, SLTSL_n, M1_n, RFSH_n, CS1_n, CS2_n, CS12_n, RESET_n, CLK, CLK_EN,
// CLK_EN_21M) y, con BUS_OK a 1, los pines CART_WAIT_n, CART_INT_n,
// CART_DATA_DIR, CART_BUSDIR_n y el dato que se saca por CART_DATA_SIG.
//
//   MODE = 0: el nuevo con ADAPTIVE_SCAN = PREWAIT_IO_EN = ADDR_HOLD =
//             DRIVE_TAIL_GUARD = 0 (la vuelta atras de la nota) y /RD, /WR al
//             azar: tiene que ser el de main salvo las guardias de salida.
//   MODE = 1: el nuevo con los valores del hito y /RD, /WR quietos a 1 (sin
//             saltos ni ciclos): el escaner tiene que ser el de tnCart.
//   MODE = 2: control: los valores del hito con /RD y /WR al azar; tiene que
//             salir distinto (si no, la comparacion no ve nada).
//
// Plusargs: +SEED=<n> +MS=<ms simulados>. Salida: EQ_OK / EQ_FAIL.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_scan_eq;
    parameter int MODE = 0;
    localparam real CLKP = 1000.0 / 108.0;

    reg clk = 1'b0;
    always #(CLKP / 2.0) clk = ~clk;
    reg clk21 = 1'b0;
    always #(1000.0 / 21.6 / 2.0) clk21 = ~clk21;
    reg rst_n = 1'b0;

    // pines del slot (lado MSX), comunes a los dos DUT
    reg  [7:0] mux_sig  = 8'hFF;
    reg        rd_n     = 1'b1;
    reg        wr_n     = 1'b1;
    reg        sltsl_n  = 1'b1;
    reg        slot_clk = 1'b0;
    reg  [7:0] msx_d    = 8'hFF;        // lo que pone el MSX en D0-D7 cuando la placa no conduce

    // lado del cartucho de los BUS_IF, comun a los dos DUT
    reg  [7:0] c_dout     = 8'h00;
    reg        c_busdir_n = 1'b1;
    reg        c_int_n    = 1'b1;
    reg        c_wait_n   = 1'b1;

    BUS_IF bus_n();     // nuevo
    BUS_IF bus_m();     // main
    assign bus_n.DOUT = c_dout;  assign bus_n.BUSDIR_n = c_busdir_n;  assign bus_n.INT_n = c_int_n;  assign bus_n.WAIT_n = c_wait_n;
    assign bus_m.DOUT = c_dout;  assign bus_m.BUSDIR_n = c_busdir_n;  assign bus_m.INT_n = c_int_n;  assign bus_m.WAIT_n = c_wait_n;

    wire [2:0] cs_n_n, cs_n_m;
    wire       busdir_n_n, busdir_n_m, int_n_n, int_n_m, wait_n_n, wait_n_m, dir_n, dir_m;
    wire [7:0] data_n, data_m;
    assign data_n = dir_n ? msx_d : 8'bzzzz_zzzz;
    assign data_m = dir_m ? msx_d : 8'bzzzz_zzzz;
    wire       bus_ok, wait_timeout;

    BOARD_REV1_BUS #(
        .ADAPTIVE_SCAN    (MODE == 0 ? 0 : 1),
        .PREWAIT_IO_EN    (MODE == 0 ? 0 : 1),
        .ADDR_HOLD        (MODE == 0 ? 0 : 1),
        .DRIVE_TAIL_GUARD (MODE == 0 ? 0 : 1)
    ) u_new (
        .RESET_n        (rst_n),
        .CLK            (clk),
        .CLK_21M        (clk21),
        .DRIVE_EN       (1'b1),
        .BOOT_HOLD      (1'b0),
        .WAIT_TIMEOUT   (wait_timeout),
        .BUS_OK         (bus_ok),
        .CART_BUSDIR_n  (busdir_n_n),
        .CART_INT_n     (int_n_n),
        .CART_WAIT_n    (wait_n_n),
        .CART_SLTSL_n   (sltsl_n),
        .CART_RD_n      (rd_n),
        .CART_WR_n      (wr_n),
        .CART_CLOCK     (slot_clk),
        .CART_MUX_SIG   (mux_sig),
        .CART_MUX_CS_n  (cs_n_n),
        .CART_DATA_SIG  (data_n),
        .CART_DATA_DIR  (dir_n),
        .Bus            (bus_n)
    );

    BOARD_REV1_BUS_MAIN u_main (
        .RESET_n        (rst_n),
        .CLK            (clk),
        .CLK_21M        (clk21),
        .CART_BUSDIR_n  (busdir_n_m),
        .CART_INT_n     (int_n_m),
        .CART_WAIT_n    (wait_n_m),
        .CART_SLTSL_n   (sltsl_n),
        .CART_RD_n      (rd_n),
        .CART_WR_n      (wr_n),
        .CART_CLOCK     (slot_clk),
        .CART_MUX_SIG   (mux_sig),
        .CART_MUX_CS_n  (cs_n_m),
        .CART_DATA_SIG  (data_m),
        .CART_DATA_DIR  (dir_m),
        .Bus            (bus_m)
    );

    // estimulo: cambia en la bajada de CLK (lejos del flanco de muestreo)
    int seed = 1, ms = 6;
    int wait_run = 0;
    int cyc = 0;
    always @(negedge clk) begin
        cyc <= cyc + 1;
        // el bit 4 del g2 es /RESET del slot: suelto salvo algun pulso, para
        // que BUS_OK pase casi todo el tiempo a 1 (con el CS del nuevo: si los
        // dos CS difieren ya lo cuenta la comparacion)
        if ($urandom % 3 == 0)  mux_sig  <= 8'($urandom) | ((cs_n_n == 3'b011 && $urandom % 4096 != 0) ? 8'h10 : 8'h00);
        else if (cs_n_n == 3'b011 && !mux_sig[4] && $urandom % 64 != 0) mux_sig[4] <= 1'b1;
        if ($urandom % 61 == 0) sltsl_n  <= ~sltsl_n;
        if (cyc % 15 == 0)      slot_clk <= ~slot_clk;           // ~3,6 MHz: bus_ok sube
        if (MODE != 1) begin
            if ($urandom % 7 == 0)  rd_n <= ($urandom % 3 != 0);   // pulsos de 1 a varios ciclos
            if ($urandom % 7 == 0)  wr_n <= ($urandom % 3 != 0);
        end
        if ($urandom % 5 == 0)  msx_d      <= 8'($urandom);
        if ($urandom % 5 == 0)  c_dout     <= 8'($urandom);
        if ($urandom % 9 == 0)  c_busdir_n <= ($urandom % 2);
        if ($urandom % 97 == 0) c_int_n    <= ~c_int_n;
        // WAIT_n de la cadena: rafagas cortas (lejos del timeout de 2^12)
        if (!c_wait_n) begin
            wait_run <= wait_run + 1;
            if (wait_run > 200 || $urandom % 50 == 0) begin c_wait_n <= 1'b1; wait_run <= 0; end
        end
        else if ($urandom % 40 == 0) c_wait_n <= 1'b0;
    end

    // comparacion en cada flanco (un poco despues, con todo asentado)
    int n_cmp = 0, n_pin = 0, n_bad_bus = 0, n_bad_pin = 0;
    reg [7:0] pn_q = 8'hFF, pm_q = 8'hFF, din_sync = 8'h00;
    always @(posedge clk) begin
        for (int i = 0; i < 8; i++) begin
            if (data_n[i] !== data_m[i])                            din_sync[i] <= 1'b0;
            else if (data_n[i] === pn_q[i] && data_m[i] === pm_q[i]) din_sync[i] <= 1'b1;
        end
        pn_q <= data_n;
        pm_q <= data_m;
    end
    task automatic chk(input string name, input logic [15:0] a, input logic [15:0] b, input bit pin);
        if (a !== b) begin
            if (pin) n_bad_pin++; else n_bad_bus++;
            if (n_bad_pin + n_bad_bus <= 10) $display("  [DIFIERE %0t] %s: nuevo %h, main %h", $time, name, a, b);
        end
    endtask
    always @(posedge clk) if (rst_n) begin
        #(CLKP / 4.0);
        n_cmp++;
        chk("CART_MUX_CS_n", cs_n_n, cs_n_m, 0);
        chk("Bus.ADDR",    bus_n.ADDR,    bus_m.ADDR, 0);
        // DIN sale del propio pin de datos: cuando uno conduce y el otro no
        // (las guardias de salida, con BUS_OK a 0) cada uno ve su dato y su
        // PIN_FILTER guarda otra historia; cada bit se compara desde que los
        // dos pines han dado la misma pareja de muestras iguales (din_sync)
        chk("Bus.DIN", bus_n.DIN & din_sync, bus_m.DIN & din_sync, 0);
        chk("Bus.RD_n",    bus_n.RD_n,    bus_m.RD_n, 0);
        chk("Bus.WR_n",    bus_n.WR_n,    bus_m.WR_n, 0);
        chk("Bus.IORQ_n",  bus_n.IORQ_n,  bus_m.IORQ_n, 0);
        chk("Bus.MERQ_n",  bus_n.MERQ_n,  bus_m.MERQ_n, 0);
        chk("Bus.SLTSL_n", bus_n.SLTSL_n, bus_m.SLTSL_n, 0);
        chk("Bus.M1_n",    bus_n.M1_n,    bus_m.M1_n, 0);
        chk("Bus.RFSH_n",  bus_n.RFSH_n,  bus_m.RFSH_n, 0);
        chk("Bus.CS1_n",   bus_n.CS1_n,   bus_m.CS1_n, 0);
        chk("Bus.CS2_n",   bus_n.CS2_n,   bus_m.CS2_n, 0);
        chk("Bus.CS12_n",  bus_n.CS12_n,  bus_m.CS12_n, 0);
        chk("Bus.RESET_n", bus_n.RESET_n, bus_m.RESET_n, 0);
        chk("Bus.CLK",     bus_n.CLK,     bus_m.CLK, 0);
        chk("Bus.CLK_EN",  bus_n.CLK_EN,  bus_m.CLK_EN, 0);
        chk("Bus.CLK_EN_21M", bus_n.CLK_EN_21M, bus_m.CLK_EN_21M, 0);
        if (bus_ok) begin
            n_pin++;
            chk("CART_WAIT_n",   wait_n_n,   wait_n_m, 1);
            chk("CART_INT_n",    int_n_n,    int_n_m, 1);
            chk("CART_DATA_DIR", dir_n,      dir_m, 1);
            chk("CART_BUSDIR_n", busdir_n_n, busdir_n_m, 1);
            if (!dir_n) chk("CART_DATA_SIG", data_n, data_m, 1);
        end
    end

    int n_dir0 = 0, n_wait1 = 0;
    always @(posedge clk) if (rst_n && bus_ok) begin
        if (!dir_n)   n_dir0++;
        if (wait_n_n) n_wait1++;
    end

    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("MS=%d", ms)) ms = 6;
        void'($urandom(seed));
        $display("== tb_scan_eq: MODE=%0d (%s) SEED=%0d, %0d ms", MODE,
                 MODE == 0 ? "ADAPTIVE_SCAN = PREWAIT_IO_EN = ADDR_HOLD = DRIVE_TAIL_GUARD = 0, /RD y /WR al azar"
                 : MODE == 1 ? "valores del hito, /RD y /WR quietos"
                             : "control: valores del hito, /RD y /WR al azar (tiene que salir distinto)", seed, ms);
        #100.0 rst_n = 1'b1;
        #(ms * 1.0e6);
        $display("   %0d ciclos comparados (%0d con BUS_OK a 1: %0d conduciendo D0-D7, %0d con /WAIT)", n_cmp, n_pin, n_dir0, n_wait1);
        $display("   diferencias: Bus y CART_MUX_CS_n %0d, pines con BUS_OK %0d; WAIT_TIMEOUT = %b", n_bad_bus, n_bad_pin, wait_timeout);
        if (n_bad_bus == 0 && n_bad_pin == 0 && n_pin > 0 && !wait_timeout) $display("EQ_OK");
        else $display("EQ_FAIL");
        $finish;
    end
endmodule
`default_nettype wire
