# Tournament Director P0: regulation and bbpPairings findings

Research date: 2026-11-13. This document settles the four draft-2 disagreements against primary sources. Quotations are short; implementation notes are explicitly distinguished from regulation text.

## Pinned sources

| Topic | Primary source | Edition |
| --- | --- | --- |
| FIDE Dutch | <https://handbook.fide.com/chapter/C0403202602> | Approved 2025-10-28; applies from 2026-02-01 |
| Competitions / round robins | <https://handbook.fide.com/files/handbook/Competition_Rules.pdf>, linked from <https://handbook.fide.com/chapter/C05GeneralRegulations> | Current linked C.05 PDF (amended through 2018) |
| Berger tables | <https://handbook.fide.com/chapter/C05Annex1> | Current linked annex |
| Tiebreaks | <https://handbook.fide.com/chapter/TieBreakRegulations032026> | Approved 2026-02-02; applies from 2026-03-01 |
| Laws | <https://handbook.fide.com/chapter/E012023> | Approved 2022-08-07; applies from 2023-01-01 |
| Rating conversion for TPR | <https://handbook.fide.com/chapter/B022024> | Applies from 2024-03-01; table 8.1.1 |
| bbpPairings | <https://github.com/BieremaBoyzProgramming/bbpPairings> | Pin release `v6.0.0`, tag object `21c01d5da4bdc70744dcaf15927716455db816fc`, commit `16a000f9811de322b0e835d5643198226165b5a9` |

## Verdict 1: bbpPairings is Apache-2.0, not MIT

`LICENSE.txt` at the pinned tag says: “The source code of BBP Pairings is released under the Apache License, Version 2.0.” `Apache-2.0.txt` contains the standard licence. The repository has no MIT licence text. Apache-2.0 is compatible with Chesswiz's GPL-2-or-later licensing; retain the copyright and licence notices when bundling.

Sources:

- <https://raw.githubusercontent.com/BieremaBoyzProgramming/bbpPairings/v6.0.0/LICENSE.txt>
- <https://raw.githubusercontent.com/BieremaBoyzProgramming/bbpPairings/v6.0.0/Apache-2.0.txt>
- <https://github.com/BieremaBoyzProgramming/bbpPairings/releases/tag/v6.0.0>

The source Makefile builds the C++20 sources without third-party link libraries. Static GCC runtimes are optional. Windows packaging contains MinGW-w64 runtime notices/patches, so each distributed binary still needs its own licence/notices review; “Apache-2.0 source” does not erase runtime notices. No bbpPairings code is copied in P0/P1.

## Verdict 2: bbpPairings has a checker mode

The pinned `README.txt` documents:

```text
bbpPairings.exe [-r] (--burstein | --dutch) input-file -c [-l [check-list-file]]
```

The default Makefile includes it (`engine_comparison = yes`; disabling it defines `OMIT_CHECKER`). Exit 0 means the operation completed, not that no discrepancy exists. Exit 1 can mean that no valid pairing exists; when checking, that condition is instead included in the discrepancy list. Errors and discrepancies can be written to stderr and/or the requested checklist.

Therefore P2 must capture and parse the diagnostic/checklist output and test its exact format against fixtures. A zero exit status alone is not a compliance certificate. The README does not establish that `-c` proves every manual override satisfies each C.04.3 absolute and quality criterion; the override UI must report actual violations and never relabel a prohibited pairing as compliant because a TD supplied a ruling. Whether an additional independent C.04.3 checker is needed will be decided from those P2 fixtures.

Sources:

- <https://raw.githubusercontent.com/BieremaBoyzProgramming/bbpPairings/v6.0.0/README.txt>
- <https://raw.githubusercontent.com/BieremaBoyzProgramming/bbpPairings/v6.0.0/Makefile>

## Verdict 3: C.07 2026 retains a dummy opponent for Swiss unplayed rounds

The strong claim that the virtual opponent was abolished is false. Article 16.4 says that, for a participant's own affected tiebreak, each unplayed round is evaluated against a **dummy** whose score is the participant's own score, subject to caps:

- forfeit win/loss (16.2.2/16.2.4): no more than the scheduled opponent's adjusted score under 16.3;
- pairing-allocated/full-point bye and the other listed categories: no more than draw points multiplied by the number of rounds.

The dummy is not the old rule unchanged. Article 16.2 separates pairing-allocated/full-point byes, forfeit wins, requested byes followed by a non-voluntary unplayed round, forfeit losses, and trailing requested byes. Under 16.3, trailing requested byes (16.2.5) are draws when adjusting a participant's score for opponents' tiebreaks. Article 16.5 gives the voluntary-unplayed-round exception to Cut modifiers. Article 16.6 permits alternative provisions only when pre-announced.

### Predetermined pairings are different

