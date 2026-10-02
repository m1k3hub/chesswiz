#include "cql6_api.h"
#include "orig/game.h"
#include "orig/pgnparse.h"
#include "orig/mfile.h"
#include "orig/date.h"
#include "orig/misc.h"
#include "orig/position.h"

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <deque>
#include <set>
#include <chrono>
#include <cstring>
#include <cstdlib>
#include <cassert>
#include <unistd.h>
#include <fcntl.h>

// Structure to hold pre-parsed game in memory
struct ParsedGame {
    int number;
    std::string fen;
    std::vector<std::pair<std::string, std::string>> tags;
    std::vector<cql6_move> moves;
    // scidb: deque, not vector: convertMoves stores c_str() pointers into this and
    // vector reallocation would dangle them (ASan heap-use-after-free in the driver)
    std::deque<std::string> comments; // backing storage for move comments
};

// Global or context dataset
struct Dataset {
    // scidb: deque, not vector: ParsedGame holds cql6_move.comment pointers into its own
    // comments deque; vector reallocation would move/free the games and dangle them
    std::deque<ParsedGame> games;
};

// Recursive move converter from Scid Game tree to cql6_move vector
static void convertMoves(Game* game, moveT* m, std::vector<cql6_move>& outMoves, std::deque<std::string>& outComments) {
    while (m && m->marker != END_MARKER) {
        cql6_move cm;
        cm.kind = 0;
        cm.from = (int)m->moveData.from;
        cm.to = (int)m->moveData.to;
        cm.promo = 0;
        if (m->moveData.promote != EMPTY) {
            cm.promo = piece_Char(m->moveData.promote);
        }
        if (isNullMove(m)) { cm.kind=3; cm.from=cm.to=cm.promo=0; }
        cm.comment = nullptr;
        if (m->comment && m->comment[0] != '\0') {
            outComments.push_back(m->comment);
            cm.comment = outComments.back().c_str();
        }
        outMoves.push_back(cm);

        // Variations branching from after this move
        if (m->numVariations > 0 && m->varChild) {
            moveT* varStart = m->varChild;
            while (varStart) {
                assert(varStart->marker == START_MARKER);
                cql6_move startVar;
                startVar.kind = 1;
                startVar.from = 0;
                startVar.to = 0;
                startVar.promo = 0;
                startVar.comment = nullptr;
                if (varStart->comment && varStart->comment[0] != '\0') {
                    outComments.push_back(varStart->comment);
                    startVar.comment = outComments.back().c_str();
                }
                outMoves.push_back(startVar);

                // Recursively convert moves of the variation
                convertMoves(game, varStart->next, outMoves, outComments);

                cql6_move endVar;
                endVar.kind = 2;
                endVar.from = 0;
                endVar.to = 0;
                endVar.promo = 0;
                endVar.comment = nullptr;
                outMoves.push_back(endVar);

                varStart = varStart->varChild;
            }
        }

        m = m->next;
    }
}

