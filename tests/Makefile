# Makefile for Scidb Test Suite
# ======================================================================

SHELL := /bin/bash
TCLSH := tclsh
XVFB_RUN := xvfb-run -a </dev/null
# The classifier-mechanics tests use a stand-in classifier with no
# calibration; the calibration gate itself is tested with this unset
# (systemone-qualified in tests/test_app_systemone.tcl).
export SCIDB_AI_UNCALIBRATED := 1
CXX := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2

# Directories
TEST_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(abspath $(TEST_DIR)/..)
SRC_DIR := $(ROOT_DIR)/src
TCL_DIR := $(ROOT_DIR)/tcl

# Test files
TCL_TESTS := $(wildcard $(TEST_DIR)test_*.tcl)
CPP_TESTS := $(TEST_DIR)test_cpp_backend.cpp

# Output
TEST_REPORT := $(TEST_DIR)test_report.txt
COVERAGE_DIR := $(TEST_DIR)coverage

# ==============================================================================
# Targets
# ==============================================================================

# Targets share build outputs (test_cpp_backend, src/ test binaries) and
# fixed log paths, and the Tcl suite itself shells out to `make cpp`
# (test_audit_regressions.tcl).  Under `make -j` those would race: one
# job relinking or deleting what another is executing.  Run serially.
.NOTPARALLEL:

.PHONY: all test tcl app-tcl cpp cpp-src ai-tests chess-facts ai-facts ai-claims ai-engine ai-eco ai-generate ai-ui ai-tools ai-precedent ai-narrate ai-annotations ai-rhetoric corpus-tests clean help report

all: tcl app-tcl cpp ai-tests corpus-tests

# Conventional alias expected by many scripts and contributors.
test: all

# App-backed AI grounding suites. They need the tkscidb shell (app-only
# ::scidb::ai::* commands) and use their own pass/fail harness, so the
# plain-tclsh runner cannot run or count them. Run them here, sequentially,
# so `make test` / `make ci` actually gate on them.
AI_TESTS := chess-facts ai-facts ai-claims ai-engine ai-eco ai-generate ai-ui ai-tools ai-precedent ai-narrate ai-annotations ai-rhetoric ai-batch ai-calibrate ai-journal

ai-tests:
	@echo "Running AI grounding suites..."
	@for t in $(AI_TESTS); do \
		$(MAKE) --no-print-directory $$t || exit 1; \
	done

# Corpus tooling (Python; no app needed): precedent index and annotation extractor.
corpus-tests:
	@echo "Running corpus tests..."
	@python3 $(TEST_DIR)test_corpus_precedent.py
	@python3 $(TEST_DIR)test_annotation_extract.py
	@python3 $(TEST_DIR)test_annotation_index.py

# ==============================================================================
# Tcl Tests
# ==============================================================================

tcl: $(TEST_DIR)run_all.tcl
	@echo "Running Tcl test suite..."
	@set -o pipefail; $(TCLSH) $(TEST_DIR)run_all.tcl -verbose 2>&1 | tee $(TEST_REPORT)

tcl-quiet: $(TEST_DIR)run_all.tcl
	@$(TCLSH) $(TEST_DIR)run_all.tcl 2>&1

tcl-match:
	@$(TCLSH) $(TEST_DIR)run_all.tcl -match "$(PATTERN)"

app-tcl: $(TEST_DIR)run_app_tests.tcl $(TEST_DIR)run_app_driver.tcl
	@echo "Running app-backed Tcl test suite..."
	@$(MAKE) -C $(ROOT_DIR)/tcl chesswiz
	@rm -f $(TEST_DIR)app_test_report.txt
	@# A fresh home each run: the suite must not depend on the developer's
	@# saved layout and settings (~/.chesswiz), as on a CI machine.
	@rm -rf $(TEST_DIR)tmp-app/app-home && mkdir -p $(TEST_DIR)tmp-app/app-home
	@HOME=$(abspath $(TEST_DIR)tmp-app/app-home) $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)run_app_tests.tcl -verbose 2>&1 || true
	@grep -q "STATUS: PASSED" $(TEST_DIR)app_test_report.txt

