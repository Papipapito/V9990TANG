#!/bin/bash
# ============================================================================
# fpga/tb/sdram/run.sh -- banco del UMA + sdram.sv (hito 4) con Verilator en WSL
#
# Uso (desde Git Bash o desde WSL):   fpga/tb/sdram/run.sh [US]
#   US = microsegundos simulados por caso (2000 por defecto).
#   HITO1_REF=<commit> elige la referencia del hito 1 (20936e6 por defecto).
#   OUT=<fichero> escribe el resumen ahi en lugar de resultados.txt (solo si se
#   lanza desde WSL: las variables de Git Bash no pasan a WSL).
#
# Compila seis builds en /tmp (el 9p de /mnt/c es lento):
#   new    uma.sv y sdram.sv de este arbol (INT_REFRESH = 1)
#   int0   lo mismo con -GINT_REFRESH=0 (control: sin temporizador)
#   hito1  uma.sv y sdram.sv del commit HITO1_REF (control y referencia de la
#          latencia del canal 1); a su sdram.sv se le aplica la misma linea
#          `ifdef VERILATOR que lleva la de este arbol (sin ella no compila)
#   mut    uma.sv de este arbol con el refresco interno pasando por done_ch y
#          DOUT capturado tras cualquier operacion (el diseno que se evita:
#          control de la comprobacion de DOUT estable)
#   slack0 sdram.sv de este arbol con un ciclo mas por acceso (STATE_END =
#          IDLE + 9: 10 ciclos ocupados en ranuras de 10, sin el ciclo de
#          holgura; control de la comprobacion de cadencia 'slot')
#   slow   lo mismo con dos ciclos mas (STATE_END = IDLE + 10: 11 ciclos en
#          ranuras de 10; la cadencia se rompe y el canal 1 lee datos
#          rancios: control de 'slot' y de los datos del canal 1)
# y corre la matriz a 108 y a 107,386 MHz. Escribe el resumen en
# fpga/tb/sdram/resultados.txt y sale con 1 si algun caso no da lo esperado.
# ============================================================================
cd "$(dirname "$0")" || exit 2
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    # MSYS_NO_PATHCONV: que Git Bash no convierta /mnt/c/... en una ruta de Windows
    MSYS_NO_PATHCONV=1 exec wsl -e bash "$(pwd | sed 's,^/\([a-zA-Z]\)/,/mnt/\L\1/,')/run.sh" "$@"
fi
set -u
TB=$(pwd)
FPGA=$(cd ../.. && pwd)
REPO=$(cd ../../.. && pwd)
US=${1:-2000}
HITO1_REF=${HITO1_REF:-20936e6}
W=/tmp/sdtb_$$
mkdir -p "$W"/new "$W"/int0 "$W"/hito1 "$W"/mut "$W"/slack0 "$W"/slow "$W"/src "$W"/logs
trap 'rm -rf "$W"' EXIT

# git desde WSL: en un worktree, .git es un fichero con una ruta de Windows
gd=""
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    gitc() { git -C "$REPO" "$@"; }
    HEAD_DESC=$(git -C "$REPO" log --oneline -1)
else
    gd=$(sed -n 's/^gitdir: //p' "$REPO/.git" | sed 's,^\([A-Za-z]\):,/mnt/\L\1,')
    common=$(cd "$gd" && cd "$(cat commondir 2>/dev/null || echo .)" && pwd)
    gitc() { git --git-dir="$common" "$@"; }
    HEAD_DESC=$(git --git-dir="$gd" log --oneline -1)
fi

RAM="$FPGA/src/peripheral/ram"
gitc show "$HITO1_REF:fpga/src/peripheral/ram/uma.sv"   > "$W/src/uma_hito1.sv"   || exit 2
gitc show "$HITO1_REF:fpga/src/peripheral/ram/sdram.sv" > "$W/src/sdram_hito1.sv" || exit 2
python3 - "$W/src/sdram_hito1.sv" <<'EOF' || exit 2
import sys
p = sys.argv[1]; s = open(p).read()
a = "    localparam ADDR8_BIT_WIDTH = $bits(Ram.ADDR);\n"
b = "`ifdef VERILATOR\n    localparam ADDR8_BIT_WIDTH = 24;\n`else\n" + a + "`endif\n"
assert s.count(a) == 1, "sdram.sv del hito 1: no esta la linea esperada"
open(p, "w").write(s.replace(a, b))
EOF
python3 - "$RAM/uma.sv" "$W/src/uma_mut.sv" <<'EOF' || exit 2
import sys
s = open(sys.argv[1]).read()
rep = [("else if(grant_any[process_ch])  processing[process_ch] <= 1;",
        "else if(grant_any[process_ch] || (process_ch == 0 && int_issue))  processing[process_ch] <= 1;"),
       ("else if(done_ch[process_ch] && proc_rw[process_ch]) Secondary[process_ch].DOUT <= Primary.DOUT;",
        "else if(done_ch[process_ch]) Secondary[process_ch].DOUT <= Primary.DOUT;")]
