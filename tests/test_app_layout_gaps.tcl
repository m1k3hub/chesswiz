# Regression tests for the five final-review layout gaps (REVIEW3).
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::layoutGaps {
	variable serial 0
}

proc ::layoutGaps::waitFor {ms} {
	variable serial
	set flag [namespace current]::tick[incr serial]
	after $ms [list set $flag 1]
	vwait $flag
	unset $flag
	update idletasks
}

proc ::layoutGaps::settle {{ms 900}} {
	set until [expr {[clock milliseconds] + $ms}]
	while {[clock milliseconds] < $until} {
		update
		after 20
	}
}

proc ::layoutGaps::inside {rect area} {
	lassign $rect x y w h
	lassign $area ax ay aw ah
	expr {$x >= $ax && $y >= $ay && $x+$w <= $ax+$aw && $y+$h <= $ay+$ah}
}

proc ::layoutGaps::overlap {a b} {
	lassign $a ax ay aw ah
	lassign $b bx by bw bh
	expr {max(0,min($ax+$aw,$bx+$bw)-max($ax,$bx))*max(0,min($ay+$ah,$by+$bh)-max($ay,$by))}
}

proc ::layoutGaps::frame {w} {
	if {![catch {::scidb::tk::wm frame $w} frame] && [llength $frame] == 4} {
		return $frame
	}
	lassign [winfo extents $w] l r t b
	return [list [expr {[winfo rootx $w]-$l}] [expr {[winfo rooty $w]-$t}] \
		[expr {[winfo width $w]+$l+$r}] [expr {[winfo height $w]+$t+$b}]]
}

proc ::layoutGaps::boardRect {} {
	if {[info exists ::application::board::Vars(3d)]
		&& $::application::board::Vars(3d)
		&& [info exists ::application::board::Vars(3dwin)]} {
		set view $::application::board::Vars(3dwin)
		if {[winfo exists $view] && [winfo ismapped $view]} {
			return [list [winfo rootx $view] [winfo rooty $view] \
				[winfo width $view] [winfo height $view]]
		}
	}
	return [::util::place::besideBoardRect]
}

proc ::layoutGaps::areas {} {
	set areas {}
	catch { set areas [::scidb::tk::wm workareas .application] }
	return $areas
}

proc ::layoutGaps::rightArea {} {
	foreach area [areas] {
		lassign $area x y w h
		if {$x > 0 && $w > 0 && $h > 0} { return $area }
	}
	return {}
}

# Xvfb exposes one output. Assigning it to LEFT and adding RIGHT with no
# output is the reviewer's RandR dual-monitor recipe.
proc ::layoutGaps::setupMonitors {} {
	catch { exec xrandr --delmonitor LEFT }
	catch { exec xrandr --delmonitor RIGHT }
	exec xrandr --setmonitor LEFT 1000/300x1080/286+0+0 screen
	exec xrandr --setmonitor RIGHT 920/300x1080/286+1000+0 none
	settle 300
}

proc ::layoutGaps::clearMonitors {} {
	catch { exec xrandr --delmonitor LEFT }
	catch { exec xrandr --delmonitor RIGHT }
	settle 300
}

set ::layoutGaps::dualmon [expr {![catch {
	exec which xrandr
	::layoutGaps::setupMonitors
	set ::layoutGaps::dualmon [expr {[llength [::layoutGaps::areas]] >= 2}]
	::layoutGaps::clearMonitors
} err]}]
tcltest::testConstraint dualmon $::layoutGaps::dualmon
set ::layoutGaps::embed3d 0
catch { set ::layoutGaps::embed3d [::board3d::LoadToglLib] }
tcltest::testConstraint embed3d $::layoutGaps::embed3d


