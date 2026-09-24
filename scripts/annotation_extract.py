#!/usr/bin/env python3
"""Extract human annotations from PGN into (position, comment, NAG) records.

    python3 annotation_extract.py --pgn FILE [--out records.jsonl] [--max-games N]

Each record is one annotatable ply:

    {"source": "...", "game": N, "ply": N, "key": "<sha1 of position>",
     "fen": "...", "comment": "...", "nags": [14, 36]}

Clock/eval engine directives ([%clk ...], [%eval ...]) are stripped; only real
prose is kept, but NAGs are kept regardless (they are the machine-readable
human judgment).  `key` hashes the same position identity as
scripts/corpus_precedent.py, but as a hex string; the precedent index stores
the raw sha1 digest, so join with bytes.fromhex(key).
"""

import argparse
import hashlib
import json
import re
import sys

import chess.pgn

DIRECTIVE = re.compile(r"\[%[a-z]+(?:[^\[\]]|\[[^\]]*\])*\]", re.IGNORECASE)
CLOCK = re.compile(r"(?i)^(time|zeit|sealed\s+move|abgabezug)[!.\/ ]*$")


def is_prose(text):
    """True for human/engine commentary, false for clocks, ChessBase meta
    tags (CBH payloads, medals) and glossary term translations."""
    if not text:
        return False
    t = text.strip()
    if CLOCK.match(t):
        return False
    if "(CBH payload:" in t:
        return False
    if re.match(r"(?i)^medal:", t):
        return False
    if not re.search(r"[A-Za-z]{3,}", t):
        return False
    # language-tagged glossary: strip <xx> and parenthesised terms; real prose remains
    if re.search(r"<[a-z]{2}>", t):
        stripped = re.sub(r"<[a-z]{2}>", " ", t)
        stripped = re.sub(r"\([^)]*\)", " ", stripped)
        if len(re.findall(r"[A-Za-z]{3,}", stripped)) < 3:
            return False
    return True


def position_key(board):
    return " ".join(board.fen().split()[:4])


def position_hash(board):
    return hashlib.sha1(position_key(board).encode()).hexdigest()


def clean_comment(text):
    if not text:
        return ""
    # Remove engine directives such as [%clk 0:05:00] / [%eval 0.5], which may
    # nest to any depth ([%eval [%emt ...] 0.5]). A regex cannot recurse, so scan
    # bracket depth; brackets that do not open a directive are kept verbatim.
    out = []
    depth = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if depth == 0:
            if ch == "[" and i + 1 < n and text[i + 1] == "%":
                depth = 1
                i += 2
                continue
            out.append(ch)
            i += 1
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        i += 1
    return "".join(out).strip()


EN_MARK = re.compile(r"<en>", re.IGNORECASE)


def prefer_english(text):
    """ChessBase teaching comments often carry German and English variants
    ("<de> ... <en> ...").  Keep only the English part when both are present,
    so the narration corpus stays in one language."""
    if not text or "<en>" not in text.lower():
        return text
    english = EN_MARK.split(text)[-1]
    english = re.sub(r"<[a-z]{2}>", " ", english)
    return english.strip()


def extract(args):
    out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
    games = 0
    records = 0
    with_comment = 0
    with_nag = 0

    with open(args.pgn, encoding="utf-8", errors="replace") as fh:
        while args.max_games == 0 or games < args.max_games:
            try:
                game = chess.pgn.read_game(fh)
            except Exception:
                continue
            if game is None:
                break
            games += 1

            board = game.board()
            ply = 0
            for node in game.mainline():
                move = node.move
                if move is None:
                    break
                ply += 1

                comment = clean_comment(node.comment)
                comment = prefer_english(comment)
                prose = is_prose(comment)
                nags = sorted(int(n) for n in node.nags)

                if prose or nags:
                    src = game.headers.get("Source", "") or args.source
                    out.write(json.dumps({
                        "source": src,
                        "game": games,
                        "ply": ply,
                        "key": position_hash(board),
                        "fen": board.fen(),
                        "comment": comment,
                        "prose": prose,
                        "nags": nags,
                    }, ensure_ascii=False) + "\n")
                    records += 1
                    if prose:
                        with_comment += 1
                    if nags:
                        with_nag += 1

                board.push(move)

            if games % 50000 == 0:
                print(f"  {games} games, {records} records, "
                      f"{with_comment} prose, {with_nag} nags",
                      file=sys.stderr, flush=True)

    if args.out:
        out.close()

    print(json.dumps({
        "games": games,
        "records": records,
        "with_comment": with_comment,
        "with_nag": with_nag,
    }))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pgn", required=True)
    ap.add_argument("--out")
    ap.add_argument("--max-games", type=int, default=20000)
    ap.add_argument("--source", default="")
    args = ap.parse_args()
    extract(args)


if __name__ == "__main__":
    main()
