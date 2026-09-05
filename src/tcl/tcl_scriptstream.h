// ======================================================================
// ChessBase media script-stream decoder (WMV "Chess Media System")
// ======================================================================
// Self-contained decoder for the ChessBase script stream embedded in
// WMV Chess Media files and .txt exports.  Grammar verified against
// CBM 168 fixtures and CBase26 decompilation (CHESSBASE_MEDIA_RE.md).
//
// Usage:
//   1. call decode_record_bytes(p, n, records) per transport command
//      — p/n = the raw bytes after the command prefix (or the full
//      packet including the UTF-16LE "GA\0" wrapper)
//   2. call decode_event(record, len, timestampMs, ev, &cp) per command
//      — timestampMs = the delivery time (packet pts or .txt prefix)
//   3. write_board_sync(out, mediaId, timeline, events) to emit the
//      SCM 1.6 [BoardSync] section (SCM_FORMAT_DESIGN.md)
// ======================================================================

#ifndef _tcl_scriptstream_included
#define _tcl_scriptstream_included

#include "m_string.h"
#include "m_vector.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>

namespace cb_media {

// ======================================================================
// kinds
// ======================================================================

enum Kind
{
	PositionSync,   GotoIndex,     BoardAction,    BoardActionVar,
	Annotation,     PromoteLine,   ViewerCall,     UnAnnotate,
	AddAnnoText,    WebOrigin,     SyncCounter,    SetMoves,
	SetHeader,      Unknown
};

inline char const* kind_name(Kind k)
{
	static char const* names[] =
	{
		"Set Game", "GotoIndex", "BoardAction", "BoardActionVar",
		"Annotation", "Promote Line", "ViewerCall", "UnAnnotate",
		"Add Annotext", "WebOrigin", "Sync", "Set Moves",
		"Set Header", "Unknown",
	};
	return names[k <= Unknown ? static_cast<unsigned>(k) : 13];
}

inline Kind kind_of_opcode(unsigned op)
{
	static Kind table[18] =
	{
		Unknown, Unknown, PositionSync, GotoIndex, BoardAction,
		BoardActionVar, Annotation, Unknown, PromoteLine, ViewerCall,
		ViewerCall, UnAnnotate, AddAnnoText, WebOrigin, SyncCounter,
		Unknown, SetMoves, SetHeader,
	};
	return op <= 17 ? table[op] : Unknown;
}

// ======================================================================
// squares: file-major (square = file*8 + rank)
//   zero-based: node table edges + opcode 4 (a1 = 0, b1 = 8, a2 = 1)
//   one-based:  opcode-06 graphics (0 = none, a1 = 1, b1 = 9, h8 = 64)
// ======================================================================

inline mstl::string square_algebraic(unsigned v)
{
	if (v >= 64) return mstl::string();
	static char const files[8] = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };
	mstl::string s;
	s += files[v >> 3];
	s += static_cast<char>('1' + (v & 7));
	return s;
}

inline mstl::string graphic_sq(unsigned v)
{
	if (v == 0 || v > 64) return mstl::string();
	return square_algebraic(v - 1);
}

inline int algebraic_to_fm0(char const* sq)
{
	if (sq == 0 || sq[0] < 'a' || sq[0] > 'h' || sq[1] < '1' || sq[1] > '8')
		return -1;
	return (sq[0] - 'a') * 8 + (sq[1] - '1');
}

// ======================================================================
// cp1252 -> UTF-8
// ======================================================================

