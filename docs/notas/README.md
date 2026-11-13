# Anexo: notas de área

Cada área del plan se hizo en su rama y dejó aquí su nota: qué se cambió, con
qué fuentes (manual del V9990, openMSX, tnCart), qué bancos lo comprueban, qué
encontraron las revisiones y qué queda pendiente. Entraron en `main` con la
fusión de la versión 0.1beta. Las guías generales
([ARCHITECTURE](../ARCHITECTURE.md), [VERIFICATION](../VERIFICATION.md),
[WONDERTANG](../WONDERTANG.md), [changelog](../changelog.md)) resumen lo que
cambia y remiten a estas notas para el detalle.

| Nota | Hitos del estudio | De qué trata |
|---|---|---|
| [integ.md](integ.md) | 3 y 6 | carcasa sin bootloader, flash, SPI ni TF; POR del rPLL, gestor con reintentos, guardia de lock (`DRIVE_EN`, `BOOT_HOLD`), `STATUS_LED`; variantes de reloj `xtal` y `sync`, un `.sdc` y un `build_*.tcl` por variante; banco `tb/integ` |
| [core.md](core.md) | 2 y 7 | los seis parches del tiny9990, P#8-P#15 a `FFh`, cuadro PAL de 313 líneas, cursor EOR, R#16, aserción de ranura perdida; bancos `tb/core` (geometría, paleta, blitter, replay de GNG contra openMSX) |
| [sdram.md](sdram.md) | 4 | refresco propio del UMA en el canal 0 sin tocar la cadencia, AUTO REFRESH en la inicialización, la VRAM conservada en standby, NOP en los pines durante el reset; banco `tb/sdram` a 108 y 107,386 MHz |
| [video.md](video.md) | 7 (vídeo) | `VIDEO_IF.PAL`, salida 720x576 en un cuadro de 855x626, palanca `BLEND`; banco `tb/video` |
| [bus.md](bus.md) | 5 | escaneo adaptativo del multiplexor, pre-WAIT de E/S y de memoria, rearme, timeout del /WAIT, guardia de bus vivo (`BUS_OK`); bancos `tb/bus` a 3,58 / 5,37 / 7,16 / 10,74 MHz |
| [megaram.md](megaram.md) | 8 | configuración `v9990_megaram`: megaROM SCC-I con ventana de 4 MB, PLAIN0, `MEGAROM_CLEAR`, /WAIT de memoria, `tncrom` r3; bancos `tb/megaram` y `tools/tncrom/test` |
| [nextor.md](nextor.md) | — | configuración `v9990_megaram_nextor` (rama `hito/nextor`): Nextor de tnCart con la microSD en la subranura 2, copia de la ROM de la flash (`NEXTOR_LOADER`), pack de Nextor, builds y escenario del banco de placa entera |
| [zynqfix.md](zynqfix.md) | — | versión 0.3beta (rama `hito/zynqfix`): arreglos del V9990 del MSXimus Z portados al tiny9990 (CMMC, CMMM, 16 bpp, P#2 sin TR, YJK/YUV, R#17/R#21, alineación horizontal) y los descartados, con su motivo |
| [fusion.md](fusion.md) | — | la fusión de las seis ramas, los contratos entre áreas, el barrido de opciones de P&R, el banco de placa entera (`tb/top`), la revisión y las builds finales |

Las cifras de las builds de cada nota son las de su rama. Las de la 0.1beta
están en [VERIFICATION.md](../VERIFICATION.md#builds-de-la-01beta).
