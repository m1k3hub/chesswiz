# Player data sources — steps 4–5

Downloads are explicit user actions only. Opening the app or source dialog does
not fetch lists. Nothing is bundled, mirrored or published by this feature.
USCF bulk acquisition and profile scraping are out of scope.

## DWZ (Deutscher Schachbund)

Official page: https://www.schachbund.de/download-dwz-daten.html
Download: https://www.schachbund.de/download-dwz-daten.html?file=files/wertungsportal/downloads/export/csv/LV-0-csv.zip
Terms: https://www.schachbund.de/impressum.html and README.txt in that archive.
The imprint states: “Downloads und Kopien dieser Seite sind nur für den privaten,
nicht kommerziellen Gebrauch gestattet.” The archive states:
“Eine Veroeffentlichung dieser Daten ist nur nach vorheriger Absprache mit dem
zustaendigen DWZ-Referenten erlaubt!” Private noncommercial downloads only;
publication requires prior agreement. This is not an open licence.

Published daily at 04:15 (timezone unspecified). Investigation on 2026-11-14
observed 3,137,713 ZIP bytes; this is a dated observation, not a fixed size.
Read only spieler.csv: comma CSV, quoted fields, Windows-1252, named columns.
The CP850 DOS archive is not supported by this workflow. DWZ is the rating;
Index is its separate evaluation index and is not a rating. Source ID,
ZPS/Mitgliedsnummer and FIDE-ID are distinct identifiers.
The installed format uses the membership pair ZPS/Mitgliedsnummer, retaining
separate memberships; it does not claim this pair is a unique person ID.
Retention: DWZ >= 1800, or FIDE ID, or FIDE title.

## ECF (English Chess Federation)

CSV: https://rating.englishchess.org.uk/api/rating-list/csv
API/access terms: https://rating.englishchess.org.uk/help/api
Privacy: https://www.englishchess.org.uk/ecf-privacy-notice/
The API documentation says: “It also allows the download of complete ratings
lists equivalent to those in the previous system.” Processing is limited to ten
minutes daily per class-C network, reset at midnight GMT, subject to change.
This is a server-processing budget, not a transfer-time or per-user quota.
No polling or automatic retry is appropriate. Public API access establishes no
open-data or commercial redistribution licence.

UTF-8 comma CSV with named columns. ECF_code is distinct from member_no and
FIDE_no. Use revised_standard, with original_standard fallback, on the modern
four-digit scale. Rapid, blitz and online ratings do not replace standard or
FIDE ratings. No birth-year column exists. Retention: standard >= 1600, or
FIDE ID, or FIDE title. Original ratings are monthly; revisions are nightly.
Effective rating period is distinct from acquisition time.

Exact current CSV size remains unverified: the investigation received no
Content-Length; a fresh HEAD on 2026-11-14 returned HTTP 403. The approximately
4 Mb figure in API help dates to October 2022 and is not a current measurement.
No complete list was downloaded to measure it.

## ICCF (international correspondence ratings)

Official entry point: https://www.iccf.com/ratings
Privacy notice: https://iccf.com/message?message=1490
Rules: https://webfiles.iccf.com/rules/2026/ICCF%20Rules%20-%20update%20for%202026.pdf
The public page offers Download as CSV, period selection and filters controlling
the displayed/downloaded list. Save that export and choose it locally in Chesswiz.
There is no verified stable CSV URL. Manual import is the supported workflow;
HTTP automation is not inherently impossible.

The privacy notice says downloaded rating lists “may be made available by third
party publishers.” Its separate permission for commercial game databases must
not be extended to all rating data. Preserve source attribution; no named open
licence has been established.

Quarterly periods; published two weeks before validity using results reported
at least one month earlier (2026 Rules §1.4(5)). Visible columns are Place,
ICCF ID, Country, Title, Name, Games, Rating, RD. RD is uncertainty, never sex.
No FIDE ID or birth year is documented. Supported import assumption: UTF-8,
semicolon-separated, no header, optional place, trailing empty field:
ICCF-ID;Country;Title;Name;Games;Rating;RD;
The existing tab-separated variant is also accepted. These wire assumptions
remain unverified against a fresh export: direct access returned HTTP 403 on
2026-11-14. CSV bytes are unknown; HTML size is not CSV size. The official page
shows 4,203 entries for 2026-10-01 through 2026-12-31, not all registered players.
Retention: rating >= 1800 or supported correspondence title. Correspondence
titles must stay separate from OTB titles; never infer sex from them.

## Implementation and maintenance

Current CSV files go through convertRatingList → installed format →
parseInstalledRatingList. The legacy parseDwzRating/parseEcfRating/parseIccfRating
paths read the older shipped fixed-width lists, not these CSV exports.
Reference-list linking must not change stored database names. Name fixes belong
only to explicitly invoked maintenance with a confirmed preview and ordinary
explicit Save. Exact parsing, identities, stale-preview checks and execution
are deterministic code; no Jev or other model is appropriate for them.

### Installation and replacement policy

Conversion completes before either cache file is replaced. Cache and provenance
files are backed up for rollback on a filesystem failure. Activation is at the
next application start, before database pointers exist; there is deliberately
no live additive reload. The active dictionary stays unchanged on successful
staging as well as failures. Startup uses the replacement instead of the shipped
national list, so stale records from the previous installed version are absent.
No database names or dirty flags change during install. Restart is stated in the UI.
Metadata records source URL, schema, input bytes, acquisition time and an explicit
unknown effective period; acquisition date must never masquerade as rating date.
Malformed CSV/ICCF rows reject the whole import. A complete-record truncation is
not detectable without a source-supplied count/checksum; no completeness guarantee
is made. RD and unsupported CCM/CCE title bits are not retained in the dictionary.
