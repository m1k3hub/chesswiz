"""Deadline/exit-status regressions without loading Tk or a display server."""
import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('app_files', Path(__file__).with_name('run_app_files.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class AppFilesTests(unittest.TestCase):
    def test_reused_output_is_not_complete_while_new_run_is_active(self):
        with tempfile.TemporaryDirectory() as directory:
            aggregate = Path(directory) / 'results.json'
            aggregate.write_text('[{"exit": 1}]')
            def active_file(test, args):
                self.assertFalse(aggregate.exists(), 'stale completion marker is visible to waiting consumers')
                return {'exit': 0}
            argv = ['run_app_files.py', '--no-build', '--output', directory, 'test_app_ask.tcl']
            with patch.object(sys, 'argv', argv), patch.object(runner, 'run_file', side_effect=active_file):
                self.assertEqual(runner.main(), 0)
            self.assertEqual(json.loads(aggregate.read_text()), [{'exit': 0}])

    def test_deadlines_must_be_bounded_positive_numbers(self):
        for value in ('0', '-1', 'nan', 'inf'):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                runner.positive_seconds(value)
        self.assertEqual(runner.file_timeout('test_app_example.tcl=900'), ('test_app_example.tcl', 900))

    def run_child(self, source, default=2, overrides=()):
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(output=Path(directory), binary=Path('/unused'),
                                      timeout=default, file_timeout=overrides)
            real_popen = subprocess.Popen
            def child(*command, **options):
                if command[0][0] == 'ps':
                    return real_popen(*command, **options)
                return real_popen([sys.executable, '-c', source], **options)
            with patch.object(runner.subprocess, 'Popen', side_effect=child), contextlib.redirect_stdout(io.StringIO()):
                return runner.run_file(Path('test_app_example.tcl'), args)

    def test_override_completes_every_assertion_after_default_deadline(self):
        source = "import time; time.sleep(.15); print('Total Passed: 7\\nTotal Failed: 0\\nTotal Skipped: 0')"
        result = self.run_child(source, default=.05, overrides=[('test_app_example.tcl', 2)])
        self.assertEqual(result['exit'], 0)
        self.assertEqual(result['summary']['Passed'], 7)
        self.assertEqual(result['deadline'], 2)

    def test_timeout_does_not_report_partial_totals(self):
        result = self.run_child("import time; print('Total Passed: 1', flush=True); time.sleep(10)", default=.1)
        self.assertEqual(result['exit'], 124)
        self.assertTrue(result['timeout'])
        self.assertEqual(result['summary'], {})

    def test_child_success_without_complete_summary_is_a_failure(self):
        self.assertEqual(self.run_child("print('Total Passed: 1')")['exit'], 1)

    def test_summary_failure_overrides_pty_success(self):
        result = self.run_child("print('Total Passed: 1\\nTotal Failed: 2\\nTotal Skipped: 0')")
        self.assertEqual(result['exit'], 1)


    def test_cleanup_leaves_unrelated_processes_alive(self):
        neighbour = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        source = ("import subprocess,sys,time; "
                  "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                  "print(child.pid, flush=True); time.sleep(30)")
        process = subprocess.Popen([sys.executable, '-c', source], stdout=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            child_pid = int(process.stdout.readline())
            runner.terminate_tree(process)
            state = subprocess.run(['ps', '-p', str(child_pid), '-o', 'stat='],
                                   capture_output=True, text=True).stdout.strip()
            self.assertTrue(not state or state.startswith('Z'), state)
            self.assertIsNone(neighbour.poll())
        finally:
            if process.poll() is None:
                runner.terminate_tree(process)
            process.stdout.close()
            neighbour.terminate()
            neighbour.wait()


if __name__ == '__main__':
    unittest.main()
