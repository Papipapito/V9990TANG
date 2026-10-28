# Procedencia

Este repositorio no es un fork con historia: es una copia de un subconjunto de
dos proyectos BSD-3, hecha el 22 de octubre de 2026, más los ficheros propios del
port. Los avisos de copyright de cada fichero copiado se conservan sin cambios.
Los cambios de cada área sobre los ficheros copiados están en su nota de
`docs/notas/` (ver [el anexo](docs/notas/README.md)); `git diff` contra el
commit de upstream los enseña todos (ver [Fines de línea](#fines-de-línea)).

## Proyectos de origen

| Proyecto | Commit | Autor | Licencia | Qué se toma |
|---|---|---|---|---|
| [herraa1/tnCartWonder](https://github.com/herraa1/tnCartWonder) | `d3a54f1b0df9e56c0d27ce1d0460f79f593d5568` (2025-10-02, "readme: make links for .fs files") | Albert Herranz, sobre el tnCart de Shinobu Hashimoto | BSD 3-Clause | la carcasa de la WonderTANG 2.00b/2.02b (`wt200b`): top, relojes, pines, `.sdc` de referencia, bus multiplexado, SDRAM + UMA, upscan, DVI, bootloader, flash, LED, DAC y los cartuchos V9990 y megaROM |
| [buppu3/tnCart](https://github.com/buppu3/tnCart) | `87147318e94f9c1714bb793093769dbe42abea7a` (2024-10-19, "Fix VRAM mask in V9990 P1 mode") | Shinobu Hashimoto (buppu3) | BSD 3-Clause | el core **tiny9990** (`fpga/v9990/tiny9990/`), sin parches |

tnCartWonder es un fork lineal de tnCart: `d3a54f1` = tnCart `9bbefbe`
(2024-10-26, buppu3, "fix #23 Generation of Bus.CLK_EN_21M fails when using
onboard 27MHz oscillator") más cuatro commits de herraa1 que añaden la placa
wt200b, su README y su bitstream. Entre `8714731` y `9bbefbe` buppu3 añadió la
placa rev2 (`481a2d8` y `d230d90`, que toca `main.sv` y `config.sv`:
`ENABLE_DAC_I2S`, `ENABLE_DAC_STEREO`) y el fix #23 (`9bbefbe`, en
`board_rev1_bus.sv`). Así que los ficheros comunes de la carcasa (`main.sv`,
`config.sv`, `board_rev1_bus.sv` y los demás) están al nivel de tnCart `9bbefbe`,
llegados a través de tnCartWonder, que solo les añade una línea en
`board_id.sv`.

El tiny9990 se copió del clon de tnCartWonder, pero es el de tnCart `8714731`:
es el último commit que toca `rtl/src/peripheral/video/tiny9990/` en esa
historia, y `git diff 8714731 d3a54f1 -- rtl/src/peripheral/video/tiny9990`
está vacío. Ninguno de los commits posteriores, de buppu3 o de herraa1, toca el
core.

**tiny9990**: emulación del V9990 de Yamaha escrita por Shinobu Hashimoto, © 2024,
BSD 3-Clause (aviso en la cabecera de cada fichero de `fpga/v9990/tiny9990/`).

## IP del fabricante

`fpga/src/board/rev1/dvi_tx/` contiene el IP **DVI_TX** de Gowin Semiconductor
tal como lo distribuyen tnCart y tnCartWonder: `dvi_tx.v` es la netlist **cifrada**
(`pragma protect`, generada con GowinSynthesis 1.9.9), `dvi_tx.ipc` la
configuración del generador de IP y `dvi_tx.vo` el modelo de simulación post-PnR
("All rights reserved", © Gowin). No es BSD: es IP del fabricante, que solo se
puede sintetizar con las herramientas de Gowin.

## Mapa de ficheros

Origen: `tnCartWonder/rtl/src/` salvo que se diga otra cosa. "Build" indica si el
fichero entra en la build `v9990` (`fpga/build_common.tcl`, que cargan
`fpga/build_v9990_xtal.tcl` y `fpga/build_v9990_sync.tcl`; en el hito 1 era
`fpga/build_v9990_xtal.tcl` solo). Los cambios de los hitos 3 y 6 están en
`docs/notas/integ.md`.

| Destino | Origen | Build | Notas |
|---|---|---|---|
| `fpga/src/tnCart_board_wt200b_top.sv` | igual | sí | top de la placa; desde el hito 3 sin `FLASH_SPI`, los `SPI` ni el LED de tnCart (pines en reposo), con la guardia de lock, la cadena de reset y el LED de estado |
| `fpga/src/main.sv` | igual | sí | desde el hito 3 sin bootloader: `SYS_RESET_n` por POR (`system/system_reset.sv`); en `v9990` el V9990 va directo al bus, sin slot expandido; en `v9990_megaram`, slot expandido con la megaROM en la subranura 0 y `MEGAROM_CLEAR` (hito 8) |
| `fpga/src/cartridge_v9990.sv` | igual | sí | puertos 60h-6Fh, genera `Video.DCLK`; desde la fusión lleva la salida `PAL` del core a `Video.PAL` y los parámetros del core por configuración |
| `fpga/src/bootloader.sv` | igual | solo MegaRAM | ya no se instancia (hito 3); la configuración MegaRAM lo compila por el paquete `XFER` y `XFER_IF` |
| `fpga/src/cartridge_megarom.sv` | igual | solo MegaRAM | hito 8: /WAIT en las lecturas de memoria (`ENABLE_MEM_WAIT`) (`docs/notas/megaram.md`) |
| `fpga/src/board/board_id.sv` | igual | sí | |
| `fpga/src/board/rev1/board_rev1_bus.sv` | igual | sí | bus multiplexado de 9 estados y filtros de pin (`PIN_FILTER`); desde el hito 5, escaneo adaptativo, pre-WAIT, rearme, timeout del /WAIT, `BUS_OK` y las guardias `DRIVE_EN`/`BOOT_HOLD` (`docs/notas/bus.md`) |
| `fpga/src/board/rev1/board_rev1_tmds.sv` | igual | sí | envoltorio del DVI_TX |
| `fpga/src/board/rev1/dvi_tx/dvi_tx.{v,ipc,vo}` | igual | `.v` sí | IP cifrado de Gowin |
| `fpga/src/board/wt200b/board_wt200b_clock.sv` | igual | sí | rPLL 108 MHz (xtal) o 107,386 MHz (sync); desde el hito 6 el rPLL base con reset del POR y `LOCK` crudo |
| `fpga/src/board/wt200b/board_wt200b_config_xtal.sv`, `board_wt200b_config_sync.sv` | `board/wt200b/board_wt200b_config.sv` | uno por variante | partido en el hito 6: `SYNC_CPU_CLK = 0` (xtal) o `1` (sync), `SYNC_CPU_UMA = 0` en los dos; `board_wt200b_config.sv` ya no existe |
| `fpga/src/board/wt200b/board_wt200b_guard.sv` | propio | sí | POR, gestor del rPLL base y guardia de lock (27 MHz). El `board_wt200b_bus_guard.sv` provisional de los hitos 3 y 6 desapareció en la fusión: los pines los gatea `board_rev1_bus.sv` |
| `fpga/src/system/system_reset.sv`, `megarom_xfer_tie.sv` | propios | `system_reset.sv` sí; el otro solo MegaRAM | cadena de reset en `CLK_BASE`; `XFER_IF` atado de la megaROM |
| `fpga/src/board/wt200b/board_wt200b.cst` | igual | sí | pines de la WonderTANG 2.00b/2.02b |
| `fpga/src/board/wt200b/board_wt200b_27M.sdc` | igual | no | referencia; lo sustituye `fpga/constraints/v9990_xtal.sdc` |
| `fpga/src/board/wt200b/board_wt200b_3_58M.sdc` | igual | no | referencia para la variante `sync` (hito 6) |
| `fpga/src/peripheral/flash.sv` | igual | solo MegaRAM | ya no se instancia (hito 3); la MegaRAM lo compila por `FLASH_IF` |
| `fpga/src/peripheral/spi.sv` | igual | solo MegaRAM | ya no se instancia (hito 3); la MegaRAM lo compila por `SPI_IF` |
| `fpga/src/peripheral/led.sv` | igual | sí | `LED` de tnCart sin cambios y sin instanciar; se añade `STATUS_LED` con los códigos 0-5 (hitos 3 y 6) |
| `fpga/src/peripheral/msx/bus.sv` | igual | sí | `BUS_IF` (y `EXPANSION_BUS`, que no se instancia) |
| `fpga/src/peripheral/msx/expansion_slot.sv` | igual | sí | slot expandido |
| `fpga/src/peripheral/msx/megarom_configure.sv`, `megarom_controller.sv` | igual | solo MegaRAM | hito 8: ventana de 4 MB, modo PLAIN0 y su borrado con el /RESET |
| `fpga/src/peripheral/msx/megarom_clear.sv` | propio | solo MegaRAM | borrado de los primeros 32 KB de la megaROM a `FFh` al arrancar (hito 8) |
| `fpga/src/peripheral/ram/ram.sv`, `sdram.sv`, `uma.sv` | igual | sí | SDRAM + UMA, sin tocar la cadencia; desde el hito 4, refresco propio del UMA y AUTO REFRESH en la inicialización, y NOP en los pines de la SDRAM durante el reset (`docs/notas/sdram.md`) |
| `fpga/src/peripheral/signal/attenuator.sv`, `limiter.sv` | igual | sí | mezclador de sonido de `main.sv` |
| `fpga/src/peripheral/sound/sound.sv`, `dac_16bit.sv`, `i2s_audio_tx.sv` | igual | sí | DAC I2S de la WonderTANG |
| `fpga/src/peripheral/sound/scc/scc.sv` | igual | solo MegaRAM | SCC de la megaROM, sin cambios |
| `fpga/src/peripheral/video/video.sv`, `video_upscan.sv` | igual | sí | upscan a 720x480 en 855x524; desde la fusión, `VIDEO_IF.PAL`, 720x576 en 855x626 y la palanca `BLEND` (`docs/notas/video.md`) |
| `fpga/v9990/tiny9990/*.sv` (17 ficheros) | `peripheral/video/tiny9990/` | sí | core sin parches en el hito 1; desde los hitos 2 y 7, con los seis parches, P#8-P#15 a `FFh`, PAL, cursor EOR, R#16 y la aserción de ranura perdida (`docs/notas/core.md`) |
| `fpga/config/v9990.sv` | `config.sv` | sí | solo cambian los `ENABLE_*`: V9990 y su VDP de comandos activos, el resto desactivado; desde la fusión, las palancas del core, de `BLEND` y del pre-WAIT de memoria |
| `fpga/config/v9990_megaram.sv` | `config/v9990.sv` | una de las dos | configuración MegaRAM (hito 8): `ENABLE_MEGA_SCC_I`, SCC, ventana de 4 MB en `00_0000h`, `ENABLE_MEM_WAIT` |
| `fpga/constraints/v9990_xtal.sdc` | propio | sí | relojes del `board_wt200b_27M.sdc` presentes en esta configuración y grupos asíncronos propios |
| `fpga/constraints/v9990_sync.sdc`, `v9990_megaram_xtal.sdc`, `v9990_megaram_sync.sdc` | propios | uno por build | variante `sync` (hito 6, a partir de `board_wt200b_3_58M.sdc`) y configuración MegaRAM |
| `fpga/build_common.tcl`, `fpga/build_v9990_{xtal,sync}.tcl`, `fpga/build_v9990_megaram_{xtal,sync}.tcl` | propios, a partir de `tnCart_board_wt200b.gprj` | — | lista de ficheros y opciones comunes, y un script por configuración y variante (hito 6) |
| `fpga/tb/integ/` | propio | — | banco Verilator de la guardia de lock, el POR y los pines (hitos 3 y 6) |
| `tools/check_build.py`, `tools/archive_build.py` | propios | — | la puerta de cada build y el archivado de su evidencia (BSD 3-Clause, cabecera propia) |
| `fpga/reports/hito1/v9990_xtal.rpt.txt`, `.tr`, `.sdf`, `gwsynthesis.log`, `pnr.log` | generados por `gw_sh` 1.9.12.03 en la build del hito 1 | — | evidencia de la build. El `.rpt.txt` y el `.tr` van sin modificar y con la cabecera de Gowin; el `.sdf` es un extracto que conserva esa cabecera y copia celdas y líneas sin cambiar ningún valor; los logs no llevan cabecera. Ninguno es BSD (ver `LICENSE`) |
| `fpga/reports/hito1/v9990_xtal.sdc`, `check_build.txt`, `v9990_xtal.fs.txt` | propios | — | copia del `.sdc` con el que se hizo la build, salida de la puerta y sumas del bitstream |
| `fpga/reports/hito1/variante_dclk_asincrono/` | `gw_sh` (informes y logs) y propios (`.sdc`, `LEEME.txt`, `check_build.txt`) | — | variante de comparación de la Fmax, no es la build del hito |
| `fpga/reports/hito3/` (`v9990_xtal`), `fpga/reports/hito6/` (`v9990_sync`) | como los de `hito1/` | — | evidencia de las builds de los hitos 3 y 6, con los mismos criterios que la del hito 1 |
| `fpga/reports/sdram_nop/`, `fpga/reports/fusion/`, `fpga/reports/v0.1beta/` (una carpeta por variante) | como los de `hito1/` | — | evidencia de las builds de la fusión: con el NOP de la SDRAM, las finales de la revisión y las de la 0.1beta (las mismas builds que `fusion/`, con la puerta repetida) |
| `fpga/tb/{core,sdram,bus,video,megaram,top}/` | propios | — | bancos de las áreas y de la placa entera (Verilator 5.020). El modelo de SDRAM de `tb/sdram` (`sdram_model_bl.v`) parte del `sdram_model.v` del MoonTANG (ver `docs/notas/sdram.md`); `tb/top/gowin_models.sv` son modelos de comportamiento propios de las primitivas de Gowin, solo para simulación |
| `tools/tncrom/{src,cfg,lib}`, `LICENSE` | `tnCartWonder/tools/tncrom/{src,cfg}` y `tools/lib` de `d3a54f1` | — | cargador de ROMs de la megaROM, BSD-3 de Shinobu Hashimoto; extendido (PLAIN0, máximos por tipo, máscara Konami, `-S` con comprobación: líneas marcadas `V9990TANG`) y compilado con SDCC en lugar de z88dk (`tools/tncrom/build.sh`, `sdcc/`, propios); `test/` es un banco propio del host (`docs/notas/megaram.md`, apartado 6) |
| `tools/tncrom/bin/TNCROM.COM`, `bitstream/TNCROM.COM` | generado | — | binario de `build.sh` (r3, 13 700 bytes) |
| `bitstream/*.fs` | generados por `gw_sh` 1.9.12.03 | — | los cuatro bitstreams de la 0.1beta, copias de `fpga/impl/pnr/`. Llevan dentro el IP DVI_TX de Gowin. `SHA256SUMS.txt`, `LEEME.md` y `README.md` son propios |

## Lo que no se copia

- **FM** (`cartridge_fm.sv`, IKAOPLL, VM2413), **PSG** (`cartridge_psg.sv`,
  `ym2149_audio`), **SCC de IKA** (IKASCC), **RAM mapper** (`cartridge_ram.sv`),
  **Nextor** (`cartridge_nextor.sv`, `tf_controller.sv`) y el **PAC**
  (`pacrom_controller.sv`): un cartucho V9990 no los usa. `main.sv` los instancia
  dentro de bloques `if(CONFIG::ENABLE_*)` que la configuración `v9990` deja sin
  elaborar, así que no hacen falta en la build. Si la variante opcional con Nextor
  llega a construirse, sus ficheros se traen entonces del mismo commit.
- El **UART** (`uart.sv`): la wt200b lo tiene desactivado
  (`CONFIG_BOARD::ENABLE_UART_MODULE = 0`) y el top solo lo instancia dentro de
  ese `if`; la salida `UART_TX` queda a 1.
- `video_dummy.sv`, `dac_1bit.sv`, `dac_i2s.sv`: no los usa la wt200b.
- Los tops y placas de tnCart rev1/rev2 y de las WonderTANG 1.01c/1.02d, el
  KiCad, las ROMs y las herramientas MSX de tnCart.

## Fines de línea

Los ficheros se copiaron desde los objetos de git (`git show d3a54f1:...` para la
carcasa y `git show 8714731:...` para el core), no desde la copia de trabajo del
clon, que tenía `core.autocrlf=true`. El hash de blob de cada fichero copiado
coincide con el del objeto de upstream, así que un `git diff` de `fpga/src/`
contra tnCartWonder `d3a54f1` y de `fpga/v9990/tiny9990/` contra tnCart `8714731`
solo enseña cambios reales. `.gitattributes` los guarda byte a byte.

## Estudio

El plan de hitos, las medidas de partida y las decisiones de este port salen de
un estudio que vive en el repositorio de la MSXimus Z (Papipapito/MSXimus_zynq):
`docs/estudios/v9990-wondertang.md`, rama `claude/v9990-wondertang-port-b2a930`,
commit `ac25ca6` (22 de octubre de 2026). Esa rama no está publicada todavía;
las cifras del estudio que se usan aquí están copiadas en `docs/`. Una
corrección: la sección 3 del estudio dice que Gowin descarta en silencio una
orden del `.sdc` que nombra un reloj inexistente; en realidad el P&R aborta con
`ERROR (TA2004)` (comprobado en el hito 1, ver `docs/ARCHITECTURE.md`).

## Bootloader y flash

El top de la wt200b instancia siempre `FLASH_SPI` y dos `SPI`, y `main.sv`
instancia siempre el `BOOTLOADER`, que además retiene `SYS_RESET_n` hasta acabar.
Quitarlos exige cambiar el RTL (un POR que espere al lock del PLL y al READY de la
SDRAM), y eso es el hito 3 del plan. En el hito 1 se quedan en la build, igual que
en la build de referencia del estudio, para poder reproducir sus números. Desde el
hito 3 ya no están en la build `v9990` (`docs/notas/integ.md`).
