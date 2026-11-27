# Chesswiz feature catalog

Generated on 2026-11-27 from the live action registry (`::action::Registry`, 838 actions) of master, with descriptions from the registry and from `tcl/knowledge.tcl`. Regenerate it rather than editing the catalog by hand; the findings in section 2 are written by hand.

## 1. How features are reached

Every user-visible operation is a registered action. One feature can have several entries, one per place you reach it (the main menu, a right-click menu, a toolbar, a key, the Ask field, the assistant).

| Surface | Actions | How you use it |
|---|---|---|
| Main menu | 186 | **Main Menu** button, top right. Ten menus: File, Edit, Game, Database, Board, Analysis, Training, Tools, View, Help. |
| Right-click menus | 339 | Twelve context menus (C1–C12), section 3.3. Each starts with *What can I do here?*, which asks the assistant about that object. |
| Keyboard shortcuts | 38 | Listed per entry; all are rebindable under Edit ▸ Keyboard Preferences…. |
| Toolbars | 82 | Pane toolbars (board, notation, analysis, tree, database switcher, …). |
| Tournament Director | 27 | Tools ▸ Tournament Director… workspace. |
| Typed commands | 25 | Type in the Ask field (Ctrl+K): *open database …*, *find games …*, *play engine* … |
| Assistant tools | 120 | Used by the AI assistant when you ask in plain language. Those that need no arguments also appear as suggestions in the Ask field. |
| Developer tools | 12 | Only with `--ai-debug` or `SCIDB_AI_DEBUG=1`. |

The Ask field (top right, Ctrl+K) searches every runnable action by name and description, so anything in this catalog that needs no arguments can also be started by typing its name.

## 2. Findings

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

## 3. Catalog

Each row: where to find it, its shortcut, and what it does.

### 3.1 Main menu


#### Registered for the menu but not placed in it

| Menu path | Key | How it works |
|---|---|---|
| Maximise / Restore Pane — *not placed in any menu* | Ctrl+Shift+Z | Maximise the active pane or restore the workspace arrangement. Use this to concentrate temporarily on a single view. |
| Focus follows size — *not placed in any menu* |  | Toggle automatic pane enlargement as focus moves. Use this when the view you are working in should gain space. |
| Zoom ratio — *not placed in any menu* |  | Cycle the size ratio used when focus enlarges a pane. Use this to adjust how much extra space the active pane receives. |
| Pin board size — *not placed in any menu* |  | Toggle whether automatic pane zoom preserves the board's size. Use this to keep the board stable while other panes gain space. |
| Focus follows size on resize — *not placed in any menu* |  | Toggle growing the focused pane whenever the window is resized. Use this to keep giving the view you are working in more space as the window changes size. |
| ♥ Donate button (top strip) ▸ Donate |  | — |
| ♥ Donate button (top strip) ▸ Ko-fi |  | — |
| ♥ Donate button (top strip) ▸ PayPal |  | — |

#### File

| Menu path | Key | How it works |
|---|---|---|
| File ▸ New Database ▸ Normal |  | Start a new database for ordinary chess games. Use this when creating a regular game collection. |
| File ▸ New Database ▸ Three-check |  | Start a new database for games won by giving three checks. Use this when collecting Three-check games. |
| File ▸ New Database ▸ Crazyhouse |  | Start a new database for games with captured pieces returned to play. Use this when collecting Crazyhouse games. |
| File ▸ New Database ▸ variant list |  | Show the supported chess variants for a new database. Use this when your collection uses rules other than ordinary chess. |
| File ▸ Open Database… | Ctrl+O | Open a database file. When you know the database file you want to work with. |
| File ▸ Close Database | Ctrl+W | Close the active database. When you have finished with the active collection. |
| File ▸ Save Changes | Ctrl+S | Save pending changes in the active database. Use this before leaving a collection you have edited. |
| File ▸ Import ▸ PGN file(s)… |  | Import portable game notation files into the database. When adding games from an existing game-text file. |
| File ▸ Import ▸ Games from another database… |  | Open the importer for games from another database file. Use this to combine games stored in separate collections. |
| File ▸ Export ▸ PGN… |  | Export the database or the listed games as portable game notation. When another chess program needs the collection or filtered games as text. |
| File ▸ Export ▸ HTML report… |  | Export the games as an HTML report. When publishing selected games as a readable web document. |
| File ▸ Export ▸ Portable archive (.scv)… |  | Export the database as a portable archive. When another computer needs a portable copy of the collection. |
| File ▸ Export ▸ Lichess study… |  | Open study-upload options for the active database. Use this when sharing a game collection through Lichess. |
| File ▸ Create Database Archive… |  | Create a portable archive of the database. When packaging a collection for transfer or backup. |
| File ▸ Quit | Ctrl+Q | Close Chesswiz after checking whether your work needs saving. Use this when you have finished working and want to exit. Asks for confirmation first. |

#### Edit

| Menu path | Key | How it works |
|---|---|---|
| Edit ▸ Undo | Ctrl+Z | Reverse the last edit in focused text or game notation. Use this to recover from an unwanted editing change. |
| Edit ▸ Redo | Ctrl+Y | Reapply the last undone edit in focused text or game notation. Use this when an edit you reversed should be restored. |
| Edit ▸ Cut | Ctrl+X | Cut selected text from the focused text editor. Use this to move text to another location. |
| Edit ▸ Copy | Ctrl+C | Copy focused text, or open the move's comment editor when the board has focus. Use this to copy a text selection or annotate the current board move. |
| Edit ▸ Paste | Ctrl+V | Paste clipboard text into the focused text editor. Use this to insert text copied elsewhere. |
| Edit ▸ Select All | Ctrl+A | Select all focused text, or open move annotations from the board. Use this before replacing text or choosing a move-quality symbol. |
| Edit ▸ Find | Ctrl+F | Find text or games in the view you are working in. Use this to locate text within the view you are using. |
| Edit ▸ Keyboard Preferences… |  | Open the keyboard shortcut preferences. When changing or checking the keys assigned to commands. |
| Edit ▸ Preferences ▸ Engines… |  | Open the engine preferences. When adjusting the application's engine-related preferences. |
| Edit ▸ Preferences ▸ PGN export options… |  | Open the portable game notation export options. When exported game text needs different formatting or included details. |
| Edit ▸ Preferences ▸ Private Player Card… |  | Edit your own private player card. When updating the private identity used for your own games. |

#### Game

| Menu path | Key | How it works |
|---|---|---|
| Game ▸ Load Game Number… |  | Load a game by its number. When you know a game's index within the active collection. |
| Game ▸ Next Game | Ctrl+Down | Load the next game of the database. When continuing a review with the following database game. |
| Game ▸ Previous Game | Ctrl+Up | Load the previous game of the database. When returning to the preceding database game during review. |
| Game ▸ First Game | Ctrl+Home | Load the first game of the database. When beginning a sequential review of the active database. |
| Game ▸ Last Game | Ctrl+End | Load the last game of the database. When jumping directly to the final game of the active database. |
| Game ▸ Random Game |  | Load a randomly chosen game from the current database view. Use this when you want an unplanned game to study. |
| Game ▸ Replace Game | Ctrl+R | Replace the loaded database game with the edited game on the board. Use this when you want your edits to overwrite the original game. |
| Game ▸ Replace Moves | Ctrl+V | Open saving options to replace the current game's stored moves. Use this when updating an existing database game from the board. |
| Game ▸ Add as New Game | Ctrl+S | Save the game on the board as a new game in the database. Use this when you have edited a game and want to keep a new copy. |
| Game ▸ Reload from Database |  | Restore the current game from the database. Use this to return to the last saved version after editing. |
| Game ▸ Copy Game |  | Copy the current game into the temporary clipboard database. Use this to retain a working copy before changing games. |
| Game ▸ Export Game… | Ctrl+E | Export the game on the board. When sharing the game currently on the board in another format. |
| Game ▸ Export ▸ Upload to Lichess Study… |  | Open the study-upload dialog for the current game. Use this to share the game through a Lichess study. |
| Game ▸ History ▸ Clear History |  | Clear the app's recent-game history through the main menu. Use this to remove the list of previously visited games. |
| Game ▸ Close Game |  | Close the game on the board. When the loaded game no longer needs to occupy a game slot. |
| Game ▸ paste last clipbase game |  | Read clipboard notation as the current game. Use this to load a game copied as portable game text. |
| Game ▸ paste from game tab |  | Paste a copied game into the selected game tab. Use this when bringing copied game notation into the board. |
| Game ▸ merge clipbase |  | Merge games from the temporary clipboard database into the current game. Use this to combine copied analysis with the board game. |
| Game ▸ merge from game tab |  | Open a merge using another available game tab. Use this to combine continuations from open games. |
| Game ▸ History ▸ recent games |  | Show recently opened games for loading again. Use this to return to a game you viewed earlier. |

#### Database

| Menu path | Key | How it works |
|---|---|---|
| Database ▸ Search ▸ Plain-Language… |  | Open the search box for describing desired games in ordinary words. Use this when it is easier to describe a search than build its fields. |
| Database ▸ Search ▸ Advanced… |  | Open the advanced search dialog. When simple criteria cannot express the games you want to find. |
| Database ▸ Search ▸ Material… |  | Open the material search dialog. When finding games with a particular balance of pieces. |
| Database ▸ Search ▸ Rating… |  | Open the rating search dialog. When limiting games to players within a rating range. |
| Database ▸ Search ▸ Duplicates… |  | Find duplicate games in the database. When repeated copies may be inflating a collection. |
| Database ▸ Search ▸ Query Editor… |  | Open the structured position-search editor. Use this to build a detailed pattern for finding games. |
| Database ▸ Reports ▸ ECO Statistics… |  | Open the opening preparation statistics (opening classification) of the database. When comparing opening results across the active collection. |
| Database ▸ Reports ▸ Opening Report… |  | Open the opening report for the board position. When studying the database evidence for the current opening position. |
| Database ▸ Reports ▸ Repertoire Report… |  | Open the repertoire report. When reviewing the coverage of your opening preparation. |
| Database ▸ Reports ▸ Result Check… |  | Run the result-checking report for database games. Use this to investigate recorded outcomes that may need review. |
| Database ▸ Reports ▸ Time-Control Profile… |  | Report the time-control types found in the database. Use this to understand which playing speeds the collection contains. |
| Database ▸ Reports ▸ Trends… |  | Report changes and patterns in the database over time. Use this when studying how the collection's game statistics develop. |
| Database ▸ Maintenance ▸ Fix player names… |  | Preview stored player-name corrections for the current database. Use only for explicit database maintenance; confirm selected changes and save separately. |
| Database ▸ Maintenance ▸ Compact… |  | Remove deleted games and reclaim space in the current database. Use this to reclaim space from obsolete stored records. |
| Database ▸ Maintenance ▸ Strip Move Information… |  | Choose which move information to remove throughout the database. Use this to remove selected clocks or evaluations from every database game. |
| Database ▸ Maintenance ▸ Strip PGN Tags… |  | Choose extra game headers to remove throughout the database. Use this to clean selected extra headers from every database game. |
| Database ▸ Maintenance ▸ Convert to Native Format… |  | Open conversion of the current database to Chesswiz's own format. Use this when a collection should become an editable Chesswiz database. |
| Database ▸ Maintenance ▸ Recode… |  | Open character-encoding conversion for the current database. Use this when names or comments display with incorrect characters. |
| Database ▸ Maintenance ▸ Change Icon… |  | Open the database icon picker. Use this to give a collection a recognizable symbol. |
| Database ▸ Discover Databases… |  | Find chess databases stored on this computer. When locating chess collections whose disk locations you have forgotten. |
| Database ▸ Properties… |  | Open the properties of the active database. When inspecting the active collection's storage and format information. |
| Database ▸ Read-only |  | Make the active database read-only, or writable again. When protecting a collection from edits or enabling edits again. |
| Database ▸ Player Data ▸ National / correspondence lists… |  | Open DWZ, ECF and ICCF source information and explicit import controls. Use to request a national or correspondence list; imports take effect after restart. |
| Database ▸ Player ▸ Update Rating Data… |  | Open the rating-data update window. Use this to refresh the app's supplemental player ratings. |
| Database ▸ Player ▸ Check Name Spellings… |  | Check the player name spellings of the database. When inconsistent player spellings may split one player's statistics. |

#### Board

