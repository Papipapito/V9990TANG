//*****************************************************************************
// v9990_megaram_xtal.sdc -- V9990TANG, configuracion v9990_megaram, variante xtal
//   CONFIG_BOARD::SYNC_CPU_CLK = 0: CLK_BASE = 27 MHz (cristal) x 4 = 108 MHz
//
// COPIA de v9990_xtal.sdc (mismas ordenes): la configuracion v9990_megaram
// (megaROM SCC-I con el scc.sv de tnCart, CONFIG::ENABLE_SCC = ENABLE) no
// anade ni quita relojes. El CLK_21M (CLKDIV u_clk/u_div_21m) solo lo usa el
// IKASCC (ENABLE_SCC = ENABLE_IKASCC, cartridge_megarom.sv): con scc.sv se poda,
// como en la build v9990_mega de referencia del estudio (CLKDIV 3/8, sin
// CLK_21M entre los PRIMARY de su .rpt.txt). Al llegar la fusion con
// hito/megaram, comprobar en el .rpt.txt de la primera build que CLKDIV sigue
// en 3/8 y que no aparece ningun reloj nuevo; si apareciera CLK_21M, hay que
// declararlo y meterlo en el grupo de CLK_BASE (sin eso, TA2004 o cruces sin
// restringir). Cualquier cambio de v9990_xtal.sdc se copia aqui.
//
// Parte de board_wt200b_27M.sdc de tnCartWonder d3a54f1 (ver UPSTREAM.md).
// Cambios y por que (detalle en docs/ARCHITECTURE.md, "Cruces de reloj y .sdc"):
//  - CLK_21M no se declara: el CLKDIV u_div_21m se poda en esta configuracion
//    (sin SCC ni OPLL). Si una orden lo nombra, el P&R de Gowin 1.9.12 aborta
//    ("ERROR (TA2004) Cannot get clock with name 'CLK_21M'", comprobado). En la
//    build de referencia del estudio se borraron a mano las dos lineas que lo
//    nombraban, y una era el set_clock_groups: de ahi sus 290 endpoints de
//    setup y su recovery violados.
//  - DCLK (Video.DCLK) NO es asincrono de CLK_BASE: es la OR de dos flops de
//    CLK_BASE (cartridge_v9990.sv), y R/G/B se lanzan en el mismo flanco que
//    genera su flanco de subida. Va en el grupo de CLK_BASE con un modelo que
//    cae en la rejilla de 108 MHz, para que el STA vigile esa carrera.
//  - CLK_MEM_P, la salida desfasada 180 grados del rPLL base que va al pin de
//    reloj de la SDRAM, se declara y va con CLK_BASE (hoy no tiene caminos).
//  - CLK_5_4M entra en el grupo de 27 MHz.
// Cada nombre de -group tiene que existir en esta configuracion. Despues de
// cada build, todas las ordenes tienen que salir "Actived" en el .tr
// (tools/check_build.py lo comprueba).
//
// Hito 3 (recorte de la carcasa y POR) y 6 (guardia de lock): fuera el
// bootloader, la flash y los SPI, que no tenian reloj propio (iban en
// CLK_BASE): no desaparece ningun reloj y los grupos son los mismos. Entran
// dominios nuevos de 27 MHz (BOARD_WT200B_GUARD y STATUS_LED, en CLK_27M) y
// dos flops en CLK_DAC (reset del I2S); todos en el grupo de 27 MHz.
// Sincronizadores de los cruces nuevos (los corta el set_clock_groups):
//   CLK_BASE -> CLK_27M  u_guard/ready_ff (SYS_RESET_n), u_guard/wto_ff (WAIT_TIMEOUT)
//   rPLL     -> CLK_27M  u_guard/lock_ff (LOCK)
//   pin      -> CLK_27M  u_guard/sclk_ff (CART_CLOCK, solo dato en xtal)
//   CLK_27M  -> CLK_BASE u_rst/base_ff (PLL_OK: afirmacion asincrona, suelta sincrona)
//   CLK_BASE -> CLK_DAC  dac_reset_ff (RESET_n: afirmacion asincrona, suelta sincrona)
// DRIVE_EN_27 y BOOT_HOLD_27 (u_guard) solo van a pines, de forma
// combinacional: no tienen flop de destino.
//*****************************************************************************

//------------------------
// Entradas
//------------------------
// 27 MHz, cristal de la Tang Nano 20K
create_clock -name CLK_27M -period 37.037 -waveform {0 18.518} [get_ports {CLK_27M}] -add

// 3,58 MHz, reloj del slot. En xtal no es el reloj de ningun flop: solo entra
// como dato en el PIN_FILTER del bus (board_rev1_bus.sv), que lo sincroniza.
create_clock -name CLK_3_58M -period 279.330 -waveform {0 139.665} [get_ports {CART_CLOCK}] -add

//------------------------
// Base
//------------------------
// 108 MHz (CLK_BASE = CLK_27M x 4, rPLL u_clk/u_pll_base)
create_generated_clock -name CLK_BASE -source [get_ports {CLK_27M}] -master_clock CLK_27M -divide_by 1 -multiply_by 4 -add [get_nets {CLK_BASE}]

