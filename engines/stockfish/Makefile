# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================
# Stockfish 19 for Scidb -- the engine installed as stockfish-chesswiz.
#
# The sources are the official sf_19 release (src/, scripts/) plus the
# Scidb "narrate" UCI command (src/narration.*, see BUILD.md). Stockfish's
# own src/Makefile does the build; this file only fits it into Scidb's
# engines/Makefile (all, clean, install, uninstall, depend).
#
# The build embeds the network named in src/evaluate.h; src/Makefile
# downloads it into src/ when it is missing (scripts/net.sh needs curl or
# wget). For an offline build, put the .nnue file into src/ first.
#
# SF_ARCH selects the CPU target of Stockfish's Makefile; empty means
# "native", right for the machine that builds and installs. Packagers
# building for other machines set a portable one, e.g.
#   make SF_ARCH=x86-64-avx2
# ======================================================================

include ../../Makefile.in

EXE		= stockfish-chesswiz
SF_ARCH	=

SF_MAKE	= $(MAKE) -C src $(if $(SF_ARCH),ARCH=$(SF_ARCH))

.PHONY: all build clean install uninstall depend

all: build

build:
	@echo "Building Stockfish 19 $(if $(SF_ARCH),($(SF_ARCH)),(native))"
	@$(SF_MAKE) build
	@cp -p src/stockfish $(EXE)

clean:
	@echo "Clean `pwd`"
	@$(MAKE) -C src clean >/dev/null
	@rm -f $(EXE)

install:
ifneq ($(wildcard $(EXE)),)
	@install -m 755 -d $(ENGINESDIR)
	@install -m 755 -p $(EXE) $(ENGINESDIR)
	@rm -f $(ENGINESDIR)/$(subst -chesswiz,-scidb,$(EXE))
else
	@echo "Skipping optional engine $(EXE): not built"
endif

uninstall:
	@rm -f $(ENGINESDIR)/$(EXE)

depend:
	@# Stockfish's Makefile tracks its own dependencies

# vi:set ts=3 sw=3:
