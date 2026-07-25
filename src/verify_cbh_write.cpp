// ======================================================================
// Round-trip verifier for CBH (ChessBase) write support.
// Imports PGN → SCI, exports to CBH, re-imports CBH, compares.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
#include "db/db_game.h"
#include "db/db_home_pawns.h"
#include "db/db_log.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"

#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"

#include "db/cbh/cbh_codec.h"
#include "db/cbh/cbh_consumer.h"
#include "db/cbh/cbh_decoder.h"
#include "db/cbh/cbh_encoder.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_byte_stream.h"
#include "util/u_misc.h"
#include "util/u_progress.h"

#include "mstl/m_sstream.h"
#include "mstl/m_string.h"
#include "mstl/m_ifstream.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

struct TestDecoder : public cbh::Decoder
{
	TestDecoder(util::ByteStream& gStrm, bool isChess960)
		:cbh::Decoder(gStrm, isChess960)
	{
	}

	void begin() { startDecoding(); }

	unsigned next(Move& move, unsigned& count)
	{
		return decodeMove(move, count, true);
	}

	Board const& currentBoard() const
	{
		return m_position.board();
	}
};

// Simple games for basic round-trip testing
char const* SamplePgn =
	"[Event \"CBH Test 1\"]\n"
	"[Site \"TestCity\"]\n"
	"[Date \"2024.06.15\"]\n"
	"[Round \"1\"]\n"
	"[White \"Smith, John\"]\n"
	"[Black \"Jones, Mary\"]\n"
	"[WhiteElo \"2500\"]\n"
	"[BlackElo \"2400\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C50\"]\n"
	"\n"
	"1. e4 $1 {King pawn opening} e5 {Symmetry} 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 5. d3 d6 6. c3 O-O 1-0\n"
	"\n"
	"[Event \"CBH Test 2\"]\n"
	"[Site \"TestCity\"]\n"
	"[Date \"2024.06.16\"]\n"
	"[Round \"2\"]\n"
	"[White \"Brown, Alice\"]\n"
	"[Black \"Green, Bob\"]\n"
	"[WhiteElo \"2300\"]\n"
	"[BlackElo \"2350\"]\n"
	"[Result \"1/2-1/2\"]\n"
	"[ECO \"D30\"]\n"
	"\n"
	"1. d4 d5 2. c4 e6 3. Nf3 Nf6 4. Bg5 Be7 5. e3 O-O 1/2-1/2\n"
	"\n"
	"[Event \"CBH Test 3\"]\n"
	"[Site \"TestCity\"]\n"
	"[Date \"2024.06.17\"]\n"
	"[Round \"3\"]\n"
	"[White \"White, Pat\"]\n"
	"[Black \"Black, Chris\"]\n"
	"[WhiteElo \"2200\"]\n"
	"[BlackElo \"2250\"]\n"
	"[Result \"0-1\"]\n"
	"[ECO \"B01\"]\n"
	"\n"
	"1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 4. d4 Nf6 5. Nf3 Bf5 0-1\n"
	"\n"
	"[Event \"CBH Test 4\"]\n"
	"[Site \"TestCity\"]\n"
	"[Date \"2024.06.18\"]\n"
	"[Round \"4\"]\n"
	"[White \"Var, Vera\"]\n"
	"[Black \"Line, Lou\"]\n"
	"[WhiteElo \"2100\"]\n"
	"[BlackElo \"2150\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C44\"]\n"
	"\n"
	"{Pre-game comment} 1. e4 e5 2. Nf3 (2. f4 exf4 {inside variation}) 2... Nc6 $2\n"
	"{after the variation} 3. Bb5 $1 a6 4. Ba4 Nf6 1-0\n";


struct SilentPgnReader : public PgnReader
{
	SilentPgnReader(mstl::istream& stream)
		:PgnReader(stream,
					 variant::Normal,
					 sys::utf8::Codec::utf8(),
					 PgnReader::File,
					 PgnReader::Normalize,
					 PgnReader::UseResultTag)
		,errors(0)
	{
	}

