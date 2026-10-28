# ============================================================================
#  build_v9990_megaram_nextor_sync.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram_nextor (V9990 + megaROM SCC-I con SCC + Nextor
#  con la microSD de la Tang, en el slot expandido), variante sync (107,386 MHz: reloj del slot x30).
#
#  Compila lo de build_v9990_megaram_sync.tcl mas CARTRIDGE_NEXTOR,
#  TF_CONTROLLER, NEXTOR_LOADER, FLASH_SPI y los dos SPI
#  (config/v9990_megaram_nextor.sv, docs/notas/nextor.md).
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_nextor_sync.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram_nextor
set VARIANT sync
# Opciones de P&R: las del barrido de la primera build (docs/notas/nextor.md)
set BUILD_OPTS {-place_option 0 -route_option 2}
source build_common.tcl
