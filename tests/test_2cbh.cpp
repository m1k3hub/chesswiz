// Synthetic format/engine regression tests; no ChessBase fixture data.
//
// Covers the 2CBH index framing, the Move16 codec (decode + encode), the
// compact and arbitrary setup prefixes, and a complete writer -> reader round
// trip (index, namebase, game data and annotations) written into a temporary
// directory.
#include "2cbh/cb2_index.h"
#include "2cbh/cb2_codec.h"
#include "2cbh/cb2_writer.h"
#include "2cbh/2cbh_move16.h"
#include "2cbh/2cbh_annotations.h"
#include "2cbh/cb2_flags.h"
#include "2cbh/cb2_namebase.h"
#include "2cbh/cb2_setup.h"
#include "db_board.h"
#include "db_move_list.h"
#include "db_tag_set.h"
#include "db_var_consumer.h"
#include <tcl.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

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
    if (ok && expected) {
        std::string got=c.getFinalBoard().toFen(db::variant::Normal,db::Board::Shredder).c_str();
        if (got!=expected) std::fprintf(stderr,"final position: got '%s' expected '%s'\n",got.c_str(),expected);
        check(got==expected,"final position");
    }
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

// ----------------------------------------------------------------------
// helpers for the writer round trip
// ----------------------------------------------------------------------
static uint16_t u16at(unsigned char const* p) { return p[0] | (p[1]<<8); }
static uint32_t be32at(unsigned char const* p) {
    return (uint32_t(p[0])<<24) | (uint32_t(p[1])<<16) | (uint32_t(p[2])<<8) | uint32_t(p[3]);
}
static uint32_t u32at(unsigned char const* p) {
    return uint32_t(p[0]) | (uint32_t(p[1])<<8) | (uint32_t(p[2])<<16) | (uint32_t(p[3])<<24);
}
static uint64_t u64at(unsigned char const* p) {
    uint64_t v=0; for (int i=7;i>=0;--i) v=(v<<8)|p[i]; return v;
}
static std::vector<unsigned char> readFile(char const* path) {
    std::vector<unsigned char> out;
    FILE* f=std::fopen(path,"rb");
    check(f!=nullptr,"open written file");
    std::fseek(f,0,SEEK_END); long n=std::ftell(f); std::fseek(f,0,SEEK_SET);
    out.resize(size_t(n));
    check(std::fread(out.data(),1,size_t(n),f)==size_t(n),"read written file");
    std::fclose(f);
    return out;
}
static bool writeFile(char const* path, std::string const& text) {
    FILE* f=std::fopen(path,"wb"); if (!f) return false;
    bool ok=std::fwrite(text.data(),1,text.size(),f)==text.size();
    std::fclose(f); return ok;
}

// scidb squares are rank-major (a1 = 0, b1 = 1, ...).
static unsigned boardSquare(char const* s) { return (s[1]-'1')*8+(s[0]-'a'); }
// Find the legal move of `board` from -> to (promotion letter optional).
static db::Move findMove(db::Board const& board, char const* uci, bool castle=false) {
    unsigned from=boardSquare(uci);
    unsigned to=boardSquare(uci+2);
    db::MoveList moves;
    board.generateMoves(db::variant::Normal,moves);
    board.filterLegalMoves(moves,db::variant::Normal);
    for (unsigned i=0;i<moves.size();++i) {
        db::Move const& m=moves[i];
        if (m.from()!=from || m.isCastling()!=castle) continue;
        if (castle) { if (m.to()!=to) continue; }
        else if (m.to()!=to) continue;
        if (m.isPromotion()) {
            db::piece::Type want=db::piece::Queen;
            switch (uci[4]) {
                case 'r': want=db::piece::Rook; break;
                case 'b': want=db::piece::Bishop; break;
                case 'n': want=db::piece::Knight; break;
                default: want=db::piece::Queen; break;
            }
            if (m.promoted()!=want) continue;
        } else if (uci[4]) { continue; }
        return m;
    }
    std::fprintf(stderr,"no legal move %s in position\n",uci);
    std::fflush(stderr);
    check(false,"legal move exists"); return db::Move();
}
static db::Move play(db::Board& board, char const* uci, bool castle=false) {
    db::Move m=findMove(board,uci,castle);
    board.prepareForPrint(m,db::variant::Normal,db::Board::ExternalRepresentation);
    board.doMove(m,db::variant::Normal);
    return m;
}

// ----------------------------------------------------------------------
// Move16 encoder
// ----------------------------------------------------------------------
static void testMove16Encoding() {
    char const* positions[] =
    {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1",
        "r3k2r/8/8/8/8/8/8/4K3 b kq - 0 1",
        "4k3/P7/8/8/8/8/7p/4K3 w - - 0 1",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "4k3/8/8/8/8/8/8/1R2K2R w K - 0 1",
        "bqnnrkrb/pppppppp/8/8/8/8/PPPPPPPP/BQNNRKRB w KQkq - 0 1",
        "rkqrbbnn/pppppppp/8/8/8/8/PPPPPPPP/RKQRBBNN w DAda - 0 1",
    };

    unsigned encoded=0, castles=0, promotions=0, enPassants=0;

    for (unsigned p=0;p<sizeof(positions)/sizeof(positions[0]);++p) {
        db::Board board;
        check(board.setup(positions[p],db::variant::Normal)!=nullptr,"test position is valid");
        db::MoveList moves;
        board.generateMoves(db::variant::Normal,moves);
        board.filterLegalMoves(moves,db::variant::Normal);

        for (unsigned i=0;i<moves.size();++i) {
            db::Move const& m=moves[i];
            uint16_t code=0;
            check(db::cb2::encodeMove16(board,m,code),"every legal move encodes");

            db::cb2::Move16Descriptor d;
            check(db::cb2::decodeMove16(code,d),"encoded code decodes");

            db::Board const& constBoard=board;
            db::Move resolved;
            check(db::cb2::resolveMove16(constBoard,d,resolved),"encoded code resolves");

            check(resolved.from()==m.from() && resolved.to()==m.to(),"encoded move squares");
            check(resolved.isCastling()==m.isCastling(),"encoded castling flag");
            if (m.isCastling())
            {
                check(resolved.castlingKingTo()==m.castlingKingTo()
                      && resolved.castlingRookTo()==m.castlingRookTo(),"encoded castle targets");
                ++castles;
            }
            else
            {
                check(resolved.isPromotion()==m.isPromotion(),"encoded promotion flag");
                if (m.isPromotion())
                {
                    check(resolved.promoted()==m.promoted(),"encoded promotion piece");
                    ++promotions;
                }
            }
            if (m.isEnPassant()) ++enPassants;
            ++encoded;
        }
    }
    check(encoded>120,"enough moves encoded");
    check(castles>=4,"castling moves encoded");
    check(promotions>=4,"promotions encoded");
    check(enPassants>=1,"en passant move encoded");
}

static void testPlacementCodes() {
    unsigned found=0;
    unsigned const pieces[] = {1,2,3,4,5,6,9,10,11,12,13,14};
    for (unsigned i=0;i<12;++i) {
        unsigned const pce=pieces[i];
        bool const pawn = (pce==6 || pce==14);
        for (unsigned sq=0;sq<64;++sq) {
            unsigned const rank = sq & 7;      // Move16 square = file*8 + rank
            if (pawn && (rank==0 || rank==7)) continue;
            uint16_t code=0;
            check(db::cb2::findPlacementCode(pce,sq,code),"placement code exists");
            db::cb2::Move16Descriptor d;
            check(db::cb2::decodeMove16(code,d),"placement code decodes");
            check(d.from==sq && d.to==sq && d.piece==pce && d.captured==0 && !d.hasWord1,
                  "placement descriptor shape");
            ++found;
        }
    }
    check(found==10*64+2*48,"all placement codes found");
}

