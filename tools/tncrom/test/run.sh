#!/usr/bin/env bash
#
# run.sh -- banco del host de tncrom (gcc; en WSL o cualquier Linux)
#
# BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
#
# Compila src/ y lib/ de tncrom para el host con TNCROM_HOST_TEST (sin el
# ensamblador de la BIOS ni del DOS: los sustituye host_mock.c) y corre
# test_tncrom. Deja en $OUT (por defecto ~/.cache/v99tang_tncrom_test) la
# salida (test_tncrom.log) y las trazas tncrom_*.trc que reproduce
# fpga/tb/megaram/run.sh tncrom. Sale con 1 si no imprime "RESULTADO: PASA".
#
#   wsl -e bash -lc "cd /mnt/c/<repo>/tools/tncrom/test && ./run.sh"
#
set -eu
cd "$(dirname "$0")"
OUT=${OUT:-$HOME/.cache/v99tang_tncrom_test}
mkdir -p "$OUT/obj"

CC=${CC:-gcc}
CFLAGS="-std=gnu11 -O1 -g -Wall -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -Wno-unused-function
        -include host_types.h -DTNCROM_HOST_TEST -I ../lib -I ../src -I ."

objs=()
for f in ../src/main.c ../src/config.c ../src/param.c ../src/rom_table.c ../lib/tools.c ../lib/rom_tools.c host_mock.c test_tncrom.c; do
    o="$OUT/obj/$(basename "${f%.c}").o"
    extra=""
    [ "$(basename "$f")" = "main.c" ] && extra="-Dmain=tncrom_main"
    $CC $CFLAGS $extra -c "$f" -o "$o"
    objs+=("$o")
done
$CC -o "$OUT/test_tncrom" "${objs[@]}"

rc=0
"$OUT/test_tncrom" "$OUT" > "$OUT/test_tncrom.log" 2>&1 || rc=$?
grep -E "^(---|  FALLO|  traza|comprobaciones|RESULTADO)" "$OUT/test_tncrom.log"
grep -q "RESULTADO: PASA" "$OUT/test_tncrom.log" || rc=1
echo "salida en $OUT/test_tncrom.log"
exit $rc
