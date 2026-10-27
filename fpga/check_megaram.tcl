# ============================================================================
#  check_megaram.tcl -- V9990TANG, comprobacion de sintesis y timing del area
#  megaram (hito 8): la configuracion v9990_megaram, variante xtal.
#
#  Uso:  cd fpga && gw_sh check_megaram.tcl
#        -> impl/pnr/check_megaram.rpt.txt y .tr,
#           impl/gwsynthesis/check_megaram_syn_rsc.xml
#  No es la build de ningun bitstream: solo mide recursos y timing.
#
#  Desde la fusion de las areas (hito/fusion) es la build
#  build_v9990_megaram_xtal.tcl con otro nombre de salida y las opciones de
#  P&R del hito 1: la lista de ficheros y el .sdc (v9990_megaram_xtal.sdc)
#  son los de build_common.tcl, y main.sv instancia MEGAROM_CLEAR en lugar
#  del bootloader. La referencia de antes de la fusion (main.sv de main, con
#  el bootloader de tnCart: v9990_mega del estudio, 9 111 CLS / 29 BSRAM)
#  esta en docs/notas/megaram.md.
# ============================================================================
set CFG        v9990_megaram
set VARIANT    xtal
set OUT_NAME   check_megaram
set BUILD_OPTS {-place_option 2 -route_option 1}
source build_common.tcl
