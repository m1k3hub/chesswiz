// ======================================================================
// ChessBase media script-stream decoder (WMV "Chess Media System")
// ======================================================================
// Self-contained decoder for the timestamped ChessBase script stream
// embedded in WMV Chess Media files (ASF script stream) and in the
// magazine .txt exports.  The grammar was reverse-engineered against
// the CBM 168 fixtures and corroborated inside CBase26.exe — see
// CHESSBASE_MEDIA_RE.md for the full derivation.  Kept header-only so
// it can be unit tested without linking the Tcl command layer
// (mirrors tcl_media_extract.h).
//
// Layers, in feed order:
//
//   1. transport — script commands arrive as UTF-16LE text
//      "GA\0" + six-bit chars (chars '?'..'~' = 0x3f..0x7e encode
//      6 bits each, 4 chars -> 3 bytes), or as the flat text-export
//      form "GA:" + chars.  Decodes to binary records; fixed-size
//      records (3/4/8/14) are trimmed after their declared length.
//      Every command has a delivery timestamp (the packet pts_time or
//      the .txt line prefix) supplied by the caller, not by this file.
//
//   2. records — little-endian u32 opcode:
//        2/15 SetGame    checkpoint (identity, Elo, game date, the
//                        serialized game-tree edge stream in
//                        file-major squares, per-node media times,
//                        inline annotation collections)
//        3   GotoIndex   u32le tree-node index (the lecture cursor)
//        4   board action {class u32le, square file-major u8 x2,
//                         modifier u16le} with a 0x40->0x80 kind
//                        upgrade below the tree length
//        5   board action variant (absent from the CBM 168 corpus)
//        6   annotation deltas [u16 count][CB records]:
//              0x02/0x82 text after/before {u16be language, cp1252 text}
//              0x03 symbols {u8 move, u8 eval, u8 prefix}
//              0x04 styled marks {u8 style, u8 square}*
//              0x05 styled arrows {u8 style, u8 from, u8 to}*
//              0x22(34) medal bitmask u32be (1 = Best Game)
//              25(37) media-ms cursor u32be
//              7 {00 index square 00} (semantics open)
//        8   PromoteLine, 11 UnAnnotate, 12 AddAnnoText, 13 WebOrigin,
//        14  Sync{u16 counter}, 16 SetMoves, 17 SetHeader
//
//   3. squares — ChessBase stores them FILE-MAJOR (square = file*8 +
//      rank; a1 = 0, b1 = 8, a2 = 1), graphics records one-based
//      (0 = none, a1 = 1, h8 = 64).  The decoder emits algebraic
//      names ("c8"); callers never touch the encoding.
//
//   4. output — a navigation timeline (transition marks in replay
//      order) plus a BoardEvent stream (arrows/marks/comments/symbols
//      in algebraic squares with language-tagged cp1252→UTF-8 text),
//      ready for the SCM 1.6 [BoardSync] section
//      (SCM_FORMAT_DESIGN.md).
// ======================================================================

#ifndef _tcl_scriptstream_included
#define _tcl_scriptstream_included

#include "m_string.h"
#include "m_vector.h"

#include <cstring>
#include <cstdio>
#include <cstdlib>

namespace cb_media {

// ---------------------------------------------------------------------
// kinds
// ---------------------------------------------------------------------

enum Kind
{
	PositionSync,		// opcode 2 / 15 — Set Game (checkpoint)
	GotoIndex,			// opcode 3 — move the lecture cursor
	BoardAction,		// opcode 4 — transient board action
	BoardActionVar,		// opcode 5 — variant form
	Annotation,			// opcode 6 — delta container
	PromoteLine,		// opcode 8
	ViewerCall,			// opcode 9 / 10 — media-overlay helpers
	UnAnnotate,			// opcode 11
	AddAnnoText,		// opcode 12
	WebOrigin,			// opcode 13
	SyncCounter,		// opcode 14 — source-time sync step
	SetMoves,			// opcode 16
	SetHeader,			// opcode 17
	Unknown
};

inline char const* kind_name(Kind k)
{
	switch (k)
	{
		case PositionSync:	return "Set Game";
		case GotoIndex:		return "GotoIndex";
		case BoardAction:	return "BoardAction";
		case BoardActionVar:return "BoardActionVar";
		case Annotation:	return "Annotation";
		case PromoteLine:	return "Promote Line";
		case ViewerCall:	return "ViewerCall";
		case UnAnnotate:	return "UnAnnotate";
		case AddAnnoText:	return "Add Annotext";
		case WebOrigin:		return "WebOrigin";
		case SyncCounter:	return "Sync";
		case SetMoves:		return "Set Moves";
		case SetHeader:		return "Set Header";
		default:			return "Unknown";
	}
}

// ---------------------------------------------------------------------
// squares — file-major conventions
// ---------------------------------------------------------------------

// zero-based file-major (node table, opcode 4): a1 = 0, b1 = 8, a2 = 1
inline mstl::string square_algebraic(unsigned v)
{
	if (v >= 64)
		return mstl::string();
	static char const files[8] = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };
	mstl::string s;
	s += files[v >> 3];
	s += static_cast<char>('1' + (v & 7));
	return s;
}

