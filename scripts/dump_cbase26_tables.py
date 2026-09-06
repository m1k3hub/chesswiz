#!/usr/bin/env python3
"""Dump ChessBase 26's runtime-built 2CBH Move16 tables from process memory.

Launches CBase26.exe under Wine as a ptrace-able child (kernel yama
ptrace_scope=1 only allows attaching to descendants), waits for the
tables to be built (they are constructed at process startup), then
dumps the relevant regions from /proc/<pid>/mem:

  - DAT_141ad7110  decode table, 512 KiB   -> /tmp/decode_table.bin
  - DAT_141b57110  encode table,   8 MiB   -> /tmp/encode_table.bin
  - DAT_142376de0  960 Chess960 start positions (128 bytes each)
  - DAT_142394de0  standard start position bitboards

Prerequisites: wine with ChessBase 26 installed, Xvfb (or any display),
ptrace permission for child processes.

Usage: python3 scripts/dump_cbase26_tables.py [--wait SECONDS]
"""

import ctypes
import sys
import time
import ctypes
import os
import subprocess
import sys
import time

CBASE_DIR = os.path.expanduser(
    "~/.wine/drive_c/Program Files/ChessBase/CBase26")
IMAGE_BASE = 0x140000000

REGIONS = {
    "decode_table.bin": (0x141ad7110, 512 * 1024),
    "encode_table.bin": (0x141b57110, 8 * 1024 * 1024),
    "pos960.bin":       (0x142376de0, 960 * 128),
    "variant_tables.bin": (0x141a783c0, 0x141a7a9c0 - 0x141a783c0),
}


def find_target():
    for pid in subprocess.run(["pgrep", "-x", "CBase26.exe"],
                              capture_output=True, text=True).stdout.split():
        try:
            with open(f"/proc/{pid}/maps") as f:
                if "141ad5000" in f.read():  # BSS region of the main module
                    return int(pid)
        except OSError:
            pass
    return None


def main() -> int:
    wait = 35
    if "--wait" in sys.argv:
        wait = int(sys.argv[sys.argv.index("--wait") + 1])
    display = os.environ.get("DUMP_DISPLAY", ":77")

    env = dict(os.environ, DISPLAY=display, WINEDEBUG="-all")
    subprocess.Popen(
        ["wine64", "CBase26.exe"], cwd=CBASE_DIR,
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(wait)

    target = find_target()
    if target is None:
        print("CBase26.exe with expected image layout not found")
        return 1

    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.ptrace(16, target, 0, 0)  # PTRACE_ATTACH
    os.waitpid(target, os.WUNTRACED)
    try:
        with open(f"/proc/{target}/mem", "rb") as mem:
            for name, (addr, size) in REGIONS.items():
                mem.seek(addr)
                data = mem.read(size)
                with open(f"/tmp/{name}", "wb") as out:
                    out.write(data)
                nz = sum(1 for b in data if b)
                print(f"{name}: {size} bytes from {addr:#x} "
                      f"(nonzero bytes: {nz})")
    finally:
        libc.ptrace(17, target, 0, 0)  # PTRACE_DETACH
    return 0


CBASE_DIR = "/home/michael-g-thomas/.wine/drive_c/Program Files/ChessBase/CBase26"


if __name__ == "__main__":
    raise SystemExit(main())