# ==============================================================================
# C++ Tests
# ==============================================================================

smoke:
	@echo "Running headless startup smoke test..."
	@timeout 30 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)startup_smoke.tcl > /tmp/scidb-smoke.log 2>&1; \
		rc=$$?; cat /tmp/scidb-smoke.log; \
		if [ $$rc -eq 124 ]; then \
			echo "STARTUP-SMOKE: FAILED (hung, killed by timeout)"; exit 1; \
		fi; \
		if grep -q "STARTUP-SMOKE: OK" /tmp/scidb-smoke.log && ! grep -q "FAIL" /tmp/scidb-smoke.log \
			&& [ $$rc -eq 0 ]; then \
			exit 0; \
		fi; \
		echo "STARTUP-SMOKE: FAILED (exit $$rc)"; exit 1

SRC_CPP_TESTS := test_html_core test_scm_media test_scriptstream test_media_extract test_corr_moveinfo

# Chess anatomy fact extractor -- grounded JSON facts for the language layer.
# The probe is standalone, so it is built here rather than in src/.
chess-facts:
	@echo "Building probe_chess_facts..."
	@$(MAKE) -C $(SRC_DIR) probe_chess_facts >/tmp/scidb-chess-facts-build.log 2>&1 || \
		{ echo "FAIL: probe_chess_facts build"; tail -30 /tmp/scidb-chess-facts-build.log; exit 1; }
	@python3 $(TEST_DIR)test_chess_facts.py

# The same facts through the Tcl binding, exercised in the real app shell
# (needs Xvfb because tcl::init pulls in the Treectrl option machinery).
ai-facts:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-facts-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-facts-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_facts.tcl 2>&1 \
		| tee /tmp/scidb-ai-facts.log | grep -E "PASS|FAIL|AI-FACTS-FAILURES"
	@grep -q "AI-FACTS-FAILURES: 0" /tmp/scidb-ai-facts.log

# The claim checker: generated prose vs. grounded facts.
ai-claims:
	@echo "Building tkchesswiz and chesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-claims-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-claims-build.log; exit 1; }
	@$(MAKE) -C $(ROOT_DIR)/tcl >/tmp/scidb-ai-claims-tcl.log 2>&1 || \
		{ echo "FAIL: chesswiz build"; tail -30 /tmp/scidb-ai-claims-tcl.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_claims.tcl 2>&1 \
		| tee /tmp/scidb-ai-claims.log | grep -E "PASS|FAIL|AI-CLAIMS-FAILURES"
	@grep -q "AI-CLAIMS-FAILURES: 0" /tmp/scidb-ai-claims.log

# Engine facts: evaluation and move classification via a UCI engine.
ai-engine:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-engine-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-engine-build.log; exit 1; }
	@timeout 240 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_engine.tcl 2>&1 \
		| tee /tmp/scidb-ai-engine.log | grep -E "PASS|FAIL|SKIP|AI-ENGINE-FAILURES"
	@grep -q "AI-ENGINE-FAILURES: 0" /tmp/scidb-ai-engine.log

# Opening theory: ECO identification for a move line.
ai-eco:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-eco-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-eco-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_eco.tcl 2>&1 \
		| tee /tmp/scidb-ai-eco.log | grep -E "PASS|FAIL|AI-ECO-FAILURES"
	@grep -q "AI-ECO-FAILURES: 0" /tmp/scidb-ai-eco.log

# Grounded generation: prompt -> provider -> claim check -> retry (stub provider).
ai-generate:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-generate-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-generate-build.log; exit 1; }
	@timeout 200 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_generate.tcl 2>&1 \
		| tee /tmp/scidb-ai-generate.log | grep -E "PASS|FAIL|AI-GENERATE-FAILURES"
	@grep -q "AI-GENERATE-FAILURES: 0" /tmp/scidb-ai-generate.log

# UI wiring: HTML rendering and the asynchronous generate path.
ai-ui:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-ui-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-ui-build.log; exit 1; }
	@timeout 200 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_ui.tcl 2>&1 \
		| tee /tmp/scidb-ai-ui.log | grep -E "PASS|FAIL|AI-UI-FAILURES"
	@grep -q "AI-UI-FAILURES: 0" /tmp/scidb-ai-ui.log

