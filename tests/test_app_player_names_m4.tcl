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
 ::scidb::db::load $base ::m4names::nop {} -readonly 0
 expr {{Fixture, Changed} in [::m4names::names $base] && {Fixture, Alpha} ni [::m4names::names $base]}
} -result 1
tcltest::test VAL-PD5-014 {Close without save preserves previous disk names} -body {
 ::m4names::rename $base {Fixture, Changed} {Fixture, Unsaved}
 ::scidb::db::close $base
 ::scidb::db::load $base ::m4names::nop {} -readonly 0
 expr {{Fixture, Changed} in [::m4names::names $base] && {Fixture, Unsaved} ni [::m4names::names $base]}
} -result 1

# Additional VAL-PD5 UI, workflow, stale-preview, undo, and isolation assertions
set fideFile $::m4names::dir/fide-pd5.txt
set fh [open $fideFile w]
puts $fh "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
foreach row {
 {999600001 {Alpha, Canonical} GER M GM 2600 1985}
 {999600002 {Beta, Canonical} ENG F IM 2400 1990}
 {999600003 {Homonym, Person} FRA M {} 2300 1980}
 {999600004 {Homonym, Person} ESP M {} 2300 1982}
} {
 lassign $row id name fed sex tit std born
 puts $fh [format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
  $id $name $fed $sex $tit "" "" "" $std 0 10 0 0 10 0 0 10 $born ""]
}
close $fh
::scidb::app::load fide $fideFile
::scidb::app::load done

proc ::m4names::openUiBase {tag {extraGame ""}} {
 variable dir
 set pgn $dir/ui-$tag.pgn
 set f [open $pgn w]
 puts $f {[Event "Synthetic"]
[Site "Fixture"]
[Date "2026.01.01"]
[Round "1"]
[White "Alpha, C"]
[Black "Beta, C"]
[WhiteElo "2600"]
[BlackElo "2400"]
[Result "1-0"]

1. e4 {Comment one} e5 2. Nf3 Nc6 1-0

[Event "Synthetic"]
[Site "Fixture"]
[Date "2026.01.02"]
[Round "2"]
[White "Homonym, P"]
[Black "Unlinked, Mystery"]
[WhiteElo "2300"]
[BlackElo "1800"]
[Result "1/2-1/2"]

1. d4 d5 1/2-1/2}
 if {$extraGame ne ""} { puts $f "\n$extraGame" }
 close $f
 set uibase $dir/ui-$tag.sci
 ::scidb::db::open $pgn ::m4names::nop {} ::m4names::nop {}
 ::scidb::db::new $uibase Normal [::application::database::lookupType Unspecific]
 ::scidb::db::attach $uibase $uibase
 ::scidb::db::copy $pgn $uibase {} ::m4names::nop {} ::m4names::nop {}
 ::scidb::db::save $uibase ::m4names::nop {}
 ::scidb::db::close $pgn
 ::scidb::db::linkPlayers $uibase Normal
 return $uibase
}

tcltest::test VAL-PD5-001-002-005 {Direct maintenance action and report open preview with accurate columns and exclude ambiguous/unlinked} -body {
 set uibase [::m4names::openUiBase p1]
 set captured {}
 rename ::dialog::question ::m4names::realQuestion
 proc ::dialog::question {args} {
  set w [toplevel .m4_preview_probe]
  if {[dict exists $args -embed]} {
   uplevel #0 [dict get $args -embed] [list $w TkDefaultFont TkDefaultFont]
  }
  set tree $::playerdata::NameFix(tree)
  set items {}
  foreach item [$tree children {}] {
   lappend items [$tree item $item -values]
  }
  set ::m4names::captured [list $::playerdata::NameFix(base) $items]
  destroy $w
  return no
 }
 ::application::database::OpenMaintenanceReport .application $uibase Normal
 set dlg [::application::database::MaintenanceDialogName $uibase]
 set hasButton [winfo exists $dlg.actions.names]
 $dlg.actions.names invoke
 destroy $dlg
 rename ::dialog::question {}
 rename ::m4names::realQuestion ::dialog::question
 ::scidb::db::close $uibase
 lassign $::m4names::captured capBase items
 list $hasButton [expr {$capBase eq $uibase}] $items
} -result {1 1 {{{[x]} {Alpha, C} {Alpha, Canonical} 1 {FIDE 999600001} Normal} {{[x]} {Beta, C} {Beta, Canonical} 1 {FIDE 999600002} Normal}}}

