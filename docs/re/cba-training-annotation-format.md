# .cba annotation type 0x09 (training question / quiz) — solved

Status: 2026-09-06. Byte-exact grammar, validated against all 344 real
records in the cbm168 fixture (168Endgame/168Training/168Tactics/168Strategy)
with **zero parse failures and zero leftover bytes**. No public documentation
of this type exists (Morphy's `annotations.md` lists it as "not done yet").

Method: extracted all 344 raw payloads with game/position context, replayed
each game with python-chess to get serialized move squares, wrote a grammar
hypothesis, then had `agy` write an independent parser and validate it
record-by-record against move data (100% match) — see scratchpad artifacts
(not committed: `payloads.txt`, `moves.txt`, `parse_t09.py`). Ghidra
corroboration was not pursued since the data-driven validation was already
exhaustive and every decoded question reads as coherent chess prose.

## Grammar

Record payload (after the 6-byte `.cba` annotation header):

```
u16 LE   version              (always 1)
u8       question_type        1 = move-entry, 2 = multiple-choice
u16 LE   data_length          = payload length - 3 (redundant framing check)
u32 LE   allotted_time        seconds (5..600 observed)
u16 LE   max_points           = max(candidate/choice points); redundant

string_set  question          almost always present (344/344)
string_set  wrong_feedback    default feedback shown on any wrong move (44/344)
string_set  hint              (116/344)
string_set  (unused)          always empty (0/344 non-empty)

if question_type == 1:        # move-entry
    u8       count
    count * {
        u8   from_square      column-major (file*8+rank), as in .cbg/.cba marks
        u8   to_square        column-major
        s16 BE points         0 = wrong answer, >0 = correct/partial credit
        string_set feedback   per-candidate text (92.1% of candidates have it)
    }

if question_type == 2:        # multiple-choice
    u8       count            2-4 observed
    count * {
        s8   points
        string_set text       the choice's prose
        string_set feedback   shown after picking this choice
    }
```

`string_set`:
```
u16 LE count
count * {
    u16 LE lang_or_kind
    u16 LE length
    bytes[length]
}
```
`lang_or_kind`: 0 = English (cp1252), 1 = German, other small values presumably
further UI languages; **7 = packed 3-byte board arrows** `(color, from, to)`,
**8 = packed 2-byte colored squares** `(color, square)` — ChessBase reuses the
string-set container to carry per-candidate board graphics alongside text.
56 arrow instances and 38 colored-square instances observed in the fixture.

## Validated statistics (344/344 records)

- question_type: 1 (move-entry) 310/344 (90.1%), 2 (MCQ) 34/344 (9.9%)
- max_points field matches `max(candidate points)` on 344/344 (100%)
- 480 total candidate moves across the 310 move-entry records; 25.0% are
  0-point (wrong) answers with refutation text, 75.0% award partial/full credit
- allotted_time correlates with max_points (harder questions get more time):
  1 pt → avg 83.6s, 3 pt → avg 284.0s, 10 pt (168Strategy only) → fixed 300s
- attach position: the annotation's `pos` field is the serialized move index
  as usual; whether the first candidate equals game move P or P+1 depends on
  whether the position already sits inside a variation (RAV-flattened index
  shift), not on any property of the training record itself

## Semantic spot-check

168Endgame game 20, pos 152 — "How did White cash in on his passed pawn?"
candidates `b4-d4` (3 pts, matches the game's actual move, "the black rook
can no longer stop the a-pawn"), `a6-a7` (0 pts, "fails to the intermediate
check on e6"), `e7-h4` (0 pts, no feedback). Coherent, correct endgame
instruction — confirms the grammar rather than an accidental byte-fit.

## Decoder implementation (2026-09-06)

`src/db/cbh/cbh_game_decoder.{h,cpp}`: `decodeTraining()` parses the full
grammar and `skipStringSet()` reads/discards or captures one string set
(English preferred, else first entry; language codes 7/8 — board graphics —
are skipped, not rendered, in this first pass). The result is formatted as
readable text and appended via `appendTextAnnotation` (post-move comment):

```
Training: <question>
- <from>-<to> (<points> pt): <feedback>
...
```

There is no scidb model for an interactive quiz (candidate moves, points,
per-candidate feedback, timed sessions), so this makes the content visible
as a comment rather than silently dropping it, matching the precedent set
for 0x07/0x16/0x17/0x18/0x24 in the prior session. Grammar mismatches
(unexpected future variants) fail safe: the record is skipped without
desynchronizing the rest of the annotation stream.

Verified: all 344 fixture records produce exactly one `Training:` comment
each (344/344, matching the census exactly — no desync, no loss); PGN export
of 168Endgame game 20 reproduces the question and all three candidates with
correct points and feedback text; `verify_cbh_write` round-trip passed; full
app suite 31/31.

## Open items

- Board graphics (arrows/colored squares, lang 7/8 in feedback string sets)
  are decoded structurally but not rendered — they'd need to attach to a
  hypothetical post-candidate-move position, which has no clean node to hang
  off in the current model.
- Multi-language slots beyond English/German (lang codes other than 0/1)
  have no fixture examples to confirm.
- Writer-side encoding (round-trip through CBH export) is not implemented;
  training annotations are import/display only, like 0x07/0x16/0x17/0x18/0x24.
