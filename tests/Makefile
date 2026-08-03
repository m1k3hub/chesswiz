# Makefile for Scidb Test Suite
# ======================================================================

SHELL := /bin/bash
TCLSH := tclsh
XVFB_RUN := xvfb-run -a
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

.PHONY: all test tcl app-tcl cpp clean help report

all: tcl app-tcl cpp

# Conventional alias expected by many scripts and contributors.
test: all

# ==============================================================================
# Tcl Tests
# ==============================================================================

tcl: $(TEST_DIR)run_all.tcl
	@echo "Running Tcl test suite..."
	@$(TCLSH) $(TEST_DIR)run_all.tcl -verbose 2>&1 | tee $(TEST_REPORT)

tcl-quiet: $(TEST_DIR)run_all.tcl
	@$(TCLSH) $(TEST_DIR)run_all.tcl 2>&1

tcl-match:
	@$(TCLSH) $(TEST_DIR)run_all.tcl -match $(PATTERN)

app-tcl: $(TEST_DIR)run_app_tests.tcl $(TEST_DIR)run_app_driver.tcl
	@echo "Running app-backed Tcl test suite..."
	@$(MAKE) -C $(ROOT_DIR)/tcl scidb-beta
	@rm -f $(TEST_DIR)app_test_report.txt
	@$(XVFB_RUN) $(SRC_DIR)/tkscidb-beta $(TEST_DIR)run_app_tests.tcl -verbose 2>&1 || true
	@grep -q "STATUS: PASSED" $(TEST_DIR)app_test_report.txt

# ==============================================================================
# C++ Tests
# ==============================================================================

cpp: $(TEST_DIR)test_cpp_backend
	@chmod +x "$(TEST_DIR)test_cpp_backend"
	@echo "Running C++ backend tests..."
	@"$(TEST_DIR)test_cpp_backend"

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

ci: clean tcl app-tcl cpp report
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
