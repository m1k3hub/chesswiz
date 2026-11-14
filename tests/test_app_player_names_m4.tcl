package require tcltest 2.5
namespace eval ::m4names {
 variable dir [file join $::env(HOME) m4-names]
 file mkdir $dir
 proc nop {args} {return 0}
 proc openBase {} {
  variable dir
  set pgn $dir/input.pgn
  set f [open $pgn w]
  puts $f {[Event "Synthetic"]
[Site "Fixture"]
[Date "2026.01.01"]
[Round "1"]
[White "Fixture, Alpha"]
[Black "Fixture, Beta"]
[WhiteElo "2100"]
[BlackElo "2000"]
[Result "1-0"]

1. e4 {Synthetic comment} e5 2. Nf3 Nc6 1-0}
  close $f
  set base $dir/test.sci
  ::scidb::db::open $pgn ::m4names::nop {} ::m4names::nop {}
  ::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
  ::scidb::db::attach $base $base
  ::scidb::db::copy $pgn $base {} ::m4names::nop {} ::m4names::nop {}
  ::scidb::db::save $base ::m4names::nop {}
  ::scidb::db::close $pgn
  return $base
 }
 proc names {base} {lmap row [::scidb::db::playerLinks $base Normal] {lindex $row 0}}
 proc rename {base old new} {
  ::scidb::db::renamePlayers $base Normal [list [::playerdata::NameIndex $base Normal $old] $old $new]
 }
 proc disk {} {
  variable dir
  set result {}
  foreach path [lsort [glob $dir/test.*]] {
   set f [open $path rb]; lappend result [file tail $path] [read $f]; close $f
  }
  return $result
 }
}
set base [::m4names::openBase]
set original [::m4names::names $base]
set disk [::m4names::disk]
set records [::scidb::db::fingerprints $base Normal]
tcltest::test VAL-PD5-008 {Duplicate source rejected before mutation} -body {
 set i [::playerdata::NameIndex $base Normal {Fixture, Alpha}]
 list [catch {::scidb::db::renamePlayers $base Normal [list $i {Fixture, Alpha} {Fixture, Changed} $i {Fixture, Alpha} {Fixture, Other}]}] [expr {$original eq [::m4names::names $base]}]
} -result {1 1}
tcltest::test VAL-PD5-006-backend {Expected name checked before mutation} -body {
 set i [::playerdata::NameIndex $base Normal {Fixture, Alpha}]
 list [catch {::scidb::db::renamePlayers $base Normal [list $i {Fixture, Stale} {Fixture, Changed}]}] [expr {$original eq [::m4names::names $base]}]
} -result {1 1}
tcltest::test VAL-PD5-010-backend {Collision produces no applied undo operation} -body {
 set result [::m4names::rename $base {Fixture, Alpha} {Fixture, Beta}]
 list [dict get $result renamed] [llength [dict get $result applied]] [llength [dict get $result skipped]]
} -result {0 0 1}
tcltest::test VAL-PD5-011 {Repeated batches preserve untouched names from previous arenas} -body {
 for {set n 0} {$n < 30} {incr n} {
  ::m4names::rename $base {Fixture, Alpha} {Fixture, Changed}
  ::m4names::rename $base {Fixture, Beta} {Fixture, Other}
  ::m4names::rename $base {Fixture, Changed} {Fixture, Alpha}
  ::m4names::rename $base {Fixture, Other} {Fixture, Beta}
 }
 expr {$original eq [::m4names::names $base]}
} -result 1
tcltest::test VAL-PD5-012-disk {Apply leaves files unchanged} -body {
 ::m4names::rename $base {Fixture, Alpha} {Fixture, Changed}
 expr {$disk eq [::m4names::disk]}
} -result 1
tcltest::test VAL-PD5-015 {Raw moves/comments record unchanged} -body {
 expr {$records eq [::scidb::db::fingerprints $base Normal]}
} -result 1
tcltest::test VAL-PD5-013 {Explicit save persists selected names} -body {
 ::scidb::db::save $base ::m4names::nop {}
 ::scidb::db::close $base
 ::scidb::db::open $base ::m4names::nop {} ::m4names::nop {}
 expr {{Fixture, Changed} in [::m4names::names $base] && {Fixture, Alpha} ni [::m4names::names $base]}
} -result 1
tcltest::test VAL-PD5-014 {Close without save preserves previous disk names} -body {
 ::m4names::rename $base {Fixture, Changed} {Fixture, Unsaved}
 ::scidb::db::close $base
 ::scidb::db::open $base ::m4names::nop {} ::m4names::nop {}
 expr {{Fixture, Changed} in [::m4names::names $base] && {Fixture, Unsaved} ni [::m4names::names $base]}
} -result 1
::scidb::db::close $base
file delete -force $::m4names::dir
tcltest::cleanupTests
