# ============================================================================
#  check_bus.tcl -- V9990TANG, hito 5 (bus y /WAIT): comprobacion de sintesis
#  y de timing de la configuracion v9990 (variante xtal) con el RTL del bus de
#  este arbol. NO es la build de un hito ni un bitstream para la placa.
#
#  Uso:  cd fpga && gw_sh check_bus.tcl
#        -> impl/pnr/check_bus.rpt.txt / .tr, impl/gwsynthesis/check_bus_syn_rsc.xml
#  Recuento por modulo frente a otra sintesis (desde fpga/):
#        python3 tb/bus/syn_rsc.py impl/gwsynthesis/check_bus_syn_rsc.xml
#                <otro>_syn_rsc.xml u_bus u_v9990
#  Puerta: tools/check_build.py con --parcial (docs/notas/bus.md, "Sintesis").
#
#  Desde la fusion de las areas (hito/fusion) el top conecta de verdad las
#  entradas nuevas de BOARD_REV1_BUS (DRIVE_EN, BOOT_HOLD, WAIT_TIMEOUT y
#  BUS_OK, con la guardia de lock de hito/integ), asi que el parche al vuelo
#  del top de main que llevaba este fichero sobra y se quita, y la lista de
#  ficheros y el .sdc son los de build_common.tcl (los de
#  build_v9990_xtal.tcl) con las opciones de P&R del hito 1. Se quitan
#  tambien los modos CHECK_BUS_REF (el bus de main sobre el top de main) y
#  CHECK_BUS_NOPATCH (el top sin conectar): con el top fusionado ninguno de
#  los dos elabora. Sus cifras, de antes de la fusion, estan en
#  docs/notas/bus.md; la referencia se puede volver a medir compilando
#  build_v9990_xtal.tcl en un worktree de main (impl/gwsynthesis/
#  v9990_xtal_syn_rsc.xml).
# ============================================================================
foreach v {CHECK_BUS_REF CHECK_BUS_NOPATCH} {
    if {[info exists ::env($v)] && $::env($v) ne "" && $::env($v) ne "0"} {
        puts "ERROR: check_bus.tcl: $v ya no existe desde la fusion (ver la cabecera)"
        exit 1
    }
}
set CFG        v9990
set VARIANT    xtal
set OUT_NAME   check_bus
set BUILD_OPTS {-place_option 2 -route_option 1}
source build_common.tcl
