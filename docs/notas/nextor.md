# Configuración `v9990_megaram_nextor`: V9990 + MegaRAM + Nextor en la microSD

Rama `hito/nextor`, desde `main` (`a242efd`, 0.1beta). El cartucho "multi
todo": el V9990 (puertos 60h-6Fh), la MegaRAM SCC-I de 4 MB (subranura 0) y
Nextor con la microSD de la Tang (subranura 2), para arrancar MSX-DOS desde la
SD y cargar desde ella las ROMs con `TNCROM.COM`. **Nada de esto se ha probado
en placa.** Las cuatro variantes de la 0.1beta no cambian: sus builds rehechas
sobre este árbol dan **el mismo cuerpo de `.fs`** que los de `bitstream/`
(sección 6).

## 1. Qué se añade y dónde

| Pieza | Fichero | Notas |
|---|---|---|
| Configuración | `fpga/config/v9990_megaram_nextor.sv` | la de `v9990_megaram.sv` con `ENABLE_NEXTOR = ENABLE` |
| Cartucho Nextor | `fpga/src/cartridge_nextor.sv` (tnCartWonder `d3a54f1`) | `MEGAROM_CONTROLLER` de 2 bancos de 8 KB (registros en 6000h y 6800h, máscara F800h, ROM protegida, solo la página 1) y el `TF_CONTROLLER` con el banco 40h. Cambios: `Megarom.Plain = 0` (contrato de la megaROM de V9990TANG) y `ENABLE_MEM_WAIT` = `CONFIG::ENABLE_MEM_WAIT` (abajo) |
| SPI de la SD | `fpga/src/peripheral/msx/tf_controller.sv` (sin cambios) y `SPI` de `spi.sv` con `CONFIG_BOARD::TF_CLK_DIV = 2` (18 MHz) | la interfaz de la MegaFlashROM SCC+ SD: banco 40h en 4000h-57FFh (A12 = /CS), selección de unidad en 5800h-5FFFh; una lectura devuelve el byte de la transferencia anterior y lanza otra con FFh |
| Copia de Nextor | `fpga/src/system/nextor_loader.sv` (propio) con `FLASH_SPI` de `flash.sv` (sin cambios, siempre en lectura) y su `SPI` (`FLASH_CLK_DIV = 2`) | 128 KB de la flash (`10_0000h`) a la SDRAM (`70_0000h`), sección 2 |
| Integración | `fpga/src/main.sv` | rama de generate `if(CONFIG::ENABLE_NEXTOR)` **dentro** de la de la megaROM (los nombres `genblk` de las otras configuraciones no se mueven: el banco `tb/top` los usa); `EXPANSION_RAM` pasa de 2 a 4 clientes solo en esta configuración; los pines de la flash y de la TF salen de `MAIN` (`TF_*`, `FLASH_*`) y, en las demás configuraciones, `MAIN` los deja en el reposo que antes ponía el top |
| Top | `fpga/src/tnCart_board_wt200b_top.sv` | conecta esos pines (`mspi_*`, `TF_*`) a `MAIN`; `HOLD_CYCLES` de la guardia = 200 ms con Nextor (50 ms en las demás) |
| Builds | `fpga/build_common.tcl` (`CFG = v9990_megaram_nextor`, `$NEXTOR`), `fpga/build_v9990_megaram_nextor_{xtal,sync}.tcl`, `fpga/constraints/v9990_megaram_nextor_{xtal,sync}.sdc` | los `.sdc` son copias de los de MegaRAM (mismas 16 órdenes): Nextor no añade relojes (sigue 8/8 PRIMARY) |
| Pack | `bitstream/v9990tang_nextor_pack_0.2beta.bin`, `tools/nextor/make_pack.py` | sección 4 |

## 2. Arranque: MEGAROM_CLEAR, la copia y BOOT_HOLD

Secuencia: `RESET_n` (rPLL enganchado y SDRAM lista) → `MEGAROM_CLEAR` (32 KB
a FFh, ~1,5 ms) → `NEXTOR_LOADER` (128 KB, ~68 ms) → `SYS_RESET_n`.

- **Un solo borrado de la megaROM**: el de `MEGAROM_CLEAR` (el de la 0.1beta,
  con su banco). El `BOOTLOADER` de tnCart no vuelve. De él solo hacía falta la
  copia de la BIOS; además borraba la megaROM (duplicado), 64 KB del mapper
  (no existe), leía la PAC (no existe) y bajaba `READY` en cada /RESET del MSX
  (V9990TANG dejó de hacerlo en el hito 3). `NEXTOR_LOADER` hace solo la copia
  con el mismo `FLASH_SPI` y ocupa una fracción del `BOOTLOADER` (508 LUT en
  la referencia del estudio): toda la configuración sube +153 CLS frente a
  `v9990_megaram_xtal` (sección 5).
