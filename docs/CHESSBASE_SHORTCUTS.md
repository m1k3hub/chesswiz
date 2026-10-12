# ChessBase shortcut research and Chesswiz mapping

Research date: 2026-10-12. CERTAIN means explicitly documented in official help;
UNSURE means no reliable shortcut verified, so no binding is installed. This is
an optional compatibility subset, not a claim to reproduce every ChessBase UI.

Sources:
- [CB14 board](https://help.chessbase.com/CBase/14/Eng/keyboard_board_window.htm)
- [CB15 board](https://help.chessbase.com/CBase/15/Eng/keyboard_board_window.htm)
- [CB16 board](https://help.chessbase.com/CBase/16/Eng/keyboard_board_window.htm)
- [CB18 board](https://help.chessbase.com/CBase/18/Eng/keyboard_board_window.htm)
- [CB18 database](https://help.chessbase.com/CBase/18/Eng/keyboard_db.htm)
- [CB18 game list](https://help.chessbase.com/CBase/18/Eng/keyboard_games_lists.htm)
- [CB18 new game](https://help.chessbase.com/CBase/18/Eng/saving_games.htm)
- [CB18 variations](https://help.chessbase.com/CBase/18/Eng/variations.htm)
- [CB18 palette](https://help.chessbase.com/CBase/18/Eng/annotation_palette.htm)
- [CB18 commenting](https://help.chessbase.com/CBase/18/Eng/commenting_functions.htm)
- [CB18 symbols in text](https://help.chessbase.com/CBase/18/Eng/keyboard_shortcuts_for_comm.htm)

The core board list agrees in 14, 15, 16 and 18. The CB17 URL could not be
fetched; do not infer independently verified certainty about that version.
The palette pages disagree (Ctrl+Alt+S versus Ctrl+Shift+S): left UNSURE.
Symbol shortcuts in text commentary are font-specific and are not board NAG keys.

Code discovery: graph tools were unavailable (approval policy never). Searched
bind/shortcut/accelerator in tcl/. Existing board bindings use board::bind and
FilterKey; pgn registers its read-only notation with board::needBinding.
menu.tcl binds application actions; options::hookWriter persists option arrays.
There is no general preferences dialog: Setup contains individual option dialogs.

Proc names below are relative to ::application unless prefixed with ::.

| Status | ChessBase key/context | Action | Chesswiz proc/command | Conflict or limitation |
|---|---|---|---|---|
| CERTAIN | Left / Right, board | Previous / next ply | board::Goto -1 / +1 | Already matches |
| CERTAIN | Home / End, board | Beginning / end | board::Goto start / end | Already matches |
| CERTAIN | PageUp / PageDown, board | Scroll notation | pgn::scroll -1 / +1 pages | Overrides ten-ply jump |
| CERTAIN | Ctrl+F, board | Flip | board::Rotate | Database Ctrl+F instead searches |
| CERTAIN | Ctrl+Alt+0, board | Null move | board::InsertNullMove | Adds alias for Ctrl+0 |
| CERTAIN | Ctrl+Y, board | Delete current variation | pgn::RemoveVariation | Overrides possible redo |
| CERTAIN | M, board | Return to parent line | board::Goto up | Plain letters only in read-only board/notation |
| CERTAIN | ], board | Remove continuation | ::scidb::game::strip truncate | Existing Delete command |
| CERTAIN | [, board | Remove preceding moves | ::scidb::game::strip moves | Existing menu command |
| CERTAIN | Ctrl+Alt+Y, board | Remove graphic marks | ::scidb::game::strip marks | Existing strip category |
| CERTAIN | Ctrl+A / Ctrl+Shift+A, board | Comment after / before | pgn::editComment after / before | Overrides annotation palette; preserves input select-all |
| CERTAIN | ! / ?, board | Good / bad move | ::annotation::addNag infix 1 / 2 | No text-entry interception |
| CERTAIN | Ctrl+S, board | Save as another game | board::SaveGame add | Matches classic board list; newer Save behavior can differ |
| CERTAIN | Ctrl+R, board | Replace game | board::SaveGame replace | Already matches |
| CERTAIN | F10 / Ctrl+F10, board | Next / previous game | board::LoadGame(any) next / prev | Existing game navigation controls |
| CERTAIN | Ctrl+Z, board | Undo edits | pgn::undo | Existing virtual Undo |
| CERTAIN | Alt+F2, board | Default engine on/off | analysis::defaultEngine, startEngine, stopEngine | Stops only the default engine; leaves other engines alone |
| CERTAIN | Ctrl+N | New game | ::menu::gameNew .application | Creates a normal game through existing dialog |
| CERTAIN | Ctrl+O | Open database | ::menu::dbOpen .application | Existing file dialog |
| CERTAIN | Ctrl+F, database | Search games | database::OpenAdvancedSearch | Overrides application find-next only in database tab |
| CERTAIN | Ctrl+X, database | New database | ::menu::dbNew .application Normal | Input widgets retain cut |
| CERTAIN | Ctrl+move / Shift+move, board | Variation / overwrite | ::move::releaseSquare | Unmapped: mouse modifier semantics differ; outside keyboard-only scope |
| CERTAIN | T, board | Take back and turn continuation into variation | — | Unmapped: no exact existing single command verified |
| CERTAIN | Ctrl+G, board | Jump to numbered move | — | Unmapped: no matching dialog verified |
| CERTAIN | *, board | Automatic replay | — | Unmapped: no matching controller verified |
| CERTAIN | Ctrl+Shift+Y, board | Remove variations and commentary | — | Unmapped: no exact combined existing command |
| CERTAIN | Space / Ctrl+Space, board | Insert engine move / all engines' best variation | analysis::InsertMoves | Unmapped: needs engine/line selection, no global equivalent |
| CERTAIN | + / -, board with engine | Change engine line count | analysis::setLines | Unmapped: ambiguous with multiple engines |
| CERTAIN | Delete, game list | Mark selected games deleted | — | Unmapped: board Delete truncates; do not conflate |
| CERTAIN | Home/End, arrows, PageUp/Down, game list | List navigation | Tk list widget bindings | Retained; no board override on lists |
| CERTAIN | Ctrl+A, game list | Select every game | Tk list widget bindings | Retained; no board override on lists |
| UNSURE | Unverified, board | Promote variation | pgn::PromoteVariation | Official variations page documents action, not key |
| UNSURE | Unverified | Full screen | ::menu::viewFullscreen toggle | Chesswiz F11 retained, not advertised as ChessBase key |
| UNSURE | Ctrl+Alt+S / Ctrl+Shift+S | Symbol palette | pgn::editAnnotation | Conflicting official pages; not installed |
| UNSURE | Unverified board sequence | +-, -+, !!, ??, !?, ?! | ::annotation::addNag | No verified sequence semantics; use existing palette |

Other database indexes, photos, correspondence/training, Fritz-only controls,
and commentary-font figurines have no equivalent in this compatibility subset.
