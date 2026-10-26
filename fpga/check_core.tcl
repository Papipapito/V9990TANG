# ============================================================================
#  check_core.tcl -- V9990TANG: comprobacion de sintesis del core tiny9990
#  fuera de contexto (top T9990, solo 'run syn'). Cuenta LUT/ALU/FF/BSRAM en
#  impl/gwsynthesis/check_core_<variante>_syn_rsc.xml.
#
#  Misma lista de ficheros del core que build_v9990_xtal.tcl, con los paquetes
#  primero (config/v9990.sv y ram.sv: CONFIG::ENABLE_V9990_CMD y RAM::DIN_SIZE_*),
#  mismo dispositivo y -verilog_std sysv2017. La variante se elige con la
#  variable de entorno CORE_VARIANT:
#
#    full   (defecto) el core de trabajo con ENABLE_PAL = ENABLE_CURSOR_EOR =
#           ENABLE_R16 = 1
#    nopal  ENABLE_PAL = 0          (coste del cuadro PAL = full - nopal)
#    noeor  ENABLE_CURSOR_EOR = 0   (coste del cursor EOR = full - noeor)
#    nor16  ENABLE_R16 = 0          (coste de R#16 = full - nor16)
#    none   los tres a 0
#    main   el core de la rama main (tiny9990 de tnCart sin parches: la
#           referencia de 8 661 LUT / 767 ALU / 4 766 FF / 18 BSRAM del estudio)
#    parches el core del commit 2f95eb8 (los seis parches + P#8-P#15)
#
#  Los parametros se cambian en una copia de t9990.sv (el valor por defecto de
#  la declaracion 'parameter'), en impl/check_core/<variante>/ (ignorado por
#  git): el top fuera de contexto es el propio T9990 y gw_sh no tiene una opcion
#  para dar parametros al top.
#
#  Uso (desde fpga/):  gw_sh check_core.tcl
#                      CORE_VARIANT=nopal gw_sh check_core.tcl
#
#  V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
set variant full
if {[info exists ::env(CORE_VARIANT)]} { set variant $::env(CORE_VARIANT) }
set known {full nopal noeor nor16 none main parches}
if {[lsearch -exact $known $variant] < 0} { error "CORE_VARIANT tiene que ser uno de: $known" }

set base check_core_${variant}
set tmp impl/check_core/$variant
file mkdir $tmp

proc slurp {path} { set f [open $path r]; fconfigure $f -encoding utf-8 -translation binary; set t [read $f]; close $f; return $t }
proc spit {path txt} { set f [open $path w]; fconfigure $f -encoding utf-8 -translation binary; puts -nonewline $f $txt; close $f }

set core {t9990_port.sv t9990.sv t9990_bitmap.sv t9990_blit.sv t9990_blit_addr.sv t9990_blit_bitmask.sv
          t9990_blit_fifo.sv t9990_clock.sv t9990_color_decode.sv t9990_palette.sv t9990_pattern.sv
          t9990_priority.sv t9990_ram.sv t9990_selector.sv t9990_shift_buffer.sv t9990_sprite.sv
          t9990_timing.sv}

# ----- de donde sale cada fichero del core -----
set files {}
if {$variant eq "main" || $variant eq "parches"} {
    set rev [expr {$variant eq "main" ? "main" : "2f95eb8"}]
    foreach f $core {
        set out $tmp/$f
        spit $out [exec git show $rev:fpga/v9990/tiny9990/$f]
        lappend files $out
    }
} else {
    set p_pal 1; set p_eor 1; set p_r16 1
    switch $variant {
        nopal { set p_pal 0 }
        noeor { set p_eor 0 }
        nor16 { set p_r16 0 }
        none  { set p_pal 0; set p_eor 0; set p_r16 0 }
    }
    foreach f $core {
        if {$f ne "t9990.sv"} { lappend files v9990/tiny9990/$f; continue }
        set txt [slurp v9990/tiny9990/$f]
        set n 0
        incr n [regsub {(parameter\s+ENABLE_PAL\s+=\s+)1} $txt "\\1$p_pal" txt]
        incr n [regsub {(parameter\s+ENABLE_CURSOR_EOR\s+=\s+)1} $txt "\\1$p_eor" txt]
        incr n [regsub {(parameter\s+ENABLE_R16\s+=\s+)1} $txt "\\1$p_r16" txt]
        if {$n != 3} { error "no se encontraron los tres parametros ENABLE_* de T9990 ($n)" }
        set out $tmp/$f
        spit $out $txt
        lappend files $out
    }
}

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
add_file config/v9990.sv
add_file src/peripheral/ram/ram.sv
foreach f $files { add_file $f }
set_option -top_module T9990 -verilog_std sysv2017
set_option -output_base_name $base
puts "check_core: variante $variant -> impl/gwsynthesis/${base}_syn_rsc.xml"
run syn
