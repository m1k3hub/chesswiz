// scidb: shared test helpers: load a PGN with the vendored PgnParser into
// cql6_game structures, feed them to cql6_search, and run the official ./cql
// as an oracle (extracting matched game numbers, order and first_ply).
#pragma once
#include "cql6_api.h"
#include "orig/game.h"
#include "orig/pgnparse.h"
#include "orig/mfile.h"
#include "orig/date.h"
#include "orig/misc.h"
#include "orig/position.h"
#include "pgnsource.h"

#include <string>
#include <vector>
#include <deque>
#include <set>
#include <map>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cctype>
#include <chrono>
#include <fstream>
#include <sstream>
#include <iostream>

struct ParsedGame {
    int number = 0;
    std::string fen;
    std::vector<std::pair<std::string, std::string>> tags;
    std::vector<cql6_move> moves;
    // scidb: deque, not vector: fc_convertMoves stores c_str() pointers into this and
    // vector reallocation would dangle them (ASan heap-use-after-free in the driver)
    std::deque<std::string> comments; // backing storage for move comments
};

struct Dataset {
    // scidb: deque, not vector: ParsedGame holds cql6_move.comment pointers into its own
    // comments deque; vector reallocation would move/free the games and dangle them
    std::deque<ParsedGame> games;
};