# Engine-as-tool grounding (model calls Stockfish during generation).
ai-tools:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-tools-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-tools-build.log; exit 1; }
	@timeout 250 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_tools.tcl 2>&1 \
		| tee /tmp/scidb-ai-tools.log | grep -E "PASS|FAIL|SKIP|AI-TOOLS-FAILURES"
	@grep -q "AI-TOOLS-FAILURES: 0" /tmp/scidb-ai-tools.log

# Master-precedent evidence wired into the narration prompt.
ai-precedent:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-precedent-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-precedent-build.log; exit 1; }
	@timeout 250 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_precedent.tcl 2>&1 \
		| tee /tmp/scidb-ai-precedent.log | grep -E "PASS|FAIL|SKIP|AI-PRECEDENT-FAILURES"
	@grep -q "AI-PRECEDENT-FAILURES: 0" /tmp/scidb-ai-precedent.log

# Engine-native anatomy from the custom Stockfish fork (narrate).
ai-narrate:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-narrate-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-narrate-build.log; exit 1; }
	@timeout 250 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_narrate.tcl 2>&1 \
		| tee /tmp/scidb-ai-narrate.log | grep -E "PASS|FAIL|SKIP|AI-NARRATE-FAILURES"
	@grep -q "AI-NARRATE-FAILURES: 0" /tmp/scidb-ai-narrate.log

# The advisory rhetoric/coverage second opinion on generated prose.
ai-rhetoric:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-rhetoric-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-rhetoric-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_rhetoric.tcl 2>&1 \
		| tee /tmp/scidb-ai-rhetoric.log | grep -E "PASS|FAIL|SKIP|AI-RHETORIC-FAILURES"
	@grep -q "AI-RHETORIC-FAILURES: 0" /tmp/scidb-ai-rhetoric.log

# The decision / override journal that feeds threshold autotune.
ai-journal:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-journal-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-journal-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_journal.tcl 2>&1 \
		| tee /tmp/scidb-ai-journal.log | grep -E "PASS|FAIL|AI-JOURNAL-FAILURES"
	@grep -q "AI-JOURNAL-FAILURES: 0" /tmp/scidb-ai-journal.log

# The calibration math and the per-backend threshold file.
ai-calibrate:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-calibrate-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-calibrate-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_calibrate.tcl 2>&1 \
		| tee /tmp/scidb-ai-calibrate.log | grep -E "PASS|FAIL|AI-CALIBRATE-FAILURES"
	@grep -q "AI-CALIBRATE-FAILURES: 0" /tmp/scidb-ai-calibrate.log

# The batch helper: concurrency, dedupe, resume, progress, graceful fallback.
ai-batch:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-batch-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-batch-build.log; exit 1; }
	@timeout 120 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_batch.tcl 2>&1 \
		| tee /tmp/scidb-ai-batch.log | grep -E "PASS|FAIL|AI-BATCH-FAILURES"
	@grep -q "AI-BATCH-FAILURES: 0" /tmp/scidb-ai-batch.log

# Annotation exemplars joined to positions by key.
ai-annotations:
	@echo "Building tkchesswiz..."
	@$(MAKE) -C $(SRC_DIR) tkchesswiz >/tmp/scidb-ai-annotations-build.log 2>&1 || \
		{ echo "FAIL: tkchesswiz build"; tail -30 /tmp/scidb-ai-annotations-build.log; exit 1; }
	@timeout 250 $(XVFB_RUN) $(SRC_DIR)/tkchesswiz $(TEST_DIR)test_ai_annotations.tcl 2>&1 \
		| tee /tmp/scidb-ai-annotations.log | grep -E "PASS|FAIL|SKIP|AI-ANNOTATIONS-FAILURES"
	@grep -q "AI-ANNOTATIONS-FAILURES: 0" /tmp/scidb-ai-annotations.log

