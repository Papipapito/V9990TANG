#!/usr/bin/env python3
# archive_build.py -- guarda la evidencia de una build de Gowin en fpga/reports/
#
# BSD 3-Clause License. Copyright (c) 2026, Papipapito.
#
# Copia a <destino>:
#   - el informe de recursos (<base>.rpt.txt) y el de timing (<base>.tr)
#   - el .sdc que uso la build (<base>.sdc; la ruta sale del .tr), despues de
#     comprobar que el .tr tiene exactamente sus ordenes: si el .sdc se ha
#     editado despues de la build, no archiva
#   - los logs que escribe gw_sh: impl/gwsynthesis/<base>.log -> gwsynthesis.log
#     e impl/pnr/<base>.log -> pnr.log
#   - un extracto del .sdf (<base>.sdf) con lo que usa tools/check_build.py
#     para el modelo de DCLK: el flop que genera Video.DCLK, la celda LUT mas
#     rapida del chip y los dos INTERCONNECT de ese flop, dentro de la celda
#     de diseno original
#   - <base>.fs.txt con las sumas del bitstream y, con --compare, las de otros
#     .fs para comparar sus cuerpos (sin las lineas de cabecera //)
# El .fs no se copia. La salida de la puerta (check_build.txt) se genera
# aparte (ver docs/VERIFICATION.md). Uso (desde la raiz del repositorio):
#   python tools/archive_build.py fpga/impl/pnr/v9990_xtal fpga/reports/hito1 [--compare otro.fs ...]

import argparse
import collections
import hashlib
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_build import created, read, sdc_commands, section, sdf_fastest_lut  # noqa: E402

CELL = re.compile(r'\(CELL\s*\n')


def cell_block(sdf, instance):
    """Bloque (CELL ...) completo de una instancia del .sdf."""
    i = sdf.find('(INSTANCE ' + instance + ')')
    if i < 0:
        raise SystemExit(f'no encuentro {instance} en el .sdf')
    start = [m.start() for m in CELL.finditer(sdf[:i])][-1]
    nxt = CELL.search(sdf, i)
    return '  ' + sdf[start:nxt.start() if nxt else len(sdf)].strip()


def fs_sums(path):
    fs = open(path, 'rb').read()
    body = b''.join(l for l in fs.splitlines(keepends=True) if not l.startswith(b'//'))
    created = re.search(rb'//Created Time: (.*)', fs)
    checksum = re.search(rb'//CheckSum: (\S+)', fs)
    return (created.group(1).decode().strip() if created else '?',
            checksum.group(1).decode() if checksum else '?',
            hashlib.md5(fs).hexdigest(), hashlib.md5(body).hexdigest())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base', help='.../impl/pnr/<output_base_name>')
    ap.add_argument('dest')
    ap.add_argument('--compare', action='append', default=[], help='otro .fs para comparar (repetible)')
    a = ap.parse_args()
    base, dest = a.base, a.dest
    name = os.path.basename(base)
    impl = os.path.dirname(os.path.dirname(base))

    tr = read(base + '.tr')
    m = re.search(r'<Timing Constraints File>:\s*(.*)', tr)
    sdc_path = m.group(1).strip() if m else None
    if not sdc_path or not os.path.exists(sdc_path):
        raise SystemExit(f'no encuentro el .sdc de la build ({sdc_path})')
    rows = re.findall(r'^\s*(TC_\w+)\s+(\w+)\s+(.*?)\s*$', section(tr, '3.8 Timing Constraints Report', None) or '', re.M)
    want = collections.Counter(sdc_commands(read(sdc_path)))
    got = collections.Counter(re.sub(r'\s+', ' ', r[2]) for r in rows)
    if want != got:
        raise SystemExit(f'{sdc_path} ya no es el .sdc de esta build: recompilar antes de archivar')
    t_ref = created(read(base + '.rpt.txt'), r'<Created Time>:(.*)')
    t_fs = created(open(base + '.fs', 'rb').read(4096).decode('latin-1'), r'//Created Time:(.*)')
    if t_ref is None or t_fs is None or abs((t_fs - t_ref).total_seconds()) > 60:
        raise SystemExit(f'{base}.fs no es de esta build ({t_fs} frente a {t_ref}): recompilar antes de archivar')

    os.makedirs(dest, exist_ok=True)
    for ext in ('.rpt.txt', '.tr'):
        shutil.copyfile(base + ext, os.path.join(dest, name + ext))
    shutil.copyfile(sdc_path, os.path.join(dest, name + '.sdc'))
    for sub in ('gwsynthesis', 'pnr'):
        shutil.copyfile(os.path.join(impl, sub, name + '.log'), os.path.join(dest, sub + '.log'))

    sdf = read(base + '.sdf')
    header = sdf[:CELL.search(sdf).start()]
    design = re.search(r'\(DESIGN "([^"]*)"\)', sdf).group(1)
    ff = r'u_main\/u_v9990\/dclk_en_ff_1_s0'
    lines = [l for l in sdf.splitlines()
             if re.search(r'\(INTERCONNECT u_clk\\/u_pll_base/CLKOUT ' + re.escape(ff) + r'/CLK ', l)
             or re.search(r'\(INTERCONNECT ' + re.escape(ff) + r'/Q u_main\\/u_v9990\\/Video\\\.DCLK_s/I\d ', l)]
    lut = sdf_fastest_lut(sdf)
    lut_inst = next(mm.group(1) for mm in re.finditer(r'\(CELLTYPE "LUT[1-4]"\)\s*\(INSTANCE ([^)]*)\)', sdf)
                    if mm.group(1).replace('\\', '') == lut[1])
    out = [header.rstrip(),
           '// EXTRACTO de ' + name + '.sdf hecho por tools/archive_build.py: solo lo que usa',
           '// tools/check_build.py para el modelo de DCLK, sin cambiar ningun valor.',
           cell_block(sdf, ff),
           cell_block(sdf, lut_inst),
           '  (CELL',
           '   (CELLTYPE "' + design + '")',
           '   (INSTANCE )',
           '    (DELAY',
           '     (ABSOLUTE',
           *lines,
           '     )',
           '    )',
           '  )',
           ')', '']
    with open(os.path.join(dest, name + '.sdf'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out))

    c, k, full, body = fs_sums(base + '.fs')
    txt = [f'{name}.fs, build del {c}',
           f'CheckSum: {k}',
           f'md5 del fichero: {full}',
           f'md5 sin las lineas de cabecera (//): {body}']
    for other in a.compare:
        oc, ok_, ofull, obody = fs_sums(other)
        txt.append(f'comparado con {os.path.basename(other)} (build del {oc}, CheckSum {ok_}): cuerpo '
                   + ('IDENTICO' if obody == body else f'DISTINTO (md5 {obody})'))
    with open(os.path.join(dest, name + '.fs.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(txt) + '\n')
    print(f'archivado en {dest}: {", ".join(sorted(os.listdir(dest)))}')


if __name__ == '__main__':
    main()
