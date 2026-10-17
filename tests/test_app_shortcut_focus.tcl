# ======================================================================
# Scidb App Test - ChessBase scheme with focus on a pane control
# ======================================================================
# Run 14: after choosing the ChessBase scheme, Ctrl+F did not flip the
# board. Focus was on the media seek slider, which clicking the board
# does not move, and only the board and notation carried the scheme.
# ======================================================================

package require tcltest 2.5

tcltest::test shortcut-focus-pane {board-tab controls get the scheme on focus} -setup {
	set w [ttk::scale .application.nb.board.shortcutProbe]
} -body {
	set ::application::Options(shortcut:scheme) chessbase
	::application::ShortcutEditingFocus $w
	set r [lindex [bindtags $w] 0]
	set ::application::Options(shortcut:scheme) chesswiz
	list $r [bind ChessBaseBoard <Control-f>]
} -cleanup {
	destroy $w
	set ::application::Options(shortcut:scheme) chesswiz
} -result {ChessBaseBoard {}}

tcltest::cleanupTests
