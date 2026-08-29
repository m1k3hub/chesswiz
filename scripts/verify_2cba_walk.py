#!/usr/bin/env python3
"""End-to-end verification of the .2cba flattening rules.

For every sampled aligned game with twin movetext:
  - walk the PGN with the no-reset (norst) tokenizer
  - check: item X+1 (in document order) == comment's norst position
    (in document order), matched by text
"""
import sys, os, re, json
from collections import Counter

ROWS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/2cba_alignment_200.json"
TWINS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/twin_movetext.json"

SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                    r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?|-{1,2})[+#!?]*$")


def tokenize_norst(mt):
    """Comments in document order: (text, norst_position, depth)."""
    out = []
    cur = 0
    stack = []
    i, n = 0, len(mt)
    while i < n:
        c = mt[i]
        if c.isspace():
            i += 1
            continue
        if c == "{":
            j = mt.find("}", i + 1)
            out.append((mt[i + 1:j].strip(), cur, len(stack)))
            i = j + 1
            continue
        if c == "(":
            stack.append(cur)
            i += 1
            continue
        if c == ")":
            stack.pop() if stack else None  # norst: no restore
            i += 1
            continue
        j = i
        while j < n and not mt[j].isspace() and mt[j] not in "{}()":
            j += 1
        tok = mt[i:j]
        i = j
        if tok.startswith("$"):
            continue
        if tok[0].isdigit() and "." in tok:
            continue
        if SAN_RE.match(tok):
            cur += 1
    return out


twins = json.load(open(TWINS))
rows = json.load(open(ROWS))

stats = Counter()
fails = []
perGame = []
for r in rows:
    if r["status"] != "aligned":
        continue
    key = f"{r['white']}|{r['black']}|{r['date']}"
    mt = twins.get(key)
    if mt is None:
        stats["no_twin_text"] += 1
        continue
    pgnComments = tokenize_norst(mt)
    pgnTexts = [c[0] for c in pgnComments]
    items = r["items"]
    ok = bad = 0
    pi = 0
    for it in items:
        if it["text"] is None:
            continue
        text = it["text"].strip()
        j = pi
        while j < len(pgnTexts) and pgnTexts[j] != text:
            j += 1
        if j >= len(pgnTexts):
            stats["item_no_pgn_comment"] += 1
            fails.append((r["k"], it["X"], text[:40], "not in twin dump"))
            continue
        walkPos = pgnComments[j][1]
        pi = j + 1
        if it["X"] + 1 == walkPos:
            ok += 1
            stats["exact"] += 1
        else:
            bad += 1
            stats["mismatch"] += 1
            fails.append((r["k"], it["X"], text[:40], f"X+1={it['X']+1} pgn={walkPos}"))
    perGame.append((r["k"], ok, bad))

gamesOk = sum(1 for (_, o, b) in perGame if b == 0)
print(f"games fully exact: {gamesOk}/{len(perGame)}")
print(dict(stats))
print(f"{len(fails)} failures")
for f in fails[:20]:
    print("  ", f)