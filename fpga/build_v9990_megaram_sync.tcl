# ============================================================================
#  build_v9990_megaram_sync.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram (V9990 + megaROM SCC-I con SCC en el slot
#  expandido), variante sync (reloj del slot x 30 = 107,386 MHz).
#
#  HASTA LA FUSION CON hito/megaram ESTA BUILD SE PARA AL EMPEZAR: faltan
#  src/peripheral/msx/megarom_clear.sv y config/v9990_megaram.sv (y hay que
#  descomentar `define HAVE_MEGAROM_CLEAR en src/main.sv).
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_sync.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram
set VARIANT sync
source build_common.tcl
