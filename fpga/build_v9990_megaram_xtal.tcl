# ============================================================================
#  build_v9990_megaram_xtal.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram (V9990 + megaROM SCC-I con SCC en el slot
#  expandido), variante xtal (108,000 MHz del cristal).
#
#  HASTA LA FUSION CON hito/megaram ESTA BUILD SE PARA AL EMPEZAR: faltan
#  src/peripheral/msx/megarom_clear.sv y config/v9990_megaram.sv (y hay que
#  descomentar `define HAVE_MEGAROM_CLEAR en src/main.sv).
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_xtal.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram
set VARIANT xtal
source build_common.tcl
