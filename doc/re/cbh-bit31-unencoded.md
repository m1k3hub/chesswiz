# Classic CBH: the bit-31 "unencoded" game flag

## Background

The classic (non-2CBH) `.cbg` game-data stream begins each game with a
4-byte header word. Bit 31 of that word, when set, means the following
data is stored *unencoded* (plain text), not run through the standard
LUT move-encoding. This is not encryption (that's the separate `.cbz`
DES archive) - it's ChessBase choosing a directly-readable text layout
for certain record types.

`Codec::startDecoding()` (`src/db/cbh/cbh_codec.cpp`) has always thrown
`DecodingFailedException` when it sees bit 31 set, with a long-standing
comment noting the format was unparsed and citing an external example
("Big2010, #1964391, Giffard, Nicolas - Castagliola, Marina") that is
not available on this machine to inspect.

## What "unencoded" turned out to mean

Scanned every classic `.cbh`/`.cbg` pair available in this environment:
`media-console/fixture/*.cbh`, `/media/michael-g-thomas/sas_mirror/fixt/cbm168/*.cbh`,
and `opening-report/tests/fixtures/twic1639.cbh` - 30 databases, ranging
from single-game files to a 717-game collection.

For each, the classic index (46-byte records starting at file offset 46,
per `Codec::readHeader`/`Codec::decodeIndex`) was scanned for records
whose corresponding `.cbg` game-offset word has bit 31 set. Result:

**100+ bit-31 records found across 25 of the 30 databases. Every single
one is a guiding-text record** (index byte 0 bit `0x2` set, i.e.
`GameInfo::isGuidingText()` true) - confirmed by cross-referencing each
hit's record type before checking the `.cbg` word.

This matches `Codec::decodeGuidingTextBody()`, which already reads this
exact same 8-byte header (`size = bstrm.uint32(); if ((size & 0x80000000)
== 0) return; // data is encoded`) and parses the *text* that follows -
a title/body structure, not chess moves. That function predates this
investigation and was already correct; it was added independently of
the `startDecoding()` TODO and nobody had connected the two.

## What was and wasn't fixed

- **Guiding-text title/body decode**: already correct, unchanged.
- **`Codec::doDecoding(BlockFileReader*, GameInfo const&, uint16_t*, ...)`**
  (the move-list accessor) previously called `startDecoding()`
  unconditionally, which throws for every guiding-text record. The
  caller (`Database::loadGame`) already wraps this in `catch (...) {
  return 0; }`, so this was never a visible bug (no crash), just an
  avoidable throw/catch cycle on every guiding-text move-list lookup.
  Fixed: added an `info.isGuidingText()` early-return before the call,
  matching the existing branch in the sibling
  `Codec::doDecoding(GameData&, GameInfo&, ...)` overload, which already
  checked `isGuidingText()` first.
- **A real "plain" (non-guiding-text) bit-31 game** - actual chess moves
  stored unencoded rather than guiding-text prose - has **no attested
  example in any fixture available here**. Zero of the 100+ real bit-31
  records found are anything but guiding texts. Per this project's policy
  against shipping unverified decodes (see `cba-quotation-format.md`,
  "Attempted and reverted"), no decoder was written for this un-attested
  case.

## Next step, if this is ever revisited

Find or reconstruct a real fixture with a non-guiding-text bit-31 game
(the cited "Big2010" database, if it can be located, or by asking
ChessBase 26 under Wine to produce one deliberately) before writing a
decoder - the guiding-text header format was ultimately simple, but
without real data to check "plain unencoded moves" against, a decoder
here would be exactly the kind of unverified guess this project avoids.