// ----------------------------------------------------------------------
// explicit setup blocks (type 2 position 1000 and type 1)
// ----------------------------------------------------------------------
static std::vector<uint16_t> placementWords(db::Board const& board) {
    std::vector<uint16_t> out;
    for (unsigned sq16=0;sq16<64;++sq16) {
        unsigned const sq=((sq16&7)<<3)|(sq16>>3);        // Move16 -> scidb square
        unsigned const pce=db::cb2::toMove16Piece(board.pieceAt(sq));
        if (!pce) continue;
        uint16_t code=0;
        check(db::cb2::findPlacementCode(pce,sq16,code),"setup placement code");
        out.push_back(code);
    }
    return out;
}

// type: 1 or 2; headerWords: 3 for the six-byte block CBase26 writes
// ([u16 1][u8 side][u8 castling][u16 0]), 2 for the four-byte form without the
// trailing zero word.  The layout is the one decoded in cb2_setup.h from
// databases ChessBase 26 wrote itself (run 9).
static std::vector<uint16_t> setupStream(uint16_t type, unsigned headerWords,
                                         bool blackToMove, db::Board const& board,
                                         std::vector<uint16_t> const& moves,
                                         unsigned castling=0) {
    std::vector<uint16_t> out;
    out.push_back(0xfffb);
    if (type==2) out.push_back(1000);
    out.push_back(1);                                     // leading word
    out.push_back(uint16_t((blackToMove ? 1 : 0) | (castling << 8)));
    if (headerWords>=3) out.push_back(0);                 // trailing word
    std::vector<uint16_t> placement=placementWords(board);
    out.insert(out.end(),placement.begin(),placement.end());
    out.push_back(0xfffc);
    out.insert(out.end(),moves.begin(),moves.end());
    out.push_back(0xffff);
    return out;
}

static void testExplicitSetup() {
    db::Board board;
    check(board.setup("8/8/8/4k3/8/8/4K3/8 w - - 0 1",db::variant::Normal)!=nullptr,"setup FEN accepted");

    db::Board game(board);
    db::Move m1=play(game,"e2e3"), m2=play(game,"e5d5"), m3=play(game,"e3d3");
    std::vector<uint16_t> moves;
    uint16_t code;
    for (db::Move const* m : {&m1,&m2,&m3}) {
        db::Board before;
        before.setup("8/8/8/4k3/8/8/4K3/8 w - - 0 1",db::variant::Normal);
        (void)m;
    }
    // Re-encode each move from its own position.
    {
        db::Board b(board);
        check(db::cb2::encodeMove16(b,m1,code),"encode setup move 1"); moves.push_back(code);
        b.prepareForPrint(m1,db::variant::Normal,db::Board::ExternalRepresentation); b.doMove(m1,db::variant::Normal);
        check(db::cb2::encodeMove16(b,m2,code),"encode setup move 2"); moves.push_back(code);
        b.prepareForPrint(m2,db::variant::Normal,db::Board::ExternalRepresentation); b.doMove(m2,db::variant::Normal);
        check(db::cb2::encodeMove16(b,m3,code),"encode setup move 3"); moves.push_back(code);
    }

    for (unsigned headerWords : {2u,3u}) {
        std::vector<uint16_t> stream=setupStream(2,headerWords,false,board,moves);
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(2,p,size,start,tags),"arbitrary setup prefix accepted");
        check(start.toFen(db::variant::Normal,db::Board::Shredder)
              =="8/8/8/4k3/8/8/4K3/8 w - - 0 1","arbitrary setup FEN");
        check(tags.contains(db::tag::Fen) && tags.value(db::tag::SetUp)=="1","setup tags");
        {
            std::vector<uint16_t> rest;
            for (uint32_t k=0;k<size/2;++k) rest.push_back(uint16_t(p[2*k]|(p[2*k+1]<<8)));
            check(rest[0]==0xfffc,"mainline starts at 0xfffc");
            check(walk(start,rest,"8/8/8/3k4/8/3K4/8/8 b - - 3 2"),"setup mainline replays");
        }
    }

    // Black to move: the position must be recognised, and a game starting
    // with a black move must replay.
    {
        db::Board b;
        check(b.setup("8/8/8/4k3/8/8/4K3/8 b - - 0 1",db::variant::Normal)!=nullptr,"black-to-move FEN");
        db::Move c1=play(b,"e5d5");
        uint16_t c;
        db::Board before;
        before.setup("8/8/8/4k3/8/8/4K3/8 b - - 0 1",db::variant::Normal);
        check(db::cb2::encodeMove16(before,c1,c),"encode black move");
        std::vector<uint16_t> stream=setupStream(2,3,true,before,{c});
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(2,p,size,start,tags),"black-to-move setup accepted");
        check(start.sideToMove()==db::color::Black,"black to move detected");
    }

    // Type 1 may carry the same explicit setup block.
    {
        std::vector<uint16_t> stream=setupStream(1,2,false,board,moves);
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(1,p,size,start,tags),"type 1 explicit setup accepted");
        check(start.toFen(db::variant::Normal,db::Board::Shredder)
              =="8/8/8/4k3/8/8/4K3/8 w - - 0 1","type 1 explicit setup FEN");
    }

    // A truncated or corrupted setup block must be refused, never guessed.
    {
        std::vector<uint16_t> stream=setupStream(2,3,false,board,moves);
        for (unsigned cut=0;cut<stream.size();++cut) {
            auto raw=bytes(stream); raw.resize(cut); unsigned char const* p=raw.data();
            uint32_t size=raw.size(); db::Board start; db::TagSet tags;
            check(!db::cb2::prepareGame(2,p,size,start,tags),"truncated setup refused");
        }
    }
}