	void warning(Warning,
					 unsigned,
					 unsigned,
					 unsigned,
					 variant::Type,
					 mstl::string const&,
					 mstl::string const&) override
	{
	}

	void error(Error,
				  unsigned,
				  unsigned,
				  unsigned,
				  variant::Type,
				  mstl::string const&,
				  mstl::string const&,
				  mstl::string const&) override
	{
		++errors;
	}

	void error(save::State, unsigned, unsigned, variant::Type) override
	{
		++errors;
	}

	unsigned estimateNumberOfGames() override
	{
		return 4;
	}

	unsigned errors;
};


struct TclInterpreter
{
	TclInterpreter()
	{
		tcl::bits::interp = Tcl_CreateInterp();
		Tcl_Init(tcl::bits::interp);
	}

	~TclInterpreter()
	{
		Tcl_DeleteInterp(tcl::bits::interp);
		tcl::bits::interp = nullptr;
	}
};


void
initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
	db::si3::Encoder::initialize();
	// cbh::Encoder::initialize() is called automatically from its constructor
}


void
loadEcoFile()
{
	mstl::string path(SHAREDIR "/data/eco.bin");
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);

	if (!stream)
	{
		::fprintf(stderr, "cannot open ECO file '%s'\n", path.c_str());
		::exit(1);
	}

	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
}


void
cleanupSci(mstl::string const& root)
{
	::remove((root + ".sci").c_str());
	::remove((root + ".scg").c_str());
	::remove((root + ".scn").c_str());
}


void
cleanupCbh(mstl::string const& root)
{
	::remove((root + ".cbh").c_str());
	::remove((root + ".cbg").c_str());
	::remove((root + ".cba").c_str());
	::remove((root + ".cbp").c_str());
	::remove((root + ".cbt").c_str());
	::remove((root + ".cbc").c_str());
	::remove((root + ".cbs").c_str());
	::remove((root + ".cbe").c_str());
	::remove((root + ".cbj").c_str());
	::remove((root + ".ini").c_str());
}


bool
verifyGameCount(Database const& db, unsigned expected, char const* label)
{
	if (db.countGames() != expected)
	{
		::fprintf(stderr, "%s: expected %u games, got %u\n",
					 label, expected, db.countGames());
		return false;
	}
	return true;
}


bool
verifyPlayerResultTags(Database const& lhs, unsigned lhsIdx,
							  Database const& rhs, unsigned rhsIdx)
{
	TagSet lhsTags, rhsTags;
	lhs.setupTags(lhsIdx, lhsTags);
	rhs.setupTags(rhsIdx, rhsTags);

	tag::ID fields[] = { tag::White, tag::Black, tag::Result };

	for (unsigned i = 0; i < sizeof(fields)/sizeof(fields[0]); ++i)
	{
		if (lhsTags.value(fields[i]) != rhsTags.value(fields[i]))
		{
			::fprintf(stderr, "game %u: tag %u mismatch: '%s' vs '%s'\n",
						 lhsIdx, unsigned(fields[i]),
						 lhsTags.value(fields[i]).c_str(),
						 rhsTags.value(fields[i]).c_str());
			return false;
		}
	}

	return true;
}


