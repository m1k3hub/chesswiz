# Media playback and lesson cache fixes

Scope: the three confirmed findings from the playback review.

## Design

- `PlayInProcess` owns backend selection (mpv, then VLC). `PlayMedia` calls it directly and retains the existing external-audio fallback.
- WMV navigation targets remain node identities. Read every packet in ffprobe's JSON packet array and preserve opcode-2 checkpoint payloads in the decoder and share checkpoint-to-position construction between WMV and text-sidecar lessons. Do not substitute mainline plies for node IDs. Report an invalid lesson if a checkpoint is absent or cannot be applied; never advertise synchronized playback with an empty position table.
- Store a versioned input signature with every built lesson: existence, modification time, and size of both the media file and its adjacent `.txt`. Check it before both memory and disk cache hits. Reject older cache entries without this signature so lessons built by the defective decoder are rebuilt. Input creation, modification, and deletion invalidate cached results, including invalid in-memory lessons.

## Implementation and validation

1. Add regression tests through the real dispatcher, decoder, lesson builder, synchronization delegates, and disk-cache reads. Stub only external playback, ffprobe output, and board commands.
2. Remove the VLC-only dispatch gate.
3. Retain WMV checkpoints and share position construction with the text-sidecar path.
4. Add input signatures and cache validation.
5. Run the regression tests, full Tcl/app/C++ suites, build, and whitespace checks.

The WMV fallback retains the source stream's known incomplete event coverage. This change does not add support for encrypted streams or unresolved checkpoint variations. Metadata signatures cannot detect an in-place edit that preserves both file size and timestamp.

## Validation results

Implemented all three fixes. Added 14 regression tests in `tests/test_media_lessons.tcl`; the initial ten-test run reproduced nine failures before implementation. The completed suite passes all 14 tests.

- `make -j4`: passed.
- `make -C tests all`: passed (130 headless Tcl, 35 app-backed Tcl, both C++ executables; seven headless skips).
- `git diff --check`: passed.
- Real Biel round-08 fixture with the text export hidden: 148 decoded WMV records, 40 navigation timestamps, 88 positions, 24 annotation events.
- The same fixture through its text export: 99 navigation timestamps, 88 positions, 108 annotation events.

The real-fixture checks exercise decoding and lesson construction, not live audiovisual playback. Backend dispatch is covered with a playback stub; navigation tests use the real decoder, builder, synchronization state machine, and goto delegate with board commands stubbed at the application boundary.
