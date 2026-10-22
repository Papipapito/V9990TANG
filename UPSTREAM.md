# Procedencia

Este repositorio no es un fork con historia: es una copia de un subconjunto de
dos proyectos BSD-3, hecha el 22 de octubre de 2026, más los ficheros propios del
port. Los avisos de copyright de cada fichero copiado se conservan sin cambios.

## Proyectos de origen

| Proyecto | Commit | Autor | Licencia | Qué se toma |
|---|---|---|---|---|
| [herraa1/tnCartWonder](https://github.com/herraa1/tnCartWonder) | `d3a54f1b0df9e56c0d27ce1d0460f79f593d5568` (2025-10-02, "readme: make links for .fs files") | Albert Herranz, sobre el tnCart de Shinobu Hashimoto | BSD 3-Clause | la carcasa de la WonderTANG 2.00b/2.02b (`wt200b`): top, relojes, pines, `.sdc` de referencia, bus multiplexado, SDRAM + UMA, upscan, DVI, bootloader, flash, LED, DAC y los cartuchos V9990 y megaROM |
| [buppu3/tnCart](https://github.com/buppu3/tnCart) | `87147318e94f9c1714bb793093769dbe42abea7a` (2024-10-19, "Fix VRAM mask in V9990 P1 mode") | Shinobu Hashimoto (buppu3) | BSD 3-Clause | el core **tiny9990** (`fpga/v9990/tiny9990/`), sin parches |

El tiny9990 se copió del clon de tnCartWonder, pero es el de tnCart: el último
commit que toca `rtl/src/peripheral/video/tiny9990/` en esa historia es
`8714731` de buppu3, y `git diff 8714731 d3a54f1 -- rtl/src/peripheral/video/tiny9990`
está vacío. tnCartWonder es un fork de tnCart; los commits de herraa1 posteriores
a `8714731` añaden la placa wt200b y no tocan el core.

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
fichero entra en `fpga/build_v9990_xtal.tcl`.

| Destino | Origen | Build | Notas |
|---|---|---|---|
| `fpga/src/tnCart_board_wt200b_top.sv` | igual | sí | top de la placa, sin cambios |
| `fpga/src/main.sv` | igual | sí | instancia siempre el bootloader (gatea `SYS_RESET_n`) |
| `fpga/src/cartridge_v9990.sv` | igual | sí | puertos 60h-6Fh, genera `Video.DCLK` |
| `fpga/src/bootloader.sv` | igual | sí | ver "Bootloader y flash" abajo |
| `fpga/src/cartridge_megarom.sv` | igual | no | para el hito 8 (MegaRAM) |
| `fpga/src/board/board_id.sv` | igual | sí | |
| `fpga/src/board/rev1/board_rev1_bus.sv` | igual | sí | bus multiplexado de 9 estados |
| `fpga/src/board/rev1/board_rev1_tmds.sv` | igual | sí | envoltorio del DVI_TX |
| `fpga/src/board/rev1/dvi_tx/dvi_tx.{v,ipc,vo}` | igual | `.v` sí | IP cifrado de Gowin |
| `fpga/src/board/wt200b/board_wt200b_clock.sv` | igual | sí | rPLL 108 MHz (xtal) o 107,386 MHz (sync) |
| `fpga/src/board/wt200b/board_wt200b_config.sv` | igual | sí | `SYNC_CPU_CLK = 0` |
| `fpga/src/board/wt200b/board_wt200b.cst` | igual | sí | pines de la WonderTANG 2.00b/2.02b |
| `fpga/src/board/wt200b/board_wt200b_27M.sdc` | igual | no | referencia; lo sustituye `fpga/constraints/v9990_xtal.sdc` |
| `fpga/src/board/wt200b/board_wt200b_3_58M.sdc` | igual | no | referencia para la variante `sync` (hito 6) |
| `fpga/src/peripheral/flash.sv` | igual | sí | lo instancia el top |
| `fpga/src/peripheral/spi.sv` | igual | sí | SPI de la flash y de la TF |
| `fpga/src/peripheral/led.sv` | igual | sí | |
| `fpga/src/peripheral/msx/bus.sv` | igual | sí | `BUS_IF`, filtros de pin |
| `fpga/src/peripheral/msx/expansion_slot.sv` | igual | sí | slot expandido |
| `fpga/src/peripheral/msx/megarom_configure.sv`, `megarom_controller.sv` | igual | no | para el hito 8 |
| `fpga/src/peripheral/ram/ram.sv`, `sdram.sv`, `uma.sv` | igual | sí | SDRAM + UMA, sin tocar la cadencia |
| `fpga/src/peripheral/signal/attenuator.sv`, `limiter.sv` | igual | sí | mezclador de sonido de `main.sv` |
| `fpga/src/peripheral/sound/sound.sv`, `dac_16bit.sv`, `i2s_audio_tx.sv` | igual | sí | DAC I2S de la WonderTANG |
| `fpga/src/peripheral/sound/scc/scc.sv` | igual | no | para el hito 8 |
| `fpga/src/peripheral/video/video.sv`, `video_upscan.sv` | igual | sí | upscan a 720x480 en 855x524 |
| `fpga/v9990/tiny9990/*.sv` (17 ficheros) | `peripheral/video/tiny9990/` | sí | core sin parches (los parches entran en el hito 2) |
| `fpga/config/v9990.sv` | `config.sv` | sí | solo cambian los `ENABLE_*`: V9990 y su VDP de comandos activos, el resto desactivado |
| `fpga/constraints/v9990_xtal.sdc` | propio | sí | relojes del `board_wt200b_27M.sdc` presentes en esta configuración y grupos asíncronos propios |
| `fpga/build_v9990_xtal.tcl` | propio, a partir de `tnCart_board_wt200b.gprj` | — | |

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
coincide con el del objeto de upstream, así que un `git diff` contra tnCart o
tnCartWonder solo enseña cambios reales. `.gitattributes` los guarda byte a byte.

## Bootloader y flash

El top de la wt200b instancia siempre `FLASH_SPI` y dos `SPI`, y `main.sv`
instancia siempre el `BOOTLOADER`, que además retiene `SYS_RESET_n` hasta acabar.
Quitarlos exige cambiar el RTL (un POR que espere al lock del PLL y al READY de la
SDRAM), y eso es el hito 3 del plan. En el hito 1 se quedan en la build, igual que
en la build de referencia del estudio, para poder reproducir sus números.
