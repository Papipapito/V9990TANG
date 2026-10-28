# V9990TANG

> **Español.** V9990TANG es un cartucho V9990 (GFX9000) para MSX sobre la
> **WonderTANG 2.02b** (Tang Nano 20K). Usa el core tiny9990 de buppu3 dentro de
> la carcasa wt200b de tnCartWonder: bus del slot multiplexado, VRAM en la SDRAM
> de la Tang y salida HDMI (DVI) a 720x480 o 720x576.
>
> **English.** V9990TANG is a V9990 (GFX9000) cartridge for MSX on the
> **WonderTANG 2.02b** (Tang Nano 20K). It runs buppu3's tiny9990 core inside the
> tnCartWonder wt200b shell: multiplexed slot bus, VRAM in the Tang's SDRAM and
> HDMI (DVI) output at 720x480 or 720x576.

## Estado

**Versión 0.1beta (28 de octubre de 2026), para probar en placa.** Los cuatro
bitstreams están en [`bitstream/`](bitstream/), con su SHA-256, el cargador de
ROMs `TNCROM.COM` y una guía para quien lo prueba
([`bitstream/LEEME.md`](bitstream/LEEME.md), con la lista de pruebas en placa;
[`bitstream/README.md`](bitstream/README.md) en inglés).

La 0.1beta reúne las seis áreas del plan sobre el hito 1 (ver
[`docs/changelog.md`](docs/changelog.md) y
[`docs/notas/fusion.md`](docs/notas/fusion.md)): carcasa sin bootloader ni
flash, con POR y guardia de lock; core tiny9990 con los parches de fidelidad y
el cuadro PAL; refresco propio de la SDRAM; bus con escaneo adaptativo y
pre-WAIT; salida 720x480 y 720x576; y la MegaRAM SCC-I de 4 MB con `tncrom` r3.
Hay dos configuraciones (`v9990`, solo el V9990, y `v9990_megaram`, con la
MegaRAM) con dos variantes de reloj cada una (`xtal`, del cristal de la Tang, y
`sync`, del reloj del slot). Los cuatro pasan la puerta y los bancos de
simulación, incluido el de placa entera, pero **ninguno se ha cargado todavía
en una placa**. El hito 1 (core sin parches, con el bootloader de tnCart) sí se
probó en placa y, según el usuario, funciona. Qué `.fs` usar y qué esperar, en
[`docs/WONDERTANG.md`](docs/WONDERTANG.md).

## Compilar

Hace falta el IDE de Gowin (probado con la 1.9.12.03). Desde `fpga/`, una de:

```
gw_sh build_v9990_xtal.tcl
gw_sh build_v9990_sync.tcl
gw_sh build_v9990_megaram_xtal.tcl
gw_sh build_v9990_megaram_sync.tcl
```

Cada una saca `fpga/impl/pnr/<configuración>_<variante>.fs`, con su informe de
recursos (`.rpt.txt`) y de timing (`.tr`) al lado. Las opciones de P&R de cada
variante están en su `build_*.tcl` y valen para este RTL: si cambia el RTL hay
que volver a barrerlas (ver [`docs/notas/fusion.md`](docs/notas/fusion.md)).
`gw_sh` no abre ficheros con rutas de más de 260 caracteres: clona el
repositorio en una ruta corta. La puerta que tiene que pasar cada build
(`tools/check_build.py`) y la orden de cada variante están en
[`docs/VERIFICATION.md`](docs/VERIFICATION.md). `TNCROM.COM`, el cargador de
ROMs de la MegaRAM, se rehace con `bash tools/tncrom/build.sh` (SDCC).

## Documentación

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): bloques, relojes, cruces de reloj y `.sdc`.
- [`docs/WONDERTANG.md`](docs/WONDERTANG.md): qué `.fs` usar, la placa, pines, puente J3, carga de ROMs, LED y grabación.
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md): puerta de cada build, números medidos, bancos y matriz de monitores.
- [`docs/notas/`](docs/notas/README.md): anexo con una nota por área (`sdram`, `integ`, `core`, `video`, `bus`, `megaram`) y la de la fusión.
- [`bitstream/LEEME.md`](bitstream/LEEME.md): la guía de la 0.1beta para probarla en placa.
- [`UPSTREAM.md`](UPSTREAM.md): de dónde sale cada fichero, y dónde está el
  estudio del port que fija el plan de hitos.

## Licencia

BSD 3-Clause (ver [`LICENSE`](LICENSE)), con los avisos de Shinobu Hashimoto
(buppu3, tnCart y tiny9990) y Albert Herranz (herraa1, tnCartWonder) intactos en
cada fichero. Las excepciones son el IP DVI_TX de Gowin en
`fpga/src/board/rev1/dvi_tx/`, que es IP cifrado del fabricante, y los informes
generados por las herramientas de Gowin que se guardan como evidencia en
`fpga/reports/`.
