# Quick result analysis and the tool -> empty final reply regression.
# Also runnable without Tk via tests/tmp-app/whylose/headless.tcl.
package require tcltest 2.5
namespace eval ::scidb::test::whylose {
	variable saved {}
	variable plies {}
	variable scores {50 50 50 150 -150 450 -450}
	variable result 0-1
	variable transcript {}
	variable searches {}
}
# Wake a private variable on completion or timeout; never manufacture a
# successful busy/done value to escape a failed asynchronous operation.
proc ::scidb::test::whylose::wake {args} {
	set ::scidb::test::whylose::wakeUp 1
}
proc ::scidb::test::whylose::waitFor {name {busy 1} {timeoutMs 5000}} {
	upvar #0 $name value
	set timer [after $timeoutMs {set ::scidb::test::whylose::wakeUp timeout}]
	trace add variable $name write ::scidb::test::whylose::wake
	try {
		while {($busy && $value) || (!$busy && $value eq "")} {
			vwait ::scidb::test::whylose::wakeUp
			if {$::scidb::test::whylose::wakeUp eq "timeout"} {
				error "timed out after ${timeoutMs}ms waiting for $name (value: $value)"
			}
		}
	} finally {
		after cancel $timer
		trace remove variable $name write ::scidb::test::whylose::wake
		unset -nocomplain ::scidb::test::whylose::wakeUp
	}
}
proc ::scidb::test::whylose::captureAsync {} {
	variable savedTimers [after info]
	variable savedResultPass [array get ::application::assistant::ResultPass]
}
proc ::scidb::test::whylose::pendingResult {token} {
	if {![info exists ::application::assistant::ResultPass(token)]
	 || $token ne $::application::assistant::ResultPass(token) || $token eq ""} {
		error "result analysis did not start asynchronously: $token"
	}
	set ::application::assistant::Priv(pending) [list $token 1 explain_game_result {} {}]
	set ::application::assistant::Priv(maxRounds) 0
	set ::application::assistant::Priv(busy) 1
}
proc ::scidb::test::whylose::stub {name args body} {
	variable saved
	set old ${name}__whylose
	if {[llength [info commands $name]]} { rename $name $old; lappend saved [list $name $old] } else { lappend saved [list $name {}] }
	proc $name $args $body
}
proc ::scidb::test::whylose::setup {} {
	captureAsync
	variable plies
	variable transcript {}
	variable searches {}
	variable scores {50 50 50 150 -150 450 -450}
	variable result 0-1
	variable savedPriv [array get ::application::assistant::Priv]
	variable savedProvider [array get ::ai::provider::Config]
	set plies {}
	for {set i 0} {$i < 6} {incr i} {
		set side [expr {$i % 2 ? "b" : "w"}]
		lappend plies [list key$i [expr {$side eq "w" ? "e4" : "e5"}] "8/8/8/8/8/8/8/K6k $side - - 0 [expr {$i / 2 + 1}]"]
	}
	stub ::scidb::game::query {args} {
		# GUI callbacks also query explicit slots and unrelated editor state.
		# Preserve those native calls while faking only this tool's snapshot.
		if {[llength $args] != 1 || [lindex $args 0] ni {mainline variant?}} {
			if {[llength [info commands ::scidb::game::query__whylose]]} {
				return [::scidb::game::query__whylose {*}$args]
			}
			error "unexpected query $args"
		}
		::switch -- [lindex $args 0] {
			mainline { return $::scidb::test::whylose::plies }
			variant? { return Normal }
			default { error "unexpected query $args" }
		}
	}
	stub ::scidb::game::current {} {return 0}
	stub ::scidb::game::tags {slot} {return [list [list Result $::scidb::test::whylose::result]]}
	stub ::scidb::ai::moveFacts {move fen} {
		set next $fen
		set side [lindex $fen 1]
		lset next 1 [expr {$side eq "w" ? "b" : "w"}]
		if {$side eq "b"} {lset next 5 [expr {[lindex $fen 5] + 1}]}
		set uci [expr {$move in {e4 e5} ? "e2e4" : "b1c3"}]
		set san [expr {$move in {e4 e5} ? $move : "Nc3"}]
		return [format {{"uci":"%s","san":"%s","fenAfter":"%s"}} $uci $san $next]
	}
	stub ::ai::engine::available {} {return 1}
	stub ::ai::engine::evaluate {fen args} {
		set i [llength $::scidb::test::whylose::searches]
		lappend ::scidb::test::whylose::searches $args
		set cp [lindex $::scidb::test::whylose::scores $i]
		return [dict create fen $fen kind cp value $cp cpl $cp bestMove b1c3 pv b1c3]
	}
	stub ::application::assistant::Append {tag text} {lappend ::scidb::test::whylose::transcript [list $tag $text]}
	stub ::application::assistant::SetBusy {flag} {set ::application::assistant::Priv(busy) $flag}
	stub ::application::assistant::MePrompt {} {return ""}
	stub ::application::assistant::LogToolCall {args} {return}
	stub ::application::assistant::ConfigureProvider {} {::ai::provider::configure -name stub -options {}}
	if {[llength [info commands ::application::assistant::RouteOrStep]]} {
		stub ::application::assistant::RouteOrStep {request} {::application::assistant::Step 0}
	}
	::application::assistant::clear
}
proc ::scidb::test::whylose::cleanup {} {
	variable savedTimers
	variable savedResultPass
	if {[info exists savedTimers]} {
		# Cancel only callbacks created by this test, before restoring commands.
		foreach id [after info] {
			if {$id in $savedTimers} {continue}
			set script [lindex [after info $id] 0]
			if {[regexp {::(application::assistant|ai::annotate|scidb::test::whylose)::} $script]} {
				after cancel $id
			}
		}
		unset savedTimers
		array unset ::application::assistant::ResultPass
		array set ::application::assistant::ResultPass $savedResultPass
		unset savedResultPass
	}
	variable saved
	foreach entry [lreverse $saved] {
		lassign $entry name old
		rename $name {}
		if {$old ne ""} {rename $old $name}
	}
	set saved {}
	variable savedPriv
	variable savedProvider
	if {[info exists savedPriv]} {
		array unset ::application::assistant::Priv
		array set ::application::assistant::Priv $savedPriv
		unset savedPriv
	}
	if {[info exists savedProvider]} {
		array unset ::ai::provider::Config
		array set ::ai::provider::Config $savedProvider
		unset savedProvider
	}
}
proc ::scidb::test::whylose::run {{side auto} {final ""}} {
	set call [dict create role assistant content "" tool_calls [list [dict create function [dict create name explain_game_result arguments [dict create side $side]]]]]
	::ai::provider::configure -name stub -chatResponses [list $call [dict create role assistant content $final]]
	::application::assistant::ask "Why did White lose this game?"
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	return [dict get [lindex $::application::assistant::Priv(messages) end] content]
}

