"""Chess rules, FEN/UCI/SAN validation, PGN parsing, and game fingerprinting.

Uses python-chess when installed, with a complete dependency-free pure-Python
fallback for standard chess and Chess960 so the reference tool works out of the
box in any standard Python 3 environment.
"""

from __future__ import annotations

import hashlib
import os
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

try:
    import chess as _pychess  # type: ignore
    import chess.pgn as _pychess_pgn  # type: ignore
    HAS_PYTHON_CHESS = True
except ImportError:
    _pychess = None
    _pychess_pgn = None
    HAS_PYTHON_CHESS = False

STANDARD_START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

FILES = "abcdefgh"
RANKS = "12345678"
UCI_RE = re.compile(r"^([a-h][1-8])([a-h][1-8])([qrbn])?$")


def _use_pychess() -> bool:
    if os.environ.get("CHESSMEDIA_PURE_PYTHON") == "1":
        return False
    return HAS_PYTHON_CHESS


def fnv1a_64_hex(text: str) -> str:
    """Compute FNV-1a 64-bit lowercase 16-hex digest matching scm_media.cpp."""
    h = 0xCBF29CE484222325
    prime = 0x100000001B3
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * prime) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


def normalize_header_string(tags: Dict[str, str]) -> str:
    """Build normalized 'white|black|event|date|round|result' string."""
    def _clean(key: str) -> str:
        val = tags.get(key, "") or ""
        return val.strip().lower()

    parts = [
        _clean("White"),
        _clean("Black"),
        _clean("Event"),
        _clean("Date"),
        _clean("Round"),
        _clean("Result"),
    ]
    return "|".join(parts)


def compute_fingerprint(
    tags: Dict[str, str],
    start_fen: str,
    mainline_ucis: List[str],
    include_normalized_header: bool = False,
) -> Dict[str, str]:
    """Compute composite game fingerprint (header_hash + move_hash + combined)."""
    norm_header = normalize_header_string(tags)
    header_hash = fnv1a_64_hex(norm_header)
    move_payload = f"{start_fen.strip()}|{' '.join(mainline_ucis)}"
    move_hash = hashlib.sha256(move_payload.encode("utf-8")).hexdigest()[:16]
    res = {
        "header_hash": header_hash,
        "move_hash": move_hash,
        "combined": f"{header_hash}:{move_hash}",
    }
    if include_normalized_header:
        res["normalized_header"] = norm_header
    return res


def fen_board_turn_key(fen: str) -> str:
    """Return the first two FEN fields (piece placement + active color)."""
    parts = fen.strip().split()
    if len(parts) < 2:
        return fen.strip()
    return f"{parts[0]} {parts[1]}"


# ---------------------------------------------------------------------------
# Pure-Python Chess Engine Fallback
# ---------------------------------------------------------------------------

