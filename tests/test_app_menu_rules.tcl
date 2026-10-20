# ======================================================================
# State rules R1-R16 and module absence (VAL-RULE-001, VAL-RULE-003)
# ======================================================================
# Every visible/enabled decision of the drop-down and the context menus
# goes through ::menu::state. This file drives that mechanism with real
# state where the app can reach it (no game, no database, trial mode, a
# real engine process, a floating pane, a real database tab, capability
# overrides) and with a temporary predicate stub only where the state is
# expensive or belongs to another mission (read-only database, board-only
# layout).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::rules {
	variable tmpDir [file join [file dirname [file normalize [info script]]] tmp-app]
}

proc ::scidb::test::rules::State {id {object {}}} { return [::menu::state $id $object] }
proc ::scidb::test::rules::Visible {id {object {}}} { return [dict get [::scidb::test::rules::State $id $object] visible] }
proc ::scidb::test::rules::Enabled {id {object {}}} { return [dict get [::scidb::test::rules::State $id $object] enabled] }

proc ::scidb::test::rules::WithStub {proc body script} {
	set had [llength [info procs $proc]]
	if {$had} { rename $proc ${proc}__saved }
	proc $proc {} $body
	set code [catch { uplevel 1 $script } result options]
	if {$had} {
		catch { rename $proc {} }
		rename ${proc}__saved $proc
	} else {
		catch { rename $proc {} }
	}
	if {$code} { return -options $options $result }
	return $result
}

# The drop-down registry is filled lazily on the first post; the rule
# checks need the same records the built menu uses.
proc ::scidb::test::rules::RegisterMenus {} {
	if {[llength $::menu::DropdownTree] == 0} { ::menu::DefineTree }
	::menu::RegisterTree
	::menu::RegisterExtras
	return
}

proc ::scidb::test::rules::MenuLabels {menu} {
	set labels {}
	if {[catch {$menu index end} last] || $last eq "none"} { return $labels }
	for {set i 0} {$i <= $last} {incr i} {
		if {[catch {$menu type $i} type] || $type eq "separator"} { continue }
		if {![catch {$menu entrycget $i -label} label]} {
			lappend labels [string trim $label]
		}
	}
	return $labels
}

# Optional module commands, parsed from the one capability table.
proc ::scidb::test::rules::ModuleCommands {} {
	set commands {}
	foreach probe [dict values $::capability::Modules] {
		foreach cmd [regexp -all -inline {::[A-Za-z0-9_:]+} $probe] {
			lappend commands $cmd
		}
	}
	return [lsort -unique $commands]
}

proc ::scidb::test::rules::BuilderProcs {} {
	return {
		::menu::DefineTree ::menu::RegisterTree ::menu::RegisterNodes
		::menu::Register ::menu::RegisterExtras ::menu::state
		::menu::FillTop ::menu::FillNodes ::menu::Do
		::context::Item ::context::Declare ::context::Rows
		::context::Build ::context::BuildRows ::context::AddRow
		::context::Visible ::context::Enabled
	}
}

# R14: no menu builder probes an optional module command with
# [info commands]/[info procs]; the single ::capability::present check is
# the only module test.
proc ::scidb::test::rules::ModuleGuardScan {} {
	set hits {}
	set moduleCommands [::scidb::test::rules::ModuleCommands]
	foreach p [::scidb::test::rules::BuilderProcs] {
		if {![llength [info procs $p]]} { continue }
		set body [info body $p]
		foreach cmd $moduleCommands {
			foreach needle [list "info commands $cmd" "info procs $cmd"] {
				if {[string first $needle $body] >= 0} {
					lappend hits [list $p $cmd]
				}
			}
		}
	}
	return $hits
}

