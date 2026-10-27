# build_nl.tcl -- sintesis (solo run syn) de NL_TOP para simular su netlist.
# Variante con NL_VAR: hito1 (video.sv y video_upscan.sv del commit 20936e6, por
# git show), b1 o b0 (los del arbol, BLEND = 1 o 0).
# Uso (Windows, desde esta carpeta): NL_VAR=hito1 gw_sh build_nl.tcl
set var $::env(NL_VAR)
if {$var ni {hito1 b1 b0}} { error "NL_VAR tiene que ser hito1, b1 o b0" }
file mkdir impl
if {$var eq "hito1"} {
    foreach {out path} {impl/video_hito1.sv fpga/src/peripheral/video/video.sv impl/video_upscan_hito1.sv fpga/src/peripheral/video/video_upscan.sv} {
        set f [open $out w]; fconfigure $f -translation lf
        puts -nonewline $f [exec git show 20936e6:$path]
        close $f
    }
    set f_video  impl/video_hito1.sv
    set f_upscan impl/video_upscan_hito1.sv
} else {
    set f_video  ../../../src/peripheral/video/video.sv
    set f_upscan ../../../src/peripheral/video/video_upscan.sv
}
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file $f_video
add_file $f_upscan
add_file top_$var.sv
set_option -top_module NL_TOP -verilog_std sysv2017
set_option -output_base_name nl_$var
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
run syn
