//
// board_wt200b_bus_guard.sv -- V9990TANG
//
// BSD 3-Clause License
//
// Copyright (c) 2026, Papipapito
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
// Guardia de lock sobre las salidas al slot, PROVISIONAL hasta la fusion con
// hito/bus (que la mete dentro de BOARD_REV1_BUS, en los pines, con sus
// entradas DRIVE_EN y BOOT_HOLD y su bus_ok). En la fusion este modulo
// desaparece: en el top, u_bus recibe .DRIVE_EN(drive_en_27) y
// .BOOT_HOLD(boot_hold_27) y se conecta directo a Bus.
//
// Va entre BOARD_REV1_BUS (lado Pin) y los cartuchos (lado Cart). Hacia los
// cartuchos pasa todo tal cual; hacia el bus solo cambian las cuatro senales
// que BOARD_REV1_BUS (el de main) usa de forma combinacional hacia los pines:
//   CART_WAIT_n   = !WAIT_n                       (1 = el transistor baja /WAIT)
//   CART_INT_n    = !INT_n (WonderTANG 2.00b; la 1.01c no invierte)
//   dir           = !(!CART_RD_n && !BUSDIR_n)    -> CART_DATA_DIR = CART_BUSDIR_n = dir,
//                   CART_DATA_SIG = dir ? Z : DOUT
// asi que en los pines queda:
//   /WAIT = BOOT_HOLD || (DRIVE_EN && wait)
//   /INT  = DRIVE_EN && int
//   datos = solo con DRIVE_EN (si no, dir = 1: CART_DATA_DIR = 1,
//           CART_BUSDIR_n = 1 y CART_DATA_SIG en alta impedancia)
// El gateo en los pines mismos no se puede hacer sin tocar board_rev1_bus.sv
// (CART_DATA_SIG es un inout con su triestado dentro del modulo); el efecto es
// el mismo. DRIVE_EN y BOOT_HOLD son flops de CLK_27M que solo llegan a pines
// por logica combinacional: no hay flop de destino (el cruce lo corta el
// set_clock_groups del .sdc). Banco: tb/integ/tb_integ_pins.sv.
//

`default_nettype none

module BOARD_WT200B_BUS_GUARD (
    input   wire            DRIVE_EN,       // BOARD_WT200B_GUARD.DRIVE_EN_27
    input   wire            BOOT_HOLD,      // BOARD_WT200B_GUARD.BOOT_HOLD_27
    BUS_IF.CARTRIDGE        Pin,            // hacia BOARD_REV1_BUS
    BUS_IF.MSX              Cart            // hacia los cartuchos (MAIN)
);
    assign Cart.ADDR       = Pin.ADDR;
    assign Cart.DIN        = Pin.DIN;
    assign Cart.RFSH_n     = Pin.RFSH_n;
    assign Cart.RD_n       = Pin.RD_n;
    assign Cart.WR_n       = Pin.WR_n;
    assign Cart.MERQ_n     = Pin.MERQ_n;
    assign Cart.IORQ_n     = Pin.IORQ_n;
    assign Cart.CS1_n      = Pin.CS1_n;
    assign Cart.CS2_n      = Pin.CS2_n;
    assign Cart.CS12_n     = Pin.CS12_n;
    assign Cart.M1_n       = Pin.M1_n;
    assign Cart.SLTSL_n    = Pin.SLTSL_n;
    assign Cart.RESET_n    = Pin.RESET_n;
    assign Cart.CLK        = Pin.CLK;
    assign Cart.CLK_EN     = Pin.CLK_EN;
    assign Cart.CLK_21M    = Pin.CLK_21M;
    assign Cart.CLK_EN_21M = Pin.CLK_EN_21M;

    assign Pin.DOUT        = Cart.DOUT;
    assign Pin.BUSDIR_n    = Cart.BUSDIR_n || !DRIVE_EN;
    assign Pin.INT_n       = Cart.INT_n    || !DRIVE_EN;
    assign Pin.WAIT_n      = !(BOOT_HOLD || (DRIVE_EN && !Cart.WAIT_n));
endmodule

`default_nettype wire
