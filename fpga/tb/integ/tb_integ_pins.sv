//
// tb_integ_pins.sv -- V9990TANG: polaridad de los pines del slot con las
// guardias de lock (DRIVE_EN, BOOT_HOLD) dentro de BOARD_REV1_BUS.
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Desde la fusion de las areas (hito/fusion) el gateo ya no lo hace
// BOARD_WT200B_BUS_GUARD delante del BOARD_REV1_BUS de main sino el propio
// BOARD_REV1_BUS de hito/bus, que ademas exige BUS_OK (reloj del slot vivo y
// /RESET del slot suelto) y corta un /WAIT de mas de 2^WAIT_TMO_BITS ciclos
// (WAIT_TIMEOUT). Modulo real: BOARD_REV1_BUS (con CONFIG_BOARD de la wt200b
// en xtal y CONFIG de config/v9990.sv), con sus parametros por defecto, como
// en el top. El banco hace de cartucho (Bus.DOUT/BUSDIR_n/INT_n/WAIT_n) y de
// MSX (/RD, CLOCK, /RESET por el mux y el bus de datos) y recorre todas las
// combinaciones de DRIVE_EN, BOOT_HOLD, WAIT_n, INT_n, BUSDIR_n y /RD:
//   fase A, sin reloj del slot (BUS_OK = 0): solo sale BOOT_HOLD
//   fase B, con reloj del slot (BUS_OK = 1):
//     CART_WAIT_n   = BOOT_HOLD || (DRIVE_EN && !WAIT_n)  (1 = /WAIT bajo en el slot)
//     CART_INT_n    = DRIVE_EN && !INT_n                  (2.00b: 1 = /INT bajo)
//     CART_DATA_DIR = CART_BUSDIR_n = !(DRIVE_EN && !/RD && !BUSDIR_n)
//     CART_DATA_SIG = DOUT cuando el FPGA conduce; si no, lo que ponga el MSX
//     (cada caso parte de reposo, /RD y BUSDIR_n a 1, para armar la guardia
//     de cola del bus de datos; baja /RD, 3 ciclos despues pone el resto y
//     se mira 3 ciclos despues)
//   fase C, /RESET del slot pulsado (BUS_OK = 0): otra vez solo BOOT_HOLD
//   fase D, timeout: un /WAIT logico pedido mas de 2^12 ciclos se suelta y
//     deja WAIT_TIMEOUT pegajoso; con BOOT_HOLD no cuenta
// (Verilator es de dos estados: la alta impedancia se comprueba viendo que el
// valor del MSX llega sin conflicto, no con 'z').
//
// Uso: tb/integ/run.sh (Verilator 5.020).
//

`timescale 1ns/1ps
`default_nettype none

