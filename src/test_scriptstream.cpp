// test_scriptstream — unit tests for the ChessBase media script-stream
// decoder in tcl/tcl_scriptstream.h.
//
// Every assertion derives from findings verified against the CBM 168
// fixture corpus and documented in CHESSBASE_MEDIA_RE.md:
//
//   * the six-bit transport (chars '?'..'~' = 0x3f + value, 4 chars ->
//     3 bytes) with the logical trim for fixed-size opcodes;
//   * the packet form ("GA\0" UTF-16LE wrapper) and the text form
//     ("GA:" prefix) both reach the same record;
//   * opcode 3 = GotoIndex (u32le node index);
//   * opcode 4 = board action, file-major squares (a1 = 0, b1 = 8);
//   * opcode-06 annotation records: text-after/before with language
//     bytes (0x2A en / 0x35 de), symbols, styled marks/arrows one-based
//     file-major (0 = none, h8 = 64), medal bitmask (1 = Best Game);
//   * Set Game checkpoints: identity strings, the Elo pair (white
//     first), the full-precision game date, and the file-major edge
//     stream (c2-c4 = 17,19 per the published Navara-Adams tree).
//
// Build (from src/): make test_scriptstream
// Run: ./test_scriptstream

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
	cb_media::decode_event(record.empty() ? 0 : &record[0],
		static_cast<unsigned>(record.size()), 0.0, ev, 0);
}

static void feed_packet(cb_media::Event& ev, char const* chars)
{
	// "GA\0" + the six-bit chars as UTF-16LE
	mstl::string packet;
	packet += 'G'; packet += '\0';
	packet += 'A'; packet += '\0';
	packet += '\0'; packet += '\0';
	for (unsigned i = 0; chars[i] != 0; ++i)
	{
		packet += chars[i];
		packet += '\0';
	}
	mstl::vector<unsigned char> record;
	if (!cb_media::decode_record_bytes(
			reinterpret_cast<unsigned char const*>(packet.data()),
			static_cast<unsigned>(packet.size()), record))
	{
		ev.kind = cb_media::Unknown;
		return;
	}
	cb_media::decode_event(record.empty() ? 0 : &record[0],
		static_cast<unsigned>(record.size()), 0.0, ev, 0);
}

static void test_squares()
{
	// corner invariants of the one-based graphics encoding
	check("g-square a1 = 1", cb_media::graphic_square_algebraic(1) == "a1");
	check("g-square h8 = 64", cb_media::graphic_square_algebraic(64) == "h8");
	check("g-square 0 = none", cb_media::graphic_square_algebraic(0).empty());
	check("g-square 26 = d2", cb_media::graphic_square_algebraic(26) == "d2");
	check("g-square 25 = d1", cb_media::graphic_square_algebraic(25) == "d1");
	check("g-square 4 = a4", cb_media::graphic_square_algebraic(4) == "a4");
	// zero-based board squares (node table / opcode 4)
	check("b-square 0 = a1", cb_media::square_algebraic(0) == "a1");
	check("b-square 8 = b1", cb_media::square_algebraic(8) == "b1");
	check("b-square 17 = c2", cb_media::square_algebraic(17) == "c2");
	check("b-square 63 = h8", cb_media::square_algebraic(63) == "h8");
}

static void test_sync_counter()
{
	// "B_????w????" (the verified .txt command) -> 0e0000000e00
	cb_media::Event ev;
	feed_text(ev, "B_????w????");
	check("sync kind", ev.kind == cb_media::SyncCounter);
	check("sync counter = 14", ev.syncCounter == 0x0E);

	// the same command in the packet form keeps the semantics
	cb_media::Event ev2;
	feed_packet(ev2, "B_????w????");
	check("sync kind (packet)", ev2.kind == cb_media::SyncCounter);
	check("sync counter (packet)", ev2.syncCounter == 0x0E);
}

static void test_goto_index()
{
	cb_media::Event ev;
	mstl::vector<unsigned char> record;
	unsigned char cmd[6] = { 0x03, 0x00, 0x00, 0x00, 0x10, 0x00 };
	for (unsigned i = 0; i < 6; ++i) record.push_back(cmd[i]);
	cb_media::decode_event(&record[0], static_cast<unsigned>(record.size()),
		21.5, ev, 0);
	check("goto kind", ev.kind == cb_media::GotoIndex);
	check("goto index = 16", ev.gotoIndex == 16);
	check("goto timestamp kept", ev.timestampMs == 21.5);
}

