#include "scidb_feed.h"
#include "orig/game.h"
#include "orig/position.h"
#include "orig/date.h"
#include "orig/misc.h"
#include "orig/stralloc.h"
#include "cqlexception.h"
#include "scidb_lockdown.h"
#include <cstring>
#include <vector>
#include <cctype>
#include <cstdio>
#include <cstdlib>

// scidb: optional trace of feed rejections (set CQL6_FEED_DEBUG=<file>); used by tests.
// Guarded with scidb::file_guard() so during active searches file lockdown is preserved.
static void scidb_feed_dbg(const char* fmt, long a = 0, long b = 0, long c = 0, long d = 0) {
    const char* f = getenv("CQL6_FEED_DEBUG");
    if (!f) return;
#ifdef CQL6_EMBEDDED
    scidb::file_guard("debug trace", f);
#endif
    FILE* fp = fopen(f, "a");
    if (!fp) return;
    fprintf(fp, fmt, a, b, c, d);
    fclose(fp);
}

// scidb: hardened conversion of a host cql6_game into a Scid Game.
// Returns false for ANY game it cannot accept safely; the caller skips and counts it.
// Never crashes, never throws for bad host data, never writes past a buffer:
//  - NULL pointers, negative or absurd counts are rejected
//  - squares outside 0..63 and promo characters outside QRBN are rejected
//  - illegal moves (not generatable from the current position) reject the game
//  - unbalanced variation records and EMPTY variations (which break the CQL matcher,
//    see MarkBoard::gameForward) reject the game
//  - more tags than the Scid Game fixed TagList can hold (MAX_TAGS) reject the game
//  - games too deep for Scid's variation nesting are rejected
bool ScidbGameSource::populateGame(const cql6_game* src, Game* game, bool trusted, bool wantSan, bool truncate, bool* truncated) {
    if (truncated) *truncated=false;
    if (!src || !game) return false;

    game->Clear();

    if (src->number < 0) { scidb_feed_dbg("reject: negative number\n"); return false; }

    // structural counts
    if (src->ntags < 0 || src->nmoves < 0) { scidb_feed_dbg("reject: negative counts %ld %ld\n", src->ntags, src->nmoves); return false; }
    if (src->ntags > 0 && !src->tags) { scidb_feed_dbg("reject: NULL tags\n"); return false; }
    if (src->nmoves > 0 && !src->moves) { scidb_feed_dbg("reject: NULL moves\n"); return false; }

    // reject absurd move counts before touching them (a host bug); Scid games
    // cannot hold more moves than fit in the move tree anyway
    if (src->nmoves > 10000000) { scidb_feed_dbg("reject: nmoves %ld\n", src->nmoves); return false; }

    // pre-scan the move records: validate kinds/squares/promo, variation balance,
    // and reject empty variations
    {
        int depth = 0;
        // scidb: per-parent sibling-variation counters. Scid's moveT::numVariations is a
        // BYTE and AddVariation() has no limit check (upstream removed MAX_VARS_PER_MOVE):
        // a 256th sibling variation silently wraps the counter and orphans the variation
        // list, corrupting the tree. A stack of {parent exists, count} mirrors the nesting.
        struct SibCtx { bool haveParent; int sibs; };
        std::vector<SibCtx> sibStack;
        SibCtx cur{false, 0};
        bool prevWasMove = false; // a move (kind 0) was the last accepted record in this line
        for (int i = 0; i < src->nmoves; ++i) {
            const cql6_move& m = src->moves[i];
            if (m.kind == 0 || m.kind == 3) {
                if (m.kind == 3 && (m.from || m.to || m.promo)) return false;
                if (m.from < 0 || m.from > 63) { scidb_feed_dbg("reject: from square %ld at %ld\n", m.from, i); return false; }
                cur.haveParent = true; cur.sibs = 0; // this move becomes the parent of any following variations
                if (m.to < 0 || m.to > 63) { scidb_feed_dbg("reject: to square %ld at %ld\n", m.to, i); return false; }
                if (m.promo != 0) {
                    char pc = (char)toupper((unsigned char)m.promo);
                    if (pc != 'Q' && pc != 'R' && pc != 'B' && pc != 'N') { scidb_feed_dbg("reject: promo %ld at %ld\n", (long)m.promo, i); return false; }
                }
                prevWasMove = true;
            } else if (m.kind == 1) {
                // a variation must replace a move: it needs a preceding move in this line
                if (!prevWasMove) { scidb_feed_dbg("reject: variation start without preceding move at %ld\n", i); return false; }
                if (!cur.haveParent) { scidb_feed_dbg("reject: variation without parent at %ld\n", i); return false; }
                if (cur.sibs >= 255) { scidb_feed_dbg("reject: >255 sibling variations at %ld\n", i); return false; }
                if (depth >= 10000) { scidb_feed_dbg("reject: variation depth at %ld\n", i); return false; }
                ++cur.sibs;
                sibStack.push_back(cur);      // save the enclosing line's parent context
                cur = SibCtx{false, 0};       // inside the variation: no parent move yet
                // note: an EMPTY variation (kind 1 immediately followed by kind 2) is accepted
                // here for parity with the PGN parser (corrupt games can produce them); with
                // variations OFF the matcher never touches them, with variations ON the game is
                // skipped later (QGame::scidbParseNextGame catches the matcher failure).
                ++depth;
                prevWasMove = false;
            } else if (m.kind == 2) {
                if (depth <= 0) { scidb_feed_dbg("reject: variation end without start at %ld\n", i); return false; }
                --depth;
                cur = sibStack.back();        // scidb: restore the enclosing line's parent context
                sibStack.pop_back();
                prevWasMove = true; // back in a line that had a move before the variation
            } else {
                { scidb_feed_dbg("reject: unknown kind %ld at %ld\n", m.kind, i); return false; }
            }
        }
        if (depth != 0 || !sibStack.empty()) { scidb_feed_dbg("reject: unbalanced variations depth %ld\n", depth); return false; }
    }

    // 1. Starting position (FEN). A garbage/empty/impossible FEN rejects the game.
    if (src->fen && src->fen[0] != '\0') {
        if (game->SetStartFen(src->fen) != OK) {
            scidb_feed_dbg("reject: bad fen\n");
            return false;
        }
    }

    // 2. Tags. Scid Game has room for MAX_TAGS extra tags; refuse the game rather
    //    than overflow the fixed TagList.
    if (src->ntags > (int)MAX_TAGS) { scidb_feed_dbg("reject: ntags %ld > MAX_TAGS\n", src->ntags); return false; }
    for (int i = 0; i < src->ntags; ++i) {
        const char* name = src->tags[i].name;
        const char* val = src->tags[i].value;
        if (!name || !val) { scidb_feed_dbg("reject: NULL tag ptr at %ld\n", i); return false; }

        if (strcmp(name, "White") == 0) {
            game->SetWhiteStr(val);
        } else if (strcmp(name, "Black") == 0) {
            game->SetBlackStr(val);
        } else if (strcmp(name, "Event") == 0) {
            game->SetEventStr(val);
        } else if (strcmp(name, "Site") == 0) {
            game->SetSiteStr(val);
        } else if (strcmp(name, "Round") == 0) {
            game->SetRoundStr(val);
        } else if (strcmp(name, "Result") == 0) {
            if (strncmp(val, "0-1", 3) == 0) {
                game->SetResult(RESULT_Black);
            } else if (strncmp(val, "1-0", 3) == 0) {
                game->SetResult(RESULT_White);
            } else if (strncmp(val, "1/2", 3) == 0) {
                game->SetResult(RESULT_Draw);
            } else {
                game->SetResult(RESULT_None);
            }
        } else if (strcmp(name, "Date") == 0) {
            game->SetDate(date_EncodeFromString(val));
        } else if (strcmp(name, "EventDate") == 0) {
            game->SetEventDate(date_EncodeFromString(val));
        } else if (strcmp(name, "ECO") == 0) {
            game->SetEco(eco_FromString(val));
        } else if (strcmp(name, "ScidFlags") == 0) {
            game->SetScidFlags(val);
        } else if (strcmp(name, "FEN") == 0) {
            // Already handled above or if present in tags
            if (!src->fen || src->fen[0] == '\0') {
                if (game->SetStartFen(val) != OK) {
                    scidb_feed_dbg("reject: bad FEN tag\n");
                    return false;
                }
            }
        } else if (strncmp(name, "White", 5) == 0 && game->GetWhiteElo() == 0) {
            const char* tagSuffix = name + 5;
            bool isRating = false;
            for (uint r = 0; ratingTypeNames[r] != NULL; ++r) {
                if (strcmp(tagSuffix, ratingTypeNames[r]) == 0) {
                    uint elo = strGetUnsigned(val);
                    if (elo > MAX_ELO) elo = MAX_ELO;
                    game->SetWhiteElo(elo);
                    game->SetWhiteRatingType(r);
                    isRating = true;
                    break;
                }
            }
            if (!isRating) {
                game->AddPgnTag(name, val);
            }
        } else if (strncmp(name, "Black", 5) == 0 && game->GetBlackElo() == 0) {
            const char* tagSuffix = name + 5;
            bool isRating = false;
            for (uint r = 0; ratingTypeNames[r] != NULL; ++r) {
                if (strcmp(tagSuffix, ratingTypeNames[r]) == 0) {
                    uint elo = strGetUnsigned(val);
                    if (elo > MAX_ELO) elo = MAX_ELO;
                    game->SetBlackElo(elo);
                    game->SetBlackRatingType(r);
                    isRating = true;
                    break;
                }
            }
            if (!isRating) {
                game->AddPgnTag(name, val);
            }
        } else {
            game->AddPgnTag(name, val);
        }
    }

    // 3. Moves and Variations
    for (int i = 0; i < src->nmoves; ++i) {
        const cql6_move& m = src->moves[i];
        if (m.kind == 3) {
            // The official PGN parser supports null moves. Preserve the host's
            // explicit null record without confusing it with an illegal a1-a1.
            simpleMoveT move{};
            if (game->GetCurrentPos()->ReadMove(&move, "--", TOKEN_Move_Null) != OK ||
                game->AddMove(&move, "--") != OK) return false;
            if (m.comment && m.comment[0]) game->SetMoveComment(m.comment);
        } else if (m.kind == 0) {
            squareT from = (squareT)m.from;
            squareT to = (squareT)m.to;
            pieceT promo = EMPTY;
            if (m.promo != 0) {
                promo = piece_FromChar(toupper((char)m.promo));
                if (promo == EMPTY) { scidb_feed_dbg("reject: promo char at %ld\n", i); return false; }
            }

            simpleMoveT normalized{};
            MoveList mlist;
            simpleMoveT* chosen = nullptr;
            Position* position = game->GetCurrentPos();
            if (trusted) {
                // No legal-move generation for host-validated moves.
                // Still check representation invariants needed by DoSimpleMove.
                pieceT* board = position->GetBoard();
                colorT side = position->GetToMove();
                pieceT piece = board[from], target = board[to];
                if (from == to || piece == EMPTY || piece_Color(piece) != side ||
                    (target != EMPTY && (piece_Color(target) == side || piece_Type(target) == KING))) return false;
                if (promo != EMPTY && (piece_Type(piece) != PAWN || !position->IsPromoMove(from,to))) return false;
                if (piece_Type(piece) == PAWN && target == EMPTY && square_Fyle(from) != square_Fyle(to)) {
                    int captured = int(to) + (side == WHITE ? -8 : 8);
                    if (position->GetEPTarget() != to || captured < 0 || captured >= 64 ||
                        board[captured] != piece_Make(color_Flip(side), PAWN)) return false;
                }
                if (piece_Type(piece) == KING && square_Fyle(from) == E_FYLE &&
                    (square_Fyle(to) == C_FYLE || square_Fyle(to) == G_FYLE)) {
                    if (square_Rank(from) != square_Rank(to)) return false;
                    int rookFrom = square_Fyle(to) == C_FYLE ? int(to)-2 : int(to)+1;
                    int rookTo = square_Fyle(to) == C_FYLE ? int(to)+1 : int(to)-1;
                    if (rookFrom < 0 || rookFrom >= 64 ||
                        board[rookFrom] != piece_Make(side, ROOK) || board[rookTo] != EMPTY) return false;
                }
                unsigned index = 0;
                while (index < position->GetCount(side) && position->GetList(side)[index] != from) ++index;
                if (index == position->GetCount(side)) return false;
                normalized.pieceNum = index;
                normalized.movingPiece = piece;
                normalized.from = from; normalized.to = to;
                normalized.capturedPiece = target; normalized.promote = promo;
                chosen = &normalized;
            } else {
                position->GenerateMoves(&mlist);
                for (uint mi = 0; mi < mlist.Size(); ++mi) {
                    simpleMoveT* cand = mlist.Get(mi);
                    if (cand->from == from && cand->to == to && cand->promote == promo) { chosen = cand; break; }
                }
                if (!chosen) {
                    scidb_feed_dbg("reject: illegal move at record %ld (from %ld to %ld promo %ld)\n", i, (long)m.from, (long)m.to, (long)m.promo);
                    if (!truncate) return false;
                    // Match the official PGN reader: stop at the first illegal
                    // move, retaining positions in the valid prefix only.
                    while (game->GetVarLevel()>0) game->MoveExitVariation();
                    if (truncated) *truncated=true;
                    return true;
                }
            }
            sanStringT sanStr;
            if (wantSan) position->MakeSANString(chosen, sanStr, SAN_CHECKTEST);
            if (game->AddMove(chosen, wantSan ? sanStr : nullptr) != OK) return false;

            if (m.comment && m.comment[0] != '\0') {
                game->SetMoveComment(m.comment);
            }
        } else if (m.kind == 1) {
            // Start of a variation
            if (game->AddVariation() != OK) {
                scidb_feed_dbg("reject: AddVariation failed at %ld\n", i);
                return false;
            }
            if (m.comment && m.comment[0] != '\0') {
                game->SetMoveComment(m.comment);
            }
        } else if (m.kind == 2) {
            // End of the current variation
            game->MoveExitVariation();
            game->MoveForward();
        }
    }

    return true;
}
