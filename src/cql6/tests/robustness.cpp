// scidb: Task 3 §C — feed robustness tests. Run under ASan/UBSan as a gate.
//
// Every case feeds hostile cql6_game structures through cql6_search and requires:
//  - no crash, no hang, no sanitizer report
//  - an unacceptable game is SKIPPED and counted in cql6_result::nskipped while
//    the search goes on (good games still match exactly as when run alone)
//  - a systemic problem (every game rejected) returns an error
#include "feed_common.h"
#include <random>
#include <climits>

static int g_failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { printf("[FAIL] "); printf(__VA_ARGS__); printf("\n"); g_failures++; } } while (0)

// ---- helpers -------------------------------------------------------------

struct OwnedGame {
    int number = 0;
    std::string fen;
    std::vector<std::pair<std::string, std::string>> tags;
    std::vector<cql6_move> moves;
    std::vector<std::string> comments;
};

// a valid game: 1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 (Ruy Lopez, no mate) and a scholar's mate game
static OwnedGame makeValidGame(int number, bool mateGame) {
    OwnedGame g;
    g.number = number;
    g.tags.emplace_back("White", "A");
    g.tags.emplace_back("Black", "B");
    g.tags.emplace_back("Result", mateGame ? "1-0" : "*");
    auto mv = [&](int from, int to, int promo = 0) {
        cql6_move m; m.kind = 0; m.from = from; m.to = to; m.promo = promo; m.comment = nullptr;
        g.moves.push_back(m);
    };
    if (!mateGame) {
        // 1.e4 e5 2.Nf3 Nc6 3.Bb5 a6
        mv(12, 28); mv(52, 36); mv(6, 21); mv(57, 42); mv(5, 33); mv(48, 40);
    } else {
        // 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6?? 4.Qxf7#
        mv(12, 28); mv(52, 36); mv(5, 26); mv(57, 42); mv(3, 39); mv(62, 45); mv(39, 53);
    }
    return g;
}

struct FeedMany {
    std::vector<const OwnedGame*> games;
    std::vector<std::vector<cql6_tag>> tagbufs; // per-game stable tag arrays
    size_t next = 0;
};

static int feedMany(void* ctx, int thread, cql6_game* g) {
    (void)thread;
    FeedMany* fm = (FeedMany*)ctx;
    if (fm->next >= fm->games.size()) return 0;
    size_t idx = fm->next++;
    const OwnedGame* og = fm->games[idx];
    g->number = og->number;
    g->fen = og->fen.empty() ? nullptr : og->fen.c_str();
    fm->tagbufs.resize(fm->games.size());
    auto& tb = fm->tagbufs[idx];
    tb.resize(og->tags.size());
    for (size_t i = 0; i < og->tags.size(); ++i) {
        tb[i].name = og->tags[i].first.c_str();
        tb[i].value = og->tags[i].second.c_str();
    }
    g->ntags = (int)og->tags.size();
    g->tags = tb.empty() ? nullptr : tb.data();
    g->nmoves = (int)og->moves.size();
    g->moves = og->moves.empty() ? nullptr : og->moves.data();
    return 1;
}

struct RawFeed {
    std::vector<cql6_game> games; // raw, possibly hostile structs
    size_t next = 0;
};
static int feedRaw(void* ctx, int thread, cql6_game* g) {
    (void)thread;
    RawFeed* rf = (RawFeed*)ctx;
    if (rf->next >= rf->games.size()) return 0;
    *g = rf->games[rf->next++];
    return 1;
}

static int searchGames(std::vector<cql6_game>& raw, cql6_result* res, char* err, size_t errlen,
                       const char* script = "mate", int threads = 2, int variations = 0) {
    RawFeed rf;
    rf.games = raw;
    cql6_options opt;
    memset(&opt, 0, sizeof(opt));
    opt.threads = threads;
    opt.variations = variations;
    return cql6_search(script, &opt, feedRaw, &rf, res, err, errlen);
}

// --------------------------------------------------------------------------