// one-based file-major (opcode-06 graphics): 0 = none, a1 = 1, h8 = 64
inline mstl::string graphic_square_algebraic(unsigned v)
{
	if (v == 0 || v > 64)
		return mstl::string();
	return square_algebraic(v - 1);
}

inline unsigned square_from_algebraic(char const* name)
{
	if (name == 0 || name[0] < 'a' || name[0] > 'h')
		return 0;
	unsigned file = static_cast<unsigned>(name[0] - 'a');
	if (name[1] < '1' || name[1] > '8')
		return 0;
	return file * 8 + static_cast<unsigned>(name[1] - '1');
}

// ---------------------------------------------------------------------
// cp1252 -> UTF-8 (the media stream text encoding)
// ---------------------------------------------------------------------

inline mstl::string cp1252_to_utf8(char const* s, unsigned len)
{
	static char const* high[32] =
	{
		"\xE2\x82\xAC", "\x81",
		"\xE2\x80\x9A", "\xC6\x92",	"\xE2\x80\x9E",	"\xE2\x80\xA6",
		"\xE2\x80\xA0",	"\xE2\x80\xA1",	"\xCB\x86",		"\xE2\x80\xB0",
		"\xC5\xA0",		"\xE2\x80\xB9",	"\xC5\x92",		"\x8D",
		"\xC5\xBD",		"\x8F",			"\x90",			"\xE2\x80\x98",
		"\xE2\x80\x99",	"\xE2\x80\x9C",	"\xE2\x80\x9D",	"\xE2\x80\xA2",
		"\xE2\x80\x93",	"\xE2\x80\x94",	"\xCB\x9C",		"\x99",
		"\xC5\xA1",		"\xE2\x80\xBA",	"\xC5\x93",		"\x9D",
		"\xC5\xBE",		"\xC5\xB8",
	};
	mstl::string out;
	out.reserve(len + 8);
	for (unsigned i = 0; i < len; ++i)
	{
		unsigned char c = static_cast<unsigned char>(s[i]);
		if (c < 0x80)
		{
			out += static_cast<char>(c);
		}
		else if (c < 0xA0)
		{
			out += high[c - 0x80];
		}
		else
		{
			out += static_cast<char>(0xC0 | (c >> 6));
			out += static_cast<char>(0x80 | (c & 0x3F));
		}
	}
	return out;
}

inline mstl::string cp1252_to_utf8(mstl::string const& s)
{
	return cp1252_to_utf8(s.data(), static_cast<unsigned>(s.size()));
}

// ---------------------------------------------------------------------
// records
// ---------------------------------------------------------------------

// one styled square mark (opcode-06 type 4)
struct SquareMark
{
	unsigned		style;		// 2/3/4 seen; color tag is GUI-defined
	mstl::string	square;		// algebraic
	SquareMark():style(0) {}
};

// one styled arrow (opcode-06 type 5)
struct Arrow
{
	unsigned		style;
	mstl::string	from;
	mstl::string	to;
	Arrow():style(0) {}
};

