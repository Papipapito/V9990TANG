#!/usr/bin/env python3
# ============================================================================
# scan_model.py -- modelo ciclo a ciclo del escaner adaptativo del multiplexor
# de BOARD_REV1_BUS (fpga/src/board/rev1/board_rev1_bus.sv, hito 5): copia de
# su always_comb (grp, ph, ret_pend, ret_grp, force2, nx2) y de la retencion
# de saltos (jhold), para sacar lo que el banco no puede barrer entero:
#
#  1. sin saltos es el escaner de 9 estados de tnCart (periodo 9);
#  2. peor revisita de cada grupo (ciclos entre dos parejas de muestras, como
#     las mide tb_bus.sv) con CUALQUIER secuencia de disparos que respete
#     JUMP_HOLD, por camino mas largo en el grafo de estados; si hay un ciclo
#     sin pareja de un grupo, su revisita no esta acotada;
#  3. peor revisita con un solo salto desde el regimen libre;
#  4. para un disparo en cada uno de los 9 estados: flanco del latch de
#     ff_addr que ve el dispositivo (el ultimo del g2 en un flanco <= E0+8,
#     cuando el RD_n/WR_n retrasado llega a Bus), pareja de muestras de los
#     grupos 0 y 1 que alimenta ese latch, y flanco de la 2a muestra fresca
#     del g2 (la que decide el pre-WAIT).
#
# Convenio de tiempos (igual que el comentario del RTL): el disparo (flanco de
# bajada de RD_n/WR_n filtrados) se ve en el ciclo [E0-1, E0) y el salto se
# aplica en el flanco E0; una muestra "en E" es la que el PIN_FILTER toma en el
# flanco E (ENA a 1 durante [E-1, E)).
#
# Uso: python3 scan_model.py [JUMP_HOLD]      (12 por defecto, el del RTL)
#      python3 scan_model.py --barrido        (peor revisita para 5..20)
#
# V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
# ============================================================================
import itertools
import sys

G0, G1, G2 = 0, 1, 2
RESET = (G0, 1, 0, G0, 0, 0)        # (grp, ph, ret_pend, ret_grp, force2, nx2)


def step(s, trig_ok):
    """Estado siguiente: copia literal del always_comb del RTL."""
    grp, ph, ret_pend, ret_grp, force2, nx2 = s
    grp_n, ph_n = grp, (ph + 1) & 3
    ret_pend_n, ret_grp_n, force2_n, nx2_n = ret_pend, ret_grp, force2, nx2
    if ph == 2:
        ph_n = 0
        if grp == G0:
            if force2:
                grp_n, nx2_n, force2_n = G2, 1, 0
            else:
                grp_n = G1
        elif grp == G1:
            grp_n = G2
        else:
            if ret_pend:
                grp_n = ret_grp
                force2_n = 1 if ret_grp == G0 else 0
                ret_pend_n = 0
            else:
                grp_n = G1 if nx2 else G0
            nx2_n = 0
    if trig_ok:
        if grp == G0 or (grp == G1 and ph != 2):
            grp_n, ph_n, ret_pend_n = G2, 0, 1
            ret_grp_n = G0 if (grp == G0 and ph != 2) else G1
            force2_n, nx2_n = 0, 0
        elif grp == G2 and ph == 2:
            grp_n, ph_n, ret_pend_n, ret_grp_n, force2_n, nx2_n = G2, 2, 1, G0, 0, 0
    return (grp_n, ph_n, ret_pend_n, ret_grp_n, force2_n, nx2_n)


def active(s):
    """Grupo que muestrea el PIN_FILTER en el flanco que cierra este ciclo."""
    return s[0] if s[1] != 0 else None


def reachable(jump_hold):
    """Estados (escaner, jhold) alcanzables desde el reset."""
    def succ(es):
        s, h = es
        out = [(step(s, False), max(h - 1, 0))]
        if h == 0:
            out.append((step(s, True), jump_hold))
        return out
    seen = {(RESET, 0)}
    todo = [(RESET, 0)]
    while todo:
        es = todo.pop()
        for e2 in succ(es):
            if e2 not in seen:
                seen.add(e2)
                todo.append(e2)
    return seen, succ


def worst_revisit(jump_hold, g):
    """Maximo de ciclos entre dos parejas del grupo g (None = no acotada)."""
    seen, succ = reachable(jump_hold)
    def is_pair(e):
        return e[0][0] == g and e[0][1] == 2
    memo, onstack = {}, set()
    sys.setrecursionlimit(100000)
    def lp(e):
        if is_pair(e):
            return 0
        if e in memo:
            return memo[e]
        if e in onstack:
            raise ValueError
        onstack.add(e)
        best = max(1 + lp(n) for n in succ(e))
        onstack.discard(e)
        memo[e] = best
        return best
    try:
        return max(1 + lp(n) for e in seen if is_pair(e) for n in succ(e))
    except ValueError:
        return None


def free_running(n):
    s = RESET
    for _ in range(n):
        s = step(s, False)
    return s


def single_jump_revisit():
    """Peor revisita con un solo salto desde el regimen libre (9 fases)."""
    worst = {G0: 0, G1: 0, G2: 0}
    for phase in range(9):
        s = free_running(36 + phase)
        last = {G0: None, G1: None, G2: None}
        for c in range(60):
            if s[1] == 2:
                gg = s[0]
                if last[gg] is not None:
                    worst[gg] = max(worst[gg], c - last[gg])
                last[gg] = c
            s = step(s, c == 20)
    return worst


def witness(jump_hold, g, horizon=40, max_jumps=3):
    """Secuencia de disparos (separados > jump_hold) que da la peor revisita de g."""
    s0 = free_running(36)
    best = (0, None)
    for k in range(1, max_jumps + 1):
        for combo in itertools.combinations(range(horizon), k):
            if any(b - a <= jump_hold for a, b in zip(combo, combo[1:])):
                continue
            s, last, w, tr = s0, None, 0, []
            for c in range(horizon + 30):
                if s[1] == 2 and s[0] == g:
                    if last is not None:
                        w = max(w, c - last)
                    last = c
                t = c in combo
                if t:
                    tr.append("c%d en g%d f%d" % (c, s[0], s[1]))
                s = step(s, t)
            if w > best[0]:
                best = (w, tr)
    return best


def trigger_table():
    """Latch de ff_addr y parejas de los grupos 0/1 para un disparo en cada estado."""
    rows = []
    order = [(G0, 0), (G0, 1), (G0, 2), (G1, 0), (G1, 1), (G1, 2), (G2, 0), (G2, 1), (G2, 2)]
    num = {(G0, 1): 0, (G0, 2): 1, (G1, 0): 2, (G1, 1): 3, (G1, 2): 4,
           (G2, 0): 5, (G2, 1): 6, (G2, 2): 7, (G0, 0): 8}
    for g, ph in order:
        s = free_running(90)
        while (s[0], s[1]) != (g, ph):
            s = step(s, False)
        # s es el estado durante [E0-1, E0). El regimen libre tiene periodo 9, asi
        # que el estado durante [E0-28, E0-27) es el mismo: se simula desde ahi
        samples = {G0: [], G1: [], G2: []}
        t = -28
        cur = s
        while t < 20:
            a = active(cur)
            if a is not None:
                samples[a].append(t + 1)
            cur = step(cur, t == -1)
            t += 1
        latch = max(e for e in samples[G2] if e <= 8)
        def pair(gg):
            ss = [e for e in samples[gg] if e <= latch - 1]
            return ss[-2], ss[-1]
        fresh = [e for e in samples[G2] if e >= 0][1]
        rows.append(((g, ph), num[(g, ph)], latch, pair(G0), pair(G1), fresh))
    return rows


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--barrido":
        print("JUMP_HOLD  peor revisita g0 / g1 / g2 (ciclos; '-' = no acotada)")
        for h in range(5, 21):
            r = [worst_revisit(h, g) for g in (G0, G1, G2)]
            print("%9d  %s" % (h, " / ".join("-" if x is None else str(x) for x in r)))
        return
    jh = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    s = RESET
    seq = []
    for _ in range(9):
        seq.append("g%df%d" % (s[0], s[1]))
        s = step(s, False)
    print("sin saltos (estados 0..8 de tnCart):", " ".join(seq))
    assert free_running(9) == RESET, "sin saltos el periodo no es 9"
    sj = single_jump_revisit()
    print("un salto aislado: peor revisita g0 %d, g1 %d, g2 %d ciclos" % (sj[G0], sj[G1], sj[G2]))
    print("JUMP_HOLD = %d, saltos encadenados cualesquiera (uno cada %d ciclos como mucho):" % (jh, jh + 1))
    for g in (G0, G1, G2):
        w = worst_revisit(jh, g)
        if w is None:
            print("  g%d: revisita NO acotada" % g)
        else:
            wt = witness(jh, g)
            print("  g%d: %d ciclos (p. ej. disparos %s)" % (g, w, ", ".join(wt[1]) if wt[1] else "-"))
    print()
    print("disparo en (estado)  latch de ff_addr  pareja g0 (A15-A8)  pareja g1 (A7-A0)  2a muestra fresca del g2")
    for (g, ph), n, latch, p0, p1, fr in trigger_table():
        print("g%d f%d (%d)            E0%+d              E0%+d / E0%+d         E0%+d / E0%+d        E0%+d"
              % (g, ph, n, latch, p0[0], p0[1], p1[0], p1[1], fr))


if __name__ == "__main__":
    main()