module tb_integ_pins;
    logic clk = 1'b0;
    always #4.63 clk = ~clk;            // 108 MHz
    logic reset_n = 1'b0;

    // pines
    wire        cart_busdir_n, cart_int_n, cart_wait_n, cart_data_dir;
    wire [2:0]  cart_mux_cs_n;
    logic       cart_rd_n = 1'b1;
    wire  [7:0] cart_data;
    logic       msx_drive = 1'b0;
    logic [7:0] msx_data  = 8'h00;
    assign cart_data = msx_drive ? msx_data : 8'bzzzz_zzzz;

    // reloj del slot (3,58 MHz) y /RESET del slot (bit 4 del grupo 2 del mux)
    logic slot_run = 1'b0;
    logic slot_clk = 1'b0;
    always begin
        #139.68;
        if(slot_run) slot_clk = ~slot_clk;
    end
    logic slot_reset_n = 1'b1;
    wire [7:0] mux_sig = slot_reset_n ? 8'hFF : 8'hEF;

    // guardias
    logic drive_en = 1'b0, boot_hold = 1'b0;
    wire  wait_timeout, bus_ok;

    BUS_IF Bus();

    BOARD_REV1_BUS u_bus (
        .RESET_n        (reset_n),
        .CLK            (clk),
        .CLK_21M        (1'b0),
        .DRIVE_EN       (drive_en),
        .BOOT_HOLD      (boot_hold),
        .WAIT_TIMEOUT   (wait_timeout),
        .BUS_OK         (bus_ok),
        .CART_BUSDIR_n  (cart_busdir_n),
        .CART_INT_n     (cart_int_n),
        .CART_WAIT_n    (cart_wait_n),
        .CART_SLTSL_n   (1'b1),
        .CART_RD_n      (cart_rd_n),
        .CART_WR_n      (1'b1),
        .CART_CLOCK     (slot_clk),
        .CART_MUX_SIG   (mux_sig),
        .CART_MUX_CS_n  (cart_mux_cs_n),
        .CART_DATA_SIG  (cart_data),
        .CART_DATA_DIR  (cart_data_dir),
        .Bus            (Bus)
    );

    // el cartucho
    logic [7:0] c_dout = 8'h00;
    logic       c_busdir_n = 1'b1, c_int_n = 1'b1, c_wait_n = 1'b1;
    assign Bus.DOUT     = c_dout;
    assign Bus.BUSDIR_n = c_busdir_n;
    assign Bus.INT_n    = c_int_n;
    assign Bus.WAIT_n   = c_wait_n;

    int n_pass = 0, n_fail = 0, n_case = 0;
    task automatic check(input bit cond, input string what);
        if(cond) n_pass++;
        else begin n_fail++; $display("FALLA  %s", what); end
    endtask

    // reposo: nada pedido; /RD y BUSDIR_n a 1 (arma la guardia de cola)
    task automatic rest();
        drive_en = 1'b0; boot_hold = 1'b0;
        c_wait_n = 1'b1; c_int_n = 1'b1; c_busdir_n = 1'b1;
        cart_rd_n = 1'b1; msx_drive = 1'b1;
        repeat(5) @(posedge clk);
    endtask

    // un caso: ok = BUS_OK esperado
    task automatic one_case(input int i, input bit ok, input string fase);
        bit de, bh, w, it, bd, rd;
        bit exp_wait, exp_int, exp_dir;
        {de, bh, w, it, bd, rd} = 6'(i);
        rest();
        // el /RD del pin baja antes que Bus.BUSDIR_n (que llega por el camino
        // retrasado, ~14 ciclos despues): asi lo espera la guardia de cola
        cart_rd_n  = rd;
        repeat(3) @(posedge clk);
        drive_en   = de;
        boot_hold  = bh;
        c_wait_n   = w;
        c_int_n    = it;
        c_busdir_n = bd;
        cart_rd_n  = rd;
        c_dout     = 8'hA5 ^ 8'(i);
        exp_wait = bh || (ok && de && !w);
        exp_int  = ok && de && !it;
        exp_dir  = !(ok && de && !rd && !bd);
        // el MSX solo conduce el bus de datos cuando el FPGA no lo hace
        msx_drive = exp_dir;
        msx_data  = 8'h3C + 8'(i);
        repeat(3) @(posedge clk);
        #1;
        n_case++;
        check(bus_ok == ok, $sformatf("%s caso %0d: BUS_OK %0d, esperado %0d", fase, i, bus_ok, ok));
        check(cart_wait_n == exp_wait,
              $sformatf("%s caso %0d (DRIVE_EN %0d BOOT_HOLD %0d WAIT_n %0d): CART_WAIT_n %0d, esperado %0d", fase, i, de, bh, w, cart_wait_n, exp_wait));
        check(cart_int_n == exp_int,
              $sformatf("%s caso %0d (DRIVE_EN %0d INT_n %0d): CART_INT_n %0d, esperado %0d", fase, i, de, it, cart_int_n, exp_int));
        check(cart_data_dir == exp_dir && cart_busdir_n == exp_dir,
              $sformatf("%s caso %0d (DRIVE_EN %0d /RD %0d BUSDIR_n %0d): CART_DATA_DIR %0d CART_BUSDIR_n %0d, esperado %0d", fase, i, de, rd, bd, cart_data_dir, cart_busdir_n, exp_dir));
        if(exp_dir)
            check(cart_data == msx_data,
                  $sformatf("%s caso %0d: el FPGA no conduce y el bus de datos lleva el valor del MSX (%02h, esperado %02h)", fase, i, cart_data, msx_data));
        else
            check(cart_data == c_dout,
                  $sformatf("%s caso %0d: el FPGA conduce DOUT (%02h, esperado %02h)", fase, i, cart_data, c_dout));
        // sin guardias nada sale al slot
        if(!bh && !(ok && de))
            check(!cart_wait_n && !cart_int_n && cart_data_dir && cart_busdir_n,
                  $sformatf("%s caso %0d: sin BOOT_HOLD ni (BUS_OK y DRIVE_EN) el slot queda libre", fase, i));
        check(!wait_timeout, $sformatf("%s caso %0d: WAIT_TIMEOUT a 0", fase, i));
    endtask

    initial begin
        int t;
        $display("== tb_integ_pins (BOARD_ID %0d)", CONFIG_BOARD::BOARD_ID);
        check(CONFIG_BOARD::BOARD_ID == BOARD_ID::WonderTANG_200b, "CONFIG_BOARD::BOARD_ID es WonderTANG_200b");
        repeat(4) @(posedge clk);
        reset_n = 1'b1;
        repeat(4) @(posedge clk);

        // fase A: sin reloj del slot
        for(int i = 0; i < 64; i++) one_case(i, 1'b0, "A sin reloj del slot:");

        // con reloj: BUS_OK sube en la primera ventana de 2^18 ciclos que lo ve entero
        rest();
        slot_run = 1'b1;
        t = 0;
        while(!bus_ok && t < 3 * (1 << 18)) begin @(posedge clk); t++; end
        check(bus_ok, $sformatf("BUS_OK sube con el reloj del slot (%0d ciclos)", t));
        $display("BUS_OK sube %0d ciclos (%.3f ms) despues de arrancar el reloj del slot", t, t * 9.26e-6);

        // fase B: con reloj del slot
        for(int i = 0; i < 64; i++) one_case(i, 1'b1, "B con reloj del slot:");

        // fase C: /RESET del slot pulsado
        rest();
        slot_reset_n = 1'b0;
        repeat(40) @(posedge clk);
        check(!bus_ok, "BUS_OK cae con el /RESET del slot");
        for(int i = 0; i < 64; i += 3) one_case(i, 1'b0, "C /RESET del slot:");
        slot_reset_n = 1'b1;
        repeat(40) @(posedge clk);
        check(bus_ok, "BUS_OK vuelve al soltar el /RESET del slot");

        // fase D: timeout fail-open del /WAIT
        rest();
        drive_en = 1'b1; boot_hold = 1'b1; c_wait_n = 1'b0;
        repeat(6000) @(posedge clk);
        #1;
        check(cart_wait_n && !wait_timeout, "D: con BOOT_HOLD el /WAIT sigue sin timeout");
        boot_hold = 1'b0;
        repeat(100) @(posedge clk);
        #1;
        check(cart_wait_n && !wait_timeout, "D: /WAIT logico pedido (antes del timeout)");
        repeat(4200) @(posedge clk);
        #1;
        check(!cart_wait_n && wait_timeout, $sformatf("D: tras 2^12 ciclos el /WAIT se suelta (CART_WAIT_n %0d) y WAIT_TIMEOUT queda a 1 (%0d)", cart_wait_n, wait_timeout));
        rest();
        #1;
        check(wait_timeout, "D: WAIT_TIMEOUT pegajoso");
        drive_en = 1'b1; c_wait_n = 1'b0;
        repeat(3) @(posedge clk);
        #1;
        check(cart_wait_n, "D: el siguiente /WAIT vuelve a salir");

        $display("RESULTADO pins: %0d casos, %0d comprobaciones pasan, %0d fallan", n_case, n_pass, n_fail);
        if(n_fail != 0) $display("BANCO: FALLA");
        else            $display("BANCO: PASA");
        $finish;
    end
endmodule

`default_nettype wire
