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

// type: 1 or 2; headerWords: number of words after the [0xfffb] (type 2 also
// has the 1000 marker) before the placement codes.
static std::vector<uint16_t> setupStream(uint16_t type, unsigned headerWords,
                                         bool blackToMove, db::Board const& board,
                                         std::vector<uint16_t> const& moves) {
    std::vector<uint16_t> out;
    out.push_back(0xfffb);
    if (type==2) out.push_back(1000);
    // The side-to-move flag lives in the first header word, which is at
    // stream index 3 for type 2 and index 2 for type 1: exactly where the
    // reader's heuristic looks for it.
    for (unsigned i=0;i<headerWords;++i) out.push_back(i==0 ? (blackToMove ? 1 : 0) : 0);
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

    for (unsigned headerWords : {2u,3u,4u}) {
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
    check(players.size()==6,"three games: six distinct players");
    check(players[0]=="Alpha, Ann" && players[1]=="Beta, Bob","written player names");

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
    };
    Expect expect[3] = {
        { "Alpha, Ann","Beta, Bob","Round Trip Open","Testville","2026.05.01","3","1-0","B12",
          2500,2400,"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w HAha - 0 2", 2 },
        { "Gamma, Gina","Delta, Dan","Chess960 Cup","Berlin","2026.06.02","1","1/2-1/2","",
          0,0,"", 5 },
        { "Epsilon, Eve","Zeta, Zoe","Setup Match","Praha","2026.07.03","4.2","0-1","",
          0,0,"8/8/8/3k4/8/3K4/8/8 b - - 3 2", 3 },
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
    }

    std::string cleanup("rm -rf '"); cleanup += dir; cleanup += "'";
    (void)std::system(cleanup.c_str());
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
    testWriterRoundTrip();

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
