# .cba annotation coverage — census and decoder status

Status: 2026-09-06. Fixture: all 27 databases of cbm168
(`/media/michael-g-thomas/sas_mirror/fixt/cbm168/`).
Record framing (validated against `cbh_codec.cpp` / `cbh_game_decoder.cpp`):
per game at the `.cbh` index offset — +10 u32 BE total length, records from
+14; each record = 3B position (BE, 0xffffff = game-wide), 1B type,
2B **BE** length incl. the 6-byte header. (Morphy's annotations.md says the
length is LE — it is big-endian.) Game-wide records precede move records.

## Census (occurrences across the fixture)

| Type | Meaning              | Count | Decoder status |
|-----:|----------------------|------:|----------------|
| 0x02 | text after move      |  7890 | decoded (pre-existing) |
| 0x82 | text before move     |  1345 | decoded (pre-existing) |
| 0x03 | symbols/NAGs         | 11522 | decoded (pre-existing) |
| 0x04 | colored squares      |   538 | decoded (pre-existing) |
| 0x05 | colored arrows       |   772 | decoded (pre-existing) |
| 0x07 | time spent on move   |   611 | **decoded 2026-09-06** → `%emt` MoveInfo |
| 0x16/17 | white/black clock |     0 | **decoded 2026-09-06** → `%clk` MoveInfo (spec'd; no fixture data) |
| 0x18 | critical position    |    13 | **decoded 2026-09-06** → text comment |
| 0x24 | time control         |     6 | **decoded 2026-09-06** → TimeControl tag |
| 0x09 | training/quiz        |   344 | **decoded 2026-09-06** → text comment (see `cba-training-annotation-format.md`) |
| 0x13 | game quotation       |    17 | **decoded 2026-09-06** → citation with ECO + full SAN replay of the quoted game (see `cba-quotation-format.md`) |
| 0x22 | medal                |    75 | decoded to text at the recorded node (including game-wide records) |
| 0x23 | variation color      |     3 | raw payload preserved in text; observed `02 00 00 00`, mode unresolved |
| 0x14 | pawn structure       |     5 | raw payload preserved in text (`03` observed) |
| 0x15 | piece path           |     3 | raw payload preserved in text (`03 36/38` observed) |

Payload validations against real data:
- 0x07 = `h m s flag` (flag 0x1e on a side's first record); e.g. Sinquefield
  game 7 move times match a live-game cadence.
- 0x24 = up to 3×11B series `initTime(4,BE,cs) incr(4,BE,cs) moves(2,BE) type(1)`;
  Sinquefield decodes to `40/7200:3600+30` — the tournament's actual control.
- 0x18 = 1 byte, 1/2/3 = opening/middlegame/endgame.

## Remaining gaps

- Correspondence types 0x19/0x61: absent from the fixture; needs a corr
  database saved by ChessBase.
- 0x13's embedded quoted-game move blob is decoded to numbered SAN and
  cross-validated 17/17 (1,650 plies) against independent python-chess
  replay; see `cba-quotation-format.md`.
- 0x23/0x14/0x15 display semantics remain unresolved. Their full payloads
  now survive import as labeled comments; there is no native color/structure/
  path rendering or binary round-trip support. See `cba-display-annotations.md`.
- 0x22 is **not** redundant with the index: move-level records retain medal
  locations and distinguish tactical from strategic blunders.

## Decoder changes (2026-09-06)

`src/db/cbh/cbh_game_decoder.{h,cpp}`:
- new cases in `getAnnotation`: 0x07 (`decodeTimeSpent`), 0x16/0x17
  (`decodeClock`), 0x18 (`decodeCriticalPosition`), 0x24 (`decodeTimeControl`).
- `traverse()` now emits `putMoveInfo` (was dropping node move info entirely).
- consumer-path `doDecoding` drains game-wide records before
  `consumer.startGame` so the TimeControl tag reaches the written tag section.

Known asymmetry: the CBH *writer* (`cbh_annotation_encoder.cpp`) still emits
only 0x02/0x82/0x03/0x04/0x05 — new types are import-only for now.

The four display-type counts above were rechecked with
`scripts/census_cba_annotations.py`; these count all records across 27 databases,
including duplicated games in the collected and individual tournament databases.
The other type counts have not been recounted in this pass.
