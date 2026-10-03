# ======================================================================
# Scidb App Test — named jobs (tcl/app-assistant-jobs.tcl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

tcltest::test jobs-offered {run_job is offered to the model} -body {
	string match {*"name":"run_job"*} [::application::assistant::toolsJson]
} -result 1

tcltest::test jobs-prepare {prepare plans the opponent's record, lines, brief, report and games} -body {
	set ::application::assistant::Priv(maxRounds) 8
	set reply [::application::assistant::runTool run_job {job prepare name {Carlsen, Magnus} colour black}]
	list [regexp -all -line {^\d\. } $reply] \
		[string match {*opponent_brief {"name":"Carlsen, Magnus","colour":"black"}*} $reply] \
		[string match {*search_games {"player":"Carlsen, Magnus","color":"black"}*} $reply] \
		[string match {*6. their games in the game list: show_search {}*} $reply] \
		$::application::assistant::Priv(maxRounds)
} -result {6 1 1 1 14}

tcltest::test jobs-need-me {jobs about the user need the user's name} -body {
	set saved $::application::ai::Settings(me)
	set ::application::ai::Settings(me) ""
	set without [::application::assistant::runTool run_job {job review}]
	set ::application::ai::Settings(me) {Thomas, Michael}
	set with [::application::assistant::runTool run_job {job review games 5}]
	set ::application::ai::Settings(me) $saved
	list [string match "error: this job needs the user's name*remember_me*" $without] \
		[string match {*study_plan {"player":"Thomas, Michael","games":5}*} $with]
} -result {1 1}

tcltest::test jobs-checks {arguments are checked} -body {
	list [::application::assistant::runTool run_job {job dance}] \
		[::application::assistant::runTool run_job {job prepare}] \
		[::application::assistant::runTool run_job {job review games 99}]
} -result {{error: job must be prepare, review, repertoire or train} {error: prepare needs the opponent's name} {error: games must be 1 to 50}}

tcltest::test jobs-rounds-reset {every request starts with the normal round budget} -body {
	set ::application::assistant::Priv(maxRounds) 14
	set ::ai::provider::Config(chatResponses) {}
	::ai::provider::configure -name stub -chatResponses [list [dict create role assistant content ok]]
	set cfg [array get ::application::ai::Config provider]
	set ::application::ai::Config(provider) stub
	::application::assistant::clear
	::application::assistant::ask "hello"
	if {$::application::assistant::Priv(busy)} { vwait ::application::assistant::Priv(busy) }
	array set ::application::ai::Config $cfg
	::application::assistant::clear
	set ::application::assistant::Priv(maxRounds)
} -result 8

tcltest::cleanupTests
