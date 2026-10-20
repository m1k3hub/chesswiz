# ======================================================================
# Scidb App Test - the Player Dictionary (tcl/player-dict.tcl)
# ======================================================================
# Gap G33: the dictionary had no app test at all. The window is opened as
# Tools > Player Dictionary opens it and driven as a user drives it: the
# letter buttons filter, the search box finds a player, a column menu sorts,
# a double click hands the player to the caller that asked for it (the way
# Save/Replace's player choice uses it), and Close closes.
#
# The rows come from the dictionary that ships with the app, so the tests
# read the name they expect from the dictionary itself
# (::scidb::player::info) instead of naming a player.
# ======================================================================

package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::pdict {
	variable Total 0
}

# The window; a dictionary left open by another test file is closed first so
# that this file always drives a fresh one.
proc ::scidb::test::pdict::openDict {} {
	set old [::playerdict::dialog]
	if {$old ne ""} { catch { destroy $old } }
	update
	catch { ::playerdict::unsetReceiver }
	::playerdict::open .application
	update
	set dlg [::playerdict::dialog]
	if {$dlg eq ""} { error "the player dictionary did not open" }
	variable Total [::scidb::player::count]
	return $dlg
}

proc ::scidb::test::pdict::closeDict {dlg} {
	catch { ::playerdict::unsetReceiver }
	catch { destroy $dlg }
	update
}

proc ::scidb::test::pdict::table {dlg} {
	return [::scrolledtable::table $dlg.top.table]
}

proc ::scidb::test::pdict::tree {dlg} {
	return [::table::tablePath [table $dlg]]
}

# The text a cell displays (the table keeps it in the cell's text element).
proc ::scidb::test::pdict::cell {dlg row column} {
	set t [tree $dlg]
	return [lindex [$t item element configure $row $column elemTxt$column -text] end]
}

# The player a row displays, in the dictionary's own spelling.
proc ::scidb::test::pdict::shownName {dlg row} {
	return "[cell $dlg $row lastName],[cell $dlg $row firstName]"
}

proc ::scidb::test::pdict::modelName {index} {
	return [lindex [::scidb::player::info $index] 1]
}

proc ::scidb::test::pdict::firstRow {dlg} {
	return [::scrolledtable::firstRow $dlg.top.table]
}

# The table widget's rows are the rows of the window (0 is the first one
# shown), while ::scrolledtable::active/firstRow speak in dictionary indexes.
proc ::scidb::test::pdict::visibleRows {dlg} {
	set t [tree $dlg]
	set rows {}
	for {set i 0} {$i < [::table::height [table $dlg]]} {incr i} {
		if {[catch {$t item element configure $i lastName elemTxtlastName -text}]} { break }
		lappend rows $i
	}
	return $rows
}

# The player a dictionary index is shown as, on the row the window shows.
proc ::scidb::test::pdict::shownAt {dlg index} {
	return [shownName $dlg [expr {$index - [firstRow $dlg]}]]
}

# Type a player's name into the search box as the user does: key presses in
# the focused entry, the interactive search firing after its delay.
proc ::scidb::test::pdict::search {dlg text} {
	set entry $dlg.top.search.e
	focus -force $entry
	update
	foreach char [split $text ""] {
		if {$char eq " "} {
			event generate $entry <KeyPress> -keysym space
		} else {
			event generate $entry <KeyPress> -keysym $char
		}
	}
	update
	after 400
	update
}

# A surname the dictionary holds, and the player holding it: plain letters
# only, so that the search box can be given it as key presses (a name may
# have spaces, accents or punctuation in it).
proc ::scidb::test::pdict::surnameAt {index} {
	variable Total
	for {} {$index < $Total} {incr index} {
		set name [modelName $index]
		set surname [lindex [split [string trim [lindex [split $name ,] 0]] " "] 0]
		if {[regexp {^[A-Za-z]{3,}$} $surname]} {
			return [list $index $surname]
		}
	}
	error "no plain surname found from index $index"
}

tcltest::test playerdict-open {the dictionary opens with its table, letter buttons, search box and count} -setup {
	set dlg [::scidb::test::pdict::openDict]
} -body {
	set label [$dlg.top.size cget -text]
	list \
		[winfo exists $dlg] \
		[winfo class $dlg] \
		[expr {[::scidb::player::count] > 1000}] \
		[expr {[string length $label] > 0 && [string match "*[::locale::formatNumber [::scidb::player::count]]*" $label]}] \
		[winfo class $dlg.top.table] \
		[winfo class $dlg.top.search.e] \
		[winfo class $dlg.top.alpha.b] \
		[llength [winfo children $dlg.top.alpha]] \
		[winfo class $dlg.close] \
		[expr {"lastName" in [::scrolledtable::visibleColumns $dlg.top.table]}] \
		[expr {[llength [::scidb::test::pdict::visibleRows $dlg]] > 0}]
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 Scidb 1 1 TFrame TTSearchBox Registerbutton 27 TButton 1 1}

