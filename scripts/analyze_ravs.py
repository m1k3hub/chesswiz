#!/usr/bin/env python3
"""Compare the Fischer twin's RAV tree with the .2cbg marker/block structure."""
import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from move16_py import decode_move16

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBG = open(os.path.join(BASE, ROOT + ".2cbg"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                    r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?)[+#!?]*$")


def mkName(code):
    d = decode_move16(code)
    if d is None:
        return f"?{code:#x}"
    s = "abcdefgh"[d["from"] >> 3] + "12345678"[d["from"] & 7] \
        + "abcdefgh"[d["to"] >> 3] + "12345678"[d["to"] & 7]
    if d["hasWord1"] and d["piece"] in (6, 14) and d["word1From"] == d["to"] == d["word1To"]:
        s += {2: "q", 3: "n", 4: "b", 5: "r"}.get(d["word1Piece"] & 7, "")
    return s


# ---------------- .2cbg stream --------------
k = 250192
off = int.from_bytes(CBH[(256 + k) * recordSize + 0x08:
                         (256 + k) * recordSize + 0x0c], "little")
ds = int.from_bytes(CBG[off + 8:off + 12], "little")
data = CBG[off + 0x1a:off + 0x1a + ds]
n = len(data) // 2

markerPlies = []
mainline = []
i = 0
while i < n:
    code = int.from_bytes(data[2*i:2*i+2], "little")
    if code == 0xfffc:
        i += 1
        continue
    if code == 0xffff:
        i += 1
        break
    if code == 0xfffd:
        markerPlies.append(len(mainline))
        i += 1
        continue
    if code >= 0xfffb:
        i += 1
        continue
    mainline.append(mkName(code))
    i += 1

blocks = []
cur = []
while i < n:
    code = int.from_bytes(data[2*i:2*i+2], "little")
    i += 1
    if code == 0xffff:
        blocks.append(cur)
        cur = []
        continue
    if code >= 0xfffb:
        continue
    cur.append(code)
if cur:
    blocks.append(cur)

print(f".2cbg: mainline={len(mainline)} moves, markers at plies {markerPlies}")
print(f".2cbg blocks: {len(blocks)} sizes {[len(b) for b in blocks]}")


# ---------------- twin RAV tree --------------
twins = json.load(open("/tmp/twin_movetext.json"))
mt = None
for tk, mtv in twins.items():
    w, b, d = tk.split("|")
    if w == "Fischer, Bobby" and b == "Petrosian, Tigran V":
        mt = mtv
        break


def build(mt2):
    """Token-stream RAV tree builder.

    Returns (mainline_count, ravs) with each rav = dict(
      branch, own, children, parent) in document order.
    """
    i = 0
    cur = 0
    root = dict(branch=-1, own=0, children=[], parent=None)
    stack = [root]
    ravs = []
    while i < len(mt2):
        c = mt2[i]
        if c.isspace():
            i += 1
            continue
        if c == "{":
            i = mt2.find("}", i) + 1
            continue
        if c == "(":
            node = dict(branch=cur, own=0, children=[], parent=stack[-1])
            stack[-1]["children"].append(node)
            ravs.append(node)
            stack.append(node)
            i += 1
            continue
        if c == ")":
            stack.pop()
            i += 1
            continue
        j = i
        while j < len(mt2) and not mt2[j].isspace() and mt2[j] not in '{}()':
            j += 1
        tok = mt2[i:j]
        i = j
        if tok.startswith("$"):
            continue
        if tok[0].isdigit() and "." in tok:
            continue
        if SAN_RE.match(tok):
            cur += 1
            stack[-1]["own"] += 1
    return cur, ravs


total, ravs = build(mt)
print(f"\nPGN: mainline={total}; RAV count={len(ravs)}")
for idx, r in enumerate(ravs):
    kids = [c for c in r["children"]]
    print(f"  RAV{idx:02d} branch_ply={r['branch']:>3} own={r['own']:>2} "
          f"kids={len(kids)}")
print("\nblock sizes:", [len(b) for b in blocks])