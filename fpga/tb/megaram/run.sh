#!/usr/bin/env bash
#
# run.sh -- compila y corre tb_megaram con Verilator 5.020 (WSL)
#
# BSD 3-Clause License. Copyright (c) 2026, Papipapito.
#
# Uso (desde Windows):
#   wsl -e bash -lc "cd /mnt/c/<repo>/fpga/tb/megaram && ./run.sh [variante...]"
# Variantes (por defecto todas). Las ESTRICTAS fallan con cualquier error;
# las de MEDIDA solo fallan si se rompe el contrato del /WAIT (cuando baja,
# dato valido al subir, dato estable; en inj_main solo se cuenta) o la VRAM,
# y cuentan lo que el Z80 lee mal o sin esperar:
#   wait       ESTRICTA  MEM_WAIT=1 PREWAIT=1 a 3,58 MHz (contrato completo)
#   noprewait  medida    MEM_WAIT=1 PREWAIT=0 a 3,58 MHz: la cadena del WAIT
#                        sola NO llega con los supuestos del Z80 del area bus
#                        (71 de 253 lecturas mal el 26/10/2026): el pre-WAIT de
#                        memoria es imprescindible tambien a 3,58 MHz
#   noprewait_opt medida igual con los supuestos antiguos del banco (/RD a
#                        46 ns, NPN 30 ns): llega justo, con margen 0
#   wait_rd9   medida    wait con /RD a 9 ciclos (83 ns) de la bajada de T1
#   wait_rd10  medida    wait con /RD a 10 ciclos (93 ns): margen del pre-WAIT
#   nowait     medida    MEM_WAIT=0 PREWAIT=0 a 3,58 MHz (como tnCart, sin WAIT)
#   turbo5     medida    MEM_WAIT=1 PREWAIT=1 a 5,37 MHz
#   turbo5i    medida    igual con pre-WAIT ideal (PW_DLY=0)
#   turbo7     medida    MEM_WAIT=1 PREWAIT=1 a 7,16 MHz
#   inj_main   medida    INJ=1 (refresco de otro cliente del canal 0 alrededor de
#                        cada lectura) con el UMA de tnCart (el de este arbol):
#                        control del defecto de ese UMA (DOUT copiado tras un
#                        RFSH); cuenta aparte las lecturas que rompen el contrato
#                        (7 de 31 el 26/10/2026). En la configuracion megaram, con
#                        ese UMA, nadie mas refresca el canal 0 (docs/notas/megaram.md)
#   wait_hito4 ESTRICTA  como wait, con el uma.sv de la rama hito/sdram (refresco
#                        interno activo, DOUT solo tras un R/W)
#   inj_hito4  ESTRICTA  INJ=1 con el uma.sv de hito/sdram
#   tncrom     ESTRICTA  como wait, pero en lugar del programa del banco
#                        reproduce las trazas del tncrom real (compilado para el
#                        host y corrido contra un modelo en C del cartucho por
#                        tools/tncrom/test/run.sh, que se lanza aqui): cada
#                        lectura tiene que dar en el RTL lo que dio el modelo
#                        (out_tncrom_<traza>.log; necesita gcc)
# Las *_hito4 usan el uma.sv de $UMA_SV si esta definido; si no, lo sacan de la
# rama $UMA_REF (por defecto hito/sdram) con git show. El git de WSL no lee los
# worktrees creados desde Windows: entonces hay que sacarlo antes, p. ej.
#   git show hito/sdram:fpga/src/peripheral/ram/uma.sv > /c/tmp/uma_hito4.sv
#   wsl -e bash -lc "cd ... && UMA_SV=/mnt/c/tmp/uma_hito4.sv ./run.sh inj_hito4"
# Si no hay ninguno de los dos se saltan con un aviso (y no cuentan).
# Los supuestos de pines del Z80 (D_ADDR, D_CTRL, D_WAIT, D_DATA, ver la
# cabecera de tb_megaram.sv) son por defecto los del banco del area bus;
# EXTRA_G="-GD_CTRL=9 ..." se anade a los parametros de todas las variantes
# (barridos a mano; la salida va al mismo out_<variante>.log).
# Los objetos y las salidas van a $TB_OUT (por defecto ~/.cache/v99tang_tb_megaram,
# fuera del repositorio); cada variante deja out_<variante>.log alli. El
# guion sale con codigo 1 si alguna variante no imprime "RESULTADO: PASA".
#
set -u
cd "$(dirname "$0")"
HERE=$(pwd)
SRC=$HERE/../../src
CFG=$HERE/../../config
OUT=${TB_OUT:-$HOME/.cache/v99tang_tb_megaram}
mkdir -p "$OUT"

FILES=(
    $CFG/v9990_megaram.sv
    $SRC/board/board_id.sv
    $SRC/board/wt200b/board_wt200b_config.sv
    $SRC/peripheral/msx/bus.sv
    $SRC/peripheral/ram/ram.sv
    @UMA@
    $SRC/peripheral/spi.sv
    $SRC/peripheral/flash.sv
    $SRC/peripheral/led.sv
    $SRC/bootloader.sv
    $SRC/peripheral/signal/attenuator.sv
    $SRC/peripheral/signal/limiter.sv
    $SRC/peripheral/sound/sound.sv
    $SRC/peripheral/sound/scc/scc.sv
    $SRC/peripheral/msx/expansion_slot.sv
    $SRC/peripheral/msx/megarom_controller.sv
    $SRC/peripheral/msx/megarom_configure.sv
    $SRC/peripheral/msx/megarom_clear.sv
    $SRC/cartridge_megarom.sv
    $SRC/board/rev1/board_rev1_bus.sv
    $HERE/dpb_model.sv
    $HERE/sdram_if_model.sv
    $HERE/tb_megaram.sv
)

