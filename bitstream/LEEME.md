# V9990TANG 0.2beta para la WonderTANG 2.02b

V9990TANG es un cartucho V9990 (el VDP del GFX9000) para MSX. Corre en la
**WonderTANG 2.02b**, con su Tang Nano 20K. Usa el core tiny9990 de buppu3
(tnCart) con parches de fidelidad, guarda la VRAM en la SDRAM de la Tang y saca
la imagen por el HDMI de la Tang (DVI, sin audio).

**Esta versión es para probar en placa.** Los seis bitstreams compilan con el
timing cerrado y pasan todos los bancos de simulación, incluido el de la placa
entera, pero **ninguno se ha cargado todavía en una placa**. Lo único probado
en placa es el hito 1 (el core sin parches, con el bootloader de tnCart), y
según el usuario funciona. Al final hay una [lista de pruebas](#lista-de-pruebas-en-placa)
con una tabla para apuntar los resultados.

Novedad de la 0.2beta: las dos variantes **`megaram_nextor_*`**, el cartucho
"multi todo": V9990 + MegaRAM SCC-I de 4 MB + **Nextor arrancando desde la
microSD de la Tang**. Las cuatro variantes de la 0.1beta son las mismas (mismo
cuerpo de `.fs`, mismos CheckSum); se repiten aquí para tenerlo todo junto.

## Ficheros

| Fichero | Qué es | Tamaño | SHA-256 (12 primeros) | CheckSum de Gowin |
|---|---|---|---|---|
| `v9990tang_wt202b_v9990_xtal_0.1beta.fs` | V9990 solo, reloj del cristal de la Tang | 7 264 153 | `f668f7abbfc8` | `0x345D` |
| `v9990tang_wt202b_v9990_sync_0.1beta.fs` | V9990 solo, reloj del slot | 7 264 153 | `5f5369227e3e` | `0x7B75` |
| `v9990tang_wt202b_megaram_xtal_0.1beta.fs` | V9990 + MegaRAM SCC-I de 4 MB, reloj del cristal | 7 264 153 | `eca3b40eba33` | `0x95F1` |
| `v9990tang_wt202b_megaram_sync_0.1beta.fs` | V9990 + MegaRAM SCC-I de 4 MB, reloj del slot | 7 264 153 | `3812094d40d5` | `0x4693` |
| `v9990tang_wt202b_megaram_nextor_xtal_0.2beta.fs` | **V9990 + MegaRAM SCC-I de 4 MB + Nextor en la microSD de la Tang**, reloj del cristal | 7 264 153 | `47ed9b813c81` | `0x0BA7` |
| `v9990tang_wt202b_megaram_nextor_sync_0.2beta.fs` | lo mismo, reloj del slot | 7 264 153 | `3c52b74b0bdb` | `0x1D3F` |
| `v9990tang_nextor_pack_0.2beta.bin` | **solo para `megaram_nextor_*`**: el kernel oficial `Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM` sin cambios, para grabar en la flash en **`0x100000`**. Las otras cuatro `.fs` no lo usan. Licencia: `NEXTOR_LICENSE.md` | 131 072 | `b2394dfca88e` | — |
| `TNCROM.COM` | cargador de ROMs para la MegaRAM (r3, `v0.07 (V9990TANG r3)`), para MSX-DOS 2 o Nextor | 13 700 | `5f40a90d4918` | — |
| `NEXTOR_LICENSE.md` | licencia de Nextor (no es MIT: sin uso comercial) | | | |
| `SHA256SUMS.txt` | el SHA-256 completo de todo lo anterior | | | |

El CheckSum es el que Gowin escribe en la cabecera del `.fs` (`//CheckSum:`).
Gowin Programmer lo enseña al cargar el fichero. Para comprobar los ficheros:
`sha256sum -c SHA256SUMS.txt` (Linux o Git Bash) o
`Get-FileHash -Algorithm SHA256 <fichero>` (PowerShell).

## Cuál elegir

| | `xtal` (reloj de la Tang) | `sync` (reloj del slot) |
|---|---|---|
| De dónde sale el reloj | cristal de 27 MHz de la Tang: 108,000 MHz | reloj del slot (3,58 MHz) x30: 107,386 MHz |
| V9990 | **un 0,57 % rápido**: 60,27 Hz en vez de 59,92. Con software que se sincroniza con el VDP del MSX se ve un tirón cada 2,9 s en un scroll continuo | **exacto**: 59,92 Hz, en fase con el VDP del MSX |
| Arranque | **siempre arranca**. Saca HDMI también con el MSX apagado | necesita el MSX encendido para tener HDMI. En máquinas con un reloj de slot raro (turbo que cambia el reloj del cartucho, relojes fuera de 3,58 MHz) puede no enganchar: entonces el LED da el código de error y el MSX arranca sin el cartucho |
| Cuándo | **la primera que hay que probar**, y el respaldo si `sync` falla | cuando `xtal` funciona, para comprobar el reloj exacto en cada máquina |

- **`v9990_*`**: solo el V9990, en los puertos `60h`-`6Fh`, como un GFX9000. El
  slot no está expandido y el cartucho no tiene memoria.
- **`megaram_*`**: lo mismo y además una **MegaRAM SCC-I de 4 MB**. El slot
  está expandido y la megaROM está en la subranura 0. Al encender es una Konami
  SCC-I RAM de 2 MB con los primeros 32 KB a `FFh`, así que la BIOS no ve
  ninguna ROM. Las ROMs se cargan con `TNCROM.COM`.
- **`megaram_nextor_*`**: lo mismo que `megaram_*` y además **Nextor en la
  subranura 2**, con la **microSD de la Tang** como disco (emula el SPI de la
  MegaFlashROM SCC+ SD; el kernel es el oficial de Konamiman). El MSX arranca
  MSX-DOS desde la SD y desde ella se cargan las ROMs con `TNCROM.COM`, sin
  otro cartucho. Al arrancar, el cartucho copia Nextor de la flash de la Tang
  (`0x100000`) a la SDRAM: por eso hay que grabar también el pack. **Sin el
  pack grabado, la subranura 2 queda vacía y lo demás funciona igual que
  `megaram_*`.**

Las seis llevan el mismo V9990: los mismos parches, el cuadro PAL, el cursor
EOR y R#16.

## Qué hace falta

- Una **WonderTANG 2.02b** con su Tang Nano 20K (vale también la 2.00b, que
  tiene el mismo pinout).
- Un monitor o televisor **HDMI**. La salida no es ningún modo CEA (ver
  [Vídeo](#vídeo)), así que hay que probarla en cada monitor.
- Para oír el SCC (solo `megaram_*`): **pon el puente J3**. El SCC sale por el
  DAC I2S de la Tang hacia la salida de audio de la placa y hacia `SOUNDIN`
  del slot. Sin J3 no se oye. Con `v9990_*` no hay ninguna fuente de sonido.
- Para cargar ROMs con `megaram_*`: un MSX con **MSX-DOS 2 o Nextor**, desde
  el disco o la SD del propio MSX (o de otro cartucho), no desde este.
- Para `megaram_nextor_*`: una **microSD** en la ranura de la Tang, con
  **FAT12 o FAT16** (una partición de hasta 4 GB; Nextor 2.1 también lee
  FAT16 en tarjetas mayores si la primera partición es FAT16) y en la raíz los
  `.SYS` de Nextor (`NEXTOR.SYS` y `COMMAND2.COM`, de la misma release 2.1.2),
  más `TNCROM.COM` y las ROMs. La tarjeta se puede preparar en el PC; también
  vale una SD que ya arranque en una MegaFlashROM SCC+ SD o en un Carnivore.
  Un MSX con **64 KB de RAM** (MSX2 o superior, o MSX1 con 64 KB) para
  arrancar MSX-DOS.

## Cómo grabarlo

### 1. Primero en SRAM

Así se prueba sin tocar la flash. Se pierde al quitar la alimentación.

- Con openFPGALoader: `openFPGALoader -b tangnano20k <fichero.fs>`
- Con Gowin Programmer: dispositivo GW2AR-18C, *Access Mode* **SRAM Mode**,
  *Operation* **SRAM Program**, el `.fs` elegido.

Lo más cómodo es cargarlo con el MSX apagado y la Tang alimentada por el USB, y
encender el MSX después. También vale cargarlo con el MSX encendido y pulsar
después el reset del MSX. En `sync` no hay HDMI hasta que el MSX está
encendido.

### 2. Después en la flash externa

Cuando la prueba en SRAM va bien, el `.fs` se graba en la flash SPI externa de
la Tang, en la dirección **`0x000000`**. Con `v9990_*` y `megaram_*` no hay
nada más que grabar: ni ROM, ni BIOS, ni Nextor. Las ROMs de la MegaRAM se
cargan cada vez desde el MSX.

- Con openFPGALoader: `openFPGALoader -b tangnano20k -f <fichero.fs>`
- Con Gowin Programmer: *Access Mode* **External Flash Mode**, *Operation*
  **exFlash Erase,Program thru GAO-Bridge**, *Start Address* `0x000000`.

**Con `megaram_nextor_*` hay que grabar dos cosas**, en este orden o en el
contrario (son zonas distintas de la flash):

| Qué | Dirección | Gowin Programmer |
|---|---|---|
| `v9990tang_wt202b_megaram_nextor_<xtal\|sync>_0.2beta.fs` | `0x000000` | **exFlash Erase,Program thru GAO-Bridge**, *Start Address* `0x000000` |
| `v9990tang_nextor_pack_0.2beta.bin` | **`0x100000`** | **exFlash C Bin Erase,Program thru GAO-Bridge**, *Start Address* `0x100000` (en *User Code / File name* el `.bin`) |

Por línea de órdenes: `openFPGALoader -b tangnano20k -f <fichero.fs>` para el
bitstream y, para el pack, `openFPGALoader -b tangnano20k -f -o 0x100000
v9990tang_nextor_pack_0.2beta.bin` (o `programmer_cli -d GW2AR-18C -r 38
--spiaddr 0x100000 -f v9990tang_nextor_pack_0.2beta.bin` de Gowin).

El pack ocupa `0x100000`-`0x11FFFF`; grabar el `.fs` en `0x000000` no lo toca
y grabar el pack no toca el `.fs`. Para probar en SRAM antes de grabar nada,
el pack tiene que estar ya en la flash: el bitstream lo lee de ahí también
cuando se carga por SRAM. Si la flash está vacía en `0x100000`, el cartucho
arranca como `megaram_*` (sin Nextor).

**Cuidado con la flash compartida con el MoonTANG.** El MoonTANG guarda su ROM
de muestras YRW801 en la misma flash, en `0x200000`. Grabar el `.fs` en
`0x000000` no la toca, pero **borrar la flash entera sí la borra** (por ejemplo,
una operación de borrado completo del chip en Gowin Programmer). Si la borras,
vuelve a grabar la YRW801 en `0x200000` antes de volver a usar el MoonTANG.

## Al encenderlo

Mientras la FPGA se configura desde la flash (unos 3 s), la placa deja `/WAIT`
activo y el MSX espera con la pantalla en negro. Es normal. Después el
cartucho arranca el PLL, la SDRAM y, en `megaram_*`, borra los primeros 32 KB
de la megaROM. Mientras tanto sigue reteniendo el MSX con `/WAIT`, con un
**tope de 50 ms**: si en ese tiempo no queda listo, suelta el MSX, que arranca
sin el cartucho. En el banco de simulación el MSX echa a andar unos 6 ms
después de que la FPGA queda configurada.

En `megaram_nextor_*`, tras el borrado copia además los 128 KB de Nextor de la
flash a la SDRAM (**~70 ms**) y el tope sube a **200 ms**. Si la copia no
acaba a tiempo, el MSX arranca igual, sin Nextor. Con el pack grabado y una
SD arrancable, la BIOS encuentra Nextor en la subranura 2 y sale MSX-DOS.

### El LED

El LED de la Tang da un código:

| Código | Qué pasa | LED |
|---|---|---|
| 0 | error de reloj: el PLL no engancha. En `sync`, también cuando el reloj del slot falta o está fuera de frecuencia. El MSX arranca sin el cartucho | parpadeo rápido (6,4 Hz) |
| 1 | arrancando, o con el `/RESET` del MSX pulsado. Si se queda así, el arranque falló y el MSX corre sin el cartucho | parpadeo lento (1,6 Hz) |
| 2 | solo `xtal`: no hay reloj del slot (MSX apagado o cartucho mal metido) | destello corto cada 1,24 s |
| 3 | funciona, pero un `/WAIT` duró más de 37,9 µs y el cartucho lo soltó (`WAIT_TIMEOUT`). Se queda hasta recargar la FPGA | doble destello cada 1,24 s |
| 4 | funciona, después de perder el enganche del PLL y recuperarlo. Se queda hasta recargar la FPGA | cuatro destellos cada 1,24 s |
| 5 | listo | fijo |

Con el LED apagado del todo, la FPGA no está configurada.

## Vídeo

| Modo del V9990 | Visible | Cuadro | `xtal` | `sync` |
|---|---|---|---|---|
| NTSC (262 líneas) | 720x480 | 855x524 | 60,27 Hz | 59,92 Hz |
| PAL (313 líneas, bit 3 de R#7) | 720x576 | 855x626 | 50,45 Hz | 50,16 Hz |

El modo lo elige el programa con el bit PAL del V9990. Al cambiar, algunos
monitores tardan en volver a enganchar. El reloj de píxel es de 27,000 MHz en
`xtal` y de 26,85 MHz en `sync`. No hay audio por HDMI.

## Cargar ROMs con `TNCROM.COM` (`megaram_*`)

Copia `TNCROM.COM` al disco o a la SD del MSX y, desde MSX-DOS 2 o Nextor:

```
TNCROM -H                          lista de opciones y de tipos, con el máximo de cada uno
TNCROM -T ASCII16 -R JUEGO.ROM     megaROM ASCII 16 KB (hasta 4 MB) y reinicia el MSX
TNCROM -T ASCII8 -R JUEGO.ROM      megaROM ASCII 8 KB (hasta 2 MB)
TNCROM -T KONAMI_SCC_I -R JUEGO.ROM   Konami con SCC (hasta 2 MB)
TNCROM -T KONAMI -R GNG2M.ROM      Konami SCC de 1 a 2 MB (GNG2M, LIFEARTH)
TNCROM -T 32K -R JUEGO.ROM         ROM plana de 32 KB
TNCROM -T PLAIN0 -R DEMO.ROM       demo V9990 plana en 0000h-BFFFh (hasta 48 KB)
```

- `-R` reinicia el MSX al acabar y arranca la ROM. `-S <slot>` fija el slot y
  comprueba que la megaROM está ahí. Sin `-S`, `TNCROM` la busca.
- **Máximos**: ASCII16 y R-TYPE, 4 MB; ASCII8, KONAMI, KONAMI_SCC_I y
  KONAMI_WO_SCC, 2 MB; 32K, 32 KB; 16K y 16K2, 16 KB; PLAIN0, 48 KB.
  `TNCROM` rechaza con un mensaje lo que no cabe (por ejemplo, una ROM de
  8 MB) antes de tocar el cartucho.
- **Konami de 1 a 2 MB**: usa `-T KONAMI`. Con `-T KONAMI_SCC_I` también
  carga, pero tras un `/RESET` del MSX la megaROM queda escribible y la
  primera escritura a un registro de banco cae en la ROM.
- **PLAIN0** es para las demos V9990 que son una ROM plana en `0000h`
  (WOLF3D, WIREFRM, FLYLOGO...). Una imagen de menos de 48 KB se rellena con
  `FFh`. **Arráncalas con `-R`**: un `/RESET` del MSX desactiva PLAIN0 y deja
  el cartucho invisible hasta el siguiente `TNCROM` o hasta apagar el MSX.
- Al apagar y encender el MSX, la megaROM vuelve a ser una SCC-I RAM de 2 MB
  vacía.

Usa este `TNCROM.COM`, no el de tnCart: el de tnCart no conoce PLAIN0 ni los
máximos de la ventana de 4 MB.

## Límites conocidos

- **Velocidad del Z80.**
  - La E/S del V9990 (puertos `60h`-`6Fh`) está pensada para **3,58 y
    5,37 MHz**. A 7,16 MHz y más fallan las lecturas de P#0 (VRAM).
  - **La MegaRAM solo funciona a 3,58 MHz.** A 5,37 MHz el banco de
    simulación lee mal 16 de 63 lecturas de la megaROM en `xtal` y 29 de 63 en
    `sync`: un juego puede colgarse o leer basura sin ningún aviso. Pon el MSX
    a 3,58 MHz para usar la MegaRAM.
  - Las cifras son de simulación con tiempos de Z80A. Nada está medido en
    placa, ni probado con Z80B/H o con el R800.
- **Modos B5 y B6** (640x400 y 640x480) no están soportados. B6 ni siquiera
  genera el sincronismo vertical. Tampoco B0 ni B7.
- **No hay ROM de kanji**: P#8 a P#15 leen `FFh`, como en un GFX9000 sin
  kanji.
- **Entrelazado en modo bob**: cada campo se dobla a pantalla completa. En
  imágenes fijas entrelazadas (por ejemplo DREAMPUZ) se ve un parpadeo como el
  de un CRT. Cada campo tiene 262 o 313 líneas, no 262,5 o 312,5.
- **R#16** (ajuste de la posición de la imagen) mueve la imagen dentro de una
  ventana fija de la salida, así que con un ajuste vertical distinto de 0 se
  recorta el borde (B1/B3) o la propia imagen (B2/B4, que no tienen borde).
- **Refresco en standby**: el cartucho conserva la VRAM en todos los modos,
  también en standby. El chip real no la refresca en standby y la pierde. Un
  programa que dependa de perderla verá otra cosa.
- **B4 con 4 bpp de paleta** sale 4 puntos tarde: los 4 primeros puntos de
  cada línea muestran el fondo.
- En `sync`, **sin el MSX encendido no hay HDMI**.
- La salida de vídeo no es CEA: algún monitor puede rechazarla, sobre todo los
  modos PAL y los 59,92 Hz de `sync`.
- **Nextor** (`megaram_nextor_*`):
  - La SD va en **modo SPI a 18 MHz**; no hay detección de tarjeta ni de
    protección de escritura (Nextor las ve siempre "presente" y escribible). Un
    cambio de tarjeta en caliente lo tiene que notar el propio Nextor.
  - Solo la **microSD de la Tang**; la ranura SD de la WonderTANG, si la tiene
    la placa, no se usa.
  - La ROM de Nextor es de **solo lectura** (no hay escritura en la flash
    desde el MSX ni `NEXTOR.SYS`/kernel actualizables en caliente: para
    cambiar de kernel se vuelve a grabar el pack).
  - Igual que la MegaRAM, está **pensado para 3,58 MHz**. La lectura del SPI
    en el banco 40h devuelve el byte anterior y lanza otra transferencia: a
    más velocidad puede perder bytes.
  - La subranura 2 lleva solo la página 1 (`4000h`-`7FFFh`); la 0 es la
    MegaRAM y la 1 y la 3 están vacías.
  - Nada de esto se ha probado en placa: ni la copia desde la flash, ni la SD,
    ni que la BIOS arranque Nextor con la MegaRAM al lado.

## Lista de pruebas en placa

Hazlas en este orden. Empieza por `v9990_xtal` en SRAM y sigue con las demás.
Apunta cada resultado en la tabla del final.

1. **Arranque.** Carga el `.fs` en SRAM con el MSX apagado y la Tang por USB.
   En `xtal`, el LED debe dar el código 2 (sin reloj del slot). Enciende el
   MSX: el LED pasa a 5 (fijo) y el MSX arranca normal hasta BASIC. En
   `megaram_*`, la BIOS no debe encontrar ninguna ROM en el cartucho.
2. **Arranque desde la flash.** Graba el `.fs` en la flash, apaga todo y
   enciende solo el MSX (la Tang alimentada desde el slot). Debe arrancar igual,
   tras los 3 s de pantalla negra. Repite 10 veces en frío y 10 con el reset.
3. **HDMI en dos monitores.** Con el MSX en BASIC, el HDMI saca el color de
   fondo del V9990. Prueba al menos dos monitores o televisores distintos.
4. **Programa de disco.** Un programa V9990 de disco (que solo use los
   puertos), por ejemplo un visor de imágenes B1/B3 o una demo de disco, pinta
   por HDMI. Apunta el programa y el modo.
5. **ROMs** (`megaram_*`, MSX a 3,58 MHz), cargadas con `TNCROM`: SAMURAI,
   DEMO9990, MRBALLON, NEONV99, una ROM de MSXgl, GNG2M y LIFEARTH
   (`-T KONAMI`), DREAMPUZ, INAROW, las demos planas WOLF3D, WIREFRM y
   FLYLOGO (`-T PLAIN0 -R`) y, en un turbo R, ANOTHERW (`-T ASCII16`). El
   SCC se oye con J3 puesto. Una ROM de 8 MB (SOCCER12) tiene que salir
   rechazada con mensaje. SofaRun debería ver la SCC-I RAM (sin confirmar).
6. **PAL.** Un programa que ponga el bit PAL de R#7 (bit 3): la salida pasa a
   720x576 y el monitor la acepta. Apunta si tarda en enganchar.
7. **Turbo.** En un MSX turbo a 5,37 MHz, el programa de disco del punto 4
   funciona con `v9990_*`. Con `megaram_*`, no se espera que funcione a
   5,37 MHz (ver Límites): apunta lo que pasa. Si tienes osciloscopio, mide
   `/RD`, `/WAIT` y `CART_MUX_CS_n`: `/WAIT` debería bajar como mucho
   125 ns después de `/RD`.
8. **Reset.** Pulsa el reset del MSX con imagen en pantalla y también mientras
   un programa escribe en la VRAM: el MSX vuelve a arrancar, no se queda
   colgado y el V9990 vuelve a contestar. Con el reset pulsado, el LED da el
   código 1.
9. **LED y reloj del slot.** En `xtal` con la Tang por USB: apaga el MSX (LED
   en 2), espera más de un segundo y vuelve a encenderlo. Debe arrancar con el
   cartucho. En `sync`, prueba en todas las máquinas que puedas (MSX1, MSX2,
   MSX2+, turbo R, un MSX en FPGA): apunta en cuáles engancha, y comprueba que
   en las que no engancha el LED da el código 0 y el MSX arranca sin cartucho.
10. **VRAM.** Llena la VRAM con un patrón y compruébala tras 1 hora con la
    pantalla apagada y tras 1 hora en standby. En `megaram_*`, comprueba
    también que la VRAM sigue intacta tras 10 minutos de `LDIR` sobre la
    megaROM.
11. **Nextor** (`megaram_nextor_*`, MSX a 3,58 MHz, pack grabado en
    `0x100000`, microSD con los `.SYS` y `TNCROM.COM`). Primero **sin SD**: el
    MSX tiene que arrancar a BASIC igual (Nextor sin tarjeta no cuelga la
    máquina). Después con SD: sale MSX-DOS (o el `COMMAND2` de Nextor),
    `DIR` lista la tarjeta, copia un fichero de 1 MB a la misma SD y
    compáralo (`FC` o un `COPY` y vuelta). Después `TNCROM -T KONAMI -R
    GNG2M.ROM` desde la propia SD: el juego arranca con la MegaRAM en la
    subranura 0 y Nextor en la 2. Pulsa el reset del MSX: vuelve a arrancar
    MSX-DOS desde la SD. Prueba por último sin el pack grabado (borra solo
    `0x100000`, o prueba la `.fs` en una Tang con la flash vacía): la BIOS no
    debe ver nada en la subranura 2 y la MegaRAM debe funcionar.

### Resultados

| Nº | Prueba | Bitstream | MSX (modelo, velocidad) | Monitor | Resultado (bien / mal / no probado) | LED | Notas | Quién y cuándo |
|---|---|---|---|---|---|---|---|---|
| 1 | Arranque en SRAM | | | | | | | |
| 2 | Arranque desde flash (10 frío + 10 reset) | | | | | | | |
| 3 | HDMI, monitor 1 | | | | | | | |
| 3 | HDMI, monitor 2 | | | | | | | |
| 4 | Programa de disco | | | | | | | |
| 5 | ROMs (una fila por ROM) | | | | | | | |
| 6 | PAL | | | | | | | |
| 7 | Turbo 5,37 MHz | | | | | | | |
| 8 | Reset | | | | | | | |
| 9 | LED y reloj del slot | | | | | | | |
| 10 | VRAM (1 h pantalla apagada, 1 h standby, LDIR) | | | | | | | |
| 11 | Nextor sin SD | | | | | | | |
| 11 | Nextor: arranque, DIR, copia de 1 MB | | | | | | | |
| 11 | Nextor: TNCROM desde la SD y reset | | | | | | | |
| 11 | Nextor sin pack grabado | | | | | | | |
| | | | | | | | | |
| | | | | | | | | |

## Más información

- [`../docs/WONDERTANG.md`](../docs/WONDERTANG.md): la guía de placa completa,
  con los pines.
- [`../docs/VERIFICATION.md`](../docs/VERIFICATION.md): la puerta de cada
  build, los bancos de simulación y la matriz de monitores.
- [`../docs/notas/nextor.md`](../docs/notas/nextor.md): cómo está hecho
  Nextor (arranque, mapa de la SDRAM y de la flash, pack, builds).
- [`../docs/changelog.md`](../docs/changelog.md): lo que entra en la 0.1beta y
  en la 0.2beta.
- Evidencia de cada build (recursos, timing, salida de la puerta):
  `../fpga/reports/v0.1beta/<variante>/` y `../fpga/reports/nextor/<variante>/`.

Licencia BSD 3-Clause (ver [`../LICENSE`](../LICENSE)). El IP DVI_TX de Gowin
que va dentro del bitstream es del fabricante.
