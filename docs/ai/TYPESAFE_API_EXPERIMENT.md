# TypeSafe API experiment — hosted Jev vs local plumb

**Status:** experiment complete; findings below are implemented or proposed.
**Method:** the labelled calibration battery that
`scripts/calibrate-systemone.tcl` uses (`tests/fixtures/systemone-battery.tcl`),
run through two backends:

- **local** `plumb-4b-v5` (llama.cpp on the GPU, `127.0.0.1:11435`)
- **hosted** TypeSafe `jev-latest` (`https://api.typesafe.ai/v1/systemone`,
  key from `TYPESAFE_API_KEY`, resolves to model `jev-1.13.0`)

Reproduce:

```sh
export TYPESAFE_API_KEY=...
xvfb-run -a src/tkscidb-beta scripts/calibrate-systemone.tcl \
    --backend typesafe --features comment_kind,event_type,language \
    --target 0.9 --out tcl/ai-thresholds.tsv
```

## Results (threshold / coverage / accuracy at target 0.9)

| feature | local plumb-4b-v5 | hosted Jev (jev-1.13.0) |
|---|---|---|
| comment_kind | 0.85 / 0.57 / 0.941 | **0.0 / 1.00 / 0.967** |
| language     | 0.75 / 0.84 / 0.941 | **0.0 / 1.00 / 1.000** |
| event_type (rule-residual) | 0.60 / 0.35 / 0.833 | 0.85 / 0.59 / 0.800 |

Both the HTTP script and the Tcl client agree; the Tcl run wrote the file.

## Findings

1. **Hosted Jev is materially better on the label gates.** It labels
   `language` perfectly and `comment_kind` at full coverage, where plumb only
   answers ~57–84 % of the battery to reach the target. The win is largest
   exactly where the model must *interpret* text rather than match a keyword.
2. **`event_type` was never a classifier problem.** An earlier version of
   this battery scored the classifier on `TimeControl` strings; plumb read
   each as "classical" (high confidence) and failed. But production never
   sends those: `::ai::event::Rule` resolves every well-formed TimeControl
   and every category keyword deterministically, and only the residual
   reaches the classifier. The battery now contains **only rule-residual
   cases** (a test enforces it). On those, **both backends score 10/17
   (0.588)** and neither meets the 0.9 target:
   - both answer the genuinely ambiguous names ("Monday League", "Weekend
     Swiss", …) as `unclear` — correct, and confidently so for Jev;
   - **both refuse to name even famous events** ("Titled Tuesday", "Tata
     Steel Masters", "World Championship") and answer `unclear` — Jev
     confidently (`0.95`), plumb with low confidence.
   Inferring a time control from an event name alone is world-knowledge
   recall, which the skill explicitly warns against. `event_type`'s honest
   answer for the residual is `unclear`; the classifier adds little and
   should not gate.
3. **A latent HTTPS bug blocked all cloud backends.** `::ai::provider`
   registered `::tls::socket` with no SNI; the async handshake `http` uses
   then fails ("failed to use socket") against SNI-requiring hosts
   (`api.typesafe.ai`, even `example.com`). Fixed during the experiment.

## Changes

Implemented:

1. **SNI-aware HTTPS handler** (`tcl/ai-provider.tcl`,
   `::ai::provider::tlsSocket`; unit test `provider-tls-sni`). Fixes every
   hosted LLM/classifier path.
2. **First-class `typesafe` backend** (`tcl/ai-systemone.tcl`):
   `api.typesafe.ai`, model `jev-latest`, key `TYPESAFE_API_KEY`;
   env-overridable, selectable in Choose Model, **not** auto-probed (cloud
   stays a deliberate choice).
3. **Per-backend thresholds** (`tcl/ai-thresholds.tsv` has `plumb` and
   `typesafe` rows). `::ai::systemone::threshold` already keys on the
   resolved backend.
4. **Calibration battery scoped to the classifier's real input.** The
   `event_type` battery stores tags, the calibrator builds the production
   state (`::ai::calibrate::StateFor`), and a test asserts every case is
   rule-residual, so the battery cannot drift back to rule-handled inputs.
5. **A failed calibration drops its threshold** (`::ai::calibrate::drop`),
   instead of leaving a stale value from an earlier battery.

Proposed:

6. **Make `event_type` rule-only — implemented.** Finding 2 led to dropping
   the classifier from `ai-event` entirely: the rule decides the informative
   cases, the residual is `unclear`, and the removed gate was a
   world-knowledge guess. Tests: `systemone-event-rule-only` asserts the
   profiler makes **no** classifier request.
7. **Recommend the `typesafe` row** in the chooser when `TYPESAFE_API_KEY`
   is set — recommendation only, never an automatic switch.

## Caveats

- Small in-tree battery; treat numbers as directional. The `recommend` rule
  maximises coverage subject to the accuracy target, so a feature accurate
  even at low confidence gets threshold `0.0` (comment_kind, language on
  Jev), which removes the confidence dial for that feature.
- Accuracy is measured over *answered* cases; abstention is not an error.
  For a feature whose fallback is a label (`event_type` → `unclear`), a
  coverage miss still costs a wrong bucket, which the accuracy figure does
  not show.
- Calibrate on the user's own data before trusting a gate (research §5.6).
- **Firewall unchanged:** these gates label comments, games and languages.
  Move quality, evaluations, tablebase verdicts and opening identity remain
  with Stockfish / the fact layer / the ECO table.
