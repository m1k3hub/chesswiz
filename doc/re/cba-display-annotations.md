# Classic CBH display annotations: 0x22 / 0x23 / 0x14 / 0x15

2026-09-06. Import support in `cbh_game_decoder.cpp` uses ordinary comments,
so these annotations survive conversion without requiring a new MoveNode model.
This is not native display support or binary record round-tripping.

## Evidence and corrections

Reproduce the census (zero-based game indices):

```
python3 scripts/census_cba_annotations.py /media/michael-g-thomas/sas_mirror/fixt/cbm168
```

Across 27 databases: 75 medals, 3 variation colors, 5 pawn structures, 3 piece
paths. Counts include duplicated games in collected and tournament databases.
The previous coverage table understated three counts and incorrectly called
medals redundant with the index.

### Medal (0x22)

Four-byte big-endian mask. Low 16 bits use the same meanings as
`Codec::decodeIndex`: best game, decided tournament, model game, novelty,
pawn structure, strategy, tactics, attack, sacrifice, defense, material,
piece play, endgame, tactical blunder, strategical blunder, user.

Unlike index flags, the record identifies a move. For example,
`A22 English Opening-168.cbh`, game 3 has `00000020` at sequence position
19 and `00000080` at 49: strategy and attack at different nodes.
Sinquefield game 23 has `00000028` at position 32: novelty **and** strategy.
The 18 game-wide records (`ffffff`) in Endgame/Tactics carry `00008000`.

The decoder emits e.g. `Medal: Novelty, Strategy`. It preserves unknown high
bits as hexadecimal, retains zero as `Medal: None`, and preserves non-four-byte
payloads verbatim instead of reading into the next record. Tactical and
strategical blunders stay distinct, unlike the aggregated index flag.

### Variation color (0x23)

All three observed payloads are **`02 00 00 00`**, in
`A37 English Opening-168.cbh`, game 2 positions 14 and 233, game 5 position
358. The old claim that the observed payload was `00 B G R` was wrong.
That layout is a historical format description, not a validated interpretation
of these records. A nonzero leading byte might select a mode or palette; this
is unresolved. Do not render these as black or discard the leading byte.

Current output: `Variation color (CBH payload: 02 00 00 00)`.

### Pawn structure (0x14) and piece path (0x15)

Pawn structure payloads are `03`: A22 game 6 position 21, Biel game 30
positions 25/48, and its collected duplicates. Piece paths are `03 38`
(A22 game 6 position 69) and `03 36` (Tournaments game 479 position 92 and
its collected duplicate). There is insufficient evidence to assign meaning
to `03` or establish the square numbering of the second path byte.

Current output: `Pawn structure (CBH payload: 03)` and
`Piece path (CBH payload: 03 36)`. All bytes, including unusual lengths and
empty payloads, are retained at the original node.

## Verification and next step

`make -C src -j4 verify-cbh-write` then
`src/verify_cbh_write --annotations-only` exercises the public tree decoder:
game-wide versus move placement, combined medals, both blunder bits, unknown
bits, zero medals, empty/short/extended payloads, and a subsequent move's medal
and critical-position annotation. The full verifier also passes its existing
CBH round-trip and Chess960 checks.

To establish display semantics, create controlled ChessBase examples changing
one setting at a time: variation palette versus custom color, pawn display
options, and piece paths on known squares. Compare payload changes before
mapping them to rendering behavior. The current sparse records cannot resolve
those choices reliably.
