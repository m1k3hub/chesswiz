package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

foreach state {mapped child-unmapped parent-unmapped destroyed} {
 tcltest::test progress-parent-$state {progress accepts child, withdrawn and destroyed parents} -setup {
  toplevel .progressHost
  wm geometry .progressHost 400x300+40+40
  frame .progressHost.child
  pack .progressHost.child
  update
  switch $state {
   child-unmapped {pack forget .progressHost.child}
   parent-unmapped {wm withdraw .progressHost; update}
   destroyed {destroy .progressHost}
  }
 } -body {
  set area [::util::place::workAreaFor .progressHost.child]
  ::dialog::progressbar::open .progressProbe -parent .progressHost.child
  update
  list [llength $area] [expr {[lindex $area 2] > 0 && [lindex $area 3] > 0}] \
   [winfo ismapped .progressProbe]
 } -cleanup {
  catch {destroy .progressProbe}
  catch {destroy .progressHost}
 } -result {4 1 1}
}

tcltest::test progress-parent-screen-fallback {destroyed parent with no mapped main window uses screen} -setup {
 set savedMain $::util::place::mainWindow
 set ::util::place::mainWindow .noSuchMain
} -body {
 expr {[::util::place::workAreaFor .noSuchParent] eq \
  [list 0 0 [winfo screenwidth .] [winfo screenheight .]]}
} -cleanup {set ::util::place::mainWindow $savedMain} -result 1

tcltest::cleanupTests
