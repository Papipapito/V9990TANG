#!/bin/bash
# ============================================================================
# run_eq.sh -- equivalencia de BOARD_REV1_BUS con el de main (tb_scan_eq.sv)
# con Verilator 5.020 en WSL.
#
# Uso (desde Git Bash; desde WSL solo si out/board_rev1_bus_main.sv ya existe):
#   fpga/tb/bus/run_eq.sh
# Variables: SEEDS="1 2 3" (semillas), MS=<ms simulados por corrida> (6).
# Saca el BOARD_REV1_BUS de main con git (renombrado a BOARD_REV1_BUS_MAIN y
# su PIN_FILTER a PIN_FILTER_MAIN) a fpga/tb/bus/out/, compila MODE = 0, 1 y 2
# (el 2 es el control: tiene que salir EQ_FAIL) y deja los logs en
# fpga/tb/bus/out/eq_<MODE>_<SEED>.log. Sale con 0 si todo es lo esperado.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
mkdir -p "$OUT"
# el bus de main se saca con el git del lado de Windows (el .git del worktree
# apunta a C:/..., que el git de WSL no entiende)
mk_main() {
    git -C "$HERE/../../.." show main:fpga/src/board/rev1/board_rev1_bus.sv \
        | sed -e 's/\bBOARD_REV1_BUS\b/BOARD_REV1_BUS_MAIN/g' -e 's/\bPIN_FILTER\b/PIN_FILTER_MAIN/g' \
        > "$OUT/board_rev1_bus_main.sv"
}
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    mk_main || exit 1
    WSLENV=SEEDS:MS MSYS_NO_PATHCONV=1 exec wsl -e bash "$(echo "$HERE" | sed -e 's,^/\([a-zA-Z]\)/,/mnt/\L\1/,')/run_eq.sh" "$@"
fi
[ -s "$OUT/board_rev1_bus_main.sv" ] || { echo "falta out/board_rev1_bus_main.sv: lanzar desde Git Bash"; exit 1; }
FPGA="$HERE/../.."
SEEDS="${SEEDS:-1 2 3}"
MS="${MS:-6}"
SRC="$FPGA/src/board/board_id.sv $FPGA/src/board/wt200b/board_wt200b_config.sv $FPGA/config/v9990.sv \
 $FPGA/src/peripheral/msx/bus.sv $FPGA/src/board/rev1/board_rev1_bus.sv $OUT/board_rev1_bus_main.sv $HERE/tb_scan_eq.sv"
status=0
for MODE in 0 1 2; do
    OBJ="$HOME/.tb_bus_obj/eq_$MODE"
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    if ! verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
            --top-module tb_scan_eq -GMODE=$MODE --Mdir "$OBJ" -o veq $SRC > "$OUT/build_eq_$MODE.log" 2>&1; then
        grep -E '%Error' "$OUT/build_eq_$MODE.log" | head -20
        echo "BUILD_FAIL MODE=$MODE"; status=1; continue
    fi
    for S in $SEEDS; do
        "$OBJ/veq" +SEED=$S +MS=$MS > "$OUT/eq_${MODE}_$S.log" 2>&1 &
    done
    wait
    for S in $SEEDS; do
        L="$OUT/eq_${MODE}_$S.log"
        echo "--- MODE=$MODE SEED=$S: $(grep -E '^(EQ_OK|EQ_FAIL)' "$L" || echo 'SIN VEREDICTO')$([ $MODE = 2 ] && echo ' (control: se espera EQ_FAIL)')"
        grep -E 'ciclos comparados|diferencias' "$L"
        if [ $MODE = 2 ]; then grep -qE '^EQ_FAIL' "$L" || status=1
        else grep -qE '^EQ_OK' "$L" || status=1; fi
    done
done
exit $status