bool
verifyAnnotatedGameData(Database& lhs, unsigned lhsIdx,
							 Database& rhs, unsigned rhsIdx)
{
	Game lhsGame;
	Game rhsGame;

	if (lhs.loadGame(lhsIdx, lhsGame) != load::Ok)
	{
		::fprintf(stderr, "failed to load source game %u\n", lhsIdx);
		return false;
	}

	if (rhs.loadGame(rhsIdx, rhsGame) != load::Ok)
	{
		::fprintf(stderr, "failed to load reimported game %u\n", rhsIdx);
		return false;
	}

	if (lhsGame.countComments() != rhsGame.countComments())
	{
		::fprintf(stderr, "game %u: comment count mismatch: %u vs %u\n",
					 lhsIdx, lhsGame.countComments(), rhsGame.countComments());
		return false;
	}

	if (lhsGame.countAnnotations() != rhsGame.countAnnotations())
	{
		::fprintf(stderr, "game %u: annotation count mismatch: %u vs %u\n",
					 lhsIdx, lhsGame.countAnnotations(), rhsGame.countAnnotations());
		return false;
	}

	while (lhsGame.forward() && rhsGame.forward())
	{
		if (lhsGame.comment(move::Post).content() != rhsGame.comment(move::Post).content())
		{
			::fprintf(stderr, "game %u: post-move comment mismatch after ply %u\n",
						 lhsIdx, lhsGame.plyNumber());
			return false;
		}

		mstl::string lhsSuffix;
		mstl::string rhsSuffix;
		lhsGame.suffix(lhsSuffix);
		rhsGame.suffix(rhsSuffix);

		if (lhsSuffix != rhsSuffix)
		{
			::fprintf(stderr, "game %u: annotation suffix mismatch after ply %u: '%s' vs '%s'\n",
						 lhsIdx, lhsGame.plyNumber(), lhsSuffix.c_str(), rhsSuffix.c_str());
			return false;
		}
	}

	if (lhsGame.isBeforeLineEnd() != rhsGame.isBeforeLineEnd())
	{
		::fprintf(stderr, "game %u: move traversal length mismatch\n", lhsIdx);
		return false;
	}

	return true;
}


