# ======================================================================
# ::ai::rhetoric -- advisory second opinion on generated chess prose.
#
# After the deterministic claim checker (::ai::claims::check, regex + C++,
# the ground truth for chess facts) has passed, this module asks the
# user-configured System One classifier two bounded questions about the
# *language* of the report — questions the claim checker cannot see:
#
#   B. rhetoric  — does the prose over-claim or hype beyond its evidence?
#   F. coverage  — does the prose actually address what was asked?
#
# Both are advisory: they can only add a fixed cautionary notice to the
# report. They never change `grounded`, never suppress the report, never
# trigger an unbounded regeneration loop, and never touch the engine or the
# fact layer. On any abstention (no classifier, error, low confidence) the
# report is shown exactly as today.
#
#   ::ai::rhetoric::check $task $text $script
#     <task>  the original instruction (the -context passed to generate):
#             "Explain the move Nf3 ...", "Explain this game ...", ...
#     <text>  the generated, claim-checked prose
#     <script> called with a dict {ok 1 notices {N ...}} or {ok 0}
#
# The notices are short, fixed, application-owned strings (never the
# classifier's own words), so the model cannot inject arbitrary text.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-rhetoric
}

package require Tcl 8.5

namespace eval ai {
namespace eval rhetoric {

# The cautionary notices, shown as a small fixed badge under the report.
# These strings are ours, not the classifier's: the model only picks a label.
namespace eval mc {
	set StrongCertainty	"Strong certainty language detected."
	set NonAnswer		"This response may not address the selected request."
}

# Confidence thresholds. Deliberately conservative: a notice appears only
# when the classifier is confident, so an uncertain model never clutters the
# report. A wrong "may not address the request" badge on a good answer
# erodes trust faster than a missed badge costs, so precision beats recall
# here. The values are calibrated against plumb-4b (the strongest open
# System One backend); other backends answer with different confidence
# distributions, so both are overridable through the environment, matching
# the triage pattern (SCIDB_AI_CLASSIFIER_MIN_CONFIDENCE).
variable RhetoricThreshold 0.6
variable CoverageThreshold  0.7

if {[info exists ::env(SCIDB_AI_RHETORIC_MIN_CONFIDENCE)]} {
	set RhetoricThreshold $::env(SCIDB_AI_RHETORIC_MIN_CONFIDENCE)
}
if {[info exists ::env(SCIDB_AI_COVERAGE_MIN_CONFIDENCE)]} {
	set CoverageThreshold $::env(SCIDB_AI_COVERAGE_MIN_CONFIDENCE)
}

# The fixed option sets the classifier must answer from. Bounded by design:
# the model cannot invent a label outside these enums.
variable RhetoricCriteria {
	ordinary           "measured, fact-backed language"
	emphatic_certainty "strong certainty or confidence beyond the evidence shown"
	promotional_hype    "promotional or exaggerated language"
	unclear             "cannot be classified"
}

variable CoverageCriteria {
	addresses_request     "directly answers the request"
	generic_nonanswer     "fluent but generic; does not answer the specific request"
	refusal_or_deferral    "defers or refuses to answer"
	unrelated             "about a different topic"
	unclear               "cannot be classified"
}

} ;# namespace rhetoric
} ;# namespace ai


# The two questions, in the /v1/systemone shape ::ai::systemone expects.
proc ::ai::rhetoric::questions {} {
	variable RhetoricCriteria
	variable CoverageCriteria

	return [dict create \
		rhetoric [dict create type choice \
			instructions "How would you describe the certainty of this chess commentary?" \
			criteria $RhetoricCriteria] \
		coverage [dict create type choice \
			instructions "Does this text answer the request it was written for?" \
			criteria $CoverageCriteria] \
	]
}


# The state the classifier reads: the task instruction and the generated
# prose, clearly delimited so the model cannot confuse them. Kept short:
# a System One model reads one forward pass, not a long context window.
proc ::ai::rhetoric::state {task text} {
	return "REQUEST:\n$task\n\nCOMMENTARY:\n[string range $text 0 4000]"
}


# Map a classifier label to a notice string, or "" if no notice is warranted.
proc ::ai::rhetoric::rhetoricNotice {answer} {
	variable RhetoricThreshold
	variable RhetoricCriteria
	variable mc

	if {![validAnswer $answer $RhetoricCriteria]} { return "" }
	if {[dict get $answer confidence] < $RhetoricThreshold} { return "" }

	set label [dict get $answer choice]
	if {$label eq "emphatic_certainty" || $label eq "promotional_hype"} {
		return $mc::StrongCertainty
	}
	return ""
}


# A usable answer: a choice from the offered criteria and a confidence that
# is a number in [0,1]. Anything else is abstention, never a guess.
proc ::ai::rhetoric::validAnswer {answer criteria} {
	return [::ai::systemone::valid [dict create type choice criteria $criteria] $answer]
}


proc ::ai::rhetoric::coverageNotice {answer} {
	variable CoverageThreshold
	variable CoverageCriteria
	variable mc

	if {![validAnswer $answer $CoverageCriteria]} { return "" }
	if {[dict get $answer confidence] < $CoverageThreshold} { return "" }

	set label [dict get $answer choice]
	if {$label eq "generic_nonanswer" || $label eq "refusal_or_deferral"
	 || $label eq "unrelated"} {
		return $mc::NonAnswer
	}
	return ""
}


# ----------------------------------------------------------------------
# ::ai::rhetoric::check $task $text $script
#
# Async: the classifier is queried once with both questions; <script> is
# called with {ok 1 notices {N ...}} (the fixed notices) or {ok 0} (no
# classifier, error, or malformed reply). On ok 0 the caller shows the
# report unchanged.
# ----------------------------------------------------------------------
proc ::ai::rhetoric::check {task text script} {
	if {![llength [info commands ::ai::systemone::enabled]] || ![::ai::systemone::enabled]} {
		after 0 [list {*}$script [list ok 0]]
		return
	}

	if {[catch {
		::ai::systemone::evaluateAsync [state $task $text] [questions] \
			[namespace code [list ::ai::rhetoric::onReply $script]]
	} err]} {
		after 0 [list {*}$script [list ok 0]]
	}
	return
}


proc ::ai::rhetoric::onReply {script result} {
	if {![dict get $result ok]} {
		uplevel #0 [list {*}$script [list ok 0]]
		return
	}

	# Validate the response shape: a malformed or short reply means
	# abstention, never a wrong notice. Each answer must carry a choice
	# from the offered criteria and a confidence in [0,1].
	set notices {}
	if {[dict exists $result answers]} {
		set answers [dict get $result answers]
		if {![catch {dict get $answers rhetoric} r]} {
			set n [rhetoricNotice $r]
			if {[string length $n]} { lappend notices $n }
		}
		if {![catch {dict get $answers coverage} c]} {
			set n [coverageNotice $c]
			if {[string length $n]} { lappend notices $n }
		}
	}
	uplevel #0 [list {*}$script [list ok 1 notices $notices]]
	return
}

# vi:set ts=3 sw=3:
