# Hito 4: refresco y SDRAM

Rama `hito/sdram`, desde `main` (`20936e6`, hito 1). Ficheros tocados:
`fpga/src/peripheral/ram/uma.sv`, `fpga/src/peripheral/ram/sdram.sv`, el banco
`fpga/tb/sdram/` y `fpga/check_sdram.tcl` (comprobación de síntesis).
`ram.sv` no cambia: no hacía falta.

Qué funciona, en una frase: el UMA genera su propio AUTO REFRESH en el canal 0
(en el peor caso, con el canal 0 ocupado en todas sus ranuras, 1580 ciclos entre
refrescos: 14,63 µs a 108 MHz y 14,71 µs a 107,386 MHz; el primer intervalo tras
la inicialización llega a 1584 ciclos, 14,67 y 14,75 µs; 6,5-7,9 µs en los
regímenes reales), el RFSH de un cliente ya no se pierde ni sale junto a un
R/W, y la inicialización de `sdram.sv` manda los dos AUTO REFRESH que pide
JEDEC. Todo comprobado en simulación; **nada de esto se ha probado en la
placa** (no tengo acceso a ella).

La cadencia no cambia: `DIV = 30`, una ranura cada 10 ciclos alternando canal 0
y canal 1, accesos de 9 ciclos en `sdram.sv`, dato listo antes del siguiente
`exec_timing`. El banco lo comprueba en cada ranura (comprobación `slot`) y mide
que el canal 1 (V9990) recibe el ACK 12 ciclos después de su `EXEC` en todas
las ranuras y en todos los regímenes, igual que con el UMA del hito 1.

**Fuentes.** Las afirmaciones sobre el V9990 son del **tiny9990** (fichero:línea);
ninguna de las que usa el diseño depende de cómo se comporta el chip real.
Sobre el chip real hay dos fuentes, y no dicen lo mismo de la VRAM en standby:

