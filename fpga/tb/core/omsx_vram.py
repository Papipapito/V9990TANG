# -*- coding: utf-8 -*-
# omsx_vram.py <vram_openmsx.bin> <salida.bin>
#   Pasa un volcado de la VRAM del V9990 de openMSX ("Sunrise GFX9000 VRAM", 512 KB) al orden en que la
#   guarda el tiny9990 en la SDRAM, que es el de la VRAM del banco (tb_vram_uma.sv, mem[]).
#
#   openMSX guarda la VRAM FISICA de los dos chips del GFX9000 seguidos (V9990VRAM.hh): en Bx el byte
#   logico A esta en transformBx(A) = ((A & 1) << 18) | (A >> 1) y en P1 en A (transformP1). El tiny9990
#   guarda en Bx el byte A en A (lineal) y en P1 en 2*A[17:0] + A[18] (los chips par/impar entrelazados).
#   En los dos modos sale la misma correspondencia entre indices fisicos:
#       tiny[2 * (p & 3FFFFh) + (p >> 18)] = openmsx[p]
#   asi que el volcado se puede comparar byte a byte sin saber en que modo se escribio cada zona (P2
#   reubica ademas 78000h-7BFFFh: no se usa en las trazas de este banco).
#
#   V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
import sys

src, dst = sys.argv[1], sys.argv[2]
a = open(src, "rb").read()
if len(a) != 0x80000:
    sys.exit("omsx_vram.py: %s tiene %d bytes, se esperaban 524288" % (src, len(a)))
b = bytearray(0x80000)
for p in range(0x80000):
    b[2 * (p & 0x3FFFF) + (p >> 18)] = a[p]
open(dst, "wb").write(bytes(b))
print("omsx_vram.py: %s -> %s (orden del tiny9990)" % (src, dst))
