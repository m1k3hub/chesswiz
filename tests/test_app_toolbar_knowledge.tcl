package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::toolbarKnowledge {
 proc words {s} {
  string trim [regsub -all {[^[:alnum:]]+} [string tolower $s] { }]
 }
 proc quality {label kind purpose when} {
  set p [words $purpose]
  set w [words $when]
  if {$p eq "" || $p in [list [words $label] [words $kind] {toolbar action}]} {return {generic purpose}}
  if {[regexp {^use this when you need the .* command$} $w]
      || $w eq "use this when you need the [words $label] command"
      || $p eq $w || [string first $p $w] >= 0} {return {circular use}}
  return {}
 }
}
tcltest::test toolbar-knowledge-reject-generic {knowledge quality rejects labels, kinds and circular use text} -body {
 list [::toolbarKnowledge::quality {Game start} button {Game start.} {Before replaying a game.}] \
      [::toolbarKnowledge::quality {Game start} button {Button.} {Before replaying a game.}] \
      [::toolbarKnowledge::quality {Game start} button {Move to the starting position.} {Use this to move to the starting position.}] \
      [::toolbarKnowledge::quality {Game start} button {Move to the starting position.} {Use this when you need the ‘Game start’ command.}]
} -result {{generic purpose} {generic purpose} {circular use} {circular use}}
tcltest::test toolbar-knowledge-native-controls {every previously generic shipped control has purpose, use cases, examples and a meaningful label} -body {
 ::knowledge::FillAll
 set bad {}
 dict for {id description} $::toolbar::Knowledge {
  set r [::action::get $id]
  set k [::knowledge::For $id en]
  set error [::toolbarKnowledge::quality [dict get $r label] button [dict get $k purpose] [dict get $k when]]
  if {$error ne {} || [dict get $r label] eq {Toolbar action} || [llength [dict get $k examples]] < 2} {lappend bad [list $id $error]}
 }
 list [dict size $::toolbar::Knowledge] $bad
} -result {65 {}}
tcltest::test toolbar-knowledge-game-start {the named game-start control really returns a generated game to its initial position} -body {
 ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
 set start [::scidb::pos::fen]
 foreach san {e4 e5 Nf3 Nc6} {::move::addMove menu $san}
 set played [::scidb::pos::fen]
 ::action::run toolbar.board_control.0
 list [expr {$played ne $start}] [expr {[::scidb::pos::fen] eq $start}] [dict get [::knowledge::For toolbar.board_control.0 en] title]
} -result {1 1 {Game start}}
# This check covers the whole shipped surface. It deliberately exposes any
# remaining label-only records, including ones outside the toolbar census.
tcltest::test knowledge-reject-label-only-records {every shipped purpose and use case describes an operation rather than repeating its label} -body {
 ::knowledge::FillAll
 set bad {}
 foreach id [::knowledge::PackIds] {
  set k [::knowledge::For $id en]
  set error [::toolbarKnowledge::quality [dict get $k title] action [dict get $k purpose] [dict get $k when]]
  if {$error ne {}} {lappend bad [list $id $error]}
 }
 puts "KNOWLEDGE_GENERIC_RECORDS [llength $bad]"
 set bad
} -result {}
# Help text is read by users. Technical action docs and argument names are
# intentionally separate from these two prose fields.
set ::toolbarKnowledge::ImplementationTerms {
 widget widgets path paths callback callbacks native policy policies proc procs
 registry dispatch dispatcher tcl handler handlers implementation executable
 toplevel grab namespace hook hooks backend parser predicate schema boolean
 parameter parameters argument arguments api identifier interpreter triaged workflow
 classifier classifiers libmpv gui argv dict namespace runtime predicate routing fen pgn uci eco ply plies san
}
proc ::toolbarKnowledge::implementationTerms {text} {
 set found {}
 foreach word [regexp -all -inline {\m[[:alnum:]_]+\M} [string tolower $text]] {
  if {$word in $::toolbarKnowledge::ImplementationTerms && $word ni $found} {lappend found $word}
 }
 return $found
}
tcltest::test knowledge-plain-words-guard {all purposes and use cases avoid implementation vocabulary} -body {
 set bad {}
 set checked 0
 foreach id [::knowledge::PackIds] {
  set k [::knowledge::For $id en]
  foreach field {purpose when examples} {
   incr checked
   set terms [::toolbarKnowledge::implementationTerms [dict get $k $field]]
   if {[llength $terms]} {lappend bad [list $id $field $terms]}
  }
 }
 puts "KNOWLEDGE_PLAIN_FIELDS $checked"
 list $checked $bad
} -result {2094 {}}
tcltest::test knowledge-plain-words-canary {implementation terms in future descriptions fail the guard} -body {
 ::toolbarKnowledge::implementationTerms {Configure a native widget by path and callback in the Tcl registry handler.}
} -result {native widget path callback tcl registry handler}
tcltest::test knowledge-chess-argument-jargon-canary {format and position argument names are also technical vocabulary} -body {
 ::toolbarKnowledge::implementationTerms {fen pgn uci eco ply plies san}
} -result {fen pgn uci eco ply plies san}
# Incomplete prose is never acceptable even if its words are simple.
proc ::toolbarKnowledge::complete {text} {
 set text [string trim $text]
 if {[regexp {\.\.$|[,;:]$|\m(and|or)$} $text]} {return 0}
 set stack {}
 foreach c [split $text {}] {
  if {$c in {( [}} {lappend stack $c}
  if {$c in {) ]}} {
   if {![llength $stack]} {return 0}
   if {($c eq ")" && [lindex $stack end] ne "(") || ($c eq "]" && [lindex $stack end] ne {[})} {return 0}
   set stack [lrange $stack 0 end-1]
  }
 }
 return [expr {![llength $stack]}]
}
tcltest::test knowledge-complete-text-canaries {truncated sentences and unfinished lists fail even without jargon} -body {
 set out {}
 foreach text {{Supported languages (English, German, ..} {Choose English...} {Choose English..} {Choose (English.} {Choose [English.} {Choose English,} {Choose English or} {Choose English (or German).}} {
  lappend out [::toolbarKnowledge::complete $text]
 }
 set out
} -result {0 0 0 0 0 0 0 1}
tcltest::test knowledge-complete-text {every shipped prose field and example is complete} -body {
 set bad {}
 foreach id [::knowledge::PackIds] {
  set k [::knowledge::For $id en]
  foreach field {purpose when} {
   if {![::toolbarKnowledge::complete [dict get $k $field]]} {lappend bad [list $id $field [dict get $k $field]]}
  }
  foreach text [dict get $k examples] {
   if {![::toolbarKnowledge::complete $text]} {lappend bad [list $id example $text]}
  }
 }
 set bad
} -result {}

tcltest::cleanupTests
