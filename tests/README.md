# Scidb Test Suite

Comprehensive test framework for the Scidb chess database application.

## Quick Start

```bash
# Run all tests
cd tests
make all

# Run Tcl tests only
make tcl

# Run C++ tests only  
make cpp

# Run specific test category
make test-database
make test-core
make test-board

# Run tests matching pattern
make tcl-match PATTERN="db*"
```

## Test Structure

```
tests/
├── run_all.tcl                # Main test runner
├── test_framework.tcl         # Test utilities and assertions
├── test_core.tcl              # Core utilities (move, game, comment)
├── test_database.tcl          # Database operations
├── test_widgets.tcl           # Tk widget tests
├── test_export.tcl            # Import/export tests
├── test_board.tcl             # Board/position tests
├── test_source_contracts.tcl  # Source-level bug pattern scanning
├── test_audit_regressions.tcl # Audit regression guards
├── test_cli_smoke.tcl         # CLI converter smoke tests
├── test_cpp_backend.cpp       # C++ backend tests
└── Makefile                   # Build and run targets
```

## Test Categories

### 1. Core Tests (`test_core.tcl`)
- Move parsing and validation
- Comment handling
- Game state management
- Utility functions (CRC32, filename sanitization)

### 2. Database Tests (`test_database.tcl`)
- Database creation/open/close
- PGN import
- Game queries
- Database modifications
- Maintenance operations (vacuum, verify)

### 3. Widget Tests (`test_widgets.tcl`)
- Custom widget creation
- Dialog operations
- Event bindings
- Geometry management
- **Note:** Requires X11 display

### 4. Export Tests (`test_export.tcl`)
- PGN import/export
- Format validation (PGN, FEN, EPD)
- Encoding handling
- Beta feature gating

### 5. Board Tests (`test_board.tcl`)
- FEN parsing
- Position validation
- Move generation patterns
- Check/checkmate/stalemate detection

### 6. Source Contract Tests (`test_source_contracts.tcl`)
Headless source-level scanning — no backend or Tk required. Reads C++ and Tcl
source files and asserts absence of known bug patterns. Acts as both:
- **Regression guards** for fixed bugs (should always pass)
- **Defect detectors** for open bugs (fail until bug is fixed)

Covers: new[]/delete mismatches, VLAs, `.empty()` vs `.size()`, string
constant typos, Makefile target consistency, extension handling gaps,
undefined Tcl variables, shell injection patterns, sprintf baseline.

