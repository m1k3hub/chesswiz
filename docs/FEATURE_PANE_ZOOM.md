# Pane zoom and focus-follows-size — feature spec

Status: queued 2026-10-10. Phase 1 first; phase 2 only after phase 1 ships.

## Which panes take part

Only panes whose content gains from more space. One per-pane flag, `zoomable`, decides it, so new panes default to *off*.

| Pane | Zoomable | Why |
|---|---|---|
| board | yes | bigger squares; but see the minimum size in phase 2 |
| editor (notation) | yes | long games, variations, comments |
| games, dbgames | yes | more rows and columns |
| tree | yes | more moves and statistics |
| analysis | yes | more PV lines, longer lines |
| report | yes | a document |
| media | yes | video |
| assistant | yes | chat history |
| eco | no | a short, fixed-height code strip |
| toolbars, status bar, clocks, eval bar | no | fixed-size controls; they are not twm panes |
| floating (undocked) windows | no | the user sizes them in the window manager |
| dialogs | no | not part of the layout |

## Phase 1 — maximise pane (toggle)

- The action toggles: it fills the main window with the pane, and the same action restores the layout.
- Triggers:
  - a button in the pane header, shown only on zoomable panes;
  - a key, `Ctrl+Shift+Z` (check it for conflicts in the keybinding table);
  - a "Window" menu entry.
- **Restore:** put back the exact sash positions and sizes the user had. Save them before maximising; never recompute them.
- **Other panes:** hide them (unmap), don't destroy them. Their state and engine processes keep running.
- **Tab groups (notebook):** maximise the whole notebook; the selected tab stays selected.
- Only one pane can be maximised at a time; maximising another pane first restores the current one.
- Not saved in the layout file: a restart always opens the normal layout.
- **Code:** in `src/tk/tk_twm.cpp` (it owns geometry) plus the Tcl glue in `tcl/application.tcl`. No change to the layout file format.

## Phase 2 — focus follows size (opt-in, per layout)

- Off by default; switched on per layout in the Window menu.
- Triggered only by a mouse click or by keyboard pane switching into a zoomable pane. Focus that the program moves (dialogs, engine output, `focus` calls) doesn't count.
- The clicked pane grows by a ratio R inside its own panedwindow (default 1.4, configurable 1.2–1.8). Its siblings shrink in proportion. Other panedwindows don't change.
- **Minimums:**
  - the board never goes below its minimum square size, and can be pinned so it never shrinks;
  - every other pane keeps its existing minimum size.
- Animated over about 150 ms; instant if the animation can't keep up.
- Switching the mode off restores the user's own layout exactly.

## Tests

- Unit:
  - maximise and restore give back the same sash positions (layouts that round-trip);
  - non-zoomable panes refuse to maximise.
- App (`tests/test_app_*.tcl`):
  - maximise and restore the board, notation and an analysis pane;
  - maximise inside a notebook;
  - a hidden pane's engine keeps running.
- Phase 2:
  - focus that the program moves doesn't resize anything;
  - the board's minimum size holds.