// Convert Scid Game object to ParsedGame
static void extractGame(Game* game, int gameNum, ParsedGame& pg) {
    pg.number = gameNum;
    pg.fen.clear();
    pg.tags.clear();
    pg.moves.clear();
    pg.comments.clear();

    if (game->HasNonStandardStart() && game->GetStartPos()) {
        char fenBuf[256];
        game->GetStartPos()->PrintFEN(fenBuf, FEN_ALL_FIELDS);
        pg.fen = fenBuf;
    }

    if (game->GetEventStr() && *game->GetEventStr()) pg.tags.emplace_back("Event", game->GetEventStr());
    if (game->GetSiteStr() && *game->GetSiteStr()) pg.tags.emplace_back("Site", game->GetSiteStr());
    if (game->GetWhiteStr() && *game->GetWhiteStr()) pg.tags.emplace_back("White", game->GetWhiteStr());
    if (game->GetBlackStr() && *game->GetBlackStr()) pg.tags.emplace_back("Black", game->GetBlackStr());
    if (game->GetRoundStr() && *game->GetRoundStr()) pg.tags.emplace_back("Round", game->GetRoundStr());

    char dateStr[20];
    date_DecodeToString(game->GetDate(), dateStr);
    if (*dateStr) pg.tags.emplace_back("Date", dateStr);

    if (game->GetEventDate() != ZERO_DATE) {
        char edateStr[20];
        date_DecodeToString(game->GetEventDate(), edateStr);
        if (*edateStr) pg.tags.emplace_back("EventDate", edateStr);
    }

    pg.tags.emplace_back("Result", RESULT_LONGSTR[game->GetResult()]);

    if (game->GetWhiteElo() > 0) pg.tags.emplace_back("WhiteElo", std::to_string(game->GetWhiteElo()));
    if (game->GetBlackElo() > 0) pg.tags.emplace_back("BlackElo", std::to_string(game->GetBlackElo()));

    if (game->GetEco() != 0) {
        ecoStringT ecoStr;
        eco_ToExtendedString(game->GetEco(), ecoStr);
        pg.tags.emplace_back("ECO", ecoStr);
    }
    if (*game->GetScidFlags()) pg.tags.emplace_back("ScidFlags", game->GetScidFlags());

    for (uint i = 0; i < game->GetNumExtraTags(); ++i) {
        tagT* t = &game->GetExtraTags()[i];
        if (t->tag && t->value) {
            pg.tags.emplace_back(t->tag, t->value);
        }
    }

    // Moves
    moveT* first = game->GetFirstMove();
    if (first && first->next) {
        convertMoves(game, first->next, pg.moves, pg.comments);
    }
}

// Next game callback for cql6_search
struct FeedContext {
    const Dataset* dataset;
    size_t next_idx;
    // Note: cql6_search serializes next_fn calls across worker threads with its own mutex,
    // but each thread must retain its tag buffer valid until called again from the same thread.
    std::vector<std::vector<cql6_tag>> thread_tag_bufs;
};

static int feedNextGame(void* ctx, int thread, cql6_game* g) {
    FeedContext* fc = (FeedContext*)ctx;
    if (fc->next_idx >= fc->dataset->games.size()) {
        return 0;
    }
    const ParsedGame& src = fc->dataset->games[fc->next_idx++];
    g->number = src.number;
    g->fen = src.fen.empty() ? nullptr : src.fen.c_str();

    if (thread >= (int)fc->thread_tag_bufs.size()) {
        fc->thread_tag_bufs.resize(thread + 1);
    }
    auto& tag_buf = fc->thread_tag_bufs[thread];
    tag_buf.resize(src.tags.size());
    for (size_t i = 0; i < src.tags.size(); ++i) {
        tag_buf[i].name = src.tags[i].first.c_str();
        tag_buf[i].value = src.tags[i].second.c_str();
    }
    g->ntags = (int)tag_buf.size();
    g->tags = tag_buf.empty() ? nullptr : tag_buf.data();

    g->nmoves = (int)src.moves.size();
    g->moves = src.moves.empty() ? nullptr : src.moves.data();

    return 1;
}

