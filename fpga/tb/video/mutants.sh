#!/usr/bin/env bash
# mutants.sh -- prueba de sensibilidad del banco: compila copias del RTL con un
# fallo metido a proposito y comprueba que el banco las rechaza (RESULT FAIL).
# En WSL: cd fpga/tb/video && ./mutants.sh
# En los textos, "\n" (barra y n) es un salto de linea.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fpga="$(cd "$here/../.." && pwd)"
mut="$here/build/mut"
jobs="${JOBS:-6}"
mkdir -p "$mut"

# nombre | fichero | texto original | texto mutado | plusargs del caso
mutants=(
"pal_backporch|board_rev1_tmds.sv|parameter           V_BACKPORCH_PAL = 40,|parameter           V_BACKPORCH_PAL = 41,|+MODE=1 +PAL=1 +PAT=0"
"pal_active|board_rev1_tmds.sv|parameter           V_ACTIVE_PAL = 576,|parameter           V_ACTIVE_PAL = 574,|+MODE=2 +PAL=1 +PAT=0"
"ntsc_backporch|board_rev1_tmds.sv|parameter           V_BACKPORCH = 33,|parameter           V_BACKPORCH = 34,|+MODE=2 +PAT=0"
"tmds_pal_ignored|board_rev1_tmds.sv|frame_pal <= in_pal;|frame_pal <= 1'b0;|+MODE=3 +PAL=1 +PAT=0"
"upscan_pal_ignored|video_upscan.sv|out_pal <= out_pal_sync[1];|out_pal <= 1'b0;|+MODE=1 +PAL=1 +PAT=0"
"nearest_tie_to_p|video_upscan.sv|                        4'h3:    OUT <= R_DATA_P;           // p3_c1\n                        4'h0, 4'h4, 4'h1, 4'h2:|                        4'h3, 4'h2: OUT <= R_DATA_P;        // p3_c1\n                        4'h0, 4'h4, 4'h1:|+MODE=3 +PAT=2"
"nearest_b2_choice|video_upscan.sv|                        4'h1, 4'h3, 4'h5:\n|                        4'h1, 4'h3:\n|+MODE=2 +PAT=2"
"nearest_b4_skip|video_upscan.sv|((out_state == 4'h7) ? 2'd2 : 2'd1)|((out_state == 4'h0) ? 2'd2 : 2'd1)|+MODE=4 +PAT=0"
"blend_coef_b2|video_upscan.sv|                        4'h3:    OUT <= p6_c2[10:3];        // 11111122     12|                        4'h3:    OUT <= p5_c3[10:3];        // 11111122     12|+MODE=2 +PAT=2"
"row_reset|video_upscan.sv|out_line_cnt <= IN.FIELD ? (ROW_COUNT-1) : 0;|out_line_cnt <= IN.FIELD ? (ROW_COUNT-1) : 1;|+MODE=1 +PAT=0"
"field_shift|video_upscan.sv|out_line_toggle <= IN.FIELD;|out_line_toggle <= 1'b0;|+MODE=3 +IL=1 +PAT=0"
"pal_at_vs_start|video_upscan.sv|else if(!out_prev_in_vs_n && out_in_vs_n) out_pal|else if(out_prev_in_vs_n && !out_in_vs_n) out_pal|+SEQ=2 +MODE=2 +PAT=0 +PALLAG=13680 +FRAMES=4"
"tmds_pal_at_vs|board_rev1_tmds.sv|else if(v_cnt == 10'(V_PAL_LATCH))  frame_pal|else if(prev_vs && !in_vs_n)  frame_pal|+SEQ=2 +MODE=1 +PAT=0 +PALLAG=-1 +FRAMES=4"
"tmds_pal_late|board_rev1_tmds.sv|parameter           V_PAL_LATCH = 20,|parameter           V_PAL_LATCH = 38,|+SEQ=2 +MODE=4 +PAT=0 +PALLAG=-1 +FRAMES=4"
)

one() {   # una linea de la tabla -> una linea de resultado
    local name file orig new args d res first
    IFS='|' read -r name file orig new args <<< "$1"
    d="$mut/$name"; rm -rf "$d"; mkdir -p "$d/src"
    cp "$fpga/src/peripheral/video/video.sv" "$fpga/src/peripheral/video/video_upscan.sv" "$fpga/src/board/rev1/board_rev1_tmds.sv" "$d/src/"
    python3 - "$d/src/$file" "$orig" "$new" > "$d/apply.log" 2>&1 <<'PY' || { echo "$name: no se pudo aplicar ($(cat "$d/apply.log"))"; return; }
import sys
nl = chr(92) + 'n'          # "\n" literal de la tabla -> salto de linea
p, a, b = sys.argv[1], sys.argv[2].replace(nl, '\n'), sys.argv[3].replace(nl, '\n')
s = open(p, encoding='utf-8').read()
if s.count(a) != 1: sys.exit("texto original no unico: %d" % s.count(a))
open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(a, b))
PY
    verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-DEFPARAM -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD --timescale 1ns/1ps \
        --top-module tb_video -Mdir "$d/obj" -o tb_video \
        "$d/src/video.sv" "$d/src/video_upscan.sv" "$d/src/board_rev1_tmds.sv" \
        "$here/ref/video_upscan_orig.sv" "$here/ref/board_rev1_tmds_orig.sv" \
        "$here/sim/dpb_sim.sv" "$here/sim/dvi_tx_stub.sv" "$here/tb_video.sv" > "$d/verilator.log" 2>&1 \
        || { echo "$name: no compila"; return; }
    "$d/obj/tb_video" $args +FRAMES=1 > "$d/run.log" 2>&1
    res="$(grep -E '^RESULT' "$d/run.log" || echo 'RESULT NO_TERMINA')"
    first="$(grep -m1 -E '^ERROR' "$d/run.log" | cut -c1-110)"
    if [[ "$res" == RESULT\ FAIL* ]]; then printf '%-20s detectado   %s | %s\n' "$name" "$res" "$first"
    else printf '%-20s NO DETECTADO %s\n' "$name" "$res"; fi
}
export -f one
export mut fpga here

printf '%s\0' "${mutants[@]}" | xargs -0 -P "$jobs" -n 1 bash -c 'one "$1"' _ > "$mut/resumen.txt"
sort "$mut/resumen.txt"
fails=$(grep -c -v ' detectado ' "$mut/resumen.txt")
echo "MUTANTES: $fails de ${#mutants[@]} sin detectar"
[ "$fails" -eq 0 ]
