# Bus y /WAIT (hito 5): nota del área

Rama `hito/bus`. Qué cambia en el bus del slot, cómo se prueba, qué se ha medido
y qué tiene que conectar la integración. Las cifras de esta nota salen del banco
`fpga/tb/bus/` (Verilator 5.020), del modelo `fpga/tb/bus/scan_model.py` y de la
comprobación de síntesis `fpga/check_bus.tcl` (Gowin 1.9.12.03); las de los
tiempos del Z80 son las cifras de Z80A del estudio y del MoonTANG, **estimadas**
(sección "Presupuestos").

## Resumen

| Parte | Fichero | Estado |
|---|---|---|
| Escaneo adaptativo del multiplexor (salto al grupo 2 con `/RD` o `/WR` filtrados) | `fpga/src/board/rev1/board_rev1_bus.sv` | hecho, banco y modelo |
| `Bus.ADDR` quieta mientras el `RD_n`/`WR_n` retrasado está a 0 (`ADDR_HOLD`) | idem | hecho, banco |
| Pre-WAIT de E/S (P#0/P#1) con vía de liberación, y de memoria (`PREWAIT_MEM_EN`) | idem | hecho, banco |
| Timeout *fail-open* de 2^12 ciclos con `WAIT_TIMEOUT` pegajosa | idem | hecho, banco |
| Guardias: `DRIVE_EN`, `BOOT_HOLD`, bus vivo, cola de `BUSDIR_n` | idem | hecho, banco |
| Rearme de 3 muestras (`served` + `idle_cnt`) | `fpga/src/cartridge_v9990.sv` | hecho, banco |
| `expansion_slot.sv` | sin cambios | — |
| Banco de bus, dos topologías, cuatro velocidades | `fpga/tb/bus/` | hecho |
| Síntesis, P&R y timing de la configuración v9990 | `fpga/check_bus.tcl` | hecho: cierra a 111,38 MHz (sección 10) |
| Placa (osciloscopio, 10^6 accesos) | — | **sin hacer**: no hay placa en esta sesión |

**Resultado** (banco, cifras de Z80A estimadas; detalle en las secciones 8 a 10):
con el slot expandido y sin él, a 3,58 y 5,37 MHz, un evento por ciclo de E/S
(cero duplicados y cero perdidos en todas las corridas), `/WAIT` en el slot a
**120 ns** como mucho del `/RD`/`/WR` del Z80 (70 en el pin; presupuesto 274 y
134 ns), datos de P#0/P#1 y P#2-6 bien, direcciones bien, timeout nunca en uso
normal, y con `bus_ok` o `DRIVE_EN` a 0 nada en el slot. Sin el pre-WAIT, el
`/WAIT` llega a 176-194 ns y a 5,37 MHz falla (variante `tncart`); sin el
rearme, los rebotes dan 65-78 eventos duplicados por corrida (mutante). A 7,16
MHz fallan, como se esperaba, las lecturas de P#0 (dato rancio) y los
presupuestos de `/WAIT`; P#2-6 siguen bien. Síntesis: +95 LUT, +17 ALU y +66 FF
en el bus frente al de `main` en la misma configuración; P&R con 0 endpoints
violados y **Fmax de `CLK_BASE` 111,38 MHz** (≥ 109), ningún camino del bus
entre los 25 peores.

## 1. Escaneo adaptativo

El escáner de tnCart recorre tres grupos del multiplexor de la WonderTANG
(`CART_MUX_CS_n`): g0 = A15-A8, g1 = A7-A0, g2 = MERQ, IORQ, CS1, CS2, RESET,
RFSH, CS12, M1 (y `SLTSL`, pin directo que se muestrea con el g2). Cada visita
son 3 ciclos de 108 MHz: uno de asentamiento después de cambiar el CS y dos
muestras (los `PIN_FILTER` piden dos muestras iguales). Vuelta: 9 ciclos,
83,3 ns.

El nuevo escáner es la misma máquina escrita como (grupo, fase); **sin saltos
es ciclo a ciclo el de 9 estados de tnCart** (estado 8 = g0 f0, 0 = g0 f1, ...
7 = g2 f2; el reset deja g0 f1 = estado 0, como antes; `scan_model.py` lo
comprueba). El salto lo da el flanco de bajada de `RD_n` o `WR_n` **filtrados**
(la salida del `PIN_FILTER`, antes de la línea de 9): el disparo se ve en el
ciclo [E0-1, E0) y se aplica en el flanco E0.

| Estado en el disparo | Qué hace | Después |
|---|---|---|
| g0 f0, g0 f1 | salta al g2 (f0 de asentamiento en [E0, E0+1), muestras en E0+2 y E0+3) | g0 → g2 → g1 → normal (el g0 se había quedado a medias) |
| g0 f2, g1 f0, g1 f1 | salta al g2 igual | g1 → g2 → normal |
| g1 f2, g2 f0, g2 f1 | nada: el g2 ya viene | normal |
| g2 f2 | alarga la f2 un ciclo sin cambiar el CS (muestras en E0 y E0+1) | g0 → g2 → g1 → normal |

El asentamiento del multiplexor no cambia: la primera muestra de un grupo es
siempre 2 ciclos (18,5 ns) después de cambiar `CART_MUX_CS_n`, como en tnCart.
Los `PIN_FILTER` no cambian (dos muestras iguales seguidas; en el g2 f2 alargado
hay tres muestras seguidas, y cada pareja igual confirma, como siempre).
`Bus.RD_n`, `Bus.WR_n`, `Bus.CLK` y `Bus.CLK_EN` no cambian (filtro + línea de 9).
`ff_addr` se sigue latcheando solo en el g2.

**Retención de saltos (`JUMP_HOLD` = 12).** Tras un salto no se acepta otro en
12 ciclos. Dos flancos de bajada de `/RD` o `/WR` de ciclos distintos del Z80
están a 2 T como poco (escritura de memoria seguida de lectura: 186 ns, 20
ciclos a 10,74 MHz), así que lo que cae dentro de la retención es un rebote del
mismo ciclo. Sin retención el escáner puede no volver nunca al g1:
`scan_model.py --barrido` recorre todas las secuencias de disparos posibles
(camino más largo en el grafo de estados) y da

| `JUMP_HOLD` | peor revisita g0 / g1 / g2 (ciclos entre parejas) |
|---|---|
| 5-6 | 22 / **no acotada** / 9 |
| 7-8 | 22 / 29 / 9 |
| 9-10 | 22 / 22 / 9 |
| **11-16** | **17 / 17 / 9** |
| ≥ 17 | 14 / 17 / 9 |

**Peor revisita de cada grupo con el salto** (`JUMP_HOLD` = 12): con un salto
aislado, **g0 14, g1 17, g2 9** ciclos (126, 157 y 83 ns); con saltos
encadenados, que solo los dan los rebotes (dos disparos a 17 ciclos, los dos en
g0 f1), **g0 17, g1 17, g2 9**. Sin saltos, 9 / 9 / 9. El banco mide lo mismo:
14 / 17 / 9 en casi todas las corridas y 17 / 17 / 9 en alguna con rebotes
encadenados (`1:60:0` a 5,37 MHz con `SEED=1`); nunca más.

**Dirección que ve el dispositivo.** El `RD_n`/`WR_n` retrasado baja en `Bus`
en el flanco E0+8. Con `ADDR_HOLD` (abajo) `ff_addr` queda quieta desde ahí, así
que la dirección del ciclo es la del último latch del g2 en un flanco ≤ E0+8.
Para un disparo en cada estado (`scan_model.py`):

| Disparo en (estado) | Latch de `ff_addr` | Pareja g0 (A15-A8) | Pareja g1 (A7-A0) | 2.ª muestra fresca del g2 | Pareja g1 en la decisión del pre-WAIT |
|---|---|---|---|---|---|
| g0 f0 (8) | E0+8 | E0+5 / E0+6 | E0-5 / E0-4 | E0+3 | E0-5 / E0-4 |
| g0 f1 (0) | E0+8 | E0+5 / E0+6 | E0-6 / E0-5 | E0+3 | E0-6 / E0-5 |
| g0 f2 (1) | E0+8 | E0-1 / E0 | E0+5 / E0+6 | E0+3 | E0-7 / E0-6 |
| g1 f0 (2) | E0+8 | E0-2 / E0-1 | E0+5 / E0+6 | E0+3 | E0-8 / E0-7 |
| g1 f1 (3) | E0+8 | E0-3 / E0-2 | E0+5 / E0+6 | E0+3 | E0-8 / E0 |
| g1 f2 (4) | E0+3 | E0-4 / E0-3 | E0-1 / E0 | E0+3 | E0-1 / E0 |
| g2 f0 (5) | E0+2 | E0-5 / E0-4 | E0-2 / E0-1 | E0+2 | E0-2 / E0-1 |
| g2 f1 (6) | E0+1 | E0-6 / E0-5 | E0-3 / E0-2 | E0+1 | E0-3 / E0-2 |
| g2 f2 (7) | E0+7 | E0+3 / E0+4 | E0-4 / E0-3 | E0+1 | E0-4 / E0-3 |

La muestra más vieja que alimenta el latch es de **E0-6**. El `/RD` del pin bajó
en (E0-3, E0-2] (el filtro necesita las muestras de E0-2 y E0-1), así que esa
muestra es 3-4 ciclos (28-37 ns) anterior al `/RD`; con los 4 ns del 74LVC245 y
1,5 del pad, la dirección tiene que estar estable en el slot unos 32-41 ns antes
del `/RD`. En E/S el Z80 la pone T - 35 ns antes con las cifras del banco (244 /
151 / 105 / 58 ns a 3,58 / 5,37 / 7,16 / 10,74 MHz): cabe siempre. En memoria,
T/2 - 35 ns (105 / 58 / 35 / 12 ns): cabe a 3,58 y 5,37, no a 7,16 ni 10,74, y
el banco lo ve así (abajo). El escáner fijo de tnCart tenía el mismo orden de
peor caso (su latch del g2 puede caer justo en E0 con la pareja del g0 de E0-7).

**Dirección que ve la decisión del pre-WAIT** (última columna). El pre-WAIT
decide con el `ff_addr` latcheado en la 2.ª muestra fresca del g2, antes de la
visita del g1 que sigue al salto, así que su A7-A0 puede ser más vieja que la
del latch final: con un disparo en g1 f0 o g1 f1 la pareja empieza en **E0-8**,
5-6 ciclos antes del `/RD` del pin; con el 74LVC245 y el pad, A7-A0 tiene que
estar estable unos 51-61 ns antes del `/RD` en el slot. En E/S hay T - 35 ns
(244 / 151 / 105 / 58 ns): cabe hasta 7,16 MHz y a 10,74 no siempre. Si no
cabe, la decisión ve la dirección del ciclo anterior (la del operando del
`IN`/`OUT`, PC+1): o el pre-WAIT espera a la siguiente visita al g2 (el banco lo
ve: como mucho 8 ciclos del `/RD` del Z80 a `pw_hold` hasta 7,16 MHz y 12 a
10,74; con `+DBGPW`, los 40 casos de 12 ciclos de `SEED=2` a 10,74, en las dos
topologías, son todos de disparos en g1 f0 o g1 f1, como dice el modelo), o, si
ese PC+1 acabara en 60h/61h, salta un pre-WAIT en un `IN`/`OUT` a otro puerto,
que se suelta por K en D+7 (unos 65 ns más de `/WAIT` en ese ciclo). Esto
último sale del modelo, no lo ha visto el banco; en cualquier caso a 10,74 MHz
el `/WAIT` no cabe en el presupuesto (-5 ns) con ni sin pre-WAIT.

**`ADDR_HOLD` (nuevo, a propósito).** `ff_addr` no se actualiza mientras el
`RD_n`/`WR_n` retrasado está a 0. El `IORQ_n` filtrado sube hasta ~10 ciclos
después del pin y el `RD_n` retrasado 11: sin la retención, la dirección del
ciclo siguiente (que el Z80 empieza a poner T/2 + 20 ns después del fin del
ciclo de E/S) puede latchearse con `IORQ_n` y `RD_n` aún a 0, y si cae en
60h-6Fh el cartucho ve un ciclo de E/S que no existe. El banco con `-GAHOLD=0`
lo muestra (tabla de variantes). Es un fallo latente del bus de tnCart, no del
salto. Como la dirección es estable mientras el `/RD` o el `/WR` del Z80 está
abajo, retenerla no cambia nada más.

## 2. Pre-WAIT

**Disparo, fuente de E/S.** Con las dos muestras del g2 tomadas después del
disparo (`fresh`), `IORQ_n` filtrado a 0, `ff_addr[7:0]` en `PREWAIT_IO_BASE`
con la máscara `PREWAIT_IO_MASK` (60h/61h: P#0 y P#1, los dos puertos en los que
el tiny9990 baja `/WAIT`, sección 6) y `RD_n` o `WR_n` filtrados a 0, `/WAIT`
sube **de nivel** al ciclo siguiente (`pw_hold`). Es la 2.ª muestra fresca de la
tabla de arriba (E0+1 a E0+3), así que `pw_hold` sube en E0+2 a E0+4: 4-7 ciclos
después del `/RD` del pin, si la decisión ya ve la dirección nueva (sección 1).
Un disparo por ciclo: se rearma con `RD_n` y `WR_n` filtrados en reposo 3
muestras seguidas.

Dos defensas contra un rebote de `/RD` o `/WR` justo después del flanco (las dos
las pidió el banco):

- un flanco de `RD_n`/`WR_n` dentro de la retención de `JUMP_HOLD` no vuelve a
  empezar la cuenta de muestras frescas (es un rebote del mismo ciclo): si no,
  el pre-WAIT esperaría a la siguiente visita al g2;
- dentro de la retención el strobe cuenta como activo aunque `RD_n`/`WR_n`
  filtrados estén a 1: un rebote de 2 muestras a ~30 ns del flanco dejaba
  `RD_n` a 1 justo cuando llegaban las muestras frescas y retrasaba el disparo
  2 ciclos (87 ns en el pin, 137 en el slot: fuera de los 134 ns de 5,37 MHz).
  Los strobes que piden pre-WAIT duran 1,5 T + 5 ns como poco (el `/RD` de un
  M1 o el de E/S: 15,6 ciclos a 10,74 MHz), más que el salto y la retención,
  así que esto no da por vivo un strobe acabado. Para la fuente de memoria solo
  vale si el salto vino de `RD_n` (`trig_rd`): el `/WR` de memoria dura T + 5 ns
  y sí puede acabar antes.

**Fuente de memoria (MegaRAM), `PREWAIT_MEM_EN` = 0 por defecto.** Igual, con
`SLTSL` y `MERQ` confirmados, `IORQ_n` a 1 y `RD_n` a 0 (solo lecturas de
memoria de nuestra ranura primaria).

**Mantenimiento y liberación.** `pw_hold` sigue a 1 hasta lo primero de:

1. el `WAIT_n` de la cadena (`Bus.WAIT_n`, el de los cartuchos) ha bajado y
   vuelto a subir: el caso normal;
2. ese `WAIT_n` no ha bajado `PREWAIT_K` ciclos (`PREWAIT_MEM_K` en memoria)
   después de que el evento llegue a `Bus` por el camino retrasado: el puerto es
   de otro, el core está en reset...;
3. `RD_n` y `WR_n` filtrados en reposo 3 muestras seguidas: fin del ciclo o
   falso disparo. Un rebote de 2 muestras no lo suelta. Sin esta vía cada falso
   disparo costaría el timeout (38 µs).

**K, del pipeline real.** Con el `RD_n`/`WR_n` retrasado bajando en `Bus` en el
flanco D (= E0+8: filtro de 2 muestras + línea de 9):

| Paso | Con `EXPANSION_SLOT` (`USE_FF` = 1) | Sin él |
|---|---|---|
| `Secondary.RD_n` registrado en el slot | D+1 | — |
| `CSR_n`/`CSW_n` registrado en `CARTRIDGE_V9990` | D+2 | D+1 |
| `WAIT_n` del core (registro sobre `det_r`/`det_w`, `t9990_port.sv`) | D+3 | D+2 |
| `Primary.WAIT_n` registrado en el slot = `Bus.WAIT_n` de la placa | **D+4** | **D+2** |

`pw_k` cuenta los ciclos con el evento ya en `Bus` y sin `WAIT_n` de la cadena:
si `Bus.WAIT_n` baja en D+n, el pre-WAIT no se suelta por K mientras n ≤ K. Con
**K = 6** quedan 2 ciclos de margen con el slot expandido y 4 sin él. El banco
mide la cadena en cada acceso a P#0/P#1 (línea "cadena" del informe): D+4 y
D+2. `PREWAIT_MEM_K` = 7 sale del contrato de la MegaRAM (abajo): ella ve la
lectura en D+1, baja su `WAIT_n` como mucho 3 ciclos después (D+4) y el slot lo
registra (D+5): 2 ciclos de margen. La MegaRAM de mentira del banco lo hace en
el límite del contrato y el banco mide D+5.

**Contrato con la MegaRAM** (para `PREWAIT_MEM_EN` = 1): baja `Bus.WAIT_n` (el de
su `BUS_IF`) como mucho 3 ciclos después de ver la lectura por el camino
retrasado (`Bus.RD_n`, `SLTSL_n`, `MERQ_n` de su interfaz) y lo mantiene hasta
que `Bus.DOUT` tiene el dato. Si no lo baja, el pre-WAIT se suelta en D+8 (en
E/S, con K = 6, en D+7): unos 75 ns después de que llegue el evento, y la
lectura no se alarga más que eso.

## 3. Rearme de 3 muestras (`cartridge_v9990.sv`)

Patrón `served` + `idle_cnt` de `v9990_cpu_glue.v` de la MSXimus Z:

- `CSR_n`/`CSW_n` bajan en la primera muestra con el ciclo de E/S a nuestros
  puertos y `served` pasa a 1 (mismo ciclo que antes: el core ve el flanco en el
  mismo sitio);
- se sueltan en la primera muestra sin el ciclo (el core solo mira el flanco de
  bajada, `t9990_port.sv`: `det_r = prev_csr_n && !CSR_n`);
- `served` solo se borra con `Bus.RD_n` y `Bus.WR_n` en reposo 3 muestras
  seguidas. Un rebote de `RD`/`WR` que pase el `PIN_FILTER` (2 muestras: un
  pulso de 2 ciclos en `Bus`) o uno de `IORQ` (que con el multiplexor dura una
  vuelta, 9 ciclos, con `RD`/`WR` quietos) no presenta otro flanco al core.

Diferencia con el glue de la Zynq: allí el reposo se mide sobre el chip-select
entero (`io_any`); aquí sobre `RD_n`/`WR_n` solos, porque un rebote de `IORQ` en
el multiplexor dura 9 ciclos y rearmaría.

El bus de datos se conduce mientras `served` marque una lectura: un rebote de
`IORQ` o uno de 2 muestras de `RD` ya no deja el bus sin dato a mitad de la
lectura (antes `BUSDIR_n` seguía a `cs_n`). La cola de 2 ciclos de más que eso
da a `Bus.BUSDIR_n` no llega al slot (guardia de cola, abajo). `Bus.BUSDIR_n`
baja además un ciclo después que en tnCart, sin coste: el core carga `CD_OUT` en
el flanco que sigue al de `CSR_n` (`det_r`) y `Bus.DOUT` lo recoge un flanco más
tarde, así que el dato nuevo llega a `Bus.DOUT` en el mismo flanco que antes; lo
que se ahorra es el ciclo en que tnCart sacaba el `CD_OUT` anterior.

Límite: un rebote de 3 muestras o más (≥ 28 ns con `/RD` arriba) es para el bus
un ciclo nuevo y el core ve un segundo acceso. El banco solo inyecta 1 y 2.

## 4. Timeout fail-open

`wtmo` cuenta los ciclos con la espera lógica (`pw_hold || !Bus.WAIT_n`) sujetando
el pin; a 2^12 (37,9 µs a 108 MHz; el banco mide 38,0) suelta el `/WAIT` del slot
y sube `WAIT_TIMEOUT`, pegajosa hasta el reset del sistema. El contador vuelve a
0 en cuanto la espera lógica cae, así que el acceso siguiente vuelve a tener
`/WAIT`. No cuenta con `BOOT_HOLD` a 1 (la retención de arranque no tiene
timeout y no debe encender el LED), ni con `bus_ok` o `DRIVE_EN` a 0 (el pin no
sale). `DRIVE_EN` y `BOOT_HOLD` entran al contador por dos flops cada una.

La espera más larga en uso normal que ve el banco es de 225 ciclos (2,08 µs de
`/WAIT` en el pin, pre-WAIT y cadena incluidos; P#0 en P1 con la pantalla
encendida): el timeout está a 18 veces eso.

## 5. Guardias de salida

| Salida al slot | Ecuación (combinacional en los pines) |
|---|---|
| `CART_DATA_SIG`, `CART_DATA_DIR`, `CART_BUSDIR_n` | conducir = `bus_ok && DRIVE_EN && drv_ok && !CART_RD_n && !Bus.BUSDIR_n` |
| `CART_INT_n` | `bus_ok && DRIVE_EN && !Bus.INT_n` (con la polaridad de cada placa) |
| `CART_WAIT_n` (1 = el NPN baja `/WAIT`) | `BOOT_HOLD \|\| (bus_ok && DRIVE_EN && (pw_hold \|\| !Bus.WAIT_n) && !timeout)` |

- **`bus_ok`** (como `moontang_core.sv`, bloque `ck_alive`): flancos del
  `CART_CLOCK` filtrado (los dos flancos) en una ventana de 2^18 ciclos (2,43 ms);
  con ≥ 64 el reloj del slot está vivo (a 3,58 MHz hay ~17 400 por ventana), y
  además `/RESET` del slot (filtrado, g2) suelto. Sube al final de la primera
  ventana con reloj y cae como mucho dos ventanas después de que el reloj pare
  (el banco: 2,43 ms al arrancar; 2,5-4,7 ms al parar el reloj). Es un flop de
  `CLK_BASE` con reset asíncrono por `RESET_n`: si el PLL pierde el lock, el
  reset del sistema lo pone a 0 sin reloj.
- **`DRIVE_EN`** y **`BOOT_HOLD`** entran directas a la lógica de los pines: la
  integración las calcula en el dominio de 27 MHz para que valgan aunque
  `CLK_BASE` no corra.
- **Guardia de cola (`DRIVE_TAIL_GUARD`, nueva, a propósito).** `Bus.BUSDIR_n`
  llega por el camino retrasado (~14 ciclos tras el `/RD` del pin) y sigue a 0 ese
  tiempo, y 2 ciclos más con el rearme, tras el fin de la lectura. El M1 que sigue
  a un `IN` baja su `/RD` T - 5 ns después del fin del `IN` (9,5 ciclos a
  10,74 MHz, 14,5 a 7,16): sin la guardia la placa conduciría el dato viejo contra
  la memoria del MSX. `drv_arm` solo deja conducir en una lectura que empezó con
  `Bus.BUSDIR_n` en reposo; se desarma con `RD_n` filtrado en reposo 3 muestras.
  Con el bus de tnCart el choque ya existía a 10,74 MHz (variante `tncart` del
  banco).

## 6. Lo que hace el chip real (fuentes)

- **Manual de aplicación del V9990 (Yamaha, E-VDP-III)**, capítulo 5 "Pin
  description" (p. 5): `/WAIT` es una salida en drenador abierto que "becomes
  active (Low) while VDP is busy" en las lecturas y escrituras de la CPU; `/CSW`:
  el dato de D7-0 entra "at the rise of this signal". Capítulo 13.3.5 "CPU-VDP
  interface" (p. 91, tabla de 13 filas): **tdWCS, retardo de `WAIT` desde
  `CSR`/`CSW`, 60 ns como máximo**; tdaCSR (acceso al dato desde `CSR`) 100 ns;
  tdaWT (acceso al dato desde `WAIT`) 0 ns; twhCS (`CSR`/`CSW` en alto) ≥ 5 TC;
  tcCS (ciclo de `CSR`/`CSW`) ≥ 8 TC (372 ns con TC = 1/21,477 MHz). Capítulo 7
  (p. 10): P#5 solo lectura; P#7 y los puertos de dirección baja del kanji (P#8,
  P#A) solo escritura. Comprobado en las páginas del PDF escaneado.
- **openMSX** (`src/video/v9990/V9990.cc`, copia de la rama master bajada el
  26/10/2026): no modela `/WAIT` (`V9990::readIO` y `V9990::writeIO` devuelven o
  escriben en el acto, sin estados de espera; el fichero no nombra ninguno); la
  lectura de P#0 sale de un búfer de prelectura (comentario de `V9990::peekIO`:
  "V9990 fetches from read buffer instead of directly from VRAM"), y los puertos
  del kanji devuelven FFh (`peekIO`).
