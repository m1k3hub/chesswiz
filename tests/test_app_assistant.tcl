# ======================================================================
# Scidb App Test — AI assistant pane (tcl/app-assistant.tcl)
# ======================================================================
# The model is replaced by the stub provider, whose scripted replies
# drive the tool loop; confirmations are answered by a test hook.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::assistant {
	variable Answer 1
	variable Asked {}
}

proc ::scidb::test::assistant::confirm {what} {
	variable Answer
	variable Asked
	lappend Asked $what
	return $Answer
}

proc ::scidb::test::assistant::setup {answer} {
	variable Answer $answer
	variable Asked {}
	set ::application::assistant::Priv(confirm) ::scidb::test::assistant::confirm
}

proc ::scidb::test::assistant::call {name {arguments {}}} {
	return [dict create role assistant content "" tool_calls \
		[list [dict create function [dict create name $name arguments $arguments]]]]
}

# Run one request against scripted replies; returns the transcript text.
proc ::scidb::test::assistant::run {request replies} {
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses $replies
	::application::assistant::ask $request
	if {$::application::assistant::Priv(busy)} {
		vwait ::application::assistant::Priv(busy)
	}
	array set $cfg $saved
	return [$::application::assistant::Priv(text) get 1.0 end-1c]
}

tcltest::test assistant-pane-is-dockable {the assistant is an undockable pane of the board layout} -body {
	::application::assistant::show
	set twm [::application::twm board]
	list [expr {"assistant" in [$twm leaves]}] [expr {!![$twm isundockable assistant]}]
} -result {1 1}

tcltest::test assistant-unknown-tool {an unknown tool is reported to the model, not raised} -body {
	::application::assistant::runTool run_shell {command {rm -rf ~}}
} -result {error: unknown tool 'run_shell'}

tcltest::test assistant-bad-arguments {tool arguments are checked before running} -body {
	list [::application::assistant::runTool switch_tab {tab settings}] \
		[::application::assistant::runTool open_database {path /nonexistent/x.sci}] \
		[::application::assistant::runTool open_database {}]
} -result {{error: tab must be 'board' or 'database'} {error: no such file: /nonexistent/x.sci} {error: missing argument 'path'}}

tcltest::test assistant-read-only-needs-no-confirm {a read-only tool runs without asking} -body {
	::scidb::test::assistant::setup 0
	set reply [::application::assistant::runTool list_open_databases {}]
	list [expr {[string first (active) $reply] >= 0}] $::scidb::test::assistant::Asked
} -result {1 {}}

tcltest::test assistant-denied-action {a changing action does not run when the user denies it} -body {
	::scidb::test::assistant::setup 0
	set called 0
	rename ::util::photos::openDialog ::scidb::test::assistant::realOpenDialog
	proc ::util::photos::openDialog {args} { set ::called 1 }
	set ::called 0
	set reply [::application::assistant::runTool install_player_photos {}]
	rename ::util::photos::openDialog {}
	rename ::scidb::test::assistant::realOpenDialog ::util::photos::openDialog
	list $reply $::called $::scidb::test::assistant::Asked
} -result {{The user declined: the action was NOT performed and no dialog was opened.} 0 {{open the player photo installer}}}

tcltest::test assistant-allowed-action {a changing action runs once the user allows it} -body {
	::scidb::test::assistant::setup 1
	rename ::util::photos::openDialog ::scidb::test::assistant::realOpenDialog
	proc ::util::photos::openDialog {args} { set ::called 1 }
	set ::called 0
	set reply [::application::assistant::runTool install_player_photos {}]
	rename ::util::photos::openDialog {}
	rename ::scidb::test::assistant::realOpenDialog ::util::photos::openDialog
	list $::called [string match "*installer dialog is open*" $reply]
} -result {1 1}

tcltest::test assistant-tool-loop {a tool call is executed and the answer shown} -body {
	::application::assistant::clear
	set text [::scidb::test::assistant::run "which databases are open?" [list \
		[::scidb::test::assistant::call list_open_databases] \
		[dict create role assistant content "Only the Clipbase is open."]]]
	list [string match "*> which databases are open?*" $text] \
		[string match "*list_open_databases: *(active)*" $text] \
		[string match "*Only the Clipbase is open.*" $text] \
		$::application::assistant::Priv(busy)
} -result {1 1 1 0}

