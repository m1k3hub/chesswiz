# ======================================================================
# AI: per-backend threshold calibration (System One)
# ======================================================================
# The gates that ship (::ai::decide) have defaults calibrated on plumb-4b,
# but `auto` discovery often resolves to a different backend, and the
# research is emphatic that a threshold fitted elsewhere does not transfer
# (SYSTEM_ONE_RESEARCH.md §5.6). This module measures a backend on a
# labelled battery and writes the per-(feature, backend) threshold that
# ::ai::systemone::threshold then reads.
#
# It is offline and read-only: it asks the classifier the *production*
# question (::ai::comment::Question, ::ai::language::Question, ...), compares
# the answer to a gold label, and reports coverage/accuracy per threshold.
# Nothing it does reaches the board or writes a comment; it writes one line
# to a thresholds file at the caller's request.
#
#   ::ai::calibrate::measure <feature> <cases> <script> ?-concurrency N? ?-cache FILE?
#       <cases> is a list of {state gold}; runs the battery through
#       ::ai::batch (dedupe, resume, cap) and calls <script> with
#       {ok 1 feature F scored {{gold choice confidence} ...} total N errors M}
#   ::ai::calibrate::sweep <scored> ?-step 0.05?
#       -> {{threshold coverage accuracy} ...}
#   ::ai::calibrate::recommend <sweep> <target>
#       -> the {threshold coverage accuracy} with the most coverage whose
#          accuracy meets <target> (else the row with the best accuracy)
#   ::ai::calibrate::run <features> <battery> <script> ?-target T? ...
#       measure + sweep + recommend for each feature; <script> gets
#       {ok 1 report {feature {threshold coverage accuracy ...}}}
#   ::ai::calibrate::write <file> <feature> <backend> <threshold>
#       merge one line into the thresholds file
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-calibrate
}

package require Tcl 8.5

namespace eval ai {
namespace eval calibrate {

variable Runs
array set Runs {seq 0}

} ;# namespace calibrate
} ;# namespace ai


# The production question for a feature, so calibration cannot drift.
proc ::ai::calibrate::QuestionFor {feature} {
	switch -- $feature {
		comment_kind { return [::ai::comment::Question] }
		language     { return [::ai::language::Question] }
		triage       { return [::application::triage::Question] }
		default      { error "no calibration question for feature '$feature'" }
	}
}


# One scored row {gold choice confidence} for sweep. Most features measure
# the top label. Triage acts on bug / not bug, so it measures P(not a bug)
# against the gold label's group: the threshold it picks is the one the
# triage gate compares.
proc ::ai::calibrate::Score {feature gold answer} {
	switch -- $feature {
		triage {
			set group [expr {$gold eq "bug" ? "bug" : "notbug"}]
			return [list $group notbug [::application::triage::notBugProbability $answer]]
		}
		default {
			return [list $gold [dict get $answer choice] [dict get $answer confidence]]
		}
	}
}


proc ::ai::calibrate::measure {feature cases script args} {
	array set opts {-concurrency 2 -cache ""}
	array set opts $args

	set question [QuestionFor $feature]

	set items {}
	set golds {}
	set index 0
	foreach case $cases {
		lassign $case state gold
		lappend items [list $index $state]
		dict set golds $index $gold
		incr index
	}

	variable Runs
	set id [incr Runs(seq)]
	set Runs($id) [dict create feature $feature golds $golds \
		total [llength $cases] script $script]

	::ai::batch::run $items $question [namespace code [list OnMeasured $id]] \
		-concurrency $opts(-concurrency) -cache $opts(-cache)
	return
}


proc ::ai::calibrate::OnMeasured {id result} {
	variable Runs
	set run $Runs($id)
	unset Runs($id)

	set golds [dict get $run golds]
	set scored {}
	set errors 0
	foreach {key r} [dict get $result results] {
		if {[dict get $r ok]} {
			set answer [dict get $r answer]
			if {[catch { Score [dict get $run feature] [dict get $golds $key] $answer } row]} {
				incr errors
			} else {
				lappend scored $row
			}
		} else {
			incr errors
		}
	}

	after 0 [list {*}[dict get $run script] [list ok 1 \
		feature [dict get $run feature] scored $scored \
		total [dict get $run total] errors $errors]]
	return
}


# {{threshold coverage accuracy} ...}: at each confidence threshold, how
# much of the battery is answered and how often the answer is right.
proc ::ai::calibrate::sweep {scored args} {
	array set opts {-step 0.05}
	array set opts $args

	set n [llength $scored]
	set out {}
	for {set t 0.0} {$t <= 0.95 + 1e-9} {set t [expr {$t + $opts(-step)}]} {
		set answered 0
		set correct 0
		foreach row $scored {
			lassign $row gold choice confidence
			if {$confidence + 1e-9 >= $t} {
				incr answered
				if {$choice eq $gold} { incr correct }
			}
		}
		set coverage [expr {$n ? double($answered)/$n : 0.0}]
		set accuracy [expr {$answered ? double($correct)/$answered : 0.0}]
		lappend out [list $t $coverage $accuracy]
	}
	return $out
}


