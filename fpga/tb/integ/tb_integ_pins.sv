//
// tb_integ_pins.sv -- V9990TANG: polaridad de los pines del slot con la
// guardia de lock (BOARD_WT200B_BUS_GUARD) delante del BOARD_REV1_BUS de main.
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Modulos reales: BOARD_REV1_BUS (con CONFIG_BOARD de la wt200b y CONFIG de
// config/v9990.sv) y BOARD_WT200B_BUS_GUARD, conectados como en el top. El
// banco hace de cartucho (Bus.DOUT/BUSDIR_n/INT_n/WAIT_n) y de MSX (/RD y el
// bus de datos) y recorre todas las combinaciones de DRIVE_EN, BOOT_HOLD,
// WAIT_n, INT_n, BUSDIR_n y /RD comprobando los pines:
//   CART_WAIT_n   = BOOT_HOLD || (DRIVE_EN && !WAIT_n)     (1 = /WAIT bajo en el slot)
//   CART_INT_n    = DRIVE_EN && !INT_n                     (2.00b: 1 = /INT bajo)
//   CART_DATA_DIR = CART_BUSDIR_n = !(DRIVE_EN && !/RD && !BUSDIR_n)
//   CART_DATA_SIG = DOUT cuando el FPGA conduce; si no, lo que ponga el MSX
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

    // guardia
    logic drive_en = 1'b0, boot_hold = 1'b0;

    BUS_IF BusPin();
    BUS_IF Bus();

    BOARD_REV1_BUS u_bus (
        .RESET_n        (reset_n),
        .CLK            (clk),
        .CLK_21M        (1'b0),
        .CART_BUSDIR_n  (cart_busdir_n),
        .CART_INT_n     (cart_int_n),
        .CART_WAIT_n    (cart_wait_n),
        .CART_SLTSL_n   (1'b1),
        .CART_RD_n      (cart_rd_n),
        .CART_WR_n      (1'b1),
        .CART_CLOCK     (1'b0),
        .CART_MUX_SIG   (8'hFF),
        .CART_MUX_CS_n  (cart_mux_cs_n),
        .CART_DATA_SIG  (cart_data),
        .CART_DATA_DIR  (cart_data_dir),
        .Bus            (BusPin)
    );

    BOARD_WT200B_BUS_GUARD u_guard (
        .DRIVE_EN       (drive_en),
        .BOOT_HOLD      (boot_hold),
        .Pin            (BusPin),
        .Cart           (Bus)
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

    initial begin
        $display("== tb_integ_pins (BOARD_ID %0d)", CONFIG_BOARD::BOARD_ID);
        check(CONFIG_BOARD::BOARD_ID == BOARD_ID::WonderTANG_200b, "CONFIG_BOARD::BOARD_ID es WonderTANG_200b");
        repeat(4) @(posedge clk);
        reset_n = 1'b1;
        repeat(4) @(posedge clk);
        for(int i = 0; i < 64; i++) begin
            bit de, bh, w, it, bd, rd;
            bit exp_wait, exp_int, exp_dir;
            {de, bh, w, it, bd, rd} = 6'(i);
            drive_en   = de;
            boot_hold  = bh;
            c_wait_n   = w;
            c_int_n    = it;
            c_busdir_n = bd;
            cart_rd_n  = rd;
            c_dout     = 8'hA5 ^ 8'(i);
            exp_wait = bh || (de && !w);
            exp_int  = de && !it;
            exp_dir  = !(de && !rd && !bd);
            // el MSX solo conduce el bus de datos cuando el FPGA no lo hace
            msx_drive = exp_dir;
            msx_data  = 8'h3C + 8'(i);
            #1;
            n_case++;
            check(cart_wait_n == exp_wait,
                  $sformatf("caso %0d (DRIVE_EN %0d BOOT_HOLD %0d WAIT_n %0d): CART_WAIT_n %0d, esperado %0d", i, de, bh, w, cart_wait_n, exp_wait));
            check(cart_int_n == exp_int,
                  $sformatf("caso %0d (DRIVE_EN %0d INT_n %0d): CART_INT_n %0d, esperado %0d", i, de, it, cart_int_n, exp_int));
            check(cart_data_dir == exp_dir && cart_busdir_n == exp_dir,
                  $sformatf("caso %0d (DRIVE_EN %0d /RD %0d BUSDIR_n %0d): CART_DATA_DIR %0d CART_BUSDIR_n %0d, esperado %0d", i, de, rd, bd, cart_data_dir, cart_busdir_n, exp_dir));
            if(exp_dir)
                check(cart_data == msx_data,
                      $sformatf("caso %0d: el FPGA no conduce y el bus de datos lleva el valor del MSX (%02h, esperado %02h)", i, cart_data, msx_data));
            else
                check(cart_data == c_dout,
                      $sformatf("caso %0d: el FPGA conduce DOUT (%02h, esperado %02h)", i, cart_data, c_dout));
            // reposo sin guardia: con DRIVE_EN = 0 y BOOT_HOLD = 0 nada sale al slot
            if(!de && !bh)
                check(!cart_wait_n && !cart_int_n && cart_data_dir && cart_busdir_n,
                      $sformatf("caso %0d: sin DRIVE_EN ni BOOT_HOLD el slot queda libre", i));
        end
        $display("RESULTADO pins: %0d casos, %0d comprobaciones pasan, %0d fallan", n_case, n_pass, n_fail);
        if(n_fail != 0) $display("BANCO: FALLA");
        else            $display("BANCO: PASA");
        $finish;
    end
endmodule

`default_nettype wire
