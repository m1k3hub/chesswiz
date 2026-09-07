// ======================================================================
// 2cbh_annotations.h -- .2cba annotation record decoder for the 2CBH
// (ChessBase 17+) format.
//
// Every game owns one .2cba record, reached through the index's @0x10
// field.  Unannotated records have a 4-byte data payload `ff ff ff 7f`.
// Annotated records hold a stream of items, stored in *document order*
// (i.e. ordered by walk position), both header variants:
//
//   A (23-byte): [u32 X][u32 2][u16 3][u16 ch][u8 0][u32 2][u16 7][u32 len][text]
//   B (18-byte): [u32 X][u32 1][u32 2][u16 type][u32 len][text]
//
//   X     flattened walk position; the comment is attached to the move
//         that raises the document-order move count to X+1 (see
//         2CBH_FORMAT_DESIGN.md section 4.1: positions count every move
//         of the game tree in DFS document order, and the walk counter
//         does NOT reset when a variation closes).
//   ch    channel of form A: the PGN NAG paired with the text
//         (2 = ?, 4 = ??, 6 = ?!* — verified across all sampled records).
//         Form B has no channel (plain text: prose, diagrams, glyph NAGs
//         such as "!", "?" and "%eval"/"%clk" payloads).
//
// The .2cbg record carries the variation tree itself: after the mainline
// terminator (0xffff) follow one block per 0xfffd marker (in document
// order), each block being a plain move run terminated by 0xffff.  See
// 2cbh_annotations.cpp for the flattening helpers.
//
// Validation: X+1 matched the PGN twin's no-reset document-order walk
// position for 233/233 items across 94 aligned twin games (2026-08-29).
// ======================================================================

#ifndef _db_cb2_2cbh_annotations_included
#define _db_cb2_2cbh_annotations_included

#include "m_string.h"
#include "m_vector.h"

#include <stdint.h>

namespace db
{

namespace cb2
{

struct CbaItem
{
   CbaItem():position(0), nag(0) {}

   uint32_t		position;	///< flattened walk position (comment after ply `position`)
   uint16_t		nag;		///< 0 = plain text; otherwise the paired PGN NAG (?, ??, ?!)
   mstl::string	text;		///< comment text (UTF-8), empty when not decodable
   bool			hasText;	///< false = the payload is not valid UTF-8 (skipped)
};

/// Parse the item stream of one .2cba record payload.
/// Returns false when the layout breaks the known grammar (parse stops at
/// the first unknown item; the items collected so far stay valid).
bool parseCbaItems(unsigned char const* data, uint32_t size, mstl::vector<CbaItem>& items);

/// Walk a .2cbg record's move stream and report its structure:
///  - the ply count of the mainline (game start .. first 0xffff)
///  - the ply positions of the 0xfffd markers inside the mainline
///  - the number of moves in each post-mainline subtree block
///    (document order, i.e. the order of the markers)
struct CbgStructure
{
   CbgStructure():mainlinePly(0), variationMoves(0) {}

   uint32_t						mainlinePly;	///< moves of mainline run
   uint32_t						variationMoves;	///< total moves in post-mainline blocks
   mstl::vector<uint32_t>	markerPly;		///< mainline ply after which each marker sits
   mstl::vector<uint32_t>	blockSize;		///< move count per post-mainline block
};

void parseCbgStructure(unsigned char const* data, uint32_t size, CbgStructure& structure);

/// Map a flattened walk position (X) back to the mainline ply at which the
/// comment must be rendered, and the variation-block index when the comment
/// lands inside a subtree.  Returns false when the comment lies inside a
/// subtree block (variation-internal comments need the tree walk; the
/// mainline-only decoder must skip them).  `markerPly[k]`/`blockSize[k]`
/// must come from parseCbgStructure.
///
///   mainlinePly = X - sum of all subtree blocks attached before the
///                 comment's position; when that adjusted position is
///                 within a subtree root's window the comment is
///                 variation-internal and *false* is returned.
bool flattenToMainline(	uint32_t position,
								CbgStructure const& structure,
								uint32_t& mainlinePly);

// ----------------------------------------------------------------------
// Variation tree (section 4.2): post-mainline storage is REVERSE
// POST-ORDER.  A node = its own move runs (interleaved with 0xfffd
// markers at nested-variation points; the marker value = the 0-based
// index of the replaced move), closed by 0xffff; a node with k markers
// is followed by k child subtrees in REVERSE doc order.
struct CbgNode
{
	mstl::vector<uint16_t>	own;      ///< node's own moves in walk order
	mstl::vector<uint32_t>	markers;  ///< 0-based own indices of nested points
	mstl::vector<uint32_t>	kids;     ///< child node indices into the pool
};

/** Parse the post-mainline token region into a variation tree.
 *
 *  The caller slices the record's tokens AFTER the mainline terminator.
 *  Output: the node pool (children refer to pool indices), the doc-order
 *  root node indices, and rootInsert[j] = the 0-based mainline index of
 *  the move replaced by doc root j.  Returns false when the child-count
 *  bookkeeping does not close cleanly.
 */
bool
parseCbgTree(	uint16_t const* region,
					uint32_t regionSize,
					mstl::vector<uint32_t> const& rootMarkers,
					mstl::vector<CbgNode>& pool,
					mstl::vector<uint32_t>& rootsDoc,
					mstl::vector<uint32_t>& rootInsert);

/** Number of own+descendant moves of the node at pool index i. */
uint32_t
cbgSubtreeSize(mstl::vector<CbgNode> const& pool, uint32_t i);

/** Total flattened (document-order) walk length. */
uint32_t
cbgWalkTotal(mstl::vector<CbgNode> const& pool, mstl::vector<uint32_t> const& rootsDoc,
				 uint32_t mainlinePly);

} // namespace cb2
} // namespace db

#endif // _db_cb2_2cbh_annotations_included

