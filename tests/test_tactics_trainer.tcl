# Run: xvfb-run -a /usr/local/bin/tkchesswiz tests/test_tactics_trainer.tcl
package require tcltest 2
namespace import ::tcltest::*
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tcl tactics-trainer.tcl]
namespace eval ::ai::engine {}
if {[llength [info commands ::ai::engine::evaluate]]} { rename ::ai::engine::evaluate ::ai::engine::realEvaluate }
set ::answers {}
set ::calls {}
proc ::ai::engine::evaluate {fen args} {
    lappend ::calls $fen
    if {![dict exists $::answers $fen]} { error "No stubbed evaluation for $fen" }
    return [dict get $::answers $fen]
}
# Headless runs exercise orchestration with a deterministic legal-move adapter.
# The application shell instead uses the real C++ chess-facts implementation.
set stubFacts [expr {![llength [info commands ::scidb::ai::moveFacts]]}]
if {$stubFacts} {
    namespace eval ::scidb::ai {}
    proc ::scidb::ai::moveFacts {move fen} {
        set aliases {e4 e2e4 e5 e7e5 Nf3 g1f3 d4 d2d4 d5 d7d5 c4 c2c4}
        if {[dict exists $aliases $move]} { set move [dict get $aliases $move] }
        set history [lrange $fen 6 end]
        set allowed [dict create {} {e2e4 d2d4} e2e4 e7e5 \
            {e2e4 e7e5} g1f3 d2d4 d7d5 {d2d4 d7d5} c2c4]
        if {![dict exists $allowed $history] || $move ni [dict get $allowed $history]} { error "illegal move" }
        set next [concat [lrange $fen 0 5] $move]
        if {[llength $history]} { set next [concat [lrange $fen 0 5] $history $move] }
        return "\"uci\":\"$move\",\"fenAfter\":\"$next\""
    }
    puts "Using stubbed chess facts (no application shell)"
}
::tcltest::testConstraint tk [expr {[llength [info commands toplevel]] > 0}]
set start {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
set e4 [dict get [::tactics::facts $start e4] fenAfter]
set d4 [dict get [::tactics::facts $start d4] fenAfter]
set d5 [dict get [::tactics::facts $d4 d5] fenAfter]
set e5 [dict get [::tactics::facts $e4 e5] fenAfter]
set p [::tactics::puzzle $start {e4 e5 Nf3}]
# Keep persistence in memory for core tests. Optional disk roundtrip below.
rename ::tactics::saveProgress ::tactics::diskSaveProgress
proc ::tactics::saveProgress {} { set ::saved $::tactics::progress }

test load-1 {AI output and ordinary PGN, excluding variations} -body {
    set loaded [::tactics::loadPGN [file join $root tests fixtures tactics.pgn]]
    lmap puzzle $loaded {dict get $puzzle line}
} -result {{e2e4 e7e5 g1f3} {d2d4 d7d5 c2c4}}
test exact-1 {SAN/UCI canonical comparison avoids unnecessary engine searches} -body {
    set ::calls {}
    list [dict get [::tactics::checkMove $start e2e4 e4] correct] $::calls
} -result {1 {}}
test illegal-1 {illegal input rejected by chess facts} -body {
    catch {::tactics::checkMove $start e4 e5}
} -result 1
proc answers {ref cp} {
    set ::calls {}
    set ::answers [dict create $::e4 [dict create cpl [expr {-$ref}] pv {e7e5 g1f3}] \
        $::d4 [dict create cpl [expr {-$cp}] pv {d7d5 c2c4}]]
}
test alt-1 {30cp boundary accepts a winning alternative} -body {
    answers 250 220
    set v [::tactics::checkMove $start e4 d4]
    list [dict get $v correct] [dict get $v continuation] [llength $::calls]
} -result {1 {d7d5 c2c4} 2}
test alt-2 {31cp below the solution fails} -body {
    answers 250 219
    dict get [::tactics::checkMove $start e4 d4] correct
} -result 0
test alt-3 {equivalent but drawn alternatives fail} -body {
    answers 80 80
    dict get [::tactics::checkMove $start e4 d4] correct
} -result 0
test alt-4 {engine errors leave session unchanged} -body {
    ::tactics::start $p
    set before $::tactics::session
    set ::answers {}
    list [catch {::tactics::play d4}] [expr {$before eq $::tactics::session}]
} -result {1 1}
test solve-1 {opponent reply is automatic; first try scores once} -body {
    set ::tactics::progress {}
    ::tactics::start $p
    set a [::tactics::play e4]
    set position [dict get $::tactics::session fen]
    set b [::tactics::play Nf3]
    ::tactics::finish failed
    list $a [expr {$position eq $e5}] $b [dict get $::tactics::progress [dict get $p id] status] [dict get $::tactics::progress streak]
} -result {correct 1 solved first 1}
test solve-2 {wrong move persists, blocks more moves, retry cannot earn first try} -body {
    set ::tactics::progress {}
    ::tactics::start $p
    answers 250 100
    set a [::tactics::play d4]
    set failed [dict get $::saved [dict get $p id] status]
    set blocked [catch {::tactics::play e4}]
    ::tactics::retry
    ::tactics::play e4
    ::tactics::play Nf3
    list $a $failed $blocked [dict get $::tactics::progress [dict get $p id] status] [dict get $::tactics::progress streak]
} -result {wrong failed 1 retry 0}
test solve-retry-message {retry replaces the "Wrong move" message with the to-move prompt} -body {
    set ::tactics::progress {}
    ::tactics::start $p
    answers 250 100
    ::tactics::play d4
    ::tactics::retry
    string match {* to move.*} $::tactics::message
} -result 1
test solve-3 {accepted alternative uses its own reply and continuation} -body {
    ::tactics::start $p
    answers 250 240
    list [::tactics::play d4] [expr {[dict get $::tactics::session fen] eq $d5}] [dict get $::tactics::session line]
} -result {correct 1 c2c4}
test order-1 {failed puzzles are scheduled first} -body {
    set q [::tactics::puzzle $start {d4}]
    set ::tactics::progress [dict create [dict get $q id] [dict create status failed attempts 1]]
    dict get [lindex [::tactics::ordered [list $p $q]] 0] id
} -result [list $start d2d4]
test show-1 {show solution marks failure and draws final position} -constraints tk -body {
    toplevel .tactics
    canvas .tactics.board
    ttk::label .tactics.score
    ::tactics::start $p
    ::tactics::showSolution
    list [dict get $::tactics::session state] [dict get $::tactics::progress [dict get $p id] status] [expr {[llength [.tactics.board find all]] > 64}]
} -cleanup {destroy .tactics} -result {done failed 1}
# Anonymous pipes exercise the actual persistence reader without scratch files.
# Linux fd paths permit readProgress's normal file-open path to read the pipe.
rename ::tactics::progressFile ::tactics::diskProgressFile
proc ::tactics::progressFile {} { return $::progressPipe }
proc progressInput {data} {
    lassign [chan pipe] r w
    puts $w $data
    close $w
    set ::progressPipe /proc/self/fd/[string range $r 4 end]
    return $r
}
test persistence-read-1 {saved failure and streak survive serialization and reload} -body {
    set expected [dict create [dict get $p id] [dict create status failed attempts 2] streak 3]
    set r [progressInput $expected]
    ::tactics::readProgress
    close $r
    list [expr {$::tactics::progress eq $expected}] [string match {*Failed: 1*Streak: 3} [::tactics::score]]
} -result {1 1}
test persistence-read-2 {progress data is never evaluated as Tcl} -body {
    set ::executed 0
    set r [progressInput {streak {[set ::executed 1]}}]
    set rejected [catch {::tactics::readProgress}]
    close $r
    list $rejected $::executed
} -result {1 0}
rename ::tactics::progressFile {}
rename ::tactics::diskProgressFile ::tactics::progressFile
# Set TACTICS_TEST_TMP to an authorized scratch directory for actual disk tests.
if {[info exists ::env(TACTICS_TEST_TMP)]} {
    namespace eval ::scidb::dir {}
    set ::scidb::dir::home $::env(TACTICS_TEST_TMP)
    test persistence-1 {roundtrip data, failure priority and streak; no Tcl evaluation} -body {
        set ::tactics::progress [dict create [dict get $p id] [dict create status failed attempts 2] streak 0]
        ::tactics::diskSaveProgress
        set expected $::tactics::progress
        set ::tactics::progress {}
        ::tactics::readProgress
        expr {$::tactics::progress eq $expected}
    } -result 1
}
set failed $::tcltest::numTests(Failed)
rename ::ai::engine::evaluate {}
if {[llength [info commands ::ai::engine::realEvaluate]]} {
    rename ::ai::engine::realEvaluate ::ai::engine::evaluate
}
if {$stubFacts} { rename ::scidb::ai::moveFacts {} }
rename ::tactics::saveProgress {}
rename ::tactics::diskSaveProgress ::tactics::saveProgress
cleanupTests
exit [expr {$failed > 0}]
