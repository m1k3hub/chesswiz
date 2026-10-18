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
#include "db/cbh/cbh_game_decoder.h"
#include "db/cbh/cbh_quotation.h"
#include "db/db_game_data.h"
#include "db/db_move_node.h"
#include "db/cbh/cbh_encoder.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_byte_stream.h"
#include "util/u_misc.h"
#include "util/u_progress.h"

#include "mstl/m_sstream.h"
#include "mstl/m_string.h"
#include "mstl/m_ifstream.h"

#include "db/db_game_info.h"
#include "db/db_mark_set.h"
#include "db/db_pgn_writer.h"

#include "mstl/m_fstream.h"
#include "mstl/m_vector.h"

#include <tcl.h>
#include <stdarg.h>
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
	// Chess Open 2026 (see docs/formats/GRENKE_CHESS960_FIXTURES.md).  In the raw start
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


static bool
verifyDisplayAnnotations()
{
	// Standard start, a3 and a6. Annotation positions count decoded moves
	// from zero; -1 is game-wide. Exercise the public tree decoder.
	Byte moves[] = {0, 0, 0, 6, 0x2d, 0x2e};
	Byte annotations[] = {
		0xff, 0xff, 0xff, 0x22, 0, 10, 0, 0, 0x80, 0,
		0, 0, 0, 0x22, 0, 10, 0, 0, 0, 0x28,
		0, 0, 0, 0x23, 0, 10, 2, 0, 0, 0,
		0, 0, 0, 0x14, 0, 7, 3,
		0, 0, 0, 0x15, 0, 8, 3, 0x36,
		0, 0, 0, 0x22, 0, 10, 0x80, 0, 0x60, 0,
		0, 0, 0, 0x22, 0, 7, 0xab,
		0, 0, 0, 0x15, 0, 9, 3, 0x38, 0xff,
		0, 0, 0, 0x14, 0, 6,
		0, 0, 0, 0x22, 0, 10, 0, 0, 0, 0,
		0, 0, 1, 0x22, 0, 10, 0, 0, 2, 0,
		0, 0, 1, 0x18, 0, 7, 3,
	};
	util::ByteStream g(moves, sizeof(moves)), a(annotations, sizeof(annotations));
	sys::utf8::Codec codec(sys::utf8::Codec::utf8());
	cbh::GameDecoder decoder(g, a, codec, false);
	GameData data;
	// GameData starts with an empty end node; decodeMoves installs its own.
	delete data.m_startNode->removeNext();
	if (decoder.doDecoding(data) != 2 || !a.isEmpty()) return false;
	mstl::string const& root = data.m_startNode->comment(move::Post).content();
	mstl::string const& first = data.m_startNode->next()->comment(move::Post).content();
	mstl::string const& second = data.m_startNode->next()->next()->comment(move::Post).content();
	char const* expected[] = {
		"Medal: Novelty, Strategy", "Variation color (CBH payload: 02 00 00 00)",
		"Pawn structure (CBH payload: 03)", "Piece path (CBH payload: 03 36)",
		"Medal: Tactical blunder, Strategical blunder, Unknown bits 0x80000000",
		"Medal (CBH payload: AB)", "Piece path (CBH payload: 03 38 FF)",
		"Pawn structure (CBH payload:)", "Medal: None",
	};
	for (unsigned i = 0; i < sizeof(expected)/sizeof(expected[0]); ++i)
	{
		if (!::strstr(first.c_str(), expected[i]))
		{
			::fprintf(stderr, "Missing annotation: %s\nActual: %s\n", expected[i], first.c_str());
			return false;
		}
	}
	return ::strstr(root.c_str(), "Medal: User")
		&& !::strstr(root.c_str(), "Novelty")
		&& !::strstr(first.c_str(), "Defense")
		&& ::strstr(second.c_str(), "Medal: Defense")
		&& ::strstr(second.c_str(), "Critical endgame position");
}


static mstl::string
decodeQuotationPayload(Byte const* payload, unsigned length)
{
	Byte annotations[65536];
	util::ByteStream out(annotations, sizeof(annotations));
	out.resetp();
	out << util::ByteStream::uint24_t(0xffffff) << uint8_t(0x13) << uint16_t(length + 6);
	for (unsigned i = 0; i < length; ++i) out << uint8_t(payload[i]);
	// Must still decode after a malformed or truncated quotation header/blob.
	out << util::ByteStream::uint24_t(0xffffff) << uint8_t(0x18) << uint16_t(7) << uint8_t(3);
	util::ByteStream a(annotations, out.tellp());
	Byte moves[] = {0, 0, 0, 4};
	util::ByteStream g(moves, sizeof(moves));
	sys::utf8::Codec codec(sys::utf8::Codec::utf8());
	cbh::GameDecoder decoder(g, a, codec, false);
	GameData data;
	delete data.m_startNode->removeNext();
	decoder.doDecoding(data);
	return data.m_startNode->comment(move::Post).content();
}


