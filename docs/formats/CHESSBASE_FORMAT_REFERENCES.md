# ChessBase Format References — Research Notes

**Compiled:** research session on ChessBase file-format documentation (official + unofficial).
**Purpose:** durable reference for Scidb's ChessBase interop work. Companion to the
existing `CBM_FORMAT_DESIGN.md`, `CBV_FORMAT_SPECIFICATION.md`, `2CBH_FORMAT_DESIGN.md`,
`CHESS960_CBG_REVERSE_ENGINEERING.md`, and `SCM_FORMAT_DESIGN.md`.

---

## 0. Key finding

ChessBase publishes **no binary format spec**. Their official "documentation" is
conceptual only (what each file is *for*). All byte-level layouts come from
**unofficial reverse engineering**, and coverage is uneven:

- **Fully documented (unofficial):** CBH, CBG, CBA, CBP, CBT, CBC, CBS, CBE, CBJ, CBV.
- **Partially documented:** CTG (leaked spec), CBM (Scidb's own RE).
- **Undocumented by ChessBase:** 2CBH (reverse engineered by Chesswiz: plaintext Move16 moves, read and write — `2CBH_FORMAT_DESIGN.md`), CBONE, CBCloud, CBZ, and all
  search-booster / theme-key files.

---

## 1. Official ChessBase documentation (conceptual only — no binary layout)

| Source | URL | Covers |
|--------|-----|--------|
| File names and extensions (CB 17) | `https://help.chessbase.com/CBase/17/Eng/filenames.htm` | Authoritative list of every extension + purpose; 2CBH conceptual description |
| Database formats (CB 16) | `https://help.chessbase.com/cbase/16/eng/database_formats.htm` | CBH, CTG, PGN, CBF, CBONE, CBCloud |
| Database formats (CB 18) | `https://help.chessbase.com/CBase/18/Eng/database_formats.htm` | Same, newer |
| InstructionsToChessBase10.pdf | `https://www.chessbase.com/download/pdf/InstructionsToChessBase10.pdf` (pp. 110–111) | File format overview |

These tell you *what* each file is, but **not a single byte offset**.

---

## 2. Unofficial reverse-engineered specs (the real documentation)

### 2.1 The canonical CBH spec — "Yarin's document"

**Primary source:** `https://talkchess.com/viewtopic.php?t=29468`
(Yarin, Aug 19 2009, "CBH file format"). This is *the* de-facto spec for the
entire classic CBH family. Every implementation (Scidb, Scid, Morphy, cbh2pgn)
builds on it. Full byte-level content reproduced in §4 below.

### 2.2 Derivative implementations (all based on Yarin)

| Project | URL | Language | Notes |
|---------|-----|----------|-------|
| Morphy | `https://github.com/Yarin78/morphy` | Java | Complete CBH docs in `morphy-cbh/docs/README.md` |
| cbh2pgn | `https://codeberg.org/FelixKling/cbh2pgn` | Python | Adds ECO + CBJ team-name support |
| Scid / Scid vs. PC | (SourceForge / GitHub) | C++ | CBH read/write in `src/cbh*` |
| Scidb | this repo | C++ | CBH/CBG/CBA/namebases + CBV + CBM |

### 2.3 CTG (opening book) — partial spec

| Source | URL | Notes |
|--------|-----|-------|
| CTG specification by Sesse (Steinar Gunderson) | Rybka Forum, Sep 30 2007; archived at `https://web.archive.org/web/20210129162445/http://rybkaforum.net/cgi-bin/rybkaforum/topic_show.pl?tid=2319` | The leaked partial CTG spec |
| ctgexporter | `https://github.com/sshivaji/ctgexporter` | CTG → Polyglot converter |
| chess-opening-book-reader | `https://github.com/gmcheems-org/chess-opening-book-reader` | JS CTG parser |
| Chess Programming Wiki — CTG | `https://www.chessprogramming.org/CTG` | 4-file structure summary |

### 2.4 CBV (archive)

Documented in this repo (`CBV_FORMAT_SPECIFICATION.md`) and implemented in
`src/db/cbv/cbv_codec.cpp`.

### 2.5 CBM (media)

No public spec. Reverse-engineered only in this repo (`CBM_FORMAT_DESIGN.md`).

### 2.6 German-language CBH writeup

- Schachclub Leinzell — "Das CBH-Format" by Peter Schreiner (March 2001).

### 2.7 Chess Programming Wiki — ChessBase (Database)

`https://www.chessprogramming.org/ChessBase_(Database)` — full file-extension
list, version history, and links to the above sources.

---

## 3. Formats with NO public documentation

| Format | Status |
|--------|--------|
| **2CBH / 2CBG** (ChessBase 17+) | No spec. Official help describes it conceptually only. Chesswiz RE (`2CBH_FORMAT_DESIGN.md`): moves are **plaintext** Move16 codes (the earlier "encrypted" reading was wrong); index, namebases, annotations, setups/Chess960 and teams decoded; Chesswiz writes and appends databases that ChessBase 26 re-opens. |
| **CBONE** (single-file DB, CB 16+) | No spec anywhere. |
| **CBCloud** (4-file cloud DB) | No spec. |
| **CBZ** (encrypted archive) | No spec — password-protected by design. |
| **Search boosters** (CBB, CBO, CBD, CBGI, CIT, CIP) | No spec. |
| **Theme keys** (CKO/CPO, CKN/CPN, CK1-3/CP1-3) | No spec. |

---

## 4. Yarin's CBH spec (full byte-level content, reproduced for reference)

> Source: TalkChess `viewtopic.php?t=29468`. Derived from ChessBase 9.0.
> Search booster (CBB) and archive (CBV) formats are explicitly *not* covered here.

### 4.1 File roles

- **CBH** — list of games + pointers into the other files.
- **CBG** — actual game data (move sequence).
- **CBA** — game annotations.
- **CBP** — player data.
- **CBT** — tournament data.
- **CBC** — annotator data.
- **CBS** — source data.
- **CBE** — team data.
- **CBM** — media (unknown in Yarin's doc).
- **CBJ** — game→team mappings among other things (unknown in Yarin's doc).
- **CBB** — search booster (unknown).

### 4.2 CBH file

46-byte header, 46-byte records.

**Header:**
```
Ofs 0,  Len 6  - ??  00 00 2C 00 2E 01 if created with cb9,
                     00 00 24 00 2E 01 if created with cblight
Ofs 6,  Len 4  - Number of games+1
Ofs 12, Len 4  - ??  Can be 2
Ofs 16, Len 4  - ??  Can be 3
Ofs 20, Len 4  - ??  Can be 3
Ofs 40, Len 4  - Either number of games+1 (?), or 0 (?)
Other bytes zero?
```

**Game record:**
```
Ofs 0,  Len 1  - bit 0: 1 = game (can be 0 if guiding text is 1?)
                 bit 1: 1 = guiding text
                 bit 7: 1 = marked as deleted
Ofs 1,  Len 4  - Position in .cbg where game data starts (or guiding text)
Ofs 5,  Len 4  - Position in .cba where annotations start (0 = none)
Ofs 9,  Len 3  - White player number (0 = first player in .cbp)
Ofs 12, Len 3  - Black player number
Ofs 15, Len 3  - Tournament number (0 = first in .cbt)
Ofs 18, Len 3  - Annotator number (0 = first in .cbc)
Ofs 21, Len 3  - Source number (0 = first in .cbs)
Ofs 24, Len 3  - year & month & day
                 bit 0-4  = Day (0 = unset)
                 bit 5-8  = Month (0 = unset)
                 bit 9-20 = Year (0 = unset)
Ofs 27, Len 1  - 3 = line, 2 = 1-0, 1 = ½-½, 0 = 0-1,
                 6 = +:-, 5 = =:=, 4 = -:+, 7 = 0-0
Ofs 28, Len 1  - Line evaluation (only if byte above is 3)
                 0 = unset, 18 = +-, 16 = +/-, 14 = +/=, 11 = =,
                 13 = unclear, 15 = -/=, 17 = -/+, 19 = -+,
                 0x92 = theoretical novelty, 0x2C = with compensation,
                 0x84 = with counterplay, 0x24 = with initiative, 0x28 = with attack
Ofs 29, Len 1  - round (0 = unset)
Ofs 30, Len 1  - subround (0 = unset)
Ofs 31, Len 2  - white rating (0 = unset)
Ofs 33, Len 2  - black rating (0 = unset)
Ofs 35, Len 2  - bit 0-6: Sub ECO (00-99)
                 bit 7-15: ECO (0 = unset, 1 = A00, 500 = E99)
Ofs 37, Len 2  - Medals (bit flags):
                 bit 0 Best game, 1 Decided tournament, 2 Model game, 3 Novelty,
                 4 Pawn structure, 5 Strategy, 6 Tactics, 7 With attack,
                 8 Sacrifice, 9 Defense, 10 Material, 11 Piece play, 12 Endgame,
                 13 Tactical blunder, 14 Strategical blunder, 15 User
Ofs 39, bit 0  - 1 = Contains critical position
Ofs 39, bit 1  - 1 = Contains correspondence header
Ofs 40, bit 0  - 1 = Contains embedded audio
Ofs 40, bit 1  - 1 = Contains embedded picture
Ofs 40, bit 2  - 1 = Contains embedded video
Ofs 40, bit 3  - 1 = Contains game quotation
Ofs 40, bit 4  - 1 = Contains path structure
Ofs 40, bit 5  - 1 = Contains piece path
Ofs 41, bit 1  - 1 = Contains training annotation
Ofs 42, Len 1  - bit 0: P (game starts from non-initial position)
                 bit 1: v (contains variations)
                 bit 2: c (contains commentary)
                 bit 3: s (contains symbols)
                 bit 4: annotated with colored squares
                 bit 5: annotated with arrows
                 bit 7: contains time notifications (??)
Ofs 43         - ?
Ofs 44, Len 1  - bit 0-1: 1=V, 2=r, 3=R (variation count class; bit 1 of ofs 42 set)
                 v=[1,50], V=[51,300], r=[301,1000], R=[1001,]
                 bit 2: C (many commentaries), bit 3: S (many symbols),
                 bit 4: color squares in >=10 positions, bit 5: arrows in >=10 positions
Ofs 45, Len 1  - number of moves in main variant (255 = check game data)
```

**Guiding-text record:**
```
Ofs 0-4  - same as game record
Ofs 5    - ?
Ofs 7,  Len 3  - Tournament Id
Ofs 10, Len 3  - Source Id
Ofs 13, Len 3  - Annotator Id
Ofs 16, Len 1  - Round
Ofs 17, Len 1  - ? 0
Ofs 18, Len 1  - bit 2: Contains stream (wmv)
Ofs 19, Len 1  - bit 0: audio link, bit 1: image link, bit 2: video link
```

### 4.3 CBG file

26-byte header. Actual game data pointed to from CBH.

```
Ofs 0,  short 2  - Pointer to first game (?)
Ofs 2,  int   4  - Pointer to end of file (= file length)
Ofs 6,  int   4  - ? Accumulated value of game bytes length changed
Ofs 14, int   4  - Pointer to end of file (= file length) (same?)
Ofs 22, int   4  - ? Accumulated value of game bytes length changed
```

**At game start:**
```
+0  int 4  - bit 0-29: Game size in bytes (incl. this, excl. trash bytes)
             bit 30: game doesn't start with initial position
             bit 31: data is not encoded (iff guiding text?)
+4  byte (28) - if game doesn't start with initial position, that position follows
?   byte ?    - game data (see below), ends with 0C (= pop position)
```

**For guiding texts:**
```
+0  int 4  - bit 0-29: size, bit 30: non-initial position, bit 31: not encoded
+4  word 2 - ? (1?)
+6  word 2 - number of titles (can be 0) (little-endian)
For each title:
  +0 word 2 - language (0=english,1=german,2=france,3=spain,4=italian,5=dutch)
  +2 word 2 - length of title
  +4 string - title
```

**Game setup format:**
```
Ofs 0, Len 1  - Always 1?
Ofs 1, Len 1  - bit 0-3: en passant file (0=none, 1=a, 8=h)
                bit 4: 0=white to move, 1=black to move
Ofs 2, Len 1  - bit 0: White O-O-O, bit 1: White O-O,
                bit 2: Black O-O-O, bit 3: Black O-O
Ofs 3, Len 1  - next move number
Ofs 4, Len 24 - piece setup as bit stream (MSB at ofs 4):
                0=empty, 10001=W king, 10010=W queen, 10011=W knight,
                10100=W bishop, 10101=W rook, 10110=W pawn,
                11001=B king, 11010=B queen, 11011=B knight,
                11100=B bishop, 11101=B rook, 11110=B pawn
Ofs 28        - start of moves
```
Board scanned a1→a8, b1→b8, etc. First piece of each type found is the
"first piece", etc. (including pawns, both colors).

**Game data (move encoding):**
Moves are a byte stream. Most moves are a single byte describing relative
movement of a piece ("first rook" = rook starting a1/a8, "second rook" = h1/h8,
etc.). To decode: first decrease the byte value by the number of moves processed
so far (minus 0 for the first move). Special codes for multi-byte moves and
begin/end of variations don't count. Move count is NOT restarted at variation end.
Pawn moves seen from the mover's point of view; pawn captures include en passant.

When a "first piece" is captured, the "second piece" becomes the new "first",
and "third" becomes "second". When a "second piece" is captured, the old "third"
becomes "second". A "fourth piece" (or higher) never promotes and is always
encoded as a multi-byte move. Pawns are never adjusted (e-pawn stays "fifth pawn").

**Multi-byte moves:** start square + destination square, 6 bits each.
Bit 0-5 of second byte = start square (a1=0, a2=1, h8=63); bit 6-7 of second byte
+ bit 0-3 of first byte = destination square. For pawn promotions, bit 4-5 also
used (0=queen, 1=rook, 2=bishop, 3=knight).

**Single-byte move translation table** (bytes look random but are "encrypted"
via a static 256-byte array at `0x7AE4A8` in CBase9.exe / `0x9D6530` in
CBase10.exe, starting `0xAA, 0x49, 0x39, 0xD8, 0x5D, 0xC2, 0xB1, 0xB2`).
Reverse-looking-up these values yields the order listed below.

```
Special:
  AA = null move
King:
  49=y+1  39=x+1,y+1  D8=x+1  5D=x+1,y+7  C2=y+7  B1=x+7,y+7  B2=x+7
  47=x+7,y+1  76=0-0  B5=0-0-0
First queen:
  A5=y+1 B8=y+2 CB=y+3 53=y+4 7F=y+5 6B=y+6 8D=y+7
  79=x+1 BE=x+2 EB=x+3 21=x+4 99=x+5 D2=x+6 57=x+7
  4D=x+1,y+1 B4=x+2,y+2 BF=x+3,y+3 62=x+4,y+4 BD=x+5,y+5 24=x+6,y+6 96=x+7,y+7
  A7=x+1,y+7 48=x+2,y+6 28=x+3,y+5 6E=x+4,y+4 2F=x+5,y+3 5A=x+6,y+2 18=x+7,y+1
First rook (a1/a8):
  4E=y+1 F8=y+2 43=y+3 D7=y+4 63=y+5 9C=y+6 E6=y+7
  2E=x+1 C6=x+2 26=x+3 88=x+4 30=x+5 61=x+6 6F=x+7
Second rook (h1/h8):
  14=y+1 A9=y+2 68=y+3 EE=y+4 FB=y+5 77=y+6 E2=y+7
  A6=x+1 05=x+2 8B=x+3 A1=x+4 98=x+5 32=x+6 52=x+7
First bishop (c1/c8):
  02=x+1,y+1 97=x+2,y+2 E1=x+3,y+3 41=x+4,y+4 C3=x+5,y+5 7C=x+6,y+6 E4=x+7,y+7
  06=x+1,y+7 B7=x+2,y+6 55=x+3,y+5 D9=x+4,y+4 2C=x+5,y+3 AE=x+6,y+2 37=x+7,y+1
Second bishop (f1/f8):
  F6=x+1,y+1 3F=x+2,y+2 08=x+3,y+3 93=x+4,y+4 73=x+5,y+5 5E=x+6,y+6 78=x+7,y+7
  35=x+1,y+7 F2=x+2,y+6 6D=x+3,y+5 71=x+4,y+4 A2=x+5,y+3 F3=x+6,y+2 16=x+7,y+1
First knight (b1/b8):
  58=x+2,y+1 3D=x+1,y+2 FA=x-1,y+2 E9=x-2,y+1 BA=x-2,y-1 D4=x-1,y-2 DD=x+1,y-2 4A=x+2,y-1
Second knight (g1/g8):
  C4=x+2,y+1 0E=x+1,y+2 FE=x-1,y+2 5F=x-2,y+1 75=x-2,y-1 07=x-1,y-2 89=x+1,y-2 34=x+2,y-1
a2/a7-pawn: 2D=one  C1=two  8E=capture right  F5=capture left
b2/b7-pawn: 64=one  17=two  70=capture right  A4=capture left
c2/c7-pawn: 7B=one  DA=two  E0=capture right  85=capture left
d2/d7-pawn: C5=one  0B=two  90=capture right  F9=capture left
e2/e7-pawn: 84=one  FF=two  15=capture right  36=capture left
f2/f7-pawn: 09=one  9E=two  7D=capture right  DE=capture left
g2/g7-pawn: BB=one  DF=two  BC=capture right  3A=capture left
h2/h7-pawn: 12=one  33=two  13=capture right  19=capture left
Second queen:
  E5=y+1 94=y+2 50=y+3 11=y+4 EA=y+5 31=y+6 01=y+7
  5C=x+1 95=x+2 CA=x+3 D3=x+4 1D=x+5 7E=x+6 EF=x+7
  44=x+1,y+1 80=x+2,y+2 A0=x+3,y+3 1F=x+4,y+4 83=x+5,y+5 00=x+6,y+6 4B=x+7,y+7
  67=x+1,y+7 20=x+2,y+6 5B=x+3,y+5 2A=x+4,y+4 92=x+5,y+3 B6=x+6,y+2 60=x+7,y+1
Third queen:
  1A=y+1 42=y+2 0F=y+3 0D=y+4 B0=y+5 D1=y+6 23=y+7
  F0=x+1 7A=x+2 54=x+3 4F=x+4 F4=x+5 A8=x+6 72=x+7
  E7=x+1,y+1 40=x+2,y+2 38=x+3,y+3 59=x+4,y+4 87=x+5,y+5 E8=x+6,y+6 6C=x+7,y+7
  86=x+1,y+7 04=x+2,y+6 F1=x+3,y+5 8C=x+4,y+4 CE=x+5,y+3 6A=x+6,y+2 DB=x+7,y+1
Third rook:
  81=y+1 82=y+2 9A=y+3 1B=y+4 9D=y+5 0A=y+6 2B=y+7
  8F=x+1 CD=x+2 ED=x+3 10=x+4 74=x+5 69=x+6 D6=x+7
Third bishop:
  51=x+1,y+1 B9=x+2,y+2 45=x+3,y+3 3B=x+4,y+4 56=x+5,y+5 91=x+6,y+6 FD=x+7,y+7
  AB=x+1,y+7 66=x+2,y+6 3E=x+3,y+5 46=x+4,y+4 B3=x+5,y+3 FC=x+6,y+2 C8=x+7,y+1
Third knight:
  9B=x+2,y+1 C0=x+1,y+2 E3=x-1,y+2 A3=x-2,y+1 AC=x-2,y-1 C9=x-1,y-2 EC=x+1,y-2 27=x+2,y-1
Special:
  29 = multiple byte move to follow
  9F = dummy - skip and don't count this move (padding in earlier CB versions)
  25 C7 CC 65 4C D5 1E CF 03 8A AF F7 AD 3C D0 22 1C = unused
  DC = push position (start of variant)
  0C = pop position (end of variant)
```

### 4.4 CBA file (annotation data)

26-byte header. Annotation data pointed to from CBH.

**Game start:**
```
Ofs 0,  Len 3  - game ID this annotation is for (little-endian)
Ofs 4         - ?
Ofs 10, Len 4  - number of bytes used for annotations in this game,
                 starting at ofs 0 (big-endian)
Ofs 14        - start of annotation data
```

**Annotation data:**
```
Ofs 0, Len 3  - position in game sequence (0=start, 1=after first move,
                -1=game general) (little-endian)
Ofs 3, Len 1  - type of annotation:
                0x02 = text after move
                0x03 = symbols
                0x18 = critical position
                0x82 = text before move
                0x14 = pawn structure
                0x15 = piece path
                0x13 = game quotation
                0x22 = medal
                0x23 = variation color
                0x10 = sound
                0x20 = video
                0x11 = picture
                0x09 = training annotation
                0x61 = correspondence header (always move -1?)
                0x19 = correspondence move (header must exist?)
Ofs 4, Len 2  - number of bytes for this annotation (from ofs 0, little-endian)
```

**Symbols:** `Ofs 6` move comment, `Ofs 7` position evaluation (optional, 0 if
missing), `Ofs 8` prefix (optional, 0 if missing).

**Text:** `Ofs 6` = 0?, `Ofs 7` language (0=All, 0x2A=English, 0x35=Deutsch,
0x31=France, 0x2B=Spain, 0x46=Italian, 0x67=Dutch, 0x75=Portugese, 0x00=Pol),
`Ofs 8` = text. `0x9E` = diagram (`{#}`).

**Critical position:** `Ofs 6` = 1 opening, 2 middlegame, 3 endgame.

**Medal:** `Ofs 6, Len 4` — bit 0-15 (bit 0 = 1 in ofs 9) sets medals.

**Variation color:** `Ofs 6`=0?, `Ofs 7`=blue, `Ofs 8`=green, `Ofs 9`=red.

**Move comments:** 1=!, 2=?, 3=!!, 4=??, 5=!?, 6=?!, 0x16=Zugzwang, 8=Only move.

**Position evaluations:** 0x12=+-, 0x10=+/-, 0x0E=+/=, 0x0B==, 0x0D=unclear,
0x0F==/+, 0x11=-/+, 0x13=-+, 0x92=theoretical novelty, 0x2C=with compensation,
0x84=with counterplay, 0x24=with initiative, 0x28=with attack,
0x20=development advantage, 0x8A=zeitnot.

**Prefix:** 0x91=Editorial annotation, 0x8E=better is, 0x8F=worse is,
0x90=Equivalent is, 0x8C=with the idea, 0x8D=directed against.

### 4.5 CBP file (player data)

28-byte header, 67-byte records.

**Header:**
```
Ofs 0,  Len 4  - number of player records (little endian)
Ofs 4,  Len 4  - the root record
Ofs 8,  Len 4  - the number 1234567890 (reserved?)
Ofs 12, Len 4  - size of a record (excl. 9 bytes of binary-tree structure)
Ofs 16, Len 4  - first deleted record (-1 if none)
Ofs 20, Len 4  - number of existing records (little endian)
Ofs 24, Len 4  - ? unused, always 0?
```
Binary tree sorts players alphabetically (last name, first name); AVL tree keeps
it balanced.

**Record:**
```
Ofs 0,  Len 4  - -999 if deleted, else left child node (-1 if missing) (LE)
Ofs 4,  Len 4  - right child node (-1 if missing); if deleted, next deleted
                 record (or -1 if last) (LE)
Ofs 8,  Len 1  - height(right subtree) - height(left subtree); AVL balance
                 factor, usually -1/0/1, may be -2/2 temporarily; 0 if deleted
Ofs 9,  Len 30 - last name
Ofs 39, Len 20 - first name
Ofs 59, Len 4  - number of games with this player? (LE)
Ofs 63, Len 4  - first game id with this player? (LE)
```
All other player info comes from the Player Encyclopedia.

### 4.6 CBT file (tournament data)

28-byte header, 99-byte records. Same header format as CBP. Binary tree sorts
tournaments alphabetically.

```
Ofs 0,  Len 2  - 19 FC == deleted??  FF FF == exist??
Ofs 9,  Len 40 - title (zero-terminated)
Ofs 49, Len 30 - place (zero-terminated)
Ofs 79, Len 3  - date (LE): bit 0-4=day, 5-8=month, 9-20=year (0=unset)
Ofs 83, Len 1  - bit 0-4 game type: 0=unset, 1=game, 2=match, 3=tourn, 4=swiss,
                 5=team, 6=k.o., 7=simul, 8=schev
                 bit 5: blitz, bit 6: rapid, bit 7: corresp
Ofs 85, Len 1  - nation (0=unset, AFG=0x01 ... GBR=0xF7; full list in Cbase9.exe
                 between 0x6ba154 and 0x6ba510, reverse order)
Ofs 87, Len 1  - category (0-99, 0=unset)
Ofs 88, Len 1  - bit 0: ?? (almost always same as bit 1), bit 1: complete,
                 bit 2: board points
Ofs 89, Len 1  - number of rounds (0-255, 0=unset)
Ofs 91, Len 4  - number of games with this tournament? (LE)
Ofs 95, Len 4  - first game id with this tournament? (LE)
```

### 4.7 CBC file (annotator data)

28-byte header, 62-byte records. Same header as CBP. Binary tree sorts
annotators alphabetically.

```
Ofs 9,  Len 45 - annotator name (not zero-terminated!?)
Ofs 54, Len 4  - number of games with this annotator? (LE)
Ofs 58, Len 4  - first game id with this annotator? (LE)
```

### 4.8 CBS file (source data)

28-byte header, 68-byte records. Same header as CBP. Binary tree sorts sources
alphabetically.

```
Ofs 9,  Len 25 - title
Ofs 34, Len 16 - publisher
Ofs 50, Len 3  - publication (LE)
Ofs 54, Len 3  - date (LE)
Ofs 58, Len 1  - version
Ofs 59, Len 1  - quality (1=high, 2=normal, 3=low, 0=unset but treated as low)
Ofs 60, Len 4  - number of games with this source? (LE)
Ofs 64, Len 4  - first game id with this source? (LE)
```

### 4.9 CBE file (team data)

28-byte header, 72-byte records. Same header as CBP. Binary tree sorts teams
alphabetically. A recent invention, not in cblight (which is why CBP lacks team
pointers).

```
Ofs 9,  Len 45 - title
Ofs 54, Len 2  - team number (ChessBase crashes if large; 5000 works, 9999 not)
Ofs 58, Len 1  - bit 0: season (if set, year is year/year+1, else just year)
Ofs 59, Len 2  - year
Ofs 63, Len 1  - nation (same numbering as CBT)
Ofs 64, Len 4  - number of games with this team? (LE)
Ofs 68, Len 4  - first game id with this team? (LE)
```

---

## 5. CTG format summary (from Chess Programming Wiki + Sesse's spec)

- Four files: **CTG** (real data), **INI** (aux text), **CTB** (bitmap of free
  pages), **CTO** (lookup table for fast indexed access).
- Only White-to-move positions stored (with moves, annotations, engine
  recommendations, statistics). Probing black positions requires color flipping
  (including en passant square and castling rights).
- If white king is on files a-d and neither side has castling rights, the board
  is mirrored horizontally.
- CTG file organized in 4 KiB pages; first page = header (number of games),
  followed by data pages. Each data page starts with a header (number of
  positions + bytes per page), then variable-length position entries.

---

## 6. Complete ChessBase file-extension list (official + CPW)

| Ext | Purpose |
|-----|---------|
| `.cbh` | Game data (header/index) |
| `.cbg` | Game moves and variations |
| `.cba` | Annotations |
| `.cbp` | Player index |
| `.cbt` | Tournament index |
| `.cbc` | Commentators index |
| `.cbs` | Source index |
| `.cbe` | Team index |
| `.cbj` | Second header file, team info, final material |
| `.cbm` | Multimedia baggage in HTML database text files |
| `.cbb` | Search booster |
| `.cbgi` | Second smaller search booster |
| `.cit` / `.cip` | Index files for fast player/tournament/team access (auto-generated) |
| `.cbo` | Extra search booster for opening positions |
| `.cbd` | Double hash tables (hashed game info) |
| `.cko` / `.cpo` | Opening key names / positions |
| `.ckn` / `.cpn` | General theme key / definitions |
| `.ck1-3` / `.cp1-3` | Tactical/strategic/endgame theme keys + definitions |
| `.ctb` / `.ctg` / `.cto` | Opening book (bitmap / data / lookup) |
| `.cbv` | Archived (compressed) database |
| `.cbz` | Encrypted archived database (password-protected) |
| `.ini` | Database initialisation file |
| `.bmp` / `.avi` / `.wav` | Multimedia subdirectories (picture/video/sound) |
| `.cbf` | Old ChessBase games file (CB 3 format) |
| `.cbi` | Old ChessBase index file |
| `.pgn` | ASCII text format |
| `.pgi` | ChessBase (redundant) index into a PGN file |
| `.cbone` | Single-file database (CB 16+) |
| `.2cbh` / `.2cbg` | ChessBase 17 successor format |

---

## 7. Version history (context)

ChessBase 1 (1987, Atari ST) → 2 (1988, DOS) → 3 (1991, CBF/CBI format) →
4 (1993) → Windows (1994) → 6.0 (1996, **CBH format introduced**) → 7 (1998) →
8 (2000) → 9 (2004) → 10 (2008) → 11 (2010) → 12 (2012) → 13 (2013) →
14 (2016) → 15 (2018) → 16 (2020, CBONE) → 17 (2022, **2CBH format**).

The CBF format (CB 3) used two files (data `.cbf` + index `.cbi`) with a
deterministic move generator storing the generation number of a move. CBH
(CB 6, 1996) added nested variations, annotations, multimedia, and richer
indices.