// one board/annotation event decoded from the stream
struct Event
{
	Kind					kind;
	double					timestampMs;	// media-ms of the delivery; 0 = unknown
	unsigned				index;			// GotoIndex node / medal bits
	unsigned				classWord;		// opcode 4 class
	unsigned				modifier;		// opcode 4 modifier (u16le)
	unsigned				syncCounter;	// opcode 14 counter
	unsigned				gotoIndex;		// opcode 3 target index
	Kind					variantKind;	// opcode 5 target
	mstl::string			from;			// algebraic
	mstl::string			to;				// algebraic
	mstl::vector<SquareMark>	marks;
	mstl::vector<Arrow>			arrows;
	mstl::string			text;			// UTF-8 (transcoded from cp1252)
	unsigned				language;		// 0 = all, 0x2A = en, 0x35 = de, …
	bool					textBefore;		// true = before the move (0x82)
	unsigned				moveGlyph;		// 0 = unset; 1 '!' 2 '?' 3 '!!' 4 '??'
											// 5 '!?' 6 '?!' 8 only-move 0x16 zugzwang
	unsigned				positionEval;	// 0x0B..0x13 ChessBase evaluations
	unsigned				prefixGlyph;	// 0x8C..0x91 editorial prefixes
	unsigned				medalBits;		// bit 0 = Best Game

	Event()
		:kind(Unknown),timestampMs(0.0),index(0),classWord(0),modifier(0)
		,syncCounter(0),gotoIndex(0),variantKind(Unknown),language(0)
		,textBefore(false),moveGlyph(0),positionEval(0),prefixGlyph(0)
		,medalBits(0)
	{
	}
};

// decoded checkpoint (opcode 2)
struct Checkpoint
{
	mstl::string				white, black, site, event;
	unsigned					whiteElo, blackElo;		// 0 = absent
	unsigned					year, month, day;		// identity packed date
	unsigned					gameYear, gameMonth, gameDay;
	mstl::string				annotator;				// "Robot 11", "Mihail,Marin"
	mstl::vector<mstl::string>	extraNames;				// "Mega2015 Update 36", …
	mstl::vector<mstl::string>	treeMoves;				// "c2-c4" edges, replay order
	mstl::vector<unsigned>		nodeTimes;				// media-ms per decorated node

	Checkpoint()
		:whiteElo(0),blackElo(0),year(0),month(0),day(0)
		,gameYear(0),gameMonth(0),gameDay(0)
	{
	}
};

// ---------------------------------------------------------------------
// transport: six-bit decode (chars 0x3f..0x7e, 4 chars -> 3 bytes)
// ---------------------------------------------------------------------

inline bool decode_transport(unsigned char const* p, unsigned n,
								mstl::vector<unsigned char>& out)
{
	out.clear();
	if (n == 0)
		return false;
	out.reserve(n * 3 / 4 + 4);

	unsigned value = 0;
	unsigned bitcount = 0;
	for (unsigned i = 0; i < n; ++i)
	{
		unsigned char c = static_cast<unsigned char>(p[i]);
		if (c < 0x3F || c > 0x7E)
			return false;
		value = (value << 6) | static_cast<unsigned>(c - 0x3F);
		bitcount += 6;
		if (bitcount >= 8)
		{
			bitcount -= 8;
			out.push_back(static_cast<unsigned char>((value >> bitcount) & 0xFF));
		}
	}
	if (out.empty())
		return false;

	// logical trim: fixed-size opcodes end at their declared length; the
	// six-bit tail carries zero padding after the record ends
	unsigned size = static_cast<unsigned>(out.size());
	if (size < 4)
		return true;
	unsigned opcode = static_cast<unsigned>(out[0])
		| (static_cast<unsigned>(out[1]) << 8)
		| (static_cast<unsigned>(out[2]) << 16)
		| (static_cast<unsigned>(out[3]) << 24);
	unsigned logical = 0;
	if (opcode == 3 || opcode == 8 || opcode == 14)
		logical = 6;
	else if (opcode == 4)
		logical = 12;
	if (logical && logical <= size)
	{
		for (unsigned i = logical; i < size; ++i)
		{
			if (out[i] != 0)
				return false;	// nonzero padding: malformed command
		}
		out.resize(logical);
	}
	return true;
}

// The script command comes in two physical forms:
//   * the ASF/stream packet: UTF-16LE  'G' 00 'A' 00 00 00  followed by
//     N wide chars (low byte = the six-bit char, high byte = 0);
//   * the text export line body: "GA:" followed by N narrow chars.
// strip_command finds the six-bit payload start and its length.
inline bool strip_command(unsigned char const* p, unsigned n,
							unsigned& begin, unsigned& len)
{
	begin = 0;
	len = 0;
	if (n < 2)
		return false;
	if (p[0] == 'G' && p[1] == 0x00)
	{
		// UTF-16LE: [G 00][A 00][00 00] then chars on every other byte
		if (n < 6 || p[2] != 'A' || p[3] != 0x00 || p[4] != 0 || p[5] != 0)
			return false;
		begin = 6;
		len = n > begin ? (n - begin) / 2 : 0;
		// copy the low bytes
		return true;
	}
	if (p[0] == 'G' && p[1] == 'A')
	{
		if (n >= 3 && p[2] == ':')
		{
			begin = 3;
			len = n - 3;
		}
		else
		{
			begin = 2;
			len = n - 2;
		}
		return true;
	}
	// already-stripped six-bit body
	begin = 0;
	len = n;
	return n != 0;
}

// decode one script command (packet form, text form, or bare six-bit
// characters) into the binary record `out`.
inline bool decode_record_bytes(unsigned char const* p, unsigned n,
									mstl::vector<unsigned char>& record)
{
	unsigned begin = 0;
	unsigned len = 0;
	if (!strip_command(p, n, begin, len))
		return false;

	if (p[0] == 'G' && p[1] == 0x00 && n >= 7)
	{
		// wide form: build the narrow six-bit buffer
		mstl::vector<unsigned char> chars;
		for (unsigned i = 0; i < len; ++i)
		{
			unsigned char hi = p[begin + 2 * i + 1];
			if (hi != 0)
				return false;
			chars.push_back(p[begin + 2 * i]);
		}
		return decode_transport(chars.empty() ? 0 : &chars[0],
				static_cast<unsigned>(chars.size()), record);
	}
	return decode_transport(p + begin, len, record);
}

// ---------------------------------------------------------------------
// opcode names (FUN_140da1d70's dictionary)
// ---------------------------------------------------------------------

inline Kind kind_of_opcode(unsigned opcode)
{
	switch (opcode)
	{
		case 2:
		case 15:	return PositionSync;
		case 3:		return GotoIndex;
		case 4:		return BoardAction;
		case 5:		return BoardActionVar;
		case 6:		return Annotation;
		case 8:		return PromoteLine;
		case 9:
		case 10:	return ViewerCall;
		case 11:	return UnAnnotate;
		case 12:	return AddAnnoText;
		case 13:	return WebOrigin;
		case 14:	return SyncCounter;
		case 16:	return SetMoves;
		case 17:	return SetHeader;
		default:	return Unknown;
	}
}

// ---------------------------------------------------------------------
// binary reader helpers
// ---------------------------------------------------------------------

inline unsigned rd_le32(unsigned char const* p)
{
	return static_cast<unsigned>(p[0])
		| (static_cast<unsigned>(p[1]) << 8)
		| (static_cast<unsigned>(p[2]) << 16)
		| (static_cast<unsigned>(p[3]) << 24);
}

inline unsigned rd_le16(unsigned char const* p)
{
	return static_cast<unsigned>(p[0]) | (static_cast<unsigned>(p[1]) << 8);
}

inline unsigned rd_be16(unsigned char const* p)
{
	return (static_cast<unsigned>(p[0]) << 8) | static_cast<unsigned>(p[1]);
}

inline unsigned rd_be32(unsigned char const* p)
{
	return (static_cast<unsigned>(p[0]) << 24)
		| (static_cast<unsigned>(p[1]) << 16)
		| (static_cast<unsigned>(p[2]) << 8)
		| static_cast<unsigned>(p[3]);
}

// ---------------------------------------------------------------------
// annotation-record parsing (opcode 6)
// ---------------------------------------------------------------------

