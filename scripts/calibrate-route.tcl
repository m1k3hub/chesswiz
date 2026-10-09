# ======================================================================
# Calibrate the System One pre-router against a live backend.
#
#   xvfb-run -a src/tkchesswiz scripts/calibrate-route.tcl \
#       --backend typesafe ?--out tcl/ai-thresholds.tsv? ?--timeout MS?
#
# Asks the backend the router's question for every request of the Ask
# Scidb corpus (tests/assistant_corpus.tcl). A request should be routed
# when one of its expected calls is an invocation the router offers (a
# bare tool, or one enum value of a single required enum); every other
# request belongs to the language model. For each pair of thresholds
# (confidence, satisfied) the router acts when both are met; a pair is
# safe when no action is wrong (a request for the model, or the wrong
# tool). Of the safe pairs the one with the most correct actions wins,
# the highest thresholds among equals, and with --out it is written as
# features route and route_satisfied for the backend.
# ======================================================================

set root [file dirname [file dirname [file normalize [info script]]]]
set argvCopy $argv
set argv {--single-process}; set argc 1
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_ERROR_LOG) [file join $root tests tmp-app route-cal-errors.log]
source [file join $root tcl chesswiz]
source [file join $root tests assistant_corpus.tcl]
fconfigure stdout -buffering line

array set opt {-backend typesafe -out "" -timeout 60000}
foreach {flag value} $argvCopy {
	switch -- $flag {
		--backend { set opt(-backend) $value }
		--out     { set opt(-out) $value }
		--timeout { set opt(-timeout) $value }
		default   { puts stderr "unknown option $flag"; exit 2 }
	}
}
::ai::systemone::configure -backend $opt(-backend) -timeout $opt(-timeout)
if {![::ai::systemone::enabled]} { puts stderr "backend $opt(-backend) is not reachable"; exit 1 }

set invocations [::application::assistant::routeInvocations]
set criteria [::application::assistant::routeCriteria $invocations]
set questions [::application::assistant::routeQuestions $criteria]

# Whether invocation <inv> performs one of the expected calls.
proc solves {inv expect} {
	foreach want $expect {
		set args [lassign $want tool]
		if {$tool ne [dict get $inv name]} continue
		set ok 1
		foreach {key glob} $args {
			set cargs [dict get $inv cargs]
			if {![dict exists $cargs $key] || ![string match -nocase $glob [dict get $cargs $key]]} { set ok 0; break }
		}
		if {$ok} { return 1 }
	}
	return 0
}

set rows {}
foreach {id job request expect} $Corpus {
	set routable [expr {[llength [lmap inv $invocations { if {![solves $inv $expect]} continue; set inv }]] > 0}]
	if {[catch { ::ai::systemone::evaluate [::application::assistant::routeState $request] $questions } answers]} {
		puts "$id: error $answers"
		continue
	}
	set d [::application::assistant::RouteDecision [dict create ok 1 answers $answers] $criteria]
	if {![dict get $d ok]} { puts "$id: malformed answer"; continue }
	set inv [lsearch -inline -index 1 $invocations [dict get $d id]]
	set right [expr {[llength $inv] && [solves $inv $expect]}]
	lappend rows [list $id $routable [dict get $d id] $right [dict get $d conf] [dict get $d sat]]
	puts [format "%-22s %-8s -> %-34s %-5s conf %.2f sat %.2f" $id \
		[expr {$routable ? "route" : "model"}] [dict get $d id] [expr {$right ? "right" : "-"}] \
		[dict get $d conf] [dict get $d sat]]
}

set best {}
for {set c 50} {$c <= 99} {incr c} {
	for {set s 0} {$s <= 99} {incr s} {
		set tc [expr {$c / 100.0}]; set ts [expr {$s / 100.0}]
		set good 0; set bad 0
		foreach r $rows {
			lassign $r id routable pred right conf sat
			if {$pred eq $::application::assistant::RouteSentinel || $conf < $tc || $sat < $ts} continue
			if {$right} { incr good } else { incr bad }
		}
		if {$bad} continue
		# most correct actions; among equals the highest (safest) thresholds
		if {$best eq "" || $good > [lindex $best 2]
		 || ($good == [lindex $best 2] && $tc + $ts >= [lindex $best 0] + [lindex $best 1])} {
			set best [list $tc $ts $good]
		}
	}
}

set routable [llength [lsearch -all -index 1 $rows 1]]
puts ""
puts "requests: [llength $rows], routable: $routable"
if {$best eq ""} {
	puts "no safe thresholds: every pair acts wrongly at least once"
	exit 1
}
lassign $best tc ts good
puts [format "thresholds: confidence %.2f satisfied %.2f -> %d of %d routable requests run directly, no wrong action" $tc $ts $good $routable]
if {$opt(-out) ne ""} {
	::ai::calibrate::write $opt(-out) route $opt(-backend) $tc
	::ai::calibrate::write $opt(-out) route_satisfied $opt(-backend) $ts
	puts "wrote $opt(-out): route, route_satisfied for $opt(-backend)"
}
exit 0
