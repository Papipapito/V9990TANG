#!/usr/bin/env bash
# run_nl.sh -- (WSL) simula el netlist de Gowin de NL_TOP (Icarus + simlib de Gowin)
# y el RTL (Verilator) con el mismo estimulo, y compara las secuencias de OUT en
# todas las resoluciones.
# Antes, en Windows y desde esta carpeta: NL_VAR=hito1|b1|b0 gw_sh build_nl.tcl
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fpga="$(cd "$here/../../.." && pwd)"
simlib="${GOWIN_SIMLIB:-/mnt/c/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw2a/prim_sim.v}"
b="$here/build"; mkdir -p "$b"
fails=0

netlist() {   # variante
    iverilog -g2012 -s tb_nl -o "$b/net_$1" "$here/tb_nl.v" "$here/impl/gwsynthesis/nl_$1.vg" "$simlib" 2> "$b/iverilog_$1.log" \
        || { tail -3 "$b/iverilog_$1.log"; return 1; }
    vvp -n "$b/net_$1" | grep '^OUT' > "$b/out_net_$1.txt"
}
rtl() {       # nombre, video.sv, video_upscan.sv, top
    verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-DEFPARAM -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD --timescale 1ns/1ps \
        --top-module tb_nl -Mdir "$b/obj_$1" -o tb "$2" "$3" "$fpga/tb/video/sim/dpb_sim.sv" "$4" "$here/tb_nl.v" > "$b/verilator_$1.log" 2>&1 \
        || { tail -3 "$b/verilator_$1.log"; return 1; }
    "$b/obj_$1/tb" | grep '^OUT' > "$b/out_rtl_$1.txt"
}
same() {      # a, b, texto
    local n; n=$(wc -l < "$b/$1")
    if [ "$n" -gt 1000 ] && cmp -s "$b/$1" "$b/$2"; then echo "IGUAL     $3 ($n ciclos)"
    else echo "DISTINTO  $3 ($(diff "$b/$1" "$b/$2" | grep -c '^<') de $n ciclos)"; fails=$((fails+1)); fi
}
differs_in() { # a, b: resoluciones (0=B1 ... 3=B4 ... 6=720x480) con diferencias
    diff "$b/$1" "$b/$2" | grep '^<' | awk '{print $4}' | sort -u | tr '\n' ' '
}

# RTL tal cual y RTL sin el segundo driver de R_ADDR (../sin_driver.py: el
# "default: R_ADDR <= R_ADDR" del case de OUT en B4), para las tres variantes
hv="$here/impl/video_hito1.sv"; hu="$here/impl/video_upscan_hito1.sv"
cu="$fpga/src/peripheral/video/video_upscan.sv"; cv="$fpga/src/peripheral/video/video.sv"
python3 "$here/../sin_driver.py" "$hu" "$b/video_upscan_hito1_sin_driver.sv" 1 || exit 2
python3 "$here/../sin_driver.py" "$cu" "$b/video_upscan_sin_driver.sv" 1 || exit 2
netlist hito1
rtl hito1 "$hv" "$hu" "$here/top_hito1.sv"
rtl hito1_sin_driver "$hv" "$b/video_upscan_hito1_sin_driver.sv" "$here/top_hito1.sv"
for v in b1 b0; do
    netlist $v
    rtl $v "$cv" "$cu" "$here/top_$v.sv"
    rtl ${v}_sin_driver "$cv" "$b/video_upscan_sin_driver.sv" "$here/top_$v.sv"
done

# lo que tiene que salir igual
same out_net_b1.txt out_net_hito1.txt "netlist Gowin BLEND=1 == netlist Gowin del hito 1"
same out_net_hito1.txt out_rtl_hito1_sin_driver.txt "netlist Gowin del hito 1 == RTL del hito 1 sin el segundo driver de R_ADDR"
same out_net_b1.txt out_rtl_b1_sin_driver.txt "netlist Gowin BLEND=1 == RTL BLEND=1 sin el segundo driver"
same out_net_b0.txt out_rtl_b0_sin_driver.txt "netlist Gowin BLEND=0 == RTL BLEND=0 sin el segundo driver"
same out_rtl_b1.txt out_rtl_hito1.txt "RTL BLEND=1 == RTL del hito 1 (Verilator, los dos con el segundo driver)"
# informativo: donde difieren Verilator con el segundo driver y el netlist, y BLEND=0 de BLEND=1
for v in hito1 b1 b0; do
    if cmp -s "$b/out_net_$v.txt" "$b/out_rtl_$v.txt"; then echo "(info)    netlist Gowin $v == RTL $v tal cual en Verilator"
    else echo "(info)    netlist Gowin $v != RTL $v tal cual en Verilator: $(diff "$b/out_net_$v.txt" "$b/out_rtl_$v.txt" | grep -c '^<') ciclos, resoluciones: $(differs_in out_net_$v.txt out_rtl_$v.txt)(3 = B4)"; fi
done
echo "(info)    BLEND=0 frente a BLEND=1 (netlist): $(diff "$b/out_net_b0.txt" "$b/out_net_b1.txt" | grep -c '^<') ciclos distintos, resoluciones: $(differs_in out_net_b0.txt out_net_b1.txt)"
echo "NETLIST: $fails comparaciones distintas"
[ $fails -eq 0 ]
