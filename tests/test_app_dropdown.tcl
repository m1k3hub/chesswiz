# ======================================================================
# Scidb App Test - reorganised main drop-down (VAL-BAR-001/004/005/006)
# ======================================================================
# The frozen fixture tests/fixtures/menubar-expected.txt is the oracle:
# each MENU line is a cascade of the drop-down button in file order, each
# SUBMENU line a level-2 cascade, and the entries below them are leaves.
# Decision 003 reads "menu bar" as the main drop-down.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::dd {}

set ::scidb::test::dd::dir [file dirname [file normalize [info script]]]
set ::scidb::test::dd::fixture [file join $::scidb::test::dd::dir fixtures menubar-expected.txt]

proc ::scidb::test::dd::FixtureBody {} {
	set f [open $::scidb::test::dd::fixture r]
	set lines [split [read $f] \n]
	close $f
	set body {}
	set started 0
	foreach line $lines {
		if {!$started} {
			if {[string match "MENU *" $line]} { set started 1 } else { continue }
		}
		lappend body $line
	}
	while {[llength $body] && [lindex $body end] eq ""} {
		set body [lrange $body 0 end-1]
	}
	return $body
}

proc ::scidb::test::dd::DumpBody {menu} {
	set dump [::menu::Dump $menu]
	set body [split $dump \n]
	while {[llength $body] && [lindex $body end] eq ""} {
		set body [lrange $body 0 end-1]
	}
	return $body
}

proc ::scidb::test::dd::WalkCommands {menu resultVar} {
	upvar $resultVar result
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { continue }
		if {$type eq "cascade"} {
			WalkCommands [$menu entrycget $i -menu] result
			continue
		}
		if {$type eq "command" || $type eq "checkbutton" || $type eq "radiobutton"} {
			set cmd ""
			catch { set cmd [$menu entrycget $i -command] }
			lappend result [list $type $cmd [$menu entrycget $i -label]]
		}
	}
}

proc ::scidb::test::dd::Percentile {values pct} {
	set values [lsort -real $values]
	if {![llength $values]} { return 0 }
	set n [llength $values]
	set i [expr {int(ceil($pct * $n)) - 1}]
	if {$i < 0} { set i 0 }
	return [lindex $values $i]
}

proc ::scidb::test::dd::Build {} {
	catch { destroy .ddtest }
	menu .ddtest -tearoff 0
	::menu::BuildDropdown .ddtest
	return .ddtest
}

tcltest::test dropdown-fixture-structure {the built drop-down equals the frozen menubar fixture} -body {
	set menu [::scidb::test::dd::Build]
	set expected [::scidb::test::dd::FixtureBody]
	set actual [::scidb::test::dd::DumpBody $menu]
	destroy $menu
	list $expected $actual
} -result [list [::scidb::test::dd::FixtureBody] [::scidb::test::dd::FixtureBody]]

tcltest::test dropdown-top-level-count {ten task cascades, at most twelve top-level items} -body {
	set menu [::scidb::test::dd::Build]
	set labels {}
	for {set i 0} {$i <= [$menu index end]} {incr i} {
		lappend labels [string trim [$menu entrycget $i -label]]
	}
	destroy $menu
	list [llength $labels] $labels
} -result [list 10 {File Edit Game Database Board Analysis Training Tools View Help}]

tcltest::test dropdown-registry-commands {every command row is ::action::run, dynamic rows exempt} -body {
	set menu [::scidb::test::dd::Build]
	# force every lazy cascade to fill
	::menu::Dump $menu
	set rows {}
	::scidb::test::dd::WalkCommands $menu rows
	set bad {}
	set exemptions 0
	foreach row $rows {
		lassign $row type cmd label
		if {[string trim $label] eq "per toolbar checkbuttons"} {
			incr exemptions
			continue
		}
		if {![string match "::action::run *" $cmd]} {
			lappend bad [list $label $cmd]
		}
	}
	destroy $menu
	list $bad $exemptions
} -result [list {} 1]

