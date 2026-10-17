# .cbtt (ChessBase tournament extras) — format notes

Status: v2 layout solved and fixture-verified (2026-09-06).
Sources: Morphy (Yarin78) cbh-format/tournaments.md, corrected and validated
against all 27 `.cbtt` files in the cbm168 fixture
(`/media/michael-g-thomas/sas_mirror/fixt/cbm168/`).

## Layout

Header (32 bytes):

| Offset | Size | Type      | Field |
|-------:|-----:|-----------|-------|
| 0      | 4    | u32 LE    | version (2 observed; 3 documented) |
| 4      | 4    | u32 LE    | record size (61 if v2, 65 if v3) |
| 8      | 4    | u32 LE    | index of last tournament stored (0-based) |
| 12     | 20   | —         | uninitialized process garbage (ASCII fragments of unrelated strings) |

Records follow sequentially; record *i* belongs to tournament index *i* in the
`.cbt`. Records are added lazily, so the file usually holds fewer records than
the `.cbt` has tournaments.

Record (61 bytes in v2; v3 appends a 4-byte end date at offset 61):

| Offset | Size | Type      | Field |
|-------:|-----:|-----------|-------|
| 0      | 8    | double **BE** | latitude |
| 8      | 8    | double **BE** | longitude |
| 16     | 10   | —         | unknown (all zero in fixture) |
| 26     | 1    | u8        | constant 7 |
| 27     | 10   | —         | unknown (all zero) |
| 37     | 1    | u8        | constant 7 |
| 38     | 10   | —         | unknown (all zero) |
| 48     | 1    | u8        | constant 7 |
| 49     | 1    | —         | unknown (zero) |
| 50     | 10   | u8[10]    | tiebreak rules, up to 4 (0x01 = unset filler) |
| 60     | 1    | u8        | count of tiebreak rules |

## Corrections to the public (Morphy) documentation

- **Coordinates are big-endian doubles**, not little-endian. LE decoding yields
  denormals; BE decoding of the fixture yields real host cities:
  Tbilisi (41.702, 44.807), Reykjavik (64.115, −21.853),
  Gothenburg (57.696, 11.973), Tallinn (59.423, 24.719).
- Header @8 verified as `record count − 1` across all 27 files.
- Const-7 bytes at record offsets 26/37/48 hold in 42/42 records.
- Observed tiebreak rule ids: 0x14, 0x15 (semantics not yet mapped;
  enumerating them needs files saved from a live ChessBase with chosen
  tiebreak settings).

## Open items

- v3 (65-byte) sample with the end-date field — none in the fixture.
- Tiebreak rule id enumeration.
- Whether scidb should surface lat/long (no model field today); parsing is
  trivial once a consumer exists.
