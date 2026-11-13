#!/usr/bin/env python3
"""Compare effective registry tools with legacy fixtures plus baseline generated tools.

Run test_app_menu_toolset.tcl, then pass its log. Empty schemas are an error:
producers must emit schemaJson(args) when the stored schema is empty.
"""
import argparse
import base64
import json
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')


def compare(log, fixtures, snapshot_path=Path(__file__).with_name('assistant-generated-baseline.json')):
    actual = {}
    surfaces = {}
    for line in log.splitlines():
        if line.startswith('TOOLSJSON|'):
            _, mode, names = line.split('|')
            if mode in surfaces:
                raise ValueError(f'duplicate toolsJson surface: {mode}')
            names = names.split(',') if names else []
            if len(names) != len(set(names)):
                raise ValueError(f'duplicate toolsJson name in {mode}')
            surfaces[mode] = set(names)
        if not line.startswith('CANONICAL|'):
            continue
        _, name, confirm, ai, operator, schema, hint = line.split('|')
        if ai not in ('1', 'debug'):
            raise ValueError(f'invalid exposed AI flag for {name}: {ai}')
        if name in actual:
            raise ValueError(f'duplicate runtime tool: {name}')
        if not schema:
            raise ValueError(f'missing effective schema: {name}')
        actual[name] = dict(params_schema=json.loads(base64.b64decode(schema)),
                            confirm=int(confirm), debug=int(ai == 'debug'), operator=int(operator),
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
    snapshot = json.loads(snapshot_path.read_text())
    generated = snapshot['tools']
    generated_names = [row['name'] for row in generated]
    if len(generated_names) != len(set(generated_names)) or set(generated_names) & set(expected):
        raise ValueError('duplicate/legacy name in generated snapshot')
    expected += generated_names
    bad = []
    for row in generated:
        name = row['name']
        flags = dict(confirm=row['confirm'], operator=row['operator'],
                     debug=int(row['ai'] == 'debug'))
        for key, value in flags.items():
            if actual.get(name, {}).get(key) != value:
                bad.append((name, key))
    for row in baseline + metadata:
        name = row['name']
        for key in ('params_schema', 'confirm', 'debug', 'tool_menu_hint'):
            if key in row and canonical(actual.get(name, {}).get(key)) != canonical(row[key]):
                bad.append((name, key))
    surface_errors = {}
    for mode in ('debug', 'normal'):
        wanted = set(expected)
        if mode == 'normal':
            debug_names = {row['name'] for row in baseline + metadata if row.get('debug')}
            debug_names |= {row['name'] for row in generated if row['ai'] == 'debug'}
            wanted -= debug_names
        if mode not in surfaces:
            surface_errors[mode] = 'missing toolsJson evidence'
        elif surfaces[mode] != wanted:
            surface_errors[mode] = dict(extras=sorted(surfaces[mode] - wanted), missing=sorted(wanted - surfaces[mode]))
    result = dict(baseline=len(baseline), legacy_approved=len(expected) - len(generated),
                  generated=len(generated), snapshot_commit=snapshot['commit'],
                  approved=len(expected), runtime=len(actual),
                  toolsJson={mode: len(names) for mode, names in surfaces.items()},
                  surface_errors=surface_errors,
                  extras=sorted(set(actual) - set(expected)), missing=sorted(set(expected) - set(actual)),
                  mismatches=bad)
    print(json.dumps(result, indent=2))
    return not (result['extras'] or result['missing'] or bad or surface_errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--fixtures', type=Path, default=Path(__file__).parent / 'fixtures')
    parser.add_argument('--snapshot', type=Path, default=Path(__file__).with_name('assistant-generated-baseline.json'))
    args = parser.parse_args()
    return int(not compare(args.log.read_text(), args.fixtures, args.snapshot))


if __name__ == '__main__':
    raise SystemExit(main())
