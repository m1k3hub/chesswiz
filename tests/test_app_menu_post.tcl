# ======================================================================
# Scidb App Test - the Main Menu menubutton and its cascades
# ======================================================================
# Laptop runs 160-164: a real click on .application.nb.menu_main posted the
# drop-down erratically, cascades did not open, and the log filled with
#
#   [bgerror] ::application::twm: no twm selected
#   in ::menu::FillDynamic LoadLayout .application.nb.menu_main.entries.view...
#
# The Information notebook page is selected at startup and owns no layout,
# so ::application::twm raises by contract. The View > Layout > Load Layout
# cascade filled itself from that call while the menu was posted; the error
# escaped from the cascade's -postcommand, the cascade stayed closed, and
# ::scidb::bgerror released the menubutton's grab (it releases any grab it
# finds), which is what made the menu post and unpost erratically.
#
# These tests drive the real path with generated mouse events on the
# menubutton and post the cascade chain, and they insist that
# ::application::twm keeps raising on a page without a layout: the menu
# handles the case, the contract is unchanged.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::mainmenu {
	variable mb .application.nb.menu_main
	variable nb .application.nb
	variable errors {}
}

proc ::scidb::test::mainmenu::FindCascade {menu pattern} {
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return "" }
	for {set i 0} {$i <= $n} {incr i} {
		if {[$menu type $i] ne "cascade"} { continue }
		if {[string match $pattern [$menu entrycget $i -label]]} { return $i }
	}
	return ""
}

# A real click on the menubutton: the mouse enters the widget, presses and
# releases button 1 over it. Tk's Menubutton <1> binding only posts while
# ::tk::Priv(inMenubutton) is the widget, which <Enter> sets.
proc ::scidb::test::mainmenu::Click {w} {
	set cx [expr {[winfo width $w] / 2}]
	set cy [expr {[winfo height $w] / 2}]
	event generate $w <Enter>
	event generate $w <ButtonPress-1> -x $cx -y $cy
	event generate $w <ButtonRelease-1> -x $cx -y $cy
	update
}

proc ::scidb::test::mainmenu::Unpost {} {
	catch { ::tk::MenuUnpost {} }
	catch { update }
}

# Post one cascade of a posted menu the way MenuMotion's hover timer does,
# then report whether the cascade's own menu opened.
proc ::scidb::test::mainmenu::PostCascade {menu pattern} {
	set index [FindCascade $menu $pattern]
	if {$index eq ""} { return [list no-such-cascade 0] }
	set sub [$menu entrycget $index -menu]
	set rc [catch {$menu postcascade $index} err]
	catch { update }
	return [list $rc [expr {$rc == 0 && [winfo exists $sub] && [winfo ismapped $sub]}]]
}

proc ::scidb::test::mainmenu::CascadeMenu {menu pattern} {
	set index [FindCascade $menu $pattern]
	if {$index eq ""} { return "" }
	return [$menu entrycget $index -menu]
}

# Record background errors instead of showing them (a notice card in a
# headless run), and put the application's handler back afterwards.
proc ::scidb::test::mainmenu::CaptureBgErrors {} {
	variable errors
	set errors {}
	set saved ::scidb::test::mainmenu::savedBgError
	if {[llength [info commands $saved]]} { return }
	if {[llength [info commands ::scidb::bgerror]]} {
		rename ::scidb::bgerror $saved
	}
	proc ::scidb::bgerror {err args} {
		lappend ::scidb::test::mainmenu::errors $err
	}
}

proc ::scidb::test::mainmenu::ReleaseBgErrors {} {
	set saved ::scidb::test::mainmenu::savedBgError
	catch { rename ::scidb::bgerror {} }
	if {[llength [info commands $saved]]} { rename $saved ::scidb::bgerror }
	interp bgerror {} ::scidb::bgerror
}

proc ::scidb::test::mainmenu::PostOne {menu index} {
	# Post one cascade and the cascades inside it, the two levels a mouse
	# travels through on the way to a command; report what did not open.
	set bad {}
	set label [$menu entrycget $index -label]
	set sub [$menu entrycget $index -menu]
	if {[catch {$menu postcascade $index} err]} {
		$menu postcascade none
		catch { update }
		return [list [string trim $label]:$err]
	}
	catch { update }
	if {![winfo exists $sub] || ![winfo ismapped $sub]} {
		lappend bad [string trim $label]:not-mapped
	} else {
		set n [$sub index end]
		if {$n ne "" && $n ne "none"} {
			for {set j 0} {$j <= $n} {incr j} {
				if {[$sub type $j] ne "cascade"} { continue }
				set child [$sub entrycget $j -menu]
				if {[catch {$sub postcascade $j} err]} {
					lappend bad [string trim $label]/[$sub entrycget $j -label]:$err
					continue
				}
				catch { update }
				if {![winfo exists $child] || ![winfo ismapped $child]} {
					lappend bad [string trim $label]/[$sub entrycget $j -label]:not-mapped
				}
				$sub postcascade none
				catch { update }
			}
		}
	}
	$menu postcascade none
	catch { update }
	return $bad
}

proc ::scidb::test::mainmenu::HasTWM {} {
	if {[catch { set twm [::menu::CurrentTWM] }]} { return 0 }
	return [expr {$twm ne ""}]
}

proc ::scidb::test::mainmenu::SelectPage {page} {
	Unpost
	set w $::scidb::test::mainmenu::nb.$page
	# Startup adds the pages from <<TwmReady>>; wait for the one asked for.
	for {set i 0} {$i < 20 && ![winfo exists $w]} {incr i} { after 50; update }
	$::scidb::test::mainmenu::nb select $w
	update
	return [$::scidb::test::mainmenu::nb select]
}