// Recursive move converter from Scid Game tree to cql6_move vector
static void fc_convertMoves(Game* game, moveT* m, std::vector<cql6_move>& outMoves, std::deque<std::string>& outComments) {
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

        if (m->numVariations > 0 && m->varChild) {
            moveT* varStart = m->varChild;
            while (varStart) {
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
                fc_convertMoves(game, varStart->next, outMoves, outComments);
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

static void fc_extractGame(Game* game, int gameNum, ParsedGame& pg) {
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

    moveT* first = game->GetFirstMove();
    if (first && first->next) {
        fc_convertMoves(game, first->next, pg.moves, pg.comments);
    }
}

// Load with the same machinery as the standalone program: PgnSource splits the file
// into one text buffer per game (defining the game numbers), PgnParser parses each
// buffer. Games that PgnSource emits but the parser rejects beyond repair are still
// counted (exactly like QGame::pgnParseNextGame does), so numbering matches the oracle.
static bool fc_loadDataset(const std::string& pgnPath, Dataset& ds) {
    PgnSource source(pgnPath);
    static std::vector<char> buffer(1000000);
    PgnParser parser;
    Game game;
    int gameNumber = 0, charsread = 0, linesstart = 0;
    while (source.nextGame(buffer.data(), (int)buffer.size(), &gameNumber, &charsread, &linesstart)) {
        parser.Init(buffer.data());
        errorT err = parser.ParseGame(&game);
        if (err == ERROR_NotFound) {
            std::cerr << "[warn] game " << gameNumber << ": parser found no game (skipped)\n";
            game.Clear();
            continue;
        }
        {
            ParsedGame pg;
            fc_extractGame(&game, gameNumber, pg);
            ds.games.push_back(std::move(pg));
        }
        game.Clear();
    }
    return !ds.games.empty();
}

struct FeedContext {
    const Dataset* dataset;
    size_t next_idx;
    std::vector<std::vector<cql6_tag>> thread_tag_bufs;
};

static int fc_feedNextGame(void* ctx, int thread, cql6_game* g) {
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

// ---- oracle side ----

struct OracleMatch {
    int game_number = -1;
    int first_ply = -1;   // ply of the first mainline {CQL} comment; -1 if none in mainline
};

struct OracleResult {
    int exit_status = -1;
    std::vector<OracleMatch> ordered;          // in the order the oracle wrote them
    std::set<int> games;
    std::map<int, int> firstPlyByGame;
    double seconds = 0;
    std::string stdoutText;
};

// Does this comment contain the CQL match annotation (as a whole word)?
static bool fc_hasCqlToken(const char* c) {
    if (!c) return false;
    const char* p = c;
    while ((p = strstr(p, "CQL")) != nullptr) {
        bool leftOk = (p == c) || !(isalnum((unsigned char)p[-1]) || p[-1] == '_');
        const char* after = p + 3;
        bool rightOk = (*after == 0) || !(isalnum((unsigned char)*after) || *after == '_');
        if (leftOk && rightOk) return true;
        p = after;
    }
    return false;
}

// first {CQL} mainline ply of one parsed game; -1 if the mainline has none.
static int fc_firstCqlPly(Game* g) {
    moveT* m = g->GetFirstMove();
    int ply = 0;
    while (m) {
        if (m->marker != END_MARKER) {
            if (fc_hasCqlToken(m->comment)) return ply; // comment on this node annotates position ply
            ply++;
        } else {
            if (fc_hasCqlToken(m->comment)) return ply;
        }
        m = m->next;
    }
    return -1;
}

static int fc_gameNumberFromComment(Game* g) {
    moveT* m = g->GetFirstMove();
    if (!m || !m->comment) return -1;
    const char* p = strstr(m->comment, "Game number");
    if (!p) return -1;
    p += strlen("Game number");
    while (*p && (isspace((unsigned char)*p))) p++;
    if (!*p || !isdigit((unsigned char)*p)) return -1;
    return atoi(p);
}

// Run the official ./cql oracle. `scriptBody` is the CQL body; the header is generated.
// If wantOutput is false, only the set of game numbers is filled in (fast path via grep
// of the output PGN); otherwise the output PGN is re-parsed with the vendored PgnParser
// to extract order and first_ply.
static OracleResult fc_runOracle(const std::string& oraclePath, const std::string& pgnPath,
                                 const std::string& scriptBody, bool wantOutput = true,
                                 bool variations = false) {
    OracleResult res;
    char tmpdir[] = "/tmp/cql_oracle_run_XXXXXX";
    if (!mkdtemp(tmpdir)) { perror("mkdtemp"); return res; }
    std::string base(tmpdir);
    std::string scriptPath = base + "/script.cql";
    std::string outPgn = base + "/out.pgn";

    {
        std::ofstream ofs(scriptPath);
        ofs << "cql(input " << pgnPath << " output " << outPgn
            << (variations ? " variations" : "") << ")\n" << scriptBody << "\n";
    }

    std::string cmd = oraclePath + " " + scriptPath + " > " + base + "/stdout.txt 2>&1";
    auto t0 = std::chrono::high_resolution_clock::now();
    int rc = system(cmd.c_str());
    res.exit_status = rc;
    auto t1 = std::chrono::high_resolution_clock::now();
    res.seconds = std::chrono::duration<double>(t1 - t0).count();

    if (wantOutput) {
        MFile mf;
        if (mf.Open(outPgn.c_str(), FMODE_ReadOnly) == OK) {
            PgnParser parser(&mf);
            Game game;
            while (parser.ParseGame(&game) == OK) {
                OracleMatch om;
                om.game_number = fc_gameNumberFromComment(&game);
                om.first_ply = fc_firstCqlPly(&game);
                if (om.game_number >= 0) {
                    res.ordered.push_back(om);
                    res.games.insert(om.game_number);
                    // keep the smallest mainline ply seen for the game
                    auto it = res.firstPlyByGame.find(om.game_number);
                    if (it == res.firstPlyByGame.end() || (om.first_ply >= 0 && (it->second < 0 || om.first_ply < it->second)))
                        res.firstPlyByGame[om.game_number] = om.first_ply;
                } else {
                    // game 1 of mega_full is an HTML text game whose huge pre-game comment hits
                    // Scid's comment size limit; identify it by its Event tag.
                    const char* ev = game.GetEventStr();
                    if (ev && strstr(ev, "Introduction Mega") != nullptr) {
                        OracleMatch om2;
                        om2.game_number = 1;
                        om2.first_ply = om.first_ply;
                        res.ordered.push_back(om2);
                        res.games.insert(1);
                        res.firstPlyByGame[1] = om2.first_ply;
                    } else {
                        std::cerr << "  [warn] oracle output game without parsable 'Game number' comment\n";
                    }
                }
                game.Clear();
            }
            mf.Close();
        }
    } else {
        std::ifstream ifs(outPgn, std::ios::binary);
        if (ifs.is_open()) {
            std::string content((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
            const std::string gnKey = "Game number";
            size_t pos = 0;
            while ((pos = content.find(gnKey, pos)) != std::string::npos) {
                size_t numPos = pos + gnKey.size();
                while (numPos < content.size() && isspace((unsigned char)content[numPos])) numPos++;
                if (numPos < content.size() && isdigit((unsigned char)content[numPos])) {
                    int gnum = atoi(content.c_str() + numPos);
                    res.games.insert(gnum);
                    OracleMatch om; om.game_number = gnum; om.first_ply = -1;
                    res.ordered.push_back(om);
                }
                pos = numPos;
            }
        }
    }
    {
        std::ifstream sf(base + "/stdout.txt", std::ios::binary);
        if (sf.is_open())
            res.stdoutText.assign((std::istreambuf_iterator<char>(sf)), std::istreambuf_iterator<char>());
    }
    std::string rm = "rm -rf " + base;
    if (system(rm.c_str())) {}
    return res;
}