tcltest::test VAL-PD5-003 {Cancel, close, or empty selection performs zero renames} -body {
 set uibase [::m4names::openUiBase p3]
 set before [::m4names::names $uibase]
 rename ::dialog::question ::m4names::realQuestion
 rename ::dialog::info ::m4names::realInfo
 proc ::dialog::info {args} {}
 # 1) Cancel on preview dialog
 proc ::dialog::question {args} { return no }
 ::playerdata::fixNames .application $uibase
 set afterCancel [::m4names::names $uibase]
 # 2) Yes on preview, Cancel on confirmation dialog
 set ::m4names::q step1
 proc ::dialog::question {args} {
  if {$::m4names::q eq "step1"} { set ::m4names::q step2; return yes }
  return no
 }
 ::playerdata::fixNames .application $uibase
 set afterConfirmNo [::m4names::names $uibase]
 # 3) Empty selection (untick all)
 proc ::dialog::question {args} {
  ::playerdata::TickNameFixes 0
  return yes
 }
 ::playerdata::fixNames .application $uibase
 set afterEmpty [::m4names::names $uibase]
 set unsaved [::scidb::db::get unsaved? $uibase]
 rename ::dialog::question {}
 rename ::m4names::realQuestion ::dialog::question
 rename ::dialog::info {}
 rename ::m4names::realInfo ::dialog::info
 ::scidb::db::close $uibase
 list [expr {$before eq $afterCancel}] [expr {$before eq $afterConfirmNo}] [expr {$before eq $afterEmpty}] $unsaved
} -result {1 1 1 0}

tcltest::test VAL-PD5-004-012 {Only explicitly confirmed selected rows change and database is marked dirty} -body {
 set uibase [::m4names::openUiBase p4]
 rename ::dialog::question ::m4names::realQuestion
 rename ::dialog::info ::m4names::realInfo
 proc ::dialog::info {args} {}
 set ::m4names::step 0
 proc ::dialog::question {args} {
  incr ::m4names::step
  if {$::m4names::step == 1} {
   # Select only row 0 (Alpha, C), untick row 1 (Beta, C)
   set ::playerdata::NameFix(tick,0) 1
   set ::playerdata::NameFix(tick,1) 0
   return yes
  }
  return yes
 }
 ::playerdata::fixNames .application $uibase
 set after [::m4names::names $uibase]
 set dirty [::scidb::db::get unsaved? $uibase]
 rename ::dialog::question {}
 rename ::m4names::realQuestion ::dialog::question
 rename ::dialog::info {}
 rename ::m4names::realInfo ::dialog::info
 ::scidb::db::close $uibase
 list [expr {{Alpha, Canonical} in $after}] [expr {{Beta, C} in $after}] [expr {{Beta, Canonical} ni $after}] $dirty
} -result {1 1 1 1}

tcltest::test VAL-PD5-006-ui {Changed database or source revision invalidates preview before apply} -body {
 set uibase [::m4names::openUiBase p6]
 set before [::m4names::names $uibase]
 rename ::dialog::question ::m4names::realQuestion
 rename ::dialog::info ::m4names::realInfo
 set ::m4names::infoMsg ""
 proc ::dialog::info {args} { set ::m4names::infoMsg [dict get $args -message] }
 set ::m4names::step 0
 proc ::dialog::question {args} {
  incr ::m4names::step
  if {$::m4names::step == 1} { return yes }
  # Mutate/invalidate before confirming second dialog
  ::playerdata::InvalidateNames
  return yes
 }
 ::playerdata::fixNames .application $uibase
 set after [::m4names::names $uibase]
 rename ::dialog::question {}
 rename ::m4names::realQuestion ::dialog::question
 rename ::dialog::info {}
 rename ::m4names::realInfo ::dialog::info
 ::scidb::db::close $uibase
 list [expr {$before eq $after}] [string match {*changed*fresh preview*} $::m4names::infoMsg]
} -result {1 1}

