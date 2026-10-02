# Native pipeline profiling

Use copied native triplets and the app-backed headless runner. This measures
the same native decoder and snapshot adapter used by the UI; it does not export
PGN as the search input. The bounded workload selects exactly 1200 source indices
by default, uses one engine worker, and checks the examined-game count.

Build an optimized archive with debug information and internal symbols retained:

```sh
make -j4 -C src/cql6 -f Makefile.scidb BUILD_DIR=/tmp/cql6-profile STRIP=true \
  CXXFLAGS='-std=c++17 -pthread -w -DASSERTIONS -DCQL6_EMBEDDED -DCQL6_LIBRARY_BUILD -fvisibility=hidden -fno-gnu-unique -fPIC -I. -I./orig -include scidb_sink.h -O2 -g' lib
python3 tests/build_cql6_native_runner.py --output /tmp/cql6-profile-native \
  --cql-library /tmp/cql6-profile/libcql6.a
CQL6_NATIVE_DIR=/tmp/cql6-native-data valgrind --tool=callgrind \
  --collect-atstart=no --toggle-collect=cql6_search '--toggle-collect=*requestGame*' \
  --callgrind-out-file=/tmp/cql6-native-check.callgrind \
  /tmp/cql6-profile-native/runner tests/cql6_profile_native.tcl
callgrind_annotate --inclusive=yes --threshold=95 /tmp/cql6-native-check.callgrind
```

The two collection boundaries include the worker's engine work and the main
thread's native decode/snapshot slices, excluding database opening and application
startup. Confirm that both boundaries appear in the output before drawing conclusions.
Worker queue waiting consumes wall time without a comparable instruction cost.

Inspect `Database::exportGame` and codec decoder descendants for decoding,
`Exporter` callbacks and `Snapshot::seal` for snapshot creation,
`ScidbGameSource::populateGame` and `QPos::visitRoot` for engine preparation,
and `CqlNode::match_game` for matching. Inclusive parent/child counts overlap;
do not add them together as independent stages. Attribute exporter callbacks
separately from decoder self-cost to avoid counting snapshots twice.

Set `CQL6_PROFILE_DATABASE` to `twic_complete`, `CCRL-4040`, or
`LumbrasGigabase_OTB`, `CQL6_PROFILE_GAMES` to change the
selection size, `CQL6_PROFILE_SCRIPT` to an entire CQL script, and
`CQL6_PROFILE_VARIATIONS` to 0 or 1. Callgrind elapsed times are instrumentation
costs; repeat the identical workload without Valgrind for throughput measurements.

First measured workload: Twic, 1200 games, `cql() check`, variations off,
one worker. Both collection boundaries are present. Total 4,125,220,615
instructions: requestGame 72.37%, engine search 27.63%. Inside those boundaries,
native export is 71.69%, engine populateGame 15.86%, QPos::visitRoot 9.74%,
and matching 1.18% of the combined total. These are inclusive costs and some
source-attributed inline entries split a function's cost across files.

The largest native cost is db::Board::isValidMove (63.00%), called from
Consumer::putMove preconditions. Board::findAnyLegalMove accounts for 58.36%
inside that check. This identifies assertion-driven native decoding as the next
performance investigation; it does not establish that removing validation is
safe. Full-source paths and shorter paths sometimes repeat attribution entries;
do not add both. Snapshot callbacks are comparatively small (Exporter::endGame
0.24%, Exporter::sendMove 0.19%).

Raw artifacts: `/tmp/cql6-native-check.callgrind`, log
`/tmp/cql6-native-check-profile.log`, inclusive function report
`/tmp/cql6-native-check-profile-functions.txt`. Callgrind elapsed time was 38287
ms; the same release smoke workload without instrumentation was 505 ms.
This is one workload, not a three-database performance gate. Current evidence
and live processes are tracked in RESUME_STATUS.md.

The normal-chess legal-move fast path reduced the identical workload to
2,058,397,935 instructions (50.10% fewer). Native requestGame fell from 2.985B
to 0.918B instructions; engine search remained 1.140B. Move validation remains
enabled. A fully legal non-null candidate proves a legal move exists, avoiding
the preliminary all-moves terminal-state query; nulls, other variants and illegal
permissive candidates retain the original check. Matching output is unchanged.
The baseline comparison test covers 81,364 candidates, and all 84 native/pristine
comparisons passed again after this change.

Artifacts `/tmp/cql6-native-check-fast.callgrind`,
`/tmp/cql6-native-check-fast-profile.log`, and
`/tmp/cql6-native-check-fast-functions.txt`. Uninstrumented 1200-game smoke was
212 ms; instrumented run 20128 ms. These elapsed figures are single samples.
