#!/usr/bin/env python3
# ============================================================================
# make_pack.py -- pack de Nextor de V9990TANG (configuracion
# v9990_megaram_nextor): la imagen que se graba en la flash de la Tang Nano 20K
# en 10_0000h y que NEXTOR_LOADER copia a la SDRAM (70_0000h) al arrancar.
#
# El pack es el kernel oficial de Nextor para la MegaFlashROM SCC+ SD, la
# interfaz que emula el TF_CONTROLLER de tnCart (banco 40h en 4000h-57FFh):
# "Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM" de las releases de Konamiman
# (https://github.com/Konamiman/Nextor/releases, v2.1.2), el mismo que pide
# tnCart (roms/nextor/README.md de tnCart / tnCartWonder). Tal cual, sin
# cambios: 131 072 bytes, "AB" al principio. La copia de la flash a la SDRAM
# es de 128 KB exactos (CONFIG::FLASH_SIZE_BIOS_NEXTOR): sin FM-BIOS.
#
# Uso:  python tools/nextor/make_pack.py <Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM> [salida]
#       (salida por defecto: bitstream/v9990tang_nextor_pack_0.2beta.bin)
# Comprueba el tamano, la cabecera "AB", las cadenas de version del kernel y
# del driver y el SHA-256 de la ROM de entrada (EXPECTED_SHA256, el de la ROM
# con la que se hizo el pack de la 0.2beta); con --otra-rom acepta otra ROM
# de la MegaFlashROM SCC+ SD de 128 KB (p. ej. una version posterior) y lo
# dice.
#
# Licencia del contenido: la de Nextor (tools/nextor/LICENSE_NEXTOR.md, copia
# del LICENSE.md del repositorio de Nextor): se puede copiar y distribuir con
# el aviso, sin cobrar por el software. Ver UPSTREAM.md.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE): solo
# este script; la ROM no.
# ============================================================================
import hashlib
import os
import sys

EXPECTED_SIZE = 131072
EXPECTED_SHA256 = "b2394dfca88e72a9386f90afe7b0e13f0c3b5538a4c397423e3b436c810e74ee"
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                           "bitstream", "v9990tang_nextor_pack_0.2beta.bin")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    other = "--otra-rom" in sys.argv[1:]
    if not args:
        print(__doc__ or "uso: make_pack.py <rom> [salida]", file=sys.stderr)
        print("uso: python tools/nextor/make_pack.py <Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM> [salida] [--otra-rom]", file=sys.stderr)
        return 2
    src = args[0]
    out = os.path.abspath(args[1] if len(args) > 1 else DEFAULT_OUT)
    data = open(src, "rb").read()
    sha = hashlib.sha256(data).hexdigest()
    errs = []
    if len(data) != EXPECTED_SIZE:
        errs.append(f"tamano {len(data)}, esperado {EXPECTED_SIZE} (128 KB)")
    if data[:2] != b"AB":
        errs.append("no empieza por 'AB' (cabecera de ROM del MSX)")
    if b"Nextor kernel version" not in data:
        errs.append("no encuentro 'Nextor kernel version'")
    if b"MegaFlashROM SCC+ SD" not in data:
        errs.append("no encuentro el driver 'MegaFlashROM SCC+ SD' (la interfaz que emula TF_CONTROLLER)")
    if sha != EXPECTED_SHA256:
        msg = f"SHA-256 {sha}, esperado {EXPECTED_SHA256} (Nextor-2.1.2.MegaFlashSDSCC.1-slot.ROM)"
        if other:
            print(f"aviso: {msg}; --otra-rom: sigo")
        else:
            errs.append(msg + "; con --otra-rom se acepta otra ROM que pase el resto de comprobaciones")
    if errs:
        for e in errs:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1
    ver = data[data.index(b"Nextor kernel version"):][:28].decode("ascii", "replace")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(data)
    print(f"{ver.strip()}; {len(data)} bytes, SHA-256 {sha}")
    print(f"pack escrito en {out}")
    print("grabar en la flash en 0x100000 (programmer_cli -d GW2AR-18C -r 38 --spiaddr 0x100000 -f <pack>)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