# Every other [info commands]/[info procs] left in a builder, reported for
# review. These are infrastructure presence tests (a builder proc, a log
# hook), not optional-module gates.
proc ::scidb::test::rules::OtherGuardScan {} {
	set hits {}
	foreach p [::scidb::test::rules::BuilderProcs] {
		if {![llength [info procs $p]]} { continue }
		set body [info body $p]
		foreach needle {{info commands} {info procs}} {
			if {[string first $needle $body] >= 0} {
				lappend hits $p
				break
			}
		}
	}
	return $hits
}

# Rows whose visible or enabled predicate names an optional module.
proc ::scidb::test::rules::ModuleGatedRows {} {
	set rows {}
	foreach surface [list dropdown {*}[lmap c {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {list context:$c}]] {
		foreach row [::action::labels $surface] {
			lassign $row id label
			if {[catch { ::action::get $id } rec]} { continue }
			set text ""
			catch { set text [dict get $rec visible] }
			catch { set text "$text [dict get $rec enabled]" }
			if {[info exists ::context::Predicates] && [dict exists $::context::Predicates $id]} {
				set pred [dict get $::context::Predicates $id]
				foreach key {visible enabled} {
					if {[dict exists $pred $key]} { append text " " [dict get $pred $key] }
				}
			}
			foreach module [dict keys $::capability::Modules] {
				if {[string first "ModulePresent $module" $text] >= 0
				 || [string first "capability::present $module" $text] >= 0} {
					lappend rows [list $surface $module $id]
				}
			}
		}
	}
	return $rows
}

proc ::scidb::test::rules::MakeDatabase {} {
	variable tmpDir
	file mkdir $tmpDir
	set base [file normalize [file join $tmpDir "rules_[pid]_[clock microseconds].sci"]]
	::application::database::newBase .application Normal $base
	update idletasks
	return $base
}

proc ::scidb::test::rules::DropDatabase {base} {
	catch { $::application::database::Vars(switcher) remove $base }
	catch { ::scidb::db::close $base }
	catch { file delete -force $base }
}

::scidb::test::rules::RegisterMenus

tcltest::test rules-one-mechanism-module-guards {menu builders use one capability check, no scattered module guards} -body {
	set hits [::scidb::test::rules::ModuleGuardScan]
	puts "VAL-RULE-001 module-guard scan: [llength $hits] hits"
	foreach h $hits { puts "  MODULE GUARD [join $h { }]" }
	set other [::scidb::test::rules::OtherGuardScan]
	puts "  infrastructure presence checks (not module guards): [llength $other]"
	foreach p $other { puts "    $p" }
	set capability [llength [info commands ::capability::present]]
	puts "  single capability check: present=$capability"
	list [llength $hits] $capability
} -result {0 1}

tcltest::test rules-real-state {R1-R5, R8, R9, R11, R14-R16 pass with real state} -body {
	set out {}
	set failed {}
	set ok 1

	# R1: no game loaded at file start.
	set r1 [list \
		[expr {![::scidb::test::rules::Visible game-save]}] \
		[expr {![::scidb::test::rules::Visible menu.game.copy]}] \
		[expr {[::scidb::test::rules::Visible game-next]}]]
	lappend out [list R1 {*}$r1]
	if {$r1 ne {1 1 1}} { set ok 0; lappend failed R1 }

	# R2: trial mode is a real, flippable state and the predicates read it.
	set before [::menu::TrialMode]
	::game::flipTrialMode
	set during [::menu::TrialMode]
	set inTrial [::scidb::test::rules::Visible game-save]
	set trialSave [::context::Visible c4.save_changes [dict create base ""]]
	::game::flipTrialMode
	set after [::menu::TrialMode]
	set wired [expr {[string first TrialMode [dict get [::action::get game-replace] visible]] >= 0}]
	set r2 [list $before $during $after $wired [expr {!$inTrial}] [expr {!$trialSave}]]
	lappend out [list R2 {*}$r2]
	if {$r2 ne {0 1 0 1 1 1}} { set ok 0; lappend failed R2 }

	# R3: no database open (the clipbase is not a database).
	set r3 [::scidb::test::rules::Visible menu.db.search.plain]
	lappend out [list R3 $r3]
	if {$r3 != 0} { set ok 0; lappend failed R3 }

	# R8: an object with no row/move/line/media/pane/selection does not
	# post. ::context::Post refuses on exactly this predicate.
	set posted {}
	foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
		if {[::context::HasObject $cid [dict create]]} { lappend posted $cid }
	}
	set r8 [list [llength $posted] $posted]
	lappend out [list R8 {*}$r8]
	if {[llength $posted]} { set ok 0; lappend failed R8 }

	# R5: no base selected in the switcher.
	catch { destroy .rulec4 }
	menu .rulec4 -tearoff 0
	set built [::context::Build C4 .rulec4 [dict create base ""]]
	set labels [::scidb::test::rules::MenuLabels .rulec4]
	destroy .rulec4
	set r5 [list $built [expr {[lsearch -exact $labels Close] < 0}]]
	lappend out [list R5 {*}$r5]
	if {$r5 ne {1 1}} { set ok 0; lappend failed R5 }

	# R9: a non-Normal game hides the Normal-only start position entry.
	set r9 [::scidb::test::rules::WithStub ::menu::NormalVariant {return 0} {
		::scidb::test::rules::Visible menu.board.start.standard
	}]
	lappend out [list R9 $r9]
	if {$r9 != 0} { set ok 0; lappend failed R9 }

	# R11: a non-sortable table hides the sort group.
	set r11 [list \
		[::context::Visible c3.sort_column [dict create sortable 0]] \
		[::context::Visible c3.sort_column [dict create sortable 1]]]
	lappend out [list R11 {*}$r11]
	if {$r11 ne {0 1}} { set ok 0; lappend failed R11 }

	# R14: no AI provider hides the AI entries (one capability check per
	# module); each AI feature module gates its own entry.
	::capability::Override ai 0
	set aiHidden [list \
		[expr {![::scidb::test::rules::Visible menu.analysis.analyze]}] \
		[expr {![::scidb::test::rules::Visible menu.analysis.explain.position]}]]
	::capability::ClearOverrides
	::capability::Override studyplan 0
	set studyplanHidden [expr {![::scidb::test::rules::Visible menu.training.studyplan]}]
	::capability::ClearOverrides
	set r14 [list {*}$aiHidden $studyplanHidden]
	lappend out [list R14 {*}$r14]
	if {$r14 ne {1 1 1}} { set ok 0; lappend failed R14 }

	# R15: platform/installer entries follow their capability.
	::capability::Override filetypes 0
	::capability::Override legacyfonts 0
	set r15 [list [::scidb::test::rules::Visible menu.tools.file_types] [::scidb::test::rules::Visible menu.tools.legacy_fonts]]
	::capability::ClearOverrides
	lappend out [list R15 {*}$r15]
	if {$r15 ne {0 0}} { set ok 0; lappend failed R15 }

	# R16: the whole Board cascade is greyed on the database tab.
	set old ""
	catch { set old [.application.nb select] }
	::application::switchTab database
	set boardVisible [::scidb::test::rules::Visible menu.board.setup]
	set boardEnabled [::scidb::test::rules::Enabled menu.board.setup]
	if {$old ne ""} { catch { .application.nb select $old } }
	lappend out [list R16a $boardVisible $boardEnabled]
	if {$boardVisible != 1 || $boardEnabled != 0} { set ok 0; lappend failed R16a }

	# R4 and R16b need a real database.
	set base [::scidb::test::rules::MakeDatabase]
	set r4 [::scidb::test::rules::WithStub ::menu::DbWritable {return 0} {
		list [::scidb::test::rules::Enabled menu.file.save] \
			[::scidb::test::rules::Enabled menu.db.maintenance.compact] \
			[::scidb::test::rules::Visible menu.file.save]
	}]
	lappend out [list R4 {*}$r4]
	if {$r4 ne {0 0 1}} { set ok 0; lappend failed R4 }

	# R16 (other direction): Database disabled on a board-only layout.
	set r16b [::scidb::test::rules::WithStub ::menu::BoardOnlyLayout {return 1} {
		set s [::scidb::test::rules::State menu.db.search.plain]
		list [dict get $s visible] [dict get $s enabled]
	}]
	lappend out [list R16b {*}$r16b]
	if {$r16b ne {1 0}} { set ok 0; lappend failed R16b }

	::scidb::test::rules::DropDatabase $base

	foreach row $out { puts "  [join $row { }]" }
	puts "  failing rules: [expr {[llength $failed] ? [join $failed {, }] : {none}}]"
	list $ok
} -result {1}

