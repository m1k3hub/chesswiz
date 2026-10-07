# ======================================================================
# Scidb App Test — runtime regressions from the 2026-09-24 Tcl audit
#
# Each case exercises a code path that used to raise only when reached
# (undefined variable, invalid subcommand, wrong option name).
# ======================================================================

package require tcltest 2.5

tcltest::test audit-log-exists {::log::exists sees the namespace Log variable} -body {
	expr {[::log::exists] in {0 1}}
} -result 1

tcltest::test audit-twm-frozen-named {frozen? with a twm argument reads Frozen, not frozen} -body {
	::twm::frozen? .no-such-twm
} -result 0

tcltest::test audit-choosefont-geometry {-geometry is stored in the parsed options} -body {
	dict get [::dialog::choosefont::ParseArguments yes -geometry 300x200] geometry
} -result 300x200

tcltest::test audit-choosecolor-usercolors {-usercolors is accepted and normalised to rows of six} -body {
	set ::auditUserColors {red}
	::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors
	llength $::auditUserColors
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result 6

tcltest::test audit-choosecolor-bad-usercolor {an invalid user colour reports the option name} -body {
	set ::auditUserColors {no-such-colour}
	list [catch {::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors} msg] $msg
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result {1 {option "-usercolors": invalid color "no-such-colour"}}

tcltest::test audit-openingreport-fonts {opening-report text tags can be (re)created} -body {
	set t [text .auditOpeningReport]
	# force the create path, including deleting fonts left by earlier calls
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	expr {[llength $::application::tree::openingreport::Fonts] > 0}
} -cleanup {
	destroy .auditOpeningReport
} -result 1

tcltest::test audit-trial-mode {trial mode switches on and off again (push and pop take no position)} -body {
	set fen [::scidb::pos::fen]
	::game::flipTrialMode
	set on [::game::trialMode?]
	::game::flipTrialMode
	list $on [::game::trialMode?] [expr {[::scidb::pos::fen] eq $fen}]
} -result {1 0 1}

tcltest::test audit-save-line-keeps-board-game {saving the line to a repertoire works on a copy, not on the game on the board} -setup {
	rename ::application::pgn::saveGame ::auditSaveGame
	proc ::application::pgn::saveGame {mode base} {
		set ::auditSaved [list [::scidb::game::current] [::scidb::game::toPGN modified]]
	}
	set position [::scidb::game::current]
	::scidb::game::move e4; ::scidb::game::go 1
	::scidb::game::move e5; ::scidb::game::go 1
	::scidb::game::move Nf3; ::scidb::game::go 1
	::scidb::game::go -1
} -body {
	set before [::scidb::game::toPGN modified]
	set fen [::scidb::pos::fen]
	::application::database::saveCurrentLineToRepertoire .application base
	lassign $::auditSaved savedAt savedPgn
	list [expr {$savedAt != $position}] [regexp {1\.e4 e5 \*} $savedPgn] \
		[expr {[::scidb::game::toPGN modified] eq $before}] [expr {[::scidb::pos::fen] eq $fen}] \
		[::scidb::game::current]
} -cleanup {
	rename ::application::pgn::saveGame {}
	rename ::auditSaveGame ::application::pgn::saveGame
	unset -nocomplain ::auditSaved
} -result [list 1 1 1 1 [::scidb::game::current]]

tcltest::test audit-game-tags-position-option {game::tags takes a position and -userSuppliedOnly together} -body {
	set pos [::scidb::game::current]
	list [catch { ::scidb::game::tags $pos -userSuppliedOnly yes } r] [catch { ::scidb::game::tags $pos } r] \
		[catch { ::scidb::game::tags -userSuppliedOnly no } r] [catch { ::scidb::game::tags $pos -userSuppliedOnly yes extra } r]
} -result {0 0 0 1}

tcltest::test audit-game-clear-fics {game::clear sets up the FICS start positions the board menu offers} -body {
	set knights [catch { ::scidb::game::clear 4005 } r]
	set fen [lindex [::scidb::pos::fen] 0]
	set bad [catch { ::scidb::game::clear 4016 } r]
	::scidb::game::clear 518
	list $knights [regexp {^[nNkKpP1-8/]+$} $fen] $bad [lindex [::scidb::pos::fen] 0]
} -result {0 1 1 rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR}

tcltest::test audit-toolbar-orientation {a toolbar moved round the sides and back again keeps working} -body {
	::application::switchTab board
	update
	set toolbar ""
	foreach key [array names ::toolbar::Specs side:*] {
		set tb [string range $key 5 end]
		if {[string match *__tb__* $tb] && [winfo exists $tb] && $::toolbar::Specs(enabled:$tb)} { set toolbar $tb; break }
	}
	if {$toolbar eq ""} { return "no toolbar" }
	set home $::toolbar::Specs(side:$toolbar)
	set errors {}
	set side $home
	foreach next {bottom top left right bottom top left right} {
		if {[catch { ::toolbar::MoveCmd $toolbar $next $side } err]} { lappend errors "$side->$next: $err" }
		set side $next
		update
	}
	catch { ::toolbar::MoveCmd $toolbar $home $side }
	update
	set errors
} -result {}

tcltest::test audit-boardgames-gone {a game-list change after the board games pane is gone is ignored} -body {
	set ns ::application::boardgames
	set saved [list [info exists ${ns}::Table] [expr {[info exists ${ns}::Table] ? [set ${ns}::Table] : ""}] \
		[expr {[info exists ${ns}::current] ? [set ${ns}::current] : ""}]]
	set base [::scidb::db::get name]
	set ${ns}::current [list $base Normal]
	set ${ns}::Table .no.such.pane.table
	set stale [catch { ${ns}::GameListChanged 0 $base Normal } err]
	unset ${ns}::Table
	set closed [catch { ${ns}::GameListChanged 0 $base Normal; ${ns}::DatabaseSwitched $base Normal } err]
	lassign $saved had table current
	if {$had} { set ${ns}::Table $table }
	if {$current ne ""} { set ${ns}::current $current }
	list $stale $closed
} -result {0 0}

tcltest::test audit-transpose-trial {a game with castling transposes, and trial mode is left cleanly} -body {
	::application::switchTab board
	set reply [::application::assistant::runTool set_position {moves {1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O Nf6 5.Re1}}]
	if {[string match "error:*" $reply]} { return $reply }
	update
	set out {}
	foreach step {
		{::scidb::game::transpose true}
		{::scidb::game::transpose true}
		{::game::flipTrialMode}
		{::application::assistant::runTool set_position {moves {1.d4}}}
		{::game::flipTrialMode}
	} {
		lappend out [catch { uplevel #0 $step; update } err]
	}
	::scidb::game::clear 518
	::scidb::game::modified [::scidb::game::current] no
	set out
} -result {0 0 0 0 0}

tcltest::cleanupTests