inline mstl::string cp1252_to_utf8(char const* s, unsigned len)
{
	static char const* hi[32] =
	{
		"\xE2\x82\xAC", "\x81",         "\xE2\x80\x9A", "\xC6\x92",
		"\xE2\x80\x9E", "\xE2\x80\xA6", "\xE2\x80\xA0", "\xE2\x80\xA1",
		"\xCB\x86",     "\xE2\x80\xB0", "\xC5\xA0",     "\xE2\x80\xB9",
		"\xC5\x92",     "\x8D",         "\xC5\xBD",     "\x8F",
		"\x90",         "\xE2\x80\x98", "\xE2\x80\x99", "\xE2\x80\x9C",
		"\xE2\x80\x9D", "\xE2\x80\xA2", "\xE2\x80\x93", "\xE2\x80\x94",
		"\xCB\x9C",     "\x99",         "\xC5\xA1",     "\xE2\x80\xBA",
		"\xC5\x93",     "\x9D",         "\xC5\xBE",     "\xC5\xB8",
	};
	mstl::string out;
	out.reserve(len + 8);
	for (unsigned i = 0; i < len; ++i)
	{
		unsigned char c = static_cast<unsigned char>(s[i]);
		if (c < 0x80)       out += static_cast<char>(c);
		else if (c < 0xA0)  out += hi[c - 0x80];
		else if (c < 0xC0)
			out += static_cast<char>(0xC0 | (c >> 6)),
			out += static_cast<char>(0x80 | (c & 0x3F));
		else
			out += static_cast<char>(0xC0 | (c >> 6)),
			out += static_cast<char>(0x80 | (c & 0x3F));
	}
	return out;
}

// ======================================================================
// binary reader helpers
// ======================================================================

