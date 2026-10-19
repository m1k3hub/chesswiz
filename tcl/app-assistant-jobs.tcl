# ======================================================================
# ::application::assistant -- named jobs (run_job; docs/ai/ASSISTANT_COVERAGE_MAP.md
# P4, phase 5).
#
# A player thinks in jobs ("prepare for Saturday's opponent"), not in tools.
# A job is a fixed plan: the tools to call, in order, with their arguments
# filled in from the job's own (and the user's remembered name). run_job
# returns the plan, shows it in the pane as a checklist, and gives the
# request the rounds the plan needs; the model then calls the tools,
# through the normal loop, so asynchronous tools and confirmations work as
# always. A plan is predictable: the same job always takes the same steps.
#
#   jobs: prepare <name> ?colour?   review ?games?   repertoire ?colour?
#         train ?pattern?
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant-jobs
}

namespace eval application {
namespace eval assistant {

dict set Actions run_job {
	0 0 "run the job '%s'"
	"Run one of Chesswiz's jobs, a fixed series of steps: prepare (for a game against 'name', who plays 'colour': statistics, openings and weak lines, the brief, the prep report, their games in the list), review (the user's own last 'games' games: record, engine audit and study plan, the games in the list), repertoire (the user's repertoire against their games: gaps and the report; 'colour' optional), train (puzzles from the user's games; 'pattern' optional). Returns the plan: then call its tools in order with exactly those arguments, and finish with a short checklist of what is done. review, repertoire and train need the user's name (remember_me)."
	{{"type":"object","properties":{"job":{"type":"string","enum":["prepare","review","repertoire","train"]},"name":{"type":"string","description":"the opponent, for prepare"},"colour":{"type":"string","enum":["white","black"],"description":"prepare: the colour the opponent plays; repertoire: your colour"},"games":{"type":"integer","description":"review: how many of your latest games, default 10"},"pattern":{"type":"string","enum":["checkmate","smothered_mate","double_check","underpromotion"]}},"required":["job"]}}
	::application::assistant::DoRunJob
}

# the rounds a job's request may use (a plan of up to 6 steps plus answers)
variable JobRounds 14

} ;# namespace assistant
} ;# namespace application


proc ::application::assistant::CheckArgs_run_job {cargs} {
	set job [Arg $cargs job]
	if {$job ni {prepare review repertoire train}} { error "job must be prepare, review, repertoire or train" }
	set name [expr {[dict exists $cargs name] ? [string trim [dict get $cargs name]] : ""}]
	set colour [expr {[dict exists $cargs colour] ? [string tolower [dict get $cargs colour]] : ""}]
	if {$colour ni {"" white black}} { error "colour must be white or black" }
	set games [expr {[dict exists $cargs games] ? [dict get $cargs games] : 10}]
	if {![string is integer -strict $games] || $games < 1 || $games > 50} { error "games must be 1 to 50" }
	set pattern [expr {[dict exists $cargs pattern] ? [dict get $cargs pattern] : ""}]
	if {$job eq "prepare" && $name eq ""} { error "prepare needs the opponent's name" }
	return [dict create job $job name $name colour $colour games $games pattern $pattern]
}


# The plan of a job: {label tool args} steps.
proc ::application::assistant::JobPlan {job name colour games pattern me} {
	switch -- $job {
		prepare {
			set side [expr {$colour eq "" ? "any" : $colour}]
			set plan [list \
				"their record" player_stats [dict create name $name] \
				"their openings and weakest lines" prepare_against [dict create name $name {*}[expr {$colour ne "" ? [list color $colour] : {}}]] \
				"the brief, in the Report pane" opponent_brief [dict create name $name {*}[expr {$colour ne "" ? [list colour $colour] : {}}]] \
				"the prep report and dossier" open_view [dict create kind prep_report name $name] \
				"their games" search_games [dict create player $name color $side] \
				"their games in the game list" show_search {}]
		}
		review {
			set plan [list \
				"your record" player_stats [dict create name $me] \
				"engine audit and study plan, in the Report pane" study_plan [dict create player $me games $games] \
				"your games" search_games [dict create player $me] \
				"your games in the game list" show_search {}]
		}
		repertoire {
			set plan [list \
				"your repertoire against your games" repertoire_check [dict create player $me {*}[expr {$colour ne "" ? [list color $colour] : {}}]] \
				"the repertoire report" open_view [dict create kind repertoire_report]]
		}
		train {
			set plan [list \
				"puzzles from your games" training_set [dict create player $me {*}[expr {$pattern ne "" ? [list pattern $pattern] : {}}]]]
		}
	}
	return $plan
}


proc ::application::assistant::DoRunJob {job name colour games pattern} {
	variable Priv
	variable JobRounds

	set me ""
	catch { set me [string trim $::application::ai::Settings(me)] }
	if {$job ne "prepare" && $me eq ""} {
		return "error: this job needs the user's name: ask for it and call remember_me, then run the job again"
	}
	set plan [JobPlan $job $name $colour $games $pattern $me]

	set lines {}
	set i 0
	foreach {label tool args} $plan {
		lappend lines "[incr i]. $label: $tool [::ai::provider::jsonObject $args]"
	}
	Append info "Plan:\n[join [lmap l $lines { set _ "  $l" }] \n]"
	# the plan's steps, then the answer
	set Priv(maxRounds) [expr {max($Priv(maxRounds), $JobRounds)}]
	return "plan of the job '$job'; call these tools in order with exactly these arguments, then end with a short checklist of what was done:\n[join $lines \n]"
}


# ----------------------------------------------------------------------
# Adapter for assistant tools registered in the action registry.
# Bridges from the registry's dict-based calling convention to the
# existing positional-arg Do* handlers via CheckArgs.
# ----------------------------------------------------------------------
proc ::application::assistant::_actionAdapter {name handler argsDict} {
	if {[catch { set checked [CheckArgs $name $argsDict] } err]} {
		return "error: $err"
	}
	if {[catch { set reply [{*}$handler {*}[dict values $checked]] } err opts]} {
		RecordError assistant "$name: $err" [dict get $opts -errorinfo]
		return "error: $err"
	}
	return $reply
}


# ----------------------------------------------------------------------
# Register all assistant tools as actions. ONE generator loop over the
# Actions table (86 tools) plus run_job (added above = 87 total).
# Uses passthrough schema (no re-generation) and the adapter handler.
# ----------------------------------------------------------------------
namespace eval application {
namespace eval assistant {

variable Actions
dict for {name entry} $Actions {
	lassign $entry confirm debug what description parameters handler
	set aiFlag [expr {$debug ? "debug" : ($confirm ? 1 : 0)}]
	set label [string map {" " "_"} $name]
	::action::register $name [dict create \
		label    $label \
		schema   $parameters \
		handler  [list ::application::assistant::_actionAdapter $name $handler] \
		confirm  $confirm \
		ai       $aiFlag \
		what     $what \
		doc      $description \
		toolmenu $what \
	]
}

} ;# namespace assistant
} ;# namespace application
