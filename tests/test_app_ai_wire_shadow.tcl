# ======================================================================
# Scidb App Test — the audit A9/A10 shadow hook in tcl/ai-provider.tcl:
# before a completion entry point sends, the cloud egress gate
# (::ai::egress::decide, cloud providers only) and the tier router
# (::ai::tier::decide, every provider) are asked and their answers are
# written to the decision journal. The request itself is untouched and
# not delayed; 'off' skips a gate; a missing gate or a failing classifier
# changes nothing.
# ======================================================================
# Modelled on tests/test_app_ai_egress.tcl / test_app_ai_tier.tcl, the
# app tests of the two modules being wired: the real gates are used (they
# answer through after 0), the journal is pointed at a per-process temp
# file, and the stub provider stands in for a send so no network is
# touched. ::ai::decide is stubbed wherever the classifier path is
# reached, and put back so the test files after this one see the real
# command. The shadow gates are driven through ::ai::provider::shadow, the
# hook the completion entry points now call, so no HTTP is involved.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::wire {}

set ::scidb::test::wire::Root \
	[file join [file dirname [file normalize [info script]]] ..]

# The provider layer under test, the real gates it calls, and the journal
# it records into.
source [file join $::scidb::test::wire::Root tcl ai-provider.tcl]
source [file join $::scidb::test::wire::Root tcl ai-egress.tcl]
source [file join $::scidb::test::wire::Root tcl ai-tier.tcl]
source [file join $::scidb::test::wire::Root tcl ai-journal.tcl]

set ::scidb::test::wire::Decision {ok 0}
set ::scidb::test::wire::Saved {}

set ::scidb::test::wire::File [file join [file dirname [file normalize [info script]]] \
	tmp-app ai-wire-shadow-[pid].txt]

# --- the prompts of each scenario (see test_app_ai_egress.tcl) ----------

# A game the user has open: PGN tags and movetext, private by the rule.
proc ::scidb::test::wire::Game {} {
	return "Annotate this game:\n\[White \"Kasparov, Garry\"\]\n\[Black \"Short, Nigel D.\"\]\n1. e4 e5 2. Nf3 Nc6 3. Bb5"
}

# A request the egress rule abstains on (nothing private, no position), so
# the classifier path is the one exercised.
proc ::scidb::test::wire::Undecided {} {
	return "what should I study next, given my recent results"
}

# A short request over read-only tools: the tier rule's 'local' case.
proc ::scidb::test::wire::Ask {} {
	return "summarize the database"
}

# --- helpers -------------------------------------------------------------

# A clean slate: journal to a fresh file, settings reset, modes to shadow.
proc ::scidb::test::wire::Reset {} {
	catch { file delete $::scidb::test::wire::File }
	::ai::journal::configure -file $::scidb::test::wire::File
	set ::ai::provider::EgressMode shadow
	set ::ai::provider::TierMode shadow
	::ai::provider::configure -name stub -model "" -endpoint "" \
		-responses {canned-answer} -chatResponses {}
	return
}

# The shadow gates answer from after 0: pump the event loop before the
# journal is read.
proc ::scidb::test::wire::Pump {} {
	# 50 ms is plenty on a fast machine, not on a slow VM: go on while the
	# journal still grows (at most 3 s)
	set size -1
	for {set waited 0} {$waited < 3000} {incr waited 50} {
		set ::scidb::test::wire::done 0
		after 50 [list set ::scidb::test::wire::done 1]
		vwait ::scidb::test::wire::done
		set now [expr {[file exists $::scidb::test::wire::File] ? [file size $::scidb::test::wire::File] : 0}]
		if {$now == $size && $waited >= 50} { break }
		set size $now
	}
	return
}

# The decision records of one feature, oldest first; no feature means every
# record in the file.
proc ::scidb::test::wire::Records {{feature ""} {file ""}} {
	if {$file eq ""} { set file $::scidb::test::wire::File }
	set out {}
	foreach r [::ai::journal::read $file] {
		if {[dict get $r type] eq "decision"
		 && ($feature eq "" || [dict get $r feature] eq $feature)} {
			lappend out $r
		}
	}
	return $out
}

