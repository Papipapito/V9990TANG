# ============================================================================
#  check_video.tcl -- V9990TANG: comprobacion de sintesis del area de video
#  (PAL en la salida y palanca BLEND del upscan). Por defecto solo 'run syn':
#  LUT/ALU/FF/BSRAM de u_upscan y u_tmds en impl/gwsynthesis/<base>_syn_rsc.xml.
#
#  Desde la fusion de las areas (hito/fusion) la lista de ficheros, el orden
#  y el .sdc son los de build_common.tcl (configuracion v9990, variante
#  xtal), con las opciones de P&R del hito 1. Lo que cambia se elige con
#  variables de entorno:
#
#    VIDEO_BLEND=1|0      BLEND del upscan (1 por defecto). Con 0 se compila
#                         una copia de config/v9990.sv con UPSCAN_BLEND = 0
#                         (el top pasa .BLEND(CONFIG::UPSCAN_BLEND)).
#    VIDEO_PAL=real|zero  'real' (defecto): cartridge_v9990.sv tal cual, que
#                         desde la fusion conduce Video.PAL con la salida PAL
#                         del T9990. 'zero': copia con Video.PAL = 0, para
#                         medir lo que cuesta la logica PAL del upscan y de
#                         BOARD_REV1_TMDS_OUT (antes de la fusion eran
#                         'live' y 'none').
#    VIDEO_PNR=0|1        1: ademas 'run pnr' (CLS y timing en impl/pnr/<base>.*,
#                         con el .sdc de la build y su informe de timing en texto).
#
#  Se quita VIDEO_SRC=hito1 (video.sv, video_upscan.sv y board_rev1_tmds.sv
#  de 20936e6): el video.sv del hito 1 no tiene Video.PAL y el
#  cartridge_v9990.sv fusionado lo conduce, asi que no elabora. Sus cifras
#  estan en docs/notas/video.md.
#
#  Uso (desde fpga/):  gw_sh check_video.tcl
#        VIDEO_BLEND=0 VIDEO_PAL=zero gw_sh check_video.tcl
#  Salida: impl/gwsynthesis/check_video_b<blend>_<pal>_syn_rsc.xml
#  Las copias parcheadas van a impl/check_video/ (ignorado por git).
# ============================================================================
set blend 1
if {[info exists ::env(VIDEO_BLEND)]} { set blend $::env(VIDEO_BLEND) }
set pal real
if {[info exists ::env(VIDEO_PAL)]} { set pal $::env(VIDEO_PAL) }
set pnr 0
if {[info exists ::env(VIDEO_PNR)]} { set pnr $::env(VIDEO_PNR) }
if {$pnr ne "0" && $pnr ne "1"} { error "VIDEO_PNR tiene que ser 0 o 1" }
if {$blend ne "0" && $blend ne "1"} { error "VIDEO_BLEND tiene que ser 0 o 1" }
if {$pal ne "real" && $pal ne "zero"} { error "VIDEO_PAL tiene que ser real o zero (desde la fusion)" }
if {[info exists ::env(VIDEO_SRC)] && $::env(VIDEO_SRC) ne "work"} { error "VIDEO_SRC=hito1 ya no existe desde la fusion (ver la cabecera)" }

set base check_video_b${blend}_${pal}
set tmp impl/check_video/$base
file mkdir $tmp

proc slurp {path} { set f [open $path r]; fconfigure $f -encoding utf-8; set t [read $f]; close $f; return $t }
proc spit {path txt} { set f [open $path w]; fconfigure $f -encoding utf-8 -translation lf; puts -nonewline $f $txt; close $f }

set FILE_SUBST {}
if {$blend eq "0"} {
    set txt [slurp config/v9990.sv]
    set n [regsub {(localparam\s+UPSCAN_BLEND\s+=\s+)1} $txt {\10} txt]
    if {$n != 1} { error "no se encontro 'localparam UPSCAN_BLEND = 1' en config/v9990.sv ($n)" }
    spit $tmp/v9990.sv $txt
    lappend FILE_SUBST config/v9990.sv $tmp/v9990.sv
}
if {$pal eq "zero"} {
    set txt [slurp src/cartridge_v9990.sv]
    set n [regsub {assign Video\.PAL = video_pal;} $txt {assign Video.PAL = 1'b0;     // check_video.tcl: PAL a 0, solo para medir} txt]
    if {$n != 1} { error "no se encontro 'assign Video.PAL = video_pal;' en cartridge_v9990.sv" }
    spit $tmp/cartridge_v9990.sv $txt
    lappend FILE_SUBST src/cartridge_v9990.sv $tmp/cartridge_v9990.sv
}
puts "check_video: BLEND=$blend PAL=$pal -> $base (copias: $FILE_SUBST)"

set CFG        v9990
set VARIANT    xtal
set OUT_NAME   $base
set BUILD_OPTS {-place_option 2 -route_option 1}
if {$pnr eq "1"} { set RUN_STEPS {syn pnr} } else { set RUN_STEPS {syn} }
source build_common.tcl
