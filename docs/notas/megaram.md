# Hito 8: MegaRAM

Rama `hito/megaram`, desde `main` (`20936e6`, hito 1). Ficheros propios:
`fpga/config/v9990_megaram.sv`, `fpga/src/cartridge_megarom.sv`,
`fpga/src/peripheral/msx/megarom_configure.sv`,
`fpga/src/peripheral/msx/megarom_controller.sv`, el módulo nuevo
`fpga/src/peripheral/msx/megarom_clear.sv`, el banco `fpga/tb/megaram/`, la
comprobación de síntesis `fpga/check_megaram.tcl` y `tools/tncrom/`.
`scc.sv` no se ha tocado.

Qué funciona, en una frase: la megaROM de tnCart arranca como Konami SCC-I RAM
en una ventana de 4 MB en `00_0000h` de la SDRAM (256 bancos de 16 KB o de 8 KB
= 2 MB), tiene un modo plano en `0000h-BFFFh` para las demos V9990 de Edd
Biddulph, pide /WAIT en sus lecturas de memoria hasta tener el dato, se borra
(32 KB a FFh) al arrancar sin bootloader, y `tncrom` compila con SDCC, conoce el
modo plano, rechaza las imágenes que no caben y carga Konami SCC de hasta 2 MB.
**Nada de esto se ha probado en la placa**: lo comprueban el banco de
Verilator, openMSX (solo `tncrom` sin cartucho) y una síntesis con P&R.

La primera tanda de este hito se cortó por un límite de sesión con todo
commiteado hasta `4560abf`; la segunda (26/10/2026) volvió a correr sus pruebas
(banco, `tncrom` en openMSX, síntesis con P&R), amplió `tncrom` a Konami de 2 MB
(apartado 6) y el banco con esa máscara (apartado 7), ensayó Another World en
openMSX (apartado 10) y corrigió esta nota donde decía de más.

## 1. Configuración `v9990_megaram`

`fpga/config/v9990_megaram.sv` es `config/v9990.sv` con:

| Parámetro | `v9990` | `v9990_megaram` | Por qué |
|---|---|---|---|
| `ENABLE_MEGAROM` | `DISABLE` | `ENABLE_MEGA_SCC_I` | arranca como Konami SCC-I RAM: bancos en 5000h/7000h/9000h/B000h, máscara FFh (2 MB en 8 KB), sin protección, SCC en modo compatible, `ENABLE_CONTINUOUS` (`main.sv`, `DEFAULT_*`) |
| `ENABLE_SCC` | `DISABLE` | `ENABLE` | el `scc.sv` de tnCart (5 BSRAM, en `CLK_BASE`: no usa `CLK_21M`) |
| `RAM_ADDR_MEGAROM` / `RAM_SIZE_MEGAROM` | `40_0000h` / 3 MB | `00_0000h` / **4 MB** | ventana `00_0000h-3F_FFFFh`; la VRAM sigue en `78_0000h` |
| `RAM_ADDR_RAM` / `RAM_SIZE_RAM` | `00_0000h` / 4 MB | `40_0000h` / 3 MB | el mapper está desactivado; solo para que el borrado de 64 KB del bootloader de tnCart (si alguien compila esta configuración con él, como `check_megaram.tcl`) no pise el principio de la ventana |
| `ENABLE_MEM_WAIT` | (no existe) | `1` (nuevo) | /WAIT en las lecturas de memoria (apartado 4). `cartridge_megarom.sv` lo toma de `CONFIG::ENABLE_MEM_WAIT` como valor por defecto de su parámetro: **toda configuración que compile `cartridge_megarom.sv` tiene que definirlo** |

**Ventana de 4 MB.** En `megarom_controller.sv` la dirección es
`MemoryTopAddr + {2'h0, banco, A[13:0]}` en 16 KB (22 bits, 4 MB) y
`MemoryTopAddr + {3'h0, banco, A[12:0]}` en 8 KB (21 bits, 2 MB), con
`MemoryTopAddr = RAM_ADDR = 0`: los 256 valores de un registro de banco de 8
bits caben sin tocar nada. El banco lo comprueba con los bancos 00h, 01h, 02h,
7Fh, 80h, BFh, C0h, FEh y FFh en ASCII16 (`3F_C000h` el último) y FFh en ASCII8 y
en SCC-I (`1F_E000h`).

**Registro de tamaño (3Eh, índice 1Eh del bloque 30h-3Fh).** Lee
`RAM_SIZE[21:14]`, el tamaño en bancos de 16 KB: con 4 MB (`40_0000h`) da 00h.
Se deja así y se **define 00h = 256 bancos = 4 MB** (la ventana nunca mide 0):
3 MB sigue leyendo C0h como en el firmware de tnCart. El `tncrom` de upstream
no lee este registro; el de V9990TANG sí (`get_window_kb`). Una aserción de
simulación en `megarom_configure.sv` exige `RAM_SIZE` múltiplo de 16 KB entre
16 KB y 4 MB.

## 2. Modo PLAIN0 (ROM plana en `0000h-BFFFh`)

Para las demos V9990 de Edd Biddulph: ROM plana de 16-48 KB con "AB" en 4000h e
ISR en 0038h (estudio, sección 7). Es lo que openMSX hace con una ROM plana en
0000h: `RomPlain.cc` mapea la imagen desde `romBase = 0x0000` (tipo
`NORMAL0000`, o `guessLocation()` si la cabecera lo indica) en páginas de 8 KB
con `romBase / 0x2000`, es decir, desplazamiento = dirección, solo lectura.

**Dónde está el flag.** El registro de flags 0Ch no tiene bits libres (b0-b7:
protección, tamaño de banco, máscaras CS1/CS2, SCC, SCC-I, `ENABLE_CONTINUOUS`,
`ENABLE`). El flag va en el **bit 0 de 1Fh**, el byte "reservado" del banco 3
(`ADDR_BANK3_RESERVED`), que `tncrom` escribe siempre con el resto del atributo
(`rom_attr_xfer`, 0Ch-1Fh): cualquier tipo de upstream lo deja a 0. Los bits 1-7
de 1Fh se guardan y no hacen nada.

**Cuándo está activo**: 1Fh.b0 = 1, la llave cerrada (`reg_protect`) y
`FLAGS.ENABLE` = 1 (`plain_active` en `megarom_configure.sv`, que lo pasa a
`Megarom.Plain`). Con la llave abierta el flag se lee y se escribe como un
registro más y el modo no actúa: `tncrom` puede configurarlo. Activo:

- `megarom_controller.sv` responde a SLTSL·MERQ en `0000h-BFFFh` (ignora las
  máscaras CS1/CS2) y lee de `MemoryTopAddr + A[15:0]`: bancos fijos.
- No escribe: ni la SDRAM (`wr_mem_n` incluye `Plain`) ni los registros de
  banco, ni el registro de modo SCC-I (BFFEh/BFFFh, en `cartridge_megarom.sv`).
  El SCC no contesta (su `CS_n` incluye `Plain`).
- Las **lecturas** de `0000h-003Fh` dan la ROM (con la llave cerrada los
  registros ya estaban ocultos) y se ignoran **todas** las escrituras a la
  configuración, **la llave `0000h-0003h` incluida** (`cs_reg_wr_n = 1`): una
  escritura casual de la demo no la desbloquea. Tampoco se puede volver a
  cargar otra ROM: `tncrom` no encuentra el cartucho (lo dice el mensaje).
- **El /RESET del MSX borra el flag y `ENABLE`**, sea cual sea
  `ENABLE_CONTINUOUS` (que en este modo se ignora; rama `!Bus.RESET_n` de
  `megarom_configure.sv`). Se borra `ENABLE` a propósito: sin él, tras el reset
  quedaría el atributo de `tncrom -T PLAIN0` sin el modo plano (bancos de 16 KB
  0 y 1 en 4000h y 8000h), la BIOS encontraría el "AB" de la demo en 8000h y
  su INIT apuntaría a 4000h-7FFFh, donde estaría la página 0 de la demo. Tras
  el reset el cartucho queda invisible hasta otro `tncrom` o un apagado (que
  vuelve a la SCC-I de fábrica y borra 32 KB).
- Para arrancar la demo: `tncrom -T PLAIN0 -R DEMO.ROM` (reinicio por software,
  CALSLT a 0000h de la BIOS; sin `-R` `tncrom` avisa de que un /RESET lo borra).

**Las demos que hay en local** (`MSXimus_zynq/files/20260921/v9990_filehunter/rom/`,
cabeceras leídas el 26/10/2026) confirman el formato: `WOLF3D.ROM` (48 KB),
`WIREFRM.ROM` y `FLYLOGO.ROM` (32 KB) llevan "AB" en el desplazamiento 4000h con
INIT = 4010h y en 0038h `F5 DB 66` (`PUSH AF / IN A,(66h)`: la ISR lee el
estado del V9990). Con PLAIN0 el desplazamiento es la dirección, así que la BIOS
ve "AB" en 4000h y la ISR queda en 0038h. Las tres caben en los 48 KB.

Riesgo conocido (estudio, sección 10), ahora con el código delante: el INIT de
WOLF3D y WIREFRM (`4010h`: `DI`, `IM 1`, `LD SP,F000h`, apaga la pantalla del
VDP, `CALL RSLREG` y `OUT (A8h),A` en 4031h) pone las páginas 0 y 2 en su slot
primario **sin tocar `FFFFh`**; FLYLOGO sí lee y escribe `FFFFh` (4072h, 4082h).
En el slot expandido de tnCart las dos primeras ven en las páginas 0 y 2 la
subranura que diga `FFFFh` para esas páginas: tiene que ser la 0 (la megaROM;
las 1-3 están vacías en V9990TANG). Tras un /RESET `FFFFh` vale 0
(`expansion_slot.sv`); con el reinicio por software de `-R` (que no pasa por
/RESET) depende de cómo lo dejen la BIOS, el DOS y `tncrom` (cuyos `RDSLT`/`WRSLT`
lo restauran). Sin probar en placa.

## 3. `MEGAROM_CLEAR` (`megarom_clear.sv`)

Sustituye al paso `STATE_CLEAR_MEGAROM` del bootloader de tnCart
(`MEGAROM_CLEAR_SIZE 32768`, relleno FFh). Con `ENABLE_MEGA_SCC_I` la megaROM
arranca habilitada en `4000h-BFFFh`; sin el borrado la BIOS buscaría "AB" en lo
que hubiera en la SDRAM al encender.

```
MEGAROM_CLEAR #(.CLEAR_ADDR(24'h00_0000), .CLEAR_SIZE(24'd32768), .CLEAR_DATA(8'hFF))
    (input RESET_n, input CLK, RAM_IF.HOST Ram, output reg DONE)
```

- Arranca al soltarse `RESET_n` (el reset de la carcasa: PLL enganchado y
  SDRAM lista). Escribe de cuatro en cuatro bytes (`DIN_SIZE_32`: una palabra de
  la SDRAM por acceso, DQM = 0000, como las escrituras de 32 bits del blitter)
  con el protocolo del UMA: `WE_n` = 0 con `ADDR`/`DIN`, espera `ACK_n` = 0,
  `WE_n` = 1 y `ADDR`/`DIN`/`DIN_SIZE` a 0 (`EXPANSION_RAM` hace OR de los
  clientes), espera `ACK_n` = 1. Al acabar saca `DONE` = 1 y deja el puerto en
  reposo hasta el siguiente `RESET_n`; el /RESET del MSX no lo relanza (el
  bootloader tampoco).
- No emite refrescos: al encender la SDRAM no tiene nada que conservar.
- Medido en el banco: **8192 escrituras, `DONE` a los 163 837 ciclos de soltar
  `RESET_n` (1,52 ms)** con el UMA de `main` (165 937, 1,54 ms, con el de
  `hito/sdram`, cuyo refresco interno ocupa alguna ranura). Una escritura por
  ranura del canal 0 (cada 20 ciclos). Nada escrito pasados los 32 KB ni en la
  VRAM. La nota de `hito/integ` estima ~7 ms; la cifra medida es 1,52 ms.
- `CLEAR_ADDR` y `CLEAR_SIZE` múltiplos de 4 (aserción de simulación).
- El puerto sale decodificado del estado (sin flops propios): 17 LUT / 21 ALU /
  25 FF en síntesis (apartado 8).

