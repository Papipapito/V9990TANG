# Core tiny9990: hitos 2 y 7

Rama `hito/core` (desde `main`, hito 1). Solo toca `fpga/v9990/tiny9990/*.sv`;
añade los bancos de `fpga/tb/core/`, `fpga/check_core.tcl` y esta nota. Nada de
la carcasa (top, `main.sv`, `cartridge_v9990.sv`, UMA, SDRAM, upscan, `.sdc`,
`build_v9990_xtal.tcl`, `config/v9990.sv`) cambia: lo que la integración tiene
que hacer está en [Contratos](#contratos-para-la-integración).

Fuentes que se citan: openMSX (copia de `src/video/v9990/` del repositorio
público: `V9990.cc`, `V9990.hh`, `V9990DisplayTiming.hh`,
`V9990BitmapConverter.cc`, `V9990SDLRasterizer.cc`, `V9990VRAM.hh`) y el
*V9990 E-VDP-III Application Manual* de Yamaha (páginas del manual impreso).

## Qué cambia en el core

| # | Cambio | Ficheros | Fuente del comportamiento |
|---|---|---|---|
| 1 | **C25M es el bit 6 de R#7** (era el 7) | `t9990_port.sv` | manual pág. 81 (R#7: C25M bit 6, SM1 bit 5, SM bit 4, PAL bit 3, EO bit 2, IL bit 1, HSCN bit 0) |
| 1 | **El maestro de 25 MHz solo con HSCN** (GNG pone R#7 = 40h en B1 y salían columnas de puntos) | `t9990_clock.sv` | manual pág. 81: "C25M: selection of 640x480 mode, valid when HSCN is 1" |
| 1 | **BD16**: la capa de paleta transparente (PRI = 1), los dos bytes del píxel en orden little-endian, YS (bit 15) enmascarado | `t9990_bitmap.sv`, `t9990_color_decode.sv` | openMSX `V9990BitmapConverter.cc` `rasterBD16`: `low + 256 * high` con el byte bajo en la dirección par; sin superimpose el bit 15 no cuenta |
| 1 | **Leer G por P#1 devolvía B** (`PLTP_R` dos veces) | `t9990_palette.sv` | openMSX `V9990.cc` `peekIO`: `palette[regs[PALETTE_POINTER]]`, el componente al que apunta el puntero |
| 1 | **LMCM y POINT** entregan el byte del carril del píxel (antes siempre el cuarto byte de la palabra) | `t9990_blit.sv` | parche del MSXimus Z, comprobado con `+BLIT=1` (4 píxeles distintos) |
| 2 | `char` → `chr` en el *union* del blitter (Verilator, y Vivado, no admiten `char` como nombre) | `t9990_blit.sv` | — |
| 3 | **P#8-P#15 leen FFh** de forma explícita (ya era así por la rama por defecto de `CD_OUT`: el estudio decía "dato rancio" y no lo era). P#4 y P#7 también FFh | `t9990_port.sv` | openMSX `V9990.cc` `peekIO`: `KANJI_ROM_1/3` "not used in Gfx9000" → FFh; `REGISTER_SELECT`, `SYSTEM_CONTROL`, `KANJI_ROM_0/2` y `default` → FFh |
| 4 | **Cuadro PAL de 313 líneas** con el bit 3 de R#7 fuera de B5/B6: sincronismo 3, borrado superior 15, borde 41, imagen 212, borde 37, borrado inferior 5; en overscan (B2/B4) los bordes son imagen, 290 líneas. El bit se toma al empezar cada cuadro. Parámetro `ENABLE_PAL` | `t9990_timing.sv`, `t9990_port.sv`, `t9990.sv` | manual pág. 103 (tabla "Vertical synchronous signal, display data timing (PAL)") y pág. 81 (PAL "invalid when in B5 and B6"); openMSX `V9990DisplayTiming.hh` `displayPAL_MCLK = {313, 15, 41, 212, 37}`, `displayPAL_XTAL = {313, 15, 0, 290, 0}`; `V9990.cc` `frameStart` (`palTiming` se fija al empezar el cuadro) |
| 5 | **Cursor con la semántica de openMSX**. Parámetro `ENABLE_CURSOR_EOR` (detalle abajo) | `t9990_sprite.sv`, `t9990_priority.sv`, `t9990_palette.sv`, `t9990_selector.sv`, `t9990.sv`, `t9990_timing.sv` | openMSX `V9990BitmapConverter.cc` (`CursorInfo`, `convertLine` y el comentario "reverse engineered from tests on a real gfx9000"), `V9990SDLRasterizer.cc` `drawBxMode`, `V9990.hh` `getCursorYOffset`; manual pág. 49 (10.13, "Cursor display specifications") |
| 6 | **R#16** (ajuste de la posición de la imagen). Parámetro `ENABLE_R16` (detalle abajo) | `t9990_timing.sv`, `t9990_port.sv` | openMSX `V9990.hh` `getLeftBorder`/`getTopBorder`; manual pág. 84 (R#16) |
| 7 | **Aserción de ranura de VRAM perdida**, solo simulación (`ifndef SYNTHESIS` + `translate_off/on`): `TIMING.EXEC` con `state != STATE_WAIT_REQ` → `$error` con el instante y cuenta en `lost_slots` | `t9990_ram.sv` | estudio, sección 5 |
| 8 | **Fondo de los modos de paleta tras un modo de color directo**: fuera de BD8/BD16/YJK/YUV la salida de `T9990_COLOR_DECODE` vuelve al valor del reset (8000h) en vez de quedarse como estaba; el selector la usa donde la paleta es transparente (índice 0 de BP2/BP4, fondo de P1/P2) y tras un BD16 esos puntos salían con el último color directo hasta el siguiente reset. Anterior a este hito (revisión del área) | `t9990_color_decode.sv` | desde el reset el core ya daba el fondo (prueba `bdbp`: cuadro de BP4 desde el reset) |
| 9 | **El blitter toma START (escritura de R#52) un ciclo después**, con la decodificación de STOP registrada: quita del camino crítico de la build completa R#52 → `REG.OP == CMD_STOP` → cadena de prioridades del blitter (7 niveles). El comando hace lo mismo 9 ns más tarde | `t9990_blit.sv` | por tiempo (revisión del área); `BLIT_OK` y el *replay* de GNG con la VRAM idéntica a openMSX |

No se llevan las salidas `DE`/`DISP` del MSXimus Z.

### Cursor (`ENABLE_CURSOR_EOR = 1`)

- **EOR y CC** (openMSX `CursorInfo`/`convertLine`): `(CC, EOR) = (0, 1)` pinta
  el color de 15 bits de debajo XOR 7FFFh (el único caso multicolor);
  `CC ≠ 0` pinta el color de paleta `{R#28, CC}`, XOR 7FFFh si además EOR;
  `(0, 0)` es invisible; el bit 4 del atributo oculta el cursor; el cursor 0
  tapa al 1, también con EOR en los dos (no se aplica dos veces). El XOR va en
  `T9990_SELECTOR`, solo dentro de la imagen (sin bordes). Antes `t9990.sv`
  dejaba `.EOR()` sin conectar y el cursor salía de un color plano.
- **Línea Y+1, Y+2 con entrelazado** (manual pág. 49: "the specified Y
  co-ordinate plus 1 (plus 2 for interlace)"; openMSX `attrY += isInterlaced()
  ? 2 : 1`). Con entrelazado y EO la Y va en **líneas del cuadro**,
  `{línea del campo, EO}` como el bitmap (`drawBxMode`: `cursorY` de 2 en 2,
  +1 en el campo impar). El tiny9990 lo pintaba en la línea Y y en líneas del
  campo. El +1/+2 se resta en `t9990.sv` sobre la línea del cursor, que va
  **registrada** (`cur_line_q`) a `T9990_SPRITE`, y este solo resta la Y del
  atributo, como en el hito 1: con la línea combinacional (multiplexor,
  overscan y las dos restas del sprite en serie) la build completa no cerraba
  a 108 MHz (revisión del área). El banco comprueba que en ningún ACK de
  lectura del sprite la línea registrada difiere de la combinacional.
- **Overscan** (B2/B4: MCS = 1 sin HSCN): la Y cuenta desde la línea 14 de la
  imagen, 41 en PAL (`getCursorYOffset` = `border1` de `displayNTSC_MCLK` /
  `displayPAL_MCLK`; openMSX deja anotado que no sabe si R#16 influye, y aquí
  no influye).
- **Primera línea de imagen**: `T9990_SPRITE` lee en cada línea lo de la
  siguiente y lo saca desde `SPR_START`. En la línea anterior a la primera (sin
  bitmap) la lectura podía acabar antes de su propio `SPR_START` y se gastaba
  en el borde: en B1 BD16 un cursor con Y de 480 a 511 no salía en la línea 0.
  Ahora no hay `SPR_START` en esa línea (`ENABLE_SPR_LINE0` de
  `T9990_TIMING`, atado a `ENABLE_CURSOR_EOR`).
- **Color alineado en color directo**: `T9990_PALETTE` saca la transparencia
  del punto k con el color del punto k+1 (hito 1). En BD8/BD16/YJK/YUV/YAE,
  donde esa transparencia elige entre paleta (cursor) y bitmap, el último
  punto de cada tramo del cursor salía con el color de fondo; en los puntos
  del cursor se toma ahora su propio color. En BP2/BP4/BP6 cursor y bitmap van
  en la misma capa y salen como en el hito 1 (el EOR se alinea con el color
  que sale en cada caso).

### R#16 (`ENABLE_R16 = 1`)

Desplazamiento respecto a R#16 = 00h de `k = (n ^ 7) − 7` pasos por eje (`n` =
nibble): 0 posición estándar, 1..7 = 1..7 pasos a la izquierda/arriba, Fh..8 =
1..8 a la derecha/abajo. Es la fórmula de openMSX menos su valor con R#16 = 00h
(`getLeftBorder`/`getTopBorder` suman `((R16 & 0Fh) ^ 7) − 8` y `((R16 >> 4) ^
7) − 8`, −1 con R#16 = 00h) y la escala del manual (pág. 84: "8 9 ··· 15 0 1
··· 6 7", Down/Right … Standard … Up/Left).

- **Unidades.** Vertical: una línea (openMSX y manual). Horizontal: el manual
  da "P1 and B1 by 1 dot unit, P2, B2 and B3 by 2-dot unit, B4, B5 and B6 by
  4-dot unit", 4 ciclos del reloj maestro en todos los modos. openMSX suma 8
  *ticks* de su reloj unificado de 42,95 MHz (`UC_TICKS_PER_SECOND = 3579545 *
  12`, 2736 por línea): 4 ciclos del maestro de 21 MHz en P1/P2/B1/B3, donde
  coincide con el manual, pero 8/3 ciclos del de 14 MHz en B2/B4 (4/3 de punto
  en B2, 8/3 en B4), que no caen en puntos enteros. **Se sigue el manual**: en
  B2/B4 el paso es de 2 y 4 puntos (en P1/P2/B1/B3 es lo mismo que openMSX).
- **Cómo.** Hay dos pares de contadores en `T9990_TIMING`. Los del
  **sincronismo** (`s_h`/`s_v`: HS, VS, `FIELD`, `PAL`) corren libres con las
  reglas del hito 1 y **no se reajustan nunca**: el cuadro de VS a VS y la
  línea de HS a HS son siempre los mismos, escriba el programa lo que escriba
  en R#16. Es lo que hace openMSX: `V9990.cc` `frameStart` programa el
  siguiente VSYNC a `frameStartTime + getUCTicksPerFrame(palTiming)`, sin
  R#16, y el principio de la imagen a `frameStartTime + getTopBorder() *
  UC_TICKS_PER_LINE` (y `VSCAN` a `getBottomBorder`), con R#16. Los de la
  **ventana** (`h_cnt`/`v_cnt`: bordes, lectura de VRAM, HR/VR,
  interrupciones, bitmap, sprites) van desplazados frente al sincronismo
  `adj_v` líneas y `adj_h` puntos. Con R#16 = 00h los dos pares coinciden
  ciclo a ciclo y HS, VS y EO son los del hito 1 (prueba `hito1`).
- **Cuándo y dónde se aplica un cambio.** Una vez, en el borrado de la
  ventana, con la diferencia entre el desplazamiento nuevo y el que está en
  vigor. Vertical (−15..+15 líneas), al acabar el cuadro de la ventana: si la
  imagen baja, el cuadro de la ventana se alarga esas líneas (`v_cnt` sigue
  más allá de `V_TOTAL`, donde no hay ninguna comparación); si sube, el
  cuadro siguiente empieza en su línea 1..15 (se salta líneas del borrado
  superior, donde solo está el VS propio de la ventana, que no sale).
  Horizontal (−60..+60 puntos), en la línea 16 de la ventana (borrado superior
  en todos los modos, y el reajuste vertical nunca se la salta), en el punto
  `H_HR_ACTIVE + 80`: `h_cnt` repite o se salta esos puntos; 60 puntos a cada
  lado de ese punto no hay ninguna comparación de `h_cnt` en ningún modo, y en
  una línea de borrado solo hay accesos de CPU/blitter y refresco, que van por
  `MEM_REQ`. La irregularidad de un cambio queda así en el cuadro de la
  ventana (como mucho dos cuadros de imagen, de VI a VI, de ± 15 líneas + 60
  puntos), como en openMSX, y nunca en el sincronismo que llega al upscan. Un
  cambio de modo (MCS, DCKM, HSCN, C25M) baja `TG_EN` (`T9990_CLOCK`) y pone a
  0 los dos pares y el desplazamiento en vigor: el cuadro siguiente aplica
  R#16 desde 0. R#16 y el punto del reajuste pasan por dos registros antes de
  llegar a los contadores (tiempo).
- **Versiones anteriores.** La primera movía el sincronismo en el (0,0) de la
  ventana (dos VS a 2 líneas con R#16 de F0h a 10h, 509 líneas sin VS de 70h a
  80h: revisión de Codex); la segunda lo movía en la línea 12 de la ventana:
  ya no había VS dobles en B1-B4, pero cada cambio dejaba un cuadro de VS a VS
  de 262/313 ± 16 líneas y una línea de HS a HS de ± 60 puntos, que el upscan
  sacaba por HDMI como un cuadro de 524 ± 32 líneas (un programa que escriba
  R#16 en cada cuadro, un temblor, los daría todos irregulares), y en B5 (VS
  de 8 líneas) el reajuste caía dentro del VS con un ajuste de −5..−7 líneas y
  salía un segundo VS (revisión del área, 26/10/2026). La prueba `r16chg`
  nueva falla con la segunda versión (ver Resultados).
- **PAL y R#16.** El bit PAL se toma al empezar el cuadro de sincronismo
  (`pal_s`, que da la salida `PAL`) y la ventana lo copia al final de su
  línea 15 (`pal_w`): el VS cae como mucho 8 líneas antes o después del (0,0)
  de la ventana, el reajuste vertical se salta como mucho las líneas 0..14 y
  ninguna comparación de la ventana que dependa de PAL cae antes de su línea
  17, así que los dos cuadros que van juntos tienen la misma longitud.

## Interfaz de `T9990`

```
module T9990 #(
    parameter ENABLE_PAL        = 1,   // cuadro PAL de 313 lineas con R#7 bit 3
    parameter ENABLE_CURSOR_EOR = 1,   // cursor de openMSX (EOR, Y+1, entrelazado, overscan, linea 0, color)
    parameter ENABLE_R16        = 1    // ajuste de posicion de R#16
) ( ... los mismos puertos del hito 1 ...,
    output wire EO,                    // paridad del campo, alineada con VS (ver abajo)
    output wire PAL                    // nuevo: 1 = el cuadro en curso es el de 313 lineas
);
```

- **`PAL`** (nuevo): 1 mientras el cuadro que se está generando (de VS a VS)
  es el de 313 líneas. Cambia solo en el límite de cuadro, en el mismo flanco
  de `CLK` en que sube la salida `VS` (los dos pasan por un registro). Es 0 en
  B5/B6 aunque R#7 tenga el bit 3, y siempre 0 con `ENABLE_PAL = 0`.
- **`EO`**: con R#16 = 00h es el `STATUS.EO` de siempre. Con R#16 distinto de
  00h es la paridad del campo de la ventana que va con ese VS (el de la
  ventana cambia en el (0,0) de la ventana, que ya no coincide con el VS).
  Cambia solo con VS.
- **`HS`/`VS`**: siempre regulares (de VS a VS 262, 313, 440 líneas; de HS a
  HS los puntos del modo), también mientras el programa cambia R#16. Con
  R#16 ≠ 00h la imagen (DE, R, G, B) se mueve frente a ellos (−7..+8 pasos y
  −7..+8 líneas); con R#16 = 00h no cambia nada frente al hito 1.
- Los tres parámetros se pueden poner a 0 por separado; con los tres a 0 el
  core es el del hito 1 más los cambios 1-3, 8 y 9 de la tabla y la aserción
  (que no sintetiza).
- La lista de ficheros del core no cambia (17 ficheros en
  `fpga/v9990/tiny9990/`), ni el orden de compilación.

## Contratos para la integración

1. **Conectar `PAL`**. `cartridge_v9990.sv` instancia `T9990` sin `.PAL`
   (compila: un puerto de salida sin conectar es legal). Para el cuadro de
   313 líneas el upscan tiene que saber que viene: hace falta un campo nuevo
   en `VIDEO_IF` (p. ej. `Video.PAL`) que `cartridge_v9990.sv` capture en
   `posedge Video.DCLK` como `video_vs_n`, y que el upscan use para la
   salida de 855x626 / 720x576 (estudio, sección 9, "Vídeo"). Sin eso, con
   R#7 bit 3 el core da 313 líneas y el upscan, que reinicia su cuadro con el
   VS de entrada (`out_v_rst = 0`), sacaría 626 líneas con la temporización
   vertical de 480.
2. **`EO`/`Video.FIELD`** no cambia de significado con R#16 = 00h. Con R#16 ≠
   00h el upscan sigue muestreando `FIELD` en el VS (`out_line_toggle <=
   IN.FIELD`), que es justo lo que ahora está alineado.
3. **R#16 en HDMI.** El upscan cuenta su ventana de entrada desde el flanco de
   HS (`IN_EN` fijo por modo) y su cuadro desde el VS, así que la imagen se
   mueve en la salida, recortada por esa ventana fija (estudio, riesgos). El
   sincronismo que le llega es siempre regular, también cuando el programa
   cambia R#16 (ya no hace falta que el upscan aguante cuadros de entrada de
   ± 16 líneas: eso era de la versión anterior). Si no se quiere el efecto o
   falta sitio: `T9990 #(.ENABLE_R16(0))`.
4. **Parámetros.** Por defecto los tres a 1. Para medir o recortar:
   `T9990 #(.ENABLE_PAL(0) | .ENABLE_CURSOR_EOR(0) | .ENABLE_R16(0))` en
   `cartridge_v9990.sv`.
5. **Aserción.** Cualquier banco que incluya el core cuenta las ranuras de
   VRAM perdidas en `u_vdp.u_ram.lost_slots` (jerarquía desde `T9990`) y saca
   un `$error` por cada una; los bancos de integración pueden exigir 0. Gowin no
   la ve.
6. **Documentación** que no es de esta área: `build_v9990_xtal.tcl` dice "core
   V9990: tiny9990 ... sin parches", `UPSTREAM.md` dice "sin parches" y
   `docs/ARCHITECTURE.md` describe el hito 1; hay que apuntar estos cambios
   (y la salida `PAL`) en ellos y en `docs/changelog.md`.
7. **Referencia de la puerta.** La orden de `tools/check_build.py` de
   `docs/VERIFICATION.md` compara la lógica con la del hito 1 (`--ref-logic
   14140 --ref-cls 8696 --tol 0.01`). Con este core la build completa da Logic
   14 508 (+2,60 %) y CLS 8 769 (+0,84 %): la puerta sale `FALLA` solo por la
   lógica, con todos los puntos de tiempo bien (Fmax 114,431 MHz). La
   integración tiene que fijar la referencia de su build (con las otras áreas
   dentro) en `docs/VERIFICATION.md`. El ruido de síntesis de Gowin pasa del 1 %
   de la lógica con cambios pequeños (el prototipo del revisor, que solo
   registraba la línea del cursor y R#16, dio 160 de lógica menos que el árbol
   revisado, y en esta build `u_boot` y `u_blit`, que no cambian, suben 28 y
   45 LUT frente a la del prototipo): una tolerancia del 1 % frente a la
   referencia del hito 1 no distingue un cambio de diseño del ruido.
8. **El blitter arranca un ciclo después** de la escritura de R#52 (`f0fa14d`,
   por tiempo). Nada de fuera lo ve (STATUS.CE sube 9 ns más tarde); un banco
   de integración que mire CE justo en el ciclo siguiente a la escritura tiene
   que esperar uno más.

## Cómo se prueba

Bancos en `fpga/tb/core/`, Verilator 5.020 en WSL (el core no compila en
Icarus). Los dos scripts se pueden lanzar desde Git Bash o desde WSL; los
objetos quedan en `~/.cache/v99tang_core/` de WSL.

- `tb_t9990_core.sv` (el `tb_t9990_timing.sv` del MSXimus Z portado) +
  `run_t9990_core.sh [prueba ...]`.
- `tb_t9990_palette.sv` + `run_t9990_palette.sh` (`PAL_OK`).
- `tb_vram_uma.sv`: los enables y la VRAM como los ve el core en la
  WonderTANG. Instancia el **`uma.sv` real** de tnCart (`DIV = 30`,
  `SYNC_CLK_EN = 0` como la variante `xtal`): `CLK21M_EN` 6 de cada 30
  ciclos, `CLK14M_EN` 4/30, `CLK25M_EN` 7/30 y el `TIMING` del canal 1 cada 20
  ciclos, 2 después del enable de 21 MHz. Detrás, un modelo de `sdram.sv`
  ciclo a ciclo en su lado del UMA (9 estados, `ACK_n` en el ciclo siguiente a
  la aceptación y de vuelta a 1 en `STATE_FETCH_RDATA_2`, `DOUT` en
  `FETCH_RDATA_1/2` con los desplazamientos y los modos `_E`/`_O`, máscaras
  DQM). Medido: el `ACK_n` vuelve a 1 a los **13 ciclos** del `TIMING` en
  todos los accesos (la siguiente ranura del canal es a los 20).
  `CH0_LOAD` ocupa el canal 0 con una lectura en cada ranura; `ACK_DELAY`
  retrasa el ACK para probar la aserción.
- `tb_dpb_model.v`: modelo de la DPB de Gowin para Verilator (lo que usa el
  tiny9990: 8/16 bits, lectura registrada de un ciclo).
- `replay_openmsx.sh <ROM> <romtype> <segundos> <tag>`: traza en openMSX
  (`mk_trace.py`/`mk_replay.py` de `fpga/zynq/tools/v9990_trace` del MSXimus
  Z, C-BIOS_MSX2+ con `-ext gfx9000`), *replay* en el banco y diff byte a byte
  de la VRAM (`omsx_vram.py` pasa el volcado de openMSX, que es la VRAM física
  de los dos chips, `V9990VRAM.hh transformBx/P1`, al orden del tiny9990).
- `fpga/check_core.tcl`: síntesis fuera de contexto (`CORE_VARIANT=full |
  nopal | noeor | nor16 | none | main | parches gw_sh check_core.tcl` desde
  `fpga/`).

Pruebas de `run_t9990_core.sh` (todas exigen `LOST_SLOTS=0` salvo `assert`):

| Prueba | Qué mide | Marca |
|---|---|---|
| `geom` | 1368 ciclos del maestro (6840 de `CLK`) por línea, 262 líneas (313 con PAL), VS de 3 líneas, PAL y EO solo cambian con VS, VS en el sitio esperado de la ventana; en B1, P1, P2, B3, B2, B4, B1 16 bpp, B1 con el canal 0 ocupado, B1 entrelazado, B1/P1/B2 PAL, B1 con R#16 = 87h, B4 PAL con R#16 = 78h y B1 con C25M (R#7 = 40h) | `GEOM_OK 1368 x 262/313` |
| build | build completa de la configuración v9990 (`gw_sh build_v9990_xtal.tcl`, síntesis + P&R) en una copia del árbol en una ruta corta y la puerta `tools/check_build.py` de `docs/VERIFICATION.md` (Fmax CLK_BASE ≥ 109 MHz, 0 endpoints violados) | `PUERTA: PASA` |
| `pal` | B1/B3/B2/B4/P1/P2 PAL (y PAL entrelazado): 313 líneas, 290 con DE, imagen 212 (290 en overscan), bordes 41/37, PAL = 1; B5 con el bit PAL: 440 líneas, PAL = 0; vuelta a NTSC | `PALT_OK` |
| `blit` | LMMV, LMMM, LMMC, PSET, LINE, POINT, LMCM y P#0 en B1 8 bpp, LMCM/POINT por carril | `BLIT_OK` |
| `ports` | P#4, P#7, P#8-P#11, P#12-P#15 leen FFh después de una lectura de P#5 | `PORTS_OK` |
| `eor` | cursores frente a un modelo de openMSX píxel a píxel: B1 BD16 (EOR con CC = 0 y con CC ≠ 0, solape, oculto, invisible, R#28, fuera de pantalla, Y con vuelta por arriba), B1 BD16 entrelazado (los dos campos), B1 BP4 y B2 BP4 en NTSC y PAL; y, en esos casos y en B3 BD16/BP4, B1 BD16 entrelazado, B4 BP4, B4 BD16 PAL entrelazado y B2 BD16 entrelazado, que en ningún ACK de lectura del sprite (ni en el ciclo siguiente) la línea registrada del cursor (`cur_line_q`) difiere de la combinacional (`cur_race`) | `EOR_OK` |
| `r16` | diez valores de R#16 en B1, P1, B3, P2, B2, B4, B1 entrelazado, B1 PAL y B4 PAL entrelazado: posición del VS en la ventana, subida de DE frente a HS y primera línea de DE frente a VS | `R16_OK` |
| `r16chg` | R#16 escrito doce veces en sitios distintos del cuadro en B1 entrelazado, B4 PAL entrelazado y B5, con cambios que cruzan el límite del cuadro de sincronismo (F0h→10h, 10h→80h, 80h→70h, 0Fh→01h, 08h→07h, 88h→77h...): el sincronismo exacto en todos los cuadros (líneas de VS a VS, ciclos por cuadro, puntos de HS a HS, ancho de HS, VS del ancho del modo con HS, FIELD que alterna en cada VS y solo cambia con él); los cuadros de la ventana (puntos entre dos `v_rst`) dentro de ± (15 líneas + 60 puntos) y como mucho 2 irregulares por cambio; tres VS después de cada cambio, el VS en el sitio de la ventana que toca al valor nuevo; de vuelta en 00h, VS en el (0,0) de la ventana y ventana regular | `R16CHG_OK` |
| `bdbp` | B1 BP4 con índice 0 (transparente) en las líneas 16..255, R#15 = 5: los puntos de índice 0 tienen que salir con el color de fondo desde el reset y también después de unos cuadros de B1 BD16 | `BDBP_OK` |
| `assert` | con el ACK 8 ciclos tarde la aserción salta | `ASSERT_SELFTEST_OK` |
| `hito1` | salida de vídeo (HS, VS, R, G, B, DE, EO, IL en cada `DCLK_EN`) idéntica punto a punto a la del core del hito 1 en B1, P1, P2, B3, B2, B4 y B1 entrelazado | `video identico` |
| `replay` | `REPLAY=<.rpl> VRAMOUT=<.bin> OMSX=<vram>`: diff de la VRAM | `VRAM identica a openMSX` |

### Resultados (26/10/2026, RTL final `f0fa14d`)

Corridas en WSL con Verilator 5.020 sobre copias del árbol en
`C:/Users/alber/AppData/Local/Temp/v99wt/ct_<nombre>/fpga` (un directorio de
objetos por copia con `OBJTAG`, para correr varias tandas a la vez sin que una
compile a medias los ficheros que otra está editando), más la paleta, el
*replay* y la build completa:

| Prueba | Orden (desde `fpga/`) | Resultado |
|---|---|---|
| `geom` (15 casos) | `OBJTAG=fin bash tb/core/run_t9990_core.sh geom r16 r16chg` | **pasa**: 6840 ciclos de `CLK` y 1368 enables de 21 MHz por línea en todos; 262 líneas (1 792 080 ciclos) en NTSC y 313 (2 140 920) con PAL en B1, P1, B2 y B4 + R#16 = 78h; VS de 3 líneas con HS; VS en el sitio de la ventana que toca con R#16 = 87h y 78h; latencia del ACK 13 ciclos en todos los accesos, cero accesos fuera de ranura, `LOST_SLOTS=0` |
| `r16` | (misma) | **pasa** (`R16_OK`): los 90 casos (diez valores de R#16 en B1, P1, B3, P2, B2, B4, B1 entrelazado, B1 PAL y B4 PAL entrelazado) con el VS en el sitio esperado de la ventana, DE desplazado el paso del manual, 262/313 líneas exactas, VS de 3 líneas y FIELD alineado |
| `r16chg` | (misma) | **pasa** (`R16CHG_OK`). Sincronismo exacto en los 36 cuadros de cada caso: B1 entrelazado 262 × 342, B4 PAL entrelazado 313 × 912, B5 440 × 848 con VS de 8 líneas; HS de 25, 68 y 64 puntos; FIELD alterna en cada VS. La ventana: 13 cuadros irregulares de 35 por los 12 cambios, de 84 459 a 94 734 puntos (estable 89 604) en B1, de 271 716 a 299 136 (285 456) en B4 PAL y de 360 340 a 385 840 (373 120) en B5; VS en su sitio tres VS después de cada cambio; de vuelta en 00h, VS en el (0,0) y ventana regular. **Con el RTL anterior** (`t9990_timing.sv` de `ea6113c`, el reajuste del sincronismo en la línea 12) **falla**: sincronismo de 247 a 277 líneas y de 327 a 357 puntos en B1, de 298 a 328 líneas y de 852 a 972 puntos en B4 PAL, y en B5 de 21 a 448 líneas, VS de 2 a 8 líneas y 2 VS sin HS (el VS doble de la revisión); la ventana, en cambio, regular |
| `bdbp` | `OBJTAG=newC bash tb/core/run_t9990_core.sh bdbp blit eor ports pal assert hito1` | **pasa** (`BDBP_OK`): 0 de 43 200 puntos de índice 0 distintos del fondo (1B82h, R#15 = 5) desde el reset y 0 después de B1 BD16. Con `t9990_color_decode.sv` anterior a `884ec59` **falla**: 0 desde el reset y 43 200 después de BD16 (salen 251Eh) |
| `blit` | (misma) | **pasa** (`BLIT_OK`): LMMV, LMMM, LMMC, PSET, LINE (20 puntos), POINT, LMCM, LMCM/POINT por carril y P#0, con el START del blitter retrasado un ciclo (`f0fa14d`) |
| `eor` | (misma) | **pasa** (`EOR_OK`): cero puntos distintos del modelo de openMSX en los 14 casos (B1 BD16 con EOR CC = 0 y CC ≠ 0, solape, oculto, invisible, R#28, fuera de pantalla, Y = 500 / 0, entrelazado campos 0 y 1; B1 BP4; B2 BP4 NTSC y PAL) con la línea del cursor registrada; `cur_line_q` igual a la línea combinacional en los 150 876 ACK del sprite (y ciclos siguientes) de todos los casos, también B3, B4, B4 PAL entrelazado y B2 entrelazado |
| `ports` | (misma) | **pasa** (`PORTS_OK`): P#4, P#7, P#8-P#15 leen FFh (con P#5 = 60h justo antes) |
| `pal` | (misma) | **pasa** (`PALT_OK`): B1/B3/P1/P2 PAL 313 líneas, DE 290 desde la 18, imagen 212, bordes 41/37; B2/B4 PAL imagen 290 sin bordes; B1 PAL entrelazado igual; B5 con el bit PAL sigue en 440 líneas con PAL = 0; vuelta a NTSC 262 |
| `assert` | (misma) | **pasa** (`ASSERT_SELFTEST_OK`): con el ACK 8 ciclos tarde la aserción salta 29 366 veces |
| `hito1` | (misma) | **pasa**: salida de vídeo idéntica punto a punto al core del hito 1 en B1, P1, P2, B3, B2, B4 y B1 entrelazado (de 716 832 a 1 911 552 bytes por caso) |
| paleta | `bash tb/core/run_t9990_palette.sh` | **pasa** (`PAL_OK`): 404 lecturas por P#1, cero componentes mal, puntero R#14 bien, cero ranuras perdidas |
| `replay` GNG | traza de `tb/core/trace/` (`GNG2M.ROM`, `KonamiSCC`, 10 s, C-BIOS_MSX2+ + gfx9000) y `OBJTAG=rep REPLAY=.../gng.rpl VRAMOUT=... OMSX=.../gng_vram.bin bash tb/core/run_t9990_core.sh replay` | **pasa**: 161 794 eventos, 471 comandos; **0 bytes distintos de 524 288** frente a la VRAM de openMSX; `LOST_SLOTS=0` |
| parámetros a 0 | `VOPT="-GENABLE_PAL=0 -GENABLE_CURSOR_EOR=0 -GENABLE_R16=0" OBJTAG=p0 bash tb/core/run_t9990_core.sh geom pal ports blit r16chg bdbp eor` | **pasa** todo salvo `eor`, que falla a propósito: los 15 `geom` (todo 262 líneas: sin PAL el bit 3 de R#7 no hace nada; R#16 no mueve el VS), `pal` (los casos PAL salen NTSC, PAL = 0), `ports`, `blit`, `r16chg` (sincronismo y ventana exactos en los tres casos aunque se escriba R#16: 262 × 342, 262 × 912, 440 × 848, 0 cuadros de la ventana irregulares) y `bdbp` (0 y 0: el arreglo del fondo no depende de los parámetros); `eor` da 839 puntos distintos del modelo en el primer caso (el cursor del hito 1, de color plano y en la línea Y) |
| build completa | copia del árbol en `C:/Users/alber/AppData/Local/Temp/v99wt/fixcore2`, `gw_sh build_v9990_xtal.tcl` desde `fpga/` y la orden de `tools/check_build.py` de `docs/VERIFICATION.md` | **tiempo: pasa**. Fmax CLK_BASE **114,431 MHz**, 0 endpoints de setup y de hold violados, peor slack de setup +0,520 ns (blitter, `state_4` → `DST_NY`, 6 niveles); el primer camino de `u_tg` está a +0,885 ns (R#7 → fin de cuadro de la ventana) y no hay ninguno de `u_sp` entre los 25 peores. Logic 14 508 (11 822 LUT + 2 656 ALU + 5 SSRAM), CLS 8 769, BSRAM 24, 8/8 relojes primarios, 2 rPLL; avisos los del hito 1 más EX3073 (`PAL` sin conectar en `cartridge_v9990.sv`, contrato 1). **La puerta sale `FALLA` por un solo punto**: la lógica se aparta un 2,60 % de la referencia del hito 1 (14 140, tolerancia 1 %). Es el crecimiento del core (PAL, cursor y R#16, ver Síntesis) más el ruido de síntesis de Gowin en módulos que no cambian (`u_boot` +28 LUT, `u_blit` +45 entre dos builds con el mismo RTL); el árbol revisado (`b53627f`) ya estaba en 14 415 (+1,9 %). Fijar la referencia nueva es de la integración (contrato 7) |

Antes del retraso del START del blitter (`f0fa14d`), la misma build con la línea
del cursor registrada y R#16 nuevo (`v99wt/fixcore1`) daba 0 endpoints violados
pero Fmax CLK_BASE 108,038 MHz: el peor camino (0,003 ns) era del blitter,
`vdp_reg[52]` → `REG.OP == CMD_STOP` → cadena de prioridades → `DST_X`/CE, 7
niveles, el mismo que limitaba el hito 1 (0,092 ns); `u_tg` y `u_sp` ya no
salían entre los 25 peores. Con la decodificación de STOP registrada ese camino
desaparece y el siguiente del blitter está a +0,520 ns.

Con los parámetros a 0 la prueba `eor` falla a propósito (el cursor es el del
hito 1, de color plano y en la línea Y): es la prueba de que `eor` no pasa por
construcción.

## Síntesis (Gowin 1.9.12.03, solo `run syn`, top `T9990`)

`CORE_VARIANT=<v> gw_sh check_core.tcl` desde `fpga/` de la copia
`v99wt/fixcore2` (RTL final `f0fa14d`), en serie, 26/10/2026. Recursos de
`impl/gwsynthesis/check_core_<v>_syn_rsc.xml`. Ningún aviso ni error en ninguna
variante. `main` y `parches` son de la corrida anterior (salen de git y su RTL no
ha cambiado). "Tocados" es la suma de `u_tg`, `u_sp`, `u_pri`, `u_pal`, `u_sel`
y `u_port`.

| Variante | Qué es | LUT | ALU | FF | BSRAM | Tocados LUT / ALU / FF |
|---|---|---|---|---|---|---|
| `main` | tiny9990 de tnCart (rama `main`) | **8 661** | **767** | **4 766** | **18** | 3 373 / 138 / 2 692 |
| `parches` | commit `2f95eb8`: los seis parches, `chr` y P#8-P#15 | 8 718 | 766 | 4 766 | 18 | 3 393 / 137 / 2 692 |
| `full` | `hito/core` con los tres parámetros a 1 | **8 871** | **828** | **4 863** | **18** | 3 569 / 179 / 2 777 |
| `nopal` | `ENABLE_PAL = 0` | 8 873 | 826 | 4 860 | 18 | 3 568 / 178 / 2 775 |
| `noeor` | `ENABLE_CURSOR_EOR = 0` | 8 885 | 810 | 4 834 | 18 | 3 560 / 179 / 2 757 |
| `nor16` | `ENABLE_R16 = 0` | 8 756 | 797 | 4 772 | 18 | 3 425 / 148 / 2 686 |
| `none` | los tres a 0 | 8 711 | 776 | 4 741 | 18 | 3 403 / 147 / 2 665 |

Frente a `main`, `full` cuesta **+210 LUT, +61 ALU, +97 FF y ninguna BSRAM**
(+2,4 % de LUT del core).

Coste de cada parte (`full` menos la variante con esa parte a 0):

| Parte | Total LUT / ALU / FF | Tocados LUT / ALU / FF | Dónde |
|---|---|---|---|
| PAL | −2 / +2 / +3 (ruido) | +1 / +1 / +2 | `u_tg` +30 LUT, +2 FF (y −31 en `u_sp`, ruido) |
| Cursor EOR | −14 / +18 / +29 | +9 / 0 / +20 | `u_pal` +19 LUT +17 FF, `u_sel` +15, `u_pri` +3 LUT +2 FF; `u_sp` −21 (sin las dos restas del +1/+2, que van a `cur_line_q`) |
| R#16 | +115 / +31 / +91 | +144 / +31 / +91 | `u_tg` +156 LUT +31 ALU +91 FF: los contadores de sincronismo, el reajuste de la ventana y los dos registros de R#16 por tiempo (la versión del reajuste del sincronismo costaba +126 / +10 / +29) |

Los totales tienen ruido de síntesis de ±60 LUT: el blitter (`u_blit`), que es
el mismo RTL en todas las variantes, sale entre 4 223 y 4 268 LUT. La columna de
módulos tocados es mejor estimación del coste de cada parte.

## Lo que no se ha hecho o no se ha podido comprobar

- **Nada se ha probado en placa.** Lo de placa del hito 2 (sin columnas de
  puntos con R#7 = 40h en B1, con un programa de disco propio) y del hito 7 (el
  contador da 50,16 Hz, el monitor acepta 855x626) queda para cuando la
  integración meta este core y el upscan sepa del cuadro PAL.
- **P&R solo de esta área**: la build completa es la de la configuración v9990
  con este core y la carcasa de `main` (sin el bus, la SDRAM, la MegaRAM ni el
  vídeo PAL de las otras áreas). La de integración tiene que repetirla.
- **La VRAM del banco es un modelo de `sdram.sv`**, no `sdram.sv` con un modelo
  de chip SDRAM: reproduce su protocolo con el UMA (estados, `ACK_n`, `DOUT`,
  máscaras), no los tiempos del chip. El UMA sí es el real. El banco UMA +
  `sdram.sv` + modelo de SDRAM es del hito 4.
- **El replay de GNG solo ejercita escrituras**: en la traza de openMSX no sale
  ninguna lectura (la *watchpoint* `read_io` no dispara; `mk_replay.py` lo
  trata así), así que P#0/P#2 en lectura no se comparan con openMSX por esta
  vía (sí en `+BLIT=1`).
- **(Arreglado en la 0.3beta: [zynqfix.md](zynqfix.md), arreglo 7.)**
  **Desplazamientos horizontales del bitmap, sin tocar** (diagnóstico
  `+HPOS=1`, scroll 0): el primer punto de la imagen es el X = 2 del bitmap en
  B1 BD16, X = 4 en B3 BD16, X = 1 en B1/B3 BP4 y X = 2 en B2 BP4 (openMSX:
  X = 0); y la capa de paleta (P1, P2, BPx) sale un punto adelantada frente a
  la ventana, con el último punto de la imagen en el color de fondo. En BP4 el
  core del hito 1 da lo mismo (mismo diagnóstico con el core de `20936e6`); en
  BD16 no se puede comparar porque en el hito 1 BD16 salía con el color 0 de la
  paleta en toda la imagen (el parche de PRI). Por eso el cursor sale en la X de openMSX frente a la ventana en
  los modos de color directo, y un punto a la izquierda (con el bitmap, como en
  el hito 1) en BP2/BP4/BP6. Arreglarlo es tocar la cadena de lectura del
  bitmap y la paleta en todos los modos: otra tarea, con `hito1` como red.
- **(Sigue igual en la 0.3beta.)**
  **B2 a 16 bpp repite cada pareja de puntos** (`+HPOS=1` y el primer intento
  de la prueba EOR en B2 BD16: 1, 4, 5, 4, 5, 8, 9, 8, 9...). Está en la
  lectura del bitmap, que este hito no toca (el parche de BD16 solo cruza los
  dos bytes de cada punto); con el core del hito 1 no se ve porque BD16 salía
  con el color 0. Sin tocar; la prueba de overscan usa B2 BP4.
- **(Arreglado en la 0.3beta: [zynqfix.md](zynqfix.md), arreglo 7.)**
  **B4 BP4 sale 4 puntos tarde** (lo vio la revisión del área al probar el
  cursor en B4 con `+EOR=2` en una copia del banco): los 4 primeros puntos de
  cada línea de la imagen muestran el fondo o restos de la línea anterior. Es
  otro caso de los desplazamientos de arriba, en la lectura del bitmap, que
  este hito no toca; por eso la prueba `eor` no compara B4 punto a punto (sí
  mira en B4 la línea registrada del cursor). Sin tocar.
- **Entrelazado de 262 y 313 líneas por campo** (el manual da 262,5 y 312,5):
  como en el hito 1.
- **B6** (HSCN + C25M) no genera VS: `v_cnt` es de 9 bits y la tabla de 525
  líneas pide 524 (`V480_TOTAL − 1`). Anterior a este hito; B6 no está
  soportado (estudio).
- **R#16 en B2/B4 sigue al manual, no a openMSX** (ver arriba). Con el
  `getCursorYOffset` de overscan openMSX deja anotado que no sabe si R#16
  influye; aquí no influye.
- **Fuera del alcance** (estudio, sección 9): B0/B7, B5/B6, ROM kanji (P#8-P#11
  solo leen FFh), prelectura de P#0.
- **Revisión de Codex** (segunda opinión sobre el diff del core, 26/10/2026,
  solo lectura). Tres hallazgos:
  1. *R#16 cambiado en marcha sacaba dos VS seguidos o se saltaba uno*: real,
     arreglado entonces con el reajuste del sincronismo en la línea 12 y,
     después de la revisión del área, cambiado por el reajuste de la ventana
     (ver R#16).
  2. *El +1/+2 de la Y del cursor toma IL en vivo; openMSX fija `interlaced`
     en `frameStart`*: cierto, pero solo cambia algo si se escribe el bit IL de
     R#7 a mitad de cuadro, y solo en ese cuadro; el bitmap del tiny9990
     (`BG_Y`) también usa R#7 en vivo y el cursor va con él. No se toca.
  3. *EO sin IL (R#7 = 04h)*: en openMSX el bit EO del estado alterna en cada
     cuadro siempre (`frameStart`: `status ^= 0x02`) y con EO activo se
     alternan las líneas pares e impares aunque no haya entrelazado
     (`V9990SDLRasterizer.cc` `drawBxMode`, `isEvenOddEnabled`). El tiny9990
     solo lo hace con IL y EO juntos, también en el bitmap (`STATUS.EO`
     forzado a 0 sin IL, `BG_Y`): es anterior a este hito y el cursor sigue al
     bitmap. No se toca (cambiaría el bitmap del hito 1).
  Lo demás que miró (EOR/CC, el anillo de la paleta, anchuras, síntesis,
  `ifndef SYNTHESIS`) lo dio por bueno.
- **Revisión del área** (revisor adversarial, 26/10/2026, sobre `b53627f`;
  repitió las pruebas y una build completa). Cuatro hallazgos, los cuatro
  reales y arreglados:
  1. *(alta) Con `ENABLE_CURSOR_EOR = 1` la build no cerraba a 108 MHz* (Fmax
     101,195 MHz, 4 endpoints violados, peor slack −0,623 ns en la línea del
     cursor; el reajuste de R#16 detrás, a +0,098 ns): línea del cursor
     registrada (`ea6113c`) y R#16 con dos registros (`f4f7001`). Con eso la
     build quedaba en 108,038 MHz por el camino del blitter que ya era el
     crítico del hito 1; registrada la decodificación de STOP (`f0fa14d`),
     114,431 MHz y 0 endpoints (Resultados). La puerta solo falla en la
     referencia de lógica del hito 1 (contrato 7).
  2. *(media) R#16 volvía a fasear el sincronismo*: cada cambio daba un cuadro
     de VS a VS de ± 16 líneas y una línea de HS a HS de ± 60 puntos, al
     revés que openMSX (VSYNC periódico, R#16 solo mueve el principio de la
     imagen). Rehecho como proponía el revisor (`f4f7001`): sincronismo libre
     y reajuste de la ventana en su borrado. `r16chg` lo comprueba y falla con
     el RTL anterior.
  3. *(baja) En B5 el reajuste de la línea 12 caía dentro del VS de 8 líneas*
     y salía un segundo VS: desaparece con el punto 2 (el sincronismo ya no se
     reajusta); `r16chg` tiene ahora un caso B5 (falla con el RTL anterior: de
     21 a 448 líneas, VS de 2 a 8).
  4. *(baja) Color de fondo de los modos de paleta tras un modo de color
     directo* (la salida retenida de `T9990_COLOR_DECODE`): arreglado
     (`884ec59`) con la prueba `bdbp`, que falla antes y pasa después.
  El revisor vio además que B4 BP4 sale 4 puntos tarde (anterior al hito, sin
  tocar: ver arriba).
