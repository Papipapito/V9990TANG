# V9990TANG en la WonderTANG 2.02b

Guía de placa para los cuatro bitstreams de la rama `hito/fusion`. **Ninguno se
ha probado todavía en una placa.** Los cuatro compilan con el timing cerrado y
pasan los bancos de simulación (incluido el de placa entera, `fpga/tb/top`).
Esta página dice qué `.fs` elegir, qué hace falta, qué ve el MSX y qué esperar
al encenderlo.

## Qué `.fs` usar

Hay dos configuraciones y, de cada una, dos variantes de reloj:

| `.fs` | Configuración | Reloj | Cuándo usarlo |
|---|---|---|---|
| `v9990_xtal.fs` | `v9990`: solo el V9990 | `xtal`: `CLK_BASE` = 108,000 MHz del cristal de 27 MHz de la Tang | **la primera que hay que probar**; da HDMI también con el MSX apagado |
| `v9990_sync.fs` | `v9990` | `sync`: `CLK_BASE` = reloj del slot x30 = 107,386 MHz | el V9990 al ritmo del MSX; **sin el MSX encendido no hay HDMI** |
| `v9990_megaram_xtal.fs` | `v9990_megaram`: V9990 + MegaRAM SCC-I de 4 MB | `xtal` | para cargar ROMs con `TNCROM.COM` |
| `v9990_megaram_sync.fs` | `v9990_megaram` | `sync` | igual, con el reloj del slot; sin MSX no hay HDMI |

Se generan con `cd fpga && gw_sh build_<configuración>_<variante>.tcl`. Los de
la última build buena quedan en `fpga/impl/fusion/`, que git ignora. La
evidencia de cada build (recursos, timing y la salida de la puerta) está en
`fpga/reports/fusion/<variante>/`, y las sumas md5 del cuerpo de cada `.fs`, en
[notas/fusion.md](notas/fusion.md). Si la variante `sync` da problemas, la
`xtal` de la misma configuración es el respaldo: tiene el mismo RTL y solo
cambia el reloj.

## Qué hace falta

- Una **WonderTANG 2.02b** con su Tang Nano 20K. La carcasa es la `wt200b` de
  tnCartWonder, escrita para la 2.00b; la 2.02b tiene el mismo pinout (el MoonTANG
  usa el mismo `.cst` en las dos).