| Menu path | Key | How it works |
|---|---|---|
| Board ▸ Start Position ▸ Standard |  | Restore the ordinary chess starting arrangement. Use this when returning to a regular game after a custom setup. |
| Board ▸ Start Position ▸ Chess960 |  | Select a Chess960 starting arrangement for the game. Use this to play with a randomized back rank under Chess960 rules. |
| Board ▸ Start Position ▸ Symm960 |  | Select a symmetric randomized arrangement for the game. Use this to try the symmetric shuffled-chess variant. |
| Board ▸ Start Position ▸ Shuffle |  | Select a shuffled starting arrangement for the game. Use this to try a nonstandard initial piece order. |
| Board ▸ Start Position ▸ Set Up Position… |  | Show the menu of available starting positions. Use this to choose a different setup for the game. |
| Board ▸ Set Start Board… |  | Open the editor for placing pieces on a starting board. Use this when entering a position from a diagram. |
| Board ▸ Set Start Position… |  | Open the chooser for the game's initial arrangement. Use this when selecting a numbered or randomized starting position. |
| Board ▸ Flip Board | Ctrl+F | Flip the board so the other side is at the bottom. Use this when you want to see the position from Black's side. |
| Board ▸ Insert Null Move | Ctrl+0 | Pass the turn without moving a piece in the current game. Use this to explore what the other side could do with an extra turn. |
| Board ▸ Appearance ▸ side to move |  | Show or hide the indicator of whose turn it is. Use this when you need a visible reminder of the side to move. |
| Board ▸ Appearance ▸ material values/bar |  | Show or hide the board's material display. Use this to see the balance of captured pieces beside the position. |
| Board ▸ Appearance ▸ border |  | Show or hide the border around the board. Use this when adjusting the board's visual framing. |
| Board ▸ Appearance ▸ coordinates |  | Show or hide the board's file letters and rank numbers. Use this when square names would help you follow the moves. |
| Board ▸ Appearance ▸ small letters |  | Switch the board coordinate letters between small and large forms. Use this to change how the file labels look. |
| Board ▸ Appearance ▸ suggested move |  | Show or hide the suggested-move marker on the board. Use this when you want to see or conceal the current suggestion. |
| Board ▸ Appearance ▸ variation arrows |  | Show or hide arrows for alternative continuations on the board. Use this when comparing candidate lines visually. |
| Board ▸ Appearance ▸ annotation |  | Show or hide move annotation symbols on the board. Use this when symbols distract from the pieces or should be visible. |
| Board ▸ Show Tablebase ▸ show |  | Show or hide exact endgame information beside the board. Use this to check table-covered positions while playing through a game. |
| Board ▸ Show Tablebase ▸ online lookup |  | Toggle remote exact-endgame lookups for the board. Use this when you want online endgame results while browsing. |
| Board ▸ Show Tablebase ▸ local folder… |  | Choose the folder containing local exact-endgame files. Use this to connect installed endgame tables to the board. |

#### Analysis

| Menu path | Key | How it works |
|---|---|---|
| Analysis ▸ Start Engine |  | Start or stop the engine analysing the board position. When beginning or pausing live analysis of the board. |
| Analysis ▸ Engines… |  | Open the engine manager to add, remove and configure chess engines. When adding an engine or editing an installed engine's configuration. |
| Analysis ▸ Engine Dictionary… |  | Open the collection of configured chess engines. Use this to inspect or manage installed engine definitions. |
| Analysis ▸ Compare Engines… |  | Open or use the comparison of chess engines. When comparing how different engines assess the same position. |
| Analysis ▸ Choose Engine for Review… |  | Choose the chess engine used for game review. When a game review should use a different engine. |
| Analysis ▸ Analyze This Position | F4 | Start engine analysis of the board position. Use this to obtain an engine assessment of the current position. |
| Analysis ▸ Explain ▸ Position |  | Request an analysis-grounded explanation of the board position. Use this to understand the position's relevant plans and features. |
| Analysis ▸ Explain ▸ Line |  | Explain the best available engine line, starting analysis if needed. Use this to understand a candidate continuation on the board. |
| Analysis ▸ Explain ▸ Move |  | Explain the current game move using the app's analysis. Use this to understand a decision in the recorded game. |
| Analysis ▸ Explain ▸ Comment |  | Explain the current stored game comment using the app's context. Use this when a written annotation is difficult to understand. |
| Analysis ▸ Annotate Game with AI… |  | Start or stop automatic engine annotation of the game. Use this to add grounded commentary while reviewing a game. |
| Analysis ▸ Fact-Check Annotations |  | Check the current game's annotations against available chess facts. Use this to find comments that need verification or correction. |
| Analysis ▸ Tablebase ▸ show |  | Show or hide the exact-endgame result display. Use this when studying positions covered by endgame tables. |
| Analysis ▸ Tablebase ▸ online lookup |  | Toggle online exact-endgame lookups in the analysis view. Use this when remote endgame results should be available. |
| Analysis ▸ Tablebase ▸ local folder… |  | Open the chooser for a local endgame-table folder. Use this when exact endgame files are installed on disk. |
| Analysis ▸ Opening Explorer |  | Open the opening explorer. When exploring the opening choices available from the board position. |

#### Training

| Menu path | Key | How it works |
|---|---|---|
| Training ▸ Tactics Trainer… |  | Open the tactics trainer with puzzles. When practicing concrete tactical puzzles. |
| Training ▸ Endgame Trainer… |  | Open the endgame trainer. Use this when you want to practise endgames. |
| Training ▸ Guess the Move… | Ctrl+G | Guess the next move of a game. When practicing prediction by choosing the next move yourself. |
| Training ▸ Train Repertoire… |  | Train your opening repertoire move by move. When rehearsing the moves of your prepared openings. |
| Training ▸ Play Against Engine… |  | Play a game against a chess engine (the computer). When you want the computer to play the opposing side. |
| Training ▸ Online ▸ Play Online (FICS)… |  | Play people online on the Free Internet Chess Server (FICS). When you want to play a person over the internet. |
| Training ▸ Online ▸ Play Online (Lichess)… |  | Play people or the Lichess computer online on lichess.org. When you want to play on Lichess. |
| Training ▸ Online ▸ Lichess Players… |  | Look up Lichess players, view rating history, challenge players, message and join teams. When you want to look up, challenge or message Lichess players or manage teams. |
| Training ▸ Online ▸ Lichess TV… |  | Watch live Lichess TV channels, games and tournament broadcasts. When you want to watch Lichess TV or live tournament broadcasts. |
| Training ▸ Online ▸ Lichess Tournaments… |  | Browse, join and withdraw from Lichess Arena and Swiss tournaments and simuls. When you want to join Lichess Arena or Swiss tournaments or simuls. |
| Training ▸ Online ▸ Lichess Puzzles… |  | Solve Lichess daily and themed puzzles, run Puzzle Storm and open Puzzle Racer. When you want to solve Lichess puzzles or run Puzzle Storm. |
| Training ▸ Online ▸ Stream to Twitch / YouTube… |  | Show your board, eval and clocks on Twitch or YouTube through OBS. When you stream or broadcast your chess live. |
| Training ▸ Engine Match… |  | Set up and run a match between two engines. When testing two engines against one another. |
| Training ▸ Tournament Director… |  | Run a tournament for people or engines: enter players, make pairings, record results and see the standings. When organising a club event or an engine tournament and you need pairings, results and standings kept for you. |
| Training ▸ Study Plan… |  | Make a study plan from your games. When deciding what to practice based on your own games. |
| Training ▸ Opponent Brief… |  | Open the opponent brief tool to prepare for an opponent. When preparing to face a specific opponent. |
| Training ▸ Training Set from Games… |  | Choose positions from database games for a training set. When turning a collection of games into practice material. |
| Training ▸ Check Game Results… |  | Run the game-quality report for recorded results. Use this to review games whose stored outcomes may be inconsistent. |

#### Tools

| Menu path | Key | How it works |
|---|---|---|
| Tools ▸ Book Editor… |  | Open the opening book editor. When inspecting or editing an opening book. |
| Tools ▸ Player Dictionary… |  | Open the player dictionary with every known player. When finding a player beyond the current collection's list. |
| Tools ▸ Player Card… |  | Open a player's card with ratings and statistics. When looking up a player's ratings and career statistics. |
| Tools ▸ Correspondence Games… |  | Open the correspondence games dialog. When managing games played by correspondence. |
| Tools ▸ ICCF Settings… |  | View or change correspondence-server settings. When configuring correspondence-server settings. |
| Tools ▸ Engine Console… |  | Open the engine console that shows the engine's raw messages. When diagnosing the messages exchanged with a running engine. |
| Tools ▸ Import Games… |  | Open the dialog that imports games into a database. When bringing games from another source into a database. |
| Tools ▸ Download Games… |  | Open the dialog that downloads games from the internet. When choosing an internet source from which to obtain games. |
| Tools ▸ Assistant |  | Open the Assistant conversation pane. Use this to request app operations in ordinary words. |
| Tools ▸ Choose Model… |  | Open the chooser for configured Assistant models. Use this to change the service or model handling requests. |
| Tools ▸ Voice Assistant |  | Toggle the app's voice-input interface. Use this when you want to dictate an app request. |
| Tools ▸ Assign File Types… |  | Open file-association settings for supported chess files. Use this when the app should handle a file type from the operating system. |
| Tools ▸ Install Legacy Fonts… |  | Open the installer for supported legacy chess fonts. Use this when older chess documents need their original symbols. |

#### View

| Menu path | Key | How it works |
|---|---|---|
| View ▸ Layout ▸ Save Layout |  | Save the current pane layout. When you want to return later to the current pane arrangement. |
| View ▸ Layout ▸ Save Layout As… |  | Open the dialog for saving the workspace under a layout name. Use this to preserve a new pane arrangement for later use. |
| View ▸ Layout ▸ Manage Layouts... |  | Manage the saved pane layouts. When organizing the arrangements you have saved. |
| View ▸ Board Style… |  | Open settings for the board's pieces, colors and display. Use this when tailoring the board for comfortable viewing. |
| View ▸ Increase Font Size | Ctrl+Shift++ | Make the text and fonts of the whole window bigger. When interface text is difficult to read at its current size. |
| View ▸ Decrease Font Size | Ctrl+Shift+− | Make the text and fonts of the whole window smaller. When interface text takes up too much space. |
| View ▸ Full-Screen | F11 | Enter or exit full screen mode. Use this when you want the window to fill the screen. |
| View ▸ Show Log… | Ctrl+L | Show the log window. Use this when you want to read what Chesswiz has been doing. |
| View ▸ Tip of the Day… |  | Open a tip about using the application. Use this when you want to discover a useful feature. |
| View ▸ Panes ▸ board |  | Show or hide the board pane. When changing whether the board occupies space in the layout. |
| View ▸ Panes ▸ editor |  | Show or hide the game editor (notation) pane. When changing whether the move notation occupies space in the layout. |
| View ▸ Panes ▸ game list |  | Show or hide the game list pane of the board tab. When changing whether a game list appears beside the board. |
| View ▸ Panes ▸ players |  | Show or hide the database's player table. Use this to browse players represented in stored games. |
| View ▸ Panes ▸ events |  | Show or hide the database's event table. Use this to browse tournaments represented in the collection. |
| View ▸ Panes ▸ sites |  | Show or hide the database's site table. Use this to browse venues represented in stored games. |
| View ▸ Panes ▸ annotators |  | Show or hide the database's annotator table. Use this to browse the authors of game comments. |
| View ▸ Panes ▸ positions |  | Show or hide the database's position table. Use this to browse stored position records. |
| View ▸ Panes ▸ tree |  | Show or hide the opening tree pane of the board tab. When database move statistics should be visible beside the board or put away. |
| View ▸ Panes ▸ analysis |  | Show or hide the engine analysis pane of the board tab. When live engine lines need more space or should be put away. |
| View ▸ Panes ▸ media |  | Show or hide the media pane (videos and streams) of the board tab. When a video lesson should be visible beside the board or put away. |
| View ▸ Panes ▸ report |  | Show or hide the report pane of the board tab. When a generated report should be visible beside the board or put away. |
| View ▸ Panes ▸ assistant |  | Show or hide the assistant pane. When you want to expose or put away the conversation area. |
| View ▸ Panes ▸ explorer |  | Show or hide the opening explorer pane of the board tab. When opening choices should be visible beside the board or put away. |
| View ▸ Open 3D Board |  | Open the separate three-dimensional board viewer. Use this when you want a perspective view in its own window. |
| View ▸ Open WebGL 3D Board |  | Open the browser-based three-dimensional board viewer. Use this to view the position using the web board display. |
| View ▸ 3D Board in Main Window |  | Toggle the three-dimensional board inside the main window. Use this to study the position in an embedded perspective view. |
| View ▸ Colors ▸ Ordinary Monitor |  | Apply the selected light or dark interface color scheme. Use this to match the workspace colors to your viewing conditions. |
| View ▸ Icon Size ▸ Medium |  | Apply the selected size to toolbar icons. Use this when toolbar controls need more or less space. |
| View ▸ Language ▸ Deutsch |  | Switch interface text to the selected supported language. Use this when you prefer menus and dialogs in another language. |
| View ▸ Layout ▸ Set docking arrow size |  | Set the pixel size of pane-docking target arrows. Use this when drop targets are hard to see or too large. |
| View ▸ Layout ▸ Show docking points |  | Show or hide docking targets in the active workspace. Use this when moving panes between docked positions. |
| View ▸ Layout ▸ Fold all Titlebars |  | Fold or unfold all pane title bars in the active layout. Use this when changing header space across the whole workspace. |
| View ▸ Layout ▸ Restore named layout |  | Restore a saved pane arrangement by its name. Use this to return to a workspace you have already saved. |
| View ▸ Layout ▸ Toggle layout pane |  | Toggle the specified pane in the active workspace layout. Use this to bring a known workspace view into or out of sight. |
| View ▸ Theme ▸ default |  | Apply the selected installed interface theme. Use this to change the appearance of window controls. |

