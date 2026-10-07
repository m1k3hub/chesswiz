# ======================================================================
# Scidb App Test — the assistant's offers and ways in
# (tcl/app-assistant-offers.tcl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::offers {}

proc ::scidb::test::offers::labels {} {
	lmap {label request} $::application::assistant::offers::Offers { set label }
}

# Run <body> with the current game's tags replaced by <tags>.
proc ::scidb::test::offers::withTags {tags body} {
	rename ::scidb::game::tags ::scidb::test::offers::realTags
	proc ::scidb::game::tags {args} [list return $tags]
	set rc [catch { uplevel 1 $body } result opts]
	rename ::scidb::game::tags {}
	rename ::scidb::test::offers::realTags ::scidb::game::tags
	return -options $opts $result
}

tcltest::test offers-mine {the user's games are recognised by surname} -body {
	set saved $::application::ai::Settings(me)
	set out {}
	foreach {me name} {
		{Thomas, Michael} {Thomas, M.}
		{Michael Thomas} {Thomas, Michael}
		{Thomas, Michael} {Carlsen, Magnus}
		{} {Thomas, Michael}
	} {
		set ::application::ai::Settings(me) $me
		lappend out [::application::assistant::offers::Mine $name]
	}
	set ::application::ai::Settings(me) $saved
	set out
} -result {1 1 0 0}

tcltest::test offers-game {a game of the user's gets review offers, any other game position offers} -body {
	set saved $::application::ai::Settings(me)
	set ::application::ai::Settings(me) {Carlsen, Magnus}
	::scidb::test::offers::withTags {{White {Carlsen, Magnus}} {Black {Anand, V}}} {
		::application::assistant::offers::GameSwitched 0 0
	}
	set mine [::scidb::test::offers::labels]
	::scidb::test::offers::withTags {{White {Kasparov, G}} {Black {Karpov, A}}} {
		::application::assistant::offers::GameSwitched 0 0
	}
	set other [::scidb::test::offers::labels]
	set ::application::ai::Settings(me) $saved
	list $mine $other
} -result {{{Review my game} {Where did I go wrong?} {Games like this}} {{Explain the position} {Games with this position} {Positions like this}}}

