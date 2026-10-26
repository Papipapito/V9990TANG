#!/usr/bin/env python3
# ============================================================================
# syn_rsc.py -- recursos de sintesis por modulo a partir del _syn_rsc.xml de
# GowinSynthesis (impl/gwsynthesis/<base>_syn_rsc.xml), para comparar el bus
# del hito 5 con el de main (fpga/check_bus.tcl, normal y CHECK_BUS_REF=1).
#
# Uso: python3 syn_rsc.py <a_syn_rsc.xml> [<b_syn_rsc.xml>] [modulo ...]
#      (modulos por defecto: u_bus, el total del top)
# Cada fila: LUT / ALU / FF / BSRAM con los submodulos (T_*) y sin ellos.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
import re
import sys
import xml.etree.ElementTree as ET


def total(attr):
    """'147(111)' -> 147; '' -> 0"""
    if not attr:
        return 0
    m = re.match(r"(\d+)", attr)
    return int(m.group(1)) if m else 0


def find(node, name):
    if node.get("name") == name:
        return node
    for ch in node:
        r = find(ch, name)
        if r is not None:
            return r
    return None


def row(node):
    return (total(node.get("T_Lut")), total(node.get("T_Alu")),
            total(node.get("T_Register")), total(node.get("T_Bsram")))


def main():
    files = [a for a in sys.argv[1:] if a.endswith(".xml")]
    mods = [a for a in sys.argv[1:] if not a.endswith(".xml")] or ["u_bus"]
    roots = [ET.parse(f).getroot() for f in files]
    print("%-28s" % "modulo" + "".join("  %-26s" % f.replace("\\", "/").split("/")[-1] for f in files))
    for m in ["(top)"] + mods:
        cells = []
        for r in roots:
            n = r if m == "(top)" else find(r, m)
            cells.append("LUT %5d ALU %4d FF %5d BSRAM %2d" % row(n) if n is not None else "-")
        print("%-28s" % m + "".join("  %-26s" % c for c in cells))
    if len(roots) == 2:
        for m in ["(top)"] + mods:
            a = roots[0] if m == "(top)" else find(roots[0], m)
            b = roots[1] if m == "(top)" else find(roots[1], m)
            if a is not None and b is not None:
                d = [x - y for x, y in zip(row(a), row(b))]
                print("%-28s  diferencia (1 - 2): LUT %+d ALU %+d FF %+d BSRAM %+d" % ((m,) + tuple(d)))


if __name__ == "__main__":
    main()
