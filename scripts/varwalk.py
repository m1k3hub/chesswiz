#!/usr/bin/env python3
"""Variation-walk reconstruction for the .2cbg record (.2cba alignment).

Model (flat part validated at 81/81 items over 43 twin games; nested-RAV
support is partial — see docs/formats/2CBH_FORMAT_DESIGN.md section 4.2):

  - mainline: [0xfffc] moves [0xffff]; 0xfffd markers inside the mainline
  - the post-mainline region stores the variation blocks in REVERSE doc
    order; a marker value M = the 1-based mainline ply the variation
    replaces; the variation's block replays legally from snap[M-1]
  - the flattened walk (PGN "norst") counts every move of the game tree
    in document order, never reset; a .2cba comment at X attaches AFTER
    the (X+1)-th move of the flattened walk

Limitation: games where a variation carries its own nested variations
(internal 0xfffd markers inside a block) or several sibling RAVs at one
marker partially break the 1:1 pairing — those games report
reconstruct failure rather than a wrong answer.
"""
from collections import defaultdict
import chess
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from move16_py import decode_move16


def mkMove(d):
    frm = chess.square(d["from"] >> 3, d["from"] & 7)
    to = chess.square(d["to"] >> 3, d["to"] & 7)
    if d["hasWord1"] and d["piece"] in (6, 14) and d["word1From"] == d["to"] == d["word1To"]:
        return chess.Move(frm, to, promotion={2: chess.QUEEN, 3: chess.KNIGHT,
                                              4: chess.BISHOP, 5: chess.ROOK}[d["word1Piece"] & 7])
    return chess.Move(frm, to)


def parseCBG(CBG, off):
    """-> (mainline [codes], rootMarkers [0-based ply], fileBlocks [[codes]])

    rootMarkers as stored (1-based); each is the mainline ply replaced by
    the corresponding root variation.
    """
    ds = int.from_bytes(CBG[off + 8:off + 12], "little")
    data = CBG[off + 0x1a:off + 0x1a + ds]
    n = len(data) // 2
    markers, mainline = [], []
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
            markers.append(len(mainline))
            i += 1
            continue
        if code >= 0xfffb:
            i += 1
            continue
        mainline.append(code)
        i += 1
    blocks, cur = [], []
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
    return mainline, markers, blocks


def reconstruct(mainline, markers, fileBlocks):
    """Simulate the flattened walk (flat/sibling model).

    Returns (plyPos, varPos, ml, varTotal):
      plyPos: {mainline_ply: walk position after it}
      varPos: {(doc_block_index, offset_in_block): walk position after it}
    """
    board = chess.Board()
    snaps = [chess.Board()]
    for code in mainline:
        d = decode_move16(code)
        mv = mkMove(d)
        if mv is None or mv not in board.legal_moves:
            return None
        board.push(mv)
        snaps.append(board.copy(stack=False))
    ml = len(snaps) - 1

    docBlocks = list(reversed(fileBlocks))
    if len(docBlocks) < len(markers):
        return None

    # monotone greedy pairing with sibling support: markers in mainline
    # order, doc blocks in doc order; a marker may host several sibling
    # RAVs.  Content check: each block must replay legally from its root
    # snaps[M-1] (the position before the replaced mainline move).
    pairRoots = []
    mi = 0
    for bi_, blk in enumerate(docBlocks):
        placed = False
        while mi < len(markers):
            M = markers[mi]
            if M < 1 or M > ml:
                return None
            b = snaps[M - 1].copy(stack=False)
            ok = True
            for code in blk:
                d = decode_move16(code)
                mv = mkMove(d)
                if mv is None or mv not in b.legal_moves:
                    ok = False
                    break
                b.push(mv)
            if ok:
                pairRoots.append(M)
                placed = True
                break          # the next block may share this marker
            mi += 1
            if mi == len(markers):
                return None
        if not placed:
            return None

    # flattened walk: block i_ walks between mainline plies M-1 and M
    byAfterPly = defaultdict(list)
    for i_, blk in enumerate(docBlocks):
        byAfterPly[pairRoots[i_] - 1].append((i_, blk))

    plyPos = {0: 0}
    varPos = {}
    cum = 0
    for t in range(0, ml + 1):
        if t >= 1:
            plyPos[t] = t + cum       # mainline ply t, before its variations
        for (di_, blk) in byAfterPly.get(t, []):
            for v in range(1, len(blk) + 1):
                varPos[(di_, v)] = cum + t + v
            cum += len(blk)
    return plyPos, varPos, ml, cum


