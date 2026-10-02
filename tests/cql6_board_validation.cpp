// Compare the optimized normal-chess validator with its original implementation.
// checkMove retains its original terminal-state check and provides the baseline.
#include "db_board.h"
#include "db_board_base.h"
#include "db_move.h"
#include <cstdio>
#include <initializer_list>
using namespace db;
static bool baseline(Board const& board, Move const& move, move::Constraint constraint) {
    if (!board.checkMove(move,variant::Normal,constraint)) return false;
    if (move.isNull()) return !(board.checkState(variant::Normal) &
                               (Board::Checkmate|Board::ThreeChecks|Board::Stalemate|Board::Losing));
    return constraint==move::AllowIllegalMove || !board.isIntoCheck(move,variant::Normal);
}
int main() {
    castling::initialize();board::base::initialize();Board::initialize();
    unsigned tested=0;
    for (const char* fen : {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1",
        "6k1/8/8/8/8/8/4r3/4K3 w - - 0 1",
        "7k/6Q1/5K2/8/8/8/8/8 b - - 0 1",
        "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1",
        "4k3/P7/8/8/8/8/7p/4K3 w - - 0 1",
        "4k3/8/8/8/8/8/4r3/4K3 b - - 0 1"}) {
        Board board;
        if (!board.setup(fen,variant::Normal)) {fprintf(stderr,"invalid fixture %s\n",fen);return 2;}
        auto check=[&](Move move) {
            move.setColor(board.sideToMove());
            for(auto constraint : {move::AllowIllegalMove,move::DontAllowIllegalMove}) {
                bool expected=baseline(board,move,constraint);
                bool actual=board.isValidMove(move,variant::Normal,constraint);
                ++tested;
                if(actual!=expected) {
                    fprintf(stderr,"validation mismatch: %s move=%s constraint=%d\n",fen,
                            move.asString().c_str(),int(constraint));return false;
                }
            }
            return true;
        };
        if(!check(Move::null()) || !check(Move::empty())) return 3;
        for(unsigned from=0;from<64;++from) for(unsigned to=0;to<64;++to) {
            if(!check(board.prepareMove(from,to,variant::Normal,move::AllowIllegalMove))) return 3;
            if(board.piece(from)!=piece::None && from!=to && board.piece(to)!=piece::King) {
                if(!check(Move::genMove(from,to,board.piece(from),board.piece(to)))) return 3;
            }
        }
    }
    printf("PASS: %u validator/baseline comparisons including terminal, illegal, null, castle, en-passant and promotion positions\n",tested);
}
