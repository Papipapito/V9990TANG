# Hitos 3 y 6: recorte de la carcasa, POR, guardia de lock y variantes de reloj

Rama `hito/integ`, desde `main` (`20936e6`, hito 1). Ficheros propios:
`fpga/src/main.sv`, `fpga/src/tnCart_board_wt200b_top.sv`,
`fpga/src/board/wt200b/board_wt200b_clock.sv`,
`fpga/src/board/wt200b/board_wt200b_config_{xtal,sync}.sv`,
`fpga/src/peripheral/led.sv` (solo se añade `STATUS_LED`), los módulos nuevos
`fpga/src/board/wt200b/board_wt200b_guard.sv`,
`fpga/src/board/wt200b/board_wt200b_bus_guard.sv`,
`fpga/src/system/system_reset.sv` y `fpga/src/system/megarom_xfer_tie.sv`, los
`.sdc` de `fpga/constraints/`, los `fpga/build_*.tcl`, `tools/check_build.py`,
el banco `fpga/tb/integ/` y la evidencia de `fpga/reports/hito3/` y
`fpga/reports/hito6/`.

Todo se compila con el core, el bus, la SDRAM, la megaROM y el vídeo de `main`
(los de las otras áreas llegan en la fusión). **Nada de esto se ha probado en
la placa.** Las dos builds de MegaRAM no se pueden compilar en esta rama (les
faltan ficheros de `hito/megaram`); ver la sección 6 y el ensayo de la
sección 8.

## Resultados

Gowin 1.9.12.03, GW2AR-LV18QN88C8/I7, place 2, route 1, el mismo árbol en las
dos variantes. Las dos pasan la puerta (`PUERTA: PASA`, salida completa en
`fpga/reports/hito3/check_build.txt` y `fpga/reports/hito6/check_build.txt`).

| | Hito 1 (`v9990_xtal`) | **Hito 3: `v9990_xtal`** | **Hito 6: `v9990_sync`** |
|---|---|---|---|
| CLK_BASE | 108,000 MHz (27 x 4) | 108,000 MHz | 107,386 MHz (reloj del slot x 30) |
| Lógica (LUT + ALU) | 14 140 (11 551 + 2 589) | **13 258** (10 663 + 2 595): **−882** (−6,2 %) | 13 124 (10 518 + 2 606) |
| Registros | 6 173 | 5 780 (−393) | 5 805 |
| CLS | 8 679 (84 %) | **8 189 (79 %): −490** (−5,6 %) | 8 180 (79 %) |
| BSRAM | 24/46 | 24/46 | 24/46 |
| rPLL / CLKDIV / PRIMARY / LW | 2/2, 3/8, 8/8, 7/8 | 2/2, 3/8, 8/8, 7/8 | 2/2, 3/8, 8/8, 7/8 |
| `set_clock_groups` | Actived | Actived (16 órdenes, todas activas) | Actived (16 órdenes, todas activas) |
| Endpoints violados: setup / hold | 0 / 0 | 0 / 0 | 0 / 0 |
| Peor slack: setup / hold | +0,092 / +0,074 ns | +0,184 / +0,076 ns | +0,187 / +0,074 ns |
| Peor slack: recovery / removal | +5,990 / +0,460 ns | +5,224 / +0,451 ns | +4,870 / +0,451 ns |
| **Fmax CLK_BASE** (≥ 109) | 109,08 MHz | **110,19 MHz** | **109,59 MHz** |
| Carrera CLK_BASE → DCLK (setup / hold) | +1,912 / +4,351 ns | +0,847 / +4,241 ns | **+0,277** / +4,877 ns |
| Modelo de DCLK (`-offset` / flanco real del SDF) | 8,2 / 8,362 ns | 8,2 / 8,362 ns (+0,162) | 7,55 / 7,724 ns (+0,174) |
| Fmax DCLK / CLK_TMDS_P / CLK_27M | 146,4 / 65,9 / — MHz | 142,9 / 70,0 / 177,1 MHz | 131,6 / 64,4 / 168,8 MHz |
| Avisos (síntesis; P&R) | CV0016 x2, NL0002 x6; PR1014 x1 | CV0016 x3, NL0002 x5; PR1014 x1 | CK3000 x3, CV0016 x3, NL0002 x5; PR1014 x2 |

- El peor camino de setup sigue siendo del blitter en las dos
  (`u_blit/state_5` → `ENQUEUE_DATA_*/CE`, `SRC_NX_*`): la Fmax es la del
  core, como en el hito 1.
- **La carrera CLK_BASE → DCLK de `sync` tiene poco margen** (+0,277 ns,
  `u_sel/OUT_4` → `video_b_7`, 3,259 ns de datos frente a 2,883 en `xtal`): es
  colocación. Como el flanco real de DCLK llega 0,174 ns después que el
  modelado, el margen real en el modelo lento es algo mayor; hay que vigilarlo
  cuando entren los parches del core (`hito/core`) y el arreglo de `DCLK` de
  `hito/bus`.
- Los avisos, leídos uno a uno: `CV0016` son las tres entradas sin carga
  (`mspi_miso`, `TF_DAT0`, `UART_RX`); `NL0002` son `EXPANSION_RAM`, los dos
  `SOUND_MIXER` y sus `LIMITER_FF`, barridos porque en `v9990` no hay ningún
  cliente en el canal 0 del UMA ni sonido (en el hito 1 había uno más, el SPI
  de la TF); `PR1014` sobre `CLK_27M_d` es el del hito 1 (el CLKDIV de 5,4 MHz
  se alimenta por enrutado genérico). En `sync`, además: `PR1014` sobre
  `CART_CLOCK_d` (sección 2) y tres `CK3000` de síntesis ("Can't calculate
  clocks' relationship": CLK_BASE con CLK_DAC, CART_CLOCK con CLK_27M y DCLK
  con CLK_TMDS_P): relojes de cristales distintos, o de otro rPLL, cuyos cruces
  son los asíncronos que corta el `set_clock_groups` (la síntesis no lee el
  `.sdc`; el STA del P&R sí). Ningún `TA*` en ninguna de las dos.
- El *placement* del hito 3 no es el del hito 1, así que la Fmax (+1,1 MHz) y
  los slacks cambian por colocación además de por el recorte.

## 1. Recorte de la carcasa (hito 3)

- **Fuera**: `BOOTLOADER` (y con él `FLASH_SPI`, los dos `SPI` y el
  `XFER_IF` que servía), el LED de tnCart, la UART y los cartuchos que ninguna
  configuración de V9990TANG elabora (FM, Nextor, mapper, PSG). Una
  configuración que active alguno no elabora
  (`MAIN_CONFIGURACION_NO_SOPORTADA_EN_V9990TANG`).
- **Sin slot expandido en `v9990`**: `CARTRIDGE_V9990` va directo al `Bus`
  (generate por `CONFIG::ENABLE_MEGAROM`), como un GFX9000: solo los puertos
  60h-6Fh, sin registro `FFFFh` ni subranuras (`cartridge_v9990.sv` solo mira
  `IORQ_n` y `ADDR[7:4]`). Con megaROM se mantiene el `EXPANSION_SLOT` de
  tnCart (megaROM en la subranura 0, el V9990 como puerto solo de E/S en
  `Secondary[5]`). Quitar el slot quita también sus dos etapas de flops
  (`SLOT_EXPANSION_USES_FF = 1`: una hacia el cartucho y otra hacia el MSX): en
  `v9990` el /WAIT y los datos del V9990 llegan al pin dos ciclos antes que en
  el hito 1 (lo tiene que medir el banco de bus de `hito/bus`).
- **POR en lugar de `BOOT_n`**: la cadena es
  `PLL_OK` (guardia, 27 MHz) → 2 FF → `BASE_READY` (reset de la SDRAM y del
  rPLL TMDS) → `RESET_n` = `BASE_READY` y `READY` de `sdram.sv` →
  `SYS_RESET_n` = `RESET_n` retenido por `HOLD` (`SYSTEM_RESET_HOLD`, en
  `main.sv`). Todas las afirmaciones son asíncronas y las sueltas síncronas a
  `CLK_BASE`; `SYS_RESET_n` sube como pronto un ciclo después de `RESET_n`,
  que es lo que mantiene seguro el *false path* de `u_rst/reset_n_s0` hacia
  `DCLK`. En el `.tr` el reset de los cartuchos sale de
  `u_main/u_sysrst/SYS_RESET_n_s0` (peor recovery +5,224 ns en `xtal`).
