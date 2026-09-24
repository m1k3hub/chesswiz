#!/usr/bin/env python3
"""annotation_index: language filter and prose-aware query.

    python3 tests/test_annotation_index.py
"""

import json
import os
import sqlite3
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import annotation_index as ai  # noqa: E402

failures = 0


def check(name, cond):
    global failures
    if cond:
        print(f"PASS: {name}")
    else:
        print(f"FAIL: {name}")
        failures += 1


# --- language detection -------------------------------------------------
check("english: short sentence", ai.looks_english("White is aiming for mate."))
check("english: long sentence",
      ai.looks_english("The Burn Variation is a good choice assuming Black plays solidly."))
check("english: notation only is neutral", ai.looks_english("Rc1 wins."))
check("english: empty is neutral", ai.looks_english(""))
check("not english: german",
      not ai.looks_english("Er hatte bis hierher schon sehr zögerlich gespielt."))
check("not english: french",
      not ai.looks_english("ALAPIN a été un des premiers à utiliser cette ligne."))
check("not english: untagged german",
      not ai.looks_english("Die beliebte Variante des israelischen Großmeisters."))

# --- query filter, end to end on a tiny database ------------------------
db = tempfile.mktemp(suffix=".sqlite")
fen = "rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq - 1 3"
key = ai.fen_key(fen)

conn = sqlite3.connect(db)
conn.execute("CREATE TABLE ann "
             "(key TEXT, comment TEXT, prose INT, nags TEXT, source TEXT, game INT, ply INT)")
for comment, prose, nags in [
    ("White is aiming for mate.", 1, ""),
    ("Er hatte bis hierher schon sehr zögerlich gespielt.", 1, ""),
    ("", 0, "5"),
]:
    conn.execute("INSERT INTO ann VALUES (?,?,?,?,?,?,?)", (key, comment, prose, nags, "t", 1, 1))
conn.commit()
conn.close()


def run(*extra):
    out = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "annotation_index.py"),
         "query", "--db", db, "--fen", fen, "--limit", "5", *extra],
        capture_output=True, text=True)
    return json.loads(out.stdout)


unfiltered = run()
check("query: unfiltered returns every row", len(unfiltered["annotations"]) == 3)

english = run("--english")
check("query: --english drops the german row", len(english["annotations"]) == 2)
check("query: --english keeps english prose",
      any("aiming for mate" in a["comment"] for a in english["annotations"]))
check("query: --english keeps the nag-only row",
      any(a["nags"] == [5] for a in english["annotations"]))
check("query: total is reported unfiltered", english["total"] == 3)

os.unlink(db)

print()
if failures:
    print(f"{failures} annotation-index check(s) failed")
    sys.exit(1)
print("all annotation-index checks passed")
