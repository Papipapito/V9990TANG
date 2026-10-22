#!/usr/bin/env python3
# check_build.py -- puerta de build de V9990TANG
#
# BSD 3-Clause License. Copyright (c) 2026, Papipapito.
#
# Lee el informe de recursos (.rpt.txt), el de timing (.tr), el .sdc, el .sdf
# y los logs de gw_sh de una build de Gowin, y aplica la puerta de
# docs/VERIFICATION.md (los numeros de cada punto son los de ese documento):
#   1. restricciones: set_clock_groups presente y "Actived", ninguna orden en
#      otro estado, el .tr con exactamente las ordenes del .sdc, y ninguna
#      excepcion sobre DCLK o CLK_BASE salvo las permitidas
#   2. 0 endpoints violados en setup y hold; tablas de setup, hold, recovery y
#      removal presentes, cada una con su informe global (sin filtros) y peor
#      slack >= 0; la carrera CLK_BASE -> DCLK analizada en setup y hold; el
#      informe DCLK -> CLK_BASE presente y ningun camino lanzado desde DCLK
#      hacia otro reloj en ninguna tabla
#   3. Fmax de los relojes pedidos
#   4. recursos frente a la referencia, tope y aviso de CLS, PRIMARY, rPLL
#   5. un log de sintesis y uno de P&R (reconocidos por su contenido), de esta
#      build y sin errores (leer los avisos es manual: aqui solo se listan)
#   6. modelo de DCLK: -offset y forma del create_generated_clock del .sdc
#      frente al .tr, DCLK en el grupo de CLK_BASE en todos los
#      set_clock_groups, el flanco real (.sdf, modelo lento) no antes que el
#      modelado, y .rpt.txt, .tr y .sdf de la misma build
# Si falta algun dato obligatorio, la puerta es INCOMPLETA (salida 2), salvo
# con --parcial, para analisis que no son la build de un hito.
# Salida: 0 pasa, 1 falla, 2 incompleta. Uso (desde la raiz del repositorio):
#   python tools/check_build.py fpga/impl/pnr/v9990_xtal \
#       --ref-logic 14140 --ref-cls 8696 --ref-bsram 24 --tol 0.01 \
#       --max-cls 9331 --warn-cls 9250 --rpll 2 --fmax CLK_BASE=109 \
#       --log fpga/impl/gwsynthesis/v9990_xtal.log --log fpga/impl/pnr/v9990_xtal.log \
#       --sdc fpga/constraints/v9990_xtal.sdc

import argparse
import collections
import datetime
import os
import re
import sys

# excepciones del .sdc que pueden nombrar DCLK o CLK_BASE (ver el .sdc)
ALLOWED_EXCEPTIONS = {'set_false_path -from [get_regs {reset_n_s0}] -to [get_clocks {DCLK}]'}
EXCEPTION_TYPES = ('TC_FALSE_PATH', 'TC_MULTICYCLE_PATH', 'TC_MAX_DELAY', 'TC_MIN_DELAY',
                   'TC_CLOCK_UNCERTAINTY', 'TC_CLOCK_LATENCY', 'TC_DISABLE_TIMING')


