// scidb: Task 3 section D — strengthened oracle comparison.
//
// Runs at least 20 scripts against the official ./cql oracle on a 20000-game PGN
// and compares: match sets, match ORDER (for sort scripts), first_ply of every
// match, want_pgn content and `messages`.  Requires at least 20 comparisons whose
// match rate is between 1% and 99% of the games.
//
// usage:
//   oracle20k rates <pgn>            # print lib match counts/rates only (fast tuning)
//   oracle20k full  <pgn> <oracle>   # full oracle comparison gate
#include "feed_common.h"
#include <algorithm>

struct ScriptDef {
    std::string name;
    std::string script;
    bool variations = false;
    bool checkOrder = false;   // script uses sort: compare ordered output
    bool wantPgn = false;      // run lib with want_pgn and inspect the PGN
    bool expectMessages = false; // lib result must carry `messages`
};

static std::vector<ScriptDef> makeScripts() {
    std::vector<ScriptDef> s;
    auto add = [&](const char* n, const char* body) { s.push_back({n, body}); };

    // --- piece counts ---
    add("pc_endgame10", "sort \"material\" [A]<=10");
    s.back().checkOrder = true;
    add("pc_fourqueens", "[Q]==1 and [q]==1 and [Aa]==24");
    // --- king / pawn structure ---
    add("ks_white_castle_shield", "Kg1 and Pf2 and Pg2 and Ph2 and not Pg3");
    add("ks_black_castle_h", "kg8 and pg7 and ph7 and pf7");
    // --- attacks ---
    add("at_qk", "Q→k");
    add("at_rook_king", "R→k or r→K");
    // --- flip ---
    add("flip_castle", "flip (Kg1 and Pf2 and Pg2 and Ph2 and not Pg3)");
    // --- flipcolor ---
    add("flipcolor_castle", "flipcolor (Kg1 and Pf2 and Pg2 and Ph2) and [A]<=24");
    // --- shift ---
    add("shift_pattern", "shift (Pe4 and Pd5 and Pc3)");
    // --- sort (order compared) ---
    add("sort_piececount", "sort \"material\" ([a]<=6)");
    s.back().checkOrder = true;
    // --- echo ---
    add("echo_castles", "echo(source target) { source: (Kg1 and Pf2 and Pg2 and Ph2) kg8 and pf7 and pg7 and ph7 }");
    // --- line / path with regex ---
    add("line_2checks", "line --> check --> check");
    add("path_promo", "⊢ ――=Q");
    add("regex_tag_eco", "tag \"ECO\" ~~ \"^B[0-9]\"");
    add("regex_white_K_path", "tag \"White\" ~~ \"^S\" and ⊢ ―― check ―― check");
    add("regex_eco_path", "tag \"ECO\" ~~ \"^[A-D]\" and ⊢ ―― check");
    // --- if ---
    add("if_early_check", "if ply<10 then check else mate");
    // --- function ---
    add("function_dist2", "function dist2(x y){ (rank x - rank y)*(rank x - rank y) + (file x - file y)*(file x - file y) }\ndist2(move from . move to .) == 2 and ply>2");
    // --- persistent (forces single thread) + messages ---
    add("persistent_gamenumber", "if initial\n persistent NumberGames += 1\nNumberGames>=4000 and NumberGames<=16000");
    s.back().expectMessages = true; // scidb: persistent var must appear in messages
    // --- comment/message with want_pgn ---
    {
        ScriptDef d{"comment_wantpgn", "check and comment \"scidb-test-comment\"", false, false, true, false};
        s.push_back(d);
    }
    {
        ScriptDef d{"message_wantpgn", "mate and message \"scidb-mated-game\"", false, false, true, false};
        s.push_back(d);
    }
    // --- move filters ---
    add("move_e2e4", "move from e2 to e4");
    add("move_capture", "move previous capture .");
    add("move_capture_eg", "move previous capture . and ply>60");
    add("move_promo_q", "――=Q");
    // --- variations on ---
    {
        ScriptDef d{"var_mate", "mate", true, false, false, false};
        s.push_back(d);
    }
    {
        ScriptDef d{"var_check_pair", "―― check ―― check", true, false, false, false};
        s.push_back(d);
    }
    // --- extras (rate may be outside band; still compared) ---
    add("mate_plain", "mate");
    add("stalemate_plain", "stalemate");
    return s;
}

