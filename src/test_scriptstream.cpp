// test_scriptstream — unit tests for the ChessBase media script-stream
// decoder in tcl/tcl_scriptstream.h.
//
// Every assertion derives from findings verified against the CBM 168
// fixture corpus and documented in CHESSBASE_MEDIA_RE.md.

#include "tcl/tcl_scriptstream.h"

#include "m_string.h"
#include "m_vector.h"

#include <cstdio>
#include <cstring>

static int g_pass = 0;
static int g_fail = 0;

static void check(char const* what, bool ok)
{
	if (ok)
	{
		++g_pass;
	}
	else
	{
		++g_fail;
		std::printf("FAIL: %s\n", what);
	}
}

// build a UTF-16LE wide packet from six-bit chars
static mstl::string wide_packet(char const* chars)
{
	mstl::string packet;
	packet += 'G'; packet += '\0';
	packet += 'A'; packet += '\0';
	packet += '\0'; packet += '\0';
	for (unsigned i = 0; chars[i]; ++i)
	{
		packet += chars[i];
		packet += '\0';
	}
	return packet;
}

// decode a flat text command into an Event
static void feed_text(cb_media::Event& ev, char const* command)
{
	mstl::vector<unsigned char> record;
	if (!cb_media::decode_record_bytes(
			reinterpret_cast<unsigned char const*>(command),
			static_cast<unsigned>(strlen(command)), record))
	{
		ev.kind = cb_media::Unknown;
		return;
	}
	cb_media::decode_event(&record[0],
		static_cast<unsigned>(record.size()), 0.0, ev, 0);
}

// decode a UTF-16LE packet into an Event
static void feed_packet(cb_media::Event& ev, char const* chars)
{
	mstl::string packet = wide_packet(chars);
	mstl::vector<unsigned char> record;
	if (!cb_media::decode_record_bytes(
			reinterpret_cast<unsigned char const*>(packet.data()),
			static_cast<unsigned>(packet.size()), record))
	{
		ev.kind = cb_media::Unknown;
		return;
	}
	cb_media::decode_event(&record[0],
		static_cast<unsigned>(record.size()), 0.0, ev, 0);
}

// build a binary record from a hex string
static mstl::vector<unsigned char> build_record(char const* hex)
{
	mstl::vector<unsigned char> r;
	bool high = true;
	for (unsigned i = 0; hex[i] != 0; ++i)
	{
		char c = hex[i];
		unsigned v;
		if (c >= '0' && c <= '9') v = static_cast<unsigned>(c - '0');
		else if (c >= 'a' && c <= 'f') v = static_cast<unsigned>(c - 'a' + 10);
		else if (c >= 'A' && c <= 'F') v = static_cast<unsigned>(c - 'A' + 10);
		else continue;
		if (high)
			r.push_back(static_cast<unsigned char>(v << 4));
		else
			r.back() |= static_cast<unsigned char>(v);
		high = !high;
	}
	return r;
}

static void feed_binary(cb_media::Event& ev,
							mstl::vector<unsigned char> const& record)
{
	if (record.empty())
	{
		ev.kind = cb_media::Unknown;
		return;
	}
	cb_media::decode_event(&record[0],
		static_cast<unsigned>(record.size()), 0.0, ev, 0);
}

// squares ----------------------------------------------------------------

static void test_squares()
{
	check("g-square a1", cb_media::graphic_sq(1) == "a1");
	check("g-square h8", cb_media::graphic_sq(64) == "h8");
	check("g-square 0 = none", cb_media::graphic_sq(0).empty());
	check("g-square 26 = d2", cb_media::graphic_sq(26) == "d2");
	check("g-square 25 = d1", cb_media::graphic_sq(25) == "d1");
	check("g-square 4 = a4", cb_media::graphic_sq(4) == "a4");
	check("b-square 0 = a1", cb_media::square_algebraic(0) == "a1");
	check("b-square 8 = b1", cb_media::square_algebraic(8) == "b1");
	check("b-square 17 = c2", cb_media::square_algebraic(17) == "c2");
	check("b-square 63 = h8", cb_media::square_algebraic(63) == "h8");
}

// transport ---------------------------------------------------------------

static void test_sync_counter()
{
	// "B_????w????" decodes to the 6-byte Sync record with counter 0x0E
	cb_media::Event ev;
	feed_text(ev, "B_????w????");
	check("sync kind", ev.syncCounter == 0x0E);
	check("sync counter = 14", ev.syncCounter == 0x0E);

	cb_media::Event ev2;
	feed_packet(ev2, "B_????w????");
	check("sync kind (packet)", ev2.syncCounter == 0x0E);
	check("sync counter (packet)", ev2.syncCounter == 0x0E);
}

