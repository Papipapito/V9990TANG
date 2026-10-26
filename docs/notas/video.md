# Vídeo: salida PAL (576 líneas) y palanca BLEND del upscan

Parte de vídeo del hito 7 y palanca de CLS del plan (estudio, sección 9). Rama
`hito/video`. Ficheros tocados: `fpga/src/peripheral/video/video.sv`,
`fpga/src/peripheral/video/video_upscan.sv`, `fpga/src/board/rev1/board_rev1_tmds.sv`;
nuevos: el banco `fpga/tb/video/`, `fpga/check_video.tcl` y esta nota. Nada de esto
cambia la cadencia del UMA ni añade relojes.

El trabajo lo empezó un implementador que se cortó por un límite de sesión y lo han
revisado dos más (26/10/2026, por la mañana y por la tarde). En cada revisión se repasó
el RTL contra el original del hito 1, se comprobaron las citas de openMSX (en su
`master` de GitHub) y se volvieron a correr desde cero todas las pruebas y las síntesis
de abajo, con `build/` e `impl/` apartados antes: los resultados salen siempre los
mismos (las síntesis, con los `*_syn_rsc.xml` idénticos byte a byte). En la segunda
revisión el área core ya tenía el cuadro PAL commiteado en su rama (`hito/core`,
700baa1, "Core: cuadro PAL de 313 lineas (R#7 bit 3) y ajuste de posicion de R#16"):
las referencias a su RTL de abajo son a ese commit.

## Qué hace

### Campo PAL en VIDEO_IF

`VIDEO_IF.PAL`: 0 = el cuadro que llega del V9990 es el de 262 líneas, 1 = el de 313.
Está en los dos modports; `connect_dummy()` lo deja a 0 (sin V9990 la salida es la NTSC).
El chip real fija la temporización PAL al empezar cada cuadro con el bit 3 de R#7
(openMSX, `V9990.cc`, `frameStart()`: `palTiming = (regs[SCREEN_MODE_1] & 0x08) != 0`,
en el mismo sitio en que invierte el bit EO del estado).

### Upscan (VIDEO_UPSCAN)

- `IN.PAL` pasa al dominio de `CLK_TMDS_P` por dos flops y se toma **al acabar el VSYNC
  de entrada** (flanco de subida de `VS_n`, tres líneas de entrada después del de bajada,
  que es el que reinicia los contadores de salida). `OUT.PAL` cambia hacia la línea 6 de
  salida y vale para el cuadro que empezó con ese VSYNC.
- El contador vertical de salida ya lo reinicia solo el VSYNC de entrada (`out_v_rst = 0`),
  así que un cuadro de 313 líneas de entrada sale con 626 líneas; no hay que tocarlo.
- Buffer de 3 líneas, `IN_LINE`/`OUT_LINE` y bob: `IN_LINE` vuelve a `ROW_COUNT-1` y el
  contador de filas de salida a `FIELD ? 2 : 0` en cada VSYNC de entrada, así que la
  secuencia de filas de cada cuadro no depende de su número de líneas. El enganche de
  línea es el mismo (6840 ciclos de `CLK_BASE` por línea de entrada = 2 x 855 de
  `CLK_TMDS_P`), y el margen entre la última lectura de una
  posición del buffer y su reescritura medido en el banco es el mismo en PAL y en NTSC:
  1021-1038 ciclos de 27 MHz con FIELD = 0 y 166-183 con FIELD = 1 (según la fase de
  `CLK_TMDS_P`). Con 313 líneas el upscan enseña la línea k de entrada en las de salida
  2(k+2) y 2(k+2)+1 (FIELD = 0), igual que con 262.

### Salida (BOARD_REV1_TMDS_OUT)

`frame_pal` se toma durante la línea `V_PAL_LATCH = 20` de salida (después de que el
upscan actualice `PAL`, hacia la 6, y antes del primer DE, la 35) y elige la ventana
vertical de DE:

| | NTSC (`PAL` = 0), sin cambios | PAL (`PAL` = 1) |
|---|---|---|
| Total | 855 x 524 a 27 MHz, 60,27 Hz (`xtal`) / 59,92 Hz (`sync`) | 855 x 626 a 27 MHz, 50,45 Hz (`xtal`) / 50,16 Hz (`sync`) |
| Sincronismo vertical | líneas 0-1 | líneas 0-1 |
| DE | 720 x 480, líneas 35-514 | 720 x 576, líneas 42-617 (`V_BACKPORCH_PAL = 40`, pórtico delantero 8) |
| Líneas de entrada en DE (FIELD = 0) | 15 (la segunda copia) a 255 (la primera) | 19 a 306 |
| Horizontal | DE de 720 desde el ciclo 68 de la línea | igual |

La ventana PAL está centrada en la zona de borde e imagen del V9990 PAL: openMSX
(`V9990DisplayTiming.hh`) da `displayPAL_MCLK = {cycle 313, blank 15, border1 41,
display 212, border2 37}` y `displayNTSC_MCLK = {262, 15, 14, 212, 14}`; el tiny9990 en
NTSC pone 3 líneas de sincronismo y 18 de borrado contando el sincronismo, 14 de borde,
212 de imagen, 14 de borde y 4 de borrado (`t9990_timing.sv`, `V212_*`), que es la tabla
de openMSX leyendo `blank` como lo que sigue a 3 líneas de sincronismo. openMSX cuenta
desde el VSYNC y pone el principio de la imagen en `blank + border1` más el ajuste de
R#16 (`V9990.hh`, `getTopBorder()`; -1 con R#16 = 0): la línea 28 en NTSC y la 55 en PAL,
cuatro antes que el tiny9990 en NTSC (32); lo que se traslada al PAL es la diferencia,
27 líneas más de borde superior en los dos. Con el mismo arranque que el NTSC del
tiny9990, la zona de borde e imagen PAL son las líneas de entrada 18-307 (290, imagen en
la 59-270), salen en las 40-619 y la ventana 42-617 deja fuera 2 líneas de salida arriba
y 2 abajo. Esto **supone** que el área core pone el cuadro PAL así (sincronismo de 3
líneas en la línea 0 y borde desde la 18); si no, la ventana se mueve con
`V_BACKPORCH_PAL = 2a + 4`, con `a` la primera línea de borde.

El área core (rama `hito/core`, 700baa1) pone el cuadro PAL justo así, con R#16 = 00h
(con otro valor mueve el sincronismo frente a la imagen; ver "Riesgos"):
`t9990_timing.sv`, `V212P_*` = 18 de borrado arriba contando 3 de sincronismo, 41 de borde, 212 de imagen, 37 de borde y 5 de borrado (313), y `V290P_*`
= 18 + 290 + 5 en B2/B4 (openMSX `displayPAL_XTAL = {313, 15, 0, 290, 0}`). En B2/B4 la
imagen son 290 líneas de entrada (580 de salida) y la ventana de 576 deja fuera la primera
y la última: 290 no caben en 288. En NTSC la ventana de tnCart del hito 1 (35-514, las
líneas de entrada 15-255) también recorta: de la imagen de 240 líneas de B2/B4
(`V240_*`, líneas 18-257) se pierden las dos últimas, y en B1/B3 las dos últimas del
borde inferior.

La clase 576p de CEA-861 (VIC 17/18) son 864 x 625 a 27 MHz: 576 líneas activas, 5 de
pórtico delantero, 5 de sincronismo y 39 de pórtico trasero; en horizontal 720 + 12 + 64
+ 68 (tabla `edid_cea_modes_1` de `drivers/gpu/drm/drm_edid.c` de Linux; la 480p, VIC 2,
es 858 x 525 con 480 + 9 + 6 + 30). Esta salida pone 2 + 40 + 576 + 8 = 626 y 855 de
total: no es CEA, como no lo es la NTSC de tnCart (2 + 33 + 480 + 9 = 524, 855 x 524). El
primer DE cae en la línea 42 contando desde el sincronismo, frente a la 44 de CEA. Que
los monitores acepten 855 x 626 a 50,45 / 50,16 Hz solo se sabe probando.

NTSC queda igual bit a bit que en el hito 1: con `PAL` = 0 la ventana es la misma
constante y `frame_pal` no cambia nunca. Comprobado en el banco contra la copia del
hito 1, ciclo a ciclo (y en síntesis, con `PAL` sin conducir, salen los mismos recursos
que en el hito 1).

