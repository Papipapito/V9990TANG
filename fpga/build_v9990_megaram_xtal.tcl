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
# Barrido del 27/10/2026, primera build de la configuracion (d3444d9,
# docs/notas/fusion.md): con las opciones del hito 1 (place 2, route 1) la
# Fmax de CLK_BASE sale a 108,04 MHz y con -map_option 2, place 2 y route 0 a
# 108,93: no pasan. Place 2 y route 2 pasa justo (111,38 MHz, setup +0,281
# ns); place 0 y route 2, con margen: Fmax 122,96 MHz, setup y carrera
# CLK_BASE -> DCLK +1,119 ns, CLS 9 046 (por debajo del aviso de 9 250).
set BUILD_OPTS {-place_option 0 -route_option 2}
source build_common.tcl
