#!/bin/bash
# run_t9990_core.sh [prueba ...] -- banco del core (tb_t9990_core.sv) en Verilator 5.020 (WSL).
#   pruebas: geom pal blit cmmc cmmm orden p2notr ycc vscroll ports eor r16 r16chg bdbp assert hito1 replay
#            (sin argumentos: todas menos replay)
#   geom    geometria 1368 x 262 (313 con PAL) en B1/P1/B3/B2/B4, con carga en el canal 0, con R#16 y
#           con C25M en B1                                -> GEOM_OK
#   pal     cuadro PAL de 313 lineas (+PALT=1)            -> PALT_OK
#   blit    motor de comandos en B1 (+BLIT=1)             -> BLIT_OK
#   cmmc    CMMC a 2/4/8/16 bpp contra el modelo del manual y de openMSX: 8 pixeles por byte de P#2, ningun
#           byte de mas, nada fuera del rectangulo (+CMMC=1)  -> CMMC_OK
#   cmmm    CMMM a 2/4/8/16 bpp: bytes de la VRAM lineal desde SA, con las lecturas del motor contadas
#           (+CMMM=1)                                         -> CMMM_OK
#   orden   orden de los bytes del color a 16 bpp (R#48 = direccion par) en LMMV/LMMC/PSET/LINE/LMCM/SRCH/
#           CMMC, y CMMM con SA = 7FFFEh (+ORDEN=1)           -> ORDEN_OK
#   p2notr  P#2 escrito sin mirar TR (SymbOS G9K): CMMC de nuevo sin sondear TR, LMMC 16x2 seguido y R#6 ->
#           comando/P#0 inmediato (+CMMC=1 +P2NOTR=1)         -> P2NOTR_OK (y CMMC_OK)
#   ycc     YJK y YUV en B1 contra el modelo de openMSX, con el desfase calibrado con BD8 (+YCC=1) -> YCC_OK
#   vscroll reinicio del scroll vertical con R#17/R#21 a mitad de pantalla (Xybots), en B1 y P1, NTSC y PAL:
#           otro banco (tb_t9990_vscroll.sv, run_t9990_vscroll.sh, que se puede lanzar solo)    -> VSCROLL_OK
#   ports   P#4/P#7/P#8-P#15 leen FFh (+PORTS=1)         -> PORTS_OK
#   eor     cursores con la semantica de openMSX sobre BD16, BD16 entrelazado, BP4 y B2 BP4 (NTSC y PAL)
#           (+EOR=1)                                      -> EOR_OK
#   r16     R#16 en B1/P1/B3/P2/B2/B4, entrelazado y PAL (+R16T=1) -> R16_OK
#   r16chg  R#16 cambiado en marcha en B1 entrelazado, B4 PAL entrelazado y B5: el sincronismo (VS a
#           VS, HS a HS, anchos) no cambia nunca; la ventana se reajusta en su borrado (como mucho 2
#           cuadros de +-(15 lineas + 60 puntos) por cambio) y queda donde toca (+R16CHG=1) -> R16CHG_OK
#   bdbp    puntos de indice 0 de BP4 desde el reset y despues de BD16: color de fondo (+BDBP=1)
#                                                         -> BDBP_OK
#   assert  ACK de la VRAM 8 ciclos tarde (+ACKDLY=8): la asercion de ranura perdida tiene que saltar
#   hito1   la salida de video (HS, VS, R, G, B, DE, EO, IL en cada DCLK_EN, +VIDDUMP) del core de trabajo
#           con R#16 = 00h y sin PAL, identica punto a punto a la del core del hito 1 (commit 20936e6, con
#           char -> chr) en B1, P1, P2, B3, B2, B4 y B1 entrelazado
#   replay  REPLAY=<.rpl> VRAMOUT=<.bin> [OMSX=<vram de openMSX .bin>]: replay de una traza de openMSX
#           (mk_trace.py + mk_replay.py del MSXimus Z) y comparacion byte a byte de la VRAM, con el volcado
#           de openMSX pasado antes al orden del tiny9990 por omsx_vram.py (rutas de WSL, /mnt/c/...)
# Parametros del core: VOPT="-GENABLE_PAL=0 -GENABLE_CURSOR_EOR=0 -GENABLE_R16=0" (los mismos -G
# llegan al banco, que ajusta lo que espera).
# Todas (salvo assert) exigen ademas LOST_SLOTS=0 (asercion de t9990_ram.sv).
# Los objetos de Verilator quedan en ~/.cache/v99tang_core de WSL (el 9p de /mnt/c es lento y asi la
# segunda vez solo se recompila lo que cambia). Se relanza dentro de WSL si se llama desde Git Bash.
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
cd "$(dirname "$0")/../.."
HITO1_REV=20936e6
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    # el core del hito 1 sale de git aqui (el git de WSL no lee el .git de un worktree de Windows)
    case " ${*:-hito1} " in *" hito1 "*)
        mkdir -p tb/core/hito1_src
        for f in $(git ls-tree --name-only $HITO1_REV v9990/tiny9990/); do
            n=tb/core/hito1_src/$(basename $f)
            git show $HITO1_REV:fpga/$f | sed -e 's/work\.char\./work.chr./g' -e 's/char_work_t char;/char_work_t chr;/' > $n.new
            if cmp -s $n.new $n; then rm $n.new; else mv $n.new $n; fi
        done ;;
    esac
    # DETACH=<log de WSL>: lanza el banco desacoplado (setsid nohup) y vuelve en el acto; la salida va al
    # log (sirve cuando el proceso que llama puede morir antes que una compilacion larga). wsl.exe pasa
    # la orden por un shell que vuelve a expandir $0/$@: la orden se monta aqui ya expandida (las rutas
    # y los nombres de prueba no llevan espacios); el sleep da tiempo a setsid antes de que wsl cierre.
    if [ -n "$DETACH" ]; then
        WSLENV=VOPT:OBJTAG:REPLAY:VRAMOUT:OMSX MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -- bash -c "setsid nohup bash $(pwd | sed s,^/c/,/mnt/c/,)/tb/core/run_t9990_core.sh $* > $DETACH 2>&1 < /dev/null & sleep 2"
        exit 0
    fi
    WSLENV=VOPT:OBJTAG:REPLAY:VRAMOUT:OMSX MSYS_NO_PATHCONV=1 exec wsl -d Ubuntu-24.04 -- bash "$(pwd | sed s,^/c/,/mnt/c/,)/tb/core/run_t9990_core.sh" "$@"
