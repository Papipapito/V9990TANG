# Arreglos del V9990 del MSXimus Z: versión 0.3beta

Rama `hito/zynqfix` (desde `main`, 0.2beta). Lleva al tiny9990 de aquí los
arreglos que el mismo core recibió en el MSXimus Z (repositorio
`MSXimus_zynq`, rama `zynq`) entre el 21 y el 30 de octubre de 2026, después de
que este port copiara los primeros (C25M, BD16, lectura de G de la paleta,
LMCM/POINT: [core.md](core.md)). Solo toca `fpga/v9990/tiny9990/*.sv` y los
bancos de `fpga/tb/core/`; la carcasa no cambia.

Los commits que se citan son del MSXimus Z.

## Portados

| # | Arreglo | Commit | Ficheros aquí | Qué se veía |
|---|---|---|---|---|
| 1 | **CMMC**: cada byte de P#2 son 8 píxeles a 2/4/8/16 bpp (eran 8 pasos fijos y a 8 bpp solo valían 4 bits) | `66ca7ae` | `t9990_blit.sv` | Chase H.Q. en negro: la orden pedía el doble de bytes y se quedaba con CE = 1 y TR = 1 |
| 2 | **CMMM**: la palabra leída de la VRAM lineal se decodifica byte a byte desde SA[1:0] | `35fba86` | `t9990_blit.sv` | retrato y letras de Chase H.Q. |
| 3 | **16 bpp**: R#48 (byte bajo del píxel) va a la dirección par en LMMV, PSET, LINE, LMMC y SRCH; en CMMC/CMMM también R#50 | `a12146a` | `t9990_blit.sv` | colores cruzados al pintar con comandos en BD16 |
| 4 | **P#2 escrito sin TR** con un comando en marcha: se retiene con /WAIT hasta que el motor lo toma, en vez de perderse | `04a9a1b` | `t9990_port.sv` | SymbOS G9K (manda el CMMC/LMMC de su caché de fuentes sin mirar TR) |
| 5 | **YJK y YUV** se decodifican con el grupo de 4 píxeles de la VRAM, en `T9990_BITMAP` (antes en fase con la pantalla, con los pares J/K cambiados) | `2f97073` | `t9990_bitmap.sv`, `t9990_color_decode.sv` | colores mal y repetidos (tnCart #31) |
| 6 | **Escribir R#17/R#21 dentro del área visible reinicia la cuenta de líneas** del plano; R#18/R#22 y DISP se toman una vez por cuadro | `fc36883` | `t9990_port.sv`, `t9990_timing.sv`, `t9990.sv` | Xybots: la pantalla partida en la línea 95 enseñaba abajo el atlas de letras |
| 7 | **Alineación horizontal**: `COLOR_DECODE_DELAY` 5 → 4, fase del generador de bitmap 3/2 también en B2 (era 4/3) y B4 (6/5), color directo un punto más tarde | `a017962`, `0f579a1`, `e61e656` | `t9990_timing.sv`, `t9990_color_decode.sv`, `t9990_palette.sv` | el contenido salía un punto antes que la imagen (2 en BD16 de B1, 4 en BD16 de B3); Dream Puzzle enseñaba por la derecha los primeros píxeles de la línea siguiente; en B2/B4 el punto 0 caía en el borrado |

### Diferencias con el MSXimus Z

- **P#2 sin TR (4): solo con LMMC o CMMC en marcha.** Allí el glue del Zynq
  suelta al Z80 por tiempo; aquí `/WAIT` va al Z80 real. Con cualquier otro
  comando el motor no pide nunca el byte (LMCM espera a que la CPU *lea*) y la
  espera duraría hasta el final del comando o para siempre. Fuera de esos dos
  comandos el byte se ignora, como antes.
- **Alineación (7): la transparencia de la paleta sale con su color.** El
  tiny9990 sacaba la transparencia de la capa de paleta (`OUT[15]` de
  `T9990_PALETTE`) un punto después que el color (`pri_index` 4-3 frente a los
  dos puntos del color). El MSXimus Z lo compensa abriendo un punto antes la
  ventana del PRI (`MUX_HDE_E`), que arregla el hueco del color directo pero
  deja el cursor un punto a la derecha en BD8/BD16/YJK. Aquí se corrige el
  origen (`pri_index` 4-2): el hueco cae en la imagen, el cursor queda en su X
  en todos los modos y sobra el apaño de [core.md](core.md) que tomaba el
  color del punto anterior en los puntos del cursor (`DIRECT`/`CUR_IN` de
  `T9990_PALETTE` quedan sin uso).
- Con (7) dejan de ser ciertos tres límites apuntados en
  [core.md](core.md#límites): los desplazamientos horizontales del bitmap, el
  último punto de la imagen en el color de fondo y el cursor un punto a la
  izquierda en BP2/BP4/BP6.

## Descartados

| Arreglo del MSXimus Z | Commit | Motivo |
|---|---|---|
| C25M en el bit 6 y solo con HSCN, BD16, lectura de G por P#1, LMCM/POINT | `a17a931`, `e3a2e33`, `bd12dfb`, `18fed6a` | ya estaban (core.md, cambios 1) |
| Cuadro PAL de 313 líneas | `7fb207d` | ya estaba, hecho aquí (core.md, cambio 4) |
| Glue y bus del T80 a prueba de rebotes; reset del core con el MSX; INT registrada | `18fed6a`, `4aebb48`, `4479b75` | son del glue del Zynq (`v9990_cpu_glue.v`), no del core; aquí el bus es el de la WonderTANG |
| Bit Ys alineado (`T9990_PALETTE.YS`, `T9990_SELECTOR.OUT_YS`) | `5cba81f` | solo sirve para superponer vídeo externo; aquí `Ys` no se conecta |
| B7 (1024 puntos) y B5 (640 x 400) | `a017962`, `8833f2e` | modos que la cadena de vídeo de la WonderTANG no saca (el core no genera B5/B6: [video.md](video.md)); son funciones nuevas, no arreglos |
| Entrelazado tejido, lector del frame buffer, escalador | `ac67068`, `87e88fe`, `80a88c4` | son del puente HDMI del Zynq (`v9990_fb`, `msx2hdmi_v9990`) |
| R#55-R#62 (ventana del V9968), canal del ARM | `86b155e`, `e7dba78` | propios del MSXimus Z |
| Memorias pequeñas a LUTRAM | `d3b3d86` | atributos de Vivado |

## Verificación

Ver [VERIFICATION.md](../VERIFICATION.md) (apartado de la 0.3beta) para las
cifras de las seis builds.

- Pruebas nuevas de `fpga/tb/core/run_t9990_core.sh` (portadas del banco del
  MSXimus Z): `cmmc` (60 casos), `cmmm` (60), `orden`, `p2notr`, `ycc` y
  `vscroll` (12 casos, banco aparte `tb_t9990_vscroll.sv`). Con el core de la
  0.2beta fallan: `cmmc` 56 de 60, `cmmm` 57 de 60, `orden` 37 errores,
  `p2notr` (el LMMC sin TR no acaba), `ycc` 754 de 760 puntos en YJK y en YUV,
  `vscroll` los 12 casos.
- `eor` exige ahora que el primer punto de la imagen sea el X = 0 del bitmap y
  el cursor en X+0 también en BP4 y B2 (antes X−1), con el último punto de la
  línea del bitmap y no del fondo.
- **Nada de esto está probado en placa.**