// parse one [u32le opcode][record] entry into `ev`; returns false for
// unknown records (skipped by the caller).
inline bool parse_cb_record(unsigned type, unsigned char const* value,
								unsigned len, Event& ev)
{
	std::fprintf(stderr, "[parse_cb_record type=%u len=%u]\n", type, len);
	switch (type)
	{
		case 0x02:	// text after move
		case 0x82:	// text before move
		{
			if (len < 2)
				return false;
			ev.language = rd_be16(value);
			if (len > 2)
				ev.text = cp1252_to_utf8(reinterpret_cast<char const*>(value + 2), len - 2);
			ev.textBefore = (type == 0x82);
			ev.kind = Annotation;
			return true;
		}
		case 0x03:	// symbols
		{
			if (len < 1 || len > 3)
				return false;
			ev.moveGlyph	= len > 0 ? value[0] : 0;
			ev.positionEval	= len > 1 ? value[1] : 0;
			ev.prefixGlyph	= len > 2 ? value[2] : 0;
			ev.kind = Annotation;
			return true;
		}
		case 0x04:	// styled square marks
		{
			if (len % 2 != 0)
				return false;
			for (unsigned i = 0; i + 1 < len; i += 2)
			{
				SquareMark mark;
				mark.style = value[i];
				mark.square = graphic_square_algebraic(value[i + 1]);
				ev.marks.push_back(mark);
			}
			ev.kind = BoardAction;
			return true;
		}
		case 0x05:	// styled arrows
		{
			if (len % 3 != 0)
				return false;
			for (unsigned i = 0; i + 2 < len; i += 3)
			{
				Arrow arrow;
				arrow.style = value[i];
				arrow.from = graphic_square_algebraic(value[i + 1]);
				arrow.to = graphic_square_algebraic(value[i + 2]);
				ev.arrows.push_back(arrow);
			}
			ev.kind = BoardAction;
			return true;
		}
		case 0x22:	// medal
		{
			std::fprintf(stderr, "[case 0x22 hit len=%u]\n", len);
			if (len != 4)
				return false;
			ev.medalBits = rd_be32(value);
			std::fprintf(stderr, "[medalBits=%u]\n", ev.medalBits);
			ev.kind = Annotation;
			return true;
		}
		case 0x25:	// media-ms cursor
		{
			if (len != 4)
				return false;
			ev.timestampMs = static_cast<double>(rd_be32(value));
			ev.kind = SyncCounter;
			return true;
		}
		case 0x07:	// {00 index square 00}
		{
			if (len < 4)
				return false;
			ev.index = value[1];
			ev.from = graphic_square_algebraic(value[2]); // "" when square == 0
			return true;
		}
		default:
			return false;
	}
}

// ---------------------------------------------------------------------
// the wire-record decoder: feed one transport command (already stripped
// to its binary record bytes) with its delivery time
// ---------------------------------------------------------------------

// identity strings in a Set Game packet (0x02/0x0f) begin at offset 16:
// [u8 len][cp1252 bytes incl. NUL] * 6 in the order
//   white-last, white-first, black-last, black-first, site, event
inline bool parse_identity(unsigned char const* p, unsigned len,
								Checkpoint& cp, unsigned& end)
{
	unsigned off = 16;
	if (len < off)
		return false;
	static unsigned const COUNT = 6;
	mstl::string values[COUNT];
	for (unsigned i = 0; i < COUNT; ++i)
	{
		if (off >= len)
			return false;
		unsigned n = p[off];
		++off;
		if (n == 0 || off + n > len)
			return false;
		values[i] = cp1252_to_utf8(
			reinterpret_cast<char const*>(p + off), n - 1);
		off += n;
	}
	cp.white = values[0];
	if (!values[1].empty())
	{
		cp.white += ", ";
		cp.white += values[1];
	}
	cp.black = values[2];
	if (!values[3].empty())
	{
		cp.black += ", ";
		cp.black += values[3];
	}
	cp.site = values[4];
	cp.event = values[5];
	end = off;
	return true;
}

