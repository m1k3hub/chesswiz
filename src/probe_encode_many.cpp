// Read SAN move-lists from stdin, one game per line (space-separated),
// all from the fixed DAda Chess960 start FEN. For each game, encode plies
// until a parse failure (castling) and print the scidb move bytes (count=idx)
// as hex on one line. This harvests (cp,lc)->cn samples for the count cipher.
//
// Usage: probe_encode_many < start_fen  (FEN hardcoded to DAda)
#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_common.h"
#include "db/db_move.h"
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
		std::string san;
		unsigned count = 0;
		bool failed = false;
		while (iss >> san)
		{
			Move m = start.parseMove(san.c_str(), variant::Normal);
			if (m.isEmpty()) { failed = true; break; }
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