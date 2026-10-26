# ============================================================================
#  build_common.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Parte comun de las cuatro builds. No se ejecuta sola: la cargan
#  build_v9990_xtal.tcl, build_v9990_sync.tcl, build_v9990_megaram_xtal.tcl y
#  build_v9990_megaram_sync.tcl despues de fijar
#    CFG      v9990 | v9990_megaram   (fpga/config/<CFG>.sv)
#    VARIANT  xtal  | sync            (src/board/wt200b/board_wt200b_config_<VARIANT>.sv
#                                      y constraints/<CFG>_<VARIANT>.sdc)
#  Salida: impl/pnr/<CFG>_<VARIANT>.fs, .bin, .rpt.txt (recursos), .tr
#  (timing), .sdf; logs en impl/gwsynthesis/<CFG>_<VARIANT>.log e
#  impl/pnr/<CFG>_<VARIANT>.log. Las cuatro escriben en el mismo impl/: una
#  build cada vez, y archivar (tools/archive_build.py) antes de la siguiente.
#
#  gw_sh (Gowin 1.9.12.03) no abre ficheros con rutas de mas de 260
#  caracteres: el repositorio tiene que estar en una ruta corta.
# ============================================================================
if {![info exists CFG] || ![info exists VARIANT]} {
    puts "ERROR: build_common.tcl no se lanza solo: usar build_v9990_xtal.tcl, build_v9990_sync.tcl, build_v9990_megaram_xtal.tcl o build_v9990_megaram_sync.tcl"
    exit 1
}
if {[lsearch -exact {v9990 v9990_megaram} $CFG] < 0 || [lsearch -exact {xtal sync} $VARIANT] < 0} {
    puts "ERROR: CFG = '$CFG' / VARIANT = '$VARIANT' no validos"
    exit 1
}
set NAME ${CFG}_${VARIANT}
set MEGA [expr {$CFG eq "v9990_megaram"}]

# Lista de ficheros: la de tnCart_board_wt200b.gprj de tnCartWonder, en el
# mismo orden, sin lo que estas configuraciones no elaboran (FM, PSG, Nextor,
# mapper, PAC, UART) y, desde el hito 3, sin bootloader, flash ni SPI. La
# configuracion MegaRAM compila bootloader.sv, flash.sv y spi.sv solo por las
# definiciones que usa la megaROM (paquete XFER y XFER_IF, y FLASH_IF y SPI_IF
# que esos ficheros necesitan para analizarse): BOOTLOADER, FLASH_SPI y SPI
# no se instancian.
set FILES {}
# ----- placa wt200b (tnCartWonder) -----
lappend FILES src/board/board_id.sv
lappend FILES src/board/rev1/board_rev1_bus.sv
lappend FILES src/board/rev1/board_rev1_tmds.sv
lappend FILES src/board/wt200b/board_wt200b_clock.sv
lappend FILES src/board/wt200b/board_wt200b_config_${VARIANT}.sv
lappend FILES src/board/wt200b/board_wt200b_guard.sv
# provisional hasta la fusion con hito/bus (ver el top)
lappend FILES src/board/wt200b/board_wt200b_bus_guard.sv
lappend FILES src/board/rev1/dvi_tx/dvi_tx.v
# ----- sistema -----
lappend FILES src/system/system_reset.sv
if {$MEGA} {
    lappend FILES src/bootloader.sv
    lappend FILES src/system/megarom_xfer_tie.sv
}
lappend FILES src/cartridge_v9990.sv
if {$MEGA} {
    lappend FILES src/cartridge_megarom.sv
}
lappend FILES config/${CFG}.sv
lappend FILES src/main.sv
if {$MEGA} {
    lappend FILES src/peripheral/flash.sv
}
lappend FILES src/peripheral/led.sv
lappend FILES src/peripheral/msx/bus.sv
lappend FILES src/peripheral/msx/expansion_slot.sv
if {$MEGA} {
    lappend FILES src/peripheral/msx/megarom_configure.sv
    lappend FILES src/peripheral/msx/megarom_controller.sv
    lappend FILES src/peripheral/msx/megarom_clear.sv
}
lappend FILES src/peripheral/ram/ram.sv
lappend FILES src/peripheral/ram/sdram.sv
lappend FILES src/peripheral/ram/uma.sv
lappend FILES src/peripheral/signal/attenuator.sv
lappend FILES src/peripheral/signal/limiter.sv
lappend FILES src/peripheral/sound/dac_16bit.sv
lappend FILES src/peripheral/sound/i2s_audio_tx.sv
if {$MEGA} {
    lappend FILES src/peripheral/sound/scc/scc.sv
}
lappend FILES src/peripheral/sound/sound.sv
if {$MEGA} {
    lappend FILES src/peripheral/spi.sv
}
# ----- core V9990: tiny9990 de buppu3/tnCart -----
foreach f {t9990 t9990_bitmap t9990_blit t9990_blit_addr t9990_blit_bitmask
           t9990_blit_fifo t9990_clock t9990_color_decode t9990_palette
           t9990_pattern t9990_port t9990_priority t9990_ram t9990_selector
           t9990_shift_buffer t9990_sprite t9990_timing} {
    lappend FILES v9990/tiny9990/$f.sv
}
# ----- video: upscan a 720x480 (855x524) -----
lappend FILES src/peripheral/video/video.sv
lappend FILES src/peripheral/video/video_upscan.sv
# ----- top -----
lappend FILES src/tnCart_board_wt200b_top.sv
# ----- restricciones -----
lappend FILES src/board/wt200b/board_wt200b.cst
lappend FILES constraints/${NAME}.sdc