@dataclass
class PureBoard:
    """Minimal complete 8x8 chess board state for standard chess & Chess960 (FEN/Shredder-FEN/X-FEN/SAN/UCI)."""
    # squares[rank 0..7 (1..8)][file 0..7 (a..h)], None or 'P','N','B','R','Q','K','p',...
    squares: List[List[Optional[str]]]
    turn: str  # 'w' or 'b'
    castling: str  # '-' or subset of 'KQkqA-Ha-h'
    ep: str  # '-' or e.g. 'e3'
    halfmove: int
    fullmove: int
    chess960: bool = False
    # Map of castling rook file (0..7) for ('w', 'k'), ('w', 'q'), ('b', 'k'), ('b', 'q')
    castling_rook_files: Dict[Tuple[str, str], int] = field(default_factory=dict)

    def copy(self) -> "PureBoard":
        return PureBoard(
            squares=[row[:] for row in self.squares],
            turn=self.turn,
            castling=self.castling,
            ep=self.ep,
            halfmove=self.halfmove,
            fullmove=self.fullmove,
            chess960=self.chess960,
            castling_rook_files=dict(self.castling_rook_files),
        )

    @staticmethod
    def from_fen(fen: str, chess960: bool = False) -> "PureBoard":
        if not isinstance(fen, str):
            raise ValueError("FEN must be a string")
        parts = fen.strip().split()
        if len(parts) != 6:
            raise ValueError(f"FEN must have exactly 6 fields, got {len(parts)}: {fen!r}")
        placement, turn, castling, ep, half_s, full_s = parts
        ranks = placement.split("/")
        if len(ranks) != 8:
            raise ValueError(f"FEN placement must have 8 ranks, got {len(ranks)}")
        squares: List[List[Optional[str]]] = [[None] * 8 for _ in range(8)]
        w_kings = 0
        b_kings = 0
        w_king_pos: Optional[Tuple[int, int]] = None
        b_king_pos: Optional[Tuple[int, int]] = None
        for r_idx, r_str in enumerate(ranks):
            rank = 7 - r_idx
            file_idx = 0
            for ch in r_str:
                if ch in "12345678":
                    file_idx += int(ch)
                elif ch in "PNBRQKpnbrqk":
                    if file_idx >= 8:
                        raise ValueError(f"Rank {rank + 1} exceeds 8 files in FEN")
                    if ch in "Pp" and rank in (0, 7):
                        raise ValueError(f"Pawn on back rank {rank + 1} in FEN")
                    if ch == "K":
                        w_kings += 1
                        w_king_pos = (rank, file_idx)
                    elif ch == "k":
                        b_kings += 1
                        b_king_pos = (rank, file_idx)
                    squares[rank][file_idx] = ch
                    file_idx += 1
                else:
                    raise ValueError(f"Invalid FEN piece character {ch!r}")
            if file_idx != 8:
                raise ValueError(f"Rank {rank + 1} has {file_idx} squares instead of 8")
        if w_kings != 1 or b_kings != 1 or w_king_pos is None or b_king_pos is None:
            raise ValueError(f"FEN must have 1 white king and 1 black king (got {w_kings}, {b_kings})")
        if turn not in ("w", "b"):
            raise ValueError(f"Invalid active color {turn!r}")

        castling_rook_files: Dict[Tuple[str, str], int] = {}
        if castling != "-":
            if not re.match(r"^[KQkqA-Ha-h]{1,4}$", castling) or len(set(castling)) != len(castling):
                raise ValueError(f"Invalid castling rights {castling!r}")
            if any(ch in "ABCDEFGHabcdefgh" for ch in castling):
                chess960 = True
            for ch in castling:
                is_w = ch.isupper()
                color_c = "w" if is_w else "b"
                back_r = 0 if is_w else 7
                rook_piece = "R" if is_w else "r"
                k_r, k_f = w_king_pos if is_w else b_king_pos
                if k_r != back_r:
                    raise ValueError(f"Castling rights {ch!r} invalid when king is not on back rank")
                if ch in ("K", "k"):
                    if not chess960:
                        if k_f != 4 or squares[back_r][7] != rook_piece:
                            # Standard chess requires king on e-file and rook on h-file
                            if squares[back_r][7] != rook_piece:
                                raise ValueError(f"Missing kingside rook for castling right {ch!r}")
                        castling_rook_files[(color_c, "k")] = 7
                    else:
                        # Outermost rook to the h-side of the king
                        r_files = [f for f in range(k_f + 1, 8) if squares[back_r][f] == rook_piece]
                        if not r_files:
                            raise ValueError(f"No kingside rook found for castling right {ch!r}")
                        castling_rook_files[(color_c, "k")] = r_files[-1]
                elif ch in ("Q", "q"):
                    if not chess960:
                        if squares[back_r][0] != rook_piece:
                            raise ValueError(f"Missing queenside rook for castling right {ch!r}")
                        castling_rook_files[(color_c, "q")] = 0
                    else:
                        # Outermost rook to the a-side of the king
                        r_files = [f for f in range(0, k_f) if squares[back_r][f] == rook_piece]
                        if not r_files:
                            raise ValueError(f"No queenside rook found for castling right {ch!r}")
                        castling_rook_files[(color_c, "q")] = r_files[0]
                else:
                    rf = FILES.index(ch.lower())
                    if squares[back_r][rf] != rook_piece:
                        raise ValueError(f"No rook on file {ch!r} for Shredder-FEN castling right")
                    if rf > k_f:
                        castling_rook_files[(color_c, "k")] = rf
                    elif rf < k_f:
                        castling_rook_files[(color_c, "q")] = rf
                    else:
                        raise ValueError(f"Castling rook file {ch!r} cannot equal king file")

        if ep != "-":
            if not re.match(r"^[a-h][36]$", ep):
                raise ValueError(f"Invalid en-passant square {ep!r}")
            ep_rank = int(ep[1])
            if (turn == "w" and ep_rank != 6) or (turn == "b" and ep_rank != 3):
                raise ValueError(f"En-passant square {ep!r} inconsistent with turn {turn!r}")
        try:
            halfmove = int(half_s)
            fullmove = int(full_s)
        except ValueError as exc:
            raise ValueError("FEN move counters must be integers") from exc
        if halfmove < 0 or fullmove < 1:
            raise ValueError("Invalid FEN move counter bounds")

        board = PureBoard(
            squares=squares,
            turn=turn,
            castling=castling,
            ep=ep,
            halfmove=halfmove,
            fullmove=fullmove,
            chess960=chess960,
            castling_rook_files=castling_rook_files,
        )
        board._sync_castling_str("shredder-fen" if chess960 else "fen")
        # Opponent king cannot already be under attack by the side to move
        opp_color = "b" if turn == "w" else "w"
        opp_king = board.find_king(opp_color)
        if opp_king and board.is_square_attacked(opp_king[0], opp_king[1], by_color=turn):
            raise ValueError("Illegal FEN: side not to move is already in check")
        return board

    def _sync_castling_str(self, fen_encoding: str = "fen") -> str:
        if not self.castling_rook_files:
            self.castling = "-"
            return "-"
        parts: List[str] = []
        if fen_encoding == "shredder-fen" or (self.chess960 and fen_encoding != "xfen" and fen_encoding != "fen"):
            # Shredder-FEN orders h-side to a-side (descending file index: H..A then h..a), matching python-chess
            w_files = sorted(
                [rf for (c, _), rf in self.castling_rook_files.items() if c == "w"],
                reverse=True,
            )
            b_files = sorted(
                [rf for (c, _), rf in self.castling_rook_files.items() if c == "b"],
                reverse=True,
            )
            for rf in w_files:
                parts.append(FILES[rf].upper())
            for rf in b_files:
                parts.append(FILES[rf])
        elif fen_encoding == "xfen":
            for color_c, is_w in (("w", True), ("b", False)):
                back_r = 0 if is_w else 7
                rook_piece = "R" if is_w else "r"
                kpos = self.find_king(color_c)
                kf = kpos[1] if kpos else 4
                for side, std_ch in (("k", "K" if is_w else "k"), ("q", "Q" if is_w else "q")):
                    if (color_c, side) not in self.castling_rook_files:
                        continue
                    rf = self.castling_rook_files[(color_c, side)]
                    if side == "k":
                        outer = [f for f in range(kf + 1, 8) if self.squares[back_r][f] == rook_piece]
                        use_std = bool(outer and outer[-1] == rf)
                    else:
                        outer = [f for f in range(0, kf) if self.squares[back_r][f] == rook_piece]
                        use_std = bool(outer and outer[0] == rf)
                    if use_std:
                        parts.append(std_ch)
                    else:
                        parts.append(FILES[rf].upper() if is_w else FILES[rf])
        else:
            for key, ch in ((("w", "k"), "K"), (("w", "q"), "Q"), (("b", "k"), "k"), (("b", "q"), "q")):
                if key in self.castling_rook_files:
                    if self.chess960 and self.castling_rook_files[key] not in (0, 7):
                        rf = self.castling_rook_files[key]
                        parts.append(FILES[rf].upper() if key[0] == "w" else FILES[rf])
                    else:
                        parts.append(ch)
        s = "".join(parts) if parts else "-"
        self.castling = s
        return s

    def to_fen(self, legal_ep_only: bool = True, fen_encoding: str = "fen") -> str:
        rank_strs = []
        for rank in range(7, -1, -1):
            empty = 0
            s = []
            for file_idx in range(8):
                p = self.squares[rank][file_idx]
                if p is None:
                    empty += 1
                else:
                    if empty:
                        s.append(str(empty))
                        empty = 0
                    s.append(p)
            if empty:
                s.append(str(empty))
            rank_strs.append("".join(s))
        placement = "/".join(rank_strs)
        ep_field = self.ep
        if legal_ep_only and ep_field != "-":
            if not self._has_legal_ep_capture():
                ep_field = "-"
        eff_enc = fen_encoding
        if self.chess960 and fen_encoding == "fen":
            eff_enc = "shredder-fen"
        castling_field = self._sync_castling_str(eff_enc)
        return f"{placement} {self.turn} {castling_field} {ep_field} {self.halfmove} {self.fullmove}"

    def _has_legal_ep_capture(self) -> bool:
        if self.ep == "-":
            return False
        ep_f = FILES.index(self.ep[0])
        ep_r = int(self.ep[1]) - 1
        pawn_r = ep_r - 1 if self.turn == "w" else ep_r + 1
        pawn_ch = "P" if self.turn == "w" else "p"
        for df in (-1, 1):
            pf = ep_f + df
            if 0 <= pf < 8 and 0 <= pawn_r < 8:
                if self.squares[pawn_r][pf] == pawn_ch:
                    uci = f"{FILES[pf]}{pawn_r + 1}{self.ep}"
                    if self._is_uci_legal_After_apply(uci):
                        return True
        return False

    def find_king(self, color: str) -> Optional[Tuple[int, int]]:
        target = "K" if color == "w" else "k"
        for r in range(8):
            for f in range(8):
                if self.squares[r][f] == target:
                    return (r, f)
        return None

    def is_square_attacked(self, r: int, f: int, by_color: str) -> bool:
        is_white = by_color == "w"
        pawn = "P" if is_white else "p"
        knight = "N" if is_white else "n"
        bishop = "B" if is_white else "b"
        rook = "R" if is_white else "r"
        queen = "Q" if is_white else "q"
        king = "K" if is_white else "k"

        # Pawn attacks
        pawn_src_r = r - 1 if is_white else r + 1
        if 0 <= pawn_src_r < 8:
            for df in (-1, 1):
                pf = f + df
                if 0 <= pf < 8 and self.squares[pawn_src_r][pf] == pawn:
                    return True

        # Knight attacks
        for dr, df in ((-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)):
            nr, nf = r + dr, f + df
            if 0 <= nr < 8 and 0 <= nf < 8 and self.squares[nr][nf] == knight:
                return True

        # King attacks
        for dr in (-1, 0, 1):
            for df in (-1, 0, 1):
                if dr == 0 and df == 0:
                    continue
                kr, kf = r + dr, f + df
                if 0 <= kr < 8 and 0 <= kf < 8 and self.squares[kr][kf] == king:
                    return True

        # Orthogonal rays (rook/queen)
        for dr, df in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            cr, cf = r + dr, f + df
            while 0 <= cr < 8 and 0 <= cf < 8:
                p = self.squares[cr][cf]
                if p is not None:
                    if p == rook or p == queen:
                        return True
                    break
                cr += dr
                cf += df

        # Diagonal rays (bishop/queen)
        for dr, df in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
            cr, cf = r + dr, f + df
            while 0 <= cr < 8 and 0 <= cf < 8:
                p = self.squares[cr][cf]
                if p is not None:
                    if p == bishop or p == queen:
                        return True
                    break
                cr += dr
                cf += df

        return False

    def is_in_check(self, color: Optional[str] = None) -> bool:
        c = color or self.turn
        opp = "b" if c == "w" else "w"
        kpos = self.find_king(c)
        if not kpos:
            return False
        return self.is_square_attacked(kpos[0], kpos[1], by_color=opp)

    def _can_castle(self, color: str, side: str) -> Optional[str]:
        if (color, side) not in self.castling_rook_files:
            return None
        is_white = color == "w"
        back_r = 0 if is_white else 7
        opp = "b" if is_white else "w"
        kpos = self.find_king(color)
        if kpos is None or kpos[0] != back_r:
            return None
        kf = kpos[1]
        rf = self.castling_rook_files[(color, side)]
        rook_piece = "R" if is_white else "r"
        if self.squares[back_r][rf] != rook_piece:
            return None
        dst_kf = 6 if side == "k" else 2
        dst_rf = 5 if side == "k" else 3

        # Every square between king's start and destination (inclusive) and between rook's start and destination (inclusive)
        # must be empty except for the castling king and castling rook themselves.
        min_k, max_k = min(kf, dst_kf), max(kf, dst_kf)
        min_r, max_r = min(rf, dst_rf), max(rf, dst_rf)
        for f_chk in set(range(min_k, max_k + 1)) | set(range(min_r, max_r + 1)):
            if f_chk in (kf, rf):
                continue
            if self.squares[back_r][f_chk] is not None:
                return None

        # King cannot start in check, pass through check, or land in check
        for f_chk in range(min_k, max_k + 1):
            if self.is_square_attacked(back_r, f_chk, opp):
                return None

        src_sq = f"{FILES[kf]}{back_r + 1}"
        if self.chess960:
            dst_sq = f"{FILES[rf]}{back_r + 1}"
        else:
            dst_sq = f"{FILES[dst_kf]}{back_r + 1}"
        return f"{src_sq}{dst_sq}"

    def generate_pseudo_legal_ucis(self) -> List[str]:
        moves: List[str] = []
        is_white = self.turn == "w"
        for r in range(8):
            for f in range(8):
                p = self.squares[r][f]
                if p is None:
                    continue
                if is_white and not p.isupper():
                    continue
                if not is_white and not p.islower():
                    continue
                pt = p.upper()
                src_sq = f"{FILES[f]}{r + 1}"
                if pt == "P":
                    step = 1 if is_white else -1
                    start_r = 1 if is_white else 6
                    promo_r = 7 if is_white else 0
                    nr = r + step
                    if 0 <= nr < 8 and self.squares[nr][f] is None:
                        dst_sq = f"{FILES[f]}{nr + 1}"
                        if nr == promo_r:
                            for pr in "qrbn":
                                moves.append(f"{src_sq}{dst_sq}{pr}")
                        else:
                            moves.append(f"{src_sq}{dst_sq}")
                            nr2 = r + 2 * step
                            if r == start_r and self.squares[nr2][f] is None:
                                moves.append(f"{src_sq}{FILES[f]}{nr2 + 1}")
                    for df in (-1, 1):
                        nf = f + df
                        if 0 <= nf < 8 and 0 <= nr < 8:
                            dst_sq = f"{FILES[nf]}{nr + 1}"
                            target = self.squares[nr][nf]
                            is_ep = (self.ep != "-" and dst_sq == self.ep)
                            if (target is not None and target.isupper() != is_white) or is_ep:
                                if nr == promo_r:
                                    for pr in "qrbn":
                                        moves.append(f"{src_sq}{dst_sq}{pr}")
                                else:
                                    moves.append(f"{src_sq}{dst_sq}")
                elif pt == "N":
                    for dr, df in ((-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)):
                        nr, nf = r + dr, f + df
                        if 0 <= nr < 8 and 0 <= nf < 8:
                            target = self.squares[nr][nf]
                            if target is None or target.isupper() != is_white:
                                moves.append(f"{src_sq}{FILES[nf]}{nr + 1}")
                elif pt in ("B", "R", "Q"):
                    dirs = []
                    if pt in ("B", "Q"):
                        dirs.extend([(-1, -1), (-1, 1), (1, -1), (1, 1)])
                    if pt in ("R", "Q"):
                        dirs.extend([(-1, 0), (1, 0), (0, -1), (0, 1)])
                    for dr, df in dirs:
                        cr, cf = r + dr, f + df
                        while 0 <= cr < 8 and 0 <= cf < 8:
                            target = self.squares[cr][cf]
                            if target is None:
                                moves.append(f"{src_sq}{FILES[cf]}{cr + 1}")
                            else:
                                if target.isupper() != is_white:
                                    moves.append(f"{src_sq}{FILES[cf]}{cr + 1}")
                                break
                            cr += dr
                            cf += df
                elif pt == "K":
                    for dr in (-1, 0, 1):
                        for df in (-1, 0, 1):
                            if dr == 0 and df == 0:
                                continue
                            nr, nf = r + dr, f + df
                            if 0 <= nr < 8 and 0 <= nf < 8:
                                target = self.squares[nr][nf]
                                if target is None or target.isupper() != is_white:
                                    moves.append(f"{src_sq}{FILES[nf]}{nr + 1}")
                    for side in ("k", "q"):
                        c_uci = self._can_castle(self.turn, side)
                        if c_uci:
                            moves.append(c_uci)
        return moves

    def _is_castling_move(self, sf: int, sr: int, df: int, dr: int) -> Optional[Tuple[str, int]]:
        piece = self.squares[sr][sf]
        if piece not in ("K", "k") or sr != dr:
            return None
        color = "w" if piece == "K" else "b"
        target = self.squares[dr][df]
        own_rook = "R" if color == "w" else "r"
        if self.chess960 and target == own_rook:
            for side in ("k", "q"):
                if self.castling_rook_files.get((color, side)) == df:
                    return side, df
        if not self.chess960 and abs(df - sf) == 2:
            side = "k" if df == 6 else "q"
            rf = self.castling_rook_files.get((color, side), 7 if side == "k" else 0)
            return side, rf
        return None

    def _apply_unchecked(self, uci: str) -> "PureBoard":
        m = UCI_RE.match(uci)
        if not m:
            raise ValueError(f"Malformed UCI move {uci!r}")
        src, dst, promo = m.group(1), m.group(2), m.group(3)
        sf, sr = FILES.index(src[0]), int(src[1]) - 1
        df, dr = FILES.index(dst[0]), int(dst[1]) - 1
        nxt = self.copy()
        piece = nxt.squares[sr][sf]
        if piece is None:
            raise ValueError(f"No piece on source square {src}")
        is_white = piece.isupper()
        color = "w" if is_white else "b"
        opp_color = "b" if is_white else "w"
        pt = piece.upper()
        target = nxt.squares[dr][df]

        castle_info = self._is_castling_move(sf, sr, df, dr)
        if castle_info is not None:
            side, rf = castle_info
            dst_kf = 6 if side == "k" else 2
            dst_rf = 5 if side == "k" else 3
            own_rook = "R" if is_white else "r"
            nxt.squares[sr][sf] = None
            nxt.squares[sr][rf] = None
            nxt.squares[sr][dst_kf] = piece
            nxt.squares[sr][dst_rf] = own_rook
            nxt.castling_rook_files.pop((color, "k"), None)
            nxt.castling_rook_files.pop((color, "q"), None)
            nxt._sync_castling_str("shredder-fen" if nxt.chess960 else "fen")
            nxt.ep = "-"
            nxt.halfmove = self.halfmove + 1
            if not is_white:
                nxt.fullmove = self.fullmove + 1
            nxt.turn = opp_color
            return nxt

        is_ep_capture = (pt == "P" and dst == self.ep and target is None and sf != df)
        is_capture = (target is not None) or is_ep_capture

        nxt.squares[sr][sf] = None
        if is_ep_capture:
            cap_r = dr - 1 if is_white else dr + 1
            nxt.squares[cap_r][df] = None

        if promo:
            placed = promo.upper() if is_white else promo.lower()
        else:
            placed = piece
        nxt.squares[dr][df] = placed

        # Update castling rights
        if pt == "K":
            nxt.castling_rook_files.pop((color, "k"), None)
            nxt.castling_rook_files.pop((color, "q"), None)
        back_own = 0 if is_white else 7
        if sr == back_own:
            for side in ("k", "q"):
                if nxt.castling_rook_files.get((color, side)) == sf:
                    nxt.castling_rook_files.pop((color, side), None)
        back_opp = 7 if is_white else 0
        if dr == back_opp:
            for side in ("k", "q"):
                if nxt.castling_rook_files.get((opp_color, side)) == df:
                    nxt.castling_rook_files.pop((opp_color, side), None)
        nxt._sync_castling_str("shredder-fen" if nxt.chess960 else "fen")

        # Update ep square
        if pt == "P" and abs(dr - sr) == 2:
            mid_r = (sr + dr) // 2
            nxt.ep = f"{FILES[sf]}{mid_r + 1}"
        else:
            nxt.ep = "-"

        # Clocks and turn
        if pt == "P" or is_capture:
            nxt.halfmove = 0
        else:
            nxt.halfmove = self.halfmove + 1
        if not is_white:
            nxt.fullmove = self.fullmove + 1
        nxt.turn = opp_color
        return nxt

    def _is_uci_legal_After_apply(self, uci: str) -> bool:
        nxt = self._apply_unchecked(uci)
        return not nxt.is_in_check(self.turn)

    def generate_legal_ucis(self) -> List[str]:
        return [u for u in self.generate_pseudo_legal_ucis() if self._is_uci_legal_After_apply(u)]

    def uci_to_san(self, uci: str, legal_moves: Optional[List[str]] = None) -> str:
        if legal_moves is None:
            legal_moves = self.generate_legal_ucis()
        if uci not in legal_moves:
            raise ValueError(f"Illegal UCI move {uci!r} in position {self.to_fen()}")
        src, dst, promo = uci[:2], uci[2:4], uci[4:]
        sf, sr = FILES.index(src[0]), int(src[1]) - 1
        df, dr = FILES.index(dst[0]), int(dst[1]) - 1
        piece = self.squares[sr][sf]
        assert piece is not None
        pt = piece.upper()
        target = self.squares[dr][df]

        castle_info = self._is_castling_move(sf, sr, df, dr)
        if castle_info is not None:
            side, _ = castle_info
            base = "O-O" if side == "k" else "O-O-O"
        elif pt == "P":
            is_ep = (dst == self.ep and target is None and sf != df)
            is_capture = (target is not None) or is_ep
            if is_capture:
                base = f"{src[0]}x{dst}"
            else:
                base = dst
            if promo:
                base += f"={promo.upper()}"
        else:
            is_capture = target is not None
            # Disambiguation among other legal moves of the same piece type to dst
            ambig = []
            for other in legal_moves:
                if other == uci or other[2:4] != dst:
                    continue
                osf, osr = FILES.index(other[0]), int(other[1]) - 1
                if self.squares[osr][osf] == piece:
                    ambig.append((osf, osr))
            disamb = ""
            if ambig:
                same_file = any(osf == sf for osf, _ in ambig)
                same_rank = any(osr == sr for _, osr in ambig)
                if not same_file:
                    disamb = src[0]
                elif not same_rank:
                    disamb = src[1]
                else:
                    disamb = src
            cap_str = "x" if is_capture else ""
            base = f"{pt}{disamb}{cap_str}{dst}"

        nxt = self._apply_unchecked(uci)
        if nxt.is_in_check():
            if not nxt.generate_legal_ucis():
                return base + "#"
            return base + "+"
        return base


