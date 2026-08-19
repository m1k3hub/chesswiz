// ======================================================================
// test_sci_result.cpp
//
// Regression test for F-003: a .sci database whose index records carry
// out-of-range result codes (5/6/7) must NOT crash Statistic::count.
//
//   result::ID has 5 values (Unknown..Lost = 0..4) and Statistic::Content::result
//   is unsigned result[5], but GameInfo::m_result is a 3-bit field (0..7).
//   The .sci format reserves 5 for guiding-text; 6/7 are invalid. Before the
//   fix, 6/7 reached Statistic::count and asserted:
//       info.result() < U_NUMBER_OF(content.result)
//
// Approach (platform-independent — does not hardcode the result bit offset,
// which depends on the compiler's bitfield layout):
//   1. build a tiny .sci from a PGN with 3 games of distinct, known results
//      (1-0 -> White=1, 1/2-1/2 -> Draw=3, 0-0 -> Lost=4),
//   2. read the 3 index records and locate the 3-bit field whose values across
//      the records are exactly (1, 3, 4) — that is the result field,
//   3. binary-patch that field in records 0/1/2 to 5/6/7,
//   4. reopen the .sci, iterate the games, run Statistic::add (the original
//      crash site), and verify:
//        - no crash / no assertion,
//        - result 5 -> guiding-text + result::Unknown,
//        - result 6/7 -> result::Unknown (clamped by the fix).
//
// Index records start at HeaderSize (128) and are 56 bytes each.
//
// Usage: test_sci_result <tmpdir> [<eco.bin path>]
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
#include "db/db_game.h"
#include "db/db_game_info.h"
#include "db/db_home_pawns.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"
#include "db/db_statistic.h"
#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"
#include "sys/sys_utf8_codec.h"
#include "util/u_progress.h"
#include "mstl/m_string.h"
#include "mstl/m_ifstream.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <vector>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

unsigned const HeaderSize		= 128;
unsigned const IndexRecordSize	= 56;	// sizeof(IndexEntry)

// 3 games with distinct results: White(1), Draw(3), Lost(4).
char const* PGN =
	"[Event \"t\"]\n[Site \"t\"]\n[Date \"2024.01.01\"]\n"
	"[White \"A\"]\n[Black \"B\"]\n[WhiteElo \"2400\"]\n[BlackElo \"2300\"]\n[Result \"1-0\"]\n\n1.e4 e5 1-0\n\n"
	"[Event \"t\"]\n[Site \"t\"]\n[Date \"2024.02.02\"]\n"
	"[White \"C\"]\n[Black \"D\"]\n[WhiteElo \"2500\"]\n[BlackElo \"2400\"]\n[Result \"1/2-1/2\"]\n\n1.d4 d5 1/2-1/2\n\n"
	"[Event \"t\"]\n[Site \"t\"]\n[Date \"2024.03.03\"]\n"
	"[White \"E\"]\n[Black \"F\"]\n[WhiteElo \"2600\"]\n[BlackElo \"2500\"]\n[Result \"0-0\"]\n\n1.Nf3 Nf6 0-0\n\n";

void loadEcoFile(mstl::string const& path)
{
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);
	if (!stream) { fprintf(stderr, "warning: cannot open ECO file '%s' (continuing)\n", path.c_str()); return; }
	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
}

class MyPgnReader : public PgnReader
{
public:
	MyPgnReader(mstl::istream& stream, variant::Type v, mstl::string const& encoding)
		:PgnReader(stream, v, encoding, PgnReader::File, PgnReader::Normalize, PgnReader::UseResultTag) {}
	void warning(Warning, unsigned, unsigned, unsigned, variant::Type, mstl::string const&, mstl::string const&) override {}
	void error(Error, unsigned, unsigned, unsigned, variant::Type, mstl::string const&, mstl::string const&, mstl::string const&) override {}
	void error(save::State, unsigned, unsigned, variant::Type) override {}
};

// Read the index records from a .sci file.
std::vector<std::vector<unsigned char> > readRecords(mstl::string const& sciPath, unsigned n)
{
	FILE* f = fopen(sciPath.c_str(), "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", sciPath.c_str()); exit(2); }
	std::vector<std::vector<unsigned char> > recs;
	for (unsigned i = 0; i < n; ++i)
	{
		std::vector<unsigned char> r(IndexRecordSize);
		if (fseek(f, HeaderSize + i*IndexRecordSize, SEEK_SET) != 0 || fread(r.data(), 1, IndexRecordSize, f) != IndexRecordSize)
		{ fprintf(stderr, "cannot read record %u\n", i); exit(2); }
		recs.push_back(r);
	}
	fclose(f);
	return recs;
}

// 3-bit value at bit offset `bit` (LSB-first, across byte boundaries).
unsigned field3(std::vector<unsigned char> const& r, unsigned bit)
{
	unsigned v = 0;
	for (unsigned k = 0; k < 3; ++k)
		v |= ((r[(bit + k) / 8] >> ((bit + k) % 8)) & 1u) << k;
	return v;
}

