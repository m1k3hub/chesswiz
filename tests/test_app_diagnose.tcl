# ======================================================================
# Scidb App Test — diagnosis of the running program (tcl/app-diagnose.tcl,
# src/tcl/tcl_diag.cpp) and the assistant's debug tools built on it.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::diag {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app diag_[pid]]
	variable Answer 1
	variable Saved {}
}

proc ::scidb::test::diag::confirm {what} { return $::scidb::test::diag::Answer }

proc ::scidb::test::diag::setup {} {
	variable Dir
	variable Saved
	file delete -force $Dir
	file mkdir $Dir
	set Saved [list $::application::assistant::Priv(debug) $::application::assistant::Priv(confirm) \
		[expr {[info exists ::scidb::dir::user] ? $::scidb::dir::user : ""}]]
	set ::application::assistant::Priv(debug) 1
	set ::application::assistant::Priv(confirm) ::scidb::test::diag::confirm
	set ::scidb::dir::user $Dir
}

proc ::scidb::test::diag::cleanup {} {
	variable Dir
	variable Saved
	lassign $Saved debug confirm user
	set ::application::assistant::Priv(debug) $debug
	set ::application::assistant::Priv(confirm) $confirm
	set ::scidb::dir::user $user
	catch { destroy .diagtest }
	catch { grab release .diagtest.mb }
	foreach id [after info] {
		if {[string match *diagtest* [lindex [after info $id] 0]]} { after cancel $id }
	}
	file delete -force $Dir
}

proc ::scidb::test::diag::stuckGrab {} {
	toplevel .diagtest
	tk::menubutton .diagtest.mb -text x -menu .diagtest.mb.m
	menu .diagtest.mb.m
	pack .diagtest.mb
	update
	grab -global .diagtest.mb
}

proc ::scidb::test::diag::tool {name {cargs {}}} {
	return [::application::assistant::runTool $name $cargs]
}

# ----------------------------------------------------------------------

tcltest::test diag-tools-gated {the diagnosis tools exist only in debug mode} -setup {
	::scidb::test::diag::setup
} -body {
	package require json
	set ::application::assistant::Priv(debug) 0
	set names [lmap t [json::json2dict [::application::assistant::toolsJson]] { dict get $t function name }]
	set refused [::scidb::test::diag::tool ui_state]
	set ::application::assistant::Priv(debug) 1
	set names2 [lmap t [json::json2dict [::application::assistant::toolsJson]] { dict get $t function name }]
	list [expr {"ui_state" in $names}] $refused \
		[expr {[llength [lmap n {ui_state timers loop_health media_state child_processes hang_dumps release_grab cancel_timer} {
			expr {$n in $names2 ? $n : [continue]}}]]}]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {0 {error: 'ui_state' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)} 8}