### Palanca BLEND

Parámetro `BLEND` en `VIDEO_UPSCAN` y `VIDEO_UPSCAN_STRETCH_BUFFER`, 1 por defecto.

- `BLEND = 1`: la mezcla lineal de tnCart, sin cambios (los sumadores y el registro `OUT`
  están movidos dentro de un bloque `generate`, línea a línea iguales).
- `BLEND = 0`: replicación del punto más cercano con los mismos estados (`out_state`),
  las mismas latencias y la misma ventana `OUT_EN`; sin sumadores. En cada salida sale el
  punto de más peso en la mezcla de tnCart (`R_DATA_P` o `R_DATA_C`, el empate hacia
  `R_DATA_C`), que es el más cercano al centro de la salida:

  | Modo | Escala | Puntos de entrada por periodo (salida -> entrada) | Repeticiones |
  |---|---|---|---|
  | B1 | 288 -> 720, x5/2 | 0 0 1 1 1 | 2 y 3 |
  | B2 | 384 -> 720, x15/8 | 0 0 1 1 2 2 3 4 4 5 5 6 6 7 7 | 1 y 2 |
  | B3 | 576 -> 720, x5/4 | 0 1 2 2 3 | 1 y 2 |
  | B4 | 768 -> 720, x15/16 | 0-7, 9-15 (se salta el 8) | 1, 48 puntos saltados por línea |

  En B4 la lectura de tnCart (+2 en el estado 0) no lee nunca el punto 16k+1 (el
  `ToDo: 最初に2バイト読む` del original), y con `BLEND = 1` ese punto no sale; elegir
  por peso sobre esa lectura repetiría el 16k y perdería el 16k+1. Por eso con
  `BLEND = 0` B4 tiene su propio avance de `R_ADDR` (+2 en el estado 7) y saca siempre el
  punto leído. El empate de la salida 7 (centro en 8,0) se resuelve a la izquierda.
  B5/B6 (que el core no genera) usan la misma regla que B3 con `RATIO_1_125`.
- El segundo driver de `R_ADDR` del original (`default: R_ADDR <= R_ADDR` en el `case`
  de `OUT` para B4) sigue en `BLEND = 1`; `BLEND = 0` no lo tiene. Simulado el netlist de
  Gowin: se comporta como el RTL **sin** esa línea, y Verilator (con `-Wno-MULTIDRIVEN`)
  como si ganara el "mantener" (la primera lectura de cada línea en B4 no avanza 2). El
  banco compila las dos cosas (abajo).

## Contratos con la integración y con el área core

1. **`cartridge_v9990.sv` tiene que conducir `Video.PAL`** con la salida PAL del T9990
   (área core, `hito/core` 700baa1: la salida se llama `PAL`, así que `.PAL(Video.PAL)` en
   la instancia `u_vdp`, junto al `.EO(Video.FIELD)` que ya hay). Hasta que el core esté en
   la integración, `assign Video.PAL = 1'b0;`. Sin conducir,
   Gowin avisa `EX0211 ... "Video_PAL" ... has no driver, assigning undriven bits to Z`
   y el valor que acabe usando no está garantizado.
2. **Cuándo puede cambiar `PAL`**: tiene que valer el del cuadro N al acabar el VSYNC de
   entrada del cuadro N y no antes de que acabe el VSYNC del cuadro N-1. Medido con el
   banco (`run.sh pallag`, B1 y B4, PAL alternando cuadro a cuadro): pasa con `IN.PAL`
   cambiando desde 258 líneas antes del flanco de bajada de `VS_n` que abre el cuadro
   (con el cuadro anterior NTSC) hasta 3 líneas después (20 520 ciclos de `CLK_BASE`, el
   flanco de subida de `VS_n`); falla con 259 líneas antes y con 21 000 ciclos después.
   Lo natural en el core, fijarlo en `v_rst` como `STATUS.EO` (un ciclo de `CLK_BASE`
   antes de que `Video.VS_n` baje), queda con casi 3 líneas de margen; puede ir directo o
   registrado con `Video.DCLK`. Lo que tiene el área core (`hito/core` 700baa1) cumple:
   su salida `PAL` del `T9990` (`PAL_FRAME` = `pal_s` de `t9990_timing.sv`, tomado al
   empezar cada cuadro de sincronismo y pasado por un registro de `CLK`, `pal_q` en
   `t9990.sv`) cambia en el mismo flanco que su salida `VS`, también con R#16 (el cuadro
   de sincronismo es el que va de VS a VS), y `cartridge_v9990.sv` registra `vs` en el flanco
   siguiente de `Video.DCLK` para sacar `Video.VS_n`: con `assign Video.PAL = pal;`
   directo, `PAL` cambia como mucho un periodo de `DCLK` (20 ciclos de `CLK_BASE` en B1)
   antes de que baje `Video.VS_n`, dentro del margen medido.
