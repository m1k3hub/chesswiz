Reviewed 2026-11-27 against the registry above and the Tcl sources; the fixes listed here landed the same day. A feature counts as *accessible* when a menu, right-click menu, toolbar, key or workspace button reaches it. The Ask field and the assistant reach almost everything, but a user has to know a feature exists before they can type its name.

### 2.1 Features that only the assistant could reach

| Feature | Before | Now |
|---|---|---|
| **Print the current game** | Assistant only; File ▸ Export could write a PDF, but there was no Print command | **Game ▸ Print Game…** (Ctrl+P) |
| **Assistant Preferences** | Ask field and assistant only; kept out of the menu so a frozen fixture stayed unchanged | **Edit ▸ Preferences ▸ Assistant…**. The help and the speech-setup message point there. |
| **Focus zoom** (Focus follows size, … on resize, Zoom ratio, Pin board size) | Registered with order `00.*`, so no menu showed them | **View ▸ Panes ▸ Focus Zoom**. Maximise / Restore Pane (Ctrl+Shift+Z) sits next to it. |
| **Tournament Director: import a TRF report** | Assistant only | Event tab ▸ **Import TRF…** |
| **Tournament Director: audit journal** | Assistant only | Event tab ▸ **Audit log…** |
| **Tournament Director: find a FIDE player** | Assistant only | Players tab ▸ **Find in FIDE list**, which fills the FIDE ID field for *Register from FIDE list* |
| **Tournament Director: prizes** | Assistant only | Standings tab ▸ prize amounts, system and **Compute prizes** |
| **Find a video lesson for this position** | Assistant only | Board right-click ▸ **Find Video Lesson** |
| **Is this move a novelty?** | Assistant only | Notation right-click ▸ **Is This a Novelty?** |
| **Player statistics / position types** | Assistant or typed commands | Player right-click ▸ **Player Statistics**, **Position Types** |
| **Transcribe a media file** | Assistant only | Media right-click ▸ **Transcribe** |

The right-click rows show the assistant tool's answer in the Report pane. Each new label is translated into all six languages.

Not changed:
- **Save a position search as a pattern** (`save_pattern`) stays assistant-only. It saves the search the user just accepted in the assistant's plain-language position search, so it has no meaning outside that conversation.
- **Time-control breakdown** (`event_types`) was already reachable as Database ▸ Reports ▸ Time Control. The first version of this review missed that.

Also fixed in the Tournament Director workspace:
- About 70 hard-coded English labels now come from `::td::ui::mc`, translated into all six languages.
- Export TRF16/TRF26 called `td.export` without the required file name, so it couldn't work. It now asks for the file.
- Errors now appear in a dialog. The unused `Safe` helper read a variable nothing set; it is fixed and now wraps every button.

### 2.2 Features users could reach but shouldn't

| Feature | Now |
|---|---|
| **Hand an issue to the coding agent** (`handoff_issue`) | Debug only (`ai debug`) |
| **Error triage and the issue list** (`triage_errors`, `list_issues`) | Debug only |
| **Tool log, classifier status, application state** (`tool_log`, `classifier_status`, `app_state`) | Still available to the assistant, but no longer suggested in the Ask field (registry field `asklist 0`) |
| **Run any action / run a job by name** (`run_action`, `run_job`) | Unchanged. Confirmation and bulk gates apply through `ConfirmHook` and `BulkHook`, so these add no new power. |
| **Developer tools** (`eval_tcl`, `proc_source`, `read_variable`, …) | Unchanged; already debug only (`--ai-debug` / `SCIDB_AI_DEBUG=1`) |

### 2.3 Other review items

- **Column header menu (C10)** now has **Sort Ascending** and **Sort Descending** for the game, player, event and site tables. The column title above them stays a disabled submenu row, because the menu tests require titles to be structural rows rather than commands.
- **Player ratings:** the highest *and* the latest rating now prefer the games when the bundled 2013 dictionary is older (`src/db/db_namebase_entry.cpp`).
- **Repeated labels in the Ask field** (Flip Board ×3) are by design. Every action, right-click copies included, must stay reachable by its own label (`test_app_menu_changed_labels`).
- **German strings** that named the removed "Extras > KI" menu now name Werkzeuge > Modell wählen….
- **Assistant-tool baseline** (`tests/fixtures/assistant-tools-baseline.json`): the `open_view` and `search_games` schemas were refreshed to the 2026-11-14/16 versions (`search_games` gained `site`).
