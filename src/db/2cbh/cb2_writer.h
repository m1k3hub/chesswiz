// ======================================================================
// cb2_writer.h -- create and append to 2CBH (ChessBase 17+) databases.
//
// The writer mirrors the reader in cb2_codec.cpp / cb2_index.h exactly, so
// every database it produces is read back by cb2::Codec (and by the 2cbh2pgn
// converter) as the same games and tags:
//
//   .2cbh  192-byte header record + one 192-byte record per game
//   .2cbg  12-byte file header + per-game records (26-byte header + Move16
//          token stream)
//   .2cba  12-byte file header + one "no annotations" record per game
//   .2lid  namebase: 0xb8-byte structural header, then one 0x108a-byte slot
//          per name.  Each slot carries the player record at +0x000, the
//          event/site/EventDate record at +0x400, the [SourceTitle]/[Source]
//          pair at +0x860 and the annotator at +0x93c.
//   .ini   the [Descr2CBG] description CBase26 needs to accept the directory
//          as a database (without it, it offers to create a new one instead).
//
// Everything is checked field by field by tests/test_2cbh.cpp and accepted by
// ChessBase 26 itself (open, list, close, re-open) -- see
// docs/formats/2CBH_FORMAT_DESIGN.md section 18.
//
// The file layouts are documented in docs/formats/2CBH_FORMAT_DESIGN.md; the
// Ghidra evidence for the record and setup writers is cited there (record
// writer 0x1401af5b0, game-record payload writer 0x1401e8310, setup code
// builder 0x14021a1e0).
// ======================================================================

#ifndef _cb2_writer_included
#define _cb2_writer_included

#include "db_date.h"

#include "m_string.h"
#include "m_vector.h"

#include <stdint.h>

namespace db {

class Board;
class Move;

namespace cb2 {

/// One game to write.  @a moves is an already encoded Move16 token stream
/// starting with Move16_GameStart (0xfffc) and ending with Move16_Terminator
/// (0xffff); variations and markers are kept verbatim, so a stream obtained
/// from an existing .2cbg record round-trips byte for byte.
struct WriteGame
{
						WriteGame();

	mstl::string	white;
	mstl::string	black;
	mstl::string	event;
	mstl::string	site;
	mstl::string	round;			///< PGN form, e.g. "7" or "7.5"
	mstl::string	result;			///< "1-0", "0-1", "1/2-1/2", "*"
	mstl::string	eco;				///< "B12", "B12a" (sub-letter ignored) or "B12/34"
	unsigned			whiteElo;
	unsigned			blackElo;
	Date				date;

	/// The game's source pair, stored in the .2lid source section (+0x860 of
	/// a slot) and referenced from index +0x38: @a sourceTitle is the first
	/// string ([SourceTitle], e.g. "playchess.com"), @a source the second
	/// ([Source], e.g. "ChessBase").  Empty strings leave the reference at
	/// "none".
	mstl::string	sourceTitle;
	mstl::string	source;
	/// White/Black team.  ChessBase keeps them in a namebase of its own
	/// (.2lid +0xd3c), referenced from index +0x40/+0x48; CBase26 fills them
	/// from the [WhiteTeam]/[BlackTeam] PGN tags.  Empty = no team.
	mstl::string	whiteTeam;
	mstl::string	blackTeam;
	/// The annotator.  ChessBase models the annotator as a person, so it is
	/// stored as a *player* record of the .2lid and referenced from index
	/// +0x30 (see cb2::Codec::getAnnotator).  Empty = no annotator.
	mstl::string	annotator;
	/// Medals / game flags word (index +0x82), see cb2_flags.h.
	unsigned			medals;

	/// -1 = standard start position.  0..959 = compact Chess960 position.
	/// 1000 = arbitrary setup, described by @a fen.  The six-byte start
	/// block CBase26 writes is emitted (see cb2_setup.h): side to move and
	/// castling rights are taken from the FEN.
	/// -2 = @a moves is the complete .2cbg payload, including any setup prefix
	/// (used to copy a stored record verbatim, e.g. when appending).
	int			setup;
	mstl::string	fen;

	/// 0 = derive from @a setup, otherwise the .2cbg record type to store.
	unsigned		recordType;

	mstl::vector<uint16_t>	moves;
};

/// Write all @a games as a new database @a rootname (".2cbh"/".2cbg"/".2cba"
/// /".2lid"/".ini" are appended).  Any existing files are replaced.  Returns
/// false and sets @a error on an I/O or encoding failure.
bool writeDatabase(	mstl::string const& rootname,
							mstl::vector<WriteGame> const& games,
							mstl::string* error = 0);

/// Append @a games to an existing database by reading its index/namebase and
/// rewriting the three files.  A missing database is created.  The existing
/// games' Move16 payloads are copied verbatim.
bool appendToDatabase(	mstl::string const& rootname,
								mstl::vector<WriteGame> const& games,
								mstl::string* error = 0);

/// Encode a legal move sequence starting at @a board into a Move16 stream
/// (leading 0xfffc and trailing 0xffff included).  Used by callers that hold
/// a move list rather than a stored token stream.
bool encodeMoveStream(	Board const& board,
								mstl::vector<Move> const& moves,
								mstl::vector<uint16_t>& stream);

} // namespace cb2
} // namespace db

#endif // _cb2_writer_included
