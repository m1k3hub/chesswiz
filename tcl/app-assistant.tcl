# ======================================================================
# ::application::assistant -- an AI intermediary that operates the app.
#
# The user types a request into the "assistant" pane of the board tab; the
# model answers, and may call tools that map onto existing menu actions.
# The model can only name a tool from the fixed table below, whose
# arguments are checked before anything runs. Every tool that changes
# something asks the user first.
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
	app_state {
		0 0 "report the application state"
		"Report the application state for diagnosis: Tcl/Tk and model versions, the selected tab, the active database and variant, game counts, the current game and position, and the panes of the board layout."
		{{"type":"object","properties":{}}}
		::application::assistant::DoAppState
	}
	recent_errors {
		0 0 "report recent errors"
		"The most recent background errors (message and Tcl stack) raised in this session, newest last."
		{{"type":"object","properties":{"count":{"type":"integer","description":"how many, default 3"}}}}
		::application::assistant::DoRecentErrors
	}
	tool_log {
		0 0 "report recent tool calls"
		"The most recent assistant tool calls of this session, newest last: time, tool, arguments, whether the user was asked, outcome (ok, error, declined) and the start of the reply. Use it to explain what the assistant did or why something failed."
		{{"type":"object","properties":{"count":{"type":"integer","description":"how many, default 10"}}}}
		::application::assistant::DoToolLog
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

# background errors seen in this session: {time message stack}
variable Errors {}
variable MaxErrors 20

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
		Step 0
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

	if {[dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]} {
		lappend Priv(messages) $msg
		foreach call [dict get $msg tool_calls] {
			set fn [dict get $call function]
			set name [dict get $fn name]
			set cargs [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
			set reply [runTool $name $cargs]
			Append tool "$name: $reply"
			Notify tool $name $reply
			lappend Priv(messages) [dict create role tool content $reply tool_name $name]
		}
		if {$round < $Priv(maxRounds)} {
			Step $round
			return
		}
		set msg [dict create role assistant content ""]
	}

	Finish [dict create ok 1 message $msg] $round
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
	if {[llength $observer]} { catch { {*}$observer {*}$event } }
}


# ----------------------------------------------------------------------
# Tool dispatch. Unknown tools and bad arguments are reported back to the
# model as text, never raised: the model can correct itself.
# ======================================================================
proc ::application::assistant::runTool {name cargs} {
	lassign [RunTool $name $cargs] outcome asked reply
	LogToolCall $name $cargs $asked $outcome $reply
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

	if {[catch { set reply [{*}$handler {*}[dict values $checked]] } err]} {
		return [list error $confirm "error: $err"]
	}
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


# Record background errors; the app's own handler still reports them.
proc ::application::assistant::RecordError {cmd op} {
	variable Errors
	variable MaxErrors

	set message [lindex $cmd 1]
	if {![string length $message]} { return }
	set opts [lindex $cmd 2]
	set stack [expr {[dict exists $opts -errorinfo] ? [dict get $opts -errorinfo] : $::errorInfo}]
	lappend Errors [list [clock format [clock seconds] -format %T] $message $stack]
	if {[llength $Errors] > $MaxErrors} { set Errors [lrange $Errors end-[expr {$MaxErrors - 1}] end] }
}

if {[llength [info commands ::scidb::bgerror]]} {
	trace add execution ::scidb::bgerror enter ::application::assistant::RecordError
}


proc ::application::assistant::DoRecentErrors {count} {
	variable Errors

	if {![llength $Errors]} { return "no background errors in this session" }
	set out {}
	foreach e [lrange $Errors end-[expr {$count - 1}] end] {
		lassign $e time message stack
		lappend out "\[$time\] $message\n$stack"
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
