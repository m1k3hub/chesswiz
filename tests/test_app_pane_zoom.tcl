# Phase 1 pane zoom: geometry unit fixtures and real application panes.
package require tcltest 2.5

namespace eval ::paneZoomTest { variable Title "Pane" }
# Match the reflow suite: approve engine registration without a modal UI.
proc ::paneZoomTest::yesConfirm {args} {return 1}

proc ::paneZoomTest::makePane {twm parent type uid} {
	set w [tk::frame $parent.$uid]
	set result [list $w ::paneZoomTest::Title 100 0 1 1 1]
	if {$uid ne "other"} { lappend result [expr {$uid ne "eco"}] }
	return $result
}
proc ::paneZoomTest::buildPane {twm w uid width height} {
	pack [ttk::label $w.content -text $uid] -fill both -expand 1
}
proc ::paneZoomTest::snapshot {twm} {
	update idletasks
	set result {}
	foreach w [lsort [winfo children $twm]] {
		if {[string match *Panedwindow [winfo class $w]]} {
			set coords {}
			for {set i 0} {$i < [llength [$w panes]]-1} {incr i} {
				lappend coords [$w sash coord $i]
			}
			lappend result $w $coords
		}
		lappend result $w [list [winfo x $w] [winfo y $w] \
			[winfo width $w] [winfo height $w] [winfo ismapped $w]]
	}
	return $result
}
proc ::paneZoomTest::fixture {children} {
	toplevel .panezoomtest
	wm geometry .panezoomtest 900x650
	set twm [::twm::twm .panezoomtest.layout \
		-makepane ::paneZoomTest::makePane -buildpane ::paneZoomTest::buildPane]
	pack $twm -fill both -expand 1
	set layout [list root {-width 900 -height 650} $children]
	$twm init $layout
	$twm load $layout
	update
	return $twm
}
proc ::paneZoomTest::cleanup {twm} {
	catch {$twm zoom ""}
	catch {destroy .panezoomtest}
	update
}

foreach orient {horz vert} {
	tcltest::test pane-zoom-unit-roundtrip-$orient {exact sash positions, geometry and layout survive a toggle} -setup {
		set t [::paneZoomTest::fixture [list panedwindow [list -orient $orient] \
			{frame board {-width 330 -height 250} frame editor {-width 420 -height 310} frame eco {-width 100 -height 80}}]]
		set p [$t leaf board]
		set pw [$t parent $p]
		$pw sash place 0 287 219
		update
	} -body {
		set before [::paneZoomTest::snapshot $t]
		set layout [$t inspect]
		$t zoom $p
		update
		set savedLayout [$t inspect]
		set fills [expr {[winfo width $p] == [winfo width $t] && [winfo height $p] == [winfo height $t]}]
		set hidden [expr {![winfo ismapped [$t leaf editor]]}]
		$t zoom $p
		update
		list $fills $hidden [expr {$before eq [::paneZoomTest::snapshot $t]}] \
			[expr {$layout eq $savedLayout && $layout eq [$t inspect]}] [$t zoomed]
	} -cleanup { ::paneZoomTest::cleanup $t } -result {1 1 1 1 {}}
}

tcltest::test pane-zoom-unit-refuse {non-zoomable panes refuse without disturbing an existing zoom} -setup {
	set t [::paneZoomTest::fixture {panedwindow {-orient horz} {frame board {} frame eco {}}}]
} -body {
	$t zoom [$t leaf board]
	set current [$t zoomed]
	list [catch {$t zoom [$t leaf eco]}] [expr {$current eq [$t zoomed]}] \
		[winfo exists [$t leaf eco].__header__.zoom]
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 1 0}

tcltest::test pane-zoom-unit-default-off {a pane without the flag refuses to zoom} -setup {
	set t [::paneZoomTest::fixture {frame other {}}]
} -body {
	list [catch {$t zoom [$t leaf other]}] [winfo exists [$t leaf other].__header__.zoom]
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 0}

tcltest::test pane-zoom-unit-controls {layout containers cannot be maximised} -setup {
	set t [::paneZoomTest::fixture {panedwindow {-orient horz} {frame board {} frame editor {}}}]
} -body {
	list [catch {$t zoom $t}] [catch {$t zoom [$t parent [$t leaf board]]}]
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 1}

tcltest::test pane-zoom-notebook {zoom fills the window with the notebook and preserves its selected tab} -setup {
	set t [::paneZoomTest::fixture {panedwindow {-orient horz} {
		notebook {} {frame board {} frame editor {}} frame eco {}}}]
	set p [$t leaf editor]
	set nb [$t parent $p]
	# Meta frames may enclose notebook pages.
	while {![$t isnotebook $nb]} { set nb [$t parent $nb] }
	set page $p
	while {[$t parent $page] ne $nb} { set page [$t parent $page] }
	$t select $nb $page
	update
} -body {
	set selected [$nb select]
	set before [::paneZoomTest::snapshot $t]
	$t zoom $p
	update
	set result [list [expr {[$t zoomed] eq $nb}] [expr {[$nb select] eq $selected}] \
		[expr {[winfo width $nb] == [winfo width $t]}]]
	$t zoom $p
	update
	lappend result [expr {$before eq [::paneZoomTest::snapshot $t]}] [expr {[$nb select] eq $selected}]
	set result
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 1 1 1 1}

tcltest::test pane-zoom-switch {zooming a second pane restores the first overlay before switching} -setup {
	set t [::paneZoomTest::fixture {panedwindow {-orient horz} {frame board {} frame editor {}}}]
} -body {
	set before [::paneZoomTest::snapshot $t]
	$t zoom [$t leaf board]
	update
	$t zoom [$t leaf editor]
	update
	set result [expr {[$t zoomed] eq [$t leaf editor] && ![winfo ismapped [$t leaf board]]}]
	$t zoom ""
	update
	list $result [expr {$before eq [::paneZoomTest::snapshot $t]}]
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 1}

tcltest::test pane-zoom-undocked {floating panes refuse to maximise} -setup {
	set t [::paneZoomTest::fixture {panedwindow {-orient horz} {frame board {} frame editor {}}}]
	set p [$t leaf editor]
	$t undock $p
	update
} -body {
	list [catch {$t zoom $p}] [$t zoomed]
} -cleanup { ::paneZoomTest::cleanup $t } -result {1 {}}

tcltest::test pane-zoom-allowlist {only the specified application panes opt in} -body {
	# explorer joined the dockable panes with the context-menu work.
	lsort [array names ::application::Zoomable]
} -result {analysis assistant board dbgames editor explorer games media report tree}

foreach uid {board editor analysis:1 tree games media} {
	tcltest::test pane-zoom-app-$uid {application pane maximises and restores without changing the saved layout} -setup {
		.application.nb select .application.nb.board
		set t [::application::twm board]
		set p [::application::openPane $uid]
		update
	} -body {
		set before [::paneZoomTest::snapshot $t]
		set layout [$t inspect]
		::application::TogglePaneZoom $p $t
		update
		set target [$t zoomed]
		set result [list [expr {$target ne "" && [winfo ismapped $p]}] \
			[expr {[winfo width $target] == [winfo width $t]}]]
		::application::TogglePaneZoom $p $t
		update
		lappend result [expr {$before eq [::paneZoomTest::snapshot $t]}] [expr {$layout eq [$t inspect]}]
		set result
	} -cleanup { catch {$t zoom ""} } -result {1 1 1 1}
}

tcltest::test pane-zoom-triggers {the registry action and the shortcut expose the toggle} -body {
	# Decision 003: there is no Window menu; the toggle is a registry action
	# reachable from the drop-down surfaces and bound to Ctrl+Shift+Z.
	catch { destroy .panezoommenu }
	menu .panezoommenu
	::menu::BuildDropdown .panezoommenu
	set rec [::action::get view.pane_zoom]
	set ids {}
	foreach row [::action::labels dropdown] { lappend ids [lindex $row 0] }
	set result [list [string match *TogglePaneZoom* [bind .application <Control-Shift-Z>]] \
		[expr {"view.pane_zoom" in $ids}] \
		[lindex [dict get $rec keys] 1]]
	destroy .panezoommenu
	set result
} -result {1 1 Ctrl+Shift+Z}