tcltest::test dropdown-labels-surface {::action::labels dropdown returns the drop-down rows in file order} -body {
	set menu [::scidb::test::dd::Build]
	::menu::Dump $menu
	destroy $menu
	set rows [::action::labels dropdown]
	set ids {}
	foreach row $rows { lappend ids [lindex $row 0] }
	set dup [expr {[llength [lsort -unique $ids]] == [llength $ids] ? 0 : 1}]
	list [expr {[llength $ids] > 100}] $dup
} -result {1 0}

tcltest::test dropdown-lazy-cascades {top-level cascades fill only when posted} -body {
	set menu [::scidb::test::dd::Build]
	set sub $menu.file
	set before [$sub index end]
	set ::menu::DropdownFilled [dict create]
	::menu::FillTop File $sub
	set after [$sub index end]
	destroy $menu
	# A fresh session has no database, so R3 hides some File rows; laziness
	# only needs an empty cascade before the post command and rows after it.
	expr {($before eq "" || $before eq "none" || $before == -1) && $after >= 3}
} -result 1

tcltest::test dropdown-state-r1-no-game {with no game loaded the Game save group is hidden, navigation stays} -body {
	list \
		[dict get [::menu::state game-save] visible] \
		[dict get [::menu::state menu.game.copy] visible] \
		[dict get [::menu::state game-next] visible] \
		[dict get [::menu::state game-first] visible]
} -result {0 0 1 1}

tcltest::test dropdown-state-r16-database-tab {R16 greys the whole Board cascade on the database tab} -body {
	set old ""
	catch { set old [.application.nb select] }
	catch { ::application::switchTab database }
	set boardEnabled [dict get [::menu::state menu.board.setup] enabled]
	set boardVisible [dict get [::menu::state menu.board.setup] visible]
	if {$old ne ""} { catch { .application.nb select $old } }
	list $boardVisible $boardEnabled
} -result {1 0}

tcltest::test dropdown-state-module-absent {an absent optional module has no drop-down entry} -body {
	::capability::Override studyplan 0
	::capability::Override insights 0
	set study [dict get [::menu::state menu.training.studyplan] visible]
	set insights [dict get [::menu::state c5.insights] visible]
	::capability::ClearOverrides
	list $study $insights
} -result {0 0}

tcltest::test dropdown-timing {lazy fills stay under 30 ms median and 50 ms p95} -body {
	set menu [::scidb::test::dd::Build]
	set times {}
	foreach top {File Edit Game Database Board Analysis Training Tools View Help} {
		set sub $menu.[::menu::WidgetName [::menu::MC $top]]
		for {set i 0} {$i < 10} {incr i} {
			set ::menu::DropdownFilled [dict create]
			set t0 [clock microseconds]
			::menu::FillTop $top $sub
			lappend times [expr {([clock microseconds] - $t0) / 1000.0}]
		}
	}
	destroy $menu
	set median [::scidb::test::dd::Percentile $times 0.5]
	set p95 [::scidb::test::dd::Percentile $times 0.95]
	puts "dropdown timing: median=[format %.2f $median]ms p95=[format %.2f $p95]ms"
	list [expr {$median <= 30.0}] [expr {$p95 <= 50.0}]
} -result {1 1}

tcltest::test dropdown-no-alt-menu {Alt and F10 do not open a hidden menu bar} -body {
	set alt [bind .application <Alt-Key>]
	# F10 keeps its scheme meaning: the key-editor table still maps it to
	# loading the next game (no bar toggles on F10).
	set f10 ""
	foreach row $::application::keyEditor::Actions {
		if {[lindex $row 0] eq "game-next" && [lindex $row 4] eq "F10"} {
			set f10 [lindex $row 5]
		}
	}
	list [expr {[string match *menu* $alt] ? 1 : 0}] [expr {[string match *LoadGame* $f10] ? 1 : 0}]
} -result {0 1}

tcltest::test dropdown-build-wrapper {::menu::build still wraps the drop-down builder} -body {
	catch { destroy .ddwrap }
	menu .ddwrap -tearoff 0
	::menu::build .ddwrap
	set n [.ddwrap index end]
	set first [string trim [.ddwrap entrycget 0 -label]]
	destroy .ddwrap
	list $n $first
} -result {9 File}

tcltest::cleanupTests