tcltest::test main-menu-real-click {a real click on the menubutton posts its drop-down} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage information
} -body {
	::scidb::test::mainmenu::Click $::scidb::test::mainmenu::mb
	set m [$::scidb::test::mainmenu::mb cget -menu]
	list \
		[set ::tk::Priv(postedMb)] \
		[expr {[winfo ismapped $m] ? 1 : 0}] \
		[grab current] \
		[$::scidb::test::mainmenu::nb select] \
		$::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::ReleaseBgErrors
} -result [list .application.nb.menu_main 1 .application.nb.menu_main .application.nb.information {}]

tcltest::test main-menu-cascades-without-layout {View > Layout > Load Layout opens on a page with no layout} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage information
	::scidb::test::mainmenu::Click $::scidb::test::mainmenu::mb
	set m [$::scidb::test::mainmenu::mb cget -menu]
} -body {
	set view [::scidb::test::mainmenu::PostCascade $m *View*]
	set viewMenu [::scidb::test::mainmenu::CascadeMenu $m *View*]
	set layout [::scidb::test::mainmenu::PostCascade $viewMenu *Layout*]
	set layoutMenu [::scidb::test::mainmenu::CascadeMenu $viewMenu *Layout*]
	set load [::scidb::test::mainmenu::PostCascade $layoutMenu *Load*]
	# the menu keeps its grab: no background error released it
	list $view $layout $load [grab current] $::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::ReleaseBgErrors
} -result [list [list 0 1] [list 0 1] [list 0 1] .application.nb.menu_main {}]

tcltest::test main-menu-file-cascade {File and File > New Database open from the posted drop-down} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage information
	::scidb::test::mainmenu::Click $::scidb::test::mainmenu::mb
	set m [$::scidb::test::mainmenu::mb cget -menu]
} -body {
	set file [::scidb::test::mainmenu::PostCascade $m *File*]
	set fileMenu [::scidb::test::mainmenu::CascadeMenu $m *File*]
	set newDb [::scidb::test::mainmenu::PostCascade $fileMenu *New*]
	list $file $newDb $::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::ReleaseBgErrors
} -result [list [list 0 1] [list 0 1] {}]

tcltest::test main-menu-twm-contract {::application::twm still raises where there is no layout, the menu just asks} -setup {
	::scidb::test::mainmenu::SelectPage information
} -body {
	set raised [catch { ::application::twm } err]
	list $raised [string match {*no twm selected*} $err] [expr {![::scidb::test::mainmenu::HasTWM]}]
} -cleanup {
	::scidb::test::mainmenu::Unpost
} -result {1 1 1}

tcltest::test main-menu-layouts-on-board {the same cascade lists layouts when the board page is current} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage board
	::scidb::test::mainmenu::Click $::scidb::test::mainmenu::mb
	set m [$::scidb::test::mainmenu::mb cget -menu]
} -body {
	set view [::scidb::test::mainmenu::PostCascade $m *View*]
	set viewMenu [::scidb::test::mainmenu::CascadeMenu $m *View*]
	set layout [::scidb::test::mainmenu::PostCascade $viewMenu *Layout*]
	set layoutMenu [::scidb::test::mainmenu::CascadeMenu $viewMenu *Layout*]
	set load [::scidb::test::mainmenu::PostCascade $layoutMenu *Load*]
	set loadMenu [::scidb::test::mainmenu::CascadeMenu $layoutMenu *Load*]
	set entries 0
	if {$loadMenu ne "" && [winfo exists $loadMenu]} { set entries [$loadMenu index end] }
	list $view $layout $load [expr {$entries ne "" && $entries ne "none" && $entries >= 0}] \
		[::scidb::test::mainmenu::HasTWM] $::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::SelectPage information
	::scidb::test::mainmenu::ReleaseBgErrors
} -result [list [list 0 1] [list 0 1] [list 0 1] 1 1 {}]

tcltest::test main-menu-every-cascade {every drop-down cascade opens on the Information page without a background error} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage information
	::scidb::test::mainmenu::Click $::scidb::test::mainmenu::mb
	set m [$::scidb::test::mainmenu::mb cget -menu]
} -body {
	set bad {}
	for {set index 0} {$index <= [$m index end]} {incr index} {
		if {[$m type $index] ne "cascade"} { continue }
		lappend bad {*}[::scidb::test::mainmenu::PostOne $m $index]
	}
	list $bad $::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::ReleaseBgErrors
} -result {{} {}}

tcltest::test main-menu-focus-zoom-without-layout {focus-follows-size reports no error on a page without a layout and still toggles on the board} -setup {
	::scidb::test::mainmenu::CaptureBgErrors
	::scidb::test::mainmenu::SelectPage information
} -body {
	set here [::action::run view.focus_zoom {}]
	::scidb::test::mainmenu::SelectPage board
	set on [::action::run view.focus_zoom {}]
	set off [::action::run view.focus_zoom {}]
	catch { ::application::focuszoom::disable [::menu::CurrentTWM] }
	list $here $on $off $::scidb::test::mainmenu::errors
} -cleanup {
	::scidb::test::mainmenu::Unpost
	::scidb::test::mainmenu::SelectPage information
	::scidb::test::mainmenu::ReleaseBgErrors
} -result [list 0 1 0 {}]

tcltest::cleanupTests