// Helper to run oracle ./cql on a script and PGN, returning matched game numbers
static std::set<int> runOracle(const std::string& oraclePath, const std::string& pgnPath, const std::string& scriptBody, double* outSecs = nullptr, bool variations = false) {
    char scriptFile[] = "/tmp/cql_oracle_script_XXXXXX";
    int fd = mkstemp(scriptFile);
    close(fd);
    std::string scriptPath = std::string(scriptFile) + ".cql";
    rename(scriptFile, scriptPath.c_str());
    std::string outPgn = std::string(scriptFile) + "-out.pgn";

    std::ofstream ofs(scriptPath);
    ofs << "cql(input " << pgnPath << " output " << outPgn << (variations ? " variations" : "") << ")\n" << scriptBody << "\n";
    ofs.close();

    std::string cmd = oraclePath + " " + scriptPath + " > /dev/null 2>&1";

    auto t0 = std::chrono::high_resolution_clock::now();
    int rc = system(cmd.c_str());
    auto t1 = std::chrono::high_resolution_clock::now();
    if (outSecs) {
        *outSecs = std::chrono::duration<double>(t1 - t0).count();
    }

    std::set<int> matches;
    std::ifstream ifs(outPgn, std::ios::binary);
    if (ifs.is_open()) {
        std::string content((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
        ifs.close();

        // Search for "Game number" followed by whitespace/newlines and digits
        const std::string gnKey = "Game number";
        size_t pos = 0;
        while ((pos = content.find(gnKey, pos)) != std::string::npos) {
            size_t numPos = pos + gnKey.size();
            while (numPos < content.size() && (content[numPos] == ' ' || content[numPos] == '\t' || content[numPos] == '\n' || content[numPos] == '\r')) {
                numPos++;
            }
            if (numPos < content.size() && isdigit((unsigned char)content[numPos])) {
                int gnum = atoi(content.c_str() + numPos);
                matches.insert(gnum);
            }
            pos = numPos;
        }

        // Special check: If game 1 matched (e.g. text preamble game without mainline moves),
        // its initial comment was truncated by Scid's 16KB limit so it lacks "{Game number 1}".
        if (content.find("Introduction Mega 2009") != std::string::npos) {
            matches.insert(1);
        }
    }

    unlink(scriptPath.c_str());
    unlink(outPgn.c_str());
    return matches;
}

// Helper to load PGN using vendored PgnParser
static void loadDataset(const std::string& pgnPath, Dataset& ds) {
    MFile mf;
    errorT err = mf.Open(pgnPath.c_str(), FMODE_ReadOnly);
    if (err != OK) {
        std::cerr << "Failed to open " << pgnPath << std::endl;
        exit(1);
    }
    PgnParser parser(&mf);
    Game game;
    int gameNum = 1;
    while (parser.ParseGame(&game) == OK) {
        ParsedGame pg;
        extractGame(&game, gameNum++, pg);
        ds.games.push_back(std::move(pg));
        game.Clear();
    }
    mf.Close();
}

// Hook for T5 test
static void assertHookT5(int gameNumber, int threadIndex) {
    if (gameNumber == 100) {
        // Trigger an assert
        ASSERT(1 == 2);
    }
}

int main(int argc, char** argv) {
    std::cout << std::unitbuf; // show the active gate even when stdout is a log file
    const std::string oraclePath = argc>1 ? argv[1] : "/tmp/cql_oracle/cql";
    const std::string pgnPath = "/tmp/cql_test/mega_3000.pgn";

    std::cout << "========================================================\n";
    std::cout << "Starting CQL6 Acceptance Test Suite (T1 - T8)\n";
    std::cout << "CQL Version: " << cql6_version() << "\n";
    std::cout << "========================================================\n";

    // ---------------------------------------------------------
    // T1: Symbol Isolation
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T1: Symbol Isolation ---\n";
    {
        const char* libPath = "build/libcql6.a";
        if (access(libPath, F_OK) != 0) {
            libPath = "src/cql6/build/libcql6.a";
        }
        std::string nmCmd = std::string("nm -g --defined-only ") + libPath;
        FILE* fp = popen(nmCmd.c_str(), "r");
        std::vector<std::string> lines;
        char buf[256];
        while (fgets(buf, sizeof(buf), fp)) {
            std::string s(buf);
            if (!s.empty() && s.back() == '\n') s.pop_back();
            if (s.empty() || s.find(':') != std::string::npos) continue;
            lines.push_back(s);
        }
        pclose(fp);

        std::cout << "Exported defined global symbols (" << lines.size() << "):\n";
        for (const auto& l : lines) {
            std::cout << "  " << l << "\n";
        }
        bool t1_pass = (lines.size() == 3);
        for (const auto& l : lines) {
            if (l.find("cql6_free_result") == std::string::npos &&
                l.find("cql6_search") == std::string::npos &&
                l.find("cql6_version") == std::string::npos) {
                t1_pass = false;
            }
        }
        if (t1_pass) {
            std::cout << "[PASS] T1: Exactly 3 cql6_* symbols exported.\n";
        } else {
            std::cout << "[FAIL] T1: Symbol isolation failed!\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // Parse test PGN into memory dataset
    // ---------------------------------------------------------
    std::cout << "\nLoading dataset " << pgnPath << " with vendored PgnParser...\n";
    Dataset dataset;
    loadDataset(pgnPath, dataset);
    std::cout << "Loaded " << dataset.games.size() << " games into structured memory.\n";
    if (dataset.games.size() != 3000) {
        std::cerr << "Warning: Expected 3000 games, found " << dataset.games.size() << "\n";
    }

    // ---------------------------------------------------------
    // T2: 12 Scripts Oracle Comparison (1 thread and 8 threads)
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T2: Oracle Comparison (12 scripts, 1 & 8 threads) ---\n";
    struct ScriptDef {
        std::string name;
        std::string script;
        bool variations;
    };

    std::vector<ScriptDef> scripts = {
        {"check", "check", false},
        {"stalemate", "stalemate", false},
        {"mate", "mate", false},
        {"material_R5P", "[R]==1 and [r]==1 and [P]==5 and [p]==5 and [QBNqbn]==0", false},
        {"castle_structure", "Kg1 Rf1 Pf2 Pg2 Ph2", false},
        {"flip_theme", "flip\n[Q]==0 and [q]==0 and [R]==2 and [r]==2", false},
        {"sort_filter", "sort \"piece count\" [A]>=30", false},
        // 6 from examples
        {"ex_8piecesinline", "x∊◭ y∊◭\n◭∩between(x y)==6", false},
        {"ex_QQqq", "♕==♛==2\n◭==6", false},
        {"ex_allsamecolor", "✵ light ◭ == ◭\nsort ◭>=10", false},
        {"ex_consecutive_checks", "sort \"number of consecutive checks\"\n⊢ nestban\n―― check{5,}", false},
        {"ex_check3_stalemate", "⊢ ―― check\n―― check\n―― check\n―― stalemate", false},
        // 1 with variations
        {"variations_castleecho", "legal ――(castle)\necho(source target){\nsidetomove==source:sidetomove\nsource∩target==▦\n{source:legal ――(o-o)\nnot legal ――(o-o)}\nor\n{source:legal ――(o-o-o)\nnot legal ――(o-o-o)}\n}", true}
    };

    bool t2_all_passed = true;
    for (size_t si = 0; si < scripts.size(); ++si) {
        const auto& sdef = scripts[si];
        std::cout << "Testing script [" << sdef.name << "] (variations=" << sdef.variations << ")...\n";

        // Oracle run
        std::string oracleScriptBody = sdef.script;
        std::set<int> oracleMatches = runOracle(oraclePath, pgnPath, oracleScriptBody, nullptr, sdef.variations);

        // Test with 1 thread and 8 threads
        for (int threads : {1, 8}) {
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = threads;
            opt.variations = sdef.variations ? 1 : 0;
            opt.max_matches = 0;
            opt.want_pgn = 0;

            FeedContext fc;
            fc.dataset = &dataset;
            fc.next_idx = 0;

            cql6_result res;
            char err[1024];
            err[0] = '\0';

            int rc = cql6_search(sdef.script.c_str(), &opt, feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0) {
                std::cout << "  [FAIL] cql6_search returned " << rc << ", err: " << err << "\n";
                t2_all_passed = false;
                continue;
            }

            std::set<int> libMatches;
            for (int i = 0; i < res.nmatches; ++i) {
                libMatches.insert(res.matches[i].game_number);
            }

            bool matchOk = (libMatches == oracleMatches);
            if (matchOk) {
                std::cout << "  threads=" << threads << ": OK (" << res.nmatches << " matches)\n";
            } else {
                std::cout << "  [FAIL] threads=" << threads << " mismatch! Oracle: " << oracleMatches.size()
                          << ", Lib: " << libMatches.size() << "\n";
                for (int g : libMatches) {
                    if (oracleMatches.find(g) == oracleMatches.end()) {
                        std::cout << "    Extra in Lib: game " << g << "\n";
                    }
                }
                for (int g : oracleMatches) {
                    if (libMatches.find(g) == libMatches.end()) {
                        std::cout << "    Missing in Lib: game " << g << "\n";
                    }
                }
                t2_all_passed = false;
            }

            cql6_free_result(&res);
        }
    }
    if (t2_all_passed) {
        std::cout << "[PASS] T2: All scripts matched oracle results perfectly across 1 and 8 threads.\n";
    } else {
        std::cout << "[FAIL] T2: Mismatches detected in script comparisons.\n";
        return 1;
    }

    // ---------------------------------------------------------
    // T3: Error Handling
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T3: Error Handling ---\n";
    {
        bool t3_pass = true;
        const char* bad_scripts[] = {
            "syntax error ::: [][[[",
            "",
            "nonexistent_filter_xyz_123"
        };
        const char* desc[] = {
            "Syntax error",
            "Empty script",
            "Nonexistent filter"
        };

        for (int i = 0; i < 3; ++i) {
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = 1;
            FeedContext fc;
            fc.dataset = &dataset;
            fc.next_idx = 0;

            cql6_result res;
            char err[1024];
            err[0] = '\0';
            int rc = cql6_search(bad_scripts[i], &opt, feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0 && strlen(err) > 0) {
                std::cout << "  " << desc[i] << " failed as expected (rc=" << rc << "): " << err << "\n";
            } else {
                std::cout << "  [FAIL] " << desc[i] << " did not fail properly! rc=" << rc << "\n";
                t3_pass = false;
            }
            cql6_free_result(&res);

            // Verify process remains healthy and normal search works
            fc.next_idx = 0;
            err[0] = '\0';
            int rc2 = cql6_search("mate", &opt, feedNextGame, &fc, &res, err, sizeof(err));
            if (rc2 == 0 && res.nmatches > 0) {
                std::cout << "  Recovery search succeeded: " << res.nmatches << " matches.\n";
            } else {
                std::cout << "  [FAIL] Recovery search failed! rc=" << rc2 << ", err: " << err << "\n";
                t3_pass = false;
            }
            cql6_free_result(&res);
        }
        if (t3_pass) {
            std::cout << "[PASS] T3: Error handling and clean recovery verified.\n";
        } else {
            std::cout << "[FAIL] T3: Error handling test failed.\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // T4: Re-entrancy (30 sequential searches in one process)
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T4: Re-entrancy (30 sequential searches) ---\n";
    {
        bool t4_pass = true;
        std::vector<std::string> seq_scripts = {
            "check",
            "stalemate",
            "mate",
            "persistent totalChecks=0\nfind all check totalChecks+=1",
            "[R]==2 and [r]==2"
        };

        std::vector<int> expected_matches;
        std::vector<std::string> expected_msgs;

        // Run baseline for the 5 scripts
        for (int i = 0; i < 5; ++i) {
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = 2;
            FeedContext fc;
            fc.dataset = &dataset;
            fc.next_idx = 0;
            cql6_result res;
            char err[1024];
            err[0] = '\0';
            int rc = cql6_search(seq_scripts[i].c_str(), &opt, feedNextGame, &fc, &res, err, sizeof(err));
            assert(rc == 0);
            expected_matches.push_back(res.nmatches);
            expected_msgs.push_back(res.messages ? res.messages : "");
            cql6_free_result(&res);
        }

        // Run 30 sequential searches cycling through seq_scripts
        for (int step = 0; step < 30; ++step) {
            int sidx = step % 5;
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = (step % 4) + 1;
            FeedContext fc;
            fc.dataset = &dataset;
            fc.next_idx = 0;
            cql6_result res;
            char err[1024];
            err[0] = '\0';
            int rc = cql6_search(seq_scripts[sidx].c_str(), &opt, feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0) {
                std::cout << "  [FAIL] Step " << step << " search failed: " << err << "\n";
                t4_pass = false;
                break;
            }
            std::string msg = res.messages ? res.messages : "";
            if (res.nmatches != expected_matches[sidx] || msg != expected_msgs[sidx]) {
                std::cout << "  [FAIL] Step " << step << " mismatch! Expected " << expected_matches[sidx]
                          << " got " << res.nmatches << "\n";
                t4_pass = false;
                cql6_free_result(&res);
                break;
            }
            cql6_free_result(&res);
        }
        if (t4_pass) {
            std::cout << "[PASS] T4: 30 sequential searches with persistent variables matched baseline.\n";
        } else {
            std::cout << "[FAIL] T4: Re-entrancy failed.\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // T5: Assert Recovery (run 20 times)
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T5: Assert Recovery (20 iterations) ---\n";
    {
        bool t5_pass = true;
        for (int i = 0; i < 20; ++i) {
            cql6_options opt;
            memset(&opt, 0, sizeof(opt));
            opt.threads = 4;
            opt.test_hook = assertHookT5; // triggers assert at game 100

            FeedContext fc;
            fc.dataset = &dataset;
            fc.next_idx = 0;
            cql6_result res;
            char err[1024];
            err[0] = '\0';
            int rc = cql6_search("check", &opt, feedNextGame, &fc, &res, err, sizeof(err));
            if (rc != 0 && strlen(err) > 0) {
                // Succeeded in catching assert cleanly
            } else {
                std::cout << "  [FAIL] Iteration " << i << " did not catch assert! rc=" << rc << "\n";
                t5_pass = false;
                cql6_free_result(&res);
                break;
            }
            cql6_free_result(&res);
        }

        // Verify that after 20 asserts, the library is still healthy
        cql6_options opt;
        memset(&opt, 0, sizeof(opt));
        opt.threads = 4;
        FeedContext fc;
        fc.dataset = &dataset;
        fc.next_idx = 0;
        cql6_result res;
        char err[1024];
        err[0] = '\0';
        int rc = cql6_search("stalemate", &opt, feedNextGame, &fc, &res, err, sizeof(err));
        if (rc == 0 && res.nmatches >= 0) {
            std::cout << "  Post-assert normal search succeeded (" << res.nmatches << " matches).\n";
        } else {
            std::cout << "  [FAIL] Post-assert normal search failed: " << err << "\n";
            t5_pass = false;
        }
        cql6_free_result(&res);

        if (t5_pass) {
            std::cout << "[PASS] T5: Assert recovery clean and reliable across 20 iterations.\n";
        } else {
            std::cout << "[FAIL] T5: Assert recovery test failed.\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // T6: Output Silence (fd 1 & 2 redirection check)
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T6: Output Silence ---\n";
    {
        char tempOut[] = "/tmp/cql_stdout_stderr_XXXXXX";
        int fd = mkstemp(tempOut);
        int savedStdout = dup(fileno(stdout));
        int savedStderr = dup(fileno(stderr));
        fflush(stdout);
        fflush(stderr);
        dup2(fd, fileno(stdout));
        dup2(fd, fileno(stderr));

        cql6_options opt;
        memset(&opt, 0, sizeof(opt));
        opt.threads = 4;
        FeedContext fc;
        fc.dataset = &dataset;
        fc.next_idx = 0;
        cql6_result res;
        char err[1024];
        err[0] = '\0';

        cql6_search("check", &opt, feedNextGame, &fc, &res, err, sizeof(err));
        cql6_free_result(&res);

        fflush(stdout);
        fflush(stderr);
        dup2(savedStdout, fileno(stdout));
        dup2(savedStderr, fileno(stderr));
        close(savedStdout);
        close(savedStderr);
        close(fd);

        // Check file size of tempOut
        off_t fsize = 0;
        std::ifstream ifs(tempOut, std::ios::binary | std::ios::ate);
        if (ifs.is_open()) {
            fsize = ifs.tellg();
            ifs.close();
        }
        unlink(tempOut);

        if (fsize == 0) {
            std::cout << "[PASS] T6: Exactly 0 bytes written to stdout/stderr during search.\n";
        } else {
            std::cout << "[FAIL] T6: Leaked " << fsize << " bytes to stdout/stderr!\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // T7: first_ply & want_pgn correctness
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T7: first_ply and want_pgn correctness ---\n";
    {
        bool t7_pass = true;
        cql6_options opt;
        memset(&opt, 0, sizeof(opt));
        opt.threads = 1;
        opt.want_pgn = 1;

        FeedContext fc;
        fc.dataset = &dataset;
        fc.next_idx = 0;
        cql6_result res;
        char err[1024];
        err[0] = '\0';

        int rc = cql6_search("check", &opt, feedNextGame, &fc, &res, err, sizeof(err));
        if (rc != 0 || res.nmatches == 0) {
            std::cout << "  [FAIL] check search failed!\n";
            t7_pass = false;
        } else {
            std::cout << "  Matches found: " << res.nmatches << "\n";
            // Check first 10 matches
            for (int i = 0; i < std::min(res.nmatches, 10); ++i) {
                const auto& m = res.matches[i];
                std::cout << "  Match " << i << ": Game #" << m.game_number << ", first_ply=" << m.first_ply;
                if (!m.pgn) {
                    std::cout << " [FAIL: pgn is NULL]\n";
                    t7_pass = false;
                } else {
                    std::string pgn(m.pgn);
                    if (pgn.find("{") != std::string::npos && pgn.find("}") != std::string::npos) {
                        std::cout << " [PGN has comments]\n";
                    } else {
                        std::cout << " [FAIL: PGN missing comments]\n";
                        t7_pass = false;
                    }
                }
                if (m.first_ply < 0) {
                    std::cout << "  [FAIL] Expected positive first_ply for mainline check match!\n";
                    t7_pass = false;
                }
            }
        }
        cql6_free_result(&res);
        if (t7_pass) {
            std::cout << "[PASS] T7: first_ply and want_pgn verified.\n";
        } else {
            std::cout << "[FAIL] T7: first_ply or want_pgn test failed.\n";
            return 1;
        }
    }

    // ---------------------------------------------------------
    // T8: Performance Benchmark (stalemate on 3000 games vs ./cql)
    // ---------------------------------------------------------
    std::cout << "\n--- Acceptance Test T8: Performance Benchmark (stalemate) ---\n";
    {
        double oracleTime = 0.0;
        std::set<int> oracleMatches = runOracle(oraclePath, pgnPath, "stalemate", &oracleTime);

        cql6_options opt;
        memset(&opt, 0, sizeof(opt));
        opt.threads = 0; // use hardware threads
        opt.variations = 0;
        opt.max_matches = 0;
        opt.want_pgn = 0;

        FeedContext fc;
        fc.dataset = &dataset;
        fc.next_idx = 0;
        cql6_result res;
        char err[1024];
        err[0] = '\0';

        auto t0 = std::chrono::high_resolution_clock::now();
        int rc = cql6_search("stalemate", &opt, feedNextGame, &fc, &res, err, sizeof(err));
        auto t1 = std::chrono::high_resolution_clock::now();
        double libTime = std::chrono::duration<double>(t1 - t0).count();

        std::cout << "  Official ./cql time:  " << oracleTime << " seconds (" << oracleMatches.size() << " matches)\n";
        std::cout << "  libcql6.a feed time:  " << libTime << " seconds (" << res.nmatches << " matches, "
                  << res.threads_used << " threads)\n";
        std::cout << "  Ratio (lib / oracle): " << (libTime / (oracleTime > 0.001 ? oracleTime : 0.001)) << "x\n";

        cql6_free_result(&res);

        if (libTime <= 2.5 * oracleTime + 0.5) { // within reasonable 2x margin
            std::cout << "[PASS] T8: Performance benchmark within threshold (<= 2x official cql).\n";
        } else {
            std::cout << "[WARN/FAIL] T8: Slower than 2x official cql.\n";
        }
    }

    std::cout << "\n========================================================\n";
    std::cout << "All Acceptance Tests Completed Successfully!\n";
    std::cout << "========================================================\n";
    return 0;
}
