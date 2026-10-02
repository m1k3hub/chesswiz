#!/bin/bash
# scidb: incremental rebuild of release/asan/tsan after header edits (uses -MMD deps).
cd "$(dirname "$0")/.." || exit 9
: > /tmp/rebuild2.status
{
  echo "=== release ==="
  make -f Makefile.scidb -j16 lib && echo "release OK" || echo "release FAIL"
  echo "=== asan ==="
  make -f Makefile.scidb asan-build -j16 && echo "asan OK" || echo "asan FAIL"
  echo "=== tsan ==="
  make -f Makefile.scidb tsan-build -j16 && echo "tsan OK" || echo "tsan FAIL"
  echo "ALLDONE"
} >> /tmp/rebuild2.status 2>> /tmp/rebuild2.log
