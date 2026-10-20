# ======================================================================
# Drop-down state predicates: engine, floating pane, HTML report
# (VAL-RULE-001; tcl/dropdown.tcl)
# ======================================================================
# Each of the three predicates decides a visible/enabled row of the
# drop-down and of the board context menus, so a predicate stuck at one
# answer hides rows that should show, or shows rows that cannot work.
# Every one is driven here in both directions with real state:
#
#   ::menu::EngineRunning  a live engine process, started and stopped
#   ::menu::PaneFloating   a real pane, undocked and docked again
#   ::menu::NoHtmlReport   the report module present, then really absent
#
# The engine list is replaced and saved to a scratch file, so the user's
# engines are neither read nor written. Stockfish is used when installed;
# tests/fixtures/fake-uci-engine.tcl is a real UCI process of the test's
# own, so the file never skips on a machine without an engine.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::menupred {
	variable Saved {}
	variable Program ""
	variable Tick 0
}

# The UCI engine for the live test: SCIDB_TEST_ENGINE first (as the other
# engine tests), then stockfish where it is installed, then the fixture.
proc ::scidb::test::menupred::findProgram {} {
	if {[info exists ::env(SCIDB_TEST_ENGINE)]} { return $::env(SCIDB_TEST_ENGINE) }
	set repoRoot [file normalize [file join [file dirname [info script]] ..]]
	set mainRoot [file normalize [file join [file dirname [file normalize [file join $repoRoot .git]]] ..]]
	foreach root [list $repoRoot $mainRoot] {
		foreach bin {stockfish-chesswiz stockfish-scidb stockfish.exe stockfish-chesswiz.exe stockfish} {
			set path [file join $root engines stockfish $bin]
			if {[file executable $path]} { return $path }
		}
	}
	if {[llength [auto_execok stockfish]]} { return [lindex [auto_execok stockfish] 0] }
	foreach dir {/usr/games /usr/local/games /usr/local/bin /usr/bin /opt/homebrew/bin} {
		set path [file join $dir stockfish]
		if {[file executable $path]} { return $path }
	}
	set fixture [file join [file dirname [info script]] fixtures fake-uci-engine.tcl]
	if {[file executable $fixture]} { return $fixture }
	return ""
}

set ::scidb::test::menupred::Program [::scidb::test::menupred::findProgram]
tcltest::testConstraint menupredEngine [expr {
	[string length $::scidb::test::menupred::Program]
	&& [file executable $::scidb::test::menupred::Program]}]

proc ::scidb::test::menupred::wait {ms} {
	set ::scidb::test::menupred::Tick 0
	after $ms { set ::scidb::test::menupred::Tick 1 }
	vwait ::scidb::test::menupred::Tick
}

# Waits until <cond> holds, at most <ms> milliseconds; a loaded machine is
# slow to give the engine its first message.
proc ::scidb::test::menupred::waitUntil {cond {ms 30000}} {
	for {set t 0} {$t < $ms && ![uplevel 1 [list expr $cond]]} {incr t 50} {
		::scidb::test::menupred::wait 50
	}
	return [uplevel 1 [list expr $cond]]
}

proc ::scidb::test::menupred::confirm {what} { return 1 }

# The user's engine list and the confirmation hooks the add_engine tool
# asks before it writes: replaced here, then put back in restore.
proc ::scidb::test::menupred::isolate {} {
	variable Saved
	set Saved [list $::engine::Engines $::scidb::file::engines \
		$::application::assistant::Priv(confirm) $::application::assistant::Priv(reqconfirm) \
		$::action::ConfirmHook $::action::BulkHook]
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [tcltest::temporaryDirectory] menupred-engines-[pid].dat]
	set ::application::assistant::Priv(confirm) ::scidb::test::menupred::confirm
	set ::application::assistant::Priv(reqconfirm) {}
	set ::action::ConfirmHook {list 1}
	set ::action::BulkHook {list 1}
}

proc ::scidb::test::menupred::addEngine {} {
	variable Program
	::application::assistant::runTool add_engine [list path $Program]
	return [dict get [lindex $::engine::Engines 0] Name]
}

proc ::scidb::test::menupred::restore {} {
	variable Saved
	if {![llength $Saved]} { return }
	foreach number [::application::analysis::Running] {
		catch { ::application::analysis::stopEngine $number }
	}
	::scidb::test::menupred::waitUntil {[llength [::application::analysis::Running]] == 0} 10000
	catch { ::scidb::engine::log close }
	catch { file delete -force $::scidb::file::engines }
	lassign $Saved engines file confirm reqConfirm actionConfirm bulk
	set ::engine::Engines $engines
	set ::scidb::file::engines $file
	set ::application::assistant::Priv(confirm) $confirm
	set ::application::assistant::Priv(reqconfirm) $reqConfirm
	set ::action::ConfirmHook $actionConfirm
	set ::action::BulkHook $bulk
	::options::hookWriter ::engine::WriteEngineOptions engines
	set Saved {}
}