tcltest::test VAL-PD5-007 {Read-only database refuses apply without side effects} -body {
 set uibase [::m4names::openUiBase p7]
 ::scidb::db::close $uibase
 ::scidb::db::load $uibase ::m4names::nop {} -readonly 1
 set before [::m4names::names $uibase]
 set idx [::playerdata::NameIndex $uibase Normal {Alpha, C}]
 set failed [catch {::scidb::db::renamePlayers $uibase Normal [list $idx {Alpha, C} {Alpha, Canonical}]} err]
 set after [::m4names::names $uibase]
 ::scidb::db::close $uibase
 list $failed [string match {*read-only*} $err] [expr {$before eq $after}]
} -result {1 1 1}

tcltest::test VAL-PD5-009-010-ui {Partial failure reports applied and skipped accurately; undo only reverts applied rows and leaves collision target untouched} -body {
 set uibase [::m4names::openUiBase p9 {[Event "Collide"]
[Site "Fixture"]
[Date "2026.01.03"]
[Round "1"]
[White "Beta, Canonical"]
[Black "Unlinked, Mystery"]
[Result "1-0"]

1. c4 c5 1-0}]

 rename ::dialog::question ::m4names::realQuestion
 rename ::dialog::info ::m4names::realInfo
 set ::m4names::msgs {}
 proc ::dialog::info {args} { lappend ::m4names::msgs [dict get $args -message] }
 proc ::dialog::question {args} { return yes }
 ::playerdata::fixNames .application $uibase
 set midNames [::m4names::names $uibase]
 set undoRecorded $::playerdata::NameFix(undo,$uibase)
 ::playerdata::revertNames .application $uibase
 set finalNames [::m4names::names $uibase]
 rename ::dialog::question {}
 rename ::m4names::realQuestion ::dialog::question
 rename ::dialog::info {}
 rename ::m4names::realInfo ::dialog::info
 ::scidb::db::close $uibase
 list \
  [expr {{Alpha, Canonical} in $midNames && {Beta, C} in $midNames && {Beta, Canonical} in $midNames}] \
  $undoRecorded \
  [string match {*1*renamed*1*left alone*database has a player*} [lindex $::m4names::msgs 0]] \
  [expr {{Alpha, C} in $finalNames && {Beta, C} in $finalNames && {Beta, Canonical} in $finalNames}]
} -result {1 {{Normal {Alpha, Canonical} {Alpha, C}}} 1 1}

tcltest::test VAL-PD5-016 {Startup, list updates, and linking never invoke renamePlayers automatically} -body {
 set uibase [::m4names::openUiBase p16]
 set ::m4names::renameCalls 0
 trace add execution ::scidb::db::renamePlayers enter {apply {args {incr ::m4names::renameCalls}}}
 ::scidb::db::linkPlayers $uibase Normal
 ::playerdata::linkOpen
 set ecfIn $::m4names::dir/ecf-p16.csv
 set f [open $ecfIn w]
 puts $f {ECF_code,full_name,revised_standard
499820A,"Fixture, NoAutoRename",2000}
 close $f
 ::playerdata::installList ecf $ecfIn
 file delete -force [::playerdata::Dir]
 ::scidb::db::close $uibase
 set ::m4names::renameCalls
} -result 0

tcltest::test VAL-PD5-017 {Fixtures and test files contain no real player personal data or personal paths} -body {
 set clean 1
 set forbidden [list [string cat Carl sen] [string cat Firou zja] [string cat Arth urton] [string cat Ric cio] [string cat "Mega " Database]]
 foreach f [glob [file join [file dirname [info script]] test_app_player_*_m4.tcl]] {
  set ch [open $f r]; set txt [read $ch]; close $ch
  foreach pat $forbidden {
   if {[string first [string tolower $pat] [string tolower $txt]] >= 0} { set clean 0 }
  }
 }
 set clean
} -result 1

::scidb::db::close $base
file delete -force $::m4names::dir [::playerdata::Dir]
tcltest::cleanupTests