# Antes de la fusion con hito/megaram faltan megarom_clear.sv y
# config/v9990_megaram.sv: la build se para aqui con la lista de lo que falta.
set MISSING {}
foreach f $FILES {
    if {![file exists $f]} { lappend MISSING $f }
}
if {[llength $MISSING] > 0} {
    puts "ERROR: build $NAME: faltan [llength $MISSING] fichero(s):"
    foreach f $MISSING { puts "ERROR:   $f" }
    if {$MEGA} {
        puts "ERROR: la configuracion MegaRAM necesita la fusion con hito/megaram (megarom_clear.sv, config/v9990_megaram.sv) y descomentar `define HAVE_MEGAROM_CLEAR en src/main.sv"
    }
    exit 1
}
# ... y, con los ficheros ya fusionados, el borrado tiene que estar activado
# en main.sv (si no, la elaboracion falla en MEGAROM_CLEAR_FALTA_HASTA_LA_FUSION)
if {$MEGA} {
    set fh [open src/main.sv r]
    set main_sv [read $fh]
    close $fh
    if {![regexp -line {^\s*`define\s+HAVE_MEGAROM_CLEAR\M} $main_sv]} {
        puts "ERROR: build $NAME: en src/main.sv falta descomentar `define HAVE_MEGAROM_CLEAR (MEGAROM_CLEAR de hito/megaram)"
        exit 1
    }
}

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
foreach f $FILES { add_file $f }

# MSPI = flash del bitstream (sin uso: pines en reposo); SSPI = pines del DAC
# I2S y del bus de la WonderTANG
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module TNCART_BOARD_WT200B_TOP -verilog_std sysv2017
set_option -output_base_name $NAME
# Opciones de sintesis y de P&R: las del hito 1 (map 1, place 2, route 1)
# salvo que el build_<cfg>_<variante>.tcl fije BUILD_OPTS antes de cargar
# este fichero (pares "-opcion valor" de set_option). Sintesis y P&R son
# deterministas, pero un cambio minimo del RTL mueve la colocacion entera, y
# los margenes de CLK_BASE (Fmax del core, que tiene que dar 109 MHz, y la
# carrera CLK_BASE -> DCLK) dependen de ella: cada variante guarda el juego
# con el que paso la puerta, y al cambiar el RTL hay que volver a barrerlo
# (docs/notas/integ.md, seccion 6). En el GW2AR-18, -place_option 1 da la
# misma colocacion que 2, 3 y 4 no existen, y -replicate_resources 1 no
# cambia nada.
if {![info exists BUILD_OPTS]} {
    set BUILD_OPTS {-place_option 2 -route_option 1}
}
puts "build $NAME: opciones de sintesis y P&R: $BUILD_OPTS"
eval set_option $BUILD_OPTS
set_option -gen_text_timing_rpt 1
# SDF post-PnR: tools/check_build.py (punto 6) toma de el la red
# CLKOUT -> dclk_en_ff[1]/CLK, el tC2Q de ese flop, la ruta Q -> OR de
# Video.DCLK y el pin de LUT mas rapido del chip (el retardo de la propia OR
# no sale), les suma la latencia del rPLL del .tr y comprueba que el flanco
# real no llega antes que el -offset del .sdc (ver docs/ARCHITECTURE.md)
set_option -gen_sdf 1

run syn
run pnr
