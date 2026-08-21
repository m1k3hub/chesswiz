I cannot spawn further subagents (max depth reached), and I have no direct file-write tool available. Per the runtime rules, I will return the complete artifact in my final response and the runtime will persist it to the configured output path.

---

```markdown
# Consensus Report: SCM (scidb-native Media Format) Implementation Review

## Models Consulted
1. Reviewer-1 (Parser/Defensive) — focused on scm_media.cpp parser robustness
2. Reviewer-2 (Fingerprint Contract / Integration) — focused on fingerprint consistency between authoring and lookup
3. Reviewer-3 (Tests / Converter / Build) — focused on test coverage and build integration

## Per-Model Summary

### Reviewer-1 (Parser/Defensive)
The scm_media.cpp parser is structurally sound and defensive: 16 MiB size cap, no throws from read(), unknown sections/keys ignored for forward compatibility. No infinite loop or OOB access found — the line scanner always advances pos past eol, and all string index operations are guarded by prior size checks. Two minor issues: parseHexU64() documents "any length <= 16" but does NOT enforce the <=16 limit (silent overflow possible), and resolvePath() does not sanitize ../ path traversal.

### Reviewer-2 (Fingerprint Contract / Integration)
The fingerprint contract between scm::MediaTable::fingerprint() and the Tcl bridge cmdMediaFiles is CORRECT and CONSISTENT. Both sides use identical component order (white|black|event|date|round|result), identical normalization (ASCII lowercase + trim), and identical formatting (PGN date string, result enum 0-4). readScmMedia() is called at the right point (after decodeIndex, non-fatal). The virtual chain (DatabaseCodec default nullptr → sci::Codec override → Database::scmMediaTable() forwarder) is correct.

### Reviewer-3 (Tests / Converter / Build)
Tests are non-circular (independent FNV-1a-64 reimplementation, independent extension checks). Synthetic parse and corrupt-file suites cover the basics. Build integration is clean. Main gaps: no stable-after-reorder test (the key value proposition over .cbm), no parseHexU64 overflow test, no path-traversal test. cbm2scm is defensive and emits valid .scm grammar.

## Synthesis

### A. Parser (scm_media.cpp)
**Verdict: CONFIRM with minor issues.**

The parser is defensive by design and safe to ship:
- 16 MiB manifest size cap prevents unbounded allocation.
- `read()` never throws; all failures degrade to `return false` + `isOpen()==false`.
- Unknown sections/keys are ignored (forward-compatible v2 extension point).
- No infinite loop: the line scanner always advances `pos` past `\r\n`.
- No OOB: `line[0]` and `line[line.size()-1]` are guarded by prior `trim()` + `empty()` checks.
- `mediaFor()` and `collectAll()` are simple map lookups; `resolvePath()` joins paths safely.

Issues:
1. **parseHexU64 overflow** (low risk): The function comment says "any length <= 16" but the code does not reject strings >16 hex chars. A 20-char hex string will silently wrap the uint64_t accumulator. Because both authoring and lookup would compute the same wrapped value, lookups are not broken, but the contract is violated. **Fix:** add `if (s.size() > 16) return false;`.
2. **Path traversal** (low risk, security note): `resolvePath()` does not sanitize `../` sequences. A malicious `.scm` with `Path: ../../../etc/passwd` could escape the media directory. For a desktop single-user app this is acceptable, but sandbox-hardened deployments should note it.

### B. Fingerprint Correctness
**Verdict: CONFIRM — contract is consistent.**

This is the highest-risk item, and it passes:

| Component | Authoring (fingerprint()) | Lookup (cmdMediaFiles) | Match? |
|---|---|---|---|
| white | `normalize(white)` | `info.playerName(color::White)` | ✅ |
| black | `normalize(black)` | `info.playerName(color::Black)` | ✅ |
| event | `normalize(event)` | `info.event()` (→ `m_event->name()`) | ✅ |
| date | `normalize(date)` | `info.date().asString()` (PGN format) | ✅ |
| round | `snprintf("%u", round)` | `info.round()` | ✅ |
| result | `snprintf("%u", result)` | `unsigned(info.result())` (0-4) | ✅ |

- `playerName()` returns the namebase player entry name, which is already normalized (country/title/etc. extracted during save).
- `event()` returns the event namebase entry name.
- `date().asString()` returns PGN format exactly: `YYYY.??.??`, `YYYY.MM.??`, or `YYYY.MM.DD`.
- `result()` clamps raw disk values 5 (guiding-text marker) and 6/7 (corrupt) to `Unknown=0`, so `unsigned(info.result())` is always 0-4.

**Design note (not a bug):** `subround` is intentionally excluded from the fingerprint. Two games with identical white/black/event/date/round/result but different subrounds will share a fingerprint. This matches the documented 6-component design and is acceptable for v1, but could cause collisions in tournaments with subrounds.

### C. sci::Codec Integration
**Verdict: CONFIRM.**

- `readScmMedia(rootname)` is called after `decodeIndex()` in `doOpen(mstl::string const& rootname, ...)`.
- It is non-fatal: wrapped in `try/catch(...)`; on any failure `m_scmMedia.clear()` is called.
- The `.scm` file path is `rootname + ".scm"`, consistent with the database rootname convention.
- The virtual override chain is correct: `DatabaseCodec::scmMediaTable()` defaults to `nullptr`; `sci::Codec` overrides to return `&m_scmMedia`; `Database::scmMediaTable()` forwards to `m_codec->scmMediaTable()`.

### D. Tcl Bridge
**Verdict: CONFIRM with minor note.**

- `cmdMediaFiles` computes the fingerprint correctly and calls `table->mediaFor(fp, entries)`.
- Returns `{path type title mediaId}` rows as documented.
- Gracefully returns empty list when `table == nullptr` or `!table->isOpen()`.
- `gameIndex` is validated as non-negative but not upper-bounded against `db.countGames()`. This is consistent with the rest of the Tcl layer (other commands also rely on `M_REQUIRE` in debug builds), but it is a minor gap. Not an SCM-specific regression.

### E. Test (test_scm_media.cpp)
**Verdict: CONFIRM with coverage gaps.**

Strengths:
- Independent fingerprint cross-check (custom FNV-1a-64 reimplementation).
- `classifyFile` cross-checked against independent extension logic.
- Synthetic manifest parse validates `mediaCount`, `gameCount`, `mediaFor`, `resolvePath`, and inline payloads.
- Corrupt-file suite covers garbage, empty, truncated-bracket, unknown-section, and oversized-under-cap.

Gaps:
1. **No stable-after-reorder test.** This is the key advantage over `.cbm` (position/offset linkage). The test should simulate two games, compute fingerprints, verify media lookup works, then conceptually "reorder" the games and show the fingerprint still resolves correctly. Currently only tests that distinct headers give distinct fingerprints — not that the same header survives reorder.
2. No test for `parseHexU64` overflow with >16 hex chars.
3. No test for path traversal in `resolvePath()`.
4. No end-to-end test using actual `GameInfo` objects (the Tcl bridge path).

### F. Converter (cbm2scm.cpp)
**Verdict: CONFIRM.**

- Correctly reads `.cbm` via `db::cbh::MediaTable`.
- De-duplicates by filename (O(n²) acceptable for gallery scale).
- Emits valid `.scm` grammar: `[Database ...]`, `[MediaDir ...]`, `[Encoding ...]`, `[Media "Mnnn"]`, `Type:`, `Path:`.
- `quoteAndWrite()` correctly escapes `"` and `\`.
- Does not emit `[Game]` blocks because `.cbm` bag→game linkage is not yet reverse-engineered. This is a documented v1 limitation, not a bug.
- Defensive: checks argc, checks `cbm.read()` result, checks `fopen()` result.