# The most coverage whose accuracy meets the target; if none does, the row
# with the best accuracy (so the caller can see how short it fell).
proc ::ai::calibrate::recommend {sweep target} {
	set best {}
	foreach row $sweep {
		if {[lindex $row 2] + 1e-9 >= $target} {
			if {$best eq "" || [lindex $row 1] > [lindex $best 1]} { set best $row }
		}
	}
	if {$best ne ""} { return $best }
	foreach row $sweep {
		if {$best eq "" || [lindex $row 2] > [lindex $best 2]} { set best $row }
	}
	return $best
}


# Measure, sweep and recommend every feature in <battery>, one batch per
# feature. <script> gets {ok 1 report {feature {threshold coverage accuracy}}}
# or {ok 0 error TEXT} on the first failure.
proc ::ai::calibrate::run {features battery script args} {
	array set opts {-target 0.9 -concurrency 2 -cache ""}
	array set opts $args

	variable Priv
	set Priv(script) $script
	set Priv(target) $opts(-target)
	set Priv(concurrency) $opts(-concurrency)
	set Priv(cache) $opts(-cache)
	set Priv(report) {}
	set Priv(pending) [llength $features]

	if {![llength $features]} {
		after 0 [list {*}$script [list ok 1 report {}]]
		return
	}

	foreach feature $features {
		if {![dict exists $battery $feature]} {
			after 0 [list {*}$script [list ok 0 error "no battery for '$feature'"]]
			return
		}
		measure $feature [dict get $battery $feature] \
			[namespace code [list OnRunFeature $feature]] \
			-concurrency $opts(-concurrency) -cache $opts(-cache)
	}
	return
}


# The accuracy a feature's threshold must reach. Triage settles a group
# for good, so a bug settled as harmless is never seen again: its "accuracy"
# is the share of settled groups that are not bugs, and with three in four
# groups harmless a 0.9 target still hides a quarter of the bugs. Its
# threshold must settle no labelled bug at all.
proc ::ai::calibrate::targetFor {feature target} {
	if {$feature eq "triage"} { return 1.0 }
	return $target
}


proc ::ai::calibrate::OnRunFeature {feature result} {
	variable Priv
	if {![dict get $result ok]} {
		set script $Priv(script)
		after 0 [list {*}$script [list ok 0 error "measure failed for '$feature'"]]
		return
	}
	set target [targetFor $feature $Priv(target)]
	set recommendation [recommend [sweep [dict get $result scored]] $target]
	dict set Priv(report) $feature [dict create \
		target    $target \
		threshold [lindex $recommendation 0] \
		coverage  [lindex $recommendation 1] \
		accuracy  [lindex $recommendation 2] \
		total     [dict get $result total] \
		errors    [dict get $result errors]]
	incr Priv(pending) -1
	if {$Priv(pending) <= 0} {
		set script $Priv(script)
		after 0 [list {*}$script [list ok 1 report $Priv(report)]]
	}
	return
}


# Merge one (feature, backend) -> threshold into a TSV file. One line per
# pair; an existing line is replaced.
proc ::ai::calibrate::write {file feature backend threshold} {
	set lines {}
	if {[file exists $file]} {
		set chan [open $file r]
		set text [read $chan]
		close $chan
		foreach line [split $text "\n"] {
			if {[string trim $line] eq ""} { continue }
			lassign [split $line "\t"] f b
			if {$f eq $feature && $b eq $backend} { continue }
			lappend lines $line
		}
	}
	lappend lines "$feature\t$backend\t$threshold"
	set chan [open $file w]
	fconfigure $chan -translation lf
	puts $chan [join $lines "\n"]
	close $chan
	return
}

# Remove one (feature, backend) from a thresholds file, so a feature that
# fails a later calibration reverts to the caller's default instead of a
# stale value from an earlier run.
proc ::ai::calibrate::drop {file feature backend} {
	if {![file exists $file]} { return }
	set chan [open $file r]
	set text [::read $chan]
	close $chan
	set lines {}
	foreach line [split $text "\n"] {
		if {[string trim $line] eq ""} { continue }
		lassign [split $line "\t"] f b
		if {$f eq $feature && $b eq $backend} { continue }
		lappend lines $line
	}
	set chan [open $file w]
	fconfigure $chan -translation lf
	puts $chan [join $lines "\n"]
	close $chan
	return
}

# vi:set ts=3 sw=3:
