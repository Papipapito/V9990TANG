#!/bin/bash
# ============================================================================
# run_m1spur.sh -- banco dirigido del pre-WAIT espurio en el M1 (tb_m1spur.sv)
# con Verilator 5.020 en WSL.
#
# Uso (desde Git Bash o desde WSL): fpga/tb/bus/run_m1spur.sh
# Variables: DIORQS="0 10 20" (retraso de la subida de /IORQ o /SLTSL frente a
#            /RD-/WR, ns), BUS_SV=<fichero> (otro board_rev1_bus.sv, p. ej. el
#            de un commit anterior para ver el fallo).
# Compila SRC = 0 (E/S a 60h) y SRC = 1 (lectura de nuestra ranura con
# PREWAIT_MEM_EN) y los corre con cada DIORQ; logs en fpga/tb/bus/out/m1spur_*.
# Sale con 0 si todo da M1SPUR_OK.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    [ -n "$BUS_SV" ] && command -v cygpath >/dev/null && BUS_SV="$(cygpath -m "$BUS_SV")" && export BUS_SV
    WSLENV=DIORQS:BUS_SV/p MSYS_NO_PATHCONV=1 exec wsl -e bash "$(echo "$HERE" | sed -e 's,^/\([a-zA-Z]\)/,/mnt/\L\1/,')/run_m1spur.sh" "$@"
fi
FPGA="$HERE/../.."
OUT="$HERE/out"
mkdir -p "$OUT"
DIORQS="${DIORQS:-0 10 20}"
SRC_F="$FPGA/src/board/board_id.sv $FPGA/src/board/wt200b/board_wt200b_config_xtal.sv $FPGA/config/v9990.sv \
 $FPGA/src/peripheral/msx/bus.sv ${BUS_SV:-$FPGA/src/board/rev1/board_rev1_bus.sv} $HERE/tb_m1spur.sv"
status=0
for SRC in 0 1; do
    OBJ="$HOME/.tb_bus_obj/m1spur_$SRC"
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    if ! verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
            --top-module tb_m1spur -GSRC=$SRC --Mdir "$OBJ" -o vm1 $SRC_F > "$OUT/build_m1spur_$SRC.log" 2>&1; then
        grep -E '%Error' "$OUT/build_m1spur_$SRC.log" | head -20
        echo "BUILD_FAIL SRC=$SRC"; status=1; continue
    fi
    for D in $DIORQS; do
        "$OBJ/vm1" +DIORQ=$D > "$OUT/m1spur_${SRC}_$D.log" 2>&1 &
    done
    wait
    for D in $DIORQS; do
        L="$OUT/m1spur_${SRC}_$D.log"
        grep -vE '^- |\$finish' "$L"
        grep -qE '^M1SPUR_OK' "$L" || status=1
    done
done
exit $status
