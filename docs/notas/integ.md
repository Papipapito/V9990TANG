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
    vigilarlo al menos 2 ms.
  - **Detector de pérdida**: sin enganche estable en 19,4 ms, o si se pierde
    (`LOCK` bajo 152 µs seguidos o, en `sync`, el reloj del slot ausente o
    fuera de frecuencia): `PLL_OK` = 0 (el diseño vuelve a reset de forma
    asíncrona: `BASE_READY`, `RESET_n` y `SYS_RESET_n` caen sin esperar a
    `CLK_BASE`), un ciclo después 38 µs de reset del rPLL, y reintento.
    `RELOCKED` queda pegajoso para el LED.
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
  859 MHz. Límites del GW2AR-18 C8/I7 en el DS226-1.9.1 (2021, tabla 4-18, la
  versión que se pudo leer): CLKIN y PFD 3-500 MHz, VCO 500-1250 MHz, CLKOUT
  3,906-625 MHz; UG286-2.0.2E (en la instalación de Gowin), tabla 5-3:
  `FCLKIN` de "3" a "500". Todo dentro; el PFD queda un 19 % sobre el mínimo.
  Con x30 y ODIV 8 el rPLL admitiría de 3,0 a 5,2 MHz en la entrada: un slot a
  5,37 MHz (turbo que cambie el CLOCK del cartucho) daría VCO 1289 MHz, fuera
  de rango; la guardia no suelta el rPLL fuera de 3,579545 MHz ±1,5 %. **Sin
  comprobar**: la DS226-2.7E (31/07/2026, la vigente según el índice de Gowin)
  pide registro; los límites de jitter y de ciclo de trabajo de la entrada y el
  tiempo máximo de enganche no están en las versiones leídas, y el jitter del
  reloj del slot no está medido en ninguna máquina.

## 3. Guardia de lock

- `DRIVE_EN_27` = `PLL_OK` y el sistema listo (`SYS_RESET_n`, que ya incluye
  el `READY` de la SDRAM, el POR y el borrado de la megaROM, con 2 FF en 27
  MHz). `BOOT_HOLD_27` = `PLL_OK` y el sistema aún no listo, con un tope de 50
  ms (1 350 000 ciclos) que solo se rearma cuando el sistema llega a estar
  listo. Sin enganche, las dos a 0: el cartucho no saca nada al slot y el MSX
  arranca. Al quedar listo, `DRIVE_EN_27` sube un ciclo antes de que baje
  `BOOT_HOLD_27`: el /WAIT no tiene hueco en el relevo.
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
  vez.

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

`bash tb/integ/run.sh` desde `fpga/` (en WSL; 4 min 38 s). Resultado del
26/10/2026: **18 de 18 pasan** (pins: 64 casos y 273 comprobaciones; guardia:
8 escenarios en `xtal` y 8 en `sync`, de 9 a 20 comprobaciones cada uno).

- `tb_integ_guard`: `BOARD_WT200B_GUARD`, `SYSTEM_RESET`,
  `SYSTEM_RESET_HOLD` y `STATUS_LED` reales con sus parámetros de la build
  (salvo el divisor del LED, 4096 veces más rápido) y modelados el rPLL (en
  `sync` solo engancha con el slot entre 3 y 5,2 MHz), `CLK_BASE`, el `READY`
  de la SDRAM y el `DONE` del borrado. En las dos variantes. Escenarios:
  - `lento`: LOCK a los 3 ms de soltar el reset; listo a los 6,64 ms (POR
    1,21 + LOCK 3 + 2,43 estable), `BOOT_HOLD` ~0,5 µs, LED fijo.
  - `perdida`: en `xtal` un hueco de LOCK de 50 µs se ignora y una pérdida
    larga baja `PLL_OK` a los 151,7 µs; en `sync` el reloj del slot se para y
    `PLL_OK` cae a los 1,22 µs; en las dos, el sistema vuelve a reset con
    `DRIVE_EN`/`BOOT_HOLD` a 0 y LED de error, reengancha y queda listo con
    `RELOCKED` (LED de cuatro destellos).
  - `nunca`: en `xtal` el rPLL no engancha (3 reintentos en 60 ms); en `sync`
    no hay reloj del slot y el rPLL no se suelta nunca; en las dos, a los 60 ms
    sin `PLL_OK`, `DRIVE_EN` ni `BOOT_HOLD` y sistema en reset, LED de error.
  - `turbo` (solo `sync`): slot a 5,37 MHz desde el arranque: el rPLL no se
    suelta.
  - `tope`: la SDRAM no acaba hasta los 70 ms: `BOOT_HOLD` dura 50,0013 ms, el
    MSX queda libre con el cartucho mudo y el LED en "arrancando"; a los 70 ms
    `DRIVE_EN` sube sin volver a `BOOT_HOLD`.
  - `mega`: el borrado de 2 ms retiene `SYS_RESET_n` y `BOOT_HOLD` dura lo que
    el borrado.
  - `timeout` (solo `xtal`): `WAIT_TIMEOUT` de 1 µs queda pegajoso (LED de
    doble destello) sin quitar `DRIVE_EN`.
  - `glitch`: tres huecos de LOCK de 10 µs al enganchar: `PLL_OK` sube una
    sola vez, 2,43 ms después del último.
  - `turbo_marcha`: el slot pasa a 5,37 MHz con el sistema listo y vuelve a
    los 2 ms: en `sync` reset y reenganche; en `xtal`, nada.

  En todo momento vigila que sin `PLL_OK` no haya `DRIVE_EN` ni `BOOT_HOLD` y
  el sistema esté en reset, que el relevo `BOOT_HOLD` → `DRIVE_EN` solape un
  ciclo como mucho y que el /WAIT del pin no tenga huecos con el V9990
  pidiéndolo.
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
- La DS226-2.7E: límites de jitter y ciclo de trabajo de la entrada del rPLL
  y tiempo de enganche (pide registro).

**Riesgos:**
- **`sync` depende del reloj del slot** en todo: sin MSX encendido no hay
  CLK_BASE ni HDMI, el pin 76 no es entrada dedicada de PLL (`PR1014`, jitter
  sin cuantificar), y el jitter del slot llega x30 a la SDRAM. La guardia
  evita que el MSX se quede colgado, pero no que el cartucho no funcione.
- **Márgenes finos**: carrera CLK_BASE → DCLK en `sync` +0,277 ns; Fmax de
  `sync` 109,59 MHz (0,6 MHz sobre la puerta). Dependen de la colocación.
- **Medidor de frecuencia**: la ventana de ±1,5 % (535-551 flancos) es una
  elección; una máquina con el CLOCK del slot fuera de esa ventana pero dentro
  del rango del rPLL se quedaría sin enganchar (LED de error y cartucho mudo)
  aunque funcionara.
- **`BOOT_HOLD` en marcha**: con la guardia, una pérdida y recuperación del
  enganche con el MSX corriendo lo retiene con /WAIT hasta que el cartucho
  vuelve a estar listo (µs en `v9990`, el borrado en MegaRAM).
- **MegaRAM sin margen de *long wires***: el ensayo da LW 8/8 (en `v9990`,
  7/8); una red de control más con mucho abanico (un reset o un *enable*
  nuevo) tendría que ir por enrutado normal.
- **Polaridad del LED** tomada del LED de tnCart; no vista en la placa.
- **Comportamiento con el /RESET del MSX** cambiado frente a tnCart (sección
  1): a validar con la MegaRAM.
