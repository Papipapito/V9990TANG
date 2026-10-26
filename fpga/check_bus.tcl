# ============================================================================
#  check_bus.tcl -- V9990TANG, hito 5 (bus y /WAIT): comprobacion de sintesis
#  y de timing de la configuracion v9990 (variante xtal) con el RTL del bus de
#  este arbol. NO es la build de un hito ni un bitstream para la placa: el top
#  se parchea al vuelo (abajo) porque conectar las entradas nuevas de
#  BOARD_REV1_BUS es trabajo de la integracion.
#
#  Uso:  cd fpga && gw_sh check_bus.tcl
#        -> impl/pnr/check_bus.rpt.txt / .tr, impl/gwsynthesis/check_bus_syn_rsc.xml
#  Referencia (el bus de main, hito 1, solo sintesis):
#        cd fpga && CHECK_BUS_REF=1 gw_sh check_bus.tcl
#        -> impl/gwsynthesis/check_bus_ref_syn_rsc.xml
#  Sin parche (el top del repositorio tal cual, con DRIVE_EN y BOOT_HOLD sin
#  conectar: lo que pasaria si se construyera esta rama sin la integracion;
#  solo sintesis):
#        cd fpga && CHECK_BUS_NOPATCH=1 gw_sh check_bus.tcl
#        -> impl/gwsynthesis/check_bus_nopatch.log / _syn_rsc.xml
#  Recuento por modulo (desde fpga/):
#        python3 tb/bus/syn_rsc.py impl/gwsynthesis/check_bus_syn_rsc.xml
#                impl/gwsynthesis/check_bus_ref_syn_rsc.xml u_bus u_v9990
#  Puerta: tools/check_build.py con --parcial (docs/notas/bus.md, "Sintesis").
#
#  Parche del top (solo en impl/check_bus_src/, el top del repositorio no se
#  toca):
#    .DRIVE_EN     (reset_n)            -- registro de CLK_BASE_READY y
#                                          sdram_ready: hace las veces de la
#                                          guardia de lock de la integracion
#    .BOOT_HOLD    (1'b0)               -- main.sv sigue reteniendo por la
#                                          cadena (BOOT_WAIT_n del EXPANSION_SLOT)
#    .WAIT_TIMEOUT -> OR con el LED     -- para que la sintesis no lo barra
#    .BUS_OK       sin conectar         -- su flop se usa dentro igualmente
#
#  Lista de ficheros: la de build_v9990_xtal.tcl, con el top parcheado.
# ============================================================================
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

set ref [expr {[info exists ::env(CHECK_BUS_REF)] && $::env(CHECK_BUS_REF) ne "" && $::env(CHECK_BUS_REF) ne "0"}]
set nopatch [expr {[info exists ::env(CHECK_BUS_NOPATCH)] && $::env(CHECK_BUS_NOPATCH) ne "" && $::env(CHECK_BUS_NOPATCH) ne "0"}]

if {$ref} {
    # bus y cartucho de main (hito 1) sacados con git a impl/check_bus_ref/
    file mkdir impl/check_bus_ref
    foreach {src dst} {fpga/src/board/rev1/board_rev1_bus.sv board_rev1_bus.sv
                       fpga/src/cartridge_v9990.sv           cartridge_v9990.sv
                       fpga/src/peripheral/msx/expansion_slot.sv expansion_slot.sv} {
        set txt [exec git -C .. show main:$src]
        set f [open impl/check_bus_ref/$dst w]
        fconfigure $f -translation binary
        puts -nonewline $f "$txt\n"
        close $f
    }
    set f_bus  impl/check_bus_ref/board_rev1_bus.sv
    set f_cart impl/check_bus_ref/cartridge_v9990.sv
    set f_slot impl/check_bus_ref/expansion_slot.sv
    set f_top  src/tnCart_board_wt200b_top.sv
    set base   check_bus_ref
} elseif {$nopatch} {
    set f_bus  src/board/rev1/board_rev1_bus.sv
    set f_cart src/cartridge_v9990.sv
    set f_slot src/peripheral/msx/expansion_slot.sv
    set f_top  src/tnCart_board_wt200b_top.sv
    set base   check_bus_nopatch
} else {
    set f_bus  src/board/rev1/board_rev1_bus.sv
    set f_cart src/cartridge_v9990.sv
    set f_slot src/peripheral/msx/expansion_slot.sv
    # top parcheado
    set f [open src/tnCart_board_wt200b_top.sv r]
    fconfigure $f -translation binary
    set top [read $f]
    close $f
    set n1 [regsub {(\n[ \t]*)BOARD_REV1_BUS u_bus \(} $top "\\1wire check_wait_timeout;\\1wire check_bus_ok;\\1BOARD_REV1_BUS u_bus (" top]
    set n2 [regsub {(\.CART_DATA_DIR,[ \t\r]*\n[ \t]*)\.Bus([ \t\r]*\n[ \t]*\);)} $top "\\1.Bus,\n        .DRIVE_EN       (reset_n),\n        .BOOT_HOLD      (1'b0),\n        .WAIT_TIMEOUT   (check_wait_timeout),\n        .BUS_OK         (check_bus_ok)\\2" top]
    set n3 [regsub {\.LedPort[ \t]*\(LED\),} $top ".LedPort        (check_led)," top]
    set n4 [regsub {(\n[ \t]*)LED_IF LedNextor\(\);} $top "\\1wire check_led;\\1assign LED = check_led | check_wait_timeout;\\1LED_IF LedNextor();" top]
    if {$n1 != 1 || $n2 != 1 || $n3 != 1 || $n4 != 1} {
        error "check_bus.tcl: el parche del top no aplica ($n1 $n2 $n3 $n4): ha cambiado tnCart_board_wt200b_top.sv"
    }
    file mkdir impl/check_bus_src
    set f [open impl/check_bus_src/tnCart_board_wt200b_top.sv w]
    fconfigure $f -translation binary
    puts -nonewline $f $top
    close $f
    set f_top  impl/check_bus_src/tnCart_board_wt200b_top.sv
    set base   check_bus
}

