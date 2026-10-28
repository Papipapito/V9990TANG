# Verificación

## Puerta de cada build

Toda build que se publique, o que cierre un hito, tiene que pasar esta puerta.
`tools/check_build.py` comprueba todos los puntos salvo la lectura de los avisos
del 5, que es manual, sobre el `.rpt.txt`, el `.tr`, el `.sdc`, el `.sdf` y los
logs de `gw_sh`. Si le falta algún dato obligatorio, la puerta sale
`INCOMPLETA` (código 2), nunca `PASA`; `--parcial` es para análisis que no son
la build de un hito, como la variante de comparación de más abajo.

1. **Restricciones aplicadas.** El `set_clock_groups` está en el *Timing
   Constraints Report* del `.tr` y sale `Actived`, ninguna orden sale en otro
   estado, y el `.tr` tiene las mismas órdenes que el `.sdc`. Con un reloj
   inexistente en una orden, el P&R de Gowin 1.9.12 aborta (`ERROR (TA2004)`,
   comprobado); la build de referencia del estudio esquivó el error borrando a
   mano el `set_clock_groups`, y sin grupos "timing cerrado" no decía nada (sus
   290 endpoints de setup violados venían de ahí). Comparar con el `.sdc` es lo
   que detecta una orden borrada o un `.sdc` editado después de la build (Gowin
   reimprime las órdenes leyendo el fichero). Ninguna excepción (false path,
   multiciclo, retardo máximo...) puede nombrar `DCLK` ni `CLK_BASE` salvo el
   false path del reset hacia `DCLK`.
2. **0 endpoints violados** en setup y hold, y peor slack ≥ 0 en las tablas de
   setup, hold, recovery y removal. Cada tabla tiene que estar y llevar su
   informe global (solo `-setup`/`-hold`/`-recovery`/`-removal`, `-max_paths` y
   `-max_common_paths`): un `report_timing` con cualquier otro filtro en el
   `.sdc` sustituye la tabla por defecto de su tipo, y entonces la puerta falla.
   La carrera `CLK_BASE` → `DCLK` tiene que salir analizada en setup y en hold
   (con caminos), el informe de setup `DCLK` → `CLK_BASE` tiene que estar, y no
   puede aparecer en ninguna tabla un camino lanzado desde `DCLK` hacia otro
   reloj (haría optimista el modelo de `DCLK`).
3. **Fmax de `CLK_BASE` ≥ 109 MHz** (108 MHz de restricción y un 1 % de margen).
4. **Recursos**: frente a la referencia del hito (±1 %); CLS ≤ 9 331 (90 %), con
   aviso desde 9 250 que no hace fallar la puerta; **PRIMARY ≤ 8**; **rPLL 2/2**.
   Las BSRAM se controlan con la tolerancia frente a la referencia (el chip
   tiene 46).
5. Un log de síntesis y uno de P&R, reconocidos por su contenido, completos, el
   de P&R con la fecha de esta build, y sin errores. Los avisos se leen uno a
   uno: la herramienta los lista por código, leerlos es manual.