int main(int argc, char** argv) {
    int threads = (argc > 1) ? atoi(argv[1]) : 2;
    printf("== Task3 §C feed robustness (threads=%d) ==\n", threads);

    // baseline: two valid games alone, one of them a mate game
    std::set<int> baselineMatches;
    {
        OwnedGame a = makeValidGame(1, false), b = makeValidGame(2, true);
        std::vector<cql6_game> raw(2);
        FeedMany fm; fm.games = {&a, &b};
        cql6_options opt; memset(&opt, 0, sizeof(opt)); opt.threads = threads;
        cql6_result res; char err[1024]; err[0] = 0;
        int rc = cql6_search("mate", &opt, feedMany, &fm, &res, err, sizeof err);
        CHECK(rc == 0, "baseline search failed: %s", err);
        for (int i = 0; i < res.nmatches; ++i) baselineMatches.insert(res.matches[i].game_number);
        CHECK(baselineMatches == std::set<int>({2}), "baseline should match game 2 only");
        cql6_free_result(&res);
    }

    // helper: one hostile game + the valid pair; expect rc==0, nskipped==1, matches=={2}
    auto expectSkip = [&](const char* name, cql6_game hostile, int expectSkipped = 1) {
        OwnedGame a = makeValidGame(1, false), b = makeValidGame(2, true);
        RawFeed rf;
        std::vector<cql6_tag> tagstore;
        rf.games.push_back(*&hostile);
        // convert valid games to raw
        std::vector<std::vector<cql6_tag>> tbs(2);
        cql6_game ga, gb;
        auto fill = [&](OwnedGame& og, cql6_game& g, std::vector<cql6_tag>& tb) {
            g.number = og.number;
            g.fen = og.fen.empty() ? nullptr : og.fen.c_str();
            tb.resize(og.tags.size());
            for (size_t i = 0; i < og.tags.size(); ++i) { tb[i].name = og.tags[i].first.c_str(); tb[i].value = og.tags[i].second.c_str(); }
            g.ntags = (int)tb.size(); g.tags = tb.data();
            g.nmoves = (int)og.moves.size(); g.moves = og.moves.data();
        };
        fill(a, ga, tbs[0]);
        fill(b, gb, tbs[1]);
        rf.games.push_back(ga);
        rf.games.push_back(gb);
        cql6_options opt; memset(&opt, 0, sizeof(opt)); opt.threads = threads;
        cql6_result res; char err[1024]; err[0] = 0;
        int rc = cql6_search("mate", &opt, feedRaw, &rf, &res, err, sizeof err);
        if (rc != 0) {
            printf("[FAIL] %s: search returned error: %s\n", name, err);
            g_failures++;
        } else {
            std::set<int> got;
            for (int i = 0; i < res.nmatches; ++i) got.insert(res.matches[i].game_number);
            CHECK(res.nskipped == expectSkipped, "%s: nskipped=%ld expected %d", name, res.nskipped, expectSkipped);
            CHECK(got == baselineMatches, "%s: matches differ from baseline", name);
        }
        cql6_free_result(&res);
        (void)tagstore;
    };

    // 1. tags of 1 MB
    {
        std::string huge(1000000, 'X');
        OwnedGame g = makeValidGame(100, true);
        g.tags.emplace_back("HugeTag", huge);
        g.tags[0].second = huge; // 1MB White name too
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err);
        CHECK(rc == 0 && res.nmatches == 1, "1MB tags: rc=%d nmatches=%d err=%s", rc, res.nmatches, err);
        cql6_free_result(&res);
    }

    // 2. comment of 500k characters
    {
        std::string huge(500000, 'c');
        OwnedGame g = makeValidGame(101, true);
        g.comments.push_back(huge);
        g.moves[0].comment = g.comments.back().c_str();
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err);
        CHECK(rc == 0 && res.nmatches == 1, "500k comment: rc=%d nmatches=%d err=%s", rc, res.nmatches, err);
        cql6_free_result(&res);
    }

    // 3. tag name with embedded NUL/newline/quotes/braces/non-UTF8 bytes
    {
        std::string name("Ta\0g\"{[<nasty>\n\xff\xfe\x80]", 20);
        std::string val("va\0lue\"\n{]}\xc3\x28\xbf", 15);
        OwnedGame g = makeValidGame(102, true);
        g.tags.emplace_back(name, val);
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err);
        CHECK(rc == 0 && res.nmatches == 1, "nasty tag name: rc=%d nmatches=%d err=%s", rc, res.nmatches, err);
        cql6_free_result(&res);
    }

    // 4. 5000-ply game (king march; legal back-and-forth)
    {
        OwnedGame g; g.number = 103;
        g.tags.emplace_back("Result", "*");
        // Kf1-e1-e2-e1... plus black king shuffle: build 5000 legal plies with two kings alternating
        g.fen = "4k3/8/8/8/8/8/8/4K3 w - - 0 1";
        auto mv = [&](int from, int to) { cql6_move m; m.kind=0; m.from=from; m.to=to; m.promo=0; m.comment=nullptr; g.moves.push_back(m); };
        // white king shuttles e1(4)<->d1(3), black king e8(60)<->d8(59): 1250*4 = 5000 plies
        for (int i = 0; i < 1250; ++i) {
            mv(4, 3); mv(60, 59); mv(3, 4); mv(59, 60);
        }
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = g.fen.c_str(); rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err, "check");
        CHECK(rc == 0 && res.ngames == 1 && res.nskipped == 0, "5000-ply: rc=%d ngames=%ld nskipped=%ld err=%s", rc, res.ngames, res.nskipped, err);
        cql6_free_result(&res);
    }

    // 5a. variation depth 1000 (nested), variations off: accepted; variations on: accepted or skipped, never crash
    {
        OwnedGame g;
        g.number = 104;
        g.tags.emplace_back("Result", "*");
        g.fen = "4k3/8/8/8/8/8/8/4K3 w - - 0 1"; // kings only: every white king move below is legal
        std::vector<cql6_move> deep;
        auto mk = [&](int kind, int from, int to) { cql6_move m; m.kind=kind; m.from=from; m.to=to; m.promo=0; m.comment=nullptr; deep.push_back(m); };
        mk(0, 4, 3);            // mainline Kd1
        for (int d = 0; d < 999; ++d) {
            mk(1, 0, 0);        // variation replacing the previous (white) move...
            mk(0, 4, (d & 1) ? 12 : 5); // ...with Ke2 or Kf1 (again from the start position)
        }
        for (int d = 0; d < 999; ++d) mk(2, 0, 0); // close all 999 variations
        g.moves = deep;
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = g.fen.c_str(); rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err, "check", threads, 0);
        CHECK(rc == 0 && res.ngames == 1, "var depth 1000 (var off): rc=%d ngames=%ld err=%s", rc, res.ngames, err);
        cql6_free_result(&res);
        rc = searchGames(v, &res, err, sizeof err, "check", threads, 1);
        CHECK(rc == 0, "var depth 1000 (var on): rc=%d err=%s", rc, err);
        printf("  var depth 1000 (var on): ngames=%ld nskipped=%ld\n", res.ngames, res.nskipped);
        cql6_free_result(&res);
    }

    // 5b-i. 250 sibling variations x ~210 plies each (100000-variation-record scale):
    // variations off -> accepted; variations on -> QPos pool guard skips it, never crashes
    {
        OwnedGame g;
        g.number = 105;
        g.tags.emplace_back("Result", "*");
        g.fen = "4k3/8/8/8/8/8/8/4K3 w - - 0 1"; // kings only, legal shuttles everywhere
        auto mk = [&](std::vector<cql6_move>& v, int kind, int from, int to) {
            cql6_move m; m.kind=kind; m.from=from; m.to=to; m.promo=0; m.comment=nullptr; v.push_back(m);
        };
        // mainline: Kd1 Kf8 Ke1 Kg8 (black shuttles e8-f8 so the variation shuttles are legal)
        mk(g.moves, 0, 4, 3); mk(g.moves, 0, 60, 61); mk(g.moves, 0, 3, 4); mk(g.moves, 0, 61, 60);
        // 250 sibling variations replacing the last mainline move, each ~210 plies of king shuttle
        for (int i = 0; i < 250; ++i) {
            mk(g.moves, 1, 0, 0);
            mk(g.moves, 0, 61, 52); // Kf8-e7 replaces the last mainline move
            for (int r = 0; r < 52; ++r) {
                mk(g.moves, 0, 4, 3); mk(g.moves, 0, 52, 53);
                mk(g.moves, 0, 3, 4); mk(g.moves, 0, 53, 52);
            }
            mk(g.moves, 0, 4, 3); mk(g.moves, 0, 52, 53);
            mk(g.moves, 2, 0, 0);
        }
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = g.fen.c_str(); rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        printf("  5b-i: %d variation records\n", rawg.nmoves);
        cql6_result res; char err[1024];
        std::vector<cql6_game> v{rawg};
        int rc = searchGames(v, &res, err, sizeof err, "check", threads, 0);
        CHECK(rc == 0 && res.ngames == 1 && res.nskipped == 0, "huge siblings (var off): rc=%d ngames=%ld nskipped=%ld err=%s", rc, res.ngames, res.nskipped, err);
        cql6_free_result(&res);
        // variations ON: the game exceeds the QPos pool and must be SKIPPED (not crash).
        // Feed it together with a valid mate game so the search continues past the skip.
        OwnedGame mateG = makeValidGame(2, true);
        cql6_game rawm; std::vector<cql6_tag> tbm(mateG.tags.size());
        for (size_t i = 0; i < mateG.tags.size(); ++i) { tbm[i].name = mateG.tags[i].first.c_str(); tbm[i].value = mateG.tags[i].second.c_str(); }
        rawm.number = mateG.number; rawm.fen = nullptr; rawm.ntags = (int)tbm.size(); rawm.tags = tbm.data();
        rawm.nmoves = (int)mateG.moves.size(); rawm.moves = mateG.moves.data();
        std::vector<cql6_game> v2{rawg, rawm};
        rc = searchGames(v2, &res, err, sizeof err, "mate", threads, 1);
        CHECK(rc == 0 && res.nskipped == 1 && res.nmatches == 1 && res.matches[0].game_number == 2,
              "huge siblings (var on): rc=%d nskipped=%ld nmatches=%d err=%s", rc, res.nskipped, res.nmatches, err);
        cql6_free_result(&res);
    }

    // 5b-ii. 300 sibling variations on ONE move: Scid's moveT::numVariations is a byte and
    // AddVariation() has no limit check (upstream removed MAX_VARS_PER_MOVE) -> would wrap and
    // corrupt the tree. The feed must reject the game instead.
    {
        OwnedGame g = makeValidGame(116, false); // ... 3.Bb5 a6
        std::vector<cql6_move> wide = g.moves;
        cql6_move vs; vs.kind = 1; vs.from = 0; vs.to = 0; vs.promo = 0; vs.comment = nullptr;
        cql6_move ve; ve.kind = 2; ve.from = 0; ve.to = 0; ve.promo = 0; ve.comment = nullptr;
        cql6_move vm; vm.kind = 0; vm.from = 51; vm.to = 43; vm.promo = 0; vm.comment = nullptr; // d7-d6 instead of a6
        for (int i = 0; i < 300; ++i) { wide.push_back(vs); wide.push_back(vm); wide.push_back(ve); }
        g.moves = wide;
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        expectSkip("300-sibling-variations", rawg);
    }

    // 6. kind 2 with no open variation / unbalanced / bad kind
    {
        OwnedGame g = makeValidGame(106, true);
        cql6_move e; e.kind = 2; e.from = 0; e.to = 0; e.promo = 0; e.comment = nullptr;
        g.moves.insert(g.moves.begin() + 2, e);
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        expectSkip("kind2-without-variation", rawg);
    }
    {
        cql6_move m; m.kind = 0; m.from = 12; m.to = 28; m.promo = 0; m.comment = nullptr;
        cql6_game rawg; memset(&rawg, 0, sizeof rawg);
        rawg.number = 107; rawg.nmoves = 1; rawg.moves = &m;
        rawg.ntags = 0; rawg.tags = nullptr;
        // unclosed variation: kind 1 at end
        cql6_move vs[2] = {m, m};
        vs[1].kind = 1;
        rawg.moves = vs; rawg.nmoves = 2;
        expectSkip("unclosed-variation", rawg);
        // unknown kind
        vs[1].kind = 7;
        expectSkip("unknown-kind", rawg);
    }

    // 7. squares -1 / 64 / INT_MAX
    for (int sq : {-1, 64, INT_MAX}) {
        cql6_move m; m.kind = 0; m.from = sq; m.to = 28; m.promo = 0; m.comment = nullptr;
        cql6_game rawg; memset(&rawg, 0, sizeof rawg);
        rawg.number = 108; rawg.nmoves = 1; rawg.moves = &m;
        expectSkip(("square " + std::to_string(sq)).c_str(), rawg);
        m.from = 12; m.to = sq;
        expectSkip(("to-square " + std::to_string(sq)).c_str(), rawg);
    }

    // 8. illegal move / null move / promotion nonsense
    {
        cql6_move m; m.kind = 0; m.from = 12; m.to = 60; m.promo = 0; m.comment = nullptr; // e2-e8 illegal
        cql6_game rawg; memset(&rawg, 0, sizeof rawg);
        rawg.number = 109; rawg.nmoves = 1; rawg.moves = &m;
        expectSkip("illegal-move", rawg); // also the position.cpp AssertPos sites: skipped, not dead
        m.from = 12; m.to = 12; // "null move" from a pawn square
        expectSkip("null-move-pawn", rawg);
        m.from = 52; m.to = 36; m.promo = 'X'; // bad promo char
        expectSkip("bad-promo-char", rawg);
        m.promo = 'Q'; m.from = 52; m.to = 36; // promo on a non-promotion pawn move
        expectSkip("impossible-promo", rawg);
    }

    // 9. ntags/nmoves negative or huge with NULL arrays
    {
        cql6_game rawg; memset(&rawg, 0, sizeof rawg);
        rawg.number = 110;
        rawg.ntags = -5; rawg.tags = nullptr;
        expectSkip("negative-ntags", rawg);
        rawg.ntags = 0;
        rawg.nmoves = -3; rawg.moves = nullptr;
        expectSkip("negative-nmoves", rawg);
        rawg.nmoves = INT_MAX; rawg.moves = nullptr;
        expectSkip("huge-nmoves-null", rawg);
        rawg.nmoves = 0;
        rawg.ntags = INT_MAX; rawg.tags = nullptr;
        expectSkip("huge-ntags-null", rawg);
        rawg.ntags = 5; rawg.tags = nullptr;
        expectSkip("ntags-5-null-array", rawg);
        rawg.ntags = 1000; // > MAX_TAGS
        cql6_tag t{"A", "B"};
        rawg.tags = &t;
        expectSkip("ntags-over-maxtags", rawg);
        rawg.number = -7; rawg.ntags = 0; rawg.tags = nullptr; rawg.nmoves = 0; rawg.moves = nullptr;
        expectSkip("negative-number", rawg);
    }

    // 10. FEN garbage / empty / impossible position
    {
        const char* fens[] = {
            "total garbage fen !!!",
            "",
            "8/8/8/8/8/8/8/8 w - - 0 1",                 // no kings: impossible
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // valid start
            "4k3/8/8/8/8/8/8/4K2R w K - 0 1",            // valid
            "4k3/8/8/8/8/8/8/4K3 b - - 999999 1000000", // absurd counters
        };
        for (const char* f : fens) {
            OwnedGame g = makeValidGame(111, true);
            g.fen = f;
            cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
            for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
            rawg.number = g.number; rawg.fen = (f[0] == '\0') ? f : f; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
            rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
            cql6_result res; char err[1024];
            std::vector<cql6_game> v{rawg};
            int rc = searchGames(v, &res, err, sizeof err);
            // either the game is accepted (valid FENs) or skipped (bad ones); never a crash,
            // and a single-game feed that is rejected must return the systemic error
            bool accepted = (rc == 0 && res.ngames == 1);
            bool skippedSystemic = (rc != 0 && strlen(err) > 0);
            CHECK(accepted || skippedSystemic, "fen '%.30s': rc=%d ngames=%ld err=%.60s", f, rc, res.ngames, err);
            cql6_free_result(&res);
        }
        // NULL fen + garbage FEN tag
        OwnedGame g = makeValidGame(112, true);
        g.tags.emplace_back("FEN", "not a fen at all $$$");
        cql6_game rawg; std::vector<cql6_tag> tb(g.tags.size());
        for (size_t i = 0; i < g.tags.size(); ++i) { tb[i].name = g.tags[i].first.c_str(); tb[i].value = g.tags[i].second.c_str(); }
        rawg.number = g.number; rawg.fen = nullptr; rawg.ntags = (int)tb.size(); rawg.tags = tb.data();
        rawg.nmoves = (int)g.moves.size(); rawg.moves = g.moves.data();
        std::vector<cql6_game> v{rawg};
        cql6_result res; char err[1024];
        int rc = searchGames(v, &res, err, sizeof err);
        CHECK(rc != 0 || res.nskipped == 1, "garbage FEN tag must be rejected");
        cql6_free_result(&res);
    }

    // 11. fuzz: 200000 random cql6_game structures interleaved with valid games
    {
        printf("  fuzz: 200000 random structures interleaved with valid games...\n");
        std::mt19937 rng(12345); // private generator, seeded, reproducible (no global rand state)
        std::vector<std::string> strpool;
        strpool.push_back(std::string("normal"));
        strpool.push_back(std::string("with\0nul", 8));
        strpool.push_back(std::string("\xff\xfe\x01\x02garbage", 9));
        strpool.push_back(std::string(1000, 'y'));
        strpool.push_back(std::string("}\"{\n"));
        strpool.push_back(std::string());
        std::vector<std::string> fenpool = {
            "", "8/8/8/8/8/8/8/8 w - - 0 1", "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
            "garbage", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "4k3/8/8/8/8/8/8/4K3 b - - 0 99999999",
        };
        const int N = 200000;
        const int BATCH = 2000;
        std::uniform_int_distribution<int> kindD(0, 6);        // includes invalid kinds
        std::uniform_int_distribution<int> sqD(-2, 70);        // includes invalid squares
        std::uniform_int_distribution<int> promoD(0, 300);     // includes invalid promo chars
        std::uniform_int_distribution<int> cntD(-2, 40);       // includes negative counts
        std::uniform_int_distribution<int> pickD(0, (int)strpool.size() - 1);
        std::uniform_int_distribution<int> fenD(0, (int)fenpool.size() - 1);
        std::uniform_int_distribution<int> validD(0, 9);
        std::uniform_int_distribution<int> threadD(1, 4);

        std::set<int> validMatched;   // matches of the interleaved valid games
        std::vector<int> validNumbers;
        int nextValidNumber = 1000000;

        // storage that outlives each search call
        std::deque<OwnedGame> validStore; // scidb: stable addresses (raw pointers point into it)
        std::vector<std::string> garbage; // backing strings for random games

        for (int batch = 0; batch * BATCH < N; ++batch) {
            std::vector<cql6_game> raws;
            std::vector<std::vector<cql6_tag>> tagbufs;
            std::vector<std::vector<cql6_move>> movebufs;
            raws.reserve(BATCH); tagbufs.reserve(BATCH); movebufs.reserve(BATCH);
            for (int i = 0; i < BATCH && batch * BATCH + i < N; ++i) {
                if (validD(rng) == 0) {
                    // a valid game with a unique number; mate every 3rd one
                    bool mate = (nextValidNumber % 3 == 0);
                    validStore.push_back(makeValidGame(nextValidNumber, mate));
                    validNumbers.push_back(nextValidNumber);
                    if (mate) validMatched.insert(nextValidNumber);
                    nextValidNumber++;
                    const OwnedGame& og = validStore.back();
                    cql6_game g;
                    g.number = og.number; g.fen = nullptr;
                    g.ntags = 0; g.tags = nullptr; // filled after all pushes (pointers!)
                    g.nmoves = 0; g.moves = nullptr;
                    raws.push_back(g);
                    tagbufs.emplace_back();
                    movebufs.emplace_back();
                } else {
                    cql6_game g;
                    memset(&g, 0, sizeof g);
                    g.number = (int)(rng() % 1000000);
                    g.fen = fenpool[fenD(rng)].empty() ? nullptr : fenpool[fenD(rng)].c_str();
                    g.ntags = cntD(rng);
                    g.nmoves = cntD(rng);
                    g.tags = nullptr;
                    g.moves = nullptr;
                    raws.push_back(g);
                    tagbufs.emplace_back();
                    movebufs.emplace_back();
                    auto& tb = tagbufs.back();
                    auto& mb = movebufs.back();
                    if (g.ntags > 0) {
                        int n = g.ntags;
                        tb.resize(n);
                        for (int t = 0; t < n; ++t) {
                            tb[t].name = strpool[pickD(rng)].c_str();
                            tb[t].value = strpool[pickD(rng)].c_str();
                        }
                        raws.back().tags = tb.data();
                    }
                    if (g.nmoves > 0) {
                        int n = g.nmoves;
                        mb.resize(n);
                        for (int m = 0; m < n; ++m) {
                            mb[m].kind = kindD(rng) <= 2 ? kindD(rng) % 3 : kindD(rng);
                            mb[m].from = sqD(rng);
                            mb[m].to = sqD(rng);
                            mb[m].promo = promoD(rng) == 0 ? 0 : (char)promoD(rng);
                            mb[m].comment = (promoD(rng) % 4 == 0) ? strpool[pickD(rng)].c_str() : nullptr;
                        }
                        raws.back().moves = mb.data();
                    }
                }
            }
            // fix pointers for valid games (their OwnedGame storage is stable in validStore)
            // (moves/tags point into validStore entries directly)
            for (size_t r = 0; r < raws.size(); ++r) {
                if (raws[r].number >= 1000000) {
                    const OwnedGame* og = nullptr;
                    for (auto& s : validStore) if (s.number == raws[r].number) { og = &s; break; }
                    if (og) {
                        raws[r].nmoves = (int)og->moves.size();
                        raws[r].moves = og->moves.data();
                        auto& tb = tagbufs[r];
                        tb.resize(og->tags.size());
                        for (size_t t = 0; t < og->tags.size(); ++t) { tb[t].name = og->tags[t].first.c_str(); tb[t].value = og->tags[t].second.c_str(); }
                        raws[r].ntags = (int)tb.size();
                        raws[r].tags = tb.empty() ? nullptr : tb.data();
                    }
                }
            }
            RawFeed rf; rf.games = raws;
            cql6_options opt; memset(&opt, 0, sizeof opt);
            opt.threads = threadD(rng);
            opt.variations = (rng() % 2);
            cql6_result res; char err[1024]; err[0] = 0;
            int rc = cql6_search("mate", &opt, feedRaw, &rf, &res, err, sizeof err);
            // a batch may legitimately fail ONLY if every game was rejected; with valid
            // games interleaved that must not happen
            CHECK(rc == 0, "fuzz batch %d: rc=%d err=%.100s", batch, rc, err);
            if (rc == 0) {
                for (int i = 0; i < res.nmatches; ++i) {
                    int gn = res.matches[i].game_number;
                    if (gn >= 1000000) validMatched.insert(gn);
                }
            }
            cql6_free_result(&res);
        }
        // the valid games must match exactly the mate games (same as when run alone)
        std::set<int> expected;
        for (int n : validNumbers) if (n % 3 == 0) expected.insert(n);
        CHECK(validMatched == expected, "fuzz: valid-game matches differ from standalone run (%zu vs %zu)",
              validMatched.size(), expected.size());
        printf("  fuzz done: %zu valid games, %zu expected matches, matched=%s\n",
               validNumbers.size(), expected.size(), validMatched == expected ? "identical" : "DIFFERENT");
    }

    // 12. systemic rejection: EVERY game invalid -> error, process alive
    {
        cql6_move m; m.kind = 9; m.from = 0; m.to = 0; m.promo = 0; m.comment = nullptr;
        std::vector<cql6_game> v(50);
        for (auto& g : v) { memset(&g, 0, sizeof g); g.number = 1; g.nmoves = 1; g.moves = &m; }
        cql6_result res; char err[1024]; err[0] = 0;
        int rc = searchGames(v, &res, err, sizeof err);
        CHECK(rc != 0 && strlen(err) > 0, "systemic rejection must return an error (rc=%d)", rc);
        cql6_free_result(&res);
        // and a normal search still works afterwards
        OwnedGame a = makeValidGame(1, false), b = makeValidGame(2, true);
        FeedMany fm; fm.games = {&a, &b};
        cql6_options opt; memset(&opt, 0, sizeof opt); opt.threads = threads;
        cql6_result res2; char err2[1024]; err2[0] = 0;
        int rc2 = cql6_search("mate", &opt, feedMany, &fm, &res2, err2, sizeof err2);
        CHECK(rc2 == 0 && res2.nmatches == 1, "recovery after systemic error failed: rc=%d", rc2);
        cql6_free_result(&res2);
    }

    printf(g_failures == 0 ? "[PASS] C: feed robustness\n" : "[FAIL] C: feed robustness (%d failures)\n", g_failures);
    return g_failures == 0 ? 0 : 1;
}