# GAP-001: a mapped dialog's own monitor decides its work area, even when the
# main window is on another monitor.
tcltest::test gap001-dialog-own-monitor {a playing dialog dragged or pinned to monitor 2 stays there} \
		-constraints dualmon -setup {
	::layoutGaps::setupMonitors
	set saved [wm geometry .application]
	wm geometry .application 700x760+30+40
	::layoutGaps::settle 300
} -body {
	set right [::layoutGaps::rightArea]
	lassign $right rx ry rw rh
	::tactics::open .application
	::scidb::test::wait::until {[winfo ismapped .tactics]}
	::layoutGaps::settle 400
	set moved "+[expr {$rx+40}]+[expr {$ry+60}]"
	wm geometry .tactics $moved
	::layoutGaps::settle 1200
	set area [winfo workarea .tactics]
	set frame [::layoutGaps::frame .tactics]
	set free [expr {$area eq $right && [::layoutGaps::inside $frame $right]}]
	# Pin while on monitor 2 and move again: the pin must not pull it to the
	# main window's monitor.
	::util::place::besidePin .tactics 1
	wm geometry .tactics "+[expr {$rx+70}]+[expr {$ry+90}]"
	::layoutGaps::settle 900
	set pinned [expr {[winfo workarea .tactics] eq $right
		&& [::layoutGaps::inside [::layoutGaps::frame .tactics] $right]}]
	list $free $pinned
} -cleanup {
	catch { destroy .tactics }
	wm geometry .application $saved
	::layoutGaps::clearMonitors
	::layoutGaps::settle 300
} -result {1 1}

tcltest::test gap001-child-on-parent-monitor {a centred child of a monitor-2 parent stays on monitor 2} \
		-constraints dualmon -setup {
	::layoutGaps::setupMonitors
	catch { destroy .mon2parent .mon2child }
} -body {
	set right [::layoutGaps::rightArea]
	lassign $right rx ry rw rh
	toplevel .mon2parent
	wm geometry .mon2parent "402x327+[expr {$rx+40}]+[expr {$ry+60}]"
	::scidb::test::wait::until {[winfo ismapped .mon2parent]}
	::layoutGaps::settle 200
	toplevel .mon2child
	wm transient .mon2child .mon2parent
	::util::place .mon2child -parent .mon2parent -position center
	::scidb::test::wait::until {[winfo ismapped .mon2child]}
	::layoutGaps::settle 200
	set inside [::layoutGaps::inside [::layoutGaps::frame .mon2child] $right]
	set wa [winfo workarea .mon2child]
	list $inside [expr {$wa eq $right}]
} -cleanup {
	catch { destroy .mon2child .mon2parent }
	::layoutGaps::clearMonitors
	::layoutGaps::settle 300
} -result {1 1}


# GAP-003: in embedded 3D mode the visible 3D view is the board a dialog must
# clear, not the stale unmapped 2D canvas.
tcltest::test gap003-beside-3d-board {playing dialogs clear the embedded 3D board and follow its resize} \
		-constraints embed3d -setup {
	set saved [wm geometry .application]
	catch { .application.nb select .application.nb.board }
	set ::board3d::State(embed) 1
	::board3d::toggleEmbed
	::layoutGaps::settle 500
	wm geometry .application 1100x760+20+20
	::layoutGaps::settle 500
} -body {
	set view $::application::board::Vars(3dwin)
	set rect [list [winfo rootx $view] [winfo rooty $view] \
		[winfo width $view] [winfo height $view]]
	::tactics::open .application
	::scidb::test::wait::until {[winfo ismapped .tactics]}
	::layoutGaps::settle 600
	set overlap [::layoutGaps::overlap [::layoutGaps::frame .tactics] $rect]
	wm geometry .application 1500x920+260+80
	::layoutGaps::settle 900
	set rect2 [list [winfo rootx $view] [winfo rooty $view] \
		[winfo width $view] [winfo height $view]]
	set overlap2 [::layoutGaps::overlap [::layoutGaps::frame .tactics] $rect2]
	list $overlap $overlap2
} -cleanup {
	catch { destroy .tactics }
	set ::board3d::State(embed) 0
	catch { ::board3d::toggleEmbed }
	wm geometry .application $saved
	::layoutGaps::settle 500
} -result {0 0}


# GAP-004: the Marks palette is a board companion and uses the shared helper.
tcltest::test gap004-marks-beside-board {the Marks palette opens clear of the board through besideBoard} \
		-setup {
	set saved [wm geometry .application]
	wm geometry .application 1280x850+40+40
	::layoutGaps::settle 400
	catch { destroy .application.__marks__ }
	set ::marks::Position {}
} -body {
	::marks::open .application
	set dlg .application.__marks__
	::scidb::test::wait::until {[winfo exists $dlg] && [winfo ismapped $dlg]}
	::layoutGaps::settle 400
	set plan [::util::place::besidePlacement $dlg]
	set overlap [::layoutGaps::overlap [::layoutGaps::frame $dlg] [::layoutGaps::boardRect]]
	set byPlanner [expr {[dict exists $plan placed_by] && [dict get $plan placed_by] eq "planner"}]
	list [expr {$overlap == 0}] $byPlanner
} -cleanup {
	catch { ::marks::close }
	catch { destroy .application.__marks__ }
	wm geometry .application $saved
	::layoutGaps::settle 300
} -result {1 1}


# GAP-005: Chesswiz Online and an undocked pane stay inside one monitor's
# work area on open and after a work-area shrink.
tcltest::test gap005-online-and-float-clamped {online and floating panes are inside the work area and re-clamped} \
		-setup {
	set saved [wm geometry .application]
	set savedProperty ""
	if {[regexp {_NET_WORKAREA\([A-Z]+\) = ([0-9, -]+)} [exec xprop -root _NET_WORKAREA] -> savedProperty]} {
		set savedProperty [string trim $savedProperty]
	}
	catch { destroy .online }
	set twm [::application::twm board]
	set floats [::scidb::tk::twm floats $twm]
	if {[llength $floats]} { catch { ::twm::Dock $twm [lindex $floats 0] } }
} -body {
	wm geometry .application 900x700+40+40
	::layoutGaps::settle 300
	set path [::online::window::open]
	::scidb::test::wait::until {[winfo exists $path] && [winfo ismapped $path]}
	::layoutGaps::settle 300
	set area [winfo workarea .application]
	set online [::layoutGaps::inside [::layoutGaps::frame $path] $area]

	# Undock an editor pane and keep it near the bottom-right edge.
	set twm [::application::twm board]
	set leaf [$twm leaf editor]
	::twm::Undock $twm $leaf
	::layoutGaps::settle 400
	set floats [::scidb::tk::twm floats $twm]
	set float [lindex $floats end]
	set insideBefore [::layoutGaps::inside [::layoutGaps::frame $float] $area]
	wm geometry $float "+[expr {[lindex $area 0]+[lindex $area 2]-380}]+[expr {[lindex $area 1]+[lindex $area 3]-320}]"
	::layoutGaps::settle 300

	# Shrink the desktop work area; the one-second watcher must pull both in.
	# Without a window manager there is no _NET_WM_DESKTOP on the window, so
	# the root current-desktop property makes the work area authoritative.
	exec xprop -root -f _NET_CURRENT_DESKTOP 32c -set _NET_CURRENT_DESKTOP 0
	exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "0,0,700,600"
	::layoutGaps::settle 1800
	set shrink [list 0 0 700 600]
	set onlineAfter [::layoutGaps::inside [::layoutGaps::frame $path] $shrink]
	set floatAfter [::layoutGaps::inside [::layoutGaps::frame $float] $shrink]
	list $online $insideBefore $onlineAfter $floatAfter
} -cleanup {
	catch { destroy .online }
	catch {
		set twm [::application::twm board]
		foreach top [::scidb::tk::twm floats $twm] { catch { ::twm::Dock $twm $top } }
	}
	if {$savedProperty ne ""} {
		catch { exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA $savedProperty }
	} else {
		catch { exec xprop -root -remove _NET_WORKAREA }
	}
	catch { exec xprop -root -remove _NET_CURRENT_DESKTOP }
	wm geometry .application $saved
	::layoutGaps::settle 500
} -result {1 1 1 1}

# REVIEW4 GAP-005: coordinates above 99 (and negatives) are numeric, not
# ASCII, so the fold handle does not land on the visible board canvas.
tcltest::test review4-gap005-beside-pack-numeric {numeric candidate order places the fold handle clear of the board view} -body {
	set view {1 126 398 217}
	set packed [::util::place::besidePack {99 129 202 202} {{56 26}} {1 98 398 245} 4 {}]
	set rect [lindex $packed 0]
	list $rect [::layoutGaps::overlap $rect $view]
} -result {{1 98 56 26} 0}