- **MegaRAM**: `HOLD = !DONE` de `MEGAROM_CLEAR` (32 KB de la ventana). El
  hueco está en `main.sv` tras `` `define HAVE_MEGAROM_CLEAR ``, conectado a
  `ExpRam[RAM_BOOTLOADER]` (el canal que usaba el borrado del bootloader, el
  canal 0 del UMA, base 0) con `CLEAR_ADDR = CONFIG::RAM_ADDR_MEGAROM` y
  `CLEAR_SIZE = 32768`. Sin la macro la configuración MegaRAM no elabora; el
  `build_common.tcl` lo detecta antes y para con un mensaje.
- **`SYS_RESET_n` ya no baja con el /RESET del MSX.** En tnCart el bootloader
  bajaba `READY` en cada /RESET (estado `STATE_COMPLETE` → `STATE_WAIT_BOOT`),
  así que todos los cartuchos recibían un reset completo. Ahora cada cartucho
  ve `Bus.RESET_n` por su cuenta: el V9990 se resetea igual
  (`T9990.RESET_n = RESET_n && Bus.RESET_n`), el registro `FFFFh` del slot
  también, y la megaROM pasa por su rama `!Bus.RESET_n` de
  `megarom_configure.sv`. Es un cambio de comportamiento que `hito/megaram`
  tiene que validar (sección 8).
- **Pines sin uso, en reposo** (top): flash del bitstream `mspi_cs` = 1
  (deseleccionada), `mspi_hold` = 1 (inactivo), `mspi_sclk` = `mspi_mosi` = 0,
  `mspi_miso` sin carga; TF `TF_DAT3` (/CS) = 1, `TF_SCLK` = 0, `TF_CMD` = 1
  (reposo de MOSI), `TF_DAT1`/`TF_DAT2` en alta impedancia con el pull-up del
  `.cst`, `TF_DAT0` sin carga; `UART_TX` = 1 (reposo), `UART_RX` sin carga.
  Los tres `CV0016` de síntesis son esas entradas.

### Ahorro medido

Frente a la build del hito 1: **−882 de lógica, −393 registros, −490 CLS, 0
BSRAM**, con la guardia, el POR y el LED nuevos ya dentro. El estudio esperaba
−841 de lógica solo por el recorte (bootloader + flash + SPI + slot expandido)
antes de añadir nada. Reparto por módulo, de la síntesis
(`*_syn_rsc.xml`, LUT / FF / ALU; referencia: la build `v9990` del estudio en
`Temp/v99wt/v9990`, mismo RTL que el hito 1, que reprodujo su lógica exacta):

| Módulo | Referencia | Hito 3 | Diferencia |
|---|---|---|---|
| `u_main/u_boot` (bootloader) | 508 / 174 / 16 | — | −508 / −174 / −16 |
| `u_flash` + `u_flash_spi` | 268 / 172 / 0 | — | −268 / −172 / 0 |
| `u_main/u_sltexp` (slot expandido) | 49 / 49 / 0 | — | −49 / −49 / 0 |
| `u_uma` (el canal 0 se queda sin cliente) | 171 / 217 / 0 | 90 / 167 / 0 | −81 / −50 / 0 |
| LED (`LED` de tnCart → `STATUS_LED`) | 63 / 50 / 25 | 5 / 26 / 24 | −58 / −24 / −1 |
| `u_guard` (POR, gestor del rPLL, guardia) | — | 114 / 82 / 25 | +114 / +82 / +25 |
| `u_rst`, `u_sysrst`, `u_bus_guard`, `u_clk` | 1 / 0 / 0 | 5 / 4 / 0 | +4 / +4 / 0 |
| `u_main/u_v9990` (mismo RTL; ruido de síntesis) | 8 700 / 4 809 / 748 | 8 652 / 4 809 / 767 | −48 / 0 / +19 |
| **Total** | 11 565 / 6 173 / 2 166 | 10 678 / 5 780 / 2 193 | **−887 / −393 / +27** |

El recorte por sí solo son unos **−964 LUT / −469 FF / −41 ALU**; lo nuevo,
**+123 LUT / +112 FF / +49 ALU**. En `sync` la guardia mide 152 / 107 / 36 (el
medidor de frecuencia del reloj del slot no se poda). Para el plan del
estudio (sección 9: si el recorte devuelve menos de 150 CLS, las palancas
R#16/EOR/`BLEND=0` entran ya): en `v9990` devuelve 490 CLS netos; la
configuración que aprieta es `v9990_megaram`, que aquí solo se ha podido
ensayar (sección 8).

## 2. Variantes de reloj (hito 6)

- `board_wt200b_config_xtal.sv` (`SYNC_CPU_CLK = 0`, 27 MHz x 4 = 108,000
  MHz) y `board_wt200b_config_sync.sv` (`SYNC_CPU_CLK = 1`, `CART_CLOCK` x 30
  = 107,386 MHz, la rama que ya estaba en `board_wt200b_clock.sv`). Cada
  `build_*.tcl` compila uno con su `.sdc`.
- `SYNC_CPU_UMA = 0` en las dos, como en la rev1 de buppu3
  (`board_rev1_config.sv:40`): el UMA corre libre con `DIV = 30`. La
  alternativa 2 de `uma.sv` (`sync_flag`: engancharse una vez al primer
  `CLK_EN` tras el reset y correr libre después) fijaría la fase entre el Z80 y
  las ranuras de la SDRAM en cada arranque; solo tiene sentido en `sync`, y
  hace que el UMA no avance sin reloj del slot (`mem_cnt` no cuenta hasta el
  primer `CLK_EN`; con él se pararía también el borrado de la megaROM). Queda
  para cuando se mida la MegaRAM sin WAIT con osciloscopio (estudio, sección
  10). La 1 reinicia la cuenta en cada `CLK_EN` (con su jitter de un ciclo del
  `PIN_FILTER`) y en `xtal` la pararía en cada ciclo del Z80: no se usa.
- **rPLL base**: el `RESET` lo da el POR de 27 MHz y el `LOCK` sale crudo; no
  hay `RESET_n = 1'b1` constante ni lock pegajoso. `BOARD_WT200B_GUARD` (todo
  en `CLK_27M`, el cristal, el único reloj que existe siempre):
  - POR de 1,21 ms (32 768 ciclos) con el rPLL en reset tras cargar la FPGA
    (los flops arrancan con su valor inicial, por GSR).
  - En `sync`, el rPLL solo se suelta con el reloj del slot presente (un flanco
    cada 1,19 µs como poco) y en frecuencia (543 flancos en una ventana de
    151,7 µs, de 535 a 551: 3,527-3,632 MHz). UG286-2.0.2E, nota a la tabla
    5-2: si el reloj de entrada cambia o es inestable, el rPLL se resetea
    cuando vuelva a ser estable.
  - `PLL_OK` tras 2,43 ms (65 536 ciclos) de `LOCK` seguido. La misma nota del
    UG286 avisa de que `LOCK` puede dar *glitches* mientras engancha y pide
    vigilarlo al menos 2 ms. DS226-2.7E, tabla 3-20 (GW2AR-18 C8/I7):
    `TLOCKMAX` 1 ms y `RSTMINPULSE` 10 ns; el reset del rPLL dura 1,21 ms en
    el POR y 38 µs en cada reintento, y `LOCK_TIMEOUT` (19,4 ms) es 19 veces
    el `TLOCKMAX`.
  - **Detector de pérdida**: sin enganche estable en 19,4 ms, o si se pierde
    (`LOCK` bajo 152 µs seguidos o, en `sync`, el reloj del slot ausente o
    fuera de frecuencia): `PLL_OK` = 0 (el diseño vuelve a reset de forma
    asíncrona: `BASE_READY`, `RESET_n` y `SYS_RESET_n` caen sin esperar a
    `CLK_BASE`), un ciclo después 38 µs de reset del rPLL, y reintento.
    `RELOCKED` queda pegajoso para el LED.
  - **Control rápido del periodo** (`sync`; resto del hallazgo 2 de la
    revisión): si el reloj del slot cambia de frecuencia sin salir del rango
    del rPLL (por ejemplo a 4,0 MHz: VCO 960 MHz, CLK_BASE 120 MHz, por
    encima de la Fmax), `LOCK` no tiene por qué caer y la ventana de 151,7 µs
    tarda de 152 a 303 µs en verlo. El control rápido cuenta los ciclos de 27
    MHz de 16 periodos del slot (4,47 µs; 120,7 ciclos a 3,579545 MHz, banda
    117-124): con la cuantificación y la metaestabilidad de los dos extremos
    (±1 cada una) pasa seguro de −1,9 a +2,3 % (la ventana de ±1,5 % cabe
    dentro) y salta seguro por debajo de −4,2 % o por encima de +4,9 %. Quita
    `SLOT_OK` con **tres** medidas seguidas fuera de banda: un flanco espurio
    aislado estropea como mucho dos (la que lo contiene y, si la cierra él, la
    siguiente). En `S_LOCKED` eso baja `PLL_OK` y `DRIVE_EN` en menos de 20
    µs. En `xtal` `SLOT_OK` no se usa.
  - `BASE_READY` resetea el rPLL TMDS, su CLKDIV y `sdram.sv` (antes era el
    LOCK crudo del rPLL base, pegajoso en `sync`).
