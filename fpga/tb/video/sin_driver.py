#!/usr/bin/env python3
# sin_driver.py -- copia de un video_upscan.sv sin el segundo driver de R_ADDR
#
# En el case de OUT para B4 (registro OUT de VIDEO_UPSCAN_STRETCH_BUFFER) el
# codigo de tnCart tiene "default: R_ADDR <= R_ADDR;": un segundo always_ff que
# escribe R_ADDR. Verilator (con -Wno-MULTIDRIVEN) y Gowin lo resuelven
# distinto en el primer ciclo de OUT_EN de cada linea en B4 (out_state_delay = F):
# en Verilator gana el "mantener" y R_ADDR no avanza 2; el netlist de Gowin se
# comporta como si esa linea no existiera (gowin_netlist/run_nl.sh lo comprueba
# simulando el netlist). Esta copia quita esa linea ("default: ;") para que
# Verilator simule lo que hace el chip.
#
# Uso: sin_driver.py entrada.sv salida.sv N   (N = apariciones esperadas)
import re, sys

src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(src, encoding='utf-8').read()
pat = re.compile(r'(case \(out_state_delay\)\n[ \t]*)default: R_ADDR <= R_ADDR;[^\n]*')
s2, k = pat.subn(r'\1default: ;', s)
if k != n:
    sys.exit('sin_driver.py: %s: %d apariciones, se esperaban %d' % (src, k, n))
open(dst, 'w', encoding='utf-8', newline='\n').write(s2)
