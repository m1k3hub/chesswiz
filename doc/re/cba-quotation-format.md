# .cba annotation type 0x13 (game quotation) — header solved

Status: 2026-09-06. Header grammar validated on all 17 real records in the
cbm168 fixture, cross-checked against the actual historical games they
quote (players, tournament, site, date, round, result all match public
record). No public documentation of this type exists; Morphy's
`annotations.md` lists it as "not done yet".

Method: extracted all 17 raw payloads, hand-derived the player-name framing
by byte inspection, then had `agy` extend it to the full header and
cross-validate every field against the real, identifiable historical games
these quotations cite (see evidence table below) — using
`src/db/cbh/cbh_decoder.cpp` as a reference for the expected shape of the
embedded quoted-game move blob.

## Grammar

Record payload (after the 6-byte `.cba` annotation header):

```
u16 BE   total_length       == the annotation length (redundant framing check)
u16 BE   name_count         always 2 (white, black)

-- white name:
u16 BE   lang               0 = English/default in the fixture
u8       len
bytes[len]  name             "Last,First"

-- black name (note: only a 1-byte language field here, unlike white's 2-byte one):
u8       lang
u8       len
bytes[len]  name

u8       flag               unknown, 0 in the fixture
u16 BE   white_elo          0 if unrated / pre-Elo era
u16 BE   black_elo
u16 BE   eco_raw            same packing as the classic .cbh index ECO field:
                             eco_index = (eco_raw >> 7) & 0x1ff (see convertEco
                             in cbh_codec.cpp - independently rediscovered here)

u8       event_len
bytes[event_len]  event_name

u8       site_lang
u8       site_len
bytes[site_len]  site_name

u16 BE   pad
3 bytes BE  packed_date     year = v>>9, month = (v>>5)&0xf, day = v&0x1f
                            (identical packing to setDate in cbh_codec.cpp)
u8       time_mode
u8       tournament_type    2=Match, 3=Tournament(RR), 4=Swiss (observed)
u16 BE   nation_id
u16 BE   category
u16 BE   total_rounds
u8       subround
u8       round
u8       result             0=0-1, 1=1/2-1/2, 2=1-0, 3=*
u16 BE   medals

-- remainder of the record: the quoted game's own move stream
```

Two formulas in this header (ECO packing, date packing) are byte-identical
to formulas already implemented independently for the classic `.cbh` index
(`convertEco`/`setDate` in `cbh_codec.cpp`) — strong internal corroboration
that the header layout hypothesis is correct, since they were derived from
this record type's data alone before comparing to the existing code.

## Historical cross-check (17/17 records)

Every quotation resolves to a real, identifiable game with the correct
date/result, e.g.:

| Players | Event / Site | Date | Round | Result |
|---|---|---|---|---|
| Kan – Capablanca | Moscow | 1936.05.14 | — | 0-1 |
| Karpov – Korchnoi | World Championship 29th, Baguio City | 1978.07.18 | 32 | 1-0 |
| Karpov – Kasparov | World Championship 32th-KK2, Moscow | 1985.09.03 | 2 | 1/2-1/2 |
| Carlsen – Anand | World Championship, Sochi | 2014.11.08 | 11 | 1-0 |
| Caruana – Carlsen | Norway Chess 3rd, Stavanger | 2015.06.16 | 2 | 1-0 |
| Polgar – Topalov | FIDE-Wch, San Luis | 2005.09.28 | 6 | 0-1 |
| Steinitz – Lasker | St Petersburg 1895/96 | 1895.12.13 | 4 | 1-0 |

(Full 17-record table in the session's scratch artifacts.)

## The embedded move blob (not decoded)

The quoted game's own moves follow the header directly, with no separate
4-byte `.cbg`-style framing (flags byte + 3-byte size) — the boundary is
just "rest of the annotation record". The first bytes of the blob are
**static across independent games sharing an opening** — e.g. every record
starting `1.e4 e5 2.Nf3 Nc6` begins with the identical 4 bytes `df 93 6c d8`
regardless of which quoted game it is — which is exactly what the existing
per-ply rolling cipher (`cbh_count_cipher.*`, keyed by move count from a
fresh start) would produce if the quoted game's cipher state is reset to
the beginning, i.e. this blob is presumed to reuse the standard `.cbg`
move encoding starting fresh (not the .cbg file's own running count from
elsewhere in that file).

This was not implemented in this pass: replaying it would need constructing
a `GameDecoder` over a synthetic stream (real blob bytes prefixed with a
synthetic all-zero 4-byte flags/startpos word, since `startDecoding()`
expects that framing) and converting the resulting move indices to SAN.
The header alone already delivers the practical value (identifying what
game is being cited); decoding the actual quoted moves is a clean,
separable follow-up.

### Attempted and reverted (2026-09-06)

Tried exactly the approach above: nested `GameDecoder` over
`[00 00 00 00] + blob`, looping `decodeMove()` (mainline only,
`skipVariations=true`), printing SAN via `Board::prepareForPrint` +
`Move::printSAN`. It ran without crashing (after fixing a `printSAN`
precondition — needs `prepareForPrint` called on the **pre-move** board,
captured before `decodeMove()` mutates the decoder's position) but produced
**the same single move, `1.g4`, for every one of the 17 records** regardless
of actual content, then immediately failed to decode a second move. Since
17 structurally distinct blobs cannot legitimately all start with the exact
same first move, this is a framing bug, not real data — most likely the
synthetic 4-byte prefix is wrong (either the wrong length, or real `.cbg`
per-game data has a different/no such prefix and `startDecoding()`'s first
`uint32()` read needs to consume something else), or the cipher's initial
`count` seed isn't actually 0 for an embedded quotation. Reverted rather
than ship plausible-looking wrong data. Next attempt should compare a
**known real quoted game's expected opening** (e.g. record 11 is
Caruana–Carlsen, Berlin Defence, so bytes should decode to `1.e4 e5 2.Nf3
Nc6 3.Bb5`) against the raw blob bytes/cipher output byte-by-byte to find
the actual framing offset, or use Ghidra to trace CBase26's own quotation-
rendering code path.

## Decoder implementation (2026-09-06)

`src/db/cbh/cbh_game_decoder.{h,cpp}`: `decodeQuotation()` parses the header
fields (skipping the embedded move blob) and renders:

```
Quoted game: <white> - <black>, <event>, <site> (<date>), round <n>, <result>
```

as a post-move text comment, via the same `appendTextAnnotation` path used
for 0x18/0x09. Player/event/site strings are decoded through the game's
UTF-8 codec (consistent with how ordinary comments are decoded) since names
may contain diacritics not present in the fixture sample. Fails safe on any
grammar mismatch: skips the record without desynchronizing the rest of the
annotation stream.

Verified: all 17 fixture records produce exactly one `Quoted game:` comment
each (17/17, matching the census); text output cross-checked by hand against
real chess history; `verify_cbh_write` round-trip passed; app suite 31/31.

## Open items

- The quoted game's own moves are parsed structurally (offset/length known)
  but not decoded to SAN — a real but separable follow-up.
- ECO/nation/category/tournament-type/medals fields are decoded but not
  rendered in the comment text (kept the change minimal); available in the
  header if a future pass wants richer output.