tcltest::test pane-zoom-shortcut-precedence {pane shortcut runs before broad widget undo bindings} -body {
	.application.nb select .application.nb.board
	set t [::application::twm board]
	set p [::application::openPane editor]
	set w $p.__zoomshortcut_test__
	ttk::entry $w
	bind $w <Control-Key-Z> {error "undo must not run for pane zoom"}
	::application::PaneZoomFocus $w
	set result [list [lindex [bindtags $w] 0] \
		[string match *TogglePaneZoom* [bind PaneZoomShortcut <Control-Shift-Z>]]]
	destroy $w
	set result
} -result {PaneZoomShortcut 1}

# A real UCI process, isolated from the user's engine list. Absence of an
# installed test engine is an explicit constraint, not a simulated pass.
set zoomEngine ""
if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
	set zoomEngine $::env(SCIDB_TEST_ENGINE)
} else { set zoomEngine [lindex [auto_execok stockfish] 0] }
tcltest::testConstraint paneZoomEngine [expr {$zoomEngine ne "" && [file executable $zoomEngine]}]
# The assistant answers confirmations through its own hook, not
# ::action::ConfirmHook.
namespace eval ::scidb::test::pz {}
proc ::scidb::test::pz::Yes {args} { return 1 }
tcltest::test pane-zoom-engine {a hidden analysis pane keeps its real engine running} -constraints paneZoomEngine -setup {
	set savedConfirm $::application::assistant::Priv(confirm)
	set ::application::assistant::Priv(confirm) ::paneZoomTest::yesConfirm
	set savedEngines $::engine::Engines
	set savedFile $::scidb::file::engines
	set savedConfirm $::application::assistant::Priv(confirm)
	set savedReqConfirm $::application::assistant::Priv(reqconfirm)
	set savedActionConfirm $::action::ConfirmHook
	set savedBulk $::action::BulkHook
	# Registering an engine is a confirm-gated tool; a scripted test
	# answers the confirmation instead of opening a modal dialog.
	set ::application::assistant::Priv(confirm) ::scidb::test::pz::Yes
	set ::application::assistant::Priv(reqconfirm) {}
	set ::action::ConfirmHook {list 1}
	set ::action::BulkHook {list 1}
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [tcltest::temporaryDirectory] pane-zoom-engines-[pid].dat]
	::application::assistant::runTool add_engine [list path $zoomEngine]
	set name [dict get [lindex $::engine::Engines 0] Name]
	set number [::application::analysis::startEngine $name "" {lines 1}]
	set t [::application::twm board]
	.application.nb select .application.nb.board
	set board [::application::openPane board]
	update
} -body {
	set running [::application::analysis::Running]
	set analysis [$t leaf analysis:$::application::MapAnalysisToTerminal($number)]
	$t zoom $board
	update
	set hidden [expr {![winfo ismapped $analysis]}]
	set tick 0
	after 1000 {set tick 1}
	vwait tick
	list $hidden [expr {$running eq [::application::analysis::Running] && [llength $running] > 0}] \
		[winfo exists $analysis]
} -cleanup {
	set ::application::assistant::Priv(confirm) $savedConfirm
	catch {$t zoom ""}
	catch {::application::analysis::stopEngine $number}
	file delete -force $::scidb::file::engines
	set ::engine::Engines $savedEngines
	set ::scidb::file::engines $savedFile
	set ::application::assistant::Priv(confirm) $savedConfirm
	set ::application::assistant::Priv(reqconfirm) $savedReqConfirm
	set ::action::ConfirmHook $savedActionConfirm
	set ::action::BulkHook $savedBulk
	::options::hookWriter ::engine::WriteEngineOptions engines
} -result {1 1 1}

tcltest::cleanupTests
