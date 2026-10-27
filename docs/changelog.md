# Changelog

Formato: un apartado por hito o versión, lo más reciente arriba. Las cifras de
cada build están en [VERIFICATION.md](VERIFICATION.md).

## Fusión de las seis áreas (rama `hito/fusion`, 27 de octubre de 2026, sin publicar)

Las seis ramas de área entran sobre el hito 1 con merges normales, sin
conflictos de texto. Los contratos entre áreas y cómo se cablean están en
[notas/fusion.md](notas/fusion.md); cada área tiene su nota en `docs/notas/`.

- **sdram** ([notas/sdram.md](notas/sdram.md)): el UMA genera su propio AUTO
  REFRESH en el canal 0, sin tocar la cadencia de las ranuras; dos AUTO REFRESH
  en la inicialización.
- **integ** ([notas/integ.md](notas/integ.md)): fuera el bootloader, la flash,
  sus SPI y la TF. Entran el POR del rPLL, el gestor con reintentos, la guardia
  de lock (`DRIVE_EN`, y `BOOT_HOLD` con un tope de 50 ms), `STATUS_LED` con los
  códigos 0-5, las variantes de reloj `xtal` y `sync`, un `.sdc` y un
  `build_*.tcl` por variante.
- **core** ([notas/core.md](notas/core.md)): seis parches del tiny9990, P#8-P#15
  a `FFh`, cuadro PAL de 313 líneas con su salida `PAL`, cursor EOR, ajuste de
  R#16 y una aserción de simulación para las ranuras perdidas del UMA.
- **video** ([notas/video.md](notas/video.md)): `VIDEO_IF.PAL`, salida 720x576
  en un cuadro de 855x626 y la palanca `BLEND`.
- **bus** ([notas/bus.md](notas/bus.md)): escaneo adaptativo del multiplexor,
  pre-WAIT de E/S y de memoria, rearme, timeout *fail-open* del /WAIT, guardia
  de bus vivo (`BUS_OK`) y las guardias `DRIVE_EN`/`BOOT_HOLD` en los pines.
- **megaram** ([notas/megaram.md](notas/megaram.md)): configuración
  `v9990_megaram`, con la megaROM de tnCart en la subranura 0 del slot
  expandido. Arranca como Konami SCC-I RAM de 2 MB sobre una ventana de 4 MB en
  `00_0000h`, con modo PLAIN0 para las demos planas, borrado de 32 KB al
  arrancar (`MEGAROM_CLEAR`) y /WAIT en sus lecturas.
- **`tncrom` r3** (`tools/tncrom/`, compilado con SDCC): el tipo `-T PLAIN0`
  (hasta 48 KB, rellena con `FFh`; arrancar con `-R`, porque un /RESET del MSX
  desactiva PLAIN0), el máximo de cada tipo (4 MB en los de bancos de 16 KB,
  2 MB en los de 8 KB, 32/16 KB en 32K/16K, 48 KB en PLAIN0; rechaza lo que no
  cabe), la máscara de banco para los Konami SCC de 1-2 MB (`-T KONAMI`) y `-S`
  con comprobación del cartucho.
- **Después de la fusión**:
  - Banco de placa entera, `fpga/tb/top` (Verilator, el top completo). Encontró
    que `SDRAM_CMD` no tenía valor de reset (MODE REGISTER SET en los pines antes
    de `BASE_READY`); ahora va NOP en el reset (`389ce97`).
  - Arreglos de la revisión: la guardia recibe `SYS_RESET_n && BUS_OK`
    registrado en un flop de `CLK_BASE`, y en `xtal` el tope de `BOOT_HOLD` se
    rearma cuando vuelve el reloj del slot (MSX apagado y encendido con la Tang
    alimentada por USB; antes el Z80 podía correr hasta 2,43 ms con el cartucho
    mudo). El escenario nuevo `usb` de `tb/integ` lo comprueba.
  - Las guías de usuario al día: [WONDERTANG.md](WONDERTANG.md) y el README.
- **Builds**: las cuatro variantes pasan la puerta con el RTL completo, sin
  ninguna palanca del estudio. Cada una lleva sus opciones de P&R del barrido.
  Las cifras y las órdenes están en [VERIFICATION.md](VERIFICATION.md#builds-de-la-fusión),
  y la evidencia, en `fpga/reports/fusion/`.
- **Límites conocidos**: la MegaRAM solo vale a 3,58 MHz (a 5,37 MHz fallan
  las lecturas de la megaROM, también en el banco); la E/S del V9990, a 3,58 y
  5,37 MHz; nada por encima. **Sin probar en placa.**

## Hito 1: repo y referencia (22 de octubre de 2026, sin publicar)

- Repositorio nuevo, BSD 3-Clause, con la carcasa wt200b de herraa1/tnCartWonder
  `d3a54f1` y el core tiny9990 de buppu3/tnCart `8714731` **sin parches**,
  copiados desde los objetos de git (ver [UPSTREAM.md](../UPSTREAM.md)). El
  bootloader, la flash y los SPI siguen en la build porque el top y `main.sv` los
  instancian siempre; quitarlos es el hito 3.
- `fpga/config/v9990.sv`: configuración solo-V9990 (V9990 y su VDP de comandos;
  megaROM, FM, PSG, Nextor, RAM mapper, SCC y PAC desactivados).
- `fpga/constraints/v9990_xtal.sdc`: los relojes del `board_wt200b_27M.sdc` de
  tnCartWonder que existen en esta configuración y grupos asíncronos revisados cruce a cruce. Con
  `CLK_21M`, que aquí no existe, el P&R de Gowin aborta; la build de referencia
  del estudio había borrado por eso el `set_clock_groups`, y sus 290 endpoints de
  setup y su recovery violados venían de ahí. `DCLK` deja de ser un grupo
  asíncrono: es un reloj generado con flops de `CLK_BASE`, con una carrera en el
  mismo flanco que ahora vigila el STA (ver
  [ARCHITECTURE.md](ARCHITECTURE.md#cruces-de-reloj-y-sdc)).
- `fpga/build_v9990_xtal.tcl`: build con `gw_sh` desde el propio repositorio.
- `tools/check_build.py` y `tools/archive_build.py`: la puerta de cada build
  (incluida la comprobación del modelo de `DCLK` contra el SDF) y el archivado
  de su evidencia en `fpga/reports/`.
- Build: 14 140 lógica (igual que la referencia), 8 679 CLS (−0,20 %), 24 BSRAM,
  todas las restricciones activas, **0 endpoints violados** en setup, hold,
  recovery y removal, Fmax de `CLK_BASE` 109,08 MHz, rPLL 2/2, PRIMARY 8/8.
- Sin probar en placa. Pendiente del hito 1: un programa V9990 de disco que pinte
  por HDMI en dos monitores (ver la matriz de monitores de
  [VERIFICATION.md](VERIFICATION.md#matriz-de-monitores)).
