# ======================================================================
# Scidb App Test — assistant from the terminal (--ask, --chat)
# ======================================================================
# The protocol is driven over a raw socket against this instance's own
# single-instance server; the model is the stub provider.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::cli {
	variable Lines {}
}

tcltest::testConstraint haveServer [info exists ::remote::Vars(port)]

# Open a session, send <messages> one at a time as the server asks for
# input, collect the decoded messages until the last "ready".
#   <answers>  replies to "confirm" messages, in order
proc ::scidb::test::cli::session {replies messages {answers {}}} {
	variable Lines {}
	variable Answers $answers
	variable Pending $messages
	variable Done 0

	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses $replies

	set sock [socket 127.0.0.1 $::remote::Vars(port)]
	fconfigure $sock -blocking 0 -buffering line -encoding utf-8
	puts $sock [list --assistant]
	fileevent $sock readable [list ::scidb::test::cli::read $sock]

	set timer [after 20000 { set ::scidb::test::cli::Done timeout }]
	vwait ::scidb::test::cli::Done
	after cancel $timer
	catch { close $sock }
	array set $cfg $saved
	return $Lines
}

proc ::scidb::test::cli::read {sock} {
	variable Lines
	variable Answers
	variable Pending

	if {[gets $sock line] < 0} {
		if {[eof $sock]} { set ::scidb::test::cli::Done eof }
		return
	}
	set msg [::remote::decodeLine $line]
	lappend Lines $msg
	switch -- [lindex $msg 0] {
		hello - ready {
			if {[llength $Pending]} {
				set Pending [lassign $Pending next]
				puts $sock [::remote::encodeLine {*}$next]
			} else {
				set ::scidb::test::cli::Done 1
			}
		}
		confirm {
			set Answers [lassign $Answers answer]
			puts $sock [::remote::encodeLine confirm $answer]
		}
	}
}

proc ::scidb::test::cli::call {name {arguments {}}} {
	return [dict create role assistant content "" tool_calls \
		[list [dict create function [dict create name $name arguments $arguments]]]]
}

tcltest::test cli-line-codec {messages with newlines and backslashes survive one line} -body {
	set msg [list tool app_state "line1\nline2 {brace} \\n literal \\\\ \r end"]
	set enc [::remote::encodeLine {*}$msg]
	list [expr {[string first \n $enc] < 0}] [expr {[::remote::decodeLine $enc] eq $msg}]
} -result {1 1}

tcltest::test cli-ask-parses-both-forms {--ask takes its value as --ask=X or --ask X} -body {
	set saved [list [array get ::process::Options] [array get ::process::Valued] $::argv $::argc]
	set result {}
	# the option table is dropped after startup; parsing needs one to warn
	set ::process::ProgramOptions {{--ask=REQUEST} {--chat}}
	foreach argv {{{--ask=hello there}} {--ask {hello there} db.sci} {--ask=} {--chat}} {
		array unset ::process::Options
		array unset ::process::Valued
		set ::argv $argv
		set ::argc [llength $argv]
		::process::ParseArgs
		lappend result [list [::process::testOption ask] [::process::optionValue ask] \
			[::process::testOption chat] [::process::arguments]]
	}
	unset ::process::ProgramOptions
	lassign $saved options valued ::argv ::argc
	array unset ::process::Options
	array unset ::process::Valued
	array set ::process::Options $options
	array set ::process::Valued $valued
	set result
} -result {{1 {hello there} 0 {}} {1 {hello there} 0 db.sci} {1 {} 0 {}} {0 {} 1 {}}}

tcltest::test cli-session-multiline-tool {a multi-line tool reply arrives whole} -constraints haveServer -body {
	::application::assistant::clear
	set lines [::scidb::test::cli::session [list \
		[::scidb::test::cli::call app_state] \
		[dict create role assistant content "Two lines\nof answer."]] \
		[list [list ask "what state is the app in?"]]]
	set kinds [lmap m $lines { lindex $m 0 }]
	set tool [lsearch -inline -index 0 $lines tool]
	list $kinds [lindex $tool 1] [string match "*\nactive database: *" [lindex $tool 2]] \
		[lindex [lsearch -inline -index 0 $lines reply] 1]
} -result {{hello tool reply ready} app_state 1 {Two lines
of answer.}}

tcltest::test cli-session-confirm-denied {a terminal "no" keeps the action from running} -constraints haveServer -body {
	rename ::menu::gameNew ::scidb::test::cli::realGameNew
	proc ::menu::gameNew {args} { set ::scidb::test::cli::ran 1 }
	set ::scidb::test::cli::ran 0
	set lines [::scidb::test::cli::session [list \
		[::scidb::test::cli::call new_game] \
		[dict create role assistant content "Declined."]] \
		[list [list ask "start a new game"]] {0}]
	rename ::menu::gameNew {}
	rename ::scidb::test::cli::realGameNew ::menu::gameNew
	list [lmap m $lines { lindex $m 0 }] $::scidb::test::cli::ran \
		[string match "*NOT performed*" [lindex [lsearch -inline -index 0 $lines tool] 2]]
} -result {{hello confirm tool reply ready} 0 1}

tcltest::test cli-session-confirm-allowed {a terminal "yes" runs the action} -constraints haveServer -body {
	rename ::menu::gameNew ::scidb::test::cli::realGameNew
	proc ::menu::gameNew {args} { set ::scidb::test::cli::ran 1 }
	set ::scidb::test::cli::ran 0
	::scidb::test::cli::session [list \
		[::scidb::test::cli::call new_game] \
		[dict create role assistant content "Done."]] \
		[list [list ask "start a new game"]] {1}
	rename ::menu::gameNew {}
	rename ::scidb::test::cli::realGameNew ::menu::gameNew
	set ::scidb::test::cli::ran
} -result 1

tcltest::test cli-session-clear-and-errors {clear, empty and unknown requests are answered} -constraints haveServer -body {
	set lines [::scidb::test::cli::session {} [list [list clear] [list ask "  "] [list frobnicate]]]
	lmap m $lines { expr {[lindex $m 0] eq "hello" ? "hello" : [lrange $m 0 1]} }
} -result {hello ready {error {empty request}} ready {error {unknown request 'frobnicate'}} ready}

tcltest::test cli-session-shares-the-pane {terminal requests appear in the assistant pane} -constraints haveServer -body {
	::application::assistant::show
	::application::assistant::clear
	::scidb::test::cli::session [list [dict create role assistant content "Hi from the pane."]] \
		[list [list ask "hello from the terminal"]]
	set text [$::application::assistant::Priv(text) get 1.0 end]
	list [string match "*> hello from the terminal*" $text] [string match "*Hi from the pane.*" $text]
} -result {1 1}

# the Windows executable loads its own script: a copied script is no other port
tcltest::test cli-ask-without-instance {--ask exits 2 when no instance is running} -constraints unix -body {
	set exe [file join $::scidb::test::app::testDir .. src tkchesswiz]
	set script [file join $::scidb::test::app::testDir .. tcl chesswiz]
	# a different script path means a different port: nothing listens there
	set copy [file join [file dirname $script] chesswiz-cli-test]
	file copy -force $script $copy
	set rc [catch { exec $exe $copy --ask "hello" 2>@1 } out opts]
	file delete $copy
	set code [expr {$rc ? [lindex [dict get $opts -errorcode] 2] : 0}]
	list $code [string match "*is not running*" $out]
} -result {2 1}

# ----------------------------------------------------------------------

::tcltest::cleanupTests
return