- **tiny9990** (`fpga/v9990/tiny9990/t9990_port.sv`): baja `WAIT_n` un ciclo
  después del flanco de `CSR_n`/`CSW_n` en P#0 y P#1 y lo sube con el dato
  (`vram_cd_update`/`palette_cd_update`). Es la fuente que usa este bus.

Lo que consigue el bus en `/WAIT`, frente a los 60 ns del chip: 70 ns del `/RD`
del Z80 al pin `CART_WAIT_n`, más el transistor (50 ns supuestos).

## 7. Presupuestos (Z80A, estimados)

Cifras del banco (las del estudio y el MoonTANG): dirección a 110 ns del flanco
de T1; `/IORQ` a 70 y `/RD`/`/WR` a 75 ns de la subida de T2 en E/S; `/MREQ` y
`/RD` a 70/75 ns de la bajada de T1 en memoria; `/WAIT` muestreado en la bajada
de TW (de T2 en memoria) con 70 ns de setup; dato en la bajada de T3 con 50 ns.
Son retardos máximos fijos: el banco no barre los mínimos. NPN: 50 ns en entrar,
300 en soltar con el pull-up del MSX (supuestos).

| Z80 | T | `/WAIT` en E/S (1,5 T - 145) | dato de E/S (2,5 T - 125) | `/WAIT` en memoria (T - 145) |
|---|---|---|---|---|
| 3,58 MHz | 279,4 ns | 274 ns | 573 ns | 134 ns |
| 5,37 MHz | 186,2 ns | 134 ns | 340 ns | 41 ns |
| 7,16 MHz | 139,7 ns | 65 ns | 224 ns | -5 ns |
| 10,74 MHz | 93,1 ns | -5 ns | 108 ns | -52 ns |

## 8. Banco (`fpga/tb/bus/`)

| Fichero | Qué es |
|---|---|
| `tb_bus.sv` | Z80 (M1 con refresco, lecturas y escrituras de memoria y de E/S, `OUT (n),A`, `IN A,(n)`, `OTIR`) a 3,58 / 5,37 / 7,16 / 10,74 MHz contra la placa: tres 74LVC245 multiplexados por `CART_MUX_CS_n` (4 ns de reloj a pad, 6 ns de habilitación con basura mientras conmuta, 4 ns de propagación, 1,5 ns de pad), el transceptor de datos, el NPN de `/WAIT` y los pines directos |
| `sdram_host_model.sv` | la VRAM: sustituye a `sdram.sv` por su comportamiento visto desde el UMA, ciclo a ciclo (acepta en IDLE, dato en IDLE+6/+7, ACK en IDLE+7, 9 ciclos), con el `UMA` real (DIV 30, libre) |
| `megaram_mock.sv` | MegaRAM de mentira para `PREWAIT_MEM_EN` = 1, en el límite del contrato |
| `dpb_sim.sv` | modelo de la DPB de Gowin para compilar el core |
| `scan_model.py` | modelo del escáner (revisitas, tabla de latch y de la decisión del pre-WAIT) |
| `run.sh` | compila y corre la matriz en WSL |
| `resumen.py` | tabla Markdown con lo esencial de los logs (la de la sección 9) |
| `syn_rsc.py` | recursos por módulo del `_syn_rsc.xml` de Gowin (sección 10) |

DUT: `BOARD_REV1_BUS` + `EXPANSION_SLOT` (`USE_FF` = 1) + `CARTRIDGE_V9990` +
`T9990` (el core de tnCart del repositorio) — topología 0 —, o sin
`EXPANSION_SLOT` — topología 1 —. Casos de `run.sh`: `0:60:0` y `1:60:0` (V9990
en 60h), `0:70:0` y `1:70:0` (V9990 en 70h: nadie contesta en 60h/61h, prueba la
liberación del pre-WAIT por K) y `0:60:1` (MegaRAM de mentira y
`PREWAIT_MEM_EN` = 1).

Fases: registros (R#16 por P#3/P#4) y lecturas de P#2/P#5/P#6; VRAM por P#0 con
`OUT` seguidos (11 T por byte) y con `OTIR` (21 T), escritura y relectura contra
una sombra; paleta por P#1 (64 colores x 3, con `OUT` y con `OTIR`, leída
después; con G = B, porque el tiny9990 sin parches de este repositorio devuelve
B al leer G, el parche del área del core); puertos y memoria ajenos (98h, 40h, FFh, 5Fh, ...); registro de
subranuras FFFFh (memoria de nuestra ranura, solo topología 0); rebotes de 1 y 2
muestras en `/RD`, `/WR` e `/IORQ` en P#0, P#3 y P#5 en un momento aleatorio
del ciclo; `/RD` y `/WR` de 1 y 2 muestras sin ciclo de E/S con 60h en el bus;
MegaRAM; `/INT` y guardias (`DRIVE_EN`, `BOOT_HOLD`, `/RESET` del slot, reloj
del slot parado); timeout (60 µs con `BOOT_HOLD` y la cadena en espera, después
sin `BOOT_HOLD`). La fase de `/RD` frente al reloj de 108 MHz recorre todos los
valores porque los dos relojes no guardan relación (el histograma de saltos por
estado del escáner sale en el informe).

Comprueba: un evento (flanco de `CSR_n`/`CSW_n` en el cartucho) por ciclo de E/S
a nuestros puertos y ninguno en los demás, con su MODE y su dato; la dirección,
`IORQ`/`MERQ` en `Bus` al llegar el `RD_n`/`WR_n` retrasado, en E/S, en nuestra
memoria y en la ajena (M1 y memoria del MSX); `/WAIT` en el slot dentro del
presupuesto en P#0/P#1 y que no se active dentro del setup del Z80; el dato
leído en la bajada de T3 (2,5 T - 125) y su estabilidad en la ventana de setup;
la latencia de la cadena (para K); que la placa no conduzca D0-D7 sin una
lectura legítima, ni 30 ns después de subir `/RD`, ni contra la memoria del MSX;
el timeout (nunca en uso normal; a 38 µs forzado; nunca con `BOOT_HOLD`); `/INT`;
y con `bus_ok` = 0 o `DRIVE_EN` = 0, datos, `/INT` y `/WAIT` en reposo.

Criterio por velocidad (`BUS_OK` / `BUS_FAIL` al final del log):

- siempre: eventos, dirección de E/S, conducción, timeout, guardias, `/INT`,
  cadena ≤ K, escrituras de registros, escrituras por `OTIR` a P#0/P#1 (21 T
  entre bytes: 5,9 µs a 3,58 MHz, 1,96 a 10,74, más que los 1,62 µs que el
  estudio da a la espera más larga) y puertos ajenos;
- a 3,58 y 5,37: todo lo de E/S y de memoria, con las direcciones de memoria
  (también la ajena); en los ciclos con rebote de `/RD` o `/WR`, dato y `/WAIT`;
  con rebote de `/IORQ`, solo a 3,58 (a 5,37 es un fallo esperado, abajo);
  MegaRAM solo a 3,58 (su presupuesto a 5,37 son 41 ns);
- a 7,16: lecturas de P#2-6; fallos esperados (no cuentan): lecturas de
  P#0/P#1, `OUT` seguidos a P#0/P#1 (11 T = 1,54 µs, menos que 1,62 µs; en las
  corridas no ha fallado ninguna, pero no están garantizadas) y memoria de
  nuestra ranura;
- a 10,74: además, lecturas de P#2-6 (108 ns de presupuesto frente a 148 ns).

Uso (desde Git Bash o WSL):

```
fpga/tb/bus/run.sh                         # matriz completa, N = 120 por fase, SEED = 1
N=60 SEED=2 fpga/tb/bus/run.sh 0:60:0      # un caso
HZS="5369318" fpga/tb/bus/run.sh 1:60:0    # una velocidad
GEN="-GAHOLD=0" TAGX=sinahold fpga/tb/bus/run.sh 0:60:0   # variante
git show main:fpga/src/cartridge_v9990.sv > fpga/tb/bus/out/cart_main.sv
CART_SV="$PWD/fpga/tb/bus/out/cart_main.sv" TAGX=sinrearme fpga/tb/bus/run.sh 0:60:0 1:60:0   # mutante sin rearme
EXTRA=+DBGPW fpga/tb/bus/run.sh 0:60:0     # traza de los pre-WAIT lentos
python3 fpga/tb/bus/scan_model.py [--barrido]
```

Logs en `fpga/tb/bus/out/` (ignorado por git); objetos en `~/.tb_bus_obj` (disco
de WSL).

## 9. Resultados del banco

Corridas: matriz completa con `SEED=1 N=120` y con `SEED=2 N=60` (esta con
`+DBGPW`), 5,37 MHz con `SEED=3 N=200` en `0:60:0`, `1:60:0` y `0:60:1`, y
3,58 y 5,37 MHz con `SEED=4 N=120` en `0:60:0` y `1:60:0`. La implementadora
anterior las corrió con el RTL y el banco de `1c412bc`; en esta sesión se han
repetido todas con el RTL de `ef19224` (el mismo, más un comentario; después
solo cambian comentarios del RTL, y `1:60:0` a 5,37 MHz repetido al final sale
igual) y el banco de `0e504bd` (solo añade la traza `+DBGPW`), y los logs de las dos matrices y de
las variantes salen **idénticos línea a línea** a los de entonces (el banco es
determinista con la misma semilla; las únicas líneas nuevas son las de
`+DBGPW`). **Todas dan `BUS_OK`**; a 3,58 MHz sin ningún fallo, ni esperado; a
5,37 los únicos fallos (esperados) son los ciclos con rebote de `/IORQ`
(sección 12) y la MegaRAM de mentira (41 ns de presupuesto). La tabla es la de
`SEED=1` (`resumen.py`); `OK*` = con los fallos esperados de esa velocidad.

| Caso | MHz | Veredicto | `/WAIT` en el slot, P#0/P#1, peor (presupuesto), ns | Lect. P#0 mal | Lect. P#2-6 mal | Duplicados / perdidos | Direcciones mal: E/S / nuestra memoria / memoria ajena | Cadena | Rebote de `/IORQ` con dato mal |
|---|---|---|---|---|---|---|---|---|---|
| `0:60:0` | 3,58 | OK | 120 (274) | 0/269 | 0/334 | 0/0 | 0 / 0 / 0 de 5 380 | D+4 | 0 |
| `0:60:0` | 5,37 | OK* | 120 (134) | 0/274 | 0/329 | 0/0 | 0 / 0 / 0 de 5 428 | D+4 | 1 |
| `0:60:0` | 7,16 | OK* | 120 (65) | 240/274 | 0/329 | 0/0 | 0 / 0 / 514 de 5 476 | D+4 | 13 |
| `0:60:0` | 10,74 | OK* | 158 (-5) | 238/271 | 328/332 | 0/0 | 0 / 23 / 3 295 de 5 410 | D+4 | 21 |
| `1:60:0` | 3,58 | OK | 120 (274) | 0/273 | 0/330 | 0/0 | 0 / — / 0 de 5 366 | D+2 | 0 |
| `1:60:0` | 5,37 | OK* | 120 (134) | 0/271 | 0/332 | 0/0 | 0 / — / 0 de 5 312 | D+2 | 2 |
| `1:60:0` | 7,16 | OK* | 120 (65) | 239/266 | 0/337 | 0/0 | 0 / — / 511 de 5 228 | D+2 | 11 |
| `1:60:0` | 10,74 | OK* | 158 (-5) | 240/264 | 337/339 | 0/0 | 0 / — / 3 173 de 5 234 | D+2 | 20 |
| `0:60:1` | 3,58 | OK | 120 (274) | 0/267 | 0/336 | 0/0 | 0 / 0 / 0 de 5 350 | D+4, MegaRAM D+5 | 0 |
| `0:60:1` | 5,37 | OK* | 120 (134) | 0/279 | 0/324 | 0/0 | 0 / 0 / 0 de 5 536 | D+4, MegaRAM D+5 | 1 |
| `0:70:0`, `1:70:0` | 3,58-10,74 | OK / OK* | sin dispositivo en 60h/61h: ráfaga de `/WAIT` de 13-15 ciclos, nunca el timeout | — | — | 0/0 | a 7,16 y 10,74, solo memoria ajena | — | — |

Además, en todas las corridas del hito: P#1 (paleta) bien hasta 7,16 MHz; las
escrituras de registros y las de `OTIR` a P#0/P#1 bien a todas las velocidades;
la espera más larga en uso normal, 225 ciclos (2,08 µs); el pre-WAIT
sube como mucho 8 ciclos después del `/RD`/`/WR` del Z80 hasta 7,16 MHz (12 a
10,74); revisita g0 14 / g1 17 / g2 9 (17/17/9 en un caso con rebotes
encadenados); `RD`/`WR` de 1-2 muestras sin ciclo de E/S: nunca `/WAIT`;
ninguna conducción de D0-D7 sin lectura legítima, tarde o contra la memoria del
MSX; `bus_ok` sube a los 2,43 ms y cae entre 2,5 y 4,7 ms después de parar el
reloj del slot; con `BOOT_HOLD` 60 µs de espera sin cortes y sin
`WAIT_TIMEOUT`; sin él, el timeout suelta a los 38,0 µs.

**Lo que arregla cada parte** (variantes del banco, `SEED=1 N=40`, `0:60:0` y
`1:60:0`):

| Variante | Qué quita | 3,58 | 5,37 | 7,16 / 10,74 |
|---|---|---|---|---|
| `tncart` (`-GSCAN=0 -GPWIO=0 -GAHOLD=0 -GTAILG=0`) | todo menos guardias y timeout: el bus de tnCart | OK, `/WAIT` a 194 ns (176 sin slot) | **falla**: `/WAIT` a 194 ns (176) frente a 134, 80 de 92 lecturas de P#0 mal, un evento duplicado | **falla**: 342-344 conducciones de D0-D7 sin lectura legítima, 342 choques con la memoria del MSX a 10,74, 2 duplicados a 7,16 sin slot |
| `sinsalto` (`-GSCAN=0`) | el salto (el pre-WAIT espera a la visita normal al g2) | OK, 167 ns | **falla**: 167 ns, 46 de 96 lecturas de P#0 mal | — |
| `sinahold` (`-GAHOLD=0`) | la retención de `ff_addr` | OK | **falla**: 2 eventos de más (MODE equivocado) en las dos topologías | **falla**: 1 evento de más a 7,16 sin slot; 3 eventos de más y 2 conducciones sin lectura legítima a 10,74 con slot |
| `sincola` (`-GTAILG=0`) | la guardia de cola | OK | OK* | **falla**: 343 conducciones sin lectura legítima (el M1 tras un `IN`), 340 choques a 10,74 |
| sin rearme (mutante: `cartridge_v9990.sv` de `main` con el bus del hito; `SEED=1 N=120`, 3,58 / 5,37 / 7,16) | el rearme de 3 muestras | **falla**: 65 y 76 eventos duplicados (con y sin slot) | **falla**: 72 y 78 duplicados | **falla**: 75 y 67 duplicados a 7,16 |

A 3,58 MHz el bus de tnCart, con las guardias, pasa el banco: el hito 5 no
cambia lo que ya funcionaba en placa a esa velocidad. El mutante sin rearme no
es un parámetro del RTL: `run.sh` compila el banco con el `cartridge_v9990.sv`
de `main` en lugar del del hito (`CART_SV`, sección 8). Los duplicados empiezan
en la fase de rebotes y no hay ninguno antes: con el `CSR_n <= Bus.RD_n ||
cs_n` de tnCart, un rebote de 2 muestras de `/RD`, `/WR` o `/IORQ` presenta un
segundo flanco al core.

## 10. Síntesis (`fpga/check_bus.tcl`)

`check_bus.tcl` es `build_v9990_xtal.tcl` (configuración `v9990`, variante
`xtal`, con el bootloader de `main`) con el bus de este árbol y el top parcheado
al vuelo en `impl/check_bus_src/` (el top es de la integración): `DRIVE_EN` =
`reset_n` del top (registro de `CLK_BASE_READY` y `sdram_ready`), `BOOT_HOLD` =
0, `WAIT_TIMEOUT` en OR con el LED para que la síntesis no lo barra y `BUS_OK`
suelto. **No es un bitstream para la placa.** Con `CHECK_BUS_REF=1` sintetiza
el bus y el cartucho de `main` (solo síntesis) para comparar. Gowin
1.9.12.03, GW2AR-LV18QN88C8/I7, `syn` + `pnr` (place 2, route 1), 26/10/2026.

**Síntesis** (`impl/gwsynthesis/*_syn_rsc.xml`, `fpga/tb/bus/syn_rsc.py`):

