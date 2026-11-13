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
# Barrido de la primera build (docs/notas/nextor.md): place 0 / route 2 da
# 107,69 MHz (falla); place 0 / route 1, 112,39 MHz, setup +0,414 ns
# 0.3beta (docs/notas/zynqfix.md): place 0 / route 1 da 108,88 MHz (falla por
# poco; 0 endpoints violados); place 0 / route 0 107,52, place 0 / route 2
# 107,60, place 1 / route 2 y place 2 / route 2 108,20; place 2 / route 1,
# 112,96 MHz (pasa)
set BUILD_OPTS {-place_option 2 -route_option 1}
source build_common.tcl
