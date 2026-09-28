# ======================================================================
# ::application::assistant -- an AI intermediary that operates the app.
#
# The user types a request into the "assistant" pane of the board tab; the
# model answers, and may call tools that map onto existing menu actions.
# The model can only name a tool from the fixed table below, whose
# arguments are checked before anything runs. Every tool that changes
# something asks the user first.
#
# Every error the app reports -- background errors, the log window, error
# dialogs, failing tools -- is recorded for recent_errors and appended to
# the error log file, which ::application::triage (app-error-triage.tcl)
# has the model sort into issues.
#
# Debug mode (--ai-debug or SCIDB_AI_DEBUG=1) adds introspection tools for developers:
# reading variables and procedure sources, and -- after confirmation of
# the exact script -- evaluating Tcl.
#
#   ::application::assistant::show
#   ::application::assistant::ask "install the player photos"
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval assistant {
namespace eval mc {

set Send				"Send"
set Clear			"Clear"
set Thinking		"Thinking..."
set Ready			"Ready"
set Confirm			"The assistant wants to: %s"
set Denied			"The user declined: the action was NOT performed and no dialog was opened."
set Greeting		"Ask me to do something in Scidb, for example \"start a new game\" or \"explain the current position\"."
set DebugGreeting	"Debug mode: I can also inspect errors, procedures and variables."

} ;# namespace mc

variable PaneTitle ""

# Tool table: name {confirm debug what description parameters handler}.
#   confirm     the tool changes something; it runs only once the user allows it
#   debug       offered only in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)
#   what        the action as shown in the confirmation (a format string over
#               the checked arguments)
#   parameters  JSON schema of the arguments
variable Actions {
	explain_position {
		0 0 "explain the current position"
		"Explain the chess position currently on the board. The assessment appears in the Report pane."
		{{"type":"object","properties":{}}}
		::application::assistant::DoExplainPosition
	}
	new_game {
		1 0 "start a new game"
		"Start a new, empty game on the board."
		{{"type":"object","properties":{}}}
		::application::assistant::DoNewGame
	}
	switch_tab {
		0 0 "switch to the %s tab"
		"Switch the main window to the board tab or the database tab."
		{{"type":"object","properties":{"tab":{"type":"string","enum":["board","database"]}},"required":["tab"]}}
		::application::assistant::DoSwitchTab
	}
	list_open_databases {
		0 0 "list the open databases"
		"List the databases currently open, and which one is active."
		{{"type":"object","properties":{}}}
		::application::assistant::DoListDatabases
	}
	discover_databases {
		0 0 "open the database discovery dialog"
		"Open the dialog that scans the disk for chess databases."
		{{"type":"object","properties":{}}}
		::application::assistant::DoDiscover
	}
	open_database {
		1 0 "open the database %s"
		"Open a database file (.sci, .si4, .cbh, .pgn, ...) given its full path."
		{{"type":"object","properties":{"path":{"type":"string","description":"absolute path of the database file"}},"required":["path"]}}
		::application::assistant::DoOpenDatabase
	}
	open_search {
		0 0 "open the %s search"
		"Open a search dialog on the active database: 'advanced' (header fields such as player, event, date, ECO), 'material' (material balance) or 'rating' (Elo ranges)."
		{{"type":"object","properties":{"kind":{"type":"string","enum":["advanced","material","rating"]}},"required":["kind"]}}
		::application::assistant::DoOpenSearch
	}
	download_games {
		1 0 "download games from the internet into this database"
		"Download games from the internet into the active database and import them: 'twic' takes the latest weekly issues of The Week in Chess (default 1 issue, up to 12), 'lichess' takes game links or 8-character game ids given in 'lichess', 'url' takes a PGN/zip/gz link given in 'url'. The import runs like 'Import PGN files'. Ask only when the user wants games from the internet."
		{{"type":"object","properties":{"source":{"type":"string","enum":["twic","lichess","url"],"description":"where to download from, default twic"},"issues":{"type":"integer","description":"TWIC: how many weekly issues, default 1 (max 12)"},"lichess":{"type":"string","description":"lichess: game links or ids, one per line"},"url":{"type":"string","description":"url: a PGN, zipped PGN or gzipped PGN link"}}}}
		::application::assistant::DoDownloadGames
	}
	export_database {
		0 0 "open the export dialog"
		"Open the export dialog for the active database (PGN, HTML, LaTeX, PDF, Scidb formats). The user picks the format and file there."
		{{"type":"object","properties":{}}}
		::application::assistant::DoExport
	}
	install_player_photos {
		1 0 "open the player photo installer"
		"Open the dialog that installs or updates the player photos."
		{{"type":"object","properties":{}}}
		::application::assistant::DoInstallPhotos
	}
	install_chessbase_fonts {
		1 0 "install the ChessBase fonts"
		"Install the ChessBase chess fonts from a Windows font directory."
		{{"type":"object","properties":{}}}
		::application::assistant::DoInstallFonts
	}
	current_game {
		0 0 "read the current game"
		"The game on the board: its header, moves and comments as PGN, and the current position as FEN. Use it to summarize or discuss the game."
		{{"type":"object","properties":{}}}
		::application::assistant::DoCurrentGame
	}
	position_moves {
		0 0 "report the moves played in this position"
		"The moves played from the position on the board in the tree's database (if none is set, the active database becomes it): for each move the games, share, score for the side to move, draws, average Elo, last year played and best player. Answers 'what is played here', 'what scores best' and 'is this move a novelty' (a move missing from the list is new to that database)."
		{{"type":"object","properties":{"limit":{"type":"integer","description":"how many moves, default 10"}}}}
		::application::assistant::DoPositionMoves
	}
	database_summary {
		0 0 "summarize the active database"
		"Summarize the active database: number of games and players, overall results, and the most played openings (ECO) with their scores."
		{{"type":"object","properties":{}}}
		::application::assistant::DoDatabaseSummary
	}
	player_stats {
		0 0 "report the statistics of %s"
		"Statistics of a player in the active database: games, wins/draws/losses with White and with Black, score, first and last game, Elo range, most played openings. The name may be partial ('carlsen'); if several players match, the candidates are listed and you call again with the exact name."
		{{"type":"object","properties":{"name":{"type":"string","description":"player name or part of it, e.g. 'Carlsen, Magnus' or 'carlsen'"}},"required":["name"]}}
		::application::assistant::DoPlayerStats
	}
	opening_score {
		0 0 "report the score of the opening %s %s"
		"Results of an opening in the active database, by ECO code: 'B90' (one code), 'B9' (B90-B99), 'B' (B00-B99) or a range 'B90-B99'. Without a player: white wins, draws, black wins. With a player: that player's wins/draws/losses with White and with Black. Map opening names to ECO codes yourself (e.g. Najdorf = B90-B99)."
		{{"type":"object","properties":{"eco":{"type":"string"},"player":{"type":"string","description":"optional player name or part of it"}},"required":["eco"]}}
		::application::assistant::DoOpeningScore
	}
	prepare_against {
		0 0 "prepare against %s %s"
		"Preparation against an opponent from the active database: the openings they play with White and with Black and how they score in each, their weakest lines, and their latest games. 'color' is the colour the opponent will have; without it both are shown. The name may be partial, as for player_stats."
		{{"type":"object","properties":{"name":{"type":"string","description":"the opponent's name or part of it"},"color":{"type":"string","enum":["white","black"],"description":"the colour the opponent will play"}},"required":["name"]}}
		::application::assistant::DoPrepareAgainst
	}
	repertoire_check {
		0 0 "check the repertoire %s %s %s"
		"Check an opening repertoire (an open database of type Openings, Openings White or Openings Black) against practice, by ECO code: its lines that score below average, openings often reached but not covered, and repertoire lines never reached. Practice is the given player's own games in the active database, else all games there. 'color' is the repertoire's side, needed only for a repertoire of both colours."
		{{"type":"object","properties":{"repertoire":{"type":"string","description":"name or part of the name of the repertoire database; needed only when several are open"},"player":{"type":"string","description":"whose games to check against, e.g. the user's own name"},"color":{"type":"string","enum":["white","black"]}}}}
		::application::assistant::DoRepertoireCheck
	}
	search_games {
		0 0 "search the games"
		"Search the active database; nothing changes, the game list included. Returns the number of games found, the first of them, and the criteria as understood. Names may be partial. 'result' is win/draw/loss from the player's side, or 1-0/0-1/1/2-1/2 without a player. 'eco' is a code, class or range as for opening_score (map opening names to ECO yourself). Dates are YYYY, YYYY.MM or YYYY.MM.DD. To show the games in the game list, call show_search afterwards."
		{{"type":"object","properties":{"player":{"type":"string"},"color":{"type":"string","enum":["white","black","any"],"description":"the player's colour, default any"},"result":{"type":"string","enum":["win","draw","loss","1-0","0-1","1/2-1/2"]},"opponent":{"type":"string"},"eco":{"type":"string"},"from":{"type":"string","description":"earliest date"},"to":{"type":"string","description":"latest date"},"event":{"type":"string","description":"part of the event name"},"min_elo":{"type":"integer","description":"minimum average Elo of the two players"}}}}
		::application::assistant::DoSearchGames
	}
	show_search {
		1 0 "show the games of the last search in the game list"
		"Filter the game list of the active database to the games of the last search_games, and switch to the database tab."
		{{"type":"object","properties":{}}}
		::application::assistant::DoShowSearch
	}
	clear_search {
		1 0 "show all games in the game list again"
		"Remove the filter from the game list of the active database."
		{{"type":"object","properties":{}}}
		::application::assistant::DoClearSearch
	}
	list_engines {
		0 0 "list the chess engines"
		"The chess engines Scidb can run: the ones bundled with Scidb and the ones the user added. For each: name, version, protocol, variants, rating, threads, hash and line limits, its program and whether that program is there. Also which analysis panes run which engine."
		{{"type":"object","properties":{}}}
		::application::assistant::DoListEngines
	}
	engine_options {
		0 0 "read the options of %s"
		"The options of an engine's profile (default 'Default') as the Options dialog shows them: name, type, value, default and range or choices. Threads, hash and the number of lines are not options here; start_engine sets them."
		{{"type":"object","properties":{"engine":{"type":"string","description":"engine name or part of it"},"profile":{"type":"string"}},"required":["engine"]}}
		::application::assistant::DoEngineOptions
	}
	start_engine {
		1 0 "analyse the board position with %s"
		"Start an engine on the position on the board in an analysis pane; it follows the board as it changes. Without a pane a free one is used or a new one opened; giving the pane of a running engine replaces or restarts it (e.g. to change lines). lines = number of best lines (MultiPV), threads, hash in MB; each defaults to the pane's setting. Then read its lines with engine_analysis."
		{{"type":"object","properties":{"engine":{"type":"string","description":"engine name or part of it"},"pane":{"type":"integer","description":"analysis pane number as in its title: 1 for 'Analysis', 2 for 'Analysis (2)'"},"lines":{"type":"integer"},"threads":{"type":"integer"},"hash":{"type":"integer","description":"hash size in MB"}},"required":["engine"]}}
		::application::assistant::DoStartEngine
	}
	engine_analysis {
		0 0 "read the engine analysis"
		"The lines the running engines show for the board position: per pane the engine, depth and for each line the score (pawns from White's side, #n = mate in n) and the moves. 'seconds' waits that long first (at most 60) so the engine can search deeper; the result comes when the wait is over."
		{{"type":"object","properties":{"pane":{"type":"integer"},"seconds":{"type":"integer"}}}}
		::application::assistant::DoEngineAnalysis
	}
	stop_engine {
		1 0 "stop the engine in analysis pane %s"
		"Stop the engine of an analysis pane; the pane stays open. The pane may be left out when only one engine runs."
		{{"type":"object","properties":{"pane":{"type":"integer"}}}}
		::application::assistant::DoStopEngine
	}
	set_engine_option {
		1 0 "set option '%2$s' of %1$s to '%3$s' (profile %4$s)"
		"Change an option of an engine's profile (default 'Default'), checked against its type and range; engine_options lists them. Running panes of that engine restart with it. The change is saved."
		{{"type":"object","properties":{"engine":{"type":"string"},"option":{"type":"string"},"value":{"type":"string"},"profile":{"type":"string"}},"required":["engine","option","value"]}}
		::application::assistant::DoSetEngineOption
	}
	add_engine {
		1 0 "add the engine program %s to the engine list"
		"Add a UCI or WinBoard engine program, given the full path of its executable. Scidb probes it for its name, options and features; a program already in the list is refreshed."
		{{"type":"object","properties":{"path":{"type":"string","description":"absolute path of the engine executable"}},"required":["path"]}}
		::application::assistant::DoAddEngine
	}
	remove_engine {
		1 0 "remove %s from the engine list"
		"Remove an engine from the engine list (its program stays on disk). Not while it runs in a pane. Only when the user asks for it."
		{{"type":"object","properties":{"engine":{"type":"string"}},"required":["engine"]}}
		::application::assistant::DoRemoveEngine
	}
	app_state {
		0 0 "report the application state"
		"Report the application state for diagnosis: Tcl/Tk and model versions, the selected tab, the active database and variant, game counts, the current game and position, and the panes of the board layout."
		{{"type":"object","properties":{}}}
		::application::assistant::DoAppState
	}
	recent_errors {
		0 0 "report recent errors"
		"The most recent errors of this session, newest last: background Tcl errors (with stack), error messages of the log window and of error dialogs, and failing assistant tools."
		{{"type":"object","properties":{"count":{"type":"integer","description":"how many, default 3"}}}}
		::application::assistant::DoRecentErrors
	}
	tool_log {
		0 0 "report recent tool calls"
		"The most recent assistant tool calls of this session, newest last: time, tool, arguments, whether the user was asked, outcome (ok, error, declined) and the start of the reply. Use it to explain what the assistant did or why something failed."
		{{"type":"object","properties":{"count":{"type":"integer","description":"how many, default 10"}}}}
		::application::assistant::DoToolLog
	}
	triage_errors {
		0 0 "triage the error log"
		"Have the error log triaged now: new error groups are classified (bug, environment, user, noise) and every bug gets an issue file. Runs in the background; the result is posted here when it is done."
		{{"type":"object","properties":{}}}
		::application::assistant::DoTriage
	}
	list_issues {
		0 0 "list the issues"
		"The bugs found by error triage, newest first: issue id, severity, summary and file."
		{{"type":"object","properties":{}}}
		::application::assistant::DoListIssues
	}
	classifier_status {
		0 0 "report the System One classifier status"
		"Which System One decision model is configured (and whether it answers), whether it routes simple requests, and the most recent routing decisions it made. Use it when the user asks about the classifier, the decision model, or why a request was or was not routed."
		{{"type":"object","properties":{}}}
		::application::assistant::DoClassifierStatus
	}
	annotate_game {
		1 0 "annotate this game with engine-grounded comments"
		"Annotate the game on the board: classify every move with the chess engine, then write a comment for the moves that deserve one (blunders, mistakes, inaccuracies, and the only move that holds). With 'prose' true (the default) the comment is written by the language model from the engine's facts and checked; with 'prose' false the comment is the engine's own verdict in words, which costs no model call. 'marks' also sets the standard annotation mark. 'max_plies' bounds the work. The game is left modified for the user to save."
		{{"type":"object","properties":{"prose":{"type":"boolean","description":"let the language model word the comments, default true"},"depth":{"type":"integer","description":"engine depth per move, default 12"},"marks":{"type":"boolean","description":"also set the move's annotation mark, default false"},"max_plies":{"type":"integer","description":"stop after this many moves, default 60"}}}}
		::application::assistant::DoAnnotateGame
	}
	voice_status {
		0 0 "report the voice assistant status"
		"Whether speaking to the assistant is available: the recorder, the local speech-to-text engine and model, and how replies are spoken. Use it when the user asks about voice input, dictation, or why the microphone button is not there."
		{{"type":"object","properties":{}}}
		::application::assistant::DoVoiceStatus
	}
	handoff_issue {
		1 0 "hand issue %s to the coding agent"
		"Start the configured coding agent on an issue found by triage, to fix it in the Scidb sources. Only when the user asks for it."
		{{"type":"object","properties":{"issue":{"type":"string","description":"the issue id, 8 hex digits"}},"required":["issue"]}}
		::application::assistant::DoHandoff
	}
	list_procs {
		0 1 "list procedures matching %s"
		"List Tcl procedures whose fully qualified name matches a glob pattern, e.g. ::application::report::*."
		{{"type":"object","properties":{"pattern":{"type":"string"}},"required":["pattern"]}}
		::application::assistant::DoListProcs
	}
	proc_source {
		0 1 "read the source of %s"
		"The argument list and body of a Tcl procedure, by fully qualified name."
		{{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}
		::application::assistant::DoProcSource
	}
	read_variable {
		0 1 "read the variable %s"
		"The value of a Tcl variable by fully qualified name; for an array, its elements (optionally only those matching a glob pattern)."
		{{"type":"object","properties":{"name":{"type":"string"},"pattern":{"type":"string"}},"required":["name"]}}
		::application::assistant::DoReadVariable
	}
	eval_tcl {
		1 1 "evaluate this Tcl script:\n\n%s"
		"Evaluate a Tcl script at global level and return its result. The user reviews the exact script first; prefer the read-only tools."
		{{"type":"object","properties":{"script":{"type":"string"}},"required":["script"]}}
		::application::assistant::DoEvalTcl
	}
}

variable System {You are the assistant of Scidb, a chess database application.
You operate the application only through the tools you are given; call a tool
whenever it does what the user asks. If no tool fits, say so briefly and name
the menu entry that does it if you know one. Never claim you did something a
tool did not report. Answer in one or two short sentences. For questions
about games, players or openings, use the numbers the tools report and never
invent statistics; a short list is fine there.}

variable DebugSystem {
You are also a debugging aid for the developer of Scidb (Tcl/Tk front end
over a C++ core). When asked about a problem, gather facts with the tools
(app_state, recent_errors, tool_log, list_procs, proc_source, read_variable) before
answering, cite procedure names and the evidence you saw, and say plainly
what you could not verify. Longer answers are fine in this role.}

# Replies longer than this are cut, so one tool cannot flood the context.
variable MaxReply 6000

# errors seen in this session: {time source message detail}, see RecordError
variable Errors {}
variable MaxErrors 20

# Every error is also appended here (SCIDB_ERROR_LOG overrides, "" disables);
# at MaxErrorLogSize the file moves to <file>.1 and a new one starts.
variable ErrorLogFile ""
variable MaxErrorLogSize 1000000
if {[info exists ::env(SCIDB_ERROR_LOG)]} {
	set ErrorLogFile $::env(SCIDB_ERROR_LOG)
} elseif {[info exists ::scidb::dir::user]} {
	set ErrorLogFile [file join $::scidb::dir::user log errors.log]
}

# tool calls made in this session: see LogToolCall
variable ToolLog {}
variable MaxToolLog 50

array set Priv {
	window		{}
	text			{}
	entry			{}
	send			{}
	status		{}
	messages		{}
	busy			0
	maxRounds	8
	debug			0
	observer		{}
	reqconfirm	{}
	confirm		::application::assistant::ConfirmDialog
	pending		{}
	laterCount	0
	routeGen		0
	routeWait	0
	routeInvocations {}
}

if {   ([info exists ::env(SCIDB_AI_DEBUG)] && [string is true -strict $::env(SCIDB_AI_DEBUG)])
	 || ([llength [info commands ::process::testOption]] && [::process::testOption ai-debug])} {
	set Priv(debug) 1
}

} ;# namespace assistant
} ;# namespace application


