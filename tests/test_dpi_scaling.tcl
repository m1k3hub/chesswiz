# Headless tests of the exact shared startup/runtime calibration rule.
package require tcltest 2.5
namespace eval ::scidb::startup { variable testing 1 }
# exec.tcl continues into native argument parsing after defining startup
# helpers; that portion requires the application. Match the startup-guard
# fixture and assert the calibration procedure was actually loaded.
catch {source [file join [file dirname [info script]] .. tcl exec.tcl]}
if {[info commands ::scidb::startup::dpiScaling] eq ""} { error "calibration not loaded" }
foreach {name dpi floor expected} {
 low-invalid 83 1.0 1.0
 lower-bound 84 1.0 1.1666666666666667
 normal 96 1.0 1.3333333333333333
 high 144 1.0 2.0
 upper-bound 288 1.0 4.0
 high-invalid 289 1.0 1.0
 preference 144 2.5 2.5
 round-down 83.4 1.0 1.0
 round-up 83.6 1.0 1.1666666666666667
} {
 tcltest::test dpi-rule-$name {startup bounds, rounding and preference floor} -body {
  ::scidb::startup::dpiScaling $dpi $floor
 } -result $expected
}
tcltest::test dpi-rule-aqua-normal {a move back from Retina uses Aqua logical points} -body {
 ::scidb::startup::dpiScaling 72 1.0 aqua
} -result 1.0
tcltest::test dpi-rule-aqua-retina {Retina backing factor uses the shared conversion} -body {
 ::scidb::startup::dpiScaling 144 1.0 aqua
} -result 2.0
tcltest::cleanupTests
