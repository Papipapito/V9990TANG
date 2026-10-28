# Fusión de las seis áreas (hitos 2, 4, 5, 7 y 8 sobre los hitos 3 y 6)

Rama `hito/fusion`, desde `main` (`20936e6`, hito 1, probado en placa). Junta
las seis ramas de área, conecta los contratos que cada una dejó para la
integración, repite todos los bancos sobre el árbol fusionado y compila las
cuatro variantes. **Nada de esto se ha probado en la placa.**

## 1. Fusiones

Merges normales (sin *squash*), en este orden, cada uno en su commit:

| Rama | Commit de la rama | Merge | Qué trae |
|---|---|---|---|
| `hito/sdram` | `b04ba1a` | `bc89065` | refresco interno del UMA, `DOUT` solo tras un R/W, dos AUTO REFRESH en la inicialización ([sdram.md](sdram.md)) |
| `hito/integ` | `267529f` | `6817d45` | carcasa sin bootloader ni flash, POR, gestor del rPLL, guardia de lock, LED de estado, variantes `xtal`/`sync`, `.sdc` y `build_*.tcl` por variante ([integ.md](integ.md)) |
| `hito/core` | `5a6be75` | `a8ef8c1` | parches del tiny9990, P#8-P#15 a FFh, cuadro PAL de 313 líneas con salida `PAL`, cursor EOR, R#16, aserción de ranura perdida ([core.md](core.md)) |
| `hito/video` | `af80c0b` | `27bd497` | `VIDEO_IF.PAL`, salida 720x576 en 855x626, palanca `BLEND` ([video.md](video.md)) |
| `hito/bus` | `4da4ddf` | `17ffb28` | escaneo adaptativo, pre-WAIT de E/S y de memoria, rearme de 3 muestras, timeout fail-open, guardia de bus vivo, `DRIVE_EN`/`BOOT_HOLD` ([bus.md](bus.md)) |
| `hito/megaram` | `a65ff05` | `558d716` | megaROM SCC-I con ventana de 4 MB en 0, PLAIN0, `MEGAROM_CLEAR`, /WAIT de memoria, `tools/tncrom` r3 ([megaram.md](megaram.md)) |

Ningún merge tuvo conflictos de texto: las áreas no comparten ficheros
(comprobado con `git diff --stat main...hito/<area>` antes de fusionar). Lo que
sí se rompía en silencio era lo que la nota de integ anunciaba (sección 8): la
lista de ficheros del hito 1 en los `check_*.tcl` y en los bancos, y los
puertos nuevos de `BOARD_REV1_BUS` sin conectar en el top.

## 2. Contratos conectados

