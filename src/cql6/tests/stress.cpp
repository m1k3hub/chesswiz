// scidb: Task 3 §B — stress test.
//
// >= 20000 games (the test PGN games repeated with changed game numbers),
// 16 worker threads, 10 different scripts (sort, flip, variations-on, a
// persistent one that forces a single thread, scripts that fail mid-search),
// run back to back, plus 5 searches one after another in the same process.
//
// Gate: zero sanitizer reports under ASan/UBSan and TSan (run via `make asan`/
// `make tsan`), deterministic match counts across rounds, failing scripts fail
// cleanly every time without hangs.
//
// usage: stress <pgn> [rounds=3] [threads=16] [games=20000]
#include "feed_common.h"
#include "orig/common.h"
#include <atomic>

struct CycleFeed {
    const Dataset* ds;
    size_t count;
    size_t served = 0;
};

static int cycleNext(void* ctx, int thread, cql6_game* g) {
    (void)thread;
    CycleFeed* cf = (CycleFeed*)ctx;
    if (cf->served >= cf->count) return 0;
    size_t idx = cf->served % cf->ds->games.size();
    long number = (long)(++cf->served); // renumbered 1..count
    const ParsedGame& src = cf->ds->games[idx];
    g->number = (int)number;
    g->fen = src.fen.empty() ? nullptr : src.fen.c_str();
    // tags/moves point into the dataset, which outlives the search
    static thread_local std::vector<cql6_tag> tagbuf;
    tagbuf.resize(src.tags.size());
    for (size_t i = 0; i < src.tags.size(); ++i) {
        tagbuf[i].name = src.tags[i].first.c_str();
        tagbuf[i].value = src.tags[i].second.c_str();
    }
    g->ntags = (int)tagbuf.size();
    g->tags = tagbuf.empty() ? nullptr : tagbuf.data();
    g->nmoves = (int)src.moves.size();
    g->moves = src.moves.empty() ? nullptr : src.moves.data();
    return 1;
}

static std::atomic<bool> g_hookArmed{false};
static int g_hookGame = 0;
static void failHook(int gameNumber, int threadIndex) {
    (void)threadIndex;
    if (g_hookArmed.load(std::memory_order_relaxed) && gameNumber == g_hookGame) {
        ASSERT(1 == 2); // scid test assert -> CqlException in embedded builds
    }
}

struct StressScript {
    const char* name;
    std::string script;
    int variations = 0;
    bool mustFail = false;
};