- **El canal 0 del UMA por turnos**: `EXPANSION_RAM` hace OR de los clientes
  sin arbitrar, así que la copia empieza con el `DONE` del borrado (`START`).
  Después, la megaROM y Nextor comparten el canal sin solaparse porque están
  en subranuras distintas (el Z80 solo selecciona una por ciclo). Las dos
  reenvían `/RFSH` al UMA, igual que antes la megaROM sola.
- **Escrituras de 32 bits**: el cargador junta 4 bytes y escribe una palabra
  (`DIN_SIZE_32`, como `MEGAROM_CLEAR`), solapada con la lectura SPI de la
  siguiente: la copia la marca el SPI, ~58 ciclos de `CLK_BASE` por byte (18
  MHz de SCLK): **68,6 ms** en el banco (de 3,64 a 72,24 ms).
- **`SYS_RESET_n` = `RESET_n` && borrado && copia** (`boot_done`). La guardia
  del top recibe `SYS_READY` como siempre: `BOOT_HOLD` retiene al MSX durante
  el borrado y la copia y `DRIVE_EN` no se suelta hasta el final. **Fail-open
  conservado**: el tope de `BOOT_HOLD` sube a 200 ms en esta configuración
  (5 400 000 ciclos de 27 MHz; el arranque completo dura ~72 ms en el banco).
  Si la copia no acabara, el MSX arranca a los 200 ms con el cartucho mudo,
  como con cualquier otro fallo de arranque. tnCart retenía al MSX ~1 s.
- La copia empieza nada más soltarse el reset de la carcasa, **sin esperar al
  /RESET del MSX** (el bootloader de tnCart esperaba a que el MSX lo soltara).
  Tras una pérdida de enganche se repiten el borrado y la copia.
- Con la flash sin grabar en `10_0000h` la copia trae FFh: la BIOS no ve "AB"
  en la subranura 2 y no hay Nextor; lo demás funciona.

## 3. Mapa de la SDRAM y de la flash

| SDRAM | Contenido |
|---|---|
| `00_0000h`-`3F_FFFFh` | megaROM (4 MB) |
| `40_0000h`-`6F_FFFFh` | sin uso (mapper de tnCart) |
| `70_0000h`-`71_FFFFh` | **Nextor** (128 KB, copia de la flash) |
| `72_0000h`-`77_FFFFh` | sin uso (FM-BIOS y PAC de tnCart: no se copian) |
| `78_0000h`-`7F_FFFFh` | VRAM (512 KB, canal 1 del UMA) |

Nextor puede escribir en sus registros de banco números de 8 bits: el banco
40h (el del SPI de la SD) apunta a `78_0000h` y los demás por encima de 0Fh
leen fuera de su ROM. Son solo lecturas (la ROM está protegida contra
escritura; `wr_mem_n` incluye `WriteProtect`), como en tnCart; con el banco 40h
el dato que sale es el del `TF_CONTROLLER`.

| Flash (8 MB) | Contenido |
|---|---|
| `00_0000h` | bitstream (`.fs`) |
| `10_0000h`-`11_FFFFh` | **pack de Nextor** |
| `20_0000h` | ROM de muestras YRW801 del MoonTANG, si se usa la misma Tang (no se toca) |

## 4. Pack de Nextor

`bitstream/v9990tang_nextor_pack_0.2beta.bin` es el kernel oficial
`Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM` (Konamiman, release v2.1.2: kernel
2.1.2, driver "MegaFlashROM SCC+ SD" v1.3), **sin cambios**: 131 072 bytes,
SHA-256 `b2394dfc...e74ee`. Es el que pide tnCart (`roms/nextor/README.md`): el
`TF_CONTROLLER` emula el SPI de la MegaFlashROM SCC+ SD y el driver va en el
kernel. Se construye con

```
python tools/nextor/make_pack.py <Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM>
```

