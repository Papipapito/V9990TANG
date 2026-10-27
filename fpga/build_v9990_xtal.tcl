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
# Barrido del 27/10/2026 sobre el RTL fusionado de las seis areas (d3444d9,
# docs/notas/fusion.md): el juego anterior (-map_option 2, place 2, route 0;
# el del barrido del 26/10 sobre f00c622) da Fmax 108,12 MHz y no pasa; con
# route 0 ninguna opcion de sintesis ni de colocacion llega a 109 MHz, y con
# route 2 pasan todas las probadas. Place 2 y route 2 es el de mas margen:
# Fmax 119,48 MHz, setup y carrera CLK_BASE -> DCLK +0,692 ns.
set BUILD_OPTS {-place_option 2 -route_option 2}
source build_common.tcl