fi
source tb/core/core_sources.sh
TESTS="${*:-geom pal blit cmmc cmmm orden p2notr ycc vscroll ports eor r16 r16chg bdbp assert hito1}"
ROOT=$HOME/.cache/v99tang_core
OBJ=$ROOT/work_$(echo "$VOPT$OBJTAG" | md5sum | cut -c1-8)    # OBJTAG: otro directorio de objetos con las mismas VOPT
LOG=$ROOT/log_$$
mkdir -p $OBJ $LOG
build() {   # build <dir> <fuentes del core> <opciones>
    local dir=$1 src=$2; shift 2
    echo "== verilator $* -> $dir"
    verilator $VFLAGS "$@" --top-module tb_t9990_core --Mdir $dir -o vtb_t9990_core $src tb/core/tb_t9990_core.sv > $dir/build.log 2>&1
    if [ $? != 0 ] || [ ! -x $dir/vtb_t9990_core ]; then grep -E '%Error|error:' $dir/build.log | head -20; return 1; fi
}
build $OBJ "$CORE_SRC" $VOPT || exit 1
FAIL=0; SUMMARY=""
run() {   # run <nombre> <marca esperada> <plusargs...>  (VTB= otro binario)
    local name=$1 mark=$2; shift 2
    echo "===== $name: $*"
    ${VTB:-$OBJ/vtb_t9990_core} +verilator+error+limit+1000000 "$@" > $LOG/run.log 2>&1
    grep -v '^- ' $LOG/run.log | grep -v 'ranura de VRAM perdida' | grep -v 'Verilog \$stop' | head -150
    local nlost=$(grep -c 'ranura de VRAM perdida' $LOG/run.log)
    [ "$nlost" != "0" ] && { echo "   ($nlost avisos de ranura perdida; el primero:)"; grep -m1 'ranura de VRAM perdida' $LOG/run.log; }
    local ok=1
    grep -q "$mark" $LOG/run.log || ok=0
    grep -q "TB_DONE" $LOG/run.log || ok=0
    if [ "$name" != "assert" ]; then grep -q "LOST_SLOTS=0 " $LOG/run.log || ok=0; fi
    if [ $ok = 1 ]; then SUMMARY="$SUMMARY\n  PASA  $name $*"; else SUMMARY="$SUMMARY\n  FALLA $name $*"; FAIL=1; fi
}
for t in $TESTS; do
    case $t in
    geom)
        run geom "GEOM_OK" +R6=130                      # B1 256 px 8 bpp
        run geom "GEOM_OK" +R6=0                        # P1 (msx-samurai)
        run geom "GEOM_OK" +R6=80                       # P2 (50h)
        run geom "GEOM_OK" +R6=150                      # B3 512 px
        run geom "GEOM_OK" +R6=150 +MCS=1               # B2 384 px (maestro de 14 MHz)
        run geom "GEOM_OK" +R6=170 +MCS=1               # B4 768 px
        run geom "GEOM_OK" +R6=131                      # B1 16 bpp
        run geom "GEOM_OK" +R6=130 +CH0=1               # B1 con el canal 0 del UMA ocupado
        run geom "GEOM_OK" +R6=130 +R7=6                # B1 entrelazado
        run geom "GEOM_OK" +R6=130 +R7=8                # B1 PAL
        run geom "GEOM_OK" +R6=0 +R7=8                  # P1 PAL
        run geom "GEOM_OK" +R6=150 +MCS=1 +R7=8         # B2 PAL
        run geom "GEOM_OK" +R6=130 +R16=87              # B1 con R#16 = 87h
        run geom "GEOM_OK" +R6=170 +MCS=1 +R7=8 +R16=78 # B4 PAL con R#16 = 78h
        run geom "GEOM_OK" +R6=130 +R7=64               # B1 con C25M (GNG): sin HSCN no cambia de reloj
        ;;
    pal)    run pal "PALT_OK" +PALT=1 ;;
    blit)   run blit "BLIT_OK" +BLIT=1 ;;
    cmmc)   run cmmc "CMMC_OK" +CMMC=1 ;;
    cmmm)   run cmmm "CMMM_OK" +CMMM=1 ;;
    orden)  run orden "ORDEN_OK" +ORDEN=1 ;;
    p2notr) run p2notr "P2NOTR_OK" +CMMC=1 +P2NOTR=1 ;;
    ycc)    run ycc "YCC_OK" +YCC=1 ;;
    vscroll)
        # otro banco: su script compila aparte (en su propio directorio de objetos) y corre la lista de casos
        echo "===== vscroll"
        bash tb/core/run_t9990_vscroll.sh > $LOG/vscroll.log 2>&1; vs=$?
        grep -v '^== verilator' $LOG/vscroll.log | head -60
        if [ $vs = 0 ]; then SUMMARY="$SUMMARY
  PASA  vscroll"; else SUMMARY="$SUMMARY
  FALLA vscroll"; FAIL=1; fi ;;
    ports)  run ports "PORTS_OK" +PORTS=1 ;;
    eor)    run eor "EOR_OK" +EOR=1 ;;
    r16)    run r16 "R16_OK" +R16T=1 ;;
    r16chg) run r16chg "R16CHG_OK" +R16CHG=1 ;;
    bdbp)   run bdbp "BDBP_OK" +BDBP=1 ;;
    assert) run assert "ASSERT_SELFTEST_OK" +R6=130 +ACKDLY=8 +FRAMES=1 ;;
    hito1)
        H1=$ROOT/hito1
        mkdir -p $H1
        H1_SRC=$(echo "$CORE_SRC" | sed -e 's,v9990/tiny9990/,tb/core/hito1_src/,g')
        build $H1 "$H1_SRC" +define+CORE_HITO1 -GENABLE_PAL=0 -GENABLE_CURSOR_EOR=0 -GENABLE_R16=0 || { FAIL=1; continue; }
        for m in "+R6=130" "+R6=0" "+R6=80" "+R6=150" "+R6=150 +MCS=1" "+R6=170 +MCS=1" "+R6=130 +R7=6"; do
            tag=$(echo "$m" | tr -d ' +=')
            run hito1 "GEOM_OK" $m +FRAMES=2 +VIDDUMP=$LOG/vid_work_$tag.bin
            VTB=$H1/vtb_t9990_core run hito1 "GEOM_OK" $m +FRAMES=2 +VIDDUMP=$LOG/vid_hito1_$tag.bin
            if [ -s $LOG/vid_work_$tag.bin ] && cmp -s $LOG/vid_work_$tag.bin $LOG/vid_hito1_$tag.bin; then
                echo "   video identico al del hito 1: $(stat -c %s $LOG/vid_work_$tag.bin) bytes"
                SUMMARY="$SUMMARY\n  PASA  hito1 video identico $m"
            else
                echo "   video DISTINTO del hito 1 ($(cmp $LOG/vid_work_$tag.bin $LOG/vid_hito1_$tag.bin 2>&1 | head -1))"
                SUMMARY="$SUMMARY\n  FALLA hito1 video distinto $m"; FAIL=1
            fi
        done
        ;;
    replay)
        if [ -z "$REPLAY" ]; then echo "replay: falta REPLAY=<fichero .rpl>"; FAIL=1; continue; fi
        OUT=${VRAMOUT:-$LOG/tb_vram.bin}
        run replay "TB_DONE" +REPLAY=$REPLAY +VRAMOUT=$OUT
        if [ -n "$OMSX" ]; then
            # el volcado de openMSX es la VRAM fisica de los dos chips seguidos: omsx_vram.py la pasa al
            # orden del tiny9990 (el de la VRAM del banco) antes de comparar byte a byte
            python3 tb/core/omsx_vram.py "$OMSX" $LOG/omsx_tiny.bin || { FAIL=1; continue; }
            nd=$(cmp -l $LOG/omsx_tiny.bin "$OUT" 2>/dev/null | wc -l)
            echo "   VRAM: $nd bytes distintos de $(stat -c %s "$OUT") frente a $OMSX (en el orden del tiny9990)"
            if [ "$nd" = "0" ] && [ "$(stat -c %s $LOG/omsx_tiny.bin)" = "$(stat -c %s "$OUT")" ]; then SUMMARY="$SUMMARY\n  PASA  VRAM identica a openMSX"; else SUMMARY="$SUMMARY\n  FALLA VRAM distinta de openMSX ($nd bytes)"; FAIL=1; fi
        fi
        ;;
    *) echo "prueba desconocida: $t"; FAIL=1 ;;
    esac
done
echo -e "== resumen (VOPT=$VOPT):$SUMMARY"
rm -rf $LOG
exit $FAIL
