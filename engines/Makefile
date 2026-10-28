# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================
# Makefile for Scidb for Unix operating systems
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

include ../Makefile.in

ENGINES_ALL       = $(ENGINES:%=all-%)
ENGINES_CLEAN     = $(ENGINES:%=clean-%)
ENGINES_INSTALL   = $(ENGINES:%=install-%)
ENGINES_UNINSTALL = $(ENGINES:%=uninstall-%)

.PHONY: all $(ENGINES_ALL) depend clean $(ENGINES_CLEAN) install $(ENGINES_INSTALL) uninstall $(ENGINES_UNINSTALL)

all: $(ENGINES_ALL)

$(ENGINES_ALL): all-%:
	@$(MAKE) -C $*

depend:
	# no action

clean: $(ENGINES_CLEAN)

$(ENGINES_CLEAN): clean-%:
	@$(MAKE) -C $* clean

install: $(ENGINES_INSTALL)
	@echo "Install engines"

$(ENGINES_INSTALL): install-%:
	@if [ -f "$*/Makefile" ]; then \
		$(MAKE) -C $* install; \
	else \
		echo "Skipping optional engine $*: sources not installed"; \
	fi

uninstall: $(ENGINES_UNINSTALL)
	@echo "Uninstall engines"

$(ENGINES_UNINSTALL): uninstall-%:
	@$(MAKE) -C $* uninstall

# vi:set ts=3 sw=3:
