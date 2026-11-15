# ======================================================================
# GAP-001: Runnable and RunAction apply the capability and menu-state
# gates to every row, not only context-menu rows.
# ======================================================================
# A row the menus would not offer now is not runnable: an absent optional
# module, an R1/R3 hidden row, an R16 disabled row, or a hidden row with
# no context at all. RunAction must refuse it before a handler runs.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] app_menu_reseal_scope_support.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::term1know {
	variable Ran 0
	variable Hidden test.term1.hidden
	variable Disabled test.term1.disabled
	variable TdIds {
		td.audit td.bye td.correct_result td.create td.crosstable
		td.enter_result td.export td.finish td.override_pairing td.pair_round
		td.publish td.redo td.register td.standings td.start td.status
		td.stop td.undo td.withdraw td.workspace
	}
}

proc ::scidb::test::term1know::Spy {args} {
	incr ::scidb::test::term1know::Ran
	return "spy handler ran"
}

proc ::scidb::test::term1know::HiddenRows {} {
	set rows {}
	foreach id [lsort [::action::list]] {
		set rec [::action::get $id]
		if {[llength [dict get $rec context]]} { continue }
		set state [::menu::state $id]
		if {![dict get $state visible] || ![dict get $state enabled]} {
			lappend rows $id
		}
	}
	return $rows
}

proc ::scidb::test::term1know::Refused {ids} {
	set bad {}
	foreach id $ids {
		lassign [::knowledge::Runnable $id] ok why
		if {$ok || $why eq ""} { lappend bad $id }
	}
	return $bad
}

proc ::scidb::test::term1know::RegisterSynthetic {} {
	variable Hidden
	variable Disabled
	::action::register $Hidden [dict create \
		label "Generated hidden action" object {} what "" doc "" \
		handler ::scidb::test::term1know::Spy ai 1 operator 1 \
		visible {expr 0}]
	::action::register $Disabled [dict create \
		label "Generated disabled action" object {} what "" doc "" \
		handler ::scidb::test::term1know::Spy ai 1 operator 1 \
		enabled {expr 0}]
	return
}

proc ::scidb::test::term1know::ForgetSynthetic {} {
	variable Hidden
	variable Disabled
	catch { dict unset ::action::Registry $Hidden }
	catch { dict unset ::action::Registry $Disabled }
	return
}

proc ::scidb::test::term1know::StartupState {} {
	::scidb::test::askscope::NoGame
	catch { ::application::switchTab information }
	update
	catch { ::knowledge::Ensure }
	return
}

tcltest::test term1-runnable-startup-gates {every startup-hidden or disabled row is not runnable} -setup {
	::scidb::test::term1know::StartupState
} -body {
	set rows [::scidb::test::term1know::HiddenRows]
	set bad [::scidb::test::term1know::Refused $rows]
	set required {
		menu.game.reload menu.game.copy menu.game.close
		menu.game.export.study menu.file.close menu.db.search.plain
		menu.db.reports.eco menu.db.maintenance.compact
		menu.game.paste_clip menu.view.panes.events
	}
	set present [lmap id $required {expr {$id in $rows}}]
	puts "GAP-001 startup rows=[llength $rows] refused_bad=[llength $bad] required=$present"
	foreach id $bad { puts "  STILL RUNNABLE $id" }
	list [llength $bad] [expr {[llength $rows] >= 60}] [join $present {}]
} -result {0 1 1111111111}

tcltest::test term1-runnable-r16-board-tab {the other-tab board cascade is refused while the database tab is active} -setup {
	::scidb::test::askscope::NoGame
	catch { ::application::switchTab database }
	update
} -body {
	set board {}
	foreach id [lsort [::action::list]] {
		if {[::menu::TopOf $id] ne "Board"} { continue }
		set state [::menu::state $id]
		if {![dict get $state visible] || ![dict get $state enabled]} { lappend board $id }
	}
	set bad [::scidb::test::term1know::Refused $board]
	puts "GAP-001 R16 board rows=[llength $board] refused_bad=[llength $bad]"
	list [expr {[llength $board] >= 20}] [expr {"board-flip" in $board}] [llength $bad]
} -cleanup {
	catch { ::application::switchTab information }
	update
} -result {1 1 0}

tcltest::test term1-runnable-td-absent {all 20 td actions and their lookups are unavailable when td is absent} -setup {
	::scidb::test::term1know::StartupState
	::capability::Override td 0
} -body {
	set TdIds $::scidb::test::term1know::TdIds
	set registered 0
	foreach id $TdIds {
		if {[dict exists $::action::Registry $id]} { incr registered }
	}
	set bad [::scidb::test::term1know::Refused $TdIds]
	set find [::knowledge::FindCapability {tournament director}]
	set advertised [regexp -all {td\.[a-z_]+ \(runnable\)} $find]
	set nearest [::knowledge::NearestActions {create a tournament} 4]
	set offered 0
	foreach pair $nearest {
		if {[string match "td.*" [lindex $pair 1]]} { set offered 1 }
	}
	set run [::knowledge::RunAction td.create {}]
	set state [::menu::state td.create]
	puts "GAP-001 td registered=$registered refused_bad=[llength $bad] advertised=$advertised nearest_td=$offered state=$state"
	puts "GAP-001 td RunAction: $run"
	list $registered [llength $bad] $advertised $offered \
		[dict get $state visible] [dict get $state enabled] \
		[string match {error: precondition:*} $run] \
		[expr {[string first {not available in this build} $run] >= 0}]
} -cleanup {
	::capability::ClearOverrides
} -result {20 0 0 0 0 0 1 1}

tcltest::test term1-runaction-hidden-no-context {RunAction refuses a hidden row before its handler runs} -setup {
	::scidb::test::term1know::StartupState
	set ::scidb::test::term1know::Ran 0
	::scidb::test::term1know::RegisterSynthetic
} -body {
	set Hidden $::scidb::test::term1know::Hidden
	set Disabled $::scidb::test::term1know::Disabled
	lassign [::knowledge::Runnable $Hidden] hiddenOk hiddenWhy
	lassign [::knowledge::Runnable $Disabled] disabledOk disabledWhy
	set hiddenRun [::knowledge::RunAction $Hidden {}]
	set disabledRun [::knowledge::RunAction $Disabled {}]
	puts "GAP-001 synthetic hidden=$hiddenOk ($hiddenWhy) disabled=$disabledOk ($disabledWhy) handler_runs=$::scidb::test::term1know::Ran"
	list $hiddenOk [string match {error: precondition:*} $hiddenRun] \
		$disabledOk [string match {error: precondition:*} $disabledRun] \
		$::scidb::test::term1know::Ran
} -cleanup {
	::scidb::test::term1know::ForgetSynthetic
} -result {0 1 0 1 0}

tcltest::cleanupTests
