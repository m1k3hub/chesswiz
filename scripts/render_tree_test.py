#!/usr/bin/env python3
"""Decisive test: child-content placement inside RAV emission.

Renders the Fischer game's tree under both conventions and diffs the
token stream against the twin's movetext.
"""
import sys, os, re, json
import chess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from move16_py import decode_move16
from pgn_ground_truth import parse_items_at

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBG = open(os.path.join(BASE, ROOT + ".2cbg"), "rb").read()
CBA = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")


def buildTree(region):
    idx = 0

    def parseSubtree():
        nonlocal idx
        node = {"own": [], "markers": [], "kids": []}
        while idx < len(region) and region[idx] != 0xffff:
            code = region[idx]
            if code == 0xfffd:
                node["markers"].append(len(node["own"]))
                idx += 1
            elif code >= 0xfffb:
                idx += 1
            else:
                node["own"].append(code)
                idx += 1
        idx += 1  # consume E
        kidsStor = []
        for _ in range(len(node["markers"])):
            kidsStor.append(parseSubtree())
        node["kids"] = list(reversed(kidsStor))   # doc order
        return node

    rootsStor = []
    while idx < len(region):
        rootsStor.append(parseSubtree())
    return list(reversed(rootsStor))


def buildTree(CBG, off):
    ds = int.from_bytes(CBG[off + 8:off + 12], "little")
    data = CBG[off + 0x1a:off + 0x1a + ds]
    n = len(data) // 2
    toks = [int.from_bytes(data[2*i:2*i+2], "little") for i in range(n)]
    mainline, rootMarkers = [], []
    i = 0
    while i < n:
        code = toks[i]
        if code == 0xfffc:
            i += 1
            continue
        if code == 0xffff:
            i += 1
            break
        if code == 0xfffd:
            rootMarkers.append(len(mainline))
            i += 1
            continue
        if code >= 0xfffb:
            i += 1
            continue
        mainline.append(code)
        i += 1
    sys.setrecursionlimit(100000)
    return mainline, rootMarkers, buildTreeRegion(toks[i:])


def buildTreeRegion(region):
    idx = 0

    def parseSubtree():
        nonlocal idx
        node = {"own": [], "markers": [], "kids": []}
        while idx < len(region) and region[idx] != 0xffff:
            code = region[idx]
            if code == 0xfffd:
                node["markers"].append(len(node["own"]))
                idx += 1
            elif code >= 0xfffb:
                idx += 1
            else:
                node["own"].append(code)
                idx += 1
        idx += 1
        kidsStor = []
        for _ in range(len(node["markers"])):
            kidsStor.append(parseSubtree())
        node["kids"] = list(reversed(kidsStor))
        return node

    rootsStor = []
    while idx < len(region):
        rootsStor.append(parseSubtree())
    return list(reversed(rootsStor))


def moveFromCode(code, board):
    d = decode_move16(code)
    frm = chess.square(d["from"] >> 3, d["from"] & 7)
    to = chess.square(d["to"] >> 3, d["to"] & 7)
    if d["hasWord1"] and d["piece"] in (6, 14) and d["word1From"] == d["to"] == d["word1To"]:
        return chess.Move(frm, to, promotion={2: chess.QUEEN, 3: chess.KNIGHT,
                                              4: chess.BISHOP, 5: chess.ROOK}[d["word1Piece"] & 7])
    return chess.Move(frm, to)


