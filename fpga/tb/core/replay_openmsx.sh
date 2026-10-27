#!/bin/bash
# replay_openmsx.sh <ROM> <romtype de openMSX> <segundos> <tag> [dir]
#   Traza una ROM en openMSX y la reproduce en el core: VRAM del banco frente a la de openMSX.
#   1. Copia mk_trace.py y mk_replay.py del MSXimus Z (TRACE_TOOLS) a <dir> (por defecto
#      fpga/tb/core/trace, fuera de git) y corre openMSX sin pantalla (C-BIOS_MSX2+, -ext gfx9000)
#      <segundos> de tiempo emulado: toda la E/S de 60h-6Fh y, al final, la VRAM, la paleta y los
#      registros del V9990 (<tag>_io.txt, <tag>_vram.bin, ...). mk_trace.py escribe junto a si mismo:
#      por eso se copia. Tarda (10 s de GNG2M: 9 minutos).
#   2. mk_replay.py: <tag>.rpl con las escrituras a 60h-6Fh (la watchpoint read_io de openMSX no
#      dispara: las lecturas no salen en la traza).
#   3. run_t9990_core.sh replay con OMSX=<tag>_vram.bin: compara byte a byte (omsx_vram.py pasa el
#      volcado de openMSX, que es la VRAM fisica de los dos chips, al orden del tiny9990).
# Desde Git Bash (openMSX es de Windows; el banco se relanza en WSL). Rutas sin espacios.
# Ejemplo (la referencia del estudio, GNG2M 10 s):
#   tb/core/replay_openmsx.sh C:/Users/alber/proyectosAI/msx/MSXimus_zynq/files/20260921/v9990_filehunter/rom/GNG2M.ROM KonamiSCC 10 gng
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
set -e
cd "$(dirname "$0")/../.."
ROM=$1; ROMTYPE=$2; SECS=$3; TAG=$4; DIR=${5:-tb/core/trace}
[ -n "$TAG" ] || { echo "uso: replay_openmsx.sh <ROM> <romtype> <segundos> <tag> [dir]"; exit 2; }
TRACE_TOOLS=${TRACE_TOOLS:-C:/Users/alber/proyectosAI/msx/MSXimus_zynq/fpga/zynq/tools/v9990_trace}
mkdir -p "$DIR"
cp "$TRACE_TOOLS/mk_trace.py" "$TRACE_TOOLS/mk_replay.py" "$DIR/"
python "$DIR/mk_trace.py" "$ROM" "$ROMTYPE" "$SECS" "$TAG"
python "$DIR/mk_replay.py" "$DIR/${TAG}_io.txt" $((SECS * 1000)) "$DIR/$TAG.rpl"
W=$(cd "$DIR" && pwd | sed 's,^/\([a-z]\)/,/mnt/\1/,')
REPLAY=$W/$TAG.rpl VRAMOUT=$W/${TAG}_tb_vram.bin OMSX=$W/${TAG}_vram.bin bash tb/core/run_t9990_core.sh replay
