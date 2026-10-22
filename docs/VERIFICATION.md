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

Para la build del hito 1, desde la raíz del repositorio y después de
`cd fpga && gw_sh build_v9990_xtal.tcl`:

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

## Pruebas en placa del hito 1

Sin hacer. Lo que hay que comprobar con el `.fs` del hito 1, en este orden:

1. Cargar en **SRAM** con el MSX apagado y la Tang por USB; encender el MSX.
   Esperado: el LED parpadea mientras corre el bootloader; el MSX arranca normal
   (el V9990 solo ocupa los puertos 60h-6Fh y un slot expandido vacío).
2. Con el MSX en BASIC, el HDMI saca el color de fondo del V9990 (pantalla
   apagada: sincronismo estable y borde).
3. Un programa V9990 **de disco** (solo puertos) pinta: por ejemplo un visor de
   imágenes B1/B3, o una demo de disco. Anotar el programa, el modo y el
   resultado en la matriz de abajo.
4. Repetir en un **segundo monitor**.
5. Reset del MSX con la imagen en pantalla: vuelve a arrancar y la imagen se
   recupera.

## Matriz de monitores

Salida del hito 1: 720x480 visibles en 855x524 a 27,000 MHz, **60,27 Hz**, DVI
sin audio. Rellenar una fila por monitor y modo probado.

| Monitor / TV (marca y modelo) | Entrada | Variante (`xtal`/`sync`) | Modo V9990 | ¿Imagen? | Notas (sobrebarrido, parpadeo, tiempo de enganche, rechazo) | Quién y cuándo |
|---|---|---|---|---|---|---|
| | | | | | | |
| | | | | | | |
| | | | | | | |
| | | | | | | |