tcltest::test assistant-keeps-history {the conversation carries into the next request} -body {
	::scidb::test::assistant::run "thanks" [list [dict create role assistant content "You're welcome."]]
	lmap m $::application::assistant::Priv(messages) { dict get $m role }
} -result {system user assistant tool assistant user assistant}

tcltest::test assistant-provider-error {a failing provider releases the pane} -body {
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) nosuchprovider
	::application::assistant::ask "hello"
	if {$::application::assistant::Priv(busy)} {
		vwait ::application::assistant::Priv(busy)
	}
	array set $cfg $saved
	list $::application::assistant::Priv(busy) \
		[string match "*Error:*" [$::application::assistant::Priv(text) get 1.0 end]]
} -result {0 1}

tcltest::test assistant-clear {clear drops the conversation} -body {
	::application::assistant::clear
	llength $::application::assistant::Priv(messages)
} -result 0

# Replace <proc> by a recorder for the duration of <body>; returns the
# recorded calls (each a list of arguments).
proc ::scidb::test::assistant::stubbed {proc body} {
	variable Calls {}
	rename $proc ${proc}__real
	proc $proc {args} { lappend ::scidb::test::assistant::Calls $args }
	set rc [catch { uplevel 1 $body } result]
	rename $proc {}
	rename ${proc}__real $proc
	if {$rc} { return -code error $result }
	return $Calls
}

tcltest::test assistant-new-game-confirms {new_game asks first and only then starts a game} -body {
	::scidb::test::assistant::setup 0
	set denied [::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}]
	::scidb::test::assistant::setup 1
	set allowed [::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}]
	list [llength $denied] [llength $allowed] [lindex $allowed 0 1]
} -result {0 1 Normal}

tcltest::test assistant-open-search {open_search opens the requested dialog on the active base} -body {
	set calls [::scidb::test::assistant::stubbed ::application::database::OpenRatingSearch {
		::application::assistant::runTool open_search {kind rating}
	}]
	list [llength $calls] [lindex $calls 0 1] [lindex $calls 0 2] \
		[::application::assistant::runTool open_search {kind players}]
} -result [list 1 [::scidb::db::get name] Normal {error: kind must be 'advanced', 'material' or 'rating'}]

tcltest::test assistant-export {export_database opens the export dialog for the active base} -body {
	set calls [::scidb::test::assistant::stubbed ::export::open {
		::application::assistant::runTool export_database {}
	}]
	set exportOpts [lrange [lindex $calls 0] 1 end]
	list [llength $calls] [expr {[dict get $exportOpts -base] eq [::scidb::db::get name]}] \
		[dict get $exportOpts -variant]
} -result {1 1 Normal}

tcltest::test assistant-app-state {app_state reports versions, database and position} -body {
	set reply [::application::assistant::runTool app_state {}]
	list [string match "*tcl 8.*" $reply] [string match "*active database: *" $reply] \
		[string match "*current position: *" $reply] [string match "*current game (slot *" $reply]
} -result {1 1 1 1}

tcltest::test assistant-recent-errors {background errors are recorded for recent_errors} -body {
	set saved $::application::assistant::Errors
	::application::assistant::RecordError [list ::scidb::bgerror "boom" {-errorinfo "boom\n    while executing x"}] enter
	set reply [::application::assistant::runTool recent_errors {count 1}]
	set ::application::assistant::Errors $saved
	list [string match "*boom*while executing x*" $reply] \
		[expr {"enter ::application::assistant::RecordError" in [trace info execution ::scidb::bgerror]}]
} -result {1 1}

tcltest::test assistant-debug-tools-gated {debug tools are hidden and refused outside debug mode} -body {
	package require json
	set ::application::assistant::Priv(debug) 0
	set names [lmap t [json::json2dict [::application::assistant::toolsJson]] { dict get $t function name }]
	list [expr {"eval_tcl" in $names}] [expr {"app_state" in $names}] \
		[::application::assistant::runTool proc_source {name ::application::openPane}]
} -result {0 1 {error: 'proc_source' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)}}

tcltest::test assistant-debug-inspection {in debug mode the model can read procs and variables} -body {
	set ::application::assistant::Priv(debug) 1
	set src [::application::assistant::runTool proc_source {name ::application::openPane}]
	set var [::application::assistant::runTool read_variable {name ::application::assistant::Priv pattern maxRounds}]
	set procs [::application::assistant::runTool list_procs {pattern ::application::report::show*}]
	set ::application::assistant::Priv(debug) 0
	list [string match "proc ::application::openPane uid *" $src] $var [llength [split $procs \n]]
} -result {1 {maxRounds = 8} 3}

tcltest::test assistant-eval-needs-confirm {eval_tcl runs only the script the user allowed} -body {
	set ::application::assistant::Priv(debug) 1
	::scidb::test::assistant::setup 0
	set ::scidb::test::assistant::x 0
	set denied [::application::assistant::runTool eval_tcl {script {set ::scidb::test::assistant::x 1}}]
	set asked $::scidb::test::assistant::Asked
	::scidb::test::assistant::setup 1
	set allowed [::application::assistant::runTool eval_tcl {script {incr ::scidb::test::assistant::x 5}}]
	set ::application::assistant::Priv(debug) 0
	list [string match "*NOT performed*" $denied] [string match "*set ::scidb::test::assistant::x 1*" $asked] \
		$allowed $::scidb::test::assistant::x
} -result {1 1 {result: 5} 5}

tcltest::test assistant-long-replies-truncated {a huge tool reply is cut} -body {
	set ::application::assistant::Priv(debug) 1
	set ::scidb::test::assistant::big [string repeat x 20000]
	set reply [::application::assistant::runTool read_variable {name ::scidb::test::assistant::big}]
	set ::application::assistant::Priv(debug) 0
	list [expr {[string length $reply] < 7000}] [string match "*(truncated)" $reply]
} -result {1 1}

# --- read-only queries over a small database ----------------------------

proc ::scidb::test::assistant::openFixture {} {
	variable Fixture
	set dir [file join [file dirname [file normalize [info script]]] tmp-app]
	file mkdir $dir
	set Fixture [file join $dir assistant_[pid].pgn]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	foreach {round white black result eco moves} {
		1 {Carlsen, Magnus} {Anand, Viswanathan} 1-0 B90 {1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6}
		2 {Anand, Viswanathan} {Carlsen, Magnus} 1/2-1/2 B92 {1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be2}
		3 {Carlsen, Henrik} {Carlsen, Magnus} 0-1 C60 {1. e4 e5 2. Nf3 Nc6 3. Bb5}
	} {
		puts $fh "\[Event \"Assistant\"\]\n\[Site \"X\"\]\n\[Date \"202$round.01.01\"\]\n\[Round \"$round\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]\n\[ECO \"$eco\"\]\n"
		puts $fh "$moves $result\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::assistant::nop {} ::scidb::test::assistant::nop {}
	# the queries read this base; switching the app to it would drag the GUI along
	rename ::application::assistant::ActiveBase ::scidb::test::assistant::realActiveBase
	proc ::application::assistant::ActiveBase {} { list $::scidb::test::assistant::Fixture Normal }
}

proc ::scidb::test::assistant::closeFixture {} {
	variable Fixture
	rename ::application::assistant::ActiveBase {}
	rename ::scidb::test::assistant::realActiveBase ::application::assistant::ActiveBase
	catch { ::scidb::db::close $Fixture }
	file delete $Fixture
}

proc ::scidb::test::assistant::nop {args} {}

::scidb::test::assistant::openFixture

tcltest::test assistant-player-stats {player_stats finds a player by part of the name} -body {
	::scidb::test::assistant::setup 0
	set reply [::application::assistant::runTool player_stats {name {carlsen, m}}]
	list [string match "Carlsen, Magnus: 3 games, 2021.01.01 to 2023.01.01*" $reply] \
		[string match "*White: 1 wins, 0 draws, 0 losses, score 100.0%*" $reply] \
		[string match "*Black: 1 wins, 1 draws, 0 losses, score 75.0%*" $reply] \
		[string match "*B92 Sicilian*1.e4 c5 2.Nf3*" $reply] \
		$::scidb::test::assistant::Asked
} -result {1 1 1 1 {}}

tcltest::test assistant-player-ambiguous {an ambiguous name lists the candidates, most games first} -body {
	list [::application::assistant::runTool player_stats {name carlsen}] \
		[::application::assistant::runTool player_stats {name kasparov}]
} -match glob -result {{error: several players match 'carlsen', call again with one exact name: Carlsen, Magnus (3 games); Carlsen, Henrik (1 games)} {error: no player matching 'kasparov' in *}}

tcltest::test assistant-opening-score {opening_score reports results by ECO code or range} -body {
	list [::application::assistant::runTool opening_score {eco b9}] \
		[::application::assistant::runTool opening_score {eco B90}] \
		[::application::assistant::runTool opening_score {eco A00-A99}] \
		[::application::assistant::runTool opening_score {eco Najdorf}]
} -result {{B90-B99: 2 games -- white wins 1, draws 1, black wins 0 (white scores 75.0%)} {B90 Sicilian Defence, Najdorf Variation: 1 games -- white wins 1, draws 0, black wins 0 (white scores 100.0%)} {no games with A00-A99} {error: eco must be like 'B90', 'B9', 'B' or 'B90-B99'}}

tcltest::test assistant-opening-score-player {opening_score with a player scores from that side} -body {
	::application::assistant::runTool opening_score {eco B player {Carlsen, Magnus}}
} -result "Carlsen, Magnus with B00-B99: 2 games\nwith White: 1 wins, 0 draws, 0 losses, score 100.0%\nwith Black: 0 wins, 1 draws, 0 losses, score 50.0%"

tcltest::test assistant-database-summary {database_summary counts games and ranks the openings} -body {
	set reply [::application::assistant::runTool database_summary {}]
	list [string match "*games: 3, players: 3*" $reply] \
		[string match "*games with an ECO code: 3 -- white wins 1, draws 1, black wins 1*" $reply] \
		[string match "*most played openings:\n  B9* games*" $reply] \
		[string match "*C60 Spanish Opening (Ruy L\u00f3pez): 1 games*" $reply]
} -result {1 1 1 1}

tcltest::test assistant-player-question-loop {the model resolves an ambiguous player in a second call} -body {
	::application::assistant::clear
	set text [::scidb::test::assistant::run "how does Carlsen do?" [list \
		[::scidb::test::assistant::call player_stats {name carlsen}] \
		[::scidb::test::assistant::call player_stats {name {Carlsen, Magnus}}] \
		[dict create role assistant content "Magnus Carlsen scored 83.3% in 3 games."]]]
	list [string match "*several players match*" $text] \
		[string match "*total: 2 wins, 1 draws, 0 losses, score 83.3%*" $text] \
		[string match "*scored 83.3% in 3 games.*" $text]
} -result {1 1 1}

::scidb::test::assistant::closeFixture

tcltest::test assistant-current-game {current_game gives the board game as PGN with the position} -body {
	set reply [::application::assistant::runTool current_game {}]
	list [string match {*\[Event *} $reply] [string match "*current position: * w *" $reply]
} -result {1 1}

tcltest::test assistant-tool-log {every tool call is logged with its outcome} -body {
	set saved $::application::assistant::ToolLog
	set ::application::assistant::ToolLog {}
	::scidb::test::assistant::setup 0
	::application::assistant::runTool run_shell {command ls}
	::application::assistant::runTool switch_tab {tab settings}
	::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}
	::application::assistant::runTool list_open_databases {}
	set reply [::application::assistant::runTool tool_log {count 4}]
	set ::application::assistant::ToolLog $saved
	lmap line [split $reply \n] { regsub {^\[[0-9:]+\] } $line "" }
} -match glob -result {{run_shell {command ls}: error -- error: unknown tool 'run_shell'} {switch_tab {tab settings}: error -- error: tab must be*} {new_game {}, asked the user: declined -- The user declined*} {list_open_databases {}: ok -- *(active)*}}

tcltest::test assistant-tool-log-bounded {the log keeps only the latest calls} -body {
	set saved $::application::assistant::ToolLog
	set ::application::assistant::ToolLog {}
	for {set i 0} {$i < 60} {incr i} { ::application::assistant::runTool list_open_databases {} }
	set n [llength $::application::assistant::ToolLog]
	set ::application::assistant::ToolLog $saved
	set n
} -result 50

set ::application::assistant::Priv(confirm) ::application::assistant::ConfirmDialog

# ----------------------------------------------------------------------

::tcltest::cleanupTests
return
