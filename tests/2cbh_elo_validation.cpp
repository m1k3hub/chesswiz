// ======================================================================
// 2cbh_elo_validation.cpp -- validate the 2CBH (.2cbh index) Elo decode
// against ground truth taken from the fixture's own source PGN.
//
// The decode under test is db::cb2::readIndexElo (src/db/2cbh/cb2_elo.h),
// the single helper used by both cb2::Codec's index read and the standalone
// 2cbh2pgn converter, so this exercises exactly the offsets and endianness
// the application uses: a plain little-endian u16 at index-record offset
// 0x60 (White) / 0x70 (Black).
//
// Expected values are checked in (tests/fixtures/2cbh_elo_sample.tsv) rather
// than read from the 763 MB source PGN, which is far too slow to parse at
// test time.  The sample is 578 identity-matched twin games spread evenly
// over all 863,538 index records of LumbrasGigaBase_OTB_ELO2400; regenerate
// it with tests/tmp-app/2cbh-elo/gen_elo_sample.py (see that script's
// docstring and docs/formats/2CBH_FORMAT_DESIGN.md for the join method).
//
// The fixture is read-only and machine-local: when it is absent the test
// prints SKIP and exits 0, so CI on a machine without it still passes.
//
// Usage: 2cbh_elo_validation [sample.tsv] [fixtureDir]
//        (fixtureDir defaults to $SCIDB_2CBH_FIXTURE_DIR)
// Build/run: make -C tests 2cbh-elo
// ======================================================================

#include "2cbh/cb2_elo.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace
{

// Default location of the read-only fixture directory holding
// LumbrasGigaBase_OTB_ELO2400.{2cbh,2lid,pgn}.  Override with argv[2] or
// $SCIDB_2CBH_FIXTURE_DIR; the same default is used by scripts/*2cbh*.py.
char const* const kDefaultFixtureDir = "/media/michael-g-thomas/sas_mirror/chess/pgn";
char const* const kFixtureRoot = "LumbrasGigaBase_OTB_ELO2400";

unsigned const kHeaderRecords = 256;	// .2cbh records 0..255 are the header block
unsigned const kMinRecordSize = 0xbe;	// same floor cb2::Codec::doOpen enforces

// One ground-truth row of tests/fixtures/2cbh_elo_sample.tsv.  The identity
// columns are index-side values kept for provenance and for diagnostics in a
// failure message; only whiteElo/blackElo (the PGN's [WhiteElo]/[BlackElo])
// are asserted.
struct Sample
{
	unsigned	game;
	std::string	white;
	std::string	black;
	std::string	date;
	std::string	result;
	std::string	round;
	std::string	eco;
	unsigned		whiteElo;
	unsigned		blackElo;
};

bool readSample(std::string const& path, std::vector<Sample>& out, std::string& err)
{
	std::ifstream in(path.c_str());
	if (!in)
	{
		err = "cannot open sample '" + path + "'";
		return false;
	}

	std::string line;
	unsigned lineNo = 0;
	while (std::getline(in, line))
	{
		++lineNo;
		if (line.empty() || line[0] == '#')
			continue;
		if (!line.empty() && line[line.size() - 1] == '\r')
			line.erase(line.size() - 1);

		std::vector<std::string> field;
		std::string::size_type start = 0;
		while (true)
		{
			std::string::size_type tab = line.find('\t', start);
			field.push_back(line.substr(start, tab == std::string::npos
													? std::string::npos : tab - start));
			if (tab == std::string::npos)
				break;
			start = tab + 1;
		}

		if (field.size() != 9)
		{
			std::ostringstream msg;
			msg << path << ':' << lineNo << ": expected 9 tab-separated columns, got "
				 << field.size();
			err = msg.str();
			return false;
		}

		Sample s;
		s.game = unsigned(::atoi(field[0].c_str()));
		s.white = field[1];
		s.black = field[2];
		s.date = field[3];
		s.result = field[4];
		s.round = field[5];
		s.eco = field[6];
		s.whiteElo = unsigned(::atoi(field[7].c_str()));
		s.blackElo = unsigned(::atoi(field[8].c_str()));
		if (s.whiteElo == 0 || s.blackElo == 0)
		{
			std::ostringstream msg;
			msg << path << ':' << lineNo << ": missing ground-truth Elo";
			err = msg.str();
			return false;
		}
		out.push_back(s);
	}

	if (out.empty())
		err = path + ": no sample rows";
	return err.empty();
}

} // namespace