- **Manual del V9990** (Yamaha, *V9990 E-VDP-III Application Manual*, sección
  12.2 "Register specifications", página 80, R#6, bits DSPM1-DSPM0; copia de
  `map.grauw.nl/resources/video/yamaha_v9990.pdf`, página 86 del PDF):
  `11` = "Stand-by mode (non-display, no VRAM refresh, kanji ROM readable)". El
  chip real **no refresca** su VRAM en standby. El tiny9990 hace lo mismo: con
  `DSPM = STANDBY` no pide ningún `RAM_RF` (`t9990_timing.sv:543-546`). De
  DISP = 0 (R#8, página 81) el manual solo dice que se ve el color de fondo.
- **openMSX** no modela ninguna pérdida de VRAM. En `src/video/v9990/V9990.cc`
  (master `a557de7`, 25/10/2026) la VRAM solo se borra en `powerUp` (líneas
  123-125), y al entrar en el reset del sistema por el puerto `SYSTEM_CONTROL`
  el comentario dice que en un MSX real ni la paleta ni la VRAM se borran
  (líneas 374-380). En todo `src/video/v9990/` la única mención de standby es
  `V9990.hh:270`, sobre el ancho de la imagen ("standby TODO check this"); nada
  de refresco.

**Decisión: la VRAM se conserva en todos los modos, también en standby.** Es
más de lo que garantiza el chip real (su VRAM es DRAM y sin refresco se pierde
pasado el tiempo de retención, que el manual no da) y es lo que hace openMSX.
Motivos: el AUTO REFRESH no distingue regiones (cada uno refresca una fila, la
que marca el contador interno de la SDRAM: `WonderTANG-ref/fpga/src/sdram.v:17-21`),
así que no se puede dejar sin refresco la VRAM y refrescar el resto, y en la
misma SDRAM viven, en otras configuraciones, la MegaRAM (en 0) y Nextor (en
`70_0000h`), que no pueden perderse por que el V9990 entre en standby; el
estudio pone como puerta del hito 4 que la VRAM sobreviva 1 h en standby; y no
conozco ningún programa que dependa de perder la VRAM en standby (tampoco
podría depender de ello: el tiempo de retención no está especificado). Es una
desviación consciente del chip real, y la integración debería apuntarla en
`docs/ARCHITECTURE.md` junto a las demás.

Las afirmaciones sobre la SDRAM se apoyan en el controlador de nand2mario para
la misma SDRAM embebida (`msx/WonderTANG-ref/fpga/src/sdram.v`), en
`wv_to_sdram.v` del MoonTANG y en el modelo `sdram_model.v` del MoonTANG.

## Qué cambia

### 1. Refresco interno en el UMA (canal 0)

Problema (estudio, sección 5): la SDRAM pide 4096 AUTO REFRESH en 64 ms, uno
cada ~15,6 µs (`WonderTANG-ref/fpga/src/sdram.v:17-21`). En tnCart los aporta el
`/RFSH` del Z80 que reenvían la RAM y la megaROM (`megarom_controller.sv:309`,
`:326`, `:345`). El tiny9990 pide un `RAM_RF` por línea y ninguno en STANDBY
(`t9990_timing.sv:543-546`: con `DSPM = STANDBY`, `MEM.STATE = RAM_XX`). El
banco lo mide con el UMA del hito 1: intervalo máximo de 63,3 µs con el V9990
activo (uno por línea de 6840 ciclos) y ningún refresco en standby. Un cartucho
solo V9990 se queda sin refresco.

Cómo funciona (`uma.sv:255-343`):

- `rf_age` (12 bits, satura en 4095) cuenta los ciclos desde el último AUTO
  REFRESH que el UMA presentó a `Primary`, de cualquier fuente: interno, RFSH
  del canal 0 o `RAM_RF` del canal 1 (`ref_issue`, `uma.sv:295`). Cada vez que
  sale uno vuelve a 0. Es decir, el temporizador se rearma con cualquier
  refresco: con el `/RFSH` del Z80 reenviado casi no hace falta el interno. En
  esto se aparta del MoonTANG, cuyo temporizador corre libre y pide un
  refresco cada 781 ciclos pase lo que pase (`wv_to_sdram.v:112-129`): allí el
  puente es el único que refresca; aquí hay otras dos fuentes, y contar desde
  el último refresco de cualquiera de ellas es lo que acota el intervalo.
- Con `REFRESH_CYCLES` = 780 ciclos sin refresco se levanta `int_req` (el
  `REFRESH_CYCLES` de `MoonTANG/fpga/src/wv_to_sdram.v:40`): 7,22 µs a 108 MHz
  y 7,26 µs a 107,386 MHz. Se sirve en la primera ranura `exec_timing[0]` sin
  R/W pendiente del canal 0 (`int_issue`, `uma.sv:293`). Nunca en
  `exec_timing[1]`: el banco lo comprueba en cada ciclo (`int_slot`).
- Con `REFRESH_ESC` = 1560 ciclos (dos periodos) sin refresco se levanta
  `int_esc` (y `int_req`, por si los parámetros fueran otros). El refresco
  interno gana entonces al R/W del canal 0 de esa ranura (`defer_rw[0]`,
  `uma.sv:399`). El R/W se queda en `save_oe`/`save_we` y sale en la ranura
  siguiente del canal 0, 20 ciclos después. Como `rf_age` vuelve a 0, cada
  refresco aplaza como mucho un R/W.
- El refresco interno no pasa por `processing`, `done_ch`, `proc_rw`,
  `Secondary[0].DOUT` ni los `ACK_n`: solo lo tocan `int_req`, `int_esc` y
  `rf_age`. Si pasara por `done_ch`, diez ciclos después copiaría en
  `Secondary[0].DOUT` la última lectura del canal 1, y la megaROM la pondría en
  el bus del Z80 (`megarom_controller.sv:323`, `:342`). El banco lo demuestra
  con un mutante (control `neg_mut_dout`, más abajo).
- Si coincide con un RFSH pendiente del canal 0, sale un solo AUTO REFRESH que
  sirve a los dos. El RFSH sigue su camino normal, con `processing` y `ACK_n`, y
  cuenta como del canal 0.
- `INT_REFRESH = 0` quita el temporizador. Los arreglos 2 y 3 se quedan.
- El UMA se resetea con el `reset_n` del top, que solo depende del PLL base y
  de `READY` de la SDRAM (`tnCart_board_wt200b_top.sv:176-181`), no con el
  /RESET del MSX: el refresco interno sigue mientras el MSX está en reset. El
  banco lo modela igual (`sys_rst_n` bajo hasta `READY`).

`sdram.sv` hace el AUTO REFRESH con la misma secuencia de 9 ciclos que un R/W
(`sdram.sv:318-330`: `CMD_REF` en `STATE_ACTIVE` y NOP en el resto), así que el
refresco interno no cambia la ocupación de la ranura. Tampoco retrasa ningún
R/W del Z80: solo sale en una ranura en la que el canal 0 no tenía nada, y un
R/W que llegue un ciclo después habría esperado a la ranura siguiente igual
que en el hito 1.

Intervalo máximo entre AUTO REFRESH, por construcción:

- con ranuras libres en el canal 0: 781 a 800 ciclos;
- con el canal 0 ocupado en todas sus ranuras: `REFRESH_ESC` + 20 =
  1580 ciclos, que son 14,63 µs a 108 MHz y 14,71 µs a 107,386 MHz. La tasa
  media es entonces de 4374 refrescos en 64 ms a 108 MHz (4349 a 107,386):
  por encima de los 4096.

El banco mide exactamente 1580 ciclos de un AUTO REFRESH al siguiente con el
cliente al 100 % (`DBG_RF_MAXGAP` = 1579, el intervalo menos 1). El 1584 que
sale en la columna `gap` de algunos casos es el primer intervalo, el que va
del último REF de la inicialización al primero del UMA.

**Cómo leo "pendiente más de 2 periodos".** El encargo dice que la escalación
llega cuando la petición lleva pendiente más de 2 periodos (1560 ciclos). Leído
al pie de la letra (1560 desde que se levanta la petición, que se levanta a los
780), el intervalo llegaría a 780 + 1560 + 20 = 2360 ciclos, 21,9 µs, y eso no
cumple los < 15,6 µs con el cliente al 100 % que pide el mismo encargo. Por
eso aquí los 1560 cuentan desde el último refresco: la petición lleva entonces
un periodo pendiente y la SDRAM dos periodos sin refresco. Es lo que dice el
estudio ("escalación a dos periodos", sección 9, y en la 5: "con 840 un
refresco perdido ya pasaría de 15,6 µs"). `REFRESH_ESC` es un parámetro, por si
la integración quiere otro valor; tiene que ser ≤ 4095 porque `rf_age` satura
ahí (en simulación, un `initial` entre `translate_off` y `translate_on` avisa,
`uma.sv:317-322`).

### 2. El RFSH no sale junto a un R/W, y no se borra si no se emitió

Antes, si en una ranura coincidían R/W y RFSH del mismo canal, el UMA los
presentaba a la vez. `sdram.sv` ejecuta solo el R/W (`sdram.sv:296-330`: el
`if(begin_rd || begin_wr)` va antes que `begin_rfsh`), y el UMA borraba
`save_rfsh` igualmente: el refresco se perdía. Ahora:

- Cada ranura emite el R/W (`grant_rw`) o, si no hay R/W, el RFSH (`grant_rf`)
  (`uma.sv:396-402`, `:504-521`).
- `save_oe`, `save_we` y `save_rfsh` solo se borran cuando su operación sale de
  verdad (`uma.sv:440-462`).
- `processing` se activa solo con una operación emitida (`grant_any`,
  `uma.sv:408-413`). Sin aplazamiento es lo mismo que el `exec_timing &&
  req_any` de tnCart.

Consecuencia para un cliente que pide R/W y RFSH a la vez: su `ACK_n` sigue
bajo 20 ciclos más, hasta que sale el RFSH aplazado. Solo pasa cuando
`EXPANSION_RAM` junta dos clientes en el mismo ciclo. El Z80 no lo produce: su
`/RFSH` cae en T3 del M1, al menos dos estados T después del flanco de `/RD`, y
para entonces la lectura ya salió (una ranura del canal 0 cada 20 ciclos =
185 ns). El V9990 tampoco: `T9990_RAM` nunca baja `RFSH_n` junto a `OE_n` o
`WE_n` (`t9990_ram.sv:411-439`, caso `RAM_RF`).

**`Secondary[n].DOUT` se captura solo tras un R/W** (`proc_rw`,
`uma.sv:415-430`). Un RFSH no trae dato, pero tnCart copiaba igualmente
`Primary.DOUT`, que tras un refresco es la última lectura del otro canal. Con
el RFSH aplazado, esa copia caería en mitad de la lectura siguiente del
cliente. Ningún cliente lee `DOUT` tras un RFSH:

- la megaROM pasa `Ram.DOUT` al bus solo con `/RD` bajo
  (`megarom_controller.sv:323`, `:342`);
- el bootloader lo lee solo tras el ACK de su lectura (`bootloader.sv:955-963`);
  sus RFSH van con handshake, sin leer el dato (`bootloader.sv:788`, `:835`,
  `:913`);
- `T9990_RAM` no entrega dato en `RAM_RF` (`t9990_ram.sv:458`, `:551-555`:
  solo copia `RAM_DOUT` a los clientes con su bit de `ack`, y `ack_bits_rf` no
  tiene ninguno de ellos).

### 3. `sdram.sv`: AUTO REFRESH en la inicialización

`STATE_INIT_REF1` y `STATE_INIT_REF2` mandaban `CMD_PRE`, donde el comentario
dice AUTO REFRESH (`sdram.sv` de tnCart, líneas 261-267; igual en
`_recursos/tnCartWonder/rtl/src/peripheral/ram/sdram.sv` y en `main`). La SDRAM
no recibía ningún AUTO REFRESH antes del MRS. Ahora mandan `CMD_REF`
(`sdram.sv:270-280`). Los estados y los ciclos son los mismos: 8 ciclos de PRE
a REF, de REF a REF y de REF al MRS, 74 ns a 108 MHz, por encima del tRC ≥ 55 ns
del modelo y de los 60 ns que usa nand2mario para esta SDRAM (`T_RC`,
`WonderTANG-ref/fpga/src/sdram.v:44`). La secuencia PRE, dos REF y MRS es la de
nand2mario (`WonderTANG-ref/fpga/src/sdram.v:157-174`). El resto de `sdram.sv`
no cambia: la cadencia es intocable.

Hay un segundo cambio en `sdram.sv`, solo para simulación (`sdram.sv:109-118`).
Verilator 5.020 no compila `localparam ADDR8_BIT_WIDTH = $bits(Ram.ADDR)`
("Parameter-resolved constants must not use dotted references"), así que
`sdram.sv` no compilaba en ningún banco de Verilator. Con `` `ifdef VERILATOR ``
el localparam vale 24, y un `initial` comprueba que `Ram.ADDR` es de 24 bits.
La síntesis sigue usando la línea de tnCart: Gowin no define `VERILATOR`, y
`u_sdram` tiene los mismos 144 FF que en el hito 1. Va con `` `ifdef VERILATOR ``
y no con `` `ifndef SYNTHESIS `` porque no es código que sobre en síntesis,
sino una alternativa a una línea que Verilator no acepta: las dos ramas definen
el localparam, y cualquier otra herramienta usa la línea original.

## Interfaces: qué cambia y qué tiene que hacer la integración

| Elemento | Cambio | Qué hay que conectar |
|---|---|---|
| Parámetros de `UMA` | nuevos: `INT_REFRESH` (1), `REFRESH_CYCLES` (780), `REFRESH_ESC` (2 × `REFRESH_CYCLES`), `DBG_W` (16) | nada: los valores por defecto son los del hito. `.INT_REFRESH(0)` quita el temporizador |
| Salidas de `UMA` | nuevas: `DBG_RF_INT`, `DBG_RF_CH0`, `DBG_RF_CH1`, `DBG_RF_ESC` (contadores de `DBG_W` bits que dan la vuelta: refrescos emitidos por el temporizador, por el RFSH del canal 0 y por el `RAM_RF` del canal 1, y escalaciones), `DBG_RF_MAXGAP[11:0]` (mayor intervalo entre AUTO REFRESH, en ciclos menos 1, satura en 4095) y `DBG_RF_STB` (un ciclo por AUTO REFRESH) | opcional. Sin conectar, Gowin las poda y el top actual compila sin tocarlo. Verilator 5.020 avisa `PINMISSING` (seis avisos) si un banco instancia `UMA` sin ellas; con las opciones por defecto el aviso es fatal, y lo quitan `-Wno-fatal` o `-Wno-lint` (comprobado con `--lint-only`). No es un requisito nuevo: el `uma.sv` de tnCart ya da tres `WIDTHEXPAND` con las opciones por defecto (`mem_cnt` en las comparaciones de `TIMING`), así que ningún banco con el UMA compilaba sin una de esas dos opciones |
| `Secondary[n].DOUT` | se actualiza solo tras un R/W, no tras un RFSH | nada (ningún cliente lo lee tras un RFSH, ver arriba) |
| `ACK_n` del canal 0 | un R/W aplazado por la escalación, o un RFSH que llegó junto a un R/W, alarga el ACK una ranura (20 ciclos) | nada para el bootloader (handshake). **Corregido en la fusión**: la megaROM de `hito/megaram` sí mira el ACK (con `ENABLE_MEM_WAIT = 1` suelta su /WAIT con `ACK_n`); el alargamiento es compatible (el /WAIT dura 20 ciclos más y se suelta con el dato), pero `ACK_n`/`DOUT` del canal 0 pasan a ser contrato del UMA: ver `docs/ARCHITECTURE.md` y `docs/notas/megaram.md`, apartado 4 |
| Canal 1 | sin cambios de comportamiento: el refresco interno nunca sale en sus ranuras | nada |
| `SDRAM` | sin cambios de interfaz | nada |

Lo que tiene que hacer la integración (fuera de mis ficheros):

1. **Documentación.** En `docs/ARCHITECTURE.md`, la sección "SDRAM y VRAM" dice
   "Refresco: por debajo de la especificación en el hito 1": pasa a describir el
   temporizador (780 ciclos, escalación a 1560, intervalo máximo 1580 ciclos) y
   la desviación consciente del chip real: el V9990 no refresca su VRAM en
   standby (manual, p. 80) y aquí se conserva, como en openMSX (ver "Fuentes").
   En `docs/VERIFICATION.md`, añadir el banco (`fpga/tb/sdram/run.sh`, sale con
   1 si algo falla; ~30 s con 2 ms por caso). En `docs/changelog.md`, los tres
   arreglos.
2. **Placa (puerta del hito 4, sin hacer).** Un patrón de 512 KB en la VRAM
   tiene que sobrevivir 1 h con DISP = 0 y 1 h en standby con el bitstream solo
   V9990. Si se quiere ver el refresco en la placa, `DBG_RF_MAXGAP` puede ir a
   un LED (por ejemplo, encenderlo si pasa de 1600). Conectar las seis salidas
   cuesta lo medido en "Síntesis".
3. **LOCK crudo en `xtal`** (riesgo apuntado al hito 4 en `ARCHITECTURE.md`).
   En `board_wt200b_clock.sv:181-184` la variante `xtal` usa el LOCK del rPLL tal
   cual como `CLK_MEM_LOCK`; la variante `sync` lo retiene en un flop pegajoso
   (`:130-137`). `CLK_MEM_READY` (`:128`) es el `RESET_n` de `sdram.sv`: un
   rebote del LOCK reinicializa la SDRAM y resetea todo el sistema. Hacerlo como
   en `sync` es tocar `board_wt200b_clock.sv`, que no es fichero mío.
4. **E/S de la SDRAM sin `set_input_delay`/`set_output_delay`** (riesgo de
   `ARCHITECTURE.md`): el banco usa la ventana del modelo del MoonTANG
   (T_VALID 10,5 ns, T_HOLD 5,5 ns), no un STA de esta placa. Restringirla es
   del `.sdc` de la integración.
5. **Orden de fusión con `hito/megaram`.** El banco de la MegaRAM ya corre con
   este `uma.sv` (variantes `wait_hito4` e `inj_hito4` de su
   `fpga/tb/megaram/run.sh`), y según su nota (`docs/notas/megaram.md` de esa
   rama) su contrato del /WAIT depende de que `Secondary[0].DOUT` solo se copie
   tras un R/W (`proc_rw`): con el `uma.sv` de `main`, un refresco del canal 0
   que acabe después de la lectura sube el ACK con la lectura del canal 1 (su
   variante `inj_main`). `hito/sdram` tiene que entrar antes que
   `hito/megaram`, o a la vez. No he corrido su banco: es de otra área.
6. **Dos cosas que no hay que cambiar sin rehacer la cuenta del intervalo.**
   (a) El reset del UMA (arriba): si la integración lo atara al /RESET del
   MSX, un reset largo dejaría la SDRAM sin refresco. (b) `SYNC_CPU_UMA = 0`
   (`board_wt200b_config.sv:43`; también en las dos variantes de la rama de
   integración). El temporizador cuenta ciclos de `CLK`, pero solo emite en
   `exec_timing[0]`, que sale de `mem_cnt`. Con `SYNC_CLK_EN = 0` el contador
   corre libre, que es lo que simula el banco; con `SYNC_CLK_EN = 1`,
   `mem_cnt` se para en `DIV - 1` si falta `CLK_EN` (`uma.sv:126-130`), y sin
   ranuras no sale ningún refresco.

## Cómo se prueba

```
fpga/tb/sdram/run.sh [US]        # desde Git Bash o WSL; US = µs por caso (2000)
```

Compila siete builds de Verilator 5.020 en `/tmp` (WSL) y corre la matriz a 108
y a 107,386 MHz. Escribe `fpga/tb/sdram/resultados.txt` (en el repositorio: la
salida de la última ejecución, 2 ms por caso) y sale con 1 si algún caso no da
lo esperado. Tarda entre 30 s y 2 min, según lo que corra a la vez en WSL.
`fpga/tb/sdram/resultados_20ms.txt` es la misma matriz con 20 ms por caso
(`run.sh 20000`, de 5 a 15 min). Para escribirla ahí hay que lanzarlo desde
WSL con `OUT=.../resultados_20ms.txt` (las variables de Git Bash no pasan a
WSL), y no lanzar dos a la vez con el mismo `OUT`: las dos ejecuciones
escriben en el mismo fichero y las líneas salen mezcladas. Icarus 12 no sirve: no
compila los puertos `RAM_IF.HOST` de tnCart ("syntax error ... Errors in port
declarations").

Builds: `new` (el árbol), `int0` (`-GINT_REFRESH=0`), `hito1` (`uma.sv` y
`sdram.sv` de `20936e6`; referencia de la latencia del canal 1 y control),
`mut` (refresco interno por `done_ch` y `DOUT` tras cualquier operación),
`mutrw` (solo `DOUT` tras cualquier operación, también tras un RFSH; el
refresco interno como en el árbol), `slack0` y `slow` (`sdram.sv` con 10 y 11
ciclos por acceso).

Si un simulador muere sin llegar al informe, el caso sale como
`FALLA (sin informe; vtb salió con N)` y cuenta como fallo; `run.sh` no lo
repite. Ha pasado una vez en once ejecuciones de la matriz (26/10, el caso
`neg_slack0_slot_107386`, con otras builds de Gowin y Verilator corriendo en
paralelo; entonces `run.sh` aún no guardaba el código de salida). Las ocho
ejecuciones posteriores pasaron enteras; los binarios son deterministas, así
que apunta a algo externo (quizá memoria de WSL), pero no lo he podido
confirmar.

Piezas:

- **Modelo de SDRAM** (`sdram_model_bl.v`): copia de
  `MoonTANG/tools/sim/board/sdram_model.v`, con la misma ventana de dato
  (T_VALID 10,5 ns, T_HOLD 5,5 ns) y las mismas comprobaciones (tRC ≥ 55 ns
  antes de REF y ACT, tRCD ≥ 15 ns, filas abiertas, MRS). Añade ráfagas
  (`sdram.sv` programa BL = 2 y el original solo hacía una palabra) y, como
  Verilator es de dos estados, fuera de la ventana pone un valor envenenado en
  lugar de X y publica la ventana para que el banco compruebe que `sdram.sv`
  captura dentro (en `STATE_FETCH_RDATA_1/2`). El reloj de la SDRAM es
  `CLK_PS` = `~CLK`, como `CLK_MEM_P` en la placa (rPLL base con
  `PSDA_SEL = "1000"`, 8/16 de vuelta = 180°, `board_wt200b_clock.sv`).
- **Canal 1**: el protocolo de `T9990_RAM`. La operación sale en EXEC =
  TIMING + 1; el cliente espera `ACK_n` = 0 y después `ACK_n` = 1, y un EXEC
  fuera de `WAIT_REQ` cuenta como ranura perdida (`t9990_ram.sv:351-361`,
  `:490-557`). Todas las ranuras van ocupadas, con un `RAM_RF` por línea de 342
  ranuras (1368 ciclos de 21,6 MHz), y lecturas y escrituras de 8, 32, 32_E y
  32_O bits. En STANDBY no hay ninguna operación.
- **Canal 0**:
  - Z80 sintético que actúa como la megaROM: OE/WE/RFSH por nivel, ADDR = 0 en
    reposo, 8 bits. M1 de 5 T con `/RFSH` tras cada M1 (o sin él), lecturas y
    escrituras de 3 T, a 3,58 y 7,16 MHz. Las señales pasan por dos flops y 8
    ciclos de retardo antes del UMA.
  - Cliente al 100 %: R/W de 8, 16 y 32 bits encadenados por `ACK_n`, uno por
    ranura del canal 0.
  - Cliente que pide R/W y RFSH en el mismo ciclo, o RFSH solo con handshake,
    como el bootloader.
- **Comprobaciones** (cada caso las imprime como `CHECK nombre PASA/FALLA`):
  - `model`: el modelo no ve ningún error de protocolo ni de tiempos;
  - `init`: ≥ 2 AUTO REFRESH antes del MRS;
  - `window`: capturas dentro de la ventana, escrituras con el bus conducido y
    sin contienda;
  - `gap`: intervalo máximo entre AUTO REFRESH en los pines < 15,6 µs
    (incluido el tramo final);
  - `slot`: en cada `exec_timing` de los dos canales `sdram.sv` ha vuelto a
    `STATE_IDLE`, su `ACK_n` está alto y el UMA no presenta OE/WE/RFSH: el
    acceso anterior y la captura del dato terminaron antes de la ranura
    siguiente, con el ciclo de holgura de "ciclo del controlador + 1 ≤ ranura";
  - `ch1`: canal 1 sin ranuras perdidas ni datos malos, latencia fija < 20,
    y `run.sh` exige que sea la misma que con el UMA del hito 1;
  - `rfsh_rw`: el UMA nunca presenta RFSH junto a OE/WE;
  - `dbg`: la suma de los contadores del UMA es igual a los REF vistos en los
    pines;
  - `int_slot`: el refresco interno solo sale en `exec_timing[0]`;
  - `ch0_quiet`: sin cliente en el canal 0, su `ACK_n` y su `DOUT` no se mueven;
  - `z80`: con el Z80, `DOUT` cambia como mucho una vez durante cada `/RD`, al
    dato correcto; `esc0`: cero escalaciones; `cov`: hay refrescos internos
    dentro de lecturas del Z80 ya capturadas, con `/RD` todavía bajo diez
    ciclos después (el momento en que un refresco por `done_ch` sobrescribiría
    el dato);
  - `esc` (cliente al 100 %): todos los refrescos internos son escalaciones y
    cada una aplaza un R/W exactamente 20 ciclos (histograma de latencias);
  - `rfsh` (R/W + RFSH): cada RFSH pedido sale como AUTO REFRESH;
  - `ch0` (cliente al 100 % y R/W + RFSH): cada lectura del canal 0 devuelve
    el dato correcto al subir el ACK. Con R/W + RFSH se corre también con el
    V9990 activo, que es cuando un `DOUT` copiado tras el RFSH aplazado traería
    la lectura del canal 1 (control `mutrw`);
  - `integ0`/`integ1`: los dos canales releen bytes que escribieron antes
    (miles de lecturas por caso), sobre la memoria precargada con un patrón.

Resultados (`resultados.txt`, 2 ms por caso, y `resultados_20ms.txt`, 20 ms;
las cifras son de 20 ms y coinciden con las de 2 ms salvo los contadores):

| Régimen | 108 MHz | 107,386 MHz | Notas |
|---|---|---|---|
| canal 0 libre, V9990 en standby | 7,45 µs, 0 escalaciones | 7,49 µs | solo refresco interno, 2699 en 20 ms |
| V9990 activo, canal 0 libre | 7,41 µs | 7,45 µs | 316 `RAM_RF` del V9990 y 2526 internos |
| Z80 a 7,16 MHz sin `/RFSH`, V9990 en standby (canal 0 al máximo realista) | 7,78-7,82 µs, 0 escalaciones, 3 semillas | 7,82-7,86 µs | 310-333 refrescos internos dentro de lecturas ya capturadas; DOUT estable |
| Z80 a 3,58 MHz sin `/RFSH`, standby | 7,63 µs | 7,64 µs | 0 escalaciones |
| Z80 a 3,58 y 7,16 MHz con `/RFSH` | 7,59 y 6,67 µs | 7,64 y 6,52 µs | el `/RFSH` reenviado hace casi todo el trabajo (35 y 0 internos) |
| Z80 a 7,16 MHz sin `/RFSH`, V9990 activo | 7,78 µs | 7,82 µs | canal 1 con latencia 12 |
| cliente al 100 %, V9990 en standby | 14,67 µs (el primer intervalo, 1584 ciclos; en régimen 1580) | 14,75 µs | 1366 escalaciones = 1366 internos = 1366 R/W aplazados exactamente 20 ciclos (latencia 18, aplazados 38) |
| cliente al 100 %, V9990 activo | 14,63 µs | 14,71 µs | ídem, con 1263 |
| R/W + RFSH a la vez | todos los RFSH salen (37 544 pedidos; 37 543 emitidos y el último en curso al acabar) | 37 325 (37 324 + 1) | también con `INT_REFRESH = 0` |
| R/W + RFSH a la vez, V9990 activo | ídem, 0 errores de dato en el canal 0 | ídem | con `mutrw`, 9096 y 9041 lecturas malas |

En todos los casos: modelo sin errores, 2 AUTO REFRESH antes del MRS, capturas
dentro de la ventana, cadencia en todas las ranuras (unas 21 500 por 2 ms), canal 1
sin ranuras perdidas ni errores de dato y con latencia 12, igual que el hito 1.

Controles negativos, que tienen que fallar en la comprobación indicada (y fallan):

| Control | Qué demuestra |
|---|---|
| reloj de la SDRAM a 0° (`+PHASE0=1`) | toda lectura cae fuera de la ventana (70 014 errores de dato en el canal 1 en 20 ms): el banco detecta el desfase |
| `INT_REFRESH = 0`, standby | sin el temporizador no hay refresco (20 ms sin ninguno) |
| UMA y `sdram.sv` del hito 1 | 0 REF antes del MRS; 63,3 µs entre refrescos con el V9990 activo (uno por línea) y ninguno en standby; con R/W + RFSH a la vez se pierden los RFSH que llegan junto a un R/W (en 2 ms salen 1258 de 5088, solo los que iban solos) |
| mutante: refresco interno por `done_ch` y DOUT tras cualquier operación | el Z80 lee el dato del canal 1 durante su `/RD`: `z80` lo detecta |
| `mutrw`: DOUT tras cualquier operación, también tras un RFSH (refresco interno como en el árbol) | con R/W + RFSH y el V9990 activo, el cliente lee tras su ACK la lectura del canal 1 que se copió al acabar su RFSH aplazado (9096 lecturas malas en 20 ms): `ch0` lo detecta, y por eso `proc_rw` hace falta |
| `slack0`: `sdram.sv` con 10 ciclos por acceso | falla solo `slot`: sin el ciclo de holgura el resto aún funciona; la comprobación es la regla del estudio |
| `slow`: `sdram.sv` con 11 ciclos por acceso | falla `slot` y el canal 1 lee datos rancios (47 683 errores en 20 ms) **sin perder ninguna ranura visible**: un acceso lento no avisa, por eso `slot` mira la cadencia directamente |

Límites del banco, dichos para no darlos por cubiertos:

- El modelo no comprueba tRFC, tRAS, tWR ni tRP más allá de los 55 ns de tRC y
  los 15 ns de tRCD. La ventana es la del MoonTANG, no una medida de esta placa.
- El retardo del bus del Z80 es una línea fija de 2 + 8 ciclos, no el
  `PIN_FILTER` y el mux reales (eso es del banco del hito 5), y el Z80 no
  modela `/WAIT`.
- El canal 1 copia el protocolo de `T9990_RAM`; no es el core. El core con el
  UMA es del banco del hito 2.
- A 7,16 MHz, una lectura de memoria tiene el `/RD` bajo 30,2 ciclos y el dato
  llega como muy tarde a los 30 (`captura_max`). Pasa sin margen en este modelo
  ideal (0 lecturas tarde en todas las semillas), pero el banco no lo exige a
  7,16 MHz: es la latencia del hito 1, el refresco interno no retrasa ningún
  R/W del Z80 y en ese régimen no hay escalaciones. La MegaRAM en turbo
  necesita el `/WAIT` del hito 8b, como ya dice el estudio.
- La placa no se ha probado (ver "qué tiene que hacer la integración").

## Síntesis

`cd fpga && gw_sh check_sdram.tcl`: es `build_v9990_xtal.tcl` (configuración
`v9990`, variante `xtal`) con solo `run syn` y salida `check_sdram`. Recursos
por módulo de `impl/gwsynthesis/check_sdram_syn_rsc.xml`. La referencia es la
misma síntesis sobre el árbol de `main` (`20936e6`, hito 1), en una copia en
una ruta corta; da las mismas cifras por módulo que la build del hito 1 que
quedó en el repositorio principal (`V9990TANG/fpga/impl/gwsynthesis/v9990_xtal_syn_rsc.xml`,
22/10, sin seguimiento en git). Las cifras que daba el encargo (`u_uma` 178 / 217, `u_sdram`
245 / 144) son de la síntesis `full` del estudio (sección 3, tabla de módulos), no
de esta configuración: en `v9990` los mismos módulos del hito 1 miden 171 / 217 y
246 / 144.

| | Hito 1 (`20936e6`), config `v9990` | Hito 4 | Diferencia |
|---|---|---|---|
| `u_uma` LUT / FF / ALU | 171 / 217 / 0 | 207 / 233 / 0 | **+36 LUT, +16 FF** |
| `u_sdram` LUT / FF / ALU | 246 / 144 / 0 | 243 / 144 / 0 | −3 LUT (ruido de mapeo) |
| total LUT / ALU / FF / BSRAM | 11 565 / 2 166 / 6 173 / 24 | 11 549 / 2 167 / 6 189 / 24 | −16 / +1 / +16 / 0 |

Los 16 FF son `rf_age` (12), `int_req`, `int_esc` y los dos `proc_rw`. Los
contadores de depuración se podan porque el top no los conecta. **Conectados**
(medido en dos copias temporales con las seis salidas llevadas a un puerto
nuevo del top) cuestan **+77 FF y +71/72 ALU** en `u_uma`; las LUT dependen de
cómo se conecten, por el reparto que hace Gowin entre el UMA y la lógica de
fuera:

| Conexión de la medida | `u_uma` LUT / FF / ALU | LUT de la XOR en el top |
|---|---|---|
| XOR de reducción de los 77 bits a un pin | 215 / 310 / 72 (+8 LUT) | 27 |
| XOR de los contadores a un bus de 16 bits | 239 / 310 / 71 (+32 LUT) | 29 |

Para presupuestar, +32 LUT, +77 FF y +72 ALU. Los avisos de la síntesis son los
mismos 8 que en el hito 1 (CV0016 x2, NL0002 x6), ninguno de `uma.sv` ni de
`sdram.sv`.

**Build completa (P&R).** `gw_sh` con un script de dos líneas,
`source check_sdram.tcl` y `run pnr`, desde `fpga/` (de 19 a 38 min en total,
según las otras builds de Gowin que corran en paralelo). La puerta del hito 1 (`tools/check_build.py
fpga/impl/pnr/check_sdram` con los mismos argumentos que
`docs/VERIFICATION.md` da para `v9990_xtal`) **pasa**. Se ha hecho cuatro veces
sobre el mismo RTL (25/10 y tres el 26/10) con cifras idénticas:

| | Hito 1 (`fpga/reports/hito1`) | Hito 4 |
|---|---|---|
| Logic / CLS / BSRAM | 14 140 / 8 679 / 24 | 14 123 (68,1 %) / 8 651 (83,4 %) / 24 |
| Register | 6 173 | 6 189 |
| Fmax `CLK_BASE` | 109,08 MHz | 110,30 MHz |
| peor slack setup / hold | 0,092 / 0,074 ns | 0,193 / 0,074 ns |
| endpoints violados (setup, hold, recovery) | 0 | 0 |
| avisos | CV0016 x2, NL0002 x6, PR1014 x1 | los mismos |

El peor camino sigue siendo el del blitter (`u_blit/state_3_s1` →
`u_blit/work_22_s0`), y ninguno de los 25 peores caminos de setup empieza ni
acaba en `u_uma` o en `u_sdram` (todos son del blitter, de `u_port` → `u_sp` o
de `u_tg` → `u_sp`). La mejora de Fmax y los −28 CLS son variación del
P&R, no algo que se deba a este cambio. El `.fs` (`impl/pnr/check_sdram.fs`) no
se ha archivado ni probado en la placa: `fpga/reports/` es de la integración.

## Verificación repetida

El hito lo han hecho tres sesiones seguidas; las dos primeras se cortaron por
el límite de sesión. Cada una releyó lo de la anterior frente a `main` y volvió
a correr todo. **El RTL es el de los commits `737b755`, `19653d3`, `adfabdc`,
`3b883c8` y `cbf65ea`, y no ha cambiado desde entonces.**

- **Primera revisión (26/10, madrugada).** El banco ganó el caso R/W + RFSH con
  el V9990 activo (`rw_rfsh_v99`) y el control `mutrw`: demuestran que
  `proc_rw` hace falta (sin él, un cliente con handshake que pida R/W y RFSH a
  la vez lee tras el ACK la lectura del canal 1 copiada al acabar su RFSH
  aplazado). `run.sh` apunta el código de salida del simulador si muere sin
  informe. La nota pasó a citar el manual del V9990 (sin refresco de VRAM en
  standby) y a tratar la conservación de la VRAM en standby como desviación
  consciente del chip.
- **Segunda revisión (26/10, mañana).** Sin cambios de RTL ni de banco. La nota
  ganó el reset del UMA, los puntos 5 y 6 de la integración, el riesgo de la
  ranura con la SDRAM ocupada y cómo lanzar la matriz de 20 ms sin pisarla.
- **Tercera revisión (26/10, tarde).** Sin cambios de RTL ni de banco.
  - `uma.sv` y `sdram.sv` releídos frente a `main`, también los casos límite
    (escalación con RFSH del canal 0 pendiente, `INT_REFRESH = 0`, alternancia
    estricta de `exec_timing[0]` y `[1]` con `SYNC_CLK_EN = 0`, `DOUT` del
    canal 1 tras un `RAM_RF`): los tres arreglos y `proc_rw`, nada más.
  - `run.sh` y `run.sh 20000`: `TOTAL: PASA` en los 48 casos de cada matriz,
    con las mismas cifras caso por caso; solo cambia la cabecera.
  - Síntesis del árbol y de `main` (`20936e6`, copia en ruta corta): las cifras
    de la tabla de arriba, mismos 8 avisos. **Corregido:** el coste de las
    salidas de depuración conectadas depende de cómo se conecten; la nota daba
    solo la medida con la XOR de reducción (+8 LUT), y con un bus de 16 bits
    salen +32 LUT (tabla de "Síntesis").
  - P&R (37 min, con otras tres builds de Gowin a la vez) y puerta de
    `check_build.py`: **PASA**, con las cifras de la tabla de "Síntesis"
    (14 123 / 8 651 / 24, Fmax 110,303 MHz, slack 0,193 / 0,074 ns, 0
    endpoints violados, mismos avisos) y ningún camino de `u_uma` ni de
    `u_sdram` entre los 25 peores de setup.
  - `DBG_RF_MAXGAP` leído en el banco: 1579 con el cliente al 100 % (con el
    V9990 activo y en standby), 799 con el canal 0 libre y 839 con el Z80 a
    7,16 MHz sin `/RFSH`; los 1584 y 804 de la columna `gap` son el primer
    intervalo, desde el último REF de la inicialización.
  - Comprobado a mano: el error de Verilator 5.020 con `$bits(Ram.ADDR)` en el
    `sdram.sv` de `main` (línea 109) y que el del árbol compila; los seis
    `PINMISSING` y los tres `WIDTHEXPAND` de `--lint-only`; el `syntax error`
    de Icarus 12 en los puertos de `ram.sv` y `uma.sv`; openMSX en el
    master actual (`powerUp` borra la VRAM; en el reset por `SYSTEM_CONTROL`,
    el comentario de que en un MSX real ni la paleta ni la VRAM se borran);
    las líneas citadas de `megarom_controller.sv`, `bootloader.sv`,
    `t9990_ram.sv`, `t9990_timing.sv`, `wv_to_sdram.v` y del `sdram.v` de
    nand2mario. **Corregido:** la nota decía que un AUTO REFRESH refresca el
    chip entero; refresca una fila (la del contador interno), y lo que importa
    para la decisión de standby es que no distingue regiones.
- Ninguna de las tres ha probado nada en la placa: sigue pendiente la puerta
  del hito 4 (punto 2 de la integración).

## Riesgos y observaciones

- **Comandos de la SDRAM antes del LOCK.** En `sdram.sv`, `SDRAM_CMD` no tiene
  valor de reset. En el netlist de síntesis, CS_n va a GND (el bit 3 de
  `SDRAM_CMD` es constante, porque ningún comando usa `CMD_DIS`). RAS, CAS y WE
  son `DFFE` con `CE = CLK_MEM_LOCK` y sin `INIT`: arrancan a 0, que según
  entiendo es el valor por defecto de la primitiva; no lo he comprobado en la
  documentación de Gowin. Si el reloj de la SDRAM corre antes del LOCK, los
  pines llevan MODE REGISTER SET con A = 0. En Verilator el banco ve `0000` en
  los pines durante el reset, y por eso le da el reloj al modelo solo desde el
  primer flanco con `RESET_n` alto. Tampoco hay espera de power-up: nand2mario
  pone NOP en el reset y espera 200 µs antes del PRECHARGE
  (`WonderTANG-ref/fpga/src/sdram.v:145-148`, `:262-278`); tnCart empieza el
  PRECHARGE en el primer flanco tras el LOCK. El MRS correcto de la
  inicialización sobrescribe el malo, y el hito 1 funciona en placa. Lo dejo
  apuntado sin tocarlo, porque este hito pedía no cambiar nada más de
  `sdram.sv`. El arreglo sería poner NOP en el reset de `SDRAM_CMD` y,
  opcionalmente, un contador de 200 µs antes de `STATE_INIT_PRE`.
- **ACK más largo en el canal 0** con escalación, o con R/W + RFSH a la vez: un
  cliente que espere el ACK lo verá 20 ciclos más tarde. Un cliente que no lo
  espere y tenga el dato en el bus (la megaROM sin `/WAIT`) recibe el dato 20
  ciclos más tarde solo si hay escalación. Con un Z80 no hay escalaciones
  (banco: 0 en todos los regímenes del Z80, también a 7,16 MHz sin `/RFSH`),
  porque siempre quedan ranuras libres.
- **Una ranura con la SDRAM aún ocupada no emite nada**, y nadie lo ve. Si en
  un `exec_timing` `Primary.ACK_n` siguiera bajo, esa rama tiene prioridad en
  `uma.sv` (`:499`) y no sale ni el R/W ni el refresco, pero `save_oe`,
  `save_we`, `save_rfsh`, `rf_age`, `int_req` y los contadores ya se habrían
  borrado o contado como emitidos. Con el R/W es lo mismo que en tnCart. No
  pasa mientras se cumpla la cadencia (la comprobación `slot` lo mira en cada
  ranura); si un hito cambia la cadencia, un refresco se perdería sin aviso y
  `DBG_RF_MAXGAP` no lo vería, porque mide lo que el UMA presenta, no lo que
  ejecuta la SDRAM.
- **Solo cuenta lo que pasa por el UMA.** `rf_age` ve los AUTO REFRESH que el
  UMA presenta. Hoy no hay otro camino a la SDRAM. Si un hito añade un cliente
  que no pase por el UMA, tendrá que avisar al temporizador.
- **Si cambia la cadencia** (por ejemplo, la base de 85,9 MHz del estudio), el
  intervalo máximo pasa a ser `REFRESH_ESC` más el periodo de ranura del
  canal 0. Hay que recalcular `REFRESH_CYCLES` y `REFRESH_ESC` para seguir
  por debajo de 15,6 µs.
- **4096 refrescos en 64 ms** es la cifra de nand2mario para esta SDRAM; Gowin
  no publica la hoja de datos de la SDRAM embebida, así que no la he podido
  contrastar. Con 2048 filas por banco podría bastar con la mitad; el diseño
  cumple la cifra más exigente.
