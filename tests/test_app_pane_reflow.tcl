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

proc ::reflowTest::enginePids {} {
 set result {}
 if {![file readable /proc/[pid]/task/[pid]/children]} {return {}}
 set f [open /proc/[pid]/task/[pid]/children]; set children [read $f]; close $f
 foreach child $children {
  if {![file readable /proc/$child/comm]} {continue}
  set f [open /proc/$child/comm]; set name [string trim [read $f]]; close $f
  if {[string match -nocase *stockfish* $name]} {lappend result $child}
 }
 return [lsort -integer $result]
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
	foreach san {e4 e5 Nf3 Nc6} {::move::addMove menu $san}
	::reflowTest::waitMs 400
	::application::assistant::runTool add_engine [list path $reflowEngine]
	set name [dict get [lindex $::engine::Engines 0] Name]
	set number [::application::analysis::startEngine $name "" {lines 1}]
	set tries 0
	while {[llength [::application::analysis::Running]] == 0 && $tries < 60} { after 100; update; incr tries }

	set movesBefore [::scidb::game::toPGN modified]
	set engineIdBefore [::engine::id $number]
	set linesBefore [::application::assistant::runTool engine_analysis {}]
 for {set tries 0} {$tries < 50 && ![regexp {depth [0-9]+} $linesBefore]} {incr tries} {
  ::reflowTest::waitMs 100
  set linesBefore [::application::assistant::runTool engine_analysis {}]
 }
 set pidsBefore [::reflowTest::enginePids]
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
	::reflowTest::waitMs 700
	set linesAfter [::application::assistant::runTool engine_analysis {}]
	set r8 [expr {[::scidb::game::toPGN modified] eq $movesBefore && [::engine::id $number] eq $engineIdBefore}]
	set r9 [expr {[regexp {depth [0-9]+} $linesBefore] && [regexp {depth [0-9]+} $linesAfter]}]
 if {[llength $pidsBefore]} {set r8 [expr {$r8 && $pidsBefore eq [::reflowTest::enginePids]}]}
	::reflowTest::say "ENGINE number=$number nativeId=$engineIdBefore running=$runningBefore children=$pidsBefore fenSame=$r5 plySame=$r6 moves=$movesBefore before=$linesBefore after=$linesAfter"
	list $r1 $r2 $r3 $r4 $r5 $r6 $r7 $r8 $r9
} -cleanup {
	catch { set ::application::assistant::Priv(confirm) $savedConfirm }
	catch {::application::analysis::stopEngine $number}
	file delete -force $::scidb::file::engines
	set ::engine::Engines $savedEngines
	set ::scidb::file::engines $savedFile
	::options::hookWriter ::engine::WriteEngineOptions engines
	::application::reflow::reset
} -result {1 1 1 1 1 1 1 1 1}

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
# Direct default row with the optional Media pane. This is a production twm
# tree with real Analysis and Media widgets, not placeholder geometry.
proc ::reflowTest::collapseSetup {} {
 set t [setup]
 ::application::reflow::restoreCollapsed
 set ::application::Vars(loading) 1
 set layout [::application::reflow::substTpl $::application::BoardLayout]
 lassign $layout root attrs outer
 lassign $outer type opts rows
 set row [lrange $rows 3 5]
 set row [lreplace $row 2 2 [concat [lindex $row 2] [list frame media $::application::PaneOptions(media)]]]
 set layout [list $root $attrs [list $type $opts [concat [lrange $rows 0 2] $row]]]
 $t load $layout
 set ::application::Vars(loading) 0
 set ::application::reflow::S(override) {}
 wm geometry .application 1200x800+0+0
 waitMs 400
 return $t
}
proc ::reflowTest::sashes {t} {return [::application::focuszoom::Snapshot $t]}

tcltest::test pane-reflow-006-unmapped {empty panes collapse by priority only when short; explicit reopen wins; exact sash restore} -setup {
 set t [::reflowTest::collapseSetup]
 set a [$t leaf analysis:1]; set m [$t leaf media]
 set ids [list [winfo id $a] [winfo id $m]]
 set before [::reflowTest::sashes $t]
} -body {
 set wide [list [winfo ismapped $a] [winfo ismapped $m]]
 wm geometry .application 1000x800
 ::reflowTest::waitMs 450
 set short [list [winfo ismapped $a] [winfo ismapped $m]]
 # User action goes through the same pane-menu command as a real click.
 ::application::twm::ChangeState $t analysis:1
 ::reflowTest::waitMs 450
 set reopened [winfo ismapped $a]
 ::application::reflow::updateCollapse
 set stays [winfo ismapped $a]
 # Content makes Media come back without touching any geometry procedure.
 ::application::media::InsertEntry 3 Lesson /generated.mp4 -1
 ::reflowTest::waitMs 450
 set content [winfo ismapped $m]
 wm geometry .application 1200x800
 ::reflowTest::waitMs 450
 set restored [expr {[::reflowTest::sashes $t] eq $before}]
 set live [expr {$ids eq [list [winfo id $a] [winfo id $m]]}]
 ::reflowTest::say "COLLAPSE wide=$wide short=$short reopened=$reopened stays=$stays content=$content restored=$restored ids=$ids sashes=$before"
 list $wide $short $reopened $stays $content $restored $live
} -cleanup {
 ::application::media::Update [::scidb::game::current]
 ::application::reflow::reset
} -result {{1 1} {0 1} 1 1 1 1 1}

tcltest::test pane-reflow-006-media-content {empty Media unmaps and content restores its prior sashes without destroying its widgets} -setup {
 set t [::reflowTest::collapseSetup]
 set m [$t leaf media]; set id [winfo id $m]
 wm geometry .application 1000x800
 ::reflowTest::waitMs 450
 # Reopen while short of space, exactly as the contract's override rule.
 ::application::openPane analysis:1
 ::reflowTest::waitMs 450
} -body {
 set unmapped [expr {![winfo ismapped $m]}]
 ::application::media::InsertEntry 3 Lesson /generated.mp4 -1
 ::reflowTest::waitMs 450
 list $unmapped [winfo ismapped $m] [expr {[winfo id $m] eq $id}]
} -cleanup {
 ::application::media::Update [::scidb::game::current]
 ::application::reflow::reset
} -result {1 1 1}

tcltest::test pane-reflow-009-save-guard {explicit save while adapted is blocked with a message; original file unchanged} -setup {
 set t [::reflowTest::setup]
 wm geometry .application 1200x800
 ::reflowTest::waitMs 400
 set name pane-reflow-restart
 ::application::twm::WriteLayout $t board $name normal
 set file [::application::twm::makeFilename board normal $name]
 set saved [::reflowTest::fileSnap $file]
 rename ::dialog::info ::reflowTest::info
 set ::reflowTest::messages {}
 proc ::dialog::info {args} {lappend ::reflowTest::messages $args; return ok}
} -body {
 wm geometry .application 800x1200
 ::reflowTest::waitMs 500
 set adapted [::application::reflow::mode]
 set answer [::application::twm::WriteLayout $t board $name normal]
 set unchanged [expr {[::reflowTest::fileSnap $file] eq $saved}]
 ::reflowTest::say "SAVE rule=block source=S(base) file=$file adapted=$adapted answer=$answer unchanged=$unchanged messages=$::reflowTest::messages"
 # This file is loaded in a separate fresh app by the rerunnable worker
 # verification script; the test itself also loads it through production.
 ::application::twm::loadLayout $t $name
 set loaded [expr {[::application::reflow::liveShape] eq [::application::reflow::wideShape]}]
 list $adapted $answer $unchanged [llength $::reflowTest::messages] $loaded
} -cleanup {
 rename ::dialog::info {}; rename ::reflowTest::info ::dialog::info
 set ::application::twm::Options(board:layout:name) {}
 ::application::reflow::reset
} -result {tall 0 1 1 1}

proc ::reflowTest::loadTrace {cmd op} {
 if {[lindex $cmd 1] eq [::application::twm board] && [lindex $cmd 2] eq "load"} {incr ::reflowTest::nativeLoads}
}
tcltest::test pane-reflow-001-threshold-sweep {actual Configure sweep cites both thresholds and counts native loads without oscillation} -setup {
 set t [::reflowTest::setup]
 wm geometry .application 1000x780+0+0
 ::reflowTest::waitMs 450
 # Establish wide without lying to the geometry evaluator.
 wm geometry .application 1200x780
 ::reflowTest::waitMs 450
 set ::reflowTest::nativeLoads 0
 trace add execution ::twm::WidgetProc enter ::reflowTest::loadTrace
 set opts [array get ::application::twm::Options board:layout:list*]
} -body {
 set states {}; set counts {}
 foreach width {1000 840 800 840 980 960 800} {
  wm geometry .application ${width}x780
  ::reflowTest::waitMs 450
  set mode [::application::reflow::mode]
  lappend states $mode; lappend counts $::reflowTest::nativeLoads
  set inspect [::application::twm::inspectLayout $t]
  ::reflowTest::say "SWEEP requested=${width}x780 actual=[wm geometry .application] constants=($::application::reflow::TallAspect,$::application::reflow::WideAspect) mode=$mode loads=$::reflowTest::nativeLoads inspect=$inspect"
  if {[info exists ::env(PANE_EVIDENCE)]} {catch {::util::execSafe import -window root [file join $::env(PANE_EVIDENCE) sweep-$width-$mode.png]}}
 }
 ::reflowTest::waitMs 700
 list $states $counts $::reflowTest::nativeLoads [expr {$opts eq [array get ::application::twm::Options board:layout:list*]}]
} -cleanup {
 trace remove execution ::twm::WidgetProc enter ::reflowTest::loadTrace
 ::application::reflow::reset
} -result {{wide wide tall tall wide wide tall} {0 0 1 1 2 2 3} 3 1}