inline unsigned rd_le16(unsigned char const* p)
{
	return static_cast<unsigned>(p[0]) | (static_cast<unsigned>(p[1]) << 8);
}
inline unsigned rd_le32(unsigned char const* p)
{
	return static_cast<unsigned>(p[0]) | (static_cast<unsigned>(p[1]) << 8)
		| (static_cast<unsigned>(p[2]) << 16)
		| (static_cast<unsigned>(p[3]) << 24);
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

// ======================================================================
// event model
// ======================================================================

struct SquareMark
{
	unsigned style;
	mstl::string square;
	SquareMark() : style(0) {}
};

struct Arrow
{
	unsigned style;
	mstl::string from, to;
	Arrow() : style(0) {}
};

struct Event
{
	Kind kind;
	double timestampMs;
	unsigned index;          // GotoIndex / symbol / medal
	unsigned classWord;      // opcode 4 class
	unsigned modifier;       // opcode 4 modifier
	unsigned syncCounter;    // opcode 14 counter
	unsigned gotoIndex;      // opcode 3 target
	::mstl::string from, to; // algebraic
	::mstl::vector<SquareMark> marks;
	::mstl::vector<Arrow> arrows;
	::mstl::string text;     // UTF-8
	unsigned language;       // 0 = all, 0x2A = en, 0x35 = de, …
	bool textBefore;
	unsigned moveGlyph, positionEval, prefixGlyph;
	unsigned medalBits;

	Event()
		: kind(Unknown), timestampMs(0.0)
		, index(0), classWord(0), modifier(0), syncCounter(0), gotoIndex(0)
		, language(0), textBefore(false)
		, moveGlyph(0), positionEval(0), prefixGlyph(0), medalBits(0)
	{
	}
};

// checkpoint (opcode 2)
struct Checkpoint
{
	mstl::string white, black, site, event, annotator;
	unsigned whiteElo, blackElo;
	unsigned year, month, day;
	unsigned gameYear, gameMonth, gameDay;
	mstl::vector<mstl::string> treeMoves;
	mstl::vector<unsigned> nodeTimes;

	Checkpoint()
		: whiteElo(0), blackElo(0), year(0), month(0), day(0)
		, gameYear(0), gameMonth(0), gameDay(0)
	{
	}
};

// ======================================================================
// transport: six-bit decode ('?'..'~' = 0x3f..0x7e, 4 chars -> 3 bytes)
// ======================================================================

inline bool strip_sixbit(unsigned char const* p, unsigned n,
							mstl::vector<unsigned char>& record)
{
	record.clear();
	if (n == 0) return false;
	unsigned value = 0, bitcount = 0;
	for (unsigned i = 0; i < n; ++i)
	{
		if (p[i] < 0x3F || p[i] > 0x7E) return false;
		value = (value << 6) | (p[i] - 0x3F);
		bitcount += 6;
		if (bitcount >= 8)
		{
			bitcount -= 8;
			record.push_back(static_cast<unsigned char>((value >> bitcount) & 0xFF));
		}
	}
	if (record.empty()) return false;

	// logical trim for fixed-size opcodes
	if (record.size() >= 4)
	{
		unsigned op = unsigned(record[0]) | (unsigned(record[1]) << 8)
			| (unsigned(record[2]) << 16) | (unsigned(record[3]) << 24);
		unsigned logical = 0;
		if (op == 3 || op == 8 || op == 14) logical = 6;
		else if (op == 4)                  logical = 12;
		if (logical && logical <= record.size())
		{
			for (unsigned i = logical; i < record.size(); ++i)
			{
				if (record[i] != 0) return false;
			}
			record.resize(logical);
		}
	}
	return true;
}

// decode one script command: packet (UTF-16LE "GA\0"), text ("GA:"),
// or bare six-bit body.
inline bool decode_record_bytes(unsigned char const* p, unsigned n,
									mstl::vector<unsigned char>& record)
{
	// binary passthrough: first u32le opcode in 2..17 = pre-decoded record
	if (n >= 4)
	{
		unsigned op = unsigned(p[0]) | (unsigned(p[1]) << 8)
			| (unsigned(p[2]) << 16) | (unsigned(p[3]) << 24);
		if (op >= 2 && op <= 17 && !(op == 6 && n > 4 && p[4] > 0x63)
				&& !(p[1] == 0x00 && p[0] == 0x00))
		{
			if (op == 3 || op == 8 || op == 14)
			{
				if (n >= 6) { record.assign(p, p + 6); return true; }
				return false;
			}
			if (op == 4 && n >= 12) { record.assign(p, p + 12); return true; }
			record.assign(p, p + n);
			return true;
		}
	}

	unsigned begin = 0, len = n;
	if (n < 2) return false;
	if (p[0] == 'G' && p[1] == 0x00)
	{
		// UTF-16LE packet
		if (n < 6 || p[2] != 'A' || p[3] != 0 || p[4] != 0 || p[5] != 0)
			return false;
		begin = 6;
		len = n > begin ? (n - begin) / 2 : 0;
		mstl::vector<unsigned char> chars;
		for (unsigned i = 0; i < len && begin + 2 * i + 1 < n; ++i)
		{
			if (p[begin + 2 * i + 1] != 0) return false;
			chars.push_back(p[begin + 2 * i]);
		}
		return strip_sixbit(chars.empty() ? 0 : &chars[0],
			static_cast<unsigned>(chars.size()), record);
	}
	if (p[0] == 'G' && p[1] == 'A')
	{
		if (n >= 3 && p[2] == ':') { begin = 3; len = n - 3; }
		else                      { begin = 2; len = n - 2; }
		return strip_sixbit(p + begin, len, record);
	}
	return strip_sixbit(p, n, record);
}

// ======================================================================
// CB annotation record parsing (opcode 6)
// ======================================================================

inline bool parse_cb_record(unsigned type, unsigned char const* value,
								unsigned len, Event& ev)
{
	switch (type)
	{
		case 0x02: case 0x82:
		{
			if (len < 2) return false;
			ev.language = rd_be16(value);
			if (len > 2)
				ev.text = cp1252_to_utf8(
					reinterpret_cast<char const*>(value + 2), len - 2);
			ev.textBefore = (type == 0x82);
			ev.kind = Annotation;
			return true;
		}
		case 0x03:
		{
			if (len < 1 || len > 3) return false;
			ev.moveGlyph    = len > 0 ? value[0] : 0;
			ev.positionEval = len > 1 ? value[1] : 0;
			ev.prefixGlyph  = len > 2 ? value[2] : 0;
			ev.kind = Annotation;
			return true;
		}
		case 0x04:
		{
			if (len == 0 || len % 2 != 0) return false;
			for (unsigned i = 0; i + 1 < len; i += 2)
			{
				SquareMark m;
				m.style = value[i];
				m.square = graphic_sq(value[i + 1]);
				ev.marks.push_back(m);
			}
			ev.kind = BoardAction;
			return true;
		}
		case 0x05:
		{
			if (len == 0 || len % 3 != 0) return false;
			for (unsigned i = 0; i + 2 < len; i += 3)
			{
				Arrow a;
				a.style = value[i];
				a.from = graphic_sq(value[i + 1]);
				a.to = graphic_sq(value[i + 2]);
				ev.arrows.push_back(a);
			}
			ev.kind = BoardAction;
			return true;
		}
		case 0x22:
		{
			if (len != 4) return false;
			ev.medalBits = rd_be32(value);
			ev.kind = Annotation;
			return true;
		}
		case 0x25:
		{
			if (len != 4) return false;
			ev.timestampMs = static_cast<double>(rd_be32(value));
			ev.kind = SyncCounter;
			return true;
		}
		default:
			return false;
	}
}

// ======================================================================
// checkpoint parsing (opcode 2)
// ======================================================================

inline bool parse_identity(unsigned char const* p, unsigned len,
								Checkpoint& cp, unsigned& end)
{
	unsigned off = 16;
	if (len < off) return false;
	mstl::string vals[6];
	for (unsigned i = 0; i < 6; ++i)
	{
		if (off >= len) return false;
		unsigned n = p[off]; ++off;
		if (n == 0 || off + n > len) return false;
		vals[i] = cp1252_to_utf8(reinterpret_cast<char const*>(p + off), n - 1);
		off += n;
	}
	cp.white = vals[0];
	if (!vals[1].empty()) { cp.white += ", "; cp.white += vals[1]; }
	cp.black = vals[2];
	if (!vals[3].empty()) { cp.black += ", "; cp.black += vals[3]; }
	cp.site = vals[4];
	cp.event = vals[5];
	end = off;
	return true;
}

inline bool parse_checkpoint_tail(unsigned char const* p, unsigned len,
									Checkpoint& cp)
{
	auto valid = [&len](unsigned char const* pp, unsigned q)
	{
		return q + 5 <= len && pp[q + 2] == 0 && pp[q + 3] == 0
			&& pp[q + 4] == 0 && pp[q] <= 63 && pp[q + 1] <= 63
			&& !(pp[q] == 0 && pp[q + 1] == 0);
	};
	unsigned pos = 0;
	fprintf(stderr, "[tail: len=%u]\n", len);
	while (pos + 10 <= len && !(valid(p, pos) && valid(p, pos + 5)))
		++pos;
	if (pos + 10 > len) return false;
	while (pos + 5 <= len)
	{
		if (p[pos + 2] == 0 && p[pos + 3] == 0 && p[pos + 4] == 0)
		{
			unsigned a = p[pos], b = p[pos + 1];
			if (a <= 63 && b <= 63 && !(a == 0 && b == 0))
			{
				cp.treeMoves.push_back(
					square_algebraic(a) + "-" + square_algebraic(b));
			}
			else break;
			pos += 5;
		}
		else if (p[pos + 2] != 0)
		{
			unsigned count = rd_le16(p + pos + 2);
			if (count == 0 || count > 64) break;
			unsigned q = pos + 4;
			bool ok = true;
			unsigned q2 = q;
			for (unsigned r = 0; ok && q2 + 2 <= len && r < count; ++r)
			{
				unsigned recLen = rd_le16(p + q2);
				if (recLen < 6 || q2 + 2 + recLen > len) { ok = false; break; }
				unsigned type = rd_be32(p + q2 + 2);
				if (type == 0x25 && recLen == 10 && q2 + 10 <= len)
					cp.nodeTimes.push_back(rd_be32(p + q2 + 8));
				q2 += 2 + recLen;
			}
			if (!ok) break;
			pos = q2;
			while (pos + 5 <= len && p[pos] == 0 && p[pos + 1] == 0)
				++pos;
		}
		else
		{
			break;
		}
	}
	return true;
}

// ======================================================================
// high-level: decode one binary record
// ======================================================================

inline Kind decode_event(unsigned char const* record, unsigned len,
							double ms, Event& ev, Checkpoint* cp)
{
	ev = Event();
	ev.timestampMs = ms;
	if (len < 4) return Unknown;
	unsigned opcode = rd_le32(record);
	ev.kind = kind_of_opcode(opcode);

	switch (opcode)
	{
		case 2:
		case 15:
		{
			ev.kind = PositionSync;
			if (!cp || len <= 16) break;
			unsigned idEnd = 0;
			if (parse_identity(record, len, *cp, idEnd))
			{
				if (len >= idEnd + 4)
				{
					unsigned d1 = rd_le32(record + idEnd);
					cp->year = d1 >> 9;
					cp->month = (d1 >> 5) & 0x0F;
					cp->day = d1 & 0x1F;
				}
			}
			if (len < idEnd + 10) break;

			// Elo pair scan
			for (unsigned probe = idEnd; probe + 8 < len; ++probe)
			{
				unsigned a = rd_le16(record + probe);
				unsigned b = rd_le16(record + probe + 2);
				if (a >= 2000 && a <= 2900 && b >= 2000 && b <= 2900
						&& rd_le16(record + probe + 4) <= 2900)
				{
					cp->whiteElo = a;
					cp->blackElo = b;
					for (unsigned dp = probe + 4; dp + 4 < len && dp < probe + 28; ++dp)
					{
						unsigned d2 = rd_le32(record + dp);
						unsigned y = d2 >> 9;
						if (y >= 1990 && y <= 2027)
						{
							cp->gameYear = y;
							cp->gameMonth = (d2 >> 5) & 0x0F;
							cp->gameDay = d2 & 0x1F;
							break;
						}
					}
					break;
				}
			}

			// tree edges + inline collections
			parse_checkpoint_tail(record + idEnd, len - idEnd, *cp);
			break;
		}
		case 3:
		{
			if (len < 8) break;
			ev.gotoIndex = rd_le32(record + 4);
			ev.kind = GotoIndex;
			break;
		}
		case 4:
		{
			if (len < 12) break;
			ev.classWord = rd_le32(record + 4);
			ev.from = square_algebraic(record[8]);
			ev.to = square_algebraic(record[9]);
			ev.modifier = rd_le16(record + 10);
			ev.kind = BoardAction;
			break;
		}
		case 6:
		{
			if (len < 10) break;
			unsigned count = rd_le16(record + 8);
			unsigned q = 10;
			ev.kind = Annotation;
			for (unsigned r = 0; r < count && q + 8 <= len; ++r)
			{
				unsigned recLen = rd_le16(record + q);
				if (recLen < 6 || q + 2 + recLen > len) break;
				unsigned type = rd_be32(record + q + 2);
				unsigned char const* value = record + q + 2 + 6;
				unsigned valueLen = recLen - 6;
				Event sub;
				sub.timestampMs = ms;
				if (parse_cb_record(type, value, valueLen, sub))
				{
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
			{
				ev.syncCounter = rd_le16(record + 4);
				ev.kind = SyncCounter;
			}
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
		case 0x2A: return "en";
		case 0x2B: return "es";
		case 0x31: return "fr";
		case 0x35: return "de";
		case 0x46: return "it";
		case 0x67: return "nl";
		case 0x75: return "pt";
		default:   return "";
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
	{
		char buf[32];
		sprintf(buf, "Step: %u\n", timeline[i]);
		out += buf;
	}
	for (unsigned i = 0; i < events.size(); ++i)
	{
		Event const& e = events[i];
		char buf[64];
		switch (e.kind)
		{
			case BoardAction:
				for (unsigned a = 0; a < e.arrows.size(); ++a)
				{
					sprintf(buf, "Arrow: %d, %u, ",
						static_cast<int>(e.timestampMs + 0.5),
						e.arrows[a].style);
					out += buf;
					out += e.arrows[a].from;
					out += "-";
					out += e.arrows[a].to;
					out += "\n";
				}
				for (unsigned m = 0; m < e.marks.size(); ++m)
				{
					sprintf(buf, "Mark: %d, %u, ",
						static_cast<int>(e.timestampMs + 0.5),
						e.marks[m].style);
					out += buf;
					out += e.marks[m].square;
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
				sprintf(buf, "Reset: %d\n", static_cast<int>(e.timestampMs + 0.5));
				out += buf;
				break;
			case SyncCounter:
				sprintf(buf, "Step: %d\n", static_cast<int>(e.timestampMs + 0.5));
				out += buf;
				break;
		}
	}
	out += "\n";
}

} // namespace cb_media

#endif