// ----------------------------------------------------------------------
// writer -> reader round trip
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// setup block: side to move and the castling byte (run 9)
// ----------------------------------------------------------------------
static void testSetupCastling() {
    // A position whose king has a rook on both sides, so every one of the
    // sixteen castling words has a rook to attach to.
    char const* fen="1r2k1r1/8/8/8/8/8/8/1R2K1R1 w BGbg - 0 1";
    char const* const expect[16]={
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w - - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w B - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w G - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w GB - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w b - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Bb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Gb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w GBb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w g - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Bg - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Gg - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w GBg - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w gb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Bgb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w Ggb - 0 1",
        "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w GBgb - 0 1",
    };

    db::Board board;
    check(board.setup(fen,db::variant::Normal)!=nullptr,"castling probe FEN accepted");
    std::vector<uint16_t> moves={0xfffc,0xffff};
    (void)moves;

    for (unsigned castling=0;castling<16;++castling) {
        std::vector<uint16_t> stream=setupStream(2,3,false,board,{0xffff},castling);
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(2,p,size,start,tags),"castling setup accepted");
        std::string got=start.toFen(db::variant::Normal,db::Board::Shredder).c_str();
        if (got!=expect[castling])
            std::fprintf(stderr,"castling %02x: '%s' expected '%s'\n",castling,
                         got.c_str(),expect[castling]);
        check(got==expect[castling],"castling byte maps to rights");
        check(start.sideToMove()==db::color::White,"setup side to move");
    }

    // Black to move, and the four-byte block (no trailing zero word).
    for (unsigned words : {2u,3u}) {
        std::vector<uint16_t> stream=setupStream(2,words,true,board,{0xffff},
                                                 db::cb2::SetupCastleAll);
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(2,p,size,start,tags),"black-to-move castling setup accepted");
        check(start.sideToMove()==db::color::Black,"black to move from the block");
        check(start.toFen(db::variant::Normal,db::Board::Shredder)
              =="1r2k1r1/8/8/8/8/8/8/1R2K1R1 b GBgb - 0 1","all rights from the block");
    }

    // Chess960 castling out of a setup block.  CBase26 stores the ordinary
    // long/short castling codes for these, although the castling rooks stand
    // on the b- and g-files: the Move16 table's castling codes carry the
    // standard a/h rook, so the reader must identify the move by the king and
    // the rook's destination (2cbh_move16.cpp resolveMove16()).
    {
        std::vector<uint16_t> stream=setupStream(2,3,false,board,{0xb129},0x03);
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(2,p,size,start,tags),"960 castling setup accepted");
        check(start.toFen(db::variant::Normal,db::Board::Shredder)
              =="1r2k1r1/8/8/8/8/8/8/1R2K1R1 w GB - 0 1","960 castling FEN");
        std::vector<uint16_t> rest;
        for (uint32_t k=0;k<size/2;++k) rest.push_back(uint16_t(p[2*k]|(p[2*k+1]<<8)));
        check(walk(start,rest,"1r2k1r1/8/8/8/8/8/8/2KR2R1 b - - 1 1"),"960 long castle replays");
    }
    // A 960 short castle whose rook starts on the king's destination square
    // (king e1, rook g1) is not representable in Scidb's board (the castling
    // move sends the king to the rook square), so only the long-castle case
    // above is asserted here; the probe database's own games cover the
    // standard short castle (FEN "4k3/.../4K2R w H").

    // A block whose leading word is not 1, or whose castling byte has bits
    // outside the four defined ones, is refused rather than guessed.
    for (uint16_t lead : {0u,2u,0xffffu}) {
        std::vector<uint16_t> stream={0xfffb,1000,lead,0x0000,0x0000,0xfffc,0xffff};
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(!db::cb2::prepareGame(2,p,size,start,tags),"bad setup leading word refused");
    }
    for (unsigned bad : {0x10u,0x80u,0x20u}) {
        std::vector<uint16_t> stream={0xfffb,1000,1,uint16_t(bad<<8),0x0000,0xfffc,0xffff};
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(!db::cb2::prepareGame(2,p,size,start,tags),"bad castling byte refused");
    }
    for (unsigned side : {2u,3u,0xffu}) {
        std::vector<uint16_t> stream={0xfffb,1000,1,uint16_t(side),0x0000,0xfffc,0xffff};
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(!db::cb2::prepareGame(2,p,size,start,tags),"bad side byte refused");
    }

    // A position the block does not describe (the stored mainline does not
    // replay) is corruption, not an alternative reading.
    {
        db::Board b;
        b.setup("8/8/8/4k3/8/8/4K3/8 w - - 0 1",db::variant::Normal);
        db::Move m=play(b,"e2e3");
        uint16_t code;
        db::Board before;
        before.setup("8/8/8/4k3/8/8/4K3/8 w - - 0 1",db::variant::Normal);
        check(db::cb2::encodeMove16(before,m,code),"encode setup move");
        std::vector<uint16_t> stream=setupStream(2,3,true,before,{code});
        auto raw=bytes(stream); unsigned char const* p=raw.data(); uint32_t size=raw.size();
        db::Board start; db::TagSet tags;
        check(!db::cb2::prepareGame(2,p,size,start,tags),"mainline that does not replay is refused");
    }
}

// ----------------------------------------------------------------------
// team namebase (.2lid +0xd3c) and index +0x40/+0x48
// ----------------------------------------------------------------------
static void testTeamNamebase() {
    // A hand-built slot array with the record CBase26 wrote for "Team White A".
    {
        std::vector<unsigned char> lid(0xb8+2*0x108a,0);
        struct Rec { unsigned slot; unsigned char const* raw; unsigned len; };
        static unsigned char const r0[]={
            0x15,0,0,0, 0x0c,0,0,0, 'T','e','a','m',' ','W','h','i','t','e',' ','A',
            0x00,0x00, 0xea,0x07 };
        static unsigned char const r1[]={
            0x15,0,0,0, 0x0c,0,0,0, 'T','e','a','m',' ','B','l','a','c','k',' ','B',
            0x00,0x00, 0xea,0x07 };
        Rec recs[2]={{0,r0,sizeof(r0)},{1,r1,sizeof(r1)}};
        for (unsigned i=0;i<2;++i)
            std::memcpy(&lid[0xb8+recs[i].slot*0x108a+0xd3c],recs[i].raw,recs[i].len);

        db::cb2::TeamSlot team;
        check(db::cb2::readTeamSlot(lid.data(),lid.size(),0,team),"team slot 0 read");
        check(std::string(team.name,team.nameLength)=="Team White A","team 0 name");
        check(team.year==2026,"team 0 year");
        check(db::cb2::readTeamSlot(lid.data(),lid.size(),1,team),"team slot 1 read");
        check(std::string(team.name,team.nameLength)=="Team Black B","team 1 name");
        check(!db::cb2::readTeamSlot(lid.data(),lid.size(),2,team),"unallocated team slot refused");
    }

    // The writer stores teams, the codec exposes them as WhiteTeam/BlackTeam.
    char dir[256];
    std::snprintf(dir,sizeof(dir),"/tmp/cb2-teams-%ld",(long)::getpid());
    std::string mk("mkdir -p '"); mk += dir; mk += "'";
    check(std::system(mk.c_str())==0,"temporary directory");
    std::string root=std::string(dir)+"/db";

    mstl::vector<db::cb2::WriteGame> games;
    for (unsigned i=0;i<3;++i) {
        db::cb2::WriteGame g;
        g.white="Teamprobe, White"; g.black="Teamprobe, Black";
        g.event="Team Match"; g.site="Leipzig";
        g.round="1"; g.result="1-0";
        g.date=db::Date(2026,4,2);
        g.setup=-1;
        g.moves.push_back(0xfffc);
        g.moves.push_back(pawnCode("e2","e4",6));
        g.moves.push_back(0xffff);
        if (i==1) { g.whiteTeam="Team White A"; g.blackTeam="Team Black B"; }
        games.push_back(g);
    }

    mstl::string err, mroot(root.c_str());
    check(db::cb2::writeDatabase(mroot,games,&err),"writeDatabase with teams");

    std::vector<unsigned char> index=readFile((root+".2cbh").c_str());
    std::vector<unsigned char> namebase=readFile((root+".2lid").c_str());
    check(u64at(&index[192*1+0x40])==~0ull,"game 0 has no WhiteTeam");
    check(u64at(&index[192*1+0x48])==~0ull,"game 0 has no BlackTeam");
    check(u64at(&index[192*2+0x40])==0ull,"game 1 WhiteTeam id");
    check(u64at(&index[192*2+0x48])==1ull,"game 1 BlackTeam id");
    check(u64at(&index[192*3+0x40])==~0ull,"game 2 has no WhiteTeam");

    db::cb2::TeamSlot team;
    check(db::cb2::readTeamSlot(namebase.data(),namebase.size(),0,team),"written team 0");
    check(std::string(team.name,team.nameLength)=="Team White A","written team 0 name");
    check(team.year==2026,"written team 0 year");
    check(db::cb2::readTeamSlot(namebase.data(),namebase.size(),1,team),"written team 1");
    check(std::string(team.name,team.nameLength)=="Team Black B","written team 1 name");

    auto be32=[&](size_t off){ return (unsigned(namebase[off])<<24)|(unsigned(namebase[off+1])<<16)
                                     |(unsigned(namebase[off+2])<<8)|unsigned(namebase[off+3]); };
    check(be32(8+4*20+8)==2,"team section count is two");

    // Appending keeps the existing team ids and records.
    {
        db::cb2::WriteGame g;
        g.white="Later, Larry"; g.black="Later, Lisa";
        g.event="Team Match"; g.site="Leipzig"; g.round="2"; g.result="0-1";
        g.date=db::Date(2026,4,3); g.setup=-1;
        g.whiteTeam="Team White A";
        g.moves.push_back(0xfffc);
        g.moves.push_back(pawnCode("d2","d4",6));
        g.moves.push_back(0xffff);
        mstl::vector<db::cb2::WriteGame> more;
        more.push_back(g);
        check(db::cb2::appendToDatabase(mroot,more,&err),"append with a repeated team");
    }
    index=readFile((root+".2cbh").c_str());
    namebase=readFile((root+".2lid").c_str());
    check(u64at(&index[192*2+0x40])==0ull,"existing team id kept after append");
    check(u64at(&index[192*2+0x48])==1ull,"existing black team id kept after append");
    check(u64at(&index[192*4+0x40])==0ull,"new game reuses the team id");
    check(u64at(&index[192*4+0x48])==~0ull,"new game has no BlackTeam");
    check(db::cb2::readTeamSlot(namebase.data(),namebase.size(),0,team),"team 0 after append");
    check(std::string(team.name,team.nameLength)=="Team White A","team 0 name after append");

    std::string rm("rm -rf '"); rm += dir; rm += "'";
    check(std::system(rm.c_str())==0,"temporary directory removed");
}