def read(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if raw.startswith(b'\xff\xfe') or raw.startswith(b'\xfe\xff') or b'\x00' in raw[:200]:
        raise ValueError(f'{path}: parece UTF-16 (redirigido con PowerShell 5.1?); '
                         'usar los logs de impl/ o redirigir con cmd o bash')
    return raw.decode('utf-8', errors='replace')


def resource(rpt, name):
    """'  CLS   | 8696/10368  |  84%' -> (8696, 10368)."""
    m = re.search(r'^\s*' + re.escape(name) + r'\s*\|\s*(\d+)/(\d+)', rpt, re.M)
    return (int(m.group(1)), int(m.group(2))) if m else None


def section(text, title, next_title):
    """Cuerpo de una seccion del .tr (la ultima aparicion: la primera es el indice).
    None si el titulo no aparece al menos dos veces."""
    starts = [m.end() for m in re.finditer(re.escape(title), text)]
    if len(starts) < 2:
        return None
    start = starts[-1]
    end = text.find(next_title, start) if next_title else -1
    return text[start:end if end >= 0 else len(text)]


def path_rows(table):
    """(slack, reloj origen, reloj destino) de cada fila de una tabla de caminos."""
    return [(float(m.group(1)), m.group(2), m.group(3)) for m in re.finditer(
        r'^\s*\d+\s+(-?\d+\.\d+)\s+\S+\s+\S+\s+(\S+?):\[[RF]\]\s+(\S+?):\[[RF]\]', table, re.M)]


def reports(body):
    """[(orden, filas)] de cada informe (<Report Command>) de una seccion 3.1.x."""
    parts = body.split('<Report Command>:')[1:]
    out = []
    for p in parts:
        cmd, _, rest = p.partition('\n')
        out.append((re.sub(r'\s+', ' ', cmd.strip()), path_rows(rest)))
    return out


def is_global(cmd):
    """report_timing sin filtros: solo -setup/-hold/-recovery/-removal y, como
    mucho, -max_paths N y -max_common_paths N."""
    t = cmd.split()
    if not t or t[0] != 'report_timing':
        return False
    t, i, kinds = t[1:], 0, 0
    while i < len(t):
        if t[i] in ('-setup', '-hold', '-recovery', '-removal'):
            kinds += 1
            i += 1
        elif t[i] in ('-max_paths', '-max_common_paths') and i + 1 < len(t) and t[i + 1].isdigit():
            i += 2
        else:
            return False
    return kinds == 1


def clock_filter(cmd, opt):
    m = re.search(re.escape(opt) + r'\s+\[get_clocks \{([^}]*)\}\]', cmd)
    return m.group(1).split() if m else None


def sdc_commands(sdc):
    """Ordenes de un .sdc (una por linea, sin comentarios ni lineas vacias)."""
    out = []
    for line in sdc.splitlines():
        line = line.strip()
        if line and not line.startswith('//') and not line.startswith('#'):
            out.append(re.sub(r'\s+', ' ', line))
    return out


def clock_groups_relation(cmds, a, b):
    """'mismo' si algun set_clock_groups pone a y b en el mismo grupo y ninguno
    los separa; 'separados' si alguno los separa; 'ninguno' si nadie los nombra
    juntos; 'ilegible' si una orden no se entiende o usa comodines."""
    same = sep = False
    for c in cmds:
        if not c.startswith('set_clock_groups'):
            continue
        rest = c[len('set_clock_groups'):]
        groups = re.findall(r'-group\s+(?:\[get_clocks\s+)?\{([^}]*)\}\]?', rest)
        groups += [[g] for g in re.findall(r'-group\s+\[get_clocks\s+([^\s{}\[\]]+)\]', rest)]
        groups = [g.split() if isinstance(g, str) else g for g in groups]
        if not groups or any(ch in rest for ch in '*?') or rest.count('-group') != len(groups):
            return 'ilegible'
        ina = [a in g for g in groups]
        inb = [b in g for g in groups]
        if not any(ina) or not any(inb):
            if len(groups) == 1 and (any(ina) != any(inb)):
                sep = True      # un solo grupo: el resto de relojes es el otro
            continue
        if ina == inb and sum(ina) == 1:
            same = True
        else:
            sep = True
    return 'separados' if sep else ('mismo' if same else 'ninguno')


def clock_summary(tr):
    """{reloj: (periodo, subida, maestro)} de la seccion 2.2 del .tr."""
    body = section(tr, '2.2 Clock Summary', '2.3 Max Frequency Summary') or ''
    out = {}
    for m in re.finditer(r'^\s*\d+\s+(\S+)\s+(Base|Generated)\s+([\d.]+)\s+[\d.]+MHz\s+([\d.]+)\s+[\d.]+\s*(\S*)\s*(\S*)', body, re.M):
        name, kind, period, rise = m.group(1), m.group(2), float(m.group(3)), float(m.group(4))
        master = m.group(6) if kind == 'Generated' else ''
        out[name] = (period, rise, master)
    return out


def sdf_delay(sdf, pattern):
    """Valor 'max' (modelo lento) del primer (a:b:c) que sigue a pattern."""
    m = re.search(pattern + r'\s*\(([\d.]+):([\d.]+):([\d.]+)\)', sdf)
    return float(m.group(3)) if m else None


def sdf_fastest_lut(sdf):
    """(retardo, instancia, pin) del IOPATH Ix->F mas rapido (valor max) de las
    celdas LUT1..LUT4 del .sdf. Los MUX2_LUTx no cuentan."""
    best = None
    for m in re.finditer(r'\(CELLTYPE "LUT[1-4]"\)\s*\(INSTANCE ([^)]*)\)\s*\(DELAY\s*\(ABSOLUTE((?:\s*\(IOPATH [^\n]*\))*)', sdf):
        for p in re.finditer(r'\(IOPATH (I\d) F \(([\d.]+):([\d.]+):([\d.]+)\)', m.group(2)):
            d = float(p.group(4))
            if best is None or d < best[0]:
                best = (d, m.group(1).replace('\\', ''), p.group(1))
    return best


def parse_date(s):
    try:
        return datetime.datetime.strptime(s.strip(), '%a %b %d %H:%M:%S %Y')
    except ValueError:
        return None


def created(text, pattern):
    m = re.search(pattern, text)
    return parse_date(m.group(1)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base', help='ruta sin extension: .../impl/pnr/<output_base_name>')
    ap.add_argument('--ref-logic', type=int)
    ap.add_argument('--ref-cls', type=int)
    ap.add_argument('--ref-bsram', type=int)
    ap.add_argument('--tol', type=float, default=0.01)
    ap.add_argument('--max-cls', type=int, help='tope de CLS (falla si se pasa)')
    ap.add_argument('--warn-cls', type=int, help='aviso de CLS (no falla)')
    ap.add_argument('--max-primary', type=int, default=8)
    ap.add_argument('--rpll', type=int, help='numero exacto de rPLL esperado')
    ap.add_argument('--fmax', action='append', default=[], help='RELOJ=MHz minimo (repetible)')
    ap.add_argument('--log', action='append', default=[], help='log de gw_sh (repetible)')
    ap.add_argument('--sdc', help='el .sdc de la build')
    ap.add_argument('--sdf', help='el .sdf de la build (por defecto <base>.sdf)')
    ap.add_argument('--dclk-offset', type=float,
                    help='confirmacion opcional del -offset de DCLK (se lee del .sdc)')
    ap.add_argument('--parcial', action='store_true',
                    help='analisis que no es la build de un hito: los puntos sin datos no la hacen incompleta')
    a = ap.parse_args()

    rpt = read(a.base + '.rpt.txt')
    tr = read(a.base + '.tr')
    sdc = read(a.sdc) if a.sdc else None
    sdc_cmds = sdc_commands(sdc) if sdc is not None else []
    ok = True
    lines = []
    missing = []

    def check(cond, text):
        nonlocal ok
        ok = ok and cond
        lines.append(('PASA ' if cond else 'FALLA') + '  ' + text)

    def info(text):
        lines.append('       ' + text)

    def not_checked(point, why):
        missing.append(point)
        lines.append(f'NO COMPROBADO  {point}: {why}')

    # ---- misma build (.rpt.txt y .tr) ----
    t_rpt = created(rpt, r'<Created Time>:(.*)')
    t_tr = created(tr, r'<Created Time>:(.*)')
    if t_rpt and t_tr:
        check(abs((t_tr - t_rpt).total_seconds()) <= 60, f'.rpt.txt y .tr de la misma build ({t_rpt} / {t_tr})')
    else:
        not_checked('6 misma build', f'sin fecha legible en el .rpt.txt ({t_rpt}) o en el .tr ({t_tr})')

    # ---- 4. recursos ----
    for name, ref in (('Logic', a.ref_logic), ('CLS', a.ref_cls), ('BSRAM', a.ref_bsram)):
        r = resource(rpt, name)
        if r is None:
            check(False, f'{name}: no encontrado en el .rpt.txt')
            continue
        used, total = r
        txt = f'{name}: {used}/{total} ({100.0 * used / total:.1f} %)'
        if ref:
            dev = (used - ref) / ref
            check(abs(dev) <= a.tol, f'{txt}, referencia {ref}, desviacion {100 * dev:+.2f} % (tolerancia {100 * a.tol:.1f} %)')
        else:
            info(txt)
            not_checked('4 recursos', f'falta --ref-{name.lower()}')
    reg = resource(rpt, 'Register')
    if reg:
        info(f'Register: {reg[0]}/{reg[1]}')
    cls = resource(rpt, 'CLS')
    if a.max_cls:
        check(cls is not None and cls[0] <= a.max_cls, f'CLS <= {a.max_cls}')
    else:
        not_checked('4 recursos', 'falta --max-cls')
    if a.warn_cls and cls is not None:
        info(f'AVISO: CLS {cls[0]} >= {a.warn_cls}' if cls[0] >= a.warn_cls else f'CLS por debajo del aviso ({a.warn_cls})')
    prim = resource(rpt, 'PRIMARY')
    check(prim is not None and prim[0] <= a.max_primary,
          f'PRIMARY: {prim[0] if prim else "?"}/{prim[1] if prim else "?"} (maximo {a.max_primary})')
    rpll = resource(rpt, 'rPLL')
    if a.rpll is not None:
        check(rpll is not None and rpll[0] == a.rpll,
              f'rPLL: {rpll[0] if rpll else "?"}/{rpll[1] if rpll else "?"} (esperado {a.rpll})')
    else:
        not_checked('4 recursos', 'falta --rpll')
    for name in ('LW', 'CLKDIV', 'GCLK_PIN'):
        r = resource(rpt, name)
        if r:
            info(f'{name}: {r[0]}/{r[1]}')

    # ---- 1. restricciones ----
    tc = section(tr, '3.8 Timing Constraints Report', None) or ''
    rows = re.findall(r'^\s*(TC_\w+)\s+(\w+)\s+(.*?)\s*$', tc, re.M)
    if not rows:
        check(False, 'Timing Constraints Report: sin filas')
    groups = [r for r in rows if r[0] == 'TC_CLOCK_GROUP']
    check(bool(groups) and all(r[1] == 'Actived' for r in groups),
          f'set_clock_groups (TC_CLOCK_GROUP): {", ".join(r[1] for r in groups) or "no aparece"}')
    inactive = [r for r in rows if r[1] != 'Actived']
    check(not inactive, f'ordenes no activas: {len(inactive)} de {len(rows)}'
          + ''.join(f'\n         {r[0]} {r[1]}: {r[2][:110]}' for r in inactive))
    kinds = collections.Counter(r[0] for r in rows)
    info('ordenes en el .tr: ' + ', '.join(f'{k} x{v}' for k, v in kinds.items()))
    bad_exc = [re.sub(r'\s+', ' ', r[2]) for r in rows
               if (r[0] in EXCEPTION_TYPES or not r[0].startswith(('TC_CLOCK', 'TC_GENERATED_CLOCK', 'TC_REPORT')))
               and re.search(r'\b(DCLK|CLK_BASE)\b', r[2]) and re.sub(r'\s+', ' ', r[2]) not in ALLOWED_EXCEPTIONS]
    check(not bad_exc, f'excepciones sobre DCLK o CLK_BASE fuera de las permitidas: {len(bad_exc)}'
          + ''.join('\n         ' + e[:110] for e in bad_exc[:5]))
    if sdc is not None:
        # el .tr reimprime cada orden leyendo el fichero (agrupadas por tipo):
        # si el .sdc cambia despues de la build, ya no coinciden
        want = collections.Counter(sdc_cmds)
        got = collections.Counter(re.sub(r'\s+', ' ', r[2]) for r in rows)
        same = want == got
        check(same, f'el .tr tiene exactamente las ordenes del .sdc ({sum(want.values())} en el .sdc, {sum(got.values())} en el .tr)'
              + ('' if same else ' -- el .sdc no es el de esta build: recompilar'
                 + ''.join('\n         falta en el .tr: ' + m[:110] for m in (want - got))
                 + ''.join('\n         sobra en el .tr: ' + s[:110] for s in (got - want))))
    else:
        not_checked('1 restricciones', 'falta --sdc')

    # ---- 2. timing ----
    m = re.search(r'<Numbers of Setup Violated Endpoints>:(\d+)', tr)
    check(m is not None and int(m.group(1)) == 0, f'endpoints de setup violados (global): {m.group(1) if m else "?"}')
    m = re.search(r'<Numbers of Hold Violated Endpoints>:(\d+)', tr)
    check(m is not None and int(m.group(1)) == 0, f'endpoints de hold violados (global): {m.group(1) if m else "?"}')
    dclk_launch = []
    by_kind = {}
    for title, nxt, what in (('3.1.1 Setup Paths Table', '3.1.2 Hold Paths Table', 'setup'),
                             ('3.1.2 Hold Paths Table', '3.1.3 Recovery Paths Table', 'hold'),
                             ('3.1.3 Recovery Paths Table', '3.1.4 Removal Paths Table', 'recovery'),
                             ('3.1.4 Removal Paths Table', '3.2 Minimum Pulse Width Table', 'removal')):
        body = section(tr, title, nxt)
        if body is None:
            check(False, f'tabla de {what}: no esta en el .tr')
            continue
        reps = reports(body)
        by_kind[what] = reps
        cmds = [c for c, _ in reps]
        if not any(is_global(c) for c in cmds):
            check(False, f'tabla de {what}: ninguna orden global (solo {cmds or "nada"}): un report_timing filtrado en el .sdc la ha sustituido')
            continue
        allrows = [r for _, rr in reps for r in rr]
        dclk_launch += [(what, r) for r in allrows if r[1] == 'DCLK' and r[2] != 'DCLK']
        if allrows:
            check(min(r[0] for r in allrows) >= 0,
                  f'peor slack de {what}: {min(r[0] for r in allrows):.3f} ns  [{len(cmds)} informe(s): ' + '; '.join(cmds) + ']')
        else:
            lines.append(f'PASA   peor slack de {what}: sin caminos  [' + '; '.join(cmds) + ']')
    for what in ('setup', 'hold'):
        race = [rr for c, rr in by_kind.get(what, [])
                if clock_filter(c, '-from_clock') == ['CLK_BASE'] and clock_filter(c, '-to_clock') == ['DCLK']]
        check(bool(race) and any(r[1] == 'CLK_BASE' and r[2] == 'DCLK' for rr in race for r in rr),
              f'carrera CLK_BASE -> DCLK analizada en {what}: '
              + (f'{sum(len(rr) for rr in race)} caminos, peor slack {min(r[0] for rr in race for r in rr):.3f} ns'
                 if race and any(race) else 'sin informe o sin caminos'))
    back = [c for c, _ in by_kind.get('setup', [])
            if clock_filter(c, '-from_clock') == ['DCLK'] and clock_filter(c, '-to_clock') == ['CLK_BASE']]
    check(bool(back), 'informe de setup DCLK -> CLK_BASE presente' + ('' if back else ': falta en el .sdc'))
    check(not dclk_launch, f'caminos lanzados desde DCLK hacia otro reloj: {len(dclk_launch)}'
          + ''.join(f'\n         {w}: {r[1]} -> {r[2]}, slack {r[0]:.3f}' for w, r in dclk_launch[:5]))

    # ---- 3. Fmax ----
    fmax = dict(re.findall(r'^\s*\d+\s+(\S+)\s+[\d.]+\(MHz\)\s+([\d.]+)\(MHz\)', tr, re.M))
    for spec in a.fmax:
        clk, mhz = spec.split('=')
        got = float(fmax[clk]) if clk in fmax else None
        check(got is not None and got >= float(mhz),
              f'Fmax {clk}: {got if got is not None else "?"} MHz (minimo {mhz})')
    if not any(s.startswith('CLK_BASE=') for s in a.fmax):
        not_checked('3 Fmax', 'falta --fmax CLK_BASE=...')
    for clk, f in fmax.items():
        if not any(s.split('=')[0] == clk for s in a.fmax):
            info(f'Fmax {clk}: {f} MHz')

    # ---- 6. modelo de DCLK (modelo lento: el del analisis de setup) ----
    sdf_path = a.sdf or (a.base + '.sdf')
    if sdc is None:
        not_checked('6 modelo de DCLK', 'falta --sdc')
    elif not os.path.exists(sdf_path):
        not_checked('6 modelo de DCLK', f'falta {sdf_path} (set_option -gen_sdf 1)')
    else:
        clocks = clock_summary(tr)
        gen = next((c for c in sdc_cmds if c.startswith('create_generated_clock') and ' -name DCLK ' in c + ' '), None)
        off = re.search(r'-offset\s+([\d.]+)', gen or '')
        offset = float(off.group(1)) if off else None
        base_p = clocks.get('CLK_BASE', (None,))[0]
        dclk = clocks.get('DCLK')
        rel = clock_groups_relation(sdc_cmds, 'CLK_BASE', 'DCLK')
        shape = (gen is not None and offset is not None and dclk is not None and base_p is not None
                 and dclk[2] == 'CLK_BASE' and abs(dclk[0] - 4 * base_p) < 0.01
                 and abs(dclk[1] - offset) < 0.001 and offset < base_p and rel == 'mismo'
                 and (a.dclk_offset is None or abs(a.dclk_offset - offset) < 0.001))
        check(shape, f'forma de DCLK: -offset {offset} en el .sdc, en el .tr periodo {dclk[0] if dclk else "?"} '
              f'(4 x CLK_BASE = {4 * base_p if base_p else "?"}), subida {dclk[1] if dclk else "?"}, '
              f'maestro {dclk[2] if dclk else "?"}, relacion con CLK_BASE en los set_clock_groups: {rel}'
              + ('' if a.dclk_offset is None else f', --dclk-offset {a.dclk_offset}'))
        sdf = read(sdf_path)
        t_sdf = created(sdf, r'//Created Time:(.*)')
        if t_sdf and t_rpt:
            check(abs((t_sdf - t_rpt).total_seconds()) <= 60, f'.sdf de la misma build ({t_sdf})')
        else:
            not_checked('6 misma build', f'sin fecha legible en el .sdf ({t_sdf}) o en el .rpt.txt')
        ff = r'u_main\\/u_v9990\\/dclk_en_ff_1_s0'
        net_clk = sdf_delay(sdf, r'\(INTERCONNECT u_clk\\/u_pll_base/CLKOUT ' + ff + r'/CLK')
        c2q = sdf_delay(sdf, r'\(INSTANCE ' + ff + r'\)\s*\(DELAY\s*\(ABSOLUTE\s*\(IOPATH CLK Q')
        route = sdf_delay(sdf, r'\(INTERCONNECT ' + ff + r'/Q u_main\\/u_v9990\\/Video\\\.DCLK_s/I\d')
        mm = re.search(r'^\s*[\d.]+\s+([\d.]+)\s+tCL\s+RR\s+\d+\s+PLL\S*\s+u_clk/u_pll_base/CLKOUT\s*$', tr, re.M)
        pll = float(mm.group(1)) if mm else None
        # el retardo de la propia OR no sale en el .sdf (Gowin la trata como
        # origen de reloj): se toma el pin de LUT mas rapido del chip
        lut = sdf_fastest_lut(sdf)
        if None in (pll, net_clk, c2q, route, offset) or lut is None:
            check(False, f'offset de DCLK: faltan datos (PLL {pll}, red {net_clk}, tC2Q {c2q}, ruta {route}, LUT {lut}, offset {offset})')
        else:
            real = pll + net_clk + c2q + route + lut[0]
            check(real >= offset,
                  f'offset de DCLK (modelo lento): flanco real >= {real:.3f} ns (PLL {pll:.3f} + red {net_clk:.3f} '
                  f'+ tC2Q {c2q:.3f} + ruta a la OR {route:.3f} + LUT mas rapida del .sdf {lut[0]:.3f}, {lut[1]} {lut[2]}), '
                  f'modelado {offset:.3f} ns, margen {real - offset:+.3f} ns')

    # ---- 5. logs ----
    seen = collections.Counter()
    for path in a.log:
        if not os.path.exists(path):
            check(False, f'falta el log {path}')
            continue
        log = read(path)
        if log.lstrip().startswith('GowinSynthesis start'):
            kind = 'sintesis'
            check(re.search(r'^GowinSynthesis finish', log, re.M) is not None, f'log de sintesis {path} completo')
        elif re.search(r'^Reading netlist file: ', log, re.M):
            kind = 'P&R'
            check(re.search(r'^Placement and routing completed', log, re.M) is not None, f'log de P&R {path} completo')
            dates = [parse_date(l) for l in log.splitlines() if l.strip()]
            dates = [d for d in dates if d]
            check(bool(dates) and t_tr is not None and abs((dates[-1] - t_tr).total_seconds()) <= 120,
                  f'log de P&R de esta build ({dates[-1] if dates else "sin fecha"} / .tr {t_tr})')
        else:
            check(False, f'log no reconocido (ni de sintesis ni de P&R): {path}')
            continue
        seen[kind] += 1
        errs = [l for l in log.splitlines() if re.search(r'\bERROR\b', l)]
        check(not errs, f'errores en el log de {kind}: {len(errs)}' + ''.join('\n         ' + e[:140] for e in errs[:10]))
        codes = collections.Counter(mw.group(1) for mw in re.finditer(r'WARN\s+\((\w+)\)', log))
        info('  avisos (leerlos a mano): ' + (', '.join(f'{k} x{v}' for k, v in sorted(codes.items())) or 'ninguno'))
    for kind in ('sintesis', 'P&R'):
        if not seen[kind]:
            not_checked('5 logs', f'falta el log de {kind}')

    print('\n'.join(lines))
    if missing and not a.parcial:
        print('\nPUERTA: INCOMPLETA (faltan puntos obligatorios: no vale como puerta)')
        return 2
    label = 'PUERTA PARCIAL' if a.parcial else 'PUERTA'
    print(f'\n{label}: ' + ('PASA' if ok else 'FALLA'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
