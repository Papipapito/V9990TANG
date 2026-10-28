# Arquitectura

Esta página describe primero el punto de partida, el hito 1: la carcasa wt200b
de tnCartWonder con el core tiny9990 de tnCart **sin cambios de RTL**, donde lo
único propio eran la configuración (`fpga/config/v9990.sv`), el `.sdc`
(`fpga/constraints/v9990_xtal.sdc`), el script de build y la puerta
(`tools/check_build.py`). **La versión 0.1beta (la fusión de las áreas, hitos 2
a 8, que es lo que hay ahora en `main`) se describe al final, en [Desde la
fusión de las áreas](#desde-la-fusión-de-las-áreas)**: esa sección manda sobre
las de en medio donde no coinciden. Las secciones de en medio siguen siendo
las del hito 1 porque los mecanismos que explican (bloques de tnCart, `DCLK`
como reloj generado de `CLK_BASE`, grupos del `.sdc`) no han cambiado; el
detalle de cada área está en el anexo de [notas](notas/README.md).

## Bloques

```
            slot MSX (multiplexado por la WonderTANG)
                │  CART_MUX_SIG / CART_MUX_CS_n / CART_DATA_SIG / RD / WR / SLTSL / CLOCK
                ▼
   BOARD_REV1_BUS ── 36 PIN_FILTER + escáner de 9 estados ── BUS_IF (CLK_BASE)
                │
   MAIN ── EXPANSION_SLOT (4 subranuras vacías + 2 puertos solo de E/S: PSG, apagado, y V9990)
                │                         └── BOOTLOADER (flash → SDRAM, retiene SYS_RESET_n y /WAIT)
                ▼
   CARTRIDGE_V9990 (puertos 60h-6Fh) ── T9990 (tiny9990 + blitter)
                │ VRAM: RAM_IF                     │ R/G/B/HS/VS en posedge Video.DCLK
                ▼                                  ▼
   UMA (dos clientes, ranura cada 10 ciclos)   VIDEO_UPSCAN (3 líneas, 855x524 a 27 MHz)
                │                                  │
   SDRAM (9 ciclos, CL2, ráfaga 2x32)          BOARD_REV1_TMDS_OUT → DVI_TX (Gowin) → HDMI
                │
   SDRAM embebida de la Tang (8 MB, VRAM en 78_0000h)
```

| Bloque | Fichero | Qué hace |
|---|---|---|
| Relojes | `src/board/wt200b/board_wt200b_clock.sv` | rPLL base (27 MHz x4 = 108 MHz, más su salida desfasada 180° para el reloj de la SDRAM), rPLL TMDS (108 x5/4 = 135 MHz) y CLKDIV /5 (27 MHz de píxel), /5 (5,4 MHz) y /3,5 (1,543 MHz del DAC) |
| Reset | `src/tnCart_board_wt200b_top.sv` | `reset_n` en `CLK_BASE`, bajo mientras el PLL no engancha o la SDRAM no está lista |
| Bus | `src/board/rev1/board_rev1_bus.sv` | 36 `PIN_FILTER` (16 de dirección, 12 de control, 8 de datos: 2 muestras por pin) y escáner del multiplexor de la WonderTANG; saca `BUS_IF` en `CLK_BASE` |
| Slot expandido | `src/peripheral/msx/expansion_slot.sv` | registro `FFFFh` con 4 subranuras (2 bits por página), todas vacías en esta configuración, y 2 puertos más solo de E/S, con `SLTSL_n` fijo a 1: el PSG (desactivado) y el V9990, que no ocupa ninguna subranura |
| Bootloader | `src/bootloader.sv` | tras el arranque de la FPGA y con el MSX fuera de `/RESET`: copia 144 KB de la flash (`10_0000h`) a `70_0000h`, borra 32 KB de la megaROM y 64 KB del mapper en la SDRAM y hace la fase PAC (lee hasta 8 bancos de 8 KB de la flash en `1F_0000h` y deja uno válido, o ceros, en `77_E000h`); mientras tanto `/WAIT` activo y V9990 en reset |
| V9990 | `src/cartridge_v9990.sv`, `v9990/tiny9990/*.sv` | el core tiny9990 de buppu3 con su VDP de comandos (blitter) |
| UMA | `src/peripheral/ram/uma.sv` | reparte la SDRAM entre dos clientes (RAM y VRAM) en ranuras fijas de 10 ciclos, alternas, dentro de un periodo de `DIV = 30` ciclos de `CLK_BASE` (3,6 MHz) que corre libre: en `xtal` el UMA no se engancha a `CART_CLOCK` (`SYNC_CPU_UMA = 0`). Saca los enables de 21,6, 14,4 y 25,2 MHz del V9990 |
| SDRAM | `src/peripheral/ram/sdram.sv` | controlador de 9 ciclos por acceso, ráfaga de 2 x 32 bits, autoprecarga |
| Upscan | `src/peripheral/video/video_upscan.sv` | escala la imagen del V9990 a 720x480 con mezcla lineal horizontal y duplicado vertical, buffer de 3 líneas entre `DCLK` y `CLK_TMDS_P` |
| DVI | `src/board/rev1/board_rev1_tmds.sv` + `dvi_tx/` | IP DVI_TX de Gowin, sin audio |
| DAC | `src/peripheral/sound/dac_16bit.sv` | I2S hacia el amplificador de la Tang; aquí siempre ceros |

## Relojes (variante `xtal`)

| Reloj | Frecuencia | Origen | Qué mueve |
|---|---|---|---|
| `CLK_27M` | 27,000 MHz | cristal de la Tang (pin 4) | entrada del rPLL base y de los CLKDIV del DAC |
| `CLK_BASE` | 108,000 MHz | rPLL base, 27 x4 | todo el sistema: bus, slot, core, UMA, SDRAM |
| salida desfasada del rPLL base | 108,000 MHz, 180° | rPLL base (`CLKOUTP`) | solo el pin de reloj de la SDRAM (`O_sdram_clk`) |
| `DCLK` (`Video.DCLK`) | según el modo: 5,4 (B1), 7,2 (B2), 10,8 (B3), 14,4 de media (B4, cadencia 7/8 ciclos), hasta 25,2 con C25M | lógica en `cartridge_v9990.sv` (OR de `dclk_en` retrasado 1 y 2 ciclos): dos ciclos en alto cada 4 a 20 ciclos de `CLK_BASE` | captura de R/G/B/HS/VS y lado de escritura del upscan |
| `CLK_TMDS_S` | 135,000 MHz | rPLL TMDS, 108 x5/4 | serializador del DVI_TX |
| `CLK_TMDS_P` | 27,000 MHz | CLKDIV /5 de `CLK_TMDS_S` | lado de lectura del upscan y DVI_TX |
| `CLK_5_4M` | 5,4 MHz | CLKDIV /5 de `CLK_27M` | solo como fuente de `CLK_DAC` |
| `CLK_DAC` | 1,543 MHz | CLKDIV /3,5 de `CLK_5_4M` | DAC I2S |
| `CLK_3_58M` | 3,58 MHz | pin `CART_CLOCK` | nada en `xtal`: solo entra como dato en el `PIN_FILTER` del bus. De él salen `Bus.CLK` y `Bus.CLK_EN`, pero en esta build no los usa nadie (el UMA corre libre); en el netlist solo quedan los dos flops del filtro |

Con `DIV = 30`, el UMA saca los enables del V9990 a 21,6 y 14,4 MHz, un 0,571 %
por encima de los 21,477 y 14,318 del chip: el V9990 va a 60,27 Hz en lugar de
59,92. Es estructural del upscan (1368 x 27 / 21,6 = 1710 = 2 x 855) y se quita
con la variante `sync` del hito 6, que saca `CLK_BASE` del reloj del slot x30
(107,386 MHz) y engancha el UMA a él (ver el estudio, sección 4, "Relojes: el
0,57 % y cómo quitarlo"; dónde está el estudio, en [UPSTREAM.md](../UPSTREAM.md#estudio)).

Los 8 relojes primarios del chip están ocupados (ver
[VERIFICATION.md](VERIFICATION.md)): no cabe ninguna red de reloj nueva sin
quitar otra.

## SDRAM y VRAM

Cada acceso del controlador dura 9 ciclos y el UMA da una ranura cada 10 ciclos
alternando dos clientes: 5,4 M accesos por segundo y cliente. La latencia es
fija, así que el tiny9990 no necesita cache. El tiny9990 pierde una ranura en
silencio si el ACK llega después del siguiente `EXEC`: cualquier cambio de
cadencia tiene que mantener "ciclo del controlador + 1 ≤ ranura". En el hito 1 no
se toca nada de esto.

Mapa de la SDRAM (de `config.sv`): mapper en `00_0000h` (sin uso; el bootloader
borra 64 KB), megaROM en `40_0000h` (sin uso; el bootloader borra 32 KB), copia de
la flash del bootloader en `70_0000h` (144 KB), PAC en `77_E000h` (8 KB que
escribe el bootloader, sin uso), **VRAM de 512 KB en `78_0000h`**.

**Refresco: por debajo de la especificación en el hito 1.** La SDRAM pide 4096
refrescos en 64 ms (64 k/s). En tnCart los aporta sobre todo el `/RFSH` del Z80,
que reenvían la RAM y la megaROM; en esta configuración no hay ninguna de las dos.
Quedan el refresco que pide el propio V9990, uno por línea (15,8 k/s con la línea
de 6840 ciclos, y ninguno en standby), y durante un reset del MSX los AUTO
REFRESH que el bootloader intercala en su bucle de lecturas. Es
el riesgo conocido de la referencia: la VRAM podría perder datos con la pantalla
en standby. Un temporizador de refresco propio en el UMA es el hito 4; en placa,
el hito 1 solo comprueba que la imagen sale.

## Cruces de reloj y .sdc

El `.sdc` de la wt200b (`board_wt200b_27M.sdc`, de herraa1 en tnCartWonder,
sobre el de tnCart) no sirve tal cual en esta configuración: declara `CLK_21M`, que aquí no existe porque su CLKDIV se poda, y
con un reloj inexistente en `-group` el P&R de Gowin 1.9.12 **aborta**
(`ERROR (TA2004) Cannot get clock with name 'CLK_21M'`, comprobado). La build de
referencia del estudio esquivó el error borrando las dos líneas que lo nombraban,
y una era el `set_clock_groups`. Sin grupos, Gowin analizó como síncronos los
cruces asíncronos del upscan: de ahí sus 290 endpoints de setup y su recovery
violados, que no eran del diseño.

`fpga/constraints/v9990_xtal.sdc` se escribió después de revisar cada cruce
contra el RTL: cuatro revisores, uno por grupo de cruces, y dos refutadores por
revisor (sincronización y modelo de STA). Esta sección resume el resultado.

### Grupos

| Grupo | Relojes | Por qué |
|---|---|---|
| sistema | `CLK_BASE`, `CLK_MEM_P`, `DCLK` | `CLK_MEM_P` es la salida a 180° del mismo rPLL; `DCLK` se genera con flops de `CLK_BASE` (ver abajo) |
| TMDS | `CLK_TMDS_S`, `CLK_TMDS_P` | juntos por el serializador del DVI_TX. Mesócronos de `CLK_BASE`: el CLKDIV /5 sale de reset con el LOCK del segundo rPLL, sin sincronizar, así que la fase frente a `CLK_BASE` cambia en cada arranque |
| 27 MHz | `CLK_27M`, `CLK_5_4M`, `CLK_DAC` | solo cruza el reset hacia el I2S |
| slot | `CLK_3_58M` | en `xtal` el pin `CART_CLOCK` no es el reloj de ningún flop: solo entra como dato en el `PIN_FILTER` del bus |

Los relojes que Gowin crea solo para las salidas sin carga de los rPLL
(`*.default_gen_clk`) no se nombran: no tienen caminos.

### DCLK va con CLK_BASE

`Video.DCLK` es la OR de `dclk_en_ff[1]` y `dclk_en_ff[0]`, dos flops de
`CLK_BASE` (`cartridge_v9990.sv`). No es asíncrono de `CLK_BASE`: cada flanco
suyo nace de un flanco de `CLK_BASE`. Y hay una carrera en el mismo flanco:

- R/G/B salen del registro `OUT` del selector del core, que se carga con
  `DCLK_EN` en el mismo flanco en que sube `dclk_en_ff[1]`. `video_r/g/b`
  capturan el valor nuevo solo si el dato llega antes que el reloj generado.
- HS y VS cambian un ciclo después; para ellos importa el hold.

tnCart ponía `DCLK` en un grupo asíncrono propio, y eso borra las dos
comprobaciones. El modelo original (`-divide_by 15 -multiply_by 2`, 7,5 ciclos)
tampoco vale dentro del grupo de `CLK_BASE`: la mitad de sus flancos caen a medio
ciclo e inventan una relación de 4,62 ns que viola siempre. El modelo nuevo:

```
create_generated_clock -name DCLK -source [get_nets {CLK_BASE}] -master_clock CLK_BASE -divide_by 4 -offset 8.2 -add [get_nets {Video.DCLK}]
```

- **`-divide_by 4`**: todos los flancos caen en la rejilla de 108 MHz, y 4 ciclos
  es el intervalo mínimo real (con C25M). Los caminos `DCLK` → `DCLK` quedan del
  lado seguro. El 50 % por defecto da 18,5 ns en alto, los dos ciclos reales.
- **`-offset 8.2`** hace de latencia de fuente. Gowin arranca `DCLK` con latencia
  0 en la salida de la OR, mientras que `CLK_BASE` llega a los flops con la
  latencia del rPLL y de su red. 8,2 ns es esa latencia, más el tC2Q del flop
  que genera `DCLK`, más el LUT más rápido del chip. El SDF de cada build permite
  comprobarlo en el modelo lento (Slow 0.95V 85C, el del análisis de setup): en
  la del hito 1 el flanco real llega como pronto a 8,362 ns (rPLL 5,329 + red
  2,274 + tC2Q 0,232 + ruta a la OR 0,156 + LUT ≥ 0,371). El modelo va 0,16 ns
  por delante, así que el setup de R/G/B queda del lado seguro. El retardo propio
  de la LUT de la OR no sale en el SDF (Gowin la trata como origen de reloj): se
  toma el pin de LUT más rápido del chip según el SDF, 0,371 ns.
  `tools/check_build.py` repite la cuenta en cada build, con el `-offset` leído
  del `.sdc` y comprobado contra el que usó el STA. En el
  modelo rápido del hold, el offset fijo deja el flanco modelado más tarde que el
  real, lo que hace el hold más pesimista, no menos.

Con este modelo, en la build del hito 1:

| Comprobación | Resultado |
|---|---|
| Setup `CLK_BASE` → `DCLK` (carrera de R/G/B, HS/VS y RESO) | peor slack 1,912 ns (HS); R/G/B desde 1,975 ns. Es el modelo lento, el único en que Gowin analiza el setup; como es un camino de ciclo cero entre dos ramas del mismo reloj, su margen baja en la esquina rápida, donde una estimación con los valores mínimos del SDF da unos 1,5 ns |
| Hold `CLK_BASE` → `DCLK` | peor slack 4,351 ns |
| Caminos `DCLK` → `CLK_BASE` | ninguno ("Nothing to report!"): si apareciera alguno, el offset lo haría optimista |

**El reset hacia `DCLK`** llega como CLEAR al lado de entrada del upscan y como
dato al CE de sus `W_DATA`. Va con un `set_false_path` estrecho
(`-from [get_regs {reset_n_s0}] -to [get_clocks {DCLK}]`): cuando `reset_n` se
suelta, `DCLK` está parado, porque el core sigue en reset por `SYS_RESET_n`, que
el bootloader retiene, y con el core en reset `DCLK_EN` vale 0.

### Lo que se corta, cruce a cruce

| Cruce | Señales | Mecanismo | Consecuencia si falla |
|---|---|---|---|
| `DCLK` → `CLK_TMDS_P` | `in_reso[2:0]` hacia el lado de lectura de los tres buffers | ninguno; cuasi-estático (solo cambia al escribir el modo) | basura durante una línea en el cambio de modo; `OUT_START` reinicia cada línea |
| `DCLK` → `CLK_TMDS_P` | `in_vs_n` | dos flops, pero el flanco se detecta con el primero; VS de 3 líneas | un cuadro con las líneas mal emparejadas; al ser mesócrono, pasa en todos los cuadros de ese arranque o en ninguno |
| `DCLK` → `CLK_TMDS_P` | buffer de líneas (DPB: escritura en `DCLK`, lectura en `CLK_TMDS_P`) | protocolo: enganche 2:1 exacto (6840 ciclos de `CLK_BASE` = 2 x 855 de `CLK_TMDS_P`) y fase de salida reiniciada en cada VS; no hay arco de STA entre puertos | desgarro durante como mucho un cuadro tras un cambio de modo o un reset; márgenes calculados (~1020 ciclos con FIELD=0, ~165 con FIELD=1), no simulados |
| `CLK_BASE` → `CLK_TMDS_P` | `Video.FIELD` | sin sincronizar: se muestrea en el flanco de VS, que se detecta con el primer flop; va un ciclo por delante del VS | un campo con la paridad equivocada |
| `CLK_BASE` → `CLK_TMDS_P` | `Video.INTERLACE` | ninguno; cuasi-estático (bit de R#7) | un píxel a media intensidad |
| `CLK_BASE` → `CLK_TMDS_P` | reset hacia el lado de salida del upscan | sin sincronizar; probablemente con `CLK_TMDS_P` aún parado (lock del segundo rPLL) | primer cuadro desalineado, se corrige con el VS |
| `CLK_BASE` → `CLK_DAC` | reset hacia 6 flops del I2S | sin sincronizar, reloj destino libre | una trama I2S desalineada, en silencio (el dato es 0) |
| `CLK_3_58M` → `CLK_BASE` | pin `CART_CLOCK` | `PIN_FILTER` (2 flops con filtro) | ninguna en esta build |

Sigue comprobado por el STA todo `CLK_BASE`, `CLK_BASE` → `DCLK`, `DCLK` →
`DCLK`, `CLK_TMDS_P` → `CLK_TMDS_P` (upscan hacia el DVI) y el par TMDS.

### Riesgos que el .sdc no cubre

Para los hitos siguientes; ninguno se toca en el hito 1, que no cambia el RTL.

- **Glitch en `Video.DCLK`** (hito 2). En el flanco en que `dclk_en_ff[1]` baja y
  `dclk_en_ff[0]` sube, la OR puede dar un pulso espurio, que adelantaría todo el
  dominio `DCLK`. Ni el STA ni el `.sdc` lo ven; depende del P&R. Arreglo mínimo:
  sacar el reloj de un solo flop (`dclk_q <= dclk_en | dclk_en_ff[1]`, misma
  forma de onda). Arreglo preferido: quitar el reloj generado por lógica y pasar
  la entrada del upscan a `CLK_BASE` con enable, lo que además libera una de las
  8 PRIMARY.
- **Margen de la carrera de R/G/B** (hito 2). Hoy está vigilado en el modelo
  lento (1,9 ns; ~1,5 ns estimados en el rápido, que Gowin no analiza para
  setup), pero depende de la colocación y de la red de `Video.DCLK` (3,27 ns en
  el modelo lento). Arreglo: capturar
  `video_*` en `CLK_BASE` con enable, o generar `DCLK` un ciclo más tarde con los
  datos retemporizados (y recalcular el offset).
- **`in_vs_n` con un flop efectivo, `in_reso` sin sincronizar, `FIELD` capturado
  en dos flops distintos** (hito 2). Endurecer con una tercera etapa y capturar
  `in_reso` y `FIELD` una sola vez en el dominio TMDS.
- **`R_ADDR` con un segundo driver** en el upscan (`default: R_ADDR <= R_ADDR` en
  el `case` de `OUT` para B4); Gowin lo fusiona sin avisar (hito 2, comprobar B4
  en el banco).
- **Resets sin sincronizador fuera de `CLK_BASE`** (hito 3). La seguridad del
  false path depende de que el core siga en reset cuando sube `reset_n`: el POR
  que sustituya al bootloader tiene que conservar ese orden. Añadir un
  sincronizador (afirmación asíncrona, suelta síncrona) en `CLK_TMDS_P`.
- **LOCK crudo como reset de la SDRAM** en `xtal`, sin el flop de retención de la
  variante `sync` (hito 4, con el refresco).
- **E/S de la SDRAM y bus del cartucho sin `set_input_delay`/`set_output_delay`**:
  el STA no las comprueba (hitos 4 y 5). Para restringir la SDRAM ya está
  declarado `CLK_MEM_P`.
- **Variante `sync`** (hito 6): su `.sdc` de tnCartWonder (`board_wt200b_3_58M.sdc`)
  repite los mismos problemas (modelo de `DCLK`, `CLK_21M`, y separa `CLK_3_58M`
  de `CLK_BASE` aunque allí `CLK_BASE` sale de él). Hay que rehacerlo igual que
  este.
- **8/8 PRIMARY es blando**: `CART_CLOCK_d` ocupa una global aunque solo es dato.
  Si un hito necesita una red de reloj, probar a quitar el `create_clock` de
  `CLK_3_58M` y revisar la sección de relojes del `.rpt.txt`.

## Desde la fusión de las áreas

Versión 0.1beta (antes rama `hito/fusion`, ahora en `main`): las seis áreas
fusionadas sobre el hito 1, con sus contratos conectados
([notas/fusion.md](notas/fusion.md)). Cada fila remite a la nota del área, que
tiene el detalle y las fuentes. Las cuatro builds y sus cifras están en
[VERIFICATION.md](VERIFICATION.md#builds-de-la-01beta) y los bitstreams en
`bitstream/`. **Nada de esto se ha probado en placa.**

### Bloques que cambian

| Bloque | Fichero | Qué cambia | Nota |
|---|---|---|---|
| Relojes | `board_wt200b_clock.sv`, `board_wt200b_config_{xtal,sync}.sv` | dos variantes: `xtal` (`CLK_BASE` = 27 x4 = 108,000 MHz del cristal) y `sync` (`CLK_BASE` = reloj del slot x30 = 107,386 MHz; sin MSX encendido no hay `CLK_BASE` ni HDMI); siguen 8/8 PRIMARY y 2/2 rPLL | [integ](notas/integ.md) |
| Guardia | `board_wt200b_guard.sv` (`CLK_27M`) | POR del rPLL base, gestor del rPLL (reintentos, sin lock pegajoso), detector de pérdida de enganche y, en `sync`, medidor de la frecuencia del slot; saca `PLL_OK`, `DRIVE_EN_27` (se pueden conducir los pines del slot) y `BOOT_HOLD_27` (/WAIT de arranque, con tope de 50 ms) | [integ](notas/integ.md) |
| Reset | `system/system_reset.sv` | `reset_n` de `CLK_BASE` con `PLL_OK` sincronizado (`BASE_READY`, también reset de la SDRAM) y el `READY` de la SDRAM; `SYSTEM_RESET_HOLD` retiene `SYS_RESET_n` hasta el fin del borrado de la megaROM | [integ](notas/integ.md) |
| Bootloader | — | fuera (y con él la flash, sus SPI y la TF): `SYS_RESET_n` ya no sigue al /RESET del MSX; cada cartucho mira `Bus.RESET_n` | [integ](notas/integ.md) |
| Bus | `board_rev1_bus.sv` | escaneo adaptativo del multiplexor (salto al grupo de control con /RD o /WR), `Bus.ADDR` quieta durante el ciclo, pre-WAIT en P#0/P#1 (y, en MegaRAM, en las lecturas de memoria: `PREWAIT_MEM_EN`), timeout *fail-open* del /WAIT de 2^12 ciclos (37,9 µs) con `WAIT_TIMEOUT` pegajoso al LED, guardia de bus vivo (`BUS_OK`: reloj del slot vivo y /RESET suelto) y las guardias de la placa en los pines: /WAIT = `BOOT_HOLD` o (`BUS_OK` y `DRIVE_EN` y espera y no timeout); datos e /INT solo con `BUS_OK` y `DRIVE_EN` | [bus](notas/bus.md) |
| Slot | `main.sv` | en `v9990` el V9990 va directo al bus, sin `EXPANSION_SLOT` (como un GFX9000); en `v9990_megaram`, slot expandido con la megaROM en la subranura 0 y el V9990 como puerto solo de E/S | [integ](notas/integ.md) |
| V9990 | `cartridge_v9990.sv`, `v9990/tiny9990/*.sv` | rearme de 3 muestras del ciclo de E/S; core con los parches del hito 2, P#8-P#15 a FFh, cuadro PAL de 313 líneas con R#7 bit 3 (salida `PAL`, a `Video.PAL` en `posedge Video.DCLK`), cursor EOR de openMSX y ajuste de R#16, los tres con parámetro (`CONFIG::V9990_ENABLE_*`) | [core](notas/core.md), [bus](notas/bus.md) |
| UMA | `uma.sv` | refresco interno en el canal 0 (abajo); `DOUT` solo tras un R/W | [sdram](notas/sdram.md) |
| SDRAM | `sdram.sv` | dos AUTO REFRESH en la inicialización (JEDEC) | [sdram](notas/sdram.md) |
| Upscan | `video_upscan.sv` | 720x480 (NTSC) o 720x576 (PAL: `IN.PAL` por dos flops, tomado al acabar el VSYNC de entrada); `BLEND` = 1 la mezcla de tnCart, 0 el punto más cercano (`CONFIG::UPSCAN_BLEND`) | [video](notas/video.md) |
| DVI | `board_rev1_tmds.sv` | ventana de DE según `PAL`: 855x524 (720x480, líneas 35-514) a 60,27 Hz en `xtal` y 59,92 en `sync`, o 855x626 (720x576, líneas 42-617) a 50,45 / 50,16 Hz; NTSC idéntico bit a bit al hito 1 | [video](notas/video.md) |
| MegaROM | `cartridge_megarom.sv`, `megarom_{configure,controller,clear}.sv`, `scc.sv` | solo `v9990_megaram`: arranca como Konami SCC-I RAM con su SCC, ventana de 4 MB en `00_0000h`, modo PLAIN0, /WAIT en sus lecturas (`ENABLE_MEM_WAIT`), borrado de 32 KB a FFh al arrancar (`MEGAROM_CLEAR`, en el canal 0) | [megaram](notas/megaram.md) |
| LED | `led.sv` (`STATUS_LED`, `CLK_27M`) | error de reloj (parpadeo rápido) / `xtal` sin reloj del slot (destello corto) / arrancando, también con `BUS_OK` a 0 (lento) / listo con `WAIT_TIMEOUT` (doble destello) / listo tras reenganchar (cuatro destellos) / listo (fijo) | [integ](notas/integ.md), [fusion](notas/fusion.md) |

### Refresco de la SDRAM

Sustituye a "Refresco: por debajo de la especificación en el hito 1" (arriba).
El UMA genera su propio AUTO REFRESH en el canal 0: un temporizador de 780
ciclos que, si el canal 0 está ocupado, escala a 1560 (contados desde el último
refresco); el intervalo máximo entre refrescos es de 1580 ciclos, 14,63 µs a
108 MHz y 14,71 µs a 107,386 (la SDRAM pide 15,6 µs: 4096 en 64 ms). La
cadencia no cambia (`DIV = 30`, ranura de 10 ciclos, acceso de 9). **Desviación
consciente del chip real**: según el manual del V9990 (p. 80, R#6) en standby no
hay refresco de VRAM; aquí la VRAM se conserva en todos los modos, como en
openMSX (el AUTO REFRESH no distingue regiones, y en la misma SDRAM viven la
megaROM y, en otras configuraciones, Nextor).

### Contrato del UMA para el canal 0

El /WAIT de memoria de la megaROM (`ENABLE_MEM_WAIT = 1`) se suelta con el
`ACK_n` del canal 0, así que estas tres reglas son interfaz del UMA, y quien
toque `uma.sv` tiene que conservarlas (si no, el /WAIT se soltará con el dato
malo; lo vigila `fpga/tb/megaram/run.sh`, variantes `wait`, `inj_hito4` e
`inj_main`):

1. `ACK_n` baja después de que el UMA vea `OE_n` = 0 y no sube mientras quede
   pendiente la lectura de ese cliente;
2. `ACK_n` sube **una sola vez** por lectura y **en el mismo flanco** en que
   `Secondary[0].DOUT` carga el dato de esa lectura, nunca antes;
3. `Secondary[0].DOUT` solo cambia al acabar un R/W del canal 0, nunca tras un
   RFSH (el UMA de tnCart lo copiaba en cada fin de acceso).

Un R/W aplazado una ranura por la escalación del refresco, o por un RFSH que
llega junto a un R/W, alarga el `ACK_n` 20 ciclos: es compatible (el /WAIT dura
20 ciclos más).

### Mapa de la SDRAM

| Configuración | `00_0000h` | `40_0000h` | `70_0000h`-`77_FFFFh` | `78_0000h` |
|---|---|---|---|---|
| `v9990` | mapper (sin uso) | megaROM (sin uso) | Nextor, FM-BIOS y PAC (sin uso) | **VRAM, 512 KB** |
| `v9990_megaram` | **megaROM, 4 MB** (32 KB borrados a FFh al arrancar) | mapper (sin uso) | Nextor, FM-BIOS y PAC (sin uso) | **VRAM, 512 KB** |

Sin bootloader nadie escribe las zonas sin uso.

### Configuración `v9990_megaram_nextor` (rama `hito/nextor`)

La de `v9990_megaram` más el cartucho Nextor de tnCart en la subranura 2
(`CARTRIDGE_NEXTOR` con su `TF_CONTROLLER`: el SPI de la microSD de la Tang como
el de la MegaFlashROM SCC+ SD) y la copia de su ROM de la flash (`10_0000h`) a la
SDRAM (`70_0000h`) al arrancar, con `FLASH_SPI` y un cargador propio
(`NEXTOR_LOADER`) en lugar del `BOOTLOADER` de tnCart. Arranque: `RESET_n` →
`MEGAROM_CLEAR` → copia (~69 ms) → `SYS_RESET_n`; `BOOT_HOLD` con tope de 200 ms
en esta configuración. Ningún reloj nuevo; los pines de la flash y de la TF los
conduce `MAIN` (en las demás configuraciones, en reposo). Las cuatro variantes de
la 0.1beta dan el mismo `.fs`. Detalle en [notas/nextor.md](notas/nextor.md).

| SDRAM en `v9990_megaram_nextor` | `00_0000h` | `40_0000h` | `70_0000h` | `72_0000h`-`77_FFFFh` | `78_0000h` |
|---|---|---|---|---|---|
| | megaROM, 4 MB | sin uso | **Nextor, 128 KB** | sin uso | VRAM, 512 KB |

### Registros nuevos de la megaROM (`v9990_megaram`)

Con la llave cerrada y `ENABLE`: `1Fh` bit 0 = modo PLAIN0 (ROM plana en
`0000h-BFFFh`; el /RESET del MSX borra el bit y `ENABLE`), y `3Eh` = `00h`
quiere decir 4 MB (256 bancos de 16 KB). Máximos por tipo: 4 MB con bancos de 16
KB y 2 MB con bancos de 8 KB (`-T KONAMI` para los Konami SCC de 1-2 MB). Las
ROM planas se cargan con `tncrom -T PLAIN0 -R` (`tools/tncrom`, r3, que las
rellena a 48 KB con FFh). Another World V9990 pide un turbo R. Detalle en
[megaram.md](notas/megaram.md), apartados 2, 4 y 6.

### Cruces de reloj nuevos

Ningún reloj nuevo (8/8 PRIMARY). Los cruces que añaden las áreas van todos por
los `set_clock_groups` que ya había:

| Cruce | Señales | Mecanismo | Consecuencia si falla |
|---|---|---|---|
| `CLK_BASE` → `CLK_TMDS_P` | `Video.PAL` | dos flops y toma al acabar el VSYNC de entrada (`VIDEO_UPSCAN`); `BOARD_REV1_TMDS_OUT` lo vuelve a tomar en la línea 20 de salida | un cuadro con la ventana de DE del otro sistema |
| `CLK_27M` → `CLK_BASE` | `DRIVE_EN_27`, `BOOT_HOLD_27` | en los pines del slot, combinacionales; para el contador del timeout, dos FF de `CLK_BASE` (`u_bus/drive_en_s`, `boot_hold_s`) | el timeout empieza a contar un ciclo antes o después |
| `CLK_BASE` → `CLK_27M` | `SYS_RESET_n && BUS_OK`, `WAIT_TIMEOUT` | dos FF en la guardia (`u_guard/ready_ff`, `wto_ff`) | un ciclo de 27 MHz más en `DRIVE_EN`/`BOOT_HOLD` o en el LED |
| `CLK_27M` → `CLK_BASE` | `PLL_OK` | `u_rst/base_ff`, afirmación asíncrona y suelta síncrona | ninguna (es un reset) |

Los márgenes del buffer de líneas del upscan, que en el hito 1 eran calculados,
ya están simulados (`fpga/tb/video`): 1021-1038 ciclos de 27 MHz con FIELD = 0 y
166-183 con FIELD = 1, iguales en PAL y en NTSC. El segundo driver de `R_ADDR`
en B4 lo resuelve Gowin como si esa línea no existiera (netlist simulado en
`fpga/tb/video/gowin_netlist`): con `BLEND = 1` el chip nunca enseña el punto
16k+1 de B4. El `create_generated_clock` de `DCLK` no cambia
(`cartridge_v9990.sv` conserva la OR de `dclk_en_ff`).

Siguen abiertos de la lista de riesgos del hito 1: el *glitch* posible de la OR
de `Video.DCLK` y la carrera de R/G/B (la vigila la puerta en cada build), el
reset sin sincronizador hacia `CLK_TMDS_P` (pide separar los resets del upscan)
y las E/S de la SDRAM y del slot sin `set_input_delay`/`set_output_delay`.
