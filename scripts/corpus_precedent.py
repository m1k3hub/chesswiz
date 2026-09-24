#!/usr/bin/env python3
"""Corpus precedent index for the chess narrator.

Builds a position -> continuation index from a PGN corpus and answers
"what did masters play in this position, and how did it score".

    python3 corpus_precedent.py build --pgn FILE --db INDEX [--max-games N] [--max-ply M]
    python3 corpus_precedent.py query --db INDEX --fen "FEN"
    python3 corpus_precedent.py query --db INDEX --moves "e4 c5 Nf3 d6"

This is the *precedent* layer: raw master games give move frequencies and
results.  It is not the annotation layer (human prose/NAGs); that needs
annotated sources.
"""

import argparse
import hashlib
import json
import sqlite3
import sys

import chess
import chess.pgn

RESULT = {"1-0": 1.0, "0-1": 0.0, "1/2-1/2": 0.5}


def position_key(board):
    """Position identity: placement + side + castling + en passant."""
    return " ".join(board.fen().split()[:4])


def position_hash(board):
    """Compact index key (sha1 digest of the position identity)."""
    return hashlib.sha1(position_key(board).encode()).digest()


def build(args):
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA journal_mode=OFF")
    conn.execute("PRAGMA synchronous=OFF")
    conn.execute("PRAGMA temp_store=MEMORY")
    conn.execute("PRAGMA cache_size=-400000")
    conn.execute("CREATE TABLE IF NOT EXISTS moves (key BLOB, move TEXT, result REAL, elo INT)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_moves_key ON moves (key)")

    rows = []
    games = 0
    plies = 0
    skipped = 0

    with open(args.pgn, encoding="utf-8", errors="replace") as fh:
        while args.max_games == 0 or games < args.max_games:
            try:
                game = chess.pgn.read_game(fh)
            except Exception:
                skipped += 1
                continue
            if game is None:
                break
            games += 1
            try:
                result = RESULT.get(game.headers.get("Result", "*"), None)
                if result is None:
                    continue
                elo = 0
                for tag in ("WhiteElo", "BlackElo"):
                    try:
                        elo = max(elo, int(game.headers.get(tag, "0")))
                    except ValueError:
                        pass
                if elo < args.min_elo:
                    continue

                board = game.board()
                ply = 0
                for move in game.mainline_moves():
                    if ply >= args.max_ply:
                        break
                    rows.append((position_hash(board), move.uci(), result, elo))
                    board.push(move)
                    ply += 1
                    plies += 1
            except Exception:
                skipped += 1

            if len(rows) >= 250000:
                conn.executemany("INSERT INTO moves VALUES (?,?,?,?)", rows)
                conn.commit()
                rows = []
            if games % args.progress_every == 0:
                print(f"  {games} games, {plies} plies, {skipped} skipped",
                      file=sys.stderr, flush=True)

    conn.executemany("INSERT INTO moves VALUES (?,?,?,?)", rows)
    conn.commit()
    conn.close()
    print(json.dumps({"games": games, "plies": plies, "skipped": skipped, "indexed": args.db}))


def query(args):
    if args.moves:
        board = chess.Board()
        for san in args.moves.split():
            board.push_san(san)
    elif args.fen:
        board = chess.Board(args.fen)
    else:
        raise SystemExit("query needs --fen or --moves")

    key = position_hash(board)

    conn = sqlite3.connect(args.db)
    cur = conn.execute(
        "SELECT move, COUNT(*) c, AVG(result) s, AVG(elo) e "
        "FROM moves WHERE key = ? GROUP BY move ORDER BY c DESC LIMIT ?",
        (key, args.limit),
    )
    total = conn.execute("SELECT COUNT(*) FROM moves WHERE key = ?", (key,)).fetchone()[0]

    # stored result is White's score; report from the side-to-move's point of view
    black_to_move = board.turn == chess.BLACK
    moves = []
    for move, count, score, elo in cur.fetchall():
        white_pct = 100.0 * score
        pct = (100.0 - white_pct) if black_to_move else white_pct
        moves.append({
            "move": move,
            "count": count,
            "share": round(100.0 * count / total, 1) if total else 0.0,
            "scorePct": round(pct, 1),
            "avgElo": int(elo or 0),
        })

    print(json.dumps({
        "key": position_key(board),
        "sideToMove": "black" if black_to_move else "white",
        "games": total,
        "moves": moves,
    }, indent=2))
    conn.close()


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build")
    b.add_argument("--pgn", required=True)
    b.add_argument("--db", required=True)
    b.add_argument("--max-games", type=int, default=20000,
                   help="0 = all games in the file")
    b.add_argument("--max-ply", type=int, default=30)
    b.add_argument("--min-elo", type=int, default=0,
                   help="skip games whose stronger player is below this Elo "
                        "(games with no rating are skipped when > 0)")
    b.add_argument("--progress-every", type=int, default=20000)
    b.set_defaults(func=build)

    q = sub.add_parser("query")
    q.add_argument("--db", required=True)
    q.add_argument("--fen")
    q.add_argument("--moves")
    q.add_argument("--limit", type=int, default=10)
    q.set_defaults(func=query)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