tcltest::test whylose-wait-timeout {a missing callback fails promptly without changing completion state} -body {
	set ::scidb::test::whylose::neverDone 1
	set rc [catch {::scidb::test::whylose::waitFor ::scidb::test::whylose::neverDone 1 10} err]
	set leakedTimers 0
	foreach id [after info] {
		if {[string match {*set ::scidb::test::whylose::wakeUp timeout*} [lindex [after info $id] 0]]} {
			incr leakedTimers
		}
	}
	list $rc [string match {timed out after 10ms*} $err] \
		$::scidb::test::whylose::neverDone \
		[llength [trace info variable ::scidb::test::whylose::neverDone]] \
		[expr {$leakedTimers == 0}]
} -cleanup {unset -nocomplain ::scidb::test::whylose::neverDone} -result {1 1 1 0 1}

tcltest::test whylose-offered {read-only tool offered and annotation steered to writes} -body {
	list [lindex [dict get $::application::assistant::Actions explain_game_result] 0] \
		[string match {*"name":"explain_game_result"*} [::application::assistant::toolsJson]] \
		[string match {*Use ONLY*write comments*} [lindex [dict get $::application::assistant::Actions annotate_game] 3]]
} -result {0 1 1}

tcltest::test whylose-empty-final {async facts survive an empty model turn as a written answer} -setup {
	::scidb::test::whylose::setup
	# Native game namespaces contain a switch command. Keep that collision
	# present even in the headless harness so this regression cannot hide.
	::scidb::test::whylose::stub ::scidb::game::switch {slot} {
		error "query stub invoked game switch instead of Tcl switch"
	}
} -body {
	set text [::scidb::test::whylose::run]
	list [string match {*3.e4*2.e4*1.e4*} $text] \
		[string match {*-1.50 -> -4.50*better was 3.Nc3*} $text] \
		[string match {*(no answer)*} $text] \
		[llength $::scidb::test::whylose::searches] \
		[lindex $::scidb::test::whylose::searches 0] \
		$::application::assistant::Priv(busy)
} -cleanup {::scidb::test::whylose::cleanup} -result {1 1 0 7 {-multipv 1 -movetime 200 -timeout 3000} 0}

