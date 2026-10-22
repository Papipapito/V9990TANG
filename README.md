# V9990TANG

> **Español.** V9990TANG es un cartucho V9990 (GFX9000) para MSX sobre la
> **WonderTANG 2.02b** (Tang Nano 20K). Usa el core tiny9990 de buppu3 dentro de
> la carcasa wt200b de tnCartWonder: bus del slot multiplexado, VRAM en la SDRAM
> de la Tang y salida HDMI (DVI) a 720x480.
>
> **English.** V9990TANG is a V9990 (GFX9000) cartridge for MSX on the
> **WonderTANG 2.02b** (Tang Nano 20K). It runs buppu3's tiny9990 core inside the
> tnCartWonder wt200b shell: multiplexed slot bus, VRAM in the Tang's SDRAM and
> HDMI (DVI) output at 720x480.

## Estado

**En desarrollo, sin publicar y sin probar en placa.** Este repositorio está en el
hito 1 del plan: la carcasa wt200b de tnCartWonder y el core tiny9990 de tnCart
**sin parches**, con la
configuración solo-V9990, un `.sdc` propio y un script de build que reproduce la
build de referencia medida en el estudio con el timing cerrado. No hay todavía
ningún bitstream para usar: los cambios de fidelidad, el refresco propio de la
SDRAM, el pre-WAIT del bus, la variante con el reloj del slot y la MegaRAM llegan
en los hitos siguientes. Ver [`docs/changelog.md`](docs/changelog.md).

## Compilar

Hace falta el IDE de Gowin (probado con la 1.9.12.03). Desde `fpga/`:

```
gw_sh build_v9990_xtal.tcl
```

El bitstream sale en `fpga/impl/pnr/v9990_xtal.fs`, con su informe de recursos
(`.rpt.txt`) y de timing (`.tr`) al lado. `gw_sh` no abre ficheros con rutas de
más de 260 caracteres: clona el repositorio en una ruta corta. La puerta que
tiene que pasar cada build (`tools/check_build.py`) está en
[`docs/VERIFICATION.md`](docs/VERIFICATION.md).

## Documentación

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): bloques, relojes, cruces de reloj y `.sdc`.
- [`docs/WONDERTANG.md`](docs/WONDERTANG.md): la placa, pines, puente J3 y grabación.
- [`docs/VERIFICATION.md`](docs/VERIFICATION.md): puerta de cada build, números medidos y matriz de monitores.
- [`UPSTREAM.md`](UPSTREAM.md): de dónde sale cada fichero, y dónde está el
  estudio del port que fija el plan de hitos.

## Licencia

BSD 3-Clause (ver [`LICENSE`](LICENSE)), con los avisos de Shinobu Hashimoto
(buppu3, tnCart y tiny9990) y Albert Herranz (herraa1, tnCartWonder) intactos en
cada fichero. Las excepciones son el IP DVI_TX de Gowin en
`fpga/src/board/rev1/dvi_tx/`, que es IP cifrado del fabricante, y los informes
generados por las herramientas de Gowin que se guardan como evidencia en
`fpga/reports/`.