// Locate the bit offset of the 3-bit result field: the field whose values across
// the records equal the expected results (1, 3, 4). Returns UINT_MAX if not found.
unsigned findResultBit(std::vector<std::vector<unsigned char> > const& recs)
{
	unsigned const expected[3] = { 1, 3, 4 };
	std::vector<unsigned> matches;
	// The result field lives in the last uint32 of the record (u32[13], bytes 52..55)
	// in both the bitfield and the BF_GET code paths, so restrict the scan there.
	for (unsigned bit = (IndexRecordSize - 4)*8; bit + 3 <= IndexRecordSize*8; ++bit)
	{
		bool ok = true;
		for (unsigned i = 0; i < 3 && ok; ++i)
			if (field3(recs[i], bit) != expected[i]) ok = false;
		if (ok) matches.push_back(bit);
	}
	if (matches.empty()) return ~0u;
	if (matches.size() > 1)
		fprintf(stderr, "warning: %zu candidate result fields; using the first\n", matches.size());
	return matches[0];
}

// Patch the 3-bit field at `bit` in record `idx` to `value`.
void patchField(mstl::string const& sciPath, unsigned idx, unsigned bit, unsigned value)
{
	FILE* f = fopen(sciPath.c_str(), "r+b");
	if (!f) { fprintf(stderr, "cannot open %s for patching\n", sciPath.c_str()); exit(2); }
	for (unsigned k = 0; k < 3; ++k)
	{
		unsigned b = bit + k;
		long off = HeaderSize + idx*IndexRecordSize + b/8;
		fseek(f, off, SEEK_SET);
		int c = fgetc(f);
		if (c < 0) { fprintf(stderr, "read failed\n"); exit(2); }
		unsigned char byte = (unsigned char)c;
		byte = (byte & ~(1u << (b % 8))) | (((value >> k) & 1u) << (b % 8));
		fseek(f, off, SEEK_SET);
		fputc(byte, f);
	}
	fclose(f);
}

} // namespace

struct TclInterpreter
{
	TclInterpreter()  { tcl::bits::interp = Tcl_CreateInterp(); Tcl_Init(tcl::bits::interp); }
	~TclInterpreter() { Tcl_DeleteInterp(tcl::bits::interp); tcl::bits::interp = nullptr; }
};

void initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
	db::si3::Encoder::initialize();
}

int main(int argc, char** argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s <tmpdir> [<eco.bin>]\n", argv[0]); return 1; }

	mstl::string tmp(argv[1]);
	::mkdir(tmp.c_str(), 0777);
	mstl::string pgnPath(tmp + "/reg.pgn");
	mstl::string sciPath(tmp + "/reg.sci");

	{ FILE* f = fopen(pgnPath.c_str(), "wb"); if (!f) { fprintf(stderr, "cannot write pgn\n"); return 2; }
	  fwrite(PGN, 1, strlen(PGN), f); fclose(f); }

	util::Progress& progress = util::Progress::null();
	TclInterpreter tcl;
	initializeStatics();
	if (argc >= 3) loadEcoFile(argv[2]);
	else loadEcoFile(SHAREDIR "/data/eco.bin");

	// 1. build the .sci
	{
		Database db(sciPath, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		mstl::ifstream pgn(pgnPath, mstl::ios_base::in | mstl::ios_base::binary);
		if (!pgn) { fprintf(stderr, "cannot open pgn\n"); return 2; }
		MyPgnReader reader(pgn, variant::Normal, sys::utf8::Codec::automatic());
		db.importGames(reader, progress);
		db.save(progress);
		db.close();
	}

	unsigned n = 0;
	{ Database db(sciPath, sys::utf8::Codec::utf8(), permission::ReadOnly, progress); n = db.countGames(); db.close(); }
	printf("created .sci with %u game(s)\n", n);
	if (n < 3) { fprintf(stderr, "FAIL: expected at least 3 games, got %u\n", n); return 1; }

	// 2. locate the result field by the known (1,3,4) pattern
	std::vector<std::vector<unsigned char> > recs = readRecords(sciPath, 3);
	unsigned resultBit = findResultBit(recs);
	if (resultBit == ~0u) { fprintf(stderr, "FAIL: could not locate result field (pattern 1,3,4 not found)\n"); return 1; }
	printf("result field at bit offset %u (byte %u, bit %u)\n", resultBit, resultBit/8, resultBit%8);

	// 3. patch results to 5 (guiding-text), 6 (invalid), 7 (invalid)
	patchField(sciPath, 0, resultBit, 5);
	patchField(sciPath, 1, resultBit, 6);
	patchField(sciPath, 2, resultBit, 7);

	// 4. reopen, iterate, run Statistic (original crash site), verify sanitization
	int fail = 0;
	{
		Database db(sciPath, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
		Statistic stat;
		for (unsigned i = 0; i < db.countGames(); ++i)
		{
			GameInfo const& info = db.gameInfo(i);
			stat.add(info); // exercises Statistic::count -> original crash site
			result::ID r = info.result();
			bool gt = info.isGuidingText();
			printf("game %u: result=%d isGuidingText=%d\n", i, int(r), int(gt));
			if (i == 0 && (r != result::Unknown || !gt))
			{ fprintf(stderr, "FAIL game 0 (result=5): expected guiding-text + Unknown\n"); fail = 1; }
			else if (i == 1 && r != result::Unknown)
			{ fprintf(stderr, "FAIL game 1 (result=6): expected Unknown (clamped)\n"); fail = 1; }
			else if (i == 2 && r != result::Unknown)
			{ fprintf(stderr, "FAIL game 2 (result=7): expected Unknown (clamped)\n"); fail = 1; }
		}
		db.close();
	}

	if (fail) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS (no crash; 5->guiding-text/Unknown, 6/7->Unknown)\n");
	return 0;
}

// vi:set ts=3 sw=3: