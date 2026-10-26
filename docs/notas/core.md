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
  campo.
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
- **Cómo.** En vez de mover la ventana se mueve el sincronismo: un segundo par
  de contadores genera HS/VS desplazados frente a `h_cnt`/`v_cnt`, que siguen
  midiendo la ventana. Bordes, lectura de VRAM, HR/VR, interrupciones, bitmap y
  sprites no cambian frente a la imagen; frente a HS/VS se mueven, igual que en
  openMSX (`DISPLAY_START` y `VSCAN` se programan con `getTopBorder` y
  `getBottomBorder`). Con R#16 = 00h HS, VS y EO son, ciclo a ciclo, los del
  hito 1 (prueba `hito1`).
- **Cuándo se toma R#16.** En la línea 12 de la ventana, en el punto
  `H_SYNC_PERIOD + 40`, se lee R#16 y se ponen los contadores de sincronismo
  en ventana + desplazamiento (en régimen estable ya están ahí y no cambia
  nada). Ahí el sincronismo está en su línea 5..20, después del VS y lejos
  del final del cuadro, y el punto cae después del HS y antes del final de la
  línea en todos los modos, así que un cambio de R#16 deja **un** cuadro de
  sincronismo de 262/313 ± 16 líneas y **una** línea de ± 60 puntos (en el
  borrado superior de la ventana, sin DE), nunca dos VS seguidos ni un cuadro
  sin VS. La primera versión reajustaba en el (0,0) de la ventana, que está a
  −9..+8 líneas del límite del cuadro de sincronismo: con R#16 de F0h a 10h
  salían dos VS a 2 líneas y de 70h a 80h 509 líneas sin VS (lo encontró la
  revisión de Codex; prueba `r16chg`). En openMSX el sincronismo es regular
  (`frameStart` cada 262/313 líneas) y lo que se mueve es el principio de la
  imagen dentro del cuadro (`getTopBorder`); aquí, para no tocar los
  contadores de la ventana, se mueve el sincronismo, una vez por cambio.
- **PAL y R#16.** El bit PAL se toma al empezar el cuadro de sincronismo
  (`pal_s`, que da la salida `PAL`) y la ventana lo copia al pasar de su
  línea 9 a la 10 (`pal_w`): con R#16 el VS cae como mucho 9 líneas antes o 7 después del
  (0,0) de la ventana, y ninguna comparación de la ventana que dependa de PAL
  cae antes de su línea 17.

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
  00h es la paridad del campo que empieza con el VS (el de la ventana cambia
  en el (0,0) de la ventana, que ya no coincide con el VS). Cambia solo con
  VS.
- **`HS`/`VS`**: con R#16 ≠ 00h se mueven frente a la imagen (−7..+8 pasos y
  −7..+8 líneas). Con R#16 = 00h no cambian. Cada vez que el programa cambia
  R#16 sale **un** cuadro (VS a VS) de 262/313 ± 16 líneas con **una** línea
  (HS a HS) de ± 60 puntos, en el borrado superior; el resto, regular.
