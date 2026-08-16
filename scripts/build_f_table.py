#!/usr/bin/env python3
"""Recover the F(lc_prev, lc, ply) function from the redundant H0 table via
majority voting, and measure coverage + determinism.

count_p = H0[count_prev, lc_prev, lc, ply]
F(lc_prev, lc, ply) = (count_p - count_prev) & 0xff  -- deterministic per triple.

The 440K H0 table encodes each (lc_prev,lc,ply) triple ~196x across count_prev.
Wrong table entries (TWIC misalignment noise) vote against the majority. Build F
by taking the majority (or a consensus) F per triple.
"""
import json
from collections import defaultdict, Counter
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
u = json.load(open(REPO/'src/count_cipher_universal.json'))
H0 = u['H0']

Fv = defaultdict(Counter)   # (lc_prev, lc, ply) -> Counter(F values)
for key, val in H0.items():
    cp, lp, lc, ply = (int(x) for x in key.split(','))
    Fv[(lp, lc, ply)][(val - cp) & 0xff] += 1

total = len(Fv)
majority = {}       # triple -> (F, votes, total)
for t, cnt in Fv.items():
    f, votes = cnt.most_common(1)[0]
    majority[t] = (f, votes, sum(cnt.values()))

# determinism: fraction of triples where the top F has >50% and no strong rival
consensus = {t: (f, v, n) for t, (f, v, n) in majority.items() if v * 2 > n}
print(f"total (lc_prev,lc,ply) triples in table: {total}")
print(f"triples with >50% F consensus: {len(consensus)} ({100.0*len(consensus)/max(total,1):.2f}%)")
print(f"non-consensus (noisy) triples: {total - len(consensus)}")

# coverage by ply
from collections import Counter as C2
plycov = C2(int(t[2]) for t in majority)
print("\n(coverage by ply: #triples)")
print("  ply <= 5:", sum(v for k,v in plycov.items() if k<=5))
print("  ply <= 10:", sum(v for k,v in plycov.items() if k<=10))
print("  ply <= 20:", sum(v for k,v in plycov.items() if k<=20))
print("  ply <= 40:", sum(v for k,v in plycov.items() if k<=40))
print("  max ply:", max(plycov))

# F value distribution (is F sparse? small set of values?)
fdist = Counter(f for f,_,_ in majority.values())
print("\nF value distribution (top 15):")
for f, n in fdist.most_common(15):
    print(f"  F={f}: {n} triples")
print(f"  ... total distinct F values: {len(fdist)}")

# write the consensus F table
out = REPO/'src/f_table.json'
json.dump({"F": {f"{a},{b},{p}": f for (a,b,p),(f,v,n) in majority.items()},
           "source": "majority-voted from count_cipher_universal.json"},
          open(out,'w'), indent=1)
print(f"\nwrote F table ({len(majority)} triples) -> {out}")
