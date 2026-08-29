#!/usr/bin/env python3
"""Scan the PGN twin for needle comments and record each hit's PGN context.

Streaming single pass over the PGN.  For every game whose movetext contains
a needle text (taken from the .2cba sample), record per comment:
  (text, ply_before, depth) plus the game's identity tags and mainline length.

Writes a JSON file: text -> [ {white, black, date, mainline, ply, depth}, ...]
"""
import sys, os, re, json, time

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
HITS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pgn_needle_hits.json"
NEEDLES_FILE = sys.argv[3] if len(sys.argv) > 3 else None

SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                    r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?|-{1,2})[+#!?]*$")


def tokenize_comments(movetext):
    """RAV-aware tokenizer.  Returns (mainline_moves, [(text, ply_before, depth)])."""
    comments = []
    stack = []
    cur = 0
    i, n = 0, len(movetext)
    while i < n:
        c = movetext[i]
        if c.isspace():
            i += 1
            continue
        if c == "{":
            j = movetext.find("}", i + 1)
            if j < 0:
                j = n
            comments.append((movetext[i + 1:j].strip(), cur, len(stack)))
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
        if c == ";":
            j = movetext.find("\n", i + 1)
            i = j + 1 if j >= 0 else n
            continue
        j = i
        while j < n and not movetext[j].isspace() and movetext[j] not in "{}()":
            j += 1
        tok = movetext[i:j]
        i = j
        if tok.startswith("$"):
            continue
        if tok[0].isdigit() and "." in tok:
            continue  # move number
        if SAN_RE.match(tok):
            cur += 1
    return cur, comments


def parse_items_at(CBA, off, ds):
    """Strict item walker handling the three header formats:
        A: [u32 X][u32 2][u16 3][u16 ch][u8 0][u32 2][u16 type][u32 len]  (23B)
        B: [u32 X][u32 1][u32 2][u16 type][u32 len]                        (18B)
        C: [u32 X][u32 2][u32 2][u16 type][u32 len]                        (18B)
    Returns (items, complete).  Items: dict(X, ch, type, text)."""
    dataEnd = off + 0x1a + ds
    p = off + 0x1a
    items = []
    while True:
        if p + 4 <= dataEnd and (CBA[p:p + 4] == b"\xff\xff\xff\x7f"
                                 or CBA[p:p + 2] == b"\xff\xff"):
            return items, True
        if p + 18 > dataEnd:
            return items, False
        X = int.from_bytes(CBA[p:p + 4], "little")
        kind = int.from_bytes(CBA[p + 4:p + 8], "little")
        if kind == 2 and int.from_bytes(CBA[p + 8:p + 10], "little") == 3:
            if p + 23 > dataEnd:
                return items, False
            ch = int.from_bytes(CBA[p + 10:p + 12], "little")
            z = CBA[p + 12]
            mid3 = int.from_bytes(CBA[p + 13:p + 17], "little")
            itype = int.from_bytes(CBA[p + 17:p + 19], "little")
            ln = int.from_bytes(CBA[p + 19:p + 23], "little")
            body = p + 23
            if z != 0 or mid3 != 2 or itype != 7 or body + ln > dataEnd:
                return items, False
        elif kind in (1, 2):
            mid = int.from_bytes(CBA[p + 8:p + 12], "little")
            itype = int.from_bytes(CBA[p + 12:p + 14], "little")
            ln = int.from_bytes(CBA[p + 14:p + 18], "little")
            ch, z = 0, 0
            body = p + 18
            if mid != 2 or itype != 7 or body + ln > dataEnd:
                return items, False
        else:
            return items, False
        payload = CBA[body:body + ln]
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            text = None
        items.append(dict(X=X, ch=ch, itype=itype, len=ln, text=text))
        p = body + ln


def extract_needles(limit=4000):
    CBA = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
    CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
    recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
    N = len(CBH) // recordSize - 256
    needles = set()
    ok = bad = 0
    for k in range(0, N, 16):
        off = int.from_bytes(CBH[(256 + k) * recordSize + 0x10:
                                 (256 + k) * recordSize + 0x14], "little")
        ds = int.from_bytes(CBA[off + 8:off + 12], "little")
        if ds <= 8:
            continue
        items, complete = parse_items_at(CBA, off, ds)
        if complete:
            ok += 1
            for it in items:
                if it["text"]:
                    needles.add(it["text"])
        else:
            bad += 1
    print(f"records ok={ok} bad={bad} needles={len(needles)}", flush=True)
    return sorted(needles)[:limit]


def main():
    if NEEDLES_FILE:
        needles = [l.strip() for l in open(NEEDLES_FILE, encoding="utf-8") if l.strip()]
    else:
        needles = extract_needles()
    print(f"{len(needles)} needles", flush=True)
    needleRe = re.compile(b"|".join(re.escape(n.encode("utf-8")) for n in needles))

    hits = {}
    tags = {}
    movetext_lines = []
    in_moves = False
    ngames = 0
    hitgames = 0
    t0 = time.time()

    def finalize():
        nonlocal tags, movetext_lines, in_moves, ngames, hitgames
        mt = b" ".join(movetext_lines)
        ngames += 1
        if (mt and needleRe.search(mt)
                and "White" in tags and "Date" in tags):
            s = mt.decode("latin1")
            mainline, comments = tokenize_comments(s)
            w = tags.get("White", "")
            b = tags.get("Black", "")
            d = tags.get("Date", "")
            hitgames += 1
            for text, ply, depth in comments:
                hits.setdefault(text, []).append(
                    dict(white=w, black=b, date=d, mainline=mainline,
                         ply=ply, depth=depth))
        tags = {}
        movetext_lines = []
        in_moves = False

    pgn = open(os.path.join(BASE, ROOT + ".pgn"), "rb")
    tagRe = re.compile(r'^\[(\w+) "(.*)"\]$')
    lineno = 0
    for raw in pgn:
        lineno += 1
        if lineno % 2000000 == 0:
            print(f"  line {lineno} t={time.time()-t0:.0f}s games={ngames} "
                  f"hitgames={hitgames} texts={len(hits)}", flush=True)
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
        movetext_lines.append(s)
        in_moves = True
    if in_moves:
        finalize()

    print(f"done: {ngames} games, hitgames={hitgames}, needle-texts={len(hits)} "
          f"({time.time()-t0:.1f}s)", flush=True)
    with open(HITS, "w") as f:
        json.dump(hits, f, ensure_ascii=False)


if __name__ == "__main__":
    main()