#### Help

| Menu path | Key | How it works |
|---|---|---|
| Help ▸ Help | F1 | Open the Chesswiz help manual. Use this when you need the manual or a reference. |
| Help ▸ Bug Report |  | Open a form to report a problem with Chesswiz. Use this to prepare a report about behavior that failed. |
| Help ▸ Feature Request |  | Open a form to suggest an improvement to Chesswiz. Use this to describe a capability you would like added. |
| Help ▸ Support Chesswiz… |  | Open the Chesswiz support page to donate or support development. When you want to contribute to continued application development. |
| Help ▸ About Chesswiz… |  | Open the program-information dialog. Use this to inspect the installed application's identity and version. |

### 3.2 Keyboard-only actions

| Action | Key | How it works |
|---|---|---|
| Edit comment after move | Control-a | Add a comment after the current move. Use this when you want to explain or annotate a move. |
| Edit comment before move | Control-Shift-A | Add a comment before the current move. Use this when you want a note to appear before a move. |
| Go back one move | Left | Go back one move in the game. Use this when you want to step backwards through the moves. |
| Go forward one move | Right | Play the next recorded move on the board. Use this to follow a game one step at a time. |
| Go into previous variation | m | Move to the previous available variation at the board position. Use this when returning to an earlier branch choice. |
| Go to end of game | End | Go to the end of the game. When you want to inspect the game's final recorded position. |
| Go to start of game | Home | Go to the start of the game. When replaying the game from its initial arrangement. |
| Good move | exclam | Mark the current move as a good move. Use this when a move deserves praise in the annotation. |
| Poor move | question | Mark the current move as a bad move. Use this when a move deserves criticism in the annotation. |

### 3.3 Right-click menus


#### C1: Board square / position (right-click the board)

| Entry | Key | How it works |
|---|---|---|
| Board Style… |  | Open the board appearance settings for the clicked board. Use this when the board colors or pieces are hard to see. |
| Copy Diagram |  | Copy a picture of the current position to the clipboard. Use this to include the board in another document. |
| Copy FEN |  | Copy the current position as position text to the clipboard. Use this to transfer the exact board position to another chess tool. |
| Edit Annotation… |  | Open the symbol editor for the current move. Use this to mark a move as good, bad or interesting. |
| Flip Board |  | Turn the clicked board around so the other side is at the bottom. Use this to study the position from the opponent's side. |
| Insert Null Move |  | Insert a turn without a piece move at the current position. Use this to test a threat as if the opponent had passed. |
| Set Start Board… |  | Open the piece-placement editor from the clicked board. Use this to enter a position that does not begin with the usual arrangement. |
| Set Start Position… |  | Open the starting-position chooser from the clicked board. Use this to select the initial arrangement for a new game. |
| Chess960 |  | Choose a starting arrangement with the Chess960 piece-placement rules. Use this to begin a game with a randomized back rank and its castling rules. |
| Set Up Position… |  | Open a board where you can place the pieces yourself. Use this when you have a position to enter by hand. |
| Shuffle |  | Choose a shuffled starting arrangement for the pieces. Use this to explore games with a different initial back rank. |
| Standard |  | Choose the usual starting arrangement for ordinary chess. Use this to return from an unusual setup to a regular game. |
| Symm960 |  | Choose a symmetric randomized starting arrangement. Use this to explore the symmetric form of shuffled chess. |
| Start Position |  | Show the starting-arrangement choices for the board. Use this when deciding between ordinary chess and a shuffled start. |

#### C2: A move in the notation

| Entry | Key | How it works |
|---|---|---|
| Add New Variation |  | Insert the existing variation into its parent line. Use this to include a side line before the parent continuation. |
| Infix symbols |  | Open the move-symbol editor for symbols within the notation. Use this to attach a symbolic assessment to the current move. |
| Prefix symbols |  | Open the move-symbol editor for symbols before the move. Use this to add a symbolic note ahead of the move text. |
| Suffix symbols |  | Open the move-symbol editor for symbols after the move. Use this to mark the quality of a move beside its notation. |
| Annotate |  | Show the choices for annotating the current move with symbols. Use this when a short symbol can express your comment. |
| Collapse Variations |  | Fold the game's alternative lines in the notation. Use this to read the main continuation without expanded branches. |
| Edit Comment After |  | Open the text comment following the current move for editing. Use this to explain the position reached by that move. |
| Edit Comment Before |  | Open the text comment preceding the current move for editing. Use this to introduce a move before the reader reaches it. |
| Copy Comments… |  | Open the options for copying the game's comments. Use this to reuse written annotations separately from the moves. |
| Exchange Move |  | Exchange the current game continuation with the selected alternative move. Use this when a side-line move should take the current move's place. |
| Expand Variations |  | Unfold the game's alternative lines in the notation. Use this to read branches that are currently hidden. |
| Explain Move |  | Request an explanation of the current move using the app's analysis. Use this when reviewing why a move was played. |
| Import PGN Game… |  | Read a complete game from the system clipboard into the notation. Use this after copying a game in portable game text. |
| Import PGN Variation… |  | Read clipboard moves as an alternative line at the current position. Use this to add analysis copied from another source. |
| Insert Diagram |  | Mark the current move for a diagram viewed from White's side. Use this to illustrate the position in printed or displayed notation. |
| Insert Diagram from Black |  | Mark the current move for a diagram viewed from Black's side. Use this when an illustration should face the other player. |
| Load First Game with this Continuation |  | Load the first database game containing the chosen continuation. Use this to study a full game that follows this move. |
| Marks Palette… |  | Open the palette for colored board marks and arrows. Use this to draw attention to squares or plans in the position. |
| Edit Move Information… |  | Open the editor for information attached to the current move. Use this to change recorded analysis or clock details for a move. |
| New Main Line |  | Promote the selected continuation into the game's main line. Use this when the alternative should become the principal continuation. |
| Promote Variation |  | Raise the current variation above its competing continuation. Use this when organizing the preferred order of alternatives. |
| Redo … |  | Reapply the last undone change to the game notation. Use this after undoing an edit you want to keep. |
| Remove Variation |  | Delete the current alternative line from the game. Use this to remove analysis you no longer want to retain. |
| Replace Move |  | Replace the game's current move with the selected continuation. Use this to correct a move while editing the game. |
| Strip |  | Show choices for removing moves or annotations from the game. Use this to clean selected kinds of recorded content. |
| Annotations |  | Remove symbolic move annotations from the current game. Use this to retain moves and prose without quality symbols. |
| Comments |  | Remove text comments from the current game. Use this to obtain move notation without prose annotations. |
| Move information |  | Remove stored move-information fields from the current game. Use this to discard per-move details while retaining the moves. |
| Language |  | Show the available languages for selective comment removal. Use this when cleaning comments in only one language. |
| Marks |  | Remove colored squares and arrows stored with the game. Use this when board markings should no longer accompany the moves. |
| Moves |  | Remove the move text from the current game. Use this when retaining the game record without its played continuation. |
| Truncate |  | Delete all moves after the current one. When the continuation after the current position should be discarded. |
| Variations |  | Remove alternative continuations from the current game. Use this to keep only the main game line. |
| Try Variation |  | Switch temporary trial analysis on or off for the notation. Use this to explore moves without committing them to the game. |
| Undo … |  | Reverse the last change to the game notation. Use this to recover from an unwanted edit. |

#### C3: A game row in the game list

| Entry | Key | How it works |
|---|---|---|
| Ask About This Game |  | Send the selected game's identity to the Assistant. Use this when you want help with a particular database row. |
| Browse Game… |  | Open the selected game in a separate game browser. Use this to inspect a game without replacing the board's game. |
| Copy Game |  | Copy selected game rows to the internal game clipboard. Use this to transfer one or more games between databases. |
| Delete / Undelete Game |  | Toggle the deletion mark on the selected game. Use this to exclude a game or restore a previously marked record. |
| Edit Characteristics… |  | Open the selected game's player and event information for editing. Use this to correct the details identifying a database game. |
| White Opening |  | Toggle the selected game's White-opening classification flag. Use this to collect examples of openings played with White. |
| Brilliancy |  | Toggle the selected game's brilliancy classification flag. Use this to collect games you regard as especially impressive. |
| Blunder |  | Toggle the selected game's blunder classification flag. Use this to collect games featuring a serious mistake. |
| User |  | Toggle the selected game's custom user classification flag. Use this to group games under your own category. |
| Best Game |  | Toggle the selected game's best-game classification flag. Use this to collect games you want to single out as favorites. |
| Decided Tournament |  | Toggle the selected game's tournament-decider classification flag. Use this to collect games that settled an event's outcome. |
| Model Game |  | Toggle the selected game's model-game classification flag. Use this to collect instructive examples worth revisiting. |
| Strategy |  | Toggle the selected game's strategy classification flag. Use this to collect examples of long-term planning. |
| Attack |  | Toggle the selected game's attack classification flag. Use this to collect examples of offensive play. |
| Sacrifice |  | Toggle the selected game's sacrifice classification flag. Use this to collect examples of giving up material for compensation. |
| Defense |  | Toggle the selected game's defense classification flag. Use this to collect examples of resisting an opponent's threats. |
| Black Opening |  | Toggle the selected game's Black-opening classification flag. Use this to collect examples of openings played with Black. |
| Middle Game |  | Toggle the selected game's middlegame classification flag. Use this to collect games for studying play after the opening. |
| End Game |  | Toggle the selected game's endgame classification flag. Use this to collect games for studying reduced-piece positions. |
| Novelty |  | Toggle the selected game's novelty classification flag. Use this to collect games featuring an opening innovation. |
| Pawn Structure |  | Toggle the selected game's pawn-structure classification flag. Use this to collect examples of characteristic pawn formations. |
| Tactics |  | Toggle the selected game's tactics classification flag. Use this to collect examples of forcing combinations. |
| King Side |  | Toggle the selected game's kingside classification flag. Use this to collect examples centered on that side of the board. |
| Queen Side |  | Toggle the selected game's queenside classification flag. Use this to collect games centered on the other side of the board. |
| Flags |  | Show the available classification flags for the selected game. Use this to organize games by themes for later retrieval. |
| Games Like This… |  | Find database games similar to the selected game. Use this to gather comparable examples for study. |
| Load Game |  | Load the selected database game onto the main board. Use this to follow its moves in the normal game view. |
| Merge Game… |  | Open choices for combining the selected database game with another game. Use this to combine its continuations with an open game. |
| Open URL |  | Open the web address recorded as the selected game's site. Use this when a game's site field contains a link you want to visit. |
| Overview… |  | Open a compact overview of the selected game. Use this to scan its positions before choosing it for study. |
| Paste Game(s) |  | Paste games from the internal clipboard into the selected database. Use this to transfer games copied from another database. |
| Ascending |  | Order the game rows upward by the clicked column. Use this to inspect that column from its smallest value. |
| Date |  | Order the game rows by the column under the menu. Use this to regroup the visible games by a chosen field. |
| Descending |  | Order the game rows downward by the clicked column. Use this to inspect that column from its largest value. |
| Sort Ascending |  | Sort the game list in ascending order using the clicked field. Use this to bring the earliest or smallest entries to the top. |
| Sort by this Column |  | Sort the games by the field selected in the column menu. Use this to change which game information controls the row order. |
| Sort Descending |  | Sort the game list in descending order using the clicked field. Use this to bring the latest or largest entries to the top. |
| Show Tournament Table… |  | Open the tournament table associated with the selected game. Use this to see the game's event results in context. |

#### C4: A database in the database switcher

