//*****************************************************************************
// v9990_megaram_sync.sdc -- V9990TANG, configuracion v9990_megaram, variante sync
//   CONFIG_BOARD::SYNC_CPU_CLK = 1: CLK_BASE = reloj del slot (CART_CLOCK,
//   3,579545 MHz) x 30 = 107,386 MHz
//
// COPIA de v9990_sync.sdc (mismas ordenes): la configuracion v9990_megaram
// (megaROM SCC-I con el scc.sv de tnCart, CONFIG::ENABLE_SCC = ENABLE) no
// anade ni quita relojes. El CLK_21M (CLKDIV u_clk/u_div_21m) solo lo usa el
// IKASCC (ENABLE_SCC = ENABLE_IKASCC, cartridge_megarom.sv): con scc.sv se poda,
// como en la build v9990_mega de referencia del estudio (CLKDIV 3/8, sin
// CLK_21M entre los PRIMARY de su .rpt.txt). Al llegar la fusion con
// hito/megaram, comprobar en el .rpt.txt de la primera build que CLKDIV sigue
// en 3/8 y que no aparece ningun reloj nuevo; si apareciera CLK_21M, hay que
// declararlo y meterlo en el grupo de CLK_BASE (sin eso, TA2004 o cruces sin
// restringir). Cualquier cambio de v9990_sync.sdc se copia aqui.
//
// Mismo modelo que v9990_xtal.sdc (ver alli y docs/ARCHITECTURE.md, "Cruces de
// reloj y .sdc"); cambia el reloj de referencia del rPLL base. Frente a
// board_wt200b_3_58M.sdc de tnCartWonder d3a54f1:
//  - CLK_3_58M con el periodo del cristal de color NTSC (279,365 ns =
//    3,579545 MHz; tnCart ponia 279,330, 3,58 MHz), de modo que CLK_BASE sale
//    a 9,312 ns / 107,386 MHz
//  - sin CLK_21M (se poda, como en xtal)
//  - DCLK en el grupo de CLK_BASE, -divide_by 4, con el -offset recalculado
//    para 9,312 ns y la latencia del rPLL de esta variante (ver DCLK abajo)
//  - CLK_MEM_P declarado (CLKOUTP del rPLL base, 180 grados)
//  - CLK_5_4M en el grupo de 27 MHz
//  - CLK_3_58M sigue en un grupo propio aunque CLK_BASE sale de el: el
//    set_clock_groups no rompe la relacion de reloj generado (periodo y
//    latencia de CLK_BASE siguen saliendo de CLK_3_58M), solo corta caminos
//    de datos, y los unicos que salen de CLK_3_58M son el pin usado como
//    dato en dos muestreadores asincronos: el PIN_FILTER u_clock del bus
//    (CLK_BASE) y u_guard/sclk_ff (CLK_27M). Analizar el del bus como sincrono
//    seria medir una carrera de un pin contra el reloj que el rPLL saca de el
//    mismo, que el filtro de dos muestras ya trata como asincrona.
// Cada nombre de -group tiene que existir en esta configuracion. Despues de
// cada build, todas las ordenes tienen que salir "Actived" en el .tr
// (tools/check_build.py lo comprueba).
//
// Dominios de 27 MHz (BOARD_WT200B_GUARD, STATUS_LED: CLK_27M) y el reset del
// I2S (CLK_DAC), en el grupo de 27 MHz. Sincronizadores de los cruces (los
// corta el set_clock_groups):
//   CLK_BASE -> CLK_27M  u_guard/ready_ff (SYS_RESET_n), u_guard/wto_ff (WAIT_TIMEOUT)
//   rPLL     -> CLK_27M  u_guard/lock_ff (LOCK)
//   pin      -> CLK_27M  u_guard/sclk_ff (CART_CLOCK: presencia y frecuencia del reloj del slot)
//   CLK_27M  -> CLK_BASE u_rst/base_ff (PLL_OK: afirmacion asincrona, suelta sincrona)
//   CLK_BASE -> CLK_DAC  dac_reset_ff (RESET_n: afirmacion asincrona, suelta sincrona)
// DRIVE_EN_27 y BOOT_HOLD_27 (u_guard) solo van a pines, de forma
// combinacional: no tienen flop de destino.
//*****************************************************************************

//------------------------
// Entradas
//------------------------
// 27 MHz, cristal de la Tang Nano 20K: POR, guardia, LED y DAC
create_clock -name CLK_27M -period 37.037 -waveform {0 18.518} [get_ports {CLK_27M}] -add

// 3,579545 MHz, reloj del slot: referencia del rPLL base. Pin 76 (IOT30[B],
// GCLKC_1): no es entrada dedicada de PLL; el P&R lo lleva al rPLL (PLL_L[1])
// por enrutado generico (aviso PR1014 sobre CART_CLOCK_d en el log)
create_clock -name CLK_3_58M -period 279.365 -waveform {0 139.683} [get_ports {CART_CLOCK}] -add

//------------------------
// Base
//------------------------
// 107,386 MHz (CLK_BASE = CLK_3_58M x 30, rPLL u_clk/u_pll_base)
create_generated_clock -name CLK_BASE -source [get_ports {CART_CLOCK}] -master_clock CLK_3_58M -divide_by 1 -multiply_by 30 -add [get_nets {CLK_BASE}]