3. **BLEND**: el top (`tnCart_board_wt200b_top.sv`) no pasa `BLEND`; para elegirlo por
   configuración, `.BLEND(CONFIG::...)` en la instancia `u_upscan` y la constante en
   `fpga/config/v9990.sv`. Por defecto (1) la salida es la de tnCart. Con `BLEND = 0` la
   Fmax de `CLK_BASE` de la P&R medida (la misma las dos veces que se corrió: el P&R de
   Gowin es determinista) queda en 108,67 MHz (camino del blitter): la build que lo active
   tiene que pasar la puerta de Fmax por su cuenta.
4. **`.sdc`**: no cambia. `Video.PAL` cruza de `CLK_BASE` (o `DCLK`) a `CLK_TMDS_P`, grupos
   asíncronos: el camino ya está cortado, como `FIELD` e `INTERLACE`. Para la tabla de
   cruces de `docs/ARCHITECTURE.md`: "`CLK_BASE` -> `CLK_TMDS_P`, `Video.PAL`, dos flops
   y toma al final del VSYNC de entrada; si falla, un cuadro con la ventana de DE del
   otro sistema". La salida de `frame_pal` hacia el DE es de `CLK_TMDS_P` a `CLK_TMDS_P`
   y la analiza el STA.
5. **Documentación**: en `docs/VERIFICATION.md`, la matriz de monitores necesita filas
   para 855 x 626 a 50,45 Hz (`xtal`) y 50,16 Hz (`sync`); en `docs/ARCHITECTURE.md`, el
   upscan "escala a 720x480 o 720x576" y el parámetro `BLEND`. En la tabla de cruces de
   `docs/ARCHITECTURE.md`, la fila del buffer de líneas dice "márgenes calculados (~1020
   ciclos con FIELD=0, ~165 con FIELD=1), no simulados": ahora están simulados (1 021-1 038
   y 166-183 ciclos de 27 MHz según la fase, `run.sh`, en NTSC y en PAL). Y en "Riesgos
   que el .sdc no cubre", el segundo driver de `R_ADDR`: el netlist de Gowin simulado se
   comporta como el RTL sin esa línea (`gowin_netlist/run_nl.sh`), es decir, en el chip,
   con `BLEND = 1`, B4 avanza 2 en el primer ciclo de cada línea y no enseña nunca el
   punto 16k+1 (Verilator, con `-Wno-MULTIDRIVEN`, deja ganar el "mantener").
6. **Disposición del cuadro PAL en el core**: la ventana supone la zona de borde e imagen
   en las líneas de entrada 18-307 (sección "Salida"). Si el core la pone en otro
   sitio, la integración cambia `V_BACKPORCH_PAL`.

## Cómo se prueba

Todo en WSL (`wsl -e bash -lc "cd /mnt/c/.../fpga/tb/video && ..."`), Verilator 5.020 e
Icarus 12. Salidas en `fpga/tb/video/build/` (ignorado por git).

Resultados de las revisiones del 26/10/2026, con `build/` apartado antes (las dos dan
lo mismo que el primer implementador, cifra a cifra; en la segunda, la matriz tardó unos
20 minutos con 6 casos en paralelo, `pallag` 13 y `mutants.sh` 3):

