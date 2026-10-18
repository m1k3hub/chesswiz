# Pane reflow (VAL-PANE-001..006): session-only wide/tall reflow of the
# default board layout, empty-pane collapse, and their guarantees.
package require tcltest 2.5

namespace eval ::reflowTest {
	variable done 0
	proc say {args} { puts "REFLOW-EVIDENCE: [join $args { }]"; flush stdout }
	proc mapBoard {} {
		.application.nb select .application.nb.board
		set t [::application::twm board]
		foreach uid {board editor games dbgames tree media analysis:1} { catch {::application::openPane $uid} }
		update
		return $t
	}
	proc setup {} {
		.application.nb select .application.nb.board
		::application::reflow::reset
		set t [::application::twm board]
		foreach uid {board editor games dbgames tree media analysis:1} { catch {::application::openPane $uid} }
		update
		::application::reflow::cancelPending
		return $t
	}
	proc paneW {t uid} { lassign [$t dimension [$t leaf $uid]] w h a b c d; return $w }
	proc waitMs {ms} { variable done; set done 0; after $ms {set ::reflowTest::done 1}; vwait ::reflowTest::done; update }
	proc fileSnap {f} { if {[file exists $f]} { set ch [open $f r]; set data [read $ch]; close $ch; return $data }; return {<none>} }
	proc dirSnap {d} { if {[file isdirectory $d]} { return [lsort [glob -nocomplain -directory $d *]]} ; return {<none>} }
	# Headless stand-in for the assistant's ConfirmDialog: approve without a
	# GUI prompt (mirrors ::scidb::test::engines::confirm), so add_engine can
	# run under Xvfb with no interactive window.
	proc yesConfirm {args} { return 1 }
}

# ----------------------------------------------------------------------
# VAL-PANE-001: default layout reflows wide/tall with hysteresis
# ----------------------------------------------------------------------
tcltest::test pane-reflow-001-wide-tall {default board layout reflows wide/tall; notation beside board when wide, below when tall; hysteresis honored} -setup {
	set t [::reflowTest::setup]
} -body {
	set R [list [::application::reflow::mode] \
		[expr {[::application::reflow::liveShape] eq [::application::reflow::wideShape]}]]
	set wideInspect [::application::twm::inspectLayout $t]

	# dead band while wide: aspect 1.1 must NOT flip to tall
	::application::reflow::evaluate 1100 1000
	update
	lappend R [::application::reflow::mode]

	# tall window (aspect 0.667 < 1.05): editor/games go below the board
	::application::reflow::evaluate 800 1200
	update
	lappend R [::application::reflow::mode] [expr {[::application::reflow::liveShape] eq [::application::reflow::tallShape]}]
	set tallInspect [::application::twm::inspectLayout $t]
	::reflowTest::say "WIDE_INSPECT=$wideInspect"
	::reflowTest::say "TALL_INSPECT=$tallInspect"

	# dead band while tall: aspect 1.1 must NOT flip to wide
	::application::reflow::evaluate 1100 1000
	update
	lappend R [::application::reflow::mode]

	# wide window (aspect 1.556 > 1.25): back to notation beside the board
	::application::reflow::evaluate 1400 900
	update
	lappend R [::application::reflow::mode] [expr {[::application::reflow::liveShape] eq [::application::reflow::wideShape]}] \
		[expr {$tallInspect ne $wideInspect}]
	set R
} -cleanup { ::application::reflow::reset } -result {wide 1 wide tall 1 tall wide 1 1}

