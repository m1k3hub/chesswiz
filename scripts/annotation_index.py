#!/usr/bin/env python3
"""Index JSONL annotation records and retrieve them by position.

    python3 annotation_index.py build --jsonl FILE --db ANN.sqlite
    python3 annotation_index.py query --db ANN.sqlite --fen "FEN" [--limit N]

Records come from annotation_extract.py and carry a hex sha1 position key.
The precedent index (corpus_precedent.py) hashes the same position identity
but stores the raw digest, so join on bytes.fromhex(key).
"""

import argparse
import hashlib
import json
import re
import sqlite3
import sys

import chess


def fen_key(fen):
    return hashlib.sha1(" ".join(chess.Board(fen).fen().split()[:4]).encode()).hexdigest()


ENG_WORDS = set("the this that with white black better best good is are was were and but for "
                "from has have into both his her its can should must would will more less not "
                "pawn pawns king queen rook bishop knight square move moves attack defence "
                "defense play played than then there which while about after before also".split())
GER_WORDS = set("der die das und ist sind nicht mit wird für von den dem des ein eine einen "
                "weiß schwarz bauer läufer springer turm dame könig aber auch noch kann muss "
                "sich nach über wenn dann hier sehr schon hatte wurden gegen ohne".split())
FRE_WORDS = set("les des une est sont avec pour dans plus coup blanc noirs noir cette leur "
                "ont être fait ainsi mais donc tout tous même aussi avant après".split())


def looks_english(text):
    """Cheap language test for chess prose. True when English markers dominate,
    or when there are no stopwords at all (e.g. pure notation like "Rc1 wins.")."""
    if not text:
        return True
    words = re.findall(r"[a-zà-ÿ']+", text.lower())
    if not words:
        return True
    e = sum(1 for w in words if w in ENG_WORDS)
    g = sum(1 for w in words if w in GER_WORDS)
    f = sum(1 for w in words if w in FRE_WORDS)
    if e + g + f == 0:
        return True
    return e > g and e > f


def build(args):
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA journal_mode=OFF")
    conn.execute("PRAGMA synchronous=OFF")
    # Drop first so a rebuild is idempotent and cannot keep a stale schema
    # (e.g. one predating the `prose` column).
    conn.execute("DROP TABLE IF EXISTS ann")
    conn.execute("CREATE TABLE IF NOT EXISTS ann "
                 "(key TEXT, comment TEXT, prose INT, nags TEXT, source TEXT, game INT, ply INT)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_ann_key ON ann (key)")

    rows = []
    n = 0
    with open(args.jsonl, encoding="utf-8") as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except Exception:
                continue
            rows.append((r["key"], r.get("comment", ""), 1 if r.get("prose") else 0,
                         ",".join(str(x) for x in r.get("nags", [])),
                         r.get("source", ""), r.get("game", 0), r.get("ply", 0)))
            n += 1
            if len(rows) >= 100000:
                conn.executemany("INSERT INTO ann VALUES (?,?,?,?,?,?,?)", rows)
                rows = []
    conn.executemany("INSERT INTO ann VALUES (?,?,?,?,?,?,?)", rows)
    conn.commit()
    conn.close()
    print(json.dumps({"records": n, "indexed": args.db}))


def query(args):
    key = fen_key(args.fen)
    conn = sqlite3.connect(args.db)
    fetch = args.limit * 25 if args.english else args.limit
    cur = conn.execute(
        "SELECT comment, nags, source, game, ply FROM ann "
        "WHERE key = ? AND (prose = 1 OR nags != '') LIMIT ?",
        (key, fetch))
    rows = cur.fetchall()
    if args.english:
        # Keep NAG-only rows (no comment text to test) plus English prose.
        rows = [r for r in rows if not r[0].strip() or looks_english(r[0])][:args.limit]
    out = [{"comment": c, "nags": [int(x) for x in n.split(",") if x], "source": s, "game": g, "ply": p}
           for c, n, s, g, p in rows]
    total = conn.execute("SELECT COUNT(*) FROM ann WHERE key = ?", (key,)).fetchone()[0]
    conn.close()
    print(json.dumps({"key": key, "total": total, "annotations": out}, indent=2))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--jsonl", required=True)
    b.add_argument("--db", required=True)
    b.set_defaults(func=build)
    q = sub.add_parser("query")
    q.add_argument("--db", required=True)
    q.add_argument("--fen", required=True)
    q.add_argument("--limit", type=int, default=5)
    q.add_argument("--english", action="store_true",
                   help="keep only English annotations (skips German/French prose)")
    q.set_defaults(func=query)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
