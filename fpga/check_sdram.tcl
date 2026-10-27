# ============================================================================
#  check_sdram.tcl -- comprobacion de sintesis del hito 4 (refresco y SDRAM) sobre V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990 (solo el V9990 con su VDP de comandos), variante xtal:
#  CLK_BASE = 108,000 MHz del cristal de 27 MHz (CONFIG_BOARD::SYNC_CPU_CLK = 0).
#
#  Uso:  cd fpga && gw_sh check_sdram.tcl   (solo sintesis; recursos por modulo en
#        impl/gwsynthesis/check_sdram_syn_rsc.xml)
#
#  Desde la fusion de las areas (hito/fusion) la lista de ficheros y las
#  opciones son las de build_common.tcl (las de build_v9990_xtal.tcl, con la
#  guardia, system_reset.sv y sin bootloader, flash ni SPI): antes este
#  fichero llevaba la lista del hito 1, que ya no elabora (falta
#  board_wt200b_config.sv).
#
#  gw_sh (Gowin 1.9.12.03) no abre ficheros con rutas de mas de 260
#  caracteres: el repositorio tiene que estar en una ruta corta.
# ============================================================================
set CFG       v9990
set VARIANT   xtal
set OUT_NAME  check_sdram
set RUN_STEPS {syn}
source build_common.tcl
