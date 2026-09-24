#!/usr/bin/env python3
"""Regression test for scripts/annotation_extract.py."""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "scripts", "annotation_extract.py")

PGN = """[Event "a"]
[Source "TestBook"]
[Result "1-0"]

1. e4 {A strong first move.} $14 e5 {Symmetric.} 2. Nf3 $36 Nc6 1-0

[Event "b"]
[Result "1/2-1/2"]

1. d4 { [%clk 0:05:00] } d5 { [%clk 0:04:59] } 1/2-1/2

[Event "c"]
[Result "1-0"]

1. e4 { [%clk [Source "X"] 1:07:58] } e5 {Real note.} 1-0
"""

failures = 0


def check(name, cond, detail=""):
    global failures
    if cond:
        print(f"PASS: {name}")
    else:
        failures += 1
        print(f"FAIL: {name} {detail}")


def main():
    with tempfile.TemporaryDirectory() as d:
        pgn = os.path.join(d, "ann.pgn")
        out = os.path.join(d, "ann.jsonl")
        with open(pgn, "w") as fh:
            fh.write(PGN)

        summary = json.loads(subprocess.check_output(
            [sys.executable, SCRIPT, "--pgn", pgn, "--out", out, "--max-games", "10"]))

        records = [json.loads(l) for l in open(out)]

        check("four annotatable records", summary["records"] == 4, summary)
        check("clock-only comments dropped", summary["with_comment"] == 3, summary)
        check("NAGs captured", summary["with_nag"] == 2, summary)

        first = records[0]
        check("prose comment kept", first["comment"] == "A strong first move.", first["comment"])
        check("NAG on first move", first["nags"] == [14], first["nags"])
        check("source tag used", first["source"] == "TestBook", first["source"])
        check("fen present", "e4" in first["fen"] or first["fen"].startswith("rnbqkbnr"))
        check("key is a sha1 hex", len(first["key"]) == 40)

        nag_only = [r for r in records if r["nags"] == [36]]
        check("NAG-only record has empty comment",
              len(nag_only) == 1 and nag_only[0]["comment"] == "")

        check("no clock directives anywhere",
              all("%clk" not in r["comment"] and "1:07:58" not in r["comment"] for r in records))
        check("nested-bracket directive fully stripped",
              any(r["comment"] == "Real note." for r in records))

    if failures:
        print(f"\n{failures} annotation-extract check(s) failed")
        return 1
    print("\nall annotation-extract checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