tcltest::test diag-stuck-grab-detected {a menubutton holding a grab with no posted menu is flagged} -setup {
	::scidb::test::diag::setup
} -body {
	::scidb::test::diag::stuckGrab
	set text [::scidb::test::diag::tool ui_state]
	list [string match "*grab: .diagtest.mb (Menubutton, global*" $text] \
		[string match "*LIKELY STUCK: a menubutton holds the grab but its menu is not posted*" $text]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {1 1}

tcltest::test diag-no-grab {a healthy state reports no grab and no warning} -setup {
	::scidb::test::diag::setup
} -body {
	set text [::scidb::test::diag::tool ui_state]
	list [string match "*grab: none*" $text] [string match "*STUCK*" $text]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {1 0}

tcltest::test diag-release-grab-confirmed {release_grab asks first, and frees the GUI only when allowed} -setup {
	::scidb::test::diag::setup
} -body {
	::scidb::test::diag::stuckGrab
	set ::scidb::test::diag::Answer 0
	set denied [::scidb::test::diag::tool release_grab {window .diagtest.mb}]
	set stillHeld [grab current]
	set ::scidb::test::diag::Answer 1
	set allowed [::scidb::test::diag::tool release_grab {window .diagtest.mb}]
	list [string match "*NOT performed*" $denied] $stillHeld [string match "released the global grab of .diagtest.mb*" $allowed] [grab current]
} -cleanup {
	set ::scidb::test::diag::Answer 1
	::scidb::test::diag::cleanup
} -result {1 .diagtest.mb 1 {}}

tcltest::test diag-release-grab-holder-only {release_grab refuses a window that holds no grab} -setup {
	::scidb::test::diag::setup
} -body {
	::scidb::test::diag::tool release_grab {window .}
} -cleanup {
	::scidb::test::diag::cleanup
} -match glob -result {error: . holds no grab*}

tcltest::test diag-timers-and-cancel {pending timers are listed; one is cancelled by id, after confirmation} -setup {
	::scidb::test::diag::setup
} -body {
	set id [after 600000 {diagtest-marker}]
	set listed [string match "*$id*diagtest-marker*" [::scidb::test::diag::tool timers]]
	set ::scidb::test::diag::Answer 0
	set denied [string match "*NOT performed*" [::scidb::test::diag::tool cancel_timer [list id $id]]]
	set stillThere [expr {$id in [after info]}]
	set ::scidb::test::diag::Answer 1
	set done [::scidb::test::diag::tool cancel_timer [list id $id]]
	list $listed $denied $stillThere [string match "cancelled $id:*" $done] [expr {$id in [after info]}] \
		[::scidb::test::diag::tool cancel_timer {id after#999999}]
} -cleanup {
	set ::scidb::test::diag::Answer 1
	::scidb::test::diag::cleanup
} -result {1 1 1 1 0 {error: no pending timer after#999999}}

tcltest::test diag-secrets-scrubbed {a credential in the environment never reaches a tool reply} -setup {
	::scidb::test::diag::setup
	set ::env(SCIDB_TEST_API_KEY) sk-very-secret-0123456789
	set ::env(SCIDB_TEST_NOTE) plain-visible-value
} -body {
	set r [::scidb::test::diag::tool read_variable {name ::env pattern SCIDB_TEST_*}]
	list [string match "*sk-very-secret*" $r] [string match "*<redacted:SCIDB_TEST_API_KEY>*" $r] \
		[string match "*plain-visible-value*" $r]
} -cleanup {
	unset -nocomplain ::env(SCIDB_TEST_API_KEY) ::env(SCIDB_TEST_NOTE)
	::scidb::test::diag::cleanup
} -result {0 1 1}

tcltest::test diag-stack-names-the-stalled-code {the stack text shows the procs being executed} -setup {
	::scidb::test::diag::setup
} -body {
	proc ::scidb::test::diag::stalledLeaf {} { ::application::diagnose::stackText }
	proc ::scidb::test::diag::stalledRoot {} { ::scidb::test::diag::stalledLeaf }
	set text [::scidb::test::diag::stalledRoot]
	set leaf [string first ::scidb::test::diag::stalledLeaf $text]
	set root [string first ::scidb::test::diag::stalledRoot $text]
	# no stack line may belong to the diagnosis code itself
	list [expr {$leaf >= 0 && $root > $leaf}] [regexp -line {^  ::application::diagnose::} $text]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {1 0}

tcltest::test diag-hang-dump-file {a dump is written to the log directory and readable through hang_dumps} -setup {
	::scidb::test::diag::setup
} -body {
	set none [::scidb::test::diag::tool hang_dumps]
	set file [::application::diagnose::dumpStack manual]
	set text [::scidb::test::diag::tool hang_dumps]
	list [string match "no hang dumps*" $none] [file exists $file] \
		[string match "*hang dump (manual)*" $text] [string match "*Tcl stack*" $text]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {1 1 1 1}

tcltest::test diag-signal-dump {SIGUSR1 makes the interpreter dump the stack of the code it is running} -setup {
	::scidb::test::diag::setup
} -constraints {unix} -body {
	::diag::install [file join $::scidb::test::diag::Dir hang-native.txt]
	proc ::scidb::test::diag::spin {} {
		exec kill -USR1 [pid]
		set end [expr {[clock milliseconds] + 400}]
		while {[clock milliseconds] < $end} { after 10 }
	}
	::scidb::test::diag::spin
	set files [glob -nocomplain -directory [file join $::scidb::test::diag::Dir log] hang-2*.txt]
	set fh [open [lindex $files 0]]; set text [read $fh]; close $fh
	list [llength $files] [string match "*hang dump (signal)*" $text] [string match "*::scidb::test::diag::spin*" $text]
} -cleanup {
	::scidb::test::diag::cleanup
} -result {1 1 1}

tcltest::test diag-loop-health {a stall of the event loop is recorded by the heartbeat} -setup {
	::scidb::test::diag::setup
	array set ::scidb::test::diag::Keep [array get ::application::diagnose::Priv]
	set ::application::diagnose::Priv(gaps) {}
	set ::application::diagnose::Priv(worst) 0
} -body {
	::application::diagnose::startHeartbeat
	set before [::application::diagnose::loopHealth]
	# let two beats through, stall the loop for 600 ms, let the next beat see it
	after 250 { set ::scidb::test::diag::go 1 }; vwait ::scidb::test::diag::go
	set end [expr {[clock milliseconds] + 600}]
	while {[clock milliseconds] < $end} {}
	after 250 { set ::scidb::test::diag::go 2 }; vwait ::scidb::test::diag::go
	set text [::scidb::test::diag::tool loop_health]
	list [string match "heartbeat every 100 ms*" $before] \
		[expr {$::application::diagnose::Priv(worst) >= 450}] [string match "*recent stalls*" $text]
} -cleanup {
	catch { after cancel $::application::diagnose::Priv(after) }
	set ::application::diagnose::Priv(after) {}
	::scidb::test::diag::cleanup
} -result {1 1 1}

::tcltest::cleanupTests
return
