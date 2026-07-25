#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


TAG_RE = re.compile(r'^\[(\w+)\s+"(.*)"\]$')


def parse_games(text: str):
    games = []
    current = []

    for line in text.splitlines():
        if line.startswith("[Event ") and current:
            games.append("\n".join(current).strip())
            current = [line]
        else:
            current.append(line)

    if current:
        games.append("\n".join(current).strip())

    parsed = []
    for index, raw in enumerate(games, start=1):
        parts = raw.split("\n\n", 1)
        header = parts[0]
        moves = parts[1] if len(parts) > 1 else ""
        tags = {}
        for line in header.splitlines():
            match = TAG_RE.match(line)
            if match:
                tags[match.group(1)] = match.group(2)
        parsed.append((index, tags, moves))

    return parsed


def castling_pattern(moves: str) -> str:
    has_ooo = "O-O-O" in moves
    scrubbed = moves.replace("O-O-O", "")
    has_oo = "O-O" in scrubbed

    if has_oo and has_ooo:
        return "OO+OOO"
    if has_oo:
        return "OO"
    if has_ooo:
        return "OOO"
    return "-"


def is_chess960_fen(fen: str) -> bool:
    parts = fen.split()
    if len(parts) < 3:
        return False
    castling = parts[2]
    return any("A" <= c <= "H" or "a" <= c <= "h" for c in castling)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <grenke-freestyle.pgn>", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    text = path.read_text(errors="replace")
    games = parse_games(text)

    fen_counter: Counter[str] = Counter()
    examples: dict[str, dict[str, list[tuple[int, dict[str, str]]]]] = defaultdict(lambda: defaultdict(list))
    global_castling: Counter[str] = Counter()

    for index, tags, moves in games:
        fen = tags.get("FEN", "")
        if not fen or not is_chess960_fen(fen):
            continue

        pattern = castling_pattern(moves)
        fen_counter[fen] += 1
        global_castling[pattern] += 1

        bucket = examples[fen][pattern]
        if len(bucket) < 2:
            bucket.append((index, tags))

    print(f"# Grenke Freestyle Chess960 Fixtures")
    print()
    print(f"source: {path}")
    print(f"games: {sum(fen_counter.values())}")
    print(f"unique_fens: {len(fen_counter)}")
    print(f"castling_patterns: {dict(global_castling)}")
    print()

    for fen, count in fen_counter.most_common():
        print(f"## FEN ({count} games)")
        print(fen)
        print()
        for pattern in sorted(examples[fen], key=lambda s: ("-" not in s, s)):
            print(f"pattern: {pattern}")
            for index, tags in examples[fen][pattern]:
                white = tags.get("White", "?")
                black = tags.get("Black", "?")
                round_ = tags.get("Round", "?")
                result = tags.get("Result", "?")
                print(f"- game {index}: round {round_}, {white} vs {black}, result {result}")
            print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
