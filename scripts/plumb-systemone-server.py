#!/usr/bin/env python3
"""A TypeSafe-style /v1/systemone server for Plumb-4B on llama.cpp.

Plumb-4B (huggingface.co/crh225/plumb-4b, Apache-2.0) is an open, one-pass
typed-decision model in the JevK5 format: give it a state and typed questions
(choice / noul / score) and it returns a calibrated probability per option,
read from the option letters' next-token logits.  The full bf16 runtime needs
about 10 GB of GPU memory, which does not fit an 8 GB card; the official GGUF
builds (huggingface.co/crh225/plumb-4b-GGUF) run in llama.cpp on almost any
GPU or a CPU.  This script is the missing piece between the two: it wraps a
running llama-server (Q8_0 ~4.5 GB, Q4_K_M 2.7 GB) in the /v1/systemone
wire contract that Scidb's System One client (tcl/ai-systemone.tcl) and the
JevBench typesafe adapter speak.

    llama-server -m plumb-4b-v5-Q8_0.gguf -c 8192 -ngl 99 --port 8080
    scripts/plumb-systemone-server.py --port 8090

    curl -s localhost:8090/v1/systemone -d '{
      "state": "I was billed twice, please refund",
      "questions": {"refund": {"type": "noul",
                                "instructions": "Asks for money back?"}}}'

The readout (letters, temperatures, knockout passes for more than 16 options)
is jevk5's (github.com/allebee/jevk5, Apache-2.0, standard library only for
this path); this file only adds the HTTP shape, modelled on jevk5's server.
The calibration temperature of Plumb-4B v5 is 2.07 (its model card).
"""

from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def normalized(question: dict) -> dict:
    if question.get("type") not in ("noul", "choice", "score"):
        raise ValueError(f"unknown question type {question.get('type')!r}")
    if "instructions" not in question:
        raise ValueError("question is missing instructions")
    criteria = question.get("criteria")
    if question["type"] == "choice":
        if isinstance(criteria, list):
            criteria = dict.fromkeys(criteria)
        if not isinstance(criteria, dict) or len(criteria) < 2:
            raise ValueError("choice criteria must name at least two options")
    if question["type"] == "score" and (not isinstance(criteria, list) or len(criteria) < 2):
        raise ValueError("score criteria must list at least two levels")
    return {**question, "criteria": criteria}


def make_handler(read_model, name):
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def _send(self, status: int, payload: dict) -> None:
            data = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:
            if self.path.rstrip("/") == "/health":
                self._send(200, {"ok": True, "model": name})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self) -> None:
            if self.path.rstrip("/") != "/v1/systemone":
                self._send(404, {"error": "not found"})
                return
            started = time.perf_counter()
            try:
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                with lock:
                    answers = {
                        qid: read_model(state=body["state"], question=normalized(q))
                        for qid, q in body["questions"].items()
                    }
            except (ValueError, KeyError, TypeError) as error:
                self._send(400, {"error": str(error)})
                return
            tokens = sum(a.pop("input_tokens", 0) for a in answers.values())
            self._send(
                200,
                {
                    "model": body.get("model") or name,
                    "answers": answers,
                    "usage": {"input_tokens": tokens, "output_tokens": 0},
                    "latency_ms": round((time.perf_counter() - started) * 1e3, 2),
                },
            )

        def log_message(self, *args) -> None:
            pass

    return Handler


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--llama", default="http://127.0.0.1:8080", help="llama-server address")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--name", default="plumb-4b-v5", help="model name reported to clients")
    parser.add_argument("--temperature", type=float, default=2.07,
                        help="calibration temperature of the model (Plumb-4B v5: 2.07)")
    args = parser.parse_args(argv)

    from jevk5.gguf import JevK5GGUF

    model = JevK5GGUF(url=args.llama, temperature=args.temperature)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(model.decide, args.name))
    print(f"serving {args.name} (llama.cpp at {args.llama}) "
          f"on http://{args.host}:{args.port}/v1/systemone", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())