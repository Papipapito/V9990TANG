#!/usr/bin/env bash
# run.sh -- compila el banco del video con Verilator y corre la matriz de casos.
# En WSL:  cd fpga/tb/video && ./run.sh            (matriz completa)
#          ./run.sh build                           (solo compilar)
#          ./run.sh one [chip] +MODE=3 +PAL=1 ...   (un caso; "chip" = RTL sin el segundo driver)
#          ./run.sh pallag                          (barrido de +PALLAG: hasta donde aguanta)
#          JOBS=n ./run.sh ...                      (casos en paralelo, 6 por defecto)
#
# Dos compilaciones del mismo banco:
#   obj/      el RTL tal cual (upscan nuevo y copia del hito 1 en ref/)
#   obj_chip/ los mismos ficheros pasados por sin_driver.py: sin el segundo driver
#             de R_ADDR en B4, que Verilator resuelve distinto que Gowin (el netlist
#             de Gowin es igual al RTL sin esa linea: gowin_netlist/run_nl.sh). Solo
#             cambia B4; los casos CHIP_* son la matriz de B4 con lo que hace el chip.
# Salida: build/logs/<caso>.log y build/logs/resumen.txt (una linea por caso).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fpga="$(cd "$here/../.." && pwd)"
build="$here/build"
jobs="${JOBS:-6}"
mkdir -p "$build/logs" "$build/chip_src"

# las copias del hito 1 tienen que seguir siendo las generadas por make_ref.sh
( cd "$here" && tail -n 2 ref/SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --quiet ) || { echo "ref/ no coincide con ref/SHA256SUMS: regenerar con make_ref.sh"; exit 2; }

compile1() {   # obj, video_upscan.sv, video_upscan_orig.sv
    local obj="$1"
    verilator --binary --timing -j 0 -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-DEFPARAM -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD --timescale 1ns/1ps \
        --top-module tb_video -Mdir "$build/$obj" -o tb_video \
        "$fpga/src/peripheral/video/video.sv" \
        "$2" \
        "$fpga/src/board/rev1/board_rev1_tmds.sv" \
        "$3" \
        "$here/ref/board_rev1_tmds_orig.sv" \
        "$here/sim/dpb_sim.sv" \
        "$here/sim/dvi_tx_stub.sv" \
        "$here/tb_video.sv" > "$build/logs/verilator_$obj.log" 2>&1
    local rc=$?
    grep -E '^%(Error|Warning)' "$build/logs/verilator_$obj.log" | sort | uniq -c | sort -rn | head -40 > "$build/logs/verilator_warnings_$obj.txt"
    if [ $rc -ne 0 ]; then tail -40 "$build/logs/verilator_$obj.log"; echo "COMPILACION FALLIDA ($obj)"; exit 1; fi
}
compile() {
    python3 "$here/sin_driver.py" "$fpga/src/peripheral/video/video_upscan.sv" "$build/chip_src/video_upscan.sv" 1 || exit 2
    python3 "$here/sin_driver.py" "$here/ref/video_upscan_orig.sv" "$build/chip_src/video_upscan_orig.sv" 1 || exit 2
    compile1 obj      "$fpga/src/peripheral/video/video_upscan.sv" "$here/ref/video_upscan_orig.sv"
    compile1 obj_chip "$build/chip_src/video_upscan.sv"            "$build/chip_src/video_upscan_orig.sv"
}

# un caso: nombre obj plusargs...  -> build/logs/<nombre>.log y .res
runcase() {
    local name="$1" obj="$2"; shift 2
    "$build/$obj/tb_video" "$@" > "$build/logs/$name.log" 2>&1
    local res
    res="$(grep -E '^RESULT' "$build/logs/$name.log" || echo 'RESULT NO_TERMINA')"
    printf '%-32s %s\n' "$name" "$res" > "$build/logs/$name.res"
}
export -f runcase
export build

# corre la lista de casos (una linea por caso: nombre obj plusargs...) en paralelo
# y escribe el resumen en el orden de la lista
runlist() {   # fichero_lista fichero_resumen
    xargs -P "$jobs" -L 1 bash -c 'runcase "$@"' _ < "$1"
    : > "$2"
    while read -r name _; do cat "$build/logs/$name.res"; done < "$1" | tee "$2"
}