que comprueba tamaño, cabecera "AB", las cadenas del kernel y del driver y el
SHA-256 (con `--otra-rom` admite otra ROM de la MegaFlashROM SCC+ SD de 128
KB). Se graba en la flash en `0x100000` ("exFlash C Bin Erase, Program thru
GAO-Bridge" en Gowin Programmer, o `programmer_cli -d GW2AR-18C -r 38
--spiaddr 0x100000 -f v9990tang_nextor_pack_0.2beta.bin`), como en
`doc/flash.md` de tnCart, sin el FM-BIOS. **Licencia**: la de Nextor, que no es
MIT (texto en `bitstream/NEXTOR_LICENSE.md`; resumen y procedencia en
`UPSTREAM.md`): distribución libre con el aviso, sin uso comercial del
software. El SHA-256 no se ha comparado con el de la release de GitHub.

En la SD: MSX-DOS (los `.SYS` de Nextor, o el arranque que traiga la tarjeta
formateada con Nextor) y `TNCROM.COM` con las ROMs.

## 5. Builds y puerta

Gowin 1.9.12.03, RTL de `3bec232` (los commits siguientes no tocan RTL).
Primera build de la configuración: puerta con `--sin-ref` y `--compara` frente
a `v9990_megaram_xtal` de la 0.1beta (15 168 / 9 019 / 29). **No ha hecho falta
ninguna palanca** (`ENABLE_R16`, `ENABLE_CURSOR_EOR` y `BLEND` siguen a 1): los
CLS quedan por debajo del aviso de 9 250 y la Fmax pasa con el juego de
opciones barrido.

Barrido (Fmax de `CLK_BASE` en MHz, peor setup en ns, CLS):

| Opciones (síntesis / place / route) | `xtal` | `sync` |
|---|---|---|
| auto / 0 / 2 | 110,106 · +0,177 · 9 172: PASA | 107,686 · +0,026 · 9 204: FALLA |
| auto / 2 / 2 | 110,106 · +0,177 · 9 128: PASA (otro `.fs`) | 107,932 · +0,047 · 9 135: FALLA |
| auto / 2 / 1 | **113,445 · +0,444 · 9 128: PASA** | 107,436 · +0,004 · 9 135: FALLA |
| auto / 0 / 1 | 110,072 · +0,174 · 9 172: PASA | **112,389 · +0,414 · 9 204: PASA** |
| auto / 2 / 0 | — | 107,557 · +0,015 · 9 135: FALLA |
| auto / 0 / 0 | 108,189 · +0,016 · 9 172: FALLA | — |
| `-map_option 2` / 0 / 2 | 111,894 · +0,322 · 9 203: PASA | 107,438 · +0,004 · 9 184: FALLA |
| `-map_option 2` / 2 / 2 | — | 109,737 · +0,199 · 9 075: PASA |
| `-map_option 2` / 2 / 0 | 108,267 · +0,023 · 9 118: FALLA | — |
| `-map_option 2` / 0 / 0 | 108,162 · +0,014 · 9 203: FALLA | — |

Elegidas: place 2 / route 1 (las del hito 1) en `xtal` y place 0 / route 1 en `sync`. Builds
archivadas en `fpga/reports/nextor/<variante>/` (`check_build.txt` es la salida
de la puerta). Cifras: ver la tabla de [VERIFICATION.md](../VERIFICATION.md#builds-de-v9990_megaram_nextor).

Avisos de síntesis y P&R: los de `v9990_megaram` menos el `CV0016` de
`TF_DAT0` y de `mspi_miso` (ahora tienen carga): queda el de `UART_RX`;
`NL0002` x5 (sonido interno y `MEGAROM_XFER_TIE`); `PR1014` el de `CLK_27M_d`
(y en `sync` el de `CART_CLOCK_d`); en `sync`, los `CK3000` de siempre.

**Margen**: 113,45 MHz en `xtal` (+5,0 % sobre 108) y 112,39 en `sync` (+4,7
% sobre 107,386), pero con la mayoria de los juegos de opciones la Fmax cae por
debajo de 109: depende de la colocacion. Si un
cambio de RTL la tumba, volver a barrer y, si no basta, las palancas en este
orden: `V9990_ENABLE_R16 = 0`, `V9990_ENABLE_CURSOR_EOR = 0`, `UPSCAN_BLEND =
0` (solo en `config/v9990_megaram_nextor.sv`).

## 6. Las cuatro variantes de la 0.1beta no cambian

Los ficheros comunes que se tocan (`main.sv`, el top, `build_common.tcl`) solo
cambian la estructura: los pines en reposo los pone `MAIN` en lugar del top y
el tope de `BOOT_HOLD` se pasa explícito con el mismo valor. Las cuatro builds
rehechas sobre este árbol (`3bec232`, con sus opciones de siempre) dan **el
mismo cuerpo de `.fs`** que los de `bitstream/` (md5 sin las líneas `//`:
`6be82d94`, `c0214336`, `be61fef2`, `04406f1f`; CheckSum `0x345D`, `0x7B75`,
`0x95F1`, `0x4693`) y pasan la puerta con las referencias de la 0.1beta
(`fpga/reports/nextor/regresion_0.1beta.txt`).