# ----------------------------------------------------------------------
# Entry points.
# ======================================================================
proc ::application::assistant::show {} {
	variable Priv

	::application::openPane assistant
	if {[winfo exists $Priv(entry)]} { focus $Priv(entry) }
	return $Priv(window)
}


# Options, for this request only:
#   -observer CMD   called as CMD tool NAME REPLY, CMD reply TEXT, CMD error TEXT
#   -confirm CMD    asks the user instead of the dialog (CMD WHAT -> 0|1)
# Returns 0 when the request was not started (empty, or another is running).
proc ::application::assistant::ask {request args} {
	variable Priv
	variable System

	array set opts {-observer {} -confirm {}}
	array set opts $args

	set request [string trim $request]
	if {![string length $request] || $Priv(busy)} { return 0 }
	set Priv(observer) $opts(-observer)
	set Priv(reqconfirm) $opts(-confirm)

	if {![llength $Priv(messages)]} {
		variable DebugSystem
		set system $System
		if {$Priv(debug)} { append system \n $DebugSystem }
		lappend Priv(messages) [dict create role system content $system]
	}
	lappend Priv(messages) [dict create role user content $request]
	Append user $request

	SetBusy 1
	if {[catch {
		ConfigureProvider
		# the System One pre-router (app-assistant-route.tcl) decides
		# whether one default tool invocation performs the request; every
		# other path ends in the ordinary model loop
		if {[llength [info commands ::application::assistant::RouteOrStep]]} {
			RouteOrStep $request
		} else {
			Step 0
		}
	} err]} {
		Finish [dict create ok 0 error $err] 0
	}
	return 1
}


proc ::application::assistant::Notify {args} {
	variable Priv

	if {[llength $Priv(observer)]} {
		catch { {*}$Priv(observer) {*}$args }
	}
}


proc ::application::assistant::clear {} {
	variable Priv
	variable mc

	if {$Priv(busy)} { return }
	set Priv(messages) {}
	# invalidate any in-flight pre-route prediction for the old conversation
	if {[info exists Priv(routeGen)]} { incr Priv(routeGen) }
	set Priv(routeWait) 0
	if {[winfo exists $Priv(text)]} {
		$Priv(text) configure -state normal
		$Priv(text) delete 1.0 end
		$Priv(text) configure -state disabled
		Greet
	}
}


# ----------------------------------------------------------------------
# The request loop: model -> tool calls -> model, at most maxRounds.
# ======================================================================
proc ::application::assistant::ConfigureProvider {} {
	variable ::application::ai::Config

	::ai::provider::configure -name $Config(provider) -model $Config(model) \
		-timeout 120000 -options {}
}


proc ::application::assistant::Step {round} {
	variable Priv

	# the last round offers no tools, so the model has to answer in prose
	set tools [expr {$round + 1 < $Priv(maxRounds) ? [toolsJson] : ""}]
	::ai::provider::chatAsync $Priv(messages) $tools \
		[namespace code [list OnReply $round]]
}


proc ::application::assistant::OnReply {round result} {
	# a failing step must still release the pane
	if {[catch { OnReplyImpl $round $result } err]} {
		Finish [dict create ok 0 error $err] $round
	}
}


proc ::application::assistant::OnReplyImpl {round result} {
	variable Priv

	if {![dict get $result ok]} {
		Finish $result $round
		return
	}

	set msg [dict get $result message]
	incr round

	# the shadow log compares the classifier's prediction with what the
	# model actually did first (app-assistant-route.tcl)
	if {$round == 1 && [llength [info commands ::application::assistant::RecordRouteActual]]} {
		if {[dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]} {
			RecordRouteActual [dict get [dict get [lindex [dict get $msg tool_calls] 0] function] name]
		} else {
			RecordRouteActual prose
		}
	}

	if {[dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]} {
		lappend Priv(messages) $msg
		RunCalls $round [dict get $msg tool_calls]
		return
	}

	Finish [dict create ok 1 message $msg] $round
}