# ::ai::decide's contract, reduced to what these tests need: the canned
# decision, else the recorded -fallback, else {ok 0}. Canned {ok 0} makes
# the gate's own -fallback decide, which is the deterministic answer.
proc ::scidb::test::wire::Decide {feature state question script args} {
	array set opts {-fallback {} -threshold 0.6}
	array set opts $args
	if {[dict get $::scidb::test::wire::Decision ok]} {
		set d $::scidb::test::wire::Decision
	} elseif {[llength $opts(-fallback)]} {
		set d [list ok 1 label [uplevel #0 $opts(-fallback)] confidence {} source rules]
	} else {
		set d [list ok 0]
	}
	after 0 [list {*}$script $d]
	return
}

# Install the stub as ::ai::decide, saving the real command aside.  An
# earlier test may have taken the stub away and left the real command;
# every state undoes (see test_app_ai_egress.tcl).
proc ::scidb::test::wire::StubDecide {{decision {ok 0}}} {
	set ::scidb::test::wire::Decision $decision
	if {[llength [info commands ::ai::decide]]} {
		set ::scidb::test::wire::Saved ::scidb::test::wire::realDecide
		rename ::ai::decide $::scidb::test::wire::Saved
	}
	rename ::scidb::test::wire::Decide ::ai::decide
	return
}

# The real command (or nothing at all) goes back: with a real ::ai::decide
# saved aside, and with no classifier in the process at all -- the stub
# then sits at ::ai::decide, and only the stub may be taken away.
proc ::scidb::test::wire::RestoreDecide {} {
	if {[info exists ::scidb::test::wire::Saved]
	 && $::scidb::test::wire::Saved ne ""
	 && [llength [info commands $::scidb::test::wire::Saved]]} {
		if {[llength [info commands ::scidb::test::wire::Decide]] == 0
		 && [llength [info commands ::ai::decide]]} {
			rename ::ai::decide ::scidb::test::wire::Decide
		}
		rename $::scidb::test::wire::Saved ::ai::decide
	} elseif {[llength [info commands ::scidb::test::wire::Decide]] == 0
	 && [llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::wire::Decide
	}
	set ::scidb::test::wire::Saved {}
	return
}

# --- the hook does not change the send -----------------------------------

# The whole point of 'shadow': the answer the caller gets is the provider's,
# unchanged. The stub provider is local, so no egress label is due.
tcltest::test wire-complete-unchanged {a labelled request still returns the provider's answer} -setup {
	::scidb::test::wire::Reset
	::scidb::test::wire::StubDecide {ok 0}
} -body {
	set text [::ai::provider::complete [::scidb::test::wire::Game]]
	::scidb::test::wire::Pump
	list $text [llength [::scidb::test::wire::Records egress]]
} -cleanup {
	::scidb::test::wire::RestoreDecide
} -result {canned-answer 0}

# --- A9: the cloud egress gate, cloud providers only ---------------------

# A local provider sends nothing off this machine, so the egress gate is
# not even asked.
tcltest::test wire-egress-local {a local provider is not asked about egress} -setup {
	::scidb::test::wire::Reset
	::scidb::test::wire::StubDecide {ok 0}
} -body {
	::ai::provider::shadow [::scidb::test::wire::Game]
	::scidb::test::wire::Pump
	llength [::scidb::test::wire::Records egress]
} -cleanup {
	::scidb::test::wire::RestoreDecide
} -result 0

# A cloud provider is asked, and a prompt carrying a game is labelled
# 'hold' -- recorded, never acted on here. The state is the prompt itself.
tcltest::test wire-egress-cloud {a cloud provider's private prompt is labelled and journalled} -setup {
	::scidb::test::wire::Reset
	::ai::provider::configure -name anthropic -model claude -endpoint http://example.invalid
} -body {
	::ai::provider::shadow [::scidb::test::wire::Game]
	::scidb::test::wire::Pump
	set r [lindex [::scidb::test::wire::Records egress] 0]
	list [dict get $r label] [dict get $r source] [dict get $r confidence] \
		[expr {[string match "*Kasparov*" [dict get $r state]] ? "prompt" : "other"}]
} -result {hold rules 1.0 prompt}

# --- A10: the tier router, every provider --------------------------------

# The tier router labels the request whatever provider serves it, so the
# tier a request wanted can be compared with the provider that answered.
# Nothing settles this request, so the router's own fallback decides.
tcltest::test wire-tier-every-provider {every provider's request is tiered} -setup {
	::scidb::test::wire::Reset
	::scidb::test::wire::StubDecide {ok 0}
} -body {
	::ai::provider::shadow [::scidb::test::wire::Undecided]
	::scidb::test::wire::Pump
	set r [lindex [::scidb::test::wire::Records tier] 0]
	list [dict get $r label] [dict get $r source] [dict get $r confidence]
} -cleanup {
	::scidb::test::wire::RestoreDecide
} -result {configured rules {}}

# The chat request is summarised by the router's own state, which names the
# tools the request may touch: a short read-only request is 'local'.
tcltest::test wire-tier-chat-tools {the chat request carries its tools into the tier state} -setup {
	::scidb::test::wire::Reset
} -body {
	::ai::provider::shadow [::ai::provider::requestText \
		[list [dict create role system content "you are scidb"] \
			[dict create role user content [::scidb::test::wire::Ask]]]] \
		{current_game list_open_databases}
	::scidb::test::wire::Pump
	set r [lindex [::scidb::test::wire::Records tier] 0]
	list [dict get $r label] [dict get $r state]
} -result {local {chars=22 tools=current_game list_open_databases}}

# --- SCIDB_AI_EGRESS / SCIDB_AI_TIER: off | shadow, default shadow -------

tcltest::test wire-modes-default-shadow {both gates default to shadow; unknown values do not win} -setup {
	unset -nocomplain ::env(SCIDB_AI_EGRESS) ::env(SCIDB_AI_TIER)
} -body {
	source [file join $::scidb::test::wire::Root tcl ai-provider.tcl]
	list $::ai::provider::EgressMode $::ai::provider::TierMode
} -cleanup {
	unset -nocomplain ::env(SCIDB_AI_EGRESS) ::env(SCIDB_AI_TIER)
	::scidb::test::wire::Reset
} -result {shadow shadow}

tcltest::test wire-modes-env-off {SCIDB_AI_EGRESS and SCIDB_AI_TIER switch a gate off} -setup {
	set ::env(SCIDB_AI_EGRESS) off
	set ::env(SCIDB_AI_TIER) off
} -body {
	source [file join $::scidb::test::wire::Root tcl ai-provider.tcl]
	list $::ai::provider::EgressMode $::ai::provider::TierMode
} -cleanup {
	unset -nocomplain ::env(SCIDB_AI_EGRESS) ::env(SCIDB_AI_TIER)
	::scidb::test::wire::Reset
} -result {off off}

tcltest::test wire-modes-off-skips {mode off asks neither gate} -setup {
	::scidb::test::wire::Reset
	::ai::provider::configure -name anthropic -model claude -endpoint http://example.invalid
} -body {
	set ::ai::provider::EgressMode off
	set ::ai::provider::TierMode off
	::ai::provider::shadow [::scidb::test::wire::Game]
	::scidb::test::wire::Pump
	list [llength [::scidb::test::wire::Records egress]] \
		[llength [::scidb::test::wire::Records tier]]
} -result {0 0}

# --- the guards ----------------------------------------------------------

# The provider layer must work with the ai module absent: no gate command,
# no call, no error.
tcltest::test wire-gate-absent {a request is unaffected when the gates are not loaded} -setup {
	::scidb::test::wire::Reset
	::ai::provider::configure -name anthropic -model claude -endpoint http://example.invalid
	rename ::ai::egress::decide ::scidb::test::wire::savedEgress
	rename ::ai::tier::decide ::scidb::test::wire::savedTier
} -body {
	::ai::provider::shadow [::scidb::test::wire::Game]
	::scidb::test::wire::Pump
	llength [::scidb::test::wire::Records]
} -cleanup {
	rename ::scidb::test::wire::savedEgress ::ai::egress::decide
	rename ::scidb::test::wire::savedTier ::ai::tier::decide
} -result 0

# A classifier that fails must never reach the request: the gate swallows
# the error and the caller sees nothing of it.
tcltest::test wire-classifier-failure {a failing classifier leaves the request alone} -setup {
	::scidb::test::wire::Reset
	::ai::provider::configure -name anthropic -model claude -endpoint http://example.invalid
	set ::scidb::test::wire::Saved {}
	if {[llength [info commands ::ai::decide]]} {
		set ::scidb::test::wire::Saved ::scidb::test::wire::realDecide
		rename ::ai::decide $::scidb::test::wire::Saved
	}
	proc ::ai::decide {args} { error "classifier is down" }
} -body {
	# the rule abstains on the prompt, so the classifier is asked and fails
	::ai::provider::shadow [::scidb::test::wire::Undecided]
	::scidb::test::wire::Pump
	set caught [catch { ::ai::provider::shadow [::scidb::test::wire::Undecided] } err]
	list $caught $err [llength [::scidb::test::wire::Records]]
} -cleanup {
	rename ::ai::decide {}
	::scidb::test::wire::RestoreDecide
} -result {0 {} 0}

::tcltest::cleanupTests
return
