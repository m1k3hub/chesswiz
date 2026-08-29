#!/usr/bin/env python3
"""Python port of the Move16 decoder (mirrors src/db/2cbh/2cbh_move16.cpp).

Loads the packed decode tables from the generated C++ source and replays a
.2cbg record mainline through python-chess as UCI moves.

This is for reverse-engineering verification only; the production decoder
is the C++ implementation in src/db/2cbh/.
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE_CPP = os.path.join(HERE, "..", "src", "db", "2cbh", "cb2_move16_table.cpp")

_special = {
    "Move16_None": 0xfffb,
    "Move16_GameStart": 0xfffc,
    "Move16_Marker": 0xfffd,
    "Move16_Terminator": 0xffff,
}

def _load_tables():
    cache = getattr(_load_tables, "_cache", None)
    if cache:
        return cache
    src = open(TABLE_CPP, "r").read()
    def grab(name):
        m = re.search(name + r"\[?(\d*)\]?\s*=\s*\{(.*?)\};", src, re.S)
        body = m.group(2)
        return [int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", body)]
    packed = grab("kPackedTable")
    side = grab("kSideTable")
    cache = (packed, len(packed), len(side) // 2)
    _load_tables._cache = cache
    return cache

def decode_move16(code):
    packed, psize, ssize_unused = _load_tables()
    side_key = getattr(decode_move16, "_side", None)
    if side_key is None:
        src = open(TABLE_CPP, "r").read()
        m = re.search(r"kSideTable\[\d*\]\s*=\s*\{(.*?)\};", src, re.S)
        side = [int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", m.group(1))]
        # decode_move16("side") = {code: w1}
        smap = {}
        for i in range(len(side) // 2):
            smap[side[2 * i] >> 16] = (side[2 * i] & 0xffff) | (side[2 * i + 1] << 16)
        decode_move16._side = smap
        side_key = smap
    if code == 0 or code >= psize:
        return None
    w = packed[code]
    d = {
        "from": w & 0x3f,
        "to": (w >> 6) & 0x3f,
        "piece": (w >> 12) & 0xf,
        "captured": (w >> 16) & 0xf,
        "hasWord1": bool((w >> 20) & 1),
        "word1From": 0, "word1To": 0, "word1Piece": 0, "word1Cap": 0,
    }
    if d["hasWord1"]:
        w1 = side_key.get(code)
        if w1 is not None:
            d["word1From"] = w1 & 0x3f
            d["word1To"] = (w1 >> 8) & 0x3f
            d["word1Piece"] = (w1 >> 16) & 0xff
            d["word1Cap"] = (w1 >> 24) & 0xff
        else:
            d["hasWord1"] = False
    return d

def _sq_name(sq):
    return "abcdefgh"[sq >> 3] + "12345678"[sq & 7]

_promo_letter = {2: 'q', 3: 'n', 4: 'b', 5: 'r'}

def cbg_uci(cbg_data, off):
    """Replay the mainline of one .2cbg record at byte offset `off`.

    Returns (uci_list, moves, terminated, ok).  uci_list entries are
    'e2e4'/'e7e8q'/'e1g1' strings ready for python-chess (standard chess
    records only, type == 1).
    """
    dataSize = int.from_bytes(cbg_data[off + 8:off + 12], "little")
    typ = int.from_bytes(cbg_data[off + 0x18:off + 0x1a], "little")
    uci, moves, terminated = [], 0, False
    if typ != 1:
        return uci, moves, terminated, False
    data = cbg_data[off + 0x1a:off + 0x1a + dataSize]
    for j in range(len(data) // 2):
        code = int.from_bytes(data[2 * j:2 * j + 2], "little")
        if code == _special["Move16_GameStart"]:
            continue
        if code == _special["Move16_Terminator"]:
            terminated = True
            break
        if code >= _special["Move16_None"]:
            continue
        d = decode_move16(code)
        if d is None:
            return uci, moves, terminated, False
        mv = _sq_name(d["from"]) + _sq_name(d["to"])
        if d["hasWord1"] and d["piece"] in (6, 14) \
           and d["word1From"] == d["to"] == d["word1To"]:
            mv += _promo_letter.get(d["word1Piece"] & 7, "")
        uci.append(mv)
        moves += 1
    return uci, moves, terminated, True

def replay(uci_list):
    """Replay UCI strings on a fresh python-chess board.

    Castling arrives as the king double-step ('e1g1'), which python-chess
    accepts for standard chess.  En passant needs no extra info.
    Returns (board, legal_move_count) or (None, fail_at_ply).
    """
    import chess
    board = chess.Board()
    for i, mv in enumerate(uci_list):
        try:
            m = chess.Move.from_uci(mv)
        except ValueError:
            return None, i
        if m not in board.legal_moves:
            return None, i
        board.push(m)
    return board, len(uci_list)

if __name__ == "__main__":
    _load_tables()
    print(f"packedTable={len(_load_tables()[0])} entries")
    decode_move16(1)  # force side-table load
    print(f"sideTable={len(decode_move16._side)} entries")
    for code in (0x0001, 0xe14d):
        print(f"code {code:#06x}:", decode_move16(code))