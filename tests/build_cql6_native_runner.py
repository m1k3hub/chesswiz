#!/usr/bin/env python3
"""Build an app-backed real-CQL runner without starting Tk (run from any cwd)."""
import argparse
import pathlib
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/cql6-native'))
parser.add_argument('--cql-library', type=pathlib.Path,
                    help='Link an isolated profiling archive instead of the normal release archive')
parser.add_argument('--harness', type=pathlib.Path,
                    help='Use a standalone validation harness with the application libraries')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['make', '-j4', '-C', str(root / 'src'), 'tkscidb-only'], check=True)
flags = ['-std=c++17', '-g', '-DBROKEN_LINKER_HACK=1', '-DDONT_USE_GDB', '-DDONT_USE_FRAME_ADDR']
flags += shlex.split(subprocess.check_output(['pkg-config', '--cflags', 'tcl'], text=True))
flags += ['-I' + str(root / 'src' / p) for p in ['', 'mstl', 'sys', 'db', 'db/sci', 'db/si3', 'util', 'app', 'tcl']]
harness = args.harness.resolve(strict=True) if args.harness else root / 'src/cql6stub/real_harness.cpp'
subprocess.run(['g++', *flags, '-c', str(harness), '-o', str(out / 'runner.o')], check=True)
plan = subprocess.check_output(['make', '-n', '-C', str(root / 'src'), '-W', 'tkscidb.o', 'tkscidb-only'], text=True)
line = next(line for line in plan.splitlines() if line.startswith('g++ -o tkscidb-beta '))
link = shlex.split(line)
if args.cql_library:
    library = args.cql_library.resolve(strict=True)
    slots = [i for i, value in enumerate(link) if value.endswith('/libcql6.a')]
    if len(slots) != 1:
        raise RuntimeError('expected exactly one CQL archive in application link command')
    link[slots[0]] = str(library)
subprocess.run([link[0], '-o', str(out / 'runner'), str(out / 'runner.o'), *link[4:]], cwd=root / 'src', check=True)
print(f'Run from {root}: CQL6_NATIVE_DIR=/path/to/copied/triplets {out / "runner"} tests/cql6_native.tcl')