# REVIEW4 GAP-005: the embedded 3D view keeps the folded Media button's top
# clearance instead of resetting it to zero.
tcltest::test review4-gap005-3d-media-button-clear {the 3D view reserves the Media button's height} 		-constraints embed3d -setup {
	catch { .application.nb select .application.nb.board }
	catch { ::application::board::show3D 0 }
	::mediainset::RefreshMediaButton
	::layoutGaps::settle 300
} -body {
	set pane [::mediainset::Pane]
	set button $pane.mediaButton
	set wanted [expr {[winfo reqheight $button] + 8}]
	::application::board::show3D 1
	::layoutGaps::settle 500
	set view $::application::board::Vars(3dwin)
	set info [pack info $view]
	set at [lsearch -exact $info -pady]
	set pady [expr {$at >= 0 ? [lindex $info [expr {$at+1}]] : {0 0}}]
	expr {[lindex $pady 0] >= $wanted}
} -cleanup {
	catch { ::application::board::show3D 0 }
	::layoutGaps::settle 300
} -result 1

# REVIEW4 GAP-001: focus-follows-size must not hold the reflow or content
# collapse behind its baseline, and switching it off must recompute at once.
tcltest::test review4-gap001-follows-size-reflow {focus follows size composes with wide/tall reflow and disable recomputes} -setup {
	set oldGeometry [wm geometry .application]
	.application.nb select .application.nb.board
	::application::reflow::reset
	set t [::application::twm board]
	foreach uid {board editor games dbgames tree media analysis:1} { catch {::application::openPane $uid} }
	catch {::application::focuszoom::disableFollowsSize $t}
	catch {::application::focuszoom::disable $t}
	wm geometry .application 1400x850
	::layoutGaps::settle 700
} -body {
	set t [::application::twm board]
	set editor [$t leaf editor]
	focus -force $editor
	::application::focuszoom::enableFollowsSize $t
	wm geometry .application 820x1100
	::layoutGaps::settle 1200
	set enabled [::application::reflow::mode]
	set guarded [::application::reflow::collapsible? $t]
	# Disabling at the tall size must recompute without another resize.
	::application::focuszoom::disableFollowsSize $t
	::layoutGaps::settle 1200
	set disabled [::application::reflow::mode]
	list $enabled $guarded $disabled
} -cleanup {
	catch { ::application::focuszoom::disableFollowsSize [::application::twm board] }
	catch { ::application::focuszoom::disable [::application::twm board] }
	::application::reflow::reset
	wm geometry .application $oldGeometry
	::layoutGaps::settle 500
} -result {tall 1 tall}

# REVIEW4 GAP-004: root-coordinate clamps respect a negative-origin monitor.
tcltest::test review4-gap004-negative-origin-menu {popup clamping keeps a negative-origin work area} -setup {
	catch { destroy .negmenu }
	menu .negmenu -tearoff 0
	.negmenu add command -label Test
	::layoutGaps::settle 100
} -body {
	lassign [::application::MenuRootClamp . 40 40 .negmenu {-800 -600 800 600}] x y
	list [expr {$x < 0 && $y < 0}]
} -cleanup {
	catch { destroy .negmenu }
} -result {1}

# REVIEW4 GAP-004: a restored floating pane is clamped to the work area it
# maps on, even when its saved coordinates came from a larger monitor.
tcltest::test review4-gap004-restore-clamped {restoring a floating pane keeps it inside the work area} -setup {
	set saved [wm geometry .application]
	set twm [::application::twm board]
	foreach top [::scidb::tk::twm floats $twm] { catch { ::twm::Dock $twm $top } }
	::layoutGaps::settle 300
	wm geometry .application 1200x800+760+250
	::layoutGaps::settle 700
} -body {
	set twm [::application::twm board]
	set leaf [$twm leaf editor]
	::twm::Undock $twm $leaf
	::layoutGaps::settle 700
	set float [lindex [::scidb::tk::twm floats $twm] end]
	wm withdraw $float
	::twm::DoDeiconify $twm $float 500 400 1900 1000 1
	::layoutGaps::settle 700
	list [::layoutGaps::inside [::layoutGaps::frame $float] [winfo workarea $float]]
} -cleanup {
	catch {
		set twm [::application::twm board]
		foreach top [::scidb::tk::twm floats $twm] { catch { ::twm::Dock $twm $top } }
	}
	wm geometry .application $saved
	::layoutGaps::settle 500
} -result {1}