# Run the tool calls of one reply in order, then ask the model again. A tool
# that answers later (see Later) parks the rest until Resolve.
proc ::application::assistant::RunCalls {round calls} {
	variable Priv

	while {[llength $calls]} {
		set calls [lassign $calls call]
		set fn [dict get $call function]
		set name [dict get $fn name]
		set cargs [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
		set reply [runTool $name $cargs]
		if {[string match "\x00later:*" $reply]} {
			set Priv(pending) [list $reply $round $name $cargs $calls]
			Append tool "$name: (working...)"
			return
		}
		ToolReply $name $reply
	}

	if {$round < $Priv(maxRounds)} {
		Step $round
	} else {
		Finish [dict create ok 1 message [dict create role assistant content ""]] $round
	}
}


proc ::application::assistant::ToolReply {name reply} {
	variable Priv

	Append tool "$name: $reply"
	Notify tool $name $reply
	lappend Priv(messages) [dict create role tool content $reply tool_name $name]
}


# For a handler that answers later: return [Later] now, and hand the reply
# to Resolve with that token when it is there.
proc ::application::assistant::Later {} {
	variable Priv
	return "\x00later:[incr Priv(laterCount)]"
}


# Returns 0 when nothing waits for <token> (the request ended meanwhile).
proc ::application::assistant::Resolve {token reply} {
	variable Priv
	variable MaxReply

	if {[lindex $Priv(pending) 0] ne $token} { return 0 }
	lassign $Priv(pending) _ round name cargs calls isRouted
	set Priv(pending) {}
	if {[string length $reply] > $MaxReply} {
		set reply "[string range $reply 0 $MaxReply-1]\n... (truncated)"
	}
	LogToolCall $name $cargs 0 [expr {[string match "error: *" $reply] ? "error" : "ok"}] $reply
	if {[llength $isRouted]} {
		# a pre-routed asynchronous tool: deliver its reply directly,
		# never re-enter the model loop
		if {[catch { DeliverRoutedReply $name $reply $round } err]} {
			Finish [dict create ok 0 error $err] $round
		}
		return 1
	}
	if {[catch { ToolReply $name $reply; RunCalls $round $calls } err]} {
		Finish [dict create ok 0 error $err] $round
	}
	return 1
}


proc ::application::assistant::Finish {result round} {
	variable Priv

	if {[dict get $result ok]} {
		set msg [dict get $result message]
		set text [expr {[dict exists $msg content] ? [string trim [dict get $msg content]] : ""}]
		if {![string length $text]} { set text "(no answer)" }
		lappend Priv(messages) [dict create role assistant content $text]
		Append assistant $text
		set event [list reply $text]
	} else {
		Append error "Error: [dict get $result error]"
		set event [list error [dict get $result error]]
	}
	SetBusy 0
	set observer $Priv(observer)
	set Priv(observer) {}
	set Priv(reqconfirm) {}
	set Priv(pending) {}
	if {[llength $observer]} { catch { {*}$observer {*}$event } }
}


# ----------------------------------------------------------------------
# Tool dispatch. Unknown tools and bad arguments are reported back to the
# model as text, never raised: the model can correct itself.
# ======================================================================
proc ::application::assistant::runTool {name cargs} {
	lassign [RunTool $name $cargs] outcome asked reply
	# a later answer is logged when it arrives (Resolve)
	if {$outcome ne "later"} { LogToolCall $name $cargs $asked $outcome $reply }
	return $reply
}


# Returns {outcome asked reply}: outcome is ok, error or declined; asked
# tells whether the user was asked to confirm.
proc ::application::assistant::RunTool {name cargs} {
	variable Actions
	variable MaxReply
	variable Priv
	variable mc

	if {![dict exists $Actions $name]} {
		return [list error 0 "error: unknown tool '$name'"]
	}
	lassign [dict get $Actions $name] confirm debug what _ _ handler
	if {$debug && !$Priv(debug)} {
		return [list error 0 "error: '$name' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)"]
	}

	if {[catch { set checked [CheckArgs $name $cargs] } err]} {
		return [list error 0 "error: $err"]
	}

	if {$confirm} {
		set what [format $what {*}[dict values $checked]]
		set confirm [expr {[llength $Priv(reqconfirm)] ? $Priv(reqconfirm) : $Priv(confirm)}]
		if {![{*}$confirm $what]} { return [list declined 1 $mc::Denied] }
		set confirm 1
	}

	if {[catch { set reply [{*}$handler {*}[dict values $checked]] } err opts]} {
		RecordError assistant "$name: $err" [dict get $opts -errorinfo]
		return [list error $confirm "error: $err"]
	}
	if {[string match "\x00later:*" $reply]} { return [list later $confirm $reply] }
	if {[string length $reply] > $MaxReply} {
		set reply "[string range $reply 0 $MaxReply-1]\n... (truncated)"
	}
	return [list ok $confirm $reply]
}


# Every tool call, whatever its outcome, for tool_log: {time name arguments asked outcome reply}
proc ::application::assistant::LogToolCall {name cargs asked outcome reply} {
	variable ToolLog
	variable MaxToolLog

	set reply [string map {\n " | "} [string trim $reply]]
	if {[string length $reply] > 200} { set reply "[string range $reply 0 199]..." }
	lappend ToolLog [list [clock format [clock seconds] -format %T] $name $cargs $asked $outcome $reply]
	if {[llength $ToolLog] > $MaxToolLog} { set ToolLog [lrange $ToolLog end-[expr {$MaxToolLog - 1}] end] }
}


# The tool definitions offered to the model in the current mode.
proc ::application::assistant::toolsJson {} {
	variable Actions
	variable Priv

	set defs {}
	dict for {name entry} $Actions {
		lassign $entry _ debug _ description parameters
		if {$debug && !$Priv(debug)} { continue }
		lappend defs [format {{"type":"function","function":{"name":"%s","description":"%s","parameters":%s}}} \
			$name [::ai::provider::jsonEscape $description] $parameters]
	}
	return "\[[join $defs ,]\]"
}


# Returns the handler arguments as an ordered dict.
proc ::application::assistant::CheckArgs {name cargs} {
	switch -- $name {
		switch_tab {
			set tab [Arg $cargs tab]
			if {$tab ni {board database}} { error "tab must be 'board' or 'database'" }
			return [dict create tab $tab]
		}
		open_database {
			set path [Arg $cargs path]
			if {![file isfile $path]} { error "no such file: $path" }
			return [dict create path [file normalize $path]]
		}
		open_search {
			set kind [Arg $cargs kind]
			if {$kind ni {advanced material rating}} {
				error "kind must be 'advanced', 'material' or 'rating'"
			}
			return [dict create kind $kind]
		}
		position_moves {
			set limit 10
			if {[dict exists $cargs limit]} { set limit [dict get $cargs limit] }
			if {![string is integer -strict $limit] || $limit < 1} { error "limit must be a positive integer" }
			return [dict create limit $limit]
		}
		recent_errors - tool_log {
			set count [expr {$name eq "tool_log" ? 10 : 3}]
			if {[dict exists $cargs count]} { set count [dict get $cargs count] }
			if {![string is integer -strict $count] || $count < 1} { error "count must be a positive integer" }
			return [dict create count $count]
		}
		list_procs {
			return [dict create pattern [Arg $cargs pattern]]
		}
		proc_source {
			return [dict create name [Arg $cargs name]]
		}
		read_variable {
			set pattern *
			if {[dict exists $cargs pattern]} { set pattern [dict get $cargs pattern] }
			return [dict create name [Arg $cargs name] pattern $pattern]
		}
		eval_tcl {
			return [dict create script [Arg $cargs script]]
		}
		handoff_issue {
			set issue [string trim [Arg $cargs issue]]
			::application::triage::issueFile $issue
			return [dict create issue $issue]
		}
		search_games {
			set c {}
			foreach key {player color result opponent eco from to event min_elo} {
				dict set c $key [expr {[dict exists $cargs $key] ? [string trim [dict get $cargs $key]] : ""}]
			}
			dict with c {
				set color [string tolower $color]
				if {$color eq ""} { set color any }
				if {$color ni {white black any}} { error "color must be white, black or any" }
				if {$result ni {"" win draw loss 1-0 0-1 1/2-1/2}} {
					error "result must be win, draw, loss, 1-0, 0-1 or 1/2-1/2"
				}
				if {$player eq "" && ($color ne "any" || $result in {win draw loss} || $opponent ne "")} {
					error "color, opponent and a win/draw/loss result need a player"
				}
				if {$player ne "" && $result in {1-0 0-1 1/2-1/2}} {
					error "with a player, give the result as win, draw or loss"
				}
				if {$eco ne ""} { set eco [EcoRange $eco] }
				foreach bound {from to} {
					if {[set $bound] ne "" && ![regexp {^\d{4}(\.\d\d?(\.\d\d?)?)?$} [set $bound]]} {
						error "$bound must be YYYY, YYYY.MM or YYYY.MM.DD"
					}
				}
				if {$min_elo ne "" && (![string is integer -strict $min_elo] || $min_elo < 0 || $min_elo > 4000)} {
					error "min_elo must be a number up to 4000"
				}
			}
			if {![llength [lmap v [dict values $c] { if {$v in {"" any}} continue; set v }]]} {
				error "give at least one criterion"
			}
			return [dict create criteria $c]
		}
		repertoire_check {
			set result {}
			foreach key {repertoire player color} {
				dict set result $key [expr {[dict exists $cargs $key] ? [string trim [dict get $cargs $key]] : ""}]
			}
			dict set result color [string tolower [dict get $result color]]
			if {[dict get $result color] ni {"" white black}} { error "color must be 'white' or 'black'" }
			return $result
		}
		prepare_against {
			set name [string trim [Arg $cargs name]]
			if {![string length $name]} { error "name must not be empty" }
			set color ""
			if {[dict exists $cargs color]} { set color [string tolower [dict get $cargs color]] }
			if {$color ni {"" white black}} { error "color must be 'white' or 'black'" }
			return [dict create name $name color $color]
		}
		engine_options - remove_engine {
			set result [dict create engine [EngineNamed [Arg $cargs engine]]]
			if {$name eq "engine_options"} { dict set result profile [OptArg $cargs profile Default] }
			return $result
		}
		start_engine {
			set result [dict create engine [EngineNamed [Arg $cargs engine]]]
			dict set result pane [OptArg $cargs pane ""]
			if {[dict get $result pane] ne ""} { PaneNumber [dict get $result pane] }
			foreach key {lines threads hash} {
				set value [OptArg $cargs $key ""]
				if {$value ne "" && (![string is integer -strict $value] || $value < 1)} {
					error "$key must be a positive integer"
				}
				dict set result $key $value
			}
			return $result
		}
		engine_analysis {
			set pane [OptArg $cargs pane ""]
			if {$pane ne ""} { PaneNumber $pane }
			set seconds [OptArg $cargs seconds 0]
			if {![string is integer -strict $seconds] || $seconds < 0 || $seconds > 60} {
				error "seconds must be a whole number from 0 to 60"
			}
			return [dict create pane $pane seconds $seconds]
		}
		stop_engine {
			set pane [OptArg $cargs pane ""]
			if {$pane eq ""} {
				set running [RunningPanes]
				if {[llength $running] == 0} { error "no engine is running" }
				if {[llength $running] > 1} {
					error "engines run in panes [join [lmap n $running { PaneLabel $n }] {, }]; name the pane"
				}
				set pane [PaneLabel [lindex $running 0]]
			} elseif {![::engine::active? [PaneNumber $pane]]} {
				error "no engine runs in analysis pane $pane"
			}
			return [dict create pane $pane]
		}
		set_engine_option {
			set engine [EngineNamed [Arg $cargs engine]]
			set profile [OptArg $cargs profile Default]
			lassign [::engine::checkOption $engine [string trim [Arg $cargs option]] \
				[string trim [Arg $cargs value]] $profile] _ option value
			return [dict create engine $engine option $option value $value profile $profile]
		}
		add_engine {
			set path [string trim [Arg $cargs path]]
			if {![file isfile $path]} { error "no such file: $path" }
			if {![file executable $path]} { error "not executable: $path" }
			return [dict create path [file normalize $path]]
		}
		player_stats {
			set name [string trim [Arg $cargs name]]
			if {![string length $name]} { error "name must not be empty" }
			return [dict create name $name]
		}
		opening_score {
			set player ""
			if {[dict exists $cargs player]} { set player [string trim [dict get $cargs player]] }
			return [dict create range [EcoRange [Arg $cargs eco]] player $player]
		}
		download_games {
			set source [OptArg $cargs source twic]
			if {$source ni {twic lichess url}} {
				error "source must be 'twic', 'lichess' or 'url'"
			}
			set issues [OptArg $cargs issues 1]
			if {![string is integer -strict $issues] || $issues < 1 || $issues > 12} {
				error "issues must be an integer between 1 and 12"
			}
			set lichess [OptArg $cargs lichess ""]
			set url [OptArg $cargs url ""]
			if {$source eq "lichess" && $lichess eq ""} {
				error "source 'lichess' needs the 'lichess' argument with links or game ids"
			}
			if {$source eq "url" && $url eq ""} {
				error "source 'url' needs the 'url' argument"
			}
			return [dict create source $source issues $issues lichess $lichess url $url]
		}
		classifier_status {
			return {}
		}
		annotate_game {
			set prose 1
			if {[dict exists $cargs prose]} {
				set prose [expr {[string is true -strict [dict get $cargs prose]] ? 1 : 0}]
			}
			set marks 0
			if {[dict exists $cargs marks]} {
				set marks [expr {[string is true -strict [dict get $cargs marks]] ? 1 : 0}]
			}
			set depth [OptArg $cargs depth 12]
			if {![string is integer -strict $depth] || $depth < 4 || $depth > 30} {
				error "depth must be an integer between 4 and 30"
			}
			set maxPlies [OptArg $cargs max_plies 60]
			if {![string is integer -strict $maxPlies] || $maxPlies < 1 || $maxPlies > 200} {
				error "max_plies must be an integer between 1 and 200"
			}
			return [dict create prose $prose marks $marks depth $depth max_plies $maxPlies]
		}
	}
	return {}
}


# "B90" -> {B90 B90}, "B9" -> {B90 B99}, "B" -> {B00 B99}, "B90-B99" -> {B90 B99}
proc ::application::assistant::EcoRange {eco} {
	set eco [string toupper [string map {" " ""} $eco]]
	if {[regexp {^([A-E]\d\d)-([A-E]\d\d)$} $eco _ from to]} {
		if {$to < $from} { error "the ECO range '$eco' is reversed" }
		return [list $from $to]
	}
	if {[regexp {^[A-E]\d?\d?$} $eco]} {
		return [list [string range ${eco}00 0 2] [string range ${eco}99 0 2]]
	}
	error "eco must be like 'B90', 'B9', 'B' or 'B90-B99'"
}


proc ::application::assistant::Arg {cargs key} {
	if {![dict exists $cargs $key]} { error "missing argument '$key'" }
	return [dict get $cargs $key]
}


proc ::application::assistant::OptArg {cargs key default} {
	if {![dict exists $cargs $key]} { return $default }
	set value [string trim [dict get $cargs $key]]
	return [expr {$value eq "" ? $default : $value}]
}


proc ::application::assistant::ConfirmDialog {what} {
	variable Priv
	variable mc

	set reply [::dialog::question \
		-parent [winfo toplevel $Priv(window)] \
		-message [format $mc::Confirm $what] \
		-default no \
	]
	return [expr {$reply eq "yes"}]
}


# ----------------------------------------------------------------------
# Tool handlers: thin wrappers over the menu actions.
# ======================================================================
proc ::application::assistant::DoExplainPosition {} {
	::application::ai::analyze .application
	return "started; the assessment appears in the Report pane"
}


proc ::application::assistant::DoNewGame {} {
	::menu::gameNew .application [::application::database::currentVariant]
	return "a new game is on the board"
}


proc ::application::assistant::DoOpenSearch {kind} {
	set base [::scidb::db::get name]
	set variant [::application::database::currentVariant]
	set open [string totitle $kind]
	::application::database::Open${open}Search .application $base $variant
	return "the $kind search dialog is open on [::util::databaseName $base no]"
}


proc ::application::assistant::DoExport {} {
	set base [::scidb::db::get name]
	set switcher [::application::database::switcherWidget]
	set ext [expr {[string length $switcher] ? [$switcher extension $base] : "sci"}]
	::export::open .application \
		-base $base \
		-variant [::application::database::currentVariant] \
		-extension $ext \
		-name [::util::databaseName $base no] \
		-view 0 \
		;
	return "the export dialog is open for [::util::databaseName $base no]; the user picks format and file"
}


# --- read-only queries over the board game and the active database ------

proc ::application::assistant::ActiveBase {} {
	return [list [::scidb::db::get name] [::application::database::currentVariant]]
}


proc ::application::assistant::DoCurrentGame {} {
	# the saved game unless it has unsaved changes
	set source [expr {[::scidb::game::query modified?] ? "modified" : "original"}]
	set pgn [string trim [::scidb::game::toPGN $source]]
	return "$pgn\n\ncurrent position: [::scidb::pos::fen]"
}


# --- moves played in the board position (the tree) -----------------------
#
# The tree is computed on a worker thread for the current board position in
# the reference base; its progress goes to the command given to tree::init:
# the tree pane's Tick once that pane is built, else ours. The C++ side calls
# that command directly, past execution traces, so with the pane the end of a
# search shows as its Tick setting the search button back to Start (done or
# interrupted alike; tree::finish tells them apart).

namespace eval ::application::assistant {
	variable TreeTimeout 60000
	array set Tree {token {} fen {} timer {} options {}}
}

proc ::application::assistant::DoPositionMoves {limit} {
	variable Tree
	variable TreeTimeout

	if {[string length $Tree(token)]} { return "error: a position search is already running" }
	if {[::scidb::game::query mainvariant?] ne "Normal"} {
		return "move statistics need standard chess"
	}

	# Without a tree database the active one becomes it, and stays: the tree
	# pane follows the switch with a search of its own, which would fail on a
	# base cleared again meanwhile.
	set base [::scidb::tree::get]
	if {![string length $base]} {
		lassign [ActiveBase] base _
		# the core refuses some bases (ChessBase formats, scratch bases), and a
		# tree subscriber may raise while the base is switched; what counts is the switch
		catch { ::scidb::tree::set $base }
		if {[::scidb::tree::get] ne $base} {
			return "error: no tree database is set, and the active database\
				[::util::databaseName $base no] cannot serve as one"
		}
	}

	set Tree(options) [TreeOptions]
	set Tree(fen) [::scidb::pos::fen]
	set Tree(limit) $limit
	set Tree(base) $base
	if {[catch { set done [::scidb::tree::update {*}$Tree(options)] }]} {
		# the tree pane was never built, so nobody receives the progress yet
		::scidb::tree::init ::application::assistant::TreeProgress {}
		if {[catch { set done [::scidb::tree::update {*}$Tree(options)] } err]} {
			return "error: $err"
		}
	}
	set Tree(token) [Later]
	if {$done} {
		after idle [namespace code TreeCollect]
	} else {
		trace add execution ::application::tree::ConfigSearchButton enter ::application::assistant::TreeButton
		set Tree(timer) [after $TreeTimeout [namespace code TreeTimedOut]]
	}
	return $Tree(token)
}


# The tree pane's settings, so its cache serves both.
proc ::application::assistant::TreeOptions {} {
	if {[info exists ::application::tree::Options(rating:type)]} {
		return [list $::application::tree::Options(rating:type) \
			$::application::tree::Options(search:mode) $::application::tree::Options(search:variations)]
	}
	return {Elo exact 0}
}


proc ::application::assistant::TreeProgress {arg n} {
	if {$n == 255 || $n == 0} { after idle [namespace code [list TreeEnded $n]] }
}


# trace on ::application::tree::ConfigSearchButton: {ConfigSearchButton table Start|Stop}
proc ::application::assistant::TreeButton {cmd op} {
	if {[lindex $cmd 2] eq "Start"} { after idle [namespace code TreeCollect] }
}


proc ::application::assistant::TreeEnded {n} {
	variable Tree
	if {![string length $Tree(token)]} { return }
	if {$n == 0} {
		TreeDone "error: the search was interrupted (the database changed or the search was stopped)"
	} else {
		TreeCollect
	}
}


proc ::application::assistant::TreeTimedOut {} {
	variable Tree
	variable TreeTimeout
	set Tree(timer) {}
	TreeDone "error: the search in [::util::databaseName $Tree(base) no] did not finish within\
		[expr {$TreeTimeout/1000}] seconds; it goes on in the tree pane"
}


proc ::application::assistant::TreeCollect {} {
	variable Tree

	if {![string length $Tree(token)]} { return }
	if {[::scidb::pos::fen] ne $Tree(fen)} {
		TreeDone "error: the board moved during the search; ask again"
		return
	}
	if {[catch { ::scidb::tree::finish {*}$Tree(options) -sort 2 } state]} {
		TreeDone "error: $state"
		return
	}
	if {$state eq "null"} {
		TreeDone "error: the search was interrupted (the database changed or the search was stopped)"
		return
	}
	if {[catch { ::scidb::tree::describe } rows]} {
		TreeDone "error: $rows"
		return
	}
	TreeDone [FormatTree $rows $Tree(fen) $Tree(base) $Tree(limit)]
}


proc ::application::assistant::TreeDone {reply} {
	variable Tree

	set token $Tree(token)
	set Tree(token) {}
	catch { after cancel $Tree(timer) }
	set Tree(timer) {}
	catch { trace remove execution ::application::tree::ConfigSearchButton enter ::application::assistant::TreeButton }
	Resolve $token $reply
}


proc ::application::assistant::FormatTree {rows fen base limit} {
	set white [expr {[lindex $fen 1] eq "w"}]
	set side [expr {$white ? "White" : "Black"}]
	set total 0
	foreach row $rows { incr total [dict get $row frequency] }
	set name [::util::databaseName $base no]
	if {!$total} { return "no games in $name reach this position" }

	set rows [lsort -decreasing -command [namespace code CompareFrequency] $rows]
	set lines [list "$total games in $name reach this position; $side to move."]
	foreach row [lrange $rows 0 [expr {$limit - 1}]] {
		lassign [dict get $row result] w b d
		set n [dict get $row frequency]
		set line [format "%s: %d games (%.0f%%)" [Figurines [dict get $row move]] $n [expr {100.0*$n/$total}]]
		if {$w + $b + $d} {
			set score [expr {$white ? [Score $w $d $b] : [Score $b $d $w]}]
			append line [format ", %s scores %.0f%%, draws %.0f%%" $side $score [expr {100.0*$d/($w + $b + $d)}]]
		}
		if {[dict get $row averageRating]} { append line ", average Elo [dict get $row averageRating]" }
		if {[dict get $row lastYear]} { append line ", last played [dict get $row lastYear]" }
		if {[string length [dict get $row bestPlayer]]} {
			append line ", best player [dict get $row bestPlayer]"
			if {[dict get $row bestPlayerRating]} { append line " ([dict get $row bestPlayerRating])" }
		}
		lappend lines "  $line"
	}
	if {[llength $rows] > $limit} { lappend lines "  ... [expr {[llength $rows] - $limit}] more moves" }
	return [join $lines \n]
}


proc ::application::assistant::CompareFrequency {a b} {
	return [expr {[dict get $a frequency] - [dict get $b frequency]}]
}


proc ::application::assistant::DoDatabaseSummary {} {
	lassign [ActiveBase] base variant
	set lines {}
	lappend lines "database: [::util::databaseName $base no] (variant $variant)"
	lappend lines "games: [::scidb::db::count games $base $variant], players: [::scidb::db::count players $base $variant]"

	set rows [lsort -integer -decreasing -index 1 [::scidb::db::ecoStats $base $variant]]
	if {![llength $rows]} { return [join $lines \n] }
	lassign {0 0 0 0} total white draws black
	foreach row $rows {
		lassign $row _ n w d b
		incr total $n; incr white $w; incr draws $d; incr black $b
	}
	lappend lines "games with an ECO code: $total -- [Results $white $draws $black]"
	lappend lines "most played openings:"
	foreach row [lrange $rows 0 9] {
		lassign $row eco n w d b
		lappend lines "  $eco [EcoName $eco $variant]: $n games -- [Results $w $d $b]"
	}
	return [join $lines \n]
}


proc ::application::assistant::DoPlayerStats {name} {
	lassign [ActiveBase] base variant
	lassign [ResolvePlayer $base $variant $name] index name

	lassign [::scidb::db::get playerStats $base $variant $index] \
		dates elo games white black total openings
	lassign $dates first last
	lassign $elo eloMin eloMax
	set lines [list "$name: $games games, $first to $last"]
	if {$eloMax} { lappend lines "Elo: $eloMin to $eloMax" }
	foreach side {White Black total} stats [list $white $black $total] {
		lassign $stats win loss draw pct
		lappend lines [format "%s: %d wins, %d draws, %d losses, score %.1f%%" \
			$side $win $draw $loss [expr {$pct/100.0}]]
	}
	foreach side {White Black} rows $openings {
		if {![llength $rows]} { continue }
		lappend lines "most played with $side:"
		foreach row $rows {
			lassign $row count eco moves
			lappend lines "  $eco [EcoName $eco $variant] ($count games): [Figurines $moves]"
		}
	}
	return [join $lines \n]
}


proc ::application::assistant::DoOpeningScore {range player} {
	lassign [ActiveBase] base variant
	if {$variant ne "Normal"} { return "ECO codes exist only for standard chess, the active variant is $variant" }
	lassign $range from to
	set label [expr {$from eq $to ? "$from [EcoName $from $variant]" : "$from-$to"}]

	if {![string length $player]} {
		lassign [::scidb::db::openingScore $base $variant $from $to] games w d b
		if {!$games} { return "no games with $label" }
		return "$label: $games games -- [Results $w $d $b]"
	}

	lassign [ResolvePlayer $base $variant $player] index name
	lassign [::scidb::db::openingScore $base $variant $from $to $index] games white black
	if {!$games} { return "$name has no games with $label" }
	set lines [list "$name with $label: $games games"]
	foreach side {White Black} wdl [list $white $black] {
		lassign $wdl win draw loss
		set n [expr {$win + $draw + $loss}]
		if {!$n} { continue }
		lappend lines [format "with %s: %d wins, %d draws, %d losses, score %.1f%%" \
			$side $win $draw $loss [expr {100.0*($win + 0.5*$draw)/$n}]]
	}
	return [join $lines \n]
}


# How many lines of each colour, and how many games a line needs to count
# as one of the opponent's weak spots.
namespace eval ::application::assistant {
	variable PrepLines 8
	variable PrepWeakGames 3
	variable PrepGames 10
}

proc ::application::assistant::DoPrepareAgainst {name color} {
	variable PrepLines
	variable PrepWeakGames
	variable PrepGames

	lassign [ActiveBase] base variant
	if {$variant ne "Normal"} { return "opening preparation needs standard chess, the active variant is $variant" }
	lassign [ResolvePlayer $base $variant $name] index name
	lassign [::scidb::db::playerOpenings $base $variant $index] asWhite asBlack

	set lines [list "Preparing against $name"]
	foreach side {white black} rows [list $asWhite $asBlack] {
		if {[string length $color] && $side ne $color} { continue }
		set title [string totitle $side]
		if {![llength $rows]} {
			lappend lines "" "As $title: no games with an ECO code"
			continue
		}
		lassign {0 0 0 0} n w d l
		foreach row $rows {
			lassign $row _ g win draw loss
			incr n $g; incr w $win; incr d $draw; incr l $loss
		}
		lappend lines "" "As $title: $n games, [Wdl $w $d $l]"
		lappend lines "most played:"
		foreach row [lrange $rows 0 [expr {$PrepLines - 1}]] {
			lappend lines "  [OpeningLine $row $variant]"
		}
		# weak spots: lines they play often enough, scoring below their average
		set average [Score $w $d $l]
		set weak {}
		foreach row $rows {
			lassign $row _ g win draw loss
			if {$g >= $PrepWeakGames && [Score $win $draw $loss] < $average} { lappend weak $row }
		}
		set weak [lsort -command [namespace code CompareScore] $weak]
		if {[llength $weak]} {
			lappend lines "weakest (at least $PrepWeakGames games, below their average):"
			foreach row [lrange $weak 0 2] { lappend lines "  [OpeningLine $row $variant]" }
		}
	}

	set games [::scidb::db::playerGames $base $variant $index $PrepGames]
	if {[llength $games]} {
		lappend lines "" "latest games:"
		foreach game $games {
			lassign $game _ date side opponent elo result eco event
			set elo [expr {$elo ? " ($elo)" : ""}]
			lappend lines "  $date as $side vs $opponent$elo: $result $eco, $event"
		}
	}
	return [join $lines \n]
}


proc ::application::assistant::OpeningLine {row variant} {
	lassign $row eco games win draw loss
	return "$eco [EcoName $eco $variant]: $games games, [Wdl $win $draw $loss]"
}


proc ::application::assistant::Wdl {win draw loss} {
	return [format "+%d =%d -%d, score %.1f%%" $win $draw $loss [Score $win $draw $loss]]
}


proc ::application::assistant::Score {win draw loss} {
	set n [expr {$win + $draw + $loss}]
	return [expr {$n ? 100.0*($win + 0.5*$draw)/$n : 0.0}]
}


proc ::application::assistant::CompareScore {a b} {
	set sa [Score {*}[lrange $a 2 4]]
	set sb [Score {*}[lrange $b 2 4]]
	return [expr {$sa < $sb ? -1 : $sa > $sb}]
}


# --- search -----------------------------------------------------------
#
# The model fills in fixed fields; BuildQuery turns them into Scidb's search
# language (tcl_search.cpp), so no query text of the model's reaches it.

namespace eval ::application::assistant {
	variable SearchGames 10
	variable LastSearch {}
}

proc ::application::assistant::DoSearchGames {criteria} {
	variable SearchGames
	variable LastSearch

	lassign [ActiveBase] base variant
	lassign [BuildQuery $base $variant $criteria] query summary
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set rc [catch {
		::scidb::view::search $base $variant $view null none $query
		set count [::scidb::view::count games $base $variant $view]
		set games {}
		for {set row 0} {$row < min($count, $SearchGames)} {incr row} {
			lappend games [GameLine [::scidb::db::get gameNumber $base $variant $row $view] $base $variant]
		}
	} err opts]
	catch { ::scidb::view::close $base $variant $view }
	if {$rc} { return -options $opts $err }

	set LastSearch [list $base $variant $query $summary]
	set lines [list "searched [::util::databaseName $base no] for: $summary" "$count games found"]
	if {$count} {
		lappend lines "first [llength $games]:"
		foreach game $games { lappend lines "  $game" }
	}
	return [join $lines \n]
}


proc ::application::assistant::DoShowSearch {} {
	variable LastSearch

	if {![llength $LastSearch]} { return "error: there is no search to show; call search_games first" }
	lassign $LastSearch base variant query summary
	if {$base ne [lindex [ActiveBase] 0]} {
		return "error: the last search was in [::util::databaseName $base no], which is no longer the active database"
	}
	::scidb::view::search $base $variant 0 null none $query
	::application::switchTab database
	return "the game list shows the [::scidb::view::count games $base $variant 0] games of: $summary"
}


proc ::application::assistant::DoClearSearch {} {
	lassign [ActiveBase] base variant
	::scidb::view::search $base $variant 0 reset none
	return "the game list shows all [::scidb::view::count games $base $variant 0] games again"
}


# {query summary} for checked criteria.
proc ::application::assistant::BuildQuery {base variant criteria} {
	dict with criteria {}
	set common {}
	set summary {}

	if {$player ne ""} {
		lassign [ResolvePlayer $base $variant $player] _ player
		set other ""
		if {$opponent ne ""} { lassign [ResolvePlayer $base $variant $opponent] _ other }
		set sides {}
		foreach side {white black} {
			if {$color ne "any" && $color ne $side} { continue }
			set otherSide [expr {$side eq "white" ? "black" : "white"}]
			# resolved names are exact; a plain pattern (no wildcards) matches exactly
			set terms [list [list playername $side [GlobQuote $player]]]
			if {$other ne ""} { lappend terms [list playername $otherSide [GlobQuote $other]] }
			set won [expr {$side eq "white" ? "1-0" : "0-1"}]
			set lost [expr {$side eq "white" ? "0-1" : "1-0"}]
			switch -- $result {
				win  { lappend terms [list result $won] }
				loss { lappend terms [list result $lost] }
				draw { lappend terms [list result 1/2-1/2] }
			}
			lappend sides [Combine AND $terms]
		}
		lappend common [Combine OR $sides]
		set text "games of $player"
		if {$color ne "any"} { append text " with $color" }
		if {$other ne ""} { append text " against $other" }
		if {$result ne ""} { append text ", [dict get {win won draw drawn loss lost} $result]" }
		lappend summary $text
	} elseif {$result ne ""} {
		lappend common [list result $result]
		lappend summary "result $result"
	}
	if {$eco ne ""} {
		lassign $eco ecoFrom ecoTo
		lappend common [list ecorange $ecoFrom $ecoTo]
		lappend summary [expr {$ecoFrom eq $ecoTo ? "ECO $ecoFrom" : "ECO $ecoFrom-$ecoTo"}]
	}
	if {$from ne "" || $to ne ""} {
		lappend common [list date [expr {$from ne "" ? $from : 1}] [expr {$to ne "" ? $to : 9999}]]
		if {$from eq ""} {
			lappend summary "until $to"
		} elseif {$to eq ""} {
			lappend summary "from $from"
		} else {
			lappend summary "from $from to $to"
		}
	}
	if {$event ne ""} {
		lappend common [list eventname "*$event*"]
		lappend summary "event matching '$event'"
	}
	if {$min_elo ne ""} {
		lappend common [list rating Elo average $min_elo-4000]
		lappend summary "average Elo at least $min_elo"
	}
	return [list [Combine AND $common] [join $summary {; }]]
}


proc ::application::assistant::GlobQuote {text} {
	return [string map {* \\* ? \\? [ \\[ ] \\]} $text]
}


# One term stays itself; AND/OR need two or more.
proc ::application::assistant::Combine {op terms} {
	if {[llength $terms] == 1} { return [lindex $terms 0] }
	return [list $op {*}$terms]
}


proc ::application::assistant::GameLine {index base variant} {
	foreach pair [::scidb::db::get tags $index $base $variant] { dict set tags {*}$pair }
	foreach tag {Date White Black Result ECO Event} {
		set $tag [expr {[dict exists $tags $tag] ? [dict get $tags $tag] : "?"}]
	}
	return "$Date $White - $Black $Result $ECO, $Event"
}


# --- repertoire check, by ECO code --------------------------------------

namespace eval ::application::assistant {
	variable RepLines 8
}

proc ::application::assistant::DoRepertoireCheck {repertoire player color} {
	variable PrepWeakGames
	variable RepLines

	lassign [ActiveBase] base variant
	if {$variant ne "Normal"} { return "the repertoire check needs standard chess, the active variant is $variant" }
	set rep [FindRepertoire $repertoire]
	set type [::scidb::db::get type $rep]
	set side [dict get {OpeningsWhite white OpeningsBlack black Openings ""} $type]
	if {[string length $color]} { set side $color }
	if {![string length $side]} {
		error "[::util::databaseName $rep no] holds both colours: say which side to check (color)"
	}

	# the repertoire's lines by ECO code
	array set lines {}
	foreach row [::scidb::db::ecoStats $rep $variant] {
		lassign $row eco n
		if {$eco ne "?"} { set lines([string range $eco 0 2]) $n }
	}
	if {![array size lines]} { return "[::util::databaseName $rep no] has no games with an ECO code" }

	# practice, from the repertoire's side: {eco games win draw loss}
	if {[string length $player]} {
		lassign [ResolvePlayer $base $variant $player] index who
		lassign [::scidb::db::playerOpenings $base $variant $index] asWhite asBlack
		set rows [expr {$side eq "white" ? $asWhite : $asBlack}]
		set source "$who's games as [string totitle $side]"
	} else {
		if {$base eq $rep} { error "the repertoire is the active database: open the games to check it against, or name a player" }
		set rows {}
		foreach row [::scidb::db::ecoStats $base $variant] {
			lassign $row eco n w d b
			if {$eco eq "?"} { continue }
			lappend rows [expr {$side eq "white" ? [list $eco $n $w $d $b] : [list $eco $n $b $d $w]}]
		}
		set rows [lsort -integer -decreasing -index 1 $rows]
		set source "all games, from [string totitle $side]'s side"
	}

	lassign {0 0 0 0} n w d l
	foreach row $rows {
		lassign $row _ g win draw loss
		incr n $g; incr w $win; incr d $draw; incr l $loss
	}
	set out [list "Repertoire [::util::databaseName $rep no] ([string totitle $side]): [array size lines] ECO codes"]
	lappend out "Checked against $source in [::util::databaseName $base no]: $n games, [Wdl $w $d $l]"
	if {!$n} { return [join $out \n] }
	set average [Score $w $d $l]

	set weak {}
	set gaps {}
	set reached {}
	foreach row $rows {
		lassign $row eco g win draw loss
		if {[info exists lines($eco)]} {
			lappend reached $eco
			if {$g >= $PrepWeakGames && [Score $win $draw $loss] < $average} { lappend weak $row }
		} elseif {$g >= $PrepWeakGames} {
			lappend gaps $row
		}
	}
	set weak [lsort -command [namespace code CompareScore] $weak]

	lappend out "" "Covered, but scoring below the average of [format %.1f $average]%:"
	if {[llength $weak]} {
		foreach row [lrange $weak 0 [expr {$RepLines - 1}]] { lappend out "  [OpeningLine $row $variant]" }
	} else {
		lappend out "  none (with at least $PrepWeakGames games)"
	}
	lappend out "" "Not covered, but reached in at least $PrepWeakGames games:"
	if {[llength $gaps]} {
		foreach row [lrange $gaps 0 [expr {$RepLines - 1}]] { lappend out "  [OpeningLine $row $variant]" }
		if {[llength $gaps] > $RepLines} { lappend out "  ... [expr {[llength $gaps] - $RepLines}] more" }
	} else {
		lappend out "  none"
	}
	set unused [lsort [lmap eco [array names lines] { if {$eco in $reached} continue; set eco }]]
	lappend out "" "In the repertoire, never reached:"
	if {[llength $unused]} {
		foreach eco [lrange $unused 0 [expr {2*$RepLines - 1}]] { lappend out "  $eco [EcoName $eco $variant]" }
		if {[llength $unused] > 2*$RepLines} { lappend out "  ... [expr {[llength $unused] - 2*$RepLines}] more" }
	} else {
		lappend out "  none"
	}
	lappend out "" "(ECO codes only: one code spans many lines, so this finds regions to look at, not moves.)"
	return [join $out \n]
}


# The open repertoire database meant by <text>, or the only one.
proc ::application::assistant::FindRepertoire {text} {
	set bases {}
	foreach base [::scidb::tree::list] {
		if {[catch { ::scidb::db::get type $base } type]} { continue }
		if {$type in {Openings OpeningsWhite OpeningsBlack}} { lappend bases $base }
	}
	if {![llength $bases]} {
		error "no repertoire is open: open a database of type Openings, Openings White or Openings Black"
	}
	if {[string length $text]} {
		set bases [lmap b $bases {
			if {[string first [string tolower $text] [string tolower [::util::databaseName $b no]]] < 0} continue
			set b
		}]
		if {![llength $bases]} { error "no open repertoire matches '$text'" }
	}
	if {[llength $bases] > 1} {
		error "several repertoires are open, say which: [join [lmap b $bases { ::util::databaseName $b no }] {, }]"
	}
	return [lindex $bases 0]
}


# Returns {index name} of the player meant by <text>: an exact (case-insensitive)
# name, or the only one containing it. Otherwise the candidates are raised, so
# the model can ask again with an exact name.
proc ::application::assistant::ResolvePlayer {base variant text} {
	set found [::scidb::db::findPlayers $base $variant $text 11]
	foreach row $found {
		if {[string equal -nocase [lindex $row 1] $text]} { return [lrange $row 0 1] }
	}
	if {[llength $found] == 1} { return [lrange [lindex $found 0] 0 1] }
	if {![llength $found]} { error "no player matching '$text' in [::util::databaseName $base no]" }
	set names {}
	foreach row [lrange $found 0 9] {
		lassign $row _ name games
		lappend names "$name ($games games)"
	}
	if {[llength $found] > 10} { lappend names "..." }
	error "several players match '$text', call again with one exact name: [join $names {; }]"
}


proc ::application::assistant::EcoName {eco variant} {
	set parts [lassign [::scidb::misc::lookup opening $eco $variant] long short]
	set name [::mc::translateEco [expr {[string length $short] ? $short : $long}]]
	foreach part $parts {
		if {[string length $part]} { append name ", " [::mc::translateEco $part] }
	}
	return $name
}


proc ::application::assistant::Results {white draws black} {
	set n [expr {$white + $draws + $black}]
	if {!$n} { return "no results" }
	return [format "white wins %d, draws %d, black wins %d (white scores %.1f%%)" \
		$white $draws $black [expr {100.0*($white + 0.5*$draws)/$n}]]
}


# SAN with piece letters: the model reads "Nf3" better than the figurine "♘f3".
proc ::application::assistant::Figurines {moves} {
	return [string map {\u2654 K \u2655 Q \u2656 R \u2657 B \u2658 N \u265a K \u265b Q \u265c R \u265d B \u265e N} $moves]
}


# --- diagnostics --------------------------------------------------------

# ----------------------------------------------------------------------
# Chess engines: the engine list of ::engine (bundled with Scidb or added
# by the user) and the analysis panes of ::application::analysis. A pane
# is named by the number in its title (1 = "Analysis", 2 = "Analysis (2)"),
# which is not the pane's internal analysis number.
# ======================================================================

# The name of the engine <text> means: its exact name, or the only engine
# whose name or version contains it.
proc ::application::assistant::EngineNamed {text} {
	set text [string trim $text]
	set names [lmap e $::engine::Engines { dict get $e Name }]
	if {![llength $names]} { error "no engine is installed; add one with add_engine" }
	set i [lsearch -nocase -exact $names $text]
	if {$i >= 0} { return [lindex $names $i] }
	set matches {}
	foreach e $::engine::Engines {
		if {   [string match -nocase *$text* [dict get $e Name]]
			 || ([dict exists $e Identifier] && [string match -nocase *$text* [dict get $e Identifier]])} {
			lappend matches [dict get $e Name]
		}
	}
	switch [llength $matches] {
		0 { error "no engine matches '$text'; the engines are: [join $names {, }]" }
		1 { return [lindex $matches 0] }
	}
	error "'$text' matches several engines: [join $matches {, }]; give the exact name"
}


# The analysis number of the pane titled with <label>.
proc ::application::assistant::PaneNumber {label} {
	if {![string is integer -strict $label]
		|| ![info exists ::application::MapTerminalToAnalysis($label)]} {
		set open [lsort -integer [array names ::application::MapTerminalToAnalysis]]
		if {![llength $open]} { error "no analysis pane is open" }
		error "no analysis pane $label; open are: [join $open {, }]"
	}
	return $::application::MapTerminalToAnalysis($label)
}


proc ::application::assistant::PaneLabel {number} {
	return [::application::mapToTerminalNumber $number]
}


# Analysis numbers of the open panes, in title order.
proc ::application::assistant::Panes {} {
	set labels [lsort -integer [array names ::application::MapTerminalToAnalysis]]
	return [lmap l $labels { set ::application::MapTerminalToAnalysis($l) }]
}


proc ::application::assistant::RunningPanes {} {
	return [lmap n [Panes] { if {![::engine::active? $n]} continue; set n }]
}


proc ::application::assistant::EngineEntry {name} {
	set index [::engine::FindIndex $name]
	if {$index == -1} { error "no engine named '$name'" }
	return [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
}


# The protocol Scidb talks to engine <e> (an EngineEntry), and its features.
proc ::application::assistant::EngineFeatures {e} {
	set protocol [dict get $e Protocol]
	set protocol [expr {"UCI" in $protocol ? "UCI" : [lindex $protocol 0]}]
	return [list $protocol [dict get $e Features:$protocol]]
}


proc ::application::assistant::DoListEngines {} {
	set lines {}
	foreach entry $::engine::Engines {
		set e [dict merge $::engine::EmptyEngine $entry]
		lassign [EngineFeatures $e] protocol features
		set line "[dict get $e Name]:"
		if {[dict get $e Identifier] ne "" && [dict get $e Identifier] ne [dict get $e Name]} {
			append line " [dict get $e Identifier],"
		}
		append line [expr {[dict get $e UserDefined] ? " added by the user" : " bundled with Scidb"}]
		append line ", [join [dict get $e Protocol] /]"
		if {[llength [dict get $e Variants]]} { append line ", variants [join [dict get $e Variants] /]" }
		foreach {key label} {Elo Elo CCRL CCRL} {
			if {[dict get $e $key] > 0} { append line ", $label [dict get $e $key]" }
		}
		if {![dict exists $features analyze]} { append line ", cannot analyse" }
		foreach {key label unit} {threads threads "" smp threads "" hashSize hash " MB"} {
			if {[dict exists $features $key] && [llength [dict get $features $key]] == 2} {
				append line ", $label [join [dict get $features $key] -]$unit"
			}
		}
		if {[dict exists $features multiPV]} { append line ", up to [dict get $features multiPV] lines" }
		append line ", program [dict get $e Command]"
		if {![file executable [dict get $e Command]]} { append line " (MISSING)" }
		lappend lines $line
	}
	if {![llength $lines]} { set lines [list "No engine is installed; add one with add_engine."] }

	set panes {}
	foreach number [Panes] {
		set label [PaneLabel $number]
		if {[::engine::active? $number]} {
			set n [llength [::application::analysis::lines $number]]
			lappend panes "pane $label: [::engine::engineName $number] is analysing ($n lines so far)"
		} else {
			lappend panes "pane $label: no engine"
		}
	}
	if {![llength $panes]} { set panes [list "no analysis pane is open"] }
	return "Engines:\n[join $lines \n]\n\nAnalysis panes:\n[join $panes \n]"
}


proc ::application::assistant::DoEngineOptions {engine profile} {
	lassign [::engine::profileOptions $engine $profile] protocol kind options
	if {$kind eq "script"} {
		return "$engine ($protocol) is set up by this script in profile '$profile':\n[join $options \n]"
	}
	set profiles [lmap {p _} [dict get [EngineEntry $engine] Profiles:$protocol] { set p }]
	set lines [list "$engine ($protocol), profile '$profile' (profiles: [join $profiles {, }]):"]
	foreach opt $options {
		lassign $opt name type value dflt var max
		switch $type {
			spin		{ set range "whole number $var-$max" }
			check		{ set range "true/false" }
			combo		{ set range "one of [join [::engine::SplitComboEntries $var] {, }]" }
			default	{ set range $type }
		}
		set line "$name = $value ($range"
		if {$dflt ne $value} { append line ", default $dflt" }
		lappend lines "$line)"
	}
	if {![llength $options]} { lappend lines "(no options)" }
	return [join $lines \n]
}


proc ::application::assistant::DoStartEngine {engine pane lines threads hash} {
	set settings {}
	foreach key {lines threads hash} {
		if {[set $key] ne ""} { dict set settings $key [set $key] }
	}
	set number [expr {$pane ne "" ? [PaneNumber $pane] : ""}]
	set number [::application::analysis::startEngine $engine $number $settings]
	namespace upvar ::engine::$number Vars Vars
	namespace upvar ::application::analysis::$number Options Options
	set n [expr {$Options(engine:singlePV) ? 1 : $Options(engine:multiPV)}]
	return "$engine is analysing the board position in analysis pane [PaneLabel $number]: $n lines,\
		$Vars(current:cores) threads, $Vars(current:memory) MB hash, profile '$Vars(current:profile)'.\
		It follows the board. Read its lines with engine_analysis."
}


proc ::application::assistant::DoEngineAnalysis {pane seconds} {
	set numbers [expr {$pane ne "" ? [list [PaneNumber $pane]] : [RunningPanes]}]
	if {![llength [lmap n $numbers { if {![::engine::active? $n]} continue; set n }]]} {
		return "No engine is running[expr {$pane ne "" ? " in analysis pane $pane" : ""}]. Start one with start_engine."
	}
	if {$seconds == 0} { return [EngineReport $numbers] }
	set token [Later]
	after [expr {$seconds*1000}] [list ::application::assistant::EngineReportLater $token $numbers]
	return $token
}


proc ::application::assistant::EngineReportLater {token numbers} {
	if {[catch { EngineReport $numbers } reply]} { set reply "error: $reply" }
	Resolve $token $reply
}


proc ::application::assistant::EngineReport {numbers} {
	set out [list "Board position: [::scidb::pos::fen]"]
	foreach number $numbers {
		set label [PaneLabel $number]
		if {![::application::analysis::exists? $number] || ![::engine::active? $number]} {
			lappend out "Pane $label: no engine running."
			continue
		}
		set rows [::application::analysis::lines $number]
		set head "Pane $label, [::engine::engineName $number]"
		if {![llength $rows]} {
			lappend out "$head: no lines yet (just started, or paused)."
			continue
		}
		set depth 0
		foreach row $rows { set depth [expr {max($depth, [lindex $row 2])}] }
		lappend out "$head, depth $depth:"
		set i 0
		foreach row $rows {
			lassign $row score mate depth seldepth time nodes nps tbhits pv
			if {$mate} {
				set eval [expr {$mate > 0 ? "#$mate" : "-#[expr {-$mate}]"}]
			} else {
				set eval [format %+.2f [expr {$score/100.0}]]
			}
			set moves [lrange [split [string trim $pv]] 0 23]
			lappend out "  [incr i]. $eval (depth $depth) [join $moves { }]"
		}
	}
	lappend out "Scores are in pawns from White's side; #n: White mates in n, -#n: Black mates in n."
	return [join $out \n]
}


proc ::application::assistant::DoStopEngine {pane} {
	set number [PaneNumber $pane]
	set name [::engine::engineName $number]
	::application::analysis::stopEngine $number
	return "Stopped $name in analysis pane $pane; the pane stays open."
}


proc ::application::assistant::DoSetEngineOption {engine option value profile} {
	::engine::setOption $engine $option $value $profile
	set restarted {}
	foreach number [RunningPanes] {
		namespace upvar ::engine::$number Vars Vars
		if {$Vars(engine:name) ne $engine || $Vars(current:profile) ne $profile} { continue }
		::application::analysis::startAnalysis $number
		lappend restarted [PaneLabel $number]
	}
	set reply "Set $option of $engine (profile '$profile') to $value; saved."
	if {[llength $restarted]} { append reply " Restarted it in analysis pane [join $restarted {, }]." }
	return $reply
}


proc ::application::assistant::DoAddEngine {path} {
	set name [::engine::install $path]
	set e [EngineEntry $name]
	return "Added $name ([dict get $e Identifier], [join [dict get $e Protocol] /]) from $path.\
		Start it with start_engine."
}


proc ::application::assistant::DoRemoveEngine {engine} {
	::engine::remove $engine
	return "Removed $engine from the engine list; its program is still on disk."
}


proc ::application::assistant::DoAppState {} {
	variable ::application::ai::Config
	variable Priv

	set lines {}
	lappend lines "tcl [info patchlevel], tk [package present Tk], windowing [tk windowingsystem]"
	lappend lines "ai: $Config(provider) $Config(model), debug mode $Priv(debug)"
	catch { lappend lines "tab: [lindex [split [.application.nb select] .] end]" }

	set base [::scidb::db::get name]
	set variant [::application::database::currentVariant]
	lappend lines "active database: $base (variant $variant)"
	catch { lappend lines "games in database: [::scidb::db::count games $base $variant]" }
	catch { lappend lines "current position: [::scidb::pos::fen]" }
	catch {
		set pos [::scidb::game::current]
		foreach pair [::scidb::game::tags $pos] { set tags([lindex $pair 0]) [lindex $pair 1] }
		set header {}
		foreach tag {White Black Event Date Result} {
			if {[info exists tags($tag)]} { lappend header "$tag=$tags($tag)" }
		}
		lappend lines "current game (slot $pos): [join $header {, }]"
	}
	catch {
		set twm [::application::twm board]
		lappend lines "board panes: [join [$twm leaves] {, }]"
		set floats {}
		foreach w [$twm floats] { lappend floats [$twm uid $w] }
		if {[llength $floats]} { lappend lines "undocked: [join $floats {, }]" }
	}
	return [join $lines \n]
}


# --- error capture ------------------------------------------------------
# Every error the app reports is recorded, whatever reports it; the app's
# own handling is unchanged.

proc ::application::assistant::RecordError {source message {detail ""}} {
	variable Errors
	variable MaxErrors

	set message [string trim $message]
	if {![string length $message]} { return }
	set now [clock seconds]
	lappend Errors [list [clock format $now -format %T] $source $message $detail]
	if {[llength $Errors] > $MaxErrors} { set Errors [lrange $Errors end-[expr {$MaxErrors - 1}] end] }
	# the log must never become an error of its own
	catch { WriteErrorLog $now $source $message $detail }
	catch { ::application::triage::schedule }
}


proc ::application::assistant::WriteErrorLog {now source message detail} {
	variable ErrorLogFile
	variable MaxErrorLogSize

	if {![string length $ErrorLogFile]} { return }
	file mkdir [file dirname $ErrorLogFile]
	if {[file exists $ErrorLogFile] && [file size $ErrorLogFile] > $MaxErrorLogSize} {
		file rename -force $ErrorLogFile $ErrorLogFile.1
	}
	# one header line per entry; further lines are indented, so the file stays parseable
	set rest [lassign [split $message \n] first]
	set entry "[clock format $now -format {%Y-%m-%d %T}] \[$source\] $first\n"
	foreach line [concat $rest [split [string trim $detail] \n]] {
		if {[string length $line]} { append entry "    " $line \n }
	}
	set fh [open $ErrorLogFile a]
	fconfigure $fh -encoding utf-8
	puts -nonewline $fh $entry
	close $fh
}


# trace on ::scidb::bgerror: {::scidb::bgerror message options}
proc ::application::assistant::TraceBgError {cmd op} {
	# what ::scidb::bgerror itself ignores or only keeps for its next call
	if {[string match {*selection doesn't exist*} [lindex $cmd 1]]} { return }
	if {[info exists ::errorCode] && $::errorCode eq "SCIDB INTERMEDIATE"} { return }
	set opts [lindex $cmd 2]
	set stack [expr {[dict exists $opts -errorinfo] ? [dict get $opts -errorinfo] : $::errorInfo}]
	RecordError background [lindex $cmd 1] $stack
}


# trace on ::log::Print: {Print type show ?callee? message}
proc ::application::assistant::TraceLog {cmd op} {
	set args [lassign $cmd _ type _]
	if {$type ne "Error"} { return }
	switch [llength $args] {
		1 { set message [lindex $args 0]; set callee "" }
		2 { lassign $args callee message }
		default { set message $args; set callee "" }
	}
	# a message may be a list of {text tags} runs
	if {[string index $message 0] eq "\{"} {
		set message [join [lmap run $message { lindex $run 0 }] ""]
	}
	if {[string length $callee]} { set message "\[$callee\] $message" }
	RecordError log $message
}


# trace on ::dialog::alert: {alert -option value ...}
proc ::application::assistant::TraceAlert {cmd op} {
	set opts [lrange $cmd 1 end]
	if {[llength $opts] % 2 || ![dict exists $opts -type] || [dict get $opts -type] ne "error"} { return }
	set detail [expr {[dict exists $opts -detail] ? [dict get $opts -detail] : ""}]
	RecordError dialog [expr {[dict exists $opts -message] ? [dict get $opts -message] : ""}] $detail
}


apply {{} {
	foreach {command handler} {
		::scidb::bgerror	TraceBgError
		::log::Print		TraceLog
		::dialog::alert	TraceAlert
	} {
		if {[llength [info commands $command]]} {
			trace add execution $command enter ::application::assistant::$handler
		}
	}
}}


proc ::application::assistant::DoRecentErrors {count} {
	variable Errors

	if {![llength $Errors]} { return "no errors in this session" }
	set out {}
	foreach e [lrange $Errors end-[expr {$count - 1}] end] {
		lassign $e time source message detail
		lappend out [string trimright "\[$time\] $source: $message\n$detail"]
	}
	return [join $out "\n\n"]
}


proc ::application::assistant::DoToolLog {count} {
	variable ToolLog

	if {![llength $ToolLog]} { return "no tool calls in this session" }
	set out {}
	foreach entry [lrange $ToolLog end-[expr {$count - 1}] end] {
		lassign $entry time name cargs asked outcome reply
		set confirmed [expr {$asked ? ", asked the user" : ""}]
		lappend out "\[$time\] $name [list $cargs]$confirmed: $outcome -- $reply"
	}
	return [join $out \n]
}


proc ::application::assistant::DoTriage {} {
	if {![string length $::application::assistant::ErrorLogFile]} { return "the error log is switched off" }
	if {$::application::triage::Priv(running)} { return "a triage is already running" }
	set n [llength [::application::triage::pending]]
	if {!$n} { return "no new errors to triage" }
	::application::triage::run -done [namespace code TriageDone]
	return "started triage of $n new error group(s); the result is posted here when it is done"
}


proc ::application::assistant::TriageDone {result} {
	if {[dict get $result ok]} {
		set text "Triage: [dict get $result summary]"
	} else {
		set text "Triage failed: [dict get $result error]"
	}
	Append assistant $text
	# The next request knows about it too -- unless one is running, whose tool
	# calls and results must stay together, or the history has no system
	# prompt yet.
	variable Priv
	if {!$Priv(busy) && [llength $Priv(messages)]} {
		lappend Priv(messages) [dict create role assistant content $text]
	}
}


proc ::application::assistant::DoListIssues {} {
	set issues [::application::triage::issues]
	if {![llength $issues]} { return "no issues" }
	return [join [lmap i $issues { lassign $i id severity summary file; set _ "$id ($severity) $summary -- $file" }] \n]
}


proc ::application::assistant::DoHandoff {issue} {
	return [::application::triage::handoff $issue]
}


proc ::application::assistant::DoListProcs {pattern} {
	if {![string match ::* $pattern]} { return "error: use a fully qualified pattern, e.g. ::application::*" }
	set names [lsort [info procs $pattern]]
	# [info procs] does not recurse into child namespaces of a pattern
	if {![llength $names]} {
		set ns [namespace qualifiers $pattern]
		if {[namespace exists $ns]} {
			foreach child [namespace children $ns] {
				lappend names {*}[info procs ${child}::*]
			}
			set names [lsort [lsearch -all -inline -glob $names $pattern]]
		}
	}
	if {![llength $names]} { return "no procedures match $pattern" }
	return [join $names \n]
}


proc ::application::assistant::DoProcSource {name} {
	if {![llength [info procs $name]]} {
		if {[llength [info commands $name]]} { return "$name is a C command, its source is not available" }
		return "error: no procedure $name"
	}
	set args {}
	foreach arg [info args $name] {
		if {[info default $name $arg value]} { lappend args [list $arg $value] } else { lappend args $arg }
	}
	return "proc $name [list $args] {[info body $name]}"
}


proc ::application::assistant::DoReadVariable {name pattern} {
	if {[array exists $name]} {
		set out {}
		foreach key [lsort [array names $name $pattern]] {
			lappend out "$key = [set ${name}($key)]"
		}
		if {![llength $out]} { return "array $name has no elements matching $pattern" }
		return [join $out \n]
	}
	if {![info exists $name]} { return "error: no variable $name" }
	return [set $name]
}


proc ::application::assistant::DoEvalTcl {script} {
	if {[catch { uplevel #0 $script } result opts]} {
		return "error: $result\n[dict get $opts -errorinfo]"
	}
	return "result: $result"
}


proc ::application::assistant::DoSwitchTab {tab} {
	::application::switchTab $tab
	return "switched to the $tab tab"
}


proc ::application::assistant::DoListDatabases {} {
	set current [::scidb::db::get name]
	set switcher [::application::database::switcherWidget]
	set bases [expr {[string length $switcher] ? [$switcher bases] : [list $current]}]
	set lines {}
	foreach base $bases {
		set mark [expr {$base eq $current ? " (active)" : ""}]
		lappend lines "[::util::databaseName $base no]$mark: $base"
	}
	return [join $lines \n]
}


proc ::application::assistant::DoDiscover {} {
	::application::database::discover::open .application
	return "the discovery dialog is open"
}


proc ::application::assistant::DoOpenDatabase {path} {
	set ok [::application::database::openBase .application $path yes \
		-encoding $::encoding::autoEncoding -switchToBase 1]
	return [expr {$ok ? "opened $path" : "could not open $path"}]
}


proc ::application::assistant::DoInstallPhotos {} {
	if {[::util::photos::busy?]} { return "a photo installation is already running" }
	::util::photos::openDialog .application
	return "the photo installer dialog is open; the user completes it"
}


proc ::application::assistant::DoInstallFonts {} {
	if {![llength [info procs ::font::installChessBaseFonts]]} {
		return "font installation is not available on this system"
	}
	::font::installChessBaseFonts .application
	return "the font installer ran"
}


# ----------------------------------------------------------------------
# The pane, built by ::application::BuildPane.
# ======================================================================
proc ::application::assistant::build {frame width height} {
	variable Priv
	variable PaneTitle
	variable mc

	set PaneTitle $::application::twm::mc::Pane(assistant)

	set bottom [ttk::frame $frame.bottom]
	set entry [ttk::entry $bottom.entry]
	set send [ttk::button $bottom.send -text $mc::Send -command [namespace code SendEntry]]
	set clear [ttk::button $bottom.clear -text $mc::Clear -command [namespace code clear]]
	pack $clear -side right -padx {2 4} -pady 4
	pack $send -side right -padx 2 -pady 4
	pack $entry -side left -fill x -expand yes -padx {4 2} -pady 4
	# push to talk, when the machine can actually do it
	set mic {}
	if {[llength [info commands ::application::voice::toggle]]} {
		set mic [ttk::button $bottom.mic -text $::application::voice::mc::Speak \
			-command ::application::voice::toggle]
		pack $mic -side right -padx 2 -pady 4
	}

	set status [ttk::label $frame.status -anchor w -relief sunken -borderwidth 1]

	set sw [ttk::frame $frame.sw]
	set text [tk::text $sw.text -wrap word -width 1 -height 1 -state disabled \
		-borderwidth 0 -padx 6 -pady 4]
	ttk::scrollbar $sw.sb -command [list $text yview]
	$text configure -yscrollcommand [list $sw.sb set]
	pack $sw.sb -side right -fill y
	pack $text -side left -fill both -expand yes

	$text tag configure user -foreground #1f4e8c -spacing1 6
	$text tag configure assistant -spacing1 2
	$text tag configure tool -foreground #707070 -font TkFixedFont
	$text tag configure error -foreground darkred
	$text tag configure info -foreground #707070

	pack $status -side bottom -fill x
	pack $bottom -side bottom -fill x
	pack $sw -fill both -expand yes

	bind $entry <Return> [namespace code SendEntry]

	set Priv(window) $frame
	set Priv(text) $text
	set Priv(entry) $entry
	set Priv(send) $send
	set Priv(status) $status
	if {[llength $mic]} { ::application::voice::attach $mic $status }

	# a rebuilt pane (layout change) replays the conversation
	set replay 0
	foreach m $Priv(messages) {
		switch -- [dict get $m role] {
			user		{ Append user [dict get $m content]; set replay 1 }
			assistant {
				if {[dict exists $m content] && [string length [dict get $m content]]} {
					Append assistant [dict get $m content]
				}
			}
		}
	}
	if {!$replay} { Greet }
	SetBusy $Priv(busy)
}


proc ::application::assistant::activate {frame flag} {}


proc ::application::assistant::closed {frame} {
	variable Priv

	if {$frame ne $Priv(window)} { return }
	foreach key {window text entry send status} { set Priv($key) {} }
}


proc ::application::assistant::Greet {} {
	variable Priv
	variable mc

	Append info $mc::Greeting
	if {$Priv(debug)} { Append info $mc::DebugGreeting }
}


proc ::application::assistant::SendEntry {} {
	variable Priv

	if {![winfo exists $Priv(entry)]} { return }
	set request [$Priv(entry) get]
	if {![string length [string trim $request]] || $Priv(busy)} { return }
	$Priv(entry) delete 0 end
	ask $request
}


proc ::application::assistant::SetBusy {flag} {
	variable Priv
	variable mc

	set Priv(busy) $flag
	if {![winfo exists $Priv(window)]} { return }
	$Priv(send) configure -state [expr {$flag ? "disabled" : "normal"}]
	$Priv(status) configure -text [expr {$flag ? $mc::Thinking : $mc::Ready}]
}


proc ::application::assistant::Append {tag text} {
	variable Priv

	if {![winfo exists $Priv(text)]} { return }
	set prefix [expr {$tag eq "user" ? "> " : ""}]
	$Priv(text) configure -state normal
	$Priv(text) insert end "$prefix$text\n" $tag
	$Priv(text) configure -state disabled
	$Priv(text) see end
}

# ----------------------------------------------------------------------
# Terminal sessions (--ask, --chat): the server end of the protocol in
# ::remote (tcl/exec.tcl). Requests share the conversation with the pane;
# confirmations are asked in the terminal.
# ======================================================================
proc ::application::assistant::attach {chan} {
	variable ::application::ai::Config
	variable Priv

	fconfigure $chan -blocking 0 -buffering line -encoding utf-8
	set Priv(answer:$chan) {}
	Send $chan hello $Config(model) $Priv(debug)
	fileevent $chan readable [namespace code [list RemoteRead $chan]]
}


proc ::application::assistant::Send {chan args} {
	catch { puts $chan [::remote::encodeLine {*}$args] }
}


proc ::application::assistant::RemoteRead {chan} {
	variable Priv

	if {[catch { gets $chan line } n] || $n < 0} {
		if {[catch { eof $chan } eof] || $eof} { RemoteClosed $chan }
		return
	}
	if {[catch { set args [lassign [::remote::decodeLine $line] kind] }]} {
		Send $chan error "garbled request"
		Send $chan ready
		return
	}

	switch -- $kind {
		ask {
			set request [lindex $args 0]
			if {![string length [string trim $request]]} {
				Send $chan error "empty request"
				Send $chan ready
			} elseif {![ask $request \
					-observer [namespace code [list RemoteEvent $chan]] \
					-confirm [namespace code [list RemoteConfirm $chan]]]} {
				Send $chan error "the assistant is busy with another request"
				Send $chan ready
			}
		}
		confirm {
			set Priv(answer:$chan) [expr {[lindex $args 0] ? 1 : 0}]
		}
		clear {
			clear
			Send $chan ready
		}
		default {
			Send $chan error "unknown request '$kind'"
			Send $chan ready
		}
	}
}


proc ::application::assistant::RemoteEvent {chan kind args} {
	Send $chan $kind {*}$args
	if {$kind ne "tool"} { Send $chan ready }
}


proc ::application::assistant::RemoteConfirm {chan what} {
	variable Priv

	set Priv(answer:$chan) {}
	Send $chan confirm $what
	# wait for the terminal; a closed connection counts as "no"
	while {$Priv(answer:$chan) eq ""} {
		vwait [namespace current]::Priv(answer:$chan)
	}
	return $Priv(answer:$chan)
}


proc ::application::assistant::RemoteClosed {chan} {
	variable Priv

	catch { close $chan }
	if {[info exists Priv(answer:$chan)] && $Priv(answer:$chan) eq ""} {
		set Priv(answer:$chan) 0
	}
	# let a pending request finish without reporting to a dead channel
	if {[string match *RemoteEvent*$chan* $Priv(observer)]} { set Priv(observer) {} }
	after idle [list array unset [namespace current]::Priv answer:$chan]
}


# --chat when no instance was running: this instance chats with itself
# from the terminal it was started in, once it is ready.
proc ::application::assistant::StartTerminalChat {} {
	if {![::application::ready?]} {
		after 500 [namespace code StartTerminalChat]
		return
	}
	::remote::assistantClient $::remote::Vars(port) chat {} \
		[list apply {{status args} { puts "(chat closed; $::scidb::app keeps running)" }}]
}

if {[llength [info commands ::process::testOption]] && [::process::testOption chat]} {
	after 1000 ::application::assistant::StartTerminalChat
}

# vi:set ts=3 sw=3:


# ----------------------------------------------------------------------
# Download games from the internet (see ::application::download). The
# download runs in the background; the reply is resolved when it is done.
# ----------------------------------------------------------------------
proc ::application::assistant::DoDownloadGames {source issues lichess url} {
	if {[llength [info commands ::application::download::run]] == 0} {
		return "error: the download module is not available"
	}
	set base [::scidb::db::get name]
	set token [Later]
	if {[catch {
		::application::download::run $base \
			[list -source $source -issues $issues -lichess $lichess -url $url] \
			[namespace code [list DownloadGamesDone $token $base]]
	} err]} {
		after 0 [list Resolve $token "error: $err"]
	}
	return $token
}


proc ::application::assistant::DownloadGamesDone {token base result} {
	if {[dict get $result ok]} {
		set reply "downloaded and imported [dict get $result files] file(s) into [::util::databaseName $base]"
	} else {
		set reply "error: [dict get $result error]"
	}
	catch { Resolve $token $reply }
	return
}


# Put <text> into the entry, for the voice assistant's review mode.
proc ::application::assistant::SetEntry {text} {
	variable Priv

	if {![winfo exists $Priv(entry)]} { return 0 }
	$Priv(entry) delete 0 end
	$Priv(entry) insert 0 $text
	focus $Priv(entry)
	return 1
}


# ----------------------------------------------------------------------
# Annotate the current game (see tcl/ai-annotate.tcl).  The engine pass and
# the drafting take a while, so the tool answers when the run is over.
# ----------------------------------------------------------------------
proc ::application::assistant::DoAnnotateGame {prose marks depth max_plies} {
	if {[llength [info commands ::ai::annotate::annotate]] == 0} {
		return "error: the annotation module is not available"
	}
	if {[::ai::annotate::running?]} {
		return "error: an annotation run is already in progress"
	}
	set token [Later]
	if {[catch {
		::ai::annotate::annotate .application \
			-prose $prose -marks $marks -depth $depth -maxPlies $max_plies \
			-done [namespace code [list AnnotateGameDone $token]]
	} err]} {
		after 0 [list Resolve $token "error: $err"]
		return $token
	}
	return $token
}


proc ::application::assistant::AnnotateGameDone {token result} {
	set reply [dict get $result summary]
	if {[dict get $result written]} {
		append reply "; the game is modified -- save it to keep the comments"
	}
	catch { Resolve $token $reply }
	return
}


# ----------------------------------------------------------------------
# Voice input, as the user sees it.
# ----------------------------------------------------------------------
proc ::application::assistant::DoVoiceStatus {} {
	if {[llength [info commands ::application::voice::status]] == 0} {
		return "the voice assistant is not loaded"
	}
	return [::application::voice::status]
}


# ----------------------------------------------------------------------
# The System One classifier as the user sees it: which backend, whether
# it routes simple requests, and what it decided recently.
# ----------------------------------------------------------------------
proc ::application::assistant::DoClassifierStatus {} {
	set out {}

	if {[llength [info commands ::ai::systemone::describe]]} {
		lappend out "System One decision model: [::ai::systemone::describe]"
		lappend out "  (enabled: [expr {[::ai::systemone::enabled] ? "yes" : "no — nothing is classified"}])"
	} else {
		lappend out "System One decision model: not loaded"
	}

	if {[llength [info commands ::application::assistant::RouteOrStep]]} {
		lappend out "assistant routing: [set ::application::assistant::RouteMode] \
			(route >= [set ::application::assistant::RouteThreshold], satisfied >= \
			[set ::application::assistant::SatisfiedThreshold]; modes: off, shadow, active)"
	} else {
		lappend out "assistant routing: not loaded"
	}

	lappend out "decision models in use: error triage (bug/environment/user/noise),"
	lappend out "  advisory rhetoric/coverage on generated reports, and request routing"
	lappend out "  (SCIDB_AI_ROUTE=active enables the routing fast path)."

	set log [file join [file dirname [LogFile]] route-shadow.log]
	if {[file readable $log]} {
		set ch [open $log]
		set lines [split [string trim [read $ch]] \n]
		close $ch
		set from [expr {max(0, [llength $lines] - 4)}]
		lappend out "recent routing decisions ($log):"
		foreach line [lrange $lines $from end] { lappend out "  $line" }
	} else {
		lappend out "no routing decisions logged yet; with routing in shadow mode they"
		lappend out "appear in route-shadow.log beside the error log."
	}
	return [join $out \n]
}


# The error log's path, for the diagnostics above.
proc ::application::assistant::LogFile {} {
	variable ErrorLogFile
	return $ErrorLogFile
}

# vi:set ts=3 sw=3:
