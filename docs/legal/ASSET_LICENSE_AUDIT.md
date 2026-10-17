# Asset licence audit (Chesswiz)

Date: 2026-10-09. Scope: everything shipped besides our own code. This is an engineering
inventory, not legal advice; get the **Replace** and **Ask** items reviewed before a
commercial Windows/macOS release.

Verdicts: **Keep** (licence allows it; keep notices) · **Ask** (needs written permission or
the licence is unknown) · **Replace** (licence forbids our use, or a third party's trademark).

## Done (2026-10-10)

- App icon: new `icons/chesswiz.svg` (Burnett knight, GPL-2+/BSD/GFDL, on a drawn tile). Rendered to `freedesktop.org/chesswiz-*.png`, `icons/chesswiz-*.png`, `icons/chesswiz.ico` (now used by `scidb.rc`), `favicon.ico`, `tcl/images/Scidb-Logo-128.png`, `tcl/help/images/scidb-logo.png` and the five embedded `::icon::NxN::logo` images. The IconDrawer files are deleted.
- Tip-of-the-day pictures: **all** old `Motive-*` images are replaced. Besides Disney they included a Care Bear, Nintendo's Princess Daisy, Spyro, a branded dartboard and a Twitter-like bird. The new ones are rendered from Noto Color Emoji (Apache-2.0), and so is `Smiley-Cry-128x128.png`; see `tcl/images/README`.
- OS logos and DigifaceDigits are deleted. They were unused, so no replacement was needed.
- The Fritz set, themes and textures are renamed Club, with newly generated wood textures. Old settings are migrated. The piece outlines remain Gorgonian's GFritz design (freeware made for BabasChess).

## Done (2026-10-11): reproducible asset clean-up

- **Board textures:** all 287 shipped JPG/PNG/GIF files are original procedural
  Chesswiz artwork under the project's GPL-2 licence. `scripts/generate-textures.py`
  is the source: seeded numpy noise and rings for wood, turbulence for marble,
  and geometric/noise patterns for misc. Names, formats, dimensions and theme
  palettes are preserved; no textures or theme references needed deletion.
  This supersedes the ambientCG replacements described below.
- **Flags:** all 289 PNGs are rebuilt by `scripts/generate-flags.sh` from
  flag-icons **v7.5.0** (MIT), with the archive pinned by SHA256 before extraction.
  The complete MIT notice is in `tcl/flags/LICENSE` and embedded in each MIT PNG
  (so the existing PNG-only install target carries it); the per-file mapping is in
  `tcl/flags/SOURCES.txt`. Historic flags and AIR/EAR/FID/NET/SEA/SPC/ANY/UNK
  are original simplified drawings (GPL-2), including a neutral pawn for FID.
  Tibet is drawn separately rather than mapped to China. Existing names and
  dimensions are preserved.
- **Tip-of-the-day:** all 29 `Motive-*.png` images are freshly rendered from Noto
  Color Emoji, preserving names and dimensions. `scripts/generate-motives.py`
  records each glyph and pins the font SHA256; `tcl/images/README` records the
  font package, artwork licence (Apache-2.0) and font licence (OFL-1.1).
- **Embedded UI icons and controls:** 1,035 literal payloads in 47 Tcl files
  (including inactive commented artwork) are replaced by Tabler Icons **v3.31.0**
  (MIT) and original GPL-2+ geometric controls. `scripts/generate-icons.py`
  contains the complete variable-to-SVG/colour mapping and verifies the pinned
  release archive SHA256. Dimensions, variables and all Tcl bytes outside image
  data are preserved. White/black, red/green and coloured status markers retain
  their meaning. Original SVG exceptions are in `tcl/cursor/icon-sources/`;
  theme backgrounds preserve their border/stretch roles. The complete MIT notice
  is in `tcl/icons-LICENSE` and in every Tabler PNG, so merged-script installs
  carry it. Country flag payloads (covered by the flags audit), licensed splash artwork and five app logos
  are inventoried and retained (447 payloads).
- **Cursors:** all 64 existing CUR/Xcursor/XBM files are original GPL-2+ drawings
  from `scripts/generate-cursors.py`, preserving names, dimensions and intended
  hotspots. Legacy malformed ICO-like `.cur` headers are corrected to valid
  Windows CUR headers with the hotspots recorded by matching Xcursor/XBM files.
- Complete embedded-image inventory (1,482 payloads), before/after contact sheets,
  mappings, cursor inventory and test evidence: `tests/tmp-app/icons/report.md`.
  Generated and verified in the isolated `build/icon-license-cleanup` worktree.
- Visual previews and validation details: `tests/tmp-app/assets/report.md` and
  the three contact sheets beside it. Work performed and tests run in the
  isolated `build/asset-license-cleanup` worktree.
- Splash screen (`tcl/splash.tcl`): the old picture (unknown background, IconDrawer knight) is replaced by a new one generated with FLUX.1-schnell (Black Forest Labs, Apache-2.0) through the Hugging Face inference API, seed 37; prompt and script in `icons/splash/generate.py`, full-size original `icons/splash/splash-flux-seed37.png`. Title in Abel (OFL). Purely machine-generated images are generally not copyrightable, so others may reuse it.

## Must replace (original findings)

| Asset | Where | Why |
|---|---|---|
| App icon / logo (knight on blue board) | `icons/Scidb-Logo-*.png`, `freedesktop.org/chesswiz-*.png`, `tcl/images/Scidb-Logo-128.png` | `icons/Read Me.rtf`: Eugen Buzuk, IconDrawer — "free for personal non-commercial use". `chesswiz-128.png` is byte-identical to it. |
| Disney characters | `tcl/images/Motive-Mickey-Mouse.png`, `Motive-Minnie.png`, `Motive-Winnie-The-Pooh-{1,2,3}.png` (tip-of-the-day) | Disney trademarks and copyright; there is no licence. |
| OS logos | `tcl/images/OS-Apple.png`, `OS-Windows.png` | Apple and Microsoft trademarks. Use generic glyphs or text instead. |
| Fonts marked "Redistribution strictly prohibited" | `tcl/fonts/DigifaceDigits.ttf` (WSI-FONT, ©1993) | The font says so itself. |
| "Fritz" piece set | `tcl/fonts/ScidbChessFritz.ttf/.sfd`, `tcl/pieces/fritz.tcl` | Fritz is a ChessBase trademark, and the design probably comes from ChessBase. |
| "Informant" fonts | `ScidbChessInformant.ttf`, `ScidbSymbolInformant.ttf` | Chess Informant's symbol set; the origin is unclear (foundry MACR). Rename at the least, ideally redraw. |

## Ask (permission or licence unknown)

| Asset | Where | Note |
|---|---|---|
| virtualpieces.net sets (Peter Wong) | `tcl/pieces/virtual.tcl` and related | `COPYRIGHT`: permission was given by email "for the use in Scidb", so it doesn't automatically cover Chesswiz. |
| "All rights reserved" chess fonts | `ScidbChessCheq` (Atech 1991), `ScidbChessChess7` (1999), `ScidbChessOle`/`ScidbSymbolOle` (ChessOle!, Frank David 1993), `ScidbChessSmart` (Christoph Wirth 1992), `ScidbCircled` (Roger White 1998, "see .txt for terms": that .txt is **missing**), `BelfastDigits*` (tibotanguy 2008) | Most chess fonts of that era were freeware, and freeware doesn't mean redistributable or modifiable. Find each one's original terms. |
| Chess fonts with no notice in the file | Adventurer, Alpha, Aquarium, Berlin, Bookup, Cases, Celtic, CMF, Condal, Cube, GoodCompanion, Habsburg, Kingdom, Leipzig, Lucena, Magnetic, Marroquin, Maya, Mediaeval, Merida, Military, Motif, OldStyle, Segoe, Standard, Traveller, USCF, Winboard, Zurich; `ScidbDiagram*`, `ScidbSymbolS1/T1/Traveller`; `Abell-Cond-Bold`, `DesignerBlockDigits`, `Digital-*Digits`, `finalnew` (Final Frontier) | Many are by Armando Marroquin, Alpine/Eric Bentzen and others (freeware). `tcl/pieces/*.tcl` are Gregor Cramer's conversions of these designs, so the copyright in the design still applies. "Segoe" and "USCF" are also third-party names. |
| Board textures | `tcl/textures/{dark,lite,tile}/{marble,misc,wood}` (287 JPG/PNG/GIF) | **Done (2026-10-11):** original procedural GPL-2 artwork; see Done and `scripts/generate-textures.py`. |
| Flags | `tcl/flags/` | **Done (2026-10-11):** pinned flag-icons (MIT) and original GPL-2 drawings; see Done and `tcl/flags/LICENSE`. |
| Remaining tip-of-the-day images | `tcl/images/Motive-*` (animals, flowers, etc.) | **Done (2026-10-11):** all 29 freshly rendered from Noto Color Emoji; see Done and `tcl/images/README`. |
| Cursors | `tcl/cursor/` | **Done (2026-10-11):** original GPL-2+ drawings; see Done and `scripts/generate-cursors.py`. |
| Embedded UI icons | `tcl/icons.tcl`, `tcl/app-db-icons.tcl` and other Tcl files | **Done (2026-10-11):** pinned Tabler Icons (MIT) and original GPL-2+ controls; see Done and `tcl/icons-LICENSE`. |
| Font credits | `tcl/info.tcl` about box | Names the designers: Marroquin, Bentzen, Cowderoy, Leschemelle, Scott and Frank David (enpassant.dk freeware); Gorgonian (BabasChess); Brown (Good Companion); Poisson (Phoenix); Burnett (GPL); Eran Karu (PyChess, GPL); Maurizio Monge (Eyes, Fantasy, Skulls, Spatial). Check each site's terms. |

## Permission-dependent assets removed (2026-10-10)

Every piece set and font whose terms needed the author's permission, or whose author is unknown, has been removed:

- **Piece sets:** Adventurer, Aquarium, Bookup, Cases, Celtic (Gorgonian), ChessCube, Clarity, Club, Condal, Eyes, Free Staunton, Good Companion, Habsburg, Kingdom, Leipzig, Lucena, Lucena-Thin, Magnetic, Marroquin, Maya, Mediaeval, Military, Motif, Old Style, Phoenix, Skulls, Standard (CMF), Usual, Virtual, Winboard, Zurich.
- **Fonts:** every `Scidb Chess/Diagram/Symbol` font except Merida and S1/T1; Circled and Belfast Digits ("all rights reserved"); Designer Block, Digital Digits, Abell Cond Bold and Final Frontier.

What remains:

- **Piece sets:** Burnett (GPL-2+), Merida (GPL-2+, Marroquín's licence on lichess), Celtic, Fantasy and Spatial (Monge, MIT), Chessnut (Apache-2.0), RhosGFX (CC0), Firi, Kiwen-suwi and Totoy (CC BY 4.0, credited in the About box).
- **Fonts:** Scidb Chess/Diagram Merida, Abel and Font Awesome (OFL), and Scidb Symbol S1/T1.
- **Unverified:** S1/T1 were made in FontForge in 2009 during Scidb's development and carry no third-party copyright; most likely Gregor Cramer's own work (GPL), but this is not recorded.

New defaults: the symbol font is Scidb Symbol T1, figurines use Scidb Chess Merida, the figurine piece images use Burnett, and the PDF and HTML exports use Merida and T1. The About box and the PGN window header use Abel instead of Final Frontier. Themes that used a removed set now use Merida (Chessnut for the modern-looking ones, Fantasy for Eyes and Skulls). Saved settings that name a removed set fall back the same way through `::board::pieceset::lookup`. Papercut (CC BY) was tried and dropped: its look depends on gradients the built-in renderer can't draw.

## Renames (2026-10-10)

These font families and sets were named after other organisations' products and are renamed: Scidb Chess/Symbol Informant → **Annotator**, Scidb Chess USCF → **Federal**, Scidb Chess Segoe and the Segoe piece set → **Clarity** (saved settings resolve Segoe to Clarity). Kept as factual references: the USCF rating system and its PGN tags, and the "Informant" database type, which is ChessBase's label for games from Chess Informant.

## Licence checks (2026-10-10)

Sources: the font list at enpassant.dk/chess/fonteng.htm, the lichess `COPYING.md` (lila repo), the CTAN `enpassant` package, the PyChess `ARTISTS` file, image metadata and file names.

### Piece fonts and sets

| Set(s) | Verdict | Evidence |
|---|---|---|
| Burnett | **Keep** | GPL-2+ (Colin Burnett; header in `tcl/pieces/burnett.tcl`). |
| Merida | **Keep** | lichess lists Marroquin's Merida as GPL-2+. |
| Fantasy, Spatial | **Keep** | lichess lists Monge's sets as MIT. |
| Standard (Unicode) | **Keep** | Unicode glyph shapes, no design copyright claimed. |
| Club (ex-Fritz), Aquarium, Bookup, Celtic, Chess7-style, ChessCube, Habsburg, Military, Old Style, Segoe, Standard/CMF, Zurich | **Ask** | Gorgonian (BabasChess); no licence found anywhere. "Segoe" is a Microsoft font name: rename regardless. |
| Alpha, Berlin | **Removed (2026-10-10)** | Eric Bentzen: "Free for personal non commercial use" (enpassant.dk, and lichess says the same). |
| Chess7 (`ScidbChessChess7`) | **Removed (2026-10-10)** | Style-7 / Sizenko: freeware but non-commercial (fontspace: "Freeware, Non-Commercial"). |
| Cheq | **Removed (2026-10-10)** | CTAN credits it to Adobe Systems Incorporated (©1991 Atech); not freeware we can rely on. |
| Adventurer, Condal, Kingdom, Leipzig, Lucena, Magnetic, Marroquin, Maya, Mediaeval, Motif, Usual (Marroquin); Cases (Leschemelle); Good Companion (Brown); Traveller (Cowderoy); Chess Olé (Frank David); Smart (Wirth); Phoenix (Poisson) | **Ask** | Listed only as "freeware" with no terms for modification or commercial use. CTAN redistributes them under LPPL, which covers redistribution, not commercial rights. Fine for a free GPL build; a paid release needs the authors' OK. Marroquin already relicensed Merida as GPL for lichess, so asking him is realistic. |
| Eyes, Skulls | **Ask** | Monge; lichess has only Fantasy, Spatial and Celtic under MIT. Probably the same terms; confirm. |
| Free Staunton | **Ask** | Eran Karu / Ben Van Vlierden via PyChess; PyChess's ARTISTS file states no licence. |
| Virtual | **Ask** | Peter Wong; permission given for Scidb only. |
| USCF, Informant, CMF, Diagram/Symbol fonts | **Ask/Replace** | Origin unknown (foundry tags only). "Informant" and "USCF" are third-party names: rename. |

Added 2026-10-10: **Chessnut** (Alexis Luengas, Apache-2.0) and **RhosGFX** (CC0), converted from lichess to `tcl/pieces/chessnut.tcl` and `rhosgfx.tcl`. The seven themes that used Alpha, Berlin or Cheq now use Chessnut. Saved settings that name a removed set resolve through `::board::pieceset::lookup` (Alpha, Berlin, Cheq → Chessnut; Chess7 → Merida).

Other ready replacements with clear licences (lichess list): cburnett/mono (GPL-2+), merida (GPL-2+), fantasy/spatial/celtic (MIT), staunton (MIT), chessnut (Apache-2.0), rhosgfx (CC0), shapes (CC BY-SA 4.0), kiwen-suwi, Firi, totoy, papercut (CC BY 4.0). Avoid the many CC BY-NC-SA sets (horsey, california, cardinal, ...): non-commercial.

### Board textures: **Replaced (2026-10-11)**

The initial 2026-10-10 replacement used ambientCG CC0 colour maps. All 287 files now hold original procedural artwork generated by `scripts/generate-textures.py` (GPL-2). Names, sizes and theme palettes are unchanged; see `tcl/textures/SOURCES.txt`. The old images remain in git history.

Original finding:

No licences are recorded, and the file names point to sources whose terms forbid redistribution in original form:

- `*_S.jpg` names (`MarbleWhite0041_1_S`, `WoodPlatesOld0036_3_S`, `WoodFine0009_S`, …) are CGTextures, now Textures.com, whose licence forbids redistributing textures "in their original form".
- `patterncooler-NN.png` are PatternCooler; no licence found.
- `2274499870_9617a0512f_b.jpg` is a Flickr photo ID; the licence is per photo and unknown.
- `Diamond_Ebony_Marble.15194542_std.jpg`, `11932818.jpg`, `13621.jpg` look like stock-photo IDs.
- `wood_hickory_clear.png`, `wood_redalder_clear.png`, … are probably from the Wood Database.
- `Arena-Blue.png` is probably from the Arena GUI.

The metadata only names Photoshop, GIMP and camera models. Replace with CC0 textures (ambientCG, Poly Haven) or generated ones, as was done for Club.

### Flags

- The 16×11 flags embedded in `tcl/utils/countries.tcl` are famfamfam's: "available for free use for any purpose with no requirement for attribution". **Keep.**
- The 72×72 set in `tcl/flags/` (289 PNGs) came from addgadget.com with no licence. **Replaced (2026-10-11)**: reproducibly rendered from pinned flag-icons v7.5.0 (MIT) and our own drawings (GPL-2); see `tcl/flags/SOURCES.txt`. The old FIDE-logo flag (FID, a trademark) is now a neutral pawn.

### Embedded UI icons: **Replaced (2026-10-11)**

The earlier partial replacement below is superseded by the complete recursive
UI icon/control replacement in Done. All 1,482 literal embedded payloads are
inventoried; 1,035 are replaced and 447 country flag, licensed logo and
splash payloads retained. See `tests/tmp-app/icons/report.md`.

Earlier findings (`tcl/icons.tcl`, `tcl/app-db-icons.tcl`; historical count: 520 images):

**Replaced (2026-10-10): 365 generic icons** (file, edit and media controls, arrows, help, database types, players and the like) are now Noto Color Emoji renders (Apache-2.0) at the old pixel sizes. Bold, italic, underline, font size and alignment are drawn as letters and lines. Not replaced: icons under 12 px (tree toggles and similar), the pie charts, and the chess-specific icons (variants, game flags, annotation marks, chess file types, Informant, board and side-to-move). These are most likely Gregor Cramer's own work (GPL), but that isn't recorded. The "Informant" name still needs renaming.

Original finding:

No source comments; PNG metadata shows only editors (80 from Adobe ImageReady, typical of downloaded icon packs; 30 Inkscape; a few GIMP and Fireworks). Visually a mix of Crystal-style media buttons (Crystal Project, LGPL), FatCow-style database and folder icons (CC BY 3.0) and unidentified sets. One stacked-books archive icon resembles the WinRAR logo (trademark): replace it. The old IconDrawer logo also survived as `variant(Normal)` (22 px) and is now replaced. **Verdict: unknown.** For a commercial release, replace them with one licensed theme (e.g. Breeze or Oxygen, LGPL; Papirus, GPL-3; Fluent UI or Material Symbols, Apache-2.0/MIT).

## Keep

| Asset | Licence |
|---|---|
| Scidb code, Tcl, help texts, translations, themes (`tcl/themes`) | GPL-2, © Gregor Cramer. Keep `COPYING`, `COPYRIGHT` and the file headers. |
| Bundled libraries listed in `COPYRIGHT` (treectrl, Tkhtml3, TkDND, libharu, libhyphenate, universalchardet, expat, agg, minizip, zlib, zziplib, gdbm, tk_busy, tkPanedWindow) | BSD/MIT/zlib/LGPL/MPL/Tcl-style. Keep their notices. Check that gdbm (GPL) and universalchardet (MPL/GPL/LGPL) stay compatible if the licence ever changes. |
| Abel-Regular.ttf | SIL OFL 1.1, Reserved Font Name "Abel". |
| fontawesome-webfont.ttf | Font Awesome 4: SIL OFL 1.1. Include the OFL text, which is missing now. |
| Engines: Stockfish (all copies), Sjeng | GPL-3 / GPL-2; ship the source. **Name:** the modified builds (`stockfish-fork-2026-09`, `stockfish-scidb-compat`) shouldn't be shipped as "Stockfish". |
| reckless | AGPL-3 (`engines/reckless/LICENSE`): ship its source; fine as a separate engine binary. |
| dreamchess-derived 3D code | GPL-2. |
| `models_3d/`, `img/pieces_3d`, `web3d/` | Our own (Blender, commit 441b4fb). |
| Format names (ChessBase, Scid, PGN, Polyglot) in import/export, and the `freedesktop.org/*-ft-*` mime icons | Naming a format you read is a factual reference. Don't use the ChessBase logo; check that `chessbase-ft-*.png` doesn't copy it. |
| `opening-report/node_modules`, `.venv` | Development-only. Make sure they aren't shipped. |

## Name residue (trademark hygiene, not copyright)

- Font family names `Scidb Chess *`, `Scidb Symbol *` and `ScidbCircled` are visible in font pickers. They can be renamed in the `.sfd` files and rebuilt, but `tcl/` references them by name, so update both together.
- `tcl/help/*`: about 260 "Scidb" mentions per language.
- `freedesktop.org/scidb-ft-*`, `x-chess-scidb.xml`: the `.sci` format may keep the name "Scidb".
- Promo film narration says "Scidb".

## Suggested order

1. New app icon (blocks any release).
2. Delete Disney and OS-logo images; drop or replace DigifaceDigits.
3. Remove the Fritz and Informant sets, or redraw them under neutral names.
4. Ask Peter Wong about the virtualpieces sets; meanwhile ship without them.
5. For the remaining fonts, textures and flags: either trace each source, or replace them with known-licence sets. Lichess's piece sets (cburnett etc., mostly CC BY-SA/GPL/MIT, listed in the lila repo's COPYING.md) cover pieces; flag-icons (MIT) covers flags; CC0 textures (ambientCG, Poly Haven) cover textures.
6. Add `LICENSES/` holding each kept licence text (OFL for Abel and Font Awesome), referenced from `COPYRIGHT`.

### UI icon refinement (2026-10-11)

The deterministic UI generator now uses a coordinated seven-ink palette and one
soft tinted badge treatment for database categories. The 37 category families
have separate glyph identities; aliases and interaction states keep their glyph
across sizes. Dense small glyphs have original simplified geometry, with pixel
hinting at 16/24px and a translucent light keyline for dark panels. Side-to-move
markers and marbles use original shaded sphere drawings. Original opening-side
indicators and four expression drawings are in `tcl/cursor/icon-sources/` under
the existing GPL-2.0-or-later terms. Tabler remains pinned to v3.31.0 with the
same verified archive digest, MIT notice and embedded PNG licence metadata.

Review artifacts and the full mapping-change table are generated/reported in
`tests/tmp-app/icons2/`: before/after contact sheets on #f6f7f9/#1f2329 and
#f0f0f0/#2b2b2b, at native resolution and nearest-neighbour 2x. The generator
continues to edit only embedded image payloads and its original SVG sources;
image names, dimensions and Tcl logic remain unchanged.
