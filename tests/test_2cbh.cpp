// Synthetic format/engine regression tests; no ChessBase fixture data.
#include "2cbh/cb2_index.h"
#include "2cbh/cb2_codec.h"
#include "2cbh/2cbh_move16.h"
#include "db_board.h"
#include "db_tag_set.h"
#include "db_var_consumer.h"
#include <tcl.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }
static unsigned checks = 0;
static void check(bool ok, char const* what) {
    ++checks;
    if (!ok) { std::fprintf(stderr, "FAIL: %s\n", what); std::exit(1); }
}
static void le32(unsigned char* p, uint32_t n) {
    for (unsigned i=0;i<4;++i) p[i]=(n>>(8*i))&255;
}
static std::vector<unsigned char> bytes(std::vector<uint16_t> const& words) {
    std::vector<unsigned char> out;
    for (auto w:words) { out.push_back(w&255); out.push_back(w>>8); }
    return out;
}
static bool walk(db::Board const& board, std::vector<uint16_t> const& words,
                 char const* expected = nullptr) {
    auto raw=bytes(words); db::VarConsumer c(board); db::TagSet tags;
    mstl::vector<db::cb2::CbaItem> items; unsigned plies=0;
    if (!c.startGame(tags)) return false;
    bool ok=db::cb2::walkGameRaw(c,raw.data(),raw.size(),items,false,plies);
    if (ok && expected) check(c.getFinalBoard().toFen(db::variant::Normal,db::Board::Shredder)==expected,"final position");
    c.finalizeGame(); return ok;
}
static unsigned square(char const* s) { return (s[0]-'a')*8+s[1]-'1'; }
// Select a geometric descriptor from the existing table, independently of
// resolveMove16. These synthetic positions distinguish king moves/castling.
static uint16_t kingCode(char const* from,char const* to,char const* rook=nullptr) {
    for (unsigned code=1;code<0xfffb;++code) {
        db::cb2::Move16Descriptor d;
        if (!db::cb2::decodeMove16(code,d) || d.piece!=1 || d.captured!=0
            || d.from!=square(from) || d.to!=square(to)) continue;
        if ((!rook && !d.hasWord1) || (rook && d.hasWord1 && d.word1Piece==5 && d.word1From==square(rook))) return code;
    }
    check(false,"king descriptor exists"); return 0;
}
static uint16_t pawnCode(char const* from,char const* to,unsigned piece) {
    for (unsigned code=1;code<0xfffb;++code) {
        db::cb2::Move16Descriptor d;
        if (db::cb2::decodeMove16(code,d) && d.piece==piece && !d.captured
            && d.from==square(from) && d.to==square(to) && !d.hasWord1) return code;
    }
    check(false,"pawn descriptor exists");return 0;
}
int main(int argc,char** argv) {
    tcl::bits::interp=Tcl_CreateInterp(); db::Board::initialize();
    unsigned char header[192]={};header[10]=192;
    db::cb2::IndexLayout layout;
    for (unsigned count: {0u,1u,2u,10u,255u,256u,300u,863793u}) {
        le32(header+16,count+1);
        check(db::cb2::readIndexLayout(header,24,uint64_t(count+1)*192,layout) && layout.gameCount==count,"index count");
        check(!db::cb2::readIndexLayout(header,24,uint64_t(count+1)*192-1,layout),"truncated index");
        check(!db::cb2::readIndexLayout(header,24,uint64_t(count+1)*192+192,layout),"header/file disagreement");
    }
    check(!db::cb2::readIndexLayout(header,23,192,layout),"short header");
    le32(header+16,0);check(!db::cb2::readIndexLayout(header,24,0,layout),"zero count");
    header[20]=1;le32(header+16,2);
    check(!db::cb2::readIndexLayout(header,24,384,layout),"high count bytes are not ignored");
    check(!db::cb2::readIndexLayout(header,24,((uint64_t(1)<<32)+2)*192,layout),"count exceeds database API");
    header[20]=0;
    header[10]=191;check(!db::cb2::readIndexLayout(header,24,382,layout),"unknown stride");
    db::Board board;db::TagSet tags;
    auto raw=bytes({0xfffb,0,0xfffc,0xffff});
    unsigned char const* p=raw.data();uint32_t size=raw.size();
    check(db::cb2::prepareGame(2,p,size,board,tags),"position zero accepted");
    check(board.toFen(db::variant::Normal,db::Board::Shredder)=="bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w HFhf - 0 1","position zero FEN");
    check(size==4 && p==raw.data()+4,"position prefix consumed");
    for (unsigned bad: {960u,1000u,65535u}) {
        raw=bytes({0xfffb,uint16_t(bad),0xfffc,0xffff});p=raw.data();size=raw.size();
        check(!db::cb2::prepareGame(2,p,size,board,tags),"unsupported position refused");
    }
    raw=bytes({0xfffb,0,0xfffc,0xffff});
    for (unsigned n=0;n<raw.size();++n) { p=raw.data();size=n;check(!db::cb2::prepareGame(2,p,size,board,tags),"truncated setup refused"); }
    raw=bytes({0xfffc,0xffff});p=raw.data();size=raw.size();
    check(db::cb2::prepareGame(1,p,size,board,tags),"standard game");
    p=raw.data();size=raw.size();check(!db::cb2::prepareGame(3,p,size,board,tags),"unsupported type");
    board.setup("4k3/8/8/8/8/8/8/1R1K3R w HB - 0 1",db::variant::Normal);
    check(walk(board,{0xfffc,kingCode("d1","c1"),0xffff},"4k3/8/8/8/8/8/8/1RK4R b - - 1 1"),"ordinary king move");
    check(walk(board,{0xfffc,kingCode("d1","c1","b1"),0xffff},"4k3/8/8/8/8/8/8/2KR3R b - - 1 1"),"one-square castle");
    board.setup("4k3/8/8/8/8/8/8/R5KR w HA - 0 1",db::variant::Normal);
    check(walk(board,{0xfffc,kingCode("g1","g1","h1"),0xffff},"4k3/8/8/8/8/8/8/R4RK1 b - - 1 1"),"stationary king castle");
    board.setup("4k3/8/8/8/8/8/8/R4KR1 w GA - 0 1",db::variant::Normal);
    check(walk(board,{0xfffc,kingCode("f1","g1","g1"),0xffff},"4k3/8/8/8/8/8/8/R4RK1 b - - 1 1"),"king-rook swap castle");
    board.setup("4k3/8/8/8/8/8/8/RKR5 w CA - 0 1",db::variant::Normal);
    check(!walk(board,{0xfffc,kingCode("b1","c1","a1"),0xffff}),"blocked long castle must not become short castle");
    check(walk(board,{0xfffc,kingCode("b1","g1","c1"),0xffff},"4k3/8/8/8/8/8/8/R4RK1 b - - 1 1"),"short castle with rook on c-file");
    check(!walk(board,{0xfffc,kingCode("f1","g1","g1")}),"missing terminator refused");
    check(!walk(board,{0xfffc,0xffff,0xffff}),"trailing tokens refused");
    // Two root markers: black's alternative must replace the second ply,
    // even though a marker already occurred after White's first ply.
    board=db::Board::standardBoard(db::variant::Normal);
    check(walk(board,{0xfffc,pawnCode("e2","e4",6),0xfffd,
                      pawnCode("e7","e5",14),0xfffd,0xffff,
                      pawnCode("c7","c5",14),0xffff,
                      pawnCode("d2","d4",6),0xffff}),"two root variations");
    // Optional independent python-chess generated expectations, one FEN/id.
    if (argc>1) {
        FILE* f=std::fopen(argv[1],"r");check(f!=nullptr,"open independent FEN oracle");
        char fen[200];unsigned count=0;
        while (std::fgets(fen,sizeof(fen),f)) {
            fen[std::strcspn(fen,"\r\n")]=0;
            raw=bytes({0xfffb,uint16_t(count),0xfffc,0xffff});p=raw.data();size=raw.size();
            check(db::cb2::prepareGame(2,p,size,board,tags),"960 setup");
            check(board.toFen(db::variant::Normal,db::Board::Shredder)==fen,"independent 960 FEN");++count;
        }
        std::fclose(f);check(count==960,"all 960 positions");
    }
    std::printf("PASS: %u checks\n",checks);
}
