# Pi harness setup — isolation + code intelligence

This records the two harness gaps closed on this machine, so they are discoverable
and reversible. Nothing here is MCP; all of it is native pi extensions/skills plus a
project config file.

## 1. Code intelligence (harness-wide, auto-loaded)

**`~/.pi/agent/extensions/code-intel.ts`** registers two native tools:

| Tool | Does | Backend |
|---|---|---|
| `code_diagnostics(path)` | real diagnostics for one file | `clangd --check` (C/C++), `pyright` (Python), `gopls check` (Go), `rust-analyzer diagnostics` (Rust) |
| `code_symbols(name, root?)` | definitions across a tree | Universal Ctags (`ctags -x -R`) |

It auto-loads globally (it sits beside the existing extensions), so every session in
every project gets it. No network, no extra auth, no process boundary.

**`compile_flags.txt`** (repo root) is what makes clangd work — without it clangd
cannot resolve `db_board.h`, `m_string.h`, etc. Verified:

```bash
cd /media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex
clangd --check=src/db/db_chess_facts.cpp     # "Loaded compilation database from .../compile_flags.txt"
```

For exact build flags instead of a curated list, install `bear` and run
`bear -- make -C src` to generate `compile_commands.json` (clangd prefers it).

Smoke test during setup (temporary harness, since removed): loaded the extension with a
fake `pi`, captured the registered tools, and ran `code_diagnostics` on a clean file
(no diagnostics) and a deliberately broken one (`[expected_expression] Line 1`), plus
`code_symbols ChessFacts` (found the class at `src/db/db_chess_facts.h:37`).

## 2. Authority gate (removed)

`permission-gate.ts` was installed to prompt before `rm -rf`, `sudo`, and
`chmod/chown 777` — but it was itself a *capability reduction* (it blocks those in
non-interactive mode and interrupts interactive work). Removed on request; nothing
else depends on it. Re-add with:

```bash
cp <pi-pkg>/examples/extensions/permission-gate.ts ~/.pi/agent/extensions/
```

## 3. Isolation (opt-in, NOT auto-loaded)

**`~/.pi/agent/sandbox/gondolin/`** — the Gondolin micro-VM extension (`@earendil-works/gondolin`,
deps installed, `npm audit` clean). It is deliberately kept out of the auto-load
directory so it cannot hijack every session.

**`~/.local/bin/pi-sandbox`** — launcher:

```bash
cd /path/to/project
pi-sandbox                 # pi with all built-in tools + ! routed into a micro-VM
```

Auth/keys stay on the host; the project cwd is mounted at `/workspace` and writes
pass through. Requires QEMU (`/dev/kvm` present on this box for acceleration).

Alternative whole-process isolation (simplest), from `docs/containerization.md`:

```bash
docker run --rm -it -e ANTHROPIC_API_KEY \
  -v "$PWD:/workspace" -v pi-agent-home:/root/.pi/agent pi-sandbox
```

Use a **named volume** for `/root/.pi/agent`, not a host mount — mounting host
`~/.pi/agent` leaks auth and sessions into the container.

## Revert

```bash
rm ~/.pi/agent/extensions/code-intel.ts
rm -rf ~/.pi/agent/sandbox/gondolin
rm ~/.local/bin/pi-sandbox
rm <repo>/compile_flags.txt
```

## Not done (deliberately)

- No MCP servers were installed. Pi has no MCP by design; the capability lives in
  native extensions, which are lower-latency, auditable, and add no credential surface.
- Gondolin is not on the default path. Auto-loading a micro-VM for every session
  would change how all tools run; isolation is opt-in per session.
