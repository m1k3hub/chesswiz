# media-console — headless media e2e fixtures

A display-free harness for end-to-end (e2e) verification of Scidb's media
commands against real ChessBase fixture databases, without booting the full
GUI app.

## Components

| File | Role |
|------|------|
| `src/media_console.cpp` | Headless console (build target `media_console`). Boots the scidb Tcl/Tk layers + `app::Application`, loads the ECO table at startup. |
| `media-console/run-e2e.tcl` | e2e fixture test: drives `::scidb::db::mediaFiles` across every game of the media-rich `CB Light Database.cbh` and asserts the per-game **guiding-text HTML extraction** matches the ground truth in `CBM_FORMAT_DESIGN.md` §7. |
| `media-console/fixture.tcl` | Diagnostic probe used during development (open + scan + report). |
| `media-console/probe_chessmedia.py` | Static decoder for the ASF ChessBase script stream in `.wmv` Chess Media files (`ffprobe` + six-bit transport decode + opcode record rendering). Companion unit tests: `test_probe_chessmedia.py` |
| `media-console/wmv2timeline.py` | Emits the machine-readable sync sidecar (JSON) for a base `.wmv`: the per-event media-time timeline the future Scidb playback will consume |
| `media-console/analyze_checkpoints.py` | Opcode-`02` snapshot diffing: cursor updates, inline annotation collections, node-table tail dumps |
| `media-console/analyze_annotations.py` | Corpus statistics for opcode-`06` record types over all CBM168 text exports (CBA-annotation verification) |
| `media-console/analyze_squares.py` / `analyze_edge64.py` | Structural probes that settled the one-based graphic-square encoding (64 = h8 rays) |

## Prerequisites

- `media_console` built: `make -C src media_console`
- A media-rich `.cbh` corpus for the full assertion test. The bundled default
  is the local `~/Documents/ChessBase/Bases/CB Light Database.cbh` (the
  system's only media-rich sample; its `.cbm`/guiding-text linkage is fully
  documented in `CBM_FORMAT_DESIGN.md`).
- [Optional] Xvfb, since `Tk_Init` needs a display:
  `xvfb-run -a ...`.

## Usage

```bash
# Build the console
make -C src media_console

# Run the e2e fixture test (exit 0 = PASS, 1 = FAIL, 0 = SKIP if fixture absent)
xvfb-run -a ./src/media_console media-console/run-e2e.tcl

# Point at a different corpus
xvfb-run -a ./src/media_console media-console/run-e2e.tcl "/path/to/SomeDB.cbh"

# Diagnostic probe
xvfb-run -a ./src/media_console media-console/fixture.tcl
```

## What `run-e2e.tcl` verifies

For the bundled `CB Light Database.cbh` (14831 games):

1. The 10 guiding-text entries carry per-game media via
   `::scidb::db::mediaFiles` (indices `0, 12059, 12128, 12645, 12676,
   12768, 12980, 13138, 13236, 13442` — the `CBM_FORMAT_DESIGN.md` §7.3
   "Rec N" rows, 1-based, minus one).
2. Reference counts match the documented per-tournament image sets
   (`1/7/7/4/4/4/5/6/9/7` → 54 rows total).
3. Every `<IMG src="...">` **picture** resolves to a file that actually
   exists in the sibling `<DB>.html` folder.
4. The `CBLink(tag_stream,...)` `.wmv` clips (CBM #125/#126) are reported as
   type-4 streams and are the exactly-expected set absent from `.html`
   (they ship on the ChessBase Magazine disc).
5. All reported media type codes are within `{1,2,3,4}`.

This is the **per-game media linkage** that was the outstanding gap:
currently only a database-wide `.cbm` gallery existed. The fallback in
`src/tcl/tcl_database.cpp` (`cmdMediaFiles`) extracts `<IMG>`/`CBLink`
references from the loaded guiding-text HTML body, resolves each to the
database's sibling `<DB>.html` folder, and feeds them to the Tcl Media pane.

## Related

- Extraction helpers (unit-tested): `src/tcl/tcl_media_extract.h`,
  `src/test_media_extract.cpp`.
- Format/RE notes: `CBM_FORMAT_DESIGN.md`, `SCM_FORMAT_DESIGN.md`.
