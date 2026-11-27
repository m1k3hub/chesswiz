Reviewed 2026-11-27 against the registry above and the Tcl sources. A feature counts as *accessible* when a menu, right-click menu, toolbar, key or workspace button reaches it. The Ask field and the assistant reach almost everything, but a user has to know a feature exists before they can type its name.

### 2.1 Features users can't reach without the assistant, but should

| Feature | Today | Suggested place |
|---|---|---|
| **Print the current game** (`print`, `::print::game`) | Assistant only. File ▸ Export can write a PDF, but there is no Print command. | Game ▸ Print… (Ctrl+P) and the notation pane menu |
| **Assistant Preferences** (`app.preferences.assistant`) | Ask field and assistant only. `app-ask.tcl` keeps it out of the menu on purpose, so a frozen menu-test fixture stays unchanged. | Edit ▸ Preferences ▸ Assistant…, next to Engines (and update the fixture) |
| **Tournament Director: import a TRF report** (`td.import_trf`) | Assistant only. The workspace can export TRF16/TRF26 but can't import. | Workspace Event tab ▸ Import TRF… |
| **Tournament Director: prizes** (`td.prizes`) | Assistant only | Standings tab ▸ Prizes… |
| **Tournament Director: find a FIDE player** (`td.lookup_player`) | Assistant only. `td.register_fide` has a button but no search. | Players tab ▸ Find FIDE player… |
| **Tournament Director: audit journal** (`td.audit`) | Assistant only. Swaps are "audited", but the user can't see the log. | Event tab ▸ Audit log… |
| **Find a video lesson for this position** (`find_lesson`) | Assistant only | Board right-click menu |
| **Transcribe a media file** (`transcribe_media`) | Assistant only | Media right-click menu (C7) |
| **Label a move as a novelty** (`novelty_label`) | Assistant only. The game list's *Novelty* flag is a different, manual feature. | Notation right-click menu (C2) ▸ Is this a novelty? |
| **Player statistics / position-type profile** (`player_stats`, `structure_profile`) | Assistant, or typed commands *player statistics* / *player structures* | Player right-click menu (C5) and player card |
| **Save a position search as a pattern** (`save_pattern`) | Assistant only | Position search dialog ▸ Save as pattern |
| **Focus zoom: Focus follows size, Zoom ratio, Pin board size, Focus follows size on resize** (`view.focus_*`) | Registered with drop-down order `00.*`, so the menu never shows them; reachable only by typing in the Ask field. Maximise / Restore Pane has Ctrl+Shift+Z and the pane-header menu. | View ▸ Panes ▸ Focus Zoom submenu |
| **Time-control breakdown** (`event_types`) | Assistant only | Database ▸ Reports (next to Trends) |

Also worth adding: the Tournament Director's hard-coded English button labels ("Crosstable", "Print standings", "Swap colours (audited)", "Export TRF16") bypass the `mc::` translation tables, so they stay English in every language.

### 2.2 Features users can reach, but probably shouldn't

| Feature | Today | Why it's a problem | Suggestion |
|---|---|---|---|
| **Hand an issue to the coding agent** (`handoff_issue`) | An assistant tool for every user (`ai 1`). It does nothing unless `SCIDB_AI_HANDOFF_CMD` is set. | It's a developer workflow that runs an external program on the user's machine. Being gated by an environment variable is safe today, but it doesn't belong in a release build's tool list. | Make it `ai debug` |
| **Error triage and issues** (`triage_errors`, `list_issues`) | Assistant tools for every user, and Ask-field suggestions ("triage the error log", "list the issues") | Developer bookkeeping; the results mean nothing to a chess player. | `ai debug`, or keep for the assistant but hide from the Ask list |
| **Tool log, classifier status, application state** (`tool_log`, `classifier_status`, `app_state`) | Ask-field suggestions for every user | Internal diagnostics shown next to chess features | Keep for the assistant, hide from the Ask list |
| **Run any action / run a job by name** (`run_action`, `run_job`) | Assistant tools for every user | `run_action` bypasses each action's own surface (all actions are already exposed individually). Each run keeps its own confirmation gate. | Keep, but confirm that `confirm 1` and `bulk` gates also apply when the action runs through `run_action` (they do today, via `ConfirmHook`); document it. |
| **`eval_tcl`, `proc_source`, `read_variable`, `release_grab`, `cancel_timer`, …** | Debug mode only (`--ai-debug` / `SCIDB_AI_DEBUG=1`) | Correctly gated | No change. Never enable debug mode in a shipped config. |

### 2.3 Gaps the review found but didn't count as features

- **Header right-click menus** (C10) show the column name as a disabled submenu with an arrow, which looks like a broken submenu. Sorting lives in the game-row menu (C3) instead. Consider adding Sort Ascending/Descending to C10 as well, since most users try the column header first.
- **No click-to-sort** on table column headers (upstream behaviour).
- **The player list's "latest rating" option** still prefers the 2013 dictionary over game ratings. The highest rating was fixed in `354fd82ad`.
- **Duplicate entry points:** many features exist as a main-menu row, one or two right-click rows and an assistant tool (Flip Board has three). This works, but the Ask list now merges rows with the same label (`ec0a46df5`) to keep it readable.