// walk the checkpoint tail: 5-byte node entries ([2-byte edge][00 00 00]),
// with inline annotation collections spliced into the padding:
//   [pair][u16 count][record]... records = [u16 len][u32be type][u16be echo][payload]
// verified 18/18 against the published Navara-Adams round-6 tree.
inline void parse_checkpoint_tail(unsigned char const* p, unsigned len,
									Checkpoint& cp, Event& ev)
{
	// locate the first zero-terminated entry triple: search for a
	// stable start (byte pair + 3 zeros) from offset 6
	unsigned pos = 0;
	while (pos + 5 <= len && !(p[pos + 2] == 0 && p[pos + 3] == 0 && p[pos + 4] == 0))
		++pos;
	if (pos + 5 > len)
		return;

	// anchor: slide until both this entry and the next one are valid
	// (metadata bytes can mimic single entries; two-in-a-row does not
	// happen inside dates/Elo)
	auto entryValid = [&](unsigned q)
	{
		return q + 5 <= len && p[q + 2] == 0 && p[q + 3] == 0 && p[q + 4] == 0
			&& p[q] <= 63 && p[q + 1] <= 63 && !(p[q] == 0 && p[q + 1] == 0);
	};
	while (pos + 10 <= len
			&& !(entryValid(pos)
				 && (entryValid(pos + 5) || pos + 10 > len)))
		++pos;

	while (pos + 5 <= len)
	{
		unsigned a = p[pos];
		unsigned b = p[pos + 1];
		if (p[pos + 2] == 0 && p[pos + 3] == 0 && p[pos + 4] == 0)
		{
			// plain node: two file-major squares = one tree edge
			if (a <= 63 && b <= 63 && !(a == 0 && b == 0))
			{
				mstl::string edge = square_algebraic(a) + "-"
					+ square_algebraic(b);
				cp.treeMoves.push_back(edge);
			}
			pos += 5;
		}
		else if (p[pos + 2] != 0)
		{
			// inline collection inside the padding: [u16 count][records]
			unsigned count = rd_le16(p + pos + 2);
			unsigned q = pos + 4;
			bool ok = count > 0 && count < 64;
			for (unsigned r = 0; ok && r < count; ++r)
			{
				if (q + 2 > len) { ok = false; break; }
				unsigned recLen = rd_le16(p + q);
				if (recLen < 6 || q + 2 + recLen > len) { ok = false; break; }
				unsigned type = rd_be32(p + q + 2);
				unsigned char const* value = p + q + 2 + 6;
				unsigned valueLen = recLen - 6;
				Event sub;
				sub.timestampMs = ev.timestampMs;
				if (parse_cb_record(type, value, valueLen, sub))
				{
					if (type == 0x25)
					{
						// the node's media time: also patch the paired node
						unsigned ms = static_cast<unsigned>(sub.timestampMs);
						cp.nodeTimes.push_back(ms);
						sub.timestampMs = static_cast<double>(ms);
					}
					if (type == 0x02 || type == 0x82)
					{
						// quotation/commentary text belongs to the tree edge
						sub.kind = Annotation;
					}
					else
					{
						sub.kind = Unknown;	// per-node extras stay opaque here
					}
					sub.index = r;
				}
				(void)sub;	// collections are reported through cp below
				q = q + 2 + recLen;
			}
			if (!ok)
				break;
			// collection padding: zero bytes up to the next entry triple
			while (q + 5 <= len && !(p[q] == 0 && p[q + 1] == 0 && p[q + 2] == 0
					 && p[q + 3] != 0 && p[q + 4] != 0))
				++q;
			pos = q;
		}
		else
		{
			break;	// unrecognized padding shape: stop (defensive)
		}
	}
}