# ---------------------------------------------------------------------------
# Public API (uses python-chess when available, or PureBoard fallback)
# ---------------------------------------------------------------------------

def validate_fen(fen: str, variant: str = "standard") -> Tuple[bool, Optional[str]]:
    """Validate a 6-field FEN string. Returns (is_valid, error_reason)."""
    if not isinstance(fen, str) or len(fen.strip().split()) != 6:
        return False, f"FEN must contain 6 space-separated fields: {fen!r}"
    chess960 = (variant == "chess960")
    if _use_pychess():
        try:
            board = _pychess.Board(fen, chess960=chess960)
            status = board.status()
            if status != _pychess.STATUS_VALID:
                return False, f"Invalid chess position status ({status}) for FEN {fen!r}"
            return True, None
        except Exception as exc:
            return False, str(exc)
    else:
        try:
            PureBoard.from_fen(fen, chess960=chess960)
            return True, None
        except Exception as exc:
            return False, str(exc)


def apply_uci_move(
    fen: str,
    uci: str,
    variant: str = "standard",
    fen_encoding: str = "fen",
) -> Tuple[str, str, str]:
    """Apply a UCI move to `fen`.

    Returns `(fen_legal_ep, fen_always_ep, canonical_san)`.
    Raises `ValueError` if `fen` is invalid or `uci` is illegal.
    """
    if not isinstance(uci, str) or not UCI_RE.match(uci):
        raise ValueError(f"Invalid UCI move syntax: {uci!r}")
    chess960 = (variant == "chess960")
    if _use_pychess():
        board = _pychess.Board(fen, chess960=chess960)
        if not board.is_valid():
            raise ValueError(f"Invalid parent FEN: {fen!r}")
        move = _pychess.Move.from_uci(uci)
        if move not in board.legal_moves:
            raise ValueError(f"Illegal move {uci!r} in position {fen!r}")
        san = board.san(move)
        board.push(move)
        if fen_encoding == "xfen":
            shredder_fen_str = board.fen(shredder=True, en_passant="fen")
            pb = PureBoard.from_fen(shredder_fen_str, chess960=chess960)
            fen_legal = pb.to_fen(legal_ep_only=True, fen_encoding="xfen")
            fen_always = pb.to_fen(legal_ep_only=False, fen_encoding="xfen")
        else:
            shredder = (fen_encoding == "shredder-fen") or (chess960 and fen_encoding == "fen")
            fen_legal = board.fen(shredder=shredder, en_passant="legal")
            fen_always = board.fen(shredder=shredder, en_passant="fen")
        return fen_legal, fen_always, san
    else:
        board = PureBoard.from_fen(fen, chess960=chess960)
        legal = board.generate_legal_ucis()
        if uci not in legal:
            raise ValueError(f"Illegal move {uci!r} in position {fen!r}")
        san = board.uci_to_san(uci, legal)
        nxt = board._apply_unchecked(uci)
        return (
            nxt.to_fen(legal_ep_only=True, fen_encoding=fen_encoding),
            nxt.to_fen(legal_ep_only=False, fen_encoding=fen_encoding),
            san,
        )


