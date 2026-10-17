#!/usr/bin/env python3
"""NEGATIVE RESULT (2026-08-05) — do not use as-is: synthetic harvesting via
scidb's own encoder CANNOT produce real H0 entries.

The H0 count cipher (src/count_cipher_universal.json) lacks triples for the
DAda-class opening book (plies 1-19), which caps decode accuracy of the Grenke
fixture at ~3%.  This script harvests additional H0 entries from SYNTHETIC
opening corpora encoded by the scidb encoder (probe_encode_many).

WHY IT FAILS: Encoder::encodeMove writes raw = InvLUT[lc] + move_index (see
src/db/cbh/cbh_encoder.cpp).  The real H0 cipher is a separate byte-stream
transform implemented only inside ChessBase 26.8's encoder (gated by game
header flag 0x08000000).  Chaining counts from scidb's encoded bytes yields
count == move_index at every ply — a tautology — so every harvested entry
is a move-index count mislabeled as an H0 count.  Verified: 13,938 such
entries merged on 2026-08-05 produced NO decode improvement (8070/501
unchanged), and the merge was reverted.

The only working oracle is ChessBase 26.8 under Wine (see docs/CHESS960_STATUS.md
"BREAKTHROUGH 2026-07-26"): use it to bulk-generate DAda-class games to ply
10-40 with the fixture's actual first-move distribution, then harvest from
those .cbg bytes.  Keep this script only as a reference for the walk/harvest
math (scripts/harvest_h0_fverified.py has the correct TWIC-vs-scidb offset
math).

Count model (validated, see docs/CHESS960_STATUS.md):
    count_0 = g(lc0); count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)
    raw_p   = InvLUT[lc_p] + count_p   (mod 256)

The scidb encoder emits raw_s = InvLUT[lc] + move_index, i.e. the encoded byte
stream is self-consistent: for encoded move byte b_i with logical code lc_i,
count_i = (b_i - InvLUT[lc_i]) & 0xff.  We therefore chain counts from the
encoder's own bytes (exactly like the walk() logic of
scripts/harvest_h0_fverified.py / harvest_count_cipher.py) and harvest
    H0["countPrev,lcPrev,lc,ply"] = count          for plies >= 2
(ply 1 is skipped because count_0 cannot be chained from the first byte).
Entries are only ADDED; conflicting existing entries are counted and skipped.

Determinism: master RNG seeded with 42.  Time budget: single batched
probe_encode_many invocation for <= ~600 synthetic games.
"""

import json
import random
import re
import subprocess
import sys
from pathlib import Path

import chess
import chess.pgn

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
PGN_FIXTURE = REPO / 'opening-report/tests/fixtures/grenke_freestyle_2026.pgn'
UPATH = REPO / 'src/count_cipher_universal.json'
PROBE = REPO / 'src/probe_encode_many'
SEED = 42
GAMES_PER_FEN = 56          # scripted + guided games per start position
PROMO_ATTEMPTS_PER_FEN = 6  # dedicated underpromotion playout attempts
HARVEST_MIN_PLY = 2         # spec: harvest moves with p >= 2 (ply is 0-based)

# --- MoveNumberLookup / inverse from the decoder source ---------------------
_src = (REPO / 'src/db/cbh/cbh_decoder.cpp').read_text()
_m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', _src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', _m.group(1))]
assert len(LUT) == 256
INV_LUT = [0] * 256
for _i, _v in enumerate(LUT):
    INV_LUT[_v] = _i

# --- Scripted openings (UCI; Chess960 castling = king-from + rook square) ---
# Applied move-by-move with a legality check; illegal moves truncate the
# script (positions differ across the DAda-class family).
SCRIPTS = [
    # classical d-pawn openings
    ['d2d4', 'd7d5', 'g1f3', 'g8f6', 'c2c4', 'e7e6', 'b1c3', 'f8e7',
     'c1f4', 'c7c5', 'e2e3', 'b8c6', 'a2a3', 'e8g8'],
    ['d2d4', 'd7d5', 'c2c4', 'c7c6', 'g1f3', 'g8f6', 'e2e3', 'c8f5',
     'f1d3', 'e7e6', 'd1c2', 'f8d6'],
    # e-pawn openings
    ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'c2c3', 'g8f6',
     'd2d4', 'e5d4', 'c3d4', 'c5b4', 'b1c3', 'f6e4'],
    ['e2e4', 'e7e6', 'd2d4', 'd7d5', 'b1c3', 'f8b4', 'g1e2', 'd5e4'],
    # c/f-pawn flank games
    ['c2c4', 'c7c5', 'g1f3', 'g8f6', 'b1c3', 'b8c6', 'g2g3', 'g7g6',
     'f1g2', 'f8g7', 'e8g8'],
    ['f2f4', 'd7d5', 'g1f3', 'g8f6', 'e2e3', 'c7c5', 'f1e2', 'b8c6'],
    # knight-first systems
    ['g1f3', 'g8f6', 'g2g3', 'd7d5', 'f1g2', 'c7c5', 'e8g8', 'b8c6'],
    ['b1c3', 'b8c6', 'e2e4', 'e7e5', 'g1f3', 'g8f6', 'f1c4', 'f8c5'],
    # explicit castling attempts (king-from + rook-square notation)
    ['d2d4', 'd7d5', 'b2b3', 'b7b6', 'c1b2', 'c8b7', 'd1d3', 'd8d6', 'b1a1'],
    ['e2e3', 'e7e6', 'f1e2', 'f8e7', 'g1f3', 'g8f6', 'e1g1', 'e8g8'],
    ['d2d4', 'd7d5', 'e1d2', 'e7e6', 'f1e3', 'f8e7', 'g1f3', 'g8f6', 'b1c1'],
    ['e2e4', 'e7e5', 'f1c4', 'f8c5', 'g1f3', 'g8f6', 'b8h8', 'b8a8'],
    ['d2d4', 'd7d5', 'b2b3', 'b7b6', 'c1b2', 'c8b7', 'd1d3', 'd8d6', 'b8d8'],
    # early queen/bishop developments
    ['d2d4', 'd7d5', 'd1d3', 'd8d6', 'e2e4', 'e7e5', 'd4e5', 'd6e5'],
    ['e2e4', 'e7e5', 'd1f3', 'd8f6', 'f1c4', 'f8c5', 'g1e2', 'g8e7'],
]

CENTRAL_FILES = {2, 3, 4, 5}  # c..f


def extract_fixture_fens():
    """Distinct Chess960 start FENs used by the Grenke fixture (FEN tags)."""
    fens = []
    seen = set()
    with open(PGN_FIXTURE, encoding='latin-1') as fh:
        while True:
            g = chess.pgn.read_game(fh)
            if g is None:
                break
            fen = g.headers.get('FEN')
            if fen and fen not in seen:
                seen.add(fen)
                fens.append(fen)
    return fens


def move_score(board, mv, rng, pawn_race=False):
    score = rng.uniform(0.0, 1.0)
    if board.is_castling(mv):
        score += 3.0
    if board.is_capture(mv):
        score += 2.5
    if mv.promotion is not None:
        score += 2.0
    piece = board.piece_at(mv.from_square)
    if piece is not None:
        if piece.piece_type == chess.PAWN:
            score += 0.5
            if pawn_race:
                # strongly prefer advancing the most advanced own pawn
                advance = chess.square_rank(mv.to_square)
                if board.turn == chess.BLACK:
                    advance = 7 - advance
                score += 1.5 * advance
                if board.is_capture(mv):
                    score += 2.0
        elif piece.piece_type in (chess.KNIGHT, chess.BISHOP):
            if chess.square_file(mv.to_square) in CENTRAL_FILES and \
               2 <= chess.square_rank(mv.to_square) <= 5:
                score += 0.75
    board.push(mv)
    if board.is_check():
        score += 1.5
    if board.is_repetition(2):
        score -= 6.0
    board.pop()
    return score


def pick_promotion_variant(board, mv, want_under):
    """Return UCI for mv; with want_under prefer knight underpromotion."""
    if mv.promotion is not None and want_under:
        return mv.uci()[:4] + 'n'
    return mv.uci()