## 4. /WAIT en las lecturas de memoria (hito 8b, `ENABLE_MEM_WAIT`)

`megarom_controller.sv`, con `ENABLE_MEM_WAIT = 1` y `USE_FF = 1` (el caso de
`CARTRIDGE_MEGAROM`); con 0 todo queda como en tnCart. Una máquina de cuatro
estados sobre `rd_mem_n` (SLTSL·MERQ·RD·!RFSH y dirección de la ventana, en el
camino retrasado):

- **Baja `Bus.WAIT_n` 1 ciclo después de ver la lectura** (`rd_mem_n` a 0 en el
  `Bus` del controlador; `Bus.WAIT_n` es un flop). Medido: rd_mem_n → WAIT_n del
  puerto 1 ciclo; `Bus.RD_n` retrasado del top → `Bus.WAIT_n` del top **3
  ciclos** (las dos etapas de flops de `EXPANSION_SLOT`, `SLOT_EXPANSION_USES_FF
  = 1`, más el flop del controlador), en todas las lecturas de todas las
  variantes.
- **Lo mantiene hasta que `Bus.DOUT` tiene el dato**: espera a que el
  `ACK_n` del canal 0 baje (el UMA lo baja en el flanco siguiente a `OE_n` = 0)
  y vuelva a subir (el UMA lo sube en el mismo flanco en que carga
  `Secondary[0].DOUT`). En el ciclo en que ve `ACK_n` = 1, `mem_wait_req` cae y,
  en el flanco siguiente, `Bus.WAIT_n` sube **en el mismo flanco en que
  `Bus.DOUT` carga `Ram.DOUT[7:0]`**. Un `ACK_n` ya bajo al empezar (escritura o
  refresco anteriores aún en curso) no adelanta la liberación: el UMA no lo sube
  mientras quede la lectura pendiente (`save_oe` en `req_any`).
- Del WAIT suelto al fin de la lectura el dato no cambia (lo vigila el banco).
- Solo lecturas: las escrituras no piden /WAIT (el UMA las guarda al ver el
  flanco de `WE_n`). Las lecturas del SCC (9800h/B800h) también esperan a la
  SDRAM, como en tnCart, aunque el dato salga del SCC. Las de los registros
  (`0000h-003Fh`, fuera de PLAIN0), del `FFFFh` y de las páginas que no son de
  la megaROM no piden /WAIT.

Cifras del banco (108 MHz): del `Bus.RD_n` retrasado a `Bus.WAIT_n` alto con
el dato, **15 a 34 ciclos (139-315 ns)** según la fase de la lectura frente a
la ranura del canal 0 (hasta 49 ciclos con un refresco inyectado en el mismo
canal; 54 con el UMA de `hito/sdram`). Del /RD del pin al /WAIT del pin, **14
ciclos (130 ns)** solo con la cadena (filtro 2 + línea de 9 + tres flops), 8 con
el modelo de pre-WAIT del banco.

**`!RFSH_n` en `rd_n`.** En el camino retrasado el `RD_n` de un M1 sigue bajo
unos ciclos (línea de 9) cuando `MERQ_n` ya ha vuelto a bajar para el refresco
con la dirección I:R. Si esa dirección cae en la ventana (página 0 en PLAIN0, o
un registro I entre 40h y BFh), tnCart lanzaba una lectura de la SDRAM, y con
`ENABLE_MEM_WAIT` sería además un /WAIT espurio. `MERQ_n` y `RFSH_n` se
muestrean juntos (grupo 2 del mux), así que basta con añadir `!Bus.RFSH_n` a la
condición de lectura. El banco cuenta los refrescos que sin esa condición
habrían sido lecturas: 0 a 3,58 y 5,37 MHz, 16 a 7,16 MHz.

### Contrato con el pre-WAIT del área bus

`hito/bus` añade a `BOARD_REV1_BUS` un pre-WAIT de memoria (`PREWAIT_MEM_EN`,
`PREWAIT_MEM_K = 7`; leído en su worktree sin fusionar): /WAIT de nivel desde
la muestra del grupo 2 tras el flanco de RD filtrado, hasta que `Bus.WAIT_n`
(el del top) baje y vuelva a subir, o hasta K ciclos con el RD retrasado en
`Bus` sin que baje. Lo que este hito garantiza:

- `Bus.WAIT_n` del top baja **3 ciclos** después del RD retrasado (≤ 3 en el
  puerto: 1), por debajo de K = 7 con 4 de margen, mientras la dirección,
  SLTSL y MERQ estén ya en `Bus` cuando llega el RD retrasado (lo que asegura el
  escaneo adaptativo de `hito/bus`).
- Sube una sola vez por lectura y con el dato en `Bus.DOUT`.
- En lo que no es suyo (registros, `FFFFh`, otras subranuras, páginas fuera de
  la ventana) no baja nunca: ahí el pre-WAIT se suelta por K.

Medido con el **modelo** de pre-WAIT del banco (disparo a `PW_DLY` ciclos del RD
filtrado; supuestos del Z80A: salidas 46 ns tras el flanco, /WAIT visto con 100
ns de NPN + setup, dato con 56 ns): a **3,58 MHz** el Z80 espera bien con y sin
pre-WAIT (la cadena sola llega en 14 ciclos; variantes `wait` y `noprewait`
estrictas). A **5,37 MHz** solo vale un pre-WAIT en el pin a ≤ 4 ciclos del /RD
del pin: con 4 ciclos, 0 fallos; con 5, 177 lecturas mal leídas y 37 sin esperar;
con 8 (el disparo por defecto del modelo), 217 y 49 (`turbo5`, `turbo5i` y un
barrido de `PW_DLY` = 1, 2, 3). A 7,16 MHz, 324 y 150 con 8 ciclos. La conclusión
para `hito/bus`: en ciclos de **memoria** (sin el TW automático de la E/S) el
pre-WAIT de 5,37 MHz tiene que salir casi a la vez que el filtro del pin
(este, 2 ciclos); con estos supuestos un disparo tras una muestra fresca del
grupo 2 (2 ciclos de asentamiento y 2 muestras después del RD filtrado) no
llega. Son cifras de un modelo, no de la placa, y dependen sobre todo del
retardo de /RD del Z80 y del setup de /WAIT supuestos. La nota del área bus
(`docs/notas/bus.md` del worktree de `hito/bus`, sin commit, leída el
26/10/2026) llega a lo mismo por su lado: el presupuesto de /WAIT en memoria a
5,37 MHz son 41 ns (T − 145 ns) y su banco solo da por buena la MegaRAM a 3,58.

