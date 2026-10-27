#!/bin/bash
# run_t9990_palette.sh -- paleta del T9990 por P#1 (tb_t9990_palette.sv) con el UMA de la WonderTANG:
# escribe R, G y B de las 64 entradas (G distinto de B) y las lee de vuelta, en autoincremento,
# apuntando a cada componente y con PLTAIH=1, con la pantalla encendida en B1. Pasa con PAL_OK.
# Verilator 5.020 en WSL; se relanza dentro de WSL si se llama desde Git Bash. Objetos en
# ~/.cache/v99tang_core de WSL. V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
cd "$(dirname "$0")/../.."
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    WSLENV=VOPT MSYS_NO_PATHCONV=1 exec wsl -d Ubuntu-24.04 -- bash "$(pwd | sed s,^/c/,/mnt/c/,)/tb/core/run_t9990_palette.sh" "$@"
fi
source tb/core/core_sources.sh
T=$HOME/.cache/v99tang_core/pal_$(echo "$VOPT" | md5sum | cut -c1-8); mkdir -p $T
echo "== verilator $VOPT -> $T"
verilator $VFLAGS $VOPT --top-module tb_t9990_palette --Mdir $T -o vtb_t9990_pal $CORE_SRC tb/core/tb_t9990_palette.sv > $T/build.log 2>&1 \
    || { grep -E '%Error' $T/build.log | head; exit 1; }
$T/vtb_t9990_pal +verilator+error+limit+1000000 | grep -v '^- ' | tee $T/run.log
grep -q PAL_OK $T/run.log
