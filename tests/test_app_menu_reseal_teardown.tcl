# ======================================================================
# View > Panes rows are real toggles (VAL-REG-010)
# ======================================================================
# Every posted pane row is a checkbutton bound to one registry action. The
# action asks the layout, never the check mark: a visible pane is hidden, an
# absent but openable pane is created through ::application::openPane, and a
# pane kind this build cannot create is posted disabled with a reason.
# Each id is invoked twice (hide/show or open/hide) by id and by the posted
# row's own -command; the twm leaves and the posted check mark are asserted
# after every call. The five dynamic Game rows are invoked as well.
# A pane hidden while the board still had a delayed rebuild queued for its
# canvas (a window resize) must drop that rebuild with the canvas: the last
# test reproduces the state that made the next file fail.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::pane {}

proc ::scidb::test::pane::Suffixes {} {
	return {board editor games players events sites annotators positions tree analysis media report assistant explorer}
}

proc ::scidb::test::pane::Leaves {} {
	set twm [::menu::PaneTWM]
	if {$twm eq ""} { return {} }
	return [$twm leaves]
}

# Restore the layout a test found. A test must not leave a hidden or an
# extra pane for the files that run after it.
proc ::scidb::test::pane::Restore {initial} {
	set twm [::menu::PaneTWM]
	if {$twm eq ""} { return }
	foreach uid [$twm leaves] {
		if {$uid ni $initial} {
			catch { ::application::twm::ChangeState $twm $uid }
		}
	}
	foreach uid $initial {
		if {$uid ni [$twm leaves]} {
			catch { ::application::openPane $uid }
		}
	}
	update idletasks
}

proc ::scidb::test::pane::PostFill {menu} {
	set pc ""
	catch { set pc [$menu cget -postcommand] }
	if {$pc ne ""} { catch { uplevel #0 $pc } }
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		if {[$menu type $i] ne "cascade"} { continue }
		set sub ""
		catch { set sub [$menu entrycget $i -menu] }
		if {$sub ne "" && [winfo exists $sub]} {
			::scidb::test::pane::PostFill $sub
		}
	}
}

proc ::scidb::test::pane::FillView {menu} {
	set view $menu.[::menu::WidgetName [::menu::MC View]]
	if {![winfo exists $view]} { return "" }
	::scidb::test::pane::PostFill $view
	return $view
}

proc ::scidb::test::pane::FindRow {menu id} {
	set want "::action::run $id"
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return "" }
	for {set i 0} {$i <= $n} {incr i} {
		set cmd ""
		catch { set cmd [string trim [$menu entrycget $i -command]] }
		if {$cmd eq $want} { return $i }
	}
	return ""
}

proc ::scidb::test::pane::RowState {menu index} {
	set type ""
	set state ""
	set var ""
	set checked ""
	catch { set type [$menu type $index] }
	catch { set state [$menu entrycget $index -state] }
	catch { set var [$menu entrycget $index -variable] }
	if {$var ne "" && [info exists $var]} { set checked [set $var] }
	return [list $type $state $var $checked]
}

proc ::scidb::test::pane::Nop {args} { return 0 }

proc ::scidb::test::pane::Base {dir name games} {
	file mkdir $dir
	set file [file join $dir ${name}_[pid].sci]
	file delete {*}[glob -nocomplain [file rootname $file].*]
	set fh [open ${file}.pgn w]
	for {set i 0} {$i < $games} {incr i} {
		puts $fh "\[Event \"Event $i\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 *\n"
	}
	close $fh
	::scidb::db::open ${file}.pgn ::scidb::test::pane::Nop {} ::scidb::test::pane::Nop {}
	::scidb::db::new $file Normal [::application::database::lookupType OpeningsWhite]
	::scidb::db::attach $file $file
	::scidb::db::copy ${file}.pgn $file {} ::scidb::test::pane::Nop {} ::scidb::test::pane::Nop {}
	::scidb::db::save $file ::scidb::test::pane::Nop {}
	::scidb::db::close ${file}.pgn
	file delete ${file}.pgn
	return $file
}

proc ::scidb::test::pane::Stash {cmd} {
	return ::scidb::test::pane::Saved[string map {:: _} $cmd]
}

proc ::scidb::test::pane::Capture {cmd body} {
	rename $cmd [::scidb::test::pane::Stash $cmd]
	proc $cmd args $body
}

