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
| 0x13 | game quotation       |    17 | skipped — embedded quoted-game header+text; RE target |
| 0x22 | medal                |    48 | skipped — duplicates the medal bits already read from the .cbh index |
| 0x23 | variation color      |     3 | skipped — payload `00 B G R`; no scidb model equivalent |
| 0x14 | pawn structure       |     3 | skipped — 1-byte payload (`03` observed) |
| 0x15 | piece path           |     2 | skipped — 2-byte payload (`03 36/38` observed) |

Payload validations against real data:
- 0x07 = `h m s flag` (flag 0x1e on a side's first record); e.g. Sinquefield
  game 7 move times match a live-game cadence.
- 0x24 = up to 3×11B series `initTime(4,BE,cs) incr(4,BE,cs) moves(2,BE) type(1)`;
  Sinquefield decodes to `40/7200:3600+30` — the tournament's actual control.
- 0x18 = 1 byte, 1/2/3 = opening/middlegame/endgame.

## RE targets with fixture data

- **0x13 quotation** (17 samples): begins with a mini header (two
  length-prefixed player names, date/site fields) then game text.
- Correspondence types 0x19/0x61: absent from the fixture; needs a corr
  database saved by ChessBase.

## Decoder changes (2026-09-06)

`src/db/cbh/cbh_game_decoder.{h,cpp}`:
- new cases in `getAnnotation`: 0x07 (`decodeTimeSpent`), 0x16/0x17
  (`decodeClock`), 0x18 (`decodeCriticalPosition`), 0x24 (`decodeTimeControl`).
- `traverse()` now emits `putMoveInfo` (was dropping node move info entirely).
- consumer-path `doDecoding` drains game-wide records before
  `consumer.startGame` so the TimeControl tag reaches the written tag section.

Known asymmetry: the CBH *writer* (`cbh_annotation_encoder.cpp`) still emits
only 0x02/0x82/0x03/0x04/0x05 — new types are import-only for now.
