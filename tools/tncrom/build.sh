#!/usr/bin/env bash
#
# build.sh -- compila TNCROM.COM (MSX-DOS 2) con SDCC
#
# BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
#
# Upstream (buppu3/tnCart, tnCartWonder) lo compilaba con z88dk:
#   zcc +msx -subtype=msxdos -O3 -o../bin/TNCROM.COM main.c ...
# (comentario al principio de src/main.c). Aqui se compila con SDCC 4.5 y un
# crt0 propio (sdcc/crt0_msxdos.s + sdcc/crt_msxdos.c).
#
# Uso (Git Bash en Windows, o cualquier shell con sdcc en el PATH):
#   tools/tncrom/build.sh            -> tools/tncrom/bin/TNCROM.COM
#   SDCC_BIN=/ruta/a/sdcc/bin tools/tncrom/build.sh
# Objetos, .map y .ihx en tools/tncrom/build/ (no se versiona).
#
set -eu
cd "$(dirname "$0")"

if [ -z "${SDCC_BIN:-}" ]; then
    if command -v sdcc >/dev/null 2>&1; then
        SDCC_BIN=$(dirname "$(command -v sdcc)")
    elif [ -x "/c/Program Files/SDCC/bin/sdcc.exe" ]; then
        SDCC_BIN="/c/Program Files/SDCC/bin"
    else
        echo "no encuentro sdcc: pon SDCC_BIN" >&2; exit 2
    fi
fi
SDCC="$SDCC_BIN/sdcc"
SDAS="$SDCC_BIN/sdasz80"
MAKEBIN="$SDCC_BIN/makebin"

B=build
rm -rf "$B"
mkdir -p "$B" bin

CFLAGS="-mz80 --opt-code-size --std-sdcc11 -I lib -I src"
SRCS="sdcc/crt_msxdos.c src/main.c src/config.c src/param.c src/rom_table.c lib/bdos.c lib/tools.c lib/rom_tools.c lib/reboot.c"

"$SDAS" -g -o "$B/crt0_msxdos.rel" sdcc/crt0_msxdos.s
RELS="$B/crt0_msxdos.rel"
for f in $SRCS; do
    o="$B/$(basename "${f%.c}").rel"
    "$SDCC" $CFLAGS -c "$f" -o "$o"
    RELS="$RELS $o"
done

# 0100h: jp init (crt0); el codigo desde 0110h; los datos detras del codigo
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x0110 --data-loc 0 -o "$B/tncrom.ihx" $RELS
"$MAKEBIN" -p -o 256 "$B/tncrom.ihx" bin/TNCROM.COM

# el buffer de transferencia vive en 6000h-7FFFh (main.c) y la pagina 2 se
# cambia al cartucho durante la copia: codigo y datos tienen que acabar antes
heap=$(grep -E '^ +0000[0-9A-Fa-f]{4} +s__HEAP' "$B/tncrom.map" | awk '{print $1}')
[ -z "$heap" ] && heap=$(grep -E 's__HEAP' "$B/tncrom.map" | grep -Eo '[0-9A-Fa-f]{8}' | head -1)
end=$((16#$heap))
size=$(wc -c < bin/TNCROM.COM)
printf "TNCROM.COM: %d bytes; codigo y datos hasta %04Xh (limite 6000h)\n" "$size" "$end"
if [ "$end" -gt $((0x6000)) ]; then
    echo "ERROR: el programa pisa el buffer de 6000h" >&2
    exit 1
fi
