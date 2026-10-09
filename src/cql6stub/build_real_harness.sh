#!/usr/bin/env bash
# Test-only runner using the existing application libraries and real codecs.
set -euo pipefail
projectRoot=$(cd "$(dirname "$0")/../.." && pwd)
buildDir=${CQL6_HARNESS_DIR:-/tmp/cql6-real}
mkdir -p "$buildDir"
sanFlag=
if [[ -n ${CQL6_HARNESS_SANITIZE:-} ]]; then
 sanFlag="-fsanitize=$CQL6_HARNESS_SANITIZE -fno-omit-frame-pointer"
fi
make -C "$projectRoot/src/tcl" -W tcl_cql6.cpp CQL6_FLAGS="$sanFlag"
make -C "$projectRoot/src/cql6stub" -W cql6_stub.cpp SANITIZE="$sanFlag"
make -C "$projectRoot/src" CQL6_LIB=cql6stub/libcql6stub.a CQL6_FLAGS="$sanFlag" SANITIZE="$sanFlag" LDFLAGS="$sanFlag"
make -n -B -C "$projectRoot/src" tkscidb-only CQL6_LIB=cql6stub/libcql6stub.a CQL6_FLAGS="$sanFlag" SANITIZE="$sanFlag" LDFLAGS="$sanFlag" > "$buildDir/link.plan"
python3 - "$projectRoot" "$buildDir" <<'PY'
import os, pathlib, shlex, subprocess, sys
root, out = map(pathlib.Path, sys.argv[1:])
flags = ['-std=c++17', '-g', '-DBROKEN_LINKER_HACK=1', '-DDONT_USE_GDB', '-DDONT_USE_FRAME_ADDR', '-I/usr/include/tcl8.6']
if os.environ.get('CQL6_HARNESS_SANITIZE'):
    flags += ['-fsanitize='+os.environ['CQL6_HARNESS_SANITIZE'], '-fno-omit-frame-pointer']
flags += ['-I'+str(root/'src'/p) for p in ['', 'mstl', 'sys', 'db', 'db/sci', 'db/si3', 'util', 'app', 'tcl']]
for name in ['real_harness', 'roundtrip_baseline']:
    subprocess.run(['g++', *flags, '-c', str(root/'src/cql6stub'/f'{name}.cpp'), '-o', str(out/f'{name}.o')], check=True)
line = next(s for s in (out/'link.plan').read_text().splitlines() if s.startswith('g++ -o tkchesswiz '))
link = shlex.split(line)
for name, old in [('headless', False), ('headless-baseline', True)]:
    command = [link[0], '-o', str(out/name), str(out/'real_harness.o')]
    if old:
        command += [str(out/'roundtrip_baseline.o')]
    command += link[4:]
    subprocess.run(command, cwd=root/'src', check=True)
PY
