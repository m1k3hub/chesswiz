# Feature catalog generator

Regenerates `docs/FEATURES.md` from the live action registry.

    cp tools/features/dump_registry.tcl tests/zz_dump_registry.tcl
    H=$(mktemp -d); DUMP_OUT=/tmp/reg.jsonl HOME=$H SCIDB_USERDIR=$H PULSE_SINK=cwtests \
      xvfb-run -a src/tkchesswiz tests/run_app_tests.tcl -file zz_dump_registry.tcl
    rm tests/zz_dump_registry.tcl
    python3 tools/features/gen.py /tmp/reg.jsonl tools/features/findings.md \
      tcl/td-ui.tcl tools/features/equiv.json docs/FEATURES.md

`findings.md` (section 2) and `equiv.json` (the "Elsewhere" column for assistant
tools) are written by hand; review them when features move.
