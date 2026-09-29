# Plain-Language Search — plan and design

**Status:** implemented. The code is in `tcl/ai-search.tcl`, `tcl/app-database-search-nl.tcl`
and the assistant's `search_games` tool; the tests are in `tests/test_app_nlsearch.tcl`.
**Supersedes:** `LLM_REACH_PLAN.md` Task 2 (C4). It extends that task with position
patterns through CQL.
**Companions:** `SYSTEM_ONE_FEATURES.md` §3a (primitives, CQL), `AI_PRODUCTS_PLAN.md` §0
(the firewall).

## 1. Goal

A request such as *"Carlsen's losses as Black in the Najdorf since 2015"* or *"smothered
mates in games rated 2500+"* becomes an **editable, reviewable search**. The user sees it
before it runs, and it runs through the same search path as the Advanced Search dialog.

## 2. The rule that shapes everything

**No model ever writes query text, and no model ever writes CQL.** A model may only
fill fixed, typed fields (the existing `search_games` schema) and choose a **pattern id**
from a vetted library. The application:

- validates every field (`CheckArgs search_games`)
- builds the query (`BuildQuery`)
- owns every CQL template

A wrong interpretation therefore costs a wrong filter the user can see and edit. It can
never cost a malformed or runaway query, and it never produces a chess claim.

## 3. Pipeline

```
request ──► extract     (deterministic: years, result, colour, ECO, Elo, pattern keywords)
        ├─► model       (optional: fills the fields + chooses a pattern id; JSON only)
        └─► classifier  (optional: `choice` over pattern ids + none, when nothing else picked one)
                │
                ▼
          merge + validate   (a valid model answer > the words > the classifier, per field and for the pattern)
                │
                ▼
          "Understood as"    (editable form; each field shows where it came from)
                │  user presses Search
                ▼
          BuildQuery ──► AND{ header terms …, cql <template> }   (CQL last: decoded only
                │                                               for games the header terms keep)
                ▼
          ::scidb::view::search <base> <variant> 0 …           (the main game list)
```

| Stage | Owner | Why it is safe |
|---|---|---|
| extract | regex rules | exact, reproducible, and always runs |
| model | `::ai::provider::completeAsync` | JSON fields only; each is re-validated; an unknown pattern id is dropped |
| classifier | `::ai::decide` (`choice`, gate 0.6) | picks from the library only, and only when neither the words nor the model named a pattern; below the gate, nothing is picked |
| query | `BuildQuery` + `cql` term | the application builds every term |
| run | `::scidb::view::search` | nothing runs without the user pressing Search |

Without a model or a classifier, the extraction alone still produces a usable,
editable interpretation. A valid model answer beats the words: the words are exact but
shallow ("knight mates" contains the checkmate alias "mates", while the model can tell
it is a smothered mate). Criteria that need a player lose their meaning without one:
"draws" becomes `1/2-1/2`, and a bare win, loss or colour is dropped.

## 4. The pattern library (`::ai::search::Patterns`)

Every template is checked against purpose-built games in `tests/test_app_nlsearch.tcl`.
A template that fails to parse at run time is dropped, never sent.

| id | Meaning | CQL |
|---|---|---|
| `checkmate` | the game ends in checkmate | `(match (position :terminal :mate))` |
| `smothered_mate` | a knight mates a king boxed in by its own pieces | `(match (position :flipcolor :attackcount k [A.] 0 :btm :mate))` |
| `stalemate` | the game ends in stalemate | `(match (position :terminal :stalemate))` |
| `en_passant` | an en-passant capture | `(match (position :enpassant))` |
| `underpromotion` | a pawn promotes to a rook, bishop or knight | `(match (position :promote [RBNrbn][a-h1,a-h8]))` |
| `double_check` | a double check | `(match (position :doublecheck))` |
| `opposite_castling` | the kings on opposite wings | `(match (position :flipcolor Ka-c1 kg-h8))` |
| `rook_endgame` | a rook ending (rooks and pawns only) | `(match (position :piececount [QBNqbn] 0 :piececount R 1 8 :piececount r 1 8))` |
| `pawn_endgame` | a pawn ending | `(match (position :piececount [QRBNqrbn] 0 :piececount [Pp] 1 16))` |

**Adding a pattern:** add a row, add a fixture game that has it and one that doesn't,
and add aliases for the keyword stage.

## 5. Surfaces

1. **Database menu → "Plain-Language Search…"**: an entry box, the editable
   "Understood as" form, Search, and Show All.
2. **Assistant `search_games`** gains a `pattern` field (an enum of the library ids). The
   assistant, voice input included, can then say "find smothered mates in Carlsen's games",
   and `show_search` puts the result in the game list.
3. **`::ai::search::interpret` / `::ai::search::query`**: the API for later callers, such
   as the classifier pre-router and a toolbar field.

## 6. Out of scope, and next steps

- **Free CQL written by a model:** never. A power user can type CQL in a later "CQL"
  field, which the parser validates.
- **More patterns** (isolated queen's pawn, Greek gift, opposite-coloured bishops) need
  fixture games first. The **square-colour designators** `L` (light) and `D` (dark) are
  implemented (`[L?]`, `[D1]`, `BL?`, `b[D?]`), and so are the spatial **flip** and
  **shift** transformations, so colour-of-square and "anywhere on the board, reflected
  or translated" patterns need no manual enumeration, and the accumulator
  extension (`:accumulate` / `:sumrange` / `:reset`) is implemented. Still
  `Not_Implemented`: the sequence-relative keywords (`:preceding` /
  `:following` / `:inside` / `:endmost`), `:pretransformmatchcount`,
  `:language`, and the relation-list keywords. The tagging keywords
  (`:forany` / `:tagmatch` / `$tag`) are implemented.
- **Progress and cancel** for CQL searches over very large databases: the view search
  is synchronous today.
- **Learning from edits:** record the user's corrections to the form (Wave 4 threshold
  autotune).
