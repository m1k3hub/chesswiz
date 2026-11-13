#!/usr/bin/env python3
"""Recompute the pre-mission generated-tool inventory by running baseline Tcl.

Requires the configured Linux checkout, tkchesswiz and Xvfb. Only the baseline
Tcl bundle is rebuilt; the checkout's native executable supplies Tk/Scidb. No
current registrations or fixture allowlists determine snapshot membership.
"""
import argparse
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

BASELINE = '08ba7f1bb'
PROBE = r'''
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
tcltest::test generated-baseline-snapshot {read the baseline registry, excluding its legacy Actions table} -body {
    foreach id [lsort [::action::list]] {
        set r [::action::get $id]
        if {[dict get $r ai] ni {1 debug} || [dict exists $::application::assistant::Actions $id]} {continue}
        set fields [list $id [dict get $r ai] [dict get $r operator] [dict get $r confirm]]
        puts "BASELINE_GENERATED|[join $fields |]"
    }
    return {}
} -result {}
::tcltest::cleanupTests
'''


def generate(root, evidence):
    commit = subprocess.check_output(['git', 'rev-parse', BASELINE], cwd=root, text=True).strip()
    archive = subprocess.check_output(['git', 'archive', commit, 'tcl',
                                      'tests/run_app_tests.tcl', 'tests/app_actions_support.tcl'], cwd=root)
    with tempfile.TemporaryDirectory(prefix='cw-generated-snapshot-') as temporary:
        work = Path(temporary)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(work, filter='data')
        shutil.copyfile(root / 'Makefile.in', work / 'Makefile.in')
        (work / 'tests/generated_snapshot_probe.tcl').write_text(PROBE)
        build = subprocess.run(['make', '-C', str(work / 'tcl'), 'chesswiz'], capture_output=True, text=True)
        (evidence / 'baseline-build.log').write_text(build.stdout + build.stderr)
        build.check_returncode()
        home = work / 'home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), PULSE_SINK='cwtests', SCIDB_AI_DEBUG='1')
        try:
            run = subprocess.run(['flock', '/tmp/chesswiz-menu-reseal.lock', 'xvfb-run', '-a', '-s',
                                  '-screen 0 1920x1080x24', str(root / 'src/tkchesswiz'),
                                  'tests/run_app_tests.tcl', '-file', 'generated_snapshot_probe.tcl'],
                                 cwd=work, env=env, capture_output=True, text=True, timeout=180)
        finally:
            shutil.rmtree(home / '.chesswiz/cache', ignore_errors=True)
        (evidence / 'baseline-runtime.log').write_text(run.stdout + run.stderr)
        run.check_returncode()
        if 'Total Passed: 1' not in run.stdout or 'Total Failed: 0' not in run.stdout:
            raise RuntimeError('baseline probe did not pass')
        tools = []
        for line in run.stdout.splitlines():
            if line.startswith('BASELINE_GENERATED|'):
                _, name, ai, operator, confirm = line.split('|')
                tools.append(dict(name=name, ai=int(ai) if ai != 'debug' else ai,
                                  operator=int(operator), confirm=int(confirm)))
        if not tools or len({r['name'] for r in tools}) != len(tools):
            raise RuntimeError('empty or duplicate snapshot')
        return dict(commit=commit, derivation='baseline registry ai in {1 debug}, excluding baseline assistant::Actions', tools=tools)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path(__file__).with_name('assistant-generated-baseline.json'))
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parent.parent
    snapshot = generate(root, args.evidence)
    args.output.write_text(json.dumps(snapshot, indent=2) + '\n')
    print(f"{snapshot['commit']}: {len(snapshot['tools'])} generated tools -> {args.output}")


if __name__ == '__main__':
    main()
