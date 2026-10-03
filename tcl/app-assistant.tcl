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
	database_trend {
		0 0 "narrate the trends of the active database"
		"A read-only narrative of the active database's opening trends: total games, games with an ECO code, the overall results, and the most played openings with their scores and names, grounded in Scidb's own counts (::scidb::db::count and ecoStats). The numbers are read by Scidb; the model only phrases them, and the claim checker audits the phrase. Use it for questions about trends, or what is played most."
		{{"type":"object","properties":{}}}
		::application::assistant::DoDatabaseTrend
	}
	similar_games {
		0 0 "find games like game %s"
		"Find the games of the active database that share the most opening plies with one game and narrate why they are alike. 'number' is the game's number as the game list shows it (the first game is 1); 'limit' bounds how many similar games are reported (default 10). Only games from the same starting position with the same first move qualify, and 'shared' counts the plies of the main line they have in common; transpositions are not found. The games are read by Scidb; the model only phrases the overlap, and the claim checker audits it. Read-only. The result appears in the Report pane."
		{{"type":"object","properties":{"number":{"type":"integer","description":"game number in the active database, as shown in the game list (1 = first game)"},"limit":{"type":"integer","description":"at most this many similar games, default 10"}},"required":["number"]}}
		::application::assistant::DoSimilarGames
	}
	remember_me {
		0 0 "remember that the user is %s"
		"Remember who the user is: their name as it is written in their games, e.g. 'Thomas, Michael'. Call it when the user tells you their name; from then on I, me and my games mean that player. An empty name forgets it."
		{{"type":"object","properties":{"name":{"type":"string","description":"the user's name as written in their games"}},"required":["name"]}}
		::application::assistant::DoRememberMe
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
		"Search the active database; nothing changes, the game list included. Returns the number of games found, the first of them, and the criteria as understood. Names may be partial. 'result' is win/draw/loss from the player's side, or 1-0/0-1/1/2-1/2 without a player. 'eco' is a code, class or range as for opening_score (map opening names to ECO yourself). Dates are YYYY, YYYY.MM or YYYY.MM.DD. To show the games in the game list, call show_search afterwards. 'pattern' keeps only games containing a position pattern (Scidb's CQL matcher reads their moves, which takes longer on a large database)."
		{{"type":"object","properties":{"player":{"type":"string"},"color":{"type":"string","enum":["white","black","any"],"description":"the player's colour, default any"},"result":{"type":"string","enum":["win","draw","loss","1-0","0-1","1/2-1/2"]},"opponent":{"type":"string"},"eco":{"type":"string"},"from":{"type":"string","description":"earliest date"},"to":{"type":"string","description":"latest date"},"event":{"type":"string","description":"part of the event name"},"min_elo":{"type":"integer","description":"minimum average Elo of the two players"},"pattern":{"type":"string","enum":["checkmate","smothered_mate","stalemate","en_passant","underpromotion","double_check","opposite_castling","rook_endgame","pawn_endgame","isolated_queen_pawn","opposite_bishops","queenless"],"description":"a position pattern the game must contain, found by Scidb's CQL matcher: the game ends in checkmate, a smothered mate, the game ends in stalemate, an en-passant capture, an underpromotion, a double check, kings on opposite wings, a rook ending, a pawn ending, an isolated queen's pawn, opposite-coloured bishops, a queenless middlegame"}}}}
		::application::assistant::DoSearchGames
	}
	find_positions {
		0 0 "find positions: %s"
		"Find positions, patterns or tactics in the active database's games with Scidb's CQL 6.2 engine. You translate the request into a CQL 6.2 script; CQL decides what matches. Put only the positional part in 'cql', starting with cql() (e.g. 'cql() mate', 'cql() flipcolor {move from N} attacks k'); put names, colour, result, dates, event, ECO and Elo in the other fields, which narrow the games before any is read. Call cql_help first for the CQL 6.2 reference and worked examples unless the script is trivial. Step 1: mode sample (the default) returns up to 3 matching positions (the move that led there, the game, the FEN) and shows them to the user as diagrams in the Report pane; tell the user in one sentence what you searched for and ask whether these are what they meant. Step 2, only after the user agrees: call again with mode all and the same arguments; the game list then shows every matching game. If the script does not parse you get the parser's message: fix it and call again. Never describe a position's quality yourself."
		{{"type":"object","properties":{"request":{"type":"string","description":"what the user asked for, in their words"},"cql":{"type":"string","description":"the CQL 6.2 script for the positional part, starting with cql()"},"mode":{"type":"string","enum":["sample","all"],"description":"sample (default): up to 3 positions to check with the user; all: every match, shown in the game list"},"player":{"type":"string"},"color":{"type":"string","enum":["white","black","any"],"description":"the player's colour, default any"},"result":{"type":"string","enum":["win","draw","loss","1-0","0-1","1/2-1/2"]},"opponent":{"type":"string"},"eco":{"type":"string"},"from":{"type":"string","description":"earliest date"},"to":{"type":"string","description":"latest date"},"event":{"type":"string","description":"part of the event name"},"min_elo":{"type":"integer","description":"minimum average Elo of the two players"}},"required":["request","cql"]}}
		::application::assistant::DoFindPositions
	}
	find_similar {
		0 0 "find positions like the one on the board"
		"Find positions like the one on the board in the active database's games; the application writes the CQL 6.2 search, so no cql_help is needed. 'aspects' says what must be alike: pawns (the pawn structure, both sides), material (the same pieces), pieces (kings and pieces on the same squares); default pawns alone. The game on the board is left out of the results. 'tolerance' lets up to 0, 1 or 2 pawns per side stand elsewhere (default 0). 'colours' both also finds the structure with the colours reversed. Same two steps as find_positions: mode sample first (the user sees diagrams and the search in the Report pane; ask whether that is what they meant), then mode all. Header fields narrow the games first."
		{{"type":"object","properties":{"aspects":{"type":"array","items":{"type":"string","enum":["pawns","material","pieces"]}},"tolerance":{"type":"integer","description":"0, 1 or 2 pawns per side may stand elsewhere"},"colours":{"type":"string","enum":["same","both"]},"mode":{"type":"string","enum":["sample","all"]},"player":{"type":"string"},"color":{"type":"string","enum":["white","black","any"],"description":"the player's colour, default any"},"result":{"type":"string","enum":["win","draw","loss","1-0","0-1","1/2-1/2"]},"opponent":{"type":"string"},"eco":{"type":"string"},"from":{"type":"string","description":"earliest date"},"to":{"type":"string","description":"latest date"},"event":{"type":"string","description":"part of the event name"},"min_elo":{"type":"integer","description":"minimum average Elo of the two players"}}}}
		::application::assistant::DoFindSimilar
	}
	cql_help {
		0 0 "read the CQL reference"
		"The CQL 6.2 reference card and worked examples (requests a player makes and the scripts that find them). Read it before writing a find_positions script."
		{{"type":"object","properties":{}}}
		::application::assistant::DoCqlHelp
	}
	save_pattern {
		0 0 "save the last position search as pattern '%s'"
		"Save the last find_positions search (the user's request, its CQL script and the sample positions the user accepted) as one of the user's own patterns, under a short name. Only when the user asks to keep or save the search. Saved patterns appear in cql_help as worked examples."
		{{"type":"object","properties":{"name":{"type":"string","description":"a short name, e.g. 'knight fork king and queen'"}},"required":["name"]}}
		::application::assistant::DoSavePattern
	}
	set_position {
		0 0 "set up a position"
		"Put a position on the board in a new game (the game on the board stays as it is): from 'fen', from 'moves' played from the start (e.g. '1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6 6.Bg5'), or moves played from 'fen'. Map an opening the user names to its moves yourself. Every move is checked first; a move that is not legal comes back as an error naming it, and nothing changes."
		{{"type":"object","properties":{"fen":{"type":"string"},"moves":{"type":"string","description":"SAN moves, with or without move numbers"}}}}
		::application::assistant::DoSetPosition
	}
	open_game {
		0 0 "open game %s"
		"Put a game of the active database on the board, at the start or at a move. 'number' is the game number as the tools list it (#123). 'move' is a move number; with 'after' white or black the board shows the position after that side's move, without it the position before White's move."
		{{"type":"object","properties":{"number":{"type":"integer"},"move":{"type":"integer"},"after":{"type":"string","enum":["white","black"]}},"required":["number"]}}
		::application::assistant::DoOpenGame
	}
	open_position {
		0 0 "open position %s of the last search"
		"Put a game found by the last find_positions call on the board, at the matching position. 'index' counts the positions as they were listed, from 1."
		{{"type":"object","properties":{"index":{"type":"integer","description":"1 for the first position listed"}},"required":["index"]}}
		::application::assistant::DoOpenPosition
	}
	show_search {
		0 0 "show the games of the last search in the game list"
		"Filter the game list of the active database to the games of the last search_games, and switch to the database tab."
		{{"type":"object","properties":{}}}
		::application::assistant::DoShowSearch
	}
	clear_search {
		0 0 "show all games in the game list again"
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
	opponent_brief {
		0 0 "build a preparation brief for an opponent"
		"Preparation brief for one opponent from the active database: their openings with both colours and how they score in each, their weakest lines and their latest games, plus a stance for the game (punish their weak line, avoid their theory, out-prepare them, or stay neutral). With 'download' above zero the latest The Week in Chess games are fetched first. The brief opens in the Report pane."
		{{"type":"object","properties":{"name":{"type":"string","description":"the opponent's name or part of it"},"colour":{"type":"string","enum":["white","black"],"description":"the colour the opponent will play"},"download":{"type":"integer","description":"fetch this many latest TWIC issues first, default 0"},"prose":{"type":"boolean","description":"let the language model write the brief, default true"}},"required":["name"]}}
		::application::assistant::DoOpponentBrief
	}
	study_plan {
		0 0 "audit the games and build a study plan"
		"Audit a sample of games in the active database with the chess engine and turn the mistakes into a study plan: every mistake is labelled by pattern (tactics, opening, endgame, king safety, position) from the position facts, and the plan lists the evidence and what to train. 'player' studies one player's games (their moves only); without it both sides of the most recent games are studied. 'games' is how many games to audit (default 10). The report opens in the Report pane."
		{{"type":"object","properties":{"player":{"type":"string","description":"study this player's games, e.g. 'Carlsen, Magnus' or part of the name"},"games":{"type":"integer","description":"how many games to audit, default 10"},"colour":{"type":"string","enum":["white","black","both"],"description":"which side's moves to study, default both"},"depth":{"type":"integer","description":"engine depth per move, default 10"}}}}
		::application::assistant::DoStudyPlan
	}
	structure_profile {
		0 0 "profile the position types of %s"
		"Which kinds of position a player's games reach and how the player scores in them, found exactly by Scidb's CQL matcher in the active database: isolated queen's pawn, opposite-coloured bishops, queenless middlegames, rook and pawn endings, kings on opposite wings. Counts and scores come from the database. 'colour' limits it to the games with that colour; 'games' is how many of the latest games to read (default 200)."
		{{"type":"object","properties":{"player":{"type":"string","description":"the player's name or part of it"},"colour":{"type":"string","enum":["white","black"]},"games":{"type":"integer","description":"how many of the latest games to read, default 200"}},"required":["player"]}}
		::application::assistant::DoStructureProfile
	}
	event_types {
		0 0 "what time controls are the games in"
		"The kinds of time control (classical, rapid, blitz, bullet, correspondence, simul, training) of the latest games in the active database, or of one player's games. A deterministic rule reads the TimeControl tag and the event name; games the rule cannot place are counted as 'unclear' (no model is consulted). Read-only. 'player' limits it to one player; 'games' is how many of the latest games to read (default 500)."
		{{"type":"object","properties":{"player":{"type":"string","description":"the player's name or part of it"},"games":{"type":"integer","description":"how many of the latest games to read, default 500"}}}}
		::application::assistant::DoEventTypes
	}
	detect_language {
		0 0 "detect the language of a comment"
		"Which language a chess comment is written in: a local classifier over a fixed set (English, German, French, Spanish, Italian, Russian, ... plus 'language independent' for notation-only text). Read-only; it does not change the comment, and the comment editor's Detect button applies the result to the current comment."
		{{"type":"object","properties":{"text":{"type":"string","description":"the comment text"}},"required":["text"]}}
		::application::assistant::DoDetectLanguage
	}
	diagnose_import {
		0 0 "diagnose import errors"
		"Turn the codes an import reported (for example 'InvalidMove MissingResultTag') into a likely cause and a fix. A deterministic table covers Scidb's PGN reader codes; a local classifier is asked for codes the table does not know. Read-only; the import log already shows the doctor's rule-only advice."
		{{"type":"object","properties":{"codes":{"type":"array","items":{"type":"string"},"description":"the import error/warning codes"}},"required":["codes"]}}
		::application::assistant::DoDiagnoseImport
	}
	comment_kind {
		0 0 "classify a comment's subject"
		"What a chess annotation comment is about: opening theory, a tactic, the endgame, a plan, an evaluation, a warning, or something else. A deterministic keyword rule answers the obvious cases; a local classifier the rest. Read-only."
		{{"type":"object","properties":{"text":{"type":"string","description":"the comment text"}},"required":["text"]}}
		::application::assistant::DoCommentKind
	}
	novelty_label {
		0 0 "label a move's novelty in the position"
		"Label a move in a position against master practice, grounded in the precedent index: a position the index knows is labelled 'known' without the classifier, and the rest (novelty, side line or transposition) is decided by the local System One classifier; an unsettled move stays 'unknown'. Read-only."
		{{"type":"object","properties":{"fen":{"type":"string","description":"the FEN of the position"},"san":{"type":"string","description":"the move in SAN"}},"required":["fen","san"]}}
		::application::assistant::DoNoveltyLabel
	}
	training_set {
		1 0 "build a training set from the games of the database"
		"Build puzzles from the active database's games: Scidb's CQL matcher finds positions just before a checkmate, a smothered mate, a double check or an underpromotion, and the chess engine keeps only those whose solution is its best move and clearly the only good one. The puzzles are written to a PGN file under the user directory, which the user can open as a database to train. 'pattern' limits it to one kind; 'player' to one player's games; 'max' bounds the number of puzzles (default 20). It runs in the background; the Report pane shows the progress and the result."
		{{"type":"object","properties":{"pattern":{"type":"string","enum":["checkmate","smothered_mate","double_check","underpromotion"]},"player":{"type":"string"},"max":{"type":"integer","description":"at most this many puzzles, default 20"}}}}
		::application::assistant::DoTrainingSet
	}
	check_results {
		1 0 "check the game results and show the games that contradict them"
		"Find the games of the active database whose recorded result contradicts how the game ended: a checkmate scored as a draw or as a win for the mated side, a stalemate scored as a win. Scidb's CQL matcher reads the final positions; nothing is changed. The report lists the games, and the game list is filtered to them (clear_search shows all again)."
		{{"type":"object","properties":{}}}
		::application::assistant::DoCheckResults
	}
	factcheck_annotations {
		0 0 "fact-check the annotations of this game"
		"Check the comments already stored in the game on the board against the positions they describe: an annotation is reported only when the facts (move legality, piece placement, pawn structure) positively contradict it. Use it for the user's own notes, or for annotations that came from a book or another program."
		{{"type":"object","properties":{}}}
		::application::assistant::DoFactCheck
	}
	voice_status {
		0 0 "report the voice assistant status"
		"Whether speaking to the assistant is available: the recorder, the local speech-to-text engine and model, and how replies are spoken. Use it when the user asks about voice input, dictation, or why the microphone button is not there."
		{{"type":"object","properties":{}}}
		::application::assistant::DoVoiceStatus
	}
	transcribe_media {
		0 0 "transcribe the audio of %s"
		"The transcript of a media file (the speech of an audio lesson or a video), as plain text, from the local speech-to-text engine. Read-only; nothing is stored. Use it when the user asks what is said in a lesson, or wants its text. Long transcripts are cut; the answer starts with a short summary."
		{{"type":"object","properties":{"path":{"type":"string","description":"the media file"}},"required":["path"]}}
		::application::assistant::DoTranscribeMedia
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
	ui_state {
		0 1 "inspect the windows, focus and grab"
		"The toplevel windows (state, geometry, title), the focus and the grab holder. A grab held by a window that is not showing or by a menu button whose menu is not posted is flagged as stuck: that is what makes a GUI ignore mouse clicks while menus still work."
		{{"type":"object","properties":{}}}
		::application::assistant::DoUiState
	}
	timers {
		0 1 "list pending timers and open channels"
		"The pending [after] timers (id, kind, script) and the open channels of the interpreter. Use it for a busy or frozen GUI and for leaked timers."
		{{"type":"object","properties":{}}}
		::application::assistant::DoTimers
	}
	loop_health {
		0 1 "report the event-loop health"
		"How long the GUI was unresponsive: the heartbeat of the event loop, the worst stall seen and the recent stalls with their times."
		{{"type":"object","properties":{}}}
		::application::assistant::DoLoopHealth
	}
	media_state {
		0 1 "report the media player state"
		"The media panel and the libmpv player: whether it plays, its state, position, duration and volume, and the last media file."
		{{"type":"object","properties":{}}}
		::application::assistant::DoMediaState
	}
	child_processes {
		0 1 "list the child processes"
		"The processes started by this program (helpers, leftover players)."
		{{"type":"object","properties":{}}}
		::application::assistant::DoChildProcesses
	}
	hang_dumps {
		0 1 "read the hang dumps"
		"The stack dumps written when the program stalled (kill -USR1, or the watchdog started by debug mode): the Tcl stack of the stalled code, the pending timers and the window state. Read the newest first."
		{{"type":"object","properties":{"count":{"type":"integer","description":"how many files to list, default 3"}}}}
		::application::assistant::DoHangDumps
	}
	release_grab {
		1 1 "release the input grab held by %s"
		"Release the grab held by a window, which frees a GUI that ignores clicks. Only for a holder ui_state flagged as stuck, and only when the user asks for it."
		{{"type":"object","properties":{"window":{"type":"string","description":"the grab holder's window path"}},"required":["window"]}}
		::application::assistant::DoReleaseGrab
	}
	cancel_timer {
		1 1 "cancel the timer %s"
		"Cancel a pending [after] timer by its id as listed by timers. Only when the user asks for it."
		{{"type":"object","properties":{"id":{"type":"string","description":"the timer id, e.g. after#12"}},"required":["id"]}}
		::application::assistant::DoCancelTimer
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
invent statistics; a short list is fine there. When a tool reply ends with a
"menu:" line, end your answer with that path in parentheses, e.g. "(also in:
Database tab > ...)", so the user learns where the feature lives.}

variable DebugSystem {
You are also a debugging aid for the developer of Scidb (Tcl/Tk front end
over a C++ core). When asked about a problem, gather facts with the tools
(app_state, recent_errors, tool_log, ui_state, timers, loop_health, media_state,
child_processes, hang_dumps, list_procs, proc_source, read_variable) before
answering, cite procedure names and the evidence you saw, and say plainly
what you could not verify. Longer answers are fine in this role.
A GUI that ignores mouse clicks while menus still work usually has a stuck grab:
check ui_state. A frozen or stalling GUI: read hang_dumps and loop_health.
release_grab and cancel_timer change the running program; use them only when the
user asks, after the evidence shows what is stuck.}

# Replies longer than this are cut, so one tool cannot flood the context.
variable MaxReply 6000

# Where a tool's feature lives in the menus: added to its reply as a
# "menu:" line, which the model passes on (ASSISTANT_COVERAGE_MAP.md P2).
variable ToolMenu {
	search_games	"Database tab > right-click the database > Maintenance > Advanced Search"
	show_search		"Database tab > right-click the database > Maintenance > Advanced Search"
	find_positions	"Database tab > right-click the database > Maintenance > CQL 6.2 Search (with the script above)"
	find_similar	"Database tab > right-click the database > Maintenance > CQL 6.2 Search (with the script above)"
	open_game		"Database tab > double-click the game in the game list"
	set_position	"Board tab > right-click the board > Set Start Board..."
	player_stats	"Players tab > right-click the player > Show Player Card"
	prepare_against	"Players tab > right-click the player > Show Prep Report"
	opening_score	"Board tab > Tree pane"
	position_moves	"Board tab > Tree pane"
}
# tools whose whole reply the model needs (the CQL reference: a cut card
# loses examples and the user's patterns)
variable MaxReplyFor {cql_help 20000}

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
		# who 'me' is, per request, from the private player card
		set me [MePrompt]
		if {[string length $me]} { append system \n $me }
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
	set Priv(cqlHelp) 0
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


# The system prompt's sentence about who the user is. The name is the one
# the user gave the assistant (remember_me, saved with the AI settings), or
# the private player card's if it is ever filled in (its dialog is not
# finished, see tcl/player-card.tcl). Read per request; a missing setting
# or card never breaks a request.
proc ::application::assistant::MePrompt {} {
	set name ""
	catch { set name [string trim $::application::ai::Settings(me)] }
	if {$name eq ""} { catch { set name [string trim $::playercard::Var(Name)] } }
	if {$name eq ""} {
		return "The user's name is not known. If the user says I, me or my games, ask for their name as written in their games and call remember_me with it."
	}
	return "The user is $name. When the user says I, me or my games, use the player name $name in tool arguments."
}


proc ::application::assistant::DoRememberMe {name} {
	set ::application::ai::Settings(me) $name
	if {$name eq ""} { return "Forgotten: the user's name is no longer known." }
	return "Remembered: the user is $name. I, me and my games now mean $name."
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
		# closed-set arguments are more reliable from the classifier than from
		# the model's emitted JSON (app-assistant-args.tcl)
		if {[llength [info commands ::application::assistant::correctArgs]]} {
			catch { set cargs [::application::assistant::correctArgs $name $cargs] }
		}
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


proc ::application::assistant::WithMenu {name reply} {
	variable ToolMenu
	if {![dict exists $ToolMenu $name] || [string match "error: *" $reply]} { return $reply }
	return "$reply\nmenu: [dict get $ToolMenu $name]"
}


proc ::application::assistant::ReplyLimit {name} {
	variable MaxReply
	variable MaxReplyFor
	return [expr {[dict exists $MaxReplyFor $name] ? [dict get $MaxReplyFor $name] : $MaxReply}]
}


# Returns 0 when nothing waits for <token> (the request ended meanwhile).
proc ::application::assistant::Resolve {token reply} {
	variable Priv
	variable MaxReply

	if {![info exists Priv(pending)] || [lindex $Priv(pending) 0] ne $token} { return 0 }
	lassign $Priv(pending) _ round name cargs calls isRouted
	set Priv(pending) {}
	set reply [WithMenu $name [Scrub $reply]]
	set limit [ReplyLimit $name]
	if {[string length $reply] > $limit} {
		set reply "[string range $reply 0 $limit-1]\n... (truncated)"
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
	set reply [WithMenu $name [Scrub $reply]]
	set limit [ReplyLimit $name]
	if {[string length $reply] > $limit} {
		set reply "[string range $reply 0 $limit-1]\n... (truncated)"
	}
	return [list ok $confirm $reply]
}


# No tool reply may carry a credential out to the model (it may be a cloud
# model): the values of environment variables that name one are replaced.
proc ::application::assistant::Scrub {text} {
	if {[llength [info commands ::application::diagnose::scrub]]} {
		return [::application::diagnose::scrub $text]
	}
	return $text
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
		hang_dumps {
			set count 3
			if {[dict exists $cargs count]} { set count [dict get $cargs count] }
			if {![string is integer -strict $count] || $count < 1} { error "count must be a positive integer" }
			return [dict create count $count]
		}
		release_grab {
			set window [string trim [Arg $cargs window]]
			if {$window ni [grab current]} { error "$window holds no grab (holders: [grab current])" }
			return [dict create window $window]
		}
		cancel_timer {
			set id [string trim [Arg $cargs id]]
			if {$id ni [after info]} { error "no pending timer $id" }
			return [dict create id $id]
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
		transcribe_media {
			set path [Arg $cargs path]
			if {![file isfile $path]} { error "no such file: $path" }
			return [dict create path [file normalize $path]]
		}
		search_games {
			set c {}
			foreach key {player color result opponent eco from to event min_elo pattern} {
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
				if {$pattern ne "" && ([llength [info commands ::ai::search::patternIds]] == 0
				 || $pattern ni [::ai::search::patternIds])} {
					error "pattern must be one of: [join [expr {[llength [info commands ::ai::search::patternIds]]
						? [::ai::search::patternIds] : {}}] {, }]"
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
		remember_me {
			return [dict create name [string trim [Arg $cargs name]]]
		}
		find_positions {
			set request [string trim [Arg $cargs request]]
			set cql [string trim [Arg $cargs cql]]
			if {$cql eq ""} { error "cql must not be empty" }
			set mode [expr {[dict exists $cargs mode] ? [string tolower [string trim [dict get $cargs mode]]] : "sample"}]
			if {$mode eq ""} { set mode sample }
			if {$mode ni {sample all}} { error "mode must be sample or all" }
			return [dict create request $request cql $cql mode $mode criteria [HeaderCriteria $cargs]]
		}
		find_similar {
			set aspects [expr {[dict exists $cargs aspects] ? [dict get $cargs aspects] : {}}]
			if {![llength $aspects]} { set aspects {pawns} }
			foreach a $aspects {
				if {$a ni {pawns material pieces}} { error "aspects are pawns, material and pieces" }
			}
			set tolerance [expr {[dict exists $cargs tolerance] ? [dict get $cargs tolerance] : 0}]
			if {$tolerance eq ""} { set tolerance 0 }
			if {![string is integer -strict $tolerance] || $tolerance < 0 || $tolerance > 2} {
				error "tolerance must be 0, 1 or 2"
			}
			set colours [expr {[dict exists $cargs colours] ? [string tolower [dict get $cargs colours]] : "same"}]
			if {$colours eq ""} { set colours same }
			if {$colours ni {same both}} { error "colours must be same or both" }
			set mode [expr {[dict exists $cargs mode] ? [string tolower [string trim [dict get $cargs mode]]] : "sample"}]
			if {$mode eq ""} { set mode sample }
			if {$mode ni {sample all}} { error "mode must be sample or all" }
			return [dict create aspects [lsort -unique $aspects] tolerance $tolerance colours $colours \
				mode $mode criteria [HeaderCriteria $cargs]]
		}
		save_pattern {
			set name [string trim [Arg $cargs name]]
			if {$name eq ""} { error "name must not be empty" }
			return [dict create name $name]
		}
		set_position {
			set fen [expr {[dict exists $cargs fen] ? [string trim [dict get $cargs fen]] : ""}]
			set moves [expr {[dict exists $cargs moves] ? [string trim [dict get $cargs moves]] : ""}]
			if {$fen eq "" && $moves eq ""} { error "give a fen, moves or both" }
			return [dict create fen $fen moves $moves]
		}
		open_game {
			set number [Arg $cargs number]
			if {![string is integer -strict $number] || $number < 1} { error "number must be a game number, 1 or more" }
			set move [expr {[dict exists $cargs move] ? [dict get $cargs move] : ""}]
			if {$move ne "" && (![string is integer -strict $move] || $move < 1)} { error "move must be 1 or more" }
			set after [expr {[dict exists $cargs after] ? [string tolower [dict get $cargs after]] : ""}]
			if {$after ni {"" white black}} { error "after must be white or black" }
			if {$after ne "" && $move eq ""} { error "after needs a move" }
			return [dict create number $number move $move after $after]
		}
		open_position {
			set index [Arg $cargs index]
			if {![string is integer -strict $index] || $index < 1} { error "index must be 1 or more" }
			return [dict create index $index]
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
		opponent_brief {
			set name [string trim [Arg $cargs name]]
			if {![string length $name]} { error "name must not be empty" }
			set colour [OptArg $cargs colour ""]
			if {$colour ni {white black ""}} { error "colour must be 'white' or 'black'" }
			set download [OptArg $cargs download 0]
			if {![string is integer -strict $download] || $download < 0 || $download > 12} {
				error "download must be an integer between 0 and 12"
			}
			set prose 1
			if {[dict exists $cargs prose]} {
				set prose [expr {[string is true -strict [dict get $cargs prose]] ? 1 : 0}]
			}
			return [dict create name $name colour $colour download $download prose $prose]
		}
		study_plan {
			set player [OptArg $cargs player ""]
			set games [OptArg $cargs games 10]
			if {![string is integer -strict $games] || $games < 1 || $games > 200} {
				error "games must be an integer between 1 and 200"
			}
			set colour [OptArg $cargs colour both]
			if {$colour ni {white black both}} { error "colour must be 'white', 'black' or 'both'" }
			set depth [OptArg $cargs depth 10]
			if {![string is integer -strict $depth] || $depth < 4 || $depth > 30} {
				error "depth must be an integer between 4 and 30"
			}
			return [dict create player $player games $games colour $colour depth $depth]
		}
		factcheck_annotations {
			return {}
		}
		database_trend {
			return {}
		}
		similar_games {
			set number [string trim [Arg $cargs number]]
			if {![string is integer -strict $number] || $number < 1} {
				error "number must be a positive integer (the game list's number, 1 = first game)"
			}
			set limit [string trim [OptArg $cargs limit 10]]
			if {![string is integer -strict $limit] || $limit < 1} {
				error "limit must be a positive integer"
			}
			return [dict create number $number limit $limit]
		}
		structure_profile {
			set player [string trim [Arg $cargs player]]
			if {$player eq ""} { error "player is required" }
			set colour [OptArg $cargs colour ""]
			if {$colour ni {"" white black}} { error "colour must be 'white' or 'black'" }
			set games [OptArg $cargs games 200]
			if {![string is integer -strict $games] || $games < 1 || $games > 5000} {
				error "games must be an integer between 1 and 5000"
			}
			return [dict create player $player colour $colour games $games]
		}
		event_types {
			set games [OptArg $cargs games 500]
			if {![string is integer -strict $games] || $games < 1 || $games > 10000} {
				error "games must be an integer between 1 and 10000"
			}
			return [dict create player [string trim [OptArg $cargs player ""]] games $games]
		}
		detect_language {
			set text [Arg $cargs text]
			if {[string trim $text] eq ""} { error "text is required" }
			return [dict create text $text]
		}
		diagnose_import {
			set codes [Arg $cargs codes]
			if {![llength $codes]} { error "codes is required" }
			return [dict create codes $codes]
		}
		comment_kind {
			set text [Arg $cargs text]
			if {[string trim $text] eq ""} { error "text is required" }
			return [dict create text $text]
		}
		novelty_label {
			set fen [string trim [Arg $cargs fen]]
			if {$fen eq ""} { error "fen is required" }
			set san [string trim [Arg $cargs san]]
			if {$san eq ""} { error "san is required" }
			return [dict create fen $fen san $san]
		}
		training_set {
			set pattern [OptArg $cargs pattern ""]
			if {$pattern ni {"" checkmate smothered_mate double_check underpromotion}} {
				error "pattern must be checkmate, smothered_mate, double_check or underpromotion"
			}
			set max [OptArg $cargs max 20]
			if {![string is integer -strict $max] || $max < 1 || $max > 200} {
				error "max must be an integer between 1 and 200"
			}
			return [dict create pattern $pattern player [string trim [OptArg $cargs player ""]] max $max]
		}
		check_results {
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


proc ::application::assistant::DoDatabaseTrend {} {
	if {[llength [info commands ::ai::trend::narrate]] == 0} {
		return "error: the trend module is not available"
	}
	lassign [ActiveBase] base variant
	if {$base eq ""} { return "error: no active database" }
	set facts [::ai::trend::facts $base $variant]
	set token [Later]
	::ai::trend::narrate .application $facts \
		-done [namespace code [list DatabaseTrendDone $token]]
	return $token
}


proc ::application::assistant::DatabaseTrendDone {token result} {
	Resolve $token [dict get $result text]
}


proc ::application::assistant::DoSimilarGames {number limit} {
	if {[llength [info commands ::ai::similar::report]] == 0} {
		return "error: the similar-games module is not available"
	}
	lassign [ActiveBase] base variant
	if {$base eq ""} { return "error: no active database" }
	if {$number > [::scidb::db::count games $base $variant]} {
		return "error: the database has only [::scidb::db::count games $base $variant] games"
	}
	set token [Later]
	::ai::similar::report .application $base $variant [expr {$number - 1}] -limit $limit \
		-done [namespace code [list SimilarGamesDone $token]]
	return $token
}


proc ::application::assistant::SimilarGamesDone {token result} {
	Resolve $token [dict get $result text]
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
	variable LastSearchCriteria {}
}

proc ::application::assistant::DoSearchGames {criteria} {
	variable SearchGames
	variable LastSearch
	variable LastSearchCriteria

	lassign [ActiveBase] base variant
	lassign [BuildQuery $base $variant $criteria] query summary
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set rc [catch {
		lassign [SearchView $base $variant $view $criteria] query summary count
		set games {}
		for {set row 0} {$row < min($count, $SearchGames)} {incr row} {
			set number [::scidb::db::get gameNumber $base $variant $row $view]
			lappend games "#[expr {$number + 1}] [GameLine $number $base $variant]"
		}
	} err opts]
	catch { ::scidb::view::close $base $variant $view }
	if {$rc} { return -options $opts $err }

	set LastSearch [list $base $variant $query $summary]
	set LastSearchCriteria $criteria
	set lines [list "searched [::util::databaseName $base no] for: $summary" "$count games found"]
	if {$count} {
		lappend lines "first [llength $games]:"
		foreach game $games { lappend lines "  $game" }
	}
	return [join $lines \n]
}


proc ::application::assistant::DoShowSearch {} {
	variable LastSearch
	variable LastSearchCriteria

	if {![llength $LastSearch]} { return "error: there is no search to show; call search_games first" }
	ForgetMatchPositions
	lassign $LastSearch base variant query summary
	if {$base ne [lindex [ActiveBase] 0]} {
		return "error: the last search was in [::util::databaseName $base no], which is no longer the active database"
	}
	if {$LastSearchCriteria ne ""} {
		SearchView $base $variant 0 $LastSearchCriteria
	} else { ::scidb::view::search $base $variant 0 null none $query }
	::application::switchTab database
	return "the game list shows the [::scidb::view::count games $base $variant 0] games of: $summary"
}


proc ::application::assistant::DoClearSearch {} {
	ForgetMatchPositions
	lassign [ActiveBase] base variant
	::scidb::view::search $base $variant 0 reset none
	return "the game list shows all [::scidb::view::count games $base $variant 0] games again"
}


# {query summary} for checked criteria.
proc ::application::assistant::BuildQuery {base variant criteria {includePattern 1}} {
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
	# a position pattern last: its games are decoded, so the terms above
	# narrow them first
	if {[info exists pattern] && $pattern ne ""} {
		set p [::ai::search::pattern $pattern]
		if {$includePattern} { lappend common [list cql [dict get $p cql]] }
		lappend summary "with [dict get $p label]"
	}
	return [list [Combine AND $common] [join $summary {; }]]
}

# Validated fields narrow the view first. The model supplies a library id;
# only application-owned templates reach the native CQL 6.2 engine.
proc ::application::assistant::SearchView {base variant view criteria {callback {}} {guard {}}} {
    set use6 [expr {$variant eq "Normal" && [dict exists $criteria pattern]
        && [dict get $criteria pattern] ne "" && [llength [info commands ::scidb::cql6::search]]
        && [::scidb::cql6::version] ne "cql6 stub 6.2"}]
    lassign [BuildQuery $base $variant $criteria [expr {!$use6}]] query summary
    if {$query eq "AND"} {
        ::scidb::view::search $base $variant $view reset none
    } else { ::scidb::view::search $base $variant $view null none $query }
    if {$use6} {
        set script [::ai::search::pattern6 [dict get $criteria pattern]]
        if {$callback ne ""} {
            return [::scidb::cql6::search $base $variant $script -view $view -compact 1 -command \
                [list ::application::assistant::PatternSearchFinished $base $variant $view $query $summary $callback $guard]]
        }
        # Assistant tools keep their return-value contract while the nested event
        # loop services GUI timers and native snapshot requests.
        variable PatternWaitSerial
        variable PatternWait
        if {![info exists PatternWaitSerial]} {set PatternWaitSerial 0}
        set token [incr PatternWaitSerial]
        set done [list ::application::assistant::PatternSearchWait $token]
        ::scidb::cql6::search $base $variant $script -view $view -compact 1 -command \
            [list ::application::assistant::PatternSearchFinished $base $variant $view $query $summary $done {}]
        vwait [namespace current]::PatternWait($token)
        set result $PatternWait($token)
        unset PatternWait($token)
        if {![dict get $result ok]} {error [dict get $result error]}
        return [list $query $summary [dict get $result count]]
    }
    if {$callback ne ""} {
        after idle [list ::application::assistant::PatternSearchNotify $callback $guard \
            [dict create ok 1 query $query summary $summary count [::scidb::view::count games $base $variant $view]]]
        return {}
    }
    return [list $query $summary [::scidb::view::count games $base $variant $view]]
}

proc ::application::assistant::PatternSearchWait {token result} {
    variable PatternWait
    set PatternWait($token) $result
}
proc ::application::assistant::PatternSearchNotify {callback guard result} {
    if {$guard ne "" && ![uplevel #0 $guard]} {return}
    uplevel #0 [list {*}$callback $result]
}
proc ::application::assistant::PatternSearchFinished {base variant view query summary callback guard result} {
    if {$guard ne "" && ![uplevel #0 $guard]} {return}
    if {![dict get $result ok]} {
        set answer [dict create ok 0 error [dict get $result error]]
    } elseif {[dict get $result cancelled]} {
        set answer [dict create ok 0 error "Pattern search cancelled"]
    } elseif {[catch {
        set games [lmap {game ply} [dict get $result matches] {set game}]
        set count [::scidb::view::setGames $base $variant $view $games]
    } error]} {set answer [dict create ok 0 error $error]} else {
        set answer [dict create ok 1 query $query summary $summary count $count]
    }
    PatternSearchNotify $callback {} $answer
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


# --- position finder (ASSISTANT_COVERAGE_MAP.md §5) ----------------------

# The header fields of a position search, checked as search_games checks
# them; {} when none is given.
proc ::application::assistant::HeaderCriteria {cargs} {
	set header [dict create pattern ""]
	foreach key {player color result opponent eco from to event min_elo} {
		if {[dict exists $cargs $key] && [string trim [dict get $cargs $key]] ni {"" any}} {
			dict set header $key [dict get $cargs $key]
		}
	}
	if {[dict size $header] == 1} { return {} }
	return [dict get [CheckArgs search_games $header] criteria]
}

namespace eval ::application::assistant {
	# {base variant {game ply ...}} of the last find_positions call
	variable LastPositions {}
	# {request cql fens} of the last find_positions call
	variable LastFind {}
	variable PositionSamples 3
	variable PositionsShown 10
	# milliseconds before a search stops with what it found
	variable ProbeBudget 30000
	variable SearchBudget 600000
}


proc ::application::assistant::DoFindPositions {request cql mode criteria} {
	variable Priv

	# models know little CQL; the reference makes the scripts right
	if {![info exists Priv(cqlHelp)] || !$Priv(cqlHelp)} {
		return "error: call cql_help first and write the script from its reference and examples; then call find_positions again"
	}
	return [FindPositions $request $cql $mode $criteria]
}


# Positions like the one on the board: the application writes the script
# (tcl/ai-similar-positions.tcl), so no reference is needed.
proc ::application::assistant::DoFindSimilar {aspects tolerance colours mode criteria} {
	if {![llength [info commands ::ai::similar::script]]} {
		return "error: finding similar positions is not available in this build"
	}
	set fen [::scidb::pos::fen]
	set opts [list -aspects $aspects -tolerance $tolerance -colours $colours]
	if {[catch { ::ai::similar::script $fen {*}$opts } cql]} { return "error: $cql" }
	set what [::ai::similar::describe $fen {*}$opts]
	# the game on the board matches itself; leave it out
	set exclude -1
	catch {
		lassign [::scidb::game::link?] linkBase linkVariant linkIndex
		if {$linkBase eq [lindex [ActiveBase] 0] && $linkIndex >= 0} { set exclude $linkIndex }
	}
	set loosen "nothing else matches: offer a looser search, e.g. tolerance 1 or 2, or fewer aspects (pawns alone)"
	return [FindPositions "positions like the one on the board: $what" $cql $mode $criteria $exclude $loosen]
}


# <exclude> is a game index left out of the results (-1: none); <loosen>
# is what to tell the model when nothing matches.
proc ::application::assistant::FindPositions {request cql mode criteria {exclude -1} {loosen ""}} {
	variable PositionSamples
	variable ProbeBudget
	variable SearchBudget

	if {![llength [info commands ::scidb::cql6::search]] || [::scidb::cql6::version] eq "cql6 stub 6.2"} {
		return "error: the CQL 6.2 engine is not available in this build"
	}
	lassign [ActiveBase] base variant
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set summary "all games"
	if {[catch {
		if {[llength $criteria]} {
			lassign [BuildQuery $base $variant $criteria 0] query summary
			::scidb::view::search $base $variant $view null none $query
		} else {
			::scidb::view::search $base $variant $view reset none
		}
	} err]} {
		catch { ::scidb::view::close $base $variant $view }
		return "error: $err"
	}
	set narrowed [::scidb::view::count games $base $variant $view]
	if {$narrowed == 0} {
		catch { ::scidb::view::close $base $variant $view }
		return "no games of [::util::databaseName $base no] match the header fields ($summary); nothing was searched"
	}

	set token [Later]
	set sample [expr {$mode eq "sample"}]
	::ai::positions::search $base $variant $view $cql \
		[namespace code [list PositionsDone $token $base $variant $view $mode $request $cql $summary $narrowed $exclude $loosen]] \
		-max [expr {$sample ? $PositionSamples + ($exclude >= 0) : 0}] -budget [expr {$sample ? $ProbeBudget : $SearchBudget}]
	return $token
}


proc ::application::assistant::PositionsDone {token base variant view mode request cql summary narrowed exclude loosen result} {
	variable LastPositions
	variable PositionsShown

	catch { ::scidb::view::close $base $variant $view }
	if {![dict get $result ok]} {
		Resolve $token "error: CQL 6.2 did not run the script: [dict get $result error]\nFix the script and call find_positions again."
		return
	}
	variable LastFind
	set pairs {}
	foreach {game ply} [dict get $result matches] {
		if {$game != $exclude} { lappend pairs $game $ply }
	}
	variable PositionSamples
	if {$mode eq "sample"} { set pairs [lrange $pairs 0 [expr {2 * $PositionSamples - 1}]] }
	set complete [dict get $result complete]
	set LastPositions [list $base $variant $pairs]
	set found [expr {[llength $pairs] / 2}]
	set where "[::util::databaseName $base no], $summary ($narrowed games)"

	if {$mode eq "all"} {
		set games [lsort -integer -unique [lmap {game ply} $pairs { set game }]]
		if {[catch {
			::scidb::view::search $base $variant 0 reset none
			set count [::scidb::view::setGames $base $variant 0 $games]
			# a double-click in the game list opens a game at its match
			catch { ::gamestable::setPositionLookup ::application::assistant::MatchPosition }
			::application::switchTab database
		} err]} {
			Resolve $token "error: $err"
			return
		}
		set lines [list "searched $where for: $request" \
			"$count games with a matching position[expr {$complete ? "" : " (the search stopped early; there may be more)"}][expr {$exclude >= 0 ? " (the game on the board left out)" : ""}]" \
			"the game list shows them; a double-click opens a game at the matching position, and open_position N puts the Nth on the board there"]
	} else {
		set lines [list "searched $where for: $request"]
		if {!$found} {
			lappend lines [expr {$complete ? "no position matches" : "no match within the time limit; the script may be too strict or match nothing"}]
			if {$loosen ne ""} { lappend lines $loosen }
		} else {
			lappend lines "sample positions (the user sees them as diagrams in the Report pane):"
		}
	}

	set samples {}
	set i 0
	foreach {game ply} $pairs {
		if {[incr i] > $PositionsShown} { break }
		if {[catch { ::ai::positions::position $base $variant $game $ply } pos]} {
			lappend lines "  $i. game [expr {$game + 1}]: $pos"
			continue
		}
		set line [GameLine $game $base $variant]
		set at [expr {[dict get $pos move] ne "" ? "after [dict get $pos move]" : "at the start"}]
		lappend lines "  $i. $line, $at; FEN [dict get $pos fen]"
		lappend samples [list $line $at [dict get $pos fen]]
	}
	set LastFind [list $request $cql [lmap s $samples { lindex $s 2 }]]
	if {$mode eq "sample" && $found} {
		lappend lines "these are the positions the script matched, not yet confirmed to be what was asked for: do not say they show it. Ask the user to look at the diagrams and say whether they are what they meant; if not, fix the script. Call again with mode all only after the user agrees."
		catch { ShowPositions $request $cql $where $samples }
	}
	Resolve $token [join $lines \n]
}


# The game list's position lookup while it shows a find_positions result:
# the FEN of <number>'s first match, or "" (open at the start).
proc ::application::assistant::MatchPosition {base variant number} {
	variable LastPositions
	if {![llength $LastPositions]} { return "" }
	lassign $LastPositions lastBase lastVariant pairs
	if {$base ne $lastBase || $variant ne $lastVariant} { return "" }
	foreach {game ply} $pairs {
		if {$game == $number} {
			return [dict get [::ai::positions::position $base $variant $game $ply] fen]
		}
	}
	return ""
}


proc ::application::assistant::ForgetMatchPositions {} {
	catch { ::gamestable::setPositionLookup {} }
}


# The sample positions as diagrams, with the script, in the Report pane.
proc ::application::assistant::ShowPositions {request cql where samples} {
	set esc {& &amp; < &lt; > &gt; \" &quot;}
	set html "<html><body><h2>[string map $esc $request]</h2>"
	append html "<p>Searched $where with this CQL 6.2 script:</p><pre>[string map $esc $cql]</pre>"
	set n 0
	foreach sample $samples {
		lassign $sample line at fen
		set caption "[string map $esc $line], $at"
		if {[llength [info commands ::ai::diagram::html]]} {
			append html [::ai::diagram::html $fen -caption $caption]
		} else {
			append html "<p>$caption<br><tt>$fen</tt></p>"
		}
		# a click puts the game on the board at this position (app-report.tcl)
		append html "<p><a href=\"scidb-ai:open_position?index=[incr n]\">Open at this position</a></p>"
	}
	append html "</body></html>"
	::application::ai::showReport .application "Positions" $html
}


proc ::application::assistant::DoCqlHelp {} {
	variable Priv
	set Priv(cqlHelp) 1
	if {[llength [info commands ::ai::positions::patterns]]} {
		set own [::ai::positions::patterns]
		if {[llength $own]} {
			append mine "\n\nThe user's saved patterns (scripts the user has accepted):"
			foreach p $own {
				append mine "\n\nRequest: [dict get $p request] (saved as '[dict get $p name]')\n[dict get $p cql]"
			}
		}
	}
	if {[llength [info commands ::ai::cqlref::card]]} {
		set text [::ai::cqlref::card]
		foreach example [::ai::cqlref::examples] {
			lassign $example id request cql
			append text "\n\nRequest: $request\n$cql"
		}
		if {[info exists mine]} { append text $mine }
		return $text
	}
	# the vetted library as worked examples when the card is not there
	set text "CQL 6.2: a script starts with cql() and is a filter run on every position; a game matches when some position passes."
	foreach id [::ai::search::patternIds] {
		set p [::ai::search::pattern $id]
		append text "\n\nRequest: [dict get $p description]\n[::ai::search::pattern6 $id]"
	}
	if {[info exists mine]} { append text $mine }
	return $text
}


proc ::application::assistant::DoSavePattern {name} {
	variable LastFind
	if {![llength $LastFind]} { return "error: there is no position search to save; call find_positions first" }
	lassign $LastFind request cql fens
	set n [::ai::positions::savePattern $name $request $cql $fens]
	return "saved as '$name'; the user now has $n saved pattern[expr {$n == 1 ? "" : "s"}]"
}


proc ::application::assistant::DoSetPosition {fen moves} {
	if {![llength [info commands ::ai::setup::position]]} {
		return "error: setting up a position is not available in this build"
	}
	if {[catch { ::ai::setup::position -fen $fen -moves $moves } result]} {
		return "error: $result; the board is unchanged"
	}
	::application::switchTab board
	set sans [dict get $result sans]
	set after [expr {[llength $sans] ? " after [llength $sans] half-moves (last [lindex $sans end])" : ""}]
	return "a new game is on the board$after; position [dict get $result fen]"
}


proc ::application::assistant::DoOpenGame {number move after} {
	lassign [ActiveBase] base variant
	set count [::scidb::db::count games $base $variant]
	if {$number > $count} { return "error: [::util::databaseName $base no] has $count games" }
	set index [expr {$number - 1}]
	::game::new .application -base $base -variant $variant -number $index
	set where "at the start"
	if {$move ne ""} {
		set ply [expr {2 * ($move - 1) + ($after eq "white" ? 1 : $after eq "black" ? 2 : 0)}]
		set plies [::scidb::game::query mainline]
		if {$ply > [llength $plies]} {
			return "error: game $number has only [expr {([llength $plies] + 1) / 2}] moves; it is on the board at the start"
		}
		# the key of a ply is the position after it
		if {$ply > 0} { ::scidb::game::go key [lindex $plies [expr {$ply - 1}] 0] }
		set where [expr {$after eq "" ? "before move $move" : "after [string totitle $after]'s move $move"}]
	}
	::application::switchTab board
	return "game $number ([GameLine $index $base $variant]) is on the board, $where"
}


proc ::application::assistant::DoOpenPosition {index} {
	variable LastPositions

	if {![llength $LastPositions]} { return "error: there is no find_positions result; call find_positions first" }
	lassign $LastPositions base variant pairs
	if {$index > [llength $pairs] / 2} { return "error: the last search found [expr {[llength $pairs] / 2}] positions" }
	set game [lindex $pairs [expr {2 * ($index - 1)}]]
	set ply [lindex $pairs [expr {2 * ($index - 1) + 1}]]
	::game::new .application -base $base -variant $variant -number $game
	set plies [::scidb::game::query mainline]
	if {$ply > 0 && $ply <= [llength $plies]} {
		# the key of a ply is the position after it
		::scidb::game::go key [lindex $plies [expr {$ply - 1}] 0]
	}
	::application::switchTab board
	return "game [expr {$game + 1}] ([GameLine $game $base $variant]) is on the board at the position"
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

	# Several candidates: the database already found them, so let the
	# classifier pick which one the text names and copy that row
	# (pre-parsed value extraction, never generation). On any abstention the
	# error below is today's behaviour.
	set picked [::application::assistant::SelectPlayer $text $found]
	if {$picked ne ""} { return $picked }

	set names {}
	foreach row [lrange $found 0 9] {
		lassign $row _ name games
		lappend names "$name ($games games)"
	}
	if {[llength $found] > 10} { lappend names "..." }
	error "several players match '$text', call again with one exact name: [join $names {; }]"
}


# The classifier picks which database candidate the request names, from the
# rows ::scidb::db::findPlayers already returned. Returns the {index name}
# row, or "" when it cannot (no classifier, low confidence, or "none"). The
# candidate names ARE the choice options, so the pick is always a real
# database entry. The gate is 0.75, not 0.6: on a labelled set
# (TYPESAFE_COOKBOOK_REVIEW.md), 0.75 commits every disambiguating query at
# 100% accuracy and abstains on every ambiguous bare surname, where 0.6
# committed a guess; any abstention falls back to the error below.
proc ::application::assistant::SelectPlayer {text found} {
	if {[llength [info commands ::ai::systemone::chooseSync]] == 0} { return "" }

	set criteria {}
	foreach row $found {
		lassign $row _ name games
		dict set criteria $name "the database player [list $name] ($games games)"
	}
	dict set criteria none "the text does not name any of these players"

	set question [dict create type choice \
		instructions "Which database player does the request name? Answer none if it names no player." \
		criteria $criteria]

	set label [::ai::systemone::chooseSync player $text $question -threshold 0.75]
	if {$label eq "" || $label eq "none"} { return "" }
	foreach row $found {
		if {[lindex $row 1] eq $label} { return [lrange $row 0 1] }
	}
	return ""
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


proc ::application::assistant::DoUiState {} { return [::application::diagnose::uiState] }
proc ::application::assistant::DoTimers {} { return [::application::diagnose::timersAndChannels] }
proc ::application::assistant::DoLoopHealth {} { return [::application::diagnose::loopHealth] }
proc ::application::assistant::DoMediaState {} { return [::application::diagnose::mediaState] }
proc ::application::assistant::DoChildProcesses {} { return [::application::diagnose::children] }
proc ::application::assistant::DoHangDumps {count} { return [::application::diagnose::hangDumps $count] }
proc ::application::assistant::DoReleaseGrab {window} { return [::application::diagnose::releaseGrab $window] }
proc ::application::assistant::DoCancelTimer {id} { return [::application::diagnose::cancelTimer $id] }


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
	if {![::application::ai::cloudReady $Priv(window)]} { return }
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
		set started [::ai::annotate::annotate .application \
			-prose $prose -marks $marks -depth $depth -maxPlies $max_plies \
			-done [namespace code [list AnnotateGameDone $token]]]
	} err]} {
		after 0 [list Resolve $token "error: $err"]
		return $token
	}
	if {!$started} { return "error: the annotation request could not start" }
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
# Opponent brief.
# ----------------------------------------------------------------------
proc ::application::assistant::DoOpponentBrief {name colour download prose} {
	if {[llength [info commands ::ai::brief::build]] == 0} {
		return "error: the brief module is not available"
	}
	::ai::brief::build .application $name -colour $colour -download $download -prose $prose
	return "brief for '$name' is being prepared; it appears in the Report pane"
}


# ----------------------------------------------------------------------
# Study plan and annotation fact-check.
# ----------------------------------------------------------------------
proc ::application::assistant::DoStudyPlan {player games colour depth} {
	if {[llength [info commands ::ai::studyplan::run]] == 0} {
		return "error: the study-plan module is not available"
	}
	if {[::ai::studyplan::running?]} {
		return "error: an audit is already running"
	}
	set token [Later]
	if {[catch {
		set started [::ai::studyplan::run .application -player $player -games $games \
			-colour $colour -depth $depth \
			-done [namespace code [list StudyPlanDone $token]]]
	} err]} {
		after 0 [list Resolve $token "error: $err"]
		return $token
	}
	if {!$started} { return "error: the study-plan request could not start" }
	return $token
}


proc ::application::assistant::StudyPlanDone {token result} {
	catch { Resolve $token "[dict get $result summary]; the plan is in the Report pane" }
	return
}


# ----------------------------------------------------------------------
# CQL: structure profile, training set, result check.
# ----------------------------------------------------------------------
proc ::application::assistant::DoEventTypes {player games} {
	if {[llength [info commands ::ai::event::report]] == 0} {
		return "error: the event-type module is not available"
	}
	lassign [ActiveBase] base variant
	set token [Later]
	::ai::event::profile $base $variant -player $player -games $games \
		-done [namespace code [list EventTypesDone $token]]
	return $token
}


proc ::application::assistant::EventTypesDone {token profile} {
	Resolve $token [::ai::event::ProfileText $profile]
}


proc ::application::assistant::DoDetectLanguage {text} {
	if {[llength [info commands ::ai::language::detect]] == 0} {
		return "error: the language module is not available"
	}
	set token [Later]
	::ai::language::detect $text [namespace code [list DetectLanguageDone $token]]
	return $token
}


proc ::application::assistant::DetectLanguageDone {token decision} {
	if {[dict get $decision ok]} {
		set code [dict get $decision label]
		Resolve $token "[::ai::language::Name $code] ($code, source [dict get $decision source])"
	} else {
		Resolve $token "the language could not be determined"
	}
}


proc ::application::assistant::DoDiagnoseImport {codes} {
	if {[llength [info commands ::ai::import::diagnose]] == 0} {
		return "error: the import doctor is not available"
	}
	set token [Later]
	::ai::import::diagnose $codes [namespace code [list DiagnoseImportDone $token $codes]]
	return $token
}


proc ::application::assistant::DoCommentKind {text} {
	if {[llength [info commands ::ai::comment::kind]] == 0} {
		return "error: the comment-kind module is not available"
	}
	set token [Later]
	::ai::comment::kind $text [namespace code [list CommentKindDone $token]]
	return $token
}


proc ::application::assistant::CommentKindDone {token decision} {
	if {[dict get $decision ok]} {
		set kind [dict get $decision label]
		Resolve $token "[::ai::comment::Name $kind] ($kind, source [dict get $decision source])"
	} else {
		Resolve $token "the comment's subject could not be determined"
	}
}


proc ::application::assistant::DoNoveltyLabel {fen san} {
	if {[llength [info commands ::ai::novelty::label]] == 0} {
		return "error: the novelty module is not available"
	}
	set token [Later]
	::ai::novelty::label $fen $san [namespace code [list NoveltyLabelDone $token]]
	return $token
}


proc ::application::assistant::NoveltyLabelDone {token decision} {
	if {[dict get $decision ok]} {
		set label [dict get $decision label]
		Resolve $token "[::ai::novelty::describe $label] ($label, source [dict get $decision source])"
	} else {
		Resolve $token "the move's novelty could not be determined"
	}
}


proc ::application::assistant::DiagnoseImportDone {token codes decision} {
	set text [::ai::import::Text $codes]
	if {[dict get $decision ok] && [dict get $decision label] ne ""} {
		set cat [dict get $decision label]
		append text "\nMost likely: [dict get $::ai::import::Categories $cat] (source [dict get $decision source])."
	}
	if {[string trim $text] eq ""} { set text "no import messages to diagnose" }
	Resolve $token $text
}


proc ::application::assistant::DoStructureProfile {player colour games} {
	lassign [ActiveBase] base variant
	set profile [::ai::cql::profile $base $variant $player -colour $colour -games $games]
	set text [::ai::cql::profileText $profile]
	if {$text eq ""} {
		return "none of the structure patterns occurs in 3 or more of [dict get $profile player]'s latest [dict get $profile games] games"
	}
	return $text
}


proc ::application::assistant::DoTrainingSet {pattern player max} {
	if {[::ai::cql::running?]} { return "error: a training set is already being built" }
	set args [list -player $player -max $max]
	if {$pattern ne ""} { lappend args -patterns [list $pattern] }
	set token [Later]
	if {[catch {
		::ai::cql::training .application {*}$args -done [namespace code [list TrainingSetDone $token]]
	} err]} {
		after 0 [list [namespace current]::Resolve $token "error: $err"]
	}
	return $token
}


proc ::application::assistant::TrainingSetDone {token result} {
	catch { Resolve $token [dict get $result text] }
}


proc ::application::assistant::DoCheckResults {} {
	return [::ai::cql::qualityReport .application]
}


proc ::application::assistant::DoFactCheck {} {
	if {[llength [info commands ::ai::factcheck::current]] == 0} {
		return "error: the fact-check module is not available"
	}
	return [::ai::factcheck::current .application]
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


proc ::application::assistant::DoTranscribeMedia {path} {
	if {[llength [info commands ::ai::transcript::transcribe]] == 0} {
		return "error: the transcript module is not available"
	}
	set token [Later]
	::ai::transcript::transcribe $path [namespace code [list TranscribeMediaDone $token]]
	return $token
}


proc ::application::assistant::TranscribeMediaDone {token result} {
	if {![dict get $result ok]} {
		Resolve $token "error: the transcription failed: [dict get $result error]"
		return
	}
	set text [dict get $result text]
	Resolve $token "[::ai::transcript::summary $text]\n\nFull transcript:\n$text"
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