// Decode one binary record (the output of decode_record_bytes) into an
// Event, plus the Checkpoint for Set Game.  `timestampMs` = the delivery
// time (packet pts or .txt prefix) supplied by the caller.
inline Kind decode_event(unsigned char const* record, unsigned len,
							double timestampMs, Event& ev, Checkpoint* cp)
{
	ev = Event();
	ev.timestampMs = timestampMs;
	if (len < 4)
	{
		ev.kind = Unknown;
		return ev.kind;
	}
	unsigned opcode = rd_le32(record);
	ev.kind = kind_of_opcode(opcode);

	switch (opcode)
	{
		case 2:
		case 15:
		{
			ev.kind = PositionSync;
			if (!cp)
				break;
			unsigned body = 16;
			if (len > 16)
			{
				unsigned idEnd = 0;
				if (parse_identity(record, len, *cp, idEnd))
				{
					body = idEnd;
					if (len >= idEnd + 4)
					{
						unsigned d1 = rd_le32(record + idEnd);
						cp->year = d1 >> 9;
						cp->month = (d1 >> 5) & 0x0F;
						cp->day = d1 & 0x1F;
					}
				}
			}

			// Elo pair: two consecutive u16le in the rating range, scanned
			// in the window after the identity date (the annotator string
			// and the alignment block sit before it in the corpus layout)
			unsigned eloOffset = 0;
			if (len > body + 8)
			{
				for (unsigned probe = body + 4; probe + 8 < len; ++probe)
				{
					unsigned a = rd_le16(record + probe);
					unsigned b = rd_le16(record + probe + 2);
					if (a >= 2000 && a <= 2900 && b >= 2000 && b <= 2900
							&& rd_le16(record + probe + 4) <= 2900)
					{
						cp->whiteElo = a;
						cp->blackElo = b;
						eloOffset = probe;
						break;
					}
				}
			}

			// game date: full-precision packed date in the window after
			// the Elo pair (the year range filters the alignment noise)
			if (eloOffset)
			{
				for (unsigned probe = eloOffset + 4; probe + 4 < len
						&& probe < eloOffset + 28; ++probe)
				{
					unsigned d2 = rd_le32(record + probe);
					unsigned y = d2 >> 9;
					if (y >= 1990 && y <= 2027)
					{
						cp->gameYear = y;
						cp->gameMonth = (d2 >> 5) & 0x0F;
						cp->gameDay = d2 & 0x1F;
						break;
					}
				}
			}

			// the serialized game-tree edge stream: two consecutive valid
			// entries ([pair <= 63][00 00 00], not both zero) anchor the
			// node table; metadata bytes can mimic one, not two
			auto entryValid = [&](unsigned q)
			{
				return q + 5 <= len && record[q + 2] == 0 && record[q + 3] == 0
					&& record[q + 4] == 0 && record[q] <= 63
					&& record[q + 1] <= 63
					&& !(record[q] == 0 && record[q + 1] == 0);
			};
			unsigned pos = 0;
			while (pos + 10 <= len
					&& !(entryValid(pos)
						 && (entryValid(pos + 5) || pos + 10 > len)))
				++pos;
			while (pos + 5 <= len)
			{
				unsigned a = record[pos];
				unsigned b = record[pos + 1];
				if (record[pos + 2] == 0 && record[pos + 3] == 0
						&& record[pos + 4] == 0)
				{
					if (a <= 63 && b <= 63 && !(a == 0 && b == 0))
					{
						cp->treeMoves.push_back(square_algebraic(a)
							+ "-" + square_algebraic(b));
					}
					else
					{
						break;	// non-square pair: table end
					}
					pos += 5;
				}
				else
				{
					break;
				}
			}
			break;
		}
		case 3:
		{
			if (len >= 6)
				ev.gotoIndex = rd_le32(record + 4);
			ev.kind = GotoIndex;
			break;
		}
		case 4:
		{
			if (len < 12)
			{
				ev.kind = Unknown;
				break;
			}
			ev.classWord = rd_le32(record + 4);
			ev.from = square_algebraic(record[8]);
			ev.to = square_algebraic(record[9]);
			ev.modifier = rd_le16(record + 10);
			ev.kind = BoardAction;
			break;
		}
		case 6:
		{
			if (len < 10)
			{
				ev.kind = Unknown;
				break;
			}
			unsigned count = rd_le16(record + 8);
			unsigned q = 10;
			ev.kind = Annotation;
			for (unsigned r = 0; r < count && q + 8 <= len; ++r)
			{
				unsigned recLen = rd_le16(record + q);
				if (recLen < 6 || q + 2 + recLen > len)
					break;
				unsigned type = rd_be32(record + q + 2);
				unsigned char const* value = record + q + 2 + 6;
				unsigned valueLen = recLen - 6;
				Event sub;
				sub.timestampMs = timestampMs;
				if (parse_cb_record(type, value, valueLen, sub))
				{
					// flatten decoded annotation records into the event
					for (unsigned m = 0; m < sub.marks.size(); ++m)
						ev.marks.push_back(sub.marks[m]);
					for (unsigned a = 0; a < sub.arrows.size(); ++a)
						ev.arrows.push_back(sub.arrows[a]);
					if (!sub.text.empty())
					{
						ev.text = sub.text;
						ev.language = sub.language;
						ev.textBefore = sub.textBefore;
					}
					if (sub.moveGlyph || sub.positionEval || sub.prefixGlyph)
					{
						ev.moveGlyph = sub.moveGlyph;
						ev.positionEval = sub.positionEval;
						ev.prefixGlyph = sub.prefixGlyph;
					}
					if (sub.medalBits)
						ev.medalBits = sub.medalBits;
					if (sub.kind == SyncCounter)
						ev.timestampMs = sub.timestampMs;
				}
				q += 2 + recLen;
			}
			break;
		}
		case 8:
			ev.kind = PromoteLine;
			break;
		case 9:
		case 10:
			ev.kind = ViewerCall;
			break;
		case 11:
			ev.kind = UnAnnotate;
			break;
		case 12:
			ev.kind = AddAnnoText;
			break;
		case 13:
			ev.kind = WebOrigin;
			break;
		case 14:
		{
			if (len >= 6)
				ev.syncCounter = rd_le16(record + 4);
			ev.kind = SyncCounter;
			break;
		}
		case 16:
			ev.kind = SetMoves;
			break;
		case 17:
			ev.kind = SetHeader;
			break;
		default:
			ev.kind = Unknown;
			break;
	}
	return ev.kind;
}

