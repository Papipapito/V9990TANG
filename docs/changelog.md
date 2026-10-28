# Changelog

Formato: un apartado por hito o versión, lo más reciente arriba. Las cifras de
cada build están en [VERIFICATION.md](VERIFICATION.md).

## 0.2beta (28 de octubre de 2026, etiqueta local `v0.2beta`, sin publicar)

Añade la configuración `v9990_megaram_nextor`, el cartucho "multi todo": V9990
+ MegaRAM SCC-I + Nextor con la microSD de la Tang
([notas/nextor.md](notas/nextor.md)). **Sin probar en placa**, como el resto.

- **`bitstream/`**: `v9990tang_wt202b_megaram_nextor_{xtal,sync}_0.2beta.fs`
  (CheckSum `0x0BA7` y `0x1D3F`; copias de las builds de
  `fpga/reports/nextor/`), el pack de Nextor para `0x100000`, `SHA256SUMS.txt`
  con todo, y el LEEME y el README ampliados (las dos grabaciones, la microSD,
  los 200 ms, los límites de Nextor y la prueba 11). Los cuatro `.fs` de la
  0.1beta no cambian.
- Revisión corta antes de fusionar (tres lentes con refutador): ningún fallo
  de RTL; se corrige la sección 7 de la nota (el arreglo del banco es una
  lectura de `FFFFh` entre la escritura y el cambio de páginas, no una espera
  en `OP_SLOT`) y se apunta como límite que, tras una pérdida de enganche con
  el MSX en marcha, la copia repetida retiene al Z80 en `/WAIT` ~75 ms sin
  refresco de su DRAM (esa sesión ya está perdida: la megaRAM se borra).

- `fpga/config/v9990_megaram_nextor.sv`, `build_v9990_megaram_nextor_{xtal,sync}.tcl`
  y sus `.sdc` (copias de los de MegaRAM).
- Vuelven, solo en esta configuración, `CARTRIDGE_NEXTOR` (subranura 2, con
  `Plain` a 0 y /WAIT de memoria), `TF_CONTROLLER`, el SPI de la TF, `FLASH_SPI`
  y su SPI; la copia de Nextor la hace `NEXTOR_LOADER` (propio) tras
  `MEGAROM_CLEAR`. `BOOT_HOLD` con tope de 200 ms con Nextor.
- Los pines de la flash y de la TF salen de `MAIN`; las cuatro variantes de la
  0.1beta dan el mismo cuerpo de `.fs` que los de `bitstream/`.
- `bitstream/v9990tang_nextor_pack_0.2beta.bin`: el kernel oficial
  `Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM` sin cambios, para la flash en
  `0x100000` (`tools/nextor/make_pack.py`, licencia en
  `bitstream/NEXTOR_LICENSE.md`: no es MIT).
- Builds: pasan la puerta sin palancas (`xtal` place 2 / route 1, `sync`
  place 0 / route 1). `tb/top`: seis variantes, escenario de Nextor con modelos
  de la flash SPI y de la microSD en modo SPI.

## 0.1beta (28 de octubre de 2026, etiqueta local `v0.1beta`, sin publicar)

Primera versión para probar en placa. Es la fusión de las seis áreas (detalle
en el apartado siguiente) llevada a `main`, con los bitstreams y la guía para
quien la prueba. **Ningún bitstream de la 0.1beta se ha cargado todavía en una
placa.**

- **`bitstream/`**: los cuatro `.fs` (`v9990tang_wt202b_{v9990,megaram}_{xtal,sync}_0.1beta.fs`),
  copias de las builds sobre `055c865`; `TNCROM.COM` r3; `SHA256SUMS.txt`;
  [`LEEME.md`](../bitstream/LEEME.md), con qué fichero elegir, cómo grabarlo
  (SRAM y flash en `0x000000`, y el aviso de la YRW801 del MoonTANG), el puente
  J3, el LED, la carga de ROMs, los límites conocidos y la lista de pruebas en
  placa con su tabla; y un [`README.md`](../bitstream/README.md) corto en
  inglés.
- **Qué entra**, frente al hito 1:
  - carcasa sin bootloader, flash, SPI ni TF; POR del rPLL, gestor con
    reintentos, guardia de lock con `DRIVE_EN` y `BOOT_HOLD` (tope de 50 ms) y
    `STATUS_LED` con los códigos 0-5;
  - variantes de reloj `xtal` (108,000 MHz del cristal) y `sync` (reloj del
    slot x30, 107,386 MHz), con su `.sdc` y su `build_*.tcl`;
  - core tiny9990 con seis parches, P#8-P#15 a `FFh`, cuadro PAL de 313 líneas,
    cursor EOR y R#16;
  - salida 720x480 en 855x524 y, con PAL, 720x576 en 855x626;
  - refresco propio de la SDRAM en el UMA, sin tocar la cadencia, y NOP en sus
    pines durante el reset;
  - bus con escaneo adaptativo, pre-WAIT de E/S y de memoria, rearme, timeout
    del /WAIT y guardia de bus vivo;
  - configuración `v9990_megaram`: MegaRAM SCC-I de 4 MB en la subranura 0,
    PLAIN0, borrado de 32 KB al arrancar, /WAIT en sus lecturas y SCC por el
    DAC I2S;
  - `tncrom` r3 (PLAIN0, máximos por tipo, Konami de 1-2 MB, `-S` con
    comprobación).
- **Builds**: las cuatro pasan la puerta con referencia (desviación +0,00 %);
  cifras, SHA-256 y CheckSum en
  [VERIFICATION.md](VERIFICATION.md#builds-de-la-01beta) y evidencia en
  `fpga/reports/v0.1beta/`.
- **Bancos**: pasan todos sobre el árbol de la 0.1beta (core, sdram, bus,
  integ, video, megaram, tncrom y placa entera).
- **Documentación**: ARCHITECTURE, VERIFICATION, WONDERTANG, UPSTREAM y el
  README al día; las notas de área quedan como anexo
  ([notas/README.md](notas/README.md)).
- **Límites conocidos**: MegaRAM solo a 3,58 MHz; E/S del V9990 a 3,58 y
  5,37 MHz; sin B5/B6, B0/B7 ni kanji; entrelazado en bob; R#16 recortado por
  la ventana fija del upscan; la VRAM se conserva en standby (el chip real no
  la refresca); en `sync` no hay HDMI sin el MSX encendido.

## Fusión de las seis áreas (rama `hito/fusion`, 27 de octubre de 2026, entra en la 0.1beta)

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
- Probado en placa por el usuario después de cerrar el hito: según él,
  funciona. Falta apuntar los monitores y los programas en la matriz de
  [VERIFICATION.md](VERIFICATION.md#matriz-de-monitores).