## 7. Banco de placa entera (`fpga/tb/top`)

`run.sh` compila ahora seis variantes (`v9990_megaram_nextor_{xtal,sync}`
además de las cuatro). Modelos nuevos alrededor del top:

- **Flash SPI** de la Tang: orden 03h con dirección de 24 bits (modo 0) y una
  ROM de Nextor de prueba de 128 KB en `10_0000h` ("AB" al principio y un
  patrón que depende del banco); FFh en el resto.
- **microSD en modo SPI**: órdenes de 6 bytes, R1 tras un byte de Ncr; CMD0,
  CMD8 (R7 con el patrón), CMD55 + ACMD41 (sale de idle al segundo), CMD17
  (FFh, testigo FEh, 512 bytes con patrón y 2 de CRC).

Escenario de Nextor (fase N, en `full`; en `io` solo lo de la subranura y "AB",
contado):

- en el arranque, por la puerta de atrás: una sola selección de la flash, orden
  03h en `10_0000h`, 131 072 bytes leídos, los 128 KB de la SDRAM en `70_0000h`
  idénticos a la imagen y nada tocado fuera; la flash suelta al acabar;
- `FFFFh` = 08h (página 1 a la subranura 2) y se lee invertido; "AB" en
  4000h/4001h (lo que busca la BIOS) con la megaROM contestando a la vez en
  8000h (subranura 0); bancos 5 y 15 por 6000h y 6800h; escrituras en la ROM
  que no llegan a la SDRAM;
- banco 40h: 10 bytes con /CS alto, CMD0 → 01h, CMD8 → 01h 00h 00h 01h AAh,
  CMD55 + ACMD41 dos veces (01h y luego 00h), CMD17 del bloque 3 → 00h, FEh y
  los 512 bytes del bloque, y la lista de órdenes que vio la tarjeta (`0 8 55
  A41 55 A41 17`);
- `FFFFh` otra vez a 0, y después la fase H de la MegaRAM entera (la
  secuencia de tncrom, PLAIN0, /RESET) y la R (/RESET con el V9990 pidiendo
  /WAIT), como en `v9990_megaram`.

Sin Nextor, el banco comprueba que la flash y la microSD no se seleccionan
nunca y que sus pines siguen en reposo. `+NXFAST` (depuración) salta las fases
B a G.

Arreglo del banco encontrado aquí: `OP_SLOT` cambiaba `slot_sel` antes de que
bajara el /WR de la escritura anterior (las tareas del Z80 vuelven antes de
soltar sus strobes), así que la escritura de `FFFFh` = 00h justo antes de un
cambio de páginas se perdía y la fase H fallaba (50 fallos, todos de la
megaROM leída en la subranura de Nextor). Ahora `OP_SLOT` espera al final del
ciclo anterior. No era del RTL.

Resultados: RESULTADOS_TB

## 8. Riesgos y pendiente

- **Sin probar en placa**: la flash de la Tang leída con la orden 03h a 18 MHz
  de SCLK justo después de configurar la FPGA (tnCart hace lo mismo), y la SD a
  18 MHz desde el principio: el estándar pide 100-400 kHz durante la
  inicialización. tnCart funciona así con las tarjetas que se han probado;
  alguna tarjeta podría no arrancar (habría que bajar `TF_CLK_DIV` durante la
  inicialización, que el `TF_CONTROLLER` no sabe hacer).
- **El /WAIT de memoria también en Nextor** (`ENABLE_MEM_WAIT`): sin él, a 3,58
  MHz las lecturas de la SDRAM no llegan a tiempo por el bus multiplexado de la
  WonderTANG (es lo que mide `docs/notas/megaram.md` para la megaROM). A 5,37
  MHz el pre-WAIT de memoria no llega, como en la megaROM: Nextor solo es fiable
  a 3,58 MHz (turbo R en modo R800: sin comprobar).
- Arranque más largo: el MSX espera ~72 ms (frente a ~7 ms de `v9990_megaram`).
- Las órdenes de flash de tncrom siguen sin servirse (`MEGAROM_XFER_TIE`): no
  se puede grabar ROMs en la flash desde el MSX.
- Margen de Fmax fino en `xtal` (sección 5).
