package require tcltest 2.5
source -encoding utf-8 [file join [file dirname [file normalize [info script]]] app_wait.tcl]
namespace eval ::m4install {
 variable dir [file join $::env(HOME) m4-install]
 file mkdir $dir
 variable requests 0
 proc contents {path} {set f [open $path rb]; set s [read $f]; close $f; return $s}
 proc walk {w} {
  set out [list $w]
  foreach child [winfo children $w] {lappend out {*}[walk $child]}
  return $out
 }
}
set input $::m4install::dir/input.csv
set f [open $input w]
puts $f {ECF_code,full_name,revised_standard
999800A,"Fixture, Install",2000}
close $f
rename ::application::download::Get ::m4install::realGet
proc ::application::download::Get {args} {incr ::m4install::requests; error {Network forbidden in tests}}
rename ::dialog::question ::m4install::realQuestion
proc ::dialog::question {args} {return cancel}
tcltest::test VAL-PD4-001 {Official source catalog and restrictions} -body {
 expr {[dict get [::playerdata::ListSource ecf] url] eq "https://rating.englishchess.org.uk/api/rating-list/csv"
 && [string match {*noncommercial*impressum*} [dict get [::playerdata::ListSource dwz] note]]
 && [string match {*class-C*help/api*} [dict get [::playerdata::ListSource ecf] note]]
 && [dict get [::playerdata::ListSource iccf] how] eq "file"}
} -result 1
tcltest::test VAL-PD4-002 {Opening list dialog makes no download request} -body {
 ::playerdata::ratingLists .application
 set ::m4install::requests
} -result 0
tcltest::test VAL-PD4-018 {USCF has no bulk source or fallback} -body {
 list $::playerdata::ListKinds [catch {::playerdata::ListSource uscf}] $::m4install::requests
} -result {{dwz ecf iccf} 1 0}
tcltest::test VAL-PD4-019 {Provenance separates acquisition and unknown effective period} -body {
 ::playerdata::installList ecf $input
 set info [::playerdata::listInfo ecf]
 list [dict get $info source] [dict get $info effectivePeriod] [dict get $info schema] [expr {[dict get $info bytes] == [file size $input]}] [dict get $info activation]
} -result {ecf unknown chesswiz-rating-list-v1 1 next-start}
tcltest::test VAL-PD4-012 {Conversion failure preserves prior cache and active dictionary} -body {
 set before [::m4install::contents [::playerdata::listFile ecf]]
 set f [open $input w]; puts $f {<html>403</html>}; close $f
 set failed [catch {::playerdata::installList ecf $input}]
 list $failed [expr {$before eq [::m4install::contents [::playerdata::listFile ecf]]}]
} -result {1 1}
tcltest::test VAL-PD4-012-numeric-ui {Real menu.db.player.lists action rejects non-numeric DWZ/ECF rows via Fetch buttons and preserves cache} -setup {
 set ::m4install::errMsgs {}
 set ::m4install::infoMsgs {}
 rename ::dialog::error ::m4install::realError
 rename ::dialog::info ::m4install::realInfo
 proc ::dialog::error {args} { lappend ::m4install::errMsgs [dict get $args -message] }
 proc ::dialog::info {args} { lappend ::m4install::infoMsgs [dict get $args -message] }
 file delete -force [::playerdata::listFile dwz] [::playerdata::listInfoFile dwz]
 set ::m4install::badDwzZip [file join $::m4install::dir bad-dwz.zip]
 exec python3 -c {
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('spieler.csv', 'ZPS,Mitgliedsnummer,"Name,Vorname",DWZ\n99999,1,"Fixture, Valid",1900\n99999,abc,"Fixture, BadMember",1900\n'.encode('cp1252'))
} $::m4install::badDwzZip
} -body {
 set beforeEcf [::m4install::contents [::playerdata::listFile ecf]]
 proc ::application::download::Get {url done} {
  if {[string match *englishchess* $url]} {
   set payload "ECF_code,full_name,revised_standard\n999001A,\"Fixture, Valid\",1900\n999002B,\"Fixture, BadRating\",abc\n"
  } else {
   set payload [::m4install::contents $::m4install::badDwzZip]
  }
  uplevel #0 [list {*}$done [dict create ok 1 data $payload code 200]]
 }
 proc ::dialog::question {args} {
  if {[dict exists $args -embed]} {
   set w [toplevel .m4_lists_numeric]
   uplevel #0 [dict get $args -embed] [list $w TkDefaultFont TkDefaultFont]
   $w.buttonecf invoke
   $w.buttondwz invoke
   destroy $w
  }
  return cancel
 }
 ::application::switchTab database
 ::action::run menu.db.player.lists
 list \
  [llength $::m4install::errMsgs] \
  [llength $::m4install::infoMsgs] \
  [expr {$beforeEcf eq [::m4install::contents [::playerdata::listFile ecf]]}] \
  [file exists [::playerdata::listFile dwz]]
} -cleanup {
 proc ::application::download::Get {args} {incr ::m4install::requests; error {Network forbidden in tests}}
 proc ::dialog::question {args} {return cancel}
 rename ::dialog::error {}
 rename ::m4install::realError ::dialog::error
 rename ::dialog::info {}
 rename ::m4install::realInfo ::dialog::info
} -result {2 0 1 0}
tcltest::test VAL-PD4-012-grade-overflow-ui {Real modal menu.db.player.lists dialog rejects overflowing legacy ECF grade and preserves installed cache} -setup {
 ::scidb::test::wait::ready
 set ::m4install::validPriorCsv [file join $::m4install::dir valid-prior.csv]
 set ch [open $::m4install::validPriorCsv w]
 puts $ch "ECF_code,full_name,revised_standard\n999002B,\"Fixture, Prior\",1900"
 close $ch
 ::playerdata::installList ecf $::m4install::validPriorCsv
 foreach c $::dialog::notice::Cards {
  ::dialog::notice::Dismiss [lindex $c 0]
 }
 set ::m4install::gradeRequests 0
 set ::m4install::gradeClicked 0
 set ::m4install::gradeAnswer {}
 set ::m4install::gradeTimer {}
 set ::m4install::reportTrace [list apply {{cmd op} {set ::m4install::gradeAnswer [lindex $cmd 3]}}]
 trace add execution ::playerdata::ReportList enter $::m4install::reportTrace
 rename ::dialog::question ::m4install::stubQuestion
 rename ::m4install::realQuestion ::dialog::question
 proc ::m4install::clickRealEcfFetch {} {
  foreach w [::m4install::walk .] {
   if {[string match *.buttonecf $w] && [winfo exists $w]} {
    set ::m4install::gradeClicked 1
    $w invoke
    set ::m4install::gradeTimer [after 50 ::m4install::closeRealListsDialog]
    return
   }
  }
  set ::m4install::gradeTimer [after 50 ::m4install::clickRealEcfFetch]
 }
 proc ::m4install::closeRealListsDialog {} {
  if {$::m4install::gradeAnswer eq ""} {
   set ::m4install::gradeTimer [after 50 ::m4install::closeRealListsDialog]
   return
  }
  foreach w [::m4install::walk .] {
   if {[string match *.bt-cancel $w] && [winfo exists $w]} {
    $w invoke
    return
   }
  }
  error {No real dialog Close button found}
 }
} -body {
 set beforeEcf [::m4install::contents [::playerdata::listFile ecf]]
 set beforeInfo [::m4install::contents [::playerdata::listInfoFile ecf]]
 proc ::application::download::Get {url done} {
  incr ::m4install::gradeRequests
  set payload "ECF_code,full_name,grade\n999001A,\"Fixture, Overflow\",536871087\n"
  after idle [list {*}$done [dict create ok 1 code 200 data $payload]]
 }
 ::application::switchTab database
 set ::m4install::gradeTimer [after 50 ::m4install::clickRealEcfFetch]
 ::action::run menu.db.player.lists
 set afterEcf [::m4install::contents [::playerdata::listFile ecf]]
 set afterInfo [::m4install::contents [::playerdata::listInfoFile ecf]]
 set cardKinds [lmap c $::dialog::notice::Cards {lindex $c 1}]
 set leftovers [glob -nocomplain [::playerdata::listFile ecf].* [::playerdata::listInfoFile ecf].*]
 list \
  $::m4install::gradeClicked \
  $::m4install::gradeRequests \
  [dict get $::m4install::gradeAnswer ok] \
  $cardKinds \
  [expr {$beforeEcf eq $afterEcf}] \
  [expr {$beforeInfo eq $afterInfo}] \
  [string match {*|2000|*} $afterEcf] \
  [llength $leftovers]
} -cleanup {
 if {$::m4install::gradeTimer ne ""} {
  catch {after cancel $::m4install::gradeTimer}
 }
 catch {trace remove execution ::playerdata::ReportList enter $::m4install::reportTrace}
 foreach c $::dialog::notice::Cards {
  ::dialog::notice::Dismiss [lindex $c 0]
 }
 rename ::dialog::question ::m4install::realQuestion
 rename ::m4install::stubQuestion ::dialog::question
 proc ::application::download::Get {args} {incr ::m4install::requests; error {Network forbidden in tests}}
} -result {1 1 0 error 1 1 0 0}
tcltest::test VAL-PD4-012-pipe-ui {Real menu.db.player.lists Fetch and Choose File actions reject pipe-containing DWZ/ECF/ICCF records} -setup {
 set ::m4install::errMsgs {}
 set ::m4install::infoMsgs {}
 rename ::dialog::error ::m4install::realError
 rename ::dialog::info ::m4install::realInfo
 rename ::tk_getOpenFile ::m4install::realChooser
 proc ::dialog::error {args} { lappend ::m4install::errMsgs [dict get $args -message] }
 proc ::dialog::info {args} { lappend ::m4install::infoMsgs [dict get $args -message] }
 file delete -force [::playerdata::listFile dwz] [::playerdata::listInfoFile dwz] \
  [::playerdata::listFile iccf] [::playerdata::listInfoFile iccf]
 set ::m4install::pipeDwzZip [file join $::m4install::dir pipe-dwz.zip]
 exec python3 -c {
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('spieler.csv', 'ZPS,Mitgliedsnummer,"Name,Vorname",DWZ\n99999,1,"Fixture, Valid",1900\n"99|999",2,"Fixture, PipeZps",1900\n'.encode('cp1252'))
} $::m4install::pipeDwzZip
 set ::m4install::pipeIccfCsv [file join $::m4install::dir pipe-iccf.csv]
 set ch [open $::m4install::pipeIccfCsv w]
 puts $ch "990098;ENG;IM;Fixture, ValidIccf;20;2200;90;\n990099;ENG;IM;Fixture, Pipe|Name;20;2200;90;"
 close $ch
 proc ::tk_getOpenFile {args} { return $::m4install::pipeIccfCsv }
} -body {
 set beforeEcf [::m4install::contents [::playerdata::listFile ecf]]
 proc ::application::download::Get {url done} {
  if {[string match *englishchess* $url]} {
   set payload "ECF_code,full_name,revised_standard\n999001A,\"Fixture, Valid\",1900\n\"99|002B\",\"Fixture, PipeEcf\",1900\n"
  } else {
   set payload [::m4install::contents $::m4install::pipeDwzZip]
  }
  uplevel #0 [list {*}$done [dict create ok 1 data $payload code 200]]
 }
 proc ::dialog::question {args} {
  if {[dict exists $args -embed]} {
   set w [toplevel .m4_lists_pipe]
   uplevel #0 [dict get $args -embed] [list $w TkDefaultFont TkDefaultFont]
   $w.buttonecf invoke
   $w.buttondwz invoke
   $w.buttoniccf invoke
   destroy $w
  }
  return cancel
 }
 ::application::switchTab database
 ::action::run menu.db.player.lists
 list \
  [llength $::m4install::errMsgs] \
  [llength $::m4install::infoMsgs] \
  [expr {$beforeEcf eq [::m4install::contents [::playerdata::listFile ecf]]}] \
  [file exists [::playerdata::listFile dwz]] \
  [file exists [::playerdata::listFile iccf]]
} -cleanup {
 proc ::application::download::Get {args} {incr ::m4install::requests; error {Network forbidden in tests}}
 proc ::dialog::question {args} {return cancel}
 rename ::tk_getOpenFile {}
 rename ::m4install::realChooser ::tk_getOpenFile
 rename ::dialog::error {}
 rename ::m4install::realError ::dialog::error
 rename ::dialog::info {}
 rename ::m4install::realInfo ::dialog::info
 file delete -force [::playerdata::listFile dwz] [::playerdata::listInfoFile dwz] \
  [::playerdata::listFile iccf] [::playerdata::listInfoFile iccf]
} -result {3 0 1 0 0}
tcltest::test VAL-PD4-010 {Cancelled ICCF chooser leaves cache absent} -setup {
 rename ::tk_getOpenFile ::m4install::realChooser
 proc ::tk_getOpenFile {args} {return {}}
} -body {
 ::playerdata::ChooseList iccf .application
 list [file exists [::playerdata::listFile iccf]] $::m4install::requests
} -cleanup {
 rename ::tk_getOpenFile {}
 rename ::m4install::realChooser ::tk_getOpenFile
} -result {0 0}
tcltest::test VAL-PD4-013-016 {Successful update is usable after isolated restart and refresh replaces stale records idempotently} -body {
 set v1 $::m4install::dir/ecf-v1.csv
 set f [open $v1 w]
 puts $f {ECF_code,full_name,revised_standard
499810A,"Staleplayer, One",2050
499811B,"Keptplayer, Two",2100}
 close $f
 ::playerdata::installList ecf $v1
 set firstFile [::m4install::contents [::playerdata::listFile ecf]]
 ::playerdata::installList ecf $v1
 set secondFile [::m4install::contents [::playerdata::listFile ecf]]
 set idempotent [expr {$firstFile eq $secondFile}]
 set v2 $::m4install::dir/ecf-v2.csv
 set f [open $v2 w]
 puts $f {ECF_code,full_name,revised_standard
499811B,"Keptplayer, Two",2125
499812C,"Freshplayer, Three",2150}
 close $f
 ::playerdata::installList ecf $v2
 set probe $::m4install::dir/probe.tcl
 set f [open $probe w]
 puts $f {
  set argv {--single-process}
  set argc 1
  set ::env(SCIDB_AI_TRIAGE) 0
  set ::env(SCIDB_AI_CLASSIFIER) off
  source -encoding utf-8 [file join [pwd] tcl chesswiz]
  set ::scidb::dir::setup 0
  set p1 [::scidb::player::lookup -name "Staleplayer, One"]
  set p2 [::scidb::player::lookup -name "Keptplayer, Two"]
  set p3 [::scidb::player::lookup -name "Freshplayer, Three"]
  puts "PROBE_RESULT:[expr {$p1 ne ""}]:[dict get $p2 ecf]:[dict get $p3 ecf]"
  catch { destroy .application }
  catch { destroy . }
  exit 0
 }
 close $f
 set out [exec src/tkchesswiz $probe]
 regexp {PROBE_RESULT:([^\r\n]+)} $out -> res
 file delete -force $probe [file join $::scidb::dir::user cache]
 list $idempotent $res
} -result {1 0:499811B:499812C}
tcltest::test VAL-PD4-017 {Downloading/importing/linking never changes database stored names or dirty state} -body {
 set f [open $input w]
 puts $f {ECF_code,full_name,revised_standard
999800A,"Fixture, Install",2000}
 close $f
 set pgn $::m4install::dir/imm.pgn
 set f [open $pgn w]
 puts $f {[Event "Synthetic"]
[Site "Fixture"]
[Date "2026.01.01"]
[Round "1"]
[White "Keptplayer, T"]
[Black "Opponent, Plain"]
[WhiteElo "2125"]
[Result "1-0"]

1. e4 e5 1-0}
 close $f
 proc ::m4install::nop {args} {return 0}
 ::scidb::db::open $pgn ::m4install::nop {} ::m4install::nop {}
 set beforeNames [lmap r [::scidb::db::playerLinks $pgn Normal] {lindex $r 0}]
 set beforeDisk [::m4install::contents $pgn]
 ::scidb::app::load installed [::playerdata::listFile ecf]
 ::scidb::app::load done
 ::scidb::db::linkPlayers $pgn Normal
 ::playerdata::installList ecf $input
 set afterNames [lmap r [::scidb::db::playerLinks $pgn Normal] {lindex $r 0}]
 set unsaved [::scidb::db::get unsaved? $pgn]
 set afterDisk [::m4install::contents $pgn]
 ::scidb::db::close $pgn
 list [expr {$beforeNames eq $afterNames}] $unsaved [expr {$beforeDisk eq $afterDisk}]
} -result {1 0 1}
rename ::application::download::Get {}
rename ::m4install::realGet ::application::download::Get
rename ::dialog::question {}
rename ::m4install::realQuestion ::dialog::question
file delete -force $::m4install::dir [::playerdata::Dir] [file join $::scidb::dir::user cache]
tcltest::cleanupTests
