// Encode a sequence of Chess960 moves (SAN) with scidb's CBH Encoder and
// dump the raw move bytes, to compare against what real ChessBase .cbv
// files store.
//
// Usage: probe_encode960 "<fen>" "<san-move>" [<san-move> ...]
//   e.g. probe_encode960 "rkqrbbnn/.../RKQRBBNN w DAda - 0 1" d4 d5 f3 Nf6 ...
// Moves are SAN, parsed by Board::parseMove and applied in sequence.

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

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

int main(int argc, char** argv)
{
	if (argc < 3)
	{
		::fprintf(stderr, "usage: %s <fen> <san-move> [<san-move> ...]\n", argv[0]);
		return 1;
	}

	Board start;
	char const* err = start.setup(argv[1], variant::Normal);
	if (!err)
	{
		::fprintf(stderr, "failed to set up board from FEN '%s'\n", argv[1]);
		return 1;
	}

	Byte buffer[1024];
	util::ByteStream encoded(buffer, sizeof(buffer));
	encoded.resetp();

	cbh::Encoder encoder(encoded);
	encoder.startEncoding(start, false);

	unsigned count = 0;
	for (int i = 2; i < argc; ++i)
	{
		Move m = start.parseMove(argv[i], variant::Normal);
		if (m.isEmpty())
		{
			::fprintf(stderr, "failed to parse move '%s' (count=%u)\n", argv[i], count);
			return 1;
		}
		encoder.encodeMove(m, count);
		start.doMove(m, variant::Normal);
	}

	unsigned totalSize = encoded.tellp();

	::printf("fen=%s plies=%u totalSize=%u\n", argv[1], count, totalSize);
	::printf("move bytes (offset %u+):", 4 + 28);
	for (unsigned i = 4 + 28; i < totalSize; ++i)
		::printf(" %02x", buffer[i]);
	::printf("\n");

	return 0;
}