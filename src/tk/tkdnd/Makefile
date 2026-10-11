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

include ../../../Makefile.in

.SUFFIXES: .c
.PRECIOUS:

INCLUDE	= $(TCL_INCLUDE) $(TK_INCLUDE) $(X_INCLUDE) -I../tk$(TCL_VERSION)
CFLAGS	+= $(OPTIMIZE) $(PROFILING) $(C_DEBUG) $(SYS_CFLAGS) -DUSE_TKINT_H

ifeq ($(TARGET_WINDOWS),yes)
CFLAGS += -DUNICODE -D_UNICODE -DPACKAGE_NAME=\"tkDND\" -DPACKAGE_VERSION=\"3.0\"
SRC = win/TkDND_OleDND.cpp
OBJS = TkDND_OleDND.o
else ifeq ($(TARGET_MACOS),yes)
CFLAGS += -DPACKAGE_NAME=\"tkDND\" -DPACKAGE_VERSION=\"3.0\"
SRC = macosx/macdnd.m
OBJS = macdnd.o
else
SRC = unix/TkDND_XDND.c unix/Cursors.c
OBJS = TkDND_XDND.o Cursors.o
endif
LIB	= libtkDnd

all: $(LIB).a

clean:
	@rm -f $(LIB).a $(OBJS) Makefile.bak

depend:
#	makedepend -fMakefile -Y -- -I../tk$(TCL_VERSION) -- -w1 $(SRC) 2>/dev/null
#	@if [ -h Makefile.bak ]; then \
#		cp Makefile Makefile.bak; \
#		mv Makefile.bak Makefile; \
#	fi

$(LIB).a: $(OBJS)
	@echo "Building $(LIB).a"
	@$(AR) $(ARFLAGS) $(LIB).a $(OBJS)
	@$(RANLIB) $(LIB).a

TkDND_XDND.o: unix/TkDND_XDND.c
	@echo "Compiling `awk 'BEGIN { printf "%-30s", "$<" }'`  [$(CFLAGS:  = )]"
	@$(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $(INCLUDE) $< -o $@

Cursors.o: unix/Cursors.c
	@echo "Compiling `awk 'BEGIN { printf "%-30s", "$<" }'`  [$(CFLAGS:  = )]"
	@$(CC) -c $(CFLAGS) $(EXTRA_CFLAGS) $(INCLUDE) $< -o $@

# vi:set ts=3 sw=3:

TkDND_OleDND.o: win/TkDND_OleDND.cpp
	$(CXX) -c $(CFLAGS) $(INCLUDE) $< -o $@

macdnd.o: macosx/macdnd.m
	$(CC) -c $(CFLAGS) $(INCLUDE) $< -o $@