tcltest::test rules-position-rows {R10 strip and comment rows follow the position} -body {
	set atStart [dict create ply 0]
	set midGame [dict create ply 10 over 0]
	set atEnd [dict create ply 10 over 1]
	set result [list \
		[::context::Visible c2.strip.moves $atStart] \
		[::context::Visible c2.strip.truncate $atStart] \
		[::context::Visible c2.comment_before $atStart] \
		[::context::Visible c2.comment_after $atStart] \
		[::context::Visible c2.strip.moves $midGame] \
		[::context::Visible c2.strip.truncate $midGame] \
		[::context::Visible c2.comment_before $midGame] \
		[::context::Visible c2.strip.truncate $atEnd]]
	foreach v $result { puts "  R10 $v" }
	return $result
} -result {0 0 0 1 1 1 1 0}

tcltest::test rules-pane-and-report {R12 floating pane and R13 absent report surface} -body {
	# R12: undock a real pane (the assistant's pane tool docks it back).
	set t [::application::twm board]
	set result {}
	catch { ::application::assistant::DoPane undock analysis:1 }
	update
	lappend result [::menu::PaneFloating analysis:1 $t]
	set object [dict create paneUid analysis:1 twm $t]
	lappend result [::context::Visible c9.fold $object]
	lappend result [::context::Visible c9.amalgamate $object]
	lappend result [::context::Visible c9.docking $object]
	lappend result [::context::Visible c9.float $object]
	catch { ::application::assistant::DoPane dock analysis:1 }
	update
	lappend result [::menu::PaneFloating analysis:1 $t]
	# R13: the report surface is absent when the module is absent.
	::capability::Override report 0
	lappend result [::context::Visible c9.report.font [dict create paneUid report]]
	lappend result [::context::Visible c9.report.print [dict create paneUid report]]
	::capability::ClearOverrides
	lappend result [::context::Visible c9.report.font [dict create paneUid report]]
	puts "  R12/R13 [join $result { }]"
	return $result
} -result {1 0 0 0 1 0 0 0 1}

