package require tcltest 2.5
namespace eval ::m4 {
 variable dir [file join $::env(HOME) m4-fixtures]
 file mkdir $dir
 proc write {name text} {
  variable dir
  set path [file join $dir $name]
  set f [open $path w]; fconfigure $f -encoding utf-8
  puts $f $text; close $f
  return $path
 }
 proc convert {kind text} {
  variable dir
  set in [write input.csv $text]
  ::scidb::app::filterRatingList $kind $in $dir/output.txt 1800
  set f [open $dir/output.txt]; set result [read $f]; close $f
  return $result
 }
}
tcltest::test VAL-PD4-007 {Revised standard takes priority independent of header order} -body {
 set result [::m4::convert ecf {ECF_code,full_name,original_standard,revised_standard
999001A,"Fixture, Alpha",1801,1902}]
 string match {*|1902|*} $result
} -result 1
tcltest::test VAL-PD4-008 {Rapid and online cannot replace standard} -body {
 set result [::m4::convert ecf {ECF_code,full_name,revised_rapid,original_standard_online,original_standard,revised_standard
999002B,"Fixture, Beta",2700,2800,1803,0}]
 expr {[string match {*|1803|*} $result] && ![string match {*|2700|*} $result]}
} -result 1
tcltest::test VAL-PD4-005 {Missing rating column fails} -body {
 catch {::m4::convert ecf {ECF_code,full_name
999003C,"Fixture, Gamma"}}
} -result 1
tcltest::test VAL-PD4-011 {Malformed suffix rejects a valid prefix} -body {
 catch {::m4::convert iccf "990001;ENG;IM;Fixture, Delta;20;2200;90;\n<html>blocked</html>"}
} -result 1
tcltest::test VAL-PD4-009 {ICCF RD does not become sex; titles use correspondence namespace} -body {
 set result [::m4::convert iccf {990002;ENG;LGM;Fixture, Epsilon;20;2200;90;}]
 expr {[string match {*|0|-|0|2200|ENG|CLGM|*} $result]}
} -result 1
tcltest::test VAL-PD4-011-quotes {Unterminated quoted CSV rejects valid prefix} -body {
 catch {::m4::convert ecf "ECF_code,full_name,revised_standard\n999004D,\"Fixture, Zeta\",1900\n999005E,\"unfinished"}
} -result 1
file delete -force $::m4::dir
tcltest::cleanupTests
