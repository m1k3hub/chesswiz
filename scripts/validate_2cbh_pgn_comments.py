#!/usr/bin/env python3
"""Validate 2cbh2pgn's emitted comments against the ChessBase PGN twin.

Per identity: build ply -> set(norm-text) maps for our export and the twin,
then report per-ply symmetric differences.  Tolerates the twin's splitting
of compound markup comments ([%eval]/Inaccuracy) which ChessBase stores as
one .2cba text.
"""
import sys, os, re, json
from collections import Counter, defaultdict

OURS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/2cba_test/full_with_comments.pgn"
TWINS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/twin_movetext.json"

SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                    r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?|-{1,2})[+#!?]*$")


def tokenize(mt):
    """restore-mode comments: (text, ply_after (1-based move they follow))."""
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
            if stack:
                cur = stack.pop()
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


def norm(t):
    return re.sub(r"\s+", " ", t.replace("(", "").replace(")", "").replace("[", "")
                  .replace("]", "").replace("{", "").replace("}", "")).strip().lower()


def toMap(comments):
    m = defaultdict(set)
    for t, p, d in comments:
        if d != 0:
            continue  # compare mainline comments only
        m[p].add(norm(t))
    return m


twins = json.load(open(TWINS))

# parse our PGN once
ours = {}
tags = {}
mtbuf = []
in_moves = False
tagRe = re.compile(r'\[(\w+) "(.*)"\]')


def finalize():
    global tags, mtbuf, in_moves
    if "White" in tags and "Date" in tags and mtbuf:
        mt = " ".join(mtbuf)
        key = (tags.get("White", ""), tags.get("Black", ""), tags.get("Date", ""))
        c = tokenize(mt)
        if c:
            ours.setdefault(key, []).append(toMap(c))
    tags = {}
    mtbuf = []
    in_moves = False


for raw in open(OURS, "rb"):
    s = raw.rstrip(b"\r\n").strip()
    if not s:
        if in_moves:
            finalize()
        continue
    if s.startswith(b"[") and s.endswith(b"]"):
        m = tagRe.match(s.decode("latin1"))
        if m:
            tags[m.group(1)] = m.group(2)
        continue
    mtbuf.append(s.decode("latin1"))
    in_moves = True
if in_moves:
    finalize()

stats = Counter()
examples = []
nGamesCompared = 0
for tk, twinMt in twins.items():
    w, b, d = tk.split("|")
    key = (w, b, d)
    if key not in ours:
        stats["no_our_export"] += 1
        continue
    twinM = toMap(tokenize(twinMt))
    ourM = ours[key][0]
    nGamesCompared += 1
    plies = set(twinM) | set(ourM)
    for p in plies:
        tset = twinM.get(p, set())
        oset = ourM.get(p, set())
        for t in tset - oset:
            stats["twin_only"] += 1
            examples.append((tk[:28], "twin_only", p, t[:50]))
        for t in oset - tset:
            stats["ours_only"] += 1
            examples.append((tk[:28], "ours_only", p, t[:50]))
        if tset & oset:
            stats["ply_equal"] += 1

print("twins:", len(twins), "compared games:", nGamesCompared)
print(dict(stats))
for e in examples[:16]:
    print("  ", e)