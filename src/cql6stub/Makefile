CXX ?= g++
AR ?= ar
CXXFLAGS ?= -O2 -Wall -std=c++17 -pthread

all: libcql6stub.a

cql6_stub.o: CXXFLAGS += $(SANITIZE)
cql6_stub.o: cql6_stub.cpp ../cql6/cql6_api.h

libcql6stub.a: cql6_stub.o
	$(AR) rcs $@ $<

clean:
	rm -f cql6_stub.o libcql6stub.a harness harness-baseline

# Standalone real-Tcl verification; nothing here is shipped.
TCL_FLAGS ?= $(shell pkg-config --cflags tcl)
TCL_LIBS ?= $(shell pkg-config --libs tcl)
HARNESS_FLAGS = -DCQL6_STANDALONE -std=c++17 -g -pthread $(TCL_FLAGS)

harness: harness.cpp harness_fake.h ../tcl/tcl_cql6.cpp cql6_stub.cpp
	$(CXX) $(HARNESS_FLAGS) -O2 $(SANITIZE) harness.cpp cql6_stub.cpp $(TCL_LIBS) -o $@

harness-baseline: harness.cpp harness_fake.h roundtrip_baseline.cpp cql6_stub.cpp
	$(CXX) $(HARNESS_FLAGS) -DCQL6_ROUNDTRIP -O2 $(SANITIZE) harness.cpp cql6_stub.cpp $(TCL_LIBS) -o $@

check-harness: harness harness-baseline
	./harness-baseline baseline.tcl
	CQL6_BASELINE_RATES="$$(cat /tmp/cql6-baseline-rates)" CQL6_BASELINE_DUMP=/tmp/cql6-baseline-dump ./harness harness_tests.tcl

.PHONY: check-harness
