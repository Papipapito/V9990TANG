# ============================================================================
#  check_megaram.tcl -- V9990TANG, comprobacion de sintesis del area megaram
#  (hito 8): la lista de build_v9990_xtal.tcl con fpga/config/v9990_megaram.sv
#  en lugar de config/v9990.sv y los ficheros de la megaROM (cartridge_megarom,
#  megarom_configure/controller/clear, scc). main.sv es el de main (con el
#  bootloader de tnCart), como la referencia v9990_mega del estudio (9 111 CLS
#  / 29 BSRAM): MEGAROM_CLEAR va en la lista pero no lo instancia nadie hasta
#  la integracion. Mismo .sdc que el hito 1 (sin CLK_21M: el SCC de tnCart
#  corre en CLK_BASE y su CLKDIV se poda).
#
#  Uso:  cd fpga && gw_sh check_megaram.tcl
#        -> impl/pnr/check_megaram.rpt.txt y .tr,
#           impl/gwsynthesis/check_megaram_syn_rsc.xml
#  No es la build de ningun bitstream: solo mide recursos y timing.
# ============================================================================
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

# ----- placa wt200b (tnCartWonder) -----
add_file src/board/board_id.sv
add_file src/board/rev1/board_rev1_bus.sv
add_file src/board/rev1/board_rev1_tmds.sv
add_file src/board/wt200b/board_wt200b_clock.sv
add_file src/board/wt200b/board_wt200b_config.sv
add_file src/board/rev1/dvi_tx/dvi_tx.v

# ----- sistema (tnCart) -----
add_file src/bootloader.sv
add_file src/cartridge_v9990.sv
add_file config/v9990_megaram.sv
add_file src/cartridge_megarom.sv
add_file src/main.sv
add_file src/peripheral/flash.sv
add_file src/peripheral/led.sv
add_file src/peripheral/msx/bus.sv
add_file src/peripheral/msx/expansion_slot.sv
add_file src/peripheral/msx/megarom_clear.sv
add_file src/peripheral/msx/megarom_configure.sv
add_file src/peripheral/msx/megarom_controller.sv
add_file src/peripheral/ram/ram.sv
add_file src/peripheral/ram/sdram.sv
add_file src/peripheral/ram/uma.sv
add_file src/peripheral/signal/attenuator.sv
add_file src/peripheral/signal/limiter.sv
add_file src/peripheral/sound/dac_16bit.sv
add_file src/peripheral/sound/i2s_audio_tx.sv
add_file src/peripheral/sound/scc/scc.sv
add_file src/peripheral/sound/sound.sv
add_file src/peripheral/spi.sv

# ----- core V9990: tiny9990 de buppu3/tnCart 8714731, sin parches -----
add_file v9990/tiny9990/t9990.sv
add_file v9990/tiny9990/t9990_bitmap.sv
add_file v9990/tiny9990/t9990_blit.sv
add_file v9990/tiny9990/t9990_blit_addr.sv
add_file v9990/tiny9990/t9990_blit_bitmask.sv
add_file v9990/tiny9990/t9990_blit_fifo.sv
add_file v9990/tiny9990/t9990_clock.sv
add_file v9990/tiny9990/t9990_color_decode.sv
add_file v9990/tiny9990/t9990_palette.sv
add_file v9990/tiny9990/t9990_pattern.sv
add_file v9990/tiny9990/t9990_port.sv
add_file v9990/tiny9990/t9990_priority.sv
add_file v9990/tiny9990/t9990_ram.sv
add_file v9990/tiny9990/t9990_selector.sv
add_file v9990/tiny9990/t9990_shift_buffer.sv
add_file v9990/tiny9990/t9990_sprite.sv
add_file v9990/tiny9990/t9990_timing.sv

# ----- video: upscan a 720x480 (855x524 a 27 MHz) -----
add_file src/peripheral/video/video.sv
add_file src/peripheral/video/video_upscan.sv

# ----- top -----
add_file src/tnCart_board_wt200b_top.sv

# ----- restricciones -----
add_file src/board/wt200b/board_wt200b.cst
add_file constraints/v9990_xtal.sdc

# MSPI = flash (bootloader); SSPI = pines del DAC I2S y del bus de la WonderTANG
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module TNCART_BOARD_WT200B_TOP -verilog_std sysv2017
set_option -output_base_name check_megaram
set_option -place_option 2 -route_option 1
set_option -gen_text_timing_rpt 1
# SDF post-PnR: tools/check_build.py (punto 6) toma de el la red
# CLKOUT -> dclk_en_ff[1]/CLK, el tC2Q de ese flop, la ruta Q -> OR de
# Video.DCLK y el pin de LUT mas rapido del chip (el retardo de la propia OR
# no sale), les suma la latencia del rPLL del .tr y comprueba que el flanco
# real no llega antes que el -offset del .sdc (ver docs/ARCHITECTURE.md)
set_option -gen_sdf 1

run syn
run pnr
