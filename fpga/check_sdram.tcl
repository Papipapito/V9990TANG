# ============================================================================
#  check_sdram.tcl -- comprobacion de sintesis del hito 4 (refresco y SDRAM) sobre V9990TANG - WonderTANG 2.02b (Tang Nano 20K, GW2AR-LV18QN88C8/I7)
#  Configuracion v9990 (solo el V9990 con su VDP de comandos), variante xtal:
#  CLK_BASE = 108,000 MHz del cristal de 27 MHz (CONFIG_BOARD::SYNC_CPU_CLK = 0).
#
#  Uso:  cd fpga && gw_sh check_sdram.tcl   (solo sintesis; recursos por modulo en
#        impl/gwsynthesis/check_sdram_syn_rsc.xml). El resto, como build_v9990_xtal.tcl:
#
#  Uso original:  cd fpga && gw_sh build_v9990_xtal.tcl
#        -> impl/pnr/v9990_xtal.fs, .rpt.txt (recursos), .tr (timing), .sdf;
#           logs en impl/gwsynthesis/v9990_xtal.log e impl/pnr/v9990_xtal.log
#        Puerta: python tools/check_build.py ... (docs/VERIFICATION.md)
#
#  gw_sh (Gowin 1.9.12.03) no abre ficheros con rutas de mas de 260
#  caracteres: el repositorio tiene que estar en una ruta corta.
#
#  Lista de ficheros: la de tnCart_board_wt200b.gprj de tnCartWonder, en el
#  mismo orden, sin lo que la configuracion v9990 deja sin elaborar (FM, PSG,
#  Nextor, RAM mapper, megaROM, SCC, PAC, UART), con fpga/config/v9990.sv en
#  lugar de config.sv y el .sdc propio en lugar de board_wt200b_27M.sdc.
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
add_file config/v9990.sv
add_file src/main.sv
add_file src/peripheral/flash.sv
add_file src/peripheral/led.sv
add_file src/peripheral/msx/bus.sv
add_file src/peripheral/msx/expansion_slot.sv
add_file src/peripheral/ram/ram.sv
add_file src/peripheral/ram/sdram.sv
add_file src/peripheral/ram/uma.sv
add_file src/peripheral/signal/attenuator.sv
add_file src/peripheral/signal/limiter.sv
add_file src/peripheral/sound/dac_16bit.sv
add_file src/peripheral/sound/i2s_audio_tx.sv
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
set_option -output_base_name check_sdram
set_option -place_option 2 -route_option 1
set_option -gen_text_timing_rpt 1
# SDF post-PnR: tools/check_build.py (punto 6) toma de el la red
# CLKOUT -> dclk_en_ff[1]/CLK, el tC2Q de ese flop, la ruta Q -> OR de
# Video.DCLK y el pin de LUT mas rapido del chip (el retardo de la propia OR
# no sale), les suma la latencia del rPLL del .tr y comprueba que el flanco
# real no llega antes que el -offset del .sdc (ver docs/ARCHITECTURE.md)
set_option -gen_sdf 1

run syn