static void test_board_action()
{
	// class 0x200, file-major squares e1 (32), c1 (16), modifier 1
	cb_media::Event ev;
	mstl::vector<unsigned char> record;
	unsigned char cmd[12] = { 0x04, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00,
		0x20, 0x10, 0x01, 0x00 };
	for (unsigned i = 0; i < 12; ++i) record.push_back(cmd[i]);
	cb_media::decode_event(&record[0], static_cast<unsigned>(record.size()),
		84.142, ev, 0);
	check("board kind", ev.kind == cb_media::BoardAction);
	check("board class = 0x200", ev.classWord == 0x200);
	check("board from = e1", ev.from == "e1");
	check("board to = c1", ev.to == "c1");
	check("board modifier = 1", ev.modifier == 1);
	check("board timestamp kept", ev.timestampMs == 84.142);
}

static void test_annotation_text()
{
	// text-after-move, language de (0x35), cp1252 "weißfeldriger Läufer"
	cb_media::Event ev;
	mstl::vector<unsigned char> record;
	unsigned char head[10] = { 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x01, 0x00 };
	for (unsigned i = 0; i < 10; ++i) record.push_back(head[i]);
	char const* body = "\x00\x35wei\xdfl""eldriger L\xe4ufer";
	unsigned blen = static_cast<unsigned>(strlen(body));
	unsigned recLen = 6 + blen;
	record.push_back(static_cast<unsigned char>(recLen & 0xFF));
	record.push_back(static_cast<unsigned char>((recLen >> 8) & 0xFF));
	record.push_back(0x00); record.push_back(0x00); record.push_back(0x00);
	record.push_back(0x02);
	record.push_back(static_cast<unsigned char>(recLen & 0xFF));
	record.push_back(static_cast<unsigned char>((recLen >> 8) & 0xFF));
	for (unsigned i = 0; i < blen; ++i) record.push_back(body[i]);

	cb_media::decode_event(&record[0], static_cast<unsigned>(record.size()),
		0.0, ev, 0);
	check("text kind", ev.kind == cb_media::Annotation);
	check("text language = de", ev.language == 0x35);
	check("text not before", !ev.textBefore);
	check("text body (utf8)", ev.text ==
			"wei\xc3\x9f" "feldriger L\xc3\xa4" "ufer");
}

static void test_medal()
{
	cb_media::Event ev;
	mstl::vector<unsigned char> record;
	unsigned char head[10] = { 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x01, 0x00 };
	for (unsigned i = 0; i < 10; ++i) record.push_back(head[i]);
	// [u16 len=10][u32be type=0x22][u16be echoed=10][u32be medal=1]
	unsigned char rec[10] = { 0x0a, 0x00, 0x00, 0x00, 0x00, 0x22, 0x0a, 0x00,
		0x00, 0x00 };
	for (unsigned i = 0; i < 10; ++i) record.push_back(rec[i]);
	record.push_back(0x00); record.push_back(0x00); record.push_back(0x00);
	record.push_back(0x01);

	cb_media::decode_event(&record[0], static_cast<unsigned>(record.size()),
		0.0, ev, 0);
	check("medal kind", ev.kind == cb_media::Annotation);
	check("medal bits = 1 (Best Game)", ev.medalBits == 1);
}

