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
| Board textures | `tcl/textures/{dark,lite,tile}/{marble,misc,wood}` (≈280 jpg/png/gif) | No source recorded anywhere. Names such as `Arena-Blue.png` (Arena GUI?) and `Diamond_Ebony_Marble.15194542_std.jpg` / `11932818.jpg` (stock-photo IDs) are the most suspect. |
| Flags | `tcl/flags/` | `readme`: "downloaded from http://addgadget.com/clock/", with additions "found in the internet". No licence. (The about box also credits famfamfam flags, which are free for any use.) |
| Remaining tip-of-the-day images | `tcl/images/Motive-*` (animals, flowers, etc.) | No source recorded. |
| Cursors | `tcl/cursor/` | No source recorded; probably Gregor Cramer's own. |
| Embedded UI icons | `tcl/icons.tcl`, `tcl/app-db-icons.tcl` (hundreds of base64 images) | No source recorded. Many look like stock icon sets (Crystal, Oxygen, famfamfam: LGPL/CC). Needs a pass. |
| Font credits | `tcl/info.tcl` about box | Names the designers: Marroquin, Bentzen, Cowderoy, Leschemelle, Scott and Frank David (enpassant.dk freeware); Gorgonian (BabasChess); Brown (Good Companion); Poisson (Phoenix); Burnett (GPL); Eran Karu (PyChess, GPL); Maurizio Monge (Eyes, Fantasy, Skulls, Spatial). Check each site's terms. |

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