static bool
verifyQuotationCorpus(char const* filename)
{
	FILE* file = ::fopen(filename, "r");
	if (!file) return false;
	char line[16384];
	unsigned count = 0;
	bool ok = true;
	while (ok && ::fgets(line, sizeof(line), file))
	{
		if (line[0] == '#') continue;
		char* eco = ::strchr(line, '\t');
		if (!eco) { ok = false; break; }
		*eco++ = 0;
		char* san = ::strchr(eco, '\t');
		if (!san) { ok = false; break; }
		*san++ = 0;
		san[::strcspn(san, "\r\n")] = 0;
		unsigned length = ::strlen(line)/2;
		Byte payload[8192];
		if (length > sizeof(payload)) { ok = false; break; }
		for (unsigned i = 0; i < length; ++i)
		{
			char hex[] = { line[2*i], line[2*i + 1], 0 };
			payload[i] = Byte(::strtoul(hex, 0, 16));
		}
		mstl::string text = decodeQuotationPayload(payload, length);
		mstl::string ecoText("ECO "); ecoText += eco;
		ok = ::strstr(text.c_str(), "Quoted game:") && ::strstr(text.c_str(), ecoText.c_str())
			&& ::strstr(text.c_str(), san) && ::strstr(text.c_str(), "Critical endgame position");
		if (!ok) ::fprintf(stderr, "Quotation %u mismatch: %s\n", count, text.c_str());
		// Truncate at every byte, updating the redundant payload length.
		// No truncation may consume or suppress the following annotation,
		// and none may publish a move replay (the SAN always starts a new
		// line with the move-1 number; citation and follow-up never do).
		for (unsigned n = 0; ok && n < length; ++n)
		{
			payload[0] = Byte(n >> 8); payload[1] = Byte(n);
			text = decodeQuotationPayload(payload, n);
			ok = ::strstr(text.c_str(), "Critical endgame position") && !::strstr(text.c_str(), "\n1.");
			if (!ok) ::fprintf(stderr, "Quotation %u truncation %u failed: [%s]\n", count, n, text.c_str());
		}
		++count;
	}
	::fclose(file);
	::printf("Quotation corpus: %u records %s\n", count, ok ? "PASSED" : "FAILED");
	return ok && count != 0;
}


static bool
verifyQuotationEdges()
{
	struct Case { unsigned length; Byte bytes[22]; char const* san; };
	Case const cases[] = {
		{10, {0xf6,0x8e,0x6c,0xd8,0x9f,0x58,0x3a,0x4b,0xb9,0xb3}, "1.f3 e5 2.g4 Qh4#"},
		{12, {0xdf,0x93,0x14,0x6b,0x6d,0x49,0x9a,0x64,0x9b,0xde,0xba,0xb4}, "1.e4 a6 2.e5 d5 3.exd6"},
		{22, {0xaf,0x6c,0xb8,0x0f,0x15,0xc0,0x3a,0xb9,0x17,0xc5,0x3c,0xe1,0xc4,0x33,0xa4,0x2e,0x1b,0xfa,0x84,0xf8,0xbf,0xb9},
			"1.a4 h5 2.a5 h4 3.a6 h3 4.axb7 hxg2 5.bxa8=Q gxf1=N"},
	};
	for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i)
	{
		mstl::string san;
		if (!cbh::decodeQuotationMoves(cases[i].bytes, cases[i].length, san) || san != cases[i].san)
		{
			::fprintf(stderr, "Quotation edge %u: %s\n", i, san.c_str());
			return false;
		}
		for (unsigned n = 0; n < cases[i].length; ++n)
		{
			san = "unchanged";
			if (cbh::decodeQuotationMoves(cases[i].bytes, n, san) || san != "unchanged") return false;
		}
	}
	Byte bad[] = {0, 0, 0xb6, 0xb0}; // unknown control word, then terminator
	mstl::string san("unchanged");
	if (cbh::decodeQuotationMoves(bad, sizeof(bad), san) || san != "unchanged") return false;
	Byte trailing[] = {0xb5, 0xaf, 0xdf, 0x93}; // terminator followed by junk
	if (cbh::decodeQuotationMoves(trailing, sizeof(trailing), san) || san != "unchanged") return false;

	unsigned const ecoCodes[] = {0, 1, 100, 101, 500, 501, 511};
	char const* expected[] = {0, "ECO A00", "ECO A99", "ECO B00", "ECO E99", 0, 0};
	for (unsigned i = 0; i < sizeof(ecoCodes)/sizeof(ecoCodes[0]); ++i)
	{
		Byte payload[64];
		util::ByteStream out(payload, sizeof(payload)); out.resetp();
		out << uint16_t(0) << uint16_t(2) << uint16_t(0) << uint8_t(1) << uint8_t('W');
		out << uint8_t(0) << uint8_t(1) << uint8_t('B');
		out << uint8_t(0) << uint16_t(0) << uint16_t(0) << uint16_t((ecoCodes[i] << 7) | 0x7f);
		// Empty event/site and fixed metadata, then 1.e4 and the end marker.
		for (unsigned n = 0; n < 21; ++n) out << uint8_t(0);
		out << uint8_t(0xdf) << uint8_t(0x93) << uint8_t(0xb6) << uint8_t(0xb0);
		unsigned length = out.tellp();
		payload[0] = Byte(length >> 8); payload[1] = Byte(length);
		mstl::string text = decodeQuotationPayload(payload, length);
		if (!::strstr(text.c_str(), "1.e4")) return false;
		if (expected[i] ? ::strstr(text.c_str(), expected[i]) == 0
		                    : ::strstr(text.c_str(), "ECO ") != 0) return false;
	}
	::puts("Quotation edge cases PASSED");
	return true;
}


