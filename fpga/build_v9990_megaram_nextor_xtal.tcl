# ============================================================================
#  build_v9990_megaram_nextor_xtal.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram_nextor (V9990 + megaROM SCC-I con SCC + Nextor
#  con la microSD de la Tang, en el slot expandido), variante xtal (108,000 MHz del cristal).
#
#  Compila lo de build_v9990_megaram_xtal.tcl mas CARTRIDGE_NEXTOR,
#  TF_CONTROLLER, NEXTOR_LOADER, FLASH_SPI y los dos SPI
#  (config/v9990_megaram_nextor.sv, docs/notas/nextor.md).
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_nextor_xtal.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram_nextor
set VARIANT xtal
# Barrido de la primera build (docs/notas/nextor.md): place 0 / route 2 y
# place 2 / route 2 dan 110,11 MHz, place 0 / route 1 110,07; place 2 /
# route 1 (las del hito 1), 113,45 MHz y setup +0,444 ns
set BUILD_OPTS {-place_option 2 -route_option 1}
source build_common.tcl