class Renderer:
    def __init__(self, mainline, rootMarkers, rootsDoc, items):
        self.mainline = mainline
        self.roots = sorted(zip(rootMarkers, rootsDoc))  # doc order
        self.dbgRendered = 0
        self.items = items
        self.board = chess.Board()
        self.tokens = []
        self.flat = 0
        self.ii = 0

    def emitMove(self, code):
        board = self.board
        self.flat += 1
        mv = moveFromCode(code, board)
        try:
            san = board.san(mv)
        except AssertionError:
            san = "ILLEGAL:" + mv.uci() + "/" + board.fen()[:40]
        if (self.flat % 2) == 1:
            self.tokens.append(f"{(self.flat + 1) // 2}.")
        self.tokens.append(san)
        board.push(mv)
        while self.ii < len(self.items) and self.items[self.ii]["X"] + 1 == self.flat:
            item = self.items[self.ii]
            self.ii += 1
            self.tokens.append("{" + (item["text"] or "").strip() + "}")

    def emitNode(self, node):
        own = node["own"]
        kids = sorted(zip(node["markers"], node["kids"]))
        
        vi = 0
        for offset, kid in kids:
            pre = self.board.copy(stack=False)   # board BEFORE own[offset]
            while vi <= offset:
                self.emitMove(own[vi])
                vi += 1
            # child content: textually after the replaced move's SAN, but it
            # replays from the position BEFORE that move
            self.tokens.append("( ")
            self.board = pre
            self.emitNode(kid)
            self.tokens.append(") ")
            self.board = saved

    def run(self, mode="after"):
        self.mode = mode
        vi = 0
        ki = 0
        dbg = 0
        # root RAVs render after the SAN of their replaced mainline move;
        # their content replays from the position BEFORE that move.
        roots = self.roots
        while vi < len(self.mainline):
            pre = self.board.copy(stack=False)   # pre-move snapshot
            self.emitMove(self.mainline[vi])
            while ki < len(roots) and self.roots[ki][0] - 1 == vi:
                _, rnode = self.roots[ki]
                saved = self.board
                self.board = pre                    # child replays pre-move
                self.tokens.append("( ")
                self.emitNode(rnode)
                self.tokens.append(") ")
                self.board = saved
                ki += 1
                self.dbgRendered += 1
            vi += 1


def main():
    k = 250192
    off = int.from_bytes(CBH[(256 + k) * recordSize + 0x08:
                             (256 + k) * recordSize + 0x0c], "little")
    mainline, rootMarkers, rootsDoc = buildTree(CBG, off)
    cbaOff = int.from_bytes(CBH[(256 + k) * recordSize + 0x10:
                                (256 + k) * recordSize + 0x14], "little")
    ds = int.from_bytes(CBA[cbaOff + 8:cbaOff + 12], "little")
    items, complete = parse_items_at(CBA, cbaOff, ds)

    twins = json.load(open("/tmp/twin_movetext.json"))
    twinMt = twins["Fischer, Bobby|Petrosian, Tigran V|1971.10.19"]

    for mode in ("after",):
        r = Renderer(mainline, rootMarkers, rootsDoc, items)
        try:
            r.run(mode)
        except AssertionError as e:
            print(f"=== mode={mode}: FAILED mid-render: {e}")
            continue
        rendered = " ".join(r.tokens)
        print(f"=== mode={mode}: RENDERED {r.dbgRendered} rav groups; walk={r.flat} tokens={len(r.tokens)}")
        norm = re.sub(r"\s+", " ", rendered).strip()
        # score against the twin: longest common prefix ratio + comment positions
        twin_norm = re.sub(r"\s+", " ", twinMt).strip()
        # strip move numbers for a comparable stream
        mine = [t for t in norm.split(" ") if t]
        twin_toks = [t for t in twin_norm.split(" ") if t]
        same = sum(1 for a, b in zip(mine, []) )
        # exact prefix length
        pl = 0
        for a, b in zip(mine, twin_norm.split(" ")):
            if a != b:
                break
            pl += 1
        tw = len(twin_norm.split(" "))
        print(f"   common-prefix tokens: {pl} of twin {tw}")
        # show first mismatch
        tt = twin_norm.split(" ")
        if pl < min(len(mine), len(tt)):
            print("   first mismatch:")
            print("    ours:", " ".join(mine[max(0, pl-4):pl+6]))
            print("    twin:", " ".join(tt[max(0, pl):pl+6]))


main()