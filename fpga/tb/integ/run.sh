#!/usr/bin/env bash
# run.sh -- V9990TANG: bancos de la integracion (Verilator 5.020 con --timing).
#   tb_integ_pins:  polaridad de los pines del slot con las guardias de lock
#                   (DRIVE_EN, BOOT_HOLD), BUS_OK y el timeout del /WAIT del
#                   BOARD_REV1_BUS de hito/bus (desde la fusion; antes,
#                   BOARD_WT200B_BUS_GUARD delante del bus de main)
#   tb_integ_guard: POR, gestor del rPLL base, detector de perdida de
#                   enganche, guardia de lock y LED, en las dos variantes
#                   (-GSYNC=0 / -GSYNC=1), un escenario por ejecucion
# Uso (WSL, desde fpga/):  bash tb/integ/run.sh
# Sale con 0 si todo pasa. Los binarios y los logs van a tb/integ/build/
# (ignorado por git).
# BSD 3-Clause License. Copyright (c) 2026, Papipapito.
set -u
cd "$(dirname "$0")"
SRC=(../../src/board/wt200b/board_wt200b_guard.sv ../../src/system/system_reset.sv ../../src/peripheral/led.sv tb_integ_guard.sv)
SRC_PINS=(../../src/board/board_id.sv ../../src/board/wt200b/board_wt200b_config_xtal.sv ../../config/v9990.sv
          ../../src/peripheral/msx/bus.sv ../../src/board/rev1/board_rev1_bus.sv
          tb_integ_pins.sv)
mkdir -p build
rc=0

# ---- pines (BOARD_REV1_BUS es de tnCart: sin -Wall, avisos no fatales) ----
obj=build/obj_pins
if ! verilator --binary --timing -Wno-fatal -Wno-BLKSEQ --timescale 1ns/1ps \
        --top-module tb_integ_pins -Mdir ${obj} -o tb "${SRC_PINS[@]}" > build/verilator_pins.log 2>&1; then
    echo "ERROR: Verilator (pins), ver tb/integ/build/verilator_pins.log"
    tail -20 build/verilator_pins.log
    exit 1
fi
log=build/pins.log
./${obj}/tb > ${log} 2>&1
res=$(grep -E '^RESULTADO' ${log})
if grep -q '^BANCO: PASA' ${log}; then echo "PASA   ${res}"; else echo "FALLA  ${res:-sin resultado} (ver ${log})"; grep '^FALLA' ${log} | head; rc=1; fi

# ---- guardia (codigo propio: -Wall) ----
for sync in 0 1; do
    obj=build/obj_sync${sync}
    if ! verilator --binary --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
            -Wno-PINCONNECTEMPTY -Wno-INITIALDLY -Wno-BLKSEQ -Wno-REALCVT -Wno-SYNCASYNCNET --timescale 1ns/1ps \
            --top-module tb_integ_guard -GSYNC=${sync} -Mdir ${obj} -o tb \
            "${SRC[@]}" > build/verilator_sync${sync}.log 2>&1; then
        echo "ERROR: Verilator (SYNC=${sync}), ver tb/integ/build/verilator_sync${sync}.log"
        tail -20 build/verilator_sync${sync}.log
        exit 1
    fi
    if [ ${sync} = 0 ]; then scens="lento perdida nunca tope mega timeout glitch turbo_marcha deriva busok usb"; else scens="lento perdida nunca turbo tope mega glitch turbo_marcha deriva busok usb"; fi
    for s in ${scens}; do
        log=build/sync${sync}_${s}.log
        ./${obj}/tb +SCEN=${s} > ${log} 2>&1
        res=$(grep -E '^RESULTADO' ${log})
        if grep -q '^BANCO: PASA' ${log}; then echo "PASA   ${res}"; else echo "FALLA  ${res:-sin resultado} (ver ${log})"; grep '^FALLA' ${log}; rc=1; fi
    done
done
exit $rc