tcltest::test whylose-black {auto selects Black from result; signs and numbering follow FEN} -setup {
	::scidb::test::whylose::setup
	set ::scidb::test::whylose::result 1-0
} -body {
	set text [::scidb::test::whylose::run]
	list [string match {*studying black*1...e5*} $text] [string match {*-0.50 -> +0.50*} $text] [string match {*3.e4*} $text]
} -cleanup {::scidb::test::whylose::cleanup} -result {1 1 0}

tcltest::test whylose-prose {normal model final is delivered after async analysis} -setup {
	::scidb::test::whylose::setup
} -body {::scidb::test::whylose::run white {The main turning point was 3.e4.}} -cleanup {
	::scidb::test::whylose::cleanup
} -result {The main turning point was 3.e4.}

tcltest::test whylose-engine-failure {engine failure still yields partial facts and a written answer} -setup {
	::scidb::test::whylose::setup
	# Replace the installed stub without changing the saved original.
	proc ::ai::engine::evaluate {fen args} {error {engine timed out}}
} -body {
	set text [::scidb::test::whylose::run]
	list [string match {*Analyzed 0 of 6*Partial pass*engine timed out*} $text] $::application::assistant::Priv(busy)
} -cleanup {::scidb::test::whylose::cleanup} -result {1 0}

tcltest::test whylose-arguments {only supported side values accepted} -body {
	list [::application::assistant::CheckArgs explain_game_result {}] \
		[catch {::application::assistant::CheckArgs explain_game_result {side purple}}]
} -result {{side auto} 1}

tcltest::test whylose-annotation-provider {annotation restores chat settings before its completion callback} -setup {
	set savedProvider [array get ::ai::provider::Config]
	set savedAnnotation [array get ::ai::annotate::Priv]
	::scidb::test::whylose::stub ::ai::annotate::SameGame {} {return 0}
	::scidb::test::whylose::stub ::ai::annotate::Report {html} {return}
	array set ::ai::annotate::Priv {running 1 done {} cancel 0 written 0 skipped 0 index 0}
	set ::ai::annotate::Priv(providerSettings) {name stub model original endpoint {} timeoutMs 120000 options {}}
	::ai::provider::configure -name stub -model drafting -timeout 300000 -options {num_predict 240}
} -body {
	::ai::annotate::Finish
	list $::ai::provider::Config(model) $::ai::provider::Config(timeoutMs) $::ai::provider::Config(options)
} -cleanup {
	::scidb::test::whylose::cleanup
	array unset ::ai::provider::Config
	array set ::ai::provider::Config $savedProvider
	array unset ::ai::annotate::Priv
	array set ::ai::annotate::Priv $savedAnnotation
} -result {original 120000 {}}


tcltest::test whylose-empty-after-annotation {a long asynchronous annotation cannot end with no answer} -setup {
	::scidb::test::whylose::setup
	::scidb::test::whylose::stub ::ai::annotate::running? {} {return 0}
	::scidb::test::whylose::stub ::ai::annotate::annotate {parent args} {
		array set opts $args
		after 5 [list {*}$opts(-done) [dict create summary {Annotated 6 moves: 1 comment written.} written 1]]
		return 1
	}
} -body {
	set call [dict create role assistant content "" tool_calls [list [dict create function [dict create name annotate_game arguments {}]]]]
	::ai::provider::configure -name stub -chatResponses [list $call [dict create role assistant content ""]]
	::application::assistant::ask "write comments into the game"
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	set text [dict get [lindex $::application::assistant::Priv(messages) end] content]
	list [string match {*Annotated 6 moves*save it*} $text] [string match {*(no answer)*} $text]
} -cleanup {::scidb::test::whylose::cleanup} -result {1 0}

