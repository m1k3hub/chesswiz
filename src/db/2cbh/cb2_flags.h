// ======================================================================
// cb2_flags.h -- medals / game flags of the 2CBH index record.
//
// The u16 word at 0x82 of the 192-byte .2cbh index record holds the game's
// medals.  The slot is the one classic .cbh uses for its medal word (bytes
// 37-38, immediately after the ECO key at 35-36), and CBase26 exposes the
// field with a plain getter/setter pair (0x1401e3d60 / 0x1401e45b0: no
// clamping, no transformation, i.e. a raw bit word), while its ECO
// accessors on the neighbouring 0x80 field do clamp.  The bit assignment
// below was measured by toggling all sixteen CBase26 checkboxes and saving
// each probe (run 10). Defense is bit 8 and Sacrifice bit 9; the dialog
// displays Sacrifice first, so checkbox order is not bit order.
//
// This header is the single definition of that mapping: cb2::Codec reads
// with cb2GameFlags() and cb2::WriteGame writes with cb2Medals(), so a
// database written by cb2::writeDatabase reads back with the same flags.
//
// Two nearby index fields are *not* part of this mapping:
//
//   0x58 bits 2..7  result subtype; subtype 1 is an unplayed score
//                   (+:-, =:=, -:+, 0-0), measured in run 10.
//   0xba bit 0     automatic good-game classification (0x14064ac80).
//   0xba bits 1..2 internal move encoding / cloud state; not medals.
// Deleted is index +0x00 bit 7, measured with the game-list Delete key.
// ======================================================================

#ifndef _cb2_flags_included
#define _cb2_flags_included

#include "db_game_info.h"

#include <stdint.h>

namespace db {

namespace cb2 {

/// GameInfo flags set by the 2CBH medal word (index +0x82).
inline unsigned
cb2GameFlags(uint16_t medals)
{
	unsigned flags = 0;

	if (medals & (1 <<  0)) flags |= GameInfo::Flag_Best_Game;
	if (medals & (1 <<  1)) flags |= GameInfo::Flag_Decided_Tournament;
	if (medals & (1 <<  2)) flags |= GameInfo::Flag_Model_Game;
	if (medals & (1 <<  3)) flags |= GameInfo::Flag_Novelty;
	if (medals & (1 <<  4)) flags |= GameInfo::Flag_Pawn_Structure;
	if (medals & (1 <<  5)) flags |= GameInfo::Flag_Strategy;
	if (medals & (1 <<  6)) flags |= GameInfo::Flag_Tactics;
	if (medals & (1 <<  7)) flags |= GameInfo::Flag_With_Attack;
	if (medals & (1 <<  9)) flags |= GameInfo::Flag_Sacrifice;
	if (medals & (1 <<  8)) flags |= GameInfo::Flag_Defense;
	if (medals & (1 << 10)) flags |= GameInfo::Flag_Material;
	if (medals & (1 << 11)) flags |= GameInfo::Flag_Piece_Play;
	if (medals & (1 << 12)) flags |= GameInfo::Flag_End_Game;
	if (medals & (1 << 13)) flags |= GameInfo::Flag_Blunder;	// tactical blunder
	if (medals & (1 << 14)) flags |= GameInfo::Flag_Blunder;	// strategical blunder
	if (medals & (1 << 15)) flags |= GameInfo::Flag_User;

	return flags;
}

/// The medal word to store for @a gameFlags (index +0x82).
inline uint16_t
cb2Medals(unsigned gameFlags)
{
	uint16_t medals = 0;

	if (gameFlags & GameInfo::Flag_Best_Game)			medals |= (1 <<  0);
	if (gameFlags & GameInfo::Flag_Decided_Tournament)	medals |= (1 <<  1);
	if (gameFlags & GameInfo::Flag_Model_Game)			medals |= (1 <<  2);
	if (gameFlags & GameInfo::Flag_Novelty)				medals |= (1 <<  3);
	if (gameFlags & GameInfo::Flag_Pawn_Structure)		medals |= (1 <<  4);
	if (gameFlags & GameInfo::Flag_Strategy)				medals |= (1 <<  5);
	if (gameFlags & GameInfo::Flag_Tactics)				medals |= (1 <<  6);
	if (gameFlags & GameInfo::Flag_With_Attack)		medals |= (1 <<  7);
	if (gameFlags & GameInfo::Flag_Sacrifice)			medals |= (1 <<  9);
	if (gameFlags & GameInfo::Flag_Defense)				medals |= (1 <<  8);
	if (gameFlags & GameInfo::Flag_Material)				medals |= (1 << 10);
	if (gameFlags & GameInfo::Flag_Piece_Play)			medals |= (1 << 11);
	if (gameFlags & GameInfo::Flag_End_Game)				medals |= (1 << 12);
	if (gameFlags & GameInfo::Flag_Blunder)				medals |= (1 << 13) | (1 << 14);
	if (gameFlags & GameInfo::Flag_User)					medals |= (1 << 15);

	return medals;
}

} // namespace cb2
} // namespace db

#endif // _cb2_flags_included
