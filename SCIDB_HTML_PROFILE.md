# SCIDB HTML Profile

The HTML contract shared by all three paths of scidb's native HTML
support (read, render, write). Everything inside scidb — the Tkhtml
report viewer, the exporter, future consumers — only ever sees HTML
that conforms to this profile. Hostile or foreign input (ChessBase
guiding texts, PGN comment markup, arbitrary web pages) is normalized
once, at the boundary.

Implemented by `src/html/html_sanitize.h` (intake) and
`src/db/db_html_writer.cpp` (publish); documented by this file.

## Document shape

- **Fragment** by default: no `<html>/<head>/<body>` wrapper — the
  profile is embeddable. `<title>` content is extracted, not emitted.
  The *publish* path (HtmlWriter) wraps the fragment in a full
  document (doctype, `<meta charset="utf-8">`, embedded CSS).
- **Encoding**: UTF-8 everywhere. Intake normalizes BOMs, UTF-16 and
  Windows-1252 (with a `<meta charset>` prescan) before anything else.
- **Escaping**: all text is entity-decoded then re-escaped
  (`&amp; &lt; &gt;` and `&quot;` in attributes). Attribute values are
  always double-quoted. Output is parseable regardless of input.

## Elements

Whitelisted tags only:

| class | tags |
|---|---|
| unwrapped | `html head body` (children kept), `title` (captured) |
| removed with content | `script style iframe object embed applet frameset frame noscript form select button svg math template textarea` |
| dropped (empty) | `meta link base input col colgroup` |
| blocks | `p div br hr h1–h6 blockquote pre center address` |
| inline | `b i u s em strong span font sub sup small big tt code cite q kbd samp var dfn abbr acronym del ins mark` |
| lists | `ul ol li dl dt dd` (`dir`/`menu` kept as-is) |
| tables | `table thead tbody tfoot tr td th caption` |
| links/media | `a img` |

Unknown tags are **unwrapped** (dropped, children kept) — Word/ChessBase
junk like `<o:p>` vanishes without losing text.

## Attributes

Per-tag whitelists (see `TagPolicy` in html_sanitize.h): structural
attributes only — `align`, `colspan`, `rowspan`, `src`, `href`,
`alt`, `width`, `height`, `bgcolor`, `color`, `size`, `face`,
`border`, `cellspacing`, `cellpadding`, `valign`, `start`, `type`,
`value`, `title`, `name`. Everything else — including every `on*`
event handler — is dropped and counted (`Report::droppedAttrs`).

URI attributes (`href`, `src`) are entity-decoded and
whitespace/C0-trimmed **before** classification (so `&#106;avascript:`
and `" javascript:"` are caught), then checked against the scheme
allowlist: `http https mailto ftp file scidb-game scidb-media`.
Everything else (`javascript:`, `vbscript:`, `data:`, …) is dropped.

## Internal URI schemes

- `scidb-game:ARGS` — a game anchor. `ARGS` is the CBLink argument
  list (`WhiteLast,WhiteFirst,BlackLast,BlackFirst,Event,Site,Year,
  Round,…`), matched to games by `::scidb::db::gameAnchor`.
- `scidb-media:PATH` — a media file of the release, played by the
  media panel.
- `scidb-open:FILE` — a cross-database link (ChessBase
  `tag_extertext`/`tag_extern gamelist`); currently reported as
  not-followed.

## Structural repair

- void elements (`br hr img …`) never enter the open-element stack
- implicit closing: `p`, `li`, `dt/dd`, `td/th/tr`, `thead/tbody/
  tfoot`, `h1–h6`, `a` close their predecessors (HTML5-flavoured,
  simplified)
- end tags close down to **and including** the matched element; the
  scan is bounded (64 levels); unmatched end tags are dropped
- nesting cap: 64 open elements (both kept and unwrapped tags count);
  beyond the cap tags are dropped and content flows
- raw-text elements (`script`, `style`, `textarea`) swallow content to
  the matching end tag — the name must be followed by a delimiter, so
  `</scriptx>` does not terminate a block
- caps: 64 attributes per tag, 64-char attribute names, 4 KiB
  attribute values, 32-char tag names — bounded output for adversarial
  input

## ChessBase adapter (read path)

Applied before sanitization (`html_cb_adapter.h`):

- `href="javascript:CBLink(tag_game,…)"` → `<a href="scidb-game:…">`
- `href="[CBLink(kind,…)]"` (bracket form) → same, per kind
- bare `CBLink(tag_stream|tag_video|tag_audio|tag_picture,FILE,…)`
  → `<a href="scidb-media:RESOLVED">BASENAME</a>` (resolved through
  the release media folders) or plain text if unresolved
- `tag_extertext` / `tag_extern gamelist` → `scidb-open:FILE`
- unknown kinds and incomplete constructs stay visible as bracketed
  text — never lost, never executed

## Classification completeness

Every reference lands in `Report::media` or `Report::anchors` with a
status: `kept / resolved / dropped / unresolved / external / game /
media`. Unresolved references stay visible in the output (broken-image
placeholder, status-bar count) — the pipeline never swallows a
reference silently.

## Guarantees

1. no active content survives (see tables above)
2. output is always well-formed, escaped, UTF-8
3. all loops bounded; no hangs; bounded memory amplification
4. never throws (try/catch boundary; degrade to escaped text)
5. every reference classified

These are enforced by `src/test_html_core.cpp` (478 checks) and
regression-tested on the real CBM168 corpus.