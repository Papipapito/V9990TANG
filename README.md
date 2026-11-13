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

**Versión 0.3beta (13 de noviembre de 2026), para probar en placa.** Los seis
bitstreams están en [`bitstream/`](bitstream/), con su SHA-256, el cargador de
ROMs `TNCROM.COM` y una guía para quien lo prueba
([`bitstream/LEEME.md`](bitstream/LEEME.md), con la lista de pruebas en placa;
[`bitstream/README.md`](bitstream/README.md) en inglés).

### Qué fichero grabar (0.3beta)

Hay tres configuraciones y cada una sale con dos relojes. Se graba **un solo
`.fs`**, en `0x000000`.

| Fichero | Qué lleva dentro | Reloj | Para qué |
|---|---|---|---|
| `v9990tang_wt202b_v9990_xtal_0.3beta.fs` | solo el V9990 | `xtal` | **la primera que hay que probar**: el cartucho de vídeo, sin nada más |
| `v9990tang_wt202b_v9990_sync_0.3beta.fs` | solo el V9990 | `sync` | lo mismo, con el V9990 al ritmo del MSX |
| `v9990tang_wt202b_megaram_xtal_0.3beta.fs` | V9990 + MegaRAM SCC-I de 4 MB | `xtal` | además cargar ROMs con `TNCROM.COM` (desde una unidad de disco que ya tenga el MSX) |
| `v9990tang_wt202b_megaram_sync_0.3beta.fs` | V9990 + MegaRAM SCC-I de 4 MB | `sync` | lo mismo, con el reloj del slot |
| `v9990tang_wt202b_megaram_nextor_xtal_0.3beta.fs` | V9990 + MegaRAM + Nextor en la microSD de la Tang | `xtal` | el cartucho completo: MSX-DOS arranca desde la microSD y `TNCROM.COM` se lanza desde ella. Necesita además `v9990tang_nextor_pack_0.2beta.bin` grabado en `0x100000` |
| `v9990tang_wt202b_megaram_nextor_sync_0.3beta.fs` | V9990 + MegaRAM + Nextor en la microSD de la Tang | `sync` | lo mismo, con el reloj del slot |

| Reloj | De dónde sale | Qué supone |
|---|---|---|
| `xtal` | del cristal de 27 MHz de la Tang (108,000 MHz) | arranca siempre y da HDMI aunque el MSX esté apagado. Es la que hay que probar primero y el respaldo si `sync` falla |
| `sync` | del reloj del slot del MSX, x30 (107,386 MHz) | el V9990 va al ritmo exacto del MSX. **Sin el MSX encendido no hay HDMI**, y si el reloj del slot de esa máquina falta o está fuera de frecuencia el cartucho no arranca |

Cómo grabarlos y qué esperar de cada uno, en
[`bitstream/LEEME.md`](bitstream/LEEME.md).

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

La **0.2beta** añade la tercera configuración, `v9990_megaram_nextor`: V9990 +
MegaRAM + Nextor con la microSD de la Tang, para arrancar MSX-DOS desde la SD y
cargar las ROMs con `TNCROM.COM` desde ella
([`docs/notas/nextor.md`](docs/notas/nextor.md)). Pasa la puerta y los bancos;
sin probar en placa. Hacen falta dos grabaciones: el `.fs` en `0x000000` y la
ROM de Nextor en `0x100000` (`bitstream/v9990tang_nextor_pack_0.2beta.bin`).
Todo lo que hay que grabar y cómo, en [`bitstream/LEEME.md`](bitstream/LEEME.md).

La **0.3beta** (13 de noviembre de 2026) lleva al core los arreglos del V9990
hechos en el MSXimus Z: CMMC, CMMM y orden de bytes a 16 bpp en el motor de
comandos, P#2 escrito sin TR, YJK/YUV, el reinicio de la cuenta de líneas con
R#17/R#21 (Xybots) y la alineación horizontal del bitmap y del cursor
([`docs/notas/zynqfix.md`](docs/notas/zynqfix.md)). Los seis `.fs` son nuevos;
el pack de Nextor no cambia. Pasan la puerta y los bancos; **sin probar en
placa**.

## Compilar

Hace falta el IDE de Gowin (probado con la 1.9.12.03). Desde `fpga/`, una de:

```
gw_sh build_v9990_xtal.tcl
gw_sh build_v9990_sync.tcl
gw_sh build_v9990_megaram_xtal.tcl
gw_sh build_v9990_megaram_sync.tcl
gw_sh build_v9990_megaram_nextor_xtal.tcl
gw_sh build_v9990_megaram_nextor_sync.tcl
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
- [`bitstream/LEEME.md`](bitstream/LEEME.md): la guía de la versión para probarla en placa.
- [`UPSTREAM.md`](UPSTREAM.md): de dónde sale cada fichero, y dónde está el
  estudio del port que fija el plan de hitos.

## Licencia

BSD 3-Clause (ver [`LICENSE`](LICENSE)), con los avisos de Shinobu Hashimoto
(buppu3, tnCart y tiny9990) y Albert Herranz (herraa1, tnCartWonder) intactos en
cada fichero. Las excepciones son el IP DVI_TX de Gowin en
`fpga/src/board/rev1/dvi_tx/`, que es IP cifrado del fabricante, y los informes
generados por las herramientas de Gowin que se guardan como evidencia en
`fpga/reports/`.
