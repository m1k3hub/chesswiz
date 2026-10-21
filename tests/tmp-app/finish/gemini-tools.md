# Gemini tools — Linux verification

Branch `fix/gemini-tools`, worktree `build/wt-gemini-tools`, based on master `8f868a1691b2b2cd0630deef9da9fe7e597fc278`. Changes are committed on this branch only; no merge, stash, reset, checkout or restore.

Evidence directory: `tests/tmp-app/finish/gemini-tools-evidence/` (also copied to the main checkout for handoff).

## Results and changes

**A — reproduced and fixed.** A real `gemini-3.8-flash` request returned a signed `current_game` tool call. Removing `extra_content` in the same way as the old adapter produced HTTP 400. The captured response body is `gemini-400.json` in the evidence directory:

```json
[{"error":{"code":400,"message":"Function call is missing a thought_signature in functionCall parts. This is required for tools to work correctly, and missing thought_signature may lead to degraded model performance. Additional data, function call `default_api:current_game` , position 2. Please refer to https://ai.google.dev/gemini-api/docs/thought-signatures for more details.","status":"INVALID_ARGUMENT"}}]
```

`openaiReply` now retains each call's opaque `extra_content` JSON span. `openaiMessages` echoes it on Gemini assistant tool calls. It remains attached to the individual call across turns; other OpenAI-compatible providers do not receive Google's extension. Tool result IDs, string content and empty `{}` arguments are verified on the wire. No Gemini schema keyword filtering or content placeholder change was needed.

Gemini also wraps some HTTP errors in an array. The adapter now reads those messages and appends the response body to the application's Assistant error log (`SCIDB_ERROR_LOG`, or its normal profile location). Credential values are redacted before logging/display; bodies are bounded to 8192 characters. Plain-text error responses retain their details too.

**B — verified and strengthened.** HTTP 503/429 and HTTP timeouts already carried the retryable `down` flag. Tests now exercise these paths against stub transports, including a server that accepts a connection and never answers. Immediate cloud transport failures now also carry `down=1`. Assistant attempts have a 30-second ceiling, preserve shorter caller deadlines, and restore the prior timeout when finished. Both configured backups are tried in order. Backup status uses the visible info tag; the final unavailable message shows a short status while the detailed body stays in the log. No Ollama calls were made.

**C — Linux analysis works.** The existing `start_engine` path produced real Stockfish analysis without a startup implementation change: active=1 and populated PV lines with depth and moves. The regression test checks lines, not just the active flag. The final GUI run uses two Stockfish threads and 64 MB hash and shows four lines.

The laptop's Play request exposed a separate missing capability: no Assistant tool could open Play Against Engine. Added `open_play_engine`, reusing the existing dialog and selecting the user's requested colour. Opening it does not start a game; Start remains the user's action. Existing active games retain their settings. The tool is registered with argument validation, a menu hint, and the dialog boundary used by multi-step plans. The action coverage count is now 88.

A recording run also exposed the model evaluating the side currently on move instead of the last move's alternatives. `current_game` now includes the native last-move SAN and predecessor FEN; the system prompt directs `engine_evaluate` to that position. A regression checks the predecessor board/side/rights/en-passant fields and unchanged current board, navigation key and modified flag. This uses the existing native `movefen` API, including its half-move-clock normalization.

## Validation

Final requested suite result: 31 files, zero failures; 162 Assistant assertions passed and five CLI socket assertions skipped. All 17 AI files passed (the opt-in live file skips in the ordinary run).

- All `test_app_assistant*.tcl` and `test_ai*.tcl` files were run in fresh profiles under Xvfb 1920×1080 and Openbox. Final per-file results and logs are in the evidence directory’s `suites/`. `python-chess` was installed in an isolated ignored venv for the annotation/precedent suites.
- The provider suite passes all 51 tests, including the recorded Gemini signature replay, error-body redaction, real HTTP timeout, and OpenAI/Fireworks/Qwen compatibility assertions.
- `test_app_actions_all.tcl`: 97 passed, covering all 88 registered Assistant actions.
- The five `haveServer` CLI tests skip because the normal app-test runner uses `--single-process` and creates no single-instance socket. The live opt-in test skips in the ordinary suite.
- `test_ai_gemini_live.tcl` passes a real tool round-trip on both `gemini-3-flash-preview` and `gemini-3.5-flash`, using the production Tcl async HTTPS adapter and echoed signature.

The initial 3.8 reproduction was real. Subsequent 3.8 validation encountered HTTP 503 and then HTTP 429: this key's free-tier `gemini-3.8-flash` quota is 20 requests/day, with a reported retry time around ten hours. A successful post-fix 3.8 live round-trip is therefore **not claimed**. The retained GUI session keeps 3.8 as primary and visibly falls back to Gemini 3.5 Flash; its three actions are real, not replayed tool results.

Live opt-in reproduction (does not print the key):

```bash
set -a; . ~/.config/private-secrets.env; set +a
export GEMINI_API_KEY="$GOOGLE_API_KEY"
SCIDB_TEST_GEMINI_LIVE=1 SCIDB_TEST_GEMINI_MODEL=gemini-3.5-flash \
  DISPLAY=:619 ../../src/tkchesswiz tests/test_ai_gemini_live.tcl
```

Omit `SCIDB_TEST_GEMINI_MODEL` to test the default `gemini-3.8-flash` after quota recovery. `reproduce-missing-signature.py` is the minimized live failure harness; the replay regression is `aipc-gemini-signature-roundtrip` in `tests/test_ai_provider_cloud.tcl`. Its recorded response is committed as `tests/fixtures/gemini-tool-call.json`.

## Recording and isolation

The retained capture and matching sidecar are in `tests/tmp-app/promo/captures/linux/`; the retained file is `20261021-1703-linux-gemini-tools-verified.mp4` (108.633 s, 8,026,288 bytes). All three final requests succeeded: alternatives in 15.610 s, engine startup in 11.039 s with four native analysis lines, and Play dialog in 8.530 s with `color=black`, `active=0`. The board stayed at the TWIC position during the final read-only alternatives request.

The sidecar records the build/source identity, video properties, timing and final state checks. The recorder started before the app, used software libx264 ultrafast CRF 18 at 1920×1080/30 fps, and stopped with SIGINT.

The GUI starts from readonly TWIC Carlsen–Ding, Sinquefield Cup tiebreak, 2019.08.29, at 3...a6. Requests are typed progressively into the real Assistant entry and submitted with Return. The retained run asks for last-move alternatives, starts engine analysis, and opens Play Against Engine as Black. Native engine lines and dialog colour are checked independently of the model's prose. No database was saved.

Capture-only presentation: tool-detail text is elided, the startup log window is kept off screen, the cloud notice is acknowledged in the isolated profile, tips are disabled, and the engine startup label says “Starting Stockfish...” instead of exposing its executable path. These affect presentation only; model requests, tool execution and pass/fail checks are unchanged. Earlier clips that showed paths in the startup log were deleted according to CAPTURE-RULES.md. The retained clip is visually reviewed with contact sheets and full-size outcome frames.

The existing main-tree binary (`../../src/tkchesswiz`, base 8f868a1) ran the newly generated worktree Tcl application. No C++ change or rebuild was required. Fresh tester profiles and owned displays/processes were used. No private database, OS credential store, local model, GPU, or Windows application was accessed.

Jev: required reading and live TypeSafe docs were consulted. No new Jev call was appropriate: metadata replay, HTTP failover, enum validation and dialog execution are exact code operations, and chess position/evaluation facts come from native chess code and Stockfish. Classifier and shadow calls were disabled for live validation; deterministic tests use stubs.
