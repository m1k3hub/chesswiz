/*
  Narration for Stockfish — implementation.

  Structured position facts, computed directly from the Position bitboards.
  Shadow-only: nothing here reads or writes search state.
*/

#include "narration.h"

#include "attacks.h"
#include "bitboard.h"
#include "movegen.h"
#include "position.h"
#include "types.h"

#include <sstream>
#include <string>

namespace Stockfish {
namespace Narration {

namespace {

Bitboard IsolatedMask[64];
Bitboard PassedMask[2][64];
bool     MasksReady = false;

void initMasks() {
    if (MasksReady)
        return;
    MasksReady = true;

    for (int s = 0; s < 64; ++s)
    {
        int f = int(file_of(Square(s)));
        int r = int(rank_of(Square(s)));

        IsolatedMask[s] = (f > 0 ? file_bb(File(f - 1)) : Bitboard(0))
                        | (f < 7 ? file_bb(File(f + 1)) : Bitboard(0));

        for (Color c : {WHITE, BLACK})
        {
            Bitboard m = 0;
            for (int g = (f > 0 ? f - 1 : 0); g <= (f < 7 ? f + 1 : 7); ++g)
                for (int rr = 0; rr < 8; ++rr)
                    if ((c == WHITE && rr > r) || (c == BLACK && rr < r))
                        m |= square_bb(make_square(File(g), Rank(rr)));
            PassedMask[c][s] = m;
        }
    }
}

const char* colorName(Color c) { return c == WHITE ? "white" : "black"; }

int mobility(const Position& pos, Color c) {
    // squares attacked by the side, excluding own-occupied squares
    Bitboard att = pos.attacks_by<PAWN>(c) | pos.attacks_by<KNIGHT>(c) | pos.attacks_by<BISHOP>(c)
                 | pos.attacks_by<ROOK>(c) | pos.attacks_by<QUEEN>(c);
    return popcount(att & ~pos.pieces(c));
}

// Attacks of the piece standing on s (compile-time dispatch on its type).
Bitboard pieceAttacks(const Position& pos, Square s, PieceType pt, Color c) {
    switch (pt)
    {
    case PAWN: return Attacks::attacks_bb<PAWN>(s, c);
    case KNIGHT: return Attacks::attacks_bb<KNIGHT>(s);
    case BISHOP: return Attacks::attacks_bb<BISHOP>(s, pos.pieces());
    case ROOK: return Attacks::attacks_bb<ROOK>(s, pos.pieces());
    case QUEEN: return Attacks::attacks_bb<QUEEN>(s, pos.pieces());
    case KING: return Attacks::attacks_bb<KING>(s);
    default: return 0;
    }
}

int countPieces(const Position& pos, Color c, PieceType pt) {
    switch (pt)
    {
    case PAWN: return popcount(pos.pieces(c, PAWN));
    case KNIGHT: return popcount(pos.pieces(c, KNIGHT));
    case BISHOP: return popcount(pos.pieces(c, BISHOP));
    case ROOK: return popcount(pos.pieces(c, ROOK));
    case QUEEN: return popcount(pos.pieces(c, QUEEN));
    default: return 0;
    }
}

void appendPawns(std::ostringstream& ss, const Position& pos, Color c) {
    Bitboard own   = pos.pieces(c, PAWN);
    Bitboard enemy = pos.pieces(~c, PAWN);
    int      files[8] = {0, 0, 0, 0, 0, 0, 0, 0};

    int count = 0, doubled = 0, isolated = 0, passed = 0;

    for (Bitboard b = own; b;)
    {
        Square s = pop_lsb(b);
        ++count;
        files[int(file_of(s))]++;

        if (!(own & IsolatedMask[s]))
            ++isolated;
        if (!(enemy & PassedMask[c][s]))
            ++passed;
    }

    for (int f = 0; f < 8; ++f)
        if (files[f] > 1)
            doubled += files[f] - 1;

    int islands = 0;
    bool inIsland = false;
    for (int f = 0; f < 8; ++f)
    {
        if (files[f])
        {
            if (!inIsland) { ++islands; inIsland = true; }
        }
        else
            inIsland = false;
    }

    ss << "\"" << colorName(c) << "\":{";
    ss << "\"count\":" << count << ",";
    ss << "\"doubled\":" << doubled << ",";
    ss << "\"isolated\":" << isolated << ",";
    ss << "\"passed\":" << passed << ",";
    ss << "\"islands\":" << islands << ",";
    ss << "\"files\":[";
    for (int f = 0; f < 8; ++f) { if (f) ss << ","; ss << files[f]; }
    ss << "]}";
}

void appendMaterial(std::ostringstream& ss, const Position& pos, Color c) {
    int value = countPieces(pos, c, PAWN) * 100 + countPieces(pos, c, KNIGHT) * 320
              + countPieces(pos, c, BISHOP) * 330 + countPieces(pos, c, ROOK) * 500
              + countPieces(pos, c, QUEEN) * 900;

    ss << "\"" << colorName(c) << "\":{";
    ss << "\"pawns\":" << countPieces(pos, c, PAWN) << ",";
    ss << "\"knights\":" << countPieces(pos, c, KNIGHT) << ",";
    ss << "\"bishops\":" << countPieces(pos, c, BISHOP) << ",";
    ss << "\"rooks\":" << countPieces(pos, c, ROOK) << ",";
    ss << "\"queens\":" << countPieces(pos, c, QUEEN) << ",";
    ss << "\"valueCp\":" << value << ",";
    ss << "\"bishopPair\":" << (countPieces(pos, c, BISHOP) >= 2 ? "true" : "false");
    ss << "}";
}

void appendPieces(std::ostringstream& ss, const Position& pos, Color c) {
    int outposted = 0, rooksOpen = 0, rooksSeventh = 0;

    Bitboard allPawns = pos.pieces(PAWN);
    Bitboard enemyPawns = pos.pieces(~c, PAWN);

    for (Bitboard b = pos.pieces(c, KNIGHT); b;)
    {
        Square s = pop_lsb(b);
        int    rel = c == WHITE ? int(rank_of(s)) : 7 - int(rank_of(s));
        if (rel >= 3 && rel <= 5)
        {
            // an outpost is not coverable by an enemy pawn
            Bitboard cover = Attacks::attacks_bb<PAWN>(s, c);
            if (!(enemyPawns & cover))
                ++outposted;
        }
    }

    for (Bitboard b = pos.pieces(c, ROOK); b;)
    {
        Square s = pop_lsb(b);
        if (!(allPawns & file_bb(s)))
            ++rooksOpen;
        Rank seventh = c == WHITE ? RANK_7 : RANK_2;
        if (rank_of(s) == seventh)
            ++rooksSeventh;
    }

    ss << "\"" << colorName(c) << "\":{";
    ss << "\"mobility\":" << mobility(pos, c) << ",";
    ss << "\"knightsOutposted\":" << outposted << ",";
    ss << "\"rooksOnOpenFile\":" << rooksOpen << ",";
    ss << "\"rooksOnSeventh\":" << rooksSeventh;
    ss << "}";
}

void appendKing(std::ostringstream& ss, const Position& pos, Color c) {
    Square ksq = pos.square<KING>(c);
    Bitboard zone = Attacks::attacks_bb<KING>(ksq) | square_bb(ksq);
    Bitboard ownPawns = pos.pieces(c, PAWN);

    int attackers = 0, defenders = 0, shield = 0;

    for (Bitboard b = pos.pieces(~c); b;)
    {
        Square    s  = pop_lsb(b);
        Piece     pc = pos.piece_on(s);
        Bitboard  att = pieceAttacks(pos, s, type_of(pc), color_of(pc));
        if (att & zone)
            ++attackers;
    }
    for (Bitboard b = pos.pieces(c) & ~square_bb(ksq); b;)
    {
        Square    s  = pop_lsb(b);
        Piece     pc = pos.piece_on(s);
        Bitboard  att = pieceAttacks(pos, s, type_of(pc), color_of(pc));
        if (att & zone)
            ++defenders;
    }

    int kf = int(file_of(ksq));
    int kr = int(rank_of(ksq));
    for (int f = (kf > 0 ? kf - 1 : 0); f <= (kf < 7 ? kf + 1 : 7); ++f)
        for (int i = 1; i <= 2; ++i)
        {
            int rr = c == WHITE ? kr + i : kr - i;
            if (rr >= 0 && rr < 8 && (ownPawns & file_bb(File(f)) & rank_bb(Rank(rr))))
                ++shield;
        }

    bool castled = (c == WHITE && (ksq == SQ_G1 || ksq == SQ_C1))
                || (c == BLACK && (ksq == SQ_G8 || ksq == SQ_C8));

    ss << "\"" << colorName(c) << "\":{";
    ss << "\"shieldPawns\":" << shield << ",";
    ss << "\"attackers\":" << attackers << ",";
    ss << "\"defenders\":" << defenders << ",";
    ss << "\"castled\":" << (castled ? "true" : "false");
    ss << "}";
}

}  // namespace


std::string json(const Position& pos) {
    initMasks();

    std::ostringstream ss;
    Color              stm = pos.side_to_move();

    int materialWhite = countPieces(pos, WHITE, PAWN) * 100 + countPieces(pos, WHITE, KNIGHT) * 320
                      + countPieces(pos, WHITE, BISHOP) * 330 + countPieces(pos, WHITE, ROOK) * 500
                      + countPieces(pos, WHITE, QUEEN) * 900;
    int materialBlack = countPieces(pos, BLACK, PAWN) * 100 + countPieces(pos, BLACK, KNIGHT) * 320
                      + countPieces(pos, BLACK, BISHOP) * 330 + countPieces(pos, BLACK, ROOK) * 500
                      + countPieces(pos, BLACK, QUEEN) * 900;

    int nonPawnValue = (materialWhite + materialBlack)
                     - (countPieces(pos, WHITE, PAWN) + countPieces(pos, BLACK, PAWN)) * 100;
    int nonPawnCount = pos.count<KNIGHT>() + pos.count<BISHOP>() + pos.count<ROOK>() + pos.count<QUEEN>();

    const char* phase = (nonPawnValue <= 1300 || nonPawnCount <= 4)
                          ? "endgame"
                          : (pos.game_ply() <= 24 && nonPawnCount >= 10 ? "opening" : "middlegame");

    unsigned legal = MoveList<LEGAL>(pos).size();

    ss << "{";
    ss << "\"fen\":\"" << pos.fen() << "\",";
    ss << "\"sideToMove\":\"" << colorName(stm) << "\",";
    ss << "\"phase\":\"" << phase << "\",";
    ss << "\"ply\":" << pos.game_ply() << ",";
    ss << "\"inCheck\":" << (pos.checkers() ? "true" : "false") << ",";
    ss << "\"legalMoves\":" << legal << ",";
    ss << "\"gameOver\":" << (legal == 0 ? "true" : "false") << ",";

    ss << "\"material\":{";
    appendMaterial(ss, pos, WHITE);
    ss << ",";
    appendMaterial(ss, pos, BLACK);
    ss << ",\"balanceCp\":" << (materialWhite - materialBlack) << "},";

    ss << "\"pawns\":{";
    appendPawns(ss, pos, WHITE);
    ss << ",";
    appendPawns(ss, pos, BLACK);
    ss << "},";

    ss << "\"pieces\":{";
    appendPieces(ss, pos, WHITE);
    ss << ",";
    appendPieces(ss, pos, BLACK);
    ss << "},";

    ss << "\"kingSafety\":{";
    appendKing(ss, pos, WHITE);
    ss << ",";
    appendKing(ss, pos, BLACK);
    ss << "}";

    ss << "}";
    return ss.str();
}

}  // namespace Narration
}  // namespace Stockfish
