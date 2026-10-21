#!/usr/bin/env python3
"""
List keys present in tcl/lang/english.tcl but missing in espanol.tcl, italiano.tcl,
magyar.tcl, and svenska.tcl.
"""

import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
LANG_DIR = os.path.join(ROOT_DIR, "tcl", "lang")

def parse_keys(filepath, encoding):
    keys = {}
    with open(filepath, "r", encoding=encoding, errors="replace") as f:
        for line in f:
            line_str = line.strip()
            if not line_str or line_str.startswith("#"):
                continue
            m = re.match(r"^(::[A-Za-z0-9_:]+(?:\([^)]+\))?)\s+(.*)$", line_str)
            if m:
                keys[m.group(1)] = m.group(2)
    return keys

def main():
    en_file = os.path.join(LANG_DIR, "english.tcl")
    de_file = os.path.join(LANG_DIR, "deutsch.tcl")

    en_keys = parse_keys(en_file, "iso-8859-1")
    de_keys = parse_keys(de_file, "iso-8859-1")

    targets = [
        ("es", "espanol.tcl", "utf-8"),
        ("it", "italiano.tcl", "utf-8"),
        ("hu", "magyar.tcl", "utf-8"),
        ("sv", "svenska.tcl", "utf-8"),
    ]

    print(f"Total keys in english.tcl: {len(en_keys)}")

    for code, filename, enc in targets:
        path = os.path.join(LANG_DIR, filename)
        target_keys = parse_keys(path, enc)
        missing = [k for k in sorted(en_keys.keys()) if k not in target_keys]
        print(f"\n[{code}] {filename}: {len(missing)} keys missing from english.tcl")
        by_ns = {}
        for k in missing:
            ns = "::".join(k.split("::")[:-1])
            by_ns.setdefault(ns, []).append(k)
        for ns in sorted(by_ns):
            print(f"  Namespace {ns} ({len(by_ns[ns])} keys):")
            for k in by_ns[ns]:
                print(f"    {k} = {en_keys[k]}")

if __name__ == "__main__":
    main()
