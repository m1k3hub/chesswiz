# Scidb and Chesswiz

Chesswiz is a fork of **Scidb** by Gregor Cramer (GPL; see `NOTICE`, `COPYING`,
`COPYRIGHT`). This page says where the line between the two is drawn.

## Where the upstream sources are

| What | Where |
|---|---|
| Scidb trunk r1531 (2018-11-24, the last upstream revision), unmodified | branch `scidb-upstream` in this repository (orphan branch, author Gregor Cramer) |
| Scidb with its full Subversion history (r1–r1531) | the private `scidb-extended` repository (`git svn` import of `https://svn.code.sf.net/p/scidb/code/trunk`) |
| Chesswiz | branch `master` of this repository |

Chesswiz's first commit (e630d26, 2026-03-24) is r1531 with nine files edited or
added. Everything since is Chesswiz work.

```sh
scripts/upstream-diff.sh                     # summary: unchanged / modified / removed / added
git diff scidb-upstream HEAD -- src/db/db_game.cpp   # one file against Scidb
git diff --stat scidb-upstream HEAD -- src/db        # one directory
```

## Summary (2026-10-17, master ac9b811)

Of Scidb's 3,538 files: 1,994 unchanged, 1,341 modified, 203 removed.
Chesswiz adds 1,892 files.

Most modified and removed files are assets, not code:

- **Assets replaced for licensing** (`docs/legal/ASSET_LICENSE_AUDIT.md`): country flags
  (rendered from flag-icons, MIT), board textures (CC0 ambientCG), icons and cursors,
  piece fonts with non-commercial or unclear terms. That accounts for about 700 modified
  and 150 removed files under `tcl/flags`, `tcl/textures`, `tcl/cursor`, `tcl/fonts`,
  `tcl/pieces`, `tcl/images`.
- **Help** (`tcl/help`, 193 files): renamed to Chesswiz; new pages.
- **Code changed in Scidb's own files**: `src/db` (formats, search, player data),
  `src/tk`, `src/util`, `src/mstl`, `src/tcl`, `src/sys`, `src/app`, and about 60
  of Scidb's `tcl/*.tcl` application files.

## What Chesswiz adds

- **AI**: the assistant, plain-language search, annotation, explanations, opponent
  briefs, study plans, training sets, provider setup (`tcl/ai-*.tcl`,
  `tcl/app-assistant*.tcl`, `tcl/app-ai*.tcl`; `docs/ai/`)
- **Search**: CQL 6.2 embedded natively (`src/cql6`, `docs/cql6/`), advanced, material
  and rating search, pattern index
- **Formats**: ChessBase 2CBH (CB 17+), CBV archives, `.cba` annotation types, Chess960
  in CBH, ChessBase media (CBM/CMS) and the SCM media format (`src/db/2cbh`,
  `src/db/cbh`, `src/db/scm`; `docs/formats/`)
- **Media**: lesson and video playback panel (`tcl/app-media*.tcl`)
- **Opening and opponent prep**: opening report, repertoire databases, dossier, novelties
- **Correspondence chess**: ICCF XFCC (`tcl/iccf-xfcc.tcl`)
- **Downloads**: TWIC and Lichess (`tcl/app-download-games.tcl`)
- **3D board** (`tcl/board-3d.tcl`, `models_3d/`)
- **Ports**: Windows and macOS builds, packaging (`scripts/`, `docs/dev/`)
- **UI**: database discovery, pane zoom, ChessBase shortcut scheme, voice input
- **Tests** (`tests/`) and the experimental web frontend (`opening-report/`)

## Names kept from Scidb

The `.sci` database format, the `::scidb::` Tcl command namespace, the C++ class
names and the `SCIDB_*` environment variables keep their Scidb names, so Scidb
databases and code stay compatible. User-visible text says Chesswiz, and credits
Scidb in the About dialog and the help.

## Change notices in modified files

Every Scidb source file Chesswiz modified carries the line
`Modified for Chesswiz, 2026; see docs/UPSTREAM.md` (under Gregor Cramer's
copyright line, or at the top where a file has none), as GPL v2 §2(a) asks.
Images, data files and third-party licence texts are not marked; the diff
against `scidb-upstream` covers them. After modifying another Scidb file, run:

```sh
git diff --no-renames --name-only --diff-filter=M scidb-upstream HEAD |
    python3 scripts/mark-modified-upstream.py
```
