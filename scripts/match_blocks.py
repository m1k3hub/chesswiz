#!/usr/bin/env python3
"""Match .2cbg variation blocks to markers/RAVs by move content.

For each block: replay the mainline to each marker ply, then try playing the
block's decoded moves; the root where the whole block replays legally AND the
mainline continuation after the block would be legal confirms the pairing.
Cross-check against the PGN twin's RAV move list.
"""
import sys, os, re, json
import chess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from move16_py import decode_move16

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBG = open(os.path.join(BASE, ROOT + ".2cbg"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                    r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?)[+#!?]*$")


def mkMove(d):
    """Build a python-chess Move from a Move16 descriptor (standard chess),
    handling castling via the king-double-step convention.
    m16 square = file*8 + rank  ->  file = sq>>3, rank = sq&7."""
    frm = chess.square(d["from"] >> 3, d["from"] & 7)
    to = chess.square(d["to"] >> 3, d["to"] & 7)
    if d["hasWord1"] and d["piece"] in (6, 14) and d["word1From"] == d["to"] == d["word1To"]:
        return chess.Move(frm, to, promotion={2: chess.QUEEN, 3: chess.KNIGHT,
                                              4: chess.BISHOP, 5: chess.ROOK}[d["word1Piece"] & 7])
    return chess.Move(frm, to)


def play(board, uci_list):
    b = board.copy(stack=False)
    for m in uci_list:
        if m not in b.legal_moves:
            return None
        b.push(m)
    return b


k = 250192
off = int.from_bytes(CBH[(256 + k) * recordSize + 0x08:
                         (256 + k) * recordSize + 0x0c], "little")
ds = int.from_bytes(CBG[off + 8:off + 12], "little")
data = CBG[off + 0x1a:off + 0x1a + ds]
n = len(data) // 2

markerPlies = []
mainline = []       # list of (from,to,promo)
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
    d = decode_move16(code)
    mainline.append(d)
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

# replay mainline to get board at each ply
board = chess.Board()
mainUci = []
for d in mainline:
    m = mkMove(d)
    if m not in board.legal_moves:
        print("BAD mainline move at ply", len(mainUci))
        break
    mainUci.append(m)
    board.push(m)

print(f"mainline={len(mainUci)} moves replay OK; markers at plies {markerPlies}")

# boards at marker positions
boards = {}
b0 = chess.Board()
step = []
for idx, m in enumerate(mainUci):
    step.append(b0.copy(stack=False))
    b0.push(m)
for mp in markerPlies:
    boards[mp] = b0.copy(stack=False)  # final board; need ply-specific
# rebuild properly
brd = chess.Board()
for idx, m in enumerate(mainUci):
    pass
# simpler rebuild loop:
brd = chess.Board()
snap = [chess.Board()]
for m in mainUci:
    brd.push(m)
    snap.append(brd.copy(stack=False))
boards = {mp: snap[mp] for mp in markerPlies}

blockNames = []
for bi, blk in enumerate(blocks):
    ds_ = []
    for code in blk:
        d = decode_move16(code)
        ds_.append(d)
    names = []
    b0 = boards[markerPlies[0]]
    for mp in markerPlies:
        b_ = boards[mp].copy(stack=False)
        ok = True
        for d in ds_:
            mv = mkMove(d)
            if mv is None or mv not in b_.legal_moves:
                ok = False
                break
            b_.push(mv)
        if ok:
            names.append(mp)
    blockNames.append(names)
    print(f"block {bi}: {len(blk)} moves, legal at marker plies {names}")

# PGN twin RAV first moves as UCI from their roots
twins = json.load(open("/tmp/twin_movetext.json"))
mt = None
for tk, mtv in twins.items():
    w, b, d = tk.split("|")
    if w == "Fischer, Bobby" and b == "Petrosian, Tigran V":
        mt = mtv
        break

# Extract each RAV's raw SAN sequence by walking the PGN with a token stream
# that records tokens per RAV with the branch board.
def extractRavs(s):
    i = 0
    cur = 0
    stack = []
    ravs = []           # (branch_ply_in_parent_walk_context, [SAN...])
    openRavs = []
    while i < len(s):
        c = s[i]
        if c.isspace():
            i += 1
            continue
        if c == "{":
            i = s.find("}", i) + 1
            continue
        if c == "(":
            openRavs.append(dict(branch=cur, sans=[]))
            stack.append("rav")
            i += 1
            continue
        if c == ")":
            stack.pop()
            r = openRavs.pop()
            ravs.append(r)
            i += 1
            continue
        j = i
        while j < len(s) and not s[j].isspace() and s[j] not in '{}()':
            j += 1
        tok = s[i:j]
        i = j
        if tok.startswith("$"):
            continue
        if tok[0].isdigit() and "." in tok:
            continue
        if SAN_RE.match(tok):
            cur += 1
            if openRavs:
                openRavs[-1]["sans"].append(tok)
    return ravs


ravs = extractRavs(mt)
print("\nPGN RAVs (branch-in-walk, first SAN):",
      [(r["branch"], r["sans"][0] + "..." + (r["sans"][-1] if r["sans"] else "")) for r in ravs])