def decodePosition(X, plyPos, varPos, total):
    """X = flattened position; the comment sits after walk move X+1.

    Returns ("ply", walkPos, mainlinePly) | ("var", walkPos, (docIdx, off))
    | None.  Lookups are VALUE-based (walk positions shift with prior
    blocks and must not be confused with ply numbers).
    """
    t = X + 1
    plyByVal = {v: k for k, v in plyPos.items()}
    if t in plyByVal:
        return ("ply", t, plyByVal[t])
    byVal = {vv: k for k, vv in varPos.items()}
    if t in byVal:
        di_, off = byVal[t]
        return ("var", t, (di_, off))
    return None

# ----------------------------------------------------------------------
# Nested tree model — section 4.2.1 grammar
# ----------------------------------------------------------------------

def parseSubtreeTokens(region, idx):
    """One storage node + its claimed child subtrees (recursive).

    Returns (node, nextIdx); node = dict(own, markers, kidsDoc):
      own     = the node's own move codes in walk order
      markers = 0-based own indices at which the child variations sit
      kidsDoc = child subtrees in DOC order
    """
    node = dict(own=[], markers=[], kids=None)
    while idx < len(region) and region[idx] != 0xffff:
        code = region[idx]
        if code == 0xfffd:
            node["markers"].append(len(node["own"]))   # own moves BEFORE = insert index
            idx += 1
        elif code >= 0xfffb:
            idx += 1
        else:
            node["own"].append(code)
            idx += 1
    idx += 1  # consume this node's E
    kidsStor = []
    for _ in range(len(node["markers"])):   # children appear in REVERSE doc order
        kid, idx = parseSubtreeTokens(region, idx)
        kidsStor.append(kid)
    node["kids"] = list(reversed(kidsStor))  # -> doc order
    return node, idx


def buildTreeModel(CBG, off):
    """-> (mainline, rootInsert, rootsDoc, region).

    rootInsert[j] = the 0-based mainline index replaced by rootsDoc[j]'s
    first move (= marker ply M minus 1, from the mainline markers).
    """
    mainline, markers, blocks = parseCBG(CBG, off)   # markers as stored (1-based)
    ds = int.from_bytes(CBG[off + 8:off + 12], "little")
    data = CBG[off + 0x1a:off + 0x1a + ds]
    n = len(data) // 2
    toks = [int.from_bytes(data[2*i:2*i+2], "little") for i in range(n)]
    idx0 = 0
    while idx0 < n and toks[idx0] != 0xffff:
        idx0 += 1
    region = toks[idx0 + 1:]
    rootsStor = []
    idx = 0
    while idx < len(region):
        node, idx = parseSubtreeTokens(region, idx)
        rootsStor.append(node)
    rootsDoc = list(reversed(rootsStor))     # doc order = marker-ascending
    rootInsert = [m - 1 for m in markers] if markers else []
    return mainline, rootInsert, rootsDoc, region


def flattenTree(mainline, rootInsert, rootsDoc):
    """Flattened (norst) walk of the tree.

    Returns walk: dict(1-based walk position -> ('main', ply0) |
    ('rav', (parentPath, ki), ownIdx)).  Uniform marker semantics: the
    child's content walks BEFORE the own move at its marker index (it
    replaces that move); root markers are pre-converted 0-based.
    """
    walkMap = {}
    state = dict(pos=0, walk=walkMap)

    def walkRec(own, markers, kids, rav):
        vi = 0
        ki = 0
        n = len(own)
        while vi < n or ki < len(kids):
            if ki < len(kids) and markers[ki] == vi:
                walkRec(kids[ki]["own"], kids[ki]["markers"], kids[ki]["kids"],
                        (rav, ki))
                ki += 1
                continue
            if vi < n:
                state["pos"] += 1
                ref = ("main", vi) if rav is None else ("rav", rav, vi)
                walkMap[state["pos"]] = ref
                vi += 1
            else:
                break

    # root: marker insert indices already 0-based (M-1)
    vi = 0
    ki = 0
    n = len(mainline)
    while vi < n or ki < len(rootsDoc):
        if ki < len(rootsDoc) and rootInsert[ki] == vi:
            walkRec(rootsDoc[ki]["own"], rootsDoc[ki]["markers"],
                    rootsDoc[ki]["kids"], ki)
            ki += 1
            continue
        if vi < n:
            state["pos"] += 1
            walkMap[state["pos"]] = ("main", vi)
            vi += 1
        else:
            break
    return walkMap, state["pos"]