declare -A PARAMS=(
    [wait]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GSTRICT=1"
    [noprewait]="-GMEM_WAIT=1 -GPREWAIT=0 -GTURBO=0 -GSTRICT=0"
    [noprewait_opt]="-GMEM_WAIT=1 -GPREWAIT=0 -GTURBO=0 -GSTRICT=0 -GD_ADDR=5 -GD_CTRL=5 -GD_WAIT=11"
    [wait_rd9]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GSTRICT=0 -GD_CTRL=9"
    [wait_rd10]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GSTRICT=0 -GD_CTRL=10"
    [nowait]="-GMEM_WAIT=0 -GPREWAIT=0 -GTURBO=0 -GSTRICT=0"
    [turbo5]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=1 -GSTRICT=0"
    [turbo5i]="-GMEM_WAIT=1 -GPREWAIT=1 -GPW_DLY=0 -GTURBO=1 -GSTRICT=0"
    [turbo7]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=2 -GSTRICT=0"
    [inj_main]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GINJ=1 -GSTRICT=0"
    [wait_hito4]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GSTRICT=1"
    [inj_hito4]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GINJ=1 -GSTRICT=1"
    [tncrom]="-GMEM_WAIT=1 -GPREWAIT=1 -GTURBO=0 -GSTRICT=1 -GTRACE=1"
)
UMA_REF=${UMA_REF:-hito/sdram}

VARIANTS=("$@")
[ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(wait tncrom noprewait noprewait_opt wait_rd9 wait_rd10 nowait turbo5 turbo5i turbo7 inj_main wait_hito4 inj_hito4)

rc=0
for v in "${VARIANTS[@]}"; do
    p=${PARAMS[$v]:-}
    if [ -z "$p" ]; then echo "variante desconocida: $v"; exit 2; fi
    p="$p ${EXTRA_G:-}"
    uma=$SRC/peripheral/ram/uma.sv
    if [[ "$v" == *_hito4 ]]; then
        if [ -n "${UMA_SV:-}" ] && [ -f "$UMA_SV" ]; then
            cp "$UMA_SV" "$OUT/uma_hito4.sv"; from="$UMA_SV"
        elif git -C "$HERE" show "$UMA_REF:fpga/src/peripheral/ram/uma.sv" > "$OUT/uma_hito4.sv" 2>/dev/null; then
            from="$UMA_REF $(git -C "$HERE" rev-parse --short "$UMA_REF")"
        else
            echo "=== $v: no hay UMA_SV ni $UMA_REF, se salta"; continue
        fi
        uma=$OUT/uma_hito4.sv
        echo "=== $v ($p, uma.sv de $from, md5 $(md5sum < "$uma" | cut -c1-8))"
    else
        echo "=== $v ($p)"
    fi
    files=("${FILES[@]/@UMA@/$uma}")
    rm -rf "$OUT/obj_$v"
    if ! verilator --binary --timing -j 0 --top-module tb_megaram \
            -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
            -Wno-PINCONNECTEMPTY -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-GENUNNAMED \
            -Wno-VARHIDDEN -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-UNOPTFLAT \
            -Wno-BLKSEQ -Wno-INITIALDLY \
            $p --Mdir "$OUT/obj_$v" -o tb "${files[@]}" > "$OUT/build_$v.log" 2>&1; then
        echo "  error de compilacion ($OUT/build_$v.log)"; grep -E "%Error" "$OUT/build_$v.log" | head -20; rc=1; continue
    fi
    runs=("$v:")
    if [ "$v" = tncrom ]; then
        # el tncrom real contra el modelo en C (tools/tncrom/test) deja las trazas
        echo "  banco del host de tncrom:"
        rm -f "$OUT"/tncrom_host/tncrom_*.trc
        if OUT="$OUT/tncrom_host" "$HERE/../../../tools/tncrom/test/run.sh" > "$OUT/tncrom_host.log" 2>&1; then
            grep -E "^(  traza|comprobaciones|RESULTADO)" "$OUT/tncrom_host.log" | sed 's/^/    /'
        else
            grep -E "^(  FALLO|comprobaciones|RESULTADO)|error" "$OUT/tncrom_host.log" | head -20 | sed 's/^/    /'
            echo "  el banco del host de tncrom FALLA ($OUT/tncrom_host.log)"; rc=1
        fi
        runs=()
        for t in "$OUT"/tncrom_host/tncrom_*.trc; do runs+=("tncrom_$(basename "$t" .trc | sed 's/^tncrom_//'):+TRACE=$t"); done
    fi
    for r in "${runs[@]}"; do
        name=${r%%:*}; [ -z "$name" ] && name=$v
        arg=${r#*:}
        [ "$name" != "$v" ] && echo "  --- $name"
        "$OUT/obj_$v/tb" $arg > "$OUT/out_$name.log" 2>&1
        grep -E "^(Z80:|borrado|traza|lecturas|refrescos|pre-WAIT|/RD|Bus\.|rd_mem_n|histograma|SDRAM|VRAM|fallos|RESULTADO)" "$OUT/out_$name.log"
        nerr=$(grep -c "ERROR" "$OUT/out_$name.log")
        [ "$nerr" -gt 0 ] && { echo "  primeros errores:"; grep "ERROR" "$OUT/out_$name.log" | head -8; }
        grep -q "RESULTADO: PASA" "$OUT/out_$name.log" || rc=1
    done
done
echo "salidas en $OUT"
exit $rc