# ----------------------------------------------------------------------
# VAL-PANE-002: reflow is session-only (no option/file writes, no prompt,
# and revert-before-save so a restart restores the user's layout)
# ----------------------------------------------------------------------
tcltest::test pane-reflow-002-session-only {reflow never changes board:layout options/files, arms no changed-prompt, and restart restores the saved layout} -setup {
	set t [::reflowTest::setup]
	set optsBefore [array get ::application::twm::Options board:layout:*]
	set listBefore [array get ::application::twm::Options board:layout:list*]
	set chgVarBefore [array get ::application::Vars board:layout:changed*]
	set chgOptBefore [array get ::application::twm::Options board:layout:changed*]
	set optfile $::scidb::file::options
	set optBefore [::reflowTest::fileSnap $optfile]
	set layoutDir [file join $::scidb::dir::layout board]
	set dirBefore [::reflowTest::dirSnap $layoutDir]
} -body {
	set R {}

	# --- Phase A: reflow cycles must not touch persisted state ---
	::application::reflow::evaluate 800 1200 ;# -> tall
	update
	::application::reflow::evaluate 1400 900 ;# -> wide
	update
	# the board:layout:list family (what saveLayouts persists) is untouched
	lappend R [expr {[array get ::application::twm::Options board:layout:list*] eq $listBefore}]
	lappend R [expr {[array get ::application::twm::Options board:layout:*] eq $optsBefore}]
	# no layout-changed prompt state armed
	lappend R [expr {[array get ::application::Vars board:layout:changed*] eq $chgVarBefore}]
	lappend R [expr {[array get ::application::twm::Options board:layout:changed*] eq $chgOptBefore}]
	# no dialog spawned by the reflow
	lappend R [expr {![winfo exists .application.shutdown]}]
	set dialogs [lsort [concat [glob -nocomplain .application.*question*] [glob -nocomplain .tk_messageBox*]]]
	lappend R [expr {[llength $dialogs] == 0}]

	# --- Phase B: reflow to tall, then the shutdown revert must leave the
	#     wide (user's) layout to be captured/persisted for next session ---
	::application::reflow::evaluate 800 1200 ;# -> tall
	update
	lappend R [::application::reflow::mode]
	::application::reflow::RevertForExit
	update
	lappend R [expr {[::application::reflow::liveShape] eq [::application::reflow::wideShape]}]
	# emulate the shutdown capture (saveLayouts grabs inspectLayout when no
	# layout is "changed"); it must see the wide shape, not the reflowed tall
	set wouldSave [::application::twm::inspectLayout $t]
	lappend R [expr {[::application::reflow::shapeOf $wouldSave] eq [::application::reflow::wideShape]}]

	# files on disk untouched by the whole session
	lappend R [expr {[::reflowTest::fileSnap $optfile] eq $optBefore}]
	lappend R [expr {[::reflowTest::dirSnap $layoutDir] eq $dirBefore}]
	set R
} -cleanup { ::application::reflow::reset } -result {1 1 1 1 1 1 tall 1 1 1 1}

# ----------------------------------------------------------------------
# VAL-PANE-003: custom, floating and zoomed layouts are left alone
# ----------------------------------------------------------------------
# 3a: custom (named / structurally different) layout is not reflowed
tcltest::test pane-reflow-003-custom {a custom saved layout is not reflowed} -setup {
	set t [::reflowTest::setup]
	# Simulate a custom layout: give it a name and a non-default structure.
	set savedName $::application::twm::Options(board:layout:name)
	set ::application::twm::Options(board:layout:name) "MyCustom"
	set before [::application::twm::inspectLayout $t]
} -body {
	set beforeMode [::application::reflow::mode]
	::application::reflow::evaluate 800 1200 ;# tall aspect, must be ignored
	update
	set afterMode [::application::reflow::mode]
	set after [::application::twm::inspectLayout $t]
	list [expr {$before eq $after}] [expr {$beforeMode eq $afterMode}] [expr {$afterMode ne "tall"}]
} -cleanup {
	set ::application::twm::Options(board:layout:name) $savedName
	::application::reflow::reset
} -result {1 1 1}