for a, b in rep:
    assert s.count(a) == 1, "mutante: no esta '%s'" % a
    s = s.replace(a, b)
open(sys.argv[2], "w").write(s)
EOF
python3 - "$RAM/sdram.sv" "$W/src" <<'EOF' || exit 2
import sys
s = open(sys.argv[1]).read()
a = "localparam      STATE_END           = (STATE_IDLE + 7'd8);"
assert s.count(a) == 1, "slow: no esta '%s'" % a
open(sys.argv[2] + "/sdram_slack0.sv", "w").write(s.replace(a, a.replace("7'd8", "7'd9")))
open(sys.argv[2] + "/sdram_slow.sv", "w").write(s.replace(a, a.replace("7'd8", "7'd10")))
EOF

VFLAGS="--binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style --top-module tb_uma_sdram -o vtb"
TBSRC="$TB/sdram_model_bl.v $TB/tb_uma_sdram.sv"
build() {   # build <dir> <opciones y fuentes...>
    local d=$1; shift
    if ! verilator $VFLAGS --Mdir "$W/$d" "$@" > "$W/logs/build_$d.log" 2>&1; then
        grep -E '^%Error' "$W/logs/build_$d.log" | head -20
        echo "ERROR: no compila la build $d"; exit 2
    fi
}
build new   "$RAM/ram.sv" "$RAM/uma.sv" "$RAM/sdram.sv" $TBSRC &
build int0  -GINT_REFRESH=0 "$RAM/ram.sv" "$RAM/uma.sv" "$RAM/sdram.sv" $TBSRC &
build hito1 -DHITO1 "$RAM/ram.sv" "$W/src/uma_hito1.sv" "$W/src/sdram_hito1.sv" $TBSRC &
build mut   "$RAM/ram.sv" "$W/src/uma_mut.sv" "$RAM/sdram.sv" $TBSRC &
build slack0 "$RAM/ram.sv" "$RAM/uma.sv" "$W/src/sdram_slack0.sv" $TBSRC &
build slow  "$RAM/ram.sv" "$RAM/uma.sv" "$W/src/sdram_slow.sv" $TBSRC &
wait
for d in new int0 hito1 mut slack0 slow; do [ -x "$W/$d/vtb" ] || { echo "ERROR: falta la build $d"; exit 2; }; done

OUT=${OUT:-$TB/resultados.txt}
NFAIL=0
{
    echo "# Banco UMA + sdram.sv (fpga/tb/sdram/run.sh), $(date '+%Y-%m-%d %H:%M')"
    echo "# arbol: $HEAD_DESC   referencia hito 1: $HITO1_REF   $US us por caso"
    echo "# $(verilator --version)"
} > "$OUT"

declare -A LAT1
run() {   # run <nombre> <build> <plusargs...>
    local name=$1 b=$2; shift 2
    local log="$W/logs/$name.log"
    "$W/$b/vtb" +US="$US" "$@" > "$log" 2>&1
    local res=$(grep '^RESULT' "$log" | head -1)
    [ -z "$res" ] && res="RESULT: FALLA (sin informe)"
    local gap=$(sed -n 's/.*intervalo_max=\([0-9.]*\) us (\([0-9]*\) ciclos).*/\1 us (\2)/p' "$log")
    local dbg=$(sed -n 's/^UMA dbg: \(.*\) MAXGAP.*/\1/p' "$log")
    local lat=$(sed -n 's/^canal 1:.* latencia=\([0-9.]*\) ciclos/\1/p' "$log")
    local extra=$(sed -n 's/^canal 0 100%: .*latencias: \(.*\)/lat0 \1/p; s/^canal 0 Z80: .* tarde=\([0-9]*\) .* captura_max=\([0-9]*\) ciclos refrescos_internos_tras_captura=\([0-9]*\)/tarde \1 captura_max \2 int_tras_captura \3/p; s/^canal 0 R\/W+RFSH: \(.*\)/\1/p' "$log")
    local init=$(sed -n 's/.*REF_antes_del_MRS=\([0-9]*\).*/\1/p' "$log")
    local c1=$(sed -n 's/^canal 1:.* perdidas=\([0-9]*\) err_dato=\([0-9]*\) .*/perd \1 err \2/p' "$log")
    printf '%-26s %-6s %-44s gap %-18s init %s | %s | ch1 %s %s | %s\n' "$name" "$b" "$*" "$gap" "$init" "$dbg" "$lat" "$c1" "$extra" >> "$OUT"
    printf '    %s\n' "$res" >> "$OUT"
    grep '^CHECK.*FALLA' "$log" | sed 's/^/    /' >> "$OUT"
    case "$res" in "RESULT: PASA"*) ;; *) NFAIL=$((NFAIL+1)); sed 's/^/    | /' "$log" >> "$OUT";; esac
    LAT1[$name]=$lat
}