tcltest::test pane-reflow-006-engine {real engine start restores a collapsed pane; stop makes it eligible again} -constraints reflowEngine -setup {
 set t [::reflowTest::collapseSetup]
 ::application::media::InsertEntry 3 Lesson /generated.mp4 -1
 set savedEngines $::engine::Engines
 set savedFile $::scidb::file::engines
 set savedConfirm $::application::assistant::Priv(confirm)
 set ::application::assistant::Priv(confirm) ::reflowTest::yesConfirm
 set ::engine::Engines {}
 set ::scidb::file::engines [file normalize tests/tmp-app/pane-collapse-engines-[pid].dat]
 ::application::assistant::runTool add_engine [list path $reflowEngine]
 set name [dict get [lindex $::engine::Engines 0] Name]
 wm geometry .application 1000x800
 ::reflowTest::waitMs 450
 set a [$t leaf analysis:1]; set id [winfo id $a]
 set before $::application::reflow::S(snapshot)
} -body {
 set collapsed [expr {![winfo ismapped $a]}]
 set number [::application::analysis::startEngine $name {} {lines 1 threads 1 hash 16}]
 ::reflowTest::waitMs 600
 set restored [winfo ismapped $a]
 set runningSashes [::reflowTest::sashes $t]
 set same [expr {$before eq $runningSashes}]
 ::application::analysis::stopEngine $number
 ::reflowTest::waitMs 450
 set stopped [expr {![winfo ismapped $a]}]
 ::reflowTest::say "ENGINE COLLAPSE collapsed=$collapsed runningMapped=$restored sameSashes=$same before=$before after=$runningSashes stoppedCollapsed=$stopped id=$id"
 list $collapsed $restored $same $stopped [expr {[winfo id $a] eq $id}]
} -cleanup {
 catch {::application::analysis::stopEngine $number}
 set ::application::assistant::Priv(confirm) $savedConfirm
 file delete -force $::scidb::file::engines
 set ::engine::Engines $savedEngines
 set ::scidb::file::engines $savedFile
 ::options::hookWriter ::engine::WriteEngineOptions engines
 ::application::media::Update [::scidb::game::current]
 ::application::reflow::reset
} -result {1 1 1 1 1}

tcltest::test pane-reflow-002-save-dialog {modal shutdown processing cannot reactivate a presentation before saved-layout capture; cancel resumes adaptation} -setup {
 set t [::reflowTest::setup]
 wm geometry .application 800x780+0+0
 ::reflowTest::waitMs 450
 rename ::application::twm::saveLayouts ::application::twm::paneSavedSaveLayouts
 rename ::game::queryCloseApplication ::reflowTest::queryCloseApplication
 proc ::game::queryCloseApplication {args} {return cancel}
 set ::reflowTest::captured {}
 proc ::application::twm::saveLayouts {} {
  # Model a modal dialog's event loop while the real shutdown is paused.
  ::application::reflow::onConfigure .application [winfo width .application] [winfo height .application]
  ::application::reflow::onPaneStateChange
  ::reflowTest::waitMs 450
  set ::reflowTest::captured [::application::reflow::liveShape]
  ::application::twm::paneSavedSaveLayouts
 }
} -body {
 ::application::shutdown
 set saved [::application::reflow::shapeOf $::application::twm::Options(board:layout:list:normal)]
 ::reflowTest::waitMs 450
 set resumed [::application::reflow::mode]
 list [expr {$::reflowTest::captured eq [::application::reflow::wideShape]}] [expr {$saved eq [::application::reflow::wideShape]}] $resumed
} -cleanup {
 rename ::application::twm::saveLayouts {}; rename ::application::twm::paneSavedSaveLayouts ::application::twm::saveLayouts
 rename ::game::queryCloseApplication {}; rename ::reflowTest::queryCloseApplication ::game::queryCloseApplication
 ::application::reflow::reset
} -result {1 1 tall}

tcltest::cleanupTests