# REVIEW4 GAP-004: reopening a withdrawn Chesswiz Online fits the current
# work area before the once-a-second display watcher gets a turn.
tcltest::test review4-gap004-online-reopen-clamped {reopening online fits a shrunken work area immediately} -setup {
	set saved [wm geometry .application]
	set savedProperty ""
	if {[regexp {_NET_WORKAREA\([A-Z]+\) = ([0-9, -]+)} [exec xprop -root _NET_WORKAREA] -> savedProperty]} {
		set savedProperty [string trim $savedProperty]
	}
	catch { destroy .online }
	wm geometry .application 900x700+40+40
	::layoutGaps::settle 300
	set path [::online::window::open]
	::scidb::test::wait::until {[winfo exists $path] && [winfo ismapped $path]}
	::layoutGaps::settle 300
	::online::window::Hide
	::layoutGaps::settle 200
	exec xprop -root -f _NET_CURRENT_DESKTOP 32c -set _NET_CURRENT_DESKTOP 0
	exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "0,0,700,600"
	::layoutGaps::settle 200
} -body {
	set path [::online::window::open]
	::layoutGaps::settle 250
	list [::layoutGaps::inside [::layoutGaps::frame $path] {0 0 700 600}]
} -cleanup {
	catch { destroy .online }
	if {$savedProperty ne ""} {
		catch { exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA $savedProperty }
	} else {
		catch { exec xprop -root -remove _NET_WORKAREA }
	}
	catch { exec xprop -root -remove _NET_CURRENT_DESKTOP }
	wm geometry .application $saved
	::layoutGaps::settle 500
} -result {1}

# REVIEW4 GAP-003: the Opening Preparation trainer is a playing dialog: it
# must share the board-avoiding helper and the scroll fallback, not open a
# 1,937 px unwrapping control row over the board.
tcltest::test review4-gap003-openingprep-beside-board {the Opening Preparation trainer stays clear of the board} -setup {
	set saved [wm geometry .application]
	set dlg [::application::database::OpeningPrepDialogName test.pgn Normal]
	catch { destroy $dlg }
	.application.nb select .application.nb.board
	wm geometry .application 1000x700+20+20
	::layoutGaps::settle 500
} -body {
	catch { ::application::database::OpenOpeningPrepReport .application test.pgn Normal }
	::scidb::test::wait::until {[winfo exists $dlg] && [winfo ismapped $dlg]} 3000
	::layoutGaps::settle 900
	set overlap [::layoutGaps::overlap [::layoutGaps::frame $dlg] [::layoutGaps::boardRect]]
	set viewport [expr {[winfo exists $dlg.__viewport] && [winfo ismapped $dlg.__viewport]}]
	set width [::layoutGaps::frame $dlg]
	list [expr {$overlap == 0}] $viewport [expr {[lindex $width 2] <= 1000}]
} -cleanup {
	catch { destroy $dlg }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1 1}

# REVIEW4 GAP-002: unplugging a secondary monitor changes the display
# signature even when .application stays on the primary, and the window that
# was on it is re-clamped to an active work area.
tcltest::test review4-gap002-monitor-unplug {a secondary monitor unplug is detected and its windows are relocated} 		-constraints dualmon -setup {
	set saved [wm geometry .application]
	::layoutGaps::setupMonitors
	catch { destroy .online }
	wm geometry .application 700x700+20+20
	::layoutGaps::settle 400
	set path [::online::window::open]
	::scidb::test::wait::until {[winfo exists $path] && [winfo ismapped $path]}
	::layoutGaps::settle 300
	wm geometry $path 500x400+1040+100
	::layoutGaps::settle 300
	::application::displayWatch
	set before [::application::displaySignature]
	exec xrandr --delmonitor RIGHT
	::layoutGaps::settle 300
} -body {
	::application::displayWatch
	::layoutGaps::settle 1200
	set after [::application::displaySignature]
	list [expr {$before ne $after}] \
		[::layoutGaps::inside [::layoutGaps::frame $path] {0 0 1000 1080}]
} -cleanup {
	catch { destroy .online }
	::layoutGaps::clearMonitors
	wm geometry .application $saved
	::layoutGaps::settle 500
} -result {1 1}

# REVIEW4 GAP-003: every board-companion window in the Training and Media
# menus must use the shared beside-board rule and the shared viewport.
proc ::layoutGaps::companionState {dlg} {
	if {![winfo exists $dlg]} { return {0 0 0} }
	set area [winfo workarea $dlg]
	if {![llength $area]} { set area {0 0 [winfo screenwidth $dlg] [winfo screenheight $dlg]} }
	list [expr {[::layoutGaps::overlap [::layoutGaps::frame $dlg] [::layoutGaps::boardRect]] == 0} ] \
		[::layoutGaps::inside [::layoutGaps::frame $dlg] $area] \
		[winfo exists $dlg.__viewport.canvas.body]
}

tcltest::test review4-gap003-stream-beside-board {Training Live Broadcast stays clear of the board} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { destroy .stream }
	::layoutGaps::settle 400
} -body {
	::stream::open .application
	::scidb::test::wait::until {[winfo exists .stream] && [winfo ismapped .stream]}
	::layoutGaps::settle 900
	::layoutGaps::companionState .stream
} -cleanup {
	catch { destroy .stream }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1 1}

tcltest::test review4-gap003-td-beside-board {Tournament Director stays clear of the board and work area} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { ::td::ui::Close }
	::layoutGaps::settle 400
} -body {
	::td::ui::Open {}
	::scidb::test::wait::until {[winfo exists .application.tournamentDirector] \
		&& [winfo ismapped .application.tournamentDirector]}
	::layoutGaps::settle 900
	::layoutGaps::companionState .application.tournamentDirector
} -cleanup {
	catch { ::td::ui::Close }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1 1}

tcltest::test review4-gap003-board3d-beside-board {the 3D viewer stays clear of the board and work area} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { ::board3d::closeViewer }
	::layoutGaps::settle 400
} -body {
	set dlg [::board3d::openViewer .application]
	::scidb::test::wait::until {[winfo exists $dlg] && [winfo ismapped $dlg]}
	::layoutGaps::settle 900
	list [expr {[::layoutGaps::overlap [::layoutGaps::frame $dlg] [::layoutGaps::boardRect]] == 0}] \
		[::layoutGaps::inside [::layoutGaps::frame $dlg] [winfo workarea $dlg]]
} -cleanup {
	catch { ::board3d::closeViewer }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1}

tcltest::test review4-gap003-open-stream-beside-board {the Media menu Open stream dialog stays clear of the board} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { destroy .application.__mediastream__ }
	::layoutGaps::settle 400
} -body {
	::application::media::OpenStream .application
	set dlg .application.__mediastream__
	::scidb::test::wait::until {[winfo exists $dlg] && [winfo ismapped $dlg]}
	::layoutGaps::settle 900
	lassign [::layoutGaps::companionState $dlg] clear inside
	list $clear $inside
} -cleanup {
	catch { destroy .application.__mediastream__ }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1}

tcltest::test review4-gap003-picture-beside-board {the Media picture viewer stays clear of the board and is floating} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { destroy .mediaPicture }
	catch { destroy .layoutGapsPicTree }
	set img [file join [tcltest::temporaryDirectory] layout-gap003.png]
	set photo [image create photo -width 8 -height 8]
	$photo write $img -format png
	image delete $photo
	set tree .layoutGapsPicTree
	ttk::treeview $tree
	$tree insert {} end -id row1 -values [list Pictures Picture $img 0]
	set ::layoutGaps::savedTree $::application::media::Priv(tree)
	set ::application::media::Priv(tree) $tree
	::layoutGaps::settle 400
} -body {
	::mediainset::Choose row1
	::scidb::test::wait::until {[winfo exists .mediaPicture] && [winfo ismapped .mediaPicture]}
	::layoutGaps::settle 900
	lassign [::layoutGaps::companionState .mediaPicture] clear inside viewport
	list $clear $inside [expr {".mediaPicture" in [::application::FloatingWindows]}]
} -cleanup {
	catch { destroy .mediaPicture }
	catch { destroy .layoutGapsPicTree }
	catch { set ::application::media::Priv(tree) $::layoutGaps::savedTree }
	catch { file delete $img }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1 1}

tcltest::test review4-gap003-book-beside-board {the Opening Book editor has a viewport and stays clear of the board} -setup {
	set saved [wm geometry .application]
	wm geometry .application 1000x700+20+20
	catch { ::book::Close }
	::layoutGaps::settle 400
} -body {
	set dlg [::book::openEditor .application]
	::scidb::test::wait::until {[winfo exists $dlg] && [winfo ismapped $dlg]}
	::layoutGaps::settle 900
	::layoutGaps::companionState $dlg
} -cleanup {
	catch { ::book::Close }
	wm geometry .application $saved
	::layoutGaps::settle 400
} -result {1 1 1}

tcltest::cleanupTests
