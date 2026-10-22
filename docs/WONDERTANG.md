# V9990TANG en la WonderTANG 2.02b

Guía de placa. **En el hito 1 todavía no hay bitstream para usar**: lo que hay es
la carcasa de tnCartWonder con el core de tnCart sin parches, que compila con el
timing cerrado pero no se ha cargado en ninguna placa. Esta página dice qué hace falta y qué esperar cuando
se pruebe.

## Qué hace falta

- Una **WonderTANG 2.02b** con su Tang Nano 20K. La carcasa es la `wt200b` de
  tnCartWonder, escrita para la 2.00b; la 2.02b tiene el mismo pinout (el MoonTANG
  usa el mismo `.cst` en las dos).
- Un monitor o televisor **HDMI**. La salida es DVI sin audio: 720x480 visibles en
  un cuadro de 855x524 a 27 MHz, **60,27 Hz**, fuera de los modos CEA. Los
  monitores con los que se probó tnCartWonder lo aceptan; si uno no lo hace, se
  apunta en la matriz de [VERIFICATION.md](VERIFICATION.md#matriz-de-monitores).
- **J3 no hace falta.** Esta configuración no tiene ninguna fuente de sonido: el
  DAC I2S de la Tang queda sin silenciar (`DAC_SDMODE_n` = reset del sistema) pero
  recibe ceros.

## Qué ve el MSX

| Recurso | Qué hay |
|---|---|
| Puertos de E/S `60h`-`6Fh` | el V9990 (P#0 a P#15), como en un GFX9000 |
| `/WAIT` | lo baja el V9990 en los accesos a P#0 (VRAM) y P#1 (paleta) |
| `/INT` | la interrupción del V9990 (línea, cuadro y fin de comando) |
| Slot | **expandido y vacío**: el slot expandido de tnCart sigue instanciado y responde al registro `FFFFh` aunque ninguna subranura tenga nada. Un GFX9000 no ocupa el slot; quitarlo es parte del hito 3 |
| VRAM | 512 KB en la SDRAM de la Tang, en `78_0000h` |

Sin MegaRAM, sin Nextor y sin sonido. El software V9990 de disco solo usa los
puertos; el de ROM necesita la MegaRAM del hito 8.

## Pines (de `board_wt200b.cst`)

| Señal | Pines de la Tang | Notas |
|---|---|---|
| `CLK_27M` | 4 | cristal de 27 MHz: con la variante `xtal` es el único reloj que hace falta |
| `CART_MUX_SIG[7:0]` | 31, 30, 29, 26, 25, 28, 27, 77 | orden 7 a 0; bus del slot multiplexado: direcciones y control en tres grupos |
| `CART_MUX_CS_n[2:0]` | 19, 17, 20 | orden 2 a 0; selección del grupo del multiplexor |
| `CART_DATA_SIG[7:0]` | 49, 53, 71, 72, 79, 86, 41, 48 | datos (orden 7 a 0) |
| `CART_DATA_DIR` | 52 | sentido del buffer de datos |
| `CART_SLTSL_n`, `CART_RD_n`, `CART_WR_n` | 18, 15, 16 | |
| `CART_CLOCK` | 76 | reloj del slot (3,58 MHz); en `xtal` solo se muestrea |
| `CART_WAIT_n`, `CART_INT_n`, `CART_BUSDIR_n` | 42, 73, 74 | salidas al slot a través de los transistores de la placa |
| TMDS (`tmds_clk`, `tmds_data[2:0]`) | 33/34, 35/36, 37/38, 39/40 | HDMI de la Tang |
| Flash SPI (`mspi_*`) | 59-63 | la usa el bootloader de tnCart (ver abajo) |
| `LED` | 75 | |
| DAC I2S (`DAC_*`) | 51, 54, 55, 56 | sin uso en esta configuración |
| TF (`TF_*`) | 80-85 | sin uso (no hay Nextor) |
| UART | 69, 70 | desactivado; `UART_TX` a 1 |

## Arranque y LED

El bootloader de tnCart corre una vez tras cargar la FPGA (`bootloader.sv`): con
el PLL enganchado y la SDRAM lista, espera a que el MSX suelte `/RESET` y, en
este orden, copia 144 KB de la flash (`10_0000h`, el sitio del Nextor y del BIOS
FM en tnCart) a `70_0000h` de la SDRAM, borra 32 KB de la ventana de la megaROM
y 64 KB del mapper, y hace la fase PAC aunque no haya FM: lee hasta 8 bancos de
8 KB de la flash en `1F_0000h`, comprueba su CRC y deja uno válido (o 8 KB a
cero) en `77_E000h`. En esta configuración nada lee esas copias, y ninguna pisa
la VRAM (`78_0000h`).

Mientras no acaba, el bootloader mantiene **`/WAIT` activo** (su `WAIT_n` entra
en el slot expandido) y `SYS_RESET_n` retiene el V9990 en reset: el MSX espera.
Cada vez que el MSX se resetea, el bootloader vuelve a bajar su `READY` (sin
volver a copiar nada) y, mientras dura el reset, repite en bucle un AUTO REFRESH
seguido de una lectura de la SDRAM para que no pierda el contenido. El LED parpadea
mientras el bootloader trabaja y después se queda quieto: lo único que lo
activa luego son los accesos a la TF del Nextor, que aquí no hay. Estos tiempos
se miden en placa en el hito 1.

## Grabación

Cuando haya bitstream:

- Primero en **SRAM** (se pierde al apagar): con el MSX apagado y la Tang
  alimentada por USB, o reseteando el MSX después.
- En flash, el `.fs` va en `0x000000` ("External Flash mode" del Gowin Programmer).
  Nada más: no hay ROM ni BIOS que grabar.
- **Ojo con la flash compartida.** Si la Tang se usa también con el MoonTANG, su
  ROM YRW801 vive en `0x200000`; algunas herramientas borran más allá del
  bitstream al grabar uno nuevo. Después de grabar el V9990TANG, vuelve a grabar
  la YRW801 antes de volver al MoonTANG.

## Antes de encenderlo

- **Alimentación.** La WonderTANG alimenta la Tang a través de un diodo Schottky;
  en nuestra placa la Tang vio 4,59 V con el slot a 5,0 V. Si la Tang no arranca
  de forma fiable, mira primero los 5 V.
- **`/WAIT` durante la configuración.** La FPGA tarda unos 3 s en cargar su
  configuración desde la flash, y mientras tanto el pull-up de la placa deja
  `/WAIT` activo: el MSX espera con la pantalla en negro. Es lo esperado.
- **Velocidad.** Según el estudio (sección 4, "/WAIT y /INT en el slot"), la
  cadena pin → filtro → escáner de 9 estados → slot expandido →
  `cartridge_v9990` → core → `Bus.WAIT_n` son unos 15 ciclos de 108 MHz (139 ns),
  más 20-50 ns del transistor de la placa. El Z80A deja 274 ns a 3,58 MHz y 134 a
  5,37: cabe a 3,58 MHz y no en turbo. No pruebes el hito 1 en modos turbo; el
  pre-WAIT es el hito 5.