| Orden | Qué es | Resultado |
|---|---|---|
| `./run.sh` | Banco `tb_video.sv` (Verilator) con la matriz de 121 casos | 121 de 121 pasan: 425 549 749 ciclos de 27 MHz comparados con el hito 1 sin diferencias en VS/HS/RGB, 190 282 766 de DE en cuadros NTSC sin diferencias; 305 cuadros NTSC y 317 PAL comprobados por instancia; líneas de entrada en DE (FIELD = 0) 15-255 en NTSC y 19-306 en PAL; margen del buffer 1 021-1 038 ciclos con FIELD = 0 y 166-183 con FIELD = 1; B4 con `BLEND = 0`, 48 puntos saltados en todas las líneas |
| `./run.sh pallag` | Barrido del desplazamiento de `IN.PAL` respecto de `VS_n` (26 valores, B1 y B4) | pasa de -258 líneas a +20 520 ciclos; falla en -259 líneas y en +21 000 ciclos (los extremos se eligieron para fallar) |
| `./mutants.sh` | 14 fallos metidos a propósito en el RTL (ventanas de DE, toma de PAL en el upscan y en la salida, coeficientes de la mezcla, elección del punto más cercano, avance de B4, filas y bob); el banco tiene que rechazarlos | 14 de 14 detectados |
| `gowin_netlist/run_nl.sh` | Netlist de Gowin (`run syn` de un `VIDEO_UPSCAN_STRETCH_BUFFER`, Icarus + `simlib/gw2a/prim_sim.v`) frente al RTL, para el hito 1, `BLEND = 1` y `BLEND = 0`; antes, en Windows, `NL_VAR=hito1|b1|b0 gw_sh build_nl.tcl` | 5 de 5 comparaciones iguales (10 360 ciclos) |
| `sim/run_dpb_check.sh` | Modelo `sim/dpb_sim.sv` del DPB frente al de la simlib de Gowin (Icarus) | 54 052 lecturas, 0 diferencias |
| `./make_ref.sh` | Regenera `ref/`: el upscan y la salida del hito 1 (commit 20936e6) con los módulos renombrados `*_ORIG`; `ref/SHA256SUMS` guarda las huellas y `run.sh` las comprueba | — |

**El banco.** Fuente sintética con la temporización del V9990 en tnCart: `CLK_BASE` de
108 MHz; enables del UMA con `DIV = 30` (21,6 MHz cada 5 ciclos, 14,4 MHz en 0/7/15/22
de cada 30); divisor de `t9990_clock.sv` (B1 21M/4, B2 14M/2, B3 21M/2, B4 14M/1);
`Video.DCLK` como en `cartridge_v9990.sv` (OR de `dclk_en` retrasado 1 y 2 ciclos: pulso
de 2 ciclos); línea de 342/456/684/912 puntos (1368 de 21,6 MHz = 6840 ciclos), HS de
25/34/50/68 puntos (`t9990_timing.sv`), VS de 3 líneas, cuadro de 262 o 313 líneas,
INTERLACE/FIELD y tres patrones (rampa con el número de línea y de cuadro, puntos
alternos 00/FF, ruido). `CLK_TMDS_P` de 27 MHz = 108 x 5/4 / 5 (rPLL TMDS y CLKDIV de
`board_wt200b_clock.sv`), mesócrono con una fase `+PHASE` que se barre. Tres instancias
con la misma entrada: la copia del hito 1 (`ref/`), `BLEND = 1` y `BLEND = 0`, cada una
con su `BOARD_REV1_TMDS_OUT`; se mira lo que entra al DVI_TX (VS, HS, DE, R, G, B; el
IP cifrado se sustituye por `sim/dvi_tx_stub.sv`). Comprueba:

- totales 855 x 524 y 855 x 626, DE de 720 x 480 en las líneas 35-514 y de 720 x 576 en
  las 42-617, DE en el mismo ciclo de cada línea, líneas de 855 ciclos;
- en cada línea de DE, que la línea de entrada que sale es la esperada (B = número de
  línea, G = cuadro y FIELD en el patrón de rampa), cuadro a cuadro: sin saltos ni
  repeticiones, también en los cambios de PAL, modo e INTERLACE;
- que el hito 1 y `BLEND = 1` dan lo mismo en VS, HS y RGB en todos los ciclos y en DE en
  todos los cuadros NTSC;