tcltest::test playerdict-letter-filter {a letter button filters the dictionary and * restores it} -setup {
	set dlg [::scidb::test::pdict::openDict]
} -body {
	set total $::scidb::test::pdict::Total
	# the B button, as a click reaches it (the widget runs its command from
	# its class binding, not from a -command option)
	event generate $dlg.top.alpha.b <ButtonPress-1>
	update
	set filtered [::scidb::player::count]
	set label [$dlg.top.size cget -text]
	set rows [::scidb::test::pdict::visibleRows $dlg]
	set firstLast [::scidb::test::pdict::cell $dlg [lindex $rows 0] lastName]
	set allStartB [expr {[llength $rows] > 0}]
	foreach row $rows {
		if {![string match -nocase "B*" [::scidb::test::pdict::cell $dlg $row lastName]]} { set allStartB 0 }
	}
	event generate $dlg.top.alpha.all <ButtonPress-1>
	update
	list \
		[expr {$filtered > 0 && $filtered < $total}] \
		[string match -nocase "B*" $firstLast] \
		$allStartB \
		[expr {[string match "*[::locale::formatNumber $filtered]*" $label]}] \
		[expr {[::scidb::player::count] == $total}]
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 1 1 1 1}

tcltest::test playerdict-search-finds-player {typing a name in the search box scrolls to that player and selects the row} -setup {
	set dlg [::scidb::test::pdict::openDict]
	set index 3000
	if {$index >= $::scidb::test::pdict::Total} { set index [expr {$::scidb::test::pdict::Total / 2}] }
	lassign [::scidb::test::pdict::surnameAt $index] index surname
} -body {
	::scidb::test::pdict::search $dlg $surname
	set expected [::scidb::player::search "$surname*" -1]
	set active [::scrolledtable::active $dlg.top.table]
	set first [::scidb::test::pdict::firstRow $dlg]
	set last [expr {$first + [::table::height [::scidb::test::pdict::table $dlg]] - 1}]
	set shown ""
	if {[catch {::scidb::test::pdict::shownAt $dlg $active} shown]} { set shown "<no row>" }
	list \
		[expr {$expected >= 0}] \
		[expr {$first <= $active && $active <= $last}] \
		[expr {$active == $expected}] \
		[expr {[string match "$surname*" $shown]}] \
		[expr {$shown eq [::scidb::test::pdict::modelName $expected]}]
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 1 1 1 1}

tcltest::test playerdict-sort-column {sorting by name redraws the visible rows in the new order} -setup {
	set dlg [::scidb::test::pdict::openDict]
	set before [::scidb::test::pdict::modelName 0]
} -body {
	set table $dlg.top.table
	# a column header's menu: Sort Descending
	::playerdict::SortColumn $table name descending
	update
	set first [::scidb::test::pdict::firstRow $dlg]
	set descending [::scidb::test::pdict::modelName $first]
	set shown [::scidb::test::pdict::shownAt $dlg $first]
	::playerdict::SortColumn $table name ascending
	update
	set ascending [::scidb::test::pdict::modelName $first]
	set shownBack [::scidb::test::pdict::shownAt $dlg $first]
	list \
		[expr {$descending ne $before}] \
		[expr {$shown eq $descending}] \
		[expr {$shownBack eq $ascending}] \
		[expr {$shownBack eq $before}]
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 1 1 1}

tcltest::test playerdict-double-click {a double click hands the player to the caller waiting for one} -setup {
	set dlg [::scidb::test::pdict::openDict]
	set ::scidb::test::pdict::Reply {}
	::playerdict::setReceiver [list apply {{info} {set ::scidb::test::pdict::Reply $info}}]
} -body {
	set row [expr {[::scidb::test::pdict::firstRow $dlg] + 2}]
	set expected [::scidb::test::pdict::modelName $row]
	# <<TableSelected>> is what the table sends on a double click
	event generate $dlg.top.table <<TableSelected>> -data $row
	update
	set reply $::scidb::test::pdict::Reply
	list \
		[expr {[llength $reply] > 0}] \
		[expr {[lindex $reply 1] eq $expected}] \
		[expr {[lindex $reply 0] eq [lindex [::scidb::player::info $row] 0]}]
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 1 1}

tcltest::test playerdict-close {Close closes the dictionary behind the window, and it opens again} -setup {
	set dlg [::scidb::test::pdict::openDict]
} -body {
	$dlg.close invoke
	update
	set closed [expr {![winfo exists $dlg] && [::playerdict::dialog] eq ""}]
	set count [::scidb::player::count]
	::playerdict::open .application
	update
	set again [::playerdict::dialog]
	set ok [expr {$again ne "" && [winfo exists $again] && [::scidb::player::count] > 1000}]
	catch { destroy $again }
	update
	list $closed $count $ok
} -cleanup {
	::scidb::test::pdict::closeDict $dlg
} -result {1 0 1}

foreach _id [after info] { catch { after cancel $_id } }

::tcltest::cleanupTests
