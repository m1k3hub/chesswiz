// ======================================================================
// 2cbh_annotations.cpp -- .2cba item walker + .2cbg structure flattening
// (see 2cbh_annotations.h for the format description).
//
// Validation against PGN twins (LumbrasGigaBase, 2026-08-29):
//   - X+1 == no-reset document-order walk position for 233/233 items
//     across 94 aligned twin games (35/35 on a 35-annotation game with
//     variations, using the PGN's own flattened RAV ordering)
//   - channel -> NAG: 2 = ?, 4 = ??, 6 = ?! (perfect text-class match)
// ======================================================================

#include "2cbh_annotations.h"
#include "2cbh_move16.h"

#include <string.h>

namespace db
{

namespace cb2
{

namespace
{

inline uint32_t readLE32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
		 | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

inline uint16_t readLE16(unsigned char const* p)
{
	return uint16_t(p[0] | (p[1] << 8));
}

inline bool isEndMarker(unsigned char const* p)
{
	// mirrors the verified Python walker: any leading ff ff (the record may
	// end with 'ff ff ff 7f' or a short 'ff ff' tail)
	return p[0] == 0xff && p[1] == 0xff;
}

} // anonymous namespace


bool
parseCbaItems(unsigned char const* data, uint32_t size, mstl::vector<CbaItem>& items)
{
	uint32_t p = 0;

	while (true)
	{
		if (p + 2 <= size && isEndMarker(data + p))
			return true; // end-of-record marker reached

		if (p + 18 > size)
			return false;

		uint32_t const position = readLE32(data + p);
		uint32_t const kind = readLE32(data + p + 4);
		uint16_t nag = 0;
		uint16_t type = 0;
		uint32_t len = 0;
		uint32_t body = 0;

		if (kind == 2 && readLE16(data + p + 8) == 3)
		{
			// channelled form: [u32 2][u16 3][u16 ch][u8 0][u32 2]
			if (p + 23 > size)
				return false;
			nag = readLE16(data + p + 10);
			uint8_t z = data[p + 12];
			uint32_t mid3 = readLE32(data + p + 13);
			type = readLE16(data + p + 17);
			len = readLE32(data + p + 19);
			body = p + 23;
			if (z != 0 || mid3 != 2 || type != 7)
				return false;
		}
		else if (kind == 1 || kind == 2)
		{
			if (p + 18 > size)
				return false;
			uint32_t mid = readLE32(data + p + 8);
			type = readLE16(data + p + 12);
			len = readLE32(data + p + 14);
			body = p + 18;
			if (mid != 2 || type != 7)
				return false;
		}
		else
		{
			return false;
		}

		if (len > size || body > size || body + len > size)
			return false;

		CbaItem& item = items.push_back();
		item.position = position;
		item.nag = nag;
		item.hasText = true;
		item.text.append(reinterpret_cast<char const*>(data + body), unsigned(len));

		p = body + len;
	}
}


void
parseCbgStructure(unsigned char const* data, uint32_t size, CbgStructure& structure)
{
	uint32_t const n = size / 2;
	uint32_t k = 0;
	structure.mainlinePly = 0;
	structure.variationMoves = 0;
	structure.markerPly.clear();
	structure.blockSize.clear();

	while (k < n)
	{
		uint16_t code = readLE16(data + 2*k);
		if (code == Move16_GameStart)
		{
			++k;
			continue;
		}
		if (code == Move16_Terminator)
		{
			++k;
			break;
		}
		if (code == Move16_Marker) // 0xfffd: a variation attaches here
		{
			structure.markerPly.push_back(structure.mainlinePly);
			++k;
			continue;
		}
		if (code >= Move16_None)
		{
			++k;
			continue;
		}
		++structure.mainlinePly;
		++k;
	}

	// post-mainline blocks: runs of variation moves, each closed by 0xffff
	uint32_t run = 0;
	while (k < n)
	{
		uint16_t code = readLE16(data + 2*k);
		++k;
		if (code == Move16_Terminator)
		{
			structure.blockSize.push_back(run);
			structure.variationMoves += run;
			run = 0;
			continue;
		}
		if (code >= Move16_None)
			continue;
		++run;
	}
	if (run > 0)
	{
		structure.blockSize.push_back(run);
		structure.variationMoves += run;
	}
}


bool
flattenToMainline(	uint32_t position,
						CbgStructure const& structure,
						uint32_t& mainlinePly)
{
	// Verified territory: games without variation data.  For those the
	// flattened walk position IS the mainline ply (233/233 + 35/35 table
	// checks).  Variation-bearing games need the subtree tree-walk, which
	// is future work (see 2CBH_FORMAT_DESIGN.md section 4.1).
	if (!structure.markerPly.empty() || !structure.blockSize.empty())
		return false;

	if (position == 0 || position > structure.mainlinePly)
		return false;

	mainlinePly = position;
	return true;
}

} // namespace cb2
} // namespace db