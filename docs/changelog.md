# Changelog

Formato: un apartado por hito o versión, lo más reciente arriba. Las cifras de
cada build están en [VERIFICATION.md](VERIFICATION.md).

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
