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
	// The .2cba item stream is a sequence of MOVE CONTAINERS:
	//   [u32 LE position][u32 LE count][count sub-items]
	// The old parser misread `count` as a `kind` discriminator, which
	// worked only for the two common cases (count 1 = text, count 2 =
	// nag + text) and desynchronized on standalone NAGs, clock times,
	// engine evaluations and 3-annotation containers.  Sub-item types:
	//   2      text comment  [u32 2][u16 lang][u32 len][text]
	//   3      NAG           [u16 3][u16 nag][u8 0]            (5 bytes)
	//   7      move time     [u8 7][u8 0][u8 m][u8 s][u8 f][u8 t] (6 bytes)
	//   0x21   engine eval   [u16 0x21][i16 centipawns][u32 depth]
	// Validated on the whole LumbrasGigaBase fixture: 17,942/17,942
	// annotated games parse to the end marker (agy, 2026-09-07).
	uint32_t p = 0;

	while (true)
	{
		if (p + 2 <= size && isEndMarker(data + p))
			return true; // end-of-record marker reached

		if (p + 8 > size)
			return false;

		uint32_t const position = readLE32(data + p);
		uint32_t const count = readLE32(data + p + 4);
		p += 8;

		if (count == 0 || count > 64)
			return false;

		CbaItem& item = items.push_back();
		item.position = position;
		item.nag = 0;
		item.hasText = false;

		for (uint32_t k = 0; k < count; ++k)
		{
			if (p >= size)
				return false;

			uint32_t const type32 = readLE32(data + p);
			uint16_t const type16 = readLE16(data + p);

			if (type32 == 2)
			{
				// text comment: [u32 2][u16 lang][u32 len][text]
				if (p + 10 > size)
					return false;
				uint32_t const len = readLE32(data + p + 6);
				if (len > size - p - 10)
					return false;
				if (len > 0 && !item.hasText)
				{
					item.text.append(reinterpret_cast<char const*>(data + p + 10), len);
					item.hasText = true;
				}
				p += 10 + len;
			}
			else if (type16 == 3 && item.nag == 0)
			{
				// NAG: [u16 3][u16 nag][u8 0]
				if (p + 5 > size)
					return false;
				item.nag = readLE16(data + p + 2);
				p += 5;
			}
			else if (data[p] == 7)
			{
				// move time: 6 bytes (consumed; rendered via a future %emt path)
				if (p + 6 > size)
					return false;
				p += 6;
			}
			else if (type16 == 0x21)
			{
				// engine evaluation: [u16 0x21][i16 cp][u32 depth]
				if (p + 8 > size)
					return false;
				p += 8;
			}
			else
			{
				return false;
			}
		}

		if (p > size)
			return false;
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
	// is future work (see docs/formats/2CBH_FORMAT_DESIGN.md section 4.1).
	if (!structure.markerPly.empty() || !structure.blockSize.empty())
		return false;

	if (position == 0 || position > structure.mainlinePly)
		return false;

	mainlinePly = position;
	return true;
}

} // namespace cb2
} // namespace db

// ----------------------------------------------------------------------
// variation tree (section 4.2): recursive parse of the reverse-post-order