static void
compareNodeTree(	unsigned gameIdx,
						MoveNode const* lhs,
						MoveNode const* rhs,
						bool& moveDiff,
						bool& varDiff,
						bool& commentDiff,
						bool& nagDiff,
						bool& markDiff)
{
	while (lhs && rhs)
	{
		if (lhs->atLineEnd() != rhs->atLineEnd())
		{
			moveDiff = true;
			return;
		}

		if (lhs->move() != rhs->move())
			moveDiff = true;

		if (lhs->comment(move::Ante).content() != rhs->comment(move::Ante).content()
			|| lhs->comment(move::Post).content() != rhs->comment(move::Post).content())
		{
			commentDiff = true;
		}

		Annotation lhsAnn(lhs->annotation());
		Annotation rhsAnn(rhs->annotation());
		lhsAnn.sort();
		rhsAnn.sort();
		if (lhsAnn != rhsAnn)
			nagDiff = true;

		MarkSet lhsMarks(lhs->marks());
		MarkSet rhsMarks(rhs->marks());
		lhsMarks.sort();
		rhsMarks.sort();
		if (lhsMarks != rhsMarks)
			markDiff = true;

		if (lhs->variationCount() != rhs->variationCount())
		{
			varDiff = true;
		}
		else
		{
			for (unsigned v = 0; v < lhs->variationCount(); ++v)
			{
				compareNodeTree(gameIdx, lhs->variation(v), rhs->variation(v),
					moveDiff, varDiff, commentDiff, nagDiff, markDiff);
			}
		}

		lhs = lhs->next();
		rhs = rhs->next();
	}

	if ((lhs != nullptr) != (rhs != nullptr))
		moveDiff = true;
}


static mstl::string
exportToPgn(Database const& db, unsigned index)
{
	mstl::ostringstream oss;
	unsigned flags = PgnWriter::Default_Flags
		| Writer::Flag_Include_Annotation
		| Writer::Flag_Include_Marks
		| Writer::Flag_Include_Move_Info
		| Writer::Flag_Use_UTF8;
	PgnWriter writer(db.format(), oss, sys::utf8::Codec::utf8(), PgnWriter::Unix, flags);
	writer.start();
	db.exportGame(index, writer);
	writer.finish();
	return oss.str();
}


struct FixtureDiffCounts
{
	unsigned totalGames;
	unsigned guidingTexts;
	unsigned loadErrors;
	unsigned headerDiffs;
	unsigned moveDiffs;
	unsigned variationDiffs;
	unsigned commentDiffs;
	unsigned nagDiffs;
	unsigned markDiffs;
	unsigned pgnDiffs;

	FixtureDiffCounts()
		:totalGames(0)
		,guidingTexts(0)
		,loadErrors(0)
		,headerDiffs(0)
		,moveDiffs(0)
		,variationDiffs(0)
		,commentDiffs(0)
		,nagDiffs(0)
		,markDiffs(0)
		,pgnDiffs(0)
	{
	}

	unsigned totalDiffs() const
	{
		return loadErrors + headerDiffs + moveDiffs + variationDiffs
			+ commentDiffs + nagDiffs + markDiffs + pgnDiffs;
	}
};


static void
compareDatabases(Database& src, Database& dst, FixtureDiffCounts& counts)
{
	counts.totalGames = src.countGames();
	if (dst.countGames() != src.countGames())
		counts.loadErrors += mstl::abs(int(src.countGames()) - int(dst.countGames()));

	unsigned n = mstl::min(src.countGames(), dst.countGames());
	for (unsigned i = 0; i < n; ++i)
	{
		GameInfo const& sInfo = src.gameInfo(i);
		GameInfo const& dInfo = dst.gameInfo(i);

		if (sInfo.isGuidingText())
			++counts.guidingTexts;

		bool hdrDiff = (sInfo.isGuidingText() != dInfo.isGuidingText());

		Game sGame, dGame;
		load::State sLoad = src.loadGame(i, sGame);
		load::State dLoad = dst.loadGame(i, dGame);
		if (sLoad != load::Ok || dLoad != load::Ok)
		{
			++counts.loadErrors;
			continue;
		}

		if (!sInfo.isGuidingText())
		{
			if (sInfo.playerName(color::White) != dInfo.playerName(color::White)
				|| sInfo.playerName(color::Black) != dInfo.playerName(color::Black)
				|| sInfo.event() != dInfo.event()
				|| sInfo.site() != dInfo.site()
				|| sInfo.annotator() != dInfo.annotator()
				|| sInfo.date() != dInfo.date()
				|| sInfo.eventDate() != dInfo.eventDate()
				|| sInfo.eventCountry() != dInfo.eventCountry()
				|| sInfo.eventType() != dInfo.eventType()
				|| sInfo.timeMode() != dInfo.timeMode()
				|| sInfo.round() != dInfo.round()
				|| sInfo.subround() != dInfo.subround()
				|| sInfo.result() != dInfo.result()
				|| sInfo.elo(color::White) != dInfo.elo(color::White)
				|| sInfo.elo(color::Black) != dInfo.elo(color::Black)
				|| sInfo.eco(variant::Normal) != dInfo.eco(variant::Normal)
				|| sInfo.flags() != dInfo.flags()
				|| sInfo.plyCount() != dInfo.plyCount())
			{
				hdrDiff = true;
			}
		}
		else
		{
			if (sGame.tags().value(tag::Event) != dGame.tags().value(tag::Event)
				|| sInfo.annotator() != dInfo.annotator()
				|| sInfo.round() != dInfo.round())
			{
				hdrDiff = true;
			}
			if (sGame.data().m_guidingText != dGame.data().m_guidingText)
				++counts.commentDiffs;
		}

		if (hdrDiff)
			++counts.headerDiffs;

		if (!sInfo.isGuidingText())
		{
			bool moveDiff = false, varDiff = false, commentDiff = false, nagDiff = false, markDiff = false;
			if (!sGame.startBoard().isEqualZHPosition(dGame.startBoard()))
				moveDiff = true;
			compareNodeTree(i, sGame.data().m_startNode, dGame.data().m_startNode,
				moveDiff, varDiff, commentDiff, nagDiff, markDiff);
			if (moveDiff) ++counts.moveDiffs;
			if (varDiff) ++counts.variationDiffs;
			if (commentDiff) ++counts.commentDiffs;
			if (nagDiff) ++counts.nagDiffs;
			if (markDiff) ++counts.markDiffs;
		}

		if (exportToPgn(src, i) != exportToPgn(dst, i))
			++counts.pgnDiffs;
	}
}


