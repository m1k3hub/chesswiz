#!/usr/bin/env python3
"""Harvest the 2CBH Move16 code -> move table empirically.

Pairs each 16-bit code in the fixture's .2cbg move streams with the ground-
truth (from, to, promo, piece) of the same ply taken from the PGN twin
(same game order, verified via PlyCount + first-game identity).

The Ghidra RE (2CBH_FORMAT_DESIGN.md §3.7.2) says decoding is
`inverseTable[code] -> 8-byte descriptor (from, to, piece, promo)` through a
static runtime-built table `s_nIndex[from][to][piece] -> code`.  If that
model is right, harvesting MUST produce a conflict-free table; any conflict
refutes the model.

Usage: harvest_move16.py [N_GAMES] [OUT_JSON]
"""
import struct, sys, os, re, json, collections

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
NGAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
OUT = sys.argv[3] if len(sys.argv) > 3 else "src/move16_table.json"

import chess  # python-chess

MAGIC = 0x1122334455667788
TOKEN_RE = re.compile(
    r'(\{[^}]*\}|\([^()]*\)|\d+\.(\.\.)?|O-O(-O)?|0-0(-0)?|[a-hKQRBN][^\s]+|[?!]+|\$+\d+|1-0|0-1|1/2-1/2|\*)'
)

SAN2PIECE = {'P': 1, 'N': 2, 'B': 3, 'R': 4, 'Q': 5, 'K': 6}


def iter_cbg(n):
    """Yield (recno, type, list-of-codes) for the first n game records."""
    path = os.path.join(BASE, ROOT + ".2cbg")
    fsize, _, hsize, ver = struct.unpack("<IIHH", open(path, "rb").read(12))
    f = open(path, "rb")
    off = hsize
    recno = 0
    while off + 38 <= fsize:
        f.seek(off)
        head = f.read(0x1a)
        magic, dsize, esz = struct.unpack("<QII", head[:16])
        if magic != MAGIC:
            break
        t = struct.unpack("<H", head[24:26])[0]
        if dsize:
            data = f.read(dsize)
        else:
            data = b""
        yield recno, t, data
        off += 16 + dsize + esz + 18
        recno += 1
        if recno >= n:
            break


def movetext_tokens(line):
    for m in TOKEN_RE.finditer(line):
        tok = m.group(1)
        if m.group(2):  # "..." continuation
            continue
        yield tok


def iter_pgn(n):
    """Yield (plies) list of (from,to,promo,piece) per game, streaming."""
    path = os.path.join(BASE, ROOT + ".pgn")
    f = open(path, "r", encoding="utf-8", errors="replace")
    games = 0
    while games < n:
        tags = {}
        movetext = []
        # read header
        for line in f:
            line = line.strip()
            if not line:
                if movetext or tags:
                    break
                continue
            m = re.match(r'\[(\w+)\s+"([^"]*)"\]', line)
            if m:
                tags[m.group(1)] = m.group(2)
            else:
                movetext.append(line)
                break
        if not tags and not movetext:
            return
        # read movetext until blank line
        for line in f:
            if line.strip() == "":
                if movetext:
                    break
                continue
            movetext.append(line.rstrip("\n"))
        board = chess.Board()
        plies = []
        san_list = []
        ok = True
        for line in movetext:
            for tok in movetext_tokens(line):
                if tok in ("1-0", "0-1", "1/2-1/2", "*"):
                    continue
                if tok[0] in "$?!" or tok[0].isdigit() or tok.startswith("{"):
                    continue
                try:
                    mv = board.push_san(tok)
                except Exception:
                    ok = False
                    break
                piece = board.piece_at(mv.to_square)
                pt = piece.piece_type if piece else 0
                promo = mv.promotion if mv.promotion else 0
                # castling: python-chess normalizes king move; keep king from/to
                plies.append((mv.from_square, mv.to_square, promo, pt))
                san_list.append(tok)
            if not ok:
                break
        if ok:
            yield plies, tags, san_list
        games += 1


