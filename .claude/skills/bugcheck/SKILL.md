---
name: bugcheck
description: Exhaustive multi-agent bug audit for this codebase (Tcl UI layer + C++ core). Sweeps for dangling namespace/proc references, mc-string mismatches, arity mismatches from file splits, C++ exception-safety/leak bugs, and general correctness issues. Verifies every finding adversarially before reporting. Use for "bugcheck", "audit the codebase for bugs", "find dangling symbols", "sweep for bugs after refactor/split", or before closing out a large refactor.
---

# Bugcheck

A thorough, multi-agent bug sweep tailored to this codebase's actual failure history (see git log: repeated Tcl-file-split regressions, namespace escapes, mc-string relocation bugs, ThreadGroup exception-safety issues). Default to running this as a `Workflow` — this is a comprehensive-audit task, not a quick lint pass — unless the user asks for a narrow/quick check on a specific file, in which case a handful of direct `Agent` calls is enough.

## Scope

Ask (or infer from context) whether this is:
- **Full sweep** — whole `tcl/` and `src/` trees. Expensive, most thorough.
- **Targeted sweep** — files changed since a given commit/ref (`git diff --name-only <ref>...HEAD`), or files touched by a recent split/refactor. Default to this if the user doesn't specify and there's a clear recent diff to scope to.
- **Single-file** — one file named by the user.

## Known failure classes for this codebase (check these explicitly, not just generically)

1. **Code stranded outside namespace closers** — after an automated file split, procs/vars/blocks can end up after the closing `}` of a `namespace eval`, becoming global. Symptom: `$mc::*` derefs resolve to `::mc::*` (missing) instead of the intended namespace; unqualified proc calls fail. Check: for every `namespace eval X { ... }` block in a file, confirm nothing meaningful follows the closer except other top-level declarations that are supposed to be global.
2. **mc string defined in the wrong namespace/panel** — strings consumed via unqualified `$mc::Foo` from panel Y but only defined in panel X's `mc` block (split put them in the wrong file). Check: for each `$mc::Name` or `$::ns::mc::Name` deref, grep for where `Name` is actually `set` inside a `namespace eval mc { ... }` block, and confirm the reference is fully qualified or in-scope.
3. **Stale proc addresses after split** — `namespace code [list ProcName ...]` or `::old::ns::ProcName` calls that point at a namespace the proc no longer lives in. Check: grep the target proc name's actual `proc` definition and confirm the call site's namespace path matches.
4. **Arity mismatches** — calls to procs with a different argument count than the current `proc` signature (common after a signature change during refactor). Check each call site against the live `proc NAME {args...}` definition.
5. **Dotted vs. dotless extension confusion** — `::util::fileExtension` returns a dotted value (`.sci`); many older call sites compare against dotless values (`sci`). Check any file-extension comparison/switch for mismatched dotted/dotless literals.
6. **C++ exception-safety / resource leaks** — code that acquires a resource (thread, reader handle, file handle, heap object), then calls something that can throw before the cleanup/join runs. Check destructors and any `join()`/`wait()`-then-cleanup pattern: does cleanup run if the intervening call throws? Does a destructor let an exception escape during stack unwinding (`std::terminate` risk)?
7. **Malformed control structures from mechanical edits** — e.g. `variable` declarations accidentally nested inside a `switch` body as extra pattern/body pairs, dangling `EOF`/heredoc artifacts, duplicate namespace closers.
8. **Latent/dead code with the same bug classes** — blocks with no current caller are lower priority but still worth flagging; note as latent so priority stays P3 unless requested otherwise.
9. **Encoding corruption** — non-ASCII literals (names, symbols) replaced by U+FFFD or mangled bytes from an editor re-encode. Grep for U+FFFD (`\xef\xbf\xbd`) across text files.

Beyond this fixed list, run general correctness review too (logic errors, off-by-one, null/empty-collection handling, race conditions) — the list above is "always check these," not "only check these."

## Procedure (Workflow-based, for full/targeted sweeps)

1. **Discover** — build the file list for the chosen scope (full tree, changed-files-since-ref, or single file).
2. **Find (parallel, one agent per failure class or per file group)** — each finder agent greps/reads for one failure class across the scoped files and returns structured findings: `{file, line, class, description, confidence}`. Don't let one mega-agent try to hold the whole tree in context.
3. **Dedup** — merge findings across finders, drop exact duplicates.
4. **Verify (parallel, adversarial)** — for each finding, spawn a verifier agent that reads the *current* file content at that location (not a diff) and either confirms or refutes the claim, with file:line evidence. Default to at least 1 verifier per finding; use 2+ independent verifiers with majority vote for anything going into a P1/P2 bucket.
5. **Prioritize** — bucket confirmed findings: P1 (breaks startup or a whole feature), P2 (error paths, leaks, rarer UI), P3 (hardening/cosmetic/latent).
6. **Report** — a bug catalog (numbered, one entry per bug: file:line, root cause, fix sketch, priority) and, if asked, a fixit plan grouped by root-cause pattern to minimize context-switching across fixes (mirrors how `FIXIT_PLAN_2026-07-02.md` was structured — group by pattern, not by discovery order).

Do not silently truncate coverage — if the scope is capped (e.g. sampling instead of full tree), say so explicitly in the report.

## When NOT to use Workflow

If the user asks to bugcheck one specific file or a small diff, just do it directly: read the file, check it against the failure-class list above, report findings inline. Don't spin up a multi-agent workflow for a 50-line diff.

## After the catalog exists

If the user then asks to fix and verify (as in the BUG_CATALOG_2026-07-02.md → FIXIT_PLAN_2026-07-02.md → commit 9870afb cycle), that's a separate follow-up: implement fixes grouped by pattern, then re-run bugcheck in verify-only mode (skip the finder stage, just re-verify each catalog entry's fix against current file state) before considering it closed.
