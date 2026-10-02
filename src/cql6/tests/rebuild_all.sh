#!/bin/bash
# scidb: full clean rebuild of release, asan and tsan after header edits.
cd "$(dirname "$0")/.." || exit 9
rm -rf build
echo "=== release ===" > /tmp/rebuild_all.status
make -f Makefile.scidb -j16 lib >> /tmp/rebuild_all.log 2>&1
echo "release EXIT=$?" >> /tmp/rebuild_all.status
make -f Makefile.scidb -j16 test >> /tmp/rebuild_all.log 2>&1
echo "test EXIT=$?" >> /tmp/rebuild_all.status
echo "=== asan ===" >> /tmp/rebuild_all.status
make -f Makefile.scidb asan-build -j16 >> /tmp/rebuild_all.log 2>&1
echo "asan EXIT=$?" >> /tmp/rebuild_all.status
echo "=== tsan ===" >> /tmp/rebuild_all.status
make -f Makefile.scidb tsan-build -j16 >> /tmp/rebuild_all.log 2>&1
echo "tsan EXIT=$?" >> /tmp/rebuild_all.status
echo "ALLDONE" >> /tmp/rebuild_all.status
