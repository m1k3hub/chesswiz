#!/usr/bin/env python3
"""Compare native TSV results with a separately built pristine CQL executable."""
import argparse
import pathlib
import subprocess

NAMES = ("twic_complete", "CCRL-4040", "LumbrasGigabase_OTB")
BODIES = ("check", "mate", "initial", "terminal", "[a]<=6",
          "move previous enpassant", 'sort "material" ([a]<=6)')

def rows(path):
    return [tuple(map(int, line.split())) for line in path.read_text().splitlines() if line.strip()]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("generate", "compare"), required=True)
    parser.add_argument("--inputs", type=pathlib.Path, required=True)
    parser.add_argument("--results", type=pathlib.Path, required=True)
    parser.add_argument("--oracle", type=pathlib.Path)
    parser.add_argument("--driver", type=pathlib.Path, default=pathlib.Path("src/cql6/build/native_oracle"))
    args = parser.parse_args()
    args.results.mkdir(parents=True, exist_ok=True)
    failures = 0
    for name in NAMES:
        mapping = [int(line) for line in (args.inputs / f"{name}.indices").read_text().splitlines()]
        if len(mapping) != 20000 or len(set(mapping)) != 20000:
            raise ValueError(f"{name}: invalid export index mapping")
        for variations in (0, 1):
            for index, body in enumerate(BODIES):
                oracle_file = args.results / f"{name}-{variations}-oracle-{index}.tsv"
                if args.mode == "generate":
                    if not args.oracle:
                        parser.error("--oracle required for generation")
                    run = subprocess.run([str(args.driver.resolve()), str(args.oracle.resolve()),
                                          str((args.inputs / f"{name}.pgn").resolve()), body, str(variations)],
                                         capture_output=True, text=True)
                    if run.returncode:
                        failures += 1
                        oracle_file.unlink(missing_ok=True)
                        print(f"FAIL {name} vars={variations} script={index}: oracle exit {run.returncode}\n{run.stderr}", flush=True)
                        continue
                    mapped = []
                    for line in run.stdout.splitlines():
                        number, ply = map(int, line.split())
                        if not 1 <= number <= len(mapping):
                            raise ValueError(f"invalid oracle game number {number}")
                        mapped.append(f"{mapping[number-1]}\t{ply}\n")
                    oracle_file.write_text("".join(mapped))
                    print(f"oracle {name} vars={variations} script={index} matches={len(mapped)}", flush=True)
                else:
                    expected = rows(oracle_file)
                    for threads in (1, 8):
                        native = rows(args.results / f"{name}-{variations}-{threads}-{index}.tsv")
                        if native != expected:
                            failures += 1
                            extra = sorted(set(native) - set(expected))[:10]
                            missing = sorted(set(expected) - set(native))[:10]
                            print(f"FAIL {name} vars={variations} threads={threads} script={index}: "
                                  f"native={len(native)} oracle={len(expected)} extra={extra} missing={missing}", flush=True)
                        else:
                            print(f"PASS {name} vars={variations} threads={threads} script={index} matches={len(native)}", flush=True)
    return 1 if failures else 0

if __name__ == "__main__":
    raise SystemExit(main())
