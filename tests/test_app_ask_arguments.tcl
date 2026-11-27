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
source [file join [file dirname [info script]] app_menu_reseal_scope_support.tcl]
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

# ----------------------------------------------------------------------
# Row-set equivalence for the cached Ask path (W-term4, VAL-PAL-001).
# The optimization caches the state-qualified rows, so the row set must
# stay exactly what the original per-row algorithm produced: context rows
# scoped by the posted menu ids, ::menu::state (with no explicit object,
# so CurrentObjectFor resolves it) for visible+enabled, and the bare
# ::action::validateArgs gate.
# ----------------------------------------------------------------------
proc ::scidb::test::term1ask::ContextIds {} {
	set ids {}
	if {[llength [info commands ::context::MenuIds]] \
	 && [llength [info commands ::context::CurrentObject]]} {
		foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
			if {![catch {set object [::context::CurrentObject $cid]}] \
			 && [dict size $object] && [::context::HasObject $cid $object]} {
				lappend ids {*}[::context::MenuIds $cid $object]
			}
		}
	}
	return $ids
}

proc ::scidb::test::term1ask::ReferenceIds {} {
	set contextIds [::scidb::test::term1ask::ContextIds]
	set out {}
	foreach id [dict keys $::action::Registry] {
		set record [::action::get $id]
		if {[dict get $record ai] eq "debug"} { continue }
		if {[dict exists $record asklist] && ![dict get $record asklist]} { continue }
		if {$id eq "context.ask"} { continue }
		set ctx [dict get $record context]
		if {[llength $ctx] && [dict get $record dropdown] eq "" \
		 && [lsearch -exact $contextIds $id] < 0} { continue }
		set state [::menu::state $id]
		if {![dict get $state visible] || ![dict get $state enabled]} { continue }
		if {[catch {::action::validateArgs $id {}} validation]
		 || [lindex $validation 0] eq "error"} { continue }
		lappend out $id
	}
	return [lsort $out]
}

proc ::scidb::test::term1ask::Compare {} {
	set got [lsort [::scidb::test::term1ask::Ids]]
	set want [::scidb::test::term1ask::ReferenceIds]
	set missing {}
	foreach id $want { if {$id ni $got} { lappend missing $id } }
	set extra {}
	foreach id $got { if {$id ni $want} { lappend extra $id } }
	return [list $missing $extra [llength $got] [llength $want]]
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

# ----------------------------------------------------------------------
# Cached row set equals the original per-row algorithm in real states.
# ----------------------------------------------------------------------
tcltest::test term1-asklist-row-set-startup {the cached rows equal the per-row reference with no game} -body {
	lassign [::scidb::test::term1ask::Compare] missing extra got want
	puts "ROWSET startup got=$got want=$want missing=$missing extra=$extra"
	list [llength $missing] [llength $extra] [expr {$got > 200}]
} -result {0 0 1}

tcltest::test term1-asklist-row-set-game {loading and closing a game invalidates the snapshot and matches} -body {
	::scidb::test::askscope::NewGame
	update
	set loaded [::scidb::test::term1ask::Ids]
	lassign [::scidb::test::term1ask::Compare] missing extra got want
	set saveIn [expr {"game-save" in $loaded}]
	::scidb::test::askscope::NoGame
	update
	set empty [::scidb::test::term1ask::Ids]
	lassign [::scidb::test::term1ask::Compare] missing2 extra2 got2 want2
	set saveOut [expr {"game-save" ni $empty}]
	puts "ROWSET game got=$got want=$want missing=$missing extra=$extra game-save=$saveIn"
	puts "ROWSET no-game got=$got2 want=$want2 missing=$missing2 extra=$extra2 game-save-gone=$saveOut"
	list [llength $missing] [llength $extra] $saveIn \
		[llength $missing2] [llength $extra2] $saveOut
} -result {0 0 1 0 0 1}

tcltest::test term1-asklist-row-set-tab {tab switches invalidate the snapshot and stay equal} -body {
	::scidb::test::askscope::NewGame
	update
	::application::switchTab database
	update
	lassign [::scidb::test::term1ask::Compare] missing extra got want
	::application::switchTab board
	update
	lassign [::scidb::test::term1ask::Compare] missing2 extra2 got2 want2
	::scidb::test::askscope::NoGame
	update
	puts "ROWSET tab-database got=$got want=$want missing=$missing extra=$extra"
	puts "ROWSET tab-board got=$got2 want=$want2 missing=$missing2 extra=$extra2"
	list [llength $missing] [llength $extra] \
		[llength $missing2] [llength $extra2] [expr {$got > 200}]
} -result {0 0 0 0 1}

tcltest::test term1-asklist-row-set-capability {capability overrides invalidate the snapshot and stay equal} -body {
	::capability::Override studyplan 1
	set on [::scidb::test::term1ask::Ids]
	lassign [::scidb::test::term1ask::Compare] missing extra got want
	::capability::Override studyplan 0
	set off [::scidb::test::term1ask::Ids]
	lassign [::scidb::test::term1ask::Compare] missing2 extra2 got2 want2
	::capability::ClearOverrides
	puts "ROWSET cap-on got=$got want=$want missing=$missing extra=$extra"
	puts "ROWSET cap-off got=$got2 want=$want2 missing=$missing2 extra=$extra2 changed=[expr {[lsort $on] ne [lsort $off]}]"
	list [llength $missing] [llength $extra] [llength $missing2] [llength $extra2]
} -result {0 0 0 0}

tcltest::cleanupTests
