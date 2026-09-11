# Database Discovery (tcl/app-database-discover.tcl)

Status: implemented 2026-09-11. Companion docs: `MEDIA_PANEL_DESIGN.md`
(media pane), `SCM_FORMAT_DESIGN.md`, `CBM_FORMAT_DESIGN.md`.

## 1. Purpose

The database switcher only knows databases the user has explicitly
opened (`RecentFiles`).  Discovery walks the machine for chess database
files of every supported format and lets the user open or register them,
so a database copied to the disk can be found without knowing its path.

## 2. Entry points

- Database tab toolbar: the magnifier button next to *Open Database*.
- Main menu → *Extras* → *Discover Databases…*.

Both call `::application::database::discover::open <parent>`, which
builds the dialog.

## 3. Recognised file types

A database is a *primary* index/header file plus companion files.  Only
the primary file is listed; companions are never offered on their own
(they are not openable in isolation).

| Extension | Format | Companion files (not listed) |
|---|---|---|
| `.sci` | Scidb | `.scg`, `.scn` |
| `.si4` / `.si3` | Scid v4 / v3 | `.sg4`/`.sn4`, `.sg3`/`.sn3` |
| `.cbh` | ChessBase | `.cba`, `.cbb`, `.cbc`, `.cbe`, `.cbg`, `.cbgi`, `.cbj`, `.cbm`, `.cbp`, `.cbs`, `.cbt`, `.cbtt`, `.cib`, … |
| `.cbf` | ChessBase DOS | `.cbi`, `.cko`, `.cpo` |
| `.cbv` | ChessBase archive | — |
| `.2cbh` | ChessBase 2 | `.2cbg`, `.2cba`, `.2lid`, … |
| `.scv` | Scidb archive | — |
| `.pgn`, `.pgn.gz` | PGN | — |
| `.bpgn`, `.bpgn.gz` | BPGN | — |

Binary formats with a stable header (`.sci`, `.si4`, `.si3`, `.scv`) are
**confirmed by magic bytes** so a wrongly-named file is not offered.
ChessBase satellites/archives are accepted on the extension alone; a
wrong file fails cleanly on open.

`classify {path {includePgn 1}}` returns `{ext label path size games}`
(or `{}`), where `games` comes from `::scidb::misc::size` (a header read,
no database open) and is `-1` for formats without a count.

## 4. Scan

`scanSync`/`start` share a queue-based walker:

- Roots are the user's home, standard XDG folders
  (`Documents`, `Desktop`, `Downloads`, `~/.local/share`) and the usual
  removable-media mounts (`/media/$USER`, `/run/media/$USER`, `/media`,
  `/mnt`).  The dialog lets the user add/remove roots.
- `Maximum depth` bounds recursion (default 6).
- Symlinks are not followed; pseudo-filesystems (`/proc`, `/sys`,
  `/dev`, …), VCS dirs (`.git`, `.svn`, `.hg`), package caches
  (`node_modules`, `.cache`) and trash are skipped.
- The visited set is a dict and the queue uses a head index, so the walk
  is linear in the number of directories.
- The dialog consumes 150 directories per event-loop tick (`after 1`),
  so it stays responsive and can be cancelled mid-scan.

`scanSync` is synchronous and UI-free; it is what the headless test
`tests/test_database_discover.tcl` exercises.

## 5. Dialog actions

- **Open** — `openBase` for each selected row; the first is switched to,
  the rest are loaded alongside.
- **Add to switcher** — `openBase … -switchToBase 0`, which resolves the
  real database type/variant and registers the base without changing the
  current one (skipping bases already present).
- **Rescan/Stop** — restart or cancel the walk.

## 6. Known limits

- Only primary files are discovered; a database whose index is missing
  (e.g. a lone `.cbg`) is invisible, correctly.
- `.zip` PGN archives are not scanned (too noisy); only uncompressed and
  gzip-compressed PGN/BPGN are.
- Network mounts can stall a `glob`; there is no per-directory timeout.
- The Games column requires reading each candidate's header; this is
  cheap but not free, and is done once per result as it is listed.