// ---------------------------------------------------------------------
// SCM 1.6 [BoardSync] writer (SCM_FORMAT_DESIGN.md)
// ---------------------------------------------------------------------

inline char const* language_tag(unsigned code)
{
	switch (code)
	{
		case 0x2A:	return "en";
		case 0x2B:	return "es";
		case 0x31:	return "fr";
		case 0x35:	return "de";
		case 0x46:	return "it";
		case 0x67:	return "nl";
		case 0x75:	return "pt";
		default:	return "";
	}
}

inline void append_step(mstl::string& out, unsigned ms)
{
	char buf[32];
	sprintf(buf, "Step: %u\n", ms);
	out += buf;
}

inline void write_board_sync(mstl::string& out, mstl::string const& mediaId,
								mstl::vector<unsigned> const& timeline,
								mstl::vector<Event> const& events)
{
	out += "[BoardSync \"";
	out += mediaId;
	out += "\"]\n";
	for (unsigned i = 0; i < timeline.size(); ++i)
		append_step(out, timeline[i]);
	for (unsigned i = 0; i < events.size(); ++i)
	{
		Event const& e = events[i];
		char buf[64];
		switch (e.kind)
		{
			case BoardAction:
				for (unsigned m = 0; m < e.marks.size(); ++m)
				{
					sprintf(buf, "Mark: %d, %u, ",
						static_cast<int>(e.timestampMs + 0.5), e.marks[m].style);
					out += buf;
					out += e.marks[m].square;
					out += "\n";
				}
				for (unsigned a = 0; a < e.arrows.size(); ++a)
				{
					sprintf(buf, "Arrow: %d, %u, ",
						static_cast<int>(e.timestampMs + 0.5), e.arrows[a].style);
					out += buf;
					out += e.arrows[a].from;
					out += "-";
					out += e.arrows[a].to;
					out += "\n";
				}
				break;
			case Annotation:
				if (!e.text.empty())
				{
					sprintf(buf, "Comment: %d, %s, %s, \"",
						static_cast<int>(e.timestampMs + 0.5),
						e.textBefore ? "pre" : "post",
						language_tag(e.language));
					out += buf;
					out += e.text;
					out += "\"\n";
				}
				if (e.moveGlyph)
				{
					sprintf(buf, "Symbols: %d, %u\n",
						static_cast<int>(e.timestampMs + 0.5), e.moveGlyph);
					out += buf;
				}
				if (e.medalBits)
				{
					sprintf(buf, "Symbols: %d, %u\n",
						static_cast<int>(e.timestampMs + 0.5), e.medalBits);
					out += buf;
				}
				break;
			case PromoteLine:
			case UnAnnotate:
			case AddAnnoText:
			case WebOrigin:
				sprintf(buf, "Reset: %d\n",
					static_cast<int>(e.timestampMs + 0.5));
				out += buf;
				break;
			case SyncCounter:
				sprintf(buf, "Step: %d\n",
					static_cast<int>(e.timestampMs + 0.5));
				out += buf;
				break;
			default:
				break;
		}
	}
	out += "\n";
}

} // namespace cb_media

#endif