# 3b: a custom (structurally different) default-named layout is not reflowed
tcltest::test pane-reflow-003-nondefault-shape {a structurally non-default layout is not reflowed} -setup {
	set t [::reflowTest::setup]
	# Load a layout whose shape is neither the wide nor the tall default.
	set custom {root { -shrink none -grow none -width 900 -height 700 } {
		panedwindow { -orient horz } {
			pane board %board%
			frame editor %editor%
		}
	}}
	set m {}
	foreach {name val} [array get ::application::PaneOptions] { lappend m %${name}% [list $val] }
	set ::application::Vars(loading) 1
	$t load [string map $m $custom]
	set ::application::Vars(loading) 0
	update
	::application::reflow::cancelPending
	set before [::application::twm::inspectLayout $t]
} -body {
	::application::reflow::evaluate 700 1300 ;# strong tall aspect
	update
	set after [::application::twm::inspectLayout $t]
	list [expr {$before eq $after}] [::application::reflow::mode]
} -cleanup { ::application::reflow::reset } -result {1 wide}

# 3c: a floating (undocked) pane blocks reflow
tcltest::test pane-reflow-003-float {an undocked pane is not reflowed} -setup {
	set t [::reflowTest::setup]
	$t undock [$t leaf editor]
	update
	set before [::application::twm::inspectLayout $t]
	set haveFloat [expr {[llength [$t floats]] > 0}]
} -body {
	::application::reflow::evaluate 800 1200 ;# tall aspect, must be ignored
	update
	set after [::application::twm::inspectLayout $t]
	list $haveFloat [expr {$before eq $after}] [::application::reflow::mode]
} -cleanup {
	::application::reflow::reset
} -result {1 1 wide}

# 3d: a zoomed pane blocks reflow
tcltest::test pane-reflow-003-zoom {a zoomed pane is not reflowed} -setup {
	set t [::reflowTest::setup]
	$t zoom [$t leaf board]
	update
	set before [::application::twm::inspectLayout $t]
	set isZoomed [expr {[string length [$t zoomed]] > 0}]
} -body {
	::application::reflow::evaluate 800 1200 ;# tall aspect, must be ignored
	update
	set after [::application::twm::inspectLayout $t]
	list $isZoomed [expr {$before eq $after}] [::application::reflow::mode]
} -cleanup {
	catch { $t zoom "" }
	update
	::application::reflow::reset
} -result {1 1 wide}

# ----------------------------------------------------------------------
# VAL-PANE-004: a running engine and the edited game survive reflow
# ----------------------------------------------------------------------
set reflowEngine ""
if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
	set reflowEngine $::env(SCIDB_TEST_ENGINE)
} else { set reflowEngine [lindex [auto_execok stockfish] 0] }
tcltest::testConstraint reflowEngine [expr {$reflowEngine ne "" && [file executable $reflowEngine]}]