tcltest::test offers-database {a database with games gets database offers; an empty one none} -body {
	::application::assistant::offers::DatabaseSwitched [::scidb::db::get clipbase name] Normal
	set empty [::scidb::test::offers::labels]
	set fixture [file join [file dirname [file normalize [info script]]] tmp-app offers.pgn]
	set fh [open $fixture w]
	puts $fh "\[Event \"O\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]\n\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\n1. e4 *\n"
	close $fh
	::scidb::db::open $fixture {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::application::assistant::offers::DatabaseSwitched $fixture Normal
	set full [::scidb::test::offers::labels]
	::scidb::db::close $fixture
	file delete $fixture
	list $empty $full
} -result {{} {{What's in this database?} {Find positions...} Duplicates?}}

# Run <body> with a classifier that answers <nouls> (one per offer, in
# pool order) after <delay> ms, or never when <nouls> is empty.
proc ::scidb::test::offers::ranked {nouls delay body} {
	foreach p {enabled evaluateAsync} { rename ::ai::systemone::$p ::scidb::test::offers::real_$p }
	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::systemone::evaluateAsync {state questions script} "[list apply {{nouls delay state questions script} {
		set ::scidb::test::offers::State $state
		set answers {}
		foreach id [dict keys $questions] p $nouls { dict set answers $id [dict create type noul noul $p] }
		if {[llength $nouls]} { after $delay [list {*}$script [dict create ok 1 answers $answers]] }
	}} $nouls $delay] \$state \$questions \$script"
	set rc [catch { uplevel 1 $body } result opts]
	foreach p {enabled evaluateAsync} { rename ::ai::systemone::$p {}; rename ::scidb::test::offers::real_$p ::ai::systemone::$p }
	return -options $opts $result
}

tcltest::test offers-ranked {the classifier's likeliest three offers replace the rules' first three} -body {
	set saved $::application::ai::Settings(me)
	set ::application::ai::Settings(me) {}
	set pool {}
	::scidb::test::offers::withTags {{White {Kasparov, G}} {Black {Karpov, A}} {ECO B90} {Result 1-0}} {
		::scidb::test::offers::ranked {0.1 0.2 0.3 0.9 0.8 0.7} 10 {
			::application::assistant::offers::GameSwitched 0 0
			set first [::scidb::test::offers::labels]
			after 100 { set ::scidb::test::offers::Done 1 }
			vwait ::scidb::test::offers::Done
		}
	}
	set ::application::ai::Settings(me) $saved
	list $first [::scidb::test::offers::labels] [string match "game: Kasparov, G - Karpov, A, B90, 1-0*" $::scidb::test::offers::State]
} -result {{{Explain the position} {Games with this position} {Positions like this}} {{Annotate this game} {Games like this} {Opening report}} 1}

tcltest::test offers-ranked-late {a late or stale ranking keeps the offers as they are} -body {
	set saved [list $::application::ai::Settings(me) $::application::assistant::offers::RankTimeout]
	set ::application::ai::Settings(me) {}
	set ::application::assistant::offers::RankTimeout 50
	::scidb::test::offers::withTags {{White {Kasparov, G}} {Black {Karpov, A}}} {
		::scidb::test::offers::ranked {0.1 0.2 0.3 0.9 0.8 0.7} 150 {
			::application::assistant::offers::GameSwitched 0 0
			after 250 { set ::scidb::test::offers::Done 1 }
			vwait ::scidb::test::offers::Done
		}
		set late [::scidb::test::offers::labels]
		set ::application::assistant::offers::RankTimeout 6000
		::scidb::test::offers::ranked {0.1 0.2 0.3 0.9 0.8 0.7} 50 {
			::application::assistant::offers::GameSwitched 0 0
			::application::assistant::offers::put {A {request a}}
			after 150 { set ::scidb::test::offers::Done 1 }
			vwait ::scidb::test::offers::Done
		}
	}
	lassign $saved ::application::ai::Settings(me) ::application::assistant::offers::RankTimeout
	set stale [::scidb::test::offers::labels]
	::application::assistant::offers::put {}
	list $late $stale
} -result {{{Explain the position} {Games with this position} {Positions like this}} A}

tcltest::test offers-buttons {the pane shows one button per offer; a click on an open request fills the entry} -body {
	::application::assistant::show
	update
	::application::assistant::offers::put {A {request a} B {Find positions where ...}}
	set frame $::application::assistant::offers::Frame
	set texts [lmap w [winfo children $frame] { $w cget -text }]
	[lindex [winfo children $frame] 1] invoke
	set entry [$::application::assistant::Priv(entry) get]
	$::application::assistant::Priv(entry) delete 0 end
	::application::assistant::offers::put {}
	list $texts $entry [llength [winfo children $frame]]
} -result {{A B} {Find positions where } 0}

tcltest::test offers-ways-in {F2 is bound everywhere; Ask about this names the game} -body {
	rename ::application::assistant::offers::askAbout ::scidb::test::offers::realAsk
	proc ::application::assistant::offers::askAbout {text} { set ::scidb::test::offers::Asked $text }
	set fixture [file join [file dirname [file normalize [info script]]] tmp-app offers2.pgn]
	set fh [open $fixture w]
	puts $fh "\[Event \"O\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]\n\[White \"Tal, M\"\]\n\[Black \"Smyslov, V\"\]\n\[Result \"1-0\"\]\n\n1. e4 1-0\n"
	close $fh
	::scidb::db::open $fixture {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::application::assistant::offers::AskAboutGame $fixture Normal 0
	set game $::scidb::test::offers::Asked
	::application::assistant::offers::AskAboutBoard
	set board $::scidb::test::offers::Asked
	::scidb::db::close $fixture
	file delete $fixture
	rename ::application::assistant::offers::askAbout {}
	rename ::scidb::test::offers::realAsk ::application::assistant::offers::askAbout
	list [expr {[bind all <F2>] ne ""}] [string match "About game #1 (*Tal, M - Smyslov, V*): " $game] $board
} -result {1 1 {About the position on the board: }}

tcltest::cleanupTests
