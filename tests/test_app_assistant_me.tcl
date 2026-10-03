# ======================================================================
# Scidb App Test — the assistant knows who 'me' is (tcl/app-assistant.tcl)
# ======================================================================
# MePrompt names the user in the system prompt: the name given to the
# remember_me tool (::application::ai::Settings(me)), else the private
# player card's (::playercard::Var(Name)); unknown, it tells the model to
# ask for the name.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::me {}

# Run <body> with Settings(me) = <me> and the card's name = <card> ("" for
# none); both are put back afterwards.
# <card>: the name on the private player card marked "This is me" (kept in
# memory here; nothing is written)
proc ::scidb::test::me::with {me card body} {
	set savedMe $::application::ai::Settings(me)
	set hadCards [info exists ::playercard::Private]
	if {$hadCards} { set savedCards $::playercard::Private }

	set ::application::ai::Settings(me) $me
	set ::playercard::Private [expr {$card eq "" ? {} : [dict create $card [dict create Name $card Me 1]]}]

	set rc [catch { uplevel 1 $body } result]

	set ::application::ai::Settings(me) $savedMe
	unset -nocomplain ::playercard::Private
	if {$hadCards} { set ::playercard::Private $savedCards }
	return -code $rc $result
}

# The system message of a one-round request answered by the stub.
proc ::scidb::test::me::systemOf {request} {
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses [list [dict create role assistant content "Hi."]]
	::application::assistant::clear
	::application::assistant::ask $request
	if {$::application::assistant::Priv(busy)} { vwait ::application::assistant::Priv(busy) }
	array set $cfg $saved
	set system [dict get [lindex $::application::assistant::Priv(messages) 0] content]
	::application::assistant::clear
	return $system
}

tcltest::test assistant-me-setting {the remembered name is used} -body {
	::scidb::test::me::with {Musterfrau, Anna} {} { ::application::assistant::MePrompt }
} -result {The user is Musterfrau, Anna. When the user says I, me or my games, use the player name Musterfrau, Anna in tool arguments.}

tcltest::test assistant-me-card {without a remembered name, the card's name is used} -body {
	::scidb::test::me::with {} {Musterfrau, Anna} {
		string match {The user is Musterfrau, Anna.*} [::application::assistant::MePrompt]
	}
} -result 1

tcltest::test assistant-me-setting-first {the remembered name wins over the card} -body {
	::scidb::test::me::with {Thomas, Michael} {Musterfrau, Anna} {
		string match {The user is Thomas, Michael.*} [::application::assistant::MePrompt]
	}
} -result 1

tcltest::test assistant-me-unknown {an unknown user is asked for the name} -body {
	::scidb::test::me::with {} {} {
		string match {*not known*remember_me*} [::application::assistant::MePrompt]
	}
} -result 1

tcltest::test assistant-me-remember {remember_me stores the name; an empty name forgets it} -body {
	::scidb::test::me::with {} {} {
		set a [::application::assistant::runTool remember_me {name {Thomas, Michael}}]
		set b $::application::ai::Settings(me)
		set c [::application::assistant::runTool remember_me {name {}}]
		list [string match {Remembered*Thomas, Michael*} $a] $b \
			[string match {Forgotten*} $c] $::application::ai::Settings(me)
	}
} -result {1 {Thomas, Michael} 1 {}}

tcltest::test assistant-me-system-message {the system message sent to the model names the user} -body {
	::scidb::test::me::with {Musterfrau, Anna} {} {
		string match {*The user is Musterfrau, Anna.*} [::scidb::test::me::systemOf "show my games"]
	}
} -result 1

tcltest::test assistant-me-offered {remember_me is offered to the model} -body {
	string match {*"name":"remember_me"*} [::application::assistant::toolsJson]
} -result 1

tcltest::cleanupTests