- Los tres parámetros se pueden poner a 0 por separado; con los tres a 0 el
  core es el del hito 1 más los parches 1-3 y la aserción (que no sintetiza).
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
   mueve en la salida, recortada por esa ventana fija (estudio, riesgos). Un
   cambio de R#16 da un cuadro de entrada de ± 16 líneas y una línea de ± 60
   puntos (ver Interfaz): el upscan tiene que aguantarlo (un cuadro de salida
   corto o largo) sin perder el enganche. Si no se quiere el efecto o falta
   sitio: `T9990 #(.ENABLE_R16(0))`.
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
| `pal` | B1/B3/B2/B4/P1/P2 PAL (y PAL entrelazado): 313 líneas, 290 con DE, imagen 212 (290 en overscan), bordes 41/37, PAL = 1; B5 con el bit PAL: 440 líneas, PAL = 0; vuelta a NTSC | `PALT_OK` |
| `blit` | LMMV, LMMM, LMMC, PSET, LINE, POINT, LMCM y P#0 en B1 8 bpp, LMCM/POINT por carril | `BLIT_OK` |
| `ports` | P#4, P#7, P#8-P#11, P#12-P#15 leen FFh después de una lectura de P#5 | `PORTS_OK` |
| `eor` | cursores frente a un modelo de openMSX píxel a píxel: B1 BD16 (EOR con CC = 0 y con CC ≠ 0, solape, oculto, invisible, R#28, fuera de pantalla, Y con vuelta por arriba), B1 BD16 entrelazado (los dos campos), B1 BP4 y B2 BP4 en NTSC y PAL | `EOR_OK` |
| `r16` | diez valores de R#16 en B1, P1, B3, P2, B2, B4, B1 entrelazado, B1 PAL y B4 PAL entrelazado: posición del VS en la ventana, subida de DE frente a HS y primera línea de DE frente a VS | `R16_OK` |
| `r16chg` | R#16 escrito doce veces a mitad de cuadro en B1 entrelazado y B4 PAL entrelazado, con cambios que cruzan el límite del cuadro de sincronismo (F0h→10h, 10h→80h, 80h→70h, 0Fh→01h, 08h→07h, 88h→77h...): cuadros de total ± 16 líneas, líneas de ± 60 puntos, HS de ancho fijo, VS de 3 líneas con HS, FIELD que alterna en cada VS; de vuelta en 00h, régimen exacto | `R16CHG_OK` |
| `assert` | con el ACK 8 ciclos tarde la aserción salta | `ASSERT_SELFTEST_OK` |
| `hito1` | salida de vídeo (HS, VS, R, G, B, DE, EO, IL en cada `DCLK_EN`) idéntica punto a punto a la del core del hito 1 en B1, P1, P2, B3, B2, B4 y B1 entrelazado | `video identico` |
| `replay` | `REPLAY=<.rpl> VRAMOUT=<.bin> OMSX=<vram>`: diff de la VRAM | `VRAM identica a openMSX` |

### Resultados (26/10/2026, RTL final `ae3e7a5` + banco `7237f5f`)

Corridas en WSL con Verilator 5.020, en tres tandas en paralelo (objetos
distintos con `OBJTAG`), más la paleta y el *replay*:

| Prueba | Orden (desde `fpga/`) | Resultado |
|---|---|---|
| `geom` (15 casos) | `OBJTAG=finA bash tb/core/run_t9990_core.sh geom pal blit ports eor` | **pasa**: 6840 ciclos de `CLK` y 1368 enables de 21 MHz por línea en todos; 262 líneas (1 792 080 ciclos) en NTSC y 313 (2 140 920) con PAL en B1, P1, B2 y B4 + R#16 = 78h; VS de 3 líneas con HS; latencia del ACK 13 ciclos en todos los accesos, cero accesos fuera de ranura, `LOST_SLOTS=0` |
| `pal` | (misma) | **pasa** (`PALT_OK`): B1/B3/P1/P2 PAL 313 líneas, DE 290 desde la 18, imagen 212, bordes 41/37; B2/B4 PAL imagen 290 sin bordes; B1 PAL entrelazado igual; B5 con el bit PAL sigue en 440 líneas con PAL = 0; vuelta a NTSC 262 |
| `blit` | (misma) | **pasa** (`BLIT_OK`): LMMV, LMMM, LMMC, PSET, LINE (20 puntos), POINT, LMCM, LMCM/POINT por carril y P#0 |
| `ports` | (misma) | **pasa** (`PORTS_OK`): P#4, P#7, P#8-P#15 leen FFh (con P#5 = 60h justo antes) |
| `eor` | (misma) | **pasa** (`EOR_OK`): cero puntos distintos del modelo de openMSX en los 14 casos (B1 BD16 con EOR CC = 0 y CC ≠ 0, solape, oculto, invisible, R#28, fuera de pantalla, Y = 500 / 0, entrelazado campos 0 y 1; B1 BP4; B2 BP4 NTSC y PAL) |
| `r16` | `OBJTAG=r16b bash .../run_t9990_core.sh r16chg r16` (copia del árbol con el mismo RTL; banco sin `7237f5f`, que solo puede bajar la cuenta de `eo_win_bad`) | RESULTADO_R16 |
| `r16chg` | `OBJTAG=finC bash tb/core/run_t9990_core.sh r16chg assert hito1` | **pasa** (`R16CHG_OK`): B1 entrelazado 247..277 líneas y 327..357 puntos; B4 PAL entrelazado 298..328 líneas y 852..972 puntos; HS de ancho fijo (25 y 68 puntos), VS siempre de 3 líneas con HS, FIELD alterna en los 18 VS; de vuelta en 00h, 262 × 342 y 313 × 912 con el VS en el (0,0). Con el RTL anterior (`108f2bb`, reajuste en el (0,0)) **falla**: cuadros de 1 a 516 líneas (B1) y de 1 a 618 (B4), líneas de 2 puntos, HS de 1 punto, VS de 1 línea, FIELD sin alternar 13 veces |
| `assert` | (misma) | **pasa** (`ASSERT_SELFTEST_OK`): con el ACK 8 ciclos tarde la aserción salta 29 366 veces |
| `hito1` | (misma) | **pasa**: salida de vídeo idéntica punto a punto al core del hito 1 en B1, P1, P2, B3, B2, B4 y B1 entrelazado (de 716 832 a 1 911 552 bytes por caso) |
| paleta | `bash tb/core/run_t9990_palette.sh` | **pasa** (`PAL_OK`): 404 lecturas por P#1, cero componentes mal, puntero R#14 bien, cero ranuras perdidas |
| `replay` GNG | traza nueva con `mk_trace.py`/`mk_replay.py` (`GNG2M.ROM`, `KonamiSCC`, 10 s, C-BIOS_MSX2+ + gfx9000, en `tb/core/trace/`) y `OBJTAG=finA REPLAY=... VRAMOUT=... OMSX=... bash tb/core/run_t9990_core.sh replay` | **pasa**: 161 794 escrituras, 471 comandos; **0 bytes distintos de 524 288** frente a la VRAM de openMSX; `LOST_SLOTS=0`. La traza sale idéntica byte a byte a la de la sesión anterior (openMSX es determinista aquí) |
| parámetros a 0 | `VOPT="-GENABLE_PAL=0 -GENABLE_CURSOR_EOR=0 -GENABLE_R16=0" bash tb/core/run_t9990_core.sh geom pal ports blit r16chg` | RESULTADO_OFF |

Con los parámetros a 0 la prueba `eor` falla a propósito (el cursor es el del
hito 1, de color plano y en la línea Y: 839 puntos distintos del modelo en el
primer caso, corrida de la sesión anterior sobre `ef22537`): es la prueba de
que `eor` no pasa por construcción.

## Síntesis (Gowin 1.9.12.03, solo `run syn`, top `T9990`)

`CORE_VARIANT=<v> gw_sh check_core.tcl` desde `fpga/`, en serie, 26/10/2026,
sobre el RTL final (commit `ae3e7a5`, R#16 en la línea 12). Recursos de
`impl/gwsynthesis/check_core_<v>_syn_rsc.xml`. Ningún aviso ni error en ninguna
variante. La síntesis de Gowin es determinista (repetida sobre el mismo RTL da
los mismos números); `main` y `parches` salen de git. "Tocados" es la suma de
los módulos que cambian estas partes (`u_tg`, `u_sp`, `u_pri`, `u_pal`, `u_sel`,
`u_port`).

| Variante | Qué es | LUT | ALU | FF | BSRAM | Tocados LUT / ALU / FF |
|---|---|---|---|---|---|---|
| `main` | tiny9990 de tnCart (rama `main`) | **8 661** | **767** | **4 766** | **18** | 3 373 / 138 / 2 692 |
| `parches` | commit `2f95eb8`: los seis parches, `chr` y P#8-P#15 | 8 718 | 766 | 4 766 | 18 | 3 393 / 137 / 2 692 |
| `full` | `hito/core` con los tres parámetros a 1 | **8 864** | **817** | **4 790** | **18** | 3 560 / 175 / 2 715 |
| `nopal` | `ENABLE_PAL = 0` | 8 889 | 815 | 4 787 | 18 | 3 557 / 175 / 2 713 |
| `noeor` | `ENABLE_CURSOR_EOR = 0` | 8 815 | 788 | 4 770 | 18 | 3 510 / 158 / 2 695 |
| `nor16` | `ENABLE_R16 = 0` | 8 804 | 808 | 4 761 | 18 | 3 438 / 166 / 2 686 |
| `none` | los tres a 0 | 8 718 | 776 | 4 739 | 18 | 3 384 / 147 / 2 665 |

`main` reproduce exactamente la referencia del estudio (8 661 / 767 / 4 766 /
18). Frente a ella `full` cuesta **+203 LUT, +50 ALU, +24 FF y ninguna BSRAM**
(+2,3 % de LUT del core).

Coste de cada parte (`full` menos la variante con esa parte a 0):

| Parte | Total LUT / ALU / FF | Tocados LUT / ALU / FF | Dónde |
|---|---|---|---|
| PAL | −25 / +2 / +3 (ruido) | +3 / 0 / +2 | `u_tg`: +8 LUT, +2 FF (las tablas verticales PAL son constantes y se van en los multiplexores que ya había) |
| Cursor EOR | +49 / +29 / +20 | +50 / +17 / +20 | `u_pal` +19 LUT +17 FF, `u_sel` +15, `u_sp` +10 LUT +17 ALU, `u_pri` +3 LUT +2 FF, `u_tg` +3 |
| R#16 | +60 / +9 / +29 | +122 / +9 / +29 | `u_tg` +126 LUT +10 ALU +29 FF (los contadores de sincronismo y el reajuste) |

Los totales tienen ruido de síntesis de ±60 LUT: el blitter (`u_blit`), que es
el mismo RTL en todas las variantes, sale entre 4 223 y 4 286 LUT, y el resto de
módulos no tocados entre 1 055 y 1 080. La columna de módulos tocados es mejor
estimación del coste de cada parte; las tres suman lo que cuestan juntas
(`full` − `none` en los tocados: +176 LUT). La primera versión de R#16
(reajuste en el (0,0) de la ventana, con la normalización módulo la línea y el
cuadro) costaba 52 LUT y 19 ALU más en `u_tg` (`full` 8 951 / 837 / 4 790).
Solo es síntesis: el coste en CLS y la Fmax (la puerta pide ≥ 109 MHz; el camino
crítico del hito 1 era del blitter) los tiene que medir el P&R de la integración.

## Lo que no se ha hecho o no se ha podido comprobar

- **Nada se ha probado en placa.** Lo de placa del hito 2 (sin columnas de
  puntos con R#7 = 40h en B1, con un programa de disco propio) y del hito 7 (el
  contador da 50,16 Hz, el monitor acepta 855x626) queda para cuando la
  integración meta este core y el upscan sepa del cuadro PAL.
- **Sin P&R**: solo síntesis fuera de contexto (lo que pedía la tarea); CLS y
  Fmax con la carcasa, en la build de integración.
- **La VRAM del banco es un modelo de `sdram.sv`**, no `sdram.sv` con un modelo
  de chip SDRAM: reproduce su protocolo con el UMA (estados, `ACK_n`, `DOUT`,
  máscaras), no los tiempos del chip. El UMA sí es el real. El banco UMA +
  `sdram.sv` + modelo de SDRAM es del hito 4.
- **El replay de GNG solo ejercita escrituras**: en la traza de openMSX no sale
  ninguna lectura (la *watchpoint* `read_io` no dispara; `mk_replay.py` lo
  trata así), así que P#0/P#2 en lectura no se comparan con openMSX por esta
  vía (sí en `+BLIT=1`).
- **Desplazamientos horizontales del bitmap, sin tocar** (diagnóstico
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
- **B2 a 16 bpp repite cada pareja de puntos** (`+HPOS=1` y el primer intento
  de la prueba EOR en B2 BD16: 1, 4, 5, 4, 5, 8, 9, 8, 9...). Está en la
  lectura del bitmap, que este hito no toca (el parche de BD16 solo cruza los
  dos bytes de cada punto); con el core del hito 1 no se ve porque BD16 salía
  con el color 0. Sin tocar; la prueba de overscan usa B2 BP4.
- **Probable color rancio en los modos de paleta**: en `+HPOS=1`, el primer
  punto de B1 BP4 (índice 0, transparente), medido justo después de los casos
  BD16, sale con un color que no es de la paleta. `T9990_COLOR_DECODE` no
  actualiza su salida fuera de BD8/BD16/YJK/YUV (`OUT <= OUT`) y el selector la
  coge donde la paleta es transparente: sería un punto de color equivocado en
  los índices 0 tras pasar de un modo directo a uno de paleta. Es anterior a
  este hito (en el core del hito 1 la rama es la misma, `OUT <= OUT`, y BD8
  deja el bit 15 a 0 igual que BD16). Arreglo propuesto, sin aplicar porque
  no es de este encargo: `OUT <= 16'h8000` en esa rama (el valor del reset,
  así que los modos de paleta arrancados desde el reset, que es lo que
  comprueba `hito1`, no cambian). No se ha comprobado más ni se ha tocado.
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
     **arreglado** (ver R#16, "Cuándo se toma R#16"; prueba `r16chg`, que
     falla con el RTL anterior y pasa con el nuevo).
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