matrix() {
    for m in 1 2 3 4; do
      for pal in 0 1; do
        for il in 0 1; do
          for pat in 0 1 2; do
            echo "B${m}_pal${pal}_il${il}_pat${pat} obj +MODE=$m +PAL=$pal +IL=$il +PAT=$pat +PHASE=137 +FRAMES=2"
          done
        done
      done
    done
    for ph in 13 61 89 255 333 399; do
      echo "B4_pal1_il1_pat2_ph${ph} obj +MODE=4 +PAL=1 +IL=1 +PAT=2 +PHASE=$ph +FRAMES=2"
      echo "B1_pal0_il1_pat0_ph${ph} obj +MODE=1 +PAL=0 +IL=1 +PAT=0 +PHASE=$ph +FRAMES=2"
    done
    for pat in 0 2; do
      echo "SEQ_pat${pat} obj +SEQ=1 +PAT=$pat +PHASE=211"
    done
    # PAL que cambia de cuadro a cuadro: un ciclo antes de VS_n (lo natural si el T9990 lo fija en
    # v_rst), en el mismo flanco, 3 ciclos y 2 lineas tarde, y 250 lineas antes (en el cuadro anterior)
    for m in 1 2 3 4; do
      for il in 0 1; do
        for lag in -1 0 3 13680 -1710000; do
          echo "SEQ2_B${m}_il${il}_lag${lag} obj +SEQ=2 +MODE=$m +IL=$il +PAT=0 +PALLAG=$lag +PHASE=173 +FRAMES=10"
        done
      done
    done
    # B4 con lo que hace el chip (sin el segundo driver de R_ADDR)
    for pal in 0 1; do
      for il in 0 1; do
        for pat in 0 1 2; do
          echo "CHIP_B4_pal${pal}_il${il}_pat${pat} obj_chip +MODE=4 +PAL=$pal +IL=$il +PAT=$pat +PHASE=137 +FRAMES=2"
        done
      done
    done
    for ph in 13 61 89 255 333 399; do
      echo "CHIP_B4_pal1_il1_pat2_ph${ph} obj_chip +MODE=4 +PAL=1 +IL=1 +PAT=2 +PHASE=$ph +FRAMES=2"
    done
    echo "CHIP_SEQ_pat0 obj_chip +SEQ=1 +PAT=0 +PHASE=211"
}

# barrido de +PALLAG (ciclos de CLK_BASE; una linea = 6840): hasta donde aguanta el muestreo de PAL
# al final del VSYNC de entrada. Por arriba el limite son las 3 lineas del VSYNC (20520 ciclos) menos
# el paso por los flops; por abajo, el cuadro anterior menos esas 3 lineas (NTSC: 259 lineas = 1771560)
pallag() {
    for m in 4 1; do
      for lag in -1778400 -1771560 -1764720 -1757880 -1710000 -68400 -6840 -1000 -20 -1 0 1 5 20 100 1000 6840 13680 17100 19000 19800 20000 20200 20520 21000 27360; do
        echo "LAG_B${m}_lag${lag} obj +SEQ=2 +MODE=$m +IL=0 +PAT=0 +PALLAG=$lag +PHASE=173 +FRAMES=10"
      done
    done
}

case "${1:-all}" in
    build) compile ;;
    one)
        shift; obj=obj
        if [ "${1:-}" = chip ]; then obj=obj_chip; shift; fi
        compile; "$build/$obj/tb_video" "$@" ;;
    pallag)
        compile
        pallag > "$build/lista_pallag.txt"
        runlist "$build/lista_pallag.txt" "$build/logs/resumen_pallag.txt"
        ;;
    all)
        compile
        matrix > "$build/lista.txt"
        runlist "$build/lista.txt" "$build/logs/resumen.txt"
        n_ok=$(grep -c 'RESULT PASS' "$build/logs/resumen.txt")
        n_all=$(wc -l < "$build/logs/resumen.txt")
        echo "TOTAL: $n_ok de $n_all casos pasan"
        [ "$n_ok" -eq "$n_all" ]
        ;;
    *) echo "uso: run.sh [all|build|one [chip] +ARGS...|pallag]"; exit 2 ;;
esac
