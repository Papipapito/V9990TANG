# ============================================================================
#  build_v9990_sync.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990 (solo el V9990 con su VDP de comandos, sin slot
#  expandido), variante sync: CLK_BASE = reloj del slot (CART_CLOCK,
#  3,579545 MHz) x 30 = 107,386 MHz (board_wt200b_config_sync.sv,
#  CONFIG_BOARD::SYNC_CPU_CLK = 1). Sin MSX encendido no hay CLK_BASE ni HDMI.
#
#  Uso:  cd fpga && gw_sh build_v9990_sync.tcl
#        -> impl/pnr/v9990_sync.{fs,bin,rpt.txt,tr,sdf}, logs en impl/
#        Puerta: python tools/check_build.py ... (docs/notas/integ.md)
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990
set VARIANT sync
# Barrido del 27/10/2026 sobre el RTL fusionado de las seis areas (d3444d9,
# docs/notas/fusion.md): el juego anterior (place 0, route 1; el del barrido
# del 26/10 sobre f00c622) da Fmax 107,91 MHz y no pasa; place 0 y route 2
# pasa con poco margen (114,81 MHz, setup y carrera +0,134 ns) y place 2 y
# route 2 con mas: Fmax 114,37 MHz, setup +0,569 ns, carrera CLK_BASE -> DCLK
# +1,223 ns.
set BUILD_OPTS {-place_option 2 -route_option 2}
source build_common.tcl
