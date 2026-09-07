// Reassembly-walk ground truth for one classic .cbg game record.
// Mirrors GameDecoder::decodeMoves' push/pop position handling (the
// reassembly itself only affects tree structure, not board states).
#include "cbh/cbh_decoder.h"
#include "db_board.h"
#include "db_move.h"
#include "db_exception.h"
#include "sys/sys_utf8_codec.h"
#include "util/u_byte_stream.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

using namespace db;

namespace {

struct TraceDecoder : public cbh::Decoder
{
	TraceDecoder(util::ByteStream& gStrm, bool isChess960)
		:cbh::Decoder(gStrm, isChess960)
	{
	}

	void begin() { startDecoding(); }
	unsigned next(Move& move, unsigned& count)
	{
		return decodeMove(move, count, false);
	}
	Board const& board() const { return m_position.board(); }

	enum { Token_Move = cbh::Decoder::Token_Move,
	       Token_Push = cbh::Decoder::Token_Push,
	       Token_Pop = cbh::Decoder::Token_Pop,
	       Token_Skip = cbh::Decoder::Token_Skip };
};

int g_depth = 0;

void walk(TraceDecoder& dec, unsigned& count)
{
	++g_depth;
	for (;;)
	{
		Move move;
		unsigned tag = dec.next(move, count);
		switch (tag)
		{
			case TraceDecoder::Token_Move:
				if (!move)
				{
					::printf("FAIL null move at count %u depth %d\n", count, g_depth);
					::exit(2);
				}
				{
					mstl::string fen;
					dec.board().toFen(fen, variant::Normal);
					::printf("mv count=%u d=%d %u-%u %s\n",
					         count, g_depth, unsigned(move.from()), unsigned(move.to()),
					         fen.c_str());
				}
				break;
			case TraceDecoder::Token_Push:
				walk(dec, count);
				break;
			case TraceDecoder::Token_Pop:
				--g_depth;
				return;
			default:
				break;
		}
	}
}

std::vector<unsigned char> loadFile(char const* path)
{
	FILE* fp = ::fopen(path, "rb");
	if (!fp) { ::perror(path); ::exit(1); }
	::fseek(fp, 0, SEEK_END);
	long sz = ::ftell(fp);
	::fseek(fp, 0, SEEK_SET);
	std::vector<unsigned char> data(sz);
	if (::fread(data.data(), 1, sz, fp) != size_t(sz)) data.clear();
	::fclose(fp);
	return data;
}

} // namespace

int main(int argc, char** argv)
{
	if (argc < 4) { ::fprintf(stderr, "usage: cbh1trace <cbg> <offset> <size>\n"); return 1; }
	::setvbuf(stdout, NULL, _IONBF, 0);
	Board::initialize();

	auto data = loadFile(argv[1]);
	unsigned offset = ::strtoul(argv[2], 0, 10);
	unsigned size = ::strtoul(argv[3], 0, 10);

	util::ByteStream gStrm(data.data() + offset, size);
	TraceDecoder dec(gStrm, false);
	try
	{
		dec.begin();
		unsigned count = 0;
		walk(dec, count);
		::printf("DONE\n");
	}
	catch (db::Exception const& e)
	{
		::printf("EXCEPTION at count ? : %s\n", e.what());
		return 1;
	}
}
