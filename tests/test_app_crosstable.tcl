# ======================================================================
# Scidb App Test - the tournament table / crosstable window (tcl/crosstable.tcl)
# ======================================================================
# Gap G33: the tournament table had no app test at all, so its regressions
# arrived silently. The window is opened the way the game list opens it
# (::crosstable::open ... game) on a generated six-player event, and the
# tests read what the user reads: the rendered table (the tkhtml widget's
# own text), the model behind it (::scidb::crosstable::get) and the window's
# real widgets (the type/order comboboxes, the settings toolbar's refresh
# button, the Close button). Sorting, the crosstable grid, the player card a
# click on a name opens, and closing are covered.
#
# The games are invented, not TWIC: the event must have a known result table
# (Alpha 3, Gamma 2.5, Beta 1.5, Delta 1, Epsilon and Zeta 0.5).
# ======================================================================

package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::xtab {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app crosstable-[pid]]
}

proc ::scidb::test::xtab::nop {args} { return 0 }

# Nine games of six players, so that the table is not a complete round
# robin (a complete one of three or more players is a simultaneous display
# to the C++ table detection and would not open as a crosstable).
proc ::scidb::test::xtab::writePgn {file} {
	set games [list \
		[list {Alpha, Ann}   {Beta, Bob}    1-0] \
		[list {Alpha, Ann}   {Gamma, Gil}   1-0] \
		[list {Beta, Bob}    {Gamma, Gil}   1/2-1/2] \
		[list {Beta, Bob}    {Delta, Dan}   1-0] \
		[list {Gamma, Gil}   {Delta, Dan}   1-0] \
		[list {Delta, Dan}   {Epsilon, Eve} 1-0] \
		[list {Epsilon, Eve} {Zeta, Zoe}    1/2-1/2] \
		[list {Alpha, Ann}   {Delta, Dan}   1-0] \
		[list {Epsilon, Eve} {Gamma, Gil}   0-1]]
	set chan [open $file w]
	fconfigure $chan -encoding utf-8
	set round 0
	foreach game $games {
		lassign $game white black result
		incr round
		puts $chan "\[Event \"Probe Open 2024\"\]"
		puts $chan "\[Site \"Probe City\"\]"
		puts $chan "\[Date \"2024.05.01\"\]"
		puts $chan "\[Round \"[expr {($round + 1) / 2}]\"\]"
		puts $chan "\[White \"$white\"\]"
		puts $chan "\[Black \"$black\"\]"
		puts $chan "\[Result \"$result\"\]"
		puts $chan ""
		puts $chan "1. d4 d5 2. c4 e6 $result"
		puts $chan ""
	}
	close $chan
}

# A generated tournament database in the .sci format a TWIC download uses,
# opened and made the active base as the file menu does it.
proc ::scidb::test::xtab::makeBase {} {
	variable Dir

	file delete -force $Dir
	file mkdir $Dir
	set pgn [file join $Dir tournament.pgn]
	writePgn $pgn

	::scidb::db::open $pgn nop {} nop {}
	set base [file join $Dir tournament.sci]
	::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $base $base
	::scidb::db::copy $pgn $base {} nop {} nop {}
	::scidb::db::save $base nop {}
	::scidb::db::close $base
	::scidb::db::close $pgn

	::scidb::db::load $base nop {} -readonly 1
	$::application::database::Vars(switcher) add $base [::scidb::db::get type $base] 1 {}
	::application::database::switchToBase $base
	update
	return $base
}

# As the game list does it: the crosstable of the event of game 0.
proc ::scidb::test::xtab::openWindow {base} {
	set rc [catch {::crosstable::open .application $base Normal 0 -1 game} err]
	if {$rc} { error "crosstable did not open: $err" }
	update
	return [set ::crosstable::Reuse]
}

# The window's own variables (they live in ::crosstable::<window>::Vars).
proc ::scidb::test::xtab::vget {dlg key} {
	upvar #0 ::crosstable::${dlg}::Vars Vars
	return $Vars($key)
}

# The text the user sees in the window: tkhtml's own rendering.
proc ::scidb::test::xtab::text {dlg} {
	return [[vget $dlg html].sub.html text text]
}

# Cells are separated by newlines and padding in that rendering; collapsing
# every run of white space to one space makes the table readable as text.
proc ::scidb::test::xtab::flat {text} {
	regsub -all {\s+} $text " " text
	return $text
}

# A user's choice in the settings toolbar: the combobox writes the value the
# window reads, and the refresh button redraws the table.
proc ::scidb::test::xtab::choose {dlg widget value} {
	[vget $dlg widget:$widget] set $value
	eval [[vget $dlg toolbar:refresh] cget -command]
	update
}

proc ::scidb::test::xtab::closeWindow {dlg base} {
	catch { destroy $dlg }
	update
	catch { $::application::database::Vars(switcher) remove $base }
	catch { ::scidb::db::close $base }
	variable Dir
	catch { file delete -force $Dir }
}

# Player cards live in .application.__card__N; a card left over by another
# test file would make the card test pass for the wrong window.
proc ::scidb::test::xtab::closeCards {} {
	foreach w [winfo children .application] {
		if {[string match *__card__* $w]} { catch { destroy $w } }
	}
	update
}

file mkdir $::scidb::test::xtab::Dir

