# Permission requests for the freeware piece sets

These sets are distributed as "freeware" with no terms on modification or
commercial use (see `docs/ASSET_LICENSE_AUDIT.md`). A free GPL release is
reasonable as is. A paid Windows/macOS release needs either each author's
written OK or a replacement set.

| Author | Sets in Chesswiz | Where to reach them |
|---|---|---|
| Armando H. Marroquín | Adventurer, Condal, Kingdom, Leipzig, Lucena, Magnetic, Marroquin, Maya, Mediaeval, Motif, Usual | via en passant (enpassant.dk); he relicensed Merida as GPL-2+ for lichess, so the lichess maintainers may have a current address |
| Gorgonian | Club (ex-Fritz), Aquarium, Bookup, Celtic, ChessCube, Habsburg, Military, Old Style, Clarity (ex-Segoe), Standard/CMF, Zurich | gorgonian.weebly.com (BabasChess) |
| Matthieu Leschemelle | Cases | via enpassant.dk |
| David L. Brown | Good Companion | bstephen.me.uk (Good Companion fonts page) |
| Alan Cowderoy | Traveller | via enpassant.dk |
| Frank David | Chess Olé | via enpassant.dk |
| Christoph Wirth | Smart | via enpassant.dk |
| Christian Poisson | Phoenix | christian.poisson.free.fr |
| Maurizio Monge | Eyes, Skulls | his lichess sets (Fantasy, Spatial, Celtic) are MIT; ask him to confirm the same for these |
| Eran Karu / Ben Van Vlierden | Free Staunton | benvanvlierden.nl |
| Peter Wong | Virtual | virtualpieces.net |

If an author can't be reached or declines, drop the set. A saved setting
that names it then falls back to Merida (`::board::pieceset::lookup`); add
an entry to `Replaced` in `tcl/board-pieceset.tcl` to choose a closer
replacement.

## Email template

Subject: Permission to include your chess font "<SET>" in Chesswiz

Dear <NAME>,

I maintain Chesswiz, a chess database application based on the open-source
Scidb (GPL). Scidb has shipped your piece set "<SET>" for many years, with
credit to you in its About box, under the freeware terms on <SOURCE>.

I'm preparing Windows and macOS releases, some of which may be sold. Could
you confirm that I may:

1. include "<SET>" in Chesswiz, in the converted form the application uses
   (outlines embedded in a Tcl file and a TrueType font named
   "Scidb Chess <SET>");
2. distribute it in both free and paid editions; and
3. if you're willing, under an open licence such as the SIL Open Font
   License, MIT or GPL-2-or-later, as you did for Merida on lichess.

You will of course keep the credit in the About box and the notices.
If you'd rather the set not be included, I'll remove it.

Many thanks,
<YOUR NAME>
<CONTACT>