Reference: BUG_LOG_2026-04-04.md (Bugs #1-#28).

### 7. Audit Regression Tests (`test_audit_regressions.tcl`)
Encode verified intended behavior from the 2026-04-09 audit (A1-A5).
Expected to fail until underlying defects are fixed.

### 8. CLI Smoke Tests (`test_cli_smoke.tcl`)
Lightweight checks for converter entry points (`cdb2sci`, `cbh2si4`).
Verifies `--help` output and basic flag handling.
Also runs `verify_cbh_write` when that binary has been built locally.

### 9. C++ Backend Tests (`test_cpp_backend.cpp`)
- UTF-8 string operations
- Levenshtein distance
- Database creation/import
- PGN parsing
- Variant handling

### 10. C++ Source Unit Tests (`make cpp-src`)
Built through the main `src/Makefile` and run by `make cpp` (and therefore by
`make all`/`make test`). Each must exit non-zero on failure; noisy success
output is captured and only `PASS:`/`FAIL:` is reported.

| Binary (in `src/`) | Covers |
|--------------------|--------|
| `test_html_core` | HTML sanitizer / structural repair / ChessBase adapter |
| `test_scm_media` | `.scm` manifest parser (fingerprint, classify, corrupt input) |
| `test_scriptstream` | ChessBase media script-stream decoder |
| `test_media_extract` | Guiding-text media extraction and path resolution |
| `test_corr_moveinfo` | Correspondence clock / elapsed MoveInfo parsing |
| `test_sci_result` | `.sci` result-field sanitization (5/6/7) |

## Requirements

### Tcl Tests
- Tcl 8.5+
- Tk 8.5+ (for widget tests)
- tcltest 2.5+

### C++ Tests
- GCC 7+ or compatible C++17 compiler
- Tcl development headers
- Compiled Scidb libraries

## Running Tests

### Full Test Suite
```bash
make all
```

### Verbose Output
```bash
tclsh run_all.tcl -verbose
```

### Filtered Tests
```bash
tclsh run_all.tcl -match "db*"
tclsh run_all.tcl -match "move*"
make tcl-match PATTERN="*import*"
```

### CI/CD Integration
```bash
make ci
cat tests/test_report.txt
```

## Writing New Tests

### Tcl Test Example
```tcl
tcltest::test my-feature-01 {Test description} -setup {
    # Setup code (runs before each test)
    set testVar "value"
} -body {
    # Test code
    set result [myFunction $testVar]
    assertEq $result "expected"
} -cleanup {
    # Cleanup code (runs after each test)
    unset testVar
} -result 1
```

### C++ Test Example
```cpp
TEST(test_my_feature)
{
    // Arrange
    MyClass obj;
    
    // Act
    auto result = obj.doSomething();
    
    // Assert
    ASSERT_EQ(expected, result);
    
    std::cout << "PASS: test_my_feature" << std::endl;
}
```

## Assertion Helpers

| Function | Description |
|----------|-------------|
| `assertEq actual expected` | Equality check |
| `assertNe actual expected` | Inequality check |
| `assertTrue value` | Boolean true check |
| `assertFalse value` | Boolean false check |
| `assertExists path` | File/directory exists |
| `assertNotExists path` | File/directory doesn't exist |
| `assertMatch value pattern` | Glob pattern match |
| `assertLength list expected` | List length check |

## Known Limitations

1. **Widget Tests**: Require X11 display. Skip in headless environments:
   ```bash
   xvfb-run make test-widgets
   ```

2. **Export Tests**: Current export tests are still lightweight and do not yet validate full HTML/PDF/TeX output generation end-to-end.

3. **C++ Tests**: Require compiled libraries. Run `make` in `src/` first.

4. **Database Tests**: Create temporary files in `tests/tmp/`

5. **CBH Round-Trip Smoke**: `test_cli_smoke.tcl` will skip the `verify_cbh_write` check unless `src/verify_cbh_write` has been built.

## Coverage

Coverage reporting requires additional tools:
```bash
# Install tclcov
tlmgr install tclcov

# Run with coverage
make coverage
```

## Troubleshooting

### "No test files found"
Ensure test files are named `test_*.tcl` in the `tests/` directory.

### Widget tests fail with "couldn't connect to display"
Run with virtual framebuffer:
```bash
xvfb-run -a make test-widgets
```

### C++ tests won't compile
Ensure Scidb libraries are built:
```bash
cd src && make
cd ../tests && make cpp
```

### Tests hang indefinitely
Check for unclosed databases or leaked resources. Each test should cleanup in `-cleanup` block.

## Continuous Integration

Add to your CI pipeline:
```yaml
test:
  script:
    - cd tests
    - make ci
  artifacts:
    reports:
      junit: tests/test_report.xml
```

## License

Same license as Scidb main project (GPL v2+).

## Isolated app files on Linux and macOS

`python3 tests/run_app_files.py` regenerates `tcl/chesswiz` and runs each
`test_app_*.tcl` in a fresh process and HOME. Linux requires Xvfb, xauth and
Openbox; each file gets its own display. Aqua output is captured through a
PTY. Set `SCIDB_SHAREDIR` to the app Resources directory when using a bundle.
The default is serial execution with a 300-second deadline **per file**.

```sh
python3 tests/run_app_files.py --output tests/tmp-app/per-file \
  --file-timeout test_app_action_reachability.tcl=2400 \
  --file-timeout test_app_action_reachability_objects.tcl=3600 \
  --file-timeout test_app_media_fold.tcl=1800
```

Use `--timeout SECONDS` for the default, or repeat `--file-timeout FILE=SECONDS`
for expensive files. These limits do not change any assertion's timing budget.
`--jobs N` allows independent files concurrently; use `--jobs 1` for timing
measurements or shared Aqua sessions. `--no-build` uses a script already
regenerated from the current sources. Logs, exit statuses and JSON results are
written per file; a deadline never contributes partial totals. A missing final
summary or a failed assertion fails the runner even if the PTY exits zero.