# ======================================================================
# ::menu::EngineRunning — any analysis engine is running
# ======================================================================

tcltest::test menupred-engine-running {EngineRunning is 1 only while a live engine runs} \
		-constraints menupredEngine -setup {
	::scidb::test::menupred::isolate
	set name [::scidb::test::menupred::addEngine]
	set before [::menu::EngineRunning]
	set number ""
} -body {
	set number [::application::analysis::startEngine $name "" {lines 1}]
	set started [::scidb::test::menupred::waitUntil {
		[llength [::application::analysis::Running]] > 0}]
	set running [::menu::EngineRunning]
	# the Start / Stop Engine row shows Stop only while the predicate holds
	set labelRunning [expr {[::menu::EngineLabel] eq [::menu::MC StopEngine]}]
	::application::analysis::stopEngine $number
	set stopped [::scidb::test::menupred::waitUntil {
		[llength [::application::analysis::Running]] == 0} 20000]
	set after [::menu::EngineRunning]
	set labelStopped [expr {[::menu::EngineLabel] eq [::menu::MC StartEngine]}]
	puts "  EngineRunning $before -> $running -> $after (started $started stopped $stopped)"
	list $before $started $running $labelRunning $stopped $labelStopped $after
} -cleanup {
	::scidb::test::menupred::restore
} -result {0 1 1 1 1 1 0}

# ======================================================================
# ::menu::PaneFloating — the pane exists and is undocked
# ======================================================================

proc ::scidb::test::menupred::dockablePane {twm} {
	# the board itself never floats; the panes beside it do
	foreach uid {editor games tree media analysis:1} {
		if {[catch { set leaf [$twm leaf $uid] }] || $leaf eq ""} {
			# not in this layout: add it, as View > Panes does
			catch { ::application::openPane $uid }
			if {[catch { set leaf [$twm leaf $uid] }] || $leaf eq ""} { continue }
		}
		if {[catch { set undock [$twm isundockable $uid] }]} { continue }
		if {!$undock} { continue }
		return [list $uid $leaf]
	}
	return {}
}

tcltest::test menupred-pane-floating {PaneFloating is 1 only while the pane is undocked} -setup {
	::application::switchTab board
	update idletasks
	set t [::application::twm board]
	lassign [::scidb::test::menupred::dockablePane $t] uid leaf
	set docked [::menu::PaneFloating $uid $t]
} -body {
	::twm::Undock $t $leaf
	update
	set top [$t toplevel $leaf]
	set separate [expr {[$t isfloat $top]}]
	set undocked [::menu::PaneFloating $uid $t]
	# a pane that is not in this layout is never floating
	set missing [::menu::PaneFloating no-such-pane $t]
	::twm::Dock $t $top
	update
	set redocked [::menu::PaneFloating $uid $t]
	puts "  PaneFloating ($uid) $docked -> $undocked -> $redocked (missing $missing)"
	list $docked $separate $undocked $missing $redocked
} -cleanup {
	if {[info exists t] && [winfo exists $t]} {
		if {[info exists uid] && ![catch { set leaf [$t leaf $uid] }] && $leaf ne ""} {
			if {[catch { set top [$t toplevel $leaf] }] == 0 && [$t isfloat $top]} {
				catch { ::twm::Dock $t $top }
			}
		}
	}
	update idletasks
} -result {0 1 1 0 0}

# ======================================================================
# ::menu::NoHtmlReport — the HTML report module is absent
# ======================================================================

tcltest::test menupred-report-module {NoHtmlReport is 1 only when the report module is absent} -setup {
	set had [llength [info commands ::application::report::show]]
	set row [dict create paneUid report]
} -body {
	set presentCapability [::capability::present report]
	set present [::menu::NoHtmlReport]
	# the consequence: the report font/print group of the pane menu
	set rowPresent [::context::Visible c9.report.font $row]
	# really absent, not overridden: the probe reads the command itself
	rename ::application::report::show ::application::report::show__menupred
	set absentCapability [::capability::present report]
	set absent [::menu::NoHtmlReport]
	set rowAbsent [::context::Visible c9.report.font $row]
	rename ::application::report::show__menupred ::application::report::show
	set again [::menu::NoHtmlReport]
	puts "  NoHtmlReport present=$present absent=$absent again=$again (had $had)"
	list $had $presentCapability $present $rowPresent \
		$absentCapability $absent $rowAbsent $again
} -cleanup {
	if {[llength [info commands ::application::report::show__menupred]]} {
		rename ::application::report::show__menupred ::application::report::show
	}
	::capability::ClearOverrides
} -result {1 1 0 1 0 1 0 0}

tcltest::cleanupTests