int main(int argc, char** argv) {
    if (argc < 2) { std::cerr << "usage: stress <pgn> [rounds] [threads] [games]\n"; return 2; }
    std::string pgn = argv[1];
    int rounds = (argc > 2) ? atoi(argv[2]) : 3;
    int threads = (argc > 3) ? atoi(argv[3]) : 16;
    long games = (argc > 4) ? atol(argv[4]) : 20000;

    Dataset ds;
    if (!fc_loadDataset(pgn, ds)) return 2;
    printf("== stress: %zu source games, feed of %ld games, %d threads, %d rounds ==\n",
           ds.games.size(), games, threads, rounds);

    std::vector<StressScript> scripts = {
        {"check",          "check", 0, false},
        {"mate",           "mate", 0, false},
        {"sort",           "sort \"material\" ([a]<=6)", 0, false},
        {"flip",           "flip (Kg1 and Pf2 and Pg2 and Ph2)", 0, false},
        {"promo",          "(――=Q) or (――=R) or (――=N)", 0, false},
        {"variations",     "―― check ―― check", 1, false},
        {"persistent",     "if initial\n persistent NGames += 1\ncheck", 0, false},
        {"echo",           "echo(source target) { source: (Kg1 and Pf2 and Pg2 and Ph2) kg8 and pf7 and pg7 and ph7 }", 0, false},
        {"path",           "⊢ ―― check ―― mate", 0, false},
        {"fail-midsearch", "mate", 0, true},
    };

    bool pass = true;
    std::vector<int> expectedMatches(scripts.size(), -1);
    std::vector<long> expectedGames(scripts.size(), -1);
    double totalTime = 0;

    for (int r = 1; r <= rounds; ++r) {
        printf("-- round %d --\n", r);
        for (size_t si = 0; si < scripts.size(); ++si) {
            StressScript& s = scripts[si];
            CycleFeed cf; cf.ds = &ds; cf.count = (size_t)games;
            cql6_options opt; memset(&opt, 0, sizeof opt);
            opt.threads = threads;
            opt.variations = s.variations;
            opt.test_hook = nullptr;
            g_hookArmed.store(false);
            if (s.mustFail) {
                opt.test_hook = failHook;
                g_hookGame = (int)(games / 2);
                g_hookArmed.store(true);
            }
            cql6_result res; char err[2048]; err[0] = 0;
            auto t0 = std::chrono::high_resolution_clock::now();
            int rc = cql6_search(s.script.c_str(), &opt, cycleNext, &cf, &res, err, sizeof err);
            auto t1 = std::chrono::high_resolution_clock::now();
            double secs = std::chrono::duration<double>(t1 - t0).count();
            totalTime += secs;

            if (s.mustFail) {
                if (rc == 0) {
                    printf("[FAIL] %s: failing script did NOT fail\n", s.name);
                    pass = false;
                } else {
                    printf("  %-14s failed as expected in %.2fs: %.60s...\n", s.name, secs, err);
                }
                cql6_free_result(&res);
                continue;
            }
            if (rc != 0) {
                printf("[FAIL] %s: rc=%d err=%.120s\n", s.name, rc, err);
                pass = false;
                cql6_free_result(&res);
                continue;
            }
            if (expectedMatches[si] < 0) {
                expectedMatches[si] = res.nmatches;
                expectedGames[si] = res.ngames;
            } else if (res.nmatches != expectedMatches[si] || res.ngames != expectedGames[si]) {
                printf("[FAIL] %s: nondeterministic: matches %d (was %d), games %ld (was %ld)\n",
                       s.name, res.nmatches, expectedMatches[si], res.ngames, expectedGames[si]);
                pass = false;
            }
            printf("  %-14s %6d matches, ngames=%ld nskipped=%ld threads=%d %.2fs\n",
                   s.name, res.nmatches, res.ngames, res.nskipped, res.threads_used, secs);
            cql6_free_result(&res);
        }
    }

    // 5 searches back to back in the same process, same script: identical results
    {
        printf("-- 5 back-to-back searches (same process) --\n");
        int refMatches = -1; long refGames = -1;
        for (int i = 0; i < 5; ++i) {
            CycleFeed cf; cf.ds = &ds; cf.count = (size_t)games;
            cql6_options opt; memset(&opt, 0, sizeof opt);
            opt.threads = threads;
            cql6_result res; char err[2048]; err[0] = 0;
            int rc = cql6_search("sort \"material\" ([a]<=6)", &opt, cycleNext, &cf, &res, err, sizeof err);
            if (rc != 0) { printf("[FAIL] back-to-back %d: rc=%d %.120s\n", i, rc, err); pass = false; break; }
            if (refMatches < 0) { refMatches = res.nmatches; refGames = res.ngames; }
            else if (res.nmatches != refMatches || res.ngames != refGames) {
                printf("[FAIL] back-to-back %d: %d/%ld != %d/%ld\n", i, res.nmatches, res.ngames, refMatches, refGames);
                pass = false;
            }
            printf("  run %d: %d matches, %ld games\n", i, res.nmatches, res.ngames);
            cql6_free_result(&res);
        }
    }

    printf("total search time: %.1fs\n", totalTime);
    printf(pass ? "[PASS] B-stress\n" : "[FAIL] B-stress\n");
    return pass ? 0 : 1;
}
