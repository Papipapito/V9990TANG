# Arquitectura

V9990TANG es, en el hito 1, la carcasa wt200b de tnCartWonder con el core tiny9990
de tnCart **sin cambios de RTL**: lo único propio son la configuración
(`fpga/config/v9990.sv`), el `.sdc` (`fpga/constraints/v9990_xtal.sdc`), el
script de build y la puerta (`tools/check_build.py`). Esta página describe ese punto de partida; cada hito siguiente
apunta aquí lo que cambia.

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