cpp: $(TEST_DIR)test_cpp_backend $(TEST_DIR)test_corr_duration tk-rangelist cpp-src
	@chmod +x "$(TEST_DIR)test_cpp_backend"
	@echo "Running C++ backend tests..."
	@"$(TEST_DIR)test_cpp_backend"
	@echo "Running correspondence-duration tests..."
	@chmod +x "$(TEST_DIR)test_corr_duration"
	@"$(TEST_DIR)test_corr_duration"

# Self-contained C++ unit tests that live in src/ and build through the main
# Makefile (html sanitizer, .scm/.cbm manifest parsers, script-stream decoder,
# media extraction, correspondence MoveInfo).  Each must exit non-zero on
# failure; noisy success output is captured and only the status is reported.
# The text widget's range lists against a model (src/tk/text/tkRangeList.c).
TK_RANGELIST_INC := -I$(SRC_DIR)/tk/text -I$(SRC_DIR)/tk/tk8.6 -I$(SRC_DIR)/tk \
	-I/usr/include/tcl8.6 -I/usr/include/tcl8.6/tk-private/generic -I/usr/include/tcl8.6/tk-private/unix \
	-I/usr/include/tcl8.6/tcl-private/generic -I/usr/include/tcl8.6/tcl-private/unix
tk-rangelist:
	@echo "Running text widget range list tests..."
	@gcc -std=gnu99 $(TK_RANGELIST_INC) -o /tmp/scidb-test-tk-rangelist $(TEST_DIR)test_tk_rangelist.c \
		$(SRC_DIR)/tk/text/tkRangeList.c -ltcl8.6 -ltk8.6
	@/tmp/scidb-test-tk-rangelist | tail -1; /tmp/scidb-test-tk-rangelist >/dev/null

cpp-src:
	@echo "Building src/ self-contained C++ tests..."
	@$(MAKE) -C $(SRC_DIR) $(SRC_CPP_TESTS) test_sci_result >/tmp/scidb-cpp-src-build.log 2>&1 || \
		{ echo "FAIL: src/ C++ test build"; tail -30 /tmp/scidb-cpp-src-build.log; exit 1; }
	@echo "Running src/ self-contained C++ tests..."
	@for t in $(SRC_CPP_TESTS); do \
		log=/tmp/scidb-test-$$t.log; \
		if "$(SRC_DIR)/$$t" >$$log 2>&1; then \
			echo "PASS: $$t"; \
		else \
			echo "FAIL: $$t"; tail -20 $$log; exit 1; \
		fi; \
	done
	@d=$$(mktemp -d "$${TMPDIR:-/tmp}/scidb-sci-result.XXXXXX") || exit 1; \
	if "$(SRC_DIR)/test_sci_result" $$d >/tmp/scidb-test-sci-result.log 2>&1; then \
		rm -rf "$$d"; echo "PASS: test_sci_result"; \
	else \
		rm -rf "$$d"; echo "FAIL: test_sci_result"; tail -20 /tmp/scidb-test-sci-result.log; exit 1; \
	fi

$(TEST_DIR)test_corr_duration: $(TEST_DIR)test_corr_duration.cpp
	@echo "Compiling correspondence-duration tests..."
	@$(CXX) $(CXXFLAGS) \
		-I$(SRC_DIR) -I$(SRC_DIR)/db -I$(SRC_DIR)/sys -I$(SRC_DIR)/util -I$(SRC_DIR)/mstl \
		-o $@ $< \
		$(SRC_DIR)/db/libdb.a $(SRC_DIR)/util/libutil.a $(SRC_DIR)/sys/libsys.a $(SRC_DIR)/mstl/libmstl.a -lz


