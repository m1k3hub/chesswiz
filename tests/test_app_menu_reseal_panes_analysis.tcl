# Retained from VU-reg-retry: default and absent analysis panes.
# Run this first in a fresh app, before other pane toggles normalize the layout.
package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::pane {}

proc ::scidb::test::pane::Suffixes {} {
	return {analysis}
}

proc ::scidb::test::pane::Leaves {} {
	set twm [::menu::PaneTWM]
	if {$twm eq ""} { return {} }
	return [$twm leaves]
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

tcltest::test panes-analysis-default-and-absent {native pane leaves and posted checks toggle both ways} -body {

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
    if {$path eq "click"} {$sub invoke $i} else {::action::invoke menu.view.panes.$suffix}
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

return ok
} -result ok

catch {destroy .vp}
::tcltest::cleanupTests
