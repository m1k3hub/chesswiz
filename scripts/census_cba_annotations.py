#!/usr/bin/env python3
"""List classic-CBH display annotations as JSON lines, including raw payloads.

Usage: python3 scripts/census_cba_annotations.py /path/to/cbm168
Game indices are zero-based; position -1 means game-wide. Duplicate games
in separate databases are deliberately counted separately.
"""
import argparse
from collections import Counter
import json
from pathlib import Path


def records(path):
    index = path.read_bytes()
    annotations = path.with_suffix('.cba').read_bytes()
    for game in range(len(index) // 46 - 1):
        start = (game + 1) * 46
        offset = int.from_bytes(index[start + 5:start + 9], 'big')
        if not offset:
            continue
        if offset + 14 > len(annotations):
            raise ValueError(f'{path}: game {game}: truncated annotation header')
        end = offset + int.from_bytes(annotations[offset + 10:offset + 14], 'big')
        cursor = offset + 14
        if end < cursor or end > len(annotations):
            raise ValueError(f'{path}: game {game}: invalid annotation block length')
        while cursor < end:
            if cursor + 6 > end:
                raise ValueError(f'{path}: game {game}: truncated record header')
            length = int.from_bytes(annotations[cursor + 4:cursor + 6], 'big')
            if length < 6 or cursor + length > end:
                raise ValueError(f'{path}: game {game}: invalid record length')
            kind = annotations[cursor + 3]
            if kind in (0x14, 0x15, 0x22, 0x23):
                position = int.from_bytes(annotations[cursor:cursor + 3], 'big')
                yield dict(game=game, position=-1 if position == 0xffffff else position,
                           type=f'0x{kind:02x}',
                           payload=annotations[cursor + 6:cursor + length].hex())
            cursor += length


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    counts = Counter()
    databases = 0
    for path in sorted(args.root.rglob('*.cbh')):
        if not path.with_suffix('.cba').exists():
            continue
        databases += 1
        for record in records(path):
            counts[record['type']] += 1
            print(json.dumps(dict(database=str(path.relative_to(args.root)), **record)))
    print(json.dumps(dict(databases=databases, counts=dict(sorted(counts.items())))))


if __name__ == '__main__':
    main()
