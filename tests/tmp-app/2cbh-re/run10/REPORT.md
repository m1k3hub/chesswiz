# Run 10B report — 2026-10-27

Status: implemented and tested the measured fields; the entire brief is not
fully resolved. Ghidra HTTP and Wine/X were available in this pass.

## App acceptance

- All 3 Tcl app export tests pass under xvfb (test-app-final2.log). They now
  check multilingual titles, result subtype and good-game tags through the
  codec, in addition to UTF-8 players, variations, teams, setup and reopen.
- Preserved the app-generated three-game export in ignored dbs/app-final.
  CBase26 opens/reopens it without an integrity page. The four binary files
  stay SHA-256-identical (final-before.sha256). Result subtype 1 displays as
  0-0 for an unknown result; the good-game bit displays as Top Game.
- Screenshots: shots/app-first-clean.png, app-reopened.png,
  app-final-game.png, and final-open/reopen captures when present.
- Direct board loading and the writer's title display in CBase26 are NOT
  established. Double-clicks did not open a board. Adding copied or empty
  .2lcd/.2lgd sidecars enabled namebase tabs, but the empty caches had no
  Game Tag entries. These experiments are excluded from the writer and final
  acceptance files. Missing namebase indexes remain a compatibility issue.

## Measured fields and changes

- Medals: quotation-mark shortcut in notation opens the actual dialog.
  Saved each of its 16 checkboxes separately into a fresh CBase database.
  UI-order masks: 0001 0002 0004 0008 0010 0020 0040 0080 0200 0100 0400
  0800 1000 2000 4000 8000. Defense=bit 8, Sacrifice=bit 9: corrected the
  old reversed mapping and its exhaustive test. medal-results.log records
  the measurements after Best game; shots/medal-best-checked.png shows it.
- The position bookmark copy is .2cba sub-item [u16 0x22][u32 mask]. The
  .2cbg move payload does not change. The parser consumes this item so later
  comments survive. Global medals are still written in the index; no fake
  position bookmark is generated for a global Scidb flag.
- Actual Game Tag text was created through loaded-game Ctrl+S > Game Tag.
  Index +0x50 references the title slot at +0xe76. Its record is [u32 total
  excluding this word][u32 count], then [u32 language][u32 byte length][UTF-8]
  for each language. English=42, German=53. Measured totals: 31 for a
  19-byte English title; 52 after adding 13 German bytes. Slot reuse was
  observed. See shots/gametag-mask.png and dbs/title-en.
- Added bounded title reader/encoder, full multilingual write/dedup and
  low-level append preservation. Extra PGN tags: GameTitle (English),
  GameTitleN (other numeric language ids). Oversize/malformed/truncated/free
  records are checked; no proprietary fixture is needed by the tests.
- Delete toggles record +0x00 bit 7, confirmed by a two-game diff and the
  struck-out row (shots/delete2.png). Read/write maps Flag_Deleted.
- The six high bits of +0x58 are a result subtype, not six markers. +:-,
  =:=, -:+, 0-0 give 06/05/04/07 (subtype 1); ordinary scores use subtype
  0. Read/write preserves this as ChessBaseResultType. result-results.log.
- +0xba bit 0 is the automatic good-game flag: Ghidra classifier 0x14064ac80
  calls setter 0x1401e4540. Read/write via ChessBaseGoodGame. The two short
  genuine probe games were rejected by the classifier; no positive genuine
  sample is claimed. CBase shows a written positive bit as Top Game.

## Remaining items and append decision

- +0x93c stayed empty with annotators, sources, teams and real bilingual
  titles. An annotator is still stored as a player. AnnotatorLib's existence
  in Ghidra does not identify the unused physical section. No guessed field
  or invented user/key mapping was added.
- +0xba bits 1 and 2 remain unmapped. Their setters were traced to move
  serialization (0x1401ae720/0x1401ae9c0) and a cloud placeholder path
  (0x1400eb430). They are not the Delete marker. Tail timestamps and beauty
  metadata are not encoded; the beauty action changed other tail bytes.
- App append was evaluated and left disabled deliberately: appendToDatabase
  reconstructs files, omits existing .2cba annotations and cannot preserve
  all unknown libraries/index fields. An open codec also has stale name/id
  maps after rewriting. The existing explicit Save as path satisfies the
  brief's read-only-codec alternative. Merely calling appendToDatabase would
  silently lose data. Its header now states the low-level preservation limit.

## Verification and hygiene

- make -C tests 2cbh: PASS, 4069 checks (test-backend-final.log).
- make -C tests 2cbh-elo: PASS, 1156/1156 values (test-elo-final.log).
- make -C src -j2 tkchesswiz: linked (build-shell-final.log).
- Tcl app export: 3/3 pass (test-app-final2.log); git diff --check passes.
- Only small scratch probes were read; no whole-file scans of big fixtures.
  Cached help was reused without refetching. No ChessBase database, cached
  help page or decompiler output is committed. Changed files have mode 644.
- Jev was not used: byte parsing, exact bit mapping and codec validation are
  deterministic operations. No local/cloud model was invoked for them.

RUN10B-DONE
