#!/usr/bin/env python3
"""Local speech-to-text for Scidb's voice assistant.

One short command, on your own machine, with no network call after the model
has been downloaded once:

    scripts/stt-transcribe.py clip.wav --model base.en   # model is chosen by the caller
    scripts/stt-transcribe.py --model base.en --language en clip.wav
    scripts/stt-transcribe.py --device cuda --compute float16 clip.wav

Prints the transcript on stdout (one line), nothing else; errors go to stderr
with a non-zero exit.  The transcription runs on CPU with int8 by default:
reliable on the machines Scidb targets (no cuDNN hunt, no bf16 requirement),
and a short spoken command transcribes in well under a second on a modern
CPU.  --device cuda --compute float16 uses a GPU when one is available.

The model is chosen by the caller (Scidb's voice settings or
SCIDB_AI_STT_MODEL); nothing is hard-coded here.  Backed by faster-whisper
(CTranslate2), which reads the usual Whisper checkpoints from the Hugging
Face hub on first use (tiny.en ~75 MB, base.en ~145 MB, small.en ~480 MB).

This script is one *engine* behind Scidb's pluggable speech-to-text: any
command that prints the transcript on stdout works as well (see
tcl/app-voice.tcl, ::application::voice::sttCommand).
"""

from __future__ import annotations

import argparse
import os
import sys


def load(model_name: str, device: str, compute: str):
    from faster_whisper import WhisperModel

    return WhisperModel(model_name, device=device, compute_type=compute)


def transcribe(model, path: str, language: str, beam: int) -> str:
    segments, _info = model.transcribe(
        path,
        language=language or None,
        beam_size=beam,
        # A single temperature: Whisper's fallback sweep (0.0, 0.2, ... 1.0)
        # re-decodes a whole clip whenever the first pass looks unlikely, which
        # is exactly what a hard word or a synthetic voice triggers -- observed
        # 12 s instead of 1 s on one clip. One pass keeps latency predictable.
        temperature=0.0,
        vad_filter=True,           # trims silence, helps short commands
        condition_on_previous_text=False,
        without_timestamps=True,   # no timecodes to generate
    )
    return " ".join(segment.text.strip() for segment in segments).strip()


def serve(model, language: str, beam: int) -> int:
    """Read one audio path per line on stdin, print one transcript per line.

    The model stays loaded, which is what makes a spoken command feel instant:
    loading it costs about two seconds, transcribing a sentence a fraction of
    one.  A failed file prints an empty line and explains itself on stderr, so
    the line protocol never desynchronises.
    """
    for line in sys.stdin:
        path = line.strip()
        if not path:
            continue
        if path in ("\q", "quit", "exit"):
            break
        try:
            print(transcribe(model, path, language, beam), flush=True)
        except Exception as error:                 # noqa: BLE001 - keep serving
            print("", flush=True)
            print(f"transcription failed for {path}: {error}", file=sys.stderr, flush=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Transcribe a WAV file locally.")
    parser.add_argument("audio", nargs="?", help="WAV file (16 kHz mono is ideal)")
    parser.add_argument("--serve", action="store_true",
                        help="read audio paths on stdin, print transcripts on stdout")
    parser.add_argument("--model", default=os.environ.get("SCIDB_AI_STT_MODEL", ""),
                        help="Whisper model name (default: SCIDB_AI_STT_MODEL)")
    parser.add_argument("--language", default="", help="language code, e.g. en (default: detect)")
    parser.add_argument("--device", default="cpu", help="cpu or cuda (default cpu)")
    parser.add_argument("--compute", default="", help="int8, int8_float16, float16, float32 (default: by device)")
    parser.add_argument("--beam", type=int, default=1, help="beam size (1 = fastest, default)")
    args = parser.parse_args(argv)

    if not args.model:
        print("no model chosen: pass --model NAME or set SCIDB_AI_STT_MODEL", file=sys.stderr)
        return 2

    try:
        import faster_whisper  # noqa: F401
    except ImportError:
        print("faster-whisper is not installed (pip install faster-whisper)", file=sys.stderr)
        return 2

    compute = args.compute or ("int8" if args.device == "cpu" else "float16")

    try:
        model = load(args.model, args.device, compute)
    except Exception as error:                     # noqa: BLE001 - report and exit
        print(f"cannot load model {args.model}: {error}", file=sys.stderr)
        return 1

    if args.serve:
        return serve(model, args.language, args.beam)

    if not args.audio:
        print("no audio file given (or --serve)", file=sys.stderr)
        return 2

    try:
        text = transcribe(model, args.audio, args.language, args.beam)
    except Exception as error:                     # noqa: BLE001 - report and exit
        print(f"transcription failed: {error}", file=sys.stderr)
        return 1

    print(text, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
