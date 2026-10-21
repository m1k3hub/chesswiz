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
# Convert a documented JSON parameters schema into the registry's Tcl
# args spec. The registry then owns validation and can regenerate the
# same JSON schema (see ::action::schemaJson).
#
# enum-style / legacy-default only affect validation text and defaults:
# schemaJson ignores them, so the documented schema stays byte-identical.
# ----------------------------------------------------------------------
set ::application::assistant::ArgEnumStyles {
	pane {action bare}
	open_search {kind quoted}
	download_games {source quoted site quoted}
	correspondence_games {action bare}
	maintenance_report {tab bare}
	prepare_against {color quoted}
	repertoire_check {color quoted}
	search_games {color bare result bare pattern oneof}
	find_positions {mode bare color bare result bare}
	find_similar {colours bare mode bare color bare result bare}
	open_view {kind oneof}
	goto_move {after bare}
	explain_side {side bare}
	explain_game_result {side bare}
	opponent_brief {colour quoted}
	study_plan {colour quoted}
	position_types {colour quoted}
	training_set {pattern oneof}
	run_job {job bare colour bare pattern oneof}
}
# No tool defaults a schema-required argument: correspondence_games.action
# and maintenance_report.tab used to be required and silently defaulted.
set ::application::assistant::LegacyArgDefaults {}

proc ::application::assistant::ParametersToArgsSpec {schema {action ""}} {
	variable ArgEnumStyles
	variable LegacyArgDefaults

	set spec {}
	set props [expr {[dict exists $schema properties] ? [dict get $schema properties] : {}}]
	set required [expr {[dict exists $schema required] ? [dict get $schema required] : {}}]
	set styles [expr {[dict exists $ArgEnumStyles $action] ? [dict get $ArgEnumStyles $action] : {}}]
	set legacy [expr {[dict exists $LegacyArgDefaults $action] ? [dict get $LegacyArgDefaults $action] : {}}]
	foreach name [dict keys $props] {
		set prop [dict get $props $name]
		set opts [dict create]
		set type [expr {[dict exists $prop type] ? [dict get $prop type] : "string"}]
		dict set opts type $type
		if {[dict exists $prop enum]} {
			dict set opts enum [dict get $prop enum]
			dict set opts enum-style [expr {[dict exists $styles $name] ? [dict get $styles $name] : "quoted"}]
		}
		if {[dict exists $prop description]} { dict set opts description [dict get $prop description] }
		if {$type eq "array"} {
			set items [expr {[dict exists $prop items] ? [dict get $prop items] : [dict create type string]}]
			dict set opts items [expr {[dict exists $items type] ? [dict get $items type] : "string"}]
			if {[dict exists $items enum]} { dict set opts item-enum [dict get $items enum] }
		}
		dict set opts required [expr {[lsearch -exact $required $name] >= 0 ? 1 : 0}]
		if {[dict exists $legacy $name]} { dict set opts legacy-default [dict get $legacy $name] }
		lappend spec [::list $name $opts]
	}
	return $spec
}

# ----------------------------------------------------------------------
# Register all assistant tools as actions. ONE generator loop over the
# Actions table (86 tools) plus run_job (added above = 87 total).
# The args spec is the single validation source; the model schema is
# generated from it and is byte-identical to the documented baseline.
# ai is the exposure flag: 1 = offered in normal mode, debug = only in
# debug mode. Confirm is a separate, independent gate flag.
# ----------------------------------------------------------------------
namespace eval application {
namespace eval assistant {

variable Actions

# Bulk actions: change more than one game or a whole database/file in one call.
variable BulkActions {
	download_games
	update_player_data
	import_games
	compact_database
	convert_database
	save_working_set
}
if {[catch { package require json }]} {
	# Without tcllib json the assistant cannot talk to a provider anyway;
	# keep the documented schema so the registry stays usable.
	proc ::application::assistant::_specFor {parameters {action ""}} { return {} }
	proc ::application::assistant::_schemaFor {parameters spec} { return $parameters }
} else {
	proc ::application::assistant::_specFor {parameters {action ""}} {
		return [ParametersToArgsSpec [::json::json2dict $parameters] $action]
	}
	proc ::application::assistant::_schemaFor {parameters spec} {
		return [::action::schemaJson $spec]
	}
}
dict for {name entry} $Actions {
	lassign $entry confirm debug what description parameters handler
	set aiFlag [expr {$debug ? "debug" : 1}]
	set isBulk [expr {$name in $BulkActions ? 1 : 0}]
	set label [string map {" " "_"} $name]
	if {$name eq "install_chessbase_fonts"} { set label "install_figurine_fonts" }
	if {$name eq "cql_help"} { set label "pattern_search_help" }
	set spec [::application::assistant::_specFor $parameters $name]
	set schemaStr [::application::assistant::_schemaFor $parameters $spec]
	if {$spec eq "{}"} { set spec {} }
	::action::register $name [dict create \
		label    $label \
		args     $spec \
		schema   $schemaStr \
		handler  [list ::application::assistant::_actionAdapter $name $handler] \
		confirm  $confirm \
		bulk     $isBulk \
		ai       $aiFlag \
		what     $what \
		object   {} \
		doc      $description \
		toolmenu $what \
		ends-in-dialog [expr {$name eq "open_play_engine"}] \
	]
}

# Wire registry hooks for confirm/bulk/debug gates.
# Assistant path uses ConfirmDialog; menu path uses ::dialog::question directly.
set ::action::ConfirmHook ::application::assistant::ConfirmDialog
set ::action::BulkHook ::application::assistant::ConfirmDialog
set ::action::DebugGate [list expr {$::application::assistant::Priv(debug)}]

# Register production object resolvers.
# Resolvers return typed references without widget paths.
::action::resolver::register game {::scidb::game::current}
::action::resolver::register database {::scidb::db::get name}
::action::resolver::register move {return [::scidb::game::query current]}

} ;# namespace assistant
} ;# namespace application