- caja blanca de los buffers: `OUT` de `BLEND = 1` igual a la mezcla
  ((2^k - wc)·P + wc·C) >> k de cada estado y `OUT` de `BLEND = 0` igual al punto de más
  peso; mismos estados en las dos; en B4 con `BLEND = 0`, `R_ADDR` contra su modelo;
- `BLEND = 0`: con puntos alternos 00/FF solo salen 00 o FF (7F en la línea atenuada del
  entrelazado), y en la rampa cada punto sale las veces de la tabla de arriba;
- el margen entre la última lectura útil de una posición del buffer y su reescritura.

`obj/` es el RTL tal cual; `obj_chip/` es el mismo RTL sin el segundo driver de `R_ADDR`
(`sin_driver.py`), que es lo que hace el chip: los casos `CHIP_*` repiten B4 con él.

Los casos de la matriz: B1-B4 x PAL 0/1 x INTERLACE 0/1 x tres patrones; B4 PAL
entrelazado y B1 NTSC entrelazado con seis fases de `CLK_TMDS_P`; una secuencia de 24
cuadros que cambia modo, PAL e INTERLACE, con dos patrones; PAL alternando cuadro a cuadro en B1-B4 con y
sin entrelazado y cinco desplazamientos de `IN.PAL` (un ciclo antes de `VS_n`, el mismo,
3 ciclos y 2 líneas después y 250 líneas antes); y B4 con lo que hace el chip.

En las secuencias, el cambio de modo mueve la rejilla de `DCLK` y la última línea del
cuadro que acaba sale con 854 ciclos: pasa igual en el hito 1 (las dos salidas son
idénticas ciclo a ciclo) y el banco lo cuenta aparte.

## Síntesis

`fpga/check_video.tcl` parte de `build_v9990_xtal.tcl` (mismos ficheros, orden y
opciones) y elige con variables de entorno: `VIDEO_SRC=hito1` (los tres ficheros de
vídeo del commit 20936e6), `VIDEO_BLEND=0` (copia de `video_upscan.sv` con el valor por
defecto de `BLEND` a 0), `VIDEO_PAL=live` (copia de `cartridge_v9990.sv` con
`assign Video.PAL = Video.INTERLACE;`, una señal viva de registro solo para medir la
lógica PAL; con `none` `PAL` queda sin conducir y se pliega) y `VIDEO_PNR=1` (además
P&R). Uso: `cd fpga && VIDEO_BLEND=0 VIDEO_PAL=live gw_sh check_video.tcl`. Gowin
1.9.12.03, GW2AR-LV18QN88C8/I7.

Síntesis (`run syn`, `impl/gwsynthesis/<base>_syn_rsc.xml`; LUT / ALU / FF / BSRAM):

| Variante | Total | `u_upscan` | `u_tmds` |
|---|---|---|---|
| hito 1 (`VIDEO_SRC=hito1`), la referencia | 11 565 / 2 166 / 6 173 / 24 | 1 230 / 1 308 / 289 / 6 | 268 / 69 / 148 / 0 |
| `BLEND = 1`, `PAL` sin conducir | 11 565 / 2 166 / 6 173 / 24 | 1 230 / 1 308 / 289 / 6 | 268 / 69 / 148 / 0 |
| `BLEND = 1`, `PAL` vivo | 11 543 / 2 167 / 6 178 / 24 | 1 232 / 1 308 / 292 / 6 | 273 / 69 / 150 / 0 |
| `BLEND = 0`, `PAL` sin conducir | 11 003 / 893 / 6 173 / 24 | 710 / 35 / 289 / 6 | 269 / 69 / 148 / 0 |
| `BLEND = 0`, `PAL` vivo | 11 074 / 891 / 6 178 / 24 | 723 / 33 / 292 / 6 | 272 / 69 / 150 / 0 |

- La cifra de partida del encargo (`u_upscan` 1 227 LUT / 1 308 ALU / 289 FF / 6 BSRAM)
  es la del estudio, medida en la síntesis de la configuración `full` de tnCart (sección
  3 del estudio, "Lo que cuesta cada módulo"); en el árbol
  del hito 1 de este repo, con esta misma herramienta, `u_upscan` sale 1 230 / 1 308 /
  289 / 6: las comparaciones de abajo van contra esta segunda.
