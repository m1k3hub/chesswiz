// Read move-lists from stdin, one game per line (space-separated).
// Moves are UCI strings (e2e4, e7e8q); Chess960 castling is given as
// king-from + rook-square-to (X-FEN/UCI convention).  Moves are matched
// against the legal move list, so castling and underpromotions work.
//
// Usage: probe_encode_many < probe_input.txt
#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_common.h"
#include "db/db_move.h"
#include "db/db_move_list.h"
#include "db/db_exception.h"
#include "db/cbh/cbh_encoder.h"
#include "util/u_byte_stream.h"
#include "mstl/m_string.h"
#include <tcl.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <iostream>
#include <sstream>
using namespace db;
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

// Each input line:  <FEN>\t<SAN> <SAN> ...   (tab-separated; FEN then moves)
// Emits:  POS=<28-byte position hex> | <scidb move bytes hex>\n

int main()
{
	std::string line;
	while (std::getline(std::cin, line))
	{
		// split on first tab: FEN | moves
		std::string::size_type tab = line.find('\t');
		if (tab == std::string::npos) { ::printf("\n"); continue; }
		std::string fen = line.substr(0, tab);
		std::string rest = line.substr(tab + 1);

		Board start;
		char const* err = start.setup(fen.c_str(), variant::Normal);
		if (!err) { ::fprintf(stderr,"setup failed for '%s'\n", fen.c_str()); ::printf("\n"); continue; }
		Byte buffer[4096];
		util::ByteStream encoded(buffer, sizeof(buffer));
		encoded.resetp();
		cbh::Encoder encoder(encoded);
		encoder.startEncoding(start, false);
		std::istringstream iss(rest);
		std::string uci;
		unsigned count = 0;
		while (iss >> uci)
		{
			if (uci.size() < 4)
				break;
			int ff = uci[0] - 'a', fr = uci[1] - '1';
			int tf = uci[2] - 'a', tr = uci[3] - '1';
			int promo = uci.size() > 4 ? uci[4] : 0;
			unsigned from = (fr * 8) + ff;   // sq::make(rank, fyle): a1=0
			unsigned to = (tr * 8) + tf;

			MoveList legal;
			start.generateMoves(variant::Normal, legal);
			Move m;
			for (MoveList::const_iterator it = legal.begin(); it != legal.end(); ++it)
			{
				if (it->from() != from || it->to() != to)
					continue;
				if (promo)
				{
					// piece::Type: Queen=2, Rook=3, Bishop=4, Knight=5
					static char const promoChar[] = { 0, 0, 'q', 'r', 'b', 'n', 0 };
					char p = it->promoted() <= 6 ? promoChar[it->promoted()] : 0;
					if (p != promo)
						continue;
				}
				m = *it;
				break;
			}
			if (m.isEmpty()) { ::fprintf(stderr, "no legal move for %s\n", uci.c_str()); break; }
			encoder.encodeMove(m, count);
			start.doMove(m, variant::Normal);
		}
		// emit the move bytes (skip 4-byte header + 28-byte std position; for DAda
		// the encoder writes a 28-byte custom position here since isStandardPosition=false
		// uses encodePosition which emits 28 bytes for this position)
		unsigned total = encoded.tellp();
		// Emit the 28-byte position block (offset 4..31) then move bytes (32..).
		::printf("POS=");
		for (unsigned i = 4; i < 4 + 28 && i < total; ++i)
			::printf("%02x", buffer[i]);
		::printf(" | ");
		for (unsigned i = 4 + 28; i < total; ++i)
			::printf("%02x ", buffer[i]);
		::printf("\n");
	}
	return 0;
}