#!/usr/bin/env python3
# ============================================================================
# filelist.py -- lista de ficheros del banco de placa entera (tb_top) sacada de
# fpga/build_common.tcl, la de las builds: interpreta la seccion "set FILES {}"
# (lappend, los if {$MEGA} y el foreach del core) con CFG y VARIANT, y
#   - quita las restricciones (.cst, .sdc),
#   - cambia el DVI_TX cifrado (src/board/rev1/dvi_tx/dvi_tx.v) por el stub de
#     tb/video/sim/dvi_tx_stub.sv,
#   - pone delante los ficheros que declaran un package (Verilator los quiere
#     antes que sus usuarios; Gowin no), en el orden de la lista.
# Uso: filelist.py <fpga> <cfg> <variante>  -> una ruta por linea (absolutas)
# Sale con 2 si la seccion no se entiende (para que el banco no compile otra
# lista sin avisar).
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
import os
import re
import sys


def main():
    fpga, cfg, variant = sys.argv[1], sys.argv[2], sys.argv[3]
    mega = cfg in ("v9990_megaram", "v9990_megaram_nextor")
    nextor = (cfg == "v9990_megaram_nextor")
    name = f"{cfg}_{variant}"
    with open(os.path.join(fpga, "build_common.tcl"), encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    try:
        i0 = next(i for i, l in enumerate(lines) if l.strip() == "set FILES {}")
        i1 = next(i for i, l in enumerate(lines) if i > i0 and l.startswith("# Copias parcheadas"))
    except StopIteration:
        print("filelist.py: no encuentro la seccion FILES de build_common.tcl", file=sys.stderr)
        sys.exit(2)

    def subst(s):
        return s.replace("${VARIANT}", variant).replace("${CFG}", cfg).replace("${NAME}", name)

    files = []
    stack = []          # condiciones de los if abiertos
    i = i0 + 1
    while i < i1:
        l = lines[i].strip()
        i += 1
        if not l or l.startswith("#"):
            continue
        if l == "if {$MEGA} {":
            stack.append(mega)
            continue
        if l == "if {$NEXTOR} {":
            stack.append(nextor)
            continue
        m = re.match(r"foreach f \{(.*)$", l)
        if m:
            body = m.group(1)
            while "}" not in body:
                body += " " + lines[i].strip()
                i += 1
            names = body[:body.index("}")].split()
            tmpl = lines[i].strip()
            i += 1
            m2 = re.match(r"lappend FILES (\S+)\$f\.sv$", tmpl)
            if not m2 or lines[i].strip() != "}":
                print(f"filelist.py: foreach no reconocido: {tmpl}", file=sys.stderr)
                sys.exit(2)
            i += 1
            if all(stack):
                files += [f"{m2.group(1)}{n}.sv" for n in names]
            continue
        if l == "}":
            if not stack:
                print("filelist.py: '}' de mas", file=sys.stderr)
                sys.exit(2)
            stack.pop()
            continue
        m = re.match(r"lappend FILES (\S+)$", l)
        if m:
            if all(stack):
                files.append(subst(m.group(1)))
            continue
        print(f"filelist.py: linea no reconocida: {l}", file=sys.stderr)
        sys.exit(2)
    if stack:
        print("filelist.py: if sin cerrar", file=sys.stderr)
        sys.exit(2)

    out = []
    for f in files:
        if f.endswith(".cst") or f.endswith(".sdc"):
            continue
        if f == "src/board/rev1/dvi_tx/dvi_tx.v":
            f = "tb/video/sim/dvi_tx_stub.sv"
        p = os.path.join(fpga, f)
        if not os.path.exists(p):
            print(f"filelist.py: falta {f}", file=sys.stderr)
            sys.exit(2)
        out.append(p)
    # ficheros con package delante, en orden topologico de los PAQUETE:: que
    # nombran (fuera de comentarios); a igualdad, el orden de la lista
    pkg = []
    rest = []
    defs = {}
    uses = {}
    for p in out:
        with open(p, encoding="utf-8", errors="replace") as fh:
            txt = fh.read()
        d = re.findall(r"^\s*package\s+(\w+)\s*;", txt, re.M)
        if d:
            pkg.append(p)
            for n in d:
                defs[n] = p
            code = re.sub(r"//.*", "", re.sub(r"/\*.*?\*/", "", txt, flags=re.S))
            uses[p] = set(re.findall(r"\b([A-Za-z_]\w*)::", code)) - set(d)
        else:
            rest.append(p)
    ordered = []
    pending = list(pkg)
    while pending:
        for p in pending:
            need = {defs[n] for n in uses[p] if n in defs}
            if need <= set(ordered):
                ordered.append(p)
                pending.remove(p)
                break
        else:
            print("filelist.py: dependencia circular entre paquetes", file=sys.stderr)
            sys.exit(2)
    final = ordered + rest
    # Copias para Verilator (solo con <dir_copias>). Dos cosas que Gowin
    # acepta y Verilator 5.020 no, y que el banco arregla en una copia sin
    # tocar el RTL:
    #  1. Verilator toma como metacomentario todo comentario que empieza por
    #     la palabra "verilator" (sin distinguir mayusculas) y da error si no
    #     lo conoce; main.sv tiene uno en prosa ("//    Verilator 5.020, que
    #     tolera ..."). La copia lo cambia por "(Verilator)".
    #  2. "Parameter-resolved constants must not use dotted references": un
    #     $bits(interfaz.Signal) o interfaz.COUNT en un parametro, un
    #     localparam o la condicion de un if de generate. La copia pone el
    #     valor que tiene en este diseno: SOUND_IF de CONFIG::SOUND_BIT_WIDTH
    #     (Sound, AttOut*, mix_* de main.sv y los puertos de SOUND_ATTENUATOR y
    #     SOUND_MIXER, que solo se instancian con ellas), de
    #     CONFIG_BOARD::DAC_BIT_WIDTH (SoundExternal/SoundInternal de main.sv
    #     y el IN de DAC_16BIT, que en el top es SoundExternal[0]) y
    #     UMA_IF.COUNT = 2 (el top instancia UMA_IF Uma() con su valor por
    #     defecto).
    #  3. BUS_IF.connect_dummy() sobre ExpBus[n] dentro de un generate: la
    #     copia de main.sv instancia en su lugar TBTOP_BUS_DUMMY
    #     (gowin_models.sv), que pone lo mismo.
    # Cada sustitucion tiene que aplicarse al menos una vez: si el RTL cambia
    # y deja de casar, el banco se para aqui.
    S = r"\$bits\(\s*%s(\[[^\]]*\])?\.Signal\s*\)"
    PATCHES = {
        "main.sv": [
            (S % r"(Sound|AttOutExt|AttOutInt|mix_ext|mix_int)", "(CONFIG::SOUND_BIT_WIDTH)"),
            (S % r"(SoundExternal|SoundInternal)", "(CONFIG_BOARD::DAC_BIT_WIDTH)"),
            (r"always_comb\s+ExpBus\[(BUS_\w+)\]\.connect_dummy\(\);", r"TBTOP_BUS_DUMMY u_tbtop_dummy_\1 (.Bus(ExpBus[\1]));"),
        ],
        "sound.sv": [
            (S % r"(IN|OUT)", "(CONFIG::SOUND_BIT_WIDTH)"),
        ],
        "dac_16bit.sv": [
            (S % r"IN", "(CONFIG_BOARD::DAC_BIT_WIDTH)"),
        ],
        "tnCart_board_wt200b_top.sv": [
            (r"\bUma\.COUNT\b", "2"),
        ],
    }
    if len(sys.argv) > 4:
        cdir = sys.argv[4]
        os.makedirs(cdir, exist_ok=True)
        rx = re.compile(r"(//|/\*)(\s*)(verilator\b)(?!\s+(lint_off|lint_on|public|tracing_off|tracing_on|coverage_off|coverage_on))", re.I)
        for k, p in enumerate(final):
            base_name = os.path.basename(p)
            with open(p, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
            new, n = rx.subn(lambda m: m.group(1) + m.group(2) + "(" + m.group(3) + ")", txt)
            what = [f"{n} comentario(s) 'verilator' en prosa"] if n else []
            for pat, rep in PATCHES.get(base_name, []):
                new, c = re.subn(pat, rep, new)
                if c == 0:
                    print(f"filelist.py: la sustitucion {pat!r} no casa en {base_name}: revisar el banco", file=sys.stderr)
                    sys.exit(2)
                what.append(f"{c} x {rep}")
            if what:
                q = os.path.join(cdir, base_name)
                with open(q, "w", encoding="utf-8") as fh:
                    fh.write(new)
                print(f"filelist.py: copia de {os.path.relpath(p, fpga)}: {', '.join(what)}", file=sys.stderr)
                final[k] = q
    for p in final:
        print(os.path.abspath(p))


if __name__ == "__main__":
    main()
