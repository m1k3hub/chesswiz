# Player/site startup cache

Implemented in the working tree based on `131d982`; no commit was made.

## Behavior and format

`tcl/load.tcl` attempts `::scidb::app::load cache-read <path> <sources>` before
loading player sources. The default path is `[file join $::scidb::dir::user cache
players.bin]`, so the existing platform-specific user-directory selection also
covers Windows `%APPDATA%/Chesswiz`.

The source list includes the spellcheck files, engine list, selected FIDE list,
the user's `ratings/fide-players.txt` (including its absence), enabled rating
lists, Wikipedia and chessgames links, and cities. The selected FIDE path is
recorded separately so switching between the shipped and user lists invalidates
the cache. Fast-load does not read or write it. Elo-only uses a different source
manifest and retains its previous load behavior.

The envelope records `CWPC`, format version 1, program version/revision/git SHA,
and the ordered normalized source paths, existence, 64-bit size and 64-bit mtime.
All integers have explicit little-endian encodings; strings have length prefixes.
The payload contains every player field and all lookup/search/alias/link tables,
plus sites, countries, aliases and their lookup/search tables. Object references
are integer indices. A CRC32, encoded in the final 64-bit slot, checks the complete
header and payload. Change the format version when changing the layout.

Reads validate the manifest, bounded regular-file size, exact byte count, EOF,
checksum, field domains, counts and references. Both databases decode into owning
staging states; neither live database changes until all validation succeeds.
Source metadata is checked again before committing. A failure returns false and
startup parses normally. A restored sorted search index bypasses `loadDone()`.

An attempted cache-read binds a possible later write to the source metadata
observed before parsing. Following successful parsing and `load done`, Tcl calls
`cache-write <path> <sources>`. Parse failures disable writing. Writes verify the
source binding again, use an exclusive temporary file in the same directory,
close it, then rename it through Tcl's filesystem API. Failures close and remove
the temporary file. Channels use binary mode and raw byte reads/writes, with
Tcl's Unicode-capable filesystem paths and opaque stat API.

`loadDone()` also uses byte comparisons instead of UTF-8 decoding and validation
on every sorting comparison. Valid UTF-8 byte order equals Unicode scalar order;
the differential test checks comparison signs against the original comparator.

## Changed files

- `src/db/db_startup_cache.h`: bounded encoding/decoding, index references, CRC,
  staging interface and bulk map restoration helpers.
- `src/db/db_player.cpp`, `src/db/db_player.h`: player serialization and owning
  staging state; cheaper final search-index sorting.
- `src/db/db_site.cpp`, `src/db/db_site.h`: site serialization and owning staging
  state; cheaper final search-index sorting.
- `src/tcl/tcl_player_cache.h`: persisted envelope, source fingerprint, atomic
  writes and transactional reads.
- `src/tcl/tcl_application.cpp`: minimal cache-read/cache-write commands and
  skipping finalization on a restored cache.
- `tcl/load.tcl`: startup wiring, source/profile selection, failure guards and
  debug timing messages.
- `tests/test_player_cache.cpp`, `tests/run_player_cache_test.sh`: full-data
  differential test and in-memory phase benchmark.
- `tests/test_player_cache_io.cpp`, `tests/run_player_cache_io_test.sh`: production
  filesystem-adapter integration tests and fresh-process persisted benchmark.
- `tests/test_load_cache.tcl`: eight headless startup-orchestration checks.

Affected objects were deleted following header edits and the Linux application
was rebuilt. The generated `tcl/chesswiz` was rebuilt with `make -C tcl`.
Existing unrelated working-tree changes were left in place.

## Validation

```sh
make -C src -j6
make -C tcl
tests/run_player_cache_test.sh
tests/run_player_cache_io_test.sh
tclsh tests/test_load_cache.tcl
```

