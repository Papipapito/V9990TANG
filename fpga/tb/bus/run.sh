#!/bin/bash
# ============================================================================
# run.sh -- banco del bus (hito 5) con Verilator 5.020 en WSL.
#
# Uso (desde Git Bash o desde WSL, en cualquier directorio):
#   fpga/tb/bus/run.sh [CASO ...]
# Sin argumentos corre la matriz completa. Un CASO es TOPO:BASE:MEMPW, p. ej.
#   0:60:0  con EXPANSION_SLOT, V9990 en 60h, sin MegaRAM
#   1:60:0  sin EXPANSION_SLOT
#   0:70:0  V9990 en 70h: nadie contesta en 60h/61h (liberacion del pre-WAIT)
#   0:60:1  con la MegaRAM de mentira y PREWAIT_MEM_EN = 1
# Variables: HZS="3579545 5369318 7159090 10738635" (frecuencias del Z80),
#            SEED=<n>, N=<accesos por fase>, EXTRA="<plusargs>" (p. ej. +HB=500),
#            REUSE=1 (no recompila si el binario del caso ya existe),
#            GEN="<-Gparam=valor ...>" (variantes del banco: -GSCAN=0, -GPWIO=0,
#            -GAHOLD=0, -GTAILG=0, -GPW_K=n; ver tb_bus.sv) con TAGX=<sufijo>
#            para que sus logs no pisen los de la configuracion normal;
#            CART_SV=<fichero> compila el banco con otro cartridge_v9990.sv (el
#            mutante sin rearme: git show main:fpga/src/cartridge_v9990.sv > f;
#            CART_SV=f TAGX=sinrearme fpga/tb/bus/run.sh 0:60:0 1:60:0).
# Compila cada caso una vez en ~/.tb_bus_obj (en el disco de WSL: el 9p de
# /mnt/c es lento) y lo ejecuta a todas las frecuencias en paralelo; deja los
# logs en fpga/tb/bus/out/ (ignorado por git).
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    # WSLENV /p solo traduce rutas de Windows (C:/...), no las de Git Bash (/c/...)
    [ -n "$CART_SV" ] && command -v cygpath >/dev/null && CART_SV="$(cygpath -m "$CART_SV")" && export CART_SV
    WSLENV=HZS:SEED:N:EXTRA:REUSE:GEN:TAGX:CART_SV/p MSYS_NO_PATHCONV=1 exec wsl -e bash "$(echo "$HERE" | sed -e 's,^/\([a-zA-Z]\)/,/mnt/\L\1/,')/run.sh" "$@"
fi
FPGA="$HERE/../.."
OUT="$HERE/out"
mkdir -p "$OUT"
HZS="${HZS:-3579545 5369318 7159090 10738635}"
SEED="${SEED:-1}"
N="${N:-120}"
CASES="${*:-0:60:0 1:60:0 0:70:0 1:70:0 0:60:1}"

SRC="$FPGA/src/board/board_id.sv $FPGA/src/board/wt200b/board_wt200b_config.sv $FPGA/config/v9990.sv \
 $FPGA/src/peripheral/msx/bus.sv $FPGA/src/peripheral/ram/ram.sv $FPGA/src/peripheral/ram/uma.sv \
 $FPGA/src/peripheral/video/video.sv"
# los paquetes del core (T9990_RESO, T9990_REG, T9990_MEM_CONNECT) antes que sus usuarios
for f in t9990_port t9990_timing t9990 t9990_bitmap t9990_blit t9990_blit_addr t9990_blit_bitmask \
         t9990_blit_fifo t9990_clock t9990_color_decode t9990_palette t9990_pattern t9990_priority \
         t9990_ram t9990_selector t9990_shift_buffer t9990_sprite; do
    SRC="$SRC $FPGA/v9990/tiny9990/$f.sv"
done
SRC="$SRC $FPGA/src/peripheral/msx/expansion_slot.sv $FPGA/src/board/rev1/board_rev1_bus.sv ${CART_SV:-$FPGA/src/cartridge_v9990.sv}"
SRC="$SRC $HERE/dpb_sim.sv $HERE/sdram_host_model.sv $HERE/megaram_mock.sv $HERE/tb_bus.sv"

status=0
OBJROOT="$HOME/.tb_bus_obj"
for C in $CASES; do
    TOPO=${C%%:*}; R=${C#*:}; BASE=${R%%:*}; MEMPW=${R#*:}
    TAG=${TOPO}_${BASE}_${MEMPW}${TAGX:+_$TAGX}
    OBJ="$OBJROOT/$TAG"
    if [ "$REUSE" = 1 ] && [ -x "$OBJ/vtb" ]; then
        echo "===== TOPO=$TOPO V99_BASE=${BASE}h MEMPW=$MEMPW (binario ya compilado) ====="
    else
        rm -rf "$OBJ"; mkdir -p "$OBJ"
        echo "===== compilando TOPO=$TOPO V99_BASE=${BASE}h MEMPW=$MEMPW $GEN ====="
        if ! verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
                --top-module tb_bus -GTOPO=$TOPO -GV99_BASE=8\'h$BASE -GMEMPW=$MEMPW $GEN \
                --Mdir "$OBJ" -o vtb $SRC > "$OUT/build_$TAG.log" 2>&1; then
            grep -E '%Error|error' "$OUT/build_$TAG.log" | head -20
            echo "BUILD_FAIL $C"; status=1; continue
        fi
    fi
    # las frecuencias en paralelo
    for HZ in $HZS; do
        stdbuf -oL "$OBJ/vtb" +HZ=$HZ +SEED=$SEED +N=$N $EXTRA > "$OUT/tb_${TAG}_${HZ}.log" 2>&1 &
    done
    wait
    for HZ in $HZS; do
        LOG="$OUT/tb_${TAG}_${HZ}.log"
        echo "--- TOPO=$TOPO BASE=${BASE}h MEMPW=$MEMPW HZ=$HZ: $(grep -E '^(BUS_OK|BUS_FAIL|TB_TIMEOUT)' "$LOG" || echo 'SIN VEREDICTO')"
        grep -qE '^BUS_OK' "$LOG" || status=1
    done
done
exit $status