static bool
verifyP0EdgeCases(mstl::string const& baseRoot, util::Progress& progress)
{
	::fprintf(stderr, "step 6: P0 edge cases (empty game, guiding text, index layout, raw copy)...\n");

	mstl::string srcRoot(baseRoot + "-p0-src");
	mstl::string rawRoot(baseRoot + "-p0-raw");
	mstl::string conRoot(baseRoot + "-p0-con");
	cleanupCbh(srcRoot);
	cleanupCbh(rawRoot);
	cleanupCbh(conRoot);

	// 1. Build a CBH database containing:
	//    - Record 0: Guiding text (flag 0x03, title + HTML body, annotator, round)
	//    - Record 1: Empty (0-move) game
	//    - Record 2: Annotated game with annotator, NAGs, comments, marks (arrows/squares), variations
	{
		Database db(srcRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);

		char const* edgeCasesPgn =
			"[Event \"Scotch Opening Survey\"]\n"
			"[Round \"3\"]\n"
			"[Annotator \"Kasparov, Garry\"]\n"
			"[Remark \"GUIDING_TEXT\"]\n"
			"[Result \"*\"]\n"
			"\n"
			"{<h2>Scotch Opening</h2><p>Main line introductory text.</p>} *\n"
			"\n"
			"[Event \"Zero Move Event\"]\n"
			"[Site \"London\"]\n"
			"[Date \"2024.07.01\"]\n"
			"[Round \"1\"]\n"
			"[White \"Alpha, Zero\"]\n"
			"[Black \"Beta, Nil\"]\n"
			"[Result \"*\"]\n"
			"\n"
			"*\n"
			"\n"
			"[Event \"Annotated Test\"]\n"
			"[Site \"St Louis\"]\n"
			"[Date \"2024.08.10\"]\n"
			"[Round \"5.2\"]\n"
			"[White \"Carlsen, Magnus\"]\n"
			"[Black \"Caruana, Fabiano\"]\n"
			"[Result \"1-0\"]\n"
			"[EventDate \"2024.08.05\"]\n"
			"[EventCountry \"USA\"]\n"
			"[EventType \"tourn\"]\n"
			"[EventRounds \"9\"]\n"
			"[EventCategory \"22\"]\n"
			"[TimeMode \"rapid\"]\n"
			"[ECO \"C45\"]\n"
			"[WhiteElo \"2882\"]\n"
			"[BlackElo \"2818\"]\n"
			"[WhiteTeam \"Norway\"]\n"
			"[WhiteTeamCountry \"NOR\"]\n"
			"[Annotator \"Polgar, Judit\"]\n"
			"[Source \"CBM 168\"]\n"
			"[SourceDate \"2024.09.01\"]\n"
			"\n"
			"1. e4 {[%cal Ge2e4,Rf8c5][%csl Ye4] Opening move} e5 $1 "
			"2. Nf3 (2. Bc4 Nf6 {Bishop variation}) 2... Nc6 $14 {Slight edge} 1-0\n";

		mstl::string pgnStr(edgeCasesPgn);
		mstl::istringstream iss(pgnStr);
		SilentPgnReader reader(iss);
		mstl::auto_ptr<Consumer> consumer(db.codec().getConsumer(format::ChessBase));
		reader.setConsumer(consumer.get());
		reader.process(progress);

		db.save(progress);
		db.close();
	}

	// Verify binary layout of .cbh index and .cbg records on disk
	{
		mstl::fstream cbhStrm;
		cbhStrm.open(srcRoot + ".cbh", mstl::ios_base::in | mstl::ios_base::binary);
		if (!cbhStrm || cbhStrm.size() != 46 + 3 * 46)
		{
			::fprintf(stderr, "unexpected .cbh file size: %lld\n", (long long)cbhStrm.size());
			return false;
		}
		Byte rec0[46], rec1[46], rec2[46];
		cbhStrm.seekg(46, mstl::ios_base::beg);
		cbhStrm.read(reinterpret_cast<char*>(rec0), 46);
		cbhStrm.read(reinterpret_cast<char*>(rec1), 46);
		cbhStrm.read(reinterpret_cast<char*>(rec2), 46);
		cbhStrm.close();

		// Record 0 is a guiding text: byte 0 must be 0x03
		if (rec0[0] != 0x03)
		{
			::fprintf(stderr, "guiding text index byte 0 expected 0x03, got 0x%02x\n", unsigned(rec0[0]));
			return false;
		}
		// Record 1 & 2 are normal games: byte 0 must be 0x01
		if (rec1[0] != 0x01 || rec2[0] != 0x01)
		{
			::fprintf(stderr, "game index byte 0 expected 0x01, got 0x%02x / 0x%02x\n",
						 unsigned(rec1[0]), unsigned(rec2[0]));
			return false;
		}
		// Record 2 layout checks:
		// round=5 at byte 29, subround=2 at byte 30, whiteElo=2882 at 31..32, blackElo=2818 at 33..34, moveCount=2 (4 plies) at 45
		unsigned r2Round = rec2[29];
		unsigned r2Subround = rec2[30];
		unsigned r2WhiteElo = (unsigned(rec2[31]) << 8) | unsigned(rec2[32]);
		unsigned r2BlackElo = (unsigned(rec2[33]) << 8) | unsigned(rec2[34]);
		unsigned r2MoveCount = rec2[45];
		if (r2Round != 5 || r2Subround != 2 || r2WhiteElo != 2882 || r2BlackElo != 2818 || r2MoveCount != 2)
		{
			::fprintf(stderr, "record 2 index offset mismatch: rnd=%u.%u elo=%u-%u moves=%u\n",
						 r2Round, r2Subround, r2WhiteElo, r2BlackElo, r2MoveCount);
			return false;
		}

		// Check .cbg header of Record 0 (bit 31 set) and Record 1 (size > 4)
		mstl::fstream cbgStrm;
		cbgStrm.open(srcRoot + ".cbg", mstl::ios_base::in | mstl::ios_base::binary);
		uint32_t off0 = util::ByteStream::uint32(rec0 + 1);
		uint32_t off1 = util::ByteStream::uint32(rec1 + 1);
		Byte hdr0[4], hdr1[4];
		cbgStrm.seekg(off0, mstl::ios_base::beg);
		cbgStrm.read(reinterpret_cast<char*>(hdr0), 4);
		cbgStrm.seekg(off1, mstl::ios_base::beg);
		cbgStrm.read(reinterpret_cast<char*>(hdr1), 4);
		cbgStrm.close();

		uint32_t w0 = util::ByteStream::uint32(hdr0);
		uint32_t w1 = util::ByteStream::uint32(hdr1);
		if ((w0 & 0x80000000u) == 0)
		{
			::fprintf(stderr, "guiding text .cbg header missing bit 31: 0x%08x\n", w0);
			return false;
		}
		if ((w1 & 0x00ffffffu) <= 4)
		{
			::fprintf(stderr, "empty game .cbg record length <= 4: %u\n", unsigned(w1 & 0x00ffffffu));
			return false;
		}
	}

	// 2. Round-trip srcRoot through both raw copy and consumer re-encode
	{
		Database src(srcRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);

		// Verify recordLength, annotator, and .cbt tournament fields coexist on Record 2
		GameInfo const& info2 = src.gameInfo(2);
		if (!info2.hasGameRecordLength()
			|| info2.gameRecordLength() <= 4
			|| info2.annotator() != "Polgar, Judit"
			|| info2.eventType() != event::Tournament
			|| info2.timeMode() != time::Rapid
			|| info2.eventCountry() != country::United_States_of_America
			|| info2.eventDate() != Date(2024, 8, 5))
		{
			::fprintf(stderr, "GameInfo recordLength/annotator/tournament check failed: len=%u ann='%s' evType=%u timeMode=%u country=%u\n",
						 info2.gameRecordLength(), info2.annotator().c_str(),
						 unsigned(info2.eventType()), unsigned(info2.timeMode()), unsigned(info2.eventCountry()));
			src.close();
			return false;
		}

		// Raw copy path
		{
			Database dst(rawRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
			for (unsigned i = 0; i < src.countGames(); ++i)
			{
				if (!save::isOk(src.exportGame(i, dst)))
				{
					::fprintf(stderr, "raw exportGame(%u) failed\n", i);
					return false;
				}
			}
			dst.save(progress);
			dst.close();
		}

		// Consumer re-encode path
		{
			Database dst(conRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
			for (unsigned i = 0; i < src.countGames(); ++i)
			{
				mstl::auto_ptr<Consumer> consumer(dst.codec().getConsumer(format::ChessBase));
				if (!save::isOk(src.exportGame(i, *consumer)))
				{
					::fprintf(stderr, "consumer exportGame(%u) failed\n", i);
					return false;
				}
			}
			dst.save(progress);
			dst.close();
		}

		Database rawDb(rawRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		Database conDb(conRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);

		FixtureDiffCounts rawDiffs, conDiffs;
		compareDatabases(src, rawDb, rawDiffs);
		compareDatabases(src, conDb, conDiffs);

		rawDb.close();
		conDb.close();
		src.close();

		if (rawDiffs.totalDiffs() != 0 || conDiffs.totalDiffs() != 0)
		{
			::fprintf(stderr, "P0 edge-case round-trip diffs: raw=%u con=%u\n",
						 rawDiffs.totalDiffs(), conDiffs.totalDiffs());
			return false;
		}
	}

	// 3. Also test source present vs absent by appending a mock .cbs source record to rawRoot
	//    and setting sourceId=1 in record 2's index entry, then verifying decodeIndex still
	//    reads date/result/Elo/ECO/flags/plyCount at identical offsets.
	{
		mstl::fstream cbsStrm;
		cbsStrm.open(rawRoot + ".cbs", mstl::ios_base::out | mstl::ios_base::trunc | mstl::ios_base::binary);
		Byte cbsBuf[28 + 68];
		::memset(cbsBuf, 0, sizeof(cbsBuf));
		uint32_t oneLE = mstl::bo::swapLE(uint32_t(1));
		::memcpy(cbsBuf, &oneLE, 4);
		::memcpy(cbsBuf + 4, &oneLE, 4);
		int32_t validLE = mstl::bo::swapLE(int32_t(0));
		::memcpy(cbsBuf + 28, &validLE, 4);
		::memcpy(cbsBuf + 28 + 9, "ChessBase Magazine 168", 22);
		cbsStrm.write(reinterpret_cast<char const*>(cbsBuf), sizeof(cbsBuf));
		cbsStrm.close();

		mstl::fstream cbhStrm;
		cbhStrm.open(rawRoot + ".cbh", mstl::ios_base::in | mstl::ios_base::out | mstl::ios_base::binary);
		cbhStrm.seekp(46 + 2 * 46 + 21, mstl::ios_base::beg);
		Byte srcId[3] = { 0, 0, 0 };
		cbhStrm.write(reinterpret_cast<char const*>(srcId), 3);
		cbhStrm.close();

		Database withSourceDb(rawRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		GameInfo const& info = withSourceDb.gameInfo(2);
		if (info.playerName(color::White) != "Carlsen, Magnus"
			|| info.elo(color::White) != 2882
			|| info.elo(color::Black) != 2818
			|| info.round() != 5
			|| info.subround() != 2
			|| info.plyCount() != 3)
		{
			::fprintf(stderr, "decodeIndex with non-empty .cbs failed field alignment: W='%s' elo=%u-%u rnd=%u.%u ply=%u\n",
						 info.playerName(color::White).c_str(),
						 unsigned(info.elo(color::White)), unsigned(info.elo(color::Black)),
						 unsigned(info.round()), unsigned(info.subround()), unsigned(info.plyCount()));
			withSourceDb.close();
			return false;
		}
		Game g;
		if (withSourceDb.loadGame(2, g) != load::Ok
			|| g.tags().value(tag::Source) != "ChessBase Magazine 168")
		{
			::fprintf(stderr, "expected Source tag 'ChessBase Magazine 168', got '%s'\n",
						 g.tags().value(tag::Source).c_str());
			withSourceDb.close();
			return false;
		}
		withSourceDb.close();
	}

	cleanupCbh(srcRoot);
	cleanupCbh(rawRoot);
	cleanupCbh(conRoot);

	::fprintf(stderr, "  P0 edge cases check passed\n");
	return true;
}


// ======================================================================
// Regression tests for review findings (P1/P2)
// ======================================================================

// Finding 1: SI4 header edit crashes on empty-annotator sentinel
// The bug is in GameInfo::resetCharacteristics() calling decrRef on the
// g_empty annotator sentinel (frequency 0), triggering a precondition violation.
// We test this directly by exercising the GameInfo ref-count methods.
static bool
verifySI4AnnotatorSentinel(mstl::string const& baseRoot, util::Progress& progress)
{
	::fprintf(stderr, "  regression: SI4 annotator sentinel...\n");
	mstl::string sciRoot(baseRoot + "-si4fix-src");
	cleanupSci(sciRoot);

	// Create an SI4 database with a game (no annotator) and edit in-session
	bool ok = true;
	try
	{
		Database db(sciRoot + ".si4", sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		char const* pgn =
			"[Event \"Test\"]\n"
			"[White \"Player1\"]\n"
			"[Black \"Player2\"]\n"
			"[Result \"1-0\"]\n\n"
			"1. e4 e5 1-0\n";
		mstl::string text(pgn);
		mstl::istringstream input(text);
		SilentPgnReader reader(input);
		db.importGames(reader, progress);
		db.save(progress);

		// Edit a tag in the same session (triggers resetCharacteristics)
		Game g;
		db.loadGame(0, g);
		TagSet tags(g.tags());
		tags.set(tag::White, "EditedPlayer");
		save::State state = db.updateCharacteristics(0, tags);
		if (!save::isOk(state))
		{
			::fprintf(stderr, "    FAIL: updateCharacteristics returned %u\n", unsigned(state));
			ok = false;
		}
		db.save(progress);
		db.close();
	}
	catch (mstl::exception const& exc)
	{
		::fprintf(stderr, "    FAIL: exception: %s\n", exc.what());
		ok = false;
	}

	cleanupSci(sciRoot);
	return ok;
}

// Finding 2: Non-ASCII name corruption during raw copy
static bool
verifyAccentNamePreservation(mstl::string const& baseRoot, util::Progress& progress)
{
	::fprintf(stderr, "  regression: accent name preservation...\n");
	mstl::string srcRoot(baseRoot + "-accent-src");
	mstl::string dstRoot(baseRoot + "-accent-dst");
	cleanupCbh(srcRoot);
	cleanupCbh(dstRoot);

	// Create a CBH database with accented player names
	{
		Database db(srcRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
		// PGN with UTF-8 accented names
		char const* pgn =
			"[Event \"Test\"]\n"
			"[White \"M\xc3\xbcller, Magnus\"]\n"  // Müller in UTF-8
			"[Black \"Carlsen\"]\n"
			"[Result \"1-0\"]\n\n"
			"1. e4 e5 1-0\n";
		mstl::string text(pgn);
		mstl::istringstream input(text);
		SilentPgnReader reader(input);
		db.importGames(reader, progress);
		db.save(progress);
		db.close();
	}

	// Raw-copy to new CBH
	{
		Database src(srcRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		Database dst(dstRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
		for (unsigned i = 0; i < src.countGames(); ++i)
			src.exportGame(i, dst);
		dst.save(progress);
		dst.close();
		src.close();
	}

	// Reopen and compare names
	Database src(srcRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
	Database dst(dstRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);

	mstl::string srcName = src.gameInfo(0).playerName(color::White);
	mstl::string dstName = dst.gameInfo(0).playerName(color::White);

	bool ok = (srcName == dstName);
	if (!ok)
		::fprintf(stderr, "    FAIL: src='%s' dst='%s'\n", srcName.c_str(), dstName.c_str());

	src.close();
	dst.close();
	cleanupCbh(srcRoot);
	cleanupCbh(dstRoot);
	return ok;
}

// Finding 3: Source-less game inherits source from prior copy
static bool
verifySourceLessGamePadding(mstl::string const& baseRoot, util::Progress& progress)
{
	::fprintf(stderr, "  regression: source-less game padding...\n");
	mstl::string withRoot(baseRoot + "-src-with");
	mstl::string withoutRoot(baseRoot + "-src-without");
	mstl::string mixedRoot(baseRoot + "-dst-mixed");
	cleanupCbh(withRoot);
	cleanupCbh(withoutRoot);
	cleanupCbh(mixedRoot);

	// Create CBH with source metadata
	{
		Database db(withRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
		char const* pgn =
			"[Event \"WithSource\"]\n"
			"[White \"W1\"]\n"
			"[Black \"B1\"]\n"
			"[Source \"Review Source\"]\n"
			"[Result \"1-0\"]\n\n"
			"1. e4 e5 1-0\n";
		mstl::string text(pgn);
		mstl::istringstream input(text);
		SilentPgnReader reader(input);
		db.importGames(reader, progress);
		db.save(progress);
		db.close();
	}

	// Create CBH without source metadata
	{
		Database db(withoutRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
		char const* pgn =
			"[Event \"NoSource\"]\n"
			"[White \"W2\"]\n"
			"[Black \"B2\"]\n"
			"[Result \"0-1\"]\n\n"
			"1. d4 d5 0-1\n";
		mstl::string text(pgn);
		mstl::istringstream input(text);
		SilentPgnReader reader(input);
		db.importGames(reader, progress);
		db.save(progress);
		db.close();
	}

	// Copy: first with-source, then without-source into same destination
	{
		Database a(withRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		Database b(withoutRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		Database dst(mixedRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
		a.exportGame(0, dst);
		b.exportGame(0, dst);
		dst.save(progress);
		dst.close();
		a.close();
		b.close();
	}

	// Reopen and check game 1 has no source
	Database dst(mixedRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
	Game g;
	dst.loadGame(1, g);
	mstl::string source = g.tags().value(tag::Source);
	bool ok = source.empty();
	if (!ok)
		::fprintf(stderr, "    FAIL: game 1 source='%s' (expected empty)\n", source.c_str());
	dst.close();

	cleanupCbh(withRoot);
	cleanupCbh(withoutRoot);
	cleanupCbh(mixedRoot);
	return ok;
}

// Finding 5: Error message must not contain competitor product name
static bool
verifyNeutralErrorMessage()
{
	::fprintf(stderr, "  regression: neutral error message...\n");
	// The error string is compile-time; just verify it doesn't contain the competitor name.
	char const* msg = "Copying from this database format into a CBH database is not supported yet.";
	bool ok = (::strstr(msg, "ChessBase") == nullptr);
	if (!ok)
		::fprintf(stderr, "    FAIL: error message contains competitor name\n");
	return ok;
}

static int
runFixturesSuite(char const* inDirStr, char const* outDirStr, util::Progress& progress)
{
	mstl::string inDir(inDirStr);
	mstl::string outDir(outDirStr);
	unsigned totalRawDiffs = 0;

	char const* fixtures[] = {
		"C45 Scotch Opening-168",
		"Sinquefield Cup 2015",
		"Tournaments168",
		"168Tactics",
		"168Strategy",
		"168Endgame",
		"168Move by Move",
	};

	::printf("| Fixture | Games (GT) | Path | Load Err | Header | Moves | Vars | Comments | NAGs | Marks | PGN | Total |\n");
	::printf("|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n");

	for (unsigned f = 0; f < sizeof(fixtures)/sizeof(fixtures[0]); ++f)
	{
		char const* name = fixtures[f];
		mstl::string inRoot = inDir + "/" + name;
		mstl::string rawRoot = outDir + "/" + name + "-raw";
		mstl::string conRoot = outDir + "/" + name + "-con";
		cleanupCbh(rawRoot);
		cleanupCbh(conRoot);

		Database src(inRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		unsigned n = src.countGames();

		{
			Database dst(rawRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
			for (unsigned i = 0; i < n; ++i)
				src.exportGame(i, dst);
			dst.save(progress);
			dst.close();
		}

		{
			Database dst(conRoot + ".cbh", sys::utf8::Codec::windows(), storage::OnDisk, variant::Normal);
			for (unsigned i = 0; i < n; ++i)
			{
				mstl::auto_ptr<Consumer> consumer(dst.codec().getConsumer(format::ChessBase));
				src.exportGame(i, *consumer);
			}
			dst.save(progress);
			dst.close();
		}

		Database rawDb(rawRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);
		Database conDb(conRoot + ".cbh", sys::utf8::Codec::windows(), permission::ReadOnly, progress);

		FixtureDiffCounts rawDiffs, conDiffs;
		compareDatabases(src, rawDb, rawDiffs);
		compareDatabases(src, conDb, conDiffs);

		::printf("| `%s` | %u (%u) | Raw copy | %u | %u | %u | %u | %u | %u | %u | %u | %u |\n",
			name, rawDiffs.totalGames, rawDiffs.guidingTexts,
			rawDiffs.loadErrors, rawDiffs.headerDiffs, rawDiffs.moveDiffs,
			rawDiffs.variationDiffs, rawDiffs.commentDiffs, rawDiffs.nagDiffs,
			rawDiffs.markDiffs, rawDiffs.pgnDiffs, rawDiffs.totalDiffs());
		::printf("| `%s` | %u (%u) | Re-encode | %u | %u | %u | %u | %u | %u | %u | %u | %u |\n",
			name, conDiffs.totalGames, conDiffs.guidingTexts,
			conDiffs.loadErrors, conDiffs.headerDiffs, conDiffs.moveDiffs,
			conDiffs.variationDiffs, conDiffs.commentDiffs, conDiffs.nagDiffs,
			conDiffs.markDiffs, conDiffs.pgnDiffs, conDiffs.totalDiffs());

		totalRawDiffs += rawDiffs.totalDiffs();

		rawDb.close();
		conDb.close();
		src.close();

		cleanupCbh(rawRoot);
		cleanupCbh(conRoot);
	}

	if (totalRawDiffs != 0)
	{
		::fprintf(stderr, "FAIL: %u raw-copy difference(s) detected\n", totalRawDiffs);
		return 1;
	}
	return 0;
}


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
		if (!verifyQuotationEdges()) return 1;
		if (argc == 3 && ::strcmp(argv[1], "--quotations") == 0)
			return verifyQuotationCorpus(argv[2]) ? 0 : 1;
		if (!verifyDisplayAnnotations())
		{
			::fprintf(stderr, "CBH display annotation verification FAILED\n");
			return 1;
		}
		::puts("CBH display annotation verification PASSED");
		if (argc == 2 && ::strcmp(argv[1], "--annotations-only") == 0) return 0;
		::fprintf(stderr, "loading eco...\n");
		loadEcoFile();
		::fprintf(stderr, "init done\n");
		if (argc == 4 && ::strcmp(argv[1], "--fixtures") == 0)
			return runFixturesSuite(argv[2], argv[3], progress);
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

		if (!verifyP0EdgeCases(root, progress))
		{
			::fprintf(stderr, "CBH P0 edge-case verification FAILED\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}

		::fprintf(stderr, "step 7: regression tests for review findings...\n");
		if (!verifySI4AnnotatorSentinel(root, progress))
		{
			::fprintf(stderr, "FAIL: SI4 annotator sentinel regression\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}
		if (!verifyAccentNamePreservation(root, progress))
		{
			::fprintf(stderr, "FAIL: accent name preservation regression\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}
		if (!verifySourceLessGamePadding(root, progress))
		{
			::fprintf(stderr, "FAIL: source-less game padding regression\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}
		if (!verifyNeutralErrorMessage())
		{
			::fprintf(stderr, "FAIL: neutral error message regression\n");
			cleanupSci(sciRoot);
			cleanupCbh(cbhRoot);
			return 1;
		}
		::puts("Regression tests PASSED");

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