static int runLib(const ScriptDef& def, const Dataset& ds, int threads, cql6_result* res, char* err, size_t errlen,
                  std::vector<int>* order) {
    cql6_options opt;
    memset(&opt, 0, sizeof(opt));
    opt.threads = threads;
    opt.variations = def.variations ? 1 : 0;
    opt.max_matches = 0;
    opt.want_pgn = def.wantPgn ? 1 : 0;
    // Host test setting: run the same pristine comparisons against optimized
    // preparation without changing the oracle or the scripts.
    const char* feedMode = std::getenv("CQL6_TEST_FEED_MODE");
    int mode = feedMode ? std::atoi(feedMode) : 0;
    opt.trusted_moves = mode & 1;
    opt.lazy_features = (mode >> 1) & 1;
    FeedContext fc;
    fc.dataset = &ds;
    fc.next_idx = 0;
    int rc = cql6_search(def.script.c_str(), &opt, fc_feedNextGame, &fc, res, err, errlen);
    if (rc == 0 && order) {
        for (int i = 0; i < res->nmatches; ++i) order->push_back(res->matches[i].game_number);
    }
    return rc;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: oracle20k rates <pgn> | oracle20k full <pgn> [oracle]\n";
        return 2;
    }
    std::string mode = argv[1];
    std::string pgnPath = argv[2];
    std::string oraclePath = (argc > 3) ? argv[3] : "/tmp/cql_oracle/cql";
    // PGN without the games that make the ORIGINAL cql abort() under `variations`
    // (corrupt games the Scid PGN parser turns into empty variations); used for the
    // variations-on comparisons so oracle and lib see the same set of games.
    std::string varPgnPath = (argc > 4) ? argv[4] : "";

    Dataset ds;
    if (!fc_loadDataset(pgnPath, ds)) return 2;
    long ngames = (long)ds.games.size();
    std::cout << "loaded " << ngames << " games from " << pgnPath << "\n";
    Dataset varDs;
    long varNgames = 0;
    if (mode == "full" && !varPgnPath.empty()) {
        if (!fc_loadDataset(varPgnPath, varDs)) return 2;
        varNgames = (long)varDs.games.size();
        std::cout << "loaded " << varNgames << " games from " << varPgnPath << " (variations-safe)\n";
    }

    std::vector<ScriptDef> scripts = makeScripts();

    if (mode == "rates") {
        int failures = 0;
        for (auto& def : scripts) {
            cql6_result res; char err[2048]; err[0] = 0;
            auto t0 = std::chrono::high_resolution_clock::now();
            int rc = runLib(def, ds, 0, &res, err, sizeof(err), nullptr);
            auto t1 = std::chrono::high_resolution_clock::now();
            double secs = std::chrono::duration<double>(t1 - t0).count();
            if (rc != 0) {
                std::cout << "  ERROR  " << def.name << ": " << err << "\n";
                failures++;
            } else {
                std::set<int> games;
                for (int i = 0; i < res.nmatches; ++i) games.insert(res.matches[i].game_number);
                double rate = 100.0 * (double)games.size() / (double)ngames;
                std::cout << "  " << def.name << ": " << games.size() << " games ("
                          << rate << "%) " << secs << "s threads=" << res.threads_used
                          << (res.messages ? " msgs=yes" : "") << "\n";
            }
            cql6_free_result(&res);
        }
        return failures ? 1 : 0;
    }

    if (mode == "one") {
        // usage: oracle20k one <pgn> <threads> <script text...>
        if (argc < 5) return 2;
        int threads = atoi(argv[3]);
        std::string script;
        for (int i = 4; i < argc; ++i) { if (i > 4) script += " "; script += argv[i]; }
        ScriptDef def{"adhoc", script};
        cql6_result res; char err[2048]; err[0] = 0;
        int rc = runLib(def, ds, threads, &res, err, sizeof(err), nullptr);
        if (rc != 0) { std::cout << "ERROR: " << err << "\n"; return 1; }
        std::set<int> games;
        for (int i = 0; i < res.nmatches; ++i) games.insert(res.matches[i].game_number);
        std::cout << games.size() << " games (" << 100.0 * (double)games.size() / (double)ngames << "%)"
                  << " ngames=" << res.ngames
                  << (res.messages ? " msgs: " : "") << (res.messages ? res.messages : "") << "\n";
        if (getenv("CQL20K_LIST")) { for (int g : games) std::cout << g << "\n"; }
        cql6_free_result(&res);
        return 0;
    }

    if (mode == "findbad") {
        // Feed each game ALONE through a variations=1 search; games that are skipped or
        // that fail the search are printed (these are games the original CQL chokes on,
        // e.g. empty variations from corrupt PGN — the official ./cql abort()s on them).
        ScriptDef def{"probe", "mate"};
        int bad = 0;
        for (size_t i = 0; i < ds.games.size(); ++i) {
            Dataset one;
            one.games.push_back(ds.games[i]);
            cql6_result res; char err[2048]; err[0] = 0;
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = 1;
            opt.variations = 1;
            FeedContext fc;
            fc.dataset = &one;
            fc.next_idx = 0;
            int rc = cql6_search(def.script.c_str(), &opt, fc_feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0 || res.nskipped > 0) {
                std::cout << "BAD " << one.games[0].number << (rc != 0 ? " rc!=0: " : " skipped");
                if (rc != 0) std::cout << err;
                std::cout << "\n";
                bad++;
            }
            cql6_free_result(&res);
        }
        std::cout << "bad games: " << bad << "\n";
        return 0;
    }

    if (mode != "full") { std::cerr << "bad mode\n"; return 2; }

    int nCompared = 0;         // in-band scripts that fully passed
    int nTotalCompared = 0;
    bool allOk = true;

    for (auto& def : scripts) {
        bool scriptAllOk = true;
        std::cout << "\n=== " << def.name << " (variations=" << def.variations
                  << " order=" << def.checkOrder << " pgn=" << def.wantPgn << ") ===\n";
        std::string body = def.script;
        const std::string& usePgn = def.variations ? varPgnPath : pgnPath;
        const Dataset& useDs = def.variations ? varDs : ds;
        long useNgames = def.variations ? varNgames : ngames;
        if (def.variations && varPgnPath.empty()) {
            std::cout << "  [FAIL] variations script needs the varsafe PGN argument\n";
            allOk = false;
            continue;
        }
        OracleResult orc = fc_runOracle(oraclePath, usePgn, body, true, def.variations);
        if (orc.exit_status != 0) {
            std::cout << "  [FAIL] oracle process failed: status=" << orc.exit_status << "\n" << orc.stdoutText;
            allOk = false;
            continue;
        }
        std::cout << "  oracle: " << orc.games.size() << " games in " << orc.seconds << "s\n";
        double rate = 100.0 * (double)orc.games.size() / (double)useNgames;
        bool inBand = (rate >= 1.0 && rate <= 99.0);
        std::cout << "  rate: " << rate << "%" << (inBand ? " (in band)" : " (OUT OF BAND)") << "\n";

        for (int threads : {1, 8}) {
            cql6_result res; char err[2048]; err[0] = 0;
            std::vector<int> order;
            int rc = runLib(def, useDs, threads, &res, err, sizeof(err), def.checkOrder ? &order : nullptr);
            if (rc != 0) {
                std::cout << "  [FAIL] threads=" << threads << " search error: " << err << "\n";
                allOk = false; scriptAllOk = false;
                continue;
            }
            std::set<int> libGames;
            std::map<int, int> libFirstPly;
            for (int i = 0; i < res.nmatches; ++i) {
                libGames.insert(res.matches[i].game_number);
                auto it = libFirstPly.find(res.matches[i].game_number);
                if (it == libFirstPly.end() ||
                    (res.matches[i].first_ply >= 0 && (it->second < 0 || res.matches[i].first_ply < it->second)))
                    libFirstPly[res.matches[i].game_number] = res.matches[i].first_ply;
            }
            nTotalCompared++;
            bool ok = true;

            if (libGames != orc.games) {
                ok = false;
                std::vector<int> extra, missing;
                for (int g : libGames) if (!orc.games.count(g)) extra.push_back(g);
                for (int g : orc.games) if (!libGames.count(g)) missing.push_back(g);
                std::cout << "  [FAIL] threads=" << threads << " set mismatch: +" << extra.size()
                          << " -" << missing.size() << "\n";
                for (size_t i = 0; i < std::min<size_t>(10, extra.size()); ++i) std::cout << "    extra: " << extra[i] << "\n";
                for (size_t i = 0; i < std::min<size_t>(10, missing.size()); ++i) std::cout << "    missing: " << missing[i] << "\n";
            }

            if (ok && def.checkOrder) {
                std::vector<int> orcOrder;
                for (auto& om : orc.ordered) orcOrder.push_back(om.game_number);
                if (orcOrder != order) {
                    ok = false;
                    size_t diffAt = 0;
                    while (diffAt < orcOrder.size() && diffAt < order.size() && orcOrder[diffAt] == order[diffAt]) diffAt++;
                    std::cout << "  [FAIL] threads=" << threads << " ORDER mismatch at index " << diffAt
                              << " (oracle n=" << orcOrder.size() << ", lib n=" << order.size() << ")\n";
                }
            }

            if (ok) {
                // first_ply comparison for every match
                int nBadPly = 0;
                for (int i = 0; i < res.nmatches; ++i) {
                    int gn = res.matches[i].game_number;
                    auto it = orc.firstPlyByGame.find(gn);
                    if (it == orc.firstPlyByGame.end()) continue;
                    if (it->second != res.matches[i].first_ply) {
                        if (nBadPly < 5)
                            std::cout << "  [FAIL] game " << gn << " first_ply lib=" << res.matches[i].first_ply
                                      << " oracle=" << it->second << "\n";
                        nBadPly++;
                    }
                }
                if (nBadPly) { ok = false; std::cout << "  [FAIL] threads=" << threads << ": " << nBadPly << " first_ply mismatches\n"; }
            }

            if (ok && def.wantPgn && threads == 1) {
                int nNoPgn = 0, nNoComment = 0;
                for (int i = 0; i < res.nmatches; ++i) {
                    if (!res.matches[i].pgn) { nNoPgn++; continue; }
                    if (!strstr(res.matches[i].pgn, "CQL")) nNoComment++;
                    if (def.name == "comment_wantpgn" && !strstr(res.matches[i].pgn, "scidb-test-comment")) nNoComment++;
                }
                if (nNoPgn || nNoComment) {
                    ok = false;
                    std::cout << "  [FAIL] want_pgn: " << nNoPgn << " null pgn, " << nNoComment << " missing comment\n";
                }
            }

            if (ok && def.expectMessages && threads == 1) {
                if (!res.messages || !strstr(res.messages, "NumberGames")) {
                    ok = false;
                    std::cout << "  [FAIL] expected messages carrying persistent variable, got: "
                              << (res.messages ? res.messages : "(null)") << "\n";
                } else {
                    std::cout << "  messages: " << res.messages << "\n";
                    // the oracle prints persistent variables to stdout as "checks: N"; compare N
                    size_t p = orc.stdoutText.rfind("NumberGames:");
                    if (p != std::string::npos) {
                        long oracleVal = atol(orc.stdoutText.c_str() + p + 12);
                        const char* lp = strchr(res.messages, ':');
                        long libVal = lp ? atol(lp + 1) : -1;
                        if (oracleVal != libVal) {
                            ok = false;
                            std::cout << "  [FAIL] persistent value lib=" << libVal << " oracle=" << oracleVal << "\n";
                        }
                    }
                }
            }

            if (ok)
                std::cout << "  threads=" << threads << ": OK (" << res.nmatches << " matches)\n";
            else {
                allOk = false; scriptAllOk = false;
            }
            cql6_free_result(&res);
        }
        if (inBand && scriptAllOk) nCompared++;
        else if (inBand) std::cout << "  [note] in-band script FAILED; does not count toward the 20\n";
    }

    std::cout << "\n=================================================\n";
    std::cout << "in-band (1%-99%) oracle comparisons: " << nCompared << " (requirement: >= 20)\n";
    std::cout << "total scripts compared: " << nTotalCompared / 2 << "\n";
    if (nCompared < 20) { std::cout << "[FAIL] fewer than 20 in-band comparisons\n"; allOk = false; }
    std::cout << (allOk ? "[PASS] D: oracle comparison gate\n" : "[FAIL] D: oracle comparison gate\n");
    return allOk ? 0 : 1;
}
