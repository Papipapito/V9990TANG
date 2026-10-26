#!/usr/bin/env bash
# run_dpb_check.sh -- compara el modelo dpb_sim.sv con el DPB de la simlib de Gowin (Icarus, WSL)
# Uso: GOWIN_SIMLIB=/mnt/c/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw2a/prim_sim.v ./run_dpb_check.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
simlib="${GOWIN_SIMLIB:-/mnt/c/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw2a/prim_sim.v}"
out="$here/../build/dpb"
mkdir -p "$out"
awk '/^module DPB \(/{p=1} p{print} p&&/^endmodule/{exit}' "$simlib" | sed 's/^module DPB (/module DPB_GOWIN (/' > "$out/dpb_gowin.v"
iverilog -g2012 -o "$out/tb_dpb" "$here/tb_dpb_vs_gowin.sv" "$here/dpb_sim.sv" "$out/dpb_gowin.v"
vvp -n "$out/tb_dpb" | tail -5
