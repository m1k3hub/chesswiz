# ======================================================================
# Runs the Ask Scidb request corpus (tests/assistant_corpus.tcl) against
# the configured model and scores it: a request is solved when the model
# calls a fitting tool. It asks a real model, so it is not part of the app
# suite; run it after changing prompts, tools or the model:
#
#   SCIDB_CORPUS_DB=<a .sci database> HOME=$(mktemp -d) \
#     xvfb-run -a src/tkscidb-beta tests/run_assistant_corpus.tcl ?-match GLOB?
#
# The model is ::application::ai::Config's (the app's default unless
# SCIDB_AI_PROVIDER / SCIDB_AI_MODEL say otherwise). Every confirmation is
# declined, so nothing is written. Each request starts a new conversation;
# the board shows game 11 at move 12 of the database, for the requests
# about the board. A report goes to tests/tmp-app/corpus-report.txt.
# ======================================================================

set argvCopy $argv
set argv {--single-process}
set argc 1
set root [file normalize [file join [file dirname [info script]] ..]]
set ::env(SCIDB_ERROR_LOG) [file join $root tests tmp-app corpus-errors.log]
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_AI_CLASSIFIER) off
source [file join $root tcl scidb-beta]
fconfigure stdout -buffering line

set match *
foreach {key value} $argvCopy { if {$key eq "-match"} { set match $value } }
source [file join $root tests assistant_corpus.tcl]

proc nop {args} { return 0 }
set db [expr {[info exists ::env(SCIDB_CORPUS_DB)] ? $::env(SCIDB_CORPUS_DB) : ""}]
if {$db eq "" || ![file exists $db]} { puts "set SCIDB_CORPUS_DB to a .sci database"; exit 2 }
::scidb::db::load $db nop {} -readonly yes
rename ::application::assistant::ActiveBase realActiveBase
proc ::application::assistant::ActiveBase {} { list $::db Normal }
::game::new .application -base $db -variant Normal -number 10
set plies [::scidb::game::query mainline]
catch { ::scidb::game::go key [lindex $plies 23 0] }
set ::application::ai::Settings(me) {Thomas, Michael}
# SCIDB_CORPUS_THINK=1 lets a thinking model (Ollama) think before answering
if {[info exists ::env(SCIDB_CORPUS_THINK)]} {
	rename ::application::assistant::ConfigureProvider ::application::assistant::RealConfigureProvider
	proc ::application::assistant::ConfigureProvider {} {
		::application::assistant::RealConfigureProvider
		::ai::provider::configure -think $::env(SCIDB_CORPUS_THINK)
	}
}

# A request's tool calls: {name args ...} in order.
proc calls {} {
	set out {}
	foreach m $::application::assistant::Priv(messages) {
		if {[dict get $m role] ne "assistant" || ![dict exists $m tool_calls]} continue
		foreach c [dict get $m tool_calls] {
			set fn [dict get $c function]
			lappend out [dict get $fn name] [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
		}
	}
	return $out
}

# Tools that only look: a request answered by asking back may use them first.
set ReadOnly {app_state list_open_databases discover_databases current_game tool_log list_engines
	engine_options cql_help recent_errors ui_state database_summary}

proc solved {calls expect} {
	if {{none} in $expect && ![llength [lmap {n a} $calls { if {$n in $::ReadOnly} continue; set n }]]} {
		return 1
	}
	foreach want $expect {
		set args [lassign $want tool]
		foreach {name cargs} $calls {
			if {$name ne $tool} continue
			set ok 1
			foreach {key glob} $args {
				if {![dict exists $cargs $key] || ![string match -nocase $glob [dict get $cargs $key]]} { set ok 0; break }
			}
			if {$ok} { return 1 }
		}
	}
	return 0
}

set report [open [file join $root tests tmp-app corpus-report.txt] w]
set total 0; set good 0
array set byJob {}
foreach {id job request expect} $Corpus {
	if {![llength [lmap m [split $match ,] { if {[string match $m $id]} { set m } else continue }]]} continue
	::application::assistant::clear
	# every request starts from the same user (me-remember changes it)
	set ::application::ai::Settings(me) {Thomas, Michael}
	set started [clock milliseconds]
	::application::assistant::ask $request -confirm {apply {args {return 0}}}
	set timer [after 180000 {set ::application::assistant::Priv(busy) 0}]
	while {$::application::assistant::Priv(busy)} { vwait ::application::assistant::Priv(busy) }
	after cancel $timer
	set seconds [expr {([clock milliseconds] - $started) / 1000.0}]
	set calls [calls]
	set ok [solved $calls $expect]
	incr total; incr good $ok
	lappend byJob($job) $ok
	set line [format "%-4s %-22s %5.1fs  %s" [expr {$ok ? "ok" : "MISS"}] $id $seconds \
		[join [lmap {n a} $calls { set n }] ,]]
	puts $line
	puts $report $line
	if {!$ok} {
		set said ""
		foreach m $::application::assistant::Priv(messages) {
			if {[dict get $m role] eq "assistant" && [dict exists $m content] && [dict get $m content] ne ""} {
				set said [dict get $m content]
			}
		}
		puts $report "     request: $request\n     calls:   $calls\n     expect:  $expect\n     said:    [string range [string map {\n { }} $said] 0 300]"
	}
}
puts $report ""
foreach job [lsort [array names byJob]] {
	set n [llength $byJob($job)]
	set k [tcl::mathop::+ {*}$byJob($job)]
	puts $report [format "%-4s %d/%d" $job $k $n]
}
set line [format "SOLVED %d/%d (%.0f%%) with %s" $good $total [expr {$total ? 100.0 * $good / $total : 0}] \
	"$::application::ai::Config(provider) [::ai::provider::model]"]
puts $report $line
puts $line
close $report
exit [expr {$good == $total ? 0 : 1}]
