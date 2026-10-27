# ============================================================================
#  build_v9990_megaram_sync.tcl -- V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990_megaram (V9990 + megaROM SCC-I con SCC en el slot
#  expandido), variante sync (reloj del slot x 30 = 107,386 MHz).
#
#  Desde la fusion de las areas (hito/fusion) compila MEGAROM_CLEAR en lugar
#  del bootloader (`define HAVE_MEGAROM_CLEAR en src/main.sv), con el /WAIT de
#  memoria de la megaROM (CONFIG::ENABLE_MEM_WAIT) y el pre-WAIT de memoria
#  del bus (CONFIG::BUS_PREWAIT_MEM_EN), los dos a 1 en config/v9990_megaram.sv.
#
#  Uso:  cd fpga && gw_sh build_v9990_megaram_sync.tcl
#  Ficheros, opciones y comprobaciones comunes: build_common.tcl.
# ============================================================================
set CFG     v9990_megaram
set VARIANT sync
# Barrido del 27/10/2026, primera build de la configuracion (d3444d9,
# docs/notas/fusion.md): pasa con las opciones del hito 1 (place 2, route 1):
# Fmax 120,19 MHz, setup +0,992 ns, carrera CLK_BASE -> DCLK +1,316 ns.
# Con la guardia revisada (c8e4fd2), place 2 / route 1 da 109,50 MHz (al
# limite); place 2 / route 2 da 125,93 MHz y setup +1,095 ns (place 0 /
# route 2: 119,29 MHz), y tarda bastante menos.
set BUILD_OPTS {-place_option 2 -route_option 2}
source build_common.tcl
