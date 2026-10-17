#!/usr/bin/env python3
"""Extract human annotations from PGN into (position, comment, NAG) records.

    python3 annotation_extract.py --pgn FILE [--out records.jsonl] [--max-games N]

Each record is one annotatable ply:

    {"source": "...", "game": N, "ply": N, "key": "<sha1 of position>",
     "fen": "...", "comment": "...", "prose": true, "nags": [14, 36]}

Clock/eval engine directives ([%clk ...], [%eval ...]) are stripped; NAGs are
kept regardless (they are the machine-readable human judgment).  `key` hashes
the same position identity as scripts/corpus_precedent.py, but as a hex string.

Deciding whether a comment is human prose (vs a clock, an engine line, a CBH
payload, a glossary) is a bounded question, and the `is_prose` regex is wrong on
a labelled set 33% of the time -- it drops every non-Latin prose comment and
passes several clock/engine lines (see docs/TYPESAFE_COOKBOOK_REVIEW.md).  With
--classifier the question goes to TypeSafe (batched, cached, opt-in because the
comments may be private) and `is_prose` is the fallback on any error.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request

import chess.pgn

DIRECTIVE = re.compile(r"\[%[a-z]+(?:[^\[\]]|\[[^\]]*\])*\]", re.IGNORECASE)
CLOCK = re.compile(r"(?i)^(time|zeit|sealed\s+move|abgabezug)[!.\/ ]*$")


def is_prose(text):
    """True for human/engine commentary, false for clocks, ChessBase meta
    tags (CBH payloads, medals) and glossary term translations."""
    if not text:
        return False
    t = text.strip()
    if CLOCK.match(t):
        return False
    if "(CBH payload:" in t:
        return False
    if re.match(r"(?i)^medal:", t):
        return False
    if not re.search(r"[A-Za-z]{3,}", t):
        return False
    # language-tagged glossary: strip <xx> and parenthesised terms; real prose remains
    if re.search(r"<[a-z]{2}>", t):
        stripped = re.sub(r"<[a-z]{2}>", " ", t)
        stripped = re.sub(r"\([^)]*\)", " ", t)
        if len(re.findall(r"[A-Za-z]{3,}", stripped)) < 3:
            return False
    return True


# --- the optional TypeSafe prose classifier --------------------------------
PROSE_CRITERIA = {
    "prose": "human chess commentary, an explanation or assessment written in sentences",
    "machine": "a clock/thinking-time, an engine evaluation line, a CBH payload, a medal, "
               "a bare move list, or a bilingual glossary term -- no human sentence",
}


def _sha(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


class ProseClassifier:
    """Batched, cached /v1/systemone prose question. Any failure returns None
    for the affected texts, and the caller falls back to is_prose."""

    def __init__(self, endpoint, model, key, cache_path, chunk=32, timeout=60,
                 min_confidence=0.6):
        self.endpoint = endpoint
        self.model = model
        self.key = key
        self.cache_path = cache_path
        self.chunk = chunk
        self.timeout = timeout
        self.min_confidence = min_confidence
        self.warned = False
        self.cache = {}
        if cache_path and os.path.exists(cache_path):
            try:
                with open(cache_path, encoding="utf-8") as fh:
                    self.cache = json.load(fh)
            except Exception:
                self.cache = {}

    def _save(self):
        if not self.cache_path:
            return
        try:
            tmp = self.cache_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(self.cache, fh)
            os.replace(tmp, self.cache_path)
        except Exception:
            pass

    def _ask(self, part):
        state = {"comments": [{"id": f"p{i}", "text": text}
                              for i, (_, text) in enumerate(part)]}
        questions = {}
        for i in range(len(part)):
            questions[f"p{i}"] = {
                "type": "choice",
                "instructions": f"Is comment p{i} human chess annotation prose, "
                                "or machine/format content?",
                "criteria": PROSE_CRITERIA,
            }
        body = json.dumps({"state": state, "model": self.model,
                           "questions": questions}).encode()
        headers = {"Content-Type": "application/json"}
        if self.key:
            headers["Authorization"] = "Bearer " + self.key
        req = urllib.request.Request(self.endpoint, data=body, headers=headers)
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            answers = json.loads(resp.read())["answers"]
        got = {}
        for i, (index, _) in enumerate(part):
            answer = answers.get(f"p{i}")
            if answer and answer.get("choice") in ("prose", "machine") \
                    and answer.get("confidence", 1.0) >= self.min_confidence:
                got[index] = answer["choice"] == "prose"
        return got

    def classify(self, texts):
        result = [None] * len(texts)
        missing = []
        for i, text in enumerate(texts):
            key = _sha(text)
            if key in self.cache:
                result[i] = self.cache[key]
            else:
                missing.append((i, text))
        for start in range(0, len(missing), self.chunk):
            part = missing[start:start + self.chunk]
            try:
                got = self._ask(part)
            except Exception as error:  # noqa: BLE001 - fall back on anything
                if not self.warned:
                    print(f"  prose classifier unavailable ({error}); "
                          "using is_prose", file=sys.stderr, flush=True)
                    self.warned = True
                continue
            for index, value in got.items():
                result[index] = value
                self.cache[_sha(texts[index])] = value
        self._save()
        return result


def build_classifier(args):
    enabled = args.classifier or os.environ.get("SCIDB_ANNOTATIONS_CLASSIFIER", "") \
        not in ("", "off", "0")
    if not enabled:
        return None
    endpoint = os.environ.get("SCIDB_ANNOTATIONS_URL", "https://api.typesafe.ai/v1/systemone")
    key = os.environ.get("SCIDB_ANNOTATIONS_API_KEY") or os.environ.get("TYPESAFE_API_KEY", "")
    model = args.classifier_model or os.environ.get("SCIDB_ANNOTATIONS_MODEL", "jev-latest")
    cache = args.classifier_cache or os.environ.get("SCIDB_ANNOTATIONS_CACHE") \
        or (args.out + ".prose-cache.json" if args.out else None)
    try:
        min_conf = float(args.classifier_min_confidence
                         if args.classifier_min_confidence is not None
                         else os.environ.get("SCIDB_ANNOTATIONS_MIN_CONFIDENCE", "0.6"))
    except ValueError:
        min_conf = 0.6
    if not key and endpoint.startswith("https://api.typesafe.ai"):
        print("  no TYPESAFE_API_KEY / SCIDB_ANNOTATIONS_API_KEY: using is_prose",
              file=sys.stderr, flush=True)
        return None
    return ProseClassifier(endpoint, model, key, cache, min_confidence=min_conf)


def position_key(board):
    return " ".join(board.fen().split()[:4])


def position_hash(board):
    return hashlib.sha1(position_key(board).encode()).hexdigest()


def clean_comment(text):
    if not text:
        return ""
    # Remove engine directives such as [%clk 0:05:00] / [%eval 0.5], which may
    # nest to any depth ([%eval [%emt ...] 0.5]). A regex cannot recurse, so scan
    # bracket depth; brackets that do not open a directive are kept verbatim.
    out = []
    depth = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if depth == 0:
            if ch == "[" and i + 1 < n and text[i + 1] == "%":
                depth = 1
                i += 2
                continue
            out.append(ch)
            i += 1
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        i += 1
    return "".join(out).strip()


EN_MARK = re.compile(r"<en>", re.IGNORECASE)


def prefer_english(text):
    """ChessBase teaching comments often carry German and English variants
    ("<de> ... <en> ...").  Keep only the English part when both are present,
    so the narration corpus stays in one language."""
    if not text or "<en>" not in text.lower():
        return text
    english = EN_MARK.split(text)[-1]
    english = re.sub(r"<[a-z]{2}>", " ", english)
    return english.strip()


def extract(args):
    out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
    classifier = build_classifier(args)
    chunk = getattr(classifier, "chunk", 32) if classifier else 0

    games = 0
    records = 0
    with_comment = 0
    with_nag = 0
    buffer = []                 # records not yet written, in order
    pending = []                # (buffer index, comment text) awaiting a verdict

    def flush():
        nonlocal records, with_comment, with_nag
        if pending:
            texts = [text for _, text in pending]
            verdicts = classifier.classify(texts) if classifier else [None] * len(texts)
            for (index, text), verdict in zip(pending, verdicts):
                buffer[index]["prose"] = is_prose(text) if verdict is None else verdict
            pending.clear()
        for record in buffer:
            if record["prose"] or record["nags"]:
                out.write(json.dumps(record, ensure_ascii=False) + "\n")
                records += 1
                if record["prose"]:
                    with_comment += 1
                if record["nags"]:
                    with_nag += 1
        buffer.clear()

    with open(args.pgn, encoding="utf-8", errors="replace") as fh:
        while args.max_games == 0 or games < args.max_games:
            try:
                game = chess.pgn.read_game(fh)
            except Exception:
                continue
            if game is None:
                break
            games += 1

            board = game.board()
            ply = 0
            for node in game.mainline():
                move = node.move
                if move is None:
                    break
                ply += 1

                comment = clean_comment(node.comment)
                comment = prefer_english(comment)
                nags = sorted(int(n) for n in node.nags)

                record = {
                    "source": game.headers.get("Source", "") or args.source,
                    "game": games,
                    "ply": ply,
                    "key": position_hash(board),
                    "fen": board.fen(),
                    "comment": comment,
                    "prose": False,
                    "nags": nags,
                }
                if comment:
                    pending.append((len(buffer), comment))
                buffer.append(record)
                if len(pending) >= (chunk or 1) or len(buffer) >= 4096:
                    flush()

                board.push(move)

            if games % 50000 == 0:
                print(f"  {games} games, {records} records, "
                      f"{with_comment} prose, {with_nag} nags",
                      file=sys.stderr, flush=True)

    flush()
    if args.out:
        out.close()

    print(json.dumps({
        "games": games,
        "records": records,
        "with_comment": with_comment,
        "with_nag": with_nag,
    }))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pgn", required=True)
    ap.add_argument("--out")
    ap.add_argument("--max-games", type=int, default=20000)
    ap.add_argument("--source", default="")
    ap.add_argument("--classifier", action="store_true",
                    help="ask TypeSafe whether each comment is prose (batched, cached); "
                         "is_prose is the fallback")
    ap.add_argument("--classifier-model", default="")
    ap.add_argument("--classifier-min-confidence", type=float, default=None,
                    help="a verdict below this falls back to is_prose (default 0.6)")
    ap.add_argument("--classifier-cache", default="")
    args = ap.parse_args()
    extract(args)


if __name__ == "__main__":
    main()