int
main(int argc, char* argv[])
{
	std::string const samplePath = argc > 1 ? argv[1] : "tests/fixtures/2cbh_elo_sample.tsv";
	std::string fixtureDir = kDefaultFixtureDir;
	if (argc > 2)
		fixtureDir = argv[2];
	else if (char const* env = ::getenv("SCIDB_2CBH_FIXTURE_DIR"))
		fixtureDir = env;

	std::string const cbhPath = fixtureDir + "/" + kFixtureRoot + ".2cbh";

	// --- skip gracefully when the machine-local fixture is absent ---------
	{
		std::ifstream probe(cbhPath.c_str(), std::ios_base::in | std::ios_base::binary);
		if (!probe)
		{
			::printf("SKIP: 2CBH fixture not readable: %s\n", cbhPath.c_str());
			::printf("SKIP: set SCIDB_2CBH_FIXTURE_DIR or pass the directory as argv[2]\n");
			::printf("2CBH-ELO: SKIPPED (fixture absent)\n");
			return 0;
		}
	}

	std::vector<Sample> sample;
	std::string err;
	if (!readSample(samplePath, sample, err))
	{
		::fprintf(stderr, "FAIL: %s\n", err.c_str());
		return 2;
	}

	std::ifstream cbh(cbhPath.c_str(), std::ios_base::in | std::ios_base::binary);
	if (!cbh)
	{
		::fprintf(stderr, "FAIL: cannot open '%s'\n", cbhPath.c_str());
		return 2;
	}

	// Index geometry: the record size is a u16 LE at header offset 0x0a, and
	// game k lives at record (256 + k).  Both are cb2::Codec::doOpen's rules.
	unsigned char header[16];
	if (!cbh.read(reinterpret_cast<char*>(header), sizeof(header)))
	{
		::fprintf(stderr, "FAIL: cannot read the .2cbh header\n");
		return 2;
	}
	unsigned const recordSize = unsigned(header[0x0a]) | (unsigned(header[0x0b]) << 8);
	if (recordSize < kMinRecordSize)
	{
		::fprintf(stderr, "FAIL: implausible .2cbh record size %u\n", recordSize);
		return 2;
	}
	cbh.seekg(0, std::ios_base::end);
	std::streamoff const fileSize = cbh.tellg();
	if (fileSize < std::streamoff(kHeaderRecords) * recordSize)
	{
		::fprintf(stderr, "FAIL: .2cbh is truncated (%ld bytes)\n", long(fileSize));
		return 2;
	}
	unsigned const numGames = unsigned(fileSize / recordSize) - kHeaderRecords;

	::printf("2CBH-ELO: fixture %s\n", cbhPath.c_str());
	::printf("2CBH-ELO: %u games, record size %u bytes\n", numGames, recordSize);
	::printf("2CBH-ELO: sample  %s (%u games)\n", samplePath.c_str(), unsigned(sample.size()));

	unsigned exact = 0;
	unsigned compared = 0;
	unsigned whiteExact = 0;
	unsigned blackExact = 0;
	unsigned badMarker = 0;
	unsigned minElo = ~0u;
	unsigned maxElo = 0;
	unsigned shown = 0;
	std::vector<unsigned> badRecords;

	for (std::vector<Sample>::const_iterator it = sample.begin(); it != sample.end(); ++it)
	{
		Sample const& s = *it;
		if (s.game >= numGames)
		{
			::fprintf(stderr, "FAIL: sample game %u beyond the fixture's %u games "
								"(sample and fixture disagree)\n", s.game, numGames);
			return 2;
		}

		std::vector<unsigned char> rec(recordSize);
		cbh.clear();
		cbh.seekg(std::streamoff(kHeaderRecords + s.game) * std::streamoff(recordSize),
					std::ios_base::beg);
		if (!cbh.read(reinterpret_cast<char*>(&rec[0]), recordSize))
		{
			::fprintf(stderr, "FAIL: short read at index record %u\n", s.game);
			return 2;
		}

		// The type/version word ChessBase's own Elo setter tests before it
		// stores (CMP word [RCX+2], 0x101); see cb2_elo.h.
		unsigned const typeWord = unsigned(rec[2]) | (unsigned(rec[3]) << 8);
		if (typeWord != 0x0101)
			++badMarker;

		unsigned const got[2] = {
			db::cb2::readIndexElo(&rec[0], db::color::White),
			db::cb2::readIndexElo(&rec[0], db::color::Black),
		};
		unsigned const want[2] = { s.whiteElo, s.blackElo };

		for (unsigned c = 0; c < 2; ++c)
		{
			++compared;
			if (got[c] == want[c])
			{
				++exact;
				if (c == 0) ++whiteExact; else ++blackExact;
			}
			else if (shown < 10)
			{
				++shown;
				::printf("MISMATCH game=%u %s vs %s [%s %s %s %s] %s decoded %u, PGN %u\n",
							s.game, s.white.c_str(), s.black.c_str(), s.date.c_str(),
							s.result.c_str(), s.round.c_str(), s.eco.c_str(),
							c == 0 ? "WhiteElo" : "BlackElo", got[c], want[c]);
			}
			if (got[c] < minElo) minElo = got[c];
			if (got[c] > maxElo) maxElo = got[c];
		}

		if (got[0] != want[0] || got[1] != want[1])
			badRecords.push_back(s.game);
	}

	unsigned const games = unsigned(sample.size());
	::printf("2CBH-ELO: decoded Elo range %u..%u over %u compared values\n",
				minElo, maxElo, compared);
	::printf("2CBH-ELO: record type word 0x0101 in %u of %u records%s\n",
				games - badMarker, games, badMarker ? " (UNEXPECTED)" : "");
	::printf("2CBH-ELO: exact match rate: %u/%u = %.4f%% "
				"(white %u/%u, black %u/%u, games %u/%u)\n",
				exact, compared, compared ? 100.0 * exact / compared : 0.0,
				whiteExact, games, blackExact, games, games - unsigned(badRecords.size()), games);

	if (badMarker || exact != compared)
	{
		::printf("FAIL: 2CBH Elo decode mismatched %u of %u values\n",
					compared - exact, compared);
		return 1;
	}

	::printf("PASS: 2CBH Elo decode exact on %u/%u values (%u games) -- "
				"u16 LE at index 0x60 (White) / 0x70 (Black)\n", exact, compared, games);
	return 0;
}