| Entry | Key | How it works |
|---|---|---|
| Close |  | Close the selected database after checking for unsaved changes. Use this when that database is no longer needed. |
| Download Games… |  | Open game downloads for the active database. Use this to obtain published game collections. |
| Export |  | Show export destinations for games in the selected database view. Use this to choose a file or study destination. |
| Lichess study… |  | Open study-upload options for the selected database view. Use this to share a collection through a Lichess study. |
| PGN file… |  | Open text-file export for the selected database's games. Use this to exchange the collection in portable game notation. |
| Help… |  | Open the app's help from the database menu. Use this when you need instructions while working with databases. |
| Import |  | Show the available game-import sources. Use this when adding recorded games to a database. |
| PGN file… |  | Open the file chooser for importing portable game text. Use this to add games saved in a text file. |
| Maintenance |  | Show maintenance operations for the selected database. Use this when cleaning or reorganizing its stored records. |
| Compact database |  | Compact the selected database to reclaim unused storage. Use this after marking records for deletion or making many changes. |
| PGN file… |  | Create a database backed by a portable-game-text file. Use this when the collection should remain in an exchangeable text format. |
| Chesswiz database… |  | Create a database in Chesswiz's own storage format. Use this for a new collection managed within the app. |
| New Database |  | Show the database formats available for a new collection. Use this when deciding how to store a new set of games. |
| Open Database… |  | Open the file chooser for loading a database. Use this when your game collection is not already open. |
| Open in New Tab |  | Open the selected database in an additional database tab. Use this to keep another view of the same collection available. |
| Open Recent |  | Show previously opened database files for reopening. Use this to return to a collection without locating its file again. |
| Properties… |  | Show the selected database's information and properties. Use this to inspect its identity and settings. |
| Read-only |  | Toggle whether the selected database accepts changes. Use this to protect a collection from accidental edits. |
| Reports |  | Show reports available for the selected database. Use this when choosing a summary of the collection. |
| Opening report |  | Open an opening report using the current database context. Use this to study the opening represented by your current work. |
| Save Changes |  | Write pending changes in the selected database to storage. Use this before closing a collection with unsaved edits. |
| Search |  | Show database search choices from the switcher menu. Use this when deciding how to narrow the game collection. |
| Current game |  | Search the database using the current game. Use this to search from the game's position or identifying details. |
| Large |  | Set database-switcher icons to the large size. Use this when database symbols are difficult to recognize. |
| Normal |  | Set database-switcher icons to the normal size. Use this to restore the usual database-symbol scale. |
| Small |  | Set database-switcher icons to the small size. Use this to fit more collection symbols in the switcher. |
| Symbol Size |  | Show size choices for database-switcher icons. Use this to adjust how much room the database symbols occupy. |

#### C5: A player, event or site (tables and cards)

| Entry | Key | How it works |
|---|---|---|
| Show Tournament Table… |  | Open the tournament table for the selected event. Use this to compare the event's players and results. |
| Open URL |  | Open the site link associated with the selected event. Use this when the event record includes a web address. |
| Open In Switcher |  | Open the matching games from the selected table in a database tab. Use this to browse the games belonging to the selected name. |
| Save Working Set... |  | Save the matching games from the selected table as a named collection. Use this to keep the selected name's games together for later study. |
| Insights… |  | Open the insights report for the selected player. Use this to inspect patterns in that player's stored games. |
| Open Games in Switcher |  | Open a filtered database tab for the selected player, event or site. Use this to browse all games belonging to that selection. |
| Insights |  | Show insights about the player selected in the table. Use this to review that player's patterns and tendencies. |
| Prep Report |  | Open the preparation report for the selected player. Use this when gathering material about an opponent. |
| Show Player Card |  | Open the information card for the selected player. Use this to inspect that player's recorded details. |
| Open URL |  | Show available web links for the selected player. Use this to visit a source associated with the player record. |
| Prep Report… |  | Open an opponent-preparation report for the selected player. Use this before studying how to face that player. |
| Save as Working Set |  | Save a filtered working set for the selected player, event or site. Use this to retain the matching games as a named collection. |
| Open URL |  | Open the web address recorded for the selected site. Use this when a venue entry contains a useful link. |
| Event |  | Sort the selected event table by event in ascending order. Use this to reorder the current named table. |
| Event |  | Sort the selected event table by event in descending order. Use this to reorder the current named table. |
| Event Country |  | Sort the selected event table by eventCountry in ascending order. Use this to reorder the current named table. |
| Event Country |  | Sort the selected event table by eventCountry in descending order. Use this to reorder the current named table. |
| Event Date |  | Sort the selected event table by eventDate in ascending order. Use this to reorder the current named table. |
| Event Date |  | Sort the selected event table by eventDate in descending order. Use this to reorder the current named table. |
| Mode |  | Sort the selected event table by eventMode in ascending order. Use this to reorder the current named table. |
| Mode |  | Sort the selected event table by eventMode in descending order. Use this to reorder the current named table. |
| Event Type |  | Sort the selected event table by eventType in ascending order. Use this to reorder the current named table. |
| Event Type |  | Sort the selected event table by eventType in descending order. Use this to reorder the current named table. |
| Frequency |  | Sort the selected event table by frequency in ascending order. Use this to reorder the current named table. |
| Frequency |  | Sort the selected event table by frequency in descending order. Use this to reorder the current named table. |
| Site |  | Sort the selected event table by site in ascending order. Use this to reorder the current named table. |
| Site |  | Sort the selected event table by site in descending order. Use this to reorder the current named table. |
| Time Mode |  | Sort the selected event table by timeMode in ascending order. Use this to reorder the current named table. |
| Time Mode |  | Sort the selected event table by timeMode in descending order. Use this to reorder the current named table. |
| Federation |  | Sort the selected player table by federation in ascending order. Use this to reorder the current named table. |
| Federation |  | Sort the selected player table by federation in descending order. Use this to reorder the current named table. |
| Fide ID |  | Sort the selected player table by federationId in ascending order. Use this to reorder the current named table. |
| Fide ID |  | Sort the selected player table by federationId in descending order. Use this to reorder the current named table. |
| First Name |  | Sort the selected player table by firstName in ascending order. Use this to reorder the current named table. |
| First Name |  | Sort the selected player table by firstName in descending order. Use this to reorder the current named table. |
| Frequency |  | Sort the selected player table by frequency in ascending order. Use this to reorder the current named table. |
| Frequency |  | Sort the selected player table by frequency in descending order. Use this to reorder the current named table. |
| Last Name |  | Sort the selected player table by lastName in ascending order. Use this to reorder the current named table. |
| Last Name |  | Sort the selected player table by lastName in descending order. Use this to reorder the current named table. |
| Info Flag |  | Sort the selected player table by playerInfo in ascending order. Use this to reorder the current named table. |
| Info Flag |  | Sort the selected player table by playerInfo in descending order. Use this to reorder the current named table. |
| Rating: Elo |  | Sort the selected player table by rating1 in ascending order. Use this to reorder the current named table. |
| Rating: Elo |  | Sort the selected player table by rating1 in descending order. Use this to reorder the current named table. |
| Rating: DWZ |  | Sort the selected player table by rating2 in ascending order. Use this to reorder the current named table. |
| Rating: DWZ |  | Sort the selected player table by rating2 in descending order. Use this to reorder the current named table. |
| Rating Type |  | Sort the selected player table by ratingType in ascending order. Use this to reorder the current named table. |
| Rating Type |  | Sort the selected player table by ratingType in descending order. Use this to reorder the current named table. |
| Sex |  | Sort the selected player table by sex in ascending order. Use this to reorder the current named table. |
| Sex |  | Sort the selected player table by sex in descending order. Use this to reorder the current named table. |
| Title |  | Sort the selected player table by title in ascending order. Use this to reorder the current named table. |
| Title |  | Sort the selected player table by title in descending order. Use this to reorder the current named table. |
| Type |  | Sort the selected player table by type in ascending order. Use this to reorder the current named table. |
| Type |  | Sort the selected player table by type in descending order. Use this to reorder the current named table. |
| Sort (ascending) |  | Choose a column to sort the named table in ascending order. Use this to choose how the selected table is ordered. |
| Sort (descending) |  | Choose a column to sort the named table in descending order. Use this to choose how the selected table is ordered. |

#### C6: An engine line in the analysis pane

| Entry | Key | How it works |
|---|---|---|
| Add All |  | Add all displayed engine continuations as game variations. Use this to preserve several candidate lines for later study. |
| Add Include |  | Merge all displayed engine lines into the game's existing branches. Use this to incorporate multiple analyses without separate duplicate branches. |
| Add Line |  | Add the selected full engine continuation as a variation. Use this to retain the engine's sequence beside the game line. |
| Add Merge |  | Merge the selected engine continuation into existing game branches. Use this when the analysis overlaps moves already recorded. |
| Add Move |  | Add the first move of the selected engine line as a variation. Use this to retain a candidate without its full continuation. |
| Add Sequence |  | Append the selected engine sequence, using a variation mid-line. Use this to continue the game with the engine's suggested sequence. |
| Best-First Order |  | Toggle whether stronger engine continuations appear first. Use this to choose between ranked display and the engine's line order. |
| Close Engine |  | Stop and close the engine attached to this analysis pane. Use this when that engine's analysis is no longer needed. |
| Copy FEN |  | Copy the current board position as text from the analysis menu. Use this to transfer the analyzed position elsewhere. |
| Copy Line |  | Copy the selected engine continuation as move text. Use this to transfer a candidate sequence to another editor. |
| Explain Line |  | Request a grounded explanation of the selected engine continuation. Use this to understand the plan shown by the engine. |
| Insert Move as Comment |  | Insert the first engine move as a comment in the game. Use this to mention a candidate without adding another branch. |
| 1 |  | Limit each engine variation's display to one text line. Use this to keep analysis rows compact. |
| 2 |  | Allow two text lines for each engine variation. Use this to read longer continuations without a tall pane. |
| 3 |  | Allow three text lines for each engine variation. Use this to see more moves in each candidate continuation. |
| 4 |  | Allow four text lines for each engine variation. Use this when detailed continuations need more display space. |
| Lines per Variation |  | Show choices for how many text lines each engine variation uses. Use this to balance readable continuations against pane height. |
| Lock Engine |  | Toggle whether this engine remains on its analyzed position. Use this to keep one position under analysis while browsing the game. |
| 1 |  | Ask the engine to display one candidate continuation. Use this to concentrate analysis on the strongest line. |
| 2 |  | Ask the engine to display two candidate continuations. Use this to compare a pair of possible moves. |
| 3 |  | Ask the engine to display three candidate continuations. Use this to compare several promising moves. |
| 4 |  | Ask the engine to display four candidate continuations. Use this to inspect a broader set of move choices. |
| 5 |  | Ask the engine to display five candidate continuations. Use this to inspect more alternatives in the position. |
| 6 |  | Ask the engine to display six candidate continuations. Use this to study a wide range of plausible moves. |
| 7 |  | Ask the engine to display seven candidate continuations. Use this when an extensive move comparison is useful. |
| 8 |  | Ask the engine to display eight candidate continuations. Use this to inspect the largest listed set of candidates. |
| Multiple Variations |  | Show choices for the number of engine candidate lines. Use this to decide how many possible moves to compare. |
| Opponents View |  | Toggle analysis as if the opponent had the next turn. Use this to examine the other side's threats. |
| Pause / Resume |  | Pause or resume the engine attached to this analysis pane. Use this when temporarily stopping computation while keeping the engine open. |
| Pin to Repertoire |  | Save the selected engine continuation into a repertoire database. Use this to retain analysis for opening preparation. |
| Setup Engine… |  | Open settings for the engine in this analysis pane. Use this to change that engine's analysis options. |
| Setup Eval Edges… |  | Open the settings for engine evaluation display boundaries. Use this to adjust how evaluation ranges are shown. |

#### C7: A media entry

| Entry | Key | How it works |
|---|---|---|
| Open in External Player |  | Open the selected media with an external player. Use this when you prefer another installed playback program. |
| Open Report |  | Select the media entry and open its associated report. Use this to read the report attached to a media item. |
| Open Stream… |  | Open a video stream or a live broadcast. Use this when you want to watch a stream or follow a live tournament. |
| Play |  | Select and play the chosen media entry. Use this to watch or hear the recording attached to the game. |
| Show in Board |  | Toggle the media inset inside the board area. Use this to watch the recording beside the chess position. |
| Position follow |  | Let the media video follow the board position. When selecting a move should seek to its moment in the video. |
| Timeline |  | Let the media video follow its own timeline. When watching the video continuously should advance the game alongside it. |
| Sync Options |  | Choose how a video in the media pane follows the game moves (not file or cloud syncing). When the video and the moves should follow one another differently. |

#### C8: A row in the opening tree

| Entry | Key | How it works |
|---|---|---|
| Analyze This Position |  | Start engine analysis for the position represented by the tree row. Use this to assess a continuation found in database games. |
| Automatic Search |  | Toggle opening-tree searches as the board position changes. Use this to choose automatic updates or manual searching. |
| Copy Line |  | Copy the played line and selected tree continuation as move text. Use this to transfer an opening sequence without changing the board. |
| Highlight Novelties |  | Toggle highlighting of moves identified as novelties in the tree. Use this to spot continuations outside the reference games. |
| Search Inside Variations |  | Toggle searching alternative lines within stored games. Use this when side variations should contribute to tree results. |
| Lock Reference Base |  | Toggle whether the tree keeps its selected reference database. Use this when changing active databases should not change the comparison source. |
| move actions for this continuation |  | Show move-insertion and game-loading choices for this tree continuation. Use this to act on a move found in the opening tree. |
| Opening Report… |  | Open the opening report for the current tree position. Use this to study the games and continuations from that opening. |
| None |  | Clear the chosen tree reference by selecting the clipboard database. Use this to stop comparing against a separate reference collection. |
| Reference Base |  | Show choices for the tree's comparison database. Use this when choosing which collection should define reference play. |
| Save Line to Repertoire… |  | Save the board line and selected tree move to a repertoire. Use this to retain a database continuation for practice. |
| Exact |  | Select exact position matching for opening-tree searches. Use this when the tree should match the board position precisely. |
| Fast |  | Select the fast opening-tree search mode. Use this when a quicker tree update is more useful than a broader search. |
| Slow |  | Select the slower opening-tree search mode. Use this when thorough opening-tree results matter more than speed. |
| Search Mode |  | Show the available opening-tree search methods. Use this to choose how the database is searched for continuations. |
| Start Search |  | Start a database search for the current opening-tree position. Use this after changing the board with automatic updates disabled. |

#### C9: A pane header (each pane's own menu)

| Entry | Key | How it works |
|---|---|---|
| Amalgamate |  | Join the pane's container with its neighbor or separate it again. Use this when adjusting how docked pane groups share space. |
| Best-First Order |  | Toggle best-first ordering from the analysis pane header. Use this when candidate lines should follow strength rather than arrival order. |
| Lines per Variation |  | Show text-height choices for variations in this analysis pane. Use this to give long engine lines more readable space. |
| Multiple Variations |  | Show candidate-count choices for this analysis pane. Use this when comparing more or fewer engine alternatives. |
| Opponents View |  | Toggle the engine's opponent-turn view from the pane header. Use this to inspect threats for the other side without moving the board. |
| Set Up Engine… |  | Open this analysis pane's engine settings from its header. Use this when changing the selected engine's options. |
| Appearance |  | Show board appearance choices in the pane-header menu. Use this to adjust visible board elements while arranging the workspace. |
| Clear Conversation |  | Erase the Assistant's current conversation. Use this to begin a new conversation without earlier messages. |
| Choose Model… |  | Open the model chooser from the Assistant pane. Use this when selecting the configured service and model for requests. |
| Board Style… |  | Open appearance settings from the board pane's header. Use this to customize the board while arranging its pane. |
| Close Pane |  | Close the pane selected by its header menu. Use this when that workspace view is no longer needed. |
| Docking Points |  | Toggle visible docking targets for the current workspace. Use this when positioning panes around one another. |
| Source |  | Show source choices for the opening explorer. Use this when choosing which game collection supplies opening statistics. |
| Flip Board |  | Reverse the main board's viewing direction from its pane menu. Use this to look at the game with the other player at the bottom. |
| Float/Dock |  | Detach the pane into a window or dock it back. Use this when you want to position a view independently. |
| Fold Title Bar |  | Fold or unfold the pane's title bar. Use this to change how much header space the docked pane uses. |
| Columns |  | Show column-visibility choices for the game list. Use this to decide which game fields appear in the table. |
| Filters |  | Show filtering choices for the game list. Use this when narrowing the visible game records. |
| Save Search Presets |  | Show options for saving and reusing game-search presets. Use this when a frequently used search should be retained. |
| Sort |  | Show ordering choices for the pane's table rows. Use this to organize visible records by a different field. |
| Hide When Leaving Tab |  | Toggle whether a floating pane hides when leaving its tab. Use this when a separate window should follow its workspace tab. |
| Layout |  | Show workspace arrangement choices from the pane header. Use this when restoring or adjusting a pane arrangement. |
| Maximise/Restore Pane |  | Enlarge the selected pane to its workspace or restore its previous size. Use this to concentrate on one view temporarily. |
| Show in Board |  | Toggle the board's media inset from the media pane header. Use this when a recording should appear alongside the position. |
| Open Stream… |  | Open the stream-entry dialog from the media pane. Use this to play a recording available at a stream address. |
| Sync Options |  | Choose how a video in the media pane follows the game moves (not file or cloud syncing). When choosing whether playback or board navigation leads a lesson. |
| Configure Notation… |  | Open the notation editor setup (display, layout, fonts) from the notation pane header. Use this when tailoring how recorded moves and comments appear. |
| Diagrams |  | Toggle embedded diagrams in the game's notation. Use this to choose whether marked positions appear as board pictures. |
| Display |  | Show notation appearance options in the pane-header menu. Use this to adjust readability without editing the game. |
| Emoticons |  | Toggle pictorial emoticons in the notation display. Use this to choose how expressive comment symbols are rendered. |
| Font Size |  | Show text-size controls for the notation pane. Use this when the game text is too large or too small. |
| Decrease |  | Reduce text size in the selected notation pane. Use this to fit more of the game on screen. |
| Increase |  | Increase text size in the selected notation pane. Use this when moves and comments are hard to read. |
| Reset |  | Restore the selected notation pane's default text size. Use this after temporary text-size adjustments. |
| Language Selection |  | Show language-selection choices for displayed game comments. Use this to choose which translations appear in the notation. |
| Markers |  | Toggle move markers in the notation display. Use this when special markers should be visible or concealed. |
| Move Info |  | Show choices for displaying information attached to moves. Use this to choose which recorded analysis or clock fields appear. |
| Move Notation |  | Show choices for the written form of chess moves. Use this when selecting how piece names and moves are displayed. |
| Numbering |  | Toggle variation numbering in the notation display. Use this when numbered branches would make analysis easier to follow. |
| Spacing |  | Toggle paragraph spacing in the notation display. Use this to change separation between blocks of game text. |
| Analysis pane |  | Show or hide the engine-analysis pane. Use this when bringing engine continuations into the workspace. |
| Assistant pane |  | Show or hide the Assistant pane from the pane menu. Use this to make the conversation view available in the workspace. |
| Board pane |  | Show or hide the chessboard pane. Use this when arranging the workspace around the board. |
| Explorer pane |  | Show or hide the opening-explorer pane. Use this when opening statistics should be part of the workspace. |
| Game list pane |  | Show or hide the game-list pane. Use this when browsing game records beside the board. |
| Media pane |  | Show or hide the media pane. Use this when recordings should be available beside the game. |
| Notation pane |  | Show or hide the game-notation pane. Use this when moves and comments should be visible beside the board. |
| Players / Events / Sites / Annotators / Positions panes |  | Show or hide the player-information table pane. Use this when browsing the people associated with database games. |
| Report / Info pane |  | Show or hide the report and information pane. Use this when reviewing generated reports alongside the board. |
| Tree pane |  | Show or hide the opening-tree pane. Use this when database continuations should be visible with the position. |
| Family |  | Show typeface choices for the displayed report. Use this when changing the report's letter style. |
| Font |  | Show report text-size and typeface controls. Use this to improve the report's readability. |
| Size |  | Show text-size choices for the displayed report. Use this when report text needs a different scale. |
| Zoom |  | Show point-size choices for magnifying report text. Use this to make a displayed report easier to read. |
| Start Position |  | Show initial-arrangement choices from the board pane. Use this to begin a different kind of game from the pane header. |
| Stay On Top |  | Toggle whether the floating pane stays above other windows. Use this to keep a separate workspace view visible while working. |
| Filter |  | Show filtering choices for the selected information table. Use this to narrow the table's visible records. |
| Show Tablebase |  | Toggle exact-endgame information from the board pane header. Use this when checking a position covered by endgame tables. |
| Automatic Search |  | Toggle automatic tree updates from the tree pane header. Use this when browsing should update database continuations automatically. |
| Highlight Novelties |  | Toggle novelty highlighting from the tree pane header. Use this to identify unfamiliar continuations while browsing the tree. |
| Reference Base |  | Show reference-database choices from the tree pane header. Use this when comparing the tree against another game collection. |
| Search Mode |  | Show search-method choices from the tree pane header. Use this to balance tree-search speed against the matching method. |

#### C10: A table column header

| Entry | Key | How it works |
|---|---|---|
| Auto Stretch Column |  | Toggle whether the selected column stretches with its table. Use this to decide which columns absorb extra window width. |
| Configure… |  | Open display settings for the selected table column. Use this when changing how a particular column appears. |
| Fill Column |  | Show or hide the filler column at the table's right edge. Use this to choose whether unused table width is filled. |
| Fit Columns |  | Resize columns to fit the available table width. Use this when the table should occupy its pane neatly. |
| Hide |  | Hide the selected table column. Use this to remove a field you do not need to see. |
| Optimize Columns |  | Choose widths that fit the selected table's contents. Use this when displayed values need more suitable widths. |
| Show Column |  | Show the list of hidden or available table columns. Use this to bring an omitted field back into view. |
| Squeeze Columns |  | Reduce table-column widths using the compact sizing mode. Use this when fitting more fields on screen matters. |

#### C11: A comment in the comment editor

| Entry | Key | How it works |
|---|---|---|
| Add Language |  | Add a language section to the comment being edited. Use this when the same position needs comments in several languages. |
| Classify Comment |  | Label the selected comment by the kind of annotation it contains. Use this to organize an annotation by its content. |
| Clear |  | Erase the current comment editor's text. Use this to start the current comment again. |
| Copy |  | Copy selected comment content to the clipboard. Use this to reuse part of an annotation elsewhere. |
| Copy Text |  | Copy the current comment into another language section. Use this as a starting text for another translation. |
| Cut |  | Remove the selected comment content and copy it to the clipboard. Use this to move part of a comment elsewhere. |
| Detect Language |  | Detect the language of the comment being edited. Use this when pasted text is under the wrong language section. |
| Display Emoticons |  | Switch comment emoticons between pictures and their text forms. Use this when choosing how expressive symbols appear in the editor. |
| Draft Comment |  | Draft a position comment in the editor for your review. Use this when you want a grounded starting point for an annotation. |
| Explain Comment |  | Request an explanation of the current comment in its position. Use this when an annotation's meaning is unclear. |
| Format |  | Show text-formatting options for the comment selection. Use this when emphasizing or arranging an annotation. |
| Insert Emoticon |  | Insert a chosen emoticon into the comment. Use this to express a reaction with a visual symbol. |
| Insert Symbol |  | Insert a chosen chess symbol into the comment. Use this when a piece or assessment symbol is clearer than words. |
| Paste |  | Insert clipboard content into the comment editor. Use this to reuse text you have already copied. |
| Redo |  | Reapply the last undone comment edit. Use this when a reversed text change should be restored. |
| Revert |  | Restore the comment to its original editor contents. Use this to discard your unsaved comment edits. |
| Select All |  | Select all text in the current comment editor. Use this before copying or replacing the entire annotation. |
| Switch Language |  | Show the comment text for a chosen language. Use this to review another translation of the same annotation. |
| Translate Comment |  | Show target-language choices for translating the comment. Use this when creating another language version of an annotation. |
| Undo |  | Reverse the last edit in the comment editor. Use this to recover comment text changed by mistake. |

#### C12: The game bar (a game tab)

| Entry | Key | How it works |
|---|---|---|
| Clear History |  | Clear the list of previously opened games. Use this when you no longer need the game-history entries. |
| Close Game Tab |  | Close the selected game tab after checking unsaved changes. Use this when you have finished working with that open game. |
| Copy Game to Clipboard |  | Copy the selected tab's game as text to the system clipboard. Use this to paste the game into another program. |
| Copy Game |  | Copy the selected tab's game to the internal clipboard database. Use this to keep a temporary database copy of an open game. |
| Export Game… |  | Open export options for the selected game tab. Use this to save that game in a shareable file. |
| Import PGN Game… |  | Open the window for importing a game from portable game notation text. Use this to bring a recorded game into the app. |
| Load Game Number… |  | Ask for a database game number to load. Use this when you know the record number of the game you want. |
| Merge |  | Show choices for combining another game with this one. Use this to collect alternative continuations in one game. |
| Game |  | Merge the chosen game tab into the current game's continuations. Use this to collect analysis from another open game. |
| Chess960 |  | Replace the board game with a fresh Chess960 start. Use this to begin another randomized-back-rank game. |
| Standard |  | Create a new ordinary chess game from the game-tab menu. Use this to begin recording a game from the normal start. |
| New Game |  | Show the available kinds of new game in the tab menu. Use this when choosing the starting rules for a fresh game. |
| Paste |  | Show choices for inserting copied moves as a game or variation. Use this to decide how clipboard notation joins the current game. |
| Game |  | Read clipboard game text as a complete game. Use this when the copied notation includes the whole game. |
| Variation |  | Read clipboard move text as a variation of the current game. Use this to add copied analysis at the board position. |
| Reload from Database |  | Reload the current game from its stored database record. Use this to discard edits and return to the saved version. |
| Remove from History |  | Remove this game's entry from the recent-game history. Use this when a single history entry is no longer useful. |
| Add Line |  | Show repertoire destinations for the line up to the current move. Use this to keep an opening line for later practice. |
| Add as New |  | Save the selected tab's game as an additional database record. Use this to preserve a new version without replacing an existing game. |
| Add to Repertoire |  | Show repertoire destinations for the selected game. Use this to keep a game as part of your opening preparation. |
| Replace |  | Save the selected tab's game over its existing database record. Use this when your edits should replace the saved game. |
| Replace Moves |  | Save the selected game tab by replacing its stored moves. Use this when updating the recorded continuation of a stored game. |
| Save Game |  | Show the save destinations and modes for the game tab. Use this when deciding whether to replace or add a record. |

### 3.4 Toolbars


#### Analysis Control

