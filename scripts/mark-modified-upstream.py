#!/usr/bin/env python3
"""Add a GPL change notice to Scidb files that Chesswiz modified.

Usage: git diff --no-renames --name-only --diff-filter=M scidb-upstream HEAD |
           python3 scripts/mark-modified-upstream.py
Idempotent: files that already carry the notice are left alone. Binary files,
data files and third-party licence texts are skipped.
"""
import re, sys

NOTE = "Modified for Chesswiz, 2026; see docs/UPSTREAM.md"
CRAMER = re.compile(rb"^(\S{0,3}) ?Copyright: \(C\) [0-9-]+ Gregor Cramer\s*$")
SLASH = (".c", ".h", ".cpp", ".ipp", ".m", ".rc", ".css")
HASH = (".tcl", ".sh", ".conf")
done = skipped = 0
for path in (l.strip() for l in sys.stdin if l.strip()):
    try:
        data = open(path, "rb").read()
    except OSError:
        continue
    if b"\0" in data[:4096] or NOTE.encode() in data:
        skipped += 1
        continue
    lines = data.splitlines(keepends=True)
    eol = b"\r\n" if lines and lines[0].endswith(b"\r\n") else b"\n"
    for i, line in enumerate(lines):
        m = CRAMER.match(line)
        if m:
            prefix = m.group(1)
            if prefix == b"#!":
                prefix = b"#"
            lines.insert(i + 1, prefix + b" " + NOTE.encode() + eol)
            break
    else:
        name = path.rsplit("/", 1)[-1]
        if path.endswith(SLASH):
            note = b"/* " + NOTE.encode() + b" */" + eol
        elif path.endswith(HASH) or name == "Makefile" or name.startswith("Makefile."):
            note = b"# " + NOTE.encode() + eol
        else:
            skipped += 1
            continue
        at = 1 if lines and lines[0].startswith(b"#!") else 0
        lines.insert(at, note)
    open(path, "wb").write(b"".join(lines))
    done += 1
print(f"marked {done}, skipped {skipped}")