tcltest::test pane-reflow-004-live-survives {a running engine keeps running and widgets/game survive reflow} -constraints reflowEngine -setup {
	::application::reflow::reset
	set t [::reflowTest::mapBoard]
	::application::reflow::cancelPending

	set savedEngines $::engine::Engines
	set savedFile $::scidb::file::engines
	set savedConfirm {}
	catch { set savedConfirm [set ::application::assistant::Priv(confirm)] }
	set ::application::assistant::Priv(confirm) ::reflowTest::yesConfirm
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [tcltest::temporaryDirectory] reflow-engines-[pid].dat]
	::application::assistant::runTool add_engine [list path $reflowEngine]
	set name [dict get [lindex $::engine::Engines 0] Name]
	set number [::application::analysis::startEngine $name "" {lines 1}]
	set tries 0
	while {[llength [::application::analysis::Running]] == 0 && $tries < 60} { after 100; update; incr tries }

	set ed [$t leaf editor]
	if {![winfo exists $ed.__reflowmark]} { ttk::label $ed.__reflowmark -text MARK }
	set anUid analysis:1
	catch { set anUid analysis:$::application::MapAnalysisToTerminal($number) }
	set an [$t leaf $anUid]
	catch { if {![winfo exists $an.__reflowmark]} { ttk::label $an.__reflowmark -text MARK } }

	set runningBefore [::application::analysis::Running]
	set edBefore $ed
	set boardBefore [$t leaf board]
	set anBefore $an
	set anUidBefore $anUid
	catch { set fenBefore [::scidb::game::fen] }
	catch { set plyBefore [::scidb::game::ply] }
} -body {
	# reflow to tall then back to wide; engine + widgets + game must survive
	::application::reflow::evaluate 800 1200
	update
	set r1 [expr {[llength $runningBefore] > 0 && [::application::analysis::Running] eq $runningBefore}]
	set r2 [expr {$edBefore eq [$t leaf editor] && [winfo exists $edBefore.__reflowmark]}]
	set r3 [expr {$boardBefore eq [$t leaf board]}]
	set r4 [expr {![catch {set a [$t leaf $anUidBefore]}] && $anBefore eq $a && [winfo exists $anBefore.__reflowmark]}]
	set r5 1; catch { set r5 [expr {[::scidb::game::fen] eq $fenBefore}] }
	set r6 1; catch { set r6 [expr {[::scidb::game::ply] eq $plyBefore}] }
	::application::reflow::evaluate 1400 900
	update
	set r7 [expr {[::application::analysis::Running] eq $runningBefore}]
	::reflowTest::say "ENGINE pid/num=$number running=$runningBefore fenSame=$r5 plySame=$r6"
	list $r1 $r2 $r3 $r4 $r5 $r6 $r7
} -cleanup {
	catch { set ::application::assistant::Priv(confirm) $savedConfirm }
	catch {::application::analysis::stopEngine $number}
	file delete -force $::scidb::file::engines
	set ::engine::Engines $savedEngines
	set ::scidb::file::engines $savedFile
	::options::hookWriter ::engine::WriteEngineOptions engines
	::application::reflow::reset
} -result {1 1 1 1 1 1 1}

# ----------------------------------------------------------------------
# VAL-PANE-005: no layout feedback loop (<=1 load per threshold crossing)
# ----------------------------------------------------------------------
tcltest::test pane-reflow-005-no-feedback {a scripted aspect sweep loads at most once per crossing and never oscillates} -setup {
	set t [::reflowTest::setup]
	::application::reflow::resetLoadCount
} -body {
	set c0 [::application::reflow::loadCount]
	# aspects: 1.556(w) 1.2(w/dead) 0.9(t) 0.95(t) 1.1(t/dead) 1.4(w) 1.3(w) 1.0(t) 1.667(w)
	foreach {w h} {1400 900 1200 1000 900 1000 950 1000 1100 1000 1400 1000 1300 1000 1000 1000 1500 900} {
		::application::reflow::evaluate $w $h
		update idletasks
	}
	::application::reflow::cancelPending
	set loads [expr {[::application::reflow::loadCount] - $c0}]
	set md [::application::reflow::mode]
	# idempotent: same size again adds no load
	::application::reflow::evaluate 1500 900
	update idletasks
	::application::reflow::cancelPending
	set loads2 [expr {[::application::reflow::loadCount] - $c0}]
	list $loads $loads2 $md
} -cleanup { ::application::reflow::reset } -result {4 4 wide}

tcltest::test pane-reflow-005-real-resize {real window resizes across the threshold each load once, with no idle oscillation} -setup {
	set t [::reflowTest::setup]
	::application::reflow::resetLoadCount
} -body {
	set c0 [::application::reflow::loadCount]
	wm geometry .application 900x1200+100+40   ;# tall
	::reflowTest::waitMs 600
	set c1 [::application::reflow::loadCount]
	set m1 [::application::reflow::mode]
	wm geometry .application 1600x1000+100+40  ;# wide
	::reflowTest::waitMs 600
	set c2 [::application::reflow::loadCount]
	set m2 [::application::reflow::mode]
	::reflowTest::waitMs 500                   ;# settle: no further loads
	set c3 [::application::reflow::loadCount]
	::reflowTest::say "REAL_RESIZE loads tall=+[expr {$c1-$c0}] wide=+[expr {$c2-$c1}] idle=+[expr {$c3-$c2}]"
	list [expr {$c1 - $c0}] $m1 [expr {$c2 - $c1}] $m2 [expr {$c3 - $c2}]
} -cleanup { ::application::reflow::reset } -result {1 tall 1 wide 0}

