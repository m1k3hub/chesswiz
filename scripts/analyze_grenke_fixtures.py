#!/usr/bin/env python3
"""
analyze_grenke_fixtures.py — Diagnostic report for GRENKE Chess960 fixtures.

Reads the official ChessBase PGN for the Grenke Freestyle Chess Open 2026
and prints a per-start-position summary:
  - number of games
  - castling patterns observed
  - whether each side has any legal castling in the start position
    (using python-chess under Chess960 rules)

This script documents what the current scidb CBH encoder/decoder can and
cannot represent without real ChessBase-generated .cbh/.cbg fixtures.
"""

from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import chess


def split_games(pgn_text: str) -> list[str]:
    """Split a multi-game PGN into individual game strings."""
    games = re.split(r'\n(?=\[Event ")', pgn_text.strip())
    return [g for g in games if g.strip()]


def main(pgn_path: Path) -> int:
    pgn_text = pgn_path.read_text(encoding="utf-8")
    game_strs = split_games(pgn_text)

    fen_counts: Counter[str] = Counter()
    fen_patterns: defaultdict[str, Counter[str]] = defaultdict(Counter)
    fen_legal_castling: dict[str, dict[str, bool]] = {}

    for i, g in enumerate(game_strs, start=1):
        # Extract the FEN tag if present; otherwise use standard start.
        setup_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        m = re.search(r'\[FEN "([^"]+)"\]', g)
        if m:
            setup_fen = m.group(1)

        fen_counts[setup_fen] += 1

        # Determine castling patterns in this game by looking at the SAN.
        body = re.sub(r"\{[^}]*\}", " ", g.split("\n\n", 1)[-1] if "\n\n" in g else g)
        patterns: set[str] = set()
        if "O-O-O" in body:
            patterns.add("OOO")
        if re.search(r"(?<![-O])O-O(?![-O])", body):
            patterns.add("OO")
        if not patterns:
            patterns.add("-")

        for p in patterns:
            fen_patterns[setup_fen][p] += 1

        # Compute legal castling rights in the start position once per FEN.
        if setup_fen not in fen_legal_castling:
            board = chess.Board(setup_fen, chess960=True)
            legal = board.generate_castling_moves()
            sides = {"OO": False, "OOO": False}
            for move in legal:
                if move.from_square < move.to_square:
                    sides["OO"] = True
                else:
                    sides["OOO"] = True
            fen_legal_castling[setup_fen] = sides

    print(f"Games analyzed: {len(game_strs)}")
    print(f"Unique start FENs: {len(fen_counts)}")
    print()

    for fen, count in fen_counts.most_common():
        board = chess.Board(fen, chess960=True)
        king_sq = board.king(chess.WHITE)
        king_file = chess.square_name(king_sq)[0]
        print(f"FEN ({count} games) king on {king_file}-file")
        print(f"  {fen}")
        print(f"  Observed patterns: {dict(fen_patterns[fen])}")
        legal = fen_legal_castling[fen]
        print(f"  Legal castling in start position: OO={legal['OO']}, OOO={legal['OOO']}")
        if king_file != "e":
            print(
                "  NOTE: CBH encoder currently encodes castling as a two-square king move; "
                "positions with the king off the e-file may not round-trip through CBH "
                "under file-based (Convention B) castling."
            )
        print()

    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <grenke.pgn>", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(Path(sys.argv[1])))