def play_one(fen, rng, script, target_ply, want_under_promo, pawn_race=False,
             max_ply=250):
    """Play one synthetic game; return (ucis, promoted_under)."""
    board = chess.Board(fen, chess960=True)
    ucis = []
    under_done = False

    # 1) scripted prefix (legality-checked)
    if script:
        for u in script:
            mv = chess.Move.from_uci(u)
            if board.is_game_over() or mv not in board.legal_moves:
                break
            ucis.append(u)
            board.push(mv)

    # 2) guided play up to target ply, then ~5 greedy moves
    greedy_extra = 5
    limit = min(target_ply + greedy_extra, max_ply)
    while len(ucis) < limit and not board.is_game_over():
        moves = list(board.legal_moves)
        if not moves:
            break
        greedy = len(ucis) >= target_ply  # final phase: prefer captures/checks
        best, best_s = None, -1e9
        for mv in moves:
            s = move_score(board, mv, rng, pawn_race=pawn_race)
            if greedy:
                s += 4.0 if board.is_capture(mv) else 0.0
            if s > best_s:
                best, best_s = mv, s
        uci = pick_promotion_variant(board, best, want_under_promo and not under_done)
        mv_play = chess.Move.from_uci(uci)
        if mv_play not in board.legal_moves:
            mv_play, uci = best, best.uci()
        if mv_play.promotion is not None and uci.endswith('n'):
            under_done = True
        ucis.append(uci)
        board.push(mv_play)
    return ucis, under_done


def generate_corpora(fens, rng):
    """Return list of (fen, ucis, kind) lines and promo statistics."""
    lines = []
    promo_stats = {}
    for fen in fens:
        tag = fen.split()[0]
        n_under = 0
        # scripted games (cycle scripts) + guided random games
        for i in range(GAMES_PER_FEN):
            script = SCRIPTS[i % len(SCRIPTS)] if i < len(SCRIPTS) * 2 else None
            target = rng.randint(25, 40)
            ucis, under = play_one(fen, rng, script, target,
                                   want_under_promo=(n_under == 0))
            if under:
                n_under += 1
            if len(ucis) >= 10:
                lines.append((fen, ucis, 'guided'))
        # dedicated underpromotion playouts until one succeeds
        attempts = 0
        while n_under == 0 and attempts < PROMO_ATTEMPTS_PER_FEN:
            attempts += 1
            ucis, under = play_one(fen, rng, None, 120, want_under_promo=True,
                                   pawn_race=True)
            if under:
                n_under += 1
                lines.append((fen, ucis, 'promo'))
        promo_stats[tag] = n_under
    return lines, promo_stats


def encode_lines(lines):
    """Batch-encode through probe_encode_many; return parsed results."""
    inp = ''.join(f'{fen}\t{" ".join(ucis)}\n' for fen, ucis, _ in lines)
    r = subprocess.run([str(PROBE)], input=inp, capture_output=True, text=True,
                       timeout=120)
    out = r.stdout.splitlines()
    if len(out) != len(lines):
        raise RuntimeError(f'probe_encode_many line mismatch: '
                           f'{len(out)} out vs {len(lines)} in')
    results = []
    for (fen, ucis, kind), line in zip(lines, out):
        m = re.match(r'POS=([0-9a-f]+) \| ([0-9a-f ]*)$', line.strip())
        if not m:
            results.append(None)
            continue
        pos, sbytes = m.group(1), bytes.fromhex(m.group(2).replace(' ', ''))
        if len(pos) != 56 or len(sbytes) == 0:
            results.append(None)
            continue
        results.append((fen, ucis, kind, sbytes))
    return results