bool
verifyCbhRoundTrip(mstl::string const& sciRoot,
						 mstl::string const& cbhRoot,
						 util::Progress& progress)
{
	// Step 1: Open the source SCI database
	::fprintf(stderr, "  opening source SCI...\n");
	Database source(sciRoot + ".sci", sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	unsigned numGames = source.countGames();

	::fprintf(stderr, "  source has %u games\n", numGames);

	// Step 2: Create a new CBH database and export games to it
	{
		::fprintf(stderr, "  creating CBH destination...\n");
		Database destination(cbhRoot + ".cbh",
								  sys::utf8::Codec::windows(),
								  storage::OnDisk,
								  variant::Normal);
		::fprintf(stderr, "  CBH destination created, writable=%d\n", destination.isWritable());

		for (unsigned i = 0; i < numGames; ++i)
		{
			::fprintf(stderr, "  exporting game %u...\n", i);
			save::State state = source.exportGame(i, destination);
			if (!save::isOk(state))
			{
				::fprintf(stderr, "export game %u to CBH failed: state=%d\n", i, int(state));
				source.close();
				destination.close();
				return false;
			}
		}

		::fprintf(stderr, "  saving CBH...\n");
		destination.save(progress);
		::fprintf(stderr, "  closing CBH...\n");
		destination.close();
		::fprintf(stderr, "  CBH closed\n");
	}

	::fprintf(stderr, "  closing source...\n");
	source.close();

	::printf("  exported %u games to CBH\n", numGames);

	// Step 3: Re-open the CBH database
	Database reimported(cbhRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);

	if (!verifyGameCount(reimported, numGames, "reimported CBH"))
	{
		reimported.close();
		return false;
	}

	::printf("  reimported %u games from CBH\n", reimported.countGames());

	// Step 4: Compare games
	Database sourceAgain(sciRoot + ".sci", sys::utf8::Codec::utf8(), permission::ReadOnly, progress);

	bool ok = true;
	for (unsigned i = 0; i < numGames && ok; ++i)
	{
		ok = verifyPlayerResultTags(sourceAgain, i, reimported, i)
			&& verifyAnnotatedGameData(sourceAgain, i, reimported, i);
	}

	if (!ok)
	{
		::fprintf(stderr, "CBH game comparison failed\n");
	}

	sourceAgain.close();
	reimported.close();

	return ok;
}


bool
verifySingleMoveCodec(Board const& start,
							 Move const& move,
							 char const* label,
							 bool expectCastling,
							 Square expectedRookFrom = sq::Null,
							 Square expectedKingTo = sq::Null,
							 Square expectedRookTo = sq::Null)
{
	Byte buffer[256];
	util::ByteStream encoded(buffer, sizeof(buffer));
	encoded.resetp();

	cbh::Encoder encoder(encoded);
	encoder.startEncoding(start, false);

	unsigned count = 0;
	encoder.encodeMove(move, count);

	unsigned totalSize = encoded.tellp();
	util::ByteStream::set(encoded.base(), uint32_t(totalSize | 0x40000000));

	util::ByteStream decodeStream(buffer, totalSize);
	TestDecoder decoder(decodeStream, true);
	decoder.begin();

	if (!decoder.currentBoard().isEqualZHPosition(start))
	{
		::fprintf(stderr, "decoded start position mismatch for %s\n", label);
		return false;
	}

	unsigned decodeCount = 0;
	Move decoded;
	unsigned tag = decoder.next(decoded, decodeCount);

	if (tag != 0)
	{
		::fprintf(stderr, "expected a move token for %s, got %u\n", label, tag);
		return false;
	}

	if (expectCastling)
	{
		if (!decoded.isCastling())
		{
			::fprintf(stderr, "decoded %s move is not castling\n", label);
			return false;
		}

		if (decoded.castlingRookFrom() != expectedRookFrom)
		{
			::fprintf(stderr, "decoded %s rook square mismatch: expected %u got %u\n",
						 label, unsigned(expectedRookFrom), unsigned(decoded.castlingRookFrom()));
			return false;
		}

		if (decoded.castlingKingTo() != expectedKingTo || decoded.castlingRookTo() != expectedRookTo)
		{
			::fprintf(stderr, "decoded %s castling targets mismatch\n", label);
			return false;
		}
	}
	else
	{
		if (decoded.isCastling())
		{
			::fprintf(stderr, "decoded %s move unexpectedly became castling\n", label);
			return false;
		}

		if (decoded.from() != move.from() || decoded.to() != move.to() || decoded.piece() != move.piece())
		{
			::fprintf(stderr, "decoded %s move mismatch\n", label);
			return false;
		}
	}

	return true;
}


bool
verifyChess960CastlingCodec()
{
	::fprintf(stderr, "step 3: low-level Chess960 castling codec check...\n");

	Board start;
	char const* err = start.setup("4k3/8/8/8/8/8/8/4K1R1 w G - 0 1", variant::Normal);
	if (!err)
	{
		::fprintf(stderr, "failed to set up Chess960 test position: %s\n", err);
		return false;
	}

	Square rookFrom = start.shortCastlingRook(color::White);
	if (rookFrom != sq::g1)
	{
		::fprintf(stderr, "unexpected short-castling rook square: %u\n", unsigned(rookFrom));
		return false;
	}

	Move castle = Move::genCastling(start.kingSquare(color::White), rookFrom);
	if (!verifySingleMoveCodec(start, castle, "Chess960 short-castling", true, sq::g1, sq::g1, sq::f1))
		return false;

	// Standard long castling (king e1, rook a1) as a sanity check for 0-0-0.
	Board longStart;
	char const* longErr = longStart.setup("4k3/8/8/8/8/8/8/R3K3 w A - 0 1", variant::Normal);
	if (!longErr)
	{
		::fprintf(stderr, "failed to set up Chess960 long-castling test position\n");
		return false;
	}

	Square longRook = longStart.longCastlingRook(color::White);
	if (longRook != sq::a1)
	{
		::fprintf(stderr, "unexpected long-castling rook square: %u\n", unsigned(longRook));
		return false;
	}

	Move longCastle = Move::genCastling(longStart.kingSquare(color::White), longRook);
	if (!verifySingleMoveCodec(longStart, longCastle, "Chess960 long-castling", true, sq::a1, sq::c1, sq::d1))
		return false;

	::fprintf(stderr, "  Chess960 short/long-castling codec check passed\n");
	return true;
}


bool
verifyChess960OffFileKingCastling()
{
	::fprintf(stderr, "step 3b: Chess960 off-e-file king castling codec check...\n");

	// King on d1 with rooks on a1 and h1. This position forces the codec to
	// handle a king that does not start on the e-file, locking in the
	// current Convention A behavior (king -> c1/g1, rook -> d1/f1).
	Board start;
	char const* err = start.setup("4k3/8/8/8/8/8/8/R2K3R w AH - 0 1", variant::Normal);
	if (!err)
	{
		::fprintf(stderr, "failed to set up Chess960 off-e-file test position\n");
		return false;
	}

	Square longRook = start.longCastlingRook(color::White);
	if (longRook != sq::a1)
	{
		::fprintf(stderr, "unexpected long-castling rook square: %u\n", unsigned(longRook));
		return false;
	}

	Move longCastle = Move::genCastling(start.kingSquare(color::White), longRook);
	if (!verifySingleMoveCodec(start, longCastle, "Chess960 off-e-file long-castling",
	                           true, sq::a1, sq::c1, sq::d1))
		return false;

	Square shortRook = start.shortCastlingRook(color::White);
	if (shortRook != sq::h1)
	{
		::fprintf(stderr, "unexpected short-castling rook square: %u\n", unsigned(shortRook));
		return false;
	}

	Move shortCastle = Move::genCastling(start.kingSquare(color::White), shortRook);
	if (!verifySingleMoveCodec(start, shortCastle, "Chess960 off-e-file short-castling",
	                           true, sq::h1, sq::g1, sq::f1))
		return false;

	::fprintf(stderr, "  Chess960 off-e-file castling codec check passed\n");
	return true;
}


bool
verifyChess960PieceMoveCodec()
{
	::fprintf(stderr, "step 4: low-level Chess960 piece-move codec check...\n");

	Board start;
	char const* err = start.setup("4k3/8/8/8/8/8/6N1/4K1R1 w G - 0 1", variant::Normal);
	if (!err)
	{
		::fprintf(stderr, "failed to set up Chess960 piece-move test position: %s\n", err);
		return false;
	}

	Move knightMove = Move::genKnightMove(sq::g2, sq::e3);
	if (!verifySingleMoveCodec(start, knightMove, "Chess960 knight move", false))
		return false;

	::fprintf(stderr, "  Chess960 piece-move codec check passed\n");
	return true;
}


bool
verifyGrenkeChess960FENs()
{
	::fprintf(stderr, "step 5: GRENKE Chess960 start-position codec check...\n");

	// The nine unique Chess960 start positions from the Grenke Freestyle
	// Chess Open 2026 (see GRENKE_CHESS960_FIXTURES.md).  In the raw start
	// positions the squares between the king and rooks are usually occupied,
	// so castling is not legal.  We therefore verify the CBH custom-position
	// codec by round-tripping a simple pawn move in each position; this still
	// exercises the 28-byte start-position encoding/decoding path for every
	// GRENKE FEN.
	char const* const fens[] =
	{
		"bnrqnkrb/pppppppp/8/8/8/8/PPPPPPPP/BNRQNKRB w GCgc - 0 1",
		"nnbbrqkr/pppppppp/8/8/8/8/PPPPPPPP/NNBBRQKR w HEhe - 0 1",
		"nrbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/NRBQKBNR w HBhb - 0 1",
		"rkqrbbnn/pppppppp/8/8/8/8/PPPPPPPP/RKQRBBNN w DAda - 0 1",
		"rnqnbkrb/pppppppp/8/8/8/8/PPPPPPPP/RNQNBKRB w GAga - 0 1",
		"rnbbknqr/pppppppp/8/8/8/8/PPPPPPPP/RNBBKNQR w HAha - 0 1",
		"rnbkqbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBKQBNR w HAha - 0 1",
		"nbrqkrbn/pppppppp/8/8/8/8/PPPPPPPP/NBRQKRBN w FCfc - 0 1",
		"nrbbknqr/pppppppp/8/8/8/8/PPPPPPPP/NRBBKNQR w HBhb - 0 1",
	};
	char const* const labels[] =
	{
		"FEN1", "FEN2", "FEN3", "FEN4", "FEN5", "FEN6", "FEN7", "FEN8", "FEN9",
	};

	for (unsigned i = 0; i < sizeof(fens)/sizeof(fens[0]); ++i)
	{
		Board start;
		char const* err = start.setup(fens[i], variant::Normal);
		if (!err)
		{
			::fprintf(stderr, "failed to set up %s (%s)\n", labels[i], fens[i]);
			return false;
		}

		// Verify that a simple one-square pawn advance round-trips through the
		// CBH custom-position codec.  a2->a3 is legal in every GRENKE FEN.
		Square fromSq = sq::make(sq::FyleA, sq::Rank2);
		Square toSq   = sq::make(sq::FyleA, sq::Rank3);
		Move m = Move::genOneForward(fromSq, toSq);
		mstl::string label;
		label.format("%s pawn move", labels[i]);
		if (!verifySingleMoveCodec(start, m, label.c_str(), false))
			return false;
	}

	::fprintf(stderr, "  GRENKE Chess960 FEN codec check passed\n");
	return true;
}

} // namespace