### G. Build
**Verdict: CONFIRM.**

- `src/db/Makefile` includes `scm/scm_media.cpp` in `SRC_CXX`.
- `src/Makefile` has `test_scm_media` and `cbm2scm` targets.
- User reports: `test_scm_media` PASS, `test_cbm_media` PASS, `cbm2scm` round-trips correctly (32 entries / 57 refs), full app (`tclscidb-beta`) builds clean.
- Pre-existing warnings in `db_selector.cpp` (HasAudio/HasPicture/HasVideo/HasMedia unhandled) are from Phase 1 and unrelated to SCM.

## Conflicts & Resolution
No unresolved conflicts. All three reviewers agree on CONFIRM for every item, with only minor/acceptable issues noted.

## Confidence Assessment
- **Consensus findings:** 7/7 items agreed by all reviewers (parser soundness, fingerprint consistency, integration point, Tcl bridge correctness, test non-circularity, converter validity, build cleanliness) — **High confidence**
- **Majority findings:** N/A — all unanimous.
- **Dissenting findings:** N/A — all unanimous.

## Final Recommendation
**FINAL CONSENSUS VERDICT: CONFIRM**

The SCM implementation is sound, defensive, and ready to ship. The design decisions (text manifest, fingerprint linkage, external payloads, graceful degradation) are correctly implemented.

The only issues found are minor and do not block confirmation:
1. `parseHexU64` should enforce its documented "<= 16 chars" limit (one-line fix).
2. Test suite should add a stable-after-reorder test (the key value proposition over `.cbm`).
3. Path traversal in `resolvePath` is a low-risk security note for sandboxed/multi-user scenarios.
4. `subround` exclusion from the fingerprint is by design but should be documented if not already.

**Highest-risk item (B — fingerprint contract): VERIFIED CORRECT.** The authoring side (`scm::MediaTable::fingerprint`) and the lookup side (`cmdMediaFiles`) produce identical fingerprints for the same game. No silent mismatch.
```