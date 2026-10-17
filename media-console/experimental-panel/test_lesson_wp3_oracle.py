#!/usr/bin/env python3
"""WP3 oracle harness: byte-compare the pure-Tcl move applier's FENs
against a python-chess replay of the same checkpoint edge stream.

docs/features/MEDIA_LESSON_V2_PLAN.md WP3 acceptance: positions[N] FENs byte-match a
python-chess replay of the same edges for all N.

Both sides emit the RAW FEN ep convention (python-chess
fen(en_passant='fen'): the ep square is printed after every double
pawn push, whether or not a capture is possible) -- python's default
is en_passant='legal', which hides non-capturable ep squares.

Usage: python3 test_lesson_wp3_oracle.py [fixture-wmv]
Exit 0 iff every position matches.

The gated fixture is round 08 (the plan's WP2/WP3 ground truth).
Round 01's edge stream currently dead-ends at edge 58 (h4-g5 not
legal at any ancestor under python-chess) — an open WP2 data item
(an upstream resync or non-standard-start question, not an applier
issue; the lesson build degrades gracefully: valid=0 + reason).
"""
import subprocess
import sys
import os

import chess

HERE = os.path.dirname(os.path.abspath(__file__))
ORACLE = os.path.join(HERE, 'wp2_checkpoint_oracle.py')
REPO = os.path.dirname(os.path.dirname(HERE))          # repo root
sys.path.insert(0, HERE)

import wp2_checkpoint_oracle as wp2                    # noqa: E402

WMV = sys.argv[1] if len(sys.argv) > 1 else (
    '/media/michael-g-thomas/sas_mirror/fixt/cbm168/'
    'Festival Biel 2015.html/Biel 2015 round 08 MVL-Adams.wmv')


def tcl_positions(edges):
    """Run the Tcl applier on the edge list; return its FEN list."""
    tcl = r'''
namespace eval ::scidb::dir {}
set ::scidb::dir::user /tmp/wp3oracle
source {%(decode)s}
source {%(lesson)s}
set edges {%(edges)s}
lassign [::media::lesson::apply-edges $edges] positions err
if {$err ne ""} { puts stderr "APPLY ERROR: $err"; exit 1 }
foreach p $positions { puts $p }
''' % {
        'decode': os.path.join(HERE, 'app-media-decode.tcl'),
        'lesson': os.path.join(HERE, 'app-media-lesson.tcl'),
        'edges': ' '.join('{%d %d}' % (f, t) for f, t in edges),
    }
    out = subprocess.run(['tclsh'], input=tcl, text=True,
                          capture_output=True)
    if out.returncode != 0:
        print('TCL FAILED:', out.stderr.strip())
        return None
    return out.stdout.strip().splitlines()


def checkpoint_edges(wmv):
    """Extract the LAST checkpoint's edges via the Tcl sidecar decoder."""
    txt = os.path.splitext(wmv)[0] + '.txt'
    tcl = r'''
source {%(decode)s}
set sd [::media::decoder::sidecar-parse {%(txt)s}]
set cps [dict get $sd checkpoints]
set cp [::media::decoder::parse-checkpoint [lindex [lindex $cps end] 2]]
if {[dict exists $cp error]} { puts stderr [dict get $cp error]; exit 1 }
foreach e [dict get $cp edges] { lassign $e f t; puts "$f $t" }
''' % {'decode': os.path.join(HERE, 'app-media-decode.tcl'), 'txt': txt}
    out = subprocess.run(['tclsh'], input=tcl, text=True,
                          capture_output=True)
    if out.returncode != 0:
        print('TCL checkpoint extraction failed:', out.stderr.strip())
        return None
    edges = [tuple(int(x) for x in line.split())
             for line in out.stdout.strip().splitlines()]
    return edges


def main():
    edges = checkpoint_edges(WMV)
    if not edges:
        return 1
    print('edges: %d' % len(edges))

    sans, positions, legal = wp2.walk(edges, ep_mode='fen')
    if not legal:
        print('python-chess walk failed')
        return 1
    print('python-chess positions: %d' % len(positions))

    tcl_fens = tcl_positions(edges)
    if tcl_fens is None:
        return 1
    print('Tcl applier positions: %d' % len(tcl_fens))

    if len(tcl_fens) != len(positions):
        print('FAIL: position count mismatch (%d vs %d)'
              % (len(tcl_fens), len(positions)))
        return 1

    mismatches = 0
    for i, (a, b) in enumerate(zip(positions, tcl_fens)):
        if a != b:
            mismatches += 1
            if mismatches <= 5:
                print('MISMATCH at %d:\n  python: %s\n  tcl:    %s' % (i, a, b))
    if mismatches:
        print('FAIL: %d/%d FENs mismatch' % (mismatches, len(positions)))
        return 1

    print('GATE WP3 (FEN byte-match): PASS (%d/%d positions)'
          % (len(positions), len(positions)))
    return 0


if __name__ == '__main__':
    sys.exit(main())