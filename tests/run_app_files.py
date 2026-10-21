#!/usr/bin/env python3
"""Run app test files in fresh processes/homes, with a deadline per file.

Linux uses a separate Xvfb/Openbox display per file. macOS uses a PTY for
Aqua stdout. Example (assertion timing budgets are unaffected):
  python3 tests/run_app_files.py --file-timeout test_app_media_fold.tcl=1200 \
      --file-timeout test_app_action_reachability_objects.tcl=2400
"""
import argparse
import concurrent.futures
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError('deadline must be a finite positive number')
    return seconds


def file_timeout(value):
    try:
        name, seconds = value.rsplit('=', 1)
        if not name or Path(name).name != name:
            raise ValueError('expected a test filename')
        return name, positive_seconds(seconds)
    except (ValueError, argparse.ArgumentTypeError) as error:
        raise argparse.ArgumentTypeError('expected FILE=POSITIVE_SECONDS') from error


def terminate_tree(process):
    # Only descendants of this runner's Popen are eligible. BSD script creates
    # another process group for its PTY, so killing one group is insufficient.
    listing = subprocess.check_output(['ps', '-axo', 'pid=,ppid='], text=True)
    pairs = [tuple(map(int, line.split())) for line in listing.splitlines()]
    descendants = {process.pid}
    while True:
        found = {pid for pid, parent in pairs if parent in descendants}
        if found <= descendants:
            break
        descendants.update(found)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in sorted(descendants, reverse=True):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        if sig == signal.SIGTERM:
            time.sleep(0.2)
    process.wait()


def run_file(test, args):
    deadline = dict(args.file_timeout).get(test.name, args.timeout)
    env = os.environ.copy()
    env['HOME'] = tempfile.mkdtemp(prefix=test.stem + '-home-', dir=args.output)
    command = [str(args.binary), str(ROOT / 'tests/run_app_tests.tcl'), '-file', test.name]
    if sys.platform == 'darwin':
        command = ['/usr/bin/script', '-q', '/dev/null', *command]
    else:
        command = ['xvfb-run', '-a', '-s', '-screen 0 1920x1200x24',
                   'bash', '-c',
                   'openbox > "$HOME/openbox.log" 2>&1 & wm_pid=$!; '
                   'trap \'kill "$wm_pid" 2>/dev/null\' EXIT; "$@"',
                   'app-test', *command]
    started = time.monotonic()
    log = args.output / (test.name + '.log')
    timed_out = False
    with log.open('w') as handle:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=handle,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=deadline)
        except subprocess.TimeoutExpired:
            timed_out = True
            terminate_tree(process)
            code = 124
    output = log.read_text(errors='replace').replace('\r', '')
    summary = {key: int(value) for key, value in re.findall(
        r'^Total (Passed|Failed|Skipped): (\d+)', output, re.M)}
    # Some script implementations don't propagate their child's exit code.
    # A missing final summary must never look like a pass.
    if not timed_out and (len(summary) != 3 or summary.get('Failed', 0)):
        code = code or 1
    result = dict(file=test.name, exit=code, timeout=timed_out,
                  deadline=deadline, seconds=round(time.monotonic() - started, 3),
                  summary={} if timed_out else summary,
                  failures=list(dict.fromkeys(re.findall(r'^==== (\S+) [^\n]* FAILED', output, re.M))))
    (args.output / (test.name + '.status')).write_text(str(code) + '\n')
    (args.output / (test.name + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    print('DONE', test.name, json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='*', help='test filenames (default: all test_app_*.tcl)')
    parser.add_argument('--timeout', type=positive_seconds, default=300, help='default seconds per file')
    parser.add_argument('--file-timeout', action='append', type=file_timeout, default=[], metavar='FILE=SECONDS')
    parser.add_argument('--jobs', type=int, default=1, help='concurrent files; keep 1 for Aqua/timing measurements')
    parser.add_argument('--output', type=Path, default=ROOT / 'tests/tmp-app/per-file')
    parser.add_argument('--binary', type=Path, default=ROOT / 'src/tkchesswiz')
    parser.add_argument('--no-build', action='store_true', help='use an already regenerated tcl/chesswiz')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    tests = [ROOT / 'tests' / Path(name).name for name in args.files] if args.files else sorted((ROOT / 'tests').glob('test_app_*.tcl'))
    if not tests or any(not test.is_file() for test in tests):
        parser.error('test files must exist in tests/')
    unknown = set(dict(args.file_timeout)) - {test.name for test in tests}
    if unknown:
        parser.error('deadline overrides do not match selected files: ' + ', '.join(sorted(unknown)))
    args.output = args.output.resolve()
    args.binary = args.binary.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.no_build:
        subprocess.run(['make', '-C', str(ROOT / 'tcl')], check=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda test: run_file(test, args), tests))
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    return int(any(result['exit'] for result in results))


if __name__ == '__main__':
    sys.exit(main())