- Con `PAL` sin conducir los recursos son exactamente los del hito 1 (el `PAL` se
  pliega). La lógica PAL viva cuesta 2 LUT y 3 FF en el upscan y 5 LUT y 2 FF en la
  salida; el total baja 22 LUT por el ruido de la síntesis en otros módulos.
- `BLEND = 0` ahorra en el upscan **509 LUT y 1 275 ALU** (con `PAL` vivo; 520 y 1 273
  sin conducir), los mismos FF y BSRAM; en el total, 469 LUT y 1 276 ALU (562 y 1 273).
  El ruido entre módulos ronda las 50-70 LUT (las dos `BLEND = 0` difieren en 71 LUT de
  total y solo 13 en el upscan). Las 33-35 ALU que quedan son de contadores o
  direcciones (no se han desglosado).
- El buffer solo, fuera de contexto (`gowin_netlist/`, un canal): 434 LUT / 451 ALU /
  77 FF con `BLEND = 1` (igual que el del hito 1) y 198 / 12 / 77 con `BLEND = 0`.
- Avisos de la síntesis (`WARN` y `ERROR` del `.log`): los mismos 8 que el hito 1 en
  todas las variantes (entradas sin usar y módulos barridos), más el `EX0211` de
  `Video_PAL` cuando `PAL` va sin conducir. Ninguno de los ficheros de vídeo da avisos
  nuevos; el segundo driver de `R_ADDR` no lo avisa Gowin ni en el hito 1.

P&R (`VIDEO_PNR=1`, con `fpga/constraints/v9990_xtal.sdc`; place 2, route 1), las dos
con `PAL` vivo, y la puerta de `tools/check_build.py` en modo `--parcial` (sin `.sdf`, así
que el punto 6, el modelo de `DCLK`, queda sin comprobar), con las referencias del hito 1
(`--ref-logic 14140 --ref-cls 8679 --ref-bsram 24 --tol 0.01 --max-cls 9331 --rpll 2
--fmax CLK_BASE=109`). Repetidas en las dos revisiones: los `.rpt.txt` salen iguales
línea a línea a los de la primera vez salvo fechas y tiempos de CPU, y en la segunda el
cuerpo de los dos `.fs` es idéntico al de la anterior (solo cambia `//Created Time`).
`BLEND = 1` pasa la puerta parcial;
`BLEND = 0` la suspende en la lógica y los CLS (-14 % y -11 % frente a la referencia de
±1 %, que es lo que se busca) y en la Fmax de `CLK_BASE` (108,669 MHz frente a 109):

| | hito 1 (`fpga/reports/hito1/`) | `BLEND = 1`, `PAL` vivo | `BLEND = 0`, `PAL` vivo |
|---|---|---|---|
| Lógica (LUT + ALU) | 14 140 (11 551 + 2 589) | 14 117 (11 529 + 2 588) | **12 134** (11 060 + 1 074) |
| Registros | 6 173 | 6 178 | 6 178 |
| **CLS** | 8 679 (84 %) | 8 658 (84 %) | **7 744 (75 %)** |
| BSRAM / PRIMARY / rPLL | 24 / 8 / 2 | 24 / 8 / 2 | 24 / 8 / 2 |
| Endpoints violados (setup / hold) | 0 / 0 | 0 / 0 | 0 / 0 |
| Peor slack setup / hold / recovery / removal (ns) | 0,092 / 0,074 / 5,990 / 0,460 | 0,120 / 0,074 / 3,955 / 0,830 | 0,057 / 0,074 / 5,393 / 0,321 |
| Carrera `CLK_BASE` -> `DCLK` setup / hold (ns) | 1,912 / 4,351 | 1,588 / 4,637 | 1,967 / 4,660 |
| Fmax `CLK_BASE` / `CLK_TMDS_P` (MHz) | 109,08 / 65,9 | 109,42 / 63,7 | **108,67** / 135,4 |