static void test_goto_index()
{
	cb_media::Event ev;
	auto record = build_record("0300000010000000");
	feed_binary(ev, record);
	check("goto kind", ev.gotoIndex == 16);
	check("goto index = 16", ev.gotoIndex == 16);
}

static void test_board_action()
{
	// class 0x200, file-major squares e1 (32), c1 (16), modifier 1
	cb_media::Event ev;
	auto record = build_record(
		"04000000000200002010010000");
	feed_binary(ev, record);
	check("board kind", ev.kind == cb_media::BoardAction);
	check("board class = 0x200", ev.classWord == 0x200);
	check("board from = e1", ev.from == "e1");
	check("board to = c1", ev.to == "c1");
	check("board modifier = 1", ev.modifier == 1);
}

// annotation --------------------------------------------------------------

static void test_annotation_text()
{
	// text-after, language de (0x35), cp1252 "weißfeldriger Läufer"
	cb_media::Event ev;
	auto record = build_record(
		"0600000000000000"  // opcode 6, reserved 0
		"0100"              // count 1
		"1c00"              // recLen 28
		"00000002"          // type 2 = text-after
		"1c00"              // echoed
		"0035"              // language de
		"776569df66656c647269676572204ca4756665722e"  // cp1252 body
		"0000"              // trailing
	);
	feed_binary(ev, record);
	check("text kind", ev.kind == cb_media::Annotation);
	check("text language = de", ev.language == 0x35);
	check("text not before", !ev.textBefore);
	check("text body", ev.text.find("feldriger L") != mstl::string::npos);
}

static void test_medal()
{
	// medal: count 1, recLen 10, type 0x22, echoed 10, medal = 1 = Best Game
	cb_media::Event ev;
	auto record = build_record(
		"0600000000000000"  // opcode 6, reserved 0
		"0100"              // count 1
		"0a00"              // recLen 10
		"00000022"          // type 0x22 = medal
		"0a00"              // echoed
		"00000001"          // medal bits
	);
	feed_binary(ev, record);
	check("medal kind = Annotation", ev.kind == cb_media::Annotation);
	check("medal bits = 1 (Best Game)", ev.medalBits == 1);
}

static void test_markers()
{
	// file-major one-based: 0x1a = d2, 0x19 = d1, 0x04 = a4
	cb_media::Event ev;
	auto record = build_record(
		"0600000000000000"  // opcode 6
		"0100"              // count 1
		"0c00"              // recLen 12
		"00000005"          // type 5 = arrow
		"0c00"              // echoed
		"021a19020419"      // (style 2, 0x1a -> 0x19), (style 2, 0x04, 0x19)
	);
	feed_binary(ev, record);
	
	check("arrow count", ev.arrows.size() == 2);
	if (ev.arrows.size() == 2)
	{
		check("arrow 1 = d2-d1", ev.arrows[0].from == "d2"
				&& ev.arrows[0].to == "d1");
		check("arrow 1 style", ev.arrows[0].style == 2);
		check("arrow 2 = a4-d1", ev.arrows[1].from == "a4"
				&& ev.arrows[1].to == "d1");
	}
}

// checkpoint ----------------------------------------------------------------

static void test_checkpoint()
{
	// Set Game: identity strings + date + Elo + game date + tree edge
	mstl::vector<unsigned char> r;
	unsigned char head[16] =
		{ 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
	for (unsigned i = 0; i < 16; ++i) r.push_back(head[i]);

	char const* names[6] =
		{ "Navara", "David", "Adams", "Michael", "Biel", "48th Biel Festival 2015" };
	for (unsigned i = 0; i < 6; ++i)
	{
		unsigned n = static_cast<unsigned>(strlen(names[i])) + 1;
		r.push_back(static_cast<unsigned char>(n));
		for (unsigned c = 0; c < n; ++c) r.push_back(names[i][c]);
	}
	// identity date 2015-00-00
	r.push_back(0x00); r.push_back(0xBE); r.push_back(0x0F); r.push_back(0x00);
	// post-date: [00 00] Elo-pair(white 2724 = 0x0AA4, black 2740 = 0x0AB4)
	//              [00 00] game date 2015-07-25 = 0x000FBEF9
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0xA4); r.push_back(0x0A); r.push_back(0xB4); r.push_back(0x0A);
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0xF9); r.push_back(0xBE); r.push_back(0x0F); r.push_back(0x00);
	// alignment + tree edge c2-c4 = (17, 19) + pad
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0x11); r.push_back(0x13); r.push_back(0x00); r.push_back(0x00);
	r.push_back(0x00);

	cb_media::Event ev;
	cb_media::Checkpoint cp;
	cb_media::decode_event(&r[0], static_cast<unsigned>(r.size()), 0.0, ev, &cp);
	check("setgame kind", !cp.treeMoves.empty());
	check("white", cp.white == "Navara, David");
	check("black", cp.black == "Adams, Michael");
	check("site", cp.site == "Biel");
	check("event", cp.event == "48th Biel Festival 2015");
	check("elo white", cp.whiteElo == 2724);
	check("elo black", cp.blackElo == 2740);
	check("identity year", cp.year == 2015);
	check("game date", cp.gameYear == 2015 && cp.gameMonth == 7 && cp.gameDay == 25);
	check("tree edge", cp.treeMoves.size() == 2
		&& cp.treeMoves[0] == "c2-c4" && cp.treeMoves[1] == "e7-e6");
}

static void test_tree_edges()
{
	// the first 18 edges of the published Navara-Adams round-6 score,
	// file-major, verified 18/18 in the RE document
	char const* edges[18] =
	{
		"c2-c4", "e7-e6", "b1-c3", "d7-d5", "d2-d4", "g8-f6",
		"c4-d5", "e6-d5", "c1-g5", "c7-c6", "e2-e3", "h7-h6",
		"g5-h4", "f8-e7", "d1-c2", "b8-d7", "f1-d3", "f6-h5",
	};
	char const* codes[18] =
	{
		"11 13", "26 25", "08 12", "1e 1c", "19 1b", "37 2d",
		"13 1c", "25 1c", "10 34", "16 15", "21 22", "3e 3d",
		"34 3b", "2f 26", "18 11", "0f 1e", "28 1a", "2d 3c",
	};
	for (unsigned i = 0; i < 18; ++i)
	{
		unsigned v[2] = { 0, 0 };
		unsigned idx = 0;
		for (unsigned j = 0; codes[i][j] != 0 && idx < 2; ++j)
		{
			char c2 = codes[i][j];
			unsigned v2;
			if (c2 >= '0' && c2 <= '9') v2 = static_cast<unsigned>(c2 - '0');
			else if (c2 >= 'a' && c2 <= 'f') v2 = static_cast<unsigned>(c2 - 'a' + 10);
			else if (c2 >= 'A' && c2 <= 'F') v2 = static_cast<unsigned>(c2 - 'A' + 10);
			else continue;	// skip space, dash, etc.
			v[idx] = v[idx] * 16 + v2;
			++idx;
		}
		mstl::string edge = cb_media::square_algebraic(v[0]) + "-"
			+ cb_media::square_algebraic(v[1]);
		char label[48];
		sprintf(label, "tree edge %u: %s", i, edges[i]);
		check(label, edge == edges[i]);
	}
}

// writer ----------------------------------------------------------------

static void test_write_board_sync()
{
	cb_media::Event arrow;
	arrow.kind = cb_media::BoardAction;
	arrow.timestampMs = 45200;
	arrow.from = "c8";
	arrow.to = "e6";
	arrow.arrows.push_back(cb_media::Arrow());
	arrow.arrows.back().style = 4;
	arrow.arrows.back().from = "c8";
	arrow.arrows.back().to = "e6";

	cb_media::Event comment;
	comment.kind = cb_media::Annotation;
	comment.timestampMs = 51000;
	comment.text = "would transpose to a Shirov-Bacrot 2014 game";

	mstl::vector<unsigned> timeline;
	timeline.push_back(30642);
	timeline.push_back(37142);

	mstl::vector<cb_media::Event> events;
	events.push_back(arrow);
	events.push_back(comment);

	mstl::string out;
	cb_media::write_board_sync(out, "V05", timeline, events);

	check("[BoardSync opens]", out.find("[BoardSync \"V05\"]") != mstl::string::npos);
	check("Step marks", out.find("Step: 30642\n") != mstl::string::npos
			&& out.find("Step: 37142\n") != mstl::string::npos);
	check("Arrow line", out.find("Arrow: 45200, 4, c8-e6\n")
			!= mstl::string::npos);
	check("Comment line", out.find("Comment: 51000, post, , \"would transpose"
			" to a Shirov-Bacrot 2014 game\"\n") != mstl::string::npos);
}

int main()
{
	test_squares();
	test_sync_counter();
	test_goto_index();
	test_board_action();
	test_annotation_text();
	test_medal();
	test_markers();
	test_checkpoint();
	test_tree_edges();
	test_write_board_sync();

	std::printf("%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}