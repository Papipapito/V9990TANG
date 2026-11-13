#!/bin/bash
# run_t9990_vscroll.sh [plusargs] -- reinicio del scroll vertical a mitad de pantalla (tb_t9990_vscroll.sv): el
# split de Xybots-V9990 (R#17 escrito en la linea 95) en B1 y en los dos planos de P1, con la escritura en
# varios puntos de la linea y R#18 cambiado a mitad de cuadro. Cada caso compara la linea de VRAM pedida en
# cada linea de pantalla con openMSX. Pasa con VSCROLL_OK en todos. Sin argumentos corre la lista; con
# argumentos, un solo caso con esos plusargs. Los tres ultimos casos de la lista son PAL (+R7=8).
# Verilator 5.020 en WSL; se relanza dentro de WSL si se llama desde Git Bash. Objetos en
# ~/.cache/v99tang_core de WSL (OBJTAG: otro directorio con las mismas VOPT).
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
cd "$(dirname "$0")/../.."
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    WSLENV=VOPT:OBJTAG MSYS_NO_PATHCONV=1 exec wsl -d Ubuntu-24.04 -- bash "$(pwd | sed s,^/c/,/mnt/c/,)/tb/core/run_t9990_vscroll.sh" "$@"
fi
source tb/core/core_sources.sh
T=$HOME/.cache/v99tang_core/vscroll_$(echo "$VOPT$OBJTAG" | md5sum | cut -c1-8); mkdir -p $T
echo "== verilator $VOPT -> $T"
verilator $VFLAGS $VOPT --top-module tb_t9990_vscroll --Mdir $T -o vtb_t9990_vscroll $CORE_SRC tb/core/tb_t9990_vscroll.sv > $T/build.log 2>&1 \
    || { grep -E '%Error' $T/build.log | head; exit 1; }
if [ $# -gt 0 ]; then CASES=("$*"); else
    CASES=("" "+WH=10" "+WH=24" "+WH=27" "+WH=330" "+R18AT=60"
           "+WLINE=150 +WH=200" "+PLANE=4 +R6=0" "+PLANE=5 +R6=0"
           "+R7=8" "+R7=8 +PLANE=4 +R6=0" "+R7=8 +WLINE=150 +WH=200")
fi
R=0
for C in "${CASES[@]}"; do
    $T/vtb_t9990_vscroll +verilator+error+limit+1000000 $C | grep -v '^- ' > $T/run.log
    if grep -q VSCROLL_OK $T/run.log; then echo "OK    $C"; else echo "FALLO $C"; grep -E 'MISMATCH|CHECK|TIMEOUT' $T/run.log | head -8; R=1; fi
done
[ $R -eq 0 ] && echo "VSCROLL_OK (${#CASES[@]} casos)"
exit $R