### Contrato con el UMA (área sdram)

El /WAIT se suelta con el `ACK_n` del canal 0. Hace falta que `ACK_n` suba
cuando `Secondary[0].DOUT` tiene **el dato de la lectura**. Con el `uma.sv` de
`main` (tnCart) `DOUT` se copia en cada fin de acceso, refrescos incluidos: si un
RFSH de **otro** cliente del canal 0 acaba después que la lectura, `ACK_n` sube
con la última lectura de la SDRAM (la del canal 1, la VRAM) y el WAIT se suelta
con el dato malo. El banco lo demuestra (`inj_main`: 7 de 31 lecturas con un
refresco inyectado rompen el contrato). En la configuración `v9990_megaram`, con
ese UMA, no pasa: el único cliente del canal 0 es la megaROM (su propio RFSH es
el del Z80, después del dato del M1) y el borrado acaba antes de soltar el
reset. Con el `uma.sv` de `hito/sdram` (refresco interno en el canal 0, `DOUT`
solo tras un R/W) el contrato se cumple siempre (`inj_hito4`: 0 de 31; y
`wait_hito4`). **La integración tiene que fusionar `hito/sdram` antes o a la vez
que el refresco interno**: es el mismo cambio.

## 5. Cambios de comportamiento frente a tnCart

Todos en la megaROM; la configuración `v9990` del hito 1 no compila estos
ficheros.

- Ventana de 4 MB en 0 (antes 3 MB en `40_0000h`); 3Eh = 00h significa 4 MB.
- PLAIN0 (nuevo; con 1Fh.b0 = 0, el valor de todos los tipos de upstream, no
  cambia nada).
- `ENABLE_MEM_WAIT` (nuevo; 0 = tnCart).
- `!RFSH_n` en la condición de lectura del controlador: un ciclo de refresco
  ya no lanza una lectura de la SDRAM (en tnCart era inocuo: el pin de datos
  solo se conduce con /RD del pin bajo).
- **/RESET del MSX** (cambio de `hito/integ`, no de este hito, validado aquí):
  sin bootloader `SYS_RESET_n` ya no sigue al /RESET, y la megaROM pasa por la
  rama `!Bus.RESET_n` de `megarom_configure.sv`: conserva el atributo que dejó
  `tncrom`, cierra la llave, pone los bancos a su valor inicial
  (`BankRegInit`) y deja `ENABLE` según `ENABLE_CONTINUOUS`. Con el bootloader
  de tnCart `READY` bajaba en cada /RESET y la megaROM volvía a sus valores de
  fábrica. El banco lo prueba: SCC-I y ASCII16 siguen tras /RESET con
  `ENABLE_CONTINUOUS` (bancos 0,1,2,3 y 0,0), se deshabilitan sin él (`tncrom
  -O`), y el 32K necesita el banco 1 inicial = 1 en la tabla de `tncrom` (con el
  0 de upstream 8000h-BFFFh repetiría 4000h-7FFFh).

Lo que no cambia y conviene saber (comparado con openMSX; código de tnCart sin
tocar, en `cartridge_megarom.sv`):

- **SCC-I tras el encendido o un /RESET.** El estado de reset del registro de
  modo deja `WriteProtect_SCC = 0000` y `BankEnable_SCC = 1111`: con el
  atributo SCC-I (sin `FLAG_WRITE_PROTECT`) la megaROM es escribible y una
  escritura a un registro de banco cambia el banco **y** cae en la RAM
  (`wr_mem_n` no excluye esas direcciones; `tncrom` lo esquiva). Es lo que
  tnCart quiere para SofaRun y MGSP sin ejecutar nada. Escribir 00h en BFFEh
  (lo hace `tncrom -T KONAMI_SCC_I`) sí deja los cuatro bancos protegidos y
  con registro, como el modo 0 del SCC+ de openMSX
  (`src/sound/MSXSCCPlusCart.cc`: `reset()` llama a `setModeRegister(0)` y
  ningún segmento es RAM; en un segmento RAM, `writeMem` escribe la RAM y no
  cambia el banco, igual que tnCart con `BankEnable_SCC = !WP`).
- **Bits 0-2 del registro de modo, desplazados.** tnCart usa el bit 0 para el
  segmento de 6000h, el 1 para 8000h y el 2 para A000h (el de 4000h solo con
  el bit 4). En openMSX (`setModeRegister`) el bit 0 es el segmento de 4000h,
  el 1 el de 6000h, el 2 el de 8000h y solo en modo SCC+ (bit 5), y el de
  A000h solo con el bit 4. Coinciden el 00h que escribe `tncrom`, el bit 4
  (todo RAM) y el 5 (SCC+). Según el README de tnCartWonder MGSP y SofaRun
  funcionan así; no se ha comprobado qué bits escriben. No se ha cambiado: es
  comportamiento de tnCart y queda fuera de este hito. El arreglo, si hiciera
  falta, son las ocho asignaciones de `BankEnable_SCC`/`WriteProtect_SCC` de
  `cartridge_megarom.sv`.
- Coinciden las direcciones de los registros (5000h, 7000h, 9000h, B000h,
  `(address & 0x1800) == 0x1000`), los bancos tras el reset (0, 1, 2, 3) y
  dónde aparece el SCC (9800h con el banco 2 a 3Fh en modo SCC; B800h con el
  bit 7 del banco 3 en SCC+). ASCII16 coincide con
  `src/memory/RomAscii16kB.cc` (registros en 6000h-67FFh y 7000h-77FFh, los
  dos bancos a 0 tras el reset; tnCart usa la máscara F800h).

## 6. `tncrom` (`tools/tncrom/`)

Copia de `tools/tncrom/{src,cfg}` y `tools/lib` de tnCartWonder `d3a54f1`
(`lib/` ahora en `tools/tncrom/lib`), con la LICENSE BSD-3 de Shinobu Hashimoto.

