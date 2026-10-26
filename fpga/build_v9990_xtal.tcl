# ============================================================================
#  build_v9990_xtal.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990 (solo el V9990 con su VDP de comandos, sin slot
#  expandido), variante xtal: CLK_BASE = 108,000 MHz del cristal de 27 MHz
#  (board_wt200b_config_xtal.sv, CONFIG_BOARD::SYNC_CPU_CLK = 0).
#
#  Uso:  cd fpga && gw_sh build_v9990_xtal.tcl
#        -> impl/pnr/v9990_xtal.{fs,bin,rpt.txt,tr,sdf}, logs en impl/
#        Puerta: python tools/check_build.py ... (docs/notas/integ.md)
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990
set VARIANT xtal
# Barrido del 26/10/2026 sobre el RTL de f00c622 (docs/notas/integ.md,
# seccion 6): con las opciones del hito 1 la carrera CLK_BASE -> DCLK sale a
# -0,077 ns; con -map_option 2 (mapeo LUT5 sin mas LUT), place 2 y route 0
# pasa la puerta (Fmax 109,15 MHz, carrera +0,106 ns).
set BUILD_OPTS {-map_option 2 -place_option 2 -route_option 0}
source build_common.tcl
