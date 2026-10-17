# ======================================================================
# Scidb App Test - endgame tablebase results under the board
# (tcl/tablebase.tcl)
# ======================================================================
# The server answers below are trimmed copies of real
# tablebase.lichess.ovh answers; the lookup is driven with a stubbed Get.
# ======================================================================

package require tcltest 2.5
package require json

namespace eval ::scidb::test::tb {}

# White: Kg7, Ph7; Black: Ke8, Ph2. White to move wins with h8=Q+.
set ::scidb::test::tb::win {{"checkmate":false,"stalemate":false,"dtz":1,"dtm":17,"category":"win","moves":[
 {"uci":"h7h8q","san":"h8=Q+","dtz":-2,"dtm":-16,"category":"loss"},
 {"uci":"h7h8r","san":"h8=R+","dtz":-2,"dtm":-26,"category":"loss"},
 {"uci":"g7g8","san":"Kg8","dtz":0,"dtm":0,"category":"draw"},
 {"uci":"g7f6","san":"Kf6","dtz":5,"dtm":21,"category":"win"}]}}

tcltest::test tablebase-piece-count {pieces are counted on the FEN board} -body {
	list [::tablebase::pieceCount {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}] \
		[::tablebase::pieceCount {4k3/6KP/8/8/8/8/7p/8 w - - 0 1}] \
		[::tablebase::url {4k3/6KP/8/8/8/8/7p/8 w - - 0 1}]
} -result {32 4 https://tablebase.lichess.ovh/standard?fen=4k3/6KP/8/8/8/8/7p/8_w_-_-_0_1}

tcltest::test tablebase-summary-win {the verdict and the fastest wins} -body {
	::tablebase::summary [::json::json2dict $::scidb::test::tb::win] w
} -result {Tablebase: White wins (mate in 17) - best h8=Q+, h8=R+}

tcltest::test tablebase-summary-loss {a lost position names the winner and the longest defence} -body {
	set a [::json::json2dict {{"dtm":-20,"category":"loss","moves":[
		{"san":"Kd7","dtm":19,"category":"win"},{"san":"Kf8","dtm":15,"category":"win"}]}}]
	::tablebase::summary $a b
} -result {Tablebase: White wins (mate in 20) - best Kd7, Kf8}

tcltest::test tablebase-summary-other {draws, mates and unknowns} -body {
	list \
		[::tablebase::summary [::json::json2dict {{"category":"draw","moves":[{"san":"Kd2","category":"draw"}]}}] w] \
		[::tablebase::summary [::json::json2dict {{"checkmate":true,"category":"loss","moves":[]}}] b] \
		[::tablebase::summary [::json::json2dict {{"category":"cursed-win","dtm":null,"moves":[]}}] w] \
		[::tablebase::summary [::json::json2dict {{"category":"unknown","moves":[]}}] w]
} -result {{Tablebase: Draw - best Kd2} {Tablebase: Checkmate} {Tablebase: White wins, but the 50-move rule draws} {}}

tcltest::test tablebase-board {a 4-piece position shows the verdict under the board; the opening hides it} -setup {
	rename ::application::download::Get ::scidb::test::tb::realGet
	proc ::application::download::Get {url done} {
		set ::scidb::test::tb::asked $url
		after 0 [list {*}$done [list ok 1 data $::scidb::test::tb::win code 200]]
	}
	set ::tablebase::Cache [dict create]
	set delay $::tablebase::Delay
	set ::tablebase::Delay 0
} -body {
	set canv $::application::board::Vars(widget:frame)
	# set the position up in the current game: a new game would need one of
	# the nine game slots, which earlier test files may have used up
	::scidb::game::clear {4k3/6KP/8/8/8/8/7p/8 w - - 0 1}
	update
	::tablebase::positionChanged $canv
	after 100 {set ::scidb::test::tb::w 1}; vwait ::scidb::test::tb::w
	set shown [$canv.tablebase cget -text]
	set placed [expr {[winfo manager $canv.tablebase] eq "place"}]
	::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	update
	::tablebase::positionChanged $canv
	list $shown $placed [winfo manager $canv.tablebase] [string match *4k3/6KP* $::scidb::test::tb::asked]
} -cleanup {
	rename ::application::download::Get {}
	rename ::scidb::test::tb::realGet ::application::download::Get
	set ::tablebase::Delay $delay
} -result {{Tablebase: White wins (mate in 17) - best h8=Q+, h8=R+} 1 {} 1}

tcltest::cleanupTests