- **El rPLL de `sync` y el pin 76.** `CART_CLOCK` está en el pin 76
  (`IOT30[B]`, función `GCLKC_1`, según el `.rpt.txt`): es entrada de reloj
  global, no entrada dedicada de PLL (en esta placa la de `LPLL1` es el pin 4,
  el de `CLK_27M`). El P&R lo acepta y avisa con `PR1014` ("Generic routing
  resource will be used to clock signal 'CART_CLOCK_d' by the specified
  constraint. And then it may lead to the excessive delay or skew"): el
  retardo del pin al rPLL entra en la latencia de CLK_BASE, que el STA ya
  tiene en cuenta (4,686 ns en el modelo lento, frente a 5,329 en `xtal`); el
  jitter que añada el enrutado no está cuantificado. Ningún aviso `TA*`.
- **Rango del rPLL en `sync`**: `FCLKIN` 3,58, `IDIV_SEL` 0 (/1),
  `FBDIV_SEL` 29 (x30), `ODIV_SEL` 8: PFD 3,58 MHz, CLKOUT 107,386 MHz, VCO
  859 MHz. Límites del GW2AR-18 C8/I7 en la DS226-2.7E (31/07/2026, tabla
  3-20; copia leída en el *scratchpad* de la sesión, los mismos que en la
  1.9.1, tabla 4-18): FIN y PFD 3-500 MHz, VCO 500-1250 MHz, CLKOUT
  3,906-625 MHz, `TLOCKMAX` 1 ms; UG286-2.0.2E (en la instalación de Gowin),
  tabla 5-3: `FCLKIN` de "3" a "500". Todo dentro; el PFD queda un 19 % sobre
  el mínimo. Con x30 y ODIV 8 el rPLL admitiría de 3,0 a 5,2 MHz en la
  entrada: un slot a 5,37 MHz (turbo que cambie el CLOCK del cartucho) daría
  VCO 1289 MHz, fuera de rango; la guardia no suelta el rPLL fuera de 3,579545
  MHz ±1,5 %.
- **Entrada del rPLL en `sync`** (misma tabla 3-20): jitter de periodo menor
  del 20 % del periodo **o 1 ns como máximo** (a 3,58 MHz, 20 % son 56 ns:
  manda el 1 ns) y ciclo de trabajo de **al menos el 25 %** (3-49 MHz). El
  reloj del slot llega por el pin 76 con enrutado genérico (`PR1014`), y su
  jitter no está medido en ninguna máquina: los dos límites pasan a ser
  criterios de placa del hito 6 (sección 9).

## 3. Guardia de lock

- `DRIVE_EN_27` = `PLL_OK`, `LOCK` alto en ese momento (`lock_s`, los 2 FF
  del sincronizador, sin filtro) y el sistema listo (`SYS_RESET_n`, que ya
  incluye el `READY` de la SDRAM, el POR y el borrado de la megaROM, con 2 FF
  en 27 MHz). Si `LOCK` baja, los pines se sueltan en 2-3 ciclos (0,11 µs en
  el banco) aunque `PLL_OK` aguante los 152 µs del filtro de pérdida antes de
  mandar el diseño a reset; en `sync`, con el slot saltando a 5,37 MHz, a los
  0,1-0,2 µs en lugar de los 33-152 µs que tarda `PLL_OK` (hallazgo 2 de la
  revisión: antes la lógica de `CLK_BASE`, posiblemente fuera de frecuencia,
  seguía gobernando `/WAIT`, `/INT`, `BUSDIR` y los datos ese tiempo).
  Contrapartida: un *glitch* de `LOCK` con el PLL ya enganchado corta un
  /WAIT en curso (sin reset: `DRIVE_EN_27` vuelve con `LOCK`, y un hueco de
  menos de 152 µs sigue sin resetear nada). Si `LOCK` no cae (el rPLL sigue
  al slot fuera de frecuencia), en `sync` los pines se sueltan con `PLL_OK`
  por el control rápido del periodo (sección 2): 9,8 µs a 4,0 MHz y 16,3 µs a
  3,40 MHz en el banco, frente a 69,7 y 185,0 µs con solo la ventana.
- `BOOT_HOLD_27` = sistema aún no listo durante un arranque, con un tope de 50
  ms (1 350 000 ciclos) por arranque:
  - **Arranque en frío**: desde que acaba la configuración de la FPGA (`xtal`:
    el cristal está siempre; el primer flanco de 27 MHz) o desde el primer
    flanco del reloj del slot (`sync`: el MSX encendido) hasta que el sistema
    queda listo por primera vez, **con el PLL enganchado o no**: cubre el POR
    (1,21 ms), el enganche (hasta 1 ms según el `TLOCKMAX`), los 2,43 ms de
    `LOCK` estable, la SDRAM y, en MegaRAM, el borrado de la ventana. En
    `sync`, si el reloj del slot desaparece (MSX apagado con la Tang
    alimentada por USB) el siguiente arranque vuelve a ser en frío, con su
    tope entero.
  - **Tras perder el enganche** con el sistema ya listo: desde que vuelve
    `PLL_OK` hasta que el sistema queda listo (como antes).
  - Sin enganche, `DRIVE_EN_27` = 0 siempre y `BOOT_HOLD_27` = 0 salvo en el
    arranque en frío, y ahí como mucho 50 ms: el cartucho queda mudo y el MSX
    arranca. Al quedar listo, `DRIVE_EN_27` sube un ciclo antes de que baje
    `BOOT_HOLD_27`: el /WAIT no tiene hueco en el relevo.
- **Por qué el arranque en frío** (hallazgo 1 de la revisión). Con
  `BOOT_HOLD_27` = `PLL_OK` y sistema no listo, el /WAIT de arranque solo
  cubría de `PLL_OK` a `SYS_RESET_n` (0,5 µs en `v9990`): desde el final de la
  configuración hasta `PLL_OK` (3,7 ms; 4,6 ms con el `TLOCKMAX`) el MSX corría
  con el cartucho mudo. En el hito 1 el /WAIT salía desde el final de la
  configuración (el reset de `EXPANSION_SLOT` pone `Primary.WAIT_n <= 0` y
  `SYS_RESET_n` seguía retenido por `BOOT_n`), y la DS226-2.7E dice que durante
  la configuración los GPIO están en alta impedancia con *pull-up* débil, lo
  que probablemente ya enciende el transistor de `CART_WAIT_n` y congela el
  MSX mientras carga el bitstream (no se ha visto en la placa). En `v9990` no
  hacía daño (solo puertos de E/S), pero en MegaRAM la BIOS podía hacer en esa
  ventana la detección del slot expandido (`FFFFh`) o buscar el `AB` con el
  cartucho invisible. Esto se aparta de la letra del encargo ("sin enganche,
  `BOOT_HOLD_27` = 0") y sigue su intención ("que el MSX no corra mientras el
  cartucho arranca, como hacía el bootloader, pero que un fallo no lo congele
  para siempre"): sin enganche el MSX queda retenido como mucho 50 ms al
  encenderse y después arranca con el cartucho mudo. Lo demuestra el banco:
  con la guardia de `83940f4` el banco nuevo falla en el POR (`BOOT_HOLD` 0,
  esperado 1) y en el arranque en frío (sección 7).
- El reloj del slot cuenta como presente desde su primer flanco de subida
  (`gap_cnt` arranca en "ausente"), no desde la configuración: en `sync` sin
  MSX no sale ningún pulso de /WAIT al encender.
- Por qué hace falta: el estado de reset de la carcasa **saca /WAIT**:
  `EXPANSION_SLOT` pone `Primary.WAIT_n <= 0` en reset
  (`expansion_slot.sv:209`) y `BOARD_REV1_BUS` hace
  `CART_WAIT_n = !Bus.WAIT_n`. Con el rPLL sin enganchar, el MSX se quedaría
  congelado en negro.
- **Gateo provisional** (`BOARD_WT200B_BUS_GUARD`, en el top, bloque
  `>>> FUSION hito/bus`): entre `BOARD_REV1_BUS` y los cartuchos, sobre las
  cuatro señales que `board_rev1_bus.sv` lleva a los pines de forma
  combinacional. Polaridades, comprobadas en `board_rev1_bus.sv:174-189`, en
  el `.cst` y con `tb_integ_pins`:
  - `CART_WAIT_n = !Bus.WAIT_n`: 1 activa el transistor que baja /WAIT
    (`PULL_MODE=NONE`). En el pin: `BOOT_HOLD || (DRIVE_EN && wait)`.
  - `CART_INT_n = !Bus.INT_n` con `BOARD_ID = WonderTANG_200b` (la 1.01c no
    invierte): 1 baja /INT (`PULL_MODE=NONE`). En el pin: `DRIVE_EN && int`.
  - `dir = !(!CART_RD_n && !Bus.BUSDIR_n)`, `CART_DATA_DIR = CART_BUSDIR_n =
    dir`, `CART_DATA_SIG = dir ? Z : DOUT`: con `DRIVE_EN` = 0, `dir` = 1
    (buffer hacia la FPGA, /BUSDIR suelto, datos en alta impedancia; los dos
    pines tienen `PULL_MODE=UP`).
  - `DRIVE_EN_27`/`BOOT_HOLD_27` son flops de 27 MHz que solo llegan a pines
    por lógica combinacional: no hay flop de destino.
- `WAIT_TIMEOUT`: entrada de error pegajoso para el LED, a 0 hasta la fusión
  (la saca `BOARD_REV1_BUS` de `hito/bus` en `CLK_BASE`; la guardia la
  sincroniza con 2 FF y la hace pegajosa en 27 MHz).
- Tras perder el enganche y recuperarlo con el sistema ya arrancado una vez,
  `BOOT_HOLD_27` vuelve a retener al MSX el tiempo que tarde el sistema en
  quedar listo (microsegundos en `v9990`; el borrado entero en MegaRAM, que
  vuelve a borrar los 32 KB de la ventana). Si el primer arranque agotó el
  tope, ya no hay `BOOT_HOLD` hasta que el sistema llegue a estar listo alguna
  vez (en `sync`, o hasta que el reloj del slot desaparezca: el siguiente
  arranque es en frío con su tope entero).
- El LED marca "error de reloj" (código 0) durante el POR y el enganche de
  cada arranque (unos 3,7 ms, no se llega a ver) y "arrancando" (código 1)
  de `PLL_OK` a listo.

## 4. LED (pin 75, 1 = encendido, como el LED de tnCart; `STATUS_LED` en 27 MHz)

| Código | Estado | Patrón |
|---|---|---|
| 0 | **error de reloj**: rPLL sin enganchar (en `sync` también reloj del slot ausente o fuera de frecuencia) | parpadeo rápido (6,4 Hz) |
| 1 | **arrancando**: rPLL enganchado, sistema sin acabar (si se queda, el arranque falló y el MSX ya corre sin el cartucho) | parpadeo lento (1,6 Hz) |
| 2 | solo `xtal`: sin reloj del slot (MSX apagado o cartucho mal metido) | destello corto cada 1,24 s |
| 3 | listo con `WAIT_TIMEOUT` pegajoso | doble destello cada 1,24 s |
| 4 | listo tras perder el enganche y recuperarlo (pegajoso) | cuatro destellos cada 1,24 s |
| 5 | **listo** | fijo |

Apagado del todo: la FPGA no está configurada. La polaridad (1 = encendido) es
la del `LED` de tnCart, que sacaba `LedPort` directo al pin; no se ha visto en
la placa.

## 5. `.sdc`

- `v9990_xtal.sdc`: los mismos relojes y grupos que el del hito 1. El
  bootloader, la flash y los SPI iban en `CLK_BASE`: no desaparece ningún
  reloj, y el `CLK_21M` sigue sin declararse (se poda). Lo nuevo de 27 MHz (la
  guardia y el LED en `CLK_27M`, el reset del I2S en `CLK_DAC`) entra en el
  grupo `{CLK_27M CLK_5_4M CLK_DAC}`. El *false path* del reset hacia `DCLK`
  nombra `u_rst/reset_n_s0`.
- `v9990_sync.sdc`: `CLK_3_58M` (279,365 ns = 3,579545 MHz; tnCart ponía
  279,330) es la referencia del rPLL base: `CLK_BASE = CLK_3_58M x 30` (9,312
  ns), `CLK_MEM_P` x30 con `-offset 4.656` (180°), `CLK_TMDS_S = CLK_BASE x
  5/4` (134,23 MHz), `CLK_TMDS_P` /5 (26,85 MHz), `DCLK` con el modelo de
  `xtal` (`-divide_by 4`, en el grupo de `CLK_BASE`) y `-offset 7.55`: latencia
  del rPLL 4,686 + red 2,274 + tC2Q 0,232 + LUT más rápida 0,371 = 7,563 ns,
  redondeado hacia abajo como el 8,2 de `xtal`. Lo confirma la build del hito
  6: el `.sdf` da 7,724 ns de flanco real (+0,174 con la ruta a la OR). Con el
  8,2 de `xtal` el modelo iría 0,476 ns por detrás del flanco real (eso lo vio
  una build de prueba de la sesión anterior que no se archivó; las cifras de
  latencia que da coinciden con las de esta). `CLK_3_58M` va en un grupo
  propio aunque `CLK_BASE` salga de él: el `set_clock_groups` corta caminos de
  datos, no la relación de reloj generado, y los únicos caminos de datos que
  salen de `CLK_3_58M` son el pin muestreado por el `PIN_FILTER`
  `u_bus/u_clock` (`CLK_BASE`) y por `u_guard/sclk_ff` (`CLK_27M`). `CLK_27M`,
  `CLK_5_4M` y `CLK_DAC`, asíncronos (otro cristal).
- Sincronizadores declarados en la cabecera de los dos (los cruces los corta el
  `set_clock_groups`): `u_guard/ready_ff` (SYS_RESET_n → 27 MHz),
  `u_guard/wto_ff` (WAIT_TIMEOUT → 27 MHz), `u_guard/lock_ff` (LOCK del rPLL),
  `u_guard/sclk_ff` (pin CART_CLOCK), `u_rst/base_ff` (PLL_OK → CLK_BASE,
  afirmación asíncrona), `dac_reset_ff` (RESET_n → CLK_DAC, afirmación
  asíncrona).
- `v9990_megaram_{xtal,sync}.sdc`: copias de los de `v9990` (mismas órdenes).
  Con `scc.sv` (`ENABLE_SCC = ENABLE`) el `CLK_21M` se poda: solo lo usa el
  IKASCC (`cartridge_megarom.sv`). Comprobado en la build `v9990_mega` de
  referencia del estudio (`Temp/v99wt/v9990_mega/impl/pnr/tnc_v9990_mega.rpt.txt`:
  CLKDIV 3/8 y ningún `CLK_21M` entre los PRIMARY) y en el ensayo de la
  sección 8.

## 6. Scripts y puerta

`fpga/build_common.tcl` tiene la lista de ficheros y las opciones; cada
`build_<cfg>_<variante>.tcl` fija `CFG` y `VARIANT` y lo carga. Salida en
`fpga/impl/pnr/<cfg>_<variante>.*` (las cuatro escriben en el mismo `impl/`:
una cada vez, y archivar antes de la siguiente). La MegaRAM añade
`cartridge_megarom.sv`, `megarom_configure.sv`, `megarom_controller.sv`,
`megarom_clear.sv`, `scc.sv` y `config/v9990_megaram.sv`, más `bootloader.sv`,
`flash.sv` y `spi.sv` solo por sus definiciones (`XFER`, `XFER_IF`,
`FLASH_IF`, `SPI_IF`; no se instancia nada de ellos) y
`system/megarom_xfer_tie.sv`. Hasta la fusión las dos builds de MegaRAM se
paran al empezar (comprobado: `gw_sh` sale con código 1 y "faltan 2
fichero(s): config/v9990_megaram.sv, src/peripheral/msx/megarom_clear.sv");
con los ficheros ya fusionados, se paran si `HAVE_MEGAROM_CLEAR` sigue
comentado (comprobado en una copia con los dos ficheros puestos: código 1 y
"en src/main.sv falta descomentar `define HAVE_MEGAROM_CLEAR"). Cada build tarda de 18 a 40 minutos en esta máquina (con otras
builds en paralelo).

`tools/check_build.py` admite `--sin-ref "motivo"` (build sin referencia de
recursos: el punto 4 frente a la referencia no se aplica y lo dice; sin él y
sin `--ref-*` la puerta sigue saliendo `INCOMPLETA`), `--max-bsram`
(obligatorio con `--sin-ref`) y `--compara LOGICA,CLS,BSRAM` (diferencia con
otra build, informativa). El false path permitido sobre `DCLK` acepta el
nombre nuevo `u_rst/reset_n_s0`. Comprobado sobre la build archivada del
hito 3: sin `--ref-*` ni `--sin-ref`, y con `--sin-ref` sin `--max-bsram`,
la puerta sale `INCOMPLETA` (código 2).

Comandos de puerta, desde la raíz del repositorio y después de
`cd fpga && gw_sh build_<cfg>_<variante>.tcl` (las mismas opciones fijas en
las cuatro: `--max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109`;
los logs son los que escribe `gw_sh` en `impl/`):

- **`v9990_xtal`** (referencia: la build del hito 3, mismo árbol):
  ```
  python tools/check_build.py fpga/impl/pnr/v9990_xtal --ref-logic 13258 --ref-cls 8189 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_xtal.log --log fpga/impl/pnr/v9990_xtal.log --sdc fpga/constraints/v9990_xtal.sdc
  ```
  La del hito 3 se pasó sin referencia: en lugar de `--ref-* --tol`,
  `--sin-ref "hito 3: recorte de la carcasa (...)" --compara 14140,8679,24
  --max-bsram 46`.
- **`v9990_sync`** (referencia: la build del hito 6):
  ```
  python tools/check_build.py fpga/impl/pnr/v9990_sync --ref-logic 13124 --ref-cls 8180 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_sync.log --log fpga/impl/pnr/v9990_sync.log --sdc fpga/constraints/v9990_sync.sdc
  ```
  La del hito 6, con `--sin-ref "hito 6: primera build de la variante sync
  (...)" --compara 13258,8189,24 --max-bsram 46`.
- **`v9990_megaram_xtal`** y **`v9990_megaram_sync`**: la primera build tras
  la fusión no tiene referencia del mismo árbol (la del estudio es
  `v9990_mega`, 15 494 / 9 111 / 29):
  ```
  python tools/check_build.py fpga/impl/pnr/v9990_megaram_xtal --sin-ref "primera build de la configuracion MegaRAM" --compara 15494,9111,29 --max-bsram 46 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_megaram_xtal.log --log fpga/impl/pnr/v9990_megaram_xtal.log --sdc fpga/constraints/v9990_megaram_xtal.sdc
  ```
  y lo mismo con `sync`; desde la segunda, `--ref-*` con los números de la
  primera.
- Archivado: `python tools/archive_build.py fpga/impl/pnr/<cfg>_<variante>
  fpga/reports/<hito>` y la orden de puerta sobre lo archivado
  (`fpga/reports/<hito>/<cfg>_<variante>`, logs `gwsynthesis.log` y
  `pnr.log`, el `.sdc` archivado) con la salida a `check_build.txt` (desde cmd
  o bash). `fpga/reports/hito3/` es `v9990_xtal`; `fpga/reports/hito6/` es
  `v9990_sync` (la `xtal` del mismo árbol es la del hito 3).

**Reproducibilidad.** La primera build `v9990_xtal` (03:58) leyó `main.sv`,
`board_wt200b_clock.sv` y `board_wt200b_guard.sv` antes de un cambio solo de
comentarios; se repitió desde el árbol ya commiteado (05:11) y el cuerpo del
`.fs` salió **idéntico** (CheckSum `0xB677`, anotado en
`fpga/reports/hito3/v9990_xtal.fs.txt`). Lo archivado en `hito3/` es esa
segunda build. La `v9990_sync` se compiló ya con el árbol commiteado.

## 7. Banco (Verilator 5.020, WSL)

`bash tb/integ/run.sh` desde `fpga/` (en WSL; de 3 a 9 min según lo que
corra en paralelo). Resultado del 26/10/2026 sobre `f00c622` (árbol
commiteado, tras los arreglos de la revisión): **19 de 19 ejecuciones pasan**
(pins: 64 casos y 273 comprobaciones; guardia: 9 escenarios en `xtal` y 9 en
`sync`, de 13 a 35 comprobaciones cada uno; 175 en `xtal` y 181 en `sync`).

- `tb_integ_guard`: `BOARD_WT200B_GUARD`, `SYSTEM_RESET`,
  `SYSTEM_RESET_HOLD` y `STATUS_LED` reales con sus parámetros de la build
  (salvo el divisor del LED, 4096 veces más rápido) y modelados el rPLL (en
  `sync` solo engancha con el slot entre 3 y 5,2 MHz), `CLK_BASE`, el `READY`
  de la SDRAM y el `DONE` del borrado. En las dos variantes. Escenarios:
  - `lento`: LOCK a los 3 ms de soltar el reset; listo a los 6,64 ms (POR
    1,21 + LOCK 3 + 2,43 estable). `BOOT_HOLD` del arranque en frío desde los
    0,019 µs (`xtal`, el primer flanco de 27 MHz) o los 0,278 µs (`sync`, el
    primer flanco del reloj del slot) hasta los 6,642 ms, sin huecos; de
    `PLL_OK` a listo, 0,56 µs. LED fijo.
  - `perdida`: en `xtal` un hueco de LOCK de 50 µs suelta los pines a los
    0,111 µs sin resetear nada (`DRIVE_EN` vuelve con LOCK) y una pérdida
    larga los suelta a los 0,115 µs y baja `PLL_OK` a los 151,8 µs; en `sync`
    el reloj del slot se para y `PLL_OK` cae a los 1,22 µs. En las dos, el
    sistema vuelve a reset con `DRIVE_EN`/`BOOT_HOLD` a 0 y LED de error,
    reengancha y queda listo con `RELOCKED` (LED de cuatro destellos). Tras
    el reenganche, en `xtal` `BOOT_HOLD` va solo de `PLL_OK` a listo (0,52
    µs); en `sync` el slot parado cuenta como MSX apagado y el siguiente
    arranque es en frío (`BOOT_HOLD` desde 0,274 µs después de volver el
    reloj del slot hasta que el sistema queda listo).
  - `nunca`: en `xtal` el rPLL no engancha (3 reintentos en 60 ms) y el
    `BOOT_HOLD` del arranque en frío dura 50,0013 ms y suelta al MSX; en
    `sync` no hay reloj del slot, el rPLL no se suelta nunca y no sale ningún
    `BOOT_HOLD`; en las dos, a los 60 ms sin `PLL_OK`, `DRIVE_EN` ni
    `BOOT_HOLD` y sistema en reset, LED de error.
  - `turbo` (solo `sync`): slot a 5,37 MHz desde el arranque: el rPLL no se
    suelta; `BOOT_HOLD` de 50,0013 ms y después el MSX libre.
  - `tope`: la SDRAM no acaba hasta los 70 ms: `BOOT_HOLD` dura 50,0013 ms
    desde la configuración, el MSX queda libre con el cartucho mudo y el LED
    en "arrancando"; a los 70 ms `DRIVE_EN` sube sin volver a `BOOT_HOLD`.
  - `mega`: el borrado de 2 ms retiene `SYS_RESET_n` (2,000 ms de `PLL_OK` a
    listo) y `BOOT_HOLD` va de la configuración al final del borrado (8,64
    ms).
  - `timeout` (solo `xtal`): `WAIT_TIMEOUT` de 1 µs queda pegajoso (LED de
    doble destello) sin quitar `DRIVE_EN`.
  - `glitch`: tres huecos de LOCK de 10 µs al enganchar: `PLL_OK` sube una
    sola vez, 2,43 ms después del último, y el `BOOT_HOLD` del arranque en
    frío no se corta.
  - `turbo_marcha`: el slot pasa a 5,37 MHz con el sistema listo y vuelve a
    los 2 ms: en `sync` los pines se sueltan a los 0,111 µs (LOCK bajo),
    `PLL_OK` cae a los 33,3 µs, reset y reenganche con `BOOT_HOLD` solo de
    `PLL_OK` a listo (el reloj del slot no llegó a pararse); en `xtal`, nada.
  - `deriva`: con el sistema listo, el slot a −1,4 % y a +1,4 % (1 ms cada
    uno) y, a +1,0 %, ocho rebotes aislados de 60 ns en el reloj del slot (seis
    al final de una medida del control rápido, que estropean dos medidas
    seguidas): ni pérdida ni reset, `DRIVE_EN` sin cortes. Después el slot a
    4,0 MHz y a 3,40 MHz, dentro del rango del rPLL (el modelo no suelta
    LOCK): en `sync` `PLL_OK` cae a los 9,77 y 16,30 µs y `DRIVE_EN` 37 ns
    después (límite del banco, 20 µs), reset de 2 ms y reenganche con
    `BOOT_HOLD` solo de `PLL_OK` a listo (518,5 ns); en `xtal`, nada.

  En todo momento vigila que sin `PLL_OK` no haya `DRIVE_EN`, que `DRIVE_EN`
  caiga como mucho 3 ciclos de 27 MHz después de bajar LOCK, que sin `PLL_OK`
  solo haya `BOOT_HOLD` en el arranque en frío (en `sync`, con reloj del slot)
  y ningún pulso pase de 50 ms, que el sistema esté en reset sin `PLL_OK`, que
  el relevo `BOOT_HOLD` → `DRIVE_EN` solape un ciclo como mucho y que el
  /WAIT del pin no tenga huecos con el V9990 pidiéndolo, con el PLL
  enganchado o en el arranque en frío.
- **El banco nuevo contra la guardia anterior** (`board_wt200b_guard.sv` de
  `83940f4` en una copia aparte, con los mismos `SYSTEM_RESET` y `STATUS_LED`;
  seis ejecuciones): fallan todas, y solo por los dos hallazgos. En las seis,
  `BOOT_HOLD` = 0 durante el POR (esperado 1) y en el arranque `BOOT_HOLD` no
  sube hasta los 6 641,2 µs (`PLL_OK`) en lugar de a los 0,019 µs (`xtal`) o
  0,278 µs (`sync`): `lento` 3 fallos de 15 en cada variante, `tope` 2 de 16.
  En `xtal perdida` (6 de 31), además, `DRIVE_EN` no cae en el hueco de LOCK
  de 50 µs ni en la pérdida hasta `PLL_OK` (5 442 ciclos de 27 MHz con
  `DRIVE_EN` y LOCK bajo); en `sync perdida` (5 de 28) el arranque en frío
  tras volver el reloj del slot empieza 5 583 µs tarde; en `sync
  turbo_marcha` (5 de 30), 896 ciclos con `DRIVE_EN` y LOCK bajo.
- **`deriva` contra el control rápido quitado o con dos medidas** (copias
  aparte de la guardia de `f00c622`, `sync`): con `SLOT_OK = SLOT_PRESENT &&
  freq_ok` (solo la ventana) fallan 2 de 35: `PLL_OK` cae a los 69,7 µs (4,0
  MHz) y a los 185,0 µs (3,40 MHz), fuera del límite de 20 µs. Con el control
  rápido quitando `fast_ok` a la segunda medida mala en lugar de a la tercera
  fallan otras 2 de 35: un solo rebote resetea el diseño (`DRIVE_EN` corta una
  vez con el slot a +1,0 %).
- `tb_integ_pins`: `BOARD_REV1_BUS` de `main` con `BOARD_WT200B_BUS_GUARD`
  delante y las 64 combinaciones de `DRIVE_EN`, `BOOT_HOLD`, `WAIT_n`,
  `INT_n`, `BUSDIR_n` y /RD contra los pines (Verilator es de dos estados: la
  alta impedancia se comprueba viendo que el dato del MSX llega sin
  conflicto).
- El top entero no pasa por Verilator 5.020 (referencias con punto en
  constantes de tnCart: `$bits(Ram.ADDR)` en `sdram.sv`, `$bits(IN.Signal)` en
  `dac_16bit.sv`, `$bits(SoundExternal[0].Signal)` en `main.sv`, `Uma.COUNT`
  en el top): la elaboración de `main.sv` y del top la comprueban las builds
  de Gowin.

## 8. Contratos para la fusión

Lo que hay que conectar o sustituir al fusionar cada rama de área (las ramas
siguen abiertas: lo que sigue es lo que se leyó en ellas el 25 y el
26/10/2026, sin fusionar nada).

**Ensayo de la configuración MegaRAM (no es la build de ningún hito).** Para
comprobar el hueco de `main.sv` antes de la fusión se compiló
`v9990_megaram_xtal` en una copia aparte (`Temp/v99wt/integ_mega`, sin tocar
esta rama): el árbol de `hito/integ` (`d3cb6f1`) más `config/v9990_megaram.sv`,
`cartridge_megarom.sv`, `megarom_configure.sv` y `megarom_controller.sv` de
`hito/megaram` (`05ea0e6`), su `megarom_clear.sv` **sin commit** (md5
`8463cc61...`, 26/10 04:12) y `` `define HAVE_MEGAROM_CLEAR `` descomentado.
Resultado: elabora y sintetiza sin errores (la rama MegaRAM de `main.sv`, el
`EXPANSION_SLOT`, `MEGAROM_XFER_TIE` y `MEGAROM_CLEAR` con sus parámetros) y
pasa la puerta en modo `--parcial`: **14 759 de lógica, 8 889 CLS (86 %), 29
BSRAM**, LW 8/8, CLKDIV 3/8 y ningún `CLK_21M` (la copia del `.sdc` vale),
16 órdenes `Actived`, 0 endpoints violados, Fmax CLK_BASE 118,1 MHz, carrera
CLK_BASE → DCLK +1,428 / +4,622 ns, modelo de DCLK +0,167 ns. Frente a la
`v9990_mega` del estudio (15 494 / 9 111 / 29): −735 de lógica y −222 CLS,
ya con lo que añade `hito/megaram` (ventana de 4 MB, PLAIN0, /WAIT de
memoria). Avisos: CV0016 x3 (las entradas sin carga), NL0002 x5 (el
atenuador y el mezclador del sonido interno, que la wt200b no saca, y
`MEGAROM_XFER_TIE`, que solo da constantes y se propaga) y PR1014 x1
(`CLK_27M_d`, como en `v9990`). LW 8/8: no queda ningún *long wire* libre en
esta configuración.
Los números valen solo como orientación: los ficheros de `hito/megaram`
pueden cambiar antes de la fusión.

**Común a todas las ramas: la lista de ficheros cambia** (hallazgo 4 de la
revisión). Este hito parte `board_wt200b_config.sv` en
`board_wt200b_config_xtal.sv` y `_sync.sv`, añade
`board/wt200b/board_wt200b_guard.sv`, `board/wt200b/board_wt200b_bus_guard.sv`
(hasta la fusión con `hito/bus`) y `system/system_reset.sv`, saca de la
build `v9990` `bootloader.sv`, `flash.sv` y `spi.sv`, y cambia el top (sin
`LED`, `LED_IF`, `FLASH_SPI` ni `SPI`). Ninguna otra rama toca estos ficheros
(`git diff main...HEAD` vacío en ellos el 26/10), así que la fusión aplica el
cambio sin conflicto y **sin aviso**, y rompe los bancos y comprobaciones de
las áreas, que siguen nombrando la lista del hito 1:
- `board_wt200b_config.sv` (deja de existir) lo nombran, en los worktrees de
  las áreas el 26/10 a las 15:15 (las líneas se mueven: buscar el nombre),
  `bus/fpga/tb/bus/run.sh`, `megaram/fpga/tb/megaram/run.sh`,
  `bus/fpga/check_bus.tcl`, `megaram/fpga/check_megaram.tcl`,
  `sdram/fpga/check_sdram.tcl`, `video/fpga/check_video.tcl` y las copias sin
  cambios del `fpga/build_v9990_xtal.tcl` del hito 1. Los bancos pasan a
  `board_wt200b_config_xtal.sv` (o `_sync.sv` si prueban esa variante).
- Los cuatro `check_*.tcl` elaboran el top entero con la lista del hito 1
  (con `bootloader.sv`, `flash.sv` y `spi.sv`, sin la guardia ni
  `system_reset.sv`): tienen que tomar la lista de `build_common.tcl` (o
  retirarse en favor de `build_v9990_{xtal,sync}.tcl`). `check_bus.tcl`
  además parchea el top del hito 1 por texto (`LedPort`, `LED_IF LedNextor`,
  `.Bus` de `u_bus`) y fallará con "el parche del top no aplica": en la
  fusión lo sustituye la conexión real del bloque `>>> FUSION hito/bus`.
- Las copias de `fpga/build_v9990_xtal.tcl` del hito 1 que hay en las ramas
  no tienen cambios, así que queda la de esta rama (dos líneas que cargan
  `build_common.tcl`).
- `UPSTREAM.md` ya describe los ficheros nuevos y partidos.

**`hito/bus`** (`board_rev1_bus.sv`, `cartridge_v9990.sv`):
- `BOARD_REV1_BUS` gana las entradas `DRIVE_EN` y `BOOT_HOLD` y las salidas
  `WAIT_TIMEOUT` (pegajosa, `CLK_BASE`) y `BUS_OK` (así está en su worktree, sin
  commit, el 26/10). En el top, bloque `>>> FUSION hito/bus`: `u_bus` recibe
  `.DRIVE_EN(drive_en_27)`, `.BOOT_HOLD(boot_hold_27)`,
  `.WAIT_TIMEOUT(wait_timeout)` y `.Bus(Bus)`; `wire wait_timeout = 1'b0`
  pasa a `logic wait_timeout`; desaparecen `BusPin`, `u_bus_guard`,
  `board_wt200b_bus_guard.sv` y su línea en `build_common.tcl`.
  `tb_integ_pins` se puede reapuntar al `BOARD_REV1_BUS` nuevo (la ecuación del
  /WAIT pasa a llevar `bus_ok`) o retirarse.
- `DRIVE_EN`/`BOOT_HOLD` salen de flops de `CLK_27M`: dentro de
  `BOARD_REV1_BUS` solo pueden ir a los pines por lógica combinacional o, si se
  registran en `CLK_BASE`, por un sincronizador (su `drive_en_s` lo es); el
  `set_clock_groups` corta el cruce de todas formas. `WAIT_TIMEOUT` lo
  sincroniza la guardia (`u_guard/wto_ff`, 2 FF).
- **`SYS_READY` de la guardia tiene que incluir `BUS_OK`**: en `hito/bus`
  (`18f9eca`, 26/10) los datos, `/INT` y el /WAIT del V9990 salen solo con
  `bus_ok && DRIVE_EN`, y `bus_ok` (reloj del slot vivo en una ventana de
  2^18 ciclos, y /RESET del slot suelto) no sube hasta 2,43 ms después de
  `RESET_n`. Con `SYS_READY = SYS_RESET_n` solo, `BOOT_HOLD` bajaría al
  quedar listo el sistema y el MSX correría esos 2,43 ms con el cartucho
  mudo: el mismo hueco del hallazgo 1, más corto. En la fusión, el top pasa
  `.SYS_READY(sys_ready && bus_ok)` a `u_guard` (`BUS_OK` es un flop de
  `CLK_BASE`; la guardia lo sincroniza con `ready_ff`). Con el /RESET del MSX
  pulsado, `BUS_OK` = 0: `DRIVE_EN` a 0 y `BOOT_HOLD` a 1 (con su tope)
  mientras dura, inofensivo con el Z80 en reset, y el LED en "arrancando".
  `bus_ok` vuelve un ciclo después de soltar el /RESET (su `ck_alive` sigue a
  1), así que tras un /RESET de más de 50 ms no queda hueco. El caso que sí
  deja uno, en `xtal`: con la Tang alimentada por USB antes que el MSX, el
  tope se agota sin MSX y no se rearma al aparecer el reloj del slot (en
  `xtal` no hay `msx_off`); si el /RESET del MSX dura menos de lo que tarda
  `ck_alive` (de 2,43 a 4,86 ms tras el primer flanco), el MSX corre ese resto
  con el cartucho mudo. Si hiciera falta, en la fusión se rearma también en
  `xtal` con `SLOT_PRESENT`, pero entonces `booting` tiene que exigir
  `msx_on` también con `PLL_OK` (si no, sin MSX `BOOT_HOLD` se quedaría a 1).
- `DRIVE_EN` puede bajar y volver sin reset (LOCK bajo menos de 152 µs, ver
  sección 3): `BOARD_REV1_BUS` no debe tomar su bajada como un reset (hoy
  solo lo usa en los pines y, sincronizado, para no contar el timeout de
  /WAIT, así que vale).
- En la configuración `v9990` el V9990 va directo al bus (sin
  `EXPANSION_SLOT`): el banco de bus por topología de `hito/bus` tiene que
  cubrir los dos casos con este `main.sv`.
- Si `cartridge_v9990.sv` cambia cómo se genera `Video.DCLK` (el arreglo del
  *glitch* de la OR), hay que rehacer el `create_generated_clock` de `DCLK` en
  los cuatro `.sdc` (y el `-offset` de cada variante: 8,2 en `xtal`, 7,55 en
  `sync`) y los nombres que lee el punto 6 de `tools/check_build.py` y
  `tools/archive_build.py` (`u_main/u_v9990/dclk_en_ff_1_s0`,
  `Video.DCLK_s`).

**`hito/megaram`** (`cartridge_megarom.sv`, `megarom_*.sv`, `scc.sv`,
`megarom_clear.sv`, `config/v9990_megaram.sv`):
- Descomentar `` `define HAVE_MEGAROM_CLEAR `` en `main.sv`. `MEGAROM_CLEAR`
  se instancia con `RESET_n` (el reset de la carcasa), `CLK`,
  `Ram(ExpRam[RAM_BOOTLOADER])` (canal 0 del UMA, base 0), `DONE`,
  `CLEAR_ADDR = CONFIG::RAM_ADDR_MEGAROM` y `CLEAR_SIZE = 24'd32768` (los
  parámetros `[23:0]` del `megarom_clear.sv` de su worktree); `DONE` retiene
  `SYS_RESET_n` y va a la entrada `WAIT_n` de `EXPANSION_SLOT`, como pide su
  contrato. Su borrado (~7 ms según su banco) cabe en el tope de 50 ms de
  `BOOT_HOLD_27`.
- `CARTRIDGE_MEGAROM` conserva el puerto `XFER_IF.HOST Xfer` (sin cambios de
  puertos en `05ea0e6`): `main.sv` le da un `XFER_IF` atado por
  `MEGAROM_XFER_TIE`. Si lo quitan, quitar también el `XFER_IF`, el
  `MEGAROM_XFER_TIE` y `bootloader.sv`/`flash.sv`/`spi.sv`/`megarom_xfer_tie.sv`
  de la lista MegaRAM de `build_common.tcl`.
- **`SYS_RESET_n` ya no sigue al /RESET del MSX** (sí lo hacía con el
  bootloader de tnCart): la megaROM pasa por la rama `!Bus.RESET_n` de
  `megarom_configure.sv` en cada reset del MSX (conserva lo que configuró
  `tncrom`; `ENABLE_CONTINUOUS` decide si sigue habilitada) en lugar de
  volver a los valores por defecto. Hay que validarlo con `tncrom` y un reset.
- Una pérdida de enganche vuelve a correr el borrado: tras reenganchar, los 32
  KB de la ventana se borran otra vez (sin refresco durante la pérdida la
  SDRAM tampoco conserva nada fiable).
- Durante un /RESET largo del MSX ya no hay quien refresque la SDRAM (el
  bootloader lo hacía con lecturas en `STATE_WAIT_BOOT`): lo cubre el
  refresco interno de `hito/sdram`, que conviene fusionar antes o a la vez.
- `build_common.tcl` espera exactamente `src/cartridge_megarom.sv`,
  `src/peripheral/msx/megarom_configure.sv`, `megarom_controller.sv`,
  `megarom_clear.sv`, `src/peripheral/sound/scc/scc.sv` y
  `config/v9990_megaram.sv`.

**`hito/sdram`** (`uma.sv`, `sdram.sv`, `ram.sv`):
- `SDRAM.RESET_n` es ahora `base_ready` (PLL_OK con 2 FF en `CLK_BASE`), no
  el LOCK crudo; `READY` se usa igual (entra en `reset_n` de `SYSTEM_RESET`).
- El `UMA` del top se instancia con `COUNT`, `SYNC_CLK_EN =
  CONFIG_BOARD::SYNC_CPU_UMA` (0) y `DIV = 30`; los parámetros nuevos
  (`INT_REFRESH`, `REFRESH_CYCLES`...) quedan con su valor por defecto y las
  salidas nuevas `DBG_RF_*` sin conectar (o se conectan a nada en el top).
- En `v9990` el canal 0 del UMA no tiene cliente (por eso la síntesis barre
  `EXPANSION_RAM` y el UMA pierde 81 LUT): el refresco interno es lo único que
  irá por él.

**`hito/video`** (`video.sv`, `video_upscan.sv`, `board_rev1_tmds.sv`):
- `VIDEO_UPSCAN` gana el parámetro `BLEND` (1 por defecto, el de tnCart): el
  top no lo pasa; elegir `BLEND = 0` es una línea en el top.
- Sigue pendiente (del hito 1) el reset sin sincronizador hacia `CLK_TMDS_P`:
  el top pasa `RESET_n` (`CLK_BASE`) a `VIDEO_UPSCAN` y a
  `BOARD_REV1_TMDS_OUT`; un sincronizador en `CLK_TMDS_P` iría en el top,
  pero solo para el lado de salida (el de entrada es el *false path* hacia
  `DCLK`), así que necesita que el upscan separe los dos resets.

**`hito/core`**: sin contrato con este hito (el core entra por
`cartridge_v9990.sv`). La Fmax de `CLK_BASE` (110,19 / 109,59 MHz) y la
carrera CLK_BASE → DCLK de `sync` (+0,277 ns) son las cifras que hay que
volver a mirar cuando entren sus parches.

## 9. Pendiente y riesgos

**Pendiente:**
- Todo lo de placa: arranque en frío y en caliente (20 veces cada uno, el
  criterio del hito 3), LED en cada estado, `sync` en MSX1, MSX2, MSX2+ (3,58 y
  turbo), turbo R y un MSX en FPGA (criterio del hito 6), qué hace el MSX
  cuando `sync` no engancha (debería arrancar con el LED de error), el batido
  con el VDP, los monitores a 59,92 Hz y la retención de la VRAM en `sync`.
- Las dos builds de MegaRAM, que esperan a la fusión con `hito/megaram` (el
  ensayo de la sección 8 no es la build del hito: usa ficheros sin commit de
  otra rama).
- Sustituir el bloque `>>> FUSION hito/bus` y conectar `WAIT_TIMEOUT` al
  fusionar `hito/bus`.
- **Criterio de placa nuevo del hito 6** (DS226-2.7E, tabla 3-20): en cada
  máquina en que se pruebe `sync`, jitter de periodo del CLOCK del slot
  **menor de 1 ns** y ciclo de trabajo **de al menos el 25 %**, medidos en el
  pin 76 de la Tang (después del *buffer* de la WonderTANG).
- Ver en la placa si el *pull-up* débil de los GPIO durante la configuración
  enciende el transistor de `CART_WAIT_n` (el MSX congelado mientras carga el
  bitstream) y cuánto dura el /RESET del MSX frente a la carga.

**Riesgos:**
- **`sync` depende del reloj del slot** en todo: sin MSX encendido no hay
  CLK_BASE ni HDMI, el pin 76 no es entrada dedicada de PLL (`PR1014`, jitter
  sin medir frente al límite de 1 ns de la DS226-2.7E), y el jitter del slot
  llega x30 a la SDRAM. La guardia evita que el MSX se quede colgado, pero no
  que el cartucho no funcione.
- **`BOOT_HOLD` al encender** (sección 3): el MSX queda retenido con /WAIT
  desde la configuración hasta que el cartucho está listo (3,7 ms en `v9990`,
  más el borrado en MegaRAM) y, si el PLL no engancha, 50 ms; después arranca
  con el cartucho mudo. Es lo que hacía el bootloader, salvo el tope.
- **`DRIVE_EN` sin filtro de LOCK**: un *glitch* de LOCK con el PLL
  enganchado corta un /WAIT del V9990 en curso (el Z80 sigue con un dato
  malo). No se ha visto ninguno en placa; con el filtro, la lógica de
  `CLK_BASE` seguía gobernando el slot hasta 152 µs tras una pérdida real.
- **Márgenes finos**: carrera CLK_BASE → DCLK en `sync` +0,277 ns; Fmax de
  `sync` 109,59 MHz (0,6 MHz sobre la puerta). Dependen de la colocación.
- **Medidor de frecuencia**: la ventana de ±1,5 % (535-551 flancos) es una
  elección; una máquina con el CLOCK del slot fuera de esa ventana pero dentro
  del rango del rPLL se quedaría sin enganchar (LED de error y cartucho mudo)
  aunque funcionara. El control rápido del periodo (banda de 16 periodos)
  resiste un flanco espurio aislado, pero dos espurios en tres medidas
  seguidas (13,4 µs) pueden resetear el diseño: un CLOCK del slot con mucho
  ruido o rebotes de más de 37 ns lo haría (sin medir en ninguna máquina).
- **`BOOT_HOLD` en marcha**: con la guardia, una pérdida y recuperación del
  enganche con el MSX corriendo lo retiene con /WAIT hasta que el cartucho
  vuelve a estar listo (µs en `v9990`, el borrado en MegaRAM); en `sync`, si
  el reloj del slot llegó a pararse, desde que vuelve (arranque en frío).
- **MegaRAM sin margen de *long wires***: el ensayo da LW 8/8 (en `v9990`,
  7/8); una red de control más con mucho abanico (un reset o un *enable*
  nuevo) tendría que ir por enrutado normal.
- **Polaridad del LED** tomada del LED de tnCart; no vista en la placa.
- **Comportamiento con el /RESET del MSX** cambiado frente a tnCart (sección
  1): a validar con la MegaRAM.

## 10. Revisión del 26/10/2026

| Hallazgo | Severidad | Resolución | Commits | Prueba |
|---|---|---|---|---|
| 1. `BOOT_HOLD` solo de `PLL_OK` a listo: el MSX corría 3,7 ms (4,6 con el `TLOCKMAX`) con el cartucho mudo al encender | media | **Real, arreglado.** `BOOT_HOLD_27` en el arranque en frío desde la configuración (`xtal`) o el primer flanco del reloj del slot (`sync`), con el PLL enganchado o no, con el tope de 50 ms (sección 3). Se aparta de la letra del encargo ("sin enganche, `BOOT_HOLD_27` = 0"): sin enganche el MSX queda retenido como mucho 50 ms al encender | `d09d121` | banco: la guardia de `83940f4` falla las seis ejecuciones probadas, solo por esto y el hallazgo 2 (sección 7) |
| 2. Los pines solo se sueltan al caer `PLL_OK` (152 µs con LOCK bajo; una ventana del medidor en `sync`) | baja | **Real, arreglado.** `DRIVE_EN_27` con `lock_s` sin filtro (0,11 µs) y, en `sync`, control rápido del periodo del reloj del slot para el caso en que LOCK no cae (9,8 / 16,3 µs) | `d09d121`, `f00c622` | `perdida`, `turbo_marcha` y `deriva`; contra la guardia sin el control rápido, `deriva` falla (69,7 / 185,0 µs) |
| 3. La DS226-2.7E sí estaba leída: límites de entrada del rPLL sin citar y pendiente abierto sin motivo | baja | **Real, arreglado.** Tabla 3-20 citada en `board_wt200b_clock.sv`, la guardia y la sección 2; el pendiente se cierra y quedan dos criterios de placa del hito 6 (jitter de periodo < 1 ns, ciclo de trabajo ≥ 25 %) | `c3e4bfc` | lectura de la copia de la DS226-2.7E (tabla 3-20) |
| 4. El renombrado de `board_wt200b_config.sv` y la lista nueva rompen los bancos y `check_*.tcl` de las áreas al fusionar, sin aviso | baja | **Real, documentado** como contrato común (sección 8) y en `UPSTREAM.md`; no se tocan ficheros de otras áreas | `90d6377` y esta nota | `grep` en los worktrees de las áreas |

Además, al leer `hito/bus` para el hallazgo 1: `SYS_READY` de la guardia
tiene que incluir `BUS_OK` en la fusión (sección 8, comentario en el bloque
`>>> FUSION hito/bus` del top, `57c19a3`).
