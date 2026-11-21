package require tcltest 2.5
set root [file join [file dirname [info script]] .. tcl]
source [file join $root command-table.tcl]
source [file join $root command-line.tcl]
source [file join $root command-learning.tcl]
namespace eval ::learningTest {variable Values {Main Other}}
proc ::learningTest::source {type query} {
 set out {}
 foreach v $::learningTest::Values {if {[::commandline::NameMatch $query $v]} {lappend out $v}}
 return $out
}
set ::commandline::Source ::learningTest::source
set channel [file tempfile path]; close $channel
set ::commandline::LearningFile $path
::tcltest::test command-learning-frequency {frequent then recent picks precede lexical quality} -body {
 set rows [::commandline::Suggest {switch to}]
 # Incomplete commands cannot be aliases; picks are concrete commands sharing a prefix.
 set ::learningTest::Values {{Main Alpha} {Main Beta}}
 set rows [::commandline::Suggest {switch to Main}]
 set second [lindex $rows 1]
 ::commandline::RecordPick $second
 ::commandline::RecordPick $second
 ::commandline::RecordPick [lindex $rows 0]
 dict get [lindex [::commandline::Suggest {switch to Main}] 0] args database
} -result {Main Beta}
::tcltest::test command-alias-exact {only the complete alias matches and it keeps exact slots} -body {
 set row [lindex [::commandline::Suggest {switch to Main Alpha}] 0]
 ::commandline::AddAlias {main db} $row
 list [dict get [lindex [::commandline::Suggest {main db}] 0] args database] [::commandline::Suggest {main d}]
} -result {{Main Alpha} {}}
::tcltest::test command-alias-restart {history and aliases survive reload as data} -body {
 set ::commandline::Loaded 0; set ::commandline::Picks {}; set ::commandline::Aliases {}
 list [dict get [lindex [::commandline::Suggest {main db}] 0] args database] [dict size $::commandline::Picks]
} -result {{Main Alpha} 2}
::tcltest::test command-alias-stale {closed databases cannot be revived by an alias} -body {
 set ::learningTest::Values {Other}
 ::commandline::Suggest {main db}
} -result {}
::tcltest::test command-alias-injection {alias names are data and never evaluated} -body {
 set ::learningTest::Values {Main}
 set ::injected 0
 ::commandline::AddAlias {[set ::injected 1]} [lindex [::commandline::Suggest {switch to Main}] 0]
 ::commandline::Suggest {[set ::injected 1]}
 set ::injected
} -result 0
::tcltest::test command-alias-corrupt {corrupt storage never executes script or blocks commands} -body {
 set f [open $path w]; puts $f {set ::injected 1}; close $f
 set ::commandline::Loaded 0; set ::commandline::Aliases {}; set ::commandline::Picks {}
 set rows [::commandline::Suggest {list engines}]
 list $::injected [dict get [lindex $rows 0] action]
} -result {0 list_engines}
::tcltest::test command-alias-missing {an incomplete row cannot be saved} -body {
 catch {::commandline::AddAlias broken [lindex [::commandline::Suggest {switch to}] 0]}
} -result 1
file delete $path
::tcltest::cleanupTests
