#!/bin/bash
# core_sources.sh -- lista de fuentes del core para los bancos de fpga/tb/core,
# relativa a fpga/: paquetes primero (CONFIG, RAM e interfaces del UMA), modelo
# de la DPB de Gowin y los 17 ficheros del tiny9990. La usan run_*.sh con "source".
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
T=v9990/tiny9990
CORE_SRC="config/v9990.sv src/peripheral/ram/ram.sv src/peripheral/ram/uma.sv tb/core/tb_dpb_model.v \
$T/t9990_port.sv $T/t9990.sv $T/t9990_timing.sv $T/t9990_ram.sv $T/t9990_clock.sv $T/t9990_selector.sv \
$T/t9990_priority.sv $T/t9990_palette.sv $T/t9990_color_decode.sv $T/t9990_pattern.sv $T/t9990_bitmap.sv \
$T/t9990_sprite.sv $T/t9990_shift_buffer.sv $T/t9990_blit.sv $T/t9990_blit_addr.sv $T/t9990_blit_bitmask.sv \
$T/t9990_blit_fifo.sv tb/core/tb_vram_uma.sv"
# -O1 en vez del -Os de Verilator: compila unas tres veces mas deprisa (5 frente a 16 minutos con las otras
# areas compilando a la vez) y corre un 20 % mas lento; --output-split reparte el C++ entre los -j 8.
VFLAGS="--binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD --output-split 3000 --output-split-cfuncs 300 -MAKEFLAGS OPT_FAST=-O1"
