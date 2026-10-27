# ============================================================================
#  build_v9990_megaram_xtal.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram (V9990 + megaROM SCC-I con SCC en el slot
#  expandido), variante xtal (108,000 MHz del cristal).
#
#  Desde la fusion de las areas (hito/fusion) compila MEGAROM_CLEAR en lugar
#  del bootloader (`define HAVE_MEGAROM_CLEAR en src/main.sv), con el /WAIT de
#  memoria de la megaROM (CONFIG::ENABLE_MEM_WAIT) y el pre-WAIT de memoria
#  del bus (CONFIG::BUS_PREWAIT_MEM_EN), los dos a 1 en config/v9990_megaram.sv.
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_xtal.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram
set VARIANT xtal
source build_common.tcl