# A real UCI process, isolated from the user's engine list (same pattern
# as test_app_pane_zoom.tcl). No installed engine is an explicit skip.
set rulesEngine ""
if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
	set rulesEngine $::env(SCIDB_TEST_ENGINE)
} else { set rulesEngine [lindex [auto_execok stockfish] 0] }
tcltest::testConstraint rulesEngine [expr {$rulesEngine ne "" && [file executable $rulesEngine]}]

namespace eval ::scidb::test::rules::engine {}
proc ::scidb::test::rules::engine::Yes {args} { return 1 }

tcltest::test rules-engine-group {R6/R7 label and engine group follow a real engine start/stop} -constraints rulesEngine -setup {
	set savedEngines $::engine::Engines
	set savedFile $::scidb::file::engines
	set savedConfirm $::application::assistant::Priv(confirm)
	set savedReqConfirm $::application::assistant::Priv(reqconfirm)
	set savedActionConfirm $::action::ConfirmHook
	set savedBulk $::action::BulkHook
	set ::application::assistant::Priv(confirm) ::scidb::test::rules::engine::Yes
	set ::application::assistant::Priv(reqconfirm) {}
	set ::action::ConfirmHook {list 1}
	set ::action::BulkHook {list 1}
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [tcltest::temporaryDirectory] rules-engines-[pid].dat]
	::application::assistant::runTool add_engine [list path $rulesEngine]
	set name [dict get [lindex $::engine::Engines 0] Name]
	set engineNumber [::application::analysis::startEngine $name "" {lines 1}]
	for {set i 0} {$i < 40} {incr i} {
		update
		if {[llength [::application::analysis::Running]]} break
		after 50 {set ::scidb::test::rules::wake 1}
		vwait ::scidb::test::rules::wake
		unset -nocomplain ::scidb::test::rules::wake
	}
} -body {
	set labelRunning [::menu::EngineLabel]
	set running [::menu::EngineRunning]
	set object [dict create engine $engineNumber]
	set shown [list \
		[::context::Visible c6.pause_resume $object] \
		[::context::Visible c6.close_engine $object] \
		[::context::Visible c6.lock_engine $object] \
		[::context::Visible c6.opponents_view $object] \
		[::context::Visible c6.best_first $object] \
		[::context::Visible c6.multiple_variations $object] \
		[::context::Visible c6.lines_per_variation $object]]
	# stop through the posted row's action, as a user would
	::action::invoke menu.analysis.engine_toggle
	for {set i 0} {$i < 40 && [llength [::application::analysis::Running]]} {incr i} {
		after 50 {set ::scidb::test::rules::wake 1}
		vwait ::scidb::test::rules::wake
		unset -nocomplain ::scidb::test::rules::wake
	}
	lappend result_stop [llength [::application::analysis::Running]]
	update
	set labelStopped [::menu::EngineLabel]
	set stopped [list \
		[::context::Visible c6.pause_resume [dict create engine -1]] \
		[::context::Visible c6.close_engine [dict create engine -1]] \
		[::context::Visible c6.multiple_variations [dict create engine -1]]]
	set result [list \
		[expr {$labelRunning eq [::menu::MC StopEngine] ? 1 : 0}] \
		$running $shown \
		[expr {$labelStopped eq [::menu::MC StartEngine] ? 1 : 0}] $stopped $result_stop]
	puts "  R6/R7 [join $result { }]"
	return $result
} -cleanup {
	catch { ::application::analysis::stopEngine $engineNumber }
	catch { file delete -force $::scidb::file::engines }
	set ::engine::Engines $savedEngines
	set ::scidb::file::engines $savedFile
	set ::application::assistant::Priv(confirm) $savedConfirm
	set ::application::assistant::Priv(reqconfirm) $savedReqConfirm
	set ::action::ConfirmHook $savedActionConfirm
	set ::action::BulkHook $savedBulk
	::options::hookWriter ::engine::WriteEngineOptions engines
} -result {1 1 {1 1 1 1 1 1 1} 1 {0 0 0} 0}

tcltest::test rules-module-absent-all-surfaces {no surface shows an action of an absent module} -body {
	set rows [::scidb::test::rules::ModuleGatedRows]
	set leaks {}
	set modules {}
	foreach row $rows {
		lassign $row surface module id
		lappend modules $module
	}
	set modules [lsort -unique $modules]
	foreach module $modules {
		::capability::Override $module 0
		foreach row $rows {
			lassign $row surface m id
			if {$m ne $module} { continue }
			if {[dict get [::scidb::test::rules::State $id] visible]} {
				lappend leaks [list $surface $module $id]
			}
		}
		::capability::ClearOverrides
	}
	puts "VAL-RULE-003: [llength [dict keys $::capability::Modules]] declared modules, [llength $rows] gated rows in [llength $modules] modules, [llength $leaks] leaks"
	foreach l $leaks { puts "  LEAK [join $l { }]" }
	list [llength $leaks] [llength $rows]
} -result {0 44}

tcltest::cleanupTests
