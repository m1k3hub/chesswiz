// ======================================================================
// cb2_namebase.h -- shared .2lid (2CBH namebase) slot reader.
//
// The .2lid is a fixed-slot array (stride 0x108a, first slot at 0xb8).
// Every slot carries several independent name records; the game index
// refers to them through the slot ordinal:
//
//   +0x000  player    [u32 total][u32 len][last][u32 len][first]
//   +0x400  event     [u32 total][u32 siteLen][site][u32 evLen][event]
//                     [u32 packed event date]
//   +0x860  source    [u32 total][u32 tLen][sourceTitle][u32 len][source]
//   +0x93c  annotator [u32 total][u32 tLen][title][u32 len][annotator]
//   +0xd3c  team      (not decoded)
//   +0xe76  game title(not decoded)
//
// The six record capacities in the file's 0xb8-byte header
// (1024/1120/220/1024/314/532 = 0x108a bytes) are the sizes of exactly these
// six records, which is how the offsets above are derived: the .2lid is one
// fixed-slot array whose slot holds one record of every section.  Each
// section is a namebase of its own: the game index stores that record's
// ordinal — which is the slot ordinal — so sources and annotators are two
// independent id spaces over the shared slot array.
//
// Both four-string sections are [total][len1][str1][len2][str2][8 zero bytes]
// with total = 20 + len1 + len2.  The genuine fixtures store the source pair
// as [SourceTitle]/[Source]: 'playchess.com'/'ChessBase' in the Grenke
// database, ''/'Codekiddy' in the Lumbras database, whose source PGN has
// [Source "Codekiddy"] and no [Annotator].
//
// The event record's trailing u32 is the EventDate, packed exactly like
// the game date at index +0xbc:
//
//   day(5) | month(4) << 5 | year(12) << 9
//
// Validated on a genuine ChessBase 26 database (tests/tmp-app/2cbh-re/
// fixtures/grenke): the slot 0 record ends 0x000fd481 = 2026.04.01, which
// is the source PGN's [EventDate "2026.04.01"]; slot 1 of the large
// fixture ends 0x000faa00 = 2005.??.??, the source game's event year.
//
// This header is the single definition of that layout: cb2::Codec and the
// 2cbh2pgn converter both read it here, so the two cannot drift apart.
// ======================================================================

#ifndef _cb2_namebase_included
#define _cb2_namebase_included

#include <stddef.h>
#include <stdint.h>

namespace db {

namespace cb2 {

/// Byte offset of slot 0 and the stride between slots in a .2lid file.
static const size_t namebaseFirstSlot = 0xb8;
static const size_t namebaseStride = 0x108a;
/// Offset of the event/site record inside a slot.
static const size_t namebaseEventOffset = 0x400;
/// Offset of the source record inside a slot ([SourceTitle]/[Source]).
static const size_t namebaseSourceOffset = 0x860;
/// Offset of the annotator record inside a slot (same record grammar).
static const size_t namebaseAnnotatorOffset = 0x93c;

/// Number of slots whose first byte lies inside a .2lid of @a size bytes.
/// The file is written sparsely: only the records that were allocated are
/// present, so a trailing partial slot is normal (the genuine Grenke database
/// ends 45 bytes into the slot of its last player record).
inline unsigned
namebaseSlotCount(size_t size)
{
	return size > namebaseFirstSlot
		  ? unsigned((size - namebaseFirstSlot) / namebaseStride)
		  : 0;
}

/// One two-string name record of a slot (source and annotator sections).
struct SlotName
{
	SlotName(): title(0), titleLength(0), name(0), nameLength(0) {}

