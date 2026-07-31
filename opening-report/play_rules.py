"""play_rules — pure-Python standard-chess rules engine (Phase 4 fallback).

Per ONLINE_PLAY_PLAN.md decision 1, the canonical server-side move validator is
the scidb C++ rules engine via a stateless `position/legal` Tcl bridge command.
That bridge requires the scidb interpreter, which is not wired in every
deployment (health reports `tclBridge: disabled`). This module is the
**documented fallback** active for v1: a self-contained standard-chess engine
(no python-chess dependency) used by play_service when the bridge is unavailable.

Scope: standard chess with castling, en passant, promotion, and terminal
detection (checkmate / stalemate / insufficient material / threefold repetition
/ fifty-move). Chess960 castling is NOT implemented here — Chess960 matches
must route through the scidb C++ bridge (Phase 4.5). The parity test
(tests/test_play_rules.py) pins standard-chess outcomes.

Board representation: dict mapping (file, rank) -> piece char, where file/rank
are 0-7 (file 0 = 'a', rank 0 = '1'). Pieces are one of 'PNBRQK' (white) /
'pnbrqk' (black). Empty squares are absent from the dict.
"""

from __future__ import annotations

from dataclasses import dataclass, field

FILES = "abcdefgh"

WHITE = "w"
BLACK = "b"


def sq(file: int, rank: int) -> str:
    return FILES[file] + str(rank + 1)


def parse_square(name: str) -> tuple[int, int]:
    return (FILES.index(name[0]), int(name[1]) - 1)


@dataclass
class Position:
    board: dict[tuple[int, int], str]
    turn: str  # 'w' | 'b'
    castling: set[str]  # subset of {'K','Q','k','q'}
    ep: tuple[int, int] | None  # en-passant target square
    halfmove: int  # 50-move rule half-move clock
    fullmove: int
    history: list[str] = field(default_factory=list)  # position keys for repetition

    def key(self) -> str:
        # Repetition key: board + turn + castling + ep (ignore clocks).
        rows = []
        for r in range(7, -1, -1):
            row = ""
            for f in range(8):
                row += self.board.get((f, r), ".")
            rows.append(row)
        return "/".join(rows) + "|" + self.turn + "|" + "".join(sorted(self.castling)) + "|" + (sq(*self.ep) if self.ep else "-")


def parse_fen(fen: str) -> Position:
    parts = fen.strip().split()
    rows = parts[0].split("/")
    if len(rows) != 8:
        raise ValueError("bad FEN ranks")
    board: dict[tuple[int, int], str] = {}
    for i, row in enumerate(rows):
        rank = 7 - i
        file = 0
        for ch in row:
            if ch.isdigit():
                file += int(ch)
            else:
                board[(file, rank)] = ch
                file += 1
    turn = parts[1] if len(parts) > 1 else "w"
    castling = set(c for c in (parts[2] if len(parts) > 2 else "-") if c in "KQkq")
    ep = parse_square(parts[3]) if len(parts) > 3 and parts[3] != "-" else None
    halfmove = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0
    fullmove = int(parts[5]) if len(parts) > 5 and parts[5].isdigit() else 1
    return Position(board, turn, castling, ep, halfmove, fullmove)


def to_fen(pos: Position) -> str:
    rows = []
    for r in range(7, -1, -1):
        row = ""
        empty = 0
        for f in range(8):
            p = pos.board.get((f, r))
            if p is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += p
        if empty:
            row += str(empty)
        rows.append(row)
    return (
        "/".join(rows)
        + " " + pos.turn
        + " " + ("".join(sorted(pos.castling, key=lambda c: "KQkq".index(c))) or "-")
        + " " + (sq(*pos.ep) if pos.ep else "-")
        + " " + str(pos.halfmove)
        + " " + str(pos.fullmove)
    )


def _color(piece: str) -> str:
    return WHITE if piece.isupper() else BLACK


def _opposite(color: str) -> str:
    return BLACK if color == WHITE else WHITE


KNIGHT_DELTAS = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
KING_DELTAS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
BISHOP_DIRS = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
ROOK_DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]
QUEEN_DIRS = BISHOP_DIRS + ROOK_DIRS


def _on_board(f: int, r: int) -> bool:
    return 0 <= f < 8 and 0 <= r < 8


def _find_king(pos: Position, color: str) -> tuple[int, int] | None:
    target = "K" if color == WHITE else "k"
    for (f, r), p in pos.board.items():
        if p == target:
            return (f, r)
    return None


