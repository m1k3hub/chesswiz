// ======================================================================
// probe_chess_facts -- dump the chess anatomy of positions and moves.
//
//   probe_chess_facts [--text] "FEN" ["FEN" ...]
//   probe_chess_facts --move "Nf3" "FEN"          # one move's facts
//   probe_chess_facts --line "e4 e5 Nf3 Nc6" "FEN" # one object per move
//   echo "FEN" | probe_chess_facts [--text]
//
// Output is one JSON object per position/move (one line each), or a
// compact human-readable report with --text.  This is the grounding
// payload that a language layer is allowed to describe -- nothing more.
// ======================================================================

#include "db/db_board.h"
#include "db/db_chess_facts.h"
#include "db/db_common.h"
#include "db/db_move.h"

#include "mstl/m_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

using namespace db;

static void
put(mstl::string const& out)
{
	::fputs(out.c_str(), stdout);
	::fputc('\n', stdout);
}

static bool
setup(Board& board, char const* fen)
{
	if (board.setup(fen, variant::Normal) == 0)
	{
		::fprintf(stderr, "invalid FEN: %s\n", fen);
		return false;
	}

	return true;
}

static bool
emitPosition(char const* fen, bool text)
{
	Board board;

	if (!setup(board, fen))
		return false;

	mstl::string out;

	if (text)
		ChessFacts::toText(board, variant::Normal, out);
	else
		ChessFacts::toJson(board, variant::Normal, out);

	put(out);
	return true;
}

static bool
parse(Board const& board, char const* token, Move& move)
{
	move = board.parseMove(token, variant::Normal);

	if (move.isEmpty() || !move.isValid())
	{
		::fprintf(stderr, "illegal or unknown move: %s\n", token);
		return false;
	}

	return true;
}

static bool
emitMove(char const* fen, char const* token)
{
	Board	board;
	Move	move;

	if (!setup(board, fen) || !parse(board, token, move))
		return false;

	mstl::string out;
	ChessFacts::toMoveJson(board, move, variant::Normal, out);
	put(out);
	return true;
}

static bool
emitLine(char const* fen, char const* moves)
{
	Board board;

	if (!setup(board, fen))
		return false;

	bool ok = true;

	// crude whitespace tokenizer over a mutable copy (heap: any length)
	char* buffer = ::strdup(moves);

	for (char* tok = ::strtok(buffer, " \t"); tok; tok = ::strtok(nullptr, " \t"))
	{
		Move move;

		if (!parse(board, tok, move))
		{
			ok = false;
			break;
		}

		mstl::string out;
		ChessFacts::toMoveJson(board, move, variant::Normal, out);
		put(out);

		board.doMove(move, variant::Normal);
	}

	::free(buffer);
	return ok;
}

int
main(int argc, char* argv[])
{
	Board::initialize();

	bool			text = false;
	char const*	move = 0;
	char const*	line = 0;
	int			i = 1;

	for ( ; i < argc; ++i)
	{
		if (::strcmp(argv[i], "--text") == 0)				text = true;
		else if (::strcmp(argv[i], "--move") == 0 && i + 1 < argc)	move = argv[++i];
		else if (::strcmp(argv[i], "--line") == 0 && i + 1 < argc)	line = argv[++i];
		else break;
	}

	if (move || line)
	{
		if (i >= argc)
		{
			::fprintf(stderr, "usage: %s [--text] %s <move> \"FEN\"\n",
					   argv[0], move ? "--move" : "--line");
			return 2;
		}

		bool ok = move ? emitMove(argv[i], move) : emitLine(argv[i], line);
		return ok ? 0 : 1;
	}

	if (i < argc)
	{
		int failures = 0;

		for ( ; i < argc; ++i)
			if (!emitPosition(argv[i], text))
				failures++;

		return failures ? 1 : 0;
	}

	// read FENs from stdin, one per line
	char buffer[1024];
	int  failures = 0;

	while (::fgets(buffer, sizeof(buffer), stdin))
	{
		size_t n = ::strlen(buffer);

		while (n > 0 && (buffer[n - 1] == '\n' || buffer[n - 1] == '\r'))
			buffer[--n] = 0;

		if (n == 0 || buffer[0] == '#')
			continue;

		if (!emitPosition(buffer, text))
			failures++;
	}

	return failures ? 1 : 0;
}

// vi:set ts=3 sw=3:
