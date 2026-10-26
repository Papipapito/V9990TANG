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
Verilator, un banco del host que corre el `tncrom` real contra un modelo en C
del cartucho y reproduce sus trazas de bus contra el RTL, openMSX (solo
`tncrom` sin cartucho) y una síntesis con P&R.

La primera tanda de este hito se cortó por un límite de sesión con todo
commiteado hasta `4560abf`; la segunda (26/10/2026, mañana) volvió a correr sus
pruebas (banco, `tncrom` en openMSX, síntesis con P&R), amplió `tncrom` a Konami
de 2 MB (apartado 6) y el banco con esa máscara (apartado 7), ensayó Another
World en openMSX (apartado 10) y corrigió esta nota donde decía de más. La
tercera (26/10/2026, tarde) partió del trabajo sin commitear de la segunda:
pasó el modelo del Z80 del banco a los supuestos del área bus (con ellos **el
pre-WAIT de memoria es imprescindible también a 3,58 MHz**, apartado 4), acabó
el banco del host de `tncrom` (`tools/tncrom/test/`) y la variante del banco
que reproduce sus trazas (apartado 7), añadió una comprobación de simulación de
`RAM_IF_EXPANSION_USES_FF` (apartado 4) y volvió a correr todo: banco, openMSX y
síntesis con P&R.

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
con `romBase / 0x2000`, es decir, desplazamiento = dirección; las páginas
fuera de la imagen quedan sin mapear (`setUnmapped`: una de 48 KB deja
C000h-FFFFh sin respuesta, como PLAIN0, y una de 32 KB deja además
8000h-BFFFh, donde se lee FFh). PLAIN0 contesta siempre en todo
`0000h-BFFFh`, mida lo que mida la imagen, así que **`tncrom` r3 rellena con
FFh hasta 48 KB** las imágenes menores (apartado 6): lo que la imagen no cubre
lee FFh como en openMSX, y no la SDRAM (basura de encendido pasados los 32 KB
del borrado, o la ROM anterior con su cabecera "AB" en 4000h, que la BIOS
tomaría por la de la demo). La diferencia que queda es que ahí la megaROM
conduce el bus y pide /WAIT; el valor leído es el mismo. Solo lectura: `RomBlocks` no redefine
`writeMem` y el de `MSXDevice` no hace nada ("write to unmapped memory, do
nothing"). Releído en el `master` de openMSX el 26/10/2026.

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
  cargar otra ROM: `tncrom` no encuentra el cartucho (lo dice el mensaje),
  tampoco con `-S` (desde r3 comprueba el cartucho también con el slot
  explícito; antes leía en 3Eh un byte de la demo como tamaño de la ventana y
  daba "complete." sin haber cargado nada).
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
  = 1`, más el flop del controlador), en todas las lecturas a 3,58 y 5,37 MHz;
  a 7,16 MHz 3-4, cuando `MERQ`/`SLTSL` llegan al `Bus` después que el `RD`
  retrasado (desde ellos sigue siendo 1 ciclo en el puerto).
- **Lo mantiene hasta que `Bus.DOUT` tiene el dato**: espera a que el
  `ACK_n` del canal 0 baje (el UMA lo baja en el flanco siguiente a `OE_n` = 0)
  y vuelva a subir (el UMA lo sube en el mismo flanco en que carga
  `Secondary[0].DOUT`). En el ciclo en que ve `ACK_n` = 1, `mem_wait_req` cae y,
  en el flanco siguiente, `Bus.WAIT_n` sube **en el mismo flanco en que
  `Bus.DOUT` carga `Ram.DOUT[7:0]`**. Un `ACK_n` ya bajo al empezar (escritura o
  refresco anteriores aún en curso) no adelanta la liberación: el UMA no lo sube
  mientras quede la lectura pendiente (`save_oe` en `req_any`).
- **Eso pide `RAM_IF_EXPANSION_USES_FF = 0`** (el valor de
  `config/v9990_megaram.sv` y de tnCart). Sin flops en `EXPANSION_RAM` el UMA ve
  el `OE_n` del controlador en el ciclo siguiente a que este pase a esperar el
  `ACK_n` (`det_oe`), y `det_any` tiene prioridad sobre el fin del acceso
  anterior (`uma.sv`, "ACK_n 更新"): un `ACK_n` bajo que el controlador vea en ese
  primer ciclo ya no vuelve a subir hasta el fin de la lectura. Con flops habría
  dos ciclos más en los que el acceso anterior podría acabar y subir `ACK_n`
  antes de que el UMA viera la lectura: el controlador lo tomaría por el fin de
  la suya y soltaría el WAIT con el dato viejo. No se ha simulado ese caso;
  `cartridge_megarom.sv` da un `$error` de simulación si alguien junta
  `ENABLE_MEM_WAIT = 1` con `RAM_IF_EXPANSION_USES_FF = 1`.
- Del WAIT suelto al fin de la lectura el dato no cambia (lo vigila el banco).
- Solo lecturas: las escrituras no piden /WAIT (el UMA las guarda al ver el
  flanco de `WE_n`). Las lecturas del SCC (9800h/B800h) también esperan a la
  SDRAM, como en tnCart, aunque el dato salga del SCC. Las de los registros
  (`0000h-003Fh`, fuera de PLAIN0), del `FFFFh` y de las páginas que no son de
  la megaROM no piden /WAIT.

Cifras del banco (108 MHz): del `Bus.RD_n` retrasado a `Bus.WAIT_n` alto con
el dato, **15 a 34 ciclos (139-315 ns)** según la fase de la lectura frente a
la ranura del canal 0 (hasta 51 ciclos con un refresco inyectado en el mismo
canal; 53 con el UMA de `hito/sdram`). Del /RD del pin al /WAIT del pin, **14
ciclos (130 ns)** solo con la cadena (filtro 2 + línea de 9 + tres flops), 8 con
el modelo de pre-WAIT del banco.

**`!RFSH_n` en `rd_n`.** En el camino retrasado el `RD_n` de un M1 sigue bajo
unos ciclos (línea de 9) cuando `MERQ_n` ya ha vuelto a bajar para el refresco
con la dirección I:R. Si esa dirección cae en la ventana (página 0 en PLAIN0, o
un registro I entre 40h y BFh), tnCart lanzaba una lectura de la SDRAM, y con
`ENABLE_MEM_WAIT` sería además un /WAIT espurio. `MERQ_n` y `RFSH_n` se
muestrean juntos (grupo 2 del mux), así que basta con añadir `!Bus.RFSH_n` a la
condición de lectura. El banco cuenta los refrescos que sin esa condición
habrían sido lecturas: 0 en todas las variantes con los supuestos del Z80 de la
tercera tanda; con los de antes, 16 a 7,16 MHz.

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

Medido con el **modelo** de pre-WAIT del banco (disparo a `PW_DLY` = 4 ciclos
del RD filtrado: /WAIT en el pin 8 ciclos, 74 ns, después del /RD del pin; se
suelta como el de `hito/bus`) y, desde la tercera tanda, **con los supuestos del
Z80 del banco del área bus** (`docs/notas/bus.md` de `hito/bus`, apartado 7:
`/RD` a 75 ns de la bajada de T1, `/WAIT` con 50 ns de NPN y 70 de setup antes
de la bajada de T2; apartado 7 de esta nota). Cifras del 26/10/2026 por la
tarde, 253 lecturas comprobadas por el Z80 en cada variante:

| Variante | MHz | Qué cambia | Lecturas mal leídas o sin esperar |
|---|---|---|---|
| `wait` | 3,58 | /WAIT + pre-WAIT a 8 ciclos | **0** (estricta) |
| `noprewait` | 3,58 | solo la cadena (/WAIT en el pin a 14 ciclos, 130 ns) | **71** |
| `wait_rd9` / `wait_rd10` | 3,58 | `/RD` 1 / 2 ciclos más tarde (83 / 93 ns) | 1 / 73 |
| `noprewait_opt` | 3,58 | solo la cadena con los supuestos de antes (`/RD` a 46 ns, NPN 30) | 0; con `/RD` un ciclo más tarde, 54 |
| `nowait` | 3,58 | sin `ENABLE_MEM_WAIT` (tnCart) | 71 |
| `turbo5` / `turbo5i` | 5,37 | pre-WAIT a 8 / 4 ciclos | 240 / 240 (47 lecturas acaban con el WAIT aún bajo) |
| `turbo7` | 7,16 | pre-WAIT a 8 ciclos | ver el apartado 7 |

Conclusiones, todas de un modelo y no de la placa:

- A **3,58 MHz** el pre-WAIT de memoria de `hito/bus` es **imprescindible**: la
  cadena sola (filtro de 2, línea de 9 y los tres flops hasta `Bus.WAIT_n`)
  pone el /WAIT en el pin a 130 ns del /RD y el presupuesto, con NPN, es de unos
  84 ns. Con el pre-WAIT a 74 ns el margen es de **un ciclo de 108 MHz** (9 ns):
  con `/RD` 9 ns más tarde ya falla una lectura y con 18 ns, 73. Hasta la
  tercera tanda esta nota decía que la cadena sola llegaba: era con un `/RD` a 46
  ns y 30 ns de NPN, y aun así con margen 0.
- A **5,37 MHz** no llega ningún pre-WAIT con estos supuestos, ni uno ideal a 4
  ciclos (37 ns) del /RD: el presupuesto de /WAIT en memoria es T − 145 = 41 ns
  desde el /RD del Z80 hasta su pin /WAIT (nota del área bus, apartado 7), menos
  que el NPN solo. Con los supuestos de antes un pre-WAIT a ≤ 4 ciclos daba 0
  fallos. La nota del área bus llega a lo mismo: su banco solo da por buena la
  MegaRAM a 3,58. Depende sobre todo del retardo de `/RD` y del NPN supuestos
  (retardos máximos de un Z80A): con un Z80 más rápido o un NPN más rápido
  cambia, y solo la placa lo dirá.

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

**Con este hito la semántica de `ACK_n` y `DOUT` del canal 0 pasa a ser parte
de la interfaz del UMA**, y la nota de `hito/sdram` dice lo contrario: su tabla
"Interfaces: qué cambia" (`docs/notas/sdram.md` de `hito/sdram` `b04ba1a`,
fila `ACK_n` del canal 0) da "nada para la megaROM (no mira el ACK)". Desde
`hito/megaram` la megaROM sí lo mira: con `ENABLE_MEM_WAIT = 1` el estado del
/WAIT avanza con `Ram.ACK_n` (`MW_ACK_LOW`/`MW_ACK_HIGH` en
`megarom_controller.sv`) y `mem_wait_req` sale de él. Lo que ese cambio de
`hito/sdram` hace (un R/W aplazado una ranura por la escalación, o por un
RFSH que llega junto a un R/W, alarga el `ACK_n` 20 ciclos) es compatible: el
/WAIT dura 20 ciclos más y sigue soltándose con el dato. Lo que **no** se
puede cambiar sin romper el /WAIT de memoria, y que la integración tiene que
escribir en `ARCHITECTURE.md` como contrato del UMA para el canal 0:

1. `ACK_n` baja después de que el UMA vea `OE_n` = 0 y no sube mientras quede
   pendiente la lectura de ese cliente (`save_oe` en `req_any`);
2. `ACK_n` sube **una sola vez** por lectura y **en el mismo flanco** en que
   `Secondary[0].DOUT` carga el dato de esa lectura, nunca antes;
3. `Secondary[0].DOUT` solo cambia al acabar un R/W del canal 0 (no tras un
   RFSH: lo cumple el `uma.sv` de `hito/sdram`, no el de `main`).

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
  bit 7 del banco 3 en SCC+), aunque openMSX lo decodifica en 9800h-9FFFh y
  B800h-BFFFh y tnCart solo en 98xxh y B8xxh (`scc_cs_n` mira `ADDR[15:8]`;
  sin cambiar, es de tnCart). Releído en `MSXSCCPlusCart.cc` el 26/10/2026, igual
  que el registro de modo de arriba. ASCII16 coincide con
  `src/memory/RomAscii16kB.cc` (registros en 6000h-67FFh y 7000h-77FFh, los
  dos bancos a 0 tras el reset; tnCart usa la máscara F800h).
- Al encender, los bancos también valen 0, 1, 2, 3 aunque el /RESET del MSX se
  suelte antes que `DONE`: la rama `!RESET_n` del controlador los pone a 0, pero
  `EXPANSION_SLOT` sale de su reset con `Secondary.RESET_n = 0` al menos un
  ciclo y el controlador pasa entonces por `!Bus.RESET_n`, que carga
  `BankRegInit`. Leído en el RTL y así lo supone el modelo del banco del host;
  el banco de Verilator no lo distingue (los cuatro bancos caen en los 32 KB
  borrados).

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
reproducible (dos builds, mismo binario). Los ganchos del banco del host (abajo)
no cambian el binario: con ellos `build.sh` da el mismo `TNCROM.COM` byte a byte
(comprobado con `cmp` el 26/10/2026 por la tarde).

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
binario de `bfc5748` (r2), dos veces (mañana y tarde: los 17 ficheros de salida
salen idénticos, y el de MSX-DOS 1 igual): Philips NMS 8250 con una Sunrise IDE de Nextor 2.1.4
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
En openMSX **la carga real no se puede probar** (no tiene la megaROM de tnCart):
la cubren el banco del host y la reproducción de sus trazas contra el RTL
(abajo y apartado 7). En la placa sigue sin probar.

**Banco del host** (`tools/tncrom/test/`, gcc 13 en WSL):

```
wsl -e bash -lc "cd /mnt/c/<repo>/tools/tncrom/test && ./run.sh"
# -> ~/.cache/v99tang_tncrom_test/test_tncrom.log y tncrom_{plain0,ascii16,scci}.trc
```

Compila `src/` y `lib/` de `tncrom` tal cual para el host, con
`TNCROM_HOST_TEST` y `-include host_types.h` (los anchos de SDCC: `uint32_t` de
32 bits), y corre su `main()` contra `host_mock.c`, que sustituye lo que
`tncrom` pide a la BIOS y al DOS: `RDSLT`/`WRSLT`/`ENASLT` + `LDIR`, `EXPTBL`,
el BDOS (ficheros en memoria, `_DOSVER`) y `reboot()`. Slots: 0 la BIOS, 1
expandido con la megaROM en 1-0, 2 vacío, 3 expandido con RAM en 3-0. La megaROM
del modelo sigue el RTL regla a regla (llave, `cs_reg_rd_n`/`cs_reg_wr_n`,
lectura de 00h-3Fh, PLAIN0, `cs_mem_n`, `wr_mem_n`, registros de banco con
`BankRegAddrMask`/`BankEnable`, `addr_16`/`addr_8`/`addr_plain`, el modo SCC-I
de BFFEh y la rama `!Bus.RESET_n`), con el orden del RTL dentro de una
escritura (la RAM con los bancos de antes). Ganchos en `tncrom`, todos tras
`TNCROM_HOST_TEST`: `EXPTBL()` en `main.c` en lugar de leer FCC1h a mano, el
búfer de 8 KB como array y las llamadas a la BIOS de `lib/rom_tools.c` hacia el
modelo; además dos casts a `unsigned long` en los `printf` de `%lu` (en SDCC no
cambian nada). 71 comprobaciones, todas bien el 26/10/2026:

- ayuda y errores de línea de órdenes y de tamaño (PLAIN0 de 48 KB + 1, vacío,
  tipo desconocido, ASCII16 de 4 MB + 1 KB, KONAMI y ASCII8 de 2 MB + 1 KB, 32K
  de 49 KB, fichero que no existe, MSX-DOS 1) **sin ninguna operación con el
  cartucho**, y la ventana de 3 MB (3Eh = C0h, la de tnCart) frente a una imagen
  de 4 MB: `rom image too large for the cartridge: 4096KB, window 3072KB.`;
- PLAIN0 de 48 KB: atributo (`flags` C3h, 1Fh = 01h), ventana = imagen, lectura
  lineal de 0000h-BFFFh, C000h sin respuesta, la llave y las escrituras no hacen
  nada, un segundo `tncrom` no encuentra el cartucho, el /RESET borra PLAIN0 y
  ENABLE, `-R` reinicia con PLAIN0 activo y sin el aviso, `-O`;
- ASCII16 de 40 KB (dos páginas, protección, /RESET con y sin `-O`) y de 4 MB
  (los 256 bancos, FFh y 80h); KONAMI de 512 / 513 KB / 2 MB con la máscara
  3Fh / 7Fh / FFh en 0Dh y los bancos FFh y 41h; KONAMI_WO_SCC y ASCII8 de 2 MB
  (FFh); KONAMI_SCC_I de 32 KB (BFFEh = 00h deja los cuatro bancos protegidos,
  10h todo RAM como hace SofaRun); 32K (banco 1 = 1 tras /RESET) y `-N`.

Lo que enseñó: `tncrom` escribe un byte fuera de la imagen. Pone el banco 0 en
el último antes de cargar (`xfer_file`) y cada escritura al registro de banco 1
(7000h, página 1, sin protección) cae también en ese banco en +3000h; si la
imagen acaba antes (último banco incompleto: la de 40 KB) ahí queda el número
del último banco. Está fuera de la imagen y no molesta; es de upstream y no se
ha cambiado.

Tres casos dejan su traza de bus con la megaROM desde el encendido (`W aaaa dd`,
`R aaaa dd` con el dato que dio el modelo, `Z` para el /RESET): PLAIN0 (148 543
operaciones), ASCII16 de 40 KB (82 589) y KONAMI_SCC_I de 32 KB (33 241). La
variante `tncrom` del banco de Verilator las reproduce contra el RTL (apartado
7).

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

**Supuestos del Z80** (parámetros `D_ADDR`, `D_CTRL`, `D_WAIT`, `D_DATA`, en
ciclos de 108 MHz): desde el 26/10/2026 por la tarde, los del banco del área bus
(`docs/notas/bus.md` de `hito/bus`, apartado 7, "retardos máximos fijos,
estimados"): dirección a 110 ns de la subida de T1 (12 ciclos), `/MREQ` y `/RD`
a 75 ns de la bajada de T1 (8), `/WAIT` visto con 50 ns de NPN y 70 de setup
antes de la bajada de T2 (13) y dato con 50 de setup más el transceptor (6).
Hasta entonces el banco suponía `/RD` a 46 ns (5) y 30 ns de NPN (11), y con
eso la cadena del /WAIT sola llegaba. `EXTRA_G="-GD_CTRL=9"` cambia los
supuestos en todas las variantes.

**Variante `tncrom`** (`TRACE = 1`): en lugar del programa, tras el borrado,
lanza el banco del host de `tools/tncrom/test` (apartado 6) y reproduce sus tres
trazas desde el encendido: cada `W` es una escritura del Z80 por el bus, cada `R`
una lectura (una de cada ocho como M1, con su refresco) que tiene que dar en el
RTL el dato que dio el modelo en C, cada `Z` un /RESET; páginas 0-2 en el
cartucho. Es el `tncrom` real contra el RTL real, con el monitor del /WAIT
activo. `TRACE` es un parámetro y no solo el plusarg `+TRACE=` porque con las
dos ramas vivas Verilator 5.020 inlinea el programa entero y el C++ del módulo
pasa de 0,5 a 24 MB (una compilación de más de 20 minutos que se cortó). La
primera pasada encontró una falsa alarma del monitor: `msx_reset` baja /RESET
nada más acabar una lectura en el pin, cuando en el camino retrasado aún no ha
acabado, y `EXPANSION_SLOT` pone en reposo el bus del cartucho; el Z80 ya había
tomado el dato. Desde entonces el monitor no mira la estabilidad del dato con
/RESET bajo.

Resultados del 26/10/2026 por la tarde: `run.sh` sin argumentos sobre `6f20c51`,
las trece variantes PASA (las tres trazas de `tncrom` incluidas); las `*_hito4`
con el `uma.sv` de `hito/sdram` `cbf65ea`, md5 `0738833e`. Las variantes de
medida del /WAIT (`noprewait`, `noprewait_opt`, `wait_rd9`, `wait_rd10`,
`nowait`, `turbo5`, `turbo5i`) están en la tabla del apartado 4.

| Variante | Qué | Resultado |
|---|---|---|
| `wait` | estricta, 3,58 MHz, /WAIT + modelo de pre-WAIT | 241 lecturas de la megaROM, todas con WAIT; 0 errores; VRAM: 13 012 lecturas, 0 malas, 0 ranuras perdidas; borrado en 163 837 ciclos (1,52 ms), 8192 escrituras |
| `tncrom` | estricta, las trazas del `tncrom` real | PLAIN0: 147 834 escrituras y 706 lecturas (652 de la megaROM, todas con WAIT), 3 /RESET; ASCII16: 82 172 y 415 (382), 2 /RESET; KONAMI_SCC_I: 32 897 y 344 (328). 0 errores; el canal 1 sin ranuras perdidas en 905 000, 507 000 y 209 000 lecturas |
| `wait_hito4` | estricta, con el `uma.sv` de `hito/sdram` | 0 errores; borrado en 165 937 ciclos (1,54 ms) |
| `inj_hito4` | estricta, refresco inyectado en el canal 0 a +0..+30 ciclos | 0 de 31 lecturas rompen el contrato (liberación 15-53 ciclos) |
| `inj_main` | medida, igual con el UMA de `main` | 8 de 31 rompen el contrato (defecto del UMA, apartado 4; eran 7 con los supuestos del Z80 de antes) |
| `turbo7` | medida, 7,16 MHz | no significativa con estos supuestos: el `/RD` de un Z80A (75 ns) cae después de la subida de T2 (semiperiodo de 70 ns) y el modelo del Z80 alarga el ciclo un T; además el `BOARD_REV1_BUS` de `main` entrega 20 de 241 lecturas con la dirección anterior (la nota del área bus da la memoria de nuestra ranura a 7,16 MHz como fallo esperado). 11 lecturas mal contadas |

En todas: `Bus.RD_n` → `Bus.WAIT_n` del top 3 ciclos (3-4 a 7,16 MHz, donde
`MERQ`/`SLTSL` llegan a veces después que el `RD` retrasado), `rd_mem_n` →
`WAIT_n` del puerto 1 ciclo, `Bus.WAIT_n` sube con `Bus.DOUT` válido a los
15-34 ciclos del `Bus.RD_n` (139-315 ns; hasta 51-53 con un refresco inyectado),
y ninguna lectura de 3,58 MHz con otra dirección en el camino retrasado.

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
en las fechas (el P&R es determinista). Y una tercera vez en la tercera tanda
(26/10/2026, 14:46-15:22, con el árbol final: el único cambio de RTL desde la
anterior es el `$error` de simulación de `cartridge_megarom.sv`, fuera de la
síntesis): otra vez `check_megaram_syn_rsc.xml` idéntico byte a byte y el
`.rpt.txt` y el `.tr` idénticos salvo las líneas con fecha. La base no se volvió
a compilar (sus cifras de lógica y registros son las del estudio, exactas):

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
  9 111 / 29, ±1 %, y los límites de CLS del hito 1, `--max-cls 9331
  --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109`): **PASA** (vuelta a pasar
  sobre la build de la tercera tanda, con las mismas cifras). Lógica +0,56 %, CLS −0,34 %, BSRAM igual,
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
  `cartridge_megarom.sv` tiene que definirlo. Con `ENABLE_MEM_WAIT = 1`,
  `RAM_IF_EXPANSION_USES_FF` tiene que seguir a 0 (apartado 4; lo vigila un
  `$error` de simulación).
- **`hito/bus`**: activar `PREWAIT_MEM_EN = 1` en la configuración MegaRAM
  (con `PREWAIT_MEM_K = 7`; el /WAIT de la megaROM llega al top a los 3 ciclos).
  **No es opcional**: con los supuestos del Z80 del propio banco del área bus,
  sin pre-WAIT la cadena del /WAIT llega tarde también a 3,58 MHz (variante
  `noprewait`, apartado 7). Para turbo, ver las cifras del apartado 4.
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
  que Another World V9990 pide un turbo R. Para VERIFICATION.md: las pruebas
  de este hito son `fpga/tb/megaram/run.sh` (Verilator; la variante `tncrom`
  necesita además gcc y lanza `tools/tncrom/test/run.sh`) y
  `fpga/check_megaram.tcl`; `tools/tncrom/build.sh` rehace `TNCROM.COM`.
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
- **Margen del /WAIT a 3,58 MHz**: con los supuestos de Z80A del área bus el
  pre-WAIT llega con un ciclo de 108 MHz de margen (apartado 4). Si en la placa
  el `/RD` del Z80 o el NPN son más lentos de lo supuesto, la MegaRAM leerá mal
  sin que nada lo avise: es lo primero que hay que mirar con el osciloscopio.
- Turbo: con el /WAIT de memoria el contrato se cumple, pero con estos
  supuestos a 5,37 MHz no llega ningún pre-WAIT (apartado 4) y a 7,16 MHz el bus
  de `main` además entrega direcciones a destiempo (apartado 7). Sin probar en
  placa.
- `tncrom -R` con PLAIN0 depende de que el registro `FFFFh` tenga las páginas 0
  y 2 en la subranura 0 cuando arranca la demo: WOLF3D y WIREFRM no lo tocan
  (apartado 2).
- El banco del host de `tncrom` usa un modelo en C del cartucho escrito a mano
  desde el RTL. Lo que se compara con el RTL de verdad son las lecturas de las
  tres trazas (1 465, todas iguales); las imágenes grandes (4 MB, 2 MB) y los
  KONAMI de más de 512 KB solo pasan por el modelo, porque reproducir 4 M
  escrituras por el Z80 del banco de Verilator llevaría horas. Y es el `tncrom`
  compilado con gcc, no el binario de SDCC: lo que dependa del compilador o del
  ensamblador (convenio de llamada, `xfer_memory`, la pila en la página 3) solo
  lo prueban openMSX (sin cartucho) y la placa.
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