$(TEST_DIR)test_cpp_backend: $(CPP_TESTS)
	@echo "Compiling C++ tests..."
	@$(CXX) $(CXXFLAGS) \
		-I$(SRC_DIR) \
		-I$(SRC_DIR)/db \
		-I$(SRC_DIR)/sys \
		-I$(SRC_DIR)/util \
		-I$(SRC_DIR)/mstl \
		-I/usr/include/tcl8.6 \
		-o $@ $< \
		$(SRC_DIR)/db/libdb.a \
		$(SRC_DIR)/util/libutil.a \
		$(SRC_DIR)/sys/libsys.a \
		$(SRC_DIR)/mstl/libmstl.a \
		$(SRC_DIR)/util/libTeXt/libTeXt.a \
		$(SRC_DIR)/util/libharu/libharu.a \
		$(SRC_DIR)/util/libhyphenate/libhyphenate.a \
		$(SRC_DIR)/util/universalchardet/libchardet.a \
		$(SRC_DIR)/util/minizip/libminizip.a \
		-ltcl8.6 -lexpat -lz -lpthread

# ==============================================================================
# Individual Test Targets
# ==============================================================================

test-core:
	@echo "=== Core Tests ==="
	@$(TCLSH) $(TEST_DIR)/test_core.tcl

test-database:
	@echo "=== Database Tests ==="
	@$(TCLSH) $(TEST_DIR)/test_database.tcl

test-widgets:
	@echo "=== Widget Tests ==="
	@$(TCLSH) $(TEST_DIR)/test_widgets.tcl

test-export:
	@echo "=== Export Tests ==="
	@$(TCLSH) $(TEST_DIR)/test_export.tcl

test-board:
	@echo "=== Board Tests ==="
	@$(TCLSH) $(TEST_DIR)/test_board.tcl

# ==============================================================================
# Coverage (requires tcov/tclcov)
# ==============================================================================

coverage: 
	@echo "Note: Coverage requires tclcov or similar tool"
	@echo "Install with: tlmgr install tclcov"
	@# tclcov -output $(COVERAGE_DIR) $(TEST_DIR)/run_all.tcl

# ==============================================================================
# CI/CD Integration
# ==============================================================================

ci: clean tcl app-tcl cpp report ai-tests corpus-tests
	@echo "CI build complete"

report: $(TEST_REPORT)
	@echo "Test report generated: $(TEST_REPORT)"

$(TEST_REPORT): 
	@$(TCLSH) $(TEST_DIR)run_all.tcl > $@ 2>&1 || true

# ==============================================================================
# Cleanup
# ==============================================================================

clean:
	@echo "Cleaning test artifacts..."
	@rm -rf $(TEST_DIR)tmp/*
	@rm -f $(TEST_DIR)test_cpp_backend
	@rm -f $(TEST_REPORT)
	@rm -rf $(COVERAGE_DIR)
	@find $(TEST_DIR) -name "*.tcl~" -delete
	@find $(TEST_DIR) -name "*.log" -delete

distclean: clean
	@rm -rf $(TEST_DIR)__pycache__
	@rm -rf $(TEST_DIR).pytest_cache

# ==============================================================================
# Help
# ==============================================================================

help:
	@echo "Scidb Test Suite"
	@echo "================"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Run all tests (Tcl + C++)"
	@echo "  tcl          - Run Tcl tests only"
	@echo "  cpp          - Run C++ tests only"
	@echo "  test-core    - Run core utility tests"
	@echo "  test-database- Run database operation tests"
	@echo "  test-widgets - Run widget tests (requires X11)"
	@echo "  test-export  - Run import/export tests"
	@echo "  test-board   - Run board/position tests"
	@echo "  ci           - Run all tests for CI/CD"
	@echo "  report       - Generate test report"
	@echo "  coverage     - Generate coverage report"
	@echo "  clean        - Remove test artifacts"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  PATTERN=xxx  - Filter tests by pattern (e.g., make tcl-match PATTERN=db*)"
	@echo ""
	@echo "Examples:"
	@echo "  make tcl                    # Run all Tcl tests"
	@echo "  make tcl-match PATTERN=move # Run only move-related tests"
	@echo "  make test-database          # Run database tests only"
	@echo "  make ci                     # Full CI build"

# Linux credential file backend and mocked OS-store migration.
.PHONY: ai-credentials
ai-credentials:
	@$(TCLSH) $(TEST_DIR)test_ai_credentials.tcl

.PHONY: tactics
tactics:
	$(TCLSH) $(TEST_DIR)test_tactics_trainer.tcl