// 107,386 MHz a 180 grados (CLKOUTP del rPLL base, PSDA_SEL 1000): solo sale
// al pin O_sdram_clk (sdram.sv). Sincrono de CLK_BASE.
create_generated_clock -name CLK_MEM_P -source [get_ports {CART_CLOCK}] -master_clock CLK_3_58M -divide_by 1 -multiply_by 30 -offset 4.656 -add [get_pins {u_clk/u_pll_base/CLKOUTP}]

// Reloj de pixel del V9990 (Video.DCLK = dclk_en_ff[1] | dclk_en_ff[0]):
// el modelo de v9990_xtal.sdc. -offset = latencia de CLK_BASE hasta el flop
// que genera DCLK + su tC2Q + el LUT mas rapido del chip (sin la ruta hasta la
// OR, que queda de margen); tiene que quedar por debajo de 9,312 ns y no por
// encima del flanco real del SDF (tools/check_build.py, punto 6). En sync la
// latencia del rPLL es otra que en xtal: la build de prueba del 25/10/2026
// con el 8,2 de xtal dio en el modelo lento rPLL 4,686 (frente a 5,329 en
// xtal) + red 2,274 + tC2Q 0,232 + LUT 0,371 = 7,563 ns (+ ruta a la OR 0,161
// = 7,724 de flanco real): con 8,2 el modelo iba 0,476 ns por detras del
// flanco real y la puerta fallaba. 7,55 = 7,563 redondeado hacia abajo, como
// el 8,2 de xtal (docs/notas/integ.md).
create_generated_clock -name DCLK -source [get_nets {CLK_BASE}] -master_clock CLK_BASE -divide_by 4 -offset 7.55 -add [get_nets {Video.DCLK}]

//------------------------
// TMDS
//------------------------
// 134,23 MHz (CLK_TMDS_S = CLK_BASE x 5 / 4, rPLL u_clk/u_pll_tmds)
create_generated_clock -name CLK_TMDS_S -source [get_nets {CLK_BASE}] -master_clock CLK_BASE -divide_by 4 -multiply_by 5 -add [get_nets {CLK_TMDS_S}]

// 26,85 MHz (CLK_TMDS_P = CLK_TMDS_S / 5, CLKDIV u_clk/u_div_tmds)
create_generated_clock -name CLK_TMDS_P -source [get_nets {CLK_TMDS_S}] -master_clock CLK_TMDS_S -divide_by 5 -multiply_by 1 -add [get_pins {u_clk/u_div_tmds/CLKOUT}]

//------------------------
// DAC
//------------------------
// 5,4 MHz (CLK_5_4M = CLK_27M / 5, CLKDIV u_clk/u_div_5p4m)
create_generated_clock -name CLK_5_4M -source [get_ports {CLK_27M}] -master_clock CLK_27M -divide_by 5 -multiply_by 1 -add [get_pins {u_clk/u_div_5p4m/CLKOUT}]

// 1,543 MHz (CLK_DAC = CLK_27M x 2 / 35 = CLK_5_4M / 3,5 ~ 32 x 48 kHz)
create_generated_clock -name CLK_DAC -source [get_ports {CLK_27M}] -master_clock CLK_27M -divide_by 35 -multiply_by 2 -add [get_pins {u_clk/u_div_dac/CLKOUT}]

//------------------------
// Grupos asincronos
//------------------------
// {CLK_3_58M}: referencia del rPLL base; como dato solo en los dos
// muestreadores de la cabecera.
// {CLK_TMDS_S CLK_TMDS_P}: mesocronos de CLK_BASE, como en xtal.
// {CLK_27M CLK_5_4M CLK_DAC}: el POR, el gestor del rPLL, la guardia de lock
// y el LED (CLK_27M) y el I2S (CLK_DAC). En sync son asincronos de verdad de
// CLK_BASE (otro cristal).
set_clock_groups -asynchronous -group [get_clocks {CLK_3_58M}] -group [get_clocks {CLK_BASE CLK_MEM_P DCLK}] -group [get_clocks {CLK_TMDS_S CLK_TMDS_P}] -group [get_clocks {CLK_27M CLK_5_4M CLK_DAC}]

//------------------------
// Excepciones
//------------------------
// reset_n (u_rst) hacia el lado de entrada del upscan (DCLK): como en xtal,
// DCLK esta parado cuando reset_n se suelta.
set_false_path -from [get_regs {u_rst/reset_n_s0}] -to [get_clocks {DCLK}]

//------------------------
// Informes
//------------------------
// Los mismos que en xtal: primero los globales (los de por defecto), luego
// los de DCLK.
report_timing -setup -max_paths 25 -max_common_paths 1
report_timing -hold -max_paths 25 -max_common_paths 1
report_timing -setup -from_clock [get_clocks {DCLK}] -to_clock [get_clocks {CLK_BASE}] -max_paths 10
report_timing -setup -from_clock [get_clocks {CLK_BASE}] -to_clock [get_clocks {DCLK}] -max_paths 50
report_timing -hold -from_clock [get_clocks {CLK_BASE}] -to_clock [get_clocks {DCLK}] -max_paths 50