	char const*	title;			///< first string, e.g. [SourceTitle]
	unsigned		titleLength;
	char const*	name;			///< second string, e.g. [Source]/[Annotator]
	unsigned		nameLength;
};

/// Read the two-string name record of @a slot at @a sectionOffset of a .2lid
/// buffer.  Returns false for an out-of-range slot, an unallocated slot (all
/// zero) or a record whose text is not printable.
inline bool
readSlotName(	unsigned char const* lid,
					size_t size,
					size_t sectionOffset,
					unsigned slot,
					SlotName& result)
{
	if (lid == 0)
		return false;

	size_t const a = namebaseFirstSlot + size_t(slot) * namebaseStride
					  + sectionOffset;

	if (a + 20 > size)
		return false;

	uint32_t const total = uint32_t(lid[a])
							 | (uint32_t(lid[a + 1]) << 8)
							 | (uint32_t(lid[a + 2]) << 16)
							 | (uint32_t(lid[a + 3]) << 24);
	uint32_t const titleLen = uint32_t(lid[a + 4])
							 | (uint32_t(lid[a + 5]) << 8)
							 | (uint32_t(lid[a + 6]) << 16)
							 | (uint32_t(lid[a + 7]) << 24);

	if (total <= 20 || total > 0x200 || titleLen > total - 20)
		return false;

	size_t const b = a + 8 + titleLen;

	if (b + 4 > size)
		return false;

	uint32_t const nameLen = uint32_t(lid[b])
						 | (uint32_t(lid[b + 1]) << 8)
						 | (uint32_t(lid[b + 2]) << 16)
						 | (uint32_t(lid[b + 3]) << 24);

	if (20 + titleLen + nameLen != total || b + 4 + nameLen > size)
		return false;

	char const* const title = reinterpret_cast<char const*>(lid + a + 8);
	char const* const name = reinterpret_cast<char const*>(lid + b + 4);

	for (uint32_t j = 0; j < titleLen; ++j)
		if (static_cast<unsigned char>(title[j]) < 32)
			return false;

	for (uint32_t j = 0; j < nameLen; ++j)
		if (static_cast<unsigned char>(name[j]) < 32)
			return false;

	result.title = title;
	result.titleLength = titleLen;
	result.name = name;
	result.nameLength = nameLen;
	return true;
}

/// A view of one .2lid event record. All pointers point into the caller's
/// buffer; no ownership is transferred.
struct EventSlot
{
	char const*	site;
	unsigned		siteLength;
	char const*	event;
	unsigned		eventLength;
	unsigned		year;
	unsigned		month;
	unsigned		day;
};

/// Decode a packed 3-byte (32-bit container) 2CBH date.
inline void
decodePackedDate(unsigned packed, unsigned& year, unsigned& month, unsigned& day)
{
	day = packed & 0x1f;
	month = (packed >> 5) & 0xf;
	year = (packed >> 9) & 0xfff;
}

/// Read the event/site/EventDate triple of @a slot from a .2lid buffer.
/// Returns false for an out-of-range slot, a deleted slot (no event) or a
/// record whose text is not printable. @a slot is the event ID stored in
/// the game index (index @0x28).
inline bool
readEventSlot(	unsigned char const* lid,
					size_t size,
					unsigned slot,
					EventSlot& result)
{
	if (lid == 0)
		return false;

	size_t const a = namebaseFirstSlot + size_t(slot) * namebaseStride
						  + namebaseEventOffset;
	if (a + 8 > size)
		return false;

	uint32_t const siteLen = uint32_t(lid[a + 4]) | (uint32_t(lid[a + 5]) << 8);
	if (siteLen > 80 || a + 8 + siteLen + 4 > size)
		return false;

	char const* const site = reinterpret_cast<char const*>(lid + a + 8);
	for (uint32_t j = 0; j < siteLen; ++j)
		if (static_cast<unsigned char>(site[j]) < 32)
			return false;

	size_t const b = a + 8 + siteLen;
	uint32_t const eventLen = uint32_t(lid[b]) | (uint32_t(lid[b + 1]) << 8);
	if (eventLen == 0 || eventLen > 90 || b + 8 + eventLen > size)
		return false;

	char const* const event = reinterpret_cast<char const*>(lid + b + 4);
	for (uint32_t j = 0; j < eventLen; ++j)
		if (static_cast<unsigned char>(event[j]) < 32)
			return false;

	unsigned const packed = uint32_t(lid[b + 4 + eventLen])
								 | (uint32_t(lid[b + 5 + eventLen]) << 8)
								 | (uint32_t(lid[b + 6 + eventLen]) << 16)
								 | (uint32_t(lid[b + 7 + eventLen]) << 24);
	unsigned year, month, day;
	decodePackedDate(packed, year, month, day);

	result.site = site;
	result.siteLength = siteLen;
	result.event = event;
	result.eventLength = eventLen;
	result.year = year;
	result.month = month;
	result.day = day;
	return true;
}

} // namespace cb2
} // namespace db

#endif // _cb2_namebase_included
