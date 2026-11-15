# ======================================================================
# GAP-003: the Ask list offers only rows that run with no arguments.
# ======================================================================
# Parameterised tools stay reachable through the assistant (run_action);
# a row whose bare call fails ::action::validateArgs never appears in the
# interactive dropdown, including every td.* and the other headless tools.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::term1ask {
	variable NeedArgs {
		td.bye td.correct_result td.create td.enter_result td.export
		td.finish td.override_pairing td.pair_round td.publish td.redo
		td.register td.start td.stop td.undo td.withdraw
		opening_line view.dialog.close open_database switch_tab pane
		find_capability run_action run_job
	}
	variable BareTd {td.audit td.crosstable td.standings td.status td.workspace}
}

proc ::scidb::test::term1ask::Ids {} {
	return [lmap row [::action::labels asklist {}] {lindex $row 0}]
}

proc ::scidb::test::term1ask::BareBad {ids} {
	set bad {}
	foreach id $ids {
		if {[lindex [::action::validateArgs $id {}] 0] eq "error"} { lappend bad $id }
	}
	return $bad
}

proc ::scidb::test::term1ask::Type {text} {
	set entry [::application::ask::Entry]
	$entry delete 0 end
	$entry insert 0 $text
	::application::ask::Typed ""
	update idletasks
	return
}

tcltest::test term1-asklist-bare-runnable {no offered row fails validation with no arguments} -body {
	catch { ::knowledge::Ensure }
	set rows [::action::labels asklist {}]
	set ids [lmap row $rows {lindex $row 0}]
	set bad [::scidb::test::term1ask::BareBad $ids]
	puts "GAP-003 asklist rows=[llength $ids] bare-validation-failures=[llength $bad]"
	foreach id $bad { puts "  NOT BARE RUNNABLE $id" }
	list [llength $bad] [expr {[llength $rows] > 200}]
} -result {0 1}

tcltest::test term1-asklist-parameterised-hidden {required-argument actions are absent and really need arguments} -body {
	set ids [::scidb::test::term1ask::Ids]
	set need $::scidb::test::term1ask::NeedArgs
	set present {}
	foreach id $need {
		if {$id in $ids} { lappend present $id }
	}
	set bareOk {}
	foreach id $need {
		if {[lindex [::action::validateArgs $id {}] 0] ne "error"} { lappend bareOk $id }
	}
	puts "GAP-003 checked=[llength $need] present=[llength $present] bare_ok=[llength $bareOk]"
	puts "  PRESENT $present"
	puts "  BARE_OK $bareOk"
	list [llength $present] [llength $bareOk]
} -result {0 0}

tcltest::test term1-asklist-keeps-no-argument-rows {actions that run bare remain offered} -body {
	set ids [::scidb::test::term1ask::Ids]
	set keep {menu.file.open new_game explain_position export_database}
	if {[::capability::present td]} {
		foreach id $::scidb::test::term1ask::BareTd {
			set state [::menu::state $id]
			if {[dict get $state visible] && [dict get $state enabled]} { lappend keep $id }
		}
	}
	set missing {}
	foreach id $keep {
		if {$id ni $ids} { lappend missing $id }
	}
	list [llength $missing] $missing
} -result {0 {}}

tcltest::test term1-asklist-real-field {the live Ask field never lists a bare-failing row} -body {
	set saved [array get ::application::ask::Priv]
	set savedQuery $::application::ask::Query
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	unset -nocomplain ::application::ask::Priv(filtered)
	::scidb::test::term1ask::Type "create tournament"
	set ids [lmap row $::application::ask::Priv(rows) {lindex $row 0}]
	set bad [::scidb::test::term1ask::BareBad $ids]
	set tdCreate [expr {"td.create" in $ids}]
	set rows [llength $ids]
	puts "GAP-003 live Ask 'create tournament' rows=$rows bare_failures=[llength $bad] td.create=$tdCreate"
	catch { ::application::ask::HideList }
	set ::application::ask::Query $savedQuery
	array set ::application::ask::Priv $saved
	list [llength $bad] $tdCreate [expr {$rows >= 0}]
} -result {0 0 1}

tcltest::cleanupTests