for M in 108000 107386; do
    F="+MHZ=$M"
    echo "## $M kHz" >> "$OUT"
    run "idle_standby_$M"        new $F +CH0=0 +V99=0
    run "v99_$M"                 new $F +CH0=0 +V99=1
    run "z80_358_rfsh_$M"        new $F +CH0=1 +Z80KHZ=3580 +Z80RFSH=1 +V99=0
    run "z80_358_norfsh_$M"      new $F +CH0=1 +Z80KHZ=3580 +Z80RFSH=0 +V99=0
    run "z80_716_rfsh_$M"        new $F +CH0=1 +Z80KHZ=7160 +Z80RFSH=1 +V99=0
    for S in 1 2 3; do
    run "z80_716_norfsh_s${S}_$M" new $F +CH0=1 +Z80KHZ=7160 +Z80RFSH=0 +V99=0 +SEED=$S
    done
    run "z80_716_norfsh_v99_$M"  new $F +CH0=1 +Z80KHZ=7160 +Z80RFSH=0 +V99=1
    for S in 1 2; do
    run "full100_s${S}_$M"       new $F +CH0=2 +V99=0 +SEED=$S
    done
    run "full100_v99_$M"         new $F +CH0=2 +V99=1
    run "rw_rfsh_$M"             new $F +CH0=3 +V99=0
    run "rw_rfsh_int0_$M"        int0 $F +CH0=3 +V99=0
    echo "## controles negativos (se espera que falle la comprobacion indicada) $M kHz" >> "$OUT"
    run "neg_phase0_$M"          new  $F +CH0=0 +V99=1 +PHASE0=1 +NEG=window
    run "neg_int0_gap_$M"        int0 $F +CH0=0 +V99=0 +NEG=gap
    run "neg_hito1_init_$M"      hito1 $F +CH0=0 +V99=1 +NEG=init
    run "neg_hito1_gap_$M"       hito1 $F +CH0=1 +Z80KHZ=7160 +Z80RFSH=0 +V99=0 +NEG=gap
    run "neg_hito1_rwrfsh_$M"    hito1 $F +CH0=3 +V99=0 +NEG=rfsh
    run "neg_mut_dout_$M"        mut  $F +CH0=1 +Z80KHZ=7160 +Z80RFSH=0 +V99=1 +NEG=z80
    run "neg_slack0_slot_$M"     slack0 $F +CH0=2 +V99=1 +NEG=slot
    run "neg_slow_slot_$M"       slow $F +CH0=2 +V99=1 +NEG=slot
    # el canal 1 no se retrasa: misma latencia que con el UMA del hito 1
    if [ -n "${LAT1[v99_$M]}" ] && [ "${LAT1[v99_$M]}" = "${LAT1[neg_hito1_init_$M]}" ]; then
        echo "CANAL1 $M: latencia ${LAT1[v99_$M]} igual que en el hito 1 (${LAT1[neg_hito1_init_$M]}): PASA" >> "$OUT"
    else
        echo "CANAL1 $M: latencia ${LAT1[v99_$M]:-?} frente a ${LAT1[neg_hito1_init_$M]:-?} del hito 1: FALLA" >> "$OUT"
        NFAIL=$((NFAIL+1))
    fi
done

if [ "$NFAIL" -eq 0 ]; then echo "TOTAL: PASA" >> "$OUT"; else echo "TOTAL: FALLA ($NFAIL casos)" >> "$OUT"; fi
cat "$OUT"
[ "$NFAIL" -eq 0 ]