6. **Modelo de `DCLK`**: el `create_generated_clock` de `DCLK` del `.sdc`
   coincide con el que usó el STA (periodo de 4 ciclos de `CLK_BASE`, maestro
   `CLK_BASE`, subida igual al `-offset`), `DCLK` va en el mismo grupo que
   `CLK_BASE` y ningún `set_clock_groups` los separa, y
   con el SDF de la build el flanco real de `Video.DCLK` no llega antes que el
   modelado (ver [ARCHITECTURE.md](ARCHITECTURE.md#dclk-va-con-clk_base)). El
   `.rpt.txt`, el `.tr` y el `.sdf` tienen que ser de la misma build (fechas).

Para las cuatro builds de la 0.1beta, desde la raíz del repositorio y
después de `cd fpga && gw_sh build_<variante>.tcl`, con la referencia de cada
variante (la de las builds archivadas en `fpga/reports/v0.1beta/` y
`fpga/reports/fusion/`, sección [Builds de la 0.1beta](#builds-de-la-01beta)):

```
python tools/check_build.py fpga/impl/pnr/v9990_xtal --ref-logic 13653 --ref-cls 8421 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_xtal.log --log fpga/impl/pnr/v9990_xtal.log --sdc fpga/constraints/v9990_xtal.sdc
python tools/check_build.py fpga/impl/pnr/v9990_sync --ref-logic 13874 --ref-cls 8489 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_sync.log --log fpga/impl/pnr/v9990_sync.log --sdc fpga/constraints/v9990_sync.sdc
python tools/check_build.py fpga/impl/pnr/v9990_megaram_xtal --ref-logic 15168 --ref-cls 9019 --ref-bsram 29 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_megaram_xtal.log --log fpga/impl/pnr/v9990_megaram_xtal.log --sdc fpga/constraints/v9990_megaram_xtal.sdc
python tools/check_build.py fpga/impl/pnr/v9990_megaram_sync --ref-logic 15253 --ref-cls 8973 --ref-bsram 29 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_megaram_sync.log --log fpga/impl/pnr/v9990_megaram_sync.log --sdc fpga/constraints/v9990_megaram_sync.sdc
```

Las referencias del hito 1 (la orden de abajo) ya no valen para el árbol
fusionado: la lógica difiere más del 1 % y la puerta daría FALLA en una build
buena. Si un cambio de RTL mueve los recursos a propósito, la build nueva se
pasa con `--sin-ref "motivo" --compara LOGICA,CLS,BSRAM` (la referencia
anterior, como cifra de comparación) y sus cifras pasan a ser la referencia.

Para la build del hito 1 (rama `main`), desde la raíz del repositorio y
después de `cd fpga && gw_sh build_v9990_xtal.tcl`:

```
python tools/check_build.py fpga/impl/pnr/v9990_xtal --ref-logic 14140 --ref-cls 8696 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 --log fpga/impl/gwsynthesis/v9990_xtal.log --log fpga/impl/pnr/v9990_xtal.log --sdc fpga/constraints/v9990_xtal.sdc
```

Los dos logs son los que escribe el propio `gw_sh` en `impl/`, así que no hace
falta redirigir su salida. El `-offset` de `DCLK` se lee del `.sdc`
(`--dclk-offset` solo sirve para confirmarlo). Para guardar la evidencia,
`python tools/archive_build.py fpga/impl/pnr/v9990_xtal fpga/reports/hito1`
(se niega a archivar si el `.sdc` o el `.fs` no son de esa build; con
`--compare otro.fs`, repetible, anota si el cuerpo de otros bitstreams es
idéntico: el `v9990_xtal.fs.txt` del hito 1 se hizo con dos, y repetir el
archivado sin ellos borra esas líneas), y después la orden de arriba con la
salida redirigida a
`fpga/reports/hito1/check_build.txt` (desde cmd o bash: el `>` de PowerShell 5.1
la guardaría en UTF-16). La misma orden sobre lo archivado repite la puerta sin
recompilar: ruta base `fpga/reports/hito1/v9990_xtal`, logs
`fpga/reports/hito1/gwsynthesis.log` y `pnr.log`, y
`--sdc fpga/reports/hito1/v9990_xtal.sdc` (el `.sdf` por defecto ya es el
extracto archivado).

La puerta no cubre la interfaz con la SDRAM embebida (`O_sdram_*`,
`IO_sdram_dq`), que no está restringida en el `.sdc` (como en tnCart y en el
MoonTANG): su margen depende de dónde caen los registros que la manejan y se
valida en placa.

## Builds medidas

Gowin 1.9.12.03, GW2AR-LV18QN88C8/I7, place 2, route 1. La evidencia de la
build del hito 1 está en [`fpga/reports/hito1/`](../fpga/reports/hito1/):
`tools/archive_build.py` guardó el `.rpt.txt`, el `.tr`, el `.sdc` con el que se
compiló, los dos logs de `gw_sh`, un extracto del `.sdf` con lo que usa la
comprobación del modelo de `DCLK` y las sumas del `.fs`; `check_build.txt` es la
salida de la puerta.

| | Referencia del estudio | **Hito 1: `v9990_xtal`** |
|---|---|---|
| Qué es | tnCartWonder con la configuración v9990 y su `board_wt200b_27M.sdc` sin las dos líneas de `CLK_21M` (sin `set_clock_groups`) | el mismo RTL, compilado desde este repositorio con `fpga/constraints/v9990_xtal.sdc` |
| Lógica (LUT + ALU) | 14 140 (11 551 + 2 589) | **14 140** (11 551 + 2 589), igual |
| Registros | 6 173 | 6 173 |
| CLS | 8 696 (84 %) | **8 679 (84 %)**, −0,20 % |
| BSRAM | 24/46 | **24/46** |
| rPLL / CLKDIV / PRIMARY / LW | 2/2, 3/8, 8/8, 7/8 | **2/2**, 3/8, **8/8**, 7/8 |
| `set_clock_groups` | ausente | **Actived** (y las otras 15 órdenes) |
| Endpoints violados: setup / hold | 290 / 0 | **0 / 0** |
| Peor slack: setup / hold | −7,190 / +0,074 ns | **+0,092 / +0,074 ns** |
| Peor slack: recovery / removal | −1,716 / +0,448 ns | **+5,990 / +0,460 ns** |
| Fmax `CLK_BASE` (108 MHz) | 111,58 MHz | **109,08 MHz** |
| Carrera `CLK_BASE` → `DCLK` (setup / hold) | sin cifra propia: sin grupos, el STA la analizó con el modelo /7,5 de tnCart y su relación espuria de 4,62 ns (de ahí el recovery de −1,716 ns) | +1,912 / +4,351 ns (setup en el modelo lento; en el rápido, que Gowin no analiza para setup, se estima en ~1,5 ns) |
| Fmax `CLK_TMDS_P` (27 MHz) | 69,4 MHz | 65,9 MHz |

- **Puerta del hito 1: pasa.** Salida completa en
  [`check_build.txt`](../fpga/reports/hito1/check_build.txt).
- **La Fmax tiene poco margen.** El peor camino es del blitter
  (`u_blit/state_3` → `ENQUEUE_DATA_17/CE`, 7 niveles, 0,092 ns de slack). Una
  variante con el mismo RTL y `DCLK` tratado como en tnCart (modelo /7,5 y grupo
  asíncrono propio) da 120,32 MHz con la misma lógica y los mismos 8 679 CLS, y
  su peor camino también es del blitter (`state_3` → `work_5/CE`): la diferencia
  es colocación, que cambia con el `.sdc`, no diseño. Está archivada en
  [`variante_dclk_asincrono/`](../fpga/reports/hito1/variante_dclk_asincrono/)
  (no es la build del hito: no vigila la carrera `CLK_BASE` → `DCLK`). La Fmax de
  la referencia (111,58 MHz) tiene los mismos 7 niveles, pero su `.tr` no lista
  caminos de `CLK_BASE`: los 25 de su tabla de setup son cruces del upscan. Es la
  cifra que hay que vigilar cuando entren los parches del hito 2.
- **El P&R es determinista.** Las compilaciones con el mismo RTL y las mismas
  órdenes en el `.sdc` (cambiando solo comentarios, y con o sin SDF) dieron el
  mismo cuerpo de bitstream (CheckSum `0x69C5`); solo cambia la línea
  `Created Time` de la cabecera. Quedan guardadas las sumas de tres (la del
  hito, la anterior con otro comentario y una sin SDF y con otros comentarios)
  en [`v9990_xtal.fs.txt`](../fpga/reports/hito1/v9990_xtal.fs.txt).
- **Avisos del log**: los de síntesis son los mismos que en la referencia
  (módulos barridos del mezclador de sonido, del `EXPANSION_RAM` y del SPI de la
  TF; entradas `TF_DAT0` y `UART_RX` sin uso) y uno de P&R, también en la
  referencia: `PR1014`, `CLK_27M_d` llega a un CLKDIV por enrutado genérico (solo
  afecta al jitter de `CLK_DAC`).

## Builds de la 0.1beta

Los cuatro `.fs` de [`bitstream/`](../bitstream/) son copias byte a byte de los
de `fpga/impl/pnr/` de las builds del 28 de octubre de 2026 sobre `055c865`
(último cambio de RTL y de opciones de P&R; después solo cambia
documentación), con Gowin 1.9.12.03. La puerta se repitió sobre esas builds
con las órdenes de arriba y **pasa en las cuatro**, con desviación +0,00 %
frente a la referencia. Evidencia en `fpga/reports/v0.1beta/<variante>/`
(`check_build.txt` es la salida de la puerta; `<variante>.fs.txt`, las sumas del
bitstream y la comparación del cuerpo frente a `fpga/impl/final/`: idéntico).
Son las mismas builds de la tabla de [Builds de la fusión](#builds-de-la-fusión),
que tiene el resto de cifras:

| | `v9990_xtal` | `v9990_sync` | `v9990_megaram_xtal` | `v9990_megaram_sync` |
|---|---|---|---|---|
| Fichero en `bitstream/` | `v9990tang_wt202b_v9990_xtal_0.1beta.fs` | `v9990tang_wt202b_v9990_sync_0.1beta.fs` | `v9990tang_wt202b_megaram_xtal_0.1beta.fs` | `v9990tang_wt202b_megaram_sync_0.1beta.fs` |
| Referencia de la puerta (lógica / CLS / BSRAM) | 13 653 / 8 421 / 24 | 13 874 / 8 489 / 24 | 15 168 / 9 019 / 29 | 15 253 / 8 973 / 29 |
| Fmax `CLK_BASE` | 111,763 MHz | 115,873 MHz | 121,542 MHz | 125,925 MHz |
| CheckSum de Gowin | `0x345D` | `0x7B75` | `0x95F1` | `0x4693` |
| SHA-256 (12 primeros) | `f668f7abbfc8` | `5f5369227e3e` | `eca3b40eba33` | `3812094d40d5` |
| md5 del cuerpo (sin `//`) | `aa4b16ac` | `0017f68e` | `97bb2bee` | `c194119b` |

El SHA-256 completo está en `bitstream/SHA256SUMS.txt`, junto con el de
`TNCROM.COM` r3 (13 700 bytes, `5f40a90d4918...`, el de `tools/tncrom/bin/`).

### Bancos sobre el árbol de la 0.1beta

Repetidos sobre `055c865`, sin cambios de RTL después. Todos en WSL con
Verilator 5.020 salvo `tb/megaram` y `tb/top`, que se lanzan desde Git Bash
porque llaman a WSL ellos mismos. El detalle de cada banco está en su nota de
área.

| Banco | Orden | Resultado |
|---|---|---|
| core | `cd fpga && bash tb/core/run_t9990_core.sh geom`, y luego con `pal blit ports eor r16 r16chg bdbp assert hito1` | pasan todos: los 15 casos de `geom`, `PALT_OK`, `BLIT_OK`, `PORTS_OK`, `EOR_OK`, `R16_OK`, `R16CHG_OK`, `BDBP_OK`, `ASSERT_SELFTEST_OK` y vídeo idéntico al hito 1 en los 7 casos; `LOST_SLOTS=0` |
| core, paleta y replay de GNG | `bash tb/core/run_t9990_palette.sh`; `OBJTAG=rep REPLAY=... bash tb/core/run_t9990_core.sh replay` | `PAL_OK`; VRAM idéntica a openMSX (0 de 524 288 bytes distintos) |
| sdram | `bash fpga/tb/sdram/run.sh` | `TOTAL: PASA` (48 casos a 108 y 107,386 MHz y los controles negativos) |
| bus | `bash fpga/tb/bus/run.sh`; `run_eq.sh`; `run_m1spur.sh` | 20 de 20 `BUS_OK` (fallos solo donde se esperan, a 7,16 y 10,74 MHz); `EQ_OK` en MODE 0 y 1; `M1SPUR_OK` en los 6 casos |
| integ | `bash fpga/tb/integ/run.sh` | pins: 150 casos, 968 comprobaciones, 0 fallos; guardia: 11 escenarios por `SYNC`, incluidos `busok` y `usb` |
| video | `bash fpga/tb/video/run.sh` | 121 de 121 |
| megaram | `cd fpga/tb/megaram && bash run.sh` (Git Bash) | 17 variantes, 25 `RESULTADO: PASA`, 0 `FALLA` |
| tncrom | `tools/tncrom/test/run.sh` (WSL) | 90 comprobaciones, 0 fallos |
| placa entera | `bash fpga/tb/top/run.sh` (Git Bash) | 12 de 12 (4 variantes por `full`, `io` y `nomsx`); 0 ranuras perdidas, 0 errores de SDRAM, 0 `WAIT_TIMEOUT`. MegaRAM a 5,37 MHz (medida, no contrato): 16 y 29 de 63 lecturas mal |

## Builds de la fusión

Gowin 1.9.12.03, rama `hito/fusion` en `c8e4fd2` (la fusión, el NOP de la
SDRAM en el reset y los arreglos de la guardia de la revisión); rehechas sobre
`055c865`, con el mismo cuerpo de `.fs`, y pasadas con referencia (`36f8f5b`). Cada variante
con las opciones de P&R de su `build_*.tcl`. Evidencia en
`fpga/reports/fusion/<variante>/` (`check_build.txt` es la salida de la
puerta); los `.fs`, en `fpga/impl/final/` y `fpga/impl/fusion_rev/` (git los ignora).

| | `v9990_xtal` | `v9990_sync` | `v9990_megaram_xtal` | `v9990_megaram_sync` |
|---|---|---|---|---|
| Opciones (place / route) | 2 / 2 | 2 / 2 | 0 / 2 | 2 / 2 |
| Lógica | 13 653 | 13 874 | 15 168 | 15 253 |
| CLS (máximo 9 331, aviso 9 250) | 8 421 | 8 489 | 9 019 | 8 973 |
| BSRAM | 24/46 | 24/46 | 29/46 | 29/46 |
| PRIMARY / rPLL | 8/8, 2/2 | 8/8, 2/2 | 8/8, 2/2 | 8/8, 2/2 |
| Endpoints violados (setup, hold, recovery, removal) | 0 | 0 | 0 | 0 |
| Peor slack: setup / hold | +0,312 / +0,074 ns | +0,682 / +0,074 ns | +0,368 / +0,074 ns | +1,095 / +0,074 ns |
| Peor slack: recovery / removal | +3,455 / +0,608 ns | +3,464 / +0,616 ns | +4,488 / +0,458 ns | +4,879 / +0,751 ns |
| Fmax `CLK_BASE` (mínimo 109) | 111,763 MHz | 115,873 MHz | 121,542 MHz | 125,925 MHz |
| Carrera `CLK_BASE` → `DCLK` (setup) | +0,864 ns | +1,238 ns | +0,368 ns | +1,095 ns |
| Margen del offset de `DCLK` (SDF) | +0,167 ns | +0,169 ns | +0,167 ns | +0,169 ns |
| `.fs`: CheckSum, md5 del cuerpo | `0x345D`, `aa4b16ac` | `0x7B75`, `0017f68e` | `0x95F1`, `97bb2bee` | `0x4693`, `c194119b` |

- **Puerta: pasa en las cuatro**, con `--sin-ref` (el RTL cambió) y
  `--compara` frente a las builds anteriores (`fpga/reports/sdram_nop/`):
  lógica −1,24 %, +0,58 %, +0,14 % y −0,05 %. Los avisos de síntesis y de P&R
  tienen los mismos códigos y en el mismo número que en esas builds.
- **Opciones de `v9990_megaram_sync`**: con las de antes (place 2, route 1)
  daba 109,50 MHz, al límite; con place 2 y route 2, 125,93 MHz (place 0 y
  route 2: 119,29), y pasa a ser su juego en `build_v9990_megaram_sync.tcl`.
  Las otras tres conservan el suyo. Cualquier cambio de RTL obliga a barrer
  otra vez las opciones de las cuatro: el margen más corto es el de
  `v9990_xtal` (111,76 MHz).

## Banco de placa entera (`fpga/tb/top`)

Simulación del top completo, `TNCART_BOARD_WT200B_TOP`, con la lista de
ficheros de `fpga/build_common.tcl` de cada configuración y variante: lo que
compila Gowin, salvo las restricciones. Verilator 5.020 con `--timing`, en
WSL. Cada área tiene su banco (core, sdram, bus, megaram, video, integ); este
las junta y les pone delante la placa y un MSX.

```
fpga/tb/top/run.sh                      # las cuatro variantes: full, io y nomsx
fpga/tb/top/run.sh v9990_megaram_sync   # una variante
RUNS="full" REUSE=1 fpga/tb/top/run.sh  # sin recompilar, un escenario
```

Se lanza desde Git Bash o desde WSL. Compila en `~/.tb_top_obj/<variante>`
(cada variante en 1-2 minutos) y deja los logs en `fpga/tb/top/build/`, que
no entra en git. Sale con 0 si todo pasa. El escenario `full` simula 128-132
ms en 20-25 minutos; los otros dos son más cortos.

**Qué hay alrededor del top** (nada de esto toca el RTL):

- **Relojes.** El cristal de 27 MHz y el CLOCK del slot a 3,579545 MHz. Los
  modelos de comportamiento de `gowin_models.sv` sustituyen a las primitivas
  de Gowin que Verilator no admite:
  - `rPLL`: enganchado en fase. Cada `IDIV_SEL + 1` flancos de entrada saca
    `FBDIV_SEL + 1` periodos. `CLKOUTP` es el mismo tren desplazado
    `PSDA_SEL`/16; con `"1000"`, el reloj de la SDRAM a 180 grados. `LOCK`
    sube tras 64 tramos estables y cae si la entrada se para. En `sync` la
    entrada es el CLOCK del slot.
  - `CLKDIV`: cuenta medios periodos, así que también divide por 3,5.
  - `MULT18X18`: el atenuador del sonido.
  - `DPB`: los modelos de los bancos de área, juntos en uno.

  El `DVI_TX` cifrado lo sustituye `tb/video/sim/dvi_tx_stub.sv`, y el banco
  mira lo que `BOARD_REV1_TMDS_OUT` le entrega.
- **Sintaxis.** `filelist.py` lee la lista de `build_common.tcl` y pone primero
  los paquetes. Copia cuatro ficheros con arreglos que Gowin no necesita y
  Verilator sí: un comentario en prosa que empieza por «Verilator» en
  `main.sv`, los `$bits(interfaz.Signal)` y `Uma.COUNT` que salen en
  constantes (cambiados por el valor que tienen en este diseño) y los
  `connect_dummy()` de `ExpBus[n]` dentro de un `generate`. Si el RTL cambia y
  una sustitución deja de casar, el banco no compila.
- **SDRAM.** El modelo de `tb/sdram` (`sdram_model_bl.v`), conectado a los
  pines `O_sdram_*` e `IO_sdram_dq`, con el reloj que saca el top.
- **Slot y MSX.** La placa y el Z80 de `tb/bus/tb_bus.sv`:
  - los tres 74LVC245 del multiplexor con sus retardos;
  - el transceptor de datos;
  - `/WAIT` e `/INT` por un NPN de 50/300 ns;
  - un Z80A con sus retardos máximos, que ejecuta instrucciones enteras:
    `OUT (n),A`, `IN A,(n)`, `LD A,(nn)` y `LD (nn),A` con su M1 y sus
    operandos, `HALT`, el reconocimiento de interrupción en IM 1 y su ISR;
  - el `/RESET` del MSX y el `/SLTSL` decodificado de `/MREQ`, refresco
    incluido;
  - la memoria del MSX, que contesta en las páginas que no son del cartucho.

**Escenarios.**

| Escenario | Z80 | Qué hace |
|---|---|---|
| `full` | 3,58 MHz | Las fases A a H y R, abajo |
| `io` | 5,37 MHz | Lo mismo sin los cuadros de vídeo: una sola `/INT` y un LMMV más corto. Las lecturas de la megaROM se cuentan pero no hacen fallar el banco |
| `nomsx` | — | Sin MSX: sin reloj del slot ni `/RESET` durante 12 ms |

Fases de `full`:

- **A. Arranque.** La FPGA arranca configurada y el MSX se enciende a los 0,1
  ms con `/RESET` bajo 1 ms. Se comprueban, en orden: el POR, el rPLL, la
  SDRAM, `RESET_n`, `SYS_READY`, `BUS_OK` y `DRIVE_EN`. El primer M1 del Z80
  se queda en `/WAIT` por `BOOT_HOLD` hasta que el sistema está listo. El LED
  pasa por los códigos 0, 1 y 5 y luego no se apaga. En MegaRAM, los 32 KB
  borrados a FFh en la SDRAM, sin pasarse.
- **B. Puertos.** P#5 en reposo, P#8-P#15 a FFh, un puerto ajeno (70h) en el
  que nadie conduce, y R#16 escrito y leído.
- **C. VRAM por P#0.** 64 bytes escritos y leídos, también comprobados en la
  SDRAM.
- **D. Paleta por P#1.** Ocho entradas con R, G y B distintos, escritas y
  leídas.
- **E. LMMV.** El fondo entero y un rectángulo de 64 x 32, esperando a que CE
  baje en P#5. El resultado se lee por P#0 y se comprueba en la SDRAM.
- **F. /INT del V9990.** VBlank activado con R#9; el Z80 la atiende desde un
  bucle de HALT, con INTA, `IN A,(66h)` y `OUT (66h),A`. El periodo tiene que
  ser el de un cuadro del V9990, y `/INT` tiene que soltarse al borrar VI.
- **G. Vídeo.** B1 BD8 con el borde de la paleta 5. NTSC: 855 x 524 con DE de
  720 x 480. Con R#7 PAL: 855 x 626 con DE de 720 x 576. Se cuentan los
  puntos de la imagen y del borde.
- **H. MegaRAM** (solo en `v9990_megaram`):
  - SCC-I RAM al arrancar: bancos de 8 KB, escrituras y lecturas.
  - La secuencia de `tncrom`: la llave cerrada y abierta, 3Eh, ASCII16 sin
    protección con bancos por 8000h (00h, 01h, 7Fh, 80h, FFh) comprobados en
    la SDRAM, el atributo final protegido, la lectura de vuelta por 4000h y
    8000h, y que con protección no se escribe.
  - PLAIN0: M1 y lecturas en 0000h-BFFFh, refrescos con I = 00h, escrituras
    ignoradas (la llave también), y que el `/RESET` lo borra.
  - El `/WAIT` de memoria: el histograma de TW por lectura.
- **R. /RESET del MSX** en medio de una lectura de P#0 con `/WAIT` subido. El
  Z80 no se queda colgado, la guardia se suelta, y el V9990 vuelve a
  contestar (P#5 y la VRAM por P#0).

**Comprobaciones activas en todos los escenarios:**

- El FPGA no conduce D0-D7 sin una lectura legítima, la INTA incluida.
  Tampoco 30 ns después de subir `/RD`, ni a la vez que el Z80 o la memoria
  del MSX.
- `WAIT_TIMEOUT` a 0.
- Cero ranuras de VRAM perdidas (la aserción de `t9990_ram.sv`).
- SDRAM:
  - cero errores del modelo;
  - cero capturas de lectura fuera de la ventana de dato válido;
  - nunca dos conductores en DQ;
  - solo NOP en los pines con el controlador en reset.
- El Z80 nunca retenido más de 3000 TW fuera del arranque.

**Resultados** (27/10/2026, árbol `389ce97`). Pasan los 12 casos, las cuatro
variantes por los tres escenarios. Lo que miden, en todas las variantes salvo
donde se dice:

| | |
|---|---|
| Arranque | `PLL_OK` a 3,64 ms (`sync`: 3,66), `BUS_OK` y `DRIVE_EN` a 6,07 ms (6,10). El primer M1 acaba a 6,07 ms tras unos 17 800 TW de `BOOT_HOLD`. LED: 0, 1 y 5 |
| E/S al V9990 | ~1 600 por escenario. TW máximo: 3 a 3,58 MHz y 6 a 5,37 MHz. Cero fallos a las dos velocidades |
| Vídeo NTSC | 524 líneas de 855 puntos y DE en 480 líneas de 720. Imagen: 10 176 puntos verdes (159 x 64) y 260 632 azules |
| Vídeo PAL | 626 líneas de 855 puntos y DE en 576 líneas de 720. La misma imagen y unos 65 000 puntos más de borde |
| `/INT` | Periodo de 16,594 ms (NTSC) y 19,824 ms (PAL). En `sync`, 16,688 y 19,937 ms, porque `CLK_BASE` es 107,386 MHz |
| MegaRAM a 3,58 MHz | 63 lecturas del slot, todas con 2-3 TW; 0 mal leídas |
| MegaRAM a 5,37 MHz | Entre 16 y 29 de las 63 lecturas mal leídas, sin contar como fallo. Es lo que ya decía `docs/notas/megaram.md`: a 5,37 MHz ningún pre-WAIT llega a tiempo |
| `/RESET` del MSX con `/WAIT` | El `/WAIT` del V9990 cae en el acto y `BOOT_HOLD` lo cubre. Al soltar el `/RESET`, el primer M1 acaba enseguida (`BUS_OK` no vuelve a esperar su ventana) y el V9990 contesta |
| `nomsx` | LED en el código 2 (`xtal`) o 0 (`sync`). `BUS_OK` y `DRIVE_EN` a 0, y nada conducido |
| Ranuras de VRAM perdidas, `WAIT_TIMEOUT`, choques en D0-D7 | 0 |

**Lo que encontró y se arregló:**

- **`sdram.sv`** (`389ce97`): `SDRAM_CMD` no tenía valor de reset. Mientras
  el reloj corre antes de `BASE_READY`, la SDRAM recibía `0000` (MODE
  REGISTER SET con A = 0 y una latencia CAS reservada) en cada flanco: 262 406
  flancos en el arranque. Tras una pérdida de enganche, además, repetía el
  último comando. Ahora el controlador pone NOP en el reset.
  - La prueba es la comprobación «solo NOP con el controlador en reset»:
    falla con el RTL de antes (log en
    `fpga/tb/top/build/control_sdram_cmd_sin_reset.log`, fuera de git) y pasa
    con el arreglo. `tb/sdram/run.sh` da las mismas cifras.
  - Las cuatro variantes se han vuelto a compilar con las opciones de P&R de
    la fusión y pasan la puerta frente a las builds de la fusión. Las cifras
    están en la tabla de abajo; la evidencia, en `fpga/reports/sdram_nop/`.

Builds con el arreglo (Gowin 1.9.12.03, árbol `389ce97`; puerta con
referencia en la build de la fusión de cada variante, `--tol 0.01`,
repetida sobre lo archivado):

| Variante | Opciones | Logic | CLS | BSRAM | Fmax `CLK_BASE` (fusión) | Setup / hold | Violados | Puerta | `.fs` (md5 del cuerpo, CheckSum) |
|---|---|---|---|---|---|---|---|---|---|
| `v9990_xtal` | place 2, route 2 | 13 824 | 8 493 (+0,22 %) | 24 | 113,534 MHz (119,478) | +0,451 / +0,074 ns | 0 | **PASA** | `3572fde9`, `0xFFB7` |
| `v9990_sync` | place 2, route 2 | 13 794 | 8 465 (+0,06 %) | 24 | 113,628 MHz (114,373) | +0,511 / +0,074 ns | 0 | **PASA** | `c8568efa`, `0x18D3` |
| `v9990_megaram_xtal` | place 0, route 2 | 15 147 | 9 050 (+0,04 %) | 29 | 125,429 MHz (122,956) | +1,119 / +0,074 ns | 0 | **PASA** | `0db63ce0`, `0x80B4` |
| `v9990_megaram_sync` | place 2, route 1 | 15 260 | 8 971 (+0,00 %) | 29 | 114,815 MHz (120,188) | +0,603 / +0,074 ns | 0 | **PASA** | `20eeddde`, `0xEBEE` |

En las cuatro: grupos de reloj `Actived`, 0 endpoints violados en setup,
hold, recovery y removal, 8/8 PRIMARY, 2/2 rPLL, CLS por debajo del aviso.
Los avisos de síntesis y de P&R son los mismos códigos, con las mismas
cuentas, que en las builds de la fusión; los de síntesis y P&R de
`v9990_megaram_sync` se han comparado línea a línea y son iguales. Los `.fs`
están en `fpga/impl/sdram_nop/`, que no entra en git. Con este cambio la
`Fmax` de `v9990_xtal` baja 6 MHz por la colocación, que se mueve entera.
Sigue por encima de los 109 MHz, pero cualquier cambio más del RTL obliga a
barrer otra vez.

**Lo que este banco no cubre**:

- Los retardos reales de los pines (en `sdram_model` la ventana de dato es
  fija), el serializador TMDS y la señal HDMI.
- El Z80 con retardos mínimos.
- 7,16 MHz.
- Una pérdida de enganche con el sistema en marcha. La cubre el banco de
  integ, pero sin SDRAM ni core.
- `BLEND = 0`: las cuentas de puntos con `BLEND = 0` no se han comprobado.
- `nomsx` llega a 12 ms, sin alcanzar el tope de 50 ms de `BOOT_HOLD`.

Las cifras son de un modelo, no de la placa.

## Pruebas en placa del hito 1

El usuario cargó el bitstream del hito 1 (`main` antes de la 0.1beta: core sin
parches, con el bootloader de tnCart) en su WonderTANG y, según él, funciona.
Aquí no consta con qué monitores ni con qué programas; conviene apuntarlos en
la matriz de abajo.

## Pruebas en placa de la 0.1beta

Sin hacer. La lista ordenada (arranque, HDMI en dos monitores, programa de
disco, ROMs de la lista del estudio, PAL, turbo, reset, LED y reloj del slot,
retención de la VRAM) y la tabla de resultados están en
[`bitstream/LEEME.md`](../bitstream/LEEME.md#lista-de-pruebas-en-placa).
Lo que el banco no cubre y solo se ve en placa: el `/WAIT` de la MegaRAM a
3,58 MHz con osciloscopio (en el banco el margen es de un ciclo de 108 MHz), el
enganche de `sync` en cada máquina, la aceptación de los modos en cada monitor,
una pérdida de enganche en marcha, el tope de 50 ms de `BOOT_HOLD` sin MSX y
las cuentas de puntos con `BLEND=0` (que ninguna build lleva).

## Matriz de monitores

Modos de salida (DVI sin audio, ninguno CEA; [WONDERTANG.md](WONDERTANG.md#vídeo)):

| Modo del V9990 | Visible | Cuadro | `xtal` (píxel 27,000 MHz) | `sync` (píxel 26,85 MHz) |
|---|---|---|---|---|
| NTSC (262 líneas) | 720x480 | 855x524 | 60,27 Hz | 59,92 Hz |
| PAL (313 líneas, R#7 bit 3) | 720x576 | 855x626 | 50,45 Hz | 50,16 Hz |

El hito 1 solo sacaba el NTSC de `xtal`. Los modos PAL y los de `sync` son los
que más pueden rechazar los monitores. Rellenar una fila por monitor, variante
y modo probados; anotar también si el monitor vuelve a enganchar al cambiar el
programa de NTSC a PAL.

| Monitor / TV (marca y modelo) | Entrada | Variante (`xtal`/`sync`) | Modo (NTSC/PAL) y frecuencia | Modo V9990 (B1-B7, P1/P2) | ¿Imagen? | Notas (sobrebarrido, parpadeo, tiempo de enganche, rechazo) | Quién y cuándo |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
