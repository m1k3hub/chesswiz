#!/usr/bin/env python3
"""Compare effective CANONICAL tool records with the frozen approved toolset.

Run test_app_menu_toolset.tcl, then pass its log. Empty schemas are an error:
producers must emit schemaJson(args) when the stored schema is empty.
"""
import argparse
import base64
import json
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')


def compare(log, fixtures):
    actual = {}
    for line in log.splitlines():
        if not line.startswith('CANONICAL|'):
            continue
        _, name, confirm, ai, schema, hint = line.split('|')
        if name in actual:
            raise ValueError(f'duplicate runtime tool: {name}')
        if not schema:
            raise ValueError(f'missing effective schema: {name}')
        actual[name] = dict(params_schema=json.loads(base64.b64decode(schema)),
                            confirm=int(confirm), debug=int(ai == 'debug'),
                            tool_menu_hint=base64.b64decode(hint).decode('utf-8'))
    baseline = json.loads((fixtures / 'assistant-tools-baseline.json').read_text())
    expected = [row['name'] for row in baseline]
    metadata = []
    for line in (fixtures / 'assistant-tools-additions.txt').read_text().splitlines():
        if line.startswith('# metadata {'):
            row = json.loads(line[11:])
            row['params_schema'] = json.loads(row['params_schema'])
            metadata.append(row)
        elif line.strip() and not line.lstrip().startswith('#'):
            expected.append(line.split()[0])
    if len(expected) != len(set(expected)):
        raise ValueError('duplicate approved tool')
    bad = []
    for row in baseline + metadata:
        name = row['name']
        for key in ('params_schema', 'confirm', 'debug', 'tool_menu_hint'):
            if key in row and canonical(actual.get(name, {}).get(key)) != canonical(row[key]):
                bad.append((name, key))
    result = dict(baseline=len(baseline), approved=len(expected), runtime=len(actual),
                  extras=sorted(set(actual) - set(expected)), missing=sorted(set(expected) - set(actual)),
                  mismatches=bad)
    print(json.dumps(result, indent=2))
    return not (result['extras'] or result['missing'] or bad)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--fixtures', type=Path, default=Path(__file__).parent / 'fixtures')
    args = parser.parse_args()
    return int(not compare(args.log.read_text(), args.fixtures))


if __name__ == '__main__':
    raise SystemExit(main())