def main():
    table = {}          # code -> (from, to, piece, promo)
    conflicts = []
    stats = collections.Counter()
    special_context = []  # samples around 0xfffb
    cbg = iter_cbg(NGAMES)
    pgn = iter_pgn(NGAMES)
    nalign_fail = 0
    for recno, t, data in cbg:
        try:
            plies, tags, san_list = next(pgn)
        except StopIteration:
            break
        # decode shorts
        shorts = [struct.unpack_from("<H", data, i)[0] for i in range(0, len(data) - 1, 2)]
        # strip leading 0xfffc
        body = shorts
        if body and body[0] == 0xffFC:
            body = body[1:]
        # cut at terminator
        term = None
        for i, s in enumerate(body):
            if s >= 0xfffb:
                term = i
                break
        codes = body[:term] if term is not None else body
        trailing = body[term:] if term is not None else []
        if t != 1:
            stats[f"type_{t}"] += 1
        if any(s in (0xfffb, 0xfffd) for s in codes):
            stats["has_fffb"] += 1
            if len(special_context) < 40:
                special_context.append((recno, [f"{s:04x}" for s in body[max(0, (term or 0) - 6):term + 8] if True][:20]))
            continue
        if term is None:
            stats["no_terminator"] += 1
            continue
        if trailing and trailing[-1] not in (0xfffe, 0xffff):
            stats["bad_trailing"] += 1
        if len(codes) != len(plies):
            nalign_fail += 1
            if nalign_fail <= 5:
                print(f"  ALIGN FAIL rec {recno}: {len(codes)} codes vs {len(plies)} plies "
                      f"(PlyCount={tags.get('PlyCount')}) trailing={[f'{s:04x}' for s in trailing]}")
            stats["align_fail"] += 1
            continue
        stats["games_ok"] += 1
        for code, (frm, to, promo, piece) in zip(codes, plies):
            desc = (frm, to, piece, promo)
            if code in table:
                if table[code] != desc:
                    conflicts.append((code, table[code], desc))
                    stats["conflicts"] += 1
            else:
                table[code] = desc
                stats["new_codes"] += 1
        if conflicts and len(conflicts) > 50:
            print("too many conflicts — model wrong, aborting")
            break

    print(f"\ngames OK: {stats['games_ok']}, new codes: {stats['new_codes']}, "
          f"conflicts: {stats['conflicts']}, align fails: {stats['align_fail']}")
    print(f"other: {dict((k, v) for k, v in stats.items() if k not in ('games_ok','new_codes','conflicts','align_fail'))}")
    if conflicts:
        print("\nfirst conflicts (code, known, new):")
        for c in conflicts[:20]:
            print(f"  {c[0]:04x}: {c[1]} vs {c[2]}")
    codes_sorted = sorted(table)
    if codes_sorted:
        print(f"\ncode range: {codes_sorted[0]:04x} .. {codes_sorted[-1]:04x}, "
              f"density: {len(codes_sorted)} distinct")
        gaps = [(a, b) for a, b in zip(codes_sorted, codes_sorted[1:]) if b - a > 1]
        print(f"gaps > 1: {len(gaps)}; first gaps: {[(f'{a:04x}',f'{b:04x}') for a, b in gaps[:10]]}")
    if special_context:
        print("\n0xfffb context samples:")
        for recno, ctx in special_context[:10]:
            print(f"  rec {recno}: {' '.join(ctx)}")

    if OUT and not conflicts:
        out = {
            "_meta": {
                "source": "harvested from LumbrasGigaBase_OTB_ELO2400 (.2cbg codes vs PGN ground truth)",
                "games": stats["games_ok"],
                "entries": len(table),
                "descriptor": "(from, to, piece, promo); squares python-chess a1=0..h8=63; piece 1..6; promo 0 or piece-type",
            },
            "table": {f"{c:04x}": list(table[c]) for c in codes_sorted},
        }
        with open(OUT, "w") as f:
            json.dump(out, f, indent=1)
        print(f"\nwrote {OUT} ({len(table)} entries)")


if __name__ == "__main__":
    main()