| Button | How it works |
|---|---|
| Pause | — |
| Lock engine to current position | — |
| Opponents view | — |
| Start engine | — |
| Stop the search (the engine keeps running) | — |
| Stop engine | — |
| Pin best line to repertoire | — |
| Multiple variations (multi-pv) | — |
| Sort by evaluation | — |
| Number of lines the engine shows | — |

#### Analysis Info

| Button | How it works |
|---|---|
| Show more | Engine information |

#### Board Control

| Button | How it works |
|---|---|
| Go to start of game (Home) | Game start |
| Go back some moves (Page↑) | Back ten plies |
| Go back one move (←) | Previous ply |
| Go forward one move (→) | Next ply |
| Go forward some moves (Page↓) | Forward ten plies |
| Go to end of game (End) | Game end |
| Go into next variation (↓) | Enter variation |
| Go into previous variation (↑) | Leave variation |

#### Board Database

| Button | How it works |
|---|---|
| Load previous game (Ctrl-↑) | Previous database game |
| Load next game (Ctrl-↓) | Next database game |
| Load first game (Ctrl-Home) | First database game |
| Load last game (Ctrl-End) | Last database game |
| Switch to game list view | — |
| Load random game | — |
| Replace saved game | — |
| Add saved game | — |

#### Board Layout

| Button | How it works |
|---|---|
| Rotate Board | — |
| Show Suggested Move | — |
| Show Side to Move | — |

#### Board Tools

| Button | How it works |
|---|---|
| Start chess analysis engine in new window | — |

#### Database Clipbase

| Button | How it works |
|---|---|
| Normal Chess | — |
| Three-check Chess | — |
| Bughouse Chess | — |
| Crazyhouse | — |
| Antichess - Suicide/Giveaway | — |
| Antichess - Losers | — |

#### Database Switcher

| Button | How it works |
|---|---|
| New Database (Normal Chess)... | — |
| Open Database... | — |
| Advanced Search... | — |
| Close Database 'Clipbase' | Close the active database. |
| Save Changes... | — |
| Set Database 'Clipbase' readonly | Database read-only mode |

#### Editor Display

| Button | How it works |
|---|---|
| Use Column Style | — |
| Use Paragraph Spacing | — |
| Show Move Information | — |
| Collapse Variations | — |
| Expand Variations | — |

#### Editor Game

| Button | How it works |
|---|---|
| New Game (Normal Chess) | — |
| Import PGN Game | Use this when you have a game copied as portable game notation text. |

#### Editor History

| Button | How it works |
|---|---|
| Remove selected game from history | — |
| Clear History | — |

#### Editor Languages

| Button | How it works |
|---|---|
| All languages | — |

#### Games Control

| Button | How it works |
|---|---|
| Go to the first page of games | — |
| Previous page of games | — |
| Go to current selection | — |
| Next page of games | — |
| Go to the last page of games | — |

#### Games Layout

| Button | How it works |
|---|---|
| Use vertical scrollbar | — |
| Use horizontal scrollbar | — |

#### Online

| Button | How it works |
|---|---|
| Abort | Abort the selected online game. |
| Accept | Accept your opponent's draw offer. |
| Analyse in Chesswiz | Open the completed online game for analysis in Chesswiz. |
| Always promote to a queen | Toggle automatic promotion to a queen in online games. |
| Send | Send the message entered beside the online board. |
| Claim victory | Claim victory in the selected online game. |
| Close tab | Close the selected online game tab. |
| Decline | Decline your opponent's draw offer. |
| Offer draw | Offer your opponent a draw. |
| Flip | Turn the online board around. |
| Back to the live position | Return the online board to the latest position. |
| Resign | Resign the selected online game. |
| Takeback | Ask to take back the last move. |

#### Playertable Options

| Button | How it works |
|---|---|
| Disable use of player base | Enable use of player base |

#### Tree Control

| Button | How it works |
|---|---|
| Automatic search | — |
| Start search | — |
| Use position search | — |
| Use accelerated search | — |

#### Tree Switcher

| Button | How it works |
|---|---|
| Lock reference database | — |

### 3.5 Tournament Director

Open with Tools ▸ Tournament Director…. Entries marked *assistant only* have no button in the workspace.

| Operation | In the workspace | How it works |
|---|---|---|
| Tournament audit | *assistant only* | Return immutable journal records, including commands, revisions, idempotency keys and before/after state. |
| Record bye | yes | Record a requested, zero-point, full-point or pairing-allocated bye with explicit points and category. |
| Check pairings | yes | Check a round's pairings against C.04.3 criteria and the Dutch pairing helper without changing tournament state. |
| Correct result | yes | Correct a completed result without rewriting audit history; published standings gain a new publication revision. |
| Create tournament | yes | Create a C.05 round robin for humans or engines. Preview with commit false, then commit at the supplied revision. For an engine event it can also pair and play every round from a named opening, an opening code range or a list of moves. |
| Tournament crosstable | *assistant only* | Return the event crosstable as text, or open its journal-backed HTML view. |
| Enter result | yes | Enter a played or forfeit result for a pending human pairing. |
| Export tournament | yes | Save the tournament's games, its crosstable as a web page, or a FIDE TRF16/TRF26 rating report to a file you name. |
| Finish tournament | yes | Finish an event when every non-bye game is complete and return the final standings. |
| Import tournament report | *assistant only* | Create a tournament journal from a FIDE TRF16 or TRF26 report file. |
| Find FIDE player | *assistant only* | Find a player by exact name or FIDE number in the installed rating list. |
| Override pairing | yes | Change seats in a pending pairing with a required reason and C.04.3 checker report; prohibited overrides require a human TD ruling and stay marked non-compliant. |
| Pair round | yes | Preview or commit Berger pairings for one round, or all rounds when round is zero. |
| Print tournament sheet | yes | Format or save the tournament pairings, standings or crosstable for printing as a web page, plain text or a printable document. |
| Compute and record prizes | *assistant only* | Compute and record tournament and category prize allocations using the Hort system, equal tie splitting or indivisible rank order, enforcing one prize per player and recording prize payments. |
| Publish standings | yes | Append an immutable publication snapshot; later corrections create another publication revision. |
| Redo tournament command | yes | Redo an undone domain command at the current revision without deleting audit history. |
| Register players | yes | Register human or configured engine players before pairings are published. |
| Register FIDE player | yes | Copy a player's identity and rating into this event, keeping a dated record for later review. |
| Record arbiter ruling | yes | Evaluate and record a human TD or arbiter ruling under Laws of Chess 2023 with setting, supervision regime, clock penalty and optional appeal status. |
| Tournament standings | *assistant only* | Compute exact C.07 standings and every tiebreak breakdown. |
| Start tournament | yes | Start or resume an event and schedule engine games with bounded concurrency. |
| Tournament status | *assistant only* | Show the event's revision, current round, how many players and pairings it has, how it is saved, and whether undo or redo is available. |
| Stop tournament | yes | Stop all event engine processes and preserve completed games; running attempts become pending. |
| Undo tournament command | yes | Undo the latest reversible domain command at the current revision without deleting audit history. |
| Withdraw player | yes | Withdraw a player before or after pairing; applies C.05 annulment or forfeits in round robins, and Swiss withdrawal handling. |
| Tournament Director workspace | *assistant only* | Open the Event, Players, Pairings, Results and Standings workspace, close it, or select a tab. |

### 3.6 Typed commands (Ask field)

| Command | How it works |
|---|---|
| Best move | — |
| Compact database | — |
| Convert database | — |
| Close database | — |
| Switch database | — |
| Export games | — |
| Replace exported file | Asks for confirmation first. |
| Find games | — |
| Import games | — |
| My score | — |
| Open search result | — |
| Play engine | — |
| Player statistics | — |
| Check repertoire against my games | — |
| Review my games | — |
| Set engine threads | — |
| Set up opening | — |
| Find similar games | — |
| Stop engine | — |
| Player structures | — |
| Study plan | — |
| Go to tab | — |
| Run tournament | — |
| Create puzzles | — |
| Download TWIC | — |

### 3.7 Assistant tools

The assistant calls these when you ask for something in plain language (Tools ▸ Assistant, or *Ask a question* in the Ask field). *Elsewhere* names the menu or button for the same feature where one exists.

