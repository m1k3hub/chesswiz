include ../makefile-flags

%.o: %.cpp ${MYHEADERS}
	$(COMPILE) ${CPP_FLAGS} -I.. -o $@ -c $<

ORIGHEADERS=	attacks.h\
	bytebuf.h\
	common.h\
	date.h\
	dstring.h\
	error.h\
	filter.h\
	game.h\
	gfile.h\
	hash.h\
	index.h\
	matsig.h\
	mfile.h\
	misc.h\
	movelist.h\
	myassert.h\
	optable.h\
	pgnparse.h\
	position.h\
	sqlist.h\
	sqmove.h\
	sqset.h\
	stralloc.h\
	strtree.h\
	textbuf.h\
	tokens.h\
	tree.h

ORIGOBJS= \
	bytebuf.o\
	date.o\
	dstring.o\
	filter.o\
	game.o\
	gfile.o\
	index.o\
	matsig.o\
	mfile.o\
	misc.o\
	movelist.o\
	myassert.o\
	namebase.o\
	pgnparse.o\
	position.o\
	stored.o\
	stralloc.o\
	textbuf.o\
	tree.o

origstuff: ${ORIGOBJS}