proc ::scidb::test::pane::Release {cmd} {
	set stash [::scidb::test::pane::Stash $cmd]
	rename $cmd {}
	rename $stash $cmd
}

# Record background errors instead of showing them (a notice card in a
# headless run), and put the application's handler back afterwards.
proc ::scidb::test::pane::CaptureBgErrors {} {
	if {[llength [info commands ::scidb::test::pane::SavedBg]]} { return }
	if {[llength [info commands ::scidb::bgerror]]} {
		rename ::scidb::bgerror ::scidb::test::pane::SavedBg
	}
	proc ::scidb::bgerror {err args} {
		lappend ::scidb::test::pane::errors $err
	}
}

proc ::scidb::test::pane::ReleaseBgErrors {} {
	catch { rename ::scidb::bgerror {} }
	if {[llength [info commands ::scidb::test::pane::SavedBg]]} {
		rename ::scidb::test::pane::SavedBg ::scidb::bgerror
	}
	interp bgerror {} ::scidb::bgerror
}


set ::reg6PaneErrors {}
proc ::reg6CaptureBg {cmd op} {
 lappend ::reg6PaneErrors [lindex $cmd 1]
 puts [list TEARDOWN_BGERROR $cmd]
}
set ::reg6Bg [lindex [interp bgerror {}] 0]
if {![llength [info commands $::reg6Bg]]} {auto_load $::reg6Bg}
trace add execution $::reg6Bg enter ::reg6CaptureBg
source tests/app_actions_support.tcl
::scidb::test::actions::ready
::action::run open_database [dict create path [::scidb::test::actions::fixture]]
::action::run open_game {number 1 move 1 after white}
::application::openPane board
update
menu .vp -tearoff 0
::menu::BuildDropdown .vp
set v [::scidb::test::pane::FillView .vp]
set sub {}
for {set i 0} {$i <= [$v index end]} {incr i} {if {[$v type $i] eq "cascade" && [string trim [$v entrycget $i -label]] eq "Panes"} {set sub [$v entrycget $i -menu]}}
set bad {}
foreach initial {default absent} {
 foreach suffix [::scidb::test::pane::Suffixes] {
  if {![::menu::PaneOpenable $suffix]} {puts [list UNOPENABLE $suffix reason [::menu::PaneReason $suffix]];continue}
  set uid [::menu::PaneLayoutUid $suffix]
  if {$initial eq "absent" && $uid in [::scidb::test::pane::Leaves]} {::action::invoke menu.view.panes.$suffix;update}
  foreach path {id click} {
   set before [expr {$uid in [::scidb::test::pane::Leaves]}]
   foreach step {1 2} {
    $sub post 100 100
    update
    set i [::scidb::test::pane::FindRow $sub menu.view.panes.$suffix]
    if {$i eq {}} {error "missing $suffix"}
    if {[info exists ::env(OBJECT_EVIDENCE)] && $step == 1 && $suffix eq "editor"} {exec import -window root [file join $::env(OBJECT_EVIDENCE) VAL-REG-010-$initial-$path.png]}
    if {$path eq "click"} {
     set x [expr {[winfo rootx $sub]+20}]
     set y [expr {[winfo rooty $sub]+[$sub yposition $i]+8}]
     exec xdotool mousemove $x $y
     exec xdotool click 1
     update
    } else {::action::invoke menu.view.panes.$suffix}
    $sub unpost
    update
    $sub post 100 100
    update
    set i [::scidb::test::pane::FindRow $sub menu.view.panes.$suffix]
    set state [::scidb::test::pane::RowState $sub $i]
    set after [expr {$uid in [::scidb::test::pane::Leaves]}]
    set want [expr {$step == 1 ? !$before : $before}]
    puts [list PANE $initial $path $suffix step $step before $before after $after want $want row $state leaves [::scidb::test::pane::Leaves]]
    if {$after != $want || [lindex $state 3] != $want} {lappend bad [list $initial $path $suffix $step $state $after $want]}
    $sub unpost
   }
  }
 }
}
puts [list VALIDATOR_PANE_BAD $bad]
if {[llength $bad]} {error $bad}

for {set i 0} {$i < 12} {incr i} {after 50;update}
trace remove execution $::reg6Bg enter ::reg6CaptureBg
tcltest::test reg6-full-native-pane-sequence {loaded default and absent panes toggle by id and physical click without bgerrors} -body {
 list $bad $::reg6PaneErrors
} -result {{} {}}
::tcltest::cleanupTests
