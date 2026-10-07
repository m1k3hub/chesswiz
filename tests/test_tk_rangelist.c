/*
 * The bundled text widget's range lists (src/tk/text/tkRangeList.c),
 * checked against a plain model of the integers they hold: Add is a set
 * union, Insert shifts every integer >= low up by the span and adds the
 * range, Delete removes the range and shifts every integer > high down
 * (tkRangeList.h). The lists must stay sorted, with no two ranges touching.
 *
 * Found by driving the app: leaving trial mode and transposing a game made
 * the notation editor's text widget fail its range list assertions.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tkRangeList.h"

#define N 4000

static int failures = 0;

void assertionFailed(char const* expr, char const* file, unsigned line, char const* func) {
    printf("FAIL: assertion %s (%s:%u) [%s]\n", expr, file, line, func);
    exit(1);
}

static char model[N], tmp[N];

static int agrees(const TkRangeList *r) {
    char got[N];
    memset(got, 0, N);
    for (unsigned i = 0; i < r->size; ++i) {
	if (i && r->items[i-1].high + 1 >= r->items[i].low) { return 0; }
	for (int k = r->items[i].low; k <= r->items[i].high; ++k) { if (k >= 0 && k < N) { got[k] = 1; } }
    }
    return memcmp(got, model, N) == 0;
}

static void check(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) { failures += 1; }
}

int main(void) {
    /* the case the editor hit: a shifted range next to an untouched one */
    TkRangeList *r = TkRangeListCreate(4);
    r = TkRangeListAdd(r, 1, 2);
    r = TkRangeListAdd(r, 5, 10);
    r = TkRangeListDelete(r, 4, 6);
    check(r->size == 2 && r->items[1].low == 4 && r->items[1].high == 7 && r->count == 6,
	"Delete shifts a range past an untouched one once");
    TkRangeListClear(r);

    /* a range overlapping the deleted block from below keeps its lower part */
    r = TkRangeListAdd(r, 3, 6);
    r = TkRangeListDelete(r, 5, 8);
    check(r->size == 1 && r->items[0].low == 3 && r->items[0].high == 4, "Delete keeps [low', low-1]");
    TkRangeListClear(r);

    /* Add extends both ends of a range it overlaps */
    r = TkRangeListAdd(r, 72, 74);
    r = TkRangeListAdd(r, 79, 97);
    r = TkRangeListAdd(r, 70, 77);
    check(r->size == 2 && r->items[0].low == 70 && r->items[0].high == 77, "Add raises the upper bound too");
    TkRangeListClear(r);

    for (unsigned seed = 1; seed <= 12; ++seed) {
	int ok = 1;
	srand(seed);
	memset(model, 0, N);
	TkRangeListClear(r);
	for (int step = 0; step < 50000 && ok; ++step) {
	    int op = rand() % 3, lo = rand() % 150, hi = lo + rand() % 8, span = hi - lo + 1;
	    if (op == 0) {
		r = TkRangeListAdd(r, lo, hi);
		for (int k = lo; k <= hi; ++k) { model[k] = 1; }
	    } else if (op == 1) {
		memset(tmp, 0, N);
		for (int k = 0; k < N; ++k) { if (model[k]) { int t = k >= lo ? k + span : k; if (t < N) { tmp[t] = 1; } } }
		for (int k = lo; k <= hi; ++k) { tmp[k] = 1; }
		memcpy(model, tmp, N);
		r = TkRangeListInsert(r, lo, hi);
	    } else {
		memset(tmp, 0, N);
		for (int k = 0; k < N; ++k) { if (model[k]) { if (k < lo) { tmp[k] = 1; } else if (k > hi) { tmp[k - span] = 1; } } }
		memcpy(model, tmp, N);
		r = TkRangeListDelete(r, lo, hi);
	    }
	    ok = agrees(r);
	    if (r->size > 30 || (r->size && r->items[r->size-1].high > 1000)) { TkRangeListClear(r); memset(model, 0, N); }
	}
	char what[64];
	snprintf(what, sizeof what, "50000 random operations, seed %u", seed);
	check(ok, what);
    }

    printf("TK-RANGELIST-FAILURES: %d\n", failures);
    return failures != 0;
}