**Compilación.** Upstream compila con z88dk (`zcc +msx -subtype=msxdos -O3 ...`,
comentario al principio de `src/main.c`; en `buppu3/tnCart` no hay Makefile ni
otra instrucción). Aquí con SDCC 4.5 (`C:/Program Files/SDCC/bin`):

```
bash tools/tncrom/build.sh        # Git Bash; SDCC_BIN=/ruta si no esta en el PATH
-> tools/tncrom/bin/TNCROM.COM (13 375 bytes, codigo y datos hasta 39F1h)
```

`build.sh` ensambla `sdcc/crt0_msxdos.s` (jp en 0100h, borra `_DATA`/`_BSS`,
copia los inicializados), compila con `-mz80 --opt-code-size`, enlaza el código
en 0110h y comprueba que código y datos acaban antes de 6000h (el búfer de 8 KB
de `main.c` vive en 6000h-7FFFh). `sdcc/crt_msxdos.c` parte la cola de 0080h en
`argv`, comprueba que la pila está en la página 3 (la página 2 pasa al cartucho
durante la copia) y sale con `_TERM`. Los bloques `#asm` de z88dk pasan a
funciones `__naked` que toman los registros de variables globales: no dependen
del convenio de llamada de SDCC y guardan IX/IY. La compilación es
reproducible (dos builds, mismo binario).

**Extensiones** (las líneas llevan `V9990TANG`):

| | |
|---|---|
| `-T PLAIN0` | atributo plano (protección, 16 KB, sin registros de banco, bancos iniciales 0/1/2) con 1Fh.b0 = 1; máximo 48 KB |
| Tamaño | cada tipo lleva su máximo (`max_kb`, después del nombre: no entra en los 20 bytes que `rom_attr_xfer` escribe en 0Ch-1Fh): los de 16 KB (ASCII16, R-TYPE) 4096 KB, los de 8 KB (ASCII8, KONAMI, KONAMI_SCC_I, KONAMI_WO_SCC) 2048, 32K 32, 16K/16K2 16, PLAIN0 48. Se comprueba antes de tocar el cartucho (fichero vacío o mayor que el tipo) y, ya encontrado, frente a la ventana que lee 3Eh. Antes no se comparaba y el banco de 8 bits daba la vuelta: SOCCER12 (8 MB) se habría escrito con *wrap* |
| Máscara de banco | KONAMI y KONAMI_WO_SCC llevan en la tabla de upstream la máscara 3Fh (64 bancos de 8 KB = 512 KB): con ella GNG2M (2 MB) y LIFEARTH (1 MB), Konami SCC, no funcionarían. Con una imagen de más de 512 KB `tncrom` escribe en 0Dh, tras el atributo, la máscara de la tabla OR la que pide la imagen redondeada a potencia de 2 (1 MB: 7Fh, 2 MB: FFh). Es lo que hace openMSX: `RomKonamiSCC::writeMem` pasa el valor de 8 bits entero y `RomBlocks::setRom` da la vuelta con `blockMask = nrBlocks - 1`. Con 512 KB o menos no cambia nada (3Fh, como upstream) |
| MSX-DOS 1 | "MSX-DOS 2 or Nextor required." (`_DOSVER`; `DEFAB`, `_TERM` y los handles son de DOS 2) |
| 32K | banco 1 inicial = 1 (apartado 5) |
| Mensajes | la ayuda da el máximo de cada tipo; "cartridge not found" recuerda PLAIN0; versión "v0.07 (V9990TANG r2)" |

Para GNG2M y LIFEARTH el tipo es `-T KONAMI` (con protección). `-T KONAMI_SCC_I`
también admite 2 MB, pero tras un /RESET del MSX queda escribible (apartado 5)
y la primera escritura a un registro de banco caería en la ROM cargada.

**Probado en openMSX** (`C:/Program Files/openMSX`; salida de cada orden por
redirección a un fichero y `get_screen` desde un Tcl). El 26/10/2026 con el
binario de `bfc5748` (r2): Philips NMS 8250 con una Sunrise IDE de Nextor 2.1.4
(extensión `v99tang_tncrom_ide.xml` en la carpeta `share/extensions` de
OneDrive) y una imagen FAT16 de 128 MB hecha con
`SymbOS-MSXimus/tools/build_sd.py` (las imágenes de 2-8 MB no caben en un
`-diska` de directorio, que es un disco de 720 KB); los ficheros de salida se
sacaron de la imagen con `extract.py`:

| Orden | Resultado |
|---|---|
| `TNCROM` | versión `v0.07 (V9990TANG r2)` y `USAGE` |
| `TNCROM -H` | ayuda con los 10 tipos y su máximo |
| `-T PLAIN0 P49K.ROM` (48 KB + 1 byte) | `rom image too large for PLAIN 0000h~BFFFh: 49KB, max 48KB.` |
| `-T PLAIN0 Z0.ROM` (0 bytes) | `empty rom image file(Z0.ROM).` |
| `-T KONAMI K2049.ROM`, `-T KONAMI_WO_SCC K2049.ROM`, `-T KONAMI_SCC_I K2049.ROM`, `-T ASCII8 A8_2049.ROM` (2049 KB) | `rom image too large for <tipo>: 2049KB, max 2048KB.` |
| `-T ASCII16 A4097.ROM` (4097 KB), `-T ASCII16 S8M.ROM` (8 MB, como SOCCER12) | `rom image too large for ASCII 16KB: 4097KB` / `8192KB, max 4096KB.` |
| `-T 32K B32K.ROM` (32 KB + 1 byte) | `rom image too large for NO BANK 32KB: 33KB, max 32KB.` |
| `-T FOO P48K.ROM` | `unknown rom type(FOO).` |
| `-T PLAIN0 P48K.ROM`, `-T KONAMI` con 512, 513 y 2048 KB, `-T ASCII16 A4096.ROM` | pasan la comprobación y dan `cartridge not found (if PLAIN0 is active, reset the MSX first).`: openMSX no tiene la megaROM de tnCart |
| `TNCROM` bajo MSX-DOS 1 (NMS 8250 sin Nextor, el `MSXDOS.SYS` de `msx_z80bench/dsk`, "MSX-DOS version 1.8", COMMAND 1.12) | `MSX-DOS 2 or Nextor required.` y vuelve al indicador |