The full-data differential test passes for 181,197 players: public fields,
ratings, names/ascii spellings, aliases, Wikipedia link order, other links,
federation ID and name lookups, engines/protocol/variant flags, site/country
lookups and complete site matches. It verifies two round trips and unchanged
live state after corrupt/truncated decoding. The old/new sorting comparison
signs agree for actual adjacent/distant/equal names and diverse UTF-8 examples.

Filesystem integration passes: revision/version/SHA changes, ordered manifests,
size and mtime changes, absent/present/removed user FIDE source, corrupt headers
and payloads, checksum-correct invalid player/site sections, truncation, missing
and directory paths, oversized manifests/files, failed reads/writes/renames,
exclusive temp cleanup and atomic replacement. Startup-orchestration tests:
8 passed, 0 failed, including fast-load, elo-only, own-FIDE selection and parse
failure suppression of cache writes.

All three changed C++ translation units compiled into Windows objects with
`zig c++ -target x86_64-windows-gnu`, the repository's Windows Tcl headers and
existing platform flags. Clang 21 syntax checks also pass. On this Linux host,
Clang checks required `-include bits/floatn.h` before the repository's existing
`__GNUC_PREREQ` override. An actual macOS SDK build and Windows runtime rename
check were not available; these are not claimed as tested.

The required app command was attempted before and after the changes:

```sh
CHESSWIZ_LOG=debug xvfb-run -a src/tkchesswiz tests/run_app_tests.tcl
```

The sandbox rejects Xvfb socket creation; Tk reports "couldn't connect to display".
The suite never reaches its tests. Consequently **767 passed / 0 failed has not
been reverified**, and no new main-window/debug-phase timings are claimed.
A scratch user directory was used for the final attempt. No `-match` was used.

## Linux measurements

Same unoptimized developer build, actual shipped startup sources, three fresh
processes per measured warm/in-memory series. File pages were warm; these are
headless player/site subsystem times, excluding ECO and UI startup. The scoring
reference is the original parse/finalize implementation; parsing remains the
independent correctness oracle.

| Operation | Seconds (median or explicitly single run) | Range |
| --- | ---: | ---: |
| Original parsing + finalization | 1.990 median | 1.984–2.139 |
| Original `loadDone()` | 0.811 median | 0.805–0.888 |
| Updated `loadDone()` | 0.049 median | 0.048–0.058 |
| Updated parse + finalization, final persisted benchmark | 1.300 single run | — |
| Persisted cache hit, including I/O + CRC + decode | 0.762 median | 0.732–0.766 |
| Cold cache write, final persisted benchmark | 1.552 single run | — |

Persisted hits are approximately 62% faster than the original parsing and
finalization, and 41% faster than the improved uncached path. Finalization alone
is about 16.5 times faster. The payload is 52,794,152 bytes (about 50.3 MiB).
The first start/cache rebuild pays the one-time write cost: the final cold
benchmark's full player/cache sequence took 2.852 seconds.

The persisted benchmark initially exposed a 1.58-second cost in repeated
`std::vector` block insertion in an unoptimized build; actual file reads took
0.01 seconds. A bounded pre-sized input buffer removed that overhead. An early
per-byte checksum loop was also replaced by the existing zlib CRC wrapper.

Reproduce the subsystem measurements with:

```sh
CACHE_TEST_REPEAT=3 tests/run_player_cache_test.sh --timing-only
mkdir -p /tmp/chesswiz-startup-benchmark
# A new/nonexistent path gives the cold parse/write run.
tests/run_player_cache_io_test.sh --benchmark /tmp/chesswiz-startup-benchmark/players.bin
# Repeat this same command three times in fresh processes for cache hits.
tests/run_player_cache_io_test.sh --benchmark /tmp/chesswiz-startup-benchmark/players.bin
```

On a host where X is permitted, obtain the remaining application evidence with
the app-suite command above and repeated normal launches under
`CHESSWIZ_LOG=debug`. `log/debug.log` under the user directory records existing
startup `phase` messages and new cache read/hit, write and loadDone elapsed times.