| Módulo | Hito 5 (LUT / ALU / FF / BSRAM) | `main` en la misma configuración | Diferencia |
|---|---|---|---|
| `u_bus` (`BOARD_REV1_BUS`) | 146 / 17 / 179 / 0 | 51 / 0 / 113 / 0 | **+95 LUT, +17 ALU, +66 FF** |
| `u_v9990` (`CARTRIDGE_V9990` + core) | 8 681 / 747 / 4 813 / 18 | 8 700 / 748 / 4 809 / 18 | -19 LUT (ruido), +4 FF (`served`, `served_rd`, `idle_cnt`) |
| top | 11 632 / 2 182 / 6 242 / 24 | 11 565 / 2 166 / 6 173 / 24 | +67 LUT, +16 ALU, +69 FF |

El `u_bus` de referencia del estudio (53 LUT / 125 FF) es el de la build `full`
de tnCartWonder; en la configuración `v9990` el mismo bus de `main` sintetiza a
51 / 113, y esa es la comparación limpia. Las 17 ALU son los contadores nuevos
(ventana de 2^18 de bus vivo, timeout de 2^12). El estudio estimaba ~120 LUT
para todo el bus; salen 95 LUT + 17 ALU. La síntesis de referencia se ha
repetido en esta sesión y su `_syn_rsc.xml` sale idéntico byte a byte al de la
sesión anterior.

**P&R** (`tools/check_build.py fpga/impl/pnr/check_bus --parcial --ref-logic 14140
--ref-cls 8696 --ref-bsram 24 --tol 0.01 --max-cls 9331 --warn-cls 9250 --rpll 2
--fmax CLK_BASE=109 --log ... --sdc fpga/constraints/v9990_xtal.sdc`):
**PUERTA PARCIAL: PASA**.

| | Hito 5 (`check_bus`) | Hito 1 (`v9990_xtal`, `fpga/reports/hito1/`) |
|---|---|---|
| Lógica (LUT + ALU) | 14 223 (68,6 %) | 14 140 |
| CLS | 8 713 (84,0 %) | 8 679 |
| Registros | 6 242 | 6 173 |
| BSRAM / PRIMARY / rPLL | 24 / 8 de 8 / 2 de 2 | igual |
| Endpoints violados (setup, hold) | 0, 0 | 0, 0 |
| Peor holgura de setup / hold / recovery / removal | 0,281 / 0,074 / 3,535 / 0,588 ns | 0,092 ns de setup |
| **Fmax `CLK_BASE`** | **111,38 MHz** (mínimo 109) | 109,08 MHz |

Las 16 órdenes del `.sdc` salen activas, el modelo de `DCLK` se cumple (+0,167
ns) y el único aviso del P&R es el PR1014 de `CLK_27M_d` que ya tenía el hito 1.
**Ningún camino de `u_bus` está entre los 25 peores de setup** (`report_timing
-setup -max_paths 25 -max_common_paths 1`): son todos del core (sprites, blitter,
generador de bitmap), y el 25.º tiene 1,351 ns de holgura, así que todo camino
que acaba en el bus tiene al menos eso (Fmax > 126 MHz para el bus). La
diferencia de Fmax con el hito 1 es del P&R (el camino crítico es del core en las
dos), no del bus. Los pines del slot siguen sin `set_input_delay` ni
`set_output_delay`, como en el hito 1: la ruta combinacional hasta
`CART_WAIT_n`, `CART_DATA_DIR` y `CART_INT_n` no la analiza el STA (el banco
mide 70 ns de `/RD` a `CART_WAIT_n` con un retardo de FPGA supuesto de 4 ns).

## 11. Cambios de interfaz y lo que tiene que hacer la integración

`BOARD_REV1_BUS` tiene **cuatro puertos nuevos**, que la instancia `u_bus` de
`fpga/src/tnCart_board_wt200b_top.sv` hoy no conecta (el top es de la
integración):

| Puerto | Dir. | Qué conectar |
|---|---|---|
| `DRIVE_EN` | entrada | la guardia de lock: PLL enganchado y sistema listo, en el dominio de 27 MHz (en `hito/integ`, `BOARD_WT200B_GUARD.DRIVE_EN_27`). **Sin conectar o a 0, el cartucho no saca nada al slot.** |
| `BOOT_HOLD` | entrada | retención de arranque, de 27 MHz y con tope propio de tiempo (en `hito/integ`, `BOOT_HOLD_27`, 50 ms): saca `/WAIT` sin mirar `bus_ok` ni `DRIVE_EN` y sin timeout, así que **tiene que estar acotada en la integración** (si no, un PLL sin enganchar dejaría el MSX congelado) |
| `WAIT_TIMEOUT` | salida | pegajosa, al LED |
| `BUS_OK` | salida | informativa (LED o depuración); se puede dejar sin conectar |

- **La retención del arranque tiene que ir por `BOOT_HOLD`.** En `main` el MSX
  queda retenido mientras corre el bootloader porque `EXPANSION_SLOT`, en reset
  (`SYS_RESET_n` = 0), saca `Primary.WAIT_n` = 0 (`expansion_slot.sv`, rama
  `!RESET_n` del bloque `USE_FF`) y porque el `WAIT_n` del bootloader entra en el
  slot. Con este bus esa retención llega a los pines como espera lógica: pasa por
  `bus_ok && DRIVE_EN`, y si `DRIVE_EN` estuviera a 1 el timeout la cortaría a
  los 38 µs y encendería `WAIT_TIMEOUT` en cada arranque. Con `DRIVE_EN` = 0
  mientras el sistema no está listo el contador no corre y no sale; la
  retención la da entonces `BOOT_HOLD`. Es lo que ya hace `hito/integ` (leído en
  su worktree: `DRIVE_EN_27` no sube hasta que sube `SYS_RESET_n`, y la
  retención es `BOOT_HOLD_27`, según el comentario de su `main.sv`). En el
  bitstream sin slot expandido no hay otra retención que `BOOT_HOLD`.
- En `hito/integ`, el bloque marcado `FUSION hito/bus` del top (y
  `BOARD_WT200B_BUS_GUARD`, que hace el mismo gateo sin `bus_ok`, sin la guardia
  de cola y sin timeout) se sustituye por `.DRIVE_EN(drive_en_27)`,
  `.BOOT_HOLD(boot_hold_27)` y `.WAIT_TIMEOUT(wait_timeout)` en `u_bus`, con
  `.Bus(Bus)`; es lo que dice su propio comentario.
- `fpga/check_bus.tcl` parchea el top de `main` al vuelo (sección 10); con el
  top de la integración ya conectado sobra, o hay que quitarle el parche.