# ----------------------------------------------------------------------
# VAL-PANE-006: empty panes collapse and return with prior size
# ----------------------------------------------------------------------
tcltest::test pane-reflow-006-analysis {Analysis with no engine collapses, neighbours gain space, and it returns to prior size when an engine runs} -setup {
	set t [::reflowTest::setup]
	set natAnalysis [::reflowTest::paneW $t analysis:1]
	set natTree [::reflowTest::paneW $t tree]
	set natMedia [::reflowTest::paneW $t media]
	# Media has content so it stays put and can act as the neighbour.
	rename ::application::media::MediaRows ::application::media::MediaRows_orig
	proc ::application::media::MediaRows {} { return {a b} }
	rename ::application::analysis::Running ::application::analysis::Running_orig
	proc ::application::analysis::Running {} { return {} }
} -body {
	# no engine -> analysis collapses, neighbours absorb the freed width
	::application::reflow::updateCollapse
	update
	set collapsed [::reflowTest::paneW $t analysis:1]
	set neighCollapsed [expr {[::reflowTest::paneW $t tree] + [::reflowTest::paneW $t media]}]
	# engine starts -> analysis returns to its prior size
	proc ::application::analysis::Running {} { return {1} }
	::application::reflow::updateCollapse
	update
	set expanded [::reflowTest::paneW $t analysis:1]
	set neighExpanded [expr {[::reflowTest::paneW $t tree] + [::reflowTest::paneW $t media]}]
	::reflowTest::say "ANALYSIS nat=$natAnalysis collapsed=$collapsed expanded=$expanded neigh($natTree+$natMedia)->$neighCollapsed->$neighExpanded"
	list [expr {$collapsed <= 80}] [expr {$collapsed < $natAnalysis}] \
		[expr {abs($expanded - $natAnalysis) <= 2}] \
		[expr {$neighCollapsed > ($natTree + $natMedia)}] \
		[expr {abs($neighExpanded - ($natTree + $natMedia)) <= 4}]
} -cleanup {
	catch { rename ::application::analysis::Running {} }
	catch { rename ::application::analysis::Running_orig ::application::analysis::Running }
	catch { rename ::application::media::MediaRows {} }
	catch { rename ::application::media::MediaRows_orig ::application::media::MediaRows }
	::application::reflow::reset
} -result {1 1 1 1 1}

tcltest::test pane-reflow-006-media {Media with no media collapses and returns to prior size when media exists} -setup {
	set t [::reflowTest::setup]
	set natMedia [::reflowTest::paneW $t media]
	# Analysis has an engine so it stays put (isolates the media behaviour).
	rename ::application::analysis::Running ::application::analysis::Running_orig
	proc ::application::analysis::Running {} { return {1} }
	rename ::application::media::MediaRows ::application::media::MediaRows_orig
	proc ::application::media::MediaRows {} { return {} }
} -body {
	# no media -> media collapses
	::application::reflow::updateCollapse
	update
	set collapsed [::reflowTest::paneW $t media]
	# media exists -> media returns to prior size
	proc ::application::media::MediaRows {} { return {a b} }
	::application::reflow::updateCollapse
	update
	set expanded [::reflowTest::paneW $t media]
	::reflowTest::say "MEDIA nat=$natMedia collapsed=$collapsed expanded=$expanded"
	list [expr {$collapsed <= 80}] [expr {$collapsed < $natMedia}] [expr {abs($expanded - $natMedia) <= 2}]
} -cleanup {
	catch { rename ::application::media::MediaRows {} }
	catch { rename ::application::media::MediaRows_orig ::application::media::MediaRows }
	catch { rename ::application::analysis::Running {} }
	catch { rename ::application::analysis::Running_orig ::application::analysis::Running }
	::application::reflow::reset
} -result {1 1 1}

tcltest::cleanupTests
