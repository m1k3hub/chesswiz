# ======================================================================
# Scidb App Test — chess diagrams for the report pane (tcl/ai-diagram.tcl)
# ======================================================================
# The board -> 8x8 grid expansion (start position, a position with every
# piece type), -flip reversing the diagram, -highlight marking exactly
# the named squares, the caption/marker/size bits of the markup, the
# short HTML error line for a bad FEN (never a Tcl error), and the
# fragment rendering in the real report pane through
# ::application::ai::showReport.
# ======================================================================
# Modelled on tests/test_app_ai_tier.tcl. The board markup is checked
# through its cell attributes (every square cell carries the board
# background plus width/height, pieces carry two dedicated ink colors)
# rather than through any widget state; the last test drives the real
# pane under the app's xvfb session. The module is sourced when the app
# does not ship it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::diagram {}

# --- the positions of each scenario ---------------------------------------

proc ::scidb::test::diagram::StartFen {} {
	return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}

# Every piece type on one board, Black to move.
proc ::scidb::test::diagram::AllPiecesFen {} {
	return "k6K/1q1Q1b1B/2rR2nN/3p2P1/8/8/8/8 b - - 0 1"
}

# An almost empty board with pawns on d5, e4 and f5 for the highlight
# checks; Black to move is exercised through the caption test instead.
proc ::scidb::test::diagram::SparseFen {} {
	return "8/8/8/3P1p2/4P3/8/8/8 w - - 0 1"
}

proc ::scidb::test::diagram::NoSideFen {} {
	return "4k3/8/8/8/8/8/8/4K3 - - - 0 1"
}

# --- the module (sourced when the app does not ship it yet) ---------------

if {[llength [info commands ::ai::diagram::html]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-diagram.tcl]
}

# --- markup readers ---------------------------------------------------------

# The piece glyphs of a fragment, in reading order (display row by row,
# left to right): the pieces are the only text rendered in one of the
# two piece ink colors; coordinates and the side dot use their own.
proc ::scidb::test::diagram::PiecesOf {html} {
	set out {}
	foreach {all glyph} [regexp -all -inline \
		{<font size="\d+" color="#(?:3a3a3a|1e1e1e)">([^<]+)</font>} $html] {
		lappend out $glyph
	}
	return $out
}

# The background of every board cell (width=height=<px>), in reading
# order: 36 for e4 on an unflipped -coords 0 board, say.
proc ::scidb::test::diagram::SquareBgs {html px} {
	set re [string map [list @px@ $px] {<td([^>]*width="@px@" height="@px@"[^>]*)>}]
	set out {}
	foreach {all attrs} [regexp -all -inline $re $html] {
		if {[regexp {bgcolor="([^"]+)"} $attrs - bg]} { lappend out $bg } else { lappend out {} }
	}
	return $out
}

# The file letters of the bottom coordinate row, left to right.
proc ::scidb::test::diagram::FileLetters {html} {
	set out {}
	foreach {all letter} [regexp -all -inline {color="#494034">([a-h])</font>} $html] {
		lappend out $letter
	}
	return $out
}

proc ::scidb::test::diagram::Count {list value} {
	set n 0
	foreach v $list { if {$v eq $value} { incr n } }
	return $n
}

# --- grid: the 8x8 expansion -------------------------------------------------

tcltest::test diagram-grid-start {the start position expands rank 8 first} -body {
	::ai::diagram::grid [::scidb::test::diagram::StartFen]
} -result {rnbqkbnr pppppppp ........ ........ ........ ........ PPPPPPPP RNBQKBNR}

tcltest::test diagram-grid-all-pieces {a position with every piece type expands as written; grid accepts a bare placement} -body {
	list [::ai::diagram::grid [::scidb::test::diagram::AllPiecesFen]] \
		[::ai::diagram::grid "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"]
} -result {{k......K .q.Q.b.B ..rR..nN ...p..P. ........ ........ ........ ........} {rnbqkbnr pppppppp ........ ........ ........ ........ PPPPPPPP RNBQKBNR}}

tcltest::test diagram-grid-invalid {an unparseable FEN answers {} instead of raising} -body {
	list [::ai::diagram::grid "this is not a FEN"] \
		[::ai::diagram::grid "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP"] \
		[::ai::diagram::grid "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR9 w"]
} -result {{} {} {}}

# --- html: flip, coords, highlight, caption, marker --------------------------

tcltest::test diagram-html-flip {-flip reverses the diagram: pieces and files go back to front} -body {
	set start [::scidb::test::diagram::StartFen]
	set up [::ai::diagram::html $start]
	set down [::ai::diagram::html $start -flip 1]
	list \
		[expr {[::scidb::test::diagram::PiecesOf $down]
			eq [lreverse [::scidb::test::diagram::PiecesOf $up]]}] \
		[expr {[::scidb::test::diagram::PiecesOf $up] ne {}}] \
		[::scidb::test::diagram::FileLetters $up] \
		[::scidb::test::diagram::FileLetters $down]
} -result {1 1 {a b c d e f g h} {h g f e d c b a}}

tcltest::test diagram-html-highlight {-highlight marks exactly the named squares; junk tokens are ignored} -body {
	set fen [::scidb::test::diagram::SparseFen]
	set a [::ai::diagram::html $fen -coords 0 -highlight {e4 d5}]
	set b [::ai::diagram::html $fen -coords 0 -highlight {E4 x9 d5 qq}]
	set hi $::ai::diagram::Hi
	set bgA [::scidb::test::diagram::SquareBgs $a 40]
	set bgB [::scidb::test::diagram::SquareBgs $b 40]
	list [llength $bgA] \
		[expr {[lindex $bgA 27] eq $hi}] \
		[expr {[lindex $bgA 36] eq $hi}] \
		[expr {$bgB eq $bgA}] \
		[::scidb::test::diagram::Count $bgA $hi] \
		[::scidb::test::diagram::Count $bgA $::ai::diagram::Light] \
		[::scidb::test::diagram::Count $bgA $::ai::diagram::Dark] \
		[expr {[lindex $bgA 56] eq $::ai::diagram::Dark}]
} -result {64 1 1 1 2 30 32 1}

tcltest::test diagram-html-caption-marker-size {the caption is escaped, the dot follows the side, -size scales the cells} -body {
	set start [::scidb::test::diagram::StartFen]
	set white [::ai::diagram::html $start \
		-caption {Kasparov - Topalov, Wijk aan Zee 1999, after 24.Rxd4 <b>!} ]
	set black [::ai::diagram::html [::scidb::test::diagram::AllPiecesFen]]
	set none [::ai::diagram::html [::scidb::test::diagram::NoSideFen]]
	set small [::ai::diagram::html $start -size 160 -coords 0]
	list \
		[string match {*Kasparov - Topalov, Wijk aan Zee 1999, after 24.Rxd4 &lt;b&gt;!*} $white] \
		[string match *color="#f5f5f5"* $white] \
		[string match *color="#101010"* $black] \
		[expr {![string match {*25CF*} $none]
			&& ![string match {*color="#f5f5f5"*} $none]
			&& ![string match {*color="#101010"*} $none]}] \
		[llength [::scidb::test::diagram::SquareBgs $small 20]] \
		[llength [::scidb::test::diagram::SquareBgs $small 40]]
} -result {1 1 1 1 64 0}

tcltest::test diagram-html-invalid-fen {a bad FEN (and a bad call) answers a short error line, never a Tcl error} -body {
	set h1 [::ai::diagram::html "this is not a FEN"]
	set h2 [::ai::diagram::html "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP"]
	set h3 [::ai::diagram::html "k6K/8/8/8/8/8/8/8 x"]
	set h4 [::ai::diagram::html [::scidb::test::diagram::StartFen] -nope 1]
	set h5 [::ai::diagram::html [::scidb::test::diagram::StartFen] -size soon]
	set h6 [::ai::diagram::html [::scidb::test::diagram::StartFen] -flip]
	list \
		[string match {*<b>Invalid FEN:</b>*} $h1] \
		[string match {*<b>Invalid FEN:</b>*} $h2] \
		[string match {*bad side to move*} $h3] \
		[string match {*<b>diagram:</b>*} $h4] \
		[string match {*<b>diagram:</b>*} $h5] \
		[string match {*<b>diagram:</b>*} $h6] \
		[expr {![string match *<table* $h1$h2$h3$h4$h5$h6]}]
} -result {1 1 1 1 1 1 1}

# --- the real report pane -----------------------------------------------------

# The pane test drives the real showReport: it needs the app commands.
tcltest::testConstraint reportPane [expr {
	[llength [info commands ::application::ai::showReport]]
	&& [llength [info commands ::application::report::showHtmlData]]}]

tcltest::test diagram-renders-in-report-pane {the fragment loads into the tkhtml report pane without errors} -constraints {
	reportPane
} -body {
	set frag [::ai::diagram::html [::scidb::test::diagram::StartFen] \
		-size 240 -highlight {e4 d5} \
		-caption {Kasparov - Topalov, Wijk aan Zee 1999, after 24.Rxd4}]
	set page "<html><body><p><b>Position</b></p>$frag</body></html>"
	set w [::application::ai::showReport .application "AI: diagram test" $page]
	update
	list [expr {$w ne ""}] [winfo exists $w]
} -result {1 1}

::tcltest::cleanupTests
return