int
main(int argc, char** argv)
{
	char buf[160];
	::snprintf(buf, sizeof(buf), "/tmp/scidb-cbh-verify-%ld", long(::getpid()));
	mstl::string root(buf);
	mstl::string sciRoot(root + "-src");
	mstl::string cbhRoot(root + "-dst");
	util::Progress& progress = util::Progress::null();

	try
	{
		::fprintf(stderr, "initializing tcl...\n");
		TclInterpreter tcl;
		::fprintf(stderr, "initializing statics...\n");
		initializeStatics();
		::fprintf(stderr, "loading eco...\n");
		loadEcoFile();
		::fprintf(stderr, "init done\n");
		cleanupSci(sciRoot);
		cleanupCbh(cbhRoot);

		// Import PGN into SCI database
		::fprintf(stderr, "step 1: importing PGN to SCI...\n");
		mstl::string samplePgn(SamplePgn);
		mstl::istringstream stream(samplePgn);
		SilentPgnReader reader(stream);
		::fprintf(stderr, "creating SCI db...\n");
		Database source(sciRoot + ".sci", sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		::fprintf(stderr, "importing games...\n");
		unsigned imported = source.importGames(reader, progress);
		::fprintf(stderr, "saving...\n");
		source.save(progress);
		::fprintf(stderr, "closing...\n");
		source.close();
		::fprintf(stderr, "import done\n");

		if (reader.errors != 0 || imported != 4)
		{
			::fprintf(stderr, "PGN import failed: imported=%u errors=%u\n", imported, reader.errors);
			cleanupSci(sciRoot);
			return 1;
		}
		::printf("  imported %u games\n", imported);

		// Round-trip test: SCI → CBH → re-read CBH
		::printf("step 2: round-trip SCI -> CBH -> verify...\n");
		if (!verifyCbhRoundTrip(sciRoot, cbhRoot, progress))
		{
			::fprintf(stderr, "CBH round-trip verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		if (!verifyChess960CastlingCodec())
		{
			::fprintf(stderr, "CBH Chess960 castling verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		if (!verifyChess960OffFileKingCastling())
		{
			::fprintf(stderr, "CBH Chess960 off-e-file castling verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		if (!verifyChess960PieceMoveCodec())
		{
			::fprintf(stderr, "CBH Chess960 piece-move verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		if (!verifyGrenkeChess960FENs())
		{
			::fprintf(stderr, "CBH GRENKE Chess960 FEN verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		cleanupSci(sciRoot);
		cleanupCbh(cbhRoot);
		::puts("CBH write round-trip verification PASSED");
		return 0;
	}
	catch (IOException const& exc)
	{
		::fprintf(stderr, "I/O exception: %s\n", exc.what());
	}
	catch (mstl::exception const& exc)
	{
		::fprintf(stderr, "exception: %s\n", exc.what());
	}

	cleanupSci(sciRoot);
	cleanupCbh(cbhRoot);
	return 1;
}
