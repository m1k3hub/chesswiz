# Ask command line: draft 1 (2026-11-14)

Goal: every request either runs exactly what the user saw and confirmed, or does not run.
No model decides what runs. Ask becomes a command line with live suggestions, built on
the action registry and the command palette (mission 2, VAL-PAL).

## 1. How it works

```
you type:  find kasp wins wh
shows:     ▸ find games  player=Kasparov, Garry  result=win  colour=white     Enter
             find games  player=Kasparov, Sergei result=win colour=white
```

- **Commands:** each command has a verb phrase, synonyms, typed slots and one registry action (or a fixed recipe of several).
- **Matching:** plain code: fuzzy prefix matching on words, synonyms and slot values. It works offline, takes under 10 ms, and the same input always gives the same result.
- **Slot values come from the app's state only:**
  - open databases, engines, panes and tabs;
  - player, event and site names from the active base's name index;
  - ECO codes and opening names from the opening table;
  - motifs from the pattern index;
  - files from a file picker or a typed path.

  Free values (numbers, years, moves, ratings, time controls) are parsed by fixed grammars. A move is checked for legality on the current board.
- **Enter:** runs the highlighted line. Destructive commands (compact, delete, overwrite) keep their confirmation dialog.
- **Missing slot:** the line is not runnable. The cursor jumps to the slot and shows its candidates.
- **Learning:**
  - Each pick is recorded (phrase → command + slots).
  - Order: frequent and recent first, then match quality.
  - User aliases ("main db" → select database Main) always match exactly.
- **Speech:** the transcript fills the box like typing; "go" or Enter confirms.
- **Jev (optional):** used only when no command matches above a set threshold. It may reorder the suggestions; it never adds commands or runs anything. Without Jev, the order stays the same.
- **Free-form LLM chat:** kept as a separate, labelled "Ask a question" mode for explanations. It is read-only and cannot change data. It is never the default.

## 2. First command set (draft; cut or add)

The sources are the 111-request corpus (tests/assistant_corpus.tcl, jobs J1-J12) and the
registry. Slots are written ⟨slot⟩ and optional parts [in brackets].

### Databases (J1)
| # | Command | Action | Corpus |
|---|---|---|---|
| 1 | open database ⟨file⟩ | database.open | |
| 2 | switch to ⟨open database⟩ | database.select | d2-switch |
| 3 | close database ⟨open database⟩ | database.close | |
| 4 | database summary / overview | database_summary | db-summary, db-overview |
| 5 | list open databases | list_open_databases | db-open-list |
| 6 | show all games / clear filter | clear filter | db-clear |
| 7 | import ⟨pgn file⟩ [into ⟨open database⟩] | import_games | db-import |
| 8 | export ⟨list/database⟩ as ⟨pgn/pdf/html⟩ to ⟨file⟩ | export_database | db-export, db-export-pgn |
| 9 | download TWIC [⟨issue⟩] | download_games | db-download |
| 10 | save list as new database ⟨name⟩ | save_working_set | db-workingset |
| 11 | find duplicates | maintenance_report tab=duplicates | db-duplicates |
| 12 | compact ⟨open database⟩ | compact_database (confirm) | db-compact, db-shrink |
| 13 | convert ⟨open database⟩ to ⟨format⟩ | convert_database | db-convert |
| 14 | maintenance report | maintenance_report | db-maintenance |

### Finding games (J2)
| # | Command | Action | Corpus |
|---|---|---|---|
| 15 | find games [player ⟨name⟩] [colour ⟨white/black⟩] [result ⟨win/loss/draw⟩] [opening ⟨eco/name⟩] [from ⟨year⟩] [to ⟨year⟩] [min elo ⟨n⟩] [both elo ⟨n⟩] [event ⟨name⟩] | search_games | find-* (9 requests) |
| 16 | open game ⟨number⟩ [at move ⟨n⟩ ⟨white/black⟩] | open_game | game-open |
| 17 | open last game of ⟨player⟩ | open_game player= | open-last-game |
| 18 | games like this one / like game ⟨n⟩ | similar_games | find-similar-games, find-like-5, game-like-board |

### Positions and motifs (J3)
| # | Command | Action | Corpus |
|---|---|---|---|
| 19 | find motif ⟨motif⟩ [from ⟨year⟩] | find_positions motif= | pos-* (22 requests; the motif list comes from the pattern index) |
| 20 | find positions like the board [pawn structure only] [one pawn may differ] | find_positions | pos-like-board, pos-structure* |
| 21 | search by material | open material search | db-material |

### Openings (J4)
| # | Command | Action | Corpus |
|---|---|---|---|
| 22 | set up ⟨opening⟩ [after ⟨move⟩] | setup_opening | open-najdorf, board-dragon |
| 23 | opening tree | pane tree | open-tree |
| 24 | score of ⟨opening⟩ [for ⟨player⟩] | opening stats | open-score, open-kid-score, open-player-eco |
| 25 | opening report | open_view opening_report | open-report |
| 26 | opening trends | open_view trend | open-trend, play-trend |
| 27 | repertoire: add this line / check against my games | repertoire actions | open-rep-* |

### Preparation (J5)
| # | Command | Action | Corpus |
|---|---|---|---|
| 28 | prepare against ⟨player⟩ [I have ⟨white/black⟩] | opponent brief | prep-brief, prep-white |
| 29 | player card ⟨player⟩ | player card | play-card, prep-card |
| 30 | ⟨player⟩ stats / structures / prep report | player report tabs | prep-stats, prep-structures, prep-report |

### Me and my games (J6)
| # | Command | Action | Corpus |
|---|---|---|---|
| 31 | I am ⟨name⟩ | remember_me | me-remember |
| 32 | review my last ⟨n⟩ games / my score | my games review | me-review, me-record |
| 33 | study plan from my games | studyplan | me-plan |
| 34 | which game is on the board | current game | me-current |

### Engines and analysis (J7)
| # | Command | Action | Corpus |
|---|---|---|---|
| 35 | start / stop ⟨engine⟩ | start_engine / stop | eng-start, eng-stop |
| 36 | best move [with ⟨engine⟩] | engine_evaluate | engine-best, eng-lines |
| 37 | check move ⟨legal move⟩ | engine_check_move | engine-check |
| 38 | analyse moves ⟨n⟩ to ⟨m⟩ / annotate game | annotate_game | annotate-range, me-annotate |
| 39 | tablebase | tablebase | tablebase-endgame |
| 40 | set ⟨engine⟩ threads ⟨n⟩ | engine option | eng-threads |
| 41 | list engines | engine list | eng-list |
| 42 | play ⟨engine⟩ [⟨time control⟩] [as ⟨white/black⟩] | engine play | |
| 43 | new game | board new | board-new |

### Training and tournaments (J8, J10)
| # | Command | Action | Corpus |
|---|---|---|---|
| 44 | puzzles from ⟨my games/this database⟩ [motif ⟨motif⟩] | training set | train-* |
| 45 | crosstable ⟨event⟩ | open_view crosstable | play-cross, find-event |
| 46 | event story ⟨event⟩ | event_report | event-story |
| 47 | run ⟨round robin/double round robin⟩ of ⟨n⟩ engines [⟨time control⟩] [opening ⟨opening⟩] | td.create recipe | your London request |
| 48 | tournament director | td.workspace | |

### Window and navigation (J1)
| # | Command | Action | Corpus |
|---|---|---|---|
| 49 | go to ⟨tab⟩ | tab select | board-tab |
| 50 | dock / undock / maximise ⟨pane⟩ | pane | pane-dock |

## 3. Requests deliberately left out

| Requests | Where they go |
|---|---|
| Explain the position, check the annotations, plain comments (me-explain, factcheck, me-annotate-plain) | They are generation, not automation, so the "Ask a question" mode. |
| ask-back ("Open that one") | Needs conversation memory. The command line instead keeps the last result list as the ⟨result⟩ slot ("open result 2"). |
| Correspondence (J12) and media lessons (J9) | Phase 2, if usage shows a need. |

## 4. Acceptance

1. Each of the 50 commands has an end-to-end test: input text → suggestion → Enter → expected registry action, arguments and app state.
2. Over the corpus, rephrased by hand to command style:
   - every request in scope reaches the right command within the top 3 suggestions;
   - zero commands run without Enter;
   - zero suggestions contain a slot value that does not exist in the state.
3. A typed full sentence never runs anything by itself.
4. Matching p95 is under 10 ms with a 4.8M-game base open (the name index is already in memory).
5. It works with the network off and no model configured.

## 5. Questions for the user

1. Cut or add commands. Which features do you use most that are missing here?
2. The free-form LLM chat: keep it as a separate "Ask a question" mode, or remove it?
3. Command style: verb first ("find games kasparov") is assumed. Is that OK?
4. Languages: English first; German later from the same tables?

## 6. Decisions (user, 2026-11-14)
The user said "use the draft defaults": the 50 commands as listed; the LLM chat stays as a separate read-only
"Ask a question" mode; verb-first style; English first, German later from the same tables.
