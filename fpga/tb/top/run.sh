#!/bin/bash
# ============================================================================
# run.sh -- banco de placa entera de V9990TANG (tb_top.sv) con Verilator 5.020
# en WSL.
#
# Uso (desde Git Bash o WSL, en cualquier directorio):
#   fpga/tb/top/run.sh [VARIANTE ...]
# VARIANTE = <cfg>_<variante>: v9990_xtal v9990_sync v9990_megaram_xtal
# v9990_megaram_sync v9990_megaram_nextor_xtal v9990_megaram_nextor_sync (sin
# argumentos, las seis). Cada una se compila una vez
# con la lista de ficheros de fpga/build_common.tcl (filelist.py) y corre:
#   full   escenario completo a 3,58 MHz (arranque, puertos, VRAM, paleta,
#          LMMV, /INT, video NTSC y PAL, MegaRAM, /RESET con /WAIT)
#   io     a 5,37 MHz: lo mismo sin los cuadros de video (una /INT) y con las
#          lecturas de la megaROM contadas, no estrictas
#   nomsx  sin MSX (sin reloj del slot ni /RESET): LED y pines en reposo
# Variables: REUSE=1 (no recompila si el binario existe), RUNS="full io nomsx"
#            (escenarios), OPT=-O1 (optimizacion del C++; -O2 corre algo mas y
#            compila mas despacio), EXTRA="<plusargs>".
# Compila en ~/.tb_top_obj/<variante> (disco de WSL: el 9p de /mnt/c es lento)
# y deja los logs en fpga/tb/top/build/ (ignorado por git). Sale con 0 si todo
# pasa.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    WSLENV=REUSE:RUNS:OPT:EXTRA MSYS_NO_PATHCONV=1 exec wsl -e bash "$(echo "$HERE" | sed -e 's,^/\([a-zA-Z]\)/,/mnt/\L\1/,')/run.sh" "$@"
fi
FPGA="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/build"
mkdir -p "$OUT"
VARS="${*:-v9990_xtal v9990_sync v9990_megaram_xtal v9990_megaram_sync v9990_megaram_nextor_xtal v9990_megaram_nextor_sync}"
RUNS="${RUNS:-full io nomsx}"
OPT="${OPT:--O1}"
OBJROOT="$HOME/.tb_top_obj"
status=0

build() {   # build <variante>
    local V=$1 CFG VAR OBJ FL
    case $V in
        v9990_megaram_nextor_*) CFG=v9990_megaram_nextor ;;
        v9990_megaram_*) CFG=v9990_megaram ;;
        v9990_*)         CFG=v9990 ;;
        *) echo "variante desconocida: $V"; return 1 ;;
    esac
    VAR=${V##*_}
    OBJ="$OBJROOT/$V"
    if [ "$REUSE" = 1 ] && [ -x "$OBJ/vtb" ]; then
        echo "===== $V: binario ya compilado ====="
        return 0
    fi
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    FL=$(python3 "$HERE/filelist.py" "$FPGA" $CFG $VAR "$OBJ/copias" 2> "$OUT/filelist_$V.log") || { cat "$OUT/filelist_$V.log"; return 1; }
    echo "===== compilando $V ($(echo $FL | wc -w) ficheros de build_common.tcl) ====="
    if ! verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-DEFPARAM -Wno-MULTIDRIVEN \
            -Wno-TIMESCALEMOD -Wno-WIDTHCONCAT -Wno-SELRANGE -Wno-UNOPTFLAT --timescale 1ns/1ps \
            --output-split 3000 --output-split-cfuncs 300 -MAKEFLAGS "OPT_FAST=$OPT" \
            --top-module tb_top --Mdir "$OBJ" -o vtb \
            "$HERE/gowin_models.sv" "$FPGA/tb/sdram/sdram_model_bl.v" $FL "$HERE/tb_top.sv" > "$OUT/build_$V.log" 2>&1; then
        grep -E '%Error' "$OUT/build_$V.log" | head -20
        echo "BUILD_FAIL $V"
        return 1
    fi
}

hz_of() { case $1 in io) echo 5369318 ;; *) echo 3579545 ;; esac; }

# compilaciones en paralelo (cada una con -j 8)
pids=()
for V in $VARS; do
    build $V > "$OUT/build_$V.out" 2>&1 &
    pids+=($!)
done
i=0
for V in $VARS; do
    wait ${pids[$i]} || status=1
    cat "$OUT/build_$V.out"
    i=$((i + 1))
done
[ $status = 0 ] || { echo "TOTAL: FALLA (compilacion)"; exit 1; }

# escenarios, todos en paralelo. El modelo de la SDRAM escribe una linea por
# error y, con el controlador en reset, da uno por flanco (MRS con A = 0,
# docs/notas/sdram.md): el filtro deja las 5 primeras de cada mensaje y la
# cuenta (el banco las cuenta aparte, antes y despues de BASE_READY)
sdram_filter() {
    awk '/^  \[SDRAM [0-9]+\] ERROR: / { m = $0; sub(/^  \[SDRAM [0-9]+\] /, "", m); n[m]++; if (n[m] <= 5) print; else if (n[m] == 6) print "  [SDRAM] (mas lineas de \"" m "\": solo se cuentan)"; next }
         { print }
         END { for (m in n) if (n[m] > 5) printf("  [SDRAM] %d lineas de \"%s\"\n", n[m], m) }'
}
for V in $VARS; do
    for R in $RUNS; do
        ( stdbuf -oL "$OBJROOT/$V/vtb" +SCEN=$R +HZ=$(hz_of $R) $EXTRA 2>&1 | sdram_filter > "$OUT/tb_${V}_$R.log" ) &
    done
done
wait
for V in $VARS; do
    for R in $RUNS; do
        LOG="$OUT/tb_${V}_$R.log"
        RES=$(grep -E '^RESULTADO' "$LOG" | head -1)
        if grep -q '^BANCO: PASA' "$LOG"; then
            echo "PASA   $RES"
        else
            echo "FALLA  ${RES:-sin resultado} (ver $LOG)"
            grep -E '^FALLA' "$LOG" | head -8
            status=1
        fi
    done
done
[ $status = 0 ] && echo "TOTAL: PASA" || echo "TOTAL: FALLA"
exit $status
