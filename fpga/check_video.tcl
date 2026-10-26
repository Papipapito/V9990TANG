# ============================================================================
#  check_video.tcl -- V9990TANG: comprobacion de sintesis del area de video
#  (PAL en la salida y palanca BLEND del upscan). Por defecto solo 'run syn':
#  LUT/ALU/FF/BSRAM de u_upscan y u_tmds en impl/gwsynthesis/<base>_syn_rsc.xml.
#
#  Parte de build_v9990_xtal.tcl (misma lista de ficheros, mismo orden, mismas
#  opciones); lo que cambia se elige con variables de entorno:
#
#    VIDEO_BLEND=1|0      BLEND del upscan (1 por defecto). Con 0 se compila
#                         una copia de video_upscan.sv con el valor por defecto
#                         de BLEND a 0 (el top no pasa BLEND).
#    VIDEO_PAL=none|live  'none' (defecto): cartridge_v9990.sv tal cual, que
#                         todavia no conduce Video.PAL (lo hara la integracion).
#                         'live': copia de cartridge_v9990.sv con
#                         'assign Video.PAL = Video.INTERLACE;', una senal
#                         viva de registro que hace de PAL solo para medir el
#                         coste de la logica PAL (no es la conexion real).
#    VIDEO_SRC=work|hito1 'hito1': video.sv, video_upscan.sv y
#                         board_rev1_tmds.sv del commit 20936e6 (git show), la
#                         referencia medida con esta misma herramienta.
#    VIDEO_PNR=0|1        1: ademas 'run pnr' (CLS y timing en impl/pnr/<base>.*,
#                         con el .sdc de la build y su informe de timing en texto).
#
#  Uso (desde fpga/):  gw_sh check_video.tcl
#        VIDEO_BLEND=0 VIDEO_PAL=live gw_sh check_video.tcl
#  Salida: impl/gwsynthesis/check_video_<src>_b<blend>_<pal>_syn_rsc.xml
#  Las copias parcheadas van a impl/check_video/ (ignorado por git).
# ============================================================================
set blend 1
if {[info exists ::env(VIDEO_BLEND)]} { set blend $::env(VIDEO_BLEND) }
set pal none
if {[info exists ::env(VIDEO_PAL)]} { set pal $::env(VIDEO_PAL) }
set src work
if {[info exists ::env(VIDEO_SRC)]} { set src $::env(VIDEO_SRC) }
set pnr 0
if {[info exists ::env(VIDEO_PNR)]} { set pnr $::env(VIDEO_PNR) }
if {$pnr ne "0" && $pnr ne "1"} { error "VIDEO_PNR tiene que ser 0 o 1" }
if {$blend ne "0" && $blend ne "1"} { error "VIDEO_BLEND tiene que ser 0 o 1" }
if {$pal ne "none" && $pal ne "live"} { error "VIDEO_PAL tiene que ser none o live" }
if {$src ne "work" && $src ne "hito1"} { error "VIDEO_SRC tiene que ser work o hito1" }
if {$src eq "hito1" && ($blend ne "1" || $pal ne "none")} { error "VIDEO_SRC=hito1 solo con VIDEO_BLEND=1 VIDEO_PAL=none" }

set base check_video_${src}_b${blend}_${pal}
set tmp impl/check_video/$base
file mkdir $tmp

proc slurp {path} { set f [open $path r]; fconfigure $f -encoding utf-8; set t [read $f]; close $f; return $t }
proc spit {path txt} { set f [open $path w]; fconfigure $f -encoding utf-8 -translation lf; puts -nonewline $f $txt; close $f }

# ----- fuentes de video -----
set f_video        src/peripheral/video/video.sv
set f_upscan       src/peripheral/video/video_upscan.sv
set f_tmds         src/board/rev1/board_rev1_tmds.sv
set f_cartridge    src/cartridge_v9990.sv
if {$src eq "hito1"} {
    foreach {var path} [list f_video $f_video f_upscan $f_upscan f_tmds $f_tmds] {
        set out $tmp/[file tail $path]
        spit $out [exec git show 20936e6:fpga/$path]
        set $var $out
    }
}
if {$blend eq "0"} {
    set txt [slurp $f_upscan]
    set n [regsub -all {(parameter BLEND\s+=\s+)1} $txt {\10} txt]
    if {$n != 2} { error "no se encontraron los dos 'parameter BLEND = 1' ($n)" }
    set f_upscan $tmp/video_upscan.sv
    spit $f_upscan $txt
}
if {$pal eq "live"} {
    set txt [slurp $f_cartridge]
    set n [regsub {(    assign Video.RESOLUTION = video_reso;\n)} $txt "\\1    assign Video.PAL = Video.INTERLACE;     // check_video.tcl: solo para medir\n" txt]
    if {$n != 1} { error "no se encontro 'assign Video.RESOLUTION' en cartridge_v9990.sv" }
    set f_cartridge $tmp/cartridge_v9990.sv
    spit $f_cartridge $txt
}
puts "check_video: src=$src BLEND=$blend PAL=$pal -> $base"
puts "check_video: video=$f_video upscan=$f_upscan tmds=$f_tmds cartridge=$f_cartridge"

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

# ----- placa wt200b (tnCartWonder) -----
add_file src/board/board_id.sv
add_file src/board/rev1/board_rev1_bus.sv
add_file $f_tmds
add_file src/board/wt200b/board_wt200b_clock.sv
add_file src/board/wt200b/board_wt200b_config.sv
add_file src/board/rev1/dvi_tx/dvi_tx.v

# ----- sistema (tnCart) -----
add_file src/bootloader.sv
add_file $f_cartridge
add_file config/v9990.sv
add_file src/main.sv
add_file src/peripheral/flash.sv
add_file src/peripheral/led.sv
add_file src/peripheral/msx/bus.sv
add_file src/peripheral/msx/expansion_slot.sv
add_file src/peripheral/ram/ram.sv
add_file src/peripheral/ram/sdram.sv
add_file src/peripheral/ram/uma.sv
add_file src/peripheral/signal/attenuator.sv
add_file src/peripheral/signal/limiter.sv
add_file src/peripheral/sound/dac_16bit.sv
add_file src/peripheral/sound/i2s_audio_tx.sv
add_file src/peripheral/sound/sound.sv
add_file src/peripheral/spi.sv

# ----- core V9990 -----
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

# ----- video -----
add_file $f_video
add_file $f_upscan

# ----- top -----
add_file src/tnCart_board_wt200b_top.sv

# ----- restricciones -----
add_file src/board/wt200b/board_wt200b.cst
add_file constraints/v9990_xtal.sdc

set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module TNCART_BOARD_WT200B_TOP -verilog_std sysv2017
set_option -output_base_name $base
set_option -place_option 2 -route_option 1

run syn
if {$pnr eq "1"} {
    set_option -gen_text_timing_rpt 1
    run pnr
}