namespace db
{

namespace cb2
{

namespace
{

uint32_t
parseSubtree(uint16_t const* region,
				 uint32_t regionSize,
				 uint32_t& idx,
				 mstl::vector<CbgNode>& pool,
				 uint32_t& nodeIdxOut)
{
	// own tokens until this node's terminator
	mstl::vector<uint16_t> own;
	mstl::vector<uint32_t> markers;
	while (idx < regionSize && region[idx] != 0xffff)
	{
		uint16_t code = region[idx];
		if (code == 0xfffd)
		{
			markers.push_back(uint32_t(own.size()));
			++idx;
		}
		else if (code >= 0xfffb)
		{
			++idx;
		}
		else
		{
			own.push_back(code);
			++idx;
		}
	}
	if (idx >= regionSize)
		return false;
	++idx;                                   // consume the node's 0xffff
	// Parse the claimed child subtrees FIRST: they append to the pool, so
	// this node's own index must be taken afterwards (appending before the
	// recursion made every marker-carrying node alias its first child).
	mstl::vector<uint32_t> kidsStor;               // storage order
	for (uint32_t k = 0; k < uint32_t(markers.size()); ++k)
	{
		uint32_t kid = 0;
		if (!parseSubtree(region, regionSize, idx, pool, kid))
			return false;
		kidsStor.push_back(kid);
	}
	uint32_t const self = uint32_t(pool.size());
	pool.push_back(CbgNode());
	pool[self].own = own;
	pool[self].markers = markers;
	// doc order = reverse of storage order
	for (uint32_t k = uint32_t(kidsStor.size()); k > 0; --k)
		pool[self].kids.push_back(kidsStor[k - 1]);
	nodeIdxOut = self;
	return true;
}

} // anonymous namespace


bool
parseCbgTree(	uint16_t const* region,
					uint32_t regionSize,
					mstl::vector<uint32_t> const& rootMarkers,
					mstl::vector<CbgNode>& pool,
					mstl::vector<uint32_t>& rootsDoc,
					mstl::vector<uint32_t>& rootInsert)
{
	pool.clear();
	rootsDoc.clear();
	rootInsert.clear();

	uint32_t idx = 0;
	mstl::vector<uint32_t> rootsStor;
	for (uint32_t k = 0; k < uint32_t(rootMarkers.size()); ++k)
	{
		uint32_t root = 0;
		if (!parseSubtree(region, regionSize, idx, pool, root))
			return false;
		rootsStor.push_back(root);          // storage order for now
	}
	if (idx != regionSize)
		return false;                        // trailing garbage -> failure

	if (rootsStor.empty())
		return true;         // no markers: empty forest (flat game)

	// storage order is REVERSE doc order (per 4.2): reverse the root list
	// and the root markers pairing; doc root j pairs with the j-th
	// smallest root marker
	mstl::vector<uint32_t> sortedMarkers(rootMarkers);
	for (mstl::vector<uint32_t>::size_type a = 0; a + 1 < sortedMarkers.size(); ++a)
		for (mstl::vector<uint32_t>::size_type b = a + 1; b < sortedMarkers.size(); ++b)
			if (sortedMarkers[b] < sortedMarkers[a])
			{
				uint32_t t = sortedMarkers[a];
				sortedMarkers[a] = sortedMarkers[b];
				sortedMarkers[b] = t;
			}
	// Root marker pairing, reverse-engineered 2026-09-07 against the
	// LumbrasGigaBase twin PGNs (Suba-Ermenkov single RAV, and the two
	// nested games Westerinen-Ernst 2012 / Kotronias-Ivanchuk 2011; all
	// 16 root RAVs verified).  rootMarkers are MOVE COUNTS (the number of
	// mainline moves before the marker; the count survives stray special
	// tokens that would shift token-index arithmetic).  The doc-order
	// root #a replaces mainline ply `count - 1 - a` (0-based) and feeds
	// directly after that move.  In token-index terms the old form was
	// token - 2 - a; the naive token - 1 reading is off by one for the
	// 2nd and later RAVs.
	for (mstl::vector<uint32_t>::size_type a = 0; a < sortedMarkers.size(); ++a)
	{
		if (sortedMarkers[a] < a + 1)
			return false; // marker before any replaceable mainline move
		uint32_t nodeIdx = rootsStor[rootsStor.size() - 1 - mstl::vector<uint32_t>::size_type(a)];
		rootsDoc.push_back(nodeIdx);
		rootInsert.push_back(sortedMarkers[a] - 1 - a);   // 0-based replaced ply
	}
	return true;
}


uint32_t
cbgSubtreeSize(mstl::vector<CbgNode> const& pool, uint32_t i)
{
	uint32_t s = uint32_t(pool[i].own.size());
	for (mstl::vector<uint32_t>::size_type k = 0; k < pool[i].kids.size(); ++k)
		s += cbgSubtreeSize(pool, pool[i].kids[k]);
	return s;
}


uint32_t
cbgWalkTotal(mstl::vector<CbgNode> const& pool, mstl::vector<uint32_t> const& rootsDoc,
				 uint32_t mainlinePly)
{
	uint32_t s = mainlinePly;
	for (mstl::vector<uint32_t>::size_type k = 0; k < rootsDoc.size(); ++k)
		s += cbgSubtreeSize(pool, rootsDoc[k]);
	return s;
}

} // namespace cb2
} // namespace db