static void testWriterRoundTrip() {
    char dir[256];
    std::snprintf(dir,sizeof(dir),"/tmp/cb2-writer-roundtrip-%ld",(long)::getpid());
    std::string mk("mkdir -p '"); mk += dir; mk += "'";
    check(std::system(mk.c_str())==0,"temporary directory");
    std::string root=std::string(dir)+"/db";

    // ---- games to write ------------------------------------------------
    mstl::vector<db::cb2::WriteGame> games;

    // game 0: standard start, full tag set, mainline + one variation
    {
        db::cb2::WriteGame g;
        g.white="Alpha, Ann"; g.black="Beta, Bob";
        g.event="Round Trip Open"; g.site="Testville";
        g.round="3"; g.result="1-0"; g.eco="B12a";
        g.whiteElo=2500; g.blackElo=2400;
        g.date=db::Date(2026,5,1);
        g.setup=-1;
        g.sourceTitle="playchess.com"; g.source="ChessBase";
        g.annotator="Annotator, Ann";
        g.medals=db::cb2::cb2Medals(db::GameInfo::Flag_Best_Game
                                   | db::GameInfo::Flag_Tactics
                                   | db::GameInfo::Flag_End_Game);

        std::vector<uint16_t> stream=
        {
            0xfffc,
            pawnCode("e2","e4",6), 0xfffd,                       // 1.e4 (alt: 1.c5)
            pawnCode("e7","e5",14),                               // 1...e5
            0xfffd,                                               // 2.Nf3 (alt: 2.d4)
            0xffff,
            pawnCode("c7","c5",14), 0xffff,                       // 1...c5
            pawnCode("d2","d4",6), 0xffff,                        // 2.d4
        };
        for (unsigned i=0;i<stream.size();++i) g.moves.push_back(stream[i]);
        games.push_back(g);
    }

    // game 1: compact Chess960 start position
    {
        db::cb2::WriteGame g;
        g.white="Gamma, Gina"; g.black="Delta, Dan";
        g.event="Chess960 Cup"; g.site="Berlin";
        g.round="1"; g.result="1/2-1/2";
        g.date=db::Date(2026,6,2);
        g.setup=906;
        g.source="Codekiddy";
        g.medals=db::cb2::cb2Medals(db::GameInfo::Flag_Sacrifice);

        db::Board board; board.setup(906,db::variant::Normal);
        db::Board const start(board);
        mstl::vector<db::Move> line;
        for (unsigned k=0;k<5;++k) {
            db::MoveList moves;
            board.generateMoves(db::variant::Normal,moves);
            board.filterLegalMoves(moves,db::variant::Normal);
            check(moves.size()>0,"chess960 move available");
            line.push_back(moves[0]);
            db::Move m(moves[0]);
            board.prepareForPrint(m,db::variant::Normal,db::Board::ExternalRepresentation);
            board.doMove(m,db::variant::Normal);
        }
        check(db::cb2::encodeMoveStream(start,line,g.moves),"encode chess960 line");
        games.push_back(g);
    }

    // game 2: arbitrary setup position
    {
        db::cb2::WriteGame g;
        g.white="Epsilon, Eve"; g.black="Zeta, Zoe";
        g.event="Setup Match"; g.site="Praha";
        g.round="4.2"; g.result="0-1";
        g.date=db::Date(2026,7,3);
        g.setup=1000;
        g.fen="8/8/8/4k3/8/8/4K3/8 w - - 0 1";

        db::Board board;
        check(board.setup(g.fen.c_str(),db::variant::Normal)!=nullptr,"writer setup FEN");
        db::Board const start(board);
        mstl::vector<db::Move> line;
        char const* ucis[] = { "e2e3", "e5d5", "e3d3" };
        for (char const* uci : ucis) {
            db::Move m=findMove(board,uci);
            line.push_back(m);
            board.prepareForPrint(m,db::variant::Normal,db::Board::ExternalRepresentation);
            board.doMove(m,db::variant::Normal);
        }
        check(db::cb2::encodeMoveStream(start,line,g.moves),"encode setup line");
        games.push_back(g);
    }

    mstl::string err;
    mstl::string mroot(root.c_str());
    check(db::cb2::writeDatabase(mroot, games, &err),"writeDatabase");

    // ---- read back -----------------------------------------------------
    std::vector<unsigned char> index=readFile((root+".2cbh").c_str());
    std::vector<unsigned char> namebase=readFile((root+".2lid").c_str());
    std::vector<unsigned char> gdata=readFile((root+".2cbg").c_str());
    std::vector<unsigned char> adata=readFile((root+".2cba").c_str());

    db::cb2::IndexLayout layout;
    check(db::cb2::readIndexLayout(index.data(),24,index.size(),layout),"written index framing");
    check(layout.gameCount==3 && layout.recordSize==192,"written game count");
    check(u64at(gdata.data())==gdata.size(),"game file length header");
    check(u16at(gdata.data()+8)==12,"game file first record offset");
    check(u64at(adata.data())==adata.size(),"annotation file length header");

    std::vector<std::string> players;
    {
        static unsigned char const sig[12]={0xff,0xff,0xff,0xff,0x08,0,0,0,0xff,0xff,0xff,0xff};
        size_t pos=0xb8;
        while (players.size()<64) {
            size_t i=pos;
            while (i+12<=namebase.size() && std::memcmp(&namebase[i],sig,12)!=0) ++i;
            if (i+12>namebase.size()) break;
            size_t start=0; bool found=false;
            for (size_t s=i+4; s-- > (i>320?i-312:0); ) {
                uint32_t total=u32at(&namebase[s]);
                if (s+total==i+12 && total>20 && total<320) { start=s; found=true; break; }
            }
            if (!found) { pos=i+12; continue; }
            uint32_t llen=u32at(&namebase[start+4]);
            size_t fo=start+8+llen;
            uint32_t flen=u32at(&namebase[fo]);
            std::string last((char const*)&namebase[start+8],llen);
            std::string first((char const*)&namebase[fo+4],flen);
            players.push_back(first.empty()?last:(last+", "+first));
            pos=i+12;
        }
    }
    // Six players plus the annotator, which is a player record: ChessBase
    // models the annotator as a person (see cb2::Codec::getAnnotator).
    check(players.size()==7,"six players and one annotator");
    check(players[0]=="Alpha, Ann" && players[1]=="Beta, Bob","written player names");
    check(players[6]=="Annotator, Ann","annotator stored as a player record");

    auto eventSlot=[&](unsigned slot, std::string& site, std::string& event, std::string& date) {
        size_t a=0xb8+size_t(slot)*0x108a+0x400;
        check(a+8<=namebase.size(),"event slot in range");
        unsigned siteLen=u16at(&namebase[a+4]);
        site.assign((char const*)&namebase[a+8],siteLen);
        size_t b=a+8+siteLen;
        unsigned evLen=u16at(&namebase[b]);
        event.assign((char const*)&namebase[b+4],evLen);
        uint32_t packed=u32at(&namebase[b+4+evLen]);
        char buf[32];
        std::snprintf(buf,sizeof(buf),"%04u.%02u.%02u",(packed>>9)&0xfff,(packed>>5)&0xf,packed&0x1f);
        date=buf;
    };

    struct Expect {
        char const* white; char const* black; char const* event; char const* site;
        char const* date; char const* round; char const* result; char const* eco;
        unsigned wElo, bElo; char const* fen; unsigned plies;
        char const* sourceTitle; char const* source; char const* annotator;
        unsigned medals;
    };
    Expect expect[3] = {
        { "Alpha, Ann","Beta, Bob","Round Trip Open","Testville","2026.05.01","3","1-0","B12",
          2500,2400,"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w HAha - 0 2", 2,
          "playchess.com","ChessBase","Annotator, Ann",
          db::cb2::cb2Medals(db::GameInfo::Flag_Best_Game | db::GameInfo::Flag_Tactics
                             | db::GameInfo::Flag_End_Game) },
        { "Gamma, Gina","Delta, Dan","Chess960 Cup","Berlin","2026.06.02","1","1/2-1/2","",
          0,0,"", 5,
          "","Codekiddy","",
          db::cb2::cb2Medals(db::GameInfo::Flag_Sacrifice) },
        { "Epsilon, Eve","Zeta, Zoe","Setup Match","Praha","2026.07.03","4.2","0-1","",
          0,0,"8/8/8/3k4/8/3K4/8/8 b - - 3 2", 3,
          "","","", 0 },
    };

    for (unsigned g=0;g<3;++g) {
        unsigned char const* rec=&index[192*(g+1)];
        check(u16at(rec+0)==1 && u16at(rec+2)==0x0101,"record version words");
        uint64_t goff=u64at(rec+0x08);
        check(goff<gdata.size(),"record offset in range");

        check(u64at(&gdata[goff])==0x1122334455667788ull,"game record magic");
        uint32_t dsz=u32at(&gdata[goff+8]), esz=u32at(&gdata[goff+0xc]);
        uint16_t type=u16at(&gdata[goff+0x18]);
        check(u64at(&gdata[goff+26+dsz+esz])==26u+dsz+esz+8,"game record trailer");
        unsigned char const* p=&gdata[goff+26];
        uint32_t size=dsz;
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(type,p,size,start,tags),"written game prefix decodes");
        if (g==0) check(type==1 && start.isStartPosition(),"standard game type");
        if (g==1) check(type==2 && start.computeIdn(db::variant::Normal)==906,"compact chess960 start");
        if (g==2) check(type==2 && start.toFen(db::variant::Normal,db::Board::Shredder)=="8/8/8/4k3/8/8/4K3/8 w - - 0 1","setup start FEN");

        mstl::vector<db::cb2::CbaItem> items;
        {
            uint32_t asz=u32at(&adata[u64at(rec+0x10)+8]);
            check(db::cb2::parseCbaItems(&adata[u64at(rec+0x10)+26],asz,items),"written annotation record parses");
        }

        db::VarConsumer consumer(start);
        db::TagSet outTags;
        check(consumer.startGame(outTags),"consumer startGame");
        consumer.startMoveSection();
        unsigned plies=0;
        check(db::cb2::walkGameRaw(consumer,p,size,items,true,plies),"written mainline replays");
        std::string finalFen=consumer.getFinalBoard().toFen(db::variant::Normal,db::Board::Shredder).c_str();
        consumer.finishMoveSection(db::result::fromString(expect[g].result));
        consumer.finishGame(outTags);
        consumer.finalizeGame();

        if (plies!=expect[g].plies) std::fprintf(stderr,"game %u plies %u expected %u\n",g,plies,expect[g].plies);
        check(plies==expect[g].plies,"replayed mainline length");
        if (expect[g].fen[0]) {
            std::string got=finalFen;
            if (got!=expect[g].fen)
                std::fprintf(stderr,"game %u final '%s' expected '%s'\n",g,got.c_str(),expect[g].fen);
            check(got==expect[g].fen,"replayed final position");
        }

        std::string site,event,eventDate;
        eventSlot(unsigned(u64at(rec+0x28)),site,event,eventDate);
        check(event==expect[g].event,"event name");
        check(site==expect[g].site,"site name");
        check(eventDate==expect[g].date,"event date");

        uint32_t white=uint32_t(u64at(rec+0x18));
        uint32_t black=uint32_t(u64at(rec+0x20));
        check(white<players.size() && black<players.size(),"player ids");
        check(players[white]==expect[g].white,"white player");
        check(players[black]==expect[g].black,"black player");

        uint16_t eco=u16at(rec+0x80);
        if (expect[g].eco[0]) {
            unsigned code=(eco>>7)-1u;
            char buf[8];
            std::snprintf(buf,sizeof(buf),"%c%02u",'A'+(code/100),code%100);
            check(std::string(buf)==expect[g].eco,"ECO base code");
        } else {
            check(eco==0,"no ECO stored");
        }

        check(u16at(rec+0x60)==expect[g].wElo && u16at(rec+0x70)==expect[g].bElo,"Elo values");

        unsigned packed=uint32_t(rec[0xbc])|(uint32_t(rec[0xbd])<<8)|(uint32_t(rec[0xbe])<<16);
        char dateBuf[32];
        std::snprintf(dateBuf,sizeof(dateBuf),"%04u.%02u.%02u",(packed>>9)&0xfff,(packed>>5)&0xf,packed&0x1f);
        check(std::string(dateBuf)==expect[g].date,"game date");

        unsigned round=u16at(rec+0x5a), sub=u16at(rec+0x5c);
        char roundBuf[32];
        if (sub) std::snprintf(roundBuf,sizeof(roundBuf),"%u.%u",round,sub);
        else std::snprintf(roundBuf,sizeof(roundBuf),"%u",round);
        check(std::string(roundBuf)==expect[g].round,"round field");

        unsigned result=rec[0x58]&3;
        char const* resultTag = result==0?"0-1":result==1?"1/2-1/2":result==2?"1-0":"*";
        check(std::string(resultTag)==expect[g].result,"result field");

        check(items.empty(),"no annotation items written");

        // ---- annotator (index @0x30 -> .2lid +0x93c) and source
        //      (index @0x38 -> .2lid +0x860) ----------------------------
        auto slotName=[&](unsigned long id, size_t section,
                          std::string& title, std::string& name) -> bool {
            db::cb2::SlotName rec;
            if (!db::cb2::readSlotName(namebase.data(), namebase.size(),
                                       section, unsigned(id), rec))
                return false;
            title.assign(rec.title, rec.titleLength);
            name.assign(rec.name, rec.nameLength);
            return true;
        };

        std::string title, name;
        uint64_t const annotatorId=u64at(rec+0x30);
        if (expect[g].annotator[0]) {
            check(annotatorId<players.size(),"annotator id is a player id");
            check(players[unsigned(annotatorId)]==expect[g].annotator,"annotator name");
        } else {
            check(annotatorId==~uint64_t(0),"no annotator reference");
        }

        uint64_t const sourceId=u64at(rec+0x38);
        if (expect[g].source[0]) {
            check(sourceId<namebase.size(),"source id in range");
            check(slotName(sourceId,db::cb2::namebaseSourceOffset,title,name),
                  "source slot record decodes");
            check(name==expect[g].source,"source name");
            check(title==expect[g].sourceTitle,"source title");
            // the record's total covers both strings plus eight bytes
            size_t const a=db::cb2::namebaseFirstSlot
                          +size_t(sourceId)*db::cb2::namebaseStride
                          +db::cb2::namebaseSourceOffset;
            check(u32at(&namebase[a])==20+title.size()+name.size(),"source record length");
        }

        check(u16at(rec+0x82)==expect[g].medals,"medal word");
        check(db::cb2::cb2GameFlags(u16at(rec+0x82))
              ==db::cb2::cb2GameFlags(expect[g].medals),"medals decode to game flags");
    }

    // ---- append to the written database --------------------------------
    {
        mstl::vector<db::cb2::WriteGame> more;
        db::cb2::WriteGame g;
        g.white="Alpha, Ann"; g.black="Eta, Hank";
        g.event="Round Trip Open"; g.site="Testville";
        g.round="4"; g.result="1-0";
        g.date=db::Date(2026,5,2);
        g.setup=-1;
        db::Board board=db::Board::standardBoard(db::variant::Normal);
        mstl::vector<db::Move> line;
        line.push_back(findMove(board,"d2d4"));
        check(db::cb2::encodeMoveStream(board,line,g.moves),"encode appended line");
        more.push_back(g);
        check(db::cb2::appendToDatabase(mroot, more, &err),"appendToDatabase");

        index=readFile((root+".2cbh").c_str());
        check(db::cb2::readIndexLayout(index.data(),24,index.size(),layout),"appended index framing");
        check(layout.gameCount==4,"appended game count");

        std::vector<unsigned char> data=readFile((root+".2cbg").c_str());
        for (unsigned g2=0;g2<4;++g2) {
            uint64_t off=u64at(&index[192*(g2+1)+0x08]);
            check(u64at(&data[off])==0x1122334455667788ull,"appended record magic");
        }
        uint64_t off=u64at(&index[192*4+0x08]);
        uint32_t dsz=u32at(&data[off+8]);
        unsigned char const* q=&data[off+26];
        uint32_t sz=dsz;
        db::Board start; db::TagSet tags;
        check(db::cb2::prepareGame(u16at(&data[off+0x18]),q,sz,start,tags),"appended game prefix");
        db::VarConsumer consumer(start);
        check(consumer.startGame(tags),"appended game consumer");
        consumer.startMoveSection();
        unsigned plies=0;
        mstl::vector<db::cb2::CbaItem> items;
        check(db::cb2::walkGameRaw(consumer,q,sz,items,true,plies),"appended game replays");
        check(plies==1,"appended game length");

        // Appending rewrites the namebase: the existing games must keep their
        // source, annotator and medals.
        std::vector<unsigned char> lid2=readFile((root+".2lid").c_str());
        unsigned char const* r0=&index[192*1];
        db::cb2::SlotName rec0;

        check(db::cb2::readSlotName(lid2.data(),lid2.size(),
                                    db::cb2::namebaseSourceOffset,
                                    unsigned(u64at(r0+0x38)),rec0),
              "appended database keeps the source record");
        check(std::string(rec0.name,rec0.nameLength)=="ChessBase","appended source name");
        check(std::string(rec0.title,rec0.titleLength)=="playchess.com","appended source title");

        {
            // The annotator is a player record: [total][lastLen][last]...
            unsigned long const annId=unsigned(u64at(r0+0x30));
            check(annId<db::cb2::namebaseSlotCount(lid2.size()),
                  "appended annotator reference is a player slot");
            size_t const slotAt=db::cb2::namebaseFirstSlot
                               +size_t(annId)*db::cb2::namebaseStride;
            std::string last((char const*)&lid2[slotAt+8],u32at(&lid2[slotAt+4]));
            check(last=="Annotator","appended annotator name");
        }
        check(u16at(&index[192*1+0x82])
              ==db::cb2::cb2Medals(db::GameInfo::Flag_Best_Game
                                   | db::GameInfo::Flag_Tactics
                                   | db::GameInfo::Flag_End_Game),
              "appended medal word");
    }

    if (!std::getenv("CB2_WRITER_KEEP")) {
        std::string cleanup("rm -rf '"); cleanup += dir; cleanup += "'";
        (void)std::system(cleanup.c_str());
    } else {
        std::printf("# kept %s\n",root.c_str());
    }
}