| Tool | Elsewhere | How it works |
|---|---|---|
| `add_engine` | Edit ▸ Preferences ▸ Engines… | Add a chess engine installed on your computer. When you want to analyze or play with another chess engine. Asks for confirmation first. |
| `add_to_repertoire` | Right-click a move or tree row ▸ Save Line to Repertoire… | Add the current line to the user's repertoire. Use this when a line should become part of the repertoire. |
| `annot-marks` | Right-click a move ▸ Marks Palette… | Draw arrows and coloured squares on the board. Use this when you want to highlight squares or show an idea on the board. |
| `annot-palette` | Right-click the board ▸ Edit Annotation… | Open the annotation palette for the current move. Use this when you want to mark a move as good, bad, interesting or dubious. |
| `annotate_game` | Analysis ▸ Annotate Game with AI… | Annotate a game with comments and marks. Use this when you want a reviewed and commented game. |
| `app.preferences.assistant` | — (no menu row; Ask field only) | Open the assistant preferences. When you want to change how the assistant behaves. |
| `app_state` | — | Report which database, game and tab are open. Use this when you want to know what Chesswiz is doing now. |
| `check_results` | Training ▸ Check Game Results… | Check whether game results in the database are wrong. Use this when you suspect results do not match the moves. |
| `classifier_status` | — | Show which service chooses actions for simple requests and whether it is responding. When checking how Chesswiz chooses actions for simple requests. |
| `clear_search` | — | Clear the game list filter so it shows every game again. When a previous search is hiding games you want to browse again. |
| `comment_kind` | — | What a chess annotation comment is about: opening theory, a tactic, the endgame, a plan, an evaluation, a warning, or something else. A deterministic keyword rule answers the obvious cases; a local classifier the rest. Read-only. When organizing annotation text by its subject without changing the notes. |
| `compact_database` | Database ▸ Maintenance ▸ Compact… | Compact the active database to make it smaller and faster. Use this when a database has grown huge or feels slow. |
| `convert_database` | Database ▸ Maintenance ▸ Convert to Native Format… | Copy the active database into a new Scidb (.sci) database, e.g. to turn a PGN, Scid or proprietary database into Scidb's format. Chesswiz asks for the format version and the new file name. When you need an editable Chesswiz copy of an existing collection. |
| `correspondence_games` | Tools ▸ Correspondence Games… | Manage correspondence games. Use this when you play games by correspondence or over several days. |
| `cql_help` | — | The pattern search reference card and worked examples (requests a player makes and the scripts that find them). Read it before writing a find_positions script. When you need worked examples before expressing a position search. |
| `current_game` | The board and notation | Read the moves, players, comments and attached media titles and numbers of the game on the board. Use this to inspect the current game or find an attached image, video or commentary to open by title or number. |
| `database_properties` | Database ▸ Properties… | Show the active database's Properties window: its file name, type, size, number of games, deleted games and encoding. Use this when the user asks for the database's properties, file information or technical details, not for statistics. When checking a collection's format, encoding, or storage details. |
| `database_summary` | — (Ask field suggestion *What's in this database?*) | Summarize the active database: number of games and players, overall results, and the most played openings (opening classification) with their scores. When you want a quick statistical picture before exploring a collection. |
| `database_trend` | Database ▸ Reports ▸ Trends… | Summarize the active database's opening trends, results and most frequently played openings. When deciding which openings are prominent in the active collection. |
| `detect_language` | — | Identify the language of a chess comment. When the language of an imported chess comment is unclear. |
| `diagnose_import` | — | Turn the codes an import reported (for example 'InvalidMove MissingResultTag') into a likely cause and a fix. A deterministic table covers Chesswiz's PGN reader codes; a local classifier is asked for codes the table does not know. Read-only; the import log already shows the doctor's rule-only advice. When an import reports codes that do not explain how to repair the source. |
| `discover_databases` | Database ▸ Discover Databases… | Open the dialog that scans the disk for chess databases. When you do not know where a chess collection is stored on disk. |
| `download_games` | Tools ▸ Download Games… | Download games from a supported internet source into the active database. When you want fresh games from a supported internet source. Asks for confirmation first. |
| `engine_analysis` | Analysis pane | The lines the running engines show for the board position: per pane the engine, depth and for each line the score (pawns from White's side, #n = mate in n) and the moves. 'seconds' waits that long first (at most 60) so the engine can search deeper; the result comes when the wait is over. When you want to read the running engines' current candidate lines. |
| `engine_check_move` | — | Ask the engine whether the current move is good. Use this when you want a check of one move. |
| `engine_evaluate` | Analysis pane | Ask the chess engine directly (no analysis pane needed) for the best moves in a position and their scores: the current board or a supplied position description. When you need an engine assessment without opening an analysis pane. |
| `engine_options` | Analysis pane ▸ Set Up Engine… | The options of an engine's profile (default 'Default') as the Options dialog shows them: name, type, value, default and range or choices. Threads, hash and the number of lines are not options here; start_engine sets them. When checking which settings and values an engine profile supports. |
| `engine_play` | Training ▸ Play Against Engine… | Let the engine play its best moves on the board, starting an engine if none runs. Use this to watch a computer continue the game from the current position. |
| `event_types` | — | The kinds of time control (classical, rapid, blitz, bullet, correspondence, simul, training) of the latest games in the active database, or of one player's games. A deterministic rule reads the TimeControl tag and the event name; games the rule cannot place are counted as 'unclear' (no model is consulted). Read-only. 'player' limits it to one player; 'games' is how many of the latest games to read (default 500). When comparing the time controls represented in a player's recent games. |
| `explain_game_result` | Game bar ▸ Explain this game | Explain a game result in plain language. Use this when you want to know why a game ended as it did. |
| `explain_position` | Analysis ▸ Explain ▸ Position | Explain the current position in plain language. Use this when you want a verbal assessment of the position. |
| `export_database` | File ▸ Export | Export games from a database to a portable game notation file. Use this when you want to save or share games outside Chesswiz. |
| `factcheck_annotations` | Analysis ▸ Fact-Check Annotations | Check stored game comments against the positions they describe. When imported or personal notes may contradict the positions they describe. |
| `find_capability` | — | Find the Chesswiz operations that can perform a task. When you know your task but need to find which operations can perform it. |
| `find_lesson` | — | Find a video lesson for the current opening position. Use this when you want a lesson or clip about this position. |
| `find_positions` | — (typed command *find games*) | Find positions in the database that match a pattern. Use this when you want positions with a piece on a square or a material pattern. |
| `find_similar` | Right-click a game ▸ Games Like This… | Find games with positions like the one on the board ('games like this one', 'similar positions') in the active database; the application writes the pattern search, so no cql_help is needed. 'aspects' says what must be alike: pawns (the pawn structure, both sides), material (the same pieces), pieces (kings and pieces on the same squares); default pawns alone. The game on the board is left out of the results. 'tolerance' lets up to 0, 1 or 2 pawns per side stand elsewhere (default 0). 'colours' both also finds the structure with the colours reversed. Same two steps as find_positions: mode sample first (the user sees diagrams and the search in the Report pane; ask whether that is what they meant), then mode all. Header fields narrow the games first. When you want examples of games that reached positions resembling the board. |
| `game-new` | File ▸ New | Start a new game on the board. Use this when you want to play or enter a fresh game. |
| `game.copy` | Right-click a game ▸ Copy Game | Copy games into the Chesswiz game clipboard so they can be pasted elsewhere. With no arguments it copies the game on the board; with base, variant and numbers it copies those games; optionally also paste them into 'database'. When transferring selected games through the application clipboard. |
| `game.paste` | Right-click a game ▸ Paste Game(s) | Paste exactly the games in the game clipboard into the database that has focus (or 'base'); read-only and unsupported variants are refused. When clipboard games should be added to a writable destination collection. |
| `goto_move` | Click the move in the notation | Navigate the game already on the board to a full move number. With after white or black show the position after that side's move; omit after for before White's move. Keeps the current game and edits. Use instead of repeated nav-forward/nav-back calls. When the discussion refers to a numbered move in the loaded game. |
| `handoff_issue` | — | Start the configured coding agent on an issue found by triage, to fix it in the Chesswiz sources. Only when the user asks for it. When a recorded problem is ready to send to the coding assistant. Asks for confirmation first. |
| `help.close` | Help window close button | Close the Help window after reading the manual. Use this to return to your game after consulting a manual page. |
| `import_games` | Tools ▸ Import Games… | Import games from a portable game notation file into a database. Use this when you have games in a portable game notation file and want them in Chesswiz. Asks for confirmation first. |
| `install_chessbase_fonts` | Tools ▸ Install Legacy Fonts… | Install the figurine chess fonts from a Windows font directory. When suitable figurine fonts are available in a Windows font folder. Asks for confirmation first. |
| `layout.delete` | View ▸ Layout ▸ Manage Layouts… | Delete a saved layout by name without opening the layout manager. When a saved arrangement is obsolete and should no longer be offered. Asks for confirmation first. |
| `layout.rename` | View ▸ Layout ▸ Manage Layouts… | Rename a saved layout by name without opening the layout manager. When a saved arrangement needs a more recognizable name. Asks for confirmation first. |
| `list_engines` | Edit ▸ Preferences ▸ Engines… | The chess engines Chesswiz can run: the ones bundled with Chesswiz and the ones the user added. For each: name, version, protocol, variants, rating, threads, hash and line limits, its program and whether that program is there. Also which analysis panes run which engine. When choosing among the engine programs already available to the application. |
| `list_issues` | — | List recorded bugs, showing the newest reports first. When reviewing the bugs recorded by error triage. |
| `list_open_databases` | Database switcher | List the databases currently open, and which one is active. When checking which collection is active among several open databases. |
| `maintenance_report` | Database ▸ Maintenance (individual commands) | Open the database overview, duplicate-game report or opening coverage report. When deciding whether a database needs cleanup or duplicate review. |
| `nav-enter-var` | Board navigation buttons | Move to the next available variation at the board position. Use this to explore another branch while playing through analysis. |
| `nav-fast-back` | Board navigation buttons | Move the board backward by ten half-moves. Use this to review an earlier stretch of the game quickly. |
| `nav-fast-forward` | Board navigation buttons | Move the board forward by ten half-moves. Use this to skip ahead while reviewing a long game. |
| `new_game` | File ▸ New | Start a new, empty game on the board. Use this when you want a fresh board to play or analyse. |
| `novelty_label` | — | Check whether a move is known in the available master games. When checking whether a position is represented in the available precedent index. |
| `open_database` | File ▸ Open | Open a Chesswiz database file, or switch to a database that is already open. Use this to load a saved collection or select another open database as the active database. |
| `open_game` | Double-click a game in the list | Load a game onto the board by number, or a player's most recent game. When selecting a known game number or a player's latest game for review. |
| `open_play_engine` | Training ▸ Play Against Engine… | Open the Play Against Engine setup dialog, optionally selecting the user's colour. Use for requests to open Play Against Engine or play as Black/White. This only opens the dialog; the user presses Start to begin the game. When setting your color before starting a computer opponent. |
| `open_position` | — | Put a game found by the last find_positions call on the board, at the matching position. 'index' counts the positions as they were listed, from 1. When a position-search result should be inspected on the board. |
| `open_search` | Database ▸ Search | Open an advanced search dialog for the database. Use this when you need a detailed search by material, rating or position. |
| `open_stream` | Media pane ▸ Open Stream… | Open a video stream or a live broadcast. Use this when you want to watch a stream or follow a live tournament. |
| `open_view` | View ▸ Panes | Open one of Chesswiz's reports or dialogs for the user (they only show things; nothing changes). kind: player_card (a player's card: ratings, photo, links; needs 'name'), prep_report (a player's preparation report: scores by colour, openings, recent games, gaps, the opponent dossier; needs 'name'), crosstable (an event's tournament table; needs 'event', part of the event name), event_report (the story of an event: standings, leaders and upsets, told from its results; needs 'event'), opening_report (the opening report of the position on the board: statistics, main lines, fashion, plans), opening_prep (opening preparation: the moves played from the board's position), repertoire_report (the active repertoire database's report), duplicates (find duplicate games in the active database), trend (the database's opening trends, in the Report pane). When you want a report or information window without modifying games. |
| `opening_line` | Tree pane / Opening Explorer | The moves of a named opening from Chesswiz's opening table, to set it up on the board. Use this to look up an opening before exploring its continuations. |
| `opening_score` | Tree pane | Results of an opening in the active database, by opening classification code: 'B90' (one code), 'B9' (B90-B99), 'B' (B00-B99) or a range 'B90-B99'. When comparing results for an opening code or family in the active collection. |
| `opponent_brief` | Training ▸ Opponent Brief… | Open the opponent brief in the Report pane. Use this when the preparation report should be shown. |
| `pane` | View ▸ Panes | Show, hide, dock or undock a pane. Use this when a pane is closed or in the wrong place. |
| `player_stats` | — (typed command *player statistics*) | Show a player's record and statistics. Use this when you want a player's results and rating. |
| `position_moves` | Tree pane | The moves played from the position on the board in the tree's database (if none is set, the active database becomes it): for each move the games, share, score for the side to move, draws, average Elo, last year played and best player. Answers 'what is played here', 'what scores best' and 'is this move a novelty' (a move missing from the list is new to that database). When choosing a continuation based on games that reached the board position. |
| `prepare_against` | Training ▸ Opponent Brief… | Prepare against a named opponent with statistics, openings and weaknesses. Use this before a game against a known player. |
| `print` | — (File ▸ Export can write PDF; no Print command) | Print the current board game to a PDF and send it to the platform printer or PDF viewer. Load a requested game first with open_game. Returns an error if printing fails. When you want a paper or PDF copy of the loaded game. |
| `recent_errors` | View ▸ Show Log… | List the most recent errors Chesswiz recorded. Use this when something went wrong just now. |
| `remember_me` | related: Edit ▸ Preferences ▸ Private Player Card… | Remember who the user is: their name as it is written in their games, e.g. 'Thomas, Michael'. Call it when the user tells you their name; from then on I, me and my games mean that player. An empty name forgets it. When reports should recognize which games and player name are yours. |
| `remove_engine` | Edit ▸ Preferences ▸ Engines… | Remove an engine from the engine list (its program stays on disk). Not while it runs in a pane. Only when the user asks for it. When an engine should disappear from the chooser while its program remains installed. Asks for confirmation first. |
| `repertoire_check` | Database ▸ Reports ▸ Repertoire Report… | Check the user's opening repertoire against their games. Use this when the user wants to find gaps in their repertoire. |
| `run_action` | Every menu entry | Run a Chesswiz operation found by capability discovery. When capability discovery has identified the operation and the information it needs. |
| `run_job` | — | Prepare for an opponent, review your games, check your repertoire or create training positions in a series of steps. When preparation or review needs several supported operations in sequence. |
| `save_pattern` | — | Save the last position search and its accepted examples under a short name. When a successful position search should be reusable under a memorable name. |
| `save_working_set` | Right-click a player/event ▸ Save Working Set… | Save the games the game list shows (after show_search, or a find_positions/find_similar run in mode all) as a new Scidb database next to the active one, a working set, and open it. Chesswiz asks the user for its name; 'name' is the suggestion. Only when the user asks to keep or save the selection. When search results should become a separate collection for later work. Asks for confirmation first. |
| `search_games` | Database ▸ Search | Find games in your database by player, opening, tournament or result. Use this to find a player’s games, an opening or a tournament, or to narrow the search by colour and result. |
| `set_engine_option` | Analysis pane ▸ Set Up Engine… | Change an option of an engine's profile (default 'Default'), checked against its type and range; engine_options lists them. Running panes of that engine restart with it. The change is saved. When a known engine setting needs a new value within its supported range. |
| `set_position` | Right-click the board ▸ Set Up Position… | Set up a position on the board. Use this when you want to enter a position from a book, diagram or a board-position description. |
| `show_search` | — | Show the games of the last search in the game list. When you want to browse the games found by the most recent search. |
| `similar_games` | Right-click a game ▸ Games Like This… | Find the games of the active database that share the most opening half-moves with one game and narrate why they are alike. When looking for games that share the early moves of a selected game. |
| `start_engine` | Analysis pane engine button | Start the chess engine on the current position. Use this when you want engine analysis. |
| `stop_engine` | Analysis pane ▸ Close Engine | Stop the analysing engine. When live analysis is no longer needed. |
| `structure_profile` | — (typed command *player structures*) | Which kinds of position a player's games reach and how the player scores in them, found exactly by Chesswiz's pattern matcher in the active database: isolated queen's pawn, opposite-coloured bishops, queenless middlegames, rook and pawn endings, kings on opposite wings. Counts and scores come from the database. 'colour' limits it to the games with that colour; 'games' is how many of the latest games to read (default 200). When preparing against a player by studying recurring pawn structures and results. |
| `study_plan` | Training ▸ Study Plan… | Build a study plan from the user's games. Use this when the user wants to improve with a training plan. |
| `switch_tab` | Information / Database / Board tabs | Switch the main window to the board tab, the database tab (game list) or another tab. When the next task belongs in another main application workspace. |
| `tablebase` | Board pane menu ▸ Show Tablebase | Look up the endgame tablebase for the current position. Use this when you want perfect play in an endgame. |
| `tool_log` | — | List the recent operations the assistant attempted and their results. When checking what the assistant attempted and whether those operations succeeded. |
| `training_set` | Training ▸ Training Set from Games… | Make a training set of positions from the database. Use this when you want puzzles or positions to practise. |
| `transcribe_media` | — | The transcript of a media file (the speech of an audio lesson or a video), as plain text, from the local speech-to-text engine. Read-only; nothing is stored. Use it when the user asks what is said in a lesson, or wants its text. Long transcripts are cut; the answer starts with a short summary. When you want readable speech from a recorded lesson. |
| `triage_errors` | — | Group newly recorded problems and create a report for each suspected bug. When newly recorded errors need categorization and issue reports. |
| `update_player_data` | Database ▸ Player ▸ Update Rating Data… | Update the rating data of the players in the database. Use this when you want current FIDE ratings for your players. Asks for confirmation first. |
| `view.dialog.close` | The dialog's own buttons | Close a named information or preferences dialog. Unsaved form fields are discarded. When an information or preferences window has served its purpose. |
| `voice_status` | Speak button | Show the status of voice input. Use this when you want to talk to Chesswiz instead of typing. |

### 3.8 Developer tools (debug mode only)

| Tool | How it works |
|---|---|
| `cancel_timer` | Cancel a scheduled task. When a scheduled task should no longer run. Asks for confirmation first. |
| `child_processes` | The processes started by this program (helpers, leftover players). When investigating a helper program that may still be running. |
| `eval_tcl` | Run a debugging instruction and report its result. When investigating a problem in a debugging session. Asks for confirmation first. |
| `hang_dumps` | Read the diagnostic reports saved when the program stopped responding. Use this when investigating a frozen application. |
| `list_procs` | Find internal operations by name. Use this when investigating which part of Chesswiz performs an operation. |
| `loop_health` | Show how long Chesswiz stopped responding and when those delays occurred. When investigating pauses or delayed input in the interface. |
| `media_state` | Show the current media file, playback progress, duration and volume. When diagnosing playback, volume, or the current media position. |
| `proc_source` | Show how a named internal operation is written. Use this when investigating a problem in an internal operation. |
| `read_variable` | Read a named internal setting or group of settings. When investigating settings during a debugging session. |
| `release_grab` | Free the mouse from a window that is preventing clicks elsewhere. When a window prevents you from clicking the rest of Chesswiz. Asks for confirmation first. |
| `timers` | List scheduled tasks and open connections. When investigating delayed work or a connection that remains open. |
| `ui_state` | Show open windows, their sizes and positions, and which window receives typing and mouse clicks. When investigating window placement or a window that prevents normal interaction. |

### 3.9 Controls the assistant can operate

These mirror controls inside panes and dialogs (the control itself is how you use them; the action lets the assistant and the Ask field operate it).

| Control | How it works |
|---|---|
| Set analysis information detail (`analysis.info`) | Show more or less information in an existing analysis tree toolbar. Tree is the native analysis widget path. When the engine toolbar is too crowded or omits details you want to see. |
| Set board display options (`board.display`) | Set the sliding variation-pane position, annotation duration in milliseconds, or promoted-piece mark. All supplied fields apply directly to the current board without opening preferences. When variation previews linger too long or promoted pieces need a visible mark. |
| Set game navigation source (`board.game_source`) | Choose whether board game-navigation buttons navigate the game list or the database. Explicit values are idempotent. When the board's next-game button should follow a different collection. |
| Navigate board moves (`board.navigate`) | Move through the current game's main line or variations. When you want to examine another point or branch of the game already loaded. |
| Choose piece-design preview (`board.piece_preview`) | Select the preview piece or background layout in an existing piece-design configuration window. Piece is k, q, r, b, n or p; layout is ll, ld, dd, dl, ldld or dldl. Omit fields to inspect. No configuration window is opened. When comparing a piece design against different squares before applying it. |
| Choose starting-position preset (`board.start_preset`) | Create a new game from a built-in starting-position preset, preserving the previous game. Preset is Normal, Chess960, Symm960, Shuffle, or a built-in numeric position identifier. Target setup instead changes the existing board-setup form without applying it to the game. When starting a fresh game from a nonstandard built-in arrangement. |
| Set 3D camera (`board3d.camera`) | Choose the White, Black, Side or Top camera preset for the 3D board without a dialog. When you want to inspect the 3D position from another side. |
| Set 3D pieces (`board3d.pieces`) | Choose how the pieces look on the three-dimensional board. When the current 3D pieces are hard to distinguish. |
| Set 3D theme (`board3d.theme`) | Select a built-in 3D board theme by name. Omit name to list available themes. When you want a different coordinated appearance for the 3D board. |
| Configure browser notation (`browser.display`) | Set the browser notation column style and move notation directly, without opening preferences. Omit fields to inspect the current settings. When an open game browser's move list needs a different reading format. |
| Resize browser board (`browser.size`) | Make the board in a game browser larger or smaller. When an open browser board is too small or occupies too much space. |
| Empty clipboard database (`database.clear_clipbase`) | Clear all games of the current variant from the clipboard database after confirmation. Unsaved modified clipboard games must first be saved or closed; they return an error rather than opening another dialog. Other databases are unchanged. When temporary games of the current variant are no longer needed. Asks for confirmation first. |
| Choose pending database copy (`database.copy_choice`) | Resolve the currently open database drag-copy menu by copying all games of the variant, the current filter, all variants, or canceling. Only enabled native choices are accepted. Parent identifies the database switcher containing the pending menu. When a database drag has paused to ask which games to copy. |
| Set database description (`database.description`) | Read or set an open database's description. Supply description to apply directly; omit it to read the current value. Empty base uses the current database. Read-only databases reject changes. When identifying a collection by more than its filename. |
| Configure game list view (`database.games_view`) | Move through the database game list or change how its scrollbars appear. When you want to jump to a game or adjust the game list's scrolling. |
| Remove recent database (`database.recent_remove`) | Remove a database from the recently used list without deleting or closing its file. When an obsolete entry should disappear from the recent-file list. |
| Set database repertoire type (`database.repertoire_type`) | Mark an editable Chesswiz database as a repertoire for both colors, White or Black. When a collection should serve as your opening repertoire for a chosen color. |
| Set database symbol size (`database.symbol_size`) | Set the database switcher's icon size in pixels, using the same persistent setting as its symbol-size menu. When collection icons are difficult to read or take too much room. |
| Switch database variant (`database.variant`) | Switch the current database view to a supported chess variant. When browsing another ruleset stored in the same database. |
| Sort engine dictionary (`engine.dictionary_sort`) | Sort the installed engine dictionary by name, Elo or rating. Opens its local dictionary window if needed; no network request is made. When finding an engine is easier by rating than by its current list order. |
| Manage file-picker bookmarks (`files.bookmark`) | List, add, rename or remove favorite folders in the file chooser. When you repeatedly navigate to the same folder in file dialogs. |
| Delete file-picker selection (`files.delete`) | Remove a file or folder and its associated database files, using the file chooser. When you want to remove an unwanted file from your computer. Asks for confirmation first. |
| Choose pending file drop (`files.drop_choice`) | Resolve an existing file picker's pending drop menu with copy, move, link, restore or cancel. The menu's native operation performs the file changes after the choice; unsupported choices and absent menus return errors. When a file drop is waiting for a copy, move, or link decision. |
| Change file-picker files (`files.mutate`) | Rename or duplicate a selected file, or create a folder in an existing file picker. Supply path to select the source, and name for the new basename; no chooser or inline name editor opens. Existing destinations are rejected. Native database companion-file callbacks are preserved. When preparing folders or making a named copy within an open file picker. |
| Operate file picker (`files.picker`) | Navigate an existing file picker by directory, backward or forward history, set list/details layout or hidden-file visibility, or invoke its registered custom operation on a supplied file. Supply the picker widget path; no script arguments are accepted. Omit widget to list active pickers. When an open file dialog needs a different directory or display mode. |
| Explain this game (`game.explain`) | Explain the current game's opening, style of play and result in the Report pane. When you want a readable account of the loaded game's character and outcome. |
| Crazyhouse (`game.new.crazy`) | Start a game where captured pieces come back into play. Use this when you want to play the Crazyhouse variant. |
| Antichess - Giveaway (`game.new.giveaway`) | Start an Antichess game where the stalemated side wins. Use this when you want the Giveaway rules for an antichess game. |
| Antichess - Losers (`game.new.losers`) | Start an Antichess game where being mated or stalemated can win. Use this when you want the Losers rules for an antichess game. |
| Normal Chess (`game.new.normal`) | Start playing an ordinary game of chess on the board. Use this when you want a fresh standard game to play through. |
| Antichess - Suicide (`game.new.suicide`) | Start an Antichess game where a stalemated side with fewer pieces wins. Use this when you want the Suicide rules for an antichess game. |
| Three-check Chess (`game.new.three`) | Start a game in which giving check three times wins. Use this when you want to play the three-check chess variant. |
| New Game (`game.new.variants`) | — |
| No writable opening databases are open. (`game.repertoire.none`) | Explain that no writable opening database is open. |
| Add to Repertoire (`game.repertoire.save`) | Save the game on the board, or the current line, into a writable opening database. |
| Transpose game (`game.transpose`) | Rearrange the move order in a trial copy of the current game. When exploring the loaded game with its position transposed in a trial copy. |
| Set trial mode (`game.trial`) | Start or stop trial mode on the current game. Stopping discards trial moves and restores the original position; enabled is idempotent. Omit enabled to toggle. When experimenting with continuations without committing them to the original game. |
| Undo or redo notation edit (`game.undo`) | Undo or redo the most recent edit in the current game notation, regardless of keyboard focus. When correcting the last notation edit or restoring an edit you undid. |
| Make variation first (`game.variation_first`) | Reorder the specified variation as the first variation. Number zero selects the current variation. When a side line should appear before its sibling variations. |
| Configure game bar (`gamebar.display`) | Set game-bar alignment, separate header, active-game placement and player line layout. Omit gamebar to use the editor game bar. Fields are idempotent and applied without a dialog. When game tabs or player headings occupy an inconvenient arrangement. |
| Set game lock (`gamebar.lock`) | Lock or unlock an unmodified game slot in its game bar. Locked games are protected from automatic replacement. Omit gamebar to use the editor game bar. When a reviewed game should remain protected in its current slot. |
| Operate help viewer (`help.viewer`) | Navigate the local help viewer, expand or collapse its contents tree, show or hide the index, or set text alignment. Use topic to load a help page by its installed filename. The help viewer opens when needed. When reading local documentation and navigating its sections or index. |
| Align pane to whole lines (`layout.align_lines`) | Adjust a text view to show whole lines without a partly hidden last line. When a text pane ends with a partially visible line. |
| Set pane grouping (`layout.group`) | Arrange a group of views as tabs or as separate windows. When related panes should share tabs or appear in separate windows. |
| Play game media (`media.play_entry`) | Open game media by its title or 1-based index. Read current_game for available titles and indices. Give exactly one selector. |
| Stop (`media.stop`) | Stop the media player. |
| Choose pending move operation (`move.choice`) | Resolve the currently open move-insertion choice: replace, variation, mainline, trial, exchange, append or cancel. Only choices offered by the native menu are accepted; no pending menu returns an error. When entering a move has paused to ask how it should affect an existing continuation. |
| Choose pending promotion (`move.promotion`) | Choose a piece for the currently open promotion menu. Only pieces legal for that native variant menu are accepted. No pending promotion returns an error. When a pawn has reached its final rank and needs a promotion piece. |
| Set notation display options (`notation.display`) | Set the arrangement of game text or choose which move details to show. When the move list needs columns or different move-information details. |
| Toggle notation language (`notation.language`) | Show or hide a comment language in the notation. Use xx to toggle all languages; otherwise supply an installed language code. When multilingual comments should be limited to the languages you read. |
| Rotate overview boards (`overview.rotate`) | Rotate every board in an open game overview. Notebook is the overview notebook widget path. When reviewing thumbnail boards from the opposite side. |
| Set player card trace (`playercard.trace`) | Show or hide the HTML or log trace for an existing player card. Omit key to list open card keys. Supplied enabled is idempotent. When investigating the appearance or information in an open player card. |
| Select save-form match fields (`save.match_fields`) | Set which matched player or event fields the save-game form applies. Field must be an existing selectable field (for example player:fideID or event:country). Explicit enabled is idempotent and uses the native checkbutton variable. Omit field to list current selections. When a save form offers matched player or event details to apply. |
| Edit save-form tags (`save.tags`) | List, set or remove extra tags in an existing save-game form without opening an inline editor. Omit dialog to list active forms. Set requires a tag name and value; remove rejects mandatory locked tags. This edits the pending form, without saving the database. When a save form needs additional metadata beyond its standard fields. |
| Size a table column (`table.column_size`) | Optimize, fit, shrink or expand a named column of an existing table. The table is a widget path; column is its column identifier. When a table column clips its contents or wastes horizontal space. |
| Find named table object (`table.find_object`) | Find a player, event or site by name prefix in its existing table, activating and scrolling to the match. Widget identifies the native table's parent for players, or the table for events/sites. When locating a known player, event, or site in an open table. |
| Set player dictionary source (`table.player_source`) | Turn player-information lookup on or off in a player list and refresh the displayed details. When a player table should include or exclude the player database. |
| Operate tournament table (`tournament.table`) | Configure or refresh an open tournament table, reset its view, navigate events, save HTML, or narrate its event. Supply filename for export to avoid a file chooser; omit window to use the most recently opened table. Configure fields use the native display settings. When inspecting another event or changing an open tournament table's presentation. |