static void test_checkpoint()
{
	// build a Set Game record: identity strings + Elo + date + one edge
	mstl::vector<unsigned char> r;
	unsigned char head[16] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
	for (unsigned i = 0; i < 16; ++i) r.push_back(head[i]);
	char const* names[6] = { "Navara", "David", "Adams", "Michael", "Biel",
		"48th Biel Festival 2015" };
	for (unsigned i = 0; i < 6; ++i)
	{
		unsigned n = static_cast<unsigned>(strlen(names[i])) + 1;
		r.push_back(static_cast<unsigned char>(n));
		for (unsigned c2 = 0; c2 < n; ++c2) r.push_back(names[i][c2]);
	}
	// identity packed date: 2015-00-00 = 0x000FBE00 (LE: 00 be 0f 00)
	r.push_back(0x00); r.push_back(0xBE); r.push_back(0x0F); r.push_back(0x00);
	// post-date at the corpus layout: [00 00] white-Elo black-Elo [00 00]
	// then the game date 2015-07-25 = 0x000FBEF9
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0xD4); r.push_back(0x0A); r.push_back(0xC4); r.push_back(0x0A);
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0xF9); r.push_back(0xBE); r.push_back(0x0F); r.push_back(0x00);
	// alignment then the single tree edge c2-c4 = (17, 19) + zero pad
	r.push_back(0x00); r.push_back(0x87); r.push_back(0x00);
	r.push_back(0x00); r.push_back(0x00);
	r.push_back(0x11); r.push_back(0x13); r.push_back(0x00); r.push_back(0x00);
	r.push_back(0x00);

	cb_media::Event ev;
	cb_media::Checkpoint cp;
	cb_media::decode_event(&r[0], static_cast<unsigned>(r.size()), 0.0, ev, &cp);
	check("setgame kind", ev.kind == cb_media::PositionSync);
	check("white = Navara, David", cp.white == "Navara, David");
	check("black = Adams, Michael", cp.black == "Adams, Michael");
	check("site = Biel", cp.site == "Biel");
	check("event", cp.event == "48th Biel Festival 2015");
	check("elo white = 2724", cp.whiteElo == 2724);
	check("elo black = 2740", cp.blackElo == 2740);
	check("game date = 2015-07-25", cp.gameYear == 2015 && cp.gameMonth == 7
			&& cp.gameDay == 25);
	check("identity year = 2015", cp.year == 2015);
	check("tree edge = c2-c4", cp.treeMoves.size() == 1
			&& cp.treeMoves[0] == "c2-c4");
}

static void check_edge(unsigned i, char const* got, char const* want)
{
	char label[64];
	sprintf(label, "tree edge %u (file-major) = %s", i, want);
	check(label, strcmp(got, want) == 0);
}

static void test_tree_edges_match_published_game()
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
	cb_media::Checkpoint cp;
	for (unsigned i = 0; i < 18; ++i)
	{
		unsigned v[2] = { 0, 0 };
		unsigned idx = 0;
		for (unsigned j = 0; codes[i][j] != 0 && idx < 2; ++j)
		{
			char c2 = codes[i][j];
			unsigned v2;
			if (c2 >= '0' && c2 <= '9') v2 = static_cast<unsigned>(c2 - '0');
			else v2 = static_cast<unsigned>(c2 - 'a' + 10);
			v[idx] = v[idx] * 16 + v2;
			++idx;
		}
		mstl::string edge = cb_media::square_algebraic(v[0]) + "-"
			+ cb_media::square_algebraic(v[1]);
		cp.treeMoves.push_back(edge);
		check_edge(i, cp.treeMoves[i].c_str(), edges[i]);
	}
}

static void test_boardsync_writer()
{
	cb_media::Event arrow;
	arrow.kind = cb_media::BoardAction;
	arrow.timestampMs = 45200;
	arrow.classWord = 0x80;
	arrow.from = "c8";
	arrow.to = "e6";
	arrow.arrows.push_back(cb_media::Arrow());
	arrow.arrows.back().style = 4;
	arrow.arrows.back().from = "c8";
	arrow.arrows.back().to = "e6";

	cb_media::Event comment;
	comment.kind = cb_media::Annotation;
	comment.timestampMs = 51000;
	comment.language = 0;
	comment.text = "would transpose to a Shirov-Bacrot 2014 game";

	mstl::vector<cb_media::Event> events;
	events.push_back(arrow);
	events.push_back(comment);

	mstl::vector<unsigned> timeline;
	timeline.push_back(30642);
	timeline.push_back(37142);

	mstl::string out;
	cb_media::write_board_sync(out, "V05", timeline, events);

	check("BoardSync opens", out.find("[BoardSync \"V05\"]") != mstl::string::npos);
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
	test_checkpoint();
	test_tree_edges_match_published_game();
	test_boardsync_writer();

	std::printf("%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}