// 108 MHz a 180 grados (CLKOUTP del rPLL base, PSDA_SEL 1000): solo sale al
// pin O_sdram_clk (sdram.sv). Sincrono de CLK_BASE.
create_generated_clock -name CLK_MEM_P -source [get_ports {CLK_27M}] -master_clock CLK_27M -divide_by 1 -multiply_by 4 -offset 4.630 -add [get_pins {u_clk/u_pll_base/CLKOUTP}]

// Reloj de pixel del V9990 (Video.DCLK = dclk_en_ff[1] | dclk_en_ff[0]).
// Real: dos ciclos de CLK_BASE en alto cada 4 a 20 ciclos segun el modo, y
// cada flanco sale de un flanco de CLK_BASE. Modelo:
//  -divide_by 4: todos los flancos en la rejilla de 108 MHz y el intervalo
//   minimo real (4 ciclos, con C25M), asi que DCLK -> DCLK queda conservador;
//   el 50 % por defecto da 18,5 ns en alto, los dos ciclos reales.
//  -offset 8.2: hace de latencia de fuente. Gowin arranca DCLK con latencia 0
//   en la salida de la OR, mientras que CLK_BASE llega a los flops con 7,6 ns
//   (salida del rPLL y red) y el flop que genera DCLK suma 0,23 ns de tC2Q:
//   7,836 ns. 8,2 = 7,836 + 0,37, el LUT mas rapido del chip. Mientras ruta +
//   LUT hasta la OR sumen al menos 0,37 ns, el flanco modelado llega antes o a
//   la vez que el real y el setup de R/G/B (lanzados en el mismo flanco) queda
//   del lado seguro. Tiene que quedar por debajo de 9,259 ns.
create_generated_clock -name DCLK -source [get_nets {CLK_BASE}] -master_clock CLK_BASE -divide_by 4 -offset 8.2 -add [get_nets {Video.DCLK}]

//------------------------
// TMDS
//------------------------
// 135 MHz (CLK_TMDS_S = CLK_BASE x 5 / 4, rPLL u_clk/u_pll_tmds)
create_generated_clock -name CLK_TMDS_S -source [get_nets {CLK_BASE}] -master_clock CLK_BASE -divide_by 4 -multiply_by 5 -add [get_nets {CLK_TMDS_S}]

// 27 MHz (CLK_TMDS_P = CLK_TMDS_S / 5, CLKDIV u_clk/u_div_tmds)
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
// {CLK_TMDS_S CLK_TMDS_P}: mesocronos de CLK_BASE (misma frecuencia de fondo,
// fase distinta en cada arranque: el CLKDIV /5 sale de reset con el LOCK del
// segundo rPLL). Cruzan el buffer de lineas del upscan, in_reso (cuasiestatico),
// in_vs_n (un flop efectivo), FIELD, INTERLACE y el reset.
// {CLK_27M CLK_5_4M CLK_DAC}: el POR, el gestor del rPLL, la guardia de lock
// y el LED (CLK_27M) y el I2S (CLK_DAC); cruzan con CLK_BASE por los
// sincronizadores de la cabecera.
// {CLK_3_58M}: solo como dato, en el PIN_FILTER del bus y en u_guard/sclk_ff.
set_clock_groups -asynchronous -group [get_clocks {CLK_3_58M}] -group [get_clocks {CLK_BASE CLK_MEM_P DCLK}] -group [get_clocks {CLK_TMDS_S CLK_TMDS_P}] -group [get_clocks {CLK_27M CLK_5_4M CLK_DAC}]

//------------------------
// Excepciones
//------------------------
// reset_n (CLK_BASE, en u_rst: system/system_reset.sv) llega como CLEAR
// asincrono al lado de entrada del upscan (dominio DCLK) y como dato al CE de
// sus W_DATA. Cuando reset_n se suelta, DCLK esta parado: SYS_RESET_n
// (SYSTEM_RESET_HOLD, main.sv) se suelta como pronto un ciclo despues, asi que
// en ese flanco el V9990 sigue en reset, y con el core en reset DCLK_EN vale 0.
set_false_path -from [get_regs {u_rst/reset_n_s0}] -to [get_clocks {DCLK}]

//------------------------
// Informes
//------------------------
// Un report_timing en el .sdc sustituye la tabla por defecto de su tipo en el
// .tr; con varios, Gowin los numera ([1], [2]...). Primero los globales (los
// de por defecto), luego los de DCLK:
//  - DCLK -> CLK_BASE: hoy no hay ninguno ("Nothing to report!"); si aparece
//    alguno, el -offset de DCLK lo haria optimista y hay que revisarlo.
//  - CLK_BASE -> DCLK: la carrera de R/G/B, HS/VS y RESO hacia video_* en
//    cartridge_v9990.sv; su slack (modelo lento) es el margen de la captura.
report_timing -setup -max_paths 25 -max_common_paths 1
report_timing -hold -max_paths 25 -max_common_paths 1
report_timing -setup -from_clock [get_clocks {DCLK}] -to_clock [get_clocks {CLK_BASE}] -max_paths 10
report_timing -setup -from_clock [get_clocks {CLK_BASE}] -to_clock [get_clocks {DCLK}] -max_paths 50
report_timing -hold -from_clock [get_clocks {CLK_BASE}] -to_clock [get_clocks {DCLK}] -max_paths 50