La revisión r1 (`b7c21e1`) se probó igual con MSX-DOS 2.20 (extensión `msxdos2`)
y un disco de directorio; el binario solo con el port (sin extensiones,
`deff8cd`) da la misma ayuda y el mismo "cartridge not found." que el original.
**La carga real no se ha probado** y la máscara de 0Dh solo se puede ver con el
cartucho: necesita la placa. La secuencia de registros que hace `tncrom`
(`lib/rom_tools.c`, `src/main.c`) es la que reproduce el banco, que comprueba
también las dos máscaras de KONAMI (apartado 7).

## 7. Banco (`fpga/tb/megaram/`, Verilator 5.020 en WSL)

```
wsl -e bash -lc "cd /mnt/c/<repo>/fpga/tb/megaram && ./run.sh [variante...]"
# las *_hito4 piden el uma.sv de hito/sdram (el git de WSL no lee los worktrees):
git show hito/sdram:fpga/src/peripheral/ram/uma.sv > /c/tmp/uma_hito4.sv
wsl -e bash -lc "cd ... && UMA_SV=/mnt/c/tmp/uma_hito4.sv ./run.sh"
```

Cadena: Z80 a nivel de pines (modelo) → `BOARD_REV1_BUS` de `main` (filtros,
mux de 9 estados, línea de 9) → `EXPANSION_SLOT` → `CARTRIDGE_MEGAROM`
(configure + controller + SCC de tnCart con un modelo mínimo de la DPB) →
`EXPANSION_RAM` (megaROM, `MEGAROM_CLEAR` y un puerto del banco que inyecta
refrescos) → `UMA` (DIV 30, libre) → `SDRAM_IF_MODEL` (modelo de ciclo del lado
`RAM_IF` de `sdram.sv`: TIMING en IDLE, 9 estados, `ACK_n` baja en IDLE y sube en
IDLE+7, dato en IDLE+6). En el canal 1 un cliente de VRAM lee en todas sus
ranuras como un V9990 a plena carga y cuenta ranuras perdidas y datos malos.
`SYS_RESET_n` se retiene hasta `DONE`, como hará `main.sv`.

Lo que recorre: el borrado al arrancar (con el Z80 ya fuera de reset, retenido
por el /WAIT de `EXPANSION_SLOT`), la SCC-I de fábrica (cabecera borrada, 2 MB
en 8 KB, el SCC en 9800h con el banco 2 a 3Fh, M1 con I = 40h en la ventana,
/RESET con `ENABLE_CONTINUOUS`), la secuencia de `tncrom` (prueba de 0000h, llave
AB CD 98 76, 3Ch-3Eh, ASCII16 sin protección con el banco 0 al último, bancos
por 7000h y datos por 8000h, atributo final, protección), 256 bancos de 16 KB
por las dos páginas, ASCII8 con el banco FFh, el /RESET con y sin
`ENABLE_CONTINUOUS`, el 32K tras /RESET, KONAMI con la máscara 3Fh de la tabla
(banco FFh → 3Fh, 41h → 01h, el registro B000h no escribe la RAM) y con la FFh
que `tncrom` r2 escribe para 2 MB (FFh y 41h), PLAIN0 (imagen de 48 KB con "AB" en
4000h, lectura lineal de `0000h-BFFFh` y barrido, registros ocultos, `C000h` sin
respuesta, M1 en la página 0 con I = 0, llave y configuración ignoradas,
escrituras y bancos bloqueados, SCC mudo, /RESET), y en cada lectura el contrato
del /WAIT (cuándo baja en el puerto y en el top, que suba con el dato válido y
que el dato no cambie hasta el fin de la lectura; ningún /WAIT fuera de una
lectura de la megaROM).

Resultados del 26/10/2026 (`run.sh` sin argumentos, las nueve PASA; las
`*_hito4` con el `uma.sv` de `hito/sdram` `cbf65ea`, md5 `0738833e`). Se corrió
dos veces: con el banco de `4560abf` (salen las mismas cifras que se habían
apuntado con él: 237 lecturas, 47 de 249 mal leídas sin /WAIT, 7 de 31 en
`inj_main`, 217 y 324 fallos en `turbo5` y `turbo7`) y con el banco ampliado con
KONAMI (`dc67fec`), que es la tabla:

| Variante | Qué | Resultado |
|---|---|---|
| `wait` | estricta, 3,58 MHz, /WAIT + modelo de pre-WAIT | 241 lecturas de la megaROM, todas con WAIT; 0 errores; VRAM: 12 937 lecturas, 0 malas, 0 ranuras perdidas; borrado en 163 837 ciclos (1,52 ms), 8192 escrituras |
| `noprewait` | estricta, 3,58 MHz, solo la cadena | 0 errores (/WAIT en el pin a 14 ciclos del /RD) |
| `wait_hito4` | estricta, con el `uma.sv` de `hito/sdram` | 0 errores; borrado en 165 937 ciclos (1,54 ms) |
| `inj_hito4` | estricta, refresco inyectado en el canal 0 a +0..+30 ciclos | 0 de 31 lecturas rompen el contrato (liberación 15-54 ciclos) |
| `inj_main` | medida, igual con el UMA de `main` | 7 de 31 rompen el contrato (defecto del UMA, apartado 4) |
| `nowait` | medida, `ENABLE_MEM_WAIT = 0` (tnCart) | 61 lecturas mal leídas por el Z80 de 253: sin /WAIT el dato llega tarde según la fase con la ranura |
| `turbo5`, `turbo5i`, `turbo7` | medidas a 5,37 / 7,16 MHz | 220 / 0 / 331 fallos contados del Z80 (pre-WAIT a 8 / 4 / 8 ciclos del /RD del pin); ver el apartado 4 |

En todas: `Bus.RD_n` → `Bus.WAIT_n` del top 3 ciclos, `rd_mem_n` → `WAIT_n` del
puerto 1 ciclo, `Bus.WAIT_n` sube con `Bus.DOUT` válido a los 15-34 ciclos del
`Bus.RD_n` (139-315 ns; hasta 49 con un refresco inyectado y 54 con el UMA de
`hito/sdram`).

El banco no modela la SDRAM física (el punto de captura de `sdram.sv`), ni el
NPN, ni el escaneo adaptativo de `hito/bus` (usa el `board_rev1_bus.sv` de
`main` y un modelo de pre-WAIT).

## 8. Síntesis (`fpga/check_megaram.tcl`)

`cd fpga && gw_sh check_megaram.tcl` (Gowin 1.9.12.03, place 2, route 1): la
lista de `build_v9990_xtal.tcl` con `config/v9990_megaram.sv` en lugar de
`config/v9990.sv` y `cartridge_megarom.sv`, `megarom_{configure,controller,clear}.sv`
y `scc.sv`; `main.sv` es el de `main`, **con el bootloader de tnCart** (como la
referencia del estudio), así que `MEGAROM_CLEAR` está en la lista pero no lo
instancia nadie. Mismo `.sdc` que el hito 1. Salida en
`fpga/impl/pnr/check_megaram.*` (no se versiona). Para separar el coste de
este hito del de la megaROM de tnCart, la misma build con los ficheros de
`main` y `config/v9990.sv` con solo `ENABLE_MEGAROM = ENABLE_MEGA_SCC_I` y
`ENABLE_SCC = ENABLE` (la configuración `v9990_mega` del estudio), compilada
en una ruta corta aparte (`Temp/v99wt/mr_base`) el mismo día. La build
`check_megaram` se volvió a lanzar en la segunda tanda (26/10/2026, 08:58-09:37,
con otras builds en paralelo; el RTL no cambió) y salió igual: el
`check_megaram_syn_rsc.xml` es idéntico byte a byte y el `.rpt.txt` solo cambia
en las fechas (el P&R es determinista). La base no se volvió a compilar (sus
cifras de lógica y registros son las del estudio, exactas):

| | Estudio `v9990_mega` | Base (megaROM de tnCart, este árbol) | **`check_megaram`** |
|---|---|---|---|
| Lógica (LUT + ALU) | 15 494 (12 721 + 2 773) | 15 494 (12 721 + 2 773) | **15 580** (12 808 + 2 772), +86 |
| Registros | 7 235 | 7 235 | **7 237**, +2 |
| CLS | 9 111 (88 %) | 9 129 (89 %) | **9 080 (88 %)** |
| BSRAM | 29/46 | 29/46 | **29/46** |
| rPLL / CLKDIV / PRIMARY / LW | 2/2, 3/8, 8/8, — | 2/2, 3/8, 8/8, 8/8 | 2/2, **3/8**, 8/8, 8/8 |
| Endpoints violados (setup / hold) | 268-290 / 0 (sin `set_clock_groups`) | 0 / 0 | **0 / 0** |
| Fmax `CLK_BASE` | 112,9 MHz | 113,17 MHz | **112,36 MHz** |

- La base reproduce la lógica y los registros del estudio exactos; sus CLS
  difieren en 18 por el `.sdc` (el P&R cambia con él).
- **Coste de este hito: +86 de lógica y +2 registros**; en la síntesis,
  `u_megarom` pasa de 1 019 a 1 057 LUT y de 925 a 927 FF (`u_rom`, el
  controlador, +29 LUT: PLAIN0, el /WAIT y `!RFSH_n`; `u_conf` +1; `u_scc` +8,
  ruido) con las mismas 168 ALU y 5 BSRAM. Los CLS bajan 49 frente a la base:
  es colocación, dentro del ruido del P&R (estudio, sección 10: 0 a 0,33 CLS
  por celda). `MEGAROM_CLEAR` no está en estas cifras (no se instancia).
  Medido aparte, solo síntesis, en una copia con un `main.sv` de medida que lo
  instancia junto al bootloader (`Temp/v99wt/mr_clear`, con el mismo
  `megarom_clear.sv`, md5 `3916c7c5`): **17 LUT / 21 ALU / 25 FF**, frente a
  los 595 LUT / 16 ALU / 266 FF del `u_boot` de `check_megaram` (más `u_flash`
  228 LUT / 108 FF y `u_flash_spi` 63 / 64), que la integración quita.
- Sin `CLK_21M` ni relojes nuevos: CLKDIV 3/8 como en el hito 1, 8/8 PRIMARY.
- **Puerta** (`tools/check_build.py` con la referencia del estudio, 15 494 /
  9 111 / 29, ±1 %): **PASA**. Lógica +0,56 %, CLS −0,34 %, BSRAM igual,
  `set_clock_groups` `Actived` y las 16 órdenes del `.sdc` en el `.tr`, peor
  slack setup / hold / recovery / removal +0,359 / +0,074 / +4,291 / +1,086 ns,
  carrera `CLK_BASE` → `DCLK` +1,954 ns en setup y +4,353 en hold, offset de
  `DCLK` con +0,167 ns de margen en el SDF, Fmax 112,36 MHz. Avisos, leídos:
  CV0016 x2 (`UART_RX` y `TF_DAT0` sin uso, como en el hito 1), NL0002 x5
  (módulos barridos: el SPI de la TF, el mezclador `u_mixer_int` y el
  atenuador `u_att_int_megarom` de la salida `SoundInternal`, que el top de la
  wt200b declara y no usa, `LIMITER_FF` y `ATT_CONST`) y PR1014 x1
  (`CLK_27M_d` a un CLKDIV por enrutado genérico, como en el hito 1).

## 9. Contratos para la integración

- **`main.sv`**: descomentar `` `define HAVE_MEGAROM_CLEAR `` (`hito/integ` ya
  instancia `MEGAROM_CLEAR` con `RESET_n`, `CLK`, `Ram(ExpRam[RAM_BOOTLOADER])`,
  `DONE`, `CLEAR_ADDR = CONFIG::RAM_ADDR_MEGAROM`, `CLEAR_SIZE = 32768`):
  coincide con este módulo. `DONE` retiene `SYS_RESET_n` y va a la entrada
  `WAIT_n` de `EXPANSION_SLOT`. `CARTRIDGE_MEGAROM` conserva sus puertos (`Xfer`
  incluido); su parámetro nuevo `ENABLE_MEM_WAIT` toma por defecto
  `CONFIG::ENABLE_MEM_WAIT` y no hace falta pasarlo.
- **Configuración**: la build MegaRAM usa `config/v9990_megaram.sv`, que define
  `ENABLE_MEM_WAIT`. Cualquier otra configuración que compile
  `cartridge_megarom.sv` tiene que definirlo.
- **`hito/bus`**: activar `PREWAIT_MEM_EN = 1` en la configuración MegaRAM
  (con `PREWAIT_MEM_K = 7`; el /WAIT de la megaROM llega al top a los 3 ciclos).
  Para turbo, ver las cifras del apartado 4.
- **`hito/sdram`**: fusionar su `uma.sv` (DOUT solo tras un R/W) antes o a la
  vez que su refresco interno; con el `uma.sv` de `main` el contrato del /WAIT
  solo se cumple mientras la megaROM sea el único cliente del canal 0.
- **UMA libre**: `MEGAROM_CLEAR` necesita las ranuras del canal 0 con el MSX
  apagado o en reset: `SYNC_CPU_UMA = 0` (lo es en las dos variantes de
  `hito/integ`). Con `SYNC_CPU_UMA = 1` el contador del UMA se para sin
  `CLK_EN` y el borrado no acaba sin el reloj del slot.
- **`.sdc`**: el SCC por defecto corre en `CLK_BASE`; `CLK_21M` sigue podado
  (lo comprueba la síntesis: CLKDIV 3/8).
- **Lista de ficheros**: `src/cartridge_megarom.sv`,
  `src/peripheral/msx/megarom_{configure,controller,clear}.sv`,
  `src/peripheral/sound/scc/scc.sv` y `config/v9990_megaram.sv` (en lugar de
  `config/v9990.sv`), los mismos nombres que espera `build_common.tcl` de
  `hito/integ`.
- **Documentación** (ARCHITECTURE/VERIFICATION/changelog, de la
  integración): el mapa de la SDRAM de la MegaRAM, los registros 1Fh y 3Eh, el
  /RESET con `tncrom`, el uso de `tncrom -T PLAIN0 -R`, los máximos por tipo
  (4 MB en 16 KB, 2 MB en 8 KB, `-T KONAMI` para los Konami SCC de 1-2 MB) y
  que Another World V9990 pide un turbo R.
- **`tools/tncrom/bin/TNCROM.COM`** es el binario de `build.sh` (r2, 13 375
  bytes); la LEEME de la 1.0 lo distribuye en lugar del de tnCart.

## 10. Pendiente y riesgos

- Nada probado en placa: carga con `tncrom` de la lista del hito 8 (SAMURAI,
  DEMO9990, MRBALLON, NEONV99, MSXgl, GNG2M, LIFEARTH, DREAMPUZ, INAROW, las
  demos planas, ANOTHERW en un turbo R), SOCCER12 rechazado (8 MB: `tncrom` lo
  rechaza en openMSX con mensaje, falta verlo con el cartucho), SofaRun con la SCC-I RAM, VRAM
  intacta tras 10 min de LDIR, osciloscopio del /WAIT, GNG y NEON a 5,37 MHz.
- **Another World V9990** (`ANOTHERW.ROM`, 1 966 080 bytes = 120 bancos de 16
  KB, firma `ASCII16X` en 10h; está en
  `MSXimus_zynq/files/20260921/v9990_filehunter/rom/`). Ensayo en openMSX 21.0
  del 26/10/2026, como pide el estudio:
  - **Exige turbo R y V9990**: su INIT (4018h) lee la versión en 002Dh
    (`CP 3`, 402Ch) y busca el V9990 (4048h-405Ch) y una MoonSound; sin los dos
    primeros se queda en un `JR $` en 40B7h. Así se queda en un NMS 8250 con
    GFX9000, con ASCII16 y con ASCII16-X (lo detecta openMSX por la firma). En
    un MSX2/2+ no arranca con ningún mapper; en local no hay ROMs de sistema de
    turbo R.
  - Saltando a mano esa comprobación (punto de parada en 40B0h que pone los
    bits 0-1 de B, y otro que salta el `CALL 0180h` de `CHGCPU`) en un NMS 8250
    con 512 KB de RAM (`-ext ram512k`) y GFX9000: **900 s emulados con
    `-romtype ASCII16` y con el ASCII16-X dan la VRAM del V9990 idéntica byte a
    byte** en los diez volcados (30 a 900 s; cambia hasta los 750 s). El código
    que copia la ROM a la RAM del mapper (0860h-08FFh, en RAM) conmuta bancos con
    `LD (6000h),A` y `LD (7000h),A`, los registros de ASCII16. Pero en el Z80 el
    juego no llega a pintar: la salida del V9990 es un color plano (el motor
    está escrito para el R800). Es un indicio de que basta ASCII16 (120 bancos
    caben en 8 bits; no se ven espejos ni bancos con A11-A8), **no una prueba**:
    falta jugarlo en un turbo R. Si funciona, sería `tncrom -T ASCII16`; la
    ventana de 4 MB ya lo admite.
- Turbo: con el /WAIT de memoria el contrato se cumple, pero el modelo dice que
  a 5,37 MHz el pre-WAIT tiene que estar en el pin a ≤ 4 ciclos del /RD.
- `tncrom -R` con PLAIN0 depende de que el registro `FFFFh` tenga las páginas 0
  y 2 en la subranura 0 cuando arranca la demo: WOLF3D y WIREFRM no lo tocan
  (apartado 2).
- El SCC sigue con sus 5 BSRAM (una DPB por canal): se pueden ahorrar 4 con una
  sola DPB si hiciera falta.
- *Known issue* #14 de tnCart (github.com/buppu3/tnCart/issues/14, abierto,
  leído el 26/10/2026): bucle de arranque en la WonderTANG 2.0b con la base
  sacada del reloj del slot (el `CLK_MEM_READY` cae durante el bootloader; es
  asunto de la variante `sync`), y además, con 27 MHz y `SYNC_CLK_EN = 0`, un
  MSX que se colgaba al arrancar Nextor, que tnCart sirve con un
  `MEGAROM_CONTROLLER` sin /WAIT; el autor da por buena una rama
  `develop-new-uma-timing` (dos commits: la conmutación del UMA sincronizada con
  el flanco de bajada del reloj de 3,58 MHz, y un ajuste para el turbo R; el
  diff no se pudo ver). Cuadra con la variante `nowait` del banco: sin /WAIT el
  dato llega tarde según la fase entre el Z80 y la ranura del canal 0. Con
  `ENABLE_MEM_WAIT = 1` la megaROM no depende de esa fase.