- `BLEND = 0` ahorra **914 CLS** y 1 983 de lógica en P&R, mucho más que los 190-310
  CLS que estimaba el estudio (sección 9, "Bitstreams de la 1.0"): con `BLEND = 0` el
  bitstream `v9990` queda en el 75 % de los CLS.
- La lógica PAL viva no se ve en P&R (-21 CLS frente al hito 1, dentro del ruido de
  colocación).
- **La Fmax de `CLK_BASE` con `BLEND = 0` sale 108,67 MHz**, por debajo de los 109 de la
  puerta (que pide un 1 % de margen sobre 108), aunque cierra a 108 MHz sin endpoints
  violados. El peor camino es del blitter (`u_port/vdp_reg[52]` -> `u_blit/work_23`,
  slack 0,057 ns), no del vídeo: es la colocación, como la diferencia de Fmax que
  `docs/VERIFICATION.md` ya documenta entre dos `.sdc`. Una build de hito con `BLEND = 0`
  puede no pasar la puerta de Fmax sin tocar el blitter.

## Riesgos y lo que no está comprobado

- **En placa, nada**: ni 855 x 626 en ningún monitor ni `BLEND = 0` a la vista. Un cambio
  de PAL cambia el número de líneas del cuadro (524 <-> 626) y el monitor se volverá a
  enganchar, como en cualquier cambio de modo.
- **El banco no usa el `T9990` real**: la fuente es sintética, con la disposición del
  cuadro PAL que tiene el área core en `hito/core` (700baa1: VS de 3 líneas en la línea 0,
  borde desde la 18, leída de su `t9990_timing.sv`, no simulada aquí). El core no está en
  `main` y su banco (`fpga/tb/core/` de su árbol) es suyo; cuando la integración junte
  las dos ramas hay que mirar con el `T9990` (en un banco de la integración o en placa)
  dónde caen el borde y la imagen PAL dentro de la ventana 42-617.
- **Ramas sin simular contra el modelo**: las de `RATIO_1_125` (macro no definida en este
  repo) y B5/B6 (el core no las genera) de `g_nearest` solo están compiladas (Verilator
  `--lint-only` con y sin la macro, sin errores) y, B5/B6, comparadas netlist de Gowin
  frente a RTL en `gowin_netlist/`; la caja blanca de `tb_video.sv` cubre B1-B4 sin la
  macro.
- **R#16 y la ventana fija**: el ajuste vertical de R#16 mueve la imagen respecto del
  sincronismo de -7 a +8 líneas de entrada (openMSX, `V9990.hh`, `getTopBorder()`), es
  decir de -14 a +16 líneas de salida, y la ventana de DE no se mueve: en PAL solo hay 1
  línea de entrada de borde fuera de la ventana arriba y 1 abajo, así que con R#16 se
  recorta borde (B1/B3) o imagen (B2/B4, que no tienen borde), como en NTSC con la ventana
  de tnCart. Es lo que haría un monitor con la imagen corrida; no se ha simulado con el
  core. El área core ya tiene R#16 (`ENABLE_R16 = 1` en `hito/core`, mueve HS/VS frente a
  la ventana y deja la ventana quieta), así que este recorte se verá en cuanto un
  programa ponga en R#16 un ajuste vertical distinto de 0.
- **Entrelazado PAL**: como en NTSC, bob con FIELD (el tiny9990 no hace medias líneas).
- **B4 con `BLEND = 1`** sigue sin enseñar el punto 16k+1 (defecto de tnCart que se
  conserva a propósito: la salida tiene que ser la del hito 1).
- **El segundo driver de `R_ADDR`** sigue en `BLEND = 1`: Gowin y Verilator lo resuelven
  distinto en el primer ciclo de cada línea en B4; el netlist simulado manda.
- **Fmax con `BLEND = 0`**: 108,67 MHz en `CLK_BASE` (0 endpoints violados a 108; la
  puerta pide 109). El camino es del blitter y depende de la colocación: el P&R es
  determinista y con este árbol sale siempre igual, pero cualquier cambio en otro módulo
  la mueve.
- **Margen del buffer con FIELD = 1**: 166 ciclos de 27 MHz (6,1 µs) en el peor caso
  medido, propio de tnCart, igual en PAL.