def walk_and_harvest(sbytes, H0, g, P1, P2, stats):
    """Walk one encoded stream; harvest H0/g/P1/P2 entries.

    Counts are chained from the encoder's own bytes:
        lc_i    = LUT[(b_i - count_i) & 0xff]
        count_i = (b_i - INV_LUT[lc_i]) & 0xff      (== move index)
    """
    # 1) walk: (offset, lc, nbytes) per move, chained counts
    moves = []  # (lc, count, offset)
    j = c = 0
    while j < len(sbytes):
        lc = LUT[(sbytes[j] - c) & 0xff]
        moves.append((lc, c, j))
        j += 3 if lc == 0xeb else 1
        c += 1
    if j != len(sbytes):
        stats['walk_fail'] += 1
        return
    # sanity: byte-chained counts reproduce the move index exactly
    for lc, count, off in moves:
        if (sbytes[off] - INV_LUT[lc]) & 0xff != count:
            stats['walk_fail'] += 1
            return

    # 2) g seed from first move (count_0 not chainable from bytes alone)
    lc0 = moves[0][0]
    kg = str(lc0)
    if kg not in g:
        g[kg] = 0  # self-consistent seed: b_0 = InvLUT[lc_0] + 0
        stats['new_g'] += 1
    elif g[kg] != 0:
        stats['conf_g'] += 1  # synthetic seed 0 differs; keep existing value

    # 3) H0 entries for plies >= HARVEST_MIN_PLY
    for p in range(HARVEST_MIN_PLY, len(moves)):
        lc_prev, count_prev, _ = moves[p - 1]
        lc, count, _ = moves[p]
        key = f'{count_prev},{lc_prev},{lc},{p}'
        if key not in H0:
            H0[key] = count
            stats['new_h'] += 1
        elif H0[key] != count:
            stats['conf_h'] += 1
        else:
            stats['dup_h'] += 1

    # 4) optional P1/P2 harvest from 0xeb triples (scidb semantics:
    #    b1 = InvLUT[X1] + cnt, b2 = InvLUT[X2] + cnt, X1=hi, X2=lo word)
    for idx, (lc, count, off) in enumerate(moves):
        if lc != 0xeb or off + 2 >= len(sbytes):
            continue
        x1 = LUT[(sbytes[off + 1] - count) & 0xff]
        x2 = LUT[(sbytes[off + 2] - count) & 0xff]
        k1 = f'{count},{x1},{idx + 1}'
        if k1 not in P1:
            P1[k1] = count
            stats['new_p1'] += 1
        elif P1[k1] != count:
            stats['conf_p1'] += 1
        k2 = f'{count},{x2},{idx + 2}'
        if k2 not in P2:
            P2[k2] = count
            stats['new_p2'] += 1
        elif P2[k2] != count:
            stats['conf_p2'] += 1


def main():
    rng = random.Random(SEED)

    u = json.load(open(UPATH))
    H0, g, P1, P2 = u['H0'], u['g_count0'], u['P1'], u['P2']
    h0_before, g_before = len(H0), len(g)
    print(f'start: H0={h0_before} g={g_before} P1={len(P1)} P2={len(P2)}')

    fens = extract_fixture_fens()
    print(f'fixture start positions: {len(fens)}')
    for f in fens:
        print('  ', f)

    lines, promo_stats = generate_corpora(fens, rng)
    print(f'generated {len(lines)} synthetic games '
          f'(underpromotion corpora: {promo_stats})')

    results = encode_lines(lines)
    encoded = [r for r in results if r is not None]
    print(f'encoded ok: {len(encoded)}/{len(results)}')

    stats = dict(walk_fail=0, new_h=0, dup_h=0, conf_h=0,
                 new_g=0, conf_g=0, new_p1=0, conf_p1=0, new_p2=0, conf_p2=0)
    n_eb = 0
    for fen, ucis, kind, sbytes in encoded:
        walk_and_harvest(sbytes, H0, g, P1, P2, stats)
        # count 0xeb triples for the report
        j = c = 0
        while j < len(sbytes):
            lc = LUT[(sbytes[j] - c) & 0xff]
            if lc == 0xeb:
                n_eb += 1
                j += 3
            else:
                j += 1
            c += 1

    print(f'walk failures: {stats["walk_fail"]}')
    print(f'0xeb triples seen: {n_eb}')
    print(f'H0: +{stats["new_h"]} new, {stats["dup_h"]} already present, '
          f'{stats["conf_h"]} conflicts skipped -> total {len(H0)}')
    print(f'g : +{stats["new_g"]} new, {stats["conf_g"]} conflicts skipped '
          f'-> total {len(g)}')
    print(f'P1: +{stats["new_p1"]} new, {stats["conf_p1"]} conflicts; '
          f'P2: +{stats["new_p2"]} new, {stats["conf_p2"]} conflicts')

    u['H0_entries'] = len(H0)
    u['source'] = (u['source'] +
                   f' +dada-oracle harvest {stats["new_h"]} entries 2026-08-05')
    json.dump(u, open(UPATH, 'w'), indent=1)
    print(f'MERGED -> {UPATH} (H0_entries={u["H0_entries"]})')


if __name__ == '__main__':
    main()