// ----------------------------------------------------------------------
// every header field of a written database, recomputed from its content
// ----------------------------------------------------------------------
// The four files plus the <name>.ini description are re-read here with plain
// little-endian accessors and checked field by field: nothing is compared
// against what the writer remembers, only against what the bytes hold and
// against the games that were handed to it.  CBase26's own databases have the
// same shape (0/1/2-game databases were used to fix the layout), so a field
// that this test accepts is one CBase26 accepts too.
static void testWriterHeaders() {
    char dir[256];    std::snprintf(dir,sizeof(dir),"/tmp/cb2-writer-headers-%ld",(long)::getpid());
    std::string mk("mkdir -p '"); mk += dir; mk += "'";
    check(std::system(mk.c_str())==0,"temporary directory");
    std::string root=std::string(dir)+"/hd";

    struct Spec { char const* white; char const* black; char const* event;
                  char const* site; char const* round; char const* result;
                  char const* eco; unsigned whiteElo; unsigned blackElo;
                  unsigned year, month, day; char const* sourceTitle;
                  char const* source; char const* annotator; int setup; };
    Spec const specs[2] = {
        { "Header, Hanna", "Probe, Paul", "Header Event", "Headerville",
          "3", "1-0", "C65", 2410, 2305, 2026, 7, 4,
          "Source Title", "Source Name", "Writer, Wanda", -1 },
        { "Second, Sam", "Third, Tina", "Second Event", "Elsewhere",
          "4.2", "0-1", "B12", 2200, 2650, 2025, 12, 31,
          "Other Title", "Other Name", "", 906 },
    };
    unsigned const gameCount=2;

    mstl::vector<db::cb2::WriteGame> games;
    unsigned plies[gameCount];
    unsigned medals[gameCount];

    for (unsigned i=0;i<gameCount;++i) {
        Spec const& s=specs[i];
        db::cb2::WriteGame g;
        g.white=s.white; g.black=s.black; g.event=s.event; g.site=s.site;
        g.round=s.round; g.result=s.result; g.eco=s.eco;
        g.whiteElo=s.whiteElo; g.blackElo=s.blackElo;
        g.date=db::Date(s.year,s.month,s.day);
        g.sourceTitle=s.sourceTitle; g.source=s.source;
        g.annotator=s.annotator; g.setup=s.setup;
        g.medals=db::cb2::cb2Medals(i==0
                    ? db::GameInfo::Flag_Tactics|db::GameInfo::Flag_End_Game
                    : db::GameInfo::Flag_Sacrifice);
        db::Board board=db::Board::standardBoard(db::variant::Normal);
        mstl::vector<db::Move> line; db::MoveList ml;
        board.generateMoves(db::variant::Normal,ml);
        board.filterLegalMoves(ml,db::variant::Normal);
        line.push_back(ml[0]);
        check(db::cb2::encodeMoveStream(board,line,g.moves),"encode header game");
        plies[i]=0;
        for (unsigned k=0;k<g.moves.size();++k)
            if (g.moves[k]!=db::cb2::Move16_GameStart
                &&g.moves[k]!=db::cb2::Move16_Marker
                &&g.moves[k]!=db::cb2::Move16_None
                &&g.moves[k]!=db::cb2::Move16_Terminator) ++plies[i];
        medals[i]=g.medals;
        games.push_back(g);
    }

    mstl::string err;
    check(db::cb2::writeDatabase(root.c_str(),games,&err),"writeDatabase headers");

    std::vector<unsigned char> index=readFile((root+".2cbh").c_str());
    std::vector<unsigned char> gdata=readFile((root+".2cbg").c_str());
    std::vector<unsigned char> adata=readFile((root+".2cba").c_str());
    std::vector<unsigned char> namebase=readFile((root+".2lid").c_str());
    std::vector<unsigned char> ini=readFile((root+".ini").c_str());

    // ---- .2cbh: framing ----------------------------------------------
    check(index.size()==192*(gameCount+1),"index holds header plus one record per game");
    check(u16at(&index[0x08])==0x26,"index header record size");
    check(u16at(&index[0x0a])==192,"index header stride");
    check(u32at(&index[0x0c])==0x500,"index header page size");
    check(u64at(&index[0x10])==gameCount+1,"index header record count");
    for (unsigned i=0;i<0x08;++i) check(index[i]==0,"index header +0 is zero");
    for (unsigned i=0x12;i<192;++i) check(index[i]==0,"index header tail is zero");

    // ---- .2lid: structural header ------------------------------------
    unsigned const be32=be32at(&namebase[0]);
    check(be32==0xb8,"namebase header length");    check(be32at(&namebase[4])==6,"namebase section count");
    unsigned const capacity[6]={1024,1120,220,1024,314,532};
    unsigned count[6]={0,0,0,0,0,0};
    unsigned capacitySum=0;
    for (unsigned s=0;s<6;++s) {
        unsigned char const* p=&namebase[8+20*s];
        unsigned const cap=be32at(p);
        unsigned const n=be32at(p+8);
        check(cap==capacity[s],"namebase section capacity");
        check(p[4]==0&&p[5]==0&&p[6]==0&&p[7]==0,"namebase section spare word");
        check(p[12]==0xff&&p[13]==0xff&&p[14]==0xff&&p[15]==0xff,"namebase section end marker");
        check(p[16]==0xff&&p[17]==0xff&&p[18]==0xff&&p[19]==0xff,"namebase section end marker 2");
        count[s]=n;
        capacitySum+=cap;
    }
    check(capacitySum==0x108a,"namebase capacities fill one slot");
    check(namebase[0x80]==0xff&&namebase[0x81]==0xff&&namebase[0x82]==0xff&&namebase[0x83]==0xff,
          "namebase free-list root");
    for (unsigned s=0;s<6;++s) {
        unsigned char const* p=&namebase[0x84+8*s];
        check(be32at(p)==1,"namebase free chunk count");
        check(be32at(p+4)==s,"namebase free chunk section");
    }
    check(be32at(&namebase[0xb4])==1,"namebase free chunk terminator");

    unsigned const slotCount=db::cb2::namebaseSlotCount(namebase.size());
    check(namebase.size()==0xb8+size_t(slotCount)*0x108a,"namebase holds whole slots");

    // ---- .2lid: section counts recomputed from the slot array --------
    unsigned seen[6]={0,0,0,0,0,0};
    for (unsigned s=0;s<slotCount;++s) {
        unsigned char const* slot=&namebase[0xb8+size_t(s)*0x108a];
        if (u32at(slot)!=0) ++seen[0];
        if (u32at(slot+db::cb2::namebaseEventOffset)!=0) ++seen[1];
        if (u32at(slot+db::cb2::namebaseSourceOffset)!=0) ++seen[2];
        if (u32at(slot+db::cb2::namebaseAnnotatorOffset)!=0) ++seen[3];
        if (slot[0xe76]==4) ++seen[5];
    }
    for (unsigned s=0;s<6;++s) {
        if (count[s]!=seen[s]) std::fprintf(stderr,"section %u count %u, slots hold %u\n",s,count[s],seen[s]);
        check(count[s]==seen[s],"namebase section count matches its slots");
    }
    check(count[0]>=gameCount*2,"one player record per named player");
    check(slotCount>=count[0]&&slotCount>=count[1]&&slotCount>=count[2],"slot array covers every count");

    // ---- .2cbg / .2cba: file headers ---------------------------------
    check(u64at(&gdata[0])==gdata.size(),"game file length header");
    check(u16at(&gdata[8])==12,"game file header length");
    check(u16at(&gdata[10])<=0x500,"game file header word within range");
    check(u64at(&adata[0])==adata.size(),"annotation file length header");
    check(u32at(&adata[8])==12,"annotation file header length");

    // ---- per game: index record against the payload it points at -----
    size_t gpos=u16at(&gdata[8]);
    size_t apos=u32at(&adata[8]);

    for (unsigned i=0;i<gameCount;++i) {
        unsigned char const* rec=&index[192+192*size_t(i)];

        check(u16at(rec+0x00)==1,"record present flag");
        check(u16at(rec+0x02)==0x0101,"record version word");

        // .2cbg record the index points at
        size_t const goff=size_t(u64at(rec+0x08));
        check(goff==gpos,"index game offset is the next record");
        check(goff+34<=gdata.size(),"game record inside the file");
        check(u64at(&gdata[goff])==0x1122334455667788ull,"game record magic");
        unsigned const dsz=u32at(&gdata[goff+8]);
        unsigned const esz=u32at(&gdata[goff+0xc]);
        check(goff+26+dsz+esz+8<=gdata.size(),"game record inside the file");
        check(u64at(&gdata[goff+26+dsz+esz])==26+dsz+esz+8,"game record length trailer");
        gpos=goff+26+dsz+esz+8;
        unsigned const type=u16at(&gdata[goff+0x18]);
        check(type==(specs[i].setup>=0&&specs[i].setup!=1000?2u:1u),"game record type follows the setup");

        // .2cba record the index points at
        size_t const aoff=size_t(u64at(rec+0x10));
        check(aoff==apos,"index annotation offset is the next record");
        check(aoff+34<=adata.size(),"annotation record inside the file");
        check(u64at(&adata[aoff])==0x1122334455667788ull,"annotation record magic");
        check(u32at(&adata[aoff+8])==4,"annotation record payload size");
        check(u16at(&adata[aoff+0x18])==0x2000,"annotation record type");
        check(adata[aoff+26]==0xff&&adata[aoff+27]==0xff
              &&adata[aoff+28]==0xff&&adata[aoff+29]==0x7f,"no-annotation marker");
        unsigned const aesz=u32at(&adata[aoff+0xc]);
        check(aoff+26+4+aesz+8<=adata.size(),"annotation record inside the file");
        check(u64at(&adata[aoff+26+4+aesz])==26+4+aesz+8,"annotation record length trailer");
        check(aesz>=196,"no-annotation record carries its trailing block");
        apos=aoff+26+4+aesz+8;

        // namebase references are ids, so they must be inside their section
        // A namebase reference is an id inside its section, or ~0 for "none".
        auto refOk=[](uint64_t id,unsigned n){ return id< n || id==~uint64_t(0); };
        check(refOk(u64at(rec+0x18),count[0]),"white player id in range");
        check(refOk(u64at(rec+0x20),count[0]),"black player id in range");
        check(refOk(u64at(rec+0x28),count[1]),"event id in range");
        check(refOk(u64at(rec+0x30),count[0]),"annotator id is a player id in range");
        check(refOk(u64at(rec+0x38),count[2]),"source id in range");
        check(u64at(rec+0x40)==~uint64_t(0),"white team unset");
        check(u64at(rec+0x48)==~uint64_t(0),"black team unset");
        check(u64at(rec+0x50)==~uint64_t(0),"no game title");

        // scalar fields
        unsigned const result=(specs[i].result[0]=='1')?2u
                              :(specs[i].result[0]=='0')?0u:1u;
        check((rec[0x58]&3)==result,"result code");
        check(u16at(rec+0x5a)==unsigned(specs[i].round[0]-'0'),"round level");
        check(u16at(rec+0x5c)==(specs[i].round[1]=='.'?unsigned(specs[i].round[2]-'0'):0u),
              "sub-round level");
        check(u16at(rec+0x60)==specs[i].whiteElo,"white Elo");
        check(u16at(rec+0x70)==specs[i].blackElo,"black Elo");
        unsigned const ecoCode=unsigned(specs[i].eco[0]-'A')*100
                                +10*unsigned(specs[i].eco[1]-'0')
                                +unsigned(specs[i].eco[2]-'0');
        check(u16at(rec+0x80)==128*(ecoCode+1),"ECO key");
        check(u16at(rec+0x82)==medals[i],"medal word");

        // move count and date recomputed from the game that was written
        unsigned const packed=unsigned(specs[i].day)
                              |(unsigned(specs[i].month)<<5)
                              |(unsigned(specs[i].year)<<9);
        unsigned const dateField=unsigned(rec[0xbc])|(unsigned(rec[0xbd])<<8)
                                 |(unsigned(rec[0xbe])<<16);
        check(dateField==packed,"packed date");
        check(rec[0xbf]==0,"date padding");
    }

    check(gpos==gdata.size(),"game file ends after the last record");
    check(apos==adata.size(),"annotation file ends after the last record");

    // The written move count field is halves of the mainline: recount the
    // Move16 codes of the stored payload for every game.
    for (unsigned i=0;i<gameCount;++i) {
        unsigned char const* rec=&index[192+192*size_t(i)];
        size_t const goff=size_t(u64at(rec+0x08));
        unsigned const dsz=u32at(&gdata[goff+8]);
        unsigned codes=0;
        for (unsigned k=0;k<dsz/2;++k) {
            uint16_t const w=u16at(&gdata[goff+26+2*k]);
            if (w==db::cb2::Move16_Terminator) break;
            if (w==db::cb2::Move16_GameStart||w==db::cb2::Move16_Marker
                ||w==db::cb2::Move16_None) continue;
            ++codes;
        }
        check(codes>=plies[i],"the stored mainline holds the moves that were written");
        check(u16at(rec+0x8a)==plies[i]/2,"move count field is half the mainline length");
    }

    // ---- .ini: the description CBase26 needs to see a database --------
    std::string text(ini.begin(),ini.end());
    std::string const iniHead("[Descr2CBG]\r\nType=1\r\n");
    check(text.compare(0,iniHead.size(),iniHead)==0,"description starts with the section and type");
    check(text.find("\r\nTitle=hd\r\n")!=std::string::npos,"description carries the database name");
    check(text.find("[Environ]\r\n")!=std::string::npos,"description carries the environment section");
    check(text.size()>400&&text[text.size()-1]=='\n'&&text[text.size()-2]=='\r',
          "description ends with a CRLF line");

    std::string cleanup; if (!std::getenv("CB2_WRITER_KEEP")) {
        cleanup="rm -rf '"; cleanup+=dir; cleanup+="'";
        (void)std::system(cleanup.c_str());
    } else {
        std::printf("# kept %s\n",root.c_str());
    }
}

// Every medal bit of the index word maps to exactly one codebase flag and
// maps back unchanged, so a database written by cb2::writeDatabase reads back
// with the flags it was given.
static void testMedalBits() {
    struct Bit { unsigned bit; unsigned flag; };
    Bit const bits[] = {
        {  0, db::GameInfo::Flag_Best_Game },
        {  1, db::GameInfo::Flag_Decided_Tournament },
        {  2, db::GameInfo::Flag_Model_Game },
        {  3, db::GameInfo::Flag_Novelty },
        {  4, db::GameInfo::Flag_Pawn_Structure },
        {  5, db::GameInfo::Flag_Strategy },
        {  6, db::GameInfo::Flag_Tactics },
        {  7, db::GameInfo::Flag_With_Attack },
        {  8, db::GameInfo::Flag_Sacrifice },
        {  9, db::GameInfo::Flag_Defense },
        { 10, db::GameInfo::Flag_Material },
        { 11, db::GameInfo::Flag_Piece_Play },
        { 12, db::GameInfo::Flag_End_Game },
        { 13, db::GameInfo::Flag_Blunder },          // tactical blunder
        { 14, db::GameInfo::Flag_Blunder },          // strategical blunder
        { 15, db::GameInfo::Flag_User },
    };
    check(sizeof(bits)/sizeof(bits[0])==16,"all sixteen medal bits mapped");

    for (unsigned i=0;i<16;++i) {
        uint16_t const word=uint16_t(1u<<bits[i].bit);
        unsigned const flags=db::cb2::cb2GameFlags(word);
        if (flags!=bits[i].flag)
            std::fprintf(stderr,"medal bit %u -> %#x expected %#x\n",
                         bits[i].bit,flags,bits[i].flag);
        check(flags==bits[i].flag,"medal bit maps to its game flag");
        // The 13th/14th bit are the two blunder flavours and share one Scidb
        // flag, so writing that flag sets both; every other bit is exclusive.
        uint16_t const expected = bits[i].flag==db::GameInfo::Flag_Blunder
                                  ? uint16_t((1u<<13)|(1u<<14)) : word;
        check(db::cb2::cb2Medals(bits[i].flag)==expected,"game flag writes its medal bit");
    }

    // The two blunder bits share one codebase flag, so the written word keeps
    // both bits and the readback is that one flag.
    check(db::cb2::cb2Medals(db::GameInfo::Flag_Blunder)==((1u<<13)|(1u<<14)),
          "blunder flag writes both blunder bits");
    check(db::cb2::cb2GameFlags(0)==0,"empty medal word");
    check(db::cb2::cb2Medals(0)==0,"no flags, no medals");
    // Every one of the 65,536 words decodes to flags and re-encodes to a
    // canonical word (the two blunder bits fold into one flag, so a word with
    // only one of them re-encodes with both; the flags are unchanged).
    bool roundTrip=true, idempotent=true;
    for (unsigned word=0;word<0x10000;++word) {
        unsigned const flags=db::cb2::cb2GameFlags(uint16_t(word));
        uint16_t const back=db::cb2::cb2Medals(flags);
        if (db::cb2::cb2GameFlags(back)!=flags) {
            std::fprintf(stderr,"medal word %#x loses flags\n",word);
            idempotent=false;
            break;
        }
        if (db::cb2::cb2Medals(db::cb2::cb2GameFlags(back))!=back) roundTrip=false;
    }
    check(idempotent,"medal word keeps its flags");
    check(roundTrip,"canonical medal word round trip");
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

    testMove16Encoding();
    testPlacementCodes();
    testExplicitSetup();
    testSetupCastling();
    testTeamNamebase();
    testMedalBits();
    testWriterRoundTrip();
    testWriterHeaders();

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