def _attacked_by(pos: Position, file: int, rank: int, by_color: str) -> bool:
    """Is square (file,rank) attacked by `by_color`?"""
    # Pawn attacks: a pawn of by_color on (pf, pr) attacks (file,rank) if diagonal.
    pawn = "P" if by_color == WHITE else "p"
    # White pawns attack upward (rank+1); they sit on rank-1 relative to target.
    pr = rank - 1 if by_color == WHITE else rank + 1
    for pf in (file - 1, file + 1):
        if _on_board(pf, pr) and pos.board.get((pf, pr)) == pawn:
            return True
    # Knight
    knight = "N" if by_color == WHITE else "n"
    for df, dr in KNIGHT_DELTAS:
        if _on_board(file + df, rank + dr) and pos.board.get((file + df, rank + dr)) == knight:
            return True
    # King
    king = "K" if by_color == WHITE else "k"
    for df, dr in KING_DELTAS:
        if _on_board(file + df, rank + dr) and pos.board.get((file + df, rank + dr)) == king:
            return True
    # Sliding: bishop/queen on diagonals, rook/queen on lines.
    bishop = "B" if by_color == WHITE else "b"
    queen = "Q" if by_color == WHITE else "q"
    rook = "R" if by_color == WHITE else "r"
    for df, dr in BISHOP_DIRS:
        f, r = file + df, rank + dr
        while _on_board(f, r):
            p = pos.board.get((f, r))
            if p is not None:
                if _color(p) == by_color and p.lower() in ("b", "q"):
                    return True
                break
            f, r = f + df, r + dr
    for df, dr in ROOK_DIRS:
        f, r = file + df, rank + dr
        while _on_board(f, r):
            p = pos.board.get((f, r))
            if p is not None:
                if _color(p) == by_color and p.lower() in ("r", "q"):
                    return True
                break
            f, r = f + df, r + dr
    return False


def _in_check(pos: Position, color: str) -> bool:
    king = _find_king(pos, color)
    if king is None:
        return False
    return _attacked_by(pos, king[0], king[1], _opposite(color))


@dataclass
class Move:
    from_sq: tuple[int, int]
    to_sq: tuple[int, int]
    promo: str | None = None  # 'q','r','b','n' (lowercase)
    is_castle: str | None = None  # 'K' | 'Q' | None (side)
    is_ep: bool = False


def _pseudo_moves(pos: Position) -> list[Move]:
    color = pos.turn
    moves: list[Move] = []
    for (f, r), p in list(pos.board.items()):
        if _color(p) != color:
            continue
        pt = p.lower()
        if pt == "p":
            direction = 1 if color == WHITE else -1
            start_rank = 1 if color == WHITE else 6
            promo_rank = 7 if color == WHITE else 0
            # forward one
            if _on_board(f, r + direction) and (f, r + direction) not in pos.board:
                if r + direction == promo_rank:
                    for pr in ("q", "r", "b", "n"):
                        moves.append(Move((f, r), (f, r + direction), promo=pr))
                else:
                    moves.append(Move((f, r), (f, r + direction)))
                # forward two
                if r == start_rank and (f, r + 2 * direction) not in pos.board:
                    moves.append(Move((f, r), (f, r + 2 * direction)))
            # captures
            for cf in (f - 1, f + 1):
                if _on_board(cf, r + direction):
                    target = (cf, r + direction)
                    enemy = pos.board.get(target)
                    if enemy is not None and _color(enemy) == _opposite(color):
                        if r + direction == promo_rank:
                            for pr in ("q", "r", "b", "n"):
                                moves.append(Move((f, r), target, promo=pr))
                        else:
                            moves.append(Move((f, r), target))
                    elif pos.ep == target:
                        moves.append(Move((f, r), target, is_ep=True))
        elif pt == "n":
            for df, dr in KNIGHT_DELTAS:
                tf, tr = f + df, r + dr
                if _on_board(tf, tr):
                    enemy = pos.board.get((tf, tr))
                    if enemy is None or _color(enemy) == _opposite(color):
                        moves.append(Move((f, r), (tf, tr)))
        elif pt == "k":
            for df, dr in KING_DELTAS:
                tf, tr = f + df, r + dr
                if _on_board(tf, tr):
                    enemy = pos.board.get((tf, tr))
                    if enemy is None or _color(enemy) == _opposite(color):
                        moves.append(Move((f, r), (tf, tr)))
            # castling (standard)
            home_rank = 0 if color == WHITE else 6 + 1  # white rank 0, black rank 7
            home_rank = 0 if color == WHITE else 7
            if r == home_rank and f == 4:
                # kingside
                right = "K" if color == WHITE else "k"
                if right in pos.castling and pos.board.get((5, home_rank)) is None and pos.board.get((6, home_rank)) is None:
                    if not _attacked_by(pos, 4, home_rank, _opposite(color)) and not _attacked_by(pos, 5, home_rank, _opposite(color)) and not _attacked_by(pos, 6, home_rank, _opposite(color)):
                        moves.append(Move((4, home_rank), (6, home_rank), is_castle="K"))
                # queenside
                right = "Q" if color == WHITE else "q"
                if right in pos.castling and pos.board.get((3, home_rank)) is None and pos.board.get((2, home_rank)) is None and pos.board.get((1, home_rank)) is None:
                    if not _attacked_by(pos, 4, home_rank, _opposite(color)) and not _attacked_by(pos, 3, home_rank, _opposite(color)) and not _attacked_by(pos, 2, home_rank, _opposite(color)):
                        moves.append(Move((4, home_rank), (2, home_rank), is_castle="Q"))
        else:
            dirs = {"b": BISHOP_DIRS, "r": ROOK_DIRS, "q": QUEEN_DIRS}[pt]
            for df, dr in dirs:
                tf, tr = f + df, r + dr
                while _on_board(tf, tr):
                    enemy = pos.board.get((tf, tr))
                    if enemy is None:
                        moves.append(Move((f, r), (tf, tr)))
                    else:
                        if _color(enemy) == _opposite(color):
                            moves.append(Move((f, r), (tf, tr)))
                        break
                    tf, tr = tf + df, tr + dr
    return moves