- Un monitor o televisor **HDMI**. La salida es DVI sin audio y fuera de los
  modos CEA; los modos de cada variante están en [Vídeo](#vídeo). Los monitores
  con los que se probó tnCartWonder aceptan el modo NTSC de `xtal`; si uno no
  acepta alguno de los modos, se apunta en la matriz de
  [VERIFICATION.md](VERIFICATION.md#matriz-de-monitores).
- **Sonido (solo `v9990_megaram`).** El SCC de la megaROM sale por el DAC I2S
  de la Tang, que la placa lleva a la salida de audio y a `SOUNDIN` del slot.
  **Pon el puente J3**: sin él no se oye el SCC. Con `v9990` no hay ninguna
  fuente de sonido y J3 da igual: el DAC recibe ceros.
- Para la MegaRAM, un MSX con **MSX-DOS 2 o Nextor**, que es lo que pide
  `TNCROM.COM`.

## Qué ve el MSX

| Recurso | `v9990` | `v9990_megaram` |
|---|---|---|
| Puertos de E/S `60h`-`6Fh` | el V9990 (P#0 a P#15; P#8-P#15 leen `FFh`), como un GFX9000 | igual |
| Slot | **no expandido y sin memoria**: el cartucho solo contesta en los puertos, como un GFX9000 | **expandido**: registro `FFFFh` con la megaROM en la subranura 0; las otras tres, vacías |
| MegaROM | — | al encender, Konami SCC-I RAM de 2 MB (bancos de 8 KB en `5000h`/`7000h`/`9000h`/`B000h`, con su SCC) con los primeros 32 KB a `FFh`, así que la BIOS no encuentra ninguna ROM. `TNCROM.COM` la cambia a cualquier otro tipo, hasta 4 MB |
| `/WAIT` | lo baja el V9990 en P#0 (VRAM) y P#1 (paleta) | además, en las lecturas de la megaROM |
| `/INT` | la interrupción del V9990 (línea, cuadro y fin de comando) | igual |
| VRAM | 512 KB en la SDRAM de la Tang, en `78_0000h` | igual; la megaROM ocupa `00_0000h-3F_FFFFh` |

No hay Nextor, ni mapper, ni bootloader, ni copia desde la flash: la flash de
la Tang solo guarda el bitstream.

## Cargar ROMs (`v9990_megaram`)

`TNCROM.COM` es el de `tools/tncrom/bin/` (r3, `v0.07 (V9990TANG r3)`), no el de
tnCart. Se rehace con `bash tools/tncrom/build.sh` (SDCC). Lo que añade el r3:

- **Máximo por tipo.** ASCII16 y R-TYPE: 4 MB. ASCII8, KONAMI, KONAMI_SCC_I y
  KONAMI_WO_SCC: 2 MB. 32K: 32 KB. 16K y 16K2: 16 KB. PLAIN0: 48 KB.
  `TNCROM.COM` rechaza con un mensaje, antes de tocar el cartucho, las
  imágenes que no caben (por ejemplo, una de 8 MB).
- **Konami SCC de 1 a 2 MB** (GNG2M, LIFEARTH): `-T KONAMI`. Con
  `-T KONAMI_SCC_I` también cabe, pero tras un /RESET del MSX la megaROM queda
  escribible y la primera escritura a un registro de banco cae en la ROM.
- **Demos V9990 planas** (ROM en `0000h-BFFFh`, sin registros de banco):
  `TNCROM -T PLAIN0 -R DEMO.ROM`. Una imagen de menos de 48 KB se rellena con
  `FFh`. `-R` reinicia por software (CALSLT a `0000h`), porque **un /RESET del
  MSX desactiva PLAIN0** y deja el cartucho invisible hasta el siguiente
  `TNCROM` o hasta que se apague el MSX. Al apagar y encender, la megaROM
  vuelve a la SCC-I de fábrica.
- **`-S <slot>`** comprueba que en ese slot está la megaROM y que no tiene
  PLAIN0 activo; si no, da "cartridge not found".

Los detalles y los tipos están en [notas/megaram.md](notas/megaram.md),
apartados 2, 5 y 6.

## Vídeo

| Modo del V9990 | Visible | Cuadro | `xtal` | `sync` |
|---|---|---|---|---|
| NTSC (262 líneas) | 720x480 | 855x524 | 60,27 Hz | 59,92 Hz |
| PAL (313 líneas, R#7 bit 3) | 720x576 | 855x626 | 50,45 Hz | 50,16 Hz |

El reloj de píxel es de 27,000 MHz en `xtal`. En `sync` sale del reloj del
slot y baja con él (26,85 MHz). El modo cambia cuando el programa cambia el
bit PAL del V9990, y algunos monitores tardan en volver a enganchar. Ninguno de
estos modos es CEA: conviene probarlos todos en cada monitor.

## Arranque y LED

Mientras la FPGA carga su configuración desde la flash (unos 3 s), el pull-up
de la placa deja `/WAIT` activo: el MSX espera con la pantalla en negro. Es lo
esperado. Después:

1. **POR**: el rPLL base queda en reset 1,21 ms. En `sync` no se suelta hasta
   que el reloj del slot está presente y en frecuencia.
2. **Enganche**: hace falta LOCK seguido durante 2,43 ms. Si no engancha en
   19,4 ms, la guardia reintenta.
3. **SDRAM** y, en `v9990_megaram`, el **borrado de 32 KB** de la megaROM a
   `FFh` (unos 2 ms).
4. **Bus vivo** (`BUS_OK`): el reloj del slot visto en una ventana de 2^18
   ciclos (2,43 ms) y el /RESET del MSX suelto.

Mientras tanto la guardia mantiene **`/WAIT` activo** (`BOOT_HOLD`), para que
el MSX no corra con el cartucho a medio arrancar. Tiene un **tope de 50 ms**:
si el cartucho no queda listo, suelta al MSX, que arranca sin él. En el banco
de placa entera, el primer M1 del Z80 acaba a unos 6,1 ms de la configuración
en las cuatro variantes (el borrado de la MegaRAM cabe dentro de la ventana de
`BUS_OK`). En `xtal`, si el MSX se apaga y se vuelve a encender con la Tang
alimentada por USB, el tope se rearma cuando vuelve el reloj del slot.

El LED (`STATUS_LED`, en el dominio del cristal, así que también parpadea sin
PLL) da un código:

| Código | Qué pasa | LED |
|---|---|---|
| 0 | error de reloj: el rPLL base no engancha (en `sync`, también el reloj del slot ausente o fuera de frecuencia) | parpadeo rápido (6,4 Hz) |
| 2 | solo `xtal`: sin reloj del slot (MSX apagado o cartucho mal metido) | destello corto cada 1,24 s |
| 1 | arrancando: rPLL enganchado y sistema aún no listo, o `BUS_OK` a 0 (por ejemplo, con el /RESET del MSX pulsado). Si se queda así, el arranque falló y el MSX corre sin el cartucho | parpadeo lento (1,6 Hz) |
| 3 | listo, pero un `/WAIT` duró más de 37,9 µs y el bus lo soltó (`WAIT_TIMEOUT`, pegajoso) | doble destello cada 1,24 s |
| 4 | listo, después de perder el enganche y recuperarlo (pegajoso) | cuatro destellos cada 1,24 s |
| 5 | listo | fijo |

Con el LED apagado del todo, la FPGA no está configurada. Los códigos 3 y 4
solo se borran al recargar la FPGA o al quitar la alimentación de la Tang.

## Pines (de `board_wt200b.cst`)

| Señal | Pines de la Tang | Notas |
|---|---|---|
| `CLK_27M` | 4 | cristal de 27 MHz: en `xtal` es la fuente de todos los relojes |
| `CART_MUX_SIG[7:0]` | 31, 30, 29, 26, 25, 28, 27, 77 | orden 7 a 0; bus del slot multiplexado: direcciones y control en tres grupos |
| `CART_MUX_CS_n[2:0]` | 19, 17, 20 | orden 2 a 0; selección del grupo del multiplexor |
| `CART_DATA_SIG[7:0]` | 49, 53, 71, 72, 79, 86, 41, 48 | datos (orden 7 a 0) |
| `CART_DATA_DIR` | 52 | sentido del buffer de datos |
| `CART_SLTSL_n`, `CART_RD_n`, `CART_WR_n` | 18, 15, 16 | |
| `CART_CLOCK` | 76 | reloj del slot (3,58 MHz): en `xtal` solo se mide; en `sync` es la entrada del rPLL base |
| `CART_WAIT_n`, `CART_INT_n`, `CART_BUSDIR_n` | 42, 73, 74 | salidas al slot a través de los transistores de la placa |
| TMDS (`tmds_clk`, `tmds_data[2:0]`) | 33/34, 35/36, 37/38, 39/40 | HDMI de la Tang |
| `LED` | 75 | los códigos de arriba |
| DAC I2S (`DAC_*`) | 51, 54, 55, 56 | el SCC en `v9990_megaram`; ceros en `v9990` |
| Flash SPI (`mspi_*`) | 59-63 | sin uso: la flash solo guarda el bitstream |
| TF (`TF_*`) | 80-85 | sin uso (no hay Nextor) |
| UART | 69, 70 | desactivado; `UART_TX` a 1 |

## Grabación

- Primero en **SRAM** (se pierde al apagar): con el MSX apagado y la Tang
  alimentada por USB, o reseteando el MSX después. En `sync` el HDMI no sale
  hasta encender el MSX.
- En flash, el `.fs` va en `0x000000` ("External Flash mode" del Gowin
  Programmer). Nada más: no hay ROM ni BIOS que grabar. Las ROMs de la MegaRAM
  se cargan cada vez desde el MSX con `TNCROM.COM`.
- **Ojo con la flash compartida.** Si la Tang se usa también con el MoonTANG, su
  ROM YRW801 vive en `0x200000`; algunas herramientas borran más allá del
  bitstream al grabar uno nuevo. Después de grabar el V9990TANG, vuelve a grabar
  la YRW801 antes de volver al MoonTANG.

## Antes de encenderlo

- **Alimentación.** La WonderTANG alimenta la Tang a través de un diodo Schottky;
  en nuestra placa la Tang vio 4,59 V con el slot a 5,0 V. Si la Tang no arranca
  de forma fiable, mira primero los 5 V.
- **Velocidad del Z80.**
  - **E/S del V9990 (P#0, P#1): 3,58 y 5,37 MHz.** Desde la fusión, el bus
    lleva el escaneo adaptativo y el pre-WAIT del hito 5
    ([notas/bus.md](notas/bus.md)). En el banco, con cifras estimadas de
    Z80A, el `/WAIT` llega al slot como mucho 120 ns después del `/RD`/`/WR`
    del Z80 (70 ns en el pin). Eso cabe en los 274 ns que deja el Z80 a
    3,58 MHz y en los 134 ns que deja a 5,37 MHz. A 7,16 MHz fallan las
    lecturas de P#0.
  - **MegaRAM (`v9990_megaram_*`): solo 3,58 MHz.** A 5,37 MHz ningún
    pre-WAIT llega a tiempo para las lecturas de la megaROM: el banco de placa
    entera lee mal 16 de 63 lecturas en `xtal` y 29 de 63 en `sync`. Un juego
    cargado con `TNCROM` en un MSX turbo a 5,37 MHz puede colgarse o leer
    basura sin que nada avise. Pon el MSX a 3,58 MHz para usar la MegaRAM.
  - Nada de esto está medido en placa (osciloscopio en `/RD`, `/WAIT` y
    `CART_MUX_CS_n`), ni probado con Z80B/H o R800 reales.