# ----- placa wt200b (tnCartWonder) -----
add_file src/board/board_id.sv
add_file $f_bus
add_file src/board/rev1/board_rev1_tmds.sv
add_file src/board/wt200b/board_wt200b_clock.sv
add_file src/board/wt200b/board_wt200b_config.sv
add_file src/board/rev1/dvi_tx/dvi_tx.v

# ----- sistema (tnCart) -----
add_file src/bootloader.sv
add_file $f_cart
add_file config/v9990.sv
add_file src/main.sv
add_file src/peripheral/flash.sv
add_file src/peripheral/led.sv
add_file src/peripheral/msx/bus.sv
add_file $f_slot
add_file src/peripheral/ram/ram.sv
add_file src/peripheral/ram/sdram.sv
add_file src/peripheral/ram/uma.sv
add_file src/peripheral/signal/attenuator.sv
add_file src/peripheral/signal/limiter.sv
add_file src/peripheral/sound/dac_16bit.sv
add_file src/peripheral/sound/i2s_audio_tx.sv
add_file src/peripheral/sound/sound.sv
add_file src/peripheral/spi.sv

# ----- core V9990: tiny9990 de buppu3/tnCart 8714731, sin parches -----
add_file v9990/tiny9990/t9990.sv
add_file v9990/tiny9990/t9990_bitmap.sv
add_file v9990/tiny9990/t9990_blit.sv
add_file v9990/tiny9990/t9990_blit_addr.sv
add_file v9990/tiny9990/t9990_blit_bitmask.sv
add_file v9990/tiny9990/t9990_blit_fifo.sv
add_file v9990/tiny9990/t9990_clock.sv
add_file v9990/tiny9990/t9990_color_decode.sv
add_file v9990/tiny9990/t9990_palette.sv
add_file v9990/tiny9990/t9990_pattern.sv
add_file v9990/tiny9990/t9990_port.sv
add_file v9990/tiny9990/t9990_priority.sv
add_file v9990/tiny9990/t9990_ram.sv
add_file v9990/tiny9990/t9990_selector.sv
add_file v9990/tiny9990/t9990_shift_buffer.sv
add_file v9990/tiny9990/t9990_sprite.sv
add_file v9990/tiny9990/t9990_timing.sv

# ----- video: upscan a 720x480 (855x524 a 27 MHz) -----
add_file src/peripheral/video/video.sv
add_file src/peripheral/video/video_upscan.sv

# ----- top -----
add_file $f_top

# ----- restricciones -----
add_file src/board/wt200b/board_wt200b.cst
add_file constraints/v9990_xtal.sdc

set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module TNCART_BOARD_WT200B_TOP -verilog_std sysv2017
set_option -output_base_name $base
set_option -place_option 2 -route_option 1
set_option -gen_text_timing_rpt 1
# SDF para el punto 6 de tools/check_build.py (modelo de DCLK), como en build_v9990_xtal.tcl
set_option -gen_sdf 1

run syn
if {!$ref && !$nopatch} {
    run pnr
}