| Contrato | Dónde | Qué se hizo |
|---|---|---|
| bus ↔ integ | `tnCart_board_wt200b_top.sv` (`786cc5b`) | fuera el bloque `>>> FUSION hito/bus`, `BusPin`, `u_bus_guard` y `board_wt200b_bus_guard.sv` (y su línea en `build_common.tcl`). `u_bus` recibe `.DRIVE_EN(drive_en_27)`, `.BOOT_HOLD(boot_hold_27)`, saca `.WAIT_TIMEOUT(wait_timeout)` (a la guardia, que lo sincroniza y lo lleva al LED) y `.BUS_OK(bus_ok)`, y va con `.Bus(Bus)`. La guardia recibe `.SYS_READY(sys_ready && bus_ok)` |
| `BUS_OK` al LED | `led.sv` (`786cc5b`) | con `SYS_READY = sys_ready && bus_ok`, el LED ve `BUS_OK = 0` como "arrancando" (código 1): /RESET del MSX pulsado o bus del slot muerto. En `xtal` sin MSX `BUS_OK` también es 0, así que el código 2 ("sin reloj del slot") pasa por delante del 1; si no, ese caso diría "arrancando" |
| core → vídeo | `cartridge_v9990.sv` (`4f881dd`) | la salida `PAL` del `T9990` va a `Video.PAL` capturada en `posedge Video.DCLK`, como `video_vs_n` (el T9990 la cambia en el mismo flanco de `CLK` que VS) |
| megaram ↔ integ | `main.sv` (`f9e844f`) | `` `define HAVE_MEGAROM_CLEAR `` activo: `MEGAROM_CLEAR` en `ExpRam[RAM_BOOTLOADER]`, `CLEAR_ADDR = CONFIG::RAM_ADDR_MEGAROM`, `CLEAR_SIZE = 32768`; `DONE` retiene `SYS_RESET_n` y va a `WAIT_n` de `EXPANSION_SLOT` |
| megaram ↔ bus | `config/*.sv` (`09e27db`) y top | `BUS_PREWAIT_MEM_EN` en cada configuración (1 en `v9990_megaram`, 0 en `v9990`) y `.PREWAIT_MEM_EN(CONFIG::BUS_PREWAIT_MEM_EN)` en `u_bus`; `ENABLE_MEM_WAIT` definido en las dos configuraciones (1 y 0). El top no elabora (módulo inexistente en una rama de `generate`) si `BUS_PREWAIT_MEM_EN` no es `ENABLE_MEGAROM != 0 && ENABLE_MEM_WAIT`. `RAM_IF_EXPANSION_USES_FF = 0` en las dos (ya lo estaba) |
| palancas | `config/*.sv`, `cartridge_v9990.sv`, top | `V9990_ENABLE_PAL`, `V9990_ENABLE_CURSOR_EOR`, `V9990_ENABLE_R16` (a `T9990`) y `UPSCAN_BLEND` (a `VIDEO_UPSCAN`), todas a 1 en las dos configuraciones; cambiar una es una línea en la configuración |
| sdram | top | sin cambios: `SDRAM.RESET_n` ya era `base_ready`, el UMA va con sus parámetros por defecto y `DBG_RF_*` sin conectar; `hito/sdram` entra antes que `hito/megaram`, como pedían las dos |
| `DCLK` | `.sdc` | sin cambios: `cartridge_v9990.sv` de `hito/bus` conserva la OR de `dclk_en_ff`, así que el `create_generated_clock` de `DCLK` y los nombres que leen `check_build.py` y `archive_build.py` siguen valiendo |

### Scripts y bancos que nombraban la lista del hito 1

- `build_common.tcl` (`5535c47`) admite `OUT_NAME`, `RUN_STEPS` y
  `FILE_SUBST` (una copia parcheada en lugar de un fichero de la lista), y
  `check_sdram.tcl`, `check_megaram.tcl`, `check_bus.tcl` y `check_video.tcl`
  (`1d50ee3`) toman de él la lista, el `.sdc` y el resto de opciones.
  `check_bus.tcl` pierde el parche al vuelo del top y sus modos `CHECK_BUS_REF`
  y `CHECK_BUS_NOPATCH`; `check_video.tcl` cambia `BLEND` en una copia de la
  configuración y pierde `VIDEO_SRC=hito1` (con el top fusionado ninguno de
  esos modos elabora; sus cifras de antes de la fusión siguen en las notas de
  área). `check_core.tcl` sintetiza el `T9990` fuera de contexto y no cambia.
- Bancos (`d3444d9`): `board_wt200b_config.sv` → `board_wt200b_config_xtal.sv`
  en `tb/bus/run.sh`, `run_eq.sh`, `run_m1spur.sh` y `tb/megaram/run.sh`. En
  `tb/megaram/run.sh` las variantes `*_hito4` usan ya el `uma.sv` del árbol
  (es el de `hito/sdram`) e `inj_main`, el control del defecto del UMA de
  tnCart, saca el de `main` (`UMA_MAIN_SV` o `git show main:...`).
- `tb_integ_pins` (`d3444d9`) se reapunta al `BOARD_REV1_BUS` de `hito/bus`
  con las guardias dentro: fase sin reloj del slot (`BUS_OK = 0`, solo sale
  `BOOT_HOLD`), con reloj (las 64 combinaciones de `DRIVE_EN`, `BOOT_HOLD`,
  `WAIT_n`, `INT_n`, `BUSDIR_n` y /RD, con el /RD del pin antes que
  `BUSDIR_n` para la guardia de cola), con el /RESET del slot pulsado y el
  timeout del /WAIT (2^12 ciclos, `WAIT_TIMEOUT` pegajoso, sin contar con
  `BOOT_HOLD`).
- `tb_integ_guard` (`61ca25f`) gana el escenario `busok`, en las dos
  variantes: un modelo del `BUS_OK` de `BOARD_REV1_BUS` (sube al acabar la
  primera ventana de 2^18 ciclos tras `RESET_n` y cae con el /RESET del MSX)
  con `SYS_READY = SYS_RESET_n && BUS_OK` y el /WAIT del pin con `BUS_OK`.
  `BOOT_HOLD` cubre los 2,43 ms de `BUS_OK` en el arranque (listo a los 9,07
  ms en lugar de 6,64) y un /RESET del MSX de 1 ms con el sistema listo
  (`DRIVE_EN` a 0, `BOOT_HOLD` a 1, LED en arrancando, sin reset del
  cartucho). **Hueco conocido**: al pulsar el /RESET del MSX, `BUS_OK` corta
  el /WAIT del V9990 en el acto y `BOOT_HOLD` llega 3-4 ciclos de 27 MHz
  después (`SYS_READY` pasa por dos FF); cae con el Z80 en reset, así que el
  banco no lo cuenta. En los otros escenarios el modelo vale 1 y el banco es
  el de antes.

## 3. Bancos sobre el árbol fusionado

Verilator 5.020 en WSL (Ubuntu 24.04), 27/10/2026: core, paleta, replay, bus y megaram sobre `948d900`, sdram, vídeo e integ sobre `d3444d9`/`61ca25f` y repetidos sobre `ca21555`
(el RTL de las builds; los commits de después solo tocan bancos,
`build_*.tcl` y documentación):

| Banco | Orden | Resultado |
|---|---|---|
| core | `bash fpga/tb/core/run_t9990_core.sh` (geom pal blit ports eor r16 r16chg bdbp assert hito1) | **pasan todas**: `geom` (15 casos, `GEOM_OK`), `pal` (`PALT_OK`), `blit` (`BLIT_OK`), `ports` (`PORTS_OK`), `eor` (`EOR_OK`), `r16` (`R16_OK`), `r16chg` (`R16CHG_OK`), `bdbp` (`BDBP_OK`), `assert` (`ASSERT_SELFTEST_OK`, salta 29 366 veces con el ACK 8 ciclos tarde) y `hito1` (vídeo idéntico al del hito 1 en los 7 casos); `TB_DONE errores=0` y `LOST_SLOTS=0` en todas. La primera corrida se cortó (la conexión con WSL cayó, código 127) al acabar `geom`; el resto se relanzó con `run_t9990_core.sh pal blit ports eor r16 r16chg bdbp assert hito1` (`RC=0`) |
| core, paleta | `bash fpga/tb/core/run_t9990_palette.sh` | **pasa** (`PAL_OK`): 404 lecturas por P#1, cero componentes mal, puntero R#14 bien, cero ranuras perdidas |
| core, *replay* GNG | traza de `fpga/tb/core/trace/` (copiada del worktree de core, fuera de git) | **pasa**: **0 bytes distintos de 524 288** frente a la VRAM de openMSX, `LOST_SLOTS=0`, `TB_DONE errores=0` (`OBJTAG=rep`) |
| sdram | `bash fpga/tb/sdram/run.sh` | **TOTAL: PASA**: 48 casos (24 a 108 MHz y 24 a 107,386, controles negativos incluidos) y la latencia del canal 1, 12..12 como en el hito 1; `resultados.txt` sale con las mismas cifras que en la rama (solo cambia la cabecera) |
| bus | `bash fpga/tb/bus/run.sh` (5 topologías x 4 frecuencias) | **20 de 20 `BUS_OK`** (`RC=0`): a 3,58 MHz sin ningún fallo; a 5,37 solo los rebotes de `/IORQ` esperados (`OK*`, 1 por caso) salvo con el V9990 en 70h (`OK`); a 7,16 y 10,74 los fallos esperados de la nota del bus. Cifras de `resumen.py`: `/WAIT` en el slot a 120 ns (158 a 10,74 MHz), 0 pre-WAIT ajenos, 0 en M1 o memoria, 0 choques de conducción. Equivalencia con el bus de main (`run_eq.sh`) y M1 espurio (`run_m1spur.sh`): **pasan** (`RC=0`): `EQ_OK` en MODE 0 y 1 con 3 semillas (0 diferencias en `Bus`, `CART_MUX_CS_n` y los pines con `BUS_OK`, `WAIT_TIMEOUT = 0`) y `EQ_FAIL` en el control (MODE 2), como se espera; `M1SPUR_OK` en los 6 casos |
| megaram | `tb/megaram/run.sh` (17 variantes; `inj_main` y `turbo7_umamain` con el `uma.sv` de `main`) | **pasan las estrictas** (`wait`, `tncrom` con sus 4 trazas, `wait_hito4`, `inj_hito4`, `wait_bus5`, `tncrom_bus5`) y las de medida (`noprewait`, `noprewait_opt`, `wait_rd9`, `wait_rd10`, `nowait`, `turbo5`, `turbo5i`, `inj_main`, `turbo5_bus5`, `turbo7_umamain`, `turbo7_bus5`). Con el bus de `hito/bus` (*_bus5): `/RD` del pin → `/WAIT` del pin 5..7 ciclos, `WAIT_TIMEOUT` 0. **`turbo7` de antes salía FALLA** (2 errores: una lectura entregada a destiempo por el bus de `main` a 7,16 MHz acaba antes de que baje el `/WAIT`): es la mezcla del bus de `main` con el UMA de `hito/sdram`, que ninguna build tiene; con el UMA de `main` da lo de la rama (20 lecturas a destiempo, 11 mal contadas, PASA) y con el bus real pasa, así que `ca21555` la cambia por `turbo7_umamain` y `turbo7_bus5` en la lista por defecto (7,16 MHz no es contrato). La primera corrida también se cortó con WSL (código 127) tras `nowait`; el resto se relanzó por nombre |
| video | `tb/video/run.sh` | **121 de 121 casos pasan** |
| integ | `bash fpga/tb/integ/run.sh` | **21 de 21**: pins (150 casos, 968 comprobaciones) y la guardia en 10 escenarios por variante, `busok` incluido |

## 4. Builds

Gowin 1.9.12.03, GW2AR-LV18QN88C8/I7. Con las opciones de P&R de antes (las
del barrido del 26/10 de integ y las del hito 1 en MegaRAM) solo pasaba
`v9990_megaram_sync`: el RTL fusionado mueve la colocación entera, como
avisaba la nota de integ. Barrido sobre el árbol `d3444d9` (copias en
`C:/Users/alber/AppData/Local/Temp/v99wt/fu_*`, puerta con `--sin-ref`):

| Variante | Opciones | Puerta | Fmax CLK_BASE | Peor setup | Carrera CLK_BASE→DCLK | CLS |
|---|---|---|---|---|---|---|
| `v9990_xtal` | place 0, route 0 (también con `-map_option` 2, 3 o 4) | FALLA | 108,057 | +0,005 | +0,601 | 8 538 |
| `v9990_xtal` | place 2, route 0 (`-map_option` 2 o 3) | FALLA | 108,12-108,27 | +0,010/+0,023 | — | 8 474 |
| `v9990_xtal` | place 0, route 2 (con o sin `-map_option`) | PASA | 115,549 | +0,460 | +0,460 | 8 538 |
| `v9990_xtal` | **place 2, route 2** (con o sin `-map_option`) | **PASA** | **119,478** | +0,692 | +0,692 | 8 474 |
| `v9990_sync` | place 0, route 1 | FALLA | 107,909 | +0,045 | +0,453 | 8 516 |
| `v9990_sync` | place 0, route 2 | PASA | 114,813 | +0,134 | +0,134 | 8 516 |
| `v9990_sync` | **place 2, route 2** | **PASA** | **114,373** | +0,569 | +1,223 | 8 460 |
| `v9990_megaram_xtal` | place 2, route 0 (`-map_option` 2) | FALLA | 108,931 | +0,079 | +1,517 | 8 988 |
| `v9990_megaram_xtal` | place 2, route 1 (las del hito 1) | FALLA | 108,038 | +0,003 | +1,727 | 8 995 |
| `v9990_megaram_xtal` | place 2, route 2 | PASA | 111,377 | +0,281 | +1,513 | 8 995 |
| `v9990_megaram_xtal` | **place 0, route 2** | **PASA** | **122,956** | +1,119 | +1,119 | 9 046 |
| `v9990_megaram_sync` | **place 2, route 1** (las del hito 1) | **PASA** | **120,188** | +0,992 | +1,316 | 8 971 |

Las filas con `-map_option` dan un `.fs` con el cuerpo idéntico al de la misma
colocación y rutado sin esa opción: en esta versión de Gowin no cambia nada.
Route 1 es el lento: 17 min en el barrido y 31 min la build final de
`v9990_megaram_sync` (con los bancos corriendo a la vez en WSL), frente a 4-5
min con route 2. Las FALLA lo son solo por Fmax (< 109 MHz): ninguna tiene
endpoints violados (CLK_BASE se restringe a 108 MHz). Cuatro corridas del
barrido de `v9990_sync` (P0r0, P2r0, M2P0r2, M2P2r2) se cortaron con la sesión y
no tienen resultado; no hacían falta.

Con route 0 ninguna opción de síntesis (`-map_option` 2, 3 o 4) ni de
colocación pasa en `xtal`; con route 2 pasan todas las probadas. **No ha hecho
falta ninguna palanca del estudio** (`ENABLE_R16`, `ENABLE_CURSOR_EOR`,
`BLEND`): las cuatro variantes pasan con el RTL completo. Las opciones elegidas
están en cada `build_<cfg>_<variante>.tcl` (`c924e80`).

Builds finales en el worktree (`gw_sh build_<cfg>_<variante>.tcl` desde
`fpga/`, `c924e80`), archivadas con `tools/archive_build.py` en
`fpga/reports/fusion/<cfg>_<variante>/` (`3a7444c`) con la puerta pasada sobre
lo archivado (`check_build.txt`; `--sin-ref` con `--compara` frente a la build
anterior de cada configuración). El cuerpo de cada `.fs` es idéntico al de la
build del barrido con las mismas opciones (P&R determinista). Los `.fs` quedan
en `fpga/impl/fusion/` (ignorado por git):

| Variante | Opciones | Logic | CLS | BSRAM | Fmax CLK_BASE | Setup / hold peor | Violados | Puerta | `.fs` (md5 del cuerpo) |
|---|---|---|---|---|---|---|---|---|---|
| `v9990_xtal` | place 2, route 2 | 13 824 | 8 474 | 24 | 119,478 MHz | +0,692 / +0,074 ns | 0 | **PASA** | `89f0c2af` |
| `v9990_sync` | place 2, route 2 | 13 794 | 8 460 | 24 | 114,373 MHz | +0,569 / +0,074 ns | 0 | **PASA** | `b99c780f` |
| `v9990_megaram_xtal` | place 0, route 2 | 15 147 | 9 046 | 29 | 122,956 MHz | +1,119 / +0,074 ns | 0 | **PASA** | `74a8d950` |
| `v9990_megaram_sync` | place 2, route 1 | 15 260 | 8 971 | 29 | 120,188 MHz | +0,992 / +0,074 ns | 0 | **PASA** | `20efb630` |

En las cuatro: grupos de reloj `Actived`, 0 endpoints violados en setup, hold,
recovery y removal, 8/8 PRIMARY, 2/2 rPLL, CLS por debajo del aviso (9 250; el
más alto, `v9990_megaram_xtal`, a 204 del aviso y 285 del máximo). Frente a las
builds de antes de la fusión, `v9990` crece +2,9 % (sync) y +4,4 % (xtal) de
lógica (core del hito 2, bus del hito 5 y upscan PAL) y MegaRAM baja un
1,5-2,2 %.

## 5. Pendiente y riesgos

- **Todo lo de placa**, de cada área y de la integración (las listas de las
  notas), más lo nuevo de la fusión: el LED con el /RESET del MSX pulsado (debe
  parpadear lento) y en `xtal` sin MSX (destello corto), y que un /RESET del MSX
  con el V9990 pidiendo /WAIT no deje el Z80 colgado.
- **Márgenes y opciones por variante**: el juego de cada variante vale para este
  RTL; cualquier cambio obliga a barrer otra vez (la nota de integ, sección 6).
  Con route 2 hay más margen que en las builds de los hitos 3 y 6.
- **Documentación de las áreas que pide la integración**: ver la sección 6.

## 6. Documentación

Al día con la fusión (`c70c299`): `docs/ARCHITECTURE.md` (bloques que
cambian, mapa de la SDRAM, registros nuevos de la megaROM, cruces de reloj
nuevos), `docs/WONDERTANG.md` (turbo con el pre-WAIT del hito 5) y
`docs/notas/sdram.md` (el contrato `ACK_n`/`DOUT` del canal 0, que la megaROM
con `ENABLE_MEM_WAIT` sí usa). Las notas de área conservan sus cifras de antes
de la fusión; las de esta nota son las del árbol fusionado.

## 7. Banco de placa entera y arreglo de `sdram.sv`

Después de la fusión, `fpga/tb/top` simula el top completo de las cuatro
variantes con la lista de `build_common.tcl`. Alrededor van el cristal, el
CLOCK del slot, la SDRAM modelada, el multiplexor y un Z80 a nivel de pines.
Cubre el arranque, P#0, P#1, el LMMV, `/INT`, el vídeo NTSC y PAL, la MegaRAM
con `tncrom` y PLAIN0, y un `/RESET` con `/WAIT`, a 3,58 MHz y una pasada a
5,37 MHz. Qué modela, qué mide y qué no cubre está en
[VERIFICATION.md](../VERIFICATION.md#banco-de-placa-entera-fpgatbtop).

Encontró un fallo de RTL. `SDRAM_CMD` de `sdram.sv` no tenía valor de reset,
así que la SDRAM recibía MODE REGISTER SET con A = 0 en cada flanco antes de
`BASE_READY`. Era el riesgo apuntado en [sdram.md](sdram.md). Ahora pone NOP
en el reset (`389ce97`), y las cuatro variantes se han vuelto a compilar y
pasan la puerta. Sus `.fs` (`fpga/impl/sdram_nop/`, evidencia en
`fpga/reports/sdram_nop/`) sustituyen a los de la sección 4. Las 12
ejecuciones del banco pasan sobre el árbol arreglado, y el banco de
`tb/sdram` da las mismas cifras. Nada de esto se ha probado en la placa.

## 8. Revisión de la fusión y builds finales

Dos revisores repasaron el árbol fusionado (`373a53f`). Veredictos:
"aceptable" (RTL, bancos y builds) y "aceptable con arreglos" (documentación).
Lo que se ha hecho con cada hallazgo:

| Hallazgo | Severidad | Qué se hizo |
|---|---|---|
| La guardia sincronizaba a `CLK_27M` la AND combinacional `sys_ready && bus_ok` de dos flops de `CLK_BASE`; el comentario de los `.sdc` decía `SYS_RESET_n` | baja | Arreglado (`c8e4fd2`): la AND pasa por un flop de `CLK_BASE` (`sys_bus_ready`) antes de cruzar; comentario de los cuatro `.sdc` al día |
| En `xtal`, con la Tang alimentada por USB, al encender otra vez el MSX no había `BOOT_HOLD` y el Z80 corría hasta 2,43 ms con el cartucho mudo | baja | Arreglado (`c8e4fd2`): el tope se rearma cuando vuelve el reloj del slot. Escenario nuevo `usb` en `tb/integ`; con la guardia anterior falla (3 de 32, sin `BOOT_HOLD` durante 2,428 ms) |
| `WONDERTANG.md` seguía en el hito 1 (J3, slot, bootloader, LED, qué `.fs`) | media | Reescrita por configuración y variante (`f470cf1`, `3510007`) |
| `WONDERTANG.md` decía que todo cabía a 5,37 MHz | media | Limitado a la E/S del V9990; la MegaRAM, solo a 3,58 MHz (`f470cf1`) |
| README y changelog en el hito 1 | baja | Al día (`8eec89c`) |
| `VERIFICATION.md`: referencias de la puerta del hito 1 y matriz de monitores solo NTSC de `xtal` | baja | Orden de la puerta por variante con sus referencias y matriz con NTSC/PAL y `xtal`/`sync` (`3510007`) |

Con el RTL nuevo, `v9990_megaram_sync` con place 2 / route 1 daba 109,50 MHz,
al límite; pasa a place 2 / route 2 (125,93 MHz, `055c865`). Las otras tres
conservan sus opciones.

**Builds finales** (`36f8f5b`): las cuatro se han rehecho sobre `055c865` con
`gw_sh build_<variante>.tcl` y pasado la puerta **con referencia** (las cifras
de `VERIFICATION.md`, tolerancia 1 %, desviación +0,00 % en las cuatro). El
cuerpo de cada `.fs` es idéntico al de la build anterior con el mismo RTL y
las mismas opciones (P&R determinista). Evidencia en
`fpga/reports/fusion/<variante>/`. Los `.fs` están en `fpga/impl/final/` y
`fpga/impl/fusion_rev/`, que git ignora, y son los que hay que cargar en la
placa:

| Variante | Opciones | Logic | CLS | BSRAM | Fmax CLK_BASE | Setup / hold peor | Violados | `.fs`: CheckSum, md5 del cuerpo |
|---|---|---|---|---|---|---|---|---|
| `v9990_xtal` | place 2, route 2 | 13 653 | 8 421 | 24 | 111,763 MHz | +0,312 / +0,074 ns | 0 | `0x345D`, `aa4b16ac` |
| `v9990_sync` | place 2, route 2 | 13 874 | 8 489 | 24 | 115,873 MHz | +0,682 / +0,074 ns | 0 | `0x7B75`, `0017f68e` |
| `v9990_megaram_xtal` | place 0, route 2 | 15 168 | 9 019 | 29 | 121,542 MHz | +0,368 / +0,074 ns | 0 | `0x95F1`, `97bb2bee` |
| `v9990_megaram_sync` | place 2, route 2 | 15 253 | 8 973 | 29 | 125,925 MHz | +1,095 / +0,074 ns | 0 | `0x4693`, `c194119b` |

En las cuatro: grupos de reloj `Actived`, 0 endpoints violados en setup,
hold, recovery y removal, 8/8 PRIMARY, 2/2 rPLL y CLS por debajo del aviso.
El margen más corto es el de `v9990_xtal`: 2,76 MHz sobre el mínimo.

**Bancos sobre el árbol final** (`055c865`, 28/10, todos con Verilator 5.020):

- core: los 15 casos de `geom`, `pal`, `blit`, `ports`, `eor`, `r16`,
  `r16chg`, `bdbp`, `assert` (la autocomprobación salta 29 366 veces, como se
  espera) y `hito1` (vídeo idéntico en los 7 casos); paleta `PAL_OK`; replay de
  GNG con 0 bytes distintos de 524 288 frente a openMSX. 0 ranuras perdidas.
- sdram: TOTAL PASA (solo cambia la cabecera de `resultados.txt`).
- bus: TOTAL PASA, 20 de 20 en la matriz; `EQ_OK` en MODE 0 y 1 (MODE 2 es el
  control y falla, como debe); `M1SPUR_OK` en los 6 casos.
- integ: pins 150 casos y 968 comprobaciones; guardia, 11 escenarios en
  `SYNC=0` y 11 en `SYNC=1`, incluidos `busok` y `usb`, sin fallos.
- video: 121 de 121.
- megaram (lanzado desde Git Bash, que es lo que saca de git el bus y el UMA de
  `main`): las 17 variantes, 25 `RESULTADO: PASA` y ninguna FALLA.
- tb/top: 12 de 12 (cuatro variantes en `full`, `io` a 5,37 MHz y `nomsx`). En
  la MegaRAM a 5,37 MHz siguen las 16 y 29 lecturas mal leídas de 63, que es
  medida y no contrato.

Nada de esto se ha probado en la placa.
