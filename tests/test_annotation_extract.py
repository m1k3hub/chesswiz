#!/usr/bin/env python3
"""Regression test for scripts/annotation_extract.py."""

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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


def _mock_server():
    """A /v1/systemone that answers prose/machine by a rule the regex disagrees
    with on purpose: CJK text is prose, a 'Time 0:05' clock is machine."""
    seen = {"requests": 0, "max_questions": 0}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            seen["requests"] += 1
            seen["max_questions"] = max(seen["max_questions"], len(body["questions"]))
            answers = {}
            for i, item in enumerate(body["state"]["comments"]):
                text = item["text"]
                prose = bool(re.search(r"[\u4e00-\u9fff]", text)) or "strong" in text
                if re.match(r"(?i)time\s", text):
                    prose = False
                answers[f"p{i}"] = {"type": "choice",
                                    "choice": "prose" if prose else "machine",
                                    "confidence": 0.9}
            payload = json.dumps({"model": "mock", "answers": answers}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, seen


CLS_PGN = """[Event "cls"]
[Result "1-0"]

1. e4 {\u4ea4\u6362\u540e\u767d\u65b9\u7a0d\u597d\u3002} e5 {Time 0:05} 2. Nf3 {A strong first move.} Nc6 1-0
"""


def main_classifier():
    server, seen = _mock_server()
    port = server.server_address[1]
    with tempfile.TemporaryDirectory() as d:
        pgn = os.path.join(d, "cls.pgn")
        out = os.path.join(d, "cls.jsonl")
        with open(pgn, "w", encoding="utf-8") as fh:
            fh.write(CLS_PGN)
        env = dict(os.environ,
                   SCIDB_ANNOTATIONS_CLASSIFIER="1",
                   SCIDB_ANNOTATIONS_URL=f"http://127.0.0.1:{port}/v1/systemone")
        subprocess.check_output(
            [sys.executable, SCRIPT, "--pgn", pgn, "--out", out, "--max-games", "10"],
            env=env)
        comments = [json.loads(l)["comment"] for l in open(out, encoding="utf-8")]

        check("classifier: CJK prose kept (regex would drop it)",
              "\u4ea4\u6362\u540e\u767d\u65b9\u7a0d\u597d\u3002" in comments, comments)
        check("classifier: a clock it calls machine is dropped (regex would keep it)",
              "Time 0:05" not in comments, comments)
        check("classifier: requests were batched, not one per comment",
              seen["requests"] == 1 and seen["max_questions"] >= 3, seen)

        # fallback: a dead endpoint -> is_prose, so the clock is kept and the
        # CJK prose is dropped, exactly the old behaviour
        out2 = os.path.join(d, "dead.jsonl")
        env2 = dict(env, SCIDB_ANNOTATIONS_URL="http://127.0.0.1:9/v1/systemone")
        subprocess.check_output(
            [sys.executable, SCRIPT, "--pgn", pgn, "--out", out2, "--max-games", "10"],
            env=env2)
        comments2 = [json.loads(l)["comment"] for l in open(out2, encoding="utf-8")]
        check("fallback: dead endpoint uses is_prose (clock kept)",
              "Time 0:05" in comments2, comments2)
        check("fallback: dead endpoint uses is_prose (CJK prose dropped)",
              all("\u4ea4\u6362" not in c for c in comments2), comments2)
    server.shutdown()
    return 1 if failures else 0


if __name__ == "__main__":
    rc = main()
    rc |= main_classifier()
    if failures == 0:
        print("\nall annotation-extract checks passed")
    sys.exit(rc)
