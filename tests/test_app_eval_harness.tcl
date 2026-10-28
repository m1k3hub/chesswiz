package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
source [file join [file dirname [info script]] eval_harness_support.tcl]
::EvalHarness::Install
namespace eval ::evalSelf {
 variable Work [file join $::tcltest::temporaryDirectory eval-harness-self]
 variable Mode model
 variable Attempts 0
 variable Responses {}
}
file mkdir [file join $::evalSelf::Work items]
proc ::evalSelf::RunAttempt {item} {
 incr ::evalSelf::Attempts
 set response [lindex $::evalSelf::Responses [expr {$::evalSelf::Attempts-1}]]
 ::EvalHarness::TransportResult $response
 set answer [::dialog::question -parent .application -message {Overwrite current game?} -buttons {yes no}]
 set f [open [file join $::evalSelf::Work items [dict get $item id].txt] w]
 puts $f "native result: $answer";close $f
 return [dict create said {visible reply} ok 1]
}

tcltest::test eval-native-safe {native confirmation APIs automatically answer and log their exact non-destructive choices} -body {
 set ::EvalHarness::Active 1
 set ::EvalHarness::Dialogs {}
 set a [::dialog::question -parent .application -message {Overwrite current game?} -buttons {yes no}]
 set b [::tk_messageBox -parent .application -message {Replace?} -type yesnocancel]
 set c [::dialog::question -parent .application -message {Continue?} -buttons {abort retry ignore}]
 list $a $b $c [lmap d $::EvalHarness::Dialogs {dict get $d answer}] \
  [dict get [lindex $::EvalHarness::Dialogs 0] message]
} -cleanup {set ::EvalHarness::Active 0} -result {no cancel abort {no cancel abort} {Overwrite current game?}}

tcltest::test eval-retry-once {HTTP 5xx, timeout and empty replies retry once and retain both attempts and native answers} -body {
 set out {}
 foreach response {{ok 0 error {HTTP 503 unavailable}} {ok 0 error {provider: timeout}} {ok 1 message {content {}}}} {
  set ::evalSelf::Attempts 0
  set ::evalSelf::Responses [list $response {ok 1 message {content recovered}}]
  ::EvalHarness::RunItem ::evalSelf {id retry}
  set f [open [file join $::evalSelf::Work items retry.txt]];set log [read $f];close $f
  set f [open [file join $::evalSelf::Work items retry.attempt-1.txt]];set first [read $f];close $f
  lappend out [list $::evalSelf::Attempts [string match {*attempt: 2*transport retries: *attempt 1 reason*} $log] \
   [string match {*native confirmations: *Overwrite current game?*answer no*} $first]]
 }
 set out
} -result {{2 1 1} {2 1 1} {2 1 1}}

tcltest::test eval-no-third-attempt {persistent transport failure never retries more than once} -body {
 set ::evalSelf::Attempts 0
 set ::evalSelf::Responses {{ok 0 error {HTTP 502}} {ok 0 error {HTTP 502}}}
 ::EvalHarness::RunItem ::evalSelf {id twice}
 set ::evalSelf::Attempts
} -result 2

tcltest::test eval-no-semantic-retry {authentication, rate limits, handler errors and ordinary misses do not trigger transport retry} -body {
 set out {}
 foreach response {{ok 0 error {HTTP 401}} {ok 0 error {HTTP 429}} {ok 0 error {handler failed}} {ok 1 message {content {Chesswiz cannot do that}}} {ok 1 message {content {} tool_calls {{function {name current_game}}}}}} {
  set ::evalSelf::Attempts 0
  set ::evalSelf::Responses [list $response]
  ::EvalHarness::RunItem ::evalSelf {id semantic}
  lappend out $::evalSelf::Attempts
 }
 set out
} -result {1 1 1 1 1}

tcltest::test eval-unavailable-bounded {only the second transport failure with the exact visible unavailable-service reply qualifies} -body {
 set result {ok 0 down 1 error {HTTP 503} summary {provider: HTTP 503}}
 set finished [dict create result $result]
 set expected [format $::application::assistant::mc::AllDown {provider: HTTP 503}]
 set ::EvalHarness::Attempt 1
 set ::EvalHarness::Failure {HTTP 503}
 set ::EvalHarness::Visible [list [list error $expected]]
 set first [::EvalHarness::UnavailableReply $finished]
 set ::EvalHarness::Attempt 2
 set second [::EvalHarness::UnavailableReply $finished]
 set ::EvalHarness::Visible {{error {some other error}}}
 set other [::EvalHarness::UnavailableReply $finished]
 list $first [expr {$second eq $expected}] $other
} -result {{} 1 {}}

tcltest::test eval-missing-fact-strict {quoted unrelated tool data cannot pass missing-fact items; successful effects keep receipts} -body {
 set out {}
 foreach id {bounds-carlsen-rating bounds-kasparov-count bounds-sicilian-count bounds-fischer-spassky} {
  set request {An unavailable fact}
  set decline [::application::assistant::BoundsDecline $request]
  lappend out [expr {[::EvalHarness::MissingFactViolation $id {Tool results (quoted data): /tmp/data games 123} $request {}] ne ""}]
  lappend out [expr {[::EvalHarness::MissingFactViolation $id $decline $request {}] eq ""}]
  lappend out [expr {[::EvalHarness::MissingFactViolation $id {Action returned 0} $request {{Action returned 0}}] eq ""}]
 }
 lsort -unique $out
} -result 1

trace remove execution ::application::assistant::Append leave ::EvalHarness::NoteAppend

# Restore the APIs so later assistant tests keep normal interactive policy.
foreach command {::dialog::alert ::tk_messageBox} {
 rename $command {}
 rename [namespace qualifiers $command]::__EvalOriginal[namespace tail $command] $command
}
rename ::dialog::nonInteractiveReply {}
rename ::dialog::__EvalOriginalReply ::dialog::nonInteractiveReply
file delete -force $::evalSelf::Work
tcltest::cleanupTests