Article 15.2 covers round robins: forfeit wins and losses are regular games except that all forfeits remain unplayed for ratings-based tiebreaks (Article 10), and forfeit losses remain unplayed for Type B own-record tiebreaks (Article 7). Do **not** apply the Swiss Article 16 dummy algorithm to a round robin.

The note under Article 8 says Buchholz tiebreaks “must not be used in round-robins.” P1's default RR order therefore uses direct encounter, Sonneborn–Berger, Koya, games won, black wins and progressive score, not Buchholz. Buchholz and the Article 16 calculations belong to the later Swiss adapter.

### Exact worked checks

These are independently derived implementation vectors, not copied fixtures:

1. Nine-round Swiss, standard 1/0.5/0 scoring, player score 6 with a pairing-allocated bye: dummy contribution is `min(6, 0.5*9) = 4.5`.
2. Same event, player score 3.5: dummy contribution is 3.5.
3. Forfeit win, own score 6, scheduled opponent's adjusted score 3.5: dummy contribution is 3.5.
4. A requested bye followed only by voluntary unplayed rounds is a draw when adjusting that player's score for opponents' Buchholz/SB.
5. In a double round robin, direct encounter uses the **average** of the two results between each pair (C.07 6.1.2), then recursively reapplies to still-tied subgroups (6.2).
6. With unrated participants, rating-based tiebreaks are dropped unless the event published a different handling rule before play (Article 10).

All standings values use rational numerator/denominator arithmetic. Every value carries the game, opponent, points and opponent-score/dummy contribution used to produce it.

## Verdict 4: Laws 2023 illegal-move penalties depend on the setting

Article 7.5.1 defines a completed OTB illegal move in terms of pressing the clock and reinstating the position. Article 7.5.5 gives the opponent **two minutes** for the first completed illegal move and declares the game lost after the second by the same player, except when the opponent cannot mate by any legal sequence.

The appendices must not be collapsed into that single sentence:

- Rapid A.3 changes penalties mentioned in Articles 7 and 9 to **one minute instead of two**.
- Rapid A.4 is the supervised/recorded regime (at most three games per arbiter); A.5 is the other regime. A.5.2 applies 7.5.5 when observed or claimed before the opponent's next move; otherwise the illegal move stands. A.6 requires the event to publish A.4 or A.5.
- Blitz B.2 is the one-game-per-arbiter, recorded regime and uses the Competitive Rules (two minutes under 7.5.5).
- Blitz B.3 otherwise imports Rapid A.2, A.3 and A.5: one minute and the A.5 observation/claim rules. B.4 requires the event to publish B.2 or B.3.

Thus the first penalty is +2 minutes in ordinary and supervised blitz play, +1 minute in rapid and unsupervised blitz; the second completed illegal move loses where 7.5.5 applies. An illegal GUI attempt rejected before completion is not an OTB Article 7.5 offence. Engine protocol violations use the engine event's published forfeit rule rather than pretending a GUI/UCI error was a physical clock-press offence.

## C.05 round-robin implementation findings

- C.05 5.1 selects Berger tables. The annex says that with an odd field the highest pairing number is the bye.
- The annex recommends reversing the order of the last two rounds of the first cycle in a double-round event to avoid three consecutive games in one colour.
- C.05 6.1–6.3 assign responsibility for the public drawing of lots. Pairing-number lots plus the printed Berger table determine the seats and colours.
- The exact sentence “colour of pairing number 1 is decided by lot” was **not found** in the current C.05 PDF or annex. P1 records a colour-lot choice for pairing number 1 as an explicit event setting; this is an implementation convention, not a fabricated quotation.
- After lots but before round 1, announced pairings remain unaltered after a withdrawal or additional entry except for minimal CA-approved amendments (6.4).
- Under 6.6(2), before 50% of a withdrawing player's games are completed, that player's results remain for rating/history but are removed from final standings. At 50% or more, completed results remain counted. Remaining games receive the prescribed unplayed/forfeit marks; P1 records them as forfeit losses and opponent wins when results count, and as annulled/non-scoring entries when they do not.

## C.04.3 facts retained for P2

The 2026 Dutch chapter defines absolute criteria C1–C3, completion C4, PAB C5 and ordered quality criteria C6–C21. These include no rematch, PAB eligibility, absolute colour preferences, completion, downfloat minimisation and ordering, next-bracket compliance, colour preferences, and repeat-float/score-difference criteria. The implementation will not substitute a homemade heuristic Dutch pairer for bbpPairings.

## Runner boundary

The P0 jitter test will establish whether the Tcl pipe loop with per-game monotonic ledgers and configurable move overhead is sufficient. C++ or an external match runner is considered only if that test shows false flags. No network play, online tablebase lookup, Lichess token, GPU model, or local Jev service is involved. The existing assistant router/tool loop may route to typed `td.*` commands; no classifier decides chess facts, pairings, results, arithmetic or recovery.