tcltest::test whylose-model-failure {failed prose request still gives the engine facts and resets timeout} -setup {
	::scidb::test::whylose::setup
	::scidb::test::whylose::stub ::ai::provider::chatAsync {messages tools callback} {
		if {[dict get [lindex $messages end] role] eq "tool"} {
			set ::scidb::test::whylose::finalTools $tools
			set ::scidb::test::whylose::finalTimeout $::ai::provider::Config(timeoutMs)
			after 0 [list {*}$callback [dict create ok 0 error {model timed out}]]
		} else {
			after 0 [list {*}$callback [dict create ok 1 message [::ai::provider::stubChat]]]
		}
	}
} -body {
	set text [::scidb::test::whylose::run]
	list [string match {*engine's findings*3.e4*} $text] $::scidb::test::whylose::finalTools 		$::scidb::test::whylose::finalTimeout $::ai::provider::Config(timeoutMs)
} -cleanup {::scidb::test::whylose::cleanup} -result {1 {} 30000 120000}

tcltest::test whylose-draw {a draw does not acquire an invented loser} -setup {
	::scidb::test::whylose::setup
	set ::scidb::test::whylose::result 1/2-1/2
} -body {
	string match {*studying both*No losing side is recorded*} [::scidb::test::whylose::run]
} -cleanup {::scidb::test::whylose::cleanup} -result 1

tcltest::test whylose-no-drop {stable evaluations are reported honestly} -setup {
	::scidb::test::whylose::setup
	set ::scidb::test::whylose::scores {50 -50 50 -50 50 -50 50}
} -body {
	string match {*No clear evaluation drop*} [::scidb::test::whylose::run]
} -cleanup {::scidb::test::whylose::cleanup} -result 1



tcltest::test whylose-mate {mate evaluations retain direction and are never printed as pawns} -setup {
	::scidb::test::whylose::setup
} -body {
	set plies [lrange $::scidb::test::whylose::plies 0 0]
	set before [dict create fen [lindex [lindex $plies 0] 2] cpl 30 kind cp value 30 bestMove b1c3 pv b1c3]
	set after [dict create fen {8/8/8/8/8/8/8/K6k b - - 0 1} cpl 9990 kind mate value 1 bestMove {} pv {}]
	string match {*evaluation +0.30 -> #-1*} [::application::assistant::ResultPassSummary $plies [list $before $after] white 0-1 200]
} -cleanup {::scidb::test::whylose::cleanup} -result 1

tcltest::test whylose-final-tools {result facts cannot trigger an annotation or new-game follow-up} -setup {
	::scidb::test::whylose::setup
	set ::scidb::test::whylose::mutations 0
	::scidb::test::whylose::stub ::application::assistant::DoNewGame {} {incr ::scidb::test::whylose::mutations; return created}
} -body {
	set first [dict create role assistant content "" tool_calls [list [dict create function [dict create name explain_game_result arguments {}]]]]
	set second [dict create role assistant content "" tool_calls [list [dict create function [dict create name new_game arguments {}]]]]
	::ai::provider::configure -name stub -chatResponses [list $first $second]
	::application::assistant::ask "Where did it go wrong?"
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	list [string match {*3.e4*} [dict get [lindex $::application::assistant::Priv(messages) end] content]] $::scidb::test::whylose::mutations
} -cleanup {::scidb::test::whylose::cleanup} -result {1 0}

tcltest::test whylose-batched-tools {a read-only result request cannot turn into new copies in the same tool batch} -setup {
	::scidb::test::whylose::setup
	set ::scidb::test::whylose::mutations 0
	::scidb::test::whylose::stub ::application::assistant::DoNewGame {} {incr ::scidb::test::whylose::mutations; return created}
} -body {
	set calls {}
	foreach name {explain_game_result new_game} {lappend calls [dict create function [dict create name $name arguments {}]]}
	set first [dict create role assistant content "" tool_calls $calls]
	::ai::provider::configure -name stub -chatResponses [list $first [dict create role assistant content ""]]
	::application::assistant::ask "Why did I lose?"
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	set messages $::application::assistant::Priv(messages)
	list [string match {*3.e4*} [dict get [lindex $messages end] content]] \
		[string match {error: not performed*} [dict get [lindex $messages end-1] content]] $::scidb::test::whylose::mutations
} -cleanup {::scidb::test::whylose::cleanup} -result {1 1 0}

tcltest::test whylose-deadline {a pass hitting its wall-clock budget returns partial evidence and releases the request} -setup {
	::scidb::test::whylose::setup
} -body {
	set token [::application::assistant::runTool explain_game_result {}]
	::scidb::test::whylose::pendingResult $token
	set ::application::assistant::ResultPass(deadline) 0
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	string match {*Analyzed 0 of 6*Partial pass*} [dict get [lindex $::application::assistant::Priv(messages) end] content]
} -cleanup {::scidb::test::whylose::cleanup} -result 1

# Native GUI-shell checks: the stubs above cover the model/engine seam; these
# use the real game backend to check header identity and read-only semantics.
tcltest::testConstraint whyloseNative [expr {[llength [info commands ::scidb::game::load]] > 0}]
proc ::scidb::test::whylose::nativeFixture {} {
	captureAsync
	variable originalSlot [::scidb::game::current]
	variable nativeAssistant [array get ::application::assistant::Priv]
	variable nativeAnnotation [array get ::ai::annotate::Priv]
	variable nativeProvider [array get ::ai::provider::Config]
	variable fixture [file join [file dirname [file normalize [info script]]] tmp-app whylose identity.pgn]
	file mkdir [file dirname $fixture]
	set f [open $fixture w]
	puts $f {[Event "Loss identity"]
[White "Alice"]
[Black "Bob"]
[Result "0-1"]

1. e4 e5 2. Nf3 Nc6 0-1}
	close $f
	::scidb::db::open $fixture ::scidb::test::whylose::nop {} ::scidb::test::whylose::nop {}
	::scidb::game::load 55 $fixture Normal 0
	::scidb::game::subscribe board 55 ::scidb::test::whylose::nop
	::scidb::game::switch 55
	stub ::ai::engine::available {} {return 1}
	stub ::application::assistant::Append {args} {return}
	stub ::application::assistant::SetBusy {flag} {set ::application::assistant::Priv(busy) $flag}
	stub ::application::assistant::LogToolCall {args} {return}
}
proc ::scidb::test::whylose::nop {args} {}
proc ::scidb::test::whylose::nativeCleanup {} {
	variable fixture
	variable originalSlot
	variable nativeAssistant
	variable nativeAnnotation
	variable nativeProvider
	::scidb::game::switch $originalSlot
	catch {::scidb::game::release 55}
	catch {::scidb::db::close $fixture}
	catch {file delete $fixture}
	cleanup
	array unset ::application::assistant::Priv
	array set ::application::assistant::Priv $nativeAssistant
	array unset ::ai::annotate::Priv
	array set ::ai::annotate::Priv $nativeAnnotation
	array unset ::ai::provider::Config
	array set ::ai::provider::Config $nativeProvider
}
proc ::scidb::test::whylose::nativeSnapshot {} {
	return [list [::scidb::game::current] [::scidb::game::link?] \
		[::scidb::game::tags 55] [::scidb::game::position key] \
		[::scidb::game::query modified?] \
		[::scidb::game::toPGN [expr {[::scidb::game::query modified?] ? "modified" : "original"}]]]
}

tcltest::test whylose-native-readonly {result pass preserves game, source link, header, key and comments} -constraints whyloseNative -setup {
	::scidb::test::whylose::nativeFixture
	::scidb::test::whylose::stub ::ai::engine::evaluate {fen args} {
		return [dict create fen $fen kind cp value 0 cpl 0 bestMove {} pv {}]
	}
} -body {
	set before [::scidb::test::whylose::nativeSnapshot]
	set token [::application::assistant::runTool explain_game_result {}]
	::scidb::test::whylose::pendingResult $token
	::scidb::test::whylose::waitFor ::application::assistant::Priv(busy)
	expr {$before eq [::scidb::test::whylose::nativeSnapshot]}
} -cleanup {::scidb::test::whylose::nativeCleanup} -result 1

tcltest::test whylose-native-annotation-identity {annotation writes in place without creating another game or changing its header} -constraints whyloseNative -setup {
	::scidb::test::whylose::nativeFixture
	::scidb::test::whylose::stub ::ai::engine::classify {fen san args} {
		return [dict create classification Mistake cpLoss 100 bestMove {} uci {} onlyMove 0]
	}
	::scidb::test::whylose::stub ::ai::annotate::Prioritise {result} {
		::ai::annotate::Write $result {Engine verdict.}
		after 1 ::ai::annotate::NextPly
	}
	set ::scidb::test::whylose::nativeDone {}
} -body {
	set before [list [::scidb::game::current] [::scidb::game::link?] [::scidb::game::tags 55] [::scidb::game::position key]]
	if {![::ai::annotate::annotate .application -prose 0 -progress ::scidb::test::whylose::nop \
		-done {set ::scidb::test::whylose::nativeDone}]} {
		error "native annotation did not start"
	}
	::scidb::test::whylose::waitFor ::scidb::test::whylose::nativeDone 0
	set after [list [::scidb::game::current] [::scidb::game::link?] [::scidb::game::tags 55] [::scidb::game::position key]]
	list [expr {$before eq $after}] [dict get $::scidb::test::whylose::nativeDone written] \
		[string match {*Engine verdict.*} [::scidb::game::toPGN modified]]
} -cleanup {::scidb::test::whylose::nativeCleanup} -result {1 4 1}

tcltest::cleanupTests
