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
source build_common.tcl