def fens_equivalent(
    fen_a: str,
    fen_b: str,
    variant: str = "standard",
    fen_encoding: str = "fen",
) -> bool:
    """Compare two 6-field FENs, accepting either legal-only or always-ep convention."""
    if fen_a.strip() == fen_b.strip():
        return True
    pa = fen_a.strip().split()
    pb = fen_b.strip().split()
    if len(pa) != 6 or len(pb) != 6:
        return False
    chess960 = (variant == "chess960")
    if _use_pychess() and fen_encoding != "xfen":
        try:
            ba = _pychess.Board(fen_a, chess960=chess960)
            bb = _pychess.Board(fen_b, chess960=chess960)
            shredder = (fen_encoding == "shredder-fen") or chess960
            return ba.fen(shredder=shredder, en_passant="legal") == bb.fen(shredder=shredder, en_passant="legal")
        except Exception:
            return False
    else:
        try:
            ba = PureBoard.from_fen(fen_a, chess960=chess960)
            bb = PureBoard.from_fen(fen_b, chess960=chess960)
            return ba.to_fen(legal_ep_only=True, fen_encoding=fen_encoding) == bb.to_fen(
                legal_ep_only=True, fen_encoding=fen_encoding
            )
        except Exception:
            return False


def san_to_uci(
    fen: str,
    san_str: str,
    variant: str = "standard",
    fen_encoding: str = "fen",
) -> Tuple[str, str, str]:
    """Resolve SAN string in `fen` to `(uci, next_fen_legal_ep, canonical_san)`."""
    cleaned = san_str.strip().rstrip("!?")
    chess960 = (variant == "chess960")
    if _use_pychess():
        board = _pychess.Board(fen, chess960=chess960)
        move = board.parse_san(cleaned)
        canon_san = board.san(move)
        uci = move.uci()
        board.push(move)
        if fen_encoding == "xfen":
            pb = PureBoard.from_fen(board.fen(shredder=True, en_passant="fen"), chess960=chess960)
            next_fen = pb.to_fen(legal_ep_only=True, fen_encoding="xfen")
        else:
            shredder = (fen_encoding == "shredder-fen") or (chess960 and fen_encoding == "fen")
            next_fen = board.fen(shredder=shredder, en_passant="legal")
        return uci, next_fen, canon_san
    else:
        board = PureBoard.from_fen(fen, chess960=chess960)
        legal = board.generate_legal_ucis()
        norm_target = cleaned.replace("0-0-0", "O-O-O").replace("0-0", "O-O").rstrip("+#")
        for uci in legal:
            cand_san = board.uci_to_san(uci, legal)
            if cand_san == cleaned or cand_san.rstrip("+#") == norm_target:
                nxt = board._apply_unchecked(uci)
                return uci, nxt.to_fen(legal_ep_only=True, fen_encoding=fen_encoding), cand_san
        raise ValueError(f"Cannot resolve SAN {san_str!r} in position {fen!r}")


def find_moves_between_squares(
    fen: str,
    from_sq: str,
    to_sq: str,
    promo_hint: Optional[str] = None,
    variant: str = "standard",
) -> Tuple[str, str, str, bool]:
    """Find legal move from `from_sq` to `to_sq` in `fen`.

    Returns `(uci, next_fen, san, inferred_promotion)`.
    """
    prefix = f"{from_sq}{to_sq}"
    if _use_pychess():
        board = _pychess.Board(fen, chess960=(variant == "chess960"))
        candidates = [m.uci() for m in board.legal_moves if m.uci().startswith(prefix)]
    else:
        board = PureBoard.from_fen(fen, chess960=(variant == "chess960"))
        candidates = [u for u in board.generate_legal_ucis() if u.startswith(prefix)]

    if not candidates:
        raise ValueError(f"No legal move from {from_sq} to {to_sq} in {fen!r}")
    inferred_promo = False
    if len(candidates) == 1:
        chosen = candidates[0]
    else:
        if promo_hint and f"{prefix}{promo_hint}" in candidates:
            chosen = f"{prefix}{promo_hint}"
        elif f"{prefix}q" in candidates:
            chosen = f"{prefix}q"
            inferred_promo = (promo_hint is None)
        else:
            chosen = candidates[0]
            inferred_promo = True

    fen_legal, _, san = apply_uci_move(fen, chosen, variant=variant)
    return chosen, fen_legal, san, inferred_promo


# ---------------------------------------------------------------------------
# PGN Parser (tags + recursive variation tree)
# ---------------------------------------------------------------------------

@dataclass
class PgnNodeData:
    id: str
    parent_id: Optional[str]
    uci: Optional[str]
    san: Optional[str]
    fen: str
    main_child_id: Optional[str] = None
    children_ids: List[str] = field(default_factory=list)
    comment: Optional[str] = None
    nags: List[int] = field(default_factory=list)


@dataclass
class ParsedPgnGame:
    tags: Dict[str, str]
    start_fen: str
    setup: bool
    nodes: List[PgnNodeData]


_PGN_TAG_RE = re.compile(r'^\s*\[\s*([A-Za-z0-9_]+)\s+"((?:\\.|[^"\\])*)"\s*\]\s*$')
_PGN_TOKEN_RE = re.compile(
    r"\{[^}]*\}|;[^\n]*|\(|\)|\$[0-9]+|1-0|0-1|1/2-1/2|\*|[0-9]+\.+(?:\s*)?|[A-Za-z0-9_+#=:-]+[!?]*"
)


def parse_pgn_text(pgn_text: str) -> List[ParsedPgnGame]:
    """Parse one or more PGN games into ChessMedia node trees."""
    lines = pgn_text.splitlines()
    raw_games: List[Tuple[Dict[str, str], str]] = []
    cur_tags: Dict[str, str] = {}
    cur_moves: List[str] = []
    in_moves = False

    for line in lines:
        m = _PGN_TAG_RE.match(line)
        if m:
            if in_moves and (cur_tags or "".join(cur_moves).strip()):
                raw_games.append((cur_tags, "\n".join(cur_moves)))
                cur_tags = {}
                cur_moves = []
                in_moves = False
            key, val = m.group(1), m.group(2).replace('\\"', '"').replace("\\\\", "\\")
            cur_tags[key] = val
        else:
            if line.strip():
                in_moves = True
            if in_moves:
                cur_moves.append(line)

    if cur_tags or "".join(cur_moves).strip():
        raw_games.append((cur_tags, "\n".join(cur_moves)))

    results: List[ParsedPgnGame] = []
    for tags, movetext in raw_games:
        start_fen = tags.get("FEN", STANDARD_START_FEN).strip()
        setup = (start_fen != STANDARD_START_FEN) or (tags.get("SetUp") == "1")
        nodes: List[PgnNodeData] = [
            PgnNodeData(id="n0", parent_id=None, uci=None, san=None, fen=start_fen)
        ]
        node_map: Dict[str, PgnNodeData] = {"n0": nodes[0]}
        counter = 0

        tokens = _PGN_TOKEN_RE.findall(movetext)
        cur_id = "n0"
        stack: List[str] = []

        for tok in tokens:
            if tok.startswith("{"):
                comment_txt = tok[1:-1].strip()
                if comment_txt:
                    existing = node_map[cur_id].comment
                    node_map[cur_id].comment = f"{existing} {comment_txt}".strip() if existing else comment_txt
            elif tok.startswith(";"):
                continue
            elif tok == "(":
                parent_id = node_map[cur_id].parent_id
                if parent_id is None:
                    parent_id = "n0"
                stack.append(cur_id)
                cur_id = parent_id
            elif tok == ")":
                if stack:
                    cur_id = stack.pop()
            elif tok.startswith("$"):
                nag = int(tok[1:])
                if 1 <= nag <= 255:
                    node_map[cur_id].nags.append(nag)
            elif tok in ("1-0", "0-1", "1/2-1/2", "*"):
                continue
            elif re.match(r"^[0-9]+\.+", tok):
                continue
            else:
                parent_node = node_map[cur_id]
                uci, next_fen, canon_san = san_to_uci(parent_node.fen, tok)
                counter += 1
                new_id = f"n{counter}"
                new_node = PgnNodeData(
                    id=new_id,
                    parent_id=cur_id,
                    uci=uci,
                    san=canon_san,
                    fen=next_fen,
                )
                nodes.append(new_node)
                node_map[new_id] = new_node
                if parent_node.main_child_id is None:
                    parent_node.main_child_id = new_id
                parent_node.children_ids.append(new_id)
                cur_id = new_id

        results.append(ParsedPgnGame(tags=tags, start_fen=start_fen, setup=setup, nodes=nodes))
    return results