tcltest::test crosstable-open {the game list's tournament table opens with the event and its six players} -setup {
	set base [::scidb::test::xtab::makeBase]
	set dlg [::scidb::test::xtab::openWindow $base]
} -body {
	set text [::scidb::test::xtab::flat [::scidb::test::xtab::text $dlg]]
	set tableId [::scidb::test::xtab::vget $dlg tableId]
	set viewId [::scidb::test::xtab::vget $dlg viewId]
	set found 0
	foreach name {{Alpha, Ann} {Beta, Bob} {Gamma, Gil} {Delta, Dan} {Epsilon, Eve} {Zeta, Zoe}} {
		if {[string first $name $text] >= 0} { incr found }
	}
	list \
		[winfo exists $dlg] \
		[winfo class $dlg] \
		[llength [info commands $dlg.close]] \
		[llength [info commands [::scidb::test::xtab::vget $dlg html].sub.html]] \
		[string match "*Probe Open 2024*" [wm title $dlg]] \
		[expr {[string first "Probe Open 2024" $text] >= 0}] \
		[::scidb::crosstable::get playerCount $tableId $viewId] \
		$found
} -cleanup {
	::scidb::test::xtab::closeWindow $dlg $base
} -result {1 Scidb 1 1 1 1 6 6}

tcltest::test crosstable-order-sorts-standings {choosing Alphabetical in the toolbar re-orders the standings} -setup {
	set base [::scidb::test::xtab::makeBase]
	set dlg [::scidb::test::xtab::openWindow $base]
	# one player per row makes the order readable straight from the text
	::scidb::test::xtab::choose $dlg type {Ranking List}
} -body {
	set score [::scidb::test::xtab::flat [::scidb::test::xtab::text $dlg]]
	# score order: Gamma (2.5) stands above Beta (1.5)
	set scoreOk [expr {[string first "Gamma, Gil" $score] >= 0
		&& [string first "Gamma, Gil" $score] < [string first "Beta, Bob" $score]}]
	set orderWidget [::scidb::test::xtab::vget $dlg widget:order]
	set values [$orderWidget cget -values]
	set state [$orderWidget cget -state]
	::scidb::test::xtab::choose $dlg order Alphabetical
	set alpha [::scidb::test::xtab::flat [::scidb::test::xtab::text $dlg]]
	list \
		$scoreOk \
		[string match "Score*" $values] \
		$state \
		[expr {[::scidb::test::xtab::vget $dlg order] eq "alphabetical"}] \
		[expr {[string first "Beta, Bob" $alpha] < [string first "Gamma, Gil" $alpha]}] \
		[expr {[string first "Delta, Dan" $alpha] < [string first "Epsilon, Eve" $alpha]}]
} -cleanup {
	::scidb::test::xtab::closeWindow $dlg $base
} -result {1 1 readonly 1 1 1}

tcltest::test crosstable-type-crosstable {choosing Crosstable draws the grid with the tie-break choices enabled} -setup {
	set base [::scidb::test::xtab::makeBase]
	set dlg [::scidb::test::xtab::openWindow $base]
} -body {
	set values [[::scidb::test::xtab::vget $dlg widget:type] cget -values]
	::scidb::test::xtab::choose $dlg type Crosstable
	set text [::scidb::test::xtab::flat [::scidb::test::xtab::text $dlg]]
	# each player heads one row, and the grid numbers its six columns
	set rows 0
	foreach name {{Alpha, Ann} {Beta, Bob} {Gamma, Gil} {Delta, Dan} {Epsilon, Eve} {Zeta, Zoe}} {
		if {[regexp -all $name $text] == 1} { incr rows }
	}
	list \
		[expr {"Crosstable" in $values && "Knockout" in $values && "Simultaneous" in $values}] \
		[expr {[::scidb::test::xtab::vget $dlg bestMode] eq "crosstable"}] \
		$rows \
		[regexp {1 2 3 4 5 6} $text] \
		[[::scidb::test::xtab::vget $dlg widget:tiebreak1] cget -state] \
		[[::scidb::test::xtab::vget $dlg widget:scoring] cget -state]
} -cleanup {
	::scidb::test::xtab::closeWindow $dlg $base
} -result {1 1 6 1 normal normal}

tcltest::test crosstable-player-card {a click on a name opens that player's card} -setup {
	::scidb::test::xtab::closeCards
	set base [::scidb::test::xtab::makeBase]
	set dlg [::scidb::test::xtab::openWindow $base]
} -body {
	set name [::scidb::crosstable::get playerName \
		[::scidb::test::xtab::vget $dlg tableId] [::scidb::test::xtab::vget $dlg viewId] 1]
	lassign [split $name ,] last first
	set last [string trim $last]
	set first [string trim $first]
	# the action the table's name nodes carry (Mouse1Down -> ShowPlayerCard)
	::crosstable::ShowPlayerCard $dlg 1
	update
	set cards {}
	foreach w [winfo children .application] {
		if {[string match *__card__* $w]} { lappend cards $w }
	}
	set text ""
	if {[llength $cards]} {
		set text [::scidb::test::xtab::flat [[lindex $cards 0].content.sub.html text text]]
	}
	list \
		[llength $cards] \
		[expr {[string first $last $text] >= 0}] \
		[expr {[string first $first $text] >= 0}] \
		[expr {[string first "Last Name: $last" $text] >= 0}]
} -cleanup {
	::scidb::test::xtab::closeCards
	::scidb::test::xtab::closeWindow $dlg $base
} -result {1 1 1 1}

tcltest::test crosstable-close {Close releases the table and the window} -setup {
	set base [::scidb::test::xtab::makeBase]
	set dlg [::scidb::test::xtab::openWindow $base]
} -body {
	set tableId [::scidb::test::xtab::vget $dlg tableId]
	set viewId [::scidb::test::xtab::vget $dlg viewId]
	$dlg.close invoke
	update
	list \
		[expr {![winfo exists $dlg]}] \
		[catch {::scidb::crosstable::get playerCount $tableId $viewId}] \
		[winfo exists .application]
} -cleanup {
	::scidb::test::xtab::closeWindow $dlg $base
} -result {1 1 1}

foreach _id [after info] { catch { after cancel $_id } }

::tcltest::cleanupTests
