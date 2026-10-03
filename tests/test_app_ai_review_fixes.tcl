# Regression coverage for the AI correctness review (2026-09-30).
package require tcltest 2.5
namespace eval ::scidb::test::aireview {
 variable Saved {}
 variable Seq 0
 variable Start {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
}
proc ::scidb::test::aireview::stub {name arguments body} {
 variable Saved
 variable Seq
 set backup ${name}.__review[incr Seq]
 rename $name $backup
 lappend Saved [list $name $backup]
 proc $name $arguments $body
}
proc ::scidb::test::aireview::restore {} {
 variable Saved
 foreach pair [lreverse $Saved] {
  lassign $pair name backup
  rename $name {}
  rename $backup $name
 }
 set Saved {}
}
proc ::scidb::test::aireview::game {} {
 variable Current A
 variable Line [list [list m-0.1 e4 $::scidb::test::aireview::Start]]
 variable Writes {}
 variable Navigation {}
 stub ::scidb::game::current {} {return $::scidb::test::aireview::Current}
 stub ::scidb::game::link? {args} {return [list database Normal $::scidb::test::aireview::Current]}
 stub ::scidb::game::query {args} {
  if {[lindex $args end] eq {mainline}} {return $::scidb::test::aireview::Line}
  return {}
 }
 stub ::scidb::game::update {args} {lappend ::scidb::test::aireview::Writes $args}
 stub ::scidb::game::go {args} {lappend ::scidb::test::aireview::Navigation $args}
 set ::ai::annotate::Priv(owner) [::ai::annotate::Owner]
 array set ::ai::annotate::Priv {running 1 cancel 0 rows {} skipped 0 written 0 marks 0 savedKey m-0.0 done {} parent .application index 0 total 1}
}
set ::scidb::test::aireview::SavedPriv [array get ::ai::annotate::Priv]

tcltest::test aireview-annotation-game-switch {a draft cannot write into a different game or restore its position} -setup {
 ::scidb::test::aireview::game
 ::scidb::test::aireview::stub ::ai::annotate::Report {args} {return}
} -body {
 set ::scidb::test::aireview::Current B
 ::ai::annotate::Write {key m-0.1 san e4 classification Mistake} {A's comment}
 ::ai::annotate::Finish
 list $::scidb::test::aireview::Writes $::scidb::test::aireview::Navigation $::ai::annotate::Priv(skipped)
} -cleanup {::scidb::test::aireview::restore} -result {{} {} 1}

tcltest::test aireview-annotation-edited-moves {editing the original mainline invalidates a pending draft} -setup {
 ::scidb::test::aireview::game
} -body {
 set ::scidb::test::aireview::Line [list [list m-0.1 d4 $::scidb::test::aireview::Start]]
 ::ai::annotate::Write {key m-0.1 san e4 classification Mistake} {Stale comment}
 list $::scidb::test::aireview::Writes $::ai::annotate::Priv(cancel)
} -cleanup {::scidb::test::aireview::restore} -result {{} 1}

tcltest::test aireview-annotation-own-writes {appending our comments does not invalidate subsequent writes} -setup {
 ::scidb::test::aireview::game
} -body {
 foreach text {first second} {::ai::annotate::Write {key m-0.1 san e4 classification Mistake} $text}
 list [llength $::scidb::test::aireview::Writes] $::ai::annotate::Priv(written)
} -cleanup {::scidb::test::aireview::restore} -result {2 2}

tcltest::test aireview-refused-tools {normally refused starts return errors rather than pending tokens} -setup {
 ::scidb::test::aireview::stub ::ai::annotate::running? {} {return 0}
 ::scidb::test::aireview::stub ::ai::annotate::annotate {args} {return 0}
 ::scidb::test::aireview::stub ::ai::studyplan::running? {} {return 0}
 ::scidb::test::aireview::stub ::ai::studyplan::run {args} {return 0}
} -body {
 list [string match {error: *} [::application::assistant::DoAnnotateGame 0 0 12 60]] \
  [string match {error: *} [::application::assistant::DoStudyPlan Alice 10 both 12]]
} -cleanup {::scidb::test::aireview::restore} -result {1 1}

tcltest::test aireview-factcheck-clean {clean comments are checked but not flagged} -setup {
 ::scidb::test::aireview::game
 ::scidb::test::aireview::stub ::scidb::game::position {args} {return m-0.0}
 ::scidb::test::aireview::stub ::scidb::game::query {args} {
  if {[lindex $args end] eq {mainline}} {return $::scidb::test::aireview::Line}
  if {[lindex $args end-1] eq {comment}} {return {Both sides have the bishop pair.}}
  return {}
 }
} -body {
 set result [::ai::factcheck::game]
 list [dict get $result checked] [dict get $result flagged] [dict get $result findings]
} -cleanup {::scidb::test::aireview::restore} -result {2 0 {}}

tcltest::test aireview-prompt-facts {successful facts appear in annotation prompts and failures do not masquerade as facts} -body {
 set verdict [dict create fen $::scidb::test::aireview::Start classification Mistake]
 set legal [::ai::annotate::prompt e4 Mistake $verdict]
 set illegal [::ai::annotate::prompt Qh5 Mistake $verdict]
 list [string match {*MOVE FACTS (JSON):*fenAfter*} $legal] [string match {*MOVE FACTS*} $illegal]
} -result {1 0}

tcltest::test aireview-explanation-classification {the explanation passes FEN before SAN to the engine} -setup {
 ::scidb::test::aireview::stub ::ai::engine::classify {fen san args} {
  if {$fen ne $::scidb::test::aireview::Start || $san ne {e4}} {error {wrong position}}
  return {classification Good cpLoss 0 bestMove e2e4}
 }
} -body {
 ::application::ai::moveClass e4 $::scidb::test::aireview::Start
} -cleanup {::scidb::test::aireview::restore} -result {classification=Good cpLoss=0 best=e2e4}

tcltest::test aireview-brief-overlap {out-of-order callbacks retain their own player's facts} -setup {
 set ::scidb::test::aireview::Callbacks {}
 set ::scidb::test::aireview::Pages {}
 ::scidb::test::aireview::stub ::ai::brief::configureProvider {} {return}
 ::scidb::test::aireview::stub ::ai::provider::completeAsync {prompt callback args} {
  lappend ::scidb::test::aireview::Callbacks $callback
 }
 ::scidb::test::aireview::stub ::ai::brief::Report {parent html} {lappend ::scidb::test::aireview::Pages $html}
} -body {
 ::ai::brief::OnStance .application Alice ALICE_FACTS 1 {} {stance neutral source rules}
 ::ai::brief::OnStance .application Bob BOB_FACTS 1 {} {stance neutral source rules}
 {*}[lindex $::scidb::test::aireview::Callbacks 1] {ok 1 text BOB_PROSE}
 {*}[lindex $::scidb::test::aireview::Callbacks 0] {ok 1 text ALICE_PROSE}
 set page [lindex $::scidb::test::aireview::Pages end]
 list [string match {*Alice*ALICE_PROSE*ALICE_FACTS*} $page] [string match {*BOB_FACTS*} $page]
} -cleanup {::scidb::test::aireview::restore} -result {1 0}

tcltest::test aireview-model-metadata {parameter sizes survive parsing including sizes in millions} -body {
 set raw {{"models":[{"name":"custom:latest","details":{"parameter_size":"8.0B"}},{"name":"small:latest","details":{"parameter_size":"300M"}}]}}
 lmap model [::ai::provider::parseModels $raw] {::application::ai::models::ParamsB $model}
} -result {8.0 0.3}

tcltest::test aireview-similar-report {the requested limit and reference FEN reach narration} -setup {
 ::scidb::test::aireview::stub ::ai::similar::StartingFen {args} {return {4k3/8/8/8/8/8/8/4K3 w - - 0 1}}
 ::scidb::test::aireview::stub ::ai::similar::candidates {args} {
  set rows {}
  for {set i 0} {$i < 15} {incr i} {lappend rows [dict create white W$i black B result * year 2024 shared 3]}
  return $rows
 }
 ::scidb::test::aireview::stub ::ai::similar::narrate {parent facts args} {return [list [dict get $facts fen] [llength [dict get $facts rows]]]}
} -body {
 ::ai::similar::report .application base Normal 0 -limit 15
} -cleanup {::scidb::test::aireview::restore} -result {{4k3/8/8/8/8/8/8/4K3 w - - 0 1} 15}

tcltest::test aireview-claim-colour {explicit piece colours and both sides are verified against the board} -body {
 set fen {4k3/8/8/8/8/8/8/2B1KB2 w - - 0 1}
 lmap text {{A black bishop on c1 supports the king.} {White bishops (c1, f1).} {Black bishops (c1, f1).} {Both sides have the bishop pair.} {White has the bishop pair.}} {
  expr {[llength [::ai::claims::check $fen $text]] > 0}
 }
} -result {1 0 1 1 0}


# Exercise the ownership guard and starting-FEN reader with native game slots.
proc ::scidb::test::aireview::nop {args} {return 0}
proc ::scidb::test::aireview::fixture {} {
 variable Fixture [file join [file dirname [info script]] tmp-app ai-review-[pid].pgn]
 variable OriginalSlot [::scidb::game::current]
 set fh [open $Fixture w]
 puts $fh {[Event "Review A"]
[White "Alice"]
[Black "Bob"]
[Result "*"]

1. e4 e5 *

[Event "Review B"]
[White "Carol"]
[Black "Dave"]
[Result "*"]

1. e4 e5 *

[Event "Review setup"]
[White "Alice"]
[Black "Bob"]
[Result "*"]
[SetUp "1"]
[FEN "4k3/8/8/8/8/8/8/4K3 w - - 0 1"]

1. Ke2 *}
 puts $fh "\n\[Event \"Review Chess960\"\]\n\[White \"Alice\"\]\n\[Black \"Bob\"\]\n\[Result \"*\"\]\n\[SetUp \"1\"\]\n\[FEN \"[lindex [::scidb::board::idnToFen 1] 0]\"\]\n\n*"
 close $fh
 ::scidb::db::open $Fixture ::scidb::test::aireview::nop {} ::scidb::test::aireview::nop {}
 ::scidb::game::load 40 $Fixture Normal 0
 ::scidb::game::load 41 $Fixture Normal 1
 foreach slot {40 41} {::scidb::game::subscribe board $slot ::scidb::test::aireview::nop}
 ::scidb::game::switch 40
 set ::ai::annotate::Priv(owner) [::ai::annotate::Owner]
 array set ::ai::annotate::Priv {running 1 cancel 0 rows {} skipped 0 written 0 marks 0}
}
proc ::scidb::test::aireview::closeFixture {} {
 variable Fixture
 variable OriginalSlot
 ::scidb::game::switch $OriginalSlot
 foreach slot {40 41} {catch {::scidb::game::release $slot}}
 catch {::scidb::db::close $Fixture}
 catch {file delete $Fixture}
}

tcltest::test aireview-native-game-switch {native slots with identical keys cannot receive each other's drafts} -setup {
 ::scidb::test::aireview::fixture
} -body {
 ::scidb::game::switch 41
 ::ai::annotate::Write {key m-0.1 san e4 classification Mistake} {Comment for Alice}
 ::scidb::game::go 41 key m-0.1
 list $::ai::annotate::Priv(written) $::ai::annotate::Priv(cancel) [::scidb::game::query 41 comment after]
} -cleanup {::scidb::test::aireview::closeFixture} -result {0 1 {}}

tcltest::test aireview-native-replacement {loading another game into the same slot invalidates a draft} -setup {
 ::scidb::test::aireview::fixture
} -body {
 ::scidb::game::load 40 $::scidb::test::aireview::Fixture Normal 1
 ::ai::annotate::Write {key m-0.1 san e4 classification Mistake} {Comment for Alice}
 list $::ai::annotate::Priv(written) $::ai::annotate::Priv(cancel)
} -cleanup {::scidb::test::aireview::closeFixture} -result {0 1}

tcltest::test aireview-native-comment {native comment writes keep the run bound to the same game} -setup {
 ::scidb::test::aireview::fixture
} -body {
 ::ai::annotate::Write {key m-0.1 san e4 classification Mistake} {Engine verdict.}
 list $::ai::annotate::Priv(written) [::ai::annotate::SameGame] \
  [string match {*Engine verdict.*} [::scidb::game::query 40 comment after]]
} -cleanup {::scidb::test::aireview::closeFixture} -result {1 1 1}

tcltest::test aireview-native-reference-fen {the native database preserves standard and setup starts} -setup {
 ::scidb::test::aireview::fixture
} -body {
 list [expr {[::ai::similar::StartingFen $::scidb::test::aireview::Fixture Normal 0] eq $::scidb::test::aireview::Start}] \
  [::ai::similar::StartingFen $::scidb::test::aireview::Fixture Normal 2] \
  [expr {[::ai::similar::StartingFen $::scidb::test::aireview::Fixture Normal 3] eq [lindex [::scidb::board::idnToFen 1] 0]}]
} -cleanup {::scidb::test::aireview::closeFixture} -result {1 {4k3/8/8/8/8/8/8/4K3 w - - 0 1} 1}

array unset ::ai::annotate::Priv
array set ::ai::annotate::Priv $::scidb::test::aireview::SavedPriv
::tcltest::cleanupTests
