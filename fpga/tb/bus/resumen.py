#!/usr/bin/env python3
# ============================================================================
# resumen.py -- tabla Markdown con lo esencial de los logs de tb_bus.sv
# (fpga/tb/bus/out/tb_<TOPO>_<BASE>_<MEMPW>[_<TAGX>]_<HZ>.log).
#
# Uso: python3 resumen.py [directorio de logs] [filtro del nombre]
#
# Columnas: veredicto; /WAIT en el slot en P#0/P#1 (peor, ns) frente al
# presupuesto; lecturas de P#0, P#1 y P#2-6 mal (dato mal o inestable) /
# accesos; eventos duplicados/perdidos; direcciones mal (E/S / nuestra memoria
# / memoria ajena); cadena D+n; rebotes de /IORQ con dato mal y peor /WAIT
# en el slot con rebote de /RD-/WR y de /IORQ; espera mas larga en uso
# normal (ciclos); pre-WAIT en IN/OUT a puertos que no son 60h/61h.
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
import glob
import os
import re
import sys


def parse(path):
    t = open(path, encoding="utf-8", errors="replace").read()
    r = {}
    m = re.search(r"TOPO=(\d).*?V99_BASE=(\w+) MEMPW=(\d) Z80 a ([\d.]+) MHz", t)
    r["topo"], r["base"], r["mempw"], r["mhz"] = m.group(1), m.group(2), m.group(3), float(m.group(4))
    m = re.search(r"ADAPTIVE_SCAN=(\d) PREWAIT_IO_EN=(\d) ADDR_HOLD=(\d) DRIVE_TAIL_GUARD=(\d)", t)
    r["cfg"] = "".join(m.groups()) if m else "?"
    m = re.search(r"presupuestos: /WAIT 1,5 T - 145 = (-?\d+) ns", t)
    r["budget"] = int(m.group(1)) if m else None
    cats = {}
    for line in t.splitlines():
        mm = re.match(r"   (P#0 lectura|P#0 escritura|P#1 lectura|P#1 escritura|P#2-6 lectura|P#2-7 escritura|"
                      r"FFFFh lectura|MegaRAM lectura|P#0 escr\. OTIR|P#1 escr\. OTIR)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)", line)
        if mm:
            n, bad, unst, bn, wb, sv = (int(x) for x in mm.groups()[1:7])
            cats[mm.group(1)] = dict(n=n, bad=bad, unst=unst, bn=bn, wb=wb, sv=sv,
                                     wpin=float(mm.group(8)), wslot=float(mm.group(9)), tw=int(mm.group(10)))
    r["cats"] = cats
    m = re.search(r"eventos: duplicados (\d+), perdidos (\d+)", t)
    r["dup"], r["lost"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"E/S (\d+) comprobadas, (\d+) mal, IORQ sin alinear (\d+); memoria (\d+), (\d+) mal", t)
    r["io_bad"], r["mem_bad"] = int(m.group(2)), int(m.group(5))
    m = re.search(r"memoria ajena \(M1 y memoria del MSX\): (\d+) comprobadas, (\d+) mal", t)
    r["fmem"] = (int(m.group(2)), int(m.group(1))) if m else None
    m = re.search(r"E/S P#0/P#1 en D\+(-?\d+).*MegaRAM en D\+(-?\d+)", t)
    r["chain"], r["chain_mem"] = (int(m.group(1)), int(m.group(2))) if m else (None, None)
    m = re.search(r"rebote de /RD o /WR (\d+) / (\d+), de /IORQ (\d+) / (\d+)", t)
    r["bb"] = tuple(int(x) for x in m.groups()) if m else None
    m = re.search(r"peor /WAIT en el slot (-?[\d.]+) / (-?[\d.]+) ns", t)
    r["bbw"] = (float(m.group(1)), float(m.group(2))) if m else None
    m = re.search(r"/WAIT seguido maximo en uso normal (\d+) ciclos", t)
    r["wmax"] = int(m.group(1)) if m else None
    m = re.search(r"pre-WAIT en IN/OUT a puertos que no son 60h/61h: (\d+)", t)
    r["pwspur"] = int(m.group(1)) if m else None
    m = re.search(r"revisita maxima \(ciclos entre parejas\): g0 (\d+), g1 (\d+), g2 (\d+)", t)
    r["rev"] = "/".join(m.groups()) if m else "?"
    m = re.search(r"conduccion: sin lectura legitima (\d+), tarde (\d+), choques (\d+)", t)
    r["drv"] = tuple(int(x) for x in m.groups())
    m = re.search(r"^(BUS_OK.*|BUS_FAIL.*|TB_TIMEOUT)$", t, re.M)
    v = m.group(1).strip() if m else "SIN VEREDICTO"
    r["verdict"] = "OK" if v == "BUS_OK" else ("OK*" if v.startswith("BUS_OK") else v.replace("BUS_FAIL", "FALLA"))
    return r


def fmt_rd(c):
    if c is None:
        return "-"
    return "%d/%d" % (c["bad"] + c["unst"], c["n"])


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "out")
    filt = sys.argv[2] if len(sys.argv) > 2 else ""
    rows = []
    for p in sorted(glob.glob(os.path.join(d, "tb_*.log"))):
        if filt and filt not in os.path.basename(p):
            continue
        try:
            rows.append((os.path.basename(p), parse(p)))
        except Exception as ex:      # log a medias
            rows.append((os.path.basename(p), None))
    rows.sort(key=lambda x: (x[0].rsplit("_", 1)[0], x[1]["mhz"] if x[1] else 0))
    print("| log | MHz | veredicto | /WAIT slot P#0/P#1 (pres.) | P#0 lect. mal | P#1 lect. mal | P#2-6 lect. mal | dup/perd | dir. E/S/mem/ajena mal | cadena | rebote IORQ mal | /WAIT slot con rebote RD-WR/IORQ | espera max | revisita | conduccion mal/choques | pre-WAIT ajeno |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for name, r in rows:
        if r is None:
            print("| %s | - | log incompleto |" % name)
            continue
        c = r["cats"]
        w = [c[k]["wslot"] for k in ("P#0 lectura", "P#0 escritura", "P#1 lectura", "P#1 escritura") if k in c]
        ws = ("%.0f (%d)" % (max(w), r["budget"])) if w and max(w) >= 0 else "-"
        fm = ("%d/%d" % r["fmem"]) if r["fmem"] else "-"
        bbw = ("%.0f/%.0f" % r["bbw"]) if r["bbw"] else "-"
        print("| %s | %.2f | %s | %s | %s | %s | %s | %d/%d | %d/%d/%s | %s | %s | %s | %s | %s | %d/%d | %s |" % (
            name.replace("tb_", "").replace(".log", ""), r["mhz"], r["verdict"], ws,
            fmt_rd(c.get("P#0 lectura")), fmt_rd(c.get("P#1 lectura")), fmt_rd(c.get("P#2-6 lectura")),
            r["dup"], r["lost"], r["io_bad"], r["mem_bad"], fm,
            ("D+%d" % r["chain"]) if r["chain"] is not None and r["chain"] >= 0 else "-",
            ("%d" % r["bb"][2]) if r["bb"] else "-", bbw,
            r["wmax"] if r["wmax"] is not None else "-", r["rev"], r["drv"][0], r["drv"][2],
            r["pwspur"] if r["pwspur"] is not None else "-"))


if __name__ == "__main__":
    main()
