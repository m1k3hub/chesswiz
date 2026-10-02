#ifndef CQL6_API_H
#define CQL6_API_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { const char* name; const char* value; } cql6_tag;

/* one move record of the game tree of one game. kind:
 *   0 = a move of the current line
 *   1 = start of a variation (it replaces the move just before it); the next records are its moves
 *   2 = end of the current variation (back to the line it came from)
 *   3 = explicit null move (analysis skip); from, to and promo must all be 0
 * from/to are squares 0..63 (a1=0, b1=1, ... h8=63). promo is 0 or one of 'Q','R','B','N'.
 * comment may be NULL. */
typedef struct { int kind; int from; int to; int promo; const char* comment; } cql6_move;

/* one game, filled in by the host. All memory belongs to the host and must stay valid until the
 * host is called again from the SAME library thread or the search ends. */
typedef struct {
    int         number;     /* host's game number (returned with matches); may be any int >= 0 */
    const char* fen;        /* start position, NULL = the standard start position */
    int         ntags;  const cql6_tag*  tags;   /* White Black Event Site Date Round Result WhiteElo ... */
    int         nmoves; const cql6_move* moves;
} cql6_game;

/* Called by the library to get the next game. Return 1 and fill *g, or 0 when there are no more.
 * The library serialises these calls with its own mutex: the host need not be thread safe.
 * `thread` (0..threads-1) identifies the calling worker. */
typedef int (*cql6_next_fn)(void* ctx, int thread, cql6_game* g);

typedef struct {
    int threads;        /* 0 = automatic (hardware threads - 1), 1 = single thread */
    int variations;     /* 1 = also search variations (like the -variations option) */
    int max_matches;    /* 0 = no limit */
    int want_pgn;       /* 1 = return the annotated PGN of every match */
    void (*test_hook)(int game_number, int thread_idx); /* internal hook for testing, NULL for normal use */
    int trusted_moves;  /* 1 only for host-validated normalised moves; default 0 validates legality */
    int lazy_features;  /* 1 computes position state only when the parsed script uses it */
    int additional_script_count; /* 0 = single script; at most 1023 additional scripts */
    const char* const* additional_scripts; /* searched on the same prepared games, in array order */
    void (*prepare_feed)(void* ctx, int variations); /* optional: called after parsing, before next;
                                                       publishes the script set's required variation mode */
    int truncate_illegal_moves; /* PGN compatibility: keep legal prefix on illegal move;
                                   default 0 rejects the game; ignored in trusted mode */
} cql6_options;

typedef struct { int game_number; int first_ply; char* pgn; int script_index; } cql6_match;
    /* first_ply: mainline ply (0 = start position) of the first position that got the match
       comment, -1 if no mainline annotation is emitted (variation-only or comment limits).
       pgn: malloc'd, NULL unless want_pgn. */

typedef struct {
    int         nmatches;  cql6_match* matches;    /* grouped by script_index, each independently sorted;
                                                   max_matches applies to each script */
    long        ngames;                            /* games examined */
    int         threads_used;
    char*       messages;                          /* malloc'd text the script printed (e.g. persistent variables), or NULL */
    long        nskipped;                          /* games the feed could not accept (corrupt or illegal data:
                                                      bad FEN, illegal move, unbalanced variation records, empty
                                                      variation, too many tags, position limit exceeded, ...).
                                                      Skipped games are NOT counted in ngames; the search continues.
                                                      If EVERY supplied game was skipped, cql6_search returns an error. */
    long        ntruncated;                        /* accepted legal prefixes in PGN compatibility mode */
} cql6_result;

/* Returns 0 on success (result filled, free with cql6_free_result), else non-zero and a message in
 * err[errlen] (syntax error, runtime assert, ...). NEVER exits, aborts or writes to stdout. */
int  cql6_search(const char* script_text, const cql6_options* opt, cql6_next_fn next, void* ctx,
                 cql6_result* out, char* err, size_t errlen);
void cql6_free_result(cql6_result* r);
const char* cql6_version(void);     /* e.g. "6.2 build 9.493" */

#ifdef __cplusplus
}
#endif

#endif /* CQL6_API_H */
