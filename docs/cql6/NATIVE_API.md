# Native CQL 6.2 searches

`::scidb::cql6::search DATABASE VARIANT SCRIPT` searches a loaded native database.
Use `-command PREFIX` for asynchronous execution; the prefix receives one result
dictionary on the Tcl thread. `-threads N`, `-variations 0|1`, `-max N` and
`-pgn 0|1` control workers, variation searching, per-script limits and annotated PGN.
Asynchronous results include `ok`, and `error` on failure.

Additional scripts share game decoding and engine preparation:

```tcl
::scidb::cql6::search $database Normal {cql() mate} \
    -scripts [list {cql(variations) check} {cql() pin}] \
    -threads 8 -command receiveResults
```

Results contain `matches`, `games`, `threads`, `cancelled` and `messages`.
Each match contains `game` (the host's zero-based database index), `first_ply`
(-1 when only variations match), and optionally `pgn`. In batches, `script`
identifies the primary script as 0 and the additional scripts as 1, 2, etc.
Results are grouped by script, with each script's sorting and limit applied
independently. `games` counts accepted games once across the whole batch.
Persistent scripts force one worker; their messages carry the script index.

`-view N` snapshots the game indices selected by an existing database view.
Metadata filters can therefore narrow candidates before any moves are decoded.
The search retains native database indices in its results and handles empty views.
The captured selection remains fixed if the view changes while the search runs.

Each script retains its own variation view and annotation/tag state. The adapter
decodes the union of requested variations, including `cql(variations)` headers.
It validates native moves before evaluation. On an imported illegal move, it
retains the legal prefix, matching the official PGN reader. The result's
`truncated` count and `messages` report this condition. The generic C API retains
whole-game rejection by default; prefix compatibility is an explicit option.

Large result sets: every match is a Tcl object created and later freed on the
GUI thread, which costs about 80 ms per million objects each way. `-compact 1`
returns `matches` as a flat `{game first_ply game first_ply ...}` list instead of
dictionaries. `-paged 1` omits `matches` altogether. The result then carries
`count` and a `results` handle, and the matches stay in the adapter until
released:

```tcl
::scidb::cql6::matches RESULTS FIRST COUNT  ;# flat {game first_ply ...} page
::scidb::cql6::release RESULTS              ;# 1 if it was still retained
```

The CQL 6.2 dialog pages its result list this way. Paged results are also freed
when the interpreter is deleted.

`::scidb::cql6::cancel JOB` cancels an asynchronous job.
`::scidb::cql6::progress JOB` reports progress, or -1 after completion delivery.
Only one engine search can run at a time.
