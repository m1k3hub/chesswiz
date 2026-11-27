# Features from the 2026-11-27 access review (docs/FEATURES.md section 2):
# reachable ones have a menu or right-click row; developer tools are not
# offered to users.
package require tcltest 2.5

proc ::FeatureAccessOrder {id} { dict get [::action::get $id] dropdown }

tcltest::test access-menu-rows {Print, Assistant preferences and Focus Zoom are in the drop-down} -body {
	set out {}
	foreach id {menu.game.print menu.edit.preferences.assistant view.pane_zoom view.focus_zoom
			view.focus_follows_size view.focus_ratio view.focus_pin} {
		set order [::FeatureAccessOrder $id]
		lappend out [expr {$order ne "" && ![string match 00.* $order]}]
	}
	set out
} -result {1 1 1 1 1 1 1}

tcltest::test access-print-key {Game > Print Game… has Ctrl+P} -body {
	lindex [dict get [::action::get menu.game.print] keys] 1
} -match glob -result {*P}

tcltest::test access-context-rows {lesson, novelty, player statistics, position types and transcription have rows} -body {
	set out {}
	foreach {cid id} {C1 c1.find_lesson C2 c2.novelty C5 c5.player_stats C5 c5.structure_profile C7 c7.transcribe} {
		lappend out [expr {$cid in [dict get [::action::get $id] context]}]
	}
	set out
} -result {1 1 1 1 1}

tcltest::test access-c10-sort {a game-list column header offers sorting} -body {
	set owner ""
	foreach ns [namespace children ::gamestable] {
		set path [string range $ns [string length ::gamestable::] end]
		if {[string match .* $path]} { set owner $path; break }
	}
	if {$owner eq ""} { return "no game table" }
	set object [dict create table $owner.table.top.table column date sortable 1]
	list [::context::SortOwner $object] [::context::SortOwner [dict create table .nosuch.table.top.table column x]]
} -match glob -result {{gamestable .*} {}}

tcltest::test access-debug-tools {developer tools are debug only} -body {
	set out {}
	foreach id {handoff_issue triage_errors list_issues} { lappend out [dict get [::action::get $id] ai] }
	set out
} -result {debug debug debug}

tcltest::test access-ask-hides-diagnostics {the Ask list does not suggest internal diagnostics} -body {
	set ids {}
	foreach row [::action::labels asklist ""] { lappend ids [lindex $row 0] }
	list [expr {"app_state" in $ids}] [expr {"tool_log" in $ids}] [expr {"classifier_status" in $ids}] [expr {"print" in $ids}]
} -result {0 0 0 1}

tcltest::cleanupTests
