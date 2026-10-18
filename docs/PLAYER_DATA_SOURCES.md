# Player data sources: where the player dictionary's rating lists come from

Player data plan, step 4. Each source was checked on **2026-10-18**: current
download URL, the file format found there today, and the terms of use. Only a
list whose terms allow downloading and local, private use is wired into the
app, and only ever on the user's explicit request (a click in the ratings
update dialog) — never automatically, and nothing is redistributed with the
application.

## FIDE (world list) — step 1, already done

- URL: https://ratings.fide.com/download/players_list.zip (`players_list_foa.txt`,
  fixed columns, read from the header), monthly.
- Terms: FIDE publishes the list for download on ratings.fide.com.
- Implemented: step 1 (`Player::parseFideFoaRating`, `::scidb::app::filterFideList`,
  `::playerdata::updateFide`). Kept: players rated 1800+ in any speed, or titled.

## DWZ — Deutscher Schachbund (Germany)

- Page: https://www.schachbund.de/download.html  ("Download von DWZ-Daten"):
  the files are re-created from the Wertungsportal (DEWIS) **daily at 04:15**
  and enriched with the current FIDE data (country, title, Elo).
- URL used: https://www.schachbund.de/download-dwz-daten.html?file=files/wertungsportal/downloads/export/csv/LV-0-csv.zip
  — `LV-0` is the whole dataset (zip, ~3 MiB); the other `LV-*` files hold one
  regional association each. The zip contains `spieler.csv`, `vereine.csv`,
  `verbaende.csv`, `README.txt`.
- Format found today (from the zip's README.txt): `spieler.csv` is
  windows-1252, comma-separated, fields containing spaces or commas are quoted;
  sorted by DWZ. Header columns (order as found 2026-10-18):

  `ID, ZPS, Mitgliedsnummer, Status, "Name,Vorname", Geschlecht,
  Spielberechtigung, Geburtsjahr, "Letzte Auswertung", DWZ, Index,
  FIDE-Elozahl, FIDE-Titel, FIDE-ID, FIDE-Land, Vorname, Nachname,
  FIDE-Frauentitel, FIDE-Elozahl-Schnellschach, FIDE-Elozahl-Blitz`

  with `ID` = the DEWIS member id (a member appears once per club membership:
  dedupe by this id), `Status` = A(ktiv)/P(assiv), `Geschlecht` = M/W,
  `Geburtsjahr` = birth year, and the five trailing FIDE columns from FIDE's
  list. Sample row shape (measured):
  `NU4073762,10614,1081,P,"Nachname,Vorname",M,,1990,202517,2400,12,2500,GM,1503014,NOR,…`
- Terms found: the zip's README.txt says — *"Eine Veroeffentlichung dieser
  Daten ist nur nach vorheriger Absprache mit dem zustaendigen DWZ-Referenten
  erlaubt!"* (publication only with prior agreement with the DWZ officer).
  Downloading for one's own local use is what the page offers; that is all the
  app does. Nothing is republished, and no copy of the list is shipped.
- Implemented: `Player::parseDwzRating` accepts both this CSV and the shipped
  fixed-column list of 2012; `::scidb::app::filterRatingList dwz` keeps the
  rows the parser keeps (DWZ ≥ 1800 or a FIDE title). Columns are found by
  header name, so a moved column does not break the reader.

## ECF — English Chess Federation (England)

- Site: rating.englishchess.org.uk (the ECF rating system; the old
  ecfrating.org.uk host is gone).
- URL used: https://rating.englishchess.org.uk/api/rating-list/csv — the full
  current rating list as one CSV, UTF-8.
- Terms found: https://rating.englishchess.org.uk/help/api — "Public API …
  allows other software systems to make quick ad hoc requests … It also allows
  the download of complete ratings lists equivalent to those in the previous
  system." There is a fairness limit: at most 10 minutes of processing time per
  day and class-C network, reset at midnight GMT. So the app downloads the list
  only on request and never mirrors it.
- Format found today: a comma-separated CSV with header row; missing values are
  empty; the name field is quoted when it contains a comma
  (`"Arthurton, Robert J"`). Header columns (order as found 2026-10-18):

  `ECF_code, full_name, member_no, FIDE_no, gender, nation, original_standard,
  standard_original_category, revised_standard, standard_revised_category,
  original_rapid, … (rapid, blitz, and the six online ones in pairs) …,
  club_code, club_name, title`

  with `ECF_code` like `280660F` (six digits + check letter A–L),
  `full_name` = "Surname, Forename", `FIDE_no` often empty, `gender` = M/F/N
  (N treated as unspecified), `nation` = ISO-3 (ENG/WLS/SCO/… or empty;
  `club_code` beginning with `F` like `FUSA` also names the FIDE federation),
  `title` = FIDE title(s) such as `GM` or `IM/WGM` (added May 2024 per the API
  help). The ratings are the Elo-like 4-digit scale introduced in August 2020
  (the shipped file of 2012 used the old 3-digit grades — values below ~600 in
  the dictionary's ECF slot must be read as that scale; see
  `docs/PLAYER_DATA_SOURCES.md` in use: the old parser keeps reading the 2012
  columns and the new parser reads the header).
- Note: no birth years are published (privacy).
- Kept: `revised_standard` (falling back to `original_standard`) ≥ 1600, or a
  FIDE title — about ten thousand of the ~46,000 rows.

## ICCF — International Correspondence Chess Federation

- Site: https://www.iccf.com/ratings — the public rating page with a
  "Download as CSV" link for the full current list (shown there as "N players
  in the list, Ratinglist valid from … to …").
- URL used: https://www.iccf.com/ratings — the CSV is behind an ASP.NET form
  postback (no static file exists; tried plausible static paths — all 404).
  The app therefore fetches the page first, then posts the form (session cookie
  plus `__VIEWSTATE`/`__EVENTVALIDATION`) exactly like clicking that link.
  This is the brittle part of the feature: if ICCF rebuilds the site, the
  fetch must be re-pointed. The parser itself checks every record's shape, so
  a changed page errors out instead of misparsing.
- Terms found: the download is offered on the public ratings page; no explicit
  license text is attached. Normal personal use assumed; nothing is shipped
  with the app or republished.
- Format found today: UTF-8, CRLF, semicolon-separated, **no header row**;
  trailing empty field allowed. Columns: `ICCF-ID; Country; Title; Name;
  Games; Rating; RD;` with Country in ICCF/ISO-3 codes (`CFR` is the Chess
  Federation of Russia label seen since 2024 — mapped to Russia), Title in
  ICCF's namespace (GM, SIM, IM, LGM, LIM, CCM, CCE — only GM/SIM/IM/LGM/LIM
  become correspondence title bits), Name = "Surname, Given" possibly with
  diacritics. Sample row: `241018;ITA;GM;Riccio, Eros;437;2640;120;`
- Note: no FIDE IDs, no birth years in this list.
- Kept: rating ≥ 1800 (unchanged from the shipped 2012 list).

## Deliberately not (re-)done

- USCF: the app has a 2013-era USCF list (old parser). No current free
  machine-readable full export was found on uschess.org — the member area is
  account-bound. Not implemented.
- IPS: the shipped list's source (chesstigers.de) no longer publishes such a
  list. Untouched.
