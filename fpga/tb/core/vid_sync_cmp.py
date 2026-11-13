#!/usr/bin/env python3
# vid_sync_cmp.py <a.bin> <b.bin> -- compara dos volcados +VIDDUMP de tb_t9990_core.sv sin el color:
# cada punto son 4 bytes little-endian {12'd0, de, eo, il, vs, hs, r[4:0], g[4:0], b[4:0]}; se
# comparan DE, EO, IL, VS y HS (bits 19..15). Sale con 0 si son iguales.
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
import sys
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
if len(a) != len(b) or len(a) == 0 or len(a) % 4:
    print("tamanos distintos o vacios: %d y %d bytes" % (len(a), len(b)))
    sys.exit(1)
# bits 15..19: bit 7 del byte 1 y bits 0..3 del byte 2
for i in range(0, len(a), 4):
    if (a[i + 1] ^ b[i + 1]) & 0x80 or (a[i + 2] ^ b[i + 2]) & 0x0F:
        print("sincronismo distinto en el punto %d" % (i // 4))
        sys.exit(1)
sys.exit(0)