- **Parámetros nuevos** de `BOARD_REV1_BUS`, todos con el valor del hito por
  defecto: `ADAPTIVE_SCAN` (1), `PREWAIT_IO_EN` (1), `PREWAIT_IO_BASE` (60h),
  `PREWAIT_IO_MASK` (FEh), `PREWAIT_K` (6), `PREWAIT_MEM_EN` (0),
  `PREWAIT_MEM_K` (7), `WAIT_TMO_BITS` (12), `ALIVE_WIN_BITS` (18),
  `ALIVE_MIN_EDGES` (64), `JUMP_HOLD` (12), `DRIVE_TAIL_GUARD` (1),
  `ADDR_HOLD` (1). Con `ADAPTIVE_SCAN` = `PREWAIT_IO_EN` = `ADDR_HOLD` =
  `DRIVE_TAIL_GUARD` = 0 el bus es el de tnCart con las guardias de salida y el
  timeout: es la vuelta atrás si algo del escáner falla en placa. Si el V9990 se
  mueve de 60h (`IO_BASE_ADDR` de `CARTRIDGE_V9990`), `PREWAIT_IO_BASE` tiene que
  ir con él.
- **MegaRAM** (bitstream `v9990_megaram`): `PREWAIT_MEM_EN` = 1 **solo** con una
  MegaRAM que cumpla el contrato de la sección 2. La de `hito/megaram` con
  `ENABLE_MEM_WAIT` = 1 lo cumple según su nota (`docs/notas/megaram.md`,
  apartado 4, leída en su worktree sin fusionar: `Bus.WAIT_n` del top en D+3,
  menos que `PREWAIT_MEM_K` = 7, y sube con el dato en `Bus.DOUT`). Con la
  megaROM de tnCart sin `/WAIT`, dejarlo a 0: toda lectura de memoria de
  nuestra ranura primaria (también los M1 de la ROM cargada) llevaría un
  pre-WAIT que nadie alarga y que se suelta por K en D+8; a 3,58 MHz eso puede
  costar un TW de más (el banco lo ve en el registro FFFFh y en las subranuras
  vacías: hasta 1). Con el contrato cumplido, el pre-WAIT de memoria cabe a
  3,58 MHz y no a 5,37 (41 ns de presupuesto con las cifras del banco; el
  modelo de `hito/megaram`, con otros supuestos del Z80, pide un pre-WAIT a ≤ 4
  ciclos del `/RD` del pin, y este sale a 4-8).
- `CARTRIDGE_V9990`: sin cambios de puertos. `Bus.BUSDIR_n` dura 2 ciclos más
  tras el fin del ciclo retrasado (no llega al slot).
- `.sdc`: no hace falta nada nuevo (ningún reloj nuevo; el bus sigue sin
  `set_input_delay`/`set_output_delay`, como en el hito 1). `DRIVE_EN` y
  `BOOT_HOLD` de 27 MHz entran a dos sincronizadores de `CLK_BASE` (los del
  timeout): el cruce lo cubre el `set_clock_groups` entre el grupo de 27 MHz y el
  de `CLK_BASE`.
- Para la documentación del repositorio (de la integración): la fila "Bus" de
  `docs/ARCHITECTURE.md` (escáner adaptativo, pre-WAIT, guardias), el banco en
  `docs/VERIFICATION.md` y la nota de velocidad de `docs/WONDERTANG.md` (el
  pre-WAIT cabe a 5,37 MHz).

## 12. Límites conocidos y riesgos

- **Turbo**: garantizado (en el banco) a 3,58 y 5,37 MHz con cifras de Z80A; a
  5,37 el margen de `/WAIT` en el slot es de unos 14 ns con 50 ns supuestos para el
  NPN. A 7,16 MHz las lecturas de P#0 fallan (P#1 no, la paleta contesta en un
  periodo de DCLK) y las escrituras a P#0/P#1 con cadencia menor que la espera
  más larga del core no están garantizadas (`OTIR` sí, bucles de `OUT (n),A`
  no): el estudio estima 1,62 µs y el banco ve `/WAIT` de hasta 2,08 µs en el pin
  (unos 2,0 µs del core), aunque ninguna escritura seguida se ha perdido en las
  corridas. P#2-P#6 sí a 7,16. A 10,74 MHz tampoco P#2-P#6, y `OTIR` (1,96 µs
  entre bytes) queda justo. Las CPU de las máquinas turbo (Z80B/H, R800) tienen
  otros retardos: hay que medirlo.
- **Rebote de `/IORQ` justo en la visita rápida**: el filtro no confirma `IORQ` y
  el pre-WAIT espera a la siguiente visita al g2 (3-9 ciclos más; `/WAIT` en el
  slot hasta 203 ns): a 5,37 MHz ese ciclo puede salirse del presupuesto y leer
  dato rancio. El banco, que inyecta estos rebotes a propósito en las muestras
  del g2, lo ve en 0 a 2 lecturas de P#0 por corrida a 5,37 MHz (semillas 1 a
  4, 60 a 200 accesos por fase). A 3,58 MHz cabe. La tarea pide `IORQ` "confirmado" (dos
  muestras) para el disparo; aceptar una sola muestra lo evitaría a cambio de
  pre-WAIT falsos con un pico de `IORQ`.
- **Rebotes de 3 muestras o más** son un ciclo nuevo (sección 3).
- **A7-A0 de la decisión del pre-WAIT a 10,74 MHz** (sección 1): la decisión
  puede ver la dirección del ciclo anterior; a lo sumo retrasa el pre-WAIT o mete
  ~65 ns de `/WAIT` en un `IN`/`OUT` ajeno. Hasta 7,16 MHz cabe.
- **Dirección de memoria a 7,16 MHz o más**: el latch puede llevar la dirección
  anterior (con las cifras del banco la del Z80A solo es válida T/2 - 35 ns antes
  de `/RD`). Afecta a la MegaRAM en turbo, no al V9990 (en E/S la dirección está
  T - 35 ns antes). A 5,37 MHz el banco deja 58 ns frente a los 32-41 que pide el
  latch, pero con retardos máximos fijos: con el `/RD` más temprano de una CPU
  real el margen es menor y no está comprobado: no hay en local una tabla de
  tiempos de Zilog legible (la sesión anterior no pudo leer el PS0178, una
  imagen escaneada, y en esta no se ha descargado ningún otro). La MegaRAM en
  turbo hay que medirla.
- **`CART_WAIT_n` combinacional** (LUT de varias entradas): un pico de un
  ciclo en un cambio simultáneo de dos entradas no se puede descartar; el NPN
  (decenas de ns) lo filtra. Registrarlo costaría 9 ns de pre-WAIT.
- El banco usa retardos fijos (máximos) del Z80A, no barre mínimos ni el
  sesgo entre `/IORQ` y `/RD`; si `/IORQ` bajara más de ~14 ns después de `/RD`,
  la visita rápida no lo vería y el pre-WAIT llegaría una visita tarde.
- La VRAM del banco es un modelo de `sdram.sv`, no el controlador real con la
  SDRAM.
- **Sin probar en placa.** Lo que falta: osciloscopio en `/RD`, `/WAIT` y
  `CART_MUX_CS_n` (`/WAIT` bajo ≤ 125 ns tras `/RD`), 10^6 accesos a P#0 a 3,58 y
  a 5,37 MHz, y un arranque con el LED de `WAIT_TIMEOUT` apagado.