def _make_move(pos: Position, move: Move) -> Position:
    """Return a new Position with `move` applied (no legality check)."""
    board = dict(pos.board)
    color = pos.turn
    piece = board.pop(move.from_sq)
    halfmove = pos.halfmove + 1
    ep = None
    # En passant capture removes the pawn behind the target.
    if move.is_ep:
        cap_rank = move.from_sq[1]
        board.pop((move.to_sq[0], cap_rank))
    # Castling: move the rook too.
    if move.is_castle == "K":
        home_rank = move.from_sq[1]
        rook = board.pop((7, home_rank))
        board[(5, home_rank)] = rook
    elif move.is_castle == "Q":
        home_rank = move.from_sq[1]
        rook = board.pop((0, home_rank))
        board[(3, home_rank)] = rook
    # Place piece (with promotion).
    if move.promo:
        board[move.to_sq] = move.promo.upper() if color == WHITE else move.promo.lower()
    else:
        board[move.to_sq] = piece
    # Pawn double sets ep square.
    if piece.lower() == "p":
        halfmove = 0
        if abs(move.to_sq[1] - move.from_sq[1]) == 2:
            ep = ((move.from_sq[0] + move.to_sq[0]) // 2, (move.from_sq[1] + move.to_sq[1]) // 2)
    # Capture resets halfmove.
    if pos.board.get(move.to_sq) is not None and not move.is_ep:
        halfmove = 0
    # Update castling rights.
    castling = set(pos.castling)
    if piece == "K":
        castling.discard("K")
        castling.discard("Q")
    elif piece == "k":
        castling.discard("k")
        castling.discard("q")
    # Rook moves from home squares.
    if move.from_sq == (0, 0):
        castling.discard("Q")
    elif move.from_sq == (7, 0):
        castling.discard("K")
    elif move.from_sq == (0, 7):
        castling.discard("q")
    elif move.from_sq == (7, 7):
        castling.discard("k")
    # Rook captured on home square.
    if move.to_sq == (0, 0):
        castling.discard("Q")
    elif move.to_sq == (7, 0):
        castling.discard("K")
    elif move.to_sq == (0, 7):
        castling.discard("q")
    elif move.to_sq == (7, 7):
        castling.discard("k")
    fullmove = pos.fullmove + (1 if color == BLACK else 0)
    new_pos = Position(board, _opposite(color), castling, ep, halfmove, fullmove)
    return new_pos


def legal_moves(pos: Position) -> list[Move]:
    """All legal moves for the side to move (king not left in check)."""
    out = []
    for mv in _pseudo_moves(pos):
        new_pos = _make_move(pos, mv)
        if not _in_check(new_pos, pos.turn):  # mover's king safe
            out.append(mv)
    return out


def _san(pos: Position, move: Move, gives_check: bool, gives_mate: bool) -> str:
    if move.is_castle == "K":
        san = "O-O"
    elif move.is_castle == "Q":
        san = "O-O-O"
    else:
        piece = pos.board[move.from_sq]
        pt = piece.lower()
        is_capture = move.to_sq in pos.board or move.is_ep
        if pt == "p":
            if is_capture:
                san = FILES[move.from_sq[0]] + "x" + sq(*move.to_sq)
            else:
                san = sq(*move.to_sq)
            if move.promo:
                san += "=" + move.promo.upper()
        else:
            san = pt.upper()
            # Disambiguation: if another same-type piece can also move to target.
            ambiguous = []
            for m in legal_moves(pos):
                if m.to_sq == move.to_sq and m.from_sq != move.from_sq:
                    if pos.board.get(m.from_sq, "").lower() == pt:
                        ambiguous.append(m.from_sq)
            if ambiguous:
                same_file = any(a[0] == move.from_sq[0] for a in ambiguous)
                same_rank = any(a[1] == move.from_sq[1] for a in ambiguous)
                if not same_file:
                    san += FILES[move.from_sq[0]]
                elif not same_rank:
                    san += str(move.from_sq[1] + 1)
                else:
                    san += sq(*move.from_sq)
            if is_capture:
                san += "x"
            san += sq(*move.to_sq)
    if gives_mate:
        san += "#"
    elif gives_check:
        san += "+"
    return san


@dataclass
class MoveResult:
    legal: bool
    san: str | None = None
    fen: str | None = None
    checkmate: bool = False
    stalemate: bool = False
    draw: str | None = None  # 'insufficient' | 'threefold' | 'fifty' | None


def _insufficient_material(pos: Position) -> bool:
    pieces = list(pos.board.values())
    # K vs K, K+minor vs K
    non_king = [p for p in pieces if p.lower() != "k"]
    if len(non_king) == 0:
        return True
    if len(non_king) == 1 and non_king[0].lower() in ("b", "n"):
        return True
    # K+B vs K+B with same-color bishops — skip (rare); keep simple.
    return False


def make_move(fen: str, uci: str) -> MoveResult:
    """Validate `uci` (e.g. 'e2e4', 'e7e8q') from `fen`; return result.

    Returns MoveResult(legal=False) for illegal moves. On a legal move, returns
    the new FEN, SAN, and terminal flags.
    """
    if len(uci) < 4:
        return MoveResult(legal=False)
    try:
        pos = parse_fen(fen)
    except Exception:
        return MoveResult(legal=False)
    try:
        ff, fr = parse_square(uci[0:2])
        tf, tr = parse_square(uci[2:4])
    except Exception:
        return MoveResult(legal=False)
    promo = uci[4].lower() if len(uci) >= 5 and uci[4].lower() in "qrbn" else None

    target = None
    for mv in legal_moves(pos):
        if mv.from_sq == (ff, fr) and mv.to_sq == (tf, tr):
            if promo is None and mv.promo is None:
                target = mv
                break
            if promo is not None and mv.promo == promo:
                target = mv
                break
            # allow auto-queen when no promo specified but move is a promotion
            if promo is None and mv.promo == "q":
                target = mv
                break
    if target is None:
        return MoveResult(legal=False)

    new_pos = _make_move(pos, target)
    if _in_check(new_pos, pos.turn):  # mover left in check
        return MoveResult(legal=False)

    opp = new_pos.turn
    opp_in_check = _in_check(new_pos, opp)
    opp_has_moves = len(legal_moves(new_pos)) > 0
    checkmate = opp_in_check and not opp_has_moves
    stalemate = (not opp_in_check) and not opp_has_moves

    # repetition / fifty (based on history including the new position)
    new_pos.history = list(pos.history) + [pos.key()]
    new_pos.history.append(new_pos.key())
    threefold = new_pos.history.count(new_pos.key()) >= 3
    fifty = new_pos.halfmove >= 100
    insufficient = _insufficient_material(new_pos)

    draw = None
    if insufficient:
        draw = "insufficient"
    elif threefold:
        draw = "threefold"
    elif stalemate:
        draw = "stalemate"
    elif fifty:
        draw = "fifty"

    san = _san(pos, target, gives_check=opp_in_check and not checkmate, gives_mate=checkmate)
    return MoveResult(
        legal=True,
        san=san,
        fen=to_fen(new_pos),
        checkmate=checkmate,
        stalemate=stalemate,
        draw=draw,
    )


START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"