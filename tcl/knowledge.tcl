# ======================================================================
# ::knowledge -- what Chesswiz can do, generated from the action registry.
#
# The assistant is an operator, not a teacher (user 2026-10-20): this
# module exists so it can choose and run actions, not so it can lecture.
#
#   ::knowledge::FillAll                 fields on every user-reachable action
#   ::knowledge::For <id> ?lang?         resolved knowledge (English fallback)
#   ::knowledge::FindCapability <text>   top capabilities for a request
#   ::knowledge::RunAction <id> <args>   the assistant's generic operator
#   ::knowledge::Generate <dir>          write share/knowledge/ (deterministic)
#   ::knowledge::RegistryHash            drift check against the pack
#
# Action knowledge in the live registry is authoritative. Explicit and toolbar
# descriptions seed empty fields; FillAll/Generate preserve later registry edits.
# The pack is generated from the registry plus the hand-written topic
# pages below; nothing here talks to a network or an embedding service.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source knowledge
}

package require Tcl 8.5

namespace eval ::knowledge {
	variable Explicit [dict create]
	variable Topics {}
	variable ContextNouns [dict create \
		C1 {board position} C2 {game list} C3 {game list column} \
		C4 {database} C5 {player list} C6 {engine line} C7 {media list} \
		C8 {opening tree} C9 {pane} C10 {table column} C11 {notation} \
		C12 {game history} \
	]
	variable StopWords {
		a an and are as at be been but by can could did do does for from
		had has have he her here hers him his how i if in into is it its
		me my of on or our she should so that the their them then there
		these they this those to was we were what when where which who why
		will with would you your im ive id youre dont doesnt cant isnt
	}
	variable SynonymGroups {
		{analyse analysis analyze analyzing analysed analyzed engine engines}
		{rating ratings elo fide}
		{mistake mistakes blunder blunders error errors}
		{opening openings repertoire repertoires}
		{broadcast broadcasts live tournament tournaments stream streams}
		{voice speech talk talking speak speaking dictate microphone mic}
		{manual manuals help documentation docs}
		{fullscreen}
		{bigger larger increase enlarge}
		{smaller decrease shrink reduce}
		{text font fonts letters}
		{previous prev back backward}
		{flip rotate turn}
		{arrows arrow squares square mark marks highlight highlights}
		{comment comments annotation annotations annotate}
		{video videos lesson lessons tutorial tutorials clip clips}
		{practice practise train training endgame endgames tablebase tablebases}
		{positions position rook rooks seventh}
		{prepare preparation opponent opponents scouting scout}
		{review reviews reviewing analyse analysed}
		{save saves saved copy duplicate}
		{import imports importing}
		{pgn pgns}
		{export exports}
		{compact compression shrink}
		{game games}
		{database databases db}
		{search searches find finding}
		{results result}
		{correspondence online}
		{setup set}
		{new create}
		{open opens opened}
		{close closes}
		{window windows}
	}
	variable Banned {
		chessbase fritz {mega database} {chess assistant} cql
		{chess query language}
	}
	# Execution exemptions are reported by ExemptList; none exempt knowledge.
	variable Exempt {context.ask}
	variable Synonyms [dict create]
	variable PackDir ""
	variable PackLoaded 0
	variable PackActions {}
	variable PackTopics {}
	variable Index {}
	variable IDF {}
	variable Built 0
	variable MaxCapabilities 5
}

# ----------------------------------------------------------------------
# Hand-written knowledge for the actions whose words matter most, plus
# the multi-step topic pages. Everything else is synthesized from the
# label and doc below; this keeps one source of truth per action.
# ----------------------------------------------------------------------
set ::knowledge::Explicit [dict create \
	context.ask [dict create \
		purpose "Ask what you can do with the selected item." \
		when "Use this when you want help with the item you clicked." \
		examples [list "What can I do with this item?" "Help me work with this selection"] \
		related {how_do_i run_action} \
	] \
	current_game [dict create \
		purpose "Read the moves, players and comments of the game on the board." \
		when "Use this to inspect or discuss the game you are viewing." \
		examples [list "Show me the moves in this game" "Who is playing the game on the board?"] \
	] \
	list_procs [dict create \
		purpose "List the program functions whose names match a pattern." \
		when "Use this when investigating which program function handles an operation." \
		examples [list "Find program functions with names matching my pattern" "Which program functions have this name?"] \
	] \
	proc_source [dict create \
		purpose "Read the source code of a named program function." \
		when "Use this when investigating how a program function works." \
		examples [list "Show me the code of this program function" "How is this program function implemented?"] \
	] \
	hang_dumps [dict create \
		purpose "Read the diagnostic reports saved when the program stopped responding." \
		when "Use this when investigating a frozen application." \
		examples [list "Show me the reports from the last freeze" "What was the program doing when it froze?"] \
	] \
	open_database [dict create \
		purpose "Open a Chesswiz database file from your computer." \
		when "Use this when you want to work with a database you downloaded or saved." \
		examples [list "open a database file I downloaded" "open my chess database"] \
		related [list import_games open_search export_database] \
		keywords [list open database file load sci cbh pgn downloaded] \
		i18n [dict create de [dict create \
			purpose "Eine Chesswiz-Datenbankdatei von Ihrem Computer \u00f6ffnen." \
			when "Verwenden Sie dies, um mit einer heruntergeladenen oder gespeicherten Datenbank zu arbeiten." \
			examples [list "eine heruntergeladene Datenbank \u00f6ffnen" "meine Schachdatenbank \u00f6ffnen"] \
		]] \
	] \
	import_games [dict create \
		purpose "Import games from a PGN file into a database." \
		when "Use this when you have games in a PGN file and want them in Chesswiz." \
		examples [list "import a pgn file into my database" "add these pgn games to my database"] \
		related [list open_database export_database search_games] \
		keywords [list import pgn file games database add] \
		i18n [dict create de [dict create \
			purpose "Partien aus einer PGN-Datei in eine Datenbank importieren." \
			when "Verwenden Sie dies, wenn Sie Partien in einer PGN-Datei haben und sie in Chesswiz zu haben." \
			examples [list "eine PGN-Datei in meine Datenbank importieren" "diese PGN-Partien hinzuf\u00fcgen"] \
		]] \
	] \
	export_database [dict create \
		purpose "Export games from a database to a PGN file." \
		when "Use this when you want to save or share games outside Chesswiz." \
		examples [list "export my games to pgn" "save these games as a pgn file"] \
		related [list import_games open_database search_games] \
		keywords [list export games pgn save share file] \
		i18n [dict create de [dict create \
			purpose "Partien aus einer Datenbank in eine PGN-Datei exportieren." \
			when "Verwenden Sie dies, um Partien au\u00dferhalb von Chesswiz zu speichern oder zu teilen." \
			examples [list "meine Partien als PGN exportieren" "diese Partien als PGN-Datei speichern"] \
		]] \
	] \
	annot-comment-after [dict create \
		purpose "Add a comment after the current move." \
		when "Use this when you want to explain or annotate a move." \
		examples [list "add a comment after a move" "write a note after this move"] \
		related [list annot-comment-before annot-palette annot-marks] \
		keywords [list comment comments note annotate after move] \
	] \
	annot-comment-before [dict create \
		purpose "Add a comment before the current move." \
		when "Use this when you want a note to appear before a move." \
		examples [list "add a comment before this move" "put a note before the move"] \
		related [list annot-comment-after annot-palette] \
		keywords [list comment comments note annotate before move] \
	] \
	annot-palette [dict create \
		purpose "Open the annotation palette for the current move." \
		when "Use this when you want to mark a move as good, bad, interesting or dubious." \
		examples [list "where do i put a ! or ?? on a move" "open the annotation palette"] \
		related [list annot-good-move annot-bad-move annot-comment-after] \
		keywords [list annotation palette ! ?? good bad move mark symbol nag] \
	] \
	annot-good-move [dict create \
		purpose "Mark the current move as a good move." \
		when "Use this when a move deserves praise in the annotation." \
		examples [list "mark this move as good" "give this move an exclamation mark"] \
		related [list annot-palette annot-bad-move annot-comment-after] \
		keywords [list good move ! annotation praise mark] \
	] \
	annot-bad-move [dict create \
		purpose "Mark the current move as a bad move." \
		when "Use this when a move deserves criticism in the annotation." \
		examples [list "mark this move as bad" "give this move a question mark"] \
		related [list annot-palette annot-good-move annot-comment-after] \
		keywords [list bad move ?? annotation mistake question mark] \
	] \
	annot-marks [dict create \
		purpose "Draw arrows and coloured squares on the board." \
		when "Use this when you want to highlight squares or show an idea on the board." \
		examples [list "draw arrows and colored squares on the board" "highlight these squares for my notes"] \
		related [list annot-palette board-flip] \
		keywords [list arrows colored squares highlight mark notes board draw] \
	] \
	game-new [dict create \
		purpose "Start a new game on the board." \
		when "Use this when you want to play or enter a fresh game." \
		examples [list "start a new game from scratch" "give me a new empty game"] \
		related [list new_game game-save board-flip] \
		keywords [list new game start scratch empty board] \
	] \
	new_game [dict create \
		purpose "Start a new, empty game on the board." \
		when "Use this when you want a fresh board to play or analyse." \
		examples [list "start a new game from scratch" "open a blank game"] \
		related [list game-new game-save] \
		keywords [list new game start scratch empty blank board] \
	] \
	game-save [dict create \
		purpose "Save the game on the board as a new game in the database." \
		when "Use this when you have edited a game and want to keep a new copy." \
		examples [list "save this game as a new one in the database" "keep a copy of this game"] \
		related [list game-replace game-new open_database] \
		keywords [list save game new copy database store] \
		i18n [dict create de [dict create \
			purpose "Die Partie auf dem Brett als neue Partie in der Datenbank speichern." \
			when "Verwenden Sie dies, wenn Sie eine bearbeitete Partie als neue Kopie behalten wollen." \
			examples [list "diese Partie als neue Partie speichern" "eine Kopie dieser Partie behalten"] \
		]] \
	] \
	game-replace [dict create \
		purpose "Replace the loaded database game with the edited game on the board." \
		when "Use this when you want your edits to overwrite the original game." \
		examples [list "overwrite the game I loaded with my edited version" "replace the database game with this"] \
		related [list game-save game-new] \
		keywords [list overwrite replace loaded game edited update] \
	] \
	search_games [dict create \
		purpose "Search the database for games matching a player or filter." \
		when "Use this when you want to find games in your database." \
		examples [list "search my database for all games by a player" "find games with this filter"] \
		related [list open_search find_positions show_search] \
		keywords [list search database games player filter find] \
	] \
	open_search [dict create \
		purpose "Open an advanced search dialog for the database." \
		when "Use this when you need a detailed search by material, rating or position." \
		examples [list "open the advanced database search" "search with more filters"] \
		related [list search_games find_positions] \
		keywords [list advanced search database filter material rating] \
	] \
	compact_database [dict create \
		purpose "Compact the active database to make it smaller and faster." \
		when "Use this when a database has grown huge or feels slow." \
		examples [list "my database got huge and slow, can i compact it" "shrink the database file"] \
		related [list open_database save_working_set] \
		keywords [list compact shrink database huge slow file maintenance] \
		i18n [dict create de [dict create \
			purpose "Die aktive Datenbank verkleinern und beschleunigen." \
			when "Verwenden Sie dies, wenn eine Datenbank sehr gro\u00df oder langsam geworden ist." \
			examples [list "meine Datenbank ist gro\u00df und langsam, kann ich sie komprimieren" "die Datenbankdatei verkleinern"] \
		]] \
	] \
	update_player_data [dict create \
		purpose "Update the rating data of the players in the database." \
		when "Use this when you want current FIDE ratings for your players." \
		examples [list "update FIDE ratings for the players in my database" "refresh the player ratings"] \
		related [list search_games player_stats] \
		keywords [list update fide ratings players elo rating data refresh] \
	] \
	board-flip [dict create \
		purpose "Flip the board so the other side is at the bottom." \
		when "Use this when you want to see the position from Black's side." \
		examples [list "flip the board so black is at the bottom" "turn the board around"] \
		related [list board-null-move set_position] \
		keywords [list flip rotate turn board black bottom side] \
		i18n [dict create de [dict create \
			purpose "Das Brett drehen, sodass die andere Seite unten ist." \
			when "Verwenden Sie dies, um die Stellung aus der Sicht von Schwarz zu sehen." \
			examples [list "das Brett drehen, sodass Schwarz unten ist" "das Brett umdrehen"] \
		]] \
	] \
	set_position [dict create \
		purpose "Set up a position on the board." \
		when "Use this when you want to enter a position from a book, diagram or FEN." \
		examples [list "set up a position from a diagram in a book" "put this FEN on the board"] \
		related [list board-flip menu.board.setup menu.board.set_start_position] \
		keywords [list set setup position fen diagram book board enter] \
		i18n [dict create de [dict create \
			purpose "Eine Stellung auf dem Brett aufbauen." \
			when "Verwenden Sie dies, um eine Stellung aus einem Buch, Diagramm oder FEN einzugeben." \
			examples [list "eine Stellung aus einem Buchdiagramm aufbauen" "diese FEN-Stellung aufs Brett bringen"] \
		]] \
	] \
	nav-back [dict create \
		purpose "Go back one move in the game." \
		when "Use this when you want to step backwards through the moves." \
		examples [list "is there a key to go back one move" "go back one move"] \
		related [list nav-forward nav-start nav-end] \
		keywords [list back previous move key left step] \
	] \
	start_engine [dict create \
		purpose "Start the chess engine on the current position." \
		when "Use this when you want engine analysis." \
		examples [list "turn on the engine to analyse this position" "start analysing with the engine"] \
		related [list engine_check_move explain_position stop_engine] \
		keywords [list start engine analyse analysis turn on position] \
		i18n [dict create de [dict create \
			purpose "Die Schach-Engine f\u00fcr die aktuelle Stellung starten." \
			when "Verwenden Sie dies, wenn Sie eine Engine-Analyse wollen." \
			examples [list "die Engine zur Analyse dieser Stellung starten" "mit der Engine analysieren"] \
		]] \
	] \
	engine_check_move [dict create \
		purpose "Ask the engine whether the current move is good." \
		when "Use this when you want a check of one move." \
		examples [list "is my move here good or bad, can the engine check it" "check this move with the engine"] \
		related [list start_engine explain_position] \
		keywords [list move good bad engine check blunder mistake evaluate] \
	] \
	explain_position [dict create \
		purpose "Explain the current position in plain language." \
		when "Use this when you want a verbal assessment of the position." \
		examples [list "explain the position in plain english" "tell me what is going on in this position"] \
		related [list start_engine engine_check_move] \
		keywords [list explain position plain english assessment describe] \
		i18n [dict create de [dict create \
			purpose "Die aktuelle Stellung in einfachen Worten erkl\u00e4ren." \
			when "Verwenden Sie dies, wenn Sie eine sprachliche Einsch\u00e4tzung der Stellung wollen." \
			examples [list "die Stellung einfach erkl\u00e4ren" "was passiert in dieser Stellung"] \
		]] \
	] \
	study_plan [dict create \
		purpose "Build a study plan from the user's games." \
		when "Use this when the user wants to improve with a training plan." \
		examples [list "make me a study plan from my games" "what should I train to improve"] \
		related [list training_set check_results annotate_game] \
		keywords [list study plan improve training games learn] \
		i18n [dict create de [dict create \
			purpose "Aus den Partien des Nutzers einen Lernplan erstellen." \
			when "Verwenden Sie dies, wenn der Nutzer mit einem Trainingsplan besser werden will." \
			examples [list "einen Lernplan aus meinen Partien machen" "was soll ich zum Verbessern trainieren"] \
		]] \
	] \
	training_set [dict create \
		purpose "Make a training set of positions from the database." \
		when "Use this when you want puzzles or positions to practise." \
		examples [list "make a training set of positions from a database" "collect puzzles for practice"] \
		related [list study_plan find_positions check_results] \
		keywords [list training set positions practice puzzles database exercises] \
		i18n [dict create de [dict create \
			purpose "Ein Trainingsset mit Stellungen aus der Datenbank erstellen." \
			when "Verwenden Sie dies, wenn Sie Aufgaben oder Stellungen zum \u00dcben wollen." \
			examples [list "ein Trainingsset aus der Datenbank erstellen" "Aufgaben zum \u00dcben sammeln"] \
		]] \
	] \
	check_results [dict create \
		purpose "Check whether game results in the database are wrong." \
		when "Use this when you suspect results do not match the moves." \
		examples [list "check whether game results in the database are wrong" "verify the results of these games"] \
		related [list training_set study_plan search_games] \
		keywords [list check results wrong verify database games] \
	] \
	correspondence_games [dict create \
		purpose "Manage correspondence games." \
		when "Use this when you play games by correspondence or over several days." \
		examples [list "manage my correspondence games" "show my correspondence games"] \
		related [list search_games player_stats] \
		keywords [list correspondence games online turn days manage] \
	] \
	voice_status [dict create \
		purpose "Show the status of voice input." \
		when "Use this when you want to talk to Chesswiz instead of typing." \
		examples [list "can i talk to the app with my voice" "is voice input ready"] \
		related [list explain_position] \
		keywords [list voice talk speak dictate speech microphone mic input] \
	] \
	find_lesson [dict create \
		purpose "Find a video lesson for the current opening position." \
		when "Use this when you want a lesson or clip about this position." \
		examples [list "is there a video lesson for this opening position" "find a lesson about this position"] \
		related [list explain_position open_stream] \
		keywords [list video lesson tutorial opening position clip find] \
	] \
	pane [dict create \
		purpose "Show, hide, dock or undock a pane." \
		when "Use this when a pane is closed or in the wrong place." \
		examples [list "show the analysis pane again, I closed it" "hide the game list pane"] \
		related [list menu.view.panes.analysis menu.view.panes.games app-fullscreen] \
		keywords [list pane show hide dock undock analysis closed view layout] \
		related_note "pane" \
	] \
	app-fullscreen [dict create \
		purpose "Enter or exit full screen mode." \
		when "Use this when you want the window to fill the screen." \
		examples [list "exit fullscreen" "make the window fullscreen"] \
		related [list app-help menu.view.layout.manage] \
		keywords [list full screen fullscreen maximize window mode exit leave restore normal] \
		i18n [dict create de [dict create \
			purpose "Den Vollbildmodus umschalten." \
			when "Verwenden Sie dies, wenn das Fenster den ganzen Bildschirm f\u00fcllen soll." \
			examples [list "Vollbildmodus" "das Fenster im Vollbild anzeigen"] \
		]] \
	] \
	app-log [dict create \
		purpose "Show the log window." \
		when "Use this when you want to read what Chesswiz has been doing." \
		examples [list "where can I see the log window" "show the log"] \
		related [list recent_errors app-help] \
		keywords [list log window messages show] \
		i18n [dict create de [dict create \
			purpose "Das Protokollfenster anzeigen." \
			when "Verwenden Sie dies, um zu lesen, was Chesswiz gemacht hat." \
			examples [list "wo ist das Protokollfenster" "das Protokoll anzeigen"] \
		]] \
	] \
	help.close [dict create \
		purpose "Close the Help window after reading the manual." \
		when "Use this to return to your game after consulting a manual page." \
		examples {{Close the manual window} {Dismiss Help and return to my game}} \
	] \
	app-help [dict create \
		purpose "Open the Chesswiz help manual." \
		when "Use this when you need the manual or a reference." \
		examples [list "where's the help manual" "open the help"] \
		related [list app-log find_capability] \
		keywords [list help manual documentation docs reference] \
	] \
	recent_errors [dict create \
		purpose "List the most recent errors Chesswiz recorded." \
		when "Use this when something went wrong just now." \
		examples [list "something went wrong just now, can I see the recent errors" "show the recent errors"] \
		related [list app-log app_state] \
		keywords [list error errors wrong recent log problem] \
		i18n [dict create de [dict create \
			purpose "Die zuletzt von Chesswiz aufgezeichneten Fehler auflisten." \
			when "Verwenden Sie dies, wenn gerade etwas schiefgegangen ist." \
			examples [list "gerade ist etwas schiefgegangen, zeig die letzten Fehler" "die letzten Fehler anzeigen"] \
		]] \
	] \
	app_state [dict create \
		purpose "Report which database, game and tab are open." \
		when "Use this when you want to know what Chesswiz is doing now." \
		examples [list "what's the app doing right now, which database and game are open" "tell me the current app state"] \
		related [list recent_errors app-log] \
		keywords [list state current database game open doing now status] \
	] \
	prepare_against [dict create \
		purpose "Prepare against a named opponent with statistics, openings and weaknesses." \
		when "Use this before a game against a known player." \
		examples [list "I play Smith next round, how do I prepare against him" "prepare me against this opponent"] \
		related [list player_stats opponent_brief open_view search_games show_search] \
		keywords [list prepare preparation opponent next round game scouting smith] \
		i18n [dict create de [dict create \
			purpose "Gegen einen genannten Gegner mit Statistik, Er\u00f6ffnungen und Schw\u00e4chen vorbereiten." \
			when "Verwenden Sie dies vor einer Partie gegen einen bekannten Spieler." \
			examples [list "ich spiele n\u00e4chste Runde gegen Smith, wie bereite ich mich vor" "bereite mich auf diesen Gegner vor"] \
		]] \
	] \
	opponent_brief [dict create \
		purpose "Open the opponent brief in the Report pane." \
		when "Use this when the preparation report should be shown." \
		examples [list "show the opponent brief" "open the prep report"] \
		related [list prepare_against player_stats open_view] \
		keywords [list opponent brief prep report scouting profile] \
	] \
	player_stats [dict create \
		purpose "Show a player's record and statistics." \
		when "Use this when you want a player's results and rating." \
		examples [list "show this player's record" "what are this player's statistics"] \
		related [list prepare_against search_games update_player_data] \
		keywords [list player record statistics stats rating results] \
	] \
	repertoire_check [dict create \
		purpose "Check the user's opening repertoire against their games." \
		when "Use this when the user wants to find gaps in their repertoire." \
		examples [list "help me build an opening repertoire for white" "check my repertoire for gaps"] \
		related [list add_to_repertoire open_view] \
		keywords [list repertoire openings white black build gaps lines] \
		i18n [dict create de [dict create \
			purpose "Das Er\u00f6ffnungsrepertoire des Nutzers gegen seine Partien pr\u00fcfen." \
			when "Verwenden Sie dies, wenn der Nutzer L\u00fccken im Repertoire finden will." \
			examples [list "hilf mir, ein Er\u00f6ffnungsrepertoire f\u00fcr Wei\u00df aufzubauen" "mein Repertoire auf L\u00fccken pr\u00fcfen"] \
		]] \
	] \
	add_to_repertoire [dict create \
		purpose "Add the current line to the user's repertoire." \
		when "Use this when a line should become part of the repertoire." \
		examples [list "add this line to my repertoire" "keep this opening in my repertoire"] \
		related [list repertoire_check open_view] \
		keywords [list add repertoire opening line keep] \
	] \
	annotate_game [dict create \
		purpose "Annotate a game with comments and marks." \
		when "Use this when you want a reviewed and commented game." \
		examples [list "review my own games and find my mistakes" "annotate this game for me"] \
		related [list explain_game_result study_plan annot-comment-after] \
		keywords [list annotate review game comments mistakes analyse improve] \
	] \
	explain_game_result [dict create \
		purpose "Explain a game result in plain language." \
		when "Use this when you want to know why a game ended as it did." \
		examples [list "explain this game result" "why did I lose this game"] \
		related [list annotate_game explain_position] \
		keywords [list explain game result why lose win draw mistakes] \
	] \
	find_positions [dict create \
		purpose "Find positions in the database that match a pattern." \
		when "Use this when you want positions with a piece on a square or a material pattern." \
		examples [list "find all positions in my database with a rook on the seventh" "search positions with this material"] \
		related [list search_games open_search training_set] \
		keywords [list find positions database rook seventh search pattern material] \
		i18n [dict create de [dict create \
			purpose "Stellungen in der Datenbank finden, die einem Muster entsprechen." \
			when "Verwenden Sie dies, wenn Sie Stellungen mit einer Figur auf einem Feld oder einem Materialmuster wollen." \
			examples [list "alle Stellungen mit einem Turm auf der siebten Reihe finden" "Stellungen mit diesem Material suchen"] \
		]] \
	] \
	tablebase [dict create \
		purpose "Look up the endgame tablebase for the current position." \
		when "Use this when you want perfect play in an endgame." \
		examples [list "i want to practice rook endgames" "what does the tablebase say about this endgame"] \
		related [list menu.training.endgame find_positions] \
		keywords [list tablebase endgame rook practice perfect play] \
		i18n [dict create de [dict create \
			purpose "Die Endspiel-Tabelle f\u00fcr die aktuelle Stellung abfragen." \
			when "Verwenden Sie dies, wenn Sie perfektes Spiel im Endspiel wollen." \
			examples [list "ich will Turmendspiele \u00fcben" "was sagt die Tabelle zu diesem Endspiel"] \
		]] \
	] \
	menu.training.endgame [dict create \
		purpose "Open the endgame trainer." \
		when "Use this when you want to practise endgames." \
		examples [list "open the endgame trainer" "practise rook endgames"] \
		related [list tablebase training_set] \
		keywords [list endgame trainer practice rook train] \
	] \
	open_stream [dict create \
		purpose "Open a video stream or a live broadcast." \
		when "Use this when you want to watch a stream or follow a live tournament." \
		examples [list "follow a live tournament broadcast" "open a chess stream"] \
		related [list c7.open_stream find_lesson] \
		keywords [list stream live broadcast tournament watch video follow] \
		i18n [dict create de [dict create \
			purpose "Einen Videostream oder eine Live-\u00dcbertragung \u00f6ffnen." \
			when "Verwenden Sie dies, um einen Stream anzusehen oder einem Live-Turnier zu folgen." \
			examples [list "einer Live-\u00dcbertragung eines Turniers folgen" "einen Schachstream \u00f6ffnen"] \
		]] \
	] \
	c7.open_stream [dict create \
		purpose "Open a video stream or a live broadcast." \
		when "Use this when you want to watch a stream or follow a live tournament." \
		examples [list "follow a live tournament broadcast" "open the stream dialog"] \
		related [list open_stream find_lesson] \
		keywords [list stream live broadcast tournament watch video follow] \
	] \
]

# The drop-down rows whose label alone does not say what they are for: a
# plain-language purpose and the words users ask with (VAL-KNOW-008).
# Rows with a full entry above keep it.
foreach {id purpose keywords} {
	menu.view.font_inc "Make the text and fonts of the whole window bigger." {font text size bigger larger increase enlarge zoom letters}
	menu.view.font_dec "Make the text and fonts of the whole window smaller." {font text size smaller decrease shrink reduce letters}
	app-fullscreen "Switch the main window into or out of full screen." {fullscreen full screen window maximise exit leave}
	menu.view.panes.tree "Show or hide the opening tree pane of the board tab." {tree opening pane show hide moves statistics}
	menu.view.panes.explorer "Show or hide the opening explorer pane of the board tab." {explorer opening pane show hide}
	menu.view.panes.media "Show or hide the media pane (videos and streams) of the board tab." {media pane video show hide}
	menu.view.panes.analysis "Show or hide the engine analysis pane of the board tab." {analysis engine pane show hide}
	menu.view.panes.report "Show or hide the report pane of the board tab." {report pane show hide}
	menu.view.panes.editor "Show or hide the game editor (notation) pane." {editor notation moves pane show hide}
	menu.view.panes.games "Show or hide the game list pane of the board tab." {games list pane show hide}
	menu.view.panes.assistant "Show or hide the assistant pane." {assistant pane show hide}
	menu.view.panes.board "Show or hide the board pane." {board pane show hide}
	menu.view.layout.save "Save the current pane layout." {layout save panes arrangement}
	menu.view.layout.manage "Manage the saved pane layouts." {layout layouts manage panes}
	menu.edit.keyboard "Open the keyboard shortcut preferences." {keyboard shortcuts keys hotkeys preferences settings bindings}
	menu.edit.preferences.engines "Open the engine preferences." {engine engines preferences settings options}
	menu.edit.preferences.pgn "Open the PGN export options." {pgn export options preferences settings}
	menu.edit.preferences.player "Edit your own private player card." {private player card my profile me preferences}
	app.preferences.assistant "Open the assistant preferences." {assistant preferences settings model ai}
	menu.tools.engine_console "Open the engine console that shows the engine's raw messages." {engine console log uci messages output}
	menu.tools.player_dictionary "Open the player dictionary with every known player." {player players dictionary names list}
	menu.tools.player_card "Open a player's card with ratings and statistics." {player card profile rating statistics}
	menu.tools.download "Open the dialog that downloads games from the internet." {download games internet online lichess fetch get}
	menu.tools.import_games "Open the dialog that imports games into a database." {import games dialog pgn add}
	menu.tools.correspondence "Open the correspondence games dialog." {correspondence iccf games dialog moves}
	menu.tools.book "Open the opening book editor." {book opening editor polyglot}
	menu.analysis.engines "Open the engine manager to add, remove and configure chess engines." {engines engine manage manager add remove configure install list}
	menu.analysis.engine_toggle "Start or stop the engine analysing the board position." {engine start stop analyse analysis toggle on off}
	menu.analysis.explorer "Open the opening explorer." {explorer opening}
	menu.analysis.game_review "Review the game with the engine." {review game mistakes engine}
	menu.training.play_engine "Play a game against a chess engine (the computer)." {play against computer engine stockfish game opponent bot}
	menu.training.tactics "Open the tactics trainer with puzzles." {tactics puzzles puzzle trainer exercises combinations}
	menu.training.endgame "Open the endgame trainer." {endgame endgames trainer practise practice}
	menu.training.repertoire "Train your opening repertoire move by move." {train repertoire opening trainer practise drill}
	menu.training.engine_match "Set up and run a match between two engines." {engine match engines tournament versus play}
	menu.training.guess "Guess the next move of a game." {guess move training}
	menu.training.brief "Open the opponent brief tool to prepare for an opponent." {opponent brief preparation prepare tool}
	menu.training.studyplan "Make a study plan from your games." {study plan games improve}
	menu.file.archive_create "Create a portable archive of the database." {archive portable backup database create}
	menu.file.export.archive "Export the database as a portable archive." {archive portable export}
	menu.file.export.pgn "Export the database or the listed games as PGN." {export pgn save games file}
	menu.file.export.html "Export the games as an HTML report." {export html report web page}
	menu.file.import.pgn "Import PGN files into the database." {import pgn file games add}
	menu.file.close "Close the active database." {close database active}
	menu.file.open "Open a database file." {open database file}
	menu.db.properties "Open the properties of the active database." {properties database info details}
	menu.db.readonly "Make the active database read-only, or writable again." {read only readonly protect lock write changes}
	menu.db.discover "Find chess databases stored on this computer." {discover find databases computer disk search scan}
	menu.db.search.material "Open the material search dialog." {material search pieces dialog}
	menu.db.search.rating "Open the rating search dialog." {rating search elo dialog}
	menu.db.search.duplicates "Find duplicate games in the database." {duplicates duplicate double games search}
	menu.db.search.advanced "Open the advanced search dialog." {advanced search dialog header}
	menu.db.reports.opening "Open the opening report for the board position." {opening report position}
	menu.db.reports.eco "Open the opening preparation statistics (ECO) of the database." {eco statistics opening prep preparation codes}
	menu.db.reports.repertoire "Open the repertoire report." {repertoire report}
	menu.db.player.names "Check the player name spellings of the database." {spelling names players check}
	menu.game.load_number "Load a game by its number." {load game number}
	menu.game.close "Close the game on the board." {close game tab}
	game-export "Export the game on the board." {export game pgn save this}
	game-new "Start a new empty game." {new game empty blank}
	game-next "Load the next game of the database." {next game following}
	game-prev "Load the previous game of the database." {previous game before}
	game-first "Load the first game of the database." {first game}
	game-last "Load the last game of the database." {last game final}
	board-flip "Flip the board to see it from the other side." {flip rotate turn board side black view}
	nav-start "Go to the start of the game." {start beginning first move game}
	nav-end "Go to the end of the game." {end last move final position game}
	nav-back "Go back one move." {back one move previous take}
	nav-forward "Go forward one move." {forward one move next}
	c2.strip.truncate "Delete all moves after the current one." {truncate delete cut moves after rest remove}
	annot-good-move "Mark the current move as a good move (!)." {good move mark ! exclamation annotate}
	annot-bad-move "Mark the current move as a poor move (?)." {bad poor move mark ? annotate}
	c7.sync_options "Choose how a video in the media pane follows the game moves (not file or cloud syncing)." {media video follow moves timeline}
	c9.media.sync "Choose how a video in the media pane follows the game moves (not file or cloud syncing)." {media video follow moves timeline}
	c7.sync.position "Let the media video follow the board position." {media video follow position}
	c7.sync.timeline "Let the media video follow its own timeline." {media video timeline}
	switch_tab "Switch the main window to the board tab, the database tab (game list) or another tab." {tab tabs switch board view show list}
	pane "Show, hide, undock into a separate window, dock back, maximise or restore a pane of the board tab." {pane panes window separate undock dock float floating maximise maximize restore show hide tree explorer analysis board}
	search_games "Search the active database for games by player, colour, result, ECO code, event or rating." {search find filter games player eco event result rating list only}
	show_search "Show the games of the last search in the game list." {show list filter games only}
	clear_search "Clear the game list filter so it shows every game again." {clear reset filter unfilter all games again list}
	open_game "Load a game onto the board by number, or a player's most recent game." {load open game number latest recent board put}
	set_position "Set up a position on the board from a FEN or a move sequence." {set up position fen moves board after play enter}
	start_engine "Start an engine analysing the board position." {start engine analyse analysis lines run}
	stop_engine "Stop the analysing engine." {stop engine off halt analysis}
	open_database "Open a database file, or switch back to an open database." {open database file switch back main active}
} {
	if {[dict exists $::knowledge::Explicit $id]} continue
	dict set ::knowledge::Explicit $id [dict create purpose $purpose keywords $keywords]
}

set ::knowledge::Topics [list \
	[dict create \
		id topic:prepare-against-opponent \
		title "Prepare against an opponent" \
		purpose "Get an opponent's record, openings, weak lines and prepared report before a game." \
		keywords [list prepare opponent next round game scouting report statistics openings weaknesses] \
		steps [list \
			[dict create action player_stats args [dict create name {<opponent>}] label "their record"] \
			[dict create action prepare_against args [dict create name {<opponent>}] label "their openings and weakest lines"] \
			[dict create action opponent_brief args [dict create name {<opponent>}] label "the brief in the Report pane"] \
			[dict create action open_view args [dict create kind prep_report name {<opponent>}] label "the prep report and dossier"] \
			[dict create action search_games args [dict create player {<opponent>}] label "their games"] \
			[dict create action show_search args [dict create] label "their games in the game list"] \
		] \
	] \
	[dict create \
		id topic:build-repertoire \
		title "Build a repertoire" \
		purpose "Turn the user's games and favourite lines into an opening repertoire and find the gaps." \
		keywords [list repertoire openings white black build lines gaps train] \
		steps [list \
			[dict create action repertoire_check args [dict create player {<me>}] label "repertoire against the user's games"] \
			[dict create action open_view args [dict create kind repertoire_report] label "the repertoire report"] \
			[dict create action add_to_repertoire args [dict create] label "keep a chosen line"] \
		] \
	] \
	[dict create \
		id topic:review-my-games \
		title "Review my games" \
		purpose "Find the user's mistakes in their own games and turn them into a study plan." \
		keywords [list review my games mistakes blunders improve analyse own results] \
		steps [list \
			[dict create action player_stats args [dict create name {<me>}] label "the user's record"] \
			[dict create action study_plan args [dict create player {<me>} games 10] label "engine audit and study plan"] \
			[dict create action search_games args [dict create player {<me>}] label "the user's games"] \
			[dict create action show_search args [dict create] label "the games in the list"] \
		] \
	] \
	[dict create \
		id topic:follow-live-broadcast \
		title "Follow a live broadcast" \
		purpose "Open the stream dialog and watch a live tournament broadcast." \
		keywords [list follow live tournament broadcast stream watch lichess twitch] \
		steps [list \
			[dict create action c7.open_stream args [dict create] label "open the stream dialog"] \
			[dict create action open_stream args [dict create url {<stream url>}] label "play the chosen stream"] \
		] \
	] \
	[dict create \
		id topic:find-positions \
		title "Find positions in my database" \
		purpose "Search the database for positions with a piece on a square or a material pattern." \
		keywords [list find positions database rook seventh search pattern material] \
		steps [list \
			[dict create action find_positions args [dict create] label "run the position search"] \
			[dict create action search_games args [dict create] label "narrow the games if needed"] \
		] \
	] \
	[dict create \
		id topic:train-endgames \
		title "Train endgames" \
		purpose "Practise endgames with the trainer and check perfect play in the tablebase." \
		keywords [list train practice endgames endgame rook tablebase exercises] \
		steps [list \
			[dict create action menu.training.endgame args [dict create] label "open the endgame trainer"] \
			[dict create action tablebase args [dict create] label "check perfect play"] \
		] \
	] \
]

# ----------------------------------------------------------------------
# Small helpers.
# ----------------------------------------------------------------------
proc ::knowledge::_dg {d key def} {
	if {[dict exists $d $key]} { return [dict get $d $key] }
	return $def
}

proc ::knowledge::Clean {text} {
	variable Banned
	set text [string trim $text]
	foreach word $Banned {
		regsub -all -nocase $word $text "pattern search" text
	}
	return $text
}

# Never clip prose by character count or split inside a parenthesized list.
proc ::knowledge::FirstSentence {text} {
	set text [string trim [regsub -all {\s+} $text { }]]
	set depth 0
	for {set i 0} {$i < [string length $text]} {incr i} {
		set c [string index $text $i]
		if {$c eq "("} {incr depth}
		if {$c eq ")"} {incr depth -1}
		if {$c eq "." && $depth == 0 && [string index $text [expr {$i+1}]] eq " " && [string index $text [expr {$i-1}]] ne "."} {
			return [string range $text 0 $i]
		}
	}
	return $text
}

proc ::knowledge::EndsWithDot {text} {
	set text [string trim $text]
	if {$text eq ""} { return $text }
	if {[string index $text end] ni {. ! ?}} { append text "." }
	return $text
}

proc ::knowledge::LowerStart {text} {
	set text [string trim $text]
	if {$text eq ""} { return $text }
	return "[string tolower [string index $text 0]][string range $text 1 end]"
}

proc ::knowledge::LabelText {label} {
	set text [::action::displayLabel $label]
	regsub {\.\.\.$} $text "" text
	regsub "\u2026$" $text "" text
	return [string trim $text]
}

proc ::knowledge::Surface {id rec} {
	set out {}
	if {[dict get $rec dropdown] ne ""} { lappend out dropdown }
	if {[llength [dict get $rec context]]} { lappend out context }
	if {[string match "toolbar.*" $id]} { lappend out toolbar }
	if {[dict get $rec ai] eq "1" || [dict get $rec ai] eq "debug"} { lappend out assistant }
	foreach k [dict get $rec keys] {
		if {$k ne ""} { lappend out keyboard; break }
	}
	return $out
}

proc ::knowledge::InScope {id rec} {
	if {[dict get $rec operator]} { return 1 }
	if {[dict get $rec ai] eq "debug"} { return 1 }
	if {[llength [Surface $id $rec]]} { return 1 }
	return 0
}

proc ::knowledge::Qualifier {id rec} {
	set surfaces [Surface $id $rec]
	if {"context" in $surfaces} {
		set ctx [lindex [dict get $rec context] 0]
		variable ContextNouns
		if {[dict exists $ContextNouns $ctx]} {
			return "in the [dict get $ContextNouns $ctx] menu, under [join [lrange [split $id .] 1 end] { > }]"
		}
		return "in the context menu"
	}
	if {"dropdown" in $surfaces} {
		if {[regexp {^menu\.([a-z0-9]+)\.} $id -> top]} {
			return "from the [string totitle $top] menu, under [join [lrange [split $id .] 2 end] { > }]"
		}
		return "from the main menu"
	}
	if {"toolbar" in $surfaces} { return "from the [string map {_ { }} [lindex [split $id .] 1]] toolbar, control [lindex [split $id .] end]" }
	if {"keyboard" in $surfaces} { return "with the keyboard" }
	return "from the assistant"
}

proc ::knowledge::Siblings {id rec} {
	set out {}
	set prefix ""
	if {[regexp {^(menu\.[a-z0-9]+\.)} $id -> p]} { set prefix $p }
	if {$prefix eq "" && [regexp {^(c[0-9]+)\.} $id -> p]} { set prefix "$p." }
	# Only same-surface ids can be siblings. Avoid scanning the registry
	# for ungrouped actions, and check names only after matching the group.
	# In particular, do not repeat BannedId? for every unrelated action.
	if {$prefix ne ""} {
		# Filter in the dictionary implementation rather than walking every
		# unrelated action in Tcl for each row. dict keys preserves the same
		# registry order as action::list, including newly registered actions.
		foreach other [dict keys $::action::Registry "$prefix*"] {
			if {$other eq $id} { continue }
			if {[BannedId? $other]} { continue }
			lappend out $other
			if {[llength $out] >= 3} { break }
		}
	}
	if {![llength $out]} {
		foreach other {app-help find_capability} {
			if {$other ne $id && [dict exists $::action::Registry $other]} { lappend out $other }
		}
	}
	return $out
}

# An action id carrying a name the product does not use (banned fixture)
# never appears in a knowledge field.
proc ::knowledge::BannedId? {id} {
	variable Banned
	set low [string tolower $id]
	foreach word $Banned {
		if {[string first [string tolower $word] $low] >= 0} { return 1 }
	}
	return 0
}

proc ::knowledge::Synthesize {id rec} {
	variable Explicit

	set label [LabelText [dict get $rec label]]
	set doc [Clean [dict get $rec doc]]
	set purpose ""
	set when ""
	set examples {}
	set related {}
	set video ""
	set keywords {}
	set i18n {}

	set authored {}
	# Authored defaults initialize records once; registry knowledge is the
	# source of truth thereafter, including edits made before regeneration.
	if {[info exists ::toolbar::Knowledge]} {
		set sourceId $id
		regsub {_[0-9]+$} $sourceId {} sourceId
		if {[dict exists $::toolbar::Knowledge $sourceId]} {set authored [dict get $::toolbar::Knowledge $sourceId]}
	}
	if {[dict exists $Explicit $id]} {set authored [dict merge $authored [dict get $Explicit $id]]}
	foreach field {purpose when examples related video keywords i18n} {
		if {[dict exists $rec $field] && [dict get $rec $field] ne ""} {
			dict set authored $field [dict get $rec $field]
		}
	}
	if {$authored ne {}} {
		set e $authored
		set purpose [_dg $e purpose {}]
		set when [_dg $e when {}]
		set examples [_dg $e examples {}]
		set related [_dg $e related {}]
		set video [_dg $e video {}]
		set keywords [_dg $e keywords {}]
		set i18n [_dg $e i18n {}]
	}

	if {$purpose eq ""} {
		set sentence [FirstSentence $doc]
		if {$sentence eq "" || $sentence eq $label} {
			set purpose $label
		} else {
			set purpose $sentence
		}
	}
	set purpose [EndsWithDot [Clean $purpose]]
	# Documentation may be a noun phrase or contain developer details. Do not
	# turn it into an imperative by blindly prepending "How do I".
	set requestLabel [Clean [string map {_ { }} $label]]
	regsub -all {%[-+0-9.]*[a-zA-Z]} $requestLabel {a value} requestLabel

	if {$when eq ""} {
		set when "Use this when you need the ‘$requestLabel’ command."
	}
	set when [EndsWithDot [Clean $when]]

	if {![llength $examples]} {
		set examples [list "How do I use ‘$requestLabel’?" "Help me use ‘$requestLabel’"]
	}
	set cleanExamples {}
	foreach ex $examples { lappend cleanExamples [Clean $ex] }
	set examples $cleanExamples

	if {![llength $related]} { set related [Siblings $id $rec] }
	set validRelated {}
	foreach rel $related {
		if {$rel eq $id || ![dict exists $::action::Registry $rel]} { continue }
		if {[BannedId? $rel]} { continue }
		lappend validRelated $rel
	}
	set related $validRelated

	return [dict create \
		purpose $purpose \
		when $when \
		examples $examples \
		related $related \
		video $video \
		keywords $keywords \
		i18n $i18n \
	]
}

# ----------------------------------------------------------------------
# FillAll: one deterministic pass over the registry. User-reachable
# actions get the knowledge fields and operator exposure; debug actions
# stay debug-only; the Ask field itself is exempt (VAL-AI-009).
# ----------------------------------------------------------------------
proc ::knowledge::FillAll {} {
	variable Built

	set ids [lsort [::action::list]]
	set seen [dict create]
	set firstPass [dict create]

	foreach id $ids {
		set rec [::action::get $id]
		if {![InScope $id $rec]} { continue }
		set k [Synthesize $id $rec]
		dict set firstPass $id $k
		foreach ex [dict get $k examples] {
			set norm [string tolower [string trim $ex]]
			dict set seen $norm [expr {[dict exists $seen $norm] ? [dict get $seen $norm] + 1 : 1}]
		}
	}

	foreach id $ids {
		set rec [::action::get $id]
		if {![InScope $id $rec]} {
			# Keep an explicit operator 0 for actions outside the surfaces.
			continue
		}
		set k [dict get $firstPass $id]
		set examples [dict get $k examples]

		# Two actions may share a label. Add the surface qualifier only
		# where the example would otherwise repeat across actions.
		set needs 0
		foreach ex $examples {
			set norm [string tolower [string trim $ex]]
			if {[dict get $seen $norm] > 1} { set needs 1; break }
		}
		if {$needs} {
			set label [Clean [string map {_ { }} [LabelText [dict get $rec label]]]]
			set qual [string map {_ { }} [Qualifier $id $rec]]
			set examples [list "How do I use ‘$label’ $qual?" "Help me use ‘$label’ $qual"]

		}

		# Re-count the final examples so a later duplicate gets fixed too.
		foreach ex $examples {
			set norm [string tolower [string trim $ex]]
			dict set seen $norm [expr {[dict exists $seen $norm] ? [dict get $seen $norm] + 1 : 1}]
		}

		dict set k examples $examples
		set rec [dict merge $rec $k]
		dict set rec operator [expr {$id ni $::knowledge::Exempt}]
		dict set ::action::Registry $id $rec
	}

	# A final guard: make every example unique across the registry.
	set used [dict create]
	foreach id [lsort [::action::list]] {
		set rec [::action::get $id]
		if {![InScope $id $rec]} { continue }
		set examples [dict get $rec examples]
		set fixed {}
		foreach ex $examples {
			set norm [string tolower [string trim $ex]]
			if {[dict exists $used $norm]} {
				# Aliases can describe the same control. Choose another plain
				# request form instead of appending code ids or numbered suffixes.
				set label [Clean [string map {_ { }} [LabelText [dict get $rec label]]]]
				set qual [string map {_ { }} [Qualifier $id $rec]]
				set found 0
				foreach template {
					{Please show me how to use ‘%s’ %s}
					{Where can I find ‘%s’ %s?}
					{Help me find ‘%s’ %s}
					{I need help with ‘%s’ %s}
					{How does ‘%s’ work %s?}
					{Show me the steps for ‘%s’ %s}
				} {
					set candidate [format $template $label $qual]
					set norm [string tolower $candidate]
					if {![dict exists $used $norm]} { set ex $candidate; set found 1; break }
				}
				if {!$found} { error "add distinct knowledge examples for $id" }
			}
			dict set used $norm 1
			lappend fixed $ex
		}
		if {$fixed ne $examples} {
			dict set rec examples $fixed
			dict set ::action::Registry $id $rec
		}
	}

	set Built 1
	return [llength [lsort [::action::list]]]
}

# ----------------------------------------------------------------------
# Register every surface and expose its operators at startup. Descriptive
# knowledge is synthesized on first use; explicit Ensure calls still refresh
# it (including after registry changes in generators and tests).
# ----------------------------------------------------------------------
proc ::knowledge::Ensure {{fill 1}} {
	if {[llength [info commands ::menu::DefineTree]]} {
		catch { ::menu::DefineTree }
		catch { ::menu::RegisterTree }
		catch { ::menu::RegisterExtras }
	}
	if {[llength [info commands ::menu::WireOperations]]} { ::menu::WireOperations }
	if {$fill} { return [FillAll] }
	foreach id [::action::list] {
		set rec [::action::get $id]
		if {[InScope $id $rec]} {
			dict set ::action::Registry $id operator [expr {$id ni $::knowledge::Exempt}]
		}
	}
	return [llength [::action::list]]
}

# ----------------------------------------------------------------------
# Resolved knowledge for display/planning, with per-field language
# fallback: German where present, English otherwise, never empty.
# ----------------------------------------------------------------------
proc ::knowledge::For {id {lang ""}} {
	if {!$::knowledge::Built} { Ensure }
	if {$lang eq ""} {
		if {[info exists ::mc::langID]} { set lang $::mc::langID } else { set lang en }
	}
	set rec [::action::get $id]
	set out [dict create \
		id $id \
		title [LabelText [dict get $rec label]] \
		purpose [dict get $rec purpose] \
		when [dict get $rec when] \
		examples [dict get $rec examples] \
		related [dict get $rec related] \
		video [dict get $rec video] \
	]
	if {$lang ne "en" && [dict exists $rec i18n $lang]} {
		set tr [dict get $rec i18n $lang]
		foreach field {purpose when examples} {
			if {[dict exists $tr $field] && [string trim [dict get $tr $field]] ne ""} {
				dict set out $field [dict get $tr $field]
			}
		}
	}
	foreach field {purpose when} {
		if {[string trim [dict get $out $field]] eq ""} {
			dict set out $field [LabelText [dict get $rec label]]
		}
	}
	if {![llength [dict get $out examples]]} {
		dict set out examples [dict get $rec examples]
	}
	return $out
}

# ----------------------------------------------------------------------
# Deterministic JSON writer (sorted keys, stable order). The generator
# and the drift hash share it, so equal registries produce equal bytes.
# ----------------------------------------------------------------------
proc ::knowledge::_jsonEscape {s} {
	set s [string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $s]
	return "\"$s\""
}

proc ::knowledge::_jsonValue {v} {
	if {[llength $v] > 1} {
		set parts {}
		foreach item $v { lappend parts [_jsonValue $item] }
		return "\[[join $parts ,]\]"
	}
	return [_jsonEscape $v]
}

proc ::knowledge::_actionCanonical {id} {
	set rec [::action::get $id]
	set k [For $id en]
	return [dict create \
		id $id \
		title [dict get $k title] \
		purpose [dict get $k purpose] \
		when [dict get $k when] \
		examples [dict get $k examples] \
		related [dict get $k related] \
		video [dict get $k video] \
		keywords [dict get $rec keywords] \
		operator [dict get $rec operator] \
		ai [dict get $rec ai] \
		surfaces [Surface $id $rec] \
		args [ArgList $id $rec] \
	]
}

proc ::knowledge::ArgList {id rec} {
	set spec [dict get $rec args]
	set out {}
	foreach param $spec {
		set name [lindex $param 0]
		set opts [lindex $param 1]
		if {$name eq "object" && [::context::NeedsObject $rec]} {
			set fields [::context::RequiredFields $id]
			if {[llength $fields]} { dict set opts description "Selected item; required details: [join $fields {, }]." }
		}
		set state [::action::_requiredState $opts]
		set required [expr {$state == 1 || ($state < 0 && ![dict exists $opts default])}]
		lappend out [dict create \
			name $name \
			type [_dg $opts type string] \
			required [expr {$required ? 1 : 0}] \
			description [_dg $opts description {}] \
		]
	}
	return $out
}

proc ::knowledge::_recordJson {rec} {
	set fields {}
	foreach key {id title purpose when examples related video keywords operator ai surfaces args} {
		lappend fields "[_jsonEscape $key]:[_jsonField $key $rec]"
	}
	return "\{[join $fields ,]\}"
}

proc ::knowledge::_jsonField {key rec} {
	if {![dict exists $rec $key]} { return "\"\"" }
	set v [dict get $rec $key]
	switch -- $key {
		examples - related - keywords - surfaces {
			set parts {}
			foreach item $v { lappend parts [_jsonEscape $item] }
			return "\[[join $parts ,]\]"
		}
		operator - ai {
			if {$v eq "debug"} { return "\"debug\"" }
			return [expr {$v ? "1" : "0"}]
		}
		args {
			set parts {}
			foreach a $v {
				set f {}
				foreach k {name type required description} {
					if {$k eq "required"} {
						lappend f "[_jsonEscape $k]:[expr {[dict get $a $k] ? "1" : "0"}]"
					} else {
						lappend f "[_jsonEscape $k]:[_jsonEscape [dict get $a $k]]"
					}
				}
				lappend parts "\{[join $f ,]\}"
			}
			return "\[[join $parts ,]\]"
		}
	}
	return [_jsonEscape $v]
}

proc ::knowledge::CanonicalText {} {
	set lines {}
	foreach id [lsort [PackIds]] {
		lappend lines [join [list \
			$id \
			[dict get [For $id en] purpose] \
			[dict get [For $id en] when] \
			[join [dict get [For $id en] examples] {|}] \
			[join [dict get [For $id en] related] {,}] \
			[dict get [For $id en] video] \
			[join [dict get [::action::get $id] keywords] {,}] \
			[dict get [::action::get $id] operator] \
		] "\t"]
	}
	foreach topic [PackTopicList] {
		set stepIds {}
		foreach st [dict get $topic steps] { lappend stepIds [dict get $st action] }
		lappend lines [join [list \
			[dict get $topic id] \
			[dict get $topic title] \
			[dict get $topic purpose] \
			[join [dict get $topic keywords] {,}] \
			[join $stepIds {,}] \
		] "\t"]
	}
	return [join $lines "\n"]
}

proc ::knowledge::RegistryHash {} {
	set text [CanonicalText]
	if {![catch {package require sha256}]} {
		foreach cmd {::sha2::sha256 ::sha256::sha256} {
			if {[llength [info commands $cmd]]} { return [$cmd $text] }
		}
	}
	if {![catch {package require sha1}]} {
		if {[llength [info commands ::sha1::sha1]]} {
			return [::sha1::sha1 $text]
		}
	}
	if {![catch {package require md5}]} {
		if {[llength [info commands ::md5::md5]]} {
			return [::md5::md5 $text]
		}
	}
	return ""
}

proc ::knowledge::PackIds {} {
	if {!$::knowledge::Built} { Ensure }
	if {![llength [::action::list]]} { return {} }
	if {![info exists ::action::Registry]} { return {} }
	set ids {}
	foreach id [lsort [::action::list]] {
		set rec [::action::get $id]
		if {[InScope $id $rec]} { lappend ids $id }
	}
	return $ids
}

proc ::knowledge::PackTopicList {} {
	variable Topics
	return $Topics
}

# ----------------------------------------------------------------------
# Pack directory and files.
# ----------------------------------------------------------------------
proc ::knowledge::Dir {} {
	variable PackDir
	if {$PackDir ne "" && [file isfile [file join $PackDir actions.json]]} { return $PackDir }
	if {[info exists ::env(CHESSWIZ_KNOWLEDGE_DIR)] && [file isfile [file join $::env(CHESSWIZ_KNOWLEDGE_DIR) actions.json]]} {
		set PackDir [file normalize $::env(CHESSWIZ_KNOWLEDGE_DIR)]
		return $PackDir
	}
	set candidates {}
	if {[info exists ::scidb::dir::share]} { lappend candidates [file join $::scidb::dir::share knowledge] }
	if {[info exists ::scidb::dir::exec]} { lappend candidates [file join [file dirname $::scidb::dir::exec] share knowledge] }
	lappend candidates [file join [pwd] share knowledge]
	foreach dir $candidates {
		if {[file isfile [file join $dir actions.json]]} {
			set PackDir [file normalize $dir]
			return $PackDir
		}
	}
	return ""
}

proc ::knowledge::Load {} {
	variable PackLoaded
	variable PackActions
	variable PackTopics
	variable Index
	variable IDF

	if {!$::knowledge::Built} { Ensure }
	if {$PackLoaded} { return }
	if {![llength [::action::list]]} { return }
	if {![info exists ::action::Registry]} { return }
	if {![catch {package require json}]} {
		set dir [Dir]
		if {$dir ne ""} {
			if {![catch {
				set f [open [file join $dir actions.json] r]
				set PackActions [::json::json2dict [read $f]]
				close $f
				set f [open [file join $dir topics.json] r]
				set PackTopics [::json::json2dict [read $f]]
				close $f
			}]} {
				# json2dict turns arrays into Tcl lists; normalise the
				# fields the planner uses.
				BuildIndex
				set PackLoaded 1
				return
			}
		}
	}
	# No pack on disk: build the same data from the live registry.
	set PackActions {}
	foreach id [PackIds] { lappend PackActions [_actionCanonical $id] }
	set PackTopics [PackTopicList]
	BuildIndex
	set PackLoaded 1
}

proc ::knowledge::EnsureSynonyms {} {
	variable Synonyms
	variable SynonymGroups

	if {[dict size $Synonyms]} { return }
	foreach group $SynonymGroups {
		foreach word $group {
			set others {}
			foreach other $group {
				if {$other ne $word} { lappend others $other }
			}
			dict set Synonyms $word $others
		}
	}
}

proc ::knowledge::Tokenize {text} {
	variable StopWords
	variable Synonyms

	EnsureSynonyms

	set text [string tolower $text]
	set tokens {}
	# Sentence punctuation separates words; standalone chess annotation
	# symbols remain searchable (for example ! and ??).
	foreach tok [regexp -all -inline {[a-z0-9]+|[!?]+} $text] {
		if {$tok in {! ??}} { lappend tokens $tok; continue }
		if {[string length $tok] < 2} { continue }
		if {$tok in $StopWords} { continue }
		if {[dict exists $Synonyms $tok]} {
			foreach syn [dict get $Synonyms $tok] {
				if {$syn ni $tokens} { lappend tokens $syn }
			}
		} else {
			if {$tok ni $tokens} { lappend tokens $tok }
		}
	}
	return $tokens
}

proc ::knowledge::BuildIndex {} {
	variable PackActions
	variable PackTopics
	variable Index
	variable IDF

	set Index {}
	set df [dict create]
	set caps [list]
	foreach topic $PackTopics {
		set text "[dict get $topic title] [dict get $topic purpose] [join [dict get $topic keywords] { }]"
		set tokens [lsort -unique [Tokenize $text]]
		lappend caps [dict create kind topic id [dict get $topic id] title [dict get $topic title] tokens $tokens data $topic]
	}
	foreach action $PackActions {
		set text "[dict get $action title] [dict get $action purpose] [dict get $action when] [join [dict get $action examples] { }] [join [dict get $action keywords] { }]"
		set tokens [lsort -unique [Tokenize $text]]
		lappend caps [dict create kind action id [dict get $action id] title [dict get $action title] tokens $tokens data $action]
	}
	foreach cap $caps {
		foreach tok [dict get $cap tokens] {
			dict set df $tok [expr {[dict exists $df $tok] ? [dict get $df $tok] + 1 : 1}]
		}
	}
	set n [llength $caps]
	set IDF [dict create]
	dict for {tok count} $df {
		dict set IDF $tok [expr {log(double($n) / double($count)) + 1.0}]
	}
	set Index $caps
	return [llength $caps]
}

proc ::knowledge::Score {tokens cap} {
	variable IDF

	set capTokens [dict get $cap tokens]
	set score 0.0
	foreach tok $tokens {
		if {![dict exists $IDF $tok]} { continue }
		if {$tok in $capTokens} {
			set weight 1.0
			if {[string first $tok [string tolower [dict get $cap title]]] >= 0} { set weight 2.0 }
			set score [expr {$score + $weight * [dict get $IDF $tok]}]
		}
	}
	if {$score <= 0} { return 0.0 }
	# Favour capabilities that cover more of the request, and topics for
	# multi-step jobs; long pages do not get an unfair advantage.
	set matched 0
	foreach tok $tokens {
		if {$tok in $capTokens} { incr matched }
	}
	set n [llength $tokens]
	if {$n < 1} { set n 1 }
	set score [expr {$score * (1.0 + double($matched) / double($n))}]
	if {[dict get $cap kind] eq "topic"} { set score [expr {$score * 1.15}] }
	return $score
}

proc ::knowledge::Search {request {limit 4}} {
	Load

	set tokens [Tokenize $request]
	if {$limit < 3} { set limit 3 }
	if {$limit > 5} { set limit 5 }
	if {![llength $tokens]} { return {} }
	set scored {}
	foreach cap $::knowledge::Index {
		set score [Score $tokens $cap]
		if {$score > 0} { lappend scored [list $score $cap] }
	}
	set scored [lsort -real -decreasing -index 0 $scored]
	set out {}
	foreach entry [lrange $scored 0 [expr {$limit - 1}]] {
		lappend out [lindex $entry 1]
	}
	return $out
}

# ----------------------------------------------------------------------
# Availability and arguments, so find_capability never offers a dead row
# as runnable.
# ----------------------------------------------------------------------
proc ::knowledge::Runnable {id {object {}}} {
	if {[string match "topic:*" $id]} { return [list 1 ""] }
	if {![dict exists $::action::Registry $id]} { return [list 0 "not part of this build"] }
	set rec [::action::get $id]
	if {[dict get $rec ai] eq "debug"} {
		set enabled 0
		catch { set enabled $::application::assistant::Priv(debug) }
		if {!$enabled} { return [list 0 "debug mode only"] }
	}
	if {![dict get $rec operator] && [dict get $rec ai] ne "1"} {
		return [list 0 "not exposed to the assistant"]
	}
	if {[::context::NeedsObject $rec]} {
		set selected [list {} $object]
		if {$object eq ""} { set selected [::context::CurrentObjectFor $id] }
		if {![llength $selected]} { return [list 0 "select an item first"] }
		set object [lindex $selected 1]
		set missing [::context::MissingFields $id $object]
		if {[llength $missing]} { return [list 0 "selected item lacks [join $missing {, }]"] }
	}
	if {$id eq "c9.float" && ![lindex [::context::ObjectRule $id $object] 1]} {
		return [list 0 "unavailable: focus or select a pane that supports floating"]
	}
	if {[llength [dict get $rec context]] && [llength [info commands ::menu::state]]} {
		if {![catch {::menu::state $id $object} state]} {
			if {![dict get $state visible] || ![dict get $state enabled]} {
				return [list 0 "not available in the current context"]
			}
		}
	}
	set ep [dict get $rec enabled]
	if {$ep ne ""} {
		if {[catch {uplevel #0 $ep} ok] || !$ok} {
			return [list 0 "disabled right now"]
		}
	}
	return [list 1 ""]
}

proc ::knowledge::ArgText {id} {
	if {[string match "topic:*" $id]} { return "" }
	if {![dict exists $::action::Registry $id]} { return "" }
	set rec [::action::get $id]
	set args [ArgList $id $rec]
	if {![llength $args]} { return "" }
	set parts {}
	foreach a $args {
		set name [dict get $a name]
		if {[dict get $a required]} {
			lappend parts "$name (required)"
		} else {
			lappend parts $name
		}
	}
	return "args: [join $parts {, }]"
}

proc ::knowledge::ChainText {topic} {
	set parts {}
	set n 0
	foreach step [dict get $topic steps] {
		incr n
		set args [dict get $step args]
		set text "$n. [dict get $step action]"
		if {[dict size $args]} {
			set pairs {}
			dict for {k v} $args { lappend pairs "$k=$v" }
			append text " \{[join $pairs {, }]\}"
		}
		lappend parts $text
	}
	return [join $parts "; "]
}

# ----------------------------------------------------------------------
# find_capability: planning input. It says what can be run and what the
# arguments are; it is never a list of instructions for the user.
# ----------------------------------------------------------------------
proc ::knowledge::FindCapability {request {limit 4}} {
	set caps [Search $request $limit]
	if {![llength $caps]} {
		return "No matching Chesswiz capability. Do not invent one; say briefly that this build has no such feature."
	}
	set lines {}
	foreach cap $caps {
		set kind [dict get $cap kind]
		set data [dict get $cap data]
		if {$kind eq "topic"} {
			lappend lines "CAPABILITY [dict get $data id]"
			lappend lines "  [dict get $data title]: [dict get $data purpose]"
			lappend lines "  chain: [ChainText $data]"
			foreach step [dict get $data steps] {
				set id [dict get $step action]
				lassign [Runnable $id] ok why
				if {$ok} {
					lappend lines "  - $id (runnable) [ArgText $id]"
				} else {
					lappend lines "  - $id (unavailable: $why) [ArgText $id]"
				}
			}
		} else {
			set id [dict get $data id]
			lassign [Runnable $id] ok why
			set status [expr {$ok ? "runnable" : "unavailable: $why"}]
			lappend lines "CAPABILITY $id"
			lappend lines "  [dict get $data title]: [dict get $data purpose]"
			lappend lines "  status: $status; [ArgText $id]"
			set rel [dict get $data related]
			if {[llength $rel]} { lappend lines "  related: [join $rel {, }]" }
		}
	}
	lappend lines "Use these ids with run_action. Report only what a tool returned; do not paste this plan to the user."
	return [join $lines "\n"]
}

# The nearest actions that exist and are usable now, as {label id} pairs.
# Used by the assistant's bounded decline (VAL-AI-012): those actions must
# come from the registry, never from the model's own knowledge.
proc ::knowledge::NearestActions {request {limit 2}} {
	set out {}
	foreach cap [Search $request [expr {$limit > 3 ? $limit : 3}]] {
		if {[dict get $cap kind] eq "topic"} {
			set data [dict get $cap data]
			set id ""
			foreach step [dict get $data steps] {
				lassign [Runnable [dict get $step action]] ok
				if {$ok} { set id [dict get $step action]; break }
			}
			if {$id eq ""} continue
			lappend out [list [dict get $data title] $id]
		} else {
			set data [dict get $cap data]
			set id [dict get $data id]
			lassign [Runnable $id] ok
			if {!$ok} continue
			lappend out [list [dict get $data title] $id]
		}
		if {[llength $out] >= $limit} break
	}
	return [lrange $out 0 [expr {$limit - 1}]]
}

# ----------------------------------------------------------------------
# The generic operator: every user-reachable registry action can be run
# by id through this tool. Confirmation, bulk and context gates are the
# registry's own (::action::run), not a second path.
# ----------------------------------------------------------------------
proc ::knowledge::RunAction {id argsDict} {
	if {$id eq ""} { return "error: an action id is required" }
	if {![dict exists $::action::Registry $id]} { return "error: unknown action id '$id'" }
	set rec [::action::get $id]
	if {$id in $::knowledge::Exempt} { return "error: '$id' is not an action the assistant may run" }
	if {[dict get $rec ai] eq "debug"} {
		set enabled 0
		catch { set enabled $::application::assistant::Priv(debug) }
		if {!$enabled} { return "error: '$id' is only available in debug mode" }
	}
	if {![dict get $rec operator] && [dict get $rec ai] ne "1"} {
		return "error: '$id' is not exposed to the assistant"
	}
	# a row the menus would not offer now (no object for a context-menu
	# row, a disabled command) is refused, as a click on it would be
	lassign [Runnable $id [_dg $argsDict object {}]] ok why
	if {!$ok} {
		return "error: precondition: '$id' is $why, so nothing was done; run a runnable action from find_capability instead"
	}
	if {[::context::NeedsObject $rec $argsDict]
	 && (![dict exists $argsDict object] || [dict get $argsDict object] eq "")} {
		set selected [::context::CurrentObjectFor $id]
		if {![llength $selected]} { return "error: precondition: select an item before running $id" }
		dict set argsDict object [lindex $selected 1]
	}
	set reply [::action::run $id $argsDict]
	if {[string trim $reply] eq ""} {
		# the handler reported nothing: say exactly what ran, no more
		set reply "ran '[LabelText [dict get $rec label]]' ($id); it reported no further result"
	}
	return $reply
}

# ----------------------------------------------------------------------
# Generate the deterministic pack.
# ----------------------------------------------------------------------
proc ::knowledge::_writeActions {path} {
	set parts {}
	foreach id [PackIds] {
		lappend parts [_recordJson [_actionCanonical $id]]
	}
	set f [open $path w]
	fconfigure $f -encoding utf-8 -translation lf
	puts -nonewline $f "\[[join $parts ,]\]\n"
	close $f
}

proc ::knowledge::_writeTopics {path} {
	set parts {}
	foreach topic [PackTopicList] {
		set steps {}
		foreach step [dict get $topic steps] {
			set args {}
			dict for {k v} [dict get $step args] {
				lappend args "[_jsonEscape $k]:[_jsonEscape $v]"
			}
			lappend steps "\{\"action\":[_jsonEscape [dict get $step action]],\"label\":[_jsonEscape [dict get $step label]],\"args\":\{[join $args ,]\}\}"
		}
		set keywords {}
		foreach k [dict get $topic keywords] { lappend keywords [_jsonEscape $k] }
		lappend parts "\{\"id\":[_jsonEscape [dict get $topic id]],\"title\":[_jsonEscape [dict get $topic title]],\"purpose\":[_jsonEscape [dict get $topic purpose]],\"keywords\":\[[join $keywords ,]\],\"steps\":\[[join $steps ,]\]\}"
	}
	set f [open $path w]
	fconfigure $f -encoding utf-8 -translation lf
	puts -nonewline $f "\[[join $parts ,]\]\n"
	close $f
}

proc ::knowledge::Generate {dir} {
	variable PackLoaded
	variable PackActions
	variable PackTopics

	FillAll
	# Always regenerate from the live registry, never from a stale pack.
	set PackLoaded 0
	set PackActions {}
	foreach id [PackIds] { lappend PackActions [_actionCanonical $id] }
	set PackTopics [PackTopicList]
	BuildIndex

	file mkdir $dir
	_writeActions [file join $dir actions.json]
	_writeTopics [file join $dir topics.json]
	set f [open [file join $dir registry.sha256] w]
	fconfigure $f -translation lf
	puts -nonewline $f "[RegistryHash]\n"
	close $f
	set f [open [file join $dir README.txt] w]
	fconfigure $f -translation lf
	puts -nonewline $f "Chesswiz knowledge pack\nGenerated from the action registry by tcl/knowledge.tcl.\nDo not edit by hand: run 'make knowledge'.\nActions: [llength $PackActions]\nTopics: [llength $PackTopics]\n"
	close $f
	set PackLoaded 1
	return [file join $dir actions.json]
}

proc ::knowledge::Drift {dir} {
	set file [file join $dir registry.sha256]
	if {![file isfile $file]} { return "missing pack hash in $dir" }
	set f [open $file r]
	set expected [string trim [read $f]]
	close $f
	set actual [RegistryHash]
	if {$expected ne $actual} { return "knowledge pack is stale: registry $actual, pack $expected" }
	return ""
}

# ----------------------------------------------------------------------
# Coverage (VAL-AI-009): every posted surface row maps to a registry id
# that the assistant can run; the exempt list stays short and explained.
# ----------------------------------------------------------------------
proc ::knowledge::ExemptList {} {
	return [list \
		[list context.ask "the Ask field itself opens the assistant"] \
	]
}

proc ::knowledge::Coverage {} {
	FillAll
	set exposed 0
	set unmapped {}
	set rows 0

	set ids [lsort [::action::list]]
	foreach id $ids {
		set rec [::action::get $id]
		if {[InScope $id $rec]} { incr exposed }
	}

	# Drop-down and context rows are registry rows by construction; the
	# posted surfaces are walked live by the test. Here we check the
	# registry-side contract: every such row is operator-exposed.
	foreach id $ids {
		set rec [::action::get $id]
		set surfaces [Surface $id $rec]
		if {![llength $surfaces]} { continue }
		incr rows
		if {$id in $::knowledge::Exempt} { continue }
		if {![dict get $rec operator] && [dict get $rec ai] ne "1"} {
			lappend unmapped $id
		}
	}
	return [dict create \
		rows $rows \
		exposed $exposed \
		unmapped $unmapped \
		exempt [ExemptList] \
		before 87 \
	]
}

# Reviewed native knowledge: board
dict set ::knowledge::Explicit board-null-move [dict create purpose {Pass the turn without moving a piece in the current game.} when {Use this to explore what the other side could do with an extra turn.} examples {{Let the other side move now} {Skip a turn in this analysis}}]
dict set ::knowledge::Explicit c1.board_setup [dict create purpose {Open the board appearance settings for the clicked board.} when {Use this when the board colors or pieces are hard to see.} examples {{Change the pieces on this board} {Adjust this board's colors}}]
dict set ::knowledge::Explicit c1.copy_diagram [dict create purpose {Copy a picture of the current position to the clipboard.} when {Use this to include the board in another document.} examples {{Copy this board as a picture} {Put a diagram of this position on the clipboard}}]
dict set ::knowledge::Explicit c1.copy_fen [dict create purpose {Copy the current position as position text to the clipboard.} when {Use this to transfer the exact board position to another chess tool.} examples {{Copy the position text from this board} {Put this board position on the clipboard as text}}]
dict set ::knowledge::Explicit c1.edit_annotation [dict create purpose {Open the symbol editor for the current move.} when {Use this to mark a move as good, bad or interesting.} examples {{Edit the symbols on this move} {Mark this move with an annotation symbol}}]
dict set ::knowledge::Explicit c1.flip_board [dict create purpose {Turn the clicked board around so the other side is at the bottom.} when {Use this to study the position from the opponent's side.} examples {{Turn this board around} {Show the other side at the bottom of this board}}]
dict set ::knowledge::Explicit c1.insert_null [dict create purpose {Insert a turn without a piece move at the current position.} when {Use this to test a threat as if the opponent had passed.} examples {{Pass a turn from this board menu} {Give the other side an extra turn here}}]
dict set ::knowledge::Explicit c1.set_start_board [dict create purpose {Open the piece-placement editor from the clicked board.} when {Use this to enter a position that does not begin with the usual arrangement.} examples {{Set up pieces from this board} {Enter a custom board arrangement here}}]
dict set ::knowledge::Explicit c1.set_start_position [dict create purpose {Open the starting-position chooser from the clicked board.} when {Use this to select the initial arrangement for a new game.} examples {{Choose the starting arrangement here} {Open the start-position chooser for this board}}]
dict set ::knowledge::Explicit c1.start.chess960 [dict create purpose {Choose a starting arrangement with the Chess960 piece-placement rules.} when {Use this to begin a game with a randomized back rank and its castling rules.} examples {{Choose a Chess960 start from this board} {Randomize this board for a Chess960 game}}]
dict set ::knowledge::Explicit c1.start.setup [dict create purpose {Open a board where you can place the pieces yourself.} when {Use this when you have a position to enter by hand.} examples {{Place pieces manually from this board menu} {Set up an arbitrary position here}}]
dict set ::knowledge::Explicit c1.start.shuffle [dict create purpose {Choose a shuffled starting arrangement for the pieces.} when {Use this to explore games with a different initial back rank.} examples {{Shuffle this board's starting pieces} {Choose a shuffled start here}}]
dict set ::knowledge::Explicit c1.start.standard [dict create purpose {Choose the usual starting arrangement for ordinary chess.} when {Use this to return from an unusual setup to a regular game.} examples {{Use the normal start from this board menu} {Put the ordinary starting pieces on this board}}]
dict set ::knowledge::Explicit c1.start.symm960 [dict create purpose {Choose a symmetric randomized starting arrangement.} when {Use this to explore the symmetric form of shuffled chess.} examples {{Choose a symmetric random start here} {Start a Symm960 position from this board menu}}]
dict set ::knowledge::Explicit c1.start_position [dict create purpose {Show the starting-arrangement choices for the board.} when {Use this when deciding between ordinary chess and a shuffled start.} examples {{Show this board's starting-position choices} {Which initial arrangements can I choose here?}}]
dict set ::knowledge::Explicit menu.board.set_start_board [dict create purpose {Open the editor for placing pieces on a starting board.} when {Use this when entering a position from a diagram.} examples {{Open the starting-board editor} {Enter the pieces from my diagram}}]
dict set ::knowledge::Explicit menu.board.set_start_position [dict create purpose {Open the chooser for the game's initial arrangement.} when {Use this when selecting a numbered or randomized starting position.} examples {{Choose an initial arrangement for the game} {Open the starting-position dialog}}]
dict set ::knowledge::Explicit menu.board.setup [dict create purpose {Open settings for the board's pieces, colors and display.} when {Use this when tailoring the board for comfortable viewing.} examples {{Open board appearance settings} {Customize the board display}}]
dict set ::knowledge::Explicit menu.board.start.chess960 [dict create purpose {Select a Chess960 starting arrangement for the game.} when {Use this to play with a randomized back rank under Chess960 rules.} examples {{Start a new Chess960 arrangement} {Choose a random Chess960 back rank}}]
dict set ::knowledge::Explicit menu.board.start.setup [dict create purpose {Show the menu of available starting positions.} when {Use this to choose a different setup for the game.} examples {{Show the available starting setups} {Open the position setup menu}}]
dict set ::knowledge::Explicit menu.board.start.shuffle [dict create purpose {Select a shuffled starting arrangement for the game.} when {Use this to try a nonstandard initial piece order.} examples {{Start with shuffled pieces} {Choose a shuffle-chess starting position}}]
dict set ::knowledge::Explicit menu.board.start.standard [dict create purpose {Restore the ordinary chess starting arrangement.} when {Use this when returning to a regular game after a custom setup.} examples {{Choose the standard chess start} {Return to the usual starting arrangement}}]
dict set ::knowledge::Explicit menu.board.start.symm960 [dict create purpose {Select a symmetric randomized arrangement for the game.} when {Use this to try the symmetric shuffled-chess variant.} examples {{Choose a Symm960 starting arrangement} {Start with symmetric randomized pieces}}]
dict set ::knowledge::Explicit menu.board.appearance.annotation [dict create purpose {Show or hide move annotation symbols on the board.} when {Use this when symbols distract from the pieces or should be visible.} examples {{Toggle board annotation symbols} {Show move annotations on the board}}]
dict set ::knowledge::Explicit menu.board.appearance.arrows [dict create purpose {Show or hide arrows for alternative continuations on the board.} when {Use this when comparing candidate lines visually.} examples {{Toggle variation arrows on the board} {Hide the arrows for alternative lines}}]
dict set ::knowledge::Explicit menu.board.appearance.border [dict create purpose {Show or hide the border around the board.} when {Use this when adjusting the board's visual framing.} examples {{Toggle the board border} {Remove the frame around the squares}}]
dict set ::knowledge::Explicit menu.board.appearance.coordinates [dict create purpose {Show or hide the board's file letters and rank numbers.} when {Use this when square names would help you follow the moves.} examples {{Toggle square coordinates} {Show the letters and numbers around the board}}]
dict set ::knowledge::Explicit menu.board.appearance.material [dict create purpose {Show or hide the board's material display.} when {Use this to see the balance of captured pieces beside the position.} examples {{Toggle the material display} {Show the material balance next to the board}}]
dict set ::knowledge::Explicit menu.board.appearance.side [dict create purpose {Show or hide the indicator of whose turn it is.} when {Use this when you need a visible reminder of the side to move.} examples {{Toggle the side-to-move indicator} {Show whose turn it is beside the board}}]
dict set ::knowledge::Explicit menu.board.appearance.small_letters [dict create purpose {Switch the board coordinate letters between small and large forms.} when {Use this to change how the file labels look.} examples {{Toggle small coordinate letters} {Change the case of the board's file labels}}]
dict set ::knowledge::Explicit menu.board.appearance.suggested [dict create purpose {Show or hide the suggested-move marker on the board.} when {Use this when you want to see or conceal the current suggestion.} examples {{Toggle the suggested move on the board} {Hide the board's suggested-move marker}}]
dict set ::knowledge::Explicit c9.board_setup [dict create purpose {Open appearance settings from the board pane's header.} when {Use this to customize the board while arranging its pane.} examples {{Configure the board from its pane header} {Change board appearance using the pane menu}}]
dict set ::knowledge::Explicit c9.flip_board [dict create purpose {Reverse the main board's viewing direction from its pane menu.} when {Use this to look at the game with the other player at the bottom.} examples {{Flip the main board from the pane menu} {Reverse the board view using its header}}]
dict set ::knowledge::Explicit c9.start_position [dict create purpose {Show initial-arrangement choices from the board pane.} when {Use this to begin a different kind of game from the pane header.} examples {{Show start-position options in the board pane} {Choose a starting setup through the pane menu}}]
# End reviewed native knowledge: board

# Reviewed native knowledge: notation
dict set ::knowledge::Explicit c2.add_variation [dict create purpose {Add the selected continuation as an alternative to the game move.} when {Use this to keep another possible reply beside the main line.} examples {{Add this continuation as a side line} {Keep this move as an alternative}}]
dict set ::knowledge::Explicit c2.annot.infix [dict create purpose {Open the move-symbol editor for symbols within the notation.} when {Use this to attach a symbolic assessment to the current move.} examples {{Edit the assessment symbol within this move} {Choose an infix annotation for this move}}]
dict set ::knowledge::Explicit c2.annot.prefix [dict create purpose {Open the move-symbol editor for symbols before the move.} when {Use this to add a symbolic note ahead of the move text.} examples {{Choose an annotation before this move} {Edit this move's prefix symbols}}]
dict set ::knowledge::Explicit c2.annot.suffix [dict create purpose {Open the move-symbol editor for symbols after the move.} when {Use this to mark the quality of a move beside its notation.} examples {{Choose a symbol after this move} {Edit this move's suffix annotations}}]
dict set ::knowledge::Explicit c2.annotate [dict create purpose {Show the choices for annotating the current move with symbols.} when {Use this when a short symbol can express your comment.} examples {{Show annotation choices for this move} {How can I mark this move with a symbol?}}]
dict set ::knowledge::Explicit c2.collapse [dict create purpose {Fold the game's alternative lines in the notation.} when {Use this to read the main continuation without expanded branches.} examples {{Fold the side lines in this notation} {Collapse all game variations here}}]
dict set ::knowledge::Explicit c2.comment_after [dict create purpose {Open the text comment following the current move for editing.} when {Use this to explain the position reached by that move.} examples {{Edit the comment following this move} {Add a note after the selected move}}]
dict set ::knowledge::Explicit c2.comment_before [dict create purpose {Open the text comment preceding the current move for editing.} when {Use this to introduce a move before the reader reaches it.} examples {{Edit the note preceding this move} {Add an introduction before the selected move}}]
dict set ::knowledge::Explicit c2.copy_comments [dict create purpose {Open the options for copying the game's comments.} when {Use this to reuse written annotations separately from the moves.} examples {{Copy comments from this game's notation} {Open the comment-copy options}}]
dict set ::knowledge::Explicit c2.exchange_move [dict create purpose {Exchange the current game continuation with the selected alternative move.} when {Use this when a side-line move should take the current move's place.} examples {{Exchange this move with its alternative} {Swap the selected continuation into the game}}]
dict set ::knowledge::Explicit c2.expand [dict create purpose {Unfold the game's alternative lines in the notation.} when {Use this to read branches that are currently hidden.} examples {{Expand all side lines in this notation} {Show the folded variations here}}]
dict set ::knowledge::Explicit c2.explain_move [dict create purpose {Request an explanation of the current move using the app's analysis.} when {Use this when reviewing why a move was played.} examples {{Explain the selected notation move} {Help me understand this move in the game}}]
dict set ::knowledge::Explicit c2.import_game [dict create purpose {Read a complete game from the system clipboard into the notation.} when {Use this after copying a game in portable game text.} examples {{Import the copied game into this notation} {Read the clipboard as a complete game here}}]
dict set ::knowledge::Explicit c2.import_variation [dict create purpose {Read clipboard moves as an alternative line at the current position.} when {Use this to add analysis copied from another source.} examples {{Import the clipboard as a side line here} {Add the copied variation to this position}}]
dict set ::knowledge::Explicit c2.insert_diagram [dict create purpose {Mark the current move for a diagram viewed from White's side.} when {Use this to illustrate the position in printed or displayed notation.} examples {{Insert a White-side diagram here} {Mark this position for a diagram from White}}]
dict set ::knowledge::Explicit c2.insert_diagram_black [dict create purpose {Mark the current move for a diagram viewed from Black's side.} when {Use this when an illustration should face the other player.} examples {{Insert a Black-side diagram here} {Mark this position for a diagram from Black}}]
dict set ::knowledge::Explicit c2.load_continuation [dict create purpose {Load the first database game containing the chosen continuation.} when {Use this to study a full game that follows this move.} examples {{Find the first game with this continuation} {Load a database example of this move sequence}}]
dict set ::knowledge::Explicit c2.marks_palette [dict create purpose {Open the palette for colored board marks and arrows.} when {Use this to draw attention to squares or plans in the position.} examples {{Open the board-mark palette from this move} {Choose arrows or colored squares for this position}}]
dict set ::knowledge::Explicit c2.move_info [dict create purpose {Open the editor for information attached to the current move.} when {Use this to change recorded analysis or clock details for a move.} examples {{Edit the information stored with this move} {Open this move's information editor}}]
dict set ::knowledge::Explicit c2.new_main_line [dict create purpose {Promote the selected continuation into the game's main line.} when {Use this when the alternative should become the principal continuation.} examples {{Make this continuation the main line} {Use the selected branch as the game continuation}}]
dict set ::knowledge::Explicit c2.promote_variation [dict create purpose {Raise the current variation above its competing continuation.} when {Use this when organizing the preferred order of alternatives.} examples {{Promote this side line} {Move this variation ahead of its competing line}}]
dict set ::knowledge::Explicit c2.redo [dict create purpose {Reapply the last undone change to the game notation.} when {Use this after undoing an edit you want to keep.} examples {{Redo the last notation edit} {Reapply the game change I just undid}}]
dict set ::knowledge::Explicit c2.remove_variation [dict create purpose {Delete the current alternative line from the game.} when {Use this to remove analysis you no longer want to retain.} examples {{Remove this side line from the game} {Delete the selected variation here}}]
dict set ::knowledge::Explicit c2.replace_move [dict create purpose {Replace the game's current move with the selected continuation.} when {Use this to correct a move while editing the game.} examples {{Replace this move with the selected alternative} {Correct the current game move here}}]
dict set ::knowledge::Explicit c2.strip [dict create purpose {Show choices for removing moves or annotations from the game.} when {Use this to clean selected kinds of recorded content.} examples {{Show ways to clean this game's notation} {Choose which game annotations to remove}}]
dict set ::knowledge::Explicit c2.strip.annotations [dict create purpose {Remove symbolic move annotations from the current game.} when {Use this to retain moves and prose without quality symbols.} examples {{Remove the game's symbolic annotations} {Clear move-quality symbols from this game}}]
dict set ::knowledge::Explicit c2.strip.comments [dict create purpose {Remove text comments from the current game.} when {Use this to obtain move notation without prose annotations.} examples {{Remove all text comments from this game} {Clear the written notes in this game's notation}}]
dict set ::knowledge::Explicit c2.strip.info [dict create purpose {Remove stored move-information fields from the current game.} when {Use this to discard per-move details while retaining the moves.} examples {{Remove this game's move-information fields} {Clear recorded clock and analysis information from moves}}]
dict set ::knowledge::Explicit c2.strip.marks [dict create purpose {Remove colored squares and arrows stored with the game.} when {Use this when board markings should no longer accompany the moves.} examples {{Remove the game's board marks} {Clear saved arrows and colored squares from this game}}]
dict set ::knowledge::Explicit c2.strip.moves [dict create purpose {Remove the move text from the current game.} when {Use this when retaining the game record without its played continuation.} examples {{Remove the current game's moves} {Clear the recorded moves while editing this game}}]
dict set ::knowledge::Explicit c2.strip.variations [dict create purpose {Remove alternative continuations from the current game.} when {Use this to keep only the main game line.} examples {{Remove all side variations from this game} {Keep the main line and discard its alternatives}}]
dict set ::knowledge::Explicit c2.try_variation [dict create purpose {Switch temporary trial analysis on or off for the notation.} when {Use this to explore moves without committing them to the game.} examples {{Try a temporary variation here} {Toggle trial mode for this notation}}]
dict set ::knowledge::Explicit c2.undo [dict create purpose {Reverse the last change to the game notation.} when {Use this to recover from an unwanted edit.} examples {{Undo the last notation change} {Reverse my most recent game edit}}]
dict set ::knowledge::Explicit c11.add_language [dict create purpose {Add a language section to the comment being edited.} when {Use this when the same position needs comments in several languages.} examples {{Add another language to this comment} {Create a new language section in the comment editor}}]
dict set ::knowledge::Explicit c11.classify_comment [dict create purpose {Classify the comment through the app's comment-classification workflow.} when {Use this to organize an annotation by its content.} examples {{Classify the comment I am editing} {Determine this annotation's content category}}]
dict set ::knowledge::Explicit c11.clear [dict create purpose {Erase the current comment editor's text.} when {Use this to start the current comment again.} examples {{Clear this comment's text} {Empty the comment editor for this language}}]
dict set ::knowledge::Explicit c11.copy [dict create purpose {Copy selected comment content to the clipboard.} when {Use this to reuse part of an annotation elsewhere.} examples {{Copy the selected comment content} {Put this comment selection on the clipboard}}]
dict set ::knowledge::Explicit c11.copy_text [dict create purpose {Copy the current comment into another language section.} when {Use this as a starting text for another translation.} examples {{Copy this comment into another language section} {Reuse this annotation text in a different language tab}}]
dict set ::knowledge::Explicit c11.cut [dict create purpose {Remove the selected comment content and copy it to the clipboard.} when {Use this to move part of a comment elsewhere.} examples {{Cut the selected comment content} {Move this comment selection to the clipboard}}]
dict set ::knowledge::Explicit c11.detect_language [dict create purpose {Detect the language of the comment being edited.} when {Use this when pasted text is under the wrong language section.} examples {{Identify this comment's language} {Detect the language of this annotation}}]
dict set ::knowledge::Explicit c11.display_emoticons [dict create purpose {Switch comment emoticons between pictures and their text forms.} when {Use this when choosing how expressive symbols appear in the editor.} examples {{Toggle pictures for comment emoticons} {Change how emoticons appear in this comment}}]
dict set ::knowledge::Explicit c11.explain_comment [dict create purpose {Request an explanation of the current comment in its position.} when {Use this when an annotation's meaning is unclear.} examples {{Explain the comment in this editor} {Help me understand this written annotation}}]
dict set ::knowledge::Explicit c11.format [dict create purpose {Show text-formatting options for the comment selection.} when {Use this when emphasizing or arranging an annotation.} examples {{Show formatting choices for this comment} {Format the selected annotation text}}]
dict set ::knowledge::Explicit c11.insert_emoticon [dict create purpose {Insert a chosen emoticon into the comment.} when {Use this to express a reaction with a visual symbol.} examples {{Insert an emoticon in this annotation} {Add an expressive face to this comment}}]
dict set ::knowledge::Explicit c11.insert_symbol [dict create purpose {Insert a chosen chess symbol into the comment.} when {Use this when a piece or assessment symbol is clearer than words.} examples {{Insert a chess symbol in this comment} {Add a piece symbol to the annotation text}}]
dict set ::knowledge::Explicit c11.paste [dict create purpose {Insert clipboard content into the comment editor.} when {Use this to reuse text you have already copied.} examples {{Paste the clipboard into this comment} {Insert copied annotation text here}}]
dict set ::knowledge::Explicit c11.redo [dict create purpose {Reapply the last undone comment edit.} when {Use this when a reversed text change should be restored.} examples {{Redo my last comment edit} {Restore the text change I undid in this annotation}}]
dict set ::knowledge::Explicit c11.revert [dict create purpose {Restore the comment to its original editor contents.} when {Use this to discard your unsaved comment edits.} examples {{Revert this comment to its original text} {Discard the changes in this comment editor}}]
dict set ::knowledge::Explicit c11.select_all [dict create purpose {Select all text in the current comment editor.} when {Use this before copying or replacing the entire annotation.} examples {{Select the whole comment text} {Highlight everything in this comment editor}}]
dict set ::knowledge::Explicit c11.switch_language [dict create purpose {Show the comment text for a chosen language.} when {Use this to review another translation of the same annotation.} examples {{Switch this comment to another language section} {Show a different language version of this comment}}]
dict set ::knowledge::Explicit c11.translate_comment [dict create purpose {Show target-language choices for translating the comment.} when {Use this when creating another language version of an annotation.} examples {{Translate this comment into another language} {Show translation targets for this annotation}}]
dict set ::knowledge::Explicit c11.undo [dict create purpose {Reverse the last edit in the comment editor.} when {Use this to recover comment text changed by mistake.} examples {{Undo my last comment edit} {Reverse the latest annotation text change}}]
# End reviewed native knowledge: notation

# Reviewed native knowledge: games
dict set ::knowledge::Explicit c3.ask_about_game [dict create purpose {Send the selected game's identity to the Assistant.} when {Use this when you want help with a particular database row.} examples {{Ask the Assistant about this game row} {Discuss the selected database game}}]
dict set ::knowledge::Explicit c3.browse [dict create purpose {Open the selected game in a separate game browser.} when {Use this to inspect a game without replacing the board's game.} examples {{Browse this game separately} {Preview the selected game in its own browser}}]
dict set ::knowledge::Explicit c3.copy_game [dict create purpose {Copy selected game rows to the internal game clipboard.} when {Use this to transfer one or more games between databases.} examples {{Copy these selected game rows} {Put the selected games in the game clipboard}}]
dict set ::knowledge::Explicit c3.delete [dict create purpose {Toggle the deletion mark on the selected game.} when {Use this to exclude a game or restore a previously marked record.} examples {{Mark this game as deleted} {Undelete this database game}}]
dict set ::knowledge::Explicit c3.edit_characteristics [dict create purpose {Open the selected game's player and event information for editing.} when {Use this to correct the details identifying a database game.} examples {{Edit the selected game's identifying details} {Correct the players or event of this game row}}]
dict set ::knowledge::Explicit c3.flags [dict create purpose {Show the available classification flags for the selected game.} when {Use this to organize games by themes for later retrieval.} examples {{Show classification flags for this game} {Choose a thematic flag for the selected game}}]
dict set ::knowledge::Explicit c3.games_like [dict create purpose {Find database games similar to the selected game.} when {Use this to gather comparable examples for study.} examples {{Find games resembling this selected game} {Show similar games for this database row}}]
dict set ::knowledge::Explicit c3.load [dict create purpose {Load the selected database game onto the main board.} when {Use this to follow its moves in the normal game view.} examples {{Load this selected game onto the board} {Open the game in this database row}}]
dict set ::knowledge::Explicit c3.merge [dict create purpose {Open the merge workflow for the selected database game.} when {Use this to combine its continuations with an open game.} examples {{Merge this selected database game} {Combine the game in this row with my analysis}}]
dict set ::knowledge::Explicit c3.open_url [dict create purpose {Open the web address recorded as the selected game's site.} when {Use this when a game's site field contains a link you want to visit.} examples {{Open this game's site link} {Visit the web address stored with this game}}]
dict set ::knowledge::Explicit c3.overview [dict create purpose {Open a compact overview of the selected game.} when {Use this to scan its positions before choosing it for study.} examples {{Show an overview of this game row} {Preview the selected game's key positions}}]
dict set ::knowledge::Explicit c3.paste_games [dict create purpose {Paste games from the internal clipboard into the selected database.} when {Use this to transfer games copied from another database.} examples {{Paste copied games into this database} {Insert the game clipboard's contents here}}]
dict set ::knowledge::Explicit c3.sort.asc [dict create purpose {Order the game rows upward by the clicked column.} when {Use this to inspect that column from its smallest value.} examples {{Use ascending order for this game column} {Put smaller values first in this game list}}]
dict set ::knowledge::Explicit c3.sort.column [dict create purpose {Order the game rows by the column under the menu.} when {Use this to regroup the visible games by a chosen field.} examples {{Sort using the column I clicked} {Order this game list by the selected field}}]
dict set ::knowledge::Explicit c3.sort.desc [dict create purpose {Order the game rows downward by the clicked column.} when {Use this to inspect that column from its largest value.} examples {{Use descending order for this game column} {Put larger values first in this game list}}]
dict set ::knowledge::Explicit c3.sort_asc [dict create purpose {Sort the game list in ascending order using the clicked field.} when {Use this to bring the earliest or smallest entries to the top.} examples {{Sort these game rows upward} {Show the earliest values first in this column}}]
dict set ::knowledge::Explicit c3.sort_column [dict create purpose {Sort the games by the field selected in the column menu.} when {Use this to change which game information controls the row order.} examples {{Choose this column for game ordering} {Arrange the games by this clicked field}}]
dict set ::knowledge::Explicit c3.sort_desc [dict create purpose {Sort the game list in descending order using the clicked field.} when {Use this to bring the latest or largest entries to the top.} examples {{Sort these game rows downward} {Show the latest values first in this column}}]
dict set ::knowledge::Explicit c3.tournament [dict create purpose {Open the tournament table associated with the selected game.} when {Use this to see the game's event results in context.} examples {{Show the tournament table for this game row} {Open the event standings linked to this game}}]
dict set ::knowledge::Explicit c12.clear_history [dict create purpose {Clear the list of previously opened games.} when {Use this when you no longer need the game-history entries.} examples {{Clear the game history from this tab menu} {Forget the previously opened game entries here}}]
dict set ::knowledge::Explicit c12.close_tab [dict create purpose {Close the selected game tab after checking unsaved changes.} when {Use this when you have finished working with that open game.} examples {{Close this selected game tab} {Remove this game from the open tabs}}]
dict set ::knowledge::Explicit c12.copy_clipboard [dict create purpose {Copy the selected tab's game as text to the system clipboard.} when {Use this to paste the game into another program.} examples {{Copy this game tab as portable game text} {Put this tab's game on the system clipboard}}]
dict set ::knowledge::Explicit c12.copy_game [dict create purpose {Copy the selected tab's game to the internal clipboard database.} when {Use this to keep a temporary database copy of an open game.} examples {{Copy this tab into the clipboard database} {Keep an internal copy of this open game}}]
dict set ::knowledge::Explicit c12.export [dict create purpose {Open export options for the selected game tab.} when {Use this to save that game in a shareable file.} examples {{Export the game in this tab} {Save this open game to an export file}}]
dict set ::knowledge::Explicit c12.import_game [dict create purpose {Open the portable-game-text import workflow.} when {Use this to bring a recorded game into the app.} examples {{Import a game from the game-tab menu} {Open game-text import for this tab}}]
dict set ::knowledge::Explicit c12.load_number [dict create purpose {Ask for a database game number to load.} when {Use this when you know the record number of the game you want.} examples {{Load a numbered game from this tab menu} {Choose a database game by its record number here}}]
dict set ::knowledge::Explicit c12.merge [dict create purpose {Show choices for combining another game with this one.} when {Use this to collect alternative continuations in one game.} examples {{Show merge choices for this game tab} {Choose a game to combine with this tab}}]
dict set ::knowledge::Explicit c12.merge.game [dict create purpose {Merge the chosen game tab into the current game's continuations.} when {Use this to collect analysis from another open game.} examples {{Merge this tab's game into my current analysis} {Combine the chosen open game with the current one}}]
dict set ::knowledge::Explicit c12.new.chess960 [dict create purpose {Replace the board game with a fresh Chess960 start.} when {Use this to begin another randomized-back-rank game.} examples {{Start a Chess960 game from this tab menu} {Create a fresh randomized game here}}]
dict set ::knowledge::Explicit c12.new.standard [dict create purpose {Create a new ordinary chess game from the game-tab menu.} when {Use this to begin recording a game from the normal start.} examples {{Start a standard game from this tab menu} {Create a fresh ordinary game here}}]
dict set ::knowledge::Explicit c12.new_game [dict create purpose {Show the available kinds of new game in the tab menu.} when {Use this when choosing the starting rules for a fresh game.} examples {{Show new-game choices from this tab} {Choose the kind of game to create here}}]
dict set ::knowledge::Explicit c12.paste [dict create purpose {Show choices for inserting copied moves as a game or variation.} when {Use this to decide how clipboard notation joins the current game.} examples {{Show paste choices for this game tab} {Choose whether copied moves replace or extend the game}}]
dict set ::knowledge::Explicit c12.paste.game [dict create purpose {Read clipboard game text as a complete game.} when {Use this when the copied notation includes the whole game.} examples {{Paste a complete game from this tab menu} {Use the clipboard as a game here}}]
dict set ::knowledge::Explicit c12.paste.variation [dict create purpose {Read clipboard move text as a variation of the current game.} when {Use this to add copied analysis at the board position.} examples {{Paste a side line from this tab menu} {Insert the copied continuation as a variation here}}]
dict set ::knowledge::Explicit c12.reload [dict create purpose {Reload the current game from its stored database record.} when {Use this to discard edits and return to the saved version.} examples {{Reload the saved game from this tab menu} {Restore this game's database version here}}]
dict set ::knowledge::Explicit c12.remove_history [dict create purpose {Remove this game's entry from the recent-game history.} when {Use this when a single history entry is no longer useful.} examples {{Remove this game from recent history} {Forget only this selected history entry}}]
dict set ::knowledge::Explicit c12.save.new [dict create purpose {Save the selected tab's game as an additional database record.} when {Use this to preserve a new version without replacing an existing game.} examples {{Save this game tab as a new record} {Add this open game to the database separately}}]
dict set ::knowledge::Explicit c12.save.replace [dict create purpose {Save the selected tab's game over its existing database record.} when {Use this when your edits should replace the saved game.} examples {{Replace the stored record with this tab's game} {Save this open game's edits over the original}}]
dict set ::knowledge::Explicit c12.save.replace_moves [dict create purpose {Save the selected tab's moves through the replace-moves workflow.} when {Use this when updating the recorded continuation of a stored game.} examples {{Replace the stored moves from this tab} {Save this tab through the move-replacement command}}]
dict set ::knowledge::Explicit c12.save_game [dict create purpose {Show the save destinations and modes for the game tab.} when {Use this when deciding whether to replace or add a record.} examples {{Show save choices for this game tab} {Choose how to store this open game}}]
dict set ::knowledge::Explicit menu.game.copy [dict create purpose {Copy the current game into the temporary clipboard database.} when {Use this to retain a working copy before changing games.} examples {{Copy my current game to the temporary database} {Keep a clipboard-database copy of the board game}}]
dict set ::knowledge::Explicit menu.game.export.study [dict create purpose {Open the study-upload dialog for the current game.} when {Use this to share the game through a Lichess study.} examples {{Upload the current game to a study} {Open study sharing for the board game}}]
dict set ::knowledge::Explicit menu.game.history.clear [dict create purpose {Clear the app's recent-game history through the main menu.} when {Use this to remove the list of previously visited games.} examples {{Clear recent games from the main menu} {Erase the recent-game list}}]
dict set ::knowledge::Explicit menu.game.history.recent [dict create purpose {Show recently opened games for loading again.} when {Use this to return to a game you viewed earlier.} examples {{Show recently visited games} {Choose a game from my recent history}}]
dict set ::knowledge::Explicit menu.game.merge_clip [dict create purpose {Merge games from the temporary clipboard database into the current game.} when {Use this to combine copied analysis with the board game.} examples {{Merge the clipboard database into this game} {Combine temporary clipboard games with the current line}}]
dict set ::knowledge::Explicit menu.game.merge_tab [dict create purpose {Open a merge using another available game tab.} when {Use this to combine continuations from open games.} examples {{Merge another open tab into the board game} {Combine my open game tabs}}]
dict set ::knowledge::Explicit menu.game.paste_clip [dict create purpose {Read clipboard notation as the current game.} when {Use this to load a game copied as portable game text.} examples {{Paste the copied game through the main menu} {Load the game text currently on the clipboard}}]
dict set ::knowledge::Explicit menu.game.paste_tab [dict create purpose {Use the game-paste workflow from the game-tab source menu.} when {Use this when bringing copied game notation into the board.} examples {{Paste game notation using the tab-source command} {Open the tab-source paste workflow}}]
dict set ::knowledge::Explicit menu.game.random [dict create purpose {Load a randomly chosen game from the current database view.} when {Use this when you want an unplanned game to study.} examples {{Load a random database game} {Pick a game for me from this list}}]
dict set ::knowledge::Explicit menu.game.reload [dict create purpose {Restore the current game from the database.} when {Use this to return to the last saved version after editing.} examples {{Reload the board game from storage} {Discard my current game edits and reload it}}]
dict set ::knowledge::Explicit game-replace-moves [dict create purpose {Open the current game's save-replacement workflow.} when {Use this when updating an existing database game from the board.} examples {{Open the save replacement dialog for this game} {Update the stored game through Replace Moves}}]
dict set ::knowledge::Explicit c3.flag.1 [dict create purpose {Toggle the selected game's White-opening classification flag.} when {Use this to collect examples of openings played with White.} examples {{Flag this game as a White-opening example} {Remove this game's White-opening flag}}]
dict set ::knowledge::Explicit c3.flag.2 [dict create purpose {Toggle the selected game's Black-opening classification flag.} when {Use this to collect examples of openings played with Black.} examples {{Flag this game as a Black-opening example} {Remove this game's Black-opening flag}}]
dict set ::knowledge::Explicit c3.flag.3 [dict create purpose {Toggle the selected game's middlegame classification flag.} when {Use this to collect games for studying play after the opening.} examples {{Mark this game for middlegame study} {Remove this game's middlegame flag}}]
dict set ::knowledge::Explicit c3.flag.4 [dict create purpose {Toggle the selected game's endgame classification flag.} when {Use this to collect games for studying reduced-piece positions.} examples {{Mark this game for endgame study} {Remove this game's endgame flag}}]
dict set ::knowledge::Explicit c3.flag.5 [dict create purpose {Toggle the selected game's novelty classification flag.} when {Use this to collect games featuring an opening innovation.} examples {{Flag this game as an opening novelty} {Remove this game's novelty flag}}]
dict set ::knowledge::Explicit c3.flag.6 [dict create purpose {Toggle the selected game's pawn-structure classification flag.} when {Use this to collect examples of characteristic pawn formations.} examples {{Mark this game for pawn-structure study} {Remove this game's pawn-structure flag}}]
dict set ::knowledge::Explicit c3.flag.7 [dict create purpose {Toggle the selected game's tactics classification flag.} when {Use this to collect examples of forcing combinations.} examples {{Flag this game for tactics study} {Remove this game's tactics flag}}]
dict set ::knowledge::Explicit c3.flag.8 [dict create purpose {Toggle the selected game's kingside classification flag.} when {Use this to collect examples centered on that side of the board.} examples {{Flag this game for kingside study} {Remove this game's kingside flag}}]
dict set ::knowledge::Explicit c3.flag.9 [dict create purpose {Toggle the selected game's queenside classification flag.} when {Use this to collect games centered on the other side of the board.} examples {{Flag this game for queenside study} {Remove this game's queenside flag}}]
dict set ::knowledge::Explicit c3.flag.10 [dict create purpose {Toggle the selected game's brilliancy classification flag.} when {Use this to collect games you regard as especially impressive.} examples {{Mark this game as a brilliancy} {Remove this game's brilliancy flag}}]
dict set ::knowledge::Explicit c3.flag.11 [dict create purpose {Toggle the selected game's blunder classification flag.} when {Use this to collect games featuring a serious mistake.} examples {{Flag this game as a blunder example} {Remove this game's blunder flag}}]
dict set ::knowledge::Explicit c3.flag.12 [dict create purpose {Toggle the selected game's custom user classification flag.} when {Use this to group games under your own category.} examples {{Set the custom user flag on this game} {Remove this game's user flag}}]
dict set ::knowledge::Explicit c3.flag.13 [dict create purpose {Toggle the selected game's best-game classification flag.} when {Use this to collect games you want to single out as favorites.} examples {{Mark this game as one of the best} {Remove this game's best-game flag}}]
dict set ::knowledge::Explicit c3.flag.14 [dict create purpose {Toggle the selected game's tournament-decider classification flag.} when {Use this to collect games that settled an event's outcome.} examples {{Flag this game as a tournament decider} {Remove this game's decided-tournament flag}}]
dict set ::knowledge::Explicit c3.flag.15 [dict create purpose {Toggle the selected game's model-game classification flag.} when {Use this to collect instructive examples worth revisiting.} examples {{Mark this game as a model example} {Remove this game's model-game flag}}]
dict set ::knowledge::Explicit c3.flag.16 [dict create purpose {Toggle the selected game's strategy classification flag.} when {Use this to collect examples of long-term planning.} examples {{Flag this game for strategic study} {Remove this game's strategy flag}}]
dict set ::knowledge::Explicit c3.flag.17 [dict create purpose {Toggle the selected game's attack classification flag.} when {Use this to collect examples of offensive play.} examples {{Mark this game as an attacking example} {Remove this game's attack flag}}]
dict set ::knowledge::Explicit c3.flag.18 [dict create purpose {Toggle the selected game's sacrifice classification flag.} when {Use this to collect examples of giving up material for compensation.} examples {{Flag this game as a sacrifice example} {Remove this game's sacrifice flag}}]
dict set ::knowledge::Explicit c3.flag.19 [dict create purpose {Toggle the selected game's defense classification flag.} when {Use this to collect examples of resisting an opponent's threats.} examples {{Mark this game as a defensive example} {Remove this game's defense flag}}]
# End reviewed native knowledge: games

# Reviewed native knowledge: database
dict set ::knowledge::Explicit c4.close [dict create purpose {Close the selected database after checking for unsaved changes.} when {Use this when that database is no longer needed.} examples {{Close this selected database} {Finish with the database under this menu}}]
dict set ::knowledge::Explicit c4.download_games [dict create purpose {Open the game-download workflow for the active database.} when {Use this to obtain published game collections.} examples {{Download games through the database menu} {Open the game downloader from this database}}]
dict set ::knowledge::Explicit c4.export [dict create purpose {Show export destinations for games in the selected database view.} when {Use this to choose a file or study destination.} examples {{Show export choices for this database} {Choose where to send this database's games}}]
dict set ::knowledge::Explicit c4.export.lichess [dict create purpose {Open study-upload options for the selected database view.} when {Use this to share a collection through a Lichess study.} examples {{Upload this database view to a study} {Share these database games as a study}}]
dict set ::knowledge::Explicit c4.export.pgn [dict create purpose {Open text-file export for the selected database's games.} when {Use this to exchange the collection in portable game notation.} examples {{Export this database view as game text} {Write these database games to a portable text file}}]
dict set ::knowledge::Explicit c4.help [dict create purpose {Open the app's help from the database menu.} when {Use this when you need instructions while working with databases.} examples {{Open help from this database menu} {Show the manual while I work with this database}}]
dict set ::knowledge::Explicit c4.import [dict create purpose {Show the available game-import sources.} when {Use this when adding recorded games to a database.} examples {{Show import choices for databases} {Choose a source of games to import here}}]
dict set ::knowledge::Explicit c4.import.pgn [dict create purpose {Open the file chooser for importing portable game text.} when {Use this to add games saved in a text file.} examples {{Import game-text files from this database menu} {Add recorded text-file games here}}]
dict set ::knowledge::Explicit c4.maintenance [dict create purpose {Show maintenance operations for the selected database.} when {Use this when cleaning or reorganizing its stored records.} examples {{Show this database's maintenance choices} {Which cleanup operations are available for this database?}}]
dict set ::knowledge::Explicit c4.maintenance.compact [dict create purpose {Compact the selected database to reclaim unused storage.} when {Use this after marking records for deletion or making many changes.} examples {{Compact this selected database} {Reclaim unused space in this database}}]
dict set ::knowledge::Explicit c4.new.pgn [dict create purpose {Create a database backed by a portable-game-text file.} when {Use this when the collection should remain in an exchangeable text format.} examples {{Create a text-file database from this menu} {Start a new portable-game collection here}}]
dict set ::knowledge::Explicit c4.new.scid [dict create purpose {Create a database in Chesswiz's native storage format.} when {Use this for a new collection managed within the app.} examples {{Create a native database from this menu} {Start a new Chesswiz game collection here}}]
dict set ::knowledge::Explicit c4.new_database [dict create purpose {Show the database formats available for a new collection.} when {Use this when deciding how to store a new set of games.} examples {{Show new-database format choices} {Choose a storage format for a new game collection}}]
dict set ::knowledge::Explicit c4.open_database [dict create purpose {Open the file chooser for loading a database.} when {Use this when your game collection is not already open.} examples {{Open a database from this switcher menu} {Choose a game database file here}}]
dict set ::knowledge::Explicit c4.open_new_tab [dict create purpose {Open the selected database in an additional database tab.} when {Use this to keep another view of the same collection available.} examples {{Open this database in another tab} {Create an additional tab for this collection}}]
dict set ::knowledge::Explicit c4.open_recent [dict create purpose {Show previously opened database files for reopening.} when {Use this to return to a collection without locating its file again.} examples {{Show recent database choices here} {Reopen a collection from the database history}}]
dict set ::knowledge::Explicit c4.properties [dict create purpose {Show the selected database's information and properties.} when {Use this to inspect its identity and settings.} examples {{Show properties of this database} {Inspect this collection's database information}}]
dict set ::knowledge::Explicit c4.readonly [dict create purpose {Toggle whether the selected database accepts changes.} when {Use this to protect a collection from accidental edits.} examples {{Make this selected database read-only} {Allow edits in this database again}}]
dict set ::knowledge::Explicit c4.reports [dict create purpose {Show reports available for the selected database.} when {Use this when choosing a summary of the collection.} examples {{Show reports for this database} {Choose a database summary here}}]
dict set ::knowledge::Explicit c4.reports.opening [dict create purpose {Open an opening report using the current database context.} when {Use this to study the opening represented by your current work.} examples {{Create an opening report from this database menu} {Show the opening-report workflow here}}]
dict set ::knowledge::Explicit c4.save_changes [dict create purpose {Write pending changes in the selected database to storage.} when {Use this before closing a collection with unsaved edits.} examples {{Save changes in this selected database} {Write this database's pending edits to disk}}]
dict set ::knowledge::Explicit c4.search [dict create purpose {Show database search choices from the switcher menu.} when {Use this when deciding how to narrow the game collection.} examples {{Show search choices for this database} {Choose how to search this collection}}]
dict set ::knowledge::Explicit c4.search.current [dict create purpose {Open the current-game database search workflow.} when {Use this to search from the game's position or identifying details.} examples {{Search using the current game from this menu} {Open current-game search for this database}}]
dict set ::knowledge::Explicit c4.symbol.large [dict create purpose {Set database-switcher icons to the large size.} when {Use this when database symbols are difficult to recognize.} examples {{Use large database icons here} {Enlarge the database-switcher symbols}}]
dict set ::knowledge::Explicit c4.symbol.normal [dict create purpose {Set database-switcher icons to the normal size.} when {Use this to restore the usual database-symbol scale.} examples {{Restore normal database icons} {Use the standard switcher-symbol size}}]
dict set ::knowledge::Explicit c4.symbol.small [dict create purpose {Set database-switcher icons to the small size.} when {Use this to fit more collection symbols in the switcher.} examples {{Use small database icons here} {Shrink the database-switcher symbols}}]
dict set ::knowledge::Explicit c4.symbol_size [dict create purpose {Show size choices for database-switcher icons.} when {Use this to adjust how much room the database symbols occupy.} examples {{Show database icon-size choices} {Choose the scale of switcher symbols}}]
dict set ::knowledge::Explicit c5.event_table [dict create purpose {Open the tournament table for the selected event.} when {Use this to compare the event's players and results.} examples {{Show standings for this selected event} {Open this event's tournament table}}]
dict set ::knowledge::Explicit c5.event_url [dict create purpose {Open the site link associated with the selected event.} when {Use this when the event record includes a web address.} examples {{Visit this selected event's site link} {Open the web address recorded for this event}}]
dict set ::knowledge::Explicit c5.insights [dict create purpose {Open the insights report for the selected player.} when {Use this to inspect patterns in that player's stored games.} examples {{Show insights for this selected player} {Explore patterns in this player's game record}}]
dict set ::knowledge::Explicit c5.open_switcher [dict create purpose {Open a filtered database tab for the selected player, event or site.} when {Use this to browse all games belonging to that selection.} examples {{Open this selection's games in a database tab} {Show all games linked to this player or event}}]
dict set ::knowledge::Explicit c5.player.insights [dict create purpose {Show insights about the player selected in the table.} when {Use this to review that player's patterns and tendencies.} examples {{Open insights from this player's menu} {Review the selected player's database tendencies}}]
dict set ::knowledge::Explicit c5.player_card [dict create purpose {Open the information card for the selected player.} when {Use this to inspect that player's recorded details.} examples {{Show this selected player's card} {Open the information card for this player row}}]
dict set ::knowledge::Explicit c5.player_url [dict create purpose {Show available web links for the selected player.} when {Use this to visit a source associated with the player record.} examples {{Show this player's available web links} {Choose an external link for this player}}]
dict set ::knowledge::Explicit c5.prep_report [dict create purpose {Open an opponent-preparation report for the selected player.} when {Use this before studying how to face that player.} examples {{Prepare a report about this selected opponent} {Open preparation for the player in this row}}]
dict set ::knowledge::Explicit c5.save_working_set [dict create purpose {Save a filtered working set for the selected player, event or site.} when {Use this to retain the matching games as a named collection.} examples {{Save this selection's games as a working set} {Keep the games for this player or event together}}]
dict set ::knowledge::Explicit menu.db.maintenance.change_icon [dict create purpose {Open database properties where its icon can be changed.} when {Use this to give a collection a recognizable symbol.} examples {{Change the current database's icon} {Open properties to choose a database symbol}}]
dict set ::knowledge::Explicit menu.db.maintenance.compact [dict create purpose {Run the current database's compaction workflow.} when {Use this to reclaim space from obsolete stored records.} examples {{Compact the active game database} {Clean unused storage from the current collection}}]
dict set ::knowledge::Explicit menu.db.maintenance.convert [dict create purpose {Open conversion of the current database to native storage.} when {Use this when a collection should use the app's native format.} examples {{Convert the active database to native format} {Open native-format conversion for this collection}}]
dict set ::knowledge::Explicit menu.db.maintenance.recode [dict create purpose {Open character-encoding conversion for the current database.} when {Use this when names or comments display with incorrect characters.} examples {{Recode the active database's text} {Fix the character encoding of this collection}}]
dict set ::knowledge::Explicit menu.db.maintenance.strip_moves [dict create purpose {Remove the current game's moves through the maintenance command.} when {Use this when clearing the recorded continuation of the board game.} examples {{Clear the board game's moves through maintenance} {Remove current move text from the maintenance menu}}]
dict set ::knowledge::Explicit menu.db.maintenance.strip_tags [dict create purpose {Remove removable game-header tags from the current game.} when {Use this to clean extra identifying fields from the board game.} examples {{Strip extra header tags from the current game} {Clean the board game's additional game tags}}]
dict set ::knowledge::Explicit menu.db.player.update [dict create purpose {Open the rating-data update workflow.} when {Use this to refresh the app's supplemental player ratings.} examples {{Update the supplemental player ratings} {Open the player rating-data updater}}]
dict set ::knowledge::Explicit menu.db.reports.result [dict create purpose {Run the result-checking report for database games.} when {Use this to investigate recorded outcomes that may need review.} examples {{Check recorded database game results} {Create a report of result inconsistencies}}]
dict set ::knowledge::Explicit menu.db.reports.timecontrol [dict create purpose {Report the time-control types found in the database.} when {Use this to understand which playing speeds the collection contains.} examples {{Show this database's time-control profile} {Summarize playing speeds in the active collection}}]
dict set ::knowledge::Explicit menu.db.reports.trends [dict create purpose {Report changes and patterns in the database over time.} when {Use this when studying how the collection's game statistics develop.} examples {{Show trends in the active database} {Report changes over time in this collection}}]
dict set ::knowledge::Explicit menu.db.search.plain [dict create purpose {Open the search box for describing desired games in ordinary words.} when {Use this when it is easier to describe a search than build its fields.} examples {{Search the database using ordinary words} {Describe which games I want to find}}]
dict set ::knowledge::Explicit menu.db.search.query [dict create purpose {Open the structured position-search editor.} when {Use this to build a detailed pattern for finding games.} examples {{Open the detailed position-search editor} {Build a structured search for game positions}}]
dict set ::knowledge::Explicit menu.file.export.lichess [dict create purpose {Open study-upload options for the active database.} when {Use this when sharing a game collection through Lichess.} examples {{Upload the active database to a study} {Share my current collection through a study}}]
dict set ::knowledge::Explicit menu.file.import.db [dict create purpose {Open the importer for games from another database file.} when {Use this to combine games stored in separate collections.} examples {{Import games from another database} {Bring another collection's games into this one}}]
dict set ::knowledge::Explicit menu.file.new.crazy [dict create purpose {Start a new database for games with captured pieces returned to play.} when {Use this when collecting Crazyhouse games.} examples {{Create a new Crazyhouse database} {Start a collection for Crazyhouse games}}]
dict set ::knowledge::Explicit menu.file.new.normal [dict create purpose {Start a new database for ordinary chess games.} when {Use this when creating a regular game collection.} examples {{Create a normal-chess database} {Start a new collection of ordinary chess games}}]
dict set ::knowledge::Explicit menu.file.new.three [dict create purpose {Start a new database for games won by giving three checks.} when {Use this when collecting Three-check games.} examples {{Create a Three-check database} {Start a collection for Three-check games}}]
dict set ::knowledge::Explicit menu.file.new.variants [dict create purpose {Show the supported chess variants for a new database.} when {Use this when your collection uses rules other than ordinary chess.} examples {{Show variant choices for a new database} {Choose the chess rules for a new collection}}]
dict set ::knowledge::Explicit menu.file.save [dict create purpose {Save pending changes in the active database.} when {Use this before leaving a collection you have edited.} examples {{Save the active database's changes} {Write current collection edits to storage}}]
# End reviewed native knowledge: database

# Reviewed native knowledge: analysis
dict set ::knowledge::Explicit c6.add_all [dict create purpose {Add all displayed engine continuations as game variations.} when {Use this to preserve several candidate lines for later study.} examples {{Add all these engine lines as variations} {Keep every displayed engine continuation in the game}}]
dict set ::knowledge::Explicit c6.add_include [dict create purpose {Merge all displayed engine lines into the game's existing branches.} when {Use this to incorporate multiple analyses without separate duplicate branches.} examples {{Merge every displayed engine continuation into the game} {Include all engine lines in the existing analysis tree}}]
dict set ::knowledge::Explicit c6.add_line [dict create purpose {Add the selected full engine continuation as a variation.} when {Use this to retain the engine's sequence beside the game line.} examples {{Add this full engine line as a variation} {Keep the selected engine continuation as a side line}}]
dict set ::knowledge::Explicit c6.add_merge [dict create purpose {Merge the selected engine continuation into existing game branches.} when {Use this when the analysis overlaps moves already recorded.} examples {{Merge this engine line with existing branches} {Combine the selected engine continuation with my game tree}}]
dict set ::knowledge::Explicit c6.add_move [dict create purpose {Add the first move of the selected engine line as a variation.} when {Use this to retain a candidate without its full continuation.} examples {{Add only this engine line's first move} {Keep this engine candidate as a one-move variation}}]
dict set ::knowledge::Explicit c6.add_sequence [dict create purpose {Append the selected engine sequence, using a variation mid-line.} when {Use this to continue the game with the engine's suggested sequence.} examples {{Append this engine sequence to my game} {Continue the game with these engine moves}}]
dict set ::knowledge::Explicit c6.best_first [dict create purpose {Toggle whether stronger engine continuations appear first.} when {Use this to choose between ranked display and the engine's line order.} examples {{Put the strongest engine line first} {Toggle best-first ordering for these engine lines}}]
dict set ::knowledge::Explicit c6.close_engine [dict create purpose {Stop and close the engine attached to this analysis pane.} when {Use this when that engine's analysis is no longer needed.} examples {{Close the engine in this analysis pane} {Stop this pane's analyzing engine}}]
dict set ::knowledge::Explicit c6.copy_fen [dict create purpose {Copy the current board position as text from the analysis menu.} when {Use this to transfer the analyzed position elsewhere.} examples {{Copy the position text from the engine menu} {Put this analyzed position on the clipboard}}]
dict set ::knowledge::Explicit c6.copy_line [dict create purpose {Copy the selected engine continuation as move text.} when {Use this to transfer a candidate sequence to another editor.} examples {{Copy this selected engine line} {Put the selected engine continuation on the clipboard}}]
dict set ::knowledge::Explicit c6.explain_line [dict create purpose {Request a grounded explanation of the selected engine continuation.} when {Use this to understand the plan shown by the engine.} examples {{Explain this selected engine continuation} {Describe the plan in this engine line}}]
dict set ::knowledge::Explicit c6.insert_comment [dict create purpose {Insert the first engine move as a comment in the game.} when {Use this to mention a candidate without adding another branch.} examples {{Put this engine candidate in a comment} {Mention the engine's first move as annotation text}}]
dict set ::knowledge::Explicit c6.lines.1 [dict create purpose {Limit each engine variation's display to one text line.} when {Use this to keep analysis rows compact.} examples {{Use one display line per engine variation} {Make each engine continuation occupy one row}}]
dict set ::knowledge::Explicit c6.lines.2 [dict create purpose {Allow two text lines for each engine variation.} when {Use this to read longer continuations without a tall pane.} examples {{Use two display lines per engine variation} {Give each engine continuation two rows}}]
dict set ::knowledge::Explicit c6.lines.3 [dict create purpose {Allow three text lines for each engine variation.} when {Use this to see more moves in each candidate continuation.} examples {{Use three display lines per engine variation} {Give each engine continuation three rows}}]
dict set ::knowledge::Explicit c6.lines.4 [dict create purpose {Allow four text lines for each engine variation.} when {Use this when detailed continuations need more display space.} examples {{Use four display lines per engine variation} {Give each engine continuation four rows}}]
dict set ::knowledge::Explicit c6.lines_per_variation [dict create purpose {Show choices for how many text lines each engine variation uses.} when {Use this to balance readable continuations against pane height.} examples {{Choose the display height of engine variations} {Show line-count choices for each engine continuation}}]
dict set ::knowledge::Explicit c6.lock_engine [dict create purpose {Toggle whether this engine remains on its analyzed position.} when {Use this to keep one position under analysis while browsing the game.} examples {{Lock this engine to its position} {Let this engine follow the board again}}]
dict set ::knowledge::Explicit c6.multi.1 [dict create purpose {Ask the engine to display one candidate continuation.} when {Use this to concentrate analysis on the strongest line.} examples {{Show one engine candidate line} {Limit this engine to a single continuation}}]
dict set ::knowledge::Explicit c6.multi.2 [dict create purpose {Ask the engine to display two candidate continuations.} when {Use this to compare a pair of possible moves.} examples {{Show two engine candidate lines} {Compare the engine's top two continuations}}]
dict set ::knowledge::Explicit c6.multi.3 [dict create purpose {Ask the engine to display three candidate continuations.} when {Use this to compare several promising moves.} examples {{Show three engine candidate lines} {Compare the engine's top three continuations}}]
dict set ::knowledge::Explicit c6.multi.4 [dict create purpose {Ask the engine to display four candidate continuations.} when {Use this to inspect a broader set of move choices.} examples {{Show four engine candidate lines} {Compare the engine's top four continuations}}]
dict set ::knowledge::Explicit c6.multi.5 [dict create purpose {Ask the engine to display five candidate continuations.} when {Use this to inspect more alternatives in the position.} examples {{Show five engine candidate lines} {Compare the engine's top five continuations}}]
dict set ::knowledge::Explicit c6.multi.6 [dict create purpose {Ask the engine to display six candidate continuations.} when {Use this to study a wide range of plausible moves.} examples {{Show six engine candidate lines} {Compare the engine's top six continuations}}]
dict set ::knowledge::Explicit c6.multi.7 [dict create purpose {Ask the engine to display seven candidate continuations.} when {Use this when an extensive move comparison is useful.} examples {{Show seven engine candidate lines} {Compare the engine's top seven continuations}}]
dict set ::knowledge::Explicit c6.multi.8 [dict create purpose {Ask the engine to display eight candidate continuations.} when {Use this to inspect the largest listed set of candidates.} examples {{Show eight engine candidate lines} {Compare the engine's top eight continuations}}]
dict set ::knowledge::Explicit c6.multiple_variations [dict create purpose {Show choices for the number of engine candidate lines.} when {Use this to decide how many possible moves to compare.} examples {{Choose how many engine candidates to show} {Show candidate-count options for this engine}}]
dict set ::knowledge::Explicit c6.opponents_view [dict create purpose {Toggle analysis as if the opponent had the next turn.} when {Use this to examine the other side's threats.} examples {{Analyze from the opponent's turn in this pane} {Toggle the engine's opponent view}}]
dict set ::knowledge::Explicit c6.pause_resume [dict create purpose {Pause or resume the engine attached to this analysis pane.} when {Use this when temporarily stopping computation while keeping the engine open.} examples {{Pause this pane's engine analysis} {Resume the analysis in this engine pane}}]
dict set ::knowledge::Explicit c6.pin_repertoire [dict create purpose {Save the selected engine continuation into a repertoire database.} when {Use this to retain analysis for opening preparation.} examples {{Pin this engine line to my repertoire} {Save the selected engine continuation for repertoire practice}}]
dict set ::knowledge::Explicit c6.setup_engine [dict create purpose {Open settings for the engine in this analysis pane.} when {Use this to change that engine's analysis options.} examples {{Configure this pane's engine} {Open settings for the selected analysis engine}}]
dict set ::knowledge::Explicit c6.setup_eval_edges [dict create purpose {Open the settings for engine evaluation display boundaries.} when {Use this to adjust how evaluation ranges are shown.} examples {{Configure this engine's evaluation boundaries} {Open the evaluation-edge settings}}]
dict set ::knowledge::Explicit c7.open_report [dict create purpose {Select the media entry and open its associated report.} when {Use this to read the report attached to a media item.} examples {{Open the report for this media entry} {Show the selected recording's associated report}}]
dict set ::knowledge::Explicit c7.play [dict create purpose {Select and play the chosen media entry.} when {Use this to watch or hear the recording attached to the game.} examples {{Play this selected media entry} {Start the recording in this media row}}]
dict set ::knowledge::Explicit c7.show_in_board [dict create purpose {Toggle the media inset inside the board area.} when {Use this to watch the recording beside the chess position.} examples {{Show the media inset on the board} {Hide the media overlay from the board}}]
dict set ::knowledge::Explicit c8.analyze [dict create purpose {Start engine analysis for the position represented by the tree row.} when {Use this to assess a continuation found in database games.} examples {{Analyze this opening-tree continuation} {Start engine analysis for this tree position}}]
dict set ::knowledge::Explicit c8.automatic [dict create purpose {Toggle opening-tree searches as the board position changes.} when {Use this to choose automatic updates or manual searching.} examples {{Update the opening tree automatically} {Stop automatic tree searches while I browse}}]
dict set ::knowledge::Explicit c8.copy_line [dict create purpose {Copy the played line and selected tree continuation as move text.} when {Use this to transfer an opening sequence without changing the board.} examples {{Copy the line through this tree move} {Put this opening-tree continuation on the clipboard}}]
dict set ::knowledge::Explicit c8.highlight [dict create purpose {Toggle highlighting of moves identified as novelties in the tree.} when {Use this to spot continuations outside the reference games.} examples {{Highlight opening novelties in this tree} {Turn off novelty highlighting in this opening tree}}]
dict set ::knowledge::Explicit c8.inside_variations [dict create purpose {Toggle searching alternative lines within stored games.} when {Use this when side variations should contribute to tree results.} examples {{Include side variations in this tree search} {Search only game main lines in the opening tree}}]
dict set ::knowledge::Explicit c8.lock_reference [dict create purpose {Toggle whether the tree keeps its selected reference database.} when {Use this when changing active databases should not change the comparison source.} examples {{Lock the opening tree's reference database} {Let the tree reference follow database changes}}]
dict set ::knowledge::Explicit c8.move_actions [dict create purpose {Show move-insertion and game-loading choices for this tree continuation.} when {Use this to act on a move found in the opening tree.} examples {{Show actions for this opening-tree move} {Choose how to use this tree continuation}}]
dict set ::knowledge::Explicit c8.opening_report [dict create purpose {Open the opening report for the current tree position.} when {Use this to study the games and continuations from that opening.} examples {{Create a report from this opening-tree position} {Show the opening report through the tree menu}}]
dict set ::knowledge::Explicit c8.reference.none [dict create purpose {Clear the chosen tree reference by selecting the clipboard database.} when {Use this to stop comparing against a separate reference collection.} examples {{Clear this tree's reference database selection} {Use no separate reference collection for the tree}}]
dict set ::knowledge::Explicit c8.reference_base [dict create purpose {Show choices for the tree's comparison database.} when {Use this when choosing which collection should define reference play.} examples {{Choose an opening-tree reference collection} {Show available reference databases for this tree}}]
dict set ::knowledge::Explicit c8.save_line [dict create purpose {Save the board line and selected tree move to a repertoire.} when {Use this to retain a database continuation for practice.} examples {{Save this tree continuation in my repertoire} {Keep the selected opening-tree move for preparation}}]
dict set ::knowledge::Explicit c8.search.exact [dict create purpose {Select exact position matching for opening-tree searches.} when {Use this when the tree should match the board position precisely.} examples {{Use exact opening-tree search} {Choose precise position matching in the tree}}]
dict set ::knowledge::Explicit c8.search.fast [dict create purpose {Select the fast opening-tree search mode.} when {Use this when a quicker tree update is more useful than a broader search.} examples {{Use fast opening-tree search} {Choose the tree's quick search mode}}]
dict set ::knowledge::Explicit c8.search.slow [dict create purpose {Select the slower opening-tree search mode.} when {Use this when you prefer the more thorough available search path.} examples {{Use slow opening-tree search} {Choose the tree's slower search mode}}]
dict set ::knowledge::Explicit c8.search_mode [dict create purpose {Show the available opening-tree search methods.} when {Use this to choose how the database is searched for continuations.} examples {{Show opening-tree search methods} {Choose the tree's position-search mode}}]
dict set ::knowledge::Explicit c8.start_search [dict create purpose {Start a database search for the current opening-tree position.} when {Use this after changing the board with automatic updates disabled.} examples {{Search this opening-tree position now} {Refresh the tree's database results manually}}]
dict set ::knowledge::Explicit menu.analysis.analyze [dict create purpose {Start the app's engine-analysis workflow for the board position.} when {Use this to obtain an engine assessment of the current position.} examples {{Analyze the current board position} {Start position analysis from the main menu}}]
dict set ::knowledge::Explicit menu.analysis.annotate [dict create purpose {Start or stop automatic game annotation using the app's analysis workflow.} when {Use this to add grounded commentary while reviewing a game.} examples {{Annotate this game automatically} {Toggle automatic annotation for the current game}}]
dict set ::knowledge::Explicit menu.analysis.engine_dictionary [dict create purpose {Open the collection of configured chess engines.} when {Use this to inspect or manage installed engine definitions.} examples {{Open the engine dictionary} {Show my configured chess engines}}]
dict set ::knowledge::Explicit menu.analysis.explain.comment [dict create purpose {Explain the current stored game comment using the app's context.} when {Use this when a written annotation is difficult to understand.} examples {{Explain the game's current stored comment} {Describe the meaning of the current game annotation}}]
dict set ::knowledge::Explicit menu.analysis.explain.line [dict create purpose {Explain the best available engine line, starting analysis if needed.} when {Use this to understand a candidate continuation on the board.} examples {{Explain the best engine continuation} {Describe the plan in the current best line}}]
dict set ::knowledge::Explicit menu.analysis.explain.move [dict create purpose {Explain the current game move using the app's analysis.} when {Use this to understand a decision in the recorded game.} examples {{Explain the current game move} {Describe why the current move was played}}]
dict set ::knowledge::Explicit menu.analysis.explain.position [dict create purpose {Request an analysis-grounded explanation of the board position.} when {Use this to understand the position's relevant plans and features.} examples {{Explain the current board position} {Describe the position using the app's analysis}}]
dict set ::knowledge::Explicit menu.analysis.factcheck [dict create purpose {Check the current game's annotations against available chess facts.} when {Use this to find comments that need verification or correction.} examples {{Fact-check this game's annotations} {Check whether the current comments agree with the analysis}}]
dict set ::knowledge::Explicit menu.analysis.tablebase.local [dict create purpose {Open the chooser for a local endgame-table folder.} when {Use this when exact endgame files are installed on disk.} examples {{Choose a local endgame-table folder for analysis} {Set the endgame file location from Analysis}}]
dict set ::knowledge::Explicit menu.analysis.tablebase.online [dict create purpose {Toggle online exact-endgame lookups in the analysis view.} when {Use this when remote endgame results should be available.} examples {{Toggle online endgame lookups from Analysis} {Use remote exact-endgame results in analysis}}]
dict set ::knowledge::Explicit menu.analysis.tablebase.show [dict create purpose {Show or hide the exact-endgame result display.} when {Use this when studying positions covered by endgame tables.} examples {{Toggle endgame results from Analysis} {Show exact endgame results in the analysis view}}]
dict set ::knowledge::Explicit menu.board.tablebase.local [dict create purpose {Choose the folder containing local exact-endgame files.} when {Use this to connect installed endgame tables to the board.} examples {{Set the board's local endgame-file folder} {Choose endgame table files from the Board menu}}]
dict set ::knowledge::Explicit menu.board.tablebase.online [dict create purpose {Toggle remote exact-endgame lookups for the board.} when {Use this when you want online endgame results while browsing.} examples {{Enable online endgame lookup from the Board menu} {Disable the board's remote endgame lookup}}]
dict set ::knowledge::Explicit menu.board.tablebase.show [dict create purpose {Show or hide exact endgame information beside the board.} when {Use this to check table-covered positions while playing through a game.} examples {{Show exact endgame information on the board} {Hide the board's endgame-result display}}]
dict set ::knowledge::Explicit menu.training.check_results [dict create purpose {Run the game-quality report for recorded results.} when {Use this to review games whose stored outcomes may be inconsistent.} examples {{Check game results from the Training menu} {Create a quality report about recorded game outcomes}}]
# End reviewed native knowledge: analysis

# Reviewed native knowledge: panes
dict set ::knowledge::Explicit c10.auto_stretch [dict create purpose {Toggle whether the selected column stretches with its table.} when {Use this to decide which columns absorb extra window width.} examples {{Let this column stretch with the table} {Stop this column from stretching automatically}}]
dict set ::knowledge::Explicit c10.configure [dict create purpose {Open display settings for the selected table column.} when {Use this when changing how a particular column appears.} examples {{Configure this table column} {Open display options for this column header}}]
dict set ::knowledge::Explicit c10.fill_column [dict create purpose {Show or hide the filler column at the table's right edge.} when {Use this to choose whether unused table width is filled.} examples {{Toggle the table's right-hand filler column} {Show a filler column after the data columns}}]
dict set ::knowledge::Explicit c10.fit [dict create purpose {Resize columns to fit the available table width.} when {Use this when the table should occupy its pane neatly.} examples {{Fit these columns within the table} {Resize all columns to the available width}}]
dict set ::knowledge::Explicit c10.hide [dict create purpose {Hide the selected table column.} when {Use this to remove a field you do not need to see.} examples {{Hide this selected table column} {Remove this field from the visible table}}]
dict set ::knowledge::Explicit c10.optimize [dict create purpose {Choose column widths using the table's content-sizing rules.} when {Use this when displayed values need more suitable widths.} examples {{Optimize these table-column widths} {Resize the columns for their displayed content}}]
dict set ::knowledge::Explicit c10.show_column [dict create purpose {Show the list of hidden or available table columns.} when {Use this to bring an omitted field back into view.} examples {{Choose a column to show in this table} {Show available hidden table fields}}]
dict set ::knowledge::Explicit c10.squeeze [dict create purpose {Reduce table-column widths using the compact sizing mode.} when {Use this when fitting more fields on screen matters.} examples {{Squeeze these table columns tighter} {Use compact widths for this table}}]
dict set ::knowledge::Explicit c9.amalgamate [dict create purpose {Join the pane's container with its neighbor or separate it again.} when {Use this when adjusting how docked pane groups share space.} examples {{Join this pane with its neighboring group} {Separate this amalgamated pane group}}]
dict set ::knowledge::Explicit c9.analysis.best [dict create purpose {Toggle best-first ordering from the analysis pane header.} when {Use this when candidate lines should follow strength rather than arrival order.} examples {{Toggle best-first lines from this pane header} {Rank this pane's candidate continuations by strength}}]
dict set ::knowledge::Explicit c9.analysis.lines [dict create purpose {Show text-height choices for variations in this analysis pane.} when {Use this to give long engine lines more readable space.} examples {{Choose variation display height from this pane header} {Show text-line options for this analysis pane}}]
dict set ::knowledge::Explicit c9.analysis.multi [dict create purpose {Show candidate-count choices for this analysis pane.} when {Use this when comparing more or fewer engine alternatives.} examples {{Choose candidate count from this pane header} {Show variation-count options for this analysis pane}}]
dict set ::knowledge::Explicit c9.analysis.opponents [dict create purpose {Toggle the engine's opponent-turn view from the pane header.} when {Use this to inspect threats for the other side without moving the board.} examples {{Toggle opponent-turn analysis from this header} {Show the opponent's threats in this engine pane}}]
dict set ::knowledge::Explicit c9.analysis.setup [dict create purpose {Open this analysis pane's engine settings from its header.} when {Use this when changing the selected engine's options.} examples {{Set up the engine from this pane header} {Configure the engine assigned to this analysis pane}}]
dict set ::knowledge::Explicit c9.appearance [dict create purpose {Show board appearance choices in the pane-header menu.} when {Use this to adjust visible board elements while arranging the workspace.} examples {{Show board appearance choices from the header} {Choose which board elements are visible here}}]
dict set ::knowledge::Explicit c9.assistant.clear [dict create purpose {Erase the Assistant's current conversation.} when {Use this to begin a new conversation without earlier messages.} examples {{Clear the Assistant conversation from its pane menu} {Start a fresh conversation in this Assistant pane}}]
dict set ::knowledge::Explicit c9.assistant.model [dict create purpose {Open the model chooser from the Assistant pane.} when {Use this when selecting the configured service and model for requests.} examples {{Choose a model from the Assistant pane} {Open this pane's model-selection dialog}}]
dict set ::knowledge::Explicit c9.close [dict create purpose {Close the pane selected by its header menu.} when {Use this when that workspace view is no longer needed.} examples {{Close the pane under this header} {Remove this pane from the workspace}}]
dict set ::knowledge::Explicit c9.docking [dict create purpose {Toggle visible docking targets for the current workspace.} when {Use this when positioning panes around one another.} examples {{Show docking targets from this pane menu} {Hide this workspace's docking points}}]
dict set ::knowledge::Explicit c9.explorer.source [dict create purpose {Show source choices for the opening explorer.} when {Use this when choosing which game collection supplies opening statistics.} examples {{Choose the explorer's game source} {Show data sources from the explorer pane header}}]
dict set ::knowledge::Explicit c9.float [dict create purpose {Detach the pane into a window or dock it back.} when {Use this when you want to position a view independently.} examples {{Float this pane in its own window} {Dock this separate pane back into the workspace}}]
dict set ::knowledge::Explicit c9.fold [dict create purpose {Fold or unfold the pane's title bar.} when {Use this to change how much header space the docked pane uses.} examples {{Fold this pane's title bar} {Unfold this pane header}}]
dict set ::knowledge::Explicit c9.games.columns [dict create purpose {Show column-visibility choices for the game list.} when {Use this to decide which game fields appear in the table.} examples {{Choose columns from the game-list pane header} {Show game-list column choices here}}]
dict set ::knowledge::Explicit c9.games.filters [dict create purpose {Show filtering choices for the game list.} when {Use this when narrowing the visible game records.} examples {{Show filters from the game-list pane header} {Choose how to filter this game-list pane}}]
dict set ::knowledge::Explicit c9.games.presets [dict create purpose {Show options for saving and reusing game-search presets.} when {Use this when a frequently used search should be retained.} examples {{Save a search preset from this game-list header} {Show reusable search choices for this game list}}]
dict set ::knowledge::Explicit c9.games.sort [dict create purpose {Show ordering choices for the pane's table rows.} when {Use this to organize visible records by a different field.} examples {{Show sorting choices from this pane header} {Choose the order of this pane's table rows}}]
dict set ::knowledge::Explicit c9.hide_leaving [dict create purpose {Toggle whether a floating pane hides when leaving its tab.} when {Use this when a separate window should follow its workspace tab.} examples {{Hide this floating pane when I leave its tab} {Keep this floating pane visible across tab changes}}]
dict set ::knowledge::Explicit c9.layout [dict create purpose {Show workspace arrangement choices from the pane header.} when {Use this when restoring or adjusting a pane arrangement.} examples {{Show layout choices for this workspace} {Open arrangement options from this pane menu}}]
dict set ::knowledge::Explicit c9.maximise [dict create purpose {Enlarge the selected pane to its workspace or restore its previous size.} when {Use this to concentrate on one view temporarily.} examples {{Maximise this pane from its header} {Restore this enlarged pane's previous size}}]
dict set ::knowledge::Explicit c9.media.show [dict create purpose {Toggle the board's media inset from the media pane header.} when {Use this when a recording should appear alongside the position.} examples {{Toggle board media from this pane header} {Show the recording on the board through this menu}}]
dict set ::knowledge::Explicit c9.media.stream [dict create purpose {Open the stream-entry dialog from the media pane.} when {Use this to play a recording available at a stream address.} examples {{Open a stream from this media pane} {Enter a stream address through the media header}}]
dict set ::knowledge::Explicit c9.not.configure [dict create purpose {Open notation preferences from the notation pane header.} when {Use this when tailoring how recorded moves and comments appear.} examples {{Configure notation from this pane header} {Open this notation pane's preferences}}]
dict set ::knowledge::Explicit c9.not.diagrams [dict create purpose {Toggle embedded diagrams in the game's notation.} when {Use this to choose whether marked positions appear as board pictures.} examples {{Toggle diagrams in this notation pane} {Show board pictures within the game text}}]
dict set ::knowledge::Explicit c9.not.display [dict create purpose {Show notation appearance options in the pane-header menu.} when {Use this to adjust readability without editing the game.} examples {{Show display choices for this notation pane} {Open notation appearance options from its header}}]
dict set ::knowledge::Explicit c9.not.emoticons [dict create purpose {Toggle pictorial emoticons in the notation display.} when {Use this to choose how expressive comment symbols are rendered.} examples {{Toggle emoticons in this notation pane} {Show comment emoticons as pictures in the game text}}]
dict set ::knowledge::Explicit c9.not.font [dict create purpose {Show text-size controls for the notation pane.} when {Use this when the game text is too large or too small.} examples {{Show font-size choices for this notation pane} {Choose the size of this pane's move text}}]
dict set ::knowledge::Explicit c9.not.font_dec [dict create purpose {Reduce text size in the selected notation pane.} when {Use this to fit more of the game on screen.} examples {{Make this notation pane's text smaller} {Decrease the move-text size in this pane}}]
dict set ::knowledge::Explicit c9.not.font_inc [dict create purpose {Increase text size in the selected notation pane.} when {Use this when moves and comments are hard to read.} examples {{Make this notation pane's text larger} {Increase the move-text size in this pane}}]
dict set ::knowledge::Explicit c9.not.font_reset [dict create purpose {Restore the selected notation pane's default text size.} when {Use this after temporary text-size adjustments.} examples {{Reset this notation pane's font size} {Return this pane's move text to its normal size}}]
dict set ::knowledge::Explicit c9.not.language [dict create purpose {Show language-selection choices for displayed game comments.} when {Use this to choose which translations appear in the notation.} examples {{Choose comment languages for this notation pane} {Show language options from the notation header}}]
dict set ::knowledge::Explicit c9.not.markers [dict create purpose {Toggle move markers in the notation display.} when {Use this when special markers should be visible or concealed.} examples {{Toggle markers in this notation pane} {Show special move markers in the game text}}]
dict set ::knowledge::Explicit c9.not.move_info [dict create purpose {Show choices for displaying information attached to moves.} when {Use this to choose which recorded analysis or clock fields appear.} examples {{Choose move-information fields for this notation pane} {Show move-data display options from this header}}]
dict set ::knowledge::Explicit c9.not.move_notation [dict create purpose {Show choices for the written form of chess moves.} when {Use this when selecting how piece names and moves are displayed.} examples {{Choose a move-notation style for this pane} {Show move-writing options from the notation header}}]
dict set ::knowledge::Explicit c9.not.numbering [dict create purpose {Toggle variation numbering in the notation display.} when {Use this when numbered branches would make analysis easier to follow.} examples {{Toggle variation numbers in this notation pane} {Show numbered branches in the game text}}]
dict set ::knowledge::Explicit c9.not.spacing [dict create purpose {Toggle paragraph spacing in the notation display.} when {Use this to change separation between blocks of game text.} examples {{Toggle paragraph spacing in this notation pane} {Separate this game's notation paragraphs more clearly}}]
dict set ::knowledge::Explicit c9.pane.analysis [dict create purpose {Show or hide the engine-analysis pane.} when {Use this when bringing engine continuations into the workspace.} examples {{Toggle the analysis pane from the pane menu} {Show engine analysis in this workspace}}]
dict set ::knowledge::Explicit c9.pane.assistant [dict create purpose {Show or hide the Assistant pane from the pane menu.} when {Use this to make the conversation view available in the workspace.} examples {{Toggle the Assistant pane from this menu} {Show the conversation pane in this workspace}}]
dict set ::knowledge::Explicit c9.pane.board [dict create purpose {Show or hide the chessboard pane.} when {Use this when arranging the workspace around the board.} examples {{Toggle the board pane from the pane menu} {Show the chessboard view in this workspace}}]
dict set ::knowledge::Explicit c9.pane.explorer [dict create purpose {Show or hide the opening-explorer pane.} when {Use this when opening statistics should be part of the workspace.} examples {{Toggle the explorer pane from this menu} {Show opening exploration in this workspace}}]
dict set ::knowledge::Explicit c9.pane.games [dict create purpose {Show or hide the game-list pane.} when {Use this when browsing game records beside the board.} examples {{Toggle the game-list pane from this menu} {Show the game table in this workspace}}]
dict set ::knowledge::Explicit c9.pane.media [dict create purpose {Show or hide the media pane.} when {Use this when recordings should be available beside the game.} examples {{Toggle the media pane from this menu} {Show recordings in this workspace}}]
dict set ::knowledge::Explicit c9.pane.notation [dict create purpose {Show or hide the game-notation pane.} when {Use this when moves and comments should be visible beside the board.} examples {{Toggle the notation pane from this menu} {Show the move text in this workspace}}]
dict set ::knowledge::Explicit c9.pane.people [dict create purpose {Show or hide the player-information table pane.} when {Use this when browsing the people associated with database games.} examples {{Toggle the people table from this pane menu} {Show the player table in this workspace}}]
dict set ::knowledge::Explicit c9.pane.report [dict create purpose {Show or hide the report and information pane.} when {Use this when reviewing generated reports alongside the board.} examples {{Toggle the report pane from this menu} {Show the information view in this workspace}}]
dict set ::knowledge::Explicit c9.pane.tree [dict create purpose {Show or hide the opening-tree pane.} when {Use this when database continuations should be visible with the position.} examples {{Toggle the tree pane from this menu} {Show the opening tree in this workspace}}]
dict set ::knowledge::Explicit c9.report.font [dict create purpose {Show report text-size and typeface controls.} when {Use this to improve the report's readability.} examples {{Show report font controls from this pane header} {Choose how the report's text looks}}]
dict set ::knowledge::Explicit c9.stay_on_top [dict create purpose {Toggle whether the floating pane stays above other windows.} when {Use this to keep a separate workspace view visible while working.} examples {{Keep this floating pane above other windows} {Turn off this pane's always-on-top setting}}]
dict set ::knowledge::Explicit c9.table.filter [dict create purpose {Show filtering choices for the selected information table.} when {Use this to narrow the table's visible records.} examples {{Show filters for this information pane} {Choose which records this table pane displays}}]
dict set ::knowledge::Explicit c9.tablebase [dict create purpose {Toggle exact-endgame information from the board pane header.} when {Use this when checking a position covered by endgame tables.} examples {{Show exact endgame information from this pane header} {Hide endgame results using the board pane menu}}]
dict set ::knowledge::Explicit c9.tree.automatic [dict create purpose {Toggle automatic tree updates from the tree pane header.} when {Use this when browsing should update database continuations automatically.} examples {{Toggle automatic search from the tree pane header} {Let this tree pane update when the board changes}}]
dict set ::knowledge::Explicit c9.tree.novelties [dict create purpose {Toggle novelty highlighting from the tree pane header.} when {Use this to identify unfamiliar continuations while browsing the tree.} examples {{Toggle novelty highlights from this tree header} {Show novel continuations in this tree pane}}]
dict set ::knowledge::Explicit c9.tree.reference [dict create purpose {Show reference-database choices from the tree pane header.} when {Use this when comparing the tree against another game collection.} examples {{Choose a reference collection from this tree header} {Show reference sources for this tree pane}}]
dict set ::knowledge::Explicit c9.tree.search_mode [dict create purpose {Show search-method choices from the tree pane header.} when {Use this to balance tree-search speed against the matching method.} examples {{Choose a search method from this tree header} {Show position-search modes for this tree pane}}]
# End reviewed native knowledge: panes

# Reviewed native knowledge: interface
dict set ::knowledge::Explicit app-copy [dict create purpose {Copy focused text, or open the move's comment editor when the board has focus.} when {Use this to copy a text selection or annotate the current board move.} examples {{Copy the text I have selected} {Open a comment for the board's current move}}]
dict set ::knowledge::Explicit app-cut [dict create purpose {Cut selected text from the focused text editor.} when {Use this to move text to another location.} examples {{Cut my focused text selection} {Move the selected editor text to the clipboard}}]
dict set ::knowledge::Explicit app-find [dict create purpose {Open the find workflow for the currently focused widget.} when {Use this to locate text within the view you are using.} examples {{Find text in the focused view} {Open Find for the current editor}}]
dict set ::knowledge::Explicit app-paste [dict create purpose {Paste clipboard text into the focused text editor.} when {Use this to insert text copied elsewhere.} examples {{Paste into the focused editor} {Insert the clipboard text where I am typing}}]
dict set ::knowledge::Explicit app-quit [dict create purpose {Close the application through its normal shutdown workflow.} when {Use this when you have finished working and want to exit.} examples {{Quit Chesswiz} {Exit the application normally}}]
dict set ::knowledge::Explicit app-redo [dict create purpose {Reapply the last undone edit in focused text or game notation.} when {Use this when an edit you reversed should be restored.} examples {{Redo my most recent undone edit} {Reapply the last change in the focused view}}]
dict set ::knowledge::Explicit app-select-all [dict create purpose {Select all focused text, or open move annotations from the board.} when {Use this before replacing text or choosing a move-quality symbol.} examples {{Select all text in the focused editor} {Open the board move's annotation symbols}}]
dict set ::knowledge::Explicit app-undo [dict create purpose {Reverse the last edit in focused text or game notation.} when {Use this to recover from an unwanted editing change.} examples {{Undo my most recent edit} {Reverse the last change in the focused view}}]
dict set ::knowledge::Explicit menu.help.about [dict create purpose {Open the program-information dialog.} when {Use this to inspect the installed application's identity and version.} examples {{Show information about this installation} {Open the About Chesswiz dialog}}]
dict set ::knowledge::Explicit menu.help.bug [dict create purpose {Open the app's bug-report workflow.} when {Use this to prepare a report about behavior that failed.} examples {{Open a bug report for this application} {Prepare a report of a problem I found}}]
dict set ::knowledge::Explicit menu.help.feature [dict create purpose {Open the app's feature-request workflow.} when {Use this to describe a capability you would like added.} examples {{Open a feature request for this application} {Prepare a suggestion for a new app feature}}]
dict set ::knowledge::Explicit menu.tools.assistant [dict create purpose {Open the Assistant conversation pane.} when {Use this to request app operations in ordinary words.} examples {{Open the Assistant from Tools} {Show the app's conversation interface}}]
dict set ::knowledge::Explicit menu.tools.choose_model [dict create purpose {Open the chooser for configured Assistant models.} when {Use this to change the service or model handling requests.} examples {{Open the Assistant model chooser} {Choose which configured model handles my requests}}]
dict set ::knowledge::Explicit menu.tools.file_types [dict create purpose {Open file-association settings for supported chess files.} when {Use this when the app should handle a file type from the operating system.} examples {{Choose which file types open with Chesswiz} {Open chess-file association settings}}]
dict set ::knowledge::Explicit menu.tools.legacy_fonts [dict create purpose {Open the installer for supported legacy chess fonts.} when {Use this when older chess documents need their original symbols.} examples {{Install supported older chess fonts} {Open the legacy chess-font installer}}]
dict set ::knowledge::Explicit menu.tools.voice [dict create purpose {Toggle the app's voice-input interface.} when {Use this when you want to dictate an app request.} examples {{Open voice input for app requests} {Toggle the voice Assistant}}]
dict set ::knowledge::Explicit menu.view.colors [dict create purpose {Apply the selected light or dark interface color scheme.} when {Use this to match the workspace colors to your viewing conditions.} examples {{Use a dark interface color scheme} {Switch the interface colors to light}}]
dict set ::knowledge::Explicit menu.view.icon_size [dict create purpose {Apply the selected size to toolbar icons.} when {Use this when toolbar controls need more or less space.} examples {{Make toolbar icons larger} {Use smaller toolbar buttons}}]
dict set ::knowledge::Explicit menu.view.language [dict create purpose {Switch interface text to the selected supported language.} when {Use this when you prefer menus and dialogs in another language.} examples {{Switch the app interface to German} {Change the language used by menus and dialogs}}]
dict set ::knowledge::Explicit menu.view.layout.arrow_size [dict create purpose {Set the pixel size of pane-docking target arrows.} when {Use this when drop targets are hard to see or too large.} examples {{Use larger docking target arrows} {Make the pane-docking arrows smaller}}]
dict set ::knowledge::Explicit menu.view.layout.docking [dict create purpose {Show or hide docking targets in the active workspace.} when {Use this when moving panes between docked positions.} examples {{Show docking points in the active layout} {Hide all active-layout docking targets}}]
dict set ::knowledge::Explicit menu.view.layout.fold [dict create purpose {Fold or unfold all pane title bars in the active layout.} when {Use this when changing header space across the whole workspace.} examples {{Fold all pane title bars} {Unfold every title bar in this layout}}]
dict set ::knowledge::Explicit menu.view.layout.load [dict create purpose {Restore a saved pane arrangement by its name.} when {Use this to return to a workspace you have already saved.} examples {{Restore my named workspace layout} {Load a saved arrangement of panes}}]
dict set ::knowledge::Explicit menu.view.layout.pane [dict create purpose {Toggle the specified pane in the active workspace layout.} when {Use this to bring a known workspace view into or out of sight.} examples {{Toggle a pane in my active layout} {Show the selected workspace pane by its identifier}}]
dict set ::knowledge::Explicit menu.view.layout.save_as [dict create purpose {Open the dialog for saving the workspace under a layout name.} when {Use this to preserve a new pane arrangement for later use.} examples {{Save this workspace under a new layout name} {Keep my current pane arrangement as a named layout}}]
dict set ::knowledge::Explicit menu.view.panes.annotators [dict create purpose {Show or hide the database's annotator table.} when {Use this to browse the authors of game comments.} examples {{Show the annotators pane} {Hide the database annotator table}}]
dict set ::knowledge::Explicit menu.view.panes.events [dict create purpose {Show or hide the database's event table.} when {Use this to browse tournaments represented in the collection.} examples {{Show the events pane} {Hide the database tournament table}}]
dict set ::knowledge::Explicit menu.view.panes.players [dict create purpose {Show or hide the database's player table.} when {Use this to browse players represented in stored games.} examples {{Show the players pane} {Hide the database player table}}]
dict set ::knowledge::Explicit menu.view.panes.positions [dict create purpose {Show or hide the database's position table.} when {Use this to browse stored position records.} examples {{Show the positions pane} {Hide the database position table}}]
dict set ::knowledge::Explicit menu.view.panes.sites [dict create purpose {Show or hide the database's site table.} when {Use this to browse venues represented in stored games.} examples {{Show the sites pane} {Hide the database venue table}}]
dict set ::knowledge::Explicit menu.view.theme [dict create purpose {Apply the selected installed interface theme.} when {Use this to change the appearance of window controls.} examples {{Use another installed interface theme} {Change the app's widget theme}}]
dict set ::knowledge::Explicit menu.view.tip [dict create purpose {Open a tip about using the application.} when {Use this when you want to discover a useful feature.} examples {{Show a tip about using Chesswiz} {Open the Tip of the Day window}}]
dict set ::knowledge::Explicit nav-enter-var [dict create purpose {Move to the next available variation at the board position.} when {Use this to explore another branch while playing through analysis.} examples {{Go into the next variation} {Navigate down to another game branch}}]
dict set ::knowledge::Explicit nav-fast-back [dict create purpose {Move the board backward by ten half-moves.} when {Use this to review an earlier stretch of the game quickly.} examples {{Go back ten half-moves} {Move backward by five full moves}}]
dict set ::knowledge::Explicit nav-fast-forward [dict create purpose {Move the board forward by ten half-moves.} when {Use this to skip ahead while reviewing a long game.} examples {{Go forward ten half-moves} {Move ahead by five full moves}}]
dict set ::knowledge::Explicit nav-forward [dict create purpose {Play the next recorded move on the board.} when {Use this to follow a game one step at a time.} examples {{Show the next recorded move} {Advance the board by one half-move}}]
dict set ::knowledge::Explicit nav-leave-var [dict create purpose {Move to the previous available variation at the board position.} when {Use this when returning to an earlier branch choice.} examples {{Go into the previous variation} {Navigate up to the preceding game branch}}]
dict set ::knowledge::Explicit view.board3d.embed [dict create purpose {Toggle the three-dimensional board inside the main window.} when {Use this to study the position in an embedded perspective view.} examples {{Show a 3D board in the main window} {Hide the embedded three-dimensional board}}]
dict set ::knowledge::Explicit view.board3d.open [dict create purpose {Open the separate three-dimensional board viewer.} when {Use this when you want a perspective view in its own window.} examples {{Open a separate 3D board window} {Show the position in the standalone 3D viewer}}]
dict set ::knowledge::Explicit view.board3d.webgl [dict create purpose {Open the browser-based three-dimensional board viewer.} when {Use this to view the position using the web board display.} examples {{Open the browser 3D board} {Show this position in the web-based 3D viewer}}]
dict set ::knowledge::Explicit view.focus_pin [dict create purpose {Toggle whether automatic pane zoom preserves the board's size.} when {Use this to keep the board stable while other panes gain space.} examples {{Pin the board size during pane zoom} {Let the board resize with automatic pane zoom}}]
dict set ::knowledge::Explicit view.focus_ratio [dict create purpose {Cycle the size ratio used when focus enlarges a pane.} when {Use this to adjust how much extra space the active pane receives.} examples {{Change the automatic pane-zoom ratio} {Adjust how much the focused pane grows}}]
dict set ::knowledge::Explicit view.focus_zoom [dict create purpose {Toggle automatic pane enlargement as focus moves.} when {Use this when the view you are working in should gain space.} examples {{Make pane size follow focus} {Turn off automatic focus-based pane enlargement}}]
dict set ::knowledge::Explicit view.pane_zoom [dict create purpose {Maximise the active pane or restore the workspace arrangement.} when {Use this to concentrate temporarily on a single view.} examples {{Maximise the active workspace pane} {Restore the workspace after pane zoom}}]
# End reviewed native knowledge: interface

# Resolved missing context leaves
dict set ::knowledge::Explicit c2.strip.language [dict create purpose {Show the available languages for selective comment removal.} when {Use this when cleaning comments in only one language.} examples {{Choose a comment language to remove} {Show language-specific comment removal options}}]
dict set ::knowledge::Explicit c11.draft_comment [dict create purpose {Draft a position comment in the editor for your review.} when {Use this when you want a grounded starting point for an annotation.} examples {{Draft an annotation for this position} {Suggest comment text for me to review}}]
dict set ::knowledge::Explicit c12.save.line [dict create purpose {Show repertoire destinations for the line up to the current move.} when {Use this to keep an opening line for later practice.} examples {{Save the line up to this tab's current move to a repertoire} {Choose a repertoire for the moves played to this position}}]
dict set ::knowledge::Explicit c12.save.repertoire [dict create purpose {Show repertoire destinations for the selected game.} when {Use this to keep a game as part of your opening preparation.} examples {{Add this game tab to a repertoire} {Choose a repertoire destination for this game}}]
dict set ::knowledge::Explicit c5.player.prep [dict create purpose {Open the preparation report for the selected player.} when {Use this when gathering material about an opponent.} examples {{Open this player's preparation report} {Show the selected opponent's preparation statistics}}]
dict set ::knowledge::Explicit c5.site_url [dict create purpose {Open the web address recorded for the selected site.} when {Use this when a venue entry contains a useful link.} examples {{Visit the selected site's web address} {Open the link recorded in this site row}}]
dict set ::knowledge::Explicit c7.external [dict create purpose {Open the selected media with an external player.} when {Use this when you prefer another installed playback program.} examples {{Play this media in an external program} {Open the selected recording outside Chesswiz}}]
dict set ::knowledge::Explicit c9.report.family [dict create purpose {Show typeface choices for the displayed report.} when {Use this when changing the report's letter style.} examples {{Choose a report typeface from this pane} {Show font-family choices for this report}}]
dict set ::knowledge::Explicit c9.report.size [dict create purpose {Show text-size choices for the displayed report.} when {Use this when report text needs a different scale.} examples {{Choose a text size for this report} {Show report font-size options here}}]
dict set ::knowledge::Explicit c9.report.zoom [dict create purpose {Show point-size choices for magnifying report text.} when {Use this to make a displayed report easier to read.} examples {{Choose the report's magnification} {Show zoom choices from this report pane header}}]

# Concrete situations for commands whose purpose comes from registry documentation.
dict set ::knowledge::Explicit add_engine when {When an engine you installed is missing from the engine chooser.}
dict set ::knowledge::Explicit analysis.info when {When the engine toolbar is too crowded or omits details you want to see.}
dict set ::knowledge::Explicit app.preferences.assistant when {When you want to change how the assistant behaves.}
dict set ::knowledge::Explicit board.display when {When variation previews linger too long or promoted pieces need a visible mark.}
dict set ::knowledge::Explicit board.game_source when {When the board's next-game button should follow a different collection.}
dict set ::knowledge::Explicit board.navigate when {When you want to examine another point or branch of the game already loaded.}
dict set ::knowledge::Explicit board.piece_preview when {When comparing a piece design against different squares before applying it.}
dict set ::knowledge::Explicit board.start_preset when {When starting a fresh game from a nonstandard built-in arrangement.}
dict set ::knowledge::Explicit board3d.camera when {When you want to inspect the 3D position from another side.}
dict set ::knowledge::Explicit board3d.pieces when {When the current 3D pieces are hard to distinguish.}
dict set ::knowledge::Explicit board3d.theme when {When you want a different coordinated appearance for the 3D board.}
dict set ::knowledge::Explicit browser.display when {When an open game browser's move list needs a different reading format.}
dict set ::knowledge::Explicit browser.size when {When an open browser board is too small or occupies too much space.}
dict set ::knowledge::Explicit c2.strip.truncate when {When the continuation after the current position should be discarded.}
dict set ::knowledge::Explicit c7.sync.position when {When selecting a move should seek to its moment in the video.}
dict set ::knowledge::Explicit c7.sync.timeline when {When watching the video continuously should advance the game alongside it.}
dict set ::knowledge::Explicit c7.sync_options when {When the video and the moves should follow one another differently.}
dict set ::knowledge::Explicit c9.media.sync when {When choosing whether playback or board navigation leads a lesson.}
dict set ::knowledge::Explicit cancel_timer when {When a known scheduled callback should no longer run.}
dict set ::knowledge::Explicit child_processes when {When investigating a helper program that may still be running.}
dict set ::knowledge::Explicit classifier_status when {When checking why simple requests are taking a particular routing path.}
dict set ::knowledge::Explicit clear_search when {When a previous search is hiding games you want to browse again.}
dict set ::knowledge::Explicit comment_kind when {When organizing annotation text by its subject without changing the notes.}
dict set ::knowledge::Explicit convert_database when {When an existing collection needs a writable native-format copy.}
dict set ::knowledge::Explicit cql_help when {When you need worked examples before expressing a position search.}
dict set ::knowledge::Explicit database.clear_clipbase when {When temporary games of the current variant are no longer needed.}
dict set ::knowledge::Explicit database.copy_choice when {When a database drag has paused to ask which games to copy.}
dict set ::knowledge::Explicit database.description when {When identifying a collection by more than its filename.}
dict set ::knowledge::Explicit database.games_view when {When you want to jump to a game or adjust the game list's scrolling.}
dict set ::knowledge::Explicit database.recent_remove when {When an obsolete entry should disappear from the recent-file list.}
dict set ::knowledge::Explicit database.repertoire_type when {When a collection should serve as your opening repertoire for a chosen color.}
dict set ::knowledge::Explicit database.symbol_size when {When collection icons are difficult to read or take too much room.}
dict set ::knowledge::Explicit database.variant when {When browsing another ruleset stored in the same database.}
dict set ::knowledge::Explicit database_properties when {When checking a collection's format, encoding, or storage details.}
dict set ::knowledge::Explicit database_summary when {When you want a quick statistical picture before exploring a collection.}
dict set ::knowledge::Explicit database_trend when {When deciding which openings are prominent in the active collection.}
dict set ::knowledge::Explicit detect_language purpose {Identify the language of a chess comment.}
dict set ::knowledge::Explicit detect_language when {When the language of an imported chess comment is unclear.}
dict set ::knowledge::Explicit diagnose_import when {When an import reports codes that do not explain how to repair the source.}
dict set ::knowledge::Explicit discover_databases when {When you do not know where a chess collection is stored on disk.}
dict set ::knowledge::Explicit download_games when {When you want fresh games from a supported internet source.}
dict set ::knowledge::Explicit engine.dictionary_sort when {When finding an engine is easier by rating than by its current list order.}
dict set ::knowledge::Explicit engine_analysis when {When you want to read the running engines' current candidate lines.}
dict set ::knowledge::Explicit engine_evaluate when {When you need an engine assessment without opening an analysis pane.}
dict set ::knowledge::Explicit engine_options when {When checking which settings and values an engine profile supports.}
dict set ::knowledge::Explicit eval_tcl when {When an explicitly authorized debugging task needs an interpreter expression.}
dict set ::knowledge::Explicit event_types when {When comparing the time controls represented in a player's recent games.}
dict set ::knowledge::Explicit factcheck_annotations when {When imported or personal notes may contradict the positions they describe.}
dict set ::knowledge::Explicit files.bookmark when {When you repeatedly navigate to the same folder in file dialogs.}
dict set ::knowledge::Explicit files.delete when {When an unwanted file should be removed through the file picker's normal policy.}
dict set ::knowledge::Explicit files.drop_choice when {When a file drop is waiting for a copy, move, or link decision.}
dict set ::knowledge::Explicit files.mutate when {When preparing folders or making a named copy within an open file picker.}
dict set ::knowledge::Explicit files.picker when {When an open file dialog needs a different directory or display mode.}
dict set ::knowledge::Explicit find_capability when {When you know the task you want but do not know its available actions or arguments.}
dict set ::knowledge::Explicit find_similar when {When you want examples of games that reached positions resembling the board.}
dict set ::knowledge::Explicit game-export when {When sharing the game currently on the board in another format.}
dict set ::knowledge::Explicit game-first when {When beginning a sequential review of the active database.}
dict set ::knowledge::Explicit game-last when {When jumping directly to the final game of the active database.}
dict set ::knowledge::Explicit game-next when {When continuing a review with the following database game.}
dict set ::knowledge::Explicit game-prev when {When returning to the preceding database game during review.}
dict set ::knowledge::Explicit game.copy when {When transferring selected games through the application clipboard.}
dict set ::knowledge::Explicit game.explain when {When you want a readable account of the loaded game's character and outcome.}
dict set ::knowledge::Explicit game.paste when {When clipboard games should be added to a writable destination collection.}
dict set ::knowledge::Explicit game.transpose when {When exploring the loaded game with its position transposed in a trial copy.}
dict set ::knowledge::Explicit game.trial when {When experimenting with continuations without committing them to the original game.}
dict set ::knowledge::Explicit game.undo when {When correcting the last notation edit or restoring an edit you undid.}
dict set ::knowledge::Explicit game.variation_first when {When a side line should appear before its sibling variations.}
dict set ::knowledge::Explicit gamebar.display when {When game tabs or player headings occupy an inconvenient arrangement.}
dict set ::knowledge::Explicit gamebar.lock when {When a reviewed game should remain protected in its current slot.}
dict set ::knowledge::Explicit goto_move when {When the discussion refers to a numbered move in the loaded game.}
dict set ::knowledge::Explicit handoff_issue when {When a triaged source-code issue is ready for the configured coding agent.}
dict set ::knowledge::Explicit help.viewer when {When reading local documentation and navigating its sections or index.}
dict set ::knowledge::Explicit install_chessbase_fonts when {When suitable figurine fonts are available in a Windows font folder.}
dict set ::knowledge::Explicit layout.align_lines when {When a text pane ends with a partially visible line.}
dict set ::knowledge::Explicit layout.delete when {When a saved arrangement is obsolete and should no longer be offered.}
dict set ::knowledge::Explicit layout.group when {When related panes should share tabs or appear in separate windows.}
dict set ::knowledge::Explicit layout.rename when {When a saved arrangement needs a more recognizable name.}
dict set ::knowledge::Explicit list_engines when {When choosing among the engine programs already available to the application.}
dict set ::knowledge::Explicit list_issues when {When reviewing the bugs recorded by error triage.}
dict set ::knowledge::Explicit list_open_databases when {When checking which collection is active among several open databases.}
dict set ::knowledge::Explicit loop_health when {When investigating pauses or delayed input in the interface.}
dict set ::knowledge::Explicit maintenance_report when {When deciding whether a database needs cleanup or duplicate review.}
dict set ::knowledge::Explicit media_state when {When diagnosing playback, volume, or the current media position.}
dict set ::knowledge::Explicit menu.analysis.compare_engines when {When comparing how different engines assess the same position.}
dict set ::knowledge::Explicit menu.analysis.engine_toggle when {When beginning or pausing live analysis of the board.}
dict set ::knowledge::Explicit menu.analysis.engines when {When adding an engine or editing an installed engine's configuration.}
dict set ::knowledge::Explicit menu.analysis.explorer when {When exploring the opening choices available from the board position.}
dict set ::knowledge::Explicit menu.analysis.game_review when {When looking for mistakes and turning points throughout a game.}
dict set ::knowledge::Explicit menu.analysis.review_engine when {When a game review should use a different engine.}
dict set ::knowledge::Explicit menu.db.discover when {When locating chess collections whose disk locations you have forgotten.}
dict set ::knowledge::Explicit menu.db.player.names when {When inconsistent player spellings may split one player's statistics.}
dict set ::knowledge::Explicit menu.db.properties when {When inspecting the active collection's storage and format information.}
dict set ::knowledge::Explicit menu.db.readonly when {When protecting a collection from edits or enabling edits again.}
dict set ::knowledge::Explicit menu.db.reports.eco when {When comparing opening results across the active collection.}
dict set ::knowledge::Explicit menu.db.reports.opening when {When studying the database evidence for the current opening position.}
dict set ::knowledge::Explicit menu.db.reports.repertoire when {When reviewing the coverage of your opening preparation.}
dict set ::knowledge::Explicit menu.db.search.advanced when {When simple criteria cannot express the games you want to find.}
dict set ::knowledge::Explicit menu.db.search.duplicates when {When repeated copies may be inflating a collection.}
dict set ::knowledge::Explicit menu.db.search.material when {When finding games with a particular balance of pieces.}
dict set ::knowledge::Explicit menu.db.search.rating when {When limiting games to players within a rating range.}
dict set ::knowledge::Explicit menu.edit.keyboard when {When changing or checking the keys assigned to commands.}
dict set ::knowledge::Explicit menu.edit.preferences.engines when {When adjusting the application's engine-related preferences.}
dict set ::knowledge::Explicit menu.edit.preferences.pgn when {When exported game text needs different formatting or included details.}
dict set ::knowledge::Explicit menu.edit.preferences.player when {When updating the private identity used for your own games.}
dict set ::knowledge::Explicit menu.file.archive_create when {When packaging a collection for transfer or backup.}
dict set ::knowledge::Explicit menu.file.close when {When you have finished with the active collection.}
dict set ::knowledge::Explicit menu.file.export.archive when {When another computer needs a portable copy of the collection.}
dict set ::knowledge::Explicit menu.file.export.html when {When publishing selected games as a readable web document.}
dict set ::knowledge::Explicit menu.file.export.pgn when {When another chess program needs the collection or filtered games as text.}
dict set ::knowledge::Explicit menu.file.import.pgn when {When adding games from an existing game-text file.}
dict set ::knowledge::Explicit menu.file.open when {When you know the database file you want to work with.}
dict set ::knowledge::Explicit menu.game.close when {When the loaded game no longer needs to occupy a game slot.}
dict set ::knowledge::Explicit menu.game.load_number when {When you know a game's index within the active collection.}
dict set ::knowledge::Explicit menu.help.support when {When you want to contribute to continued application development.}
dict set ::knowledge::Explicit menu.tools.book when {When inspecting or editing an opening book.}
dict set ::knowledge::Explicit menu.tools.correspondence when {When managing games played by correspondence.}
dict set ::knowledge::Explicit menu.tools.download when {When choosing an internet source from which to obtain games.}
dict set ::knowledge::Explicit menu.tools.engine_console when {When diagnosing the messages exchanged with a running engine.}
dict set ::knowledge::Explicit menu.tools.iccf when {When configuring correspondence-server settings.}
dict set ::knowledge::Explicit menu.tools.import_games when {When bringing games from another source into a database.}
dict set ::knowledge::Explicit menu.tools.player_card when {When looking up a player's ratings and career statistics.}
dict set ::knowledge::Explicit menu.tools.player_dictionary when {When finding a player beyond the current collection's list.}
dict set ::knowledge::Explicit menu.training.brief when {When preparing to face a specific opponent.}
dict set ::knowledge::Explicit menu.training.engine_match when {When testing two engines against one another.}
dict set ::knowledge::Explicit menu.training.guess when {When practicing prediction by choosing the next move yourself.}
dict set ::knowledge::Explicit menu.training.play_engine when {When you want the computer to play the opposing side.}
dict set ::knowledge::Explicit menu.training.repertoire when {When rehearsing the moves of your prepared openings.}
dict set ::knowledge::Explicit menu.training.studyplan when {When deciding what to practice based on your own games.}
dict set ::knowledge::Explicit menu.training.tactics when {When practicing concrete tactical puzzles.}
dict set ::knowledge::Explicit menu.training.training_set when {When turning a collection of games into practice material.}
dict set ::knowledge::Explicit menu.view.font_dec when {When interface text takes up too much space.}
dict set ::knowledge::Explicit menu.view.font_inc when {When interface text is difficult to read at its current size.}
dict set ::knowledge::Explicit menu.view.layout.manage when {When organizing the arrangements you have saved.}
dict set ::knowledge::Explicit menu.view.layout.save when {When you want to return later to the current pane arrangement.}
dict set ::knowledge::Explicit menu.view.panes.analysis when {When live engine lines need more space or should be put away.}
dict set ::knowledge::Explicit menu.view.panes.assistant when {When you want to expose or put away the conversation area.}
dict set ::knowledge::Explicit menu.view.panes.board when {When changing whether the board occupies space in the layout.}
dict set ::knowledge::Explicit menu.view.panes.editor when {When changing whether the move notation occupies space in the layout.}
dict set ::knowledge::Explicit menu.view.panes.explorer when {When opening choices should be visible beside the board or put away.}
dict set ::knowledge::Explicit menu.view.panes.games when {When changing whether a game list appears beside the board.}
dict set ::knowledge::Explicit menu.view.panes.media when {When a video lesson should be visible beside the board or put away.}
dict set ::knowledge::Explicit menu.view.panes.report when {When a generated report should be visible beside the board or put away.}
dict set ::knowledge::Explicit menu.view.panes.tree when {When database move statistics should be visible beside the board or put away.}
dict set ::knowledge::Explicit move.choice when {When entering a move has paused to ask how it should affect an existing continuation.}
dict set ::knowledge::Explicit move.promotion when {When a pawn has reached its final rank and needs a promotion piece.}
dict set ::knowledge::Explicit nav-end when {When you want to inspect the game's final recorded position.}
dict set ::knowledge::Explicit nav-start when {When replaying the game from its initial arrangement.}
dict set ::knowledge::Explicit notation.display when {When the move list needs columns or different move-information details.}
dict set ::knowledge::Explicit notation.language when {When multilingual comments should be limited to the languages you read.}
dict set ::knowledge::Explicit novelty_label when {When checking whether a position is represented in the available precedent index.}
dict set ::knowledge::Explicit open_game when {When selecting a known game number or a player's latest game for review.}
dict set ::knowledge::Explicit open_play_engine when {When setting your color before starting a computer opponent.}
dict set ::knowledge::Explicit open_position when {When a position-search result should be inspected on the board.}
dict set ::knowledge::Explicit open_view when {When you want a report or information window without modifying games.}
dict set ::knowledge::Explicit opening_score when {When comparing results for an opening code or family in the active collection.}
dict set ::knowledge::Explicit overview.rotate when {When reviewing thumbnail boards from the opposite side.}
dict set ::knowledge::Explicit playercard.trace when {When diagnosing the rendering or data behind an open player card.}
dict set ::knowledge::Explicit position_moves when {When choosing a continuation based on games that reached the board position.}
dict set ::knowledge::Explicit print when {When you want a paper or PDF copy of the loaded game.}
dict set ::knowledge::Explicit read_variable when {When an authorized debugging task needs the current interpreter state.}
dict set ::knowledge::Explicit release_grab when {When a modal grab is preventing clicks from reaching the intended window.}
dict set ::knowledge::Explicit remember_me when {When reports should recognize which games and player name are yours.}
dict set ::knowledge::Explicit remove_engine when {When an engine should disappear from the chooser while its program remains installed.}
dict set ::knowledge::Explicit run_action when {When a discovered action and its validated argument names are already known.}
dict set ::knowledge::Explicit run_job when {When a supported preparation or review workflow should run as a series of steps.}
dict set ::knowledge::Explicit save.match_fields when {When a save form offers matched player or event details to apply.}
dict set ::knowledge::Explicit save.tags when {When a save form needs additional metadata beyond its standard fields.}
dict set ::knowledge::Explicit save_pattern when {When a successful position search should be reusable under a memorable name.}
dict set ::knowledge::Explicit save_working_set when {When search results should become a separate collection for later work.}
dict set ::knowledge::Explicit set_engine_option when {When a known engine setting needs a new value within its supported range.}
dict set ::knowledge::Explicit show_search when {When you want to browse the games found by the most recent search.}
dict set ::knowledge::Explicit similar_games when {When looking for games that share the early moves of a selected game.}
dict set ::knowledge::Explicit stop_engine when {When live analysis is no longer needed.}
dict set ::knowledge::Explicit structure_profile when {When preparing against a player by studying recurring pawn structures and results.}
dict set ::knowledge::Explicit switch_tab when {When the next task belongs in another main application workspace.}
dict set ::knowledge::Explicit table.column_size when {When a table column clips its contents or wastes horizontal space.}
dict set ::knowledge::Explicit table.find_object when {When locating a known player, event, or site in an open table.}
dict set ::knowledge::Explicit table.player_source when {When a player table should include or exclude the player database.}
dict set ::knowledge::Explicit timers when {When diagnosing delayed callbacks or interpreter channels.}
dict set ::knowledge::Explicit tool_log when {When checking what the assistant attempted and whether those operations succeeded.}
dict set ::knowledge::Explicit toolbar.configure when {When a visible toolbar needs different controls or presentation.}
dict set ::knowledge::Explicit toolbar.frame when {When aligning a toolbar or changing how its containing frame uses space.}
dict set ::knowledge::Explicit tournament.table when {When inspecting another event or changing an open tournament table's presentation.}
dict set ::knowledge::Explicit transcribe_media when {When you want readable speech from a recorded lesson.}
dict set ::knowledge::Explicit triage_errors when {When newly recorded errors need categorization and issue reports.}
dict set ::knowledge::Explicit ui_state when {When diagnosing window placement, keyboard focus, or a modal grab.}
dict set ::knowledge::Explicit view.dialog.close when {When an information or preferences window has served its purpose.}

# Plain-language descriptions for operators whose technical docs are not user help.
dict set ::knowledge::Explicit add_engine purpose {Add a chess engine installed on your computer.}
dict set ::knowledge::Explicit add_engine when {When you want to analyze or play with another chess engine.}
dict set ::knowledge::Explicit app-find purpose {Find text or games in the view you are working in.}
dict set ::knowledge::Explicit board.navigate purpose {Move through the current game's main line or variations.}
dict set ::knowledge::Explicit browser.size purpose {Make the board in a game browser larger or smaller.}
dict set ::knowledge::Explicit c4.new.scid purpose {Create a database in Chesswiz's own storage format.}
dict set ::knowledge::Explicit c8.search.slow when {Use this when thorough opening-tree results matter more than speed.}
dict set ::knowledge::Explicit cancel_timer purpose {Cancel a scheduled task.}
dict set ::knowledge::Explicit cancel_timer when {When a scheduled task should no longer run.}
dict set ::knowledge::Explicit classifier_status when {When checking how Chesswiz chooses actions for simple requests.}
dict set ::knowledge::Explicit convert_database when {When you need an editable Chesswiz copy of an existing collection.}
dict set ::knowledge::Explicit database.games_view purpose {Move through the database game list or change how its scrollbars appear.}
dict set ::knowledge::Explicit database.recent_remove purpose {Remove a database from the recently used list without deleting or closing its file.}
dict set ::knowledge::Explicit database.repertoire_type purpose {Mark an editable Chesswiz database as a repertoire for both colors, White or Black.}
dict set ::knowledge::Explicit eval_tcl purpose {Run a debugging instruction and report its result.}
dict set ::knowledge::Explicit eval_tcl when {When investigating a problem in a debugging session.}
dict set ::knowledge::Explicit files.bookmark purpose {List, add, rename or remove favorite folders in the file chooser.}
dict set ::knowledge::Explicit files.delete purpose {Remove a file or folder and its associated database files, using the file chooser.}
dict set ::knowledge::Explicit files.delete when {When you want to remove an unwanted file from your computer.}
dict set ::knowledge::Explicit game.transpose purpose {Rearrange the move order in a trial copy of the current game.}
dict set ::knowledge::Explicit handoff_issue when {When a recorded problem is ready to send to the coding assistant.}
dict set ::knowledge::Explicit layout.align_lines purpose {Adjust a text view to show whole lines without a partly hidden last line.}
dict set ::knowledge::Explicit layout.group purpose {Arrange a group of views as tabs or as separate windows.}
dict set ::knowledge::Explicit list_procs purpose {Find internal operations by name.}
dict set ::knowledge::Explicit list_procs when {Use this when investigating which part of Chesswiz performs an operation.}
dict set ::knowledge::Explicit menu.db.maintenance.convert purpose {Open conversion of the current database to Chesswiz's own format.}
dict set ::knowledge::Explicit menu.db.maintenance.convert when {Use this when a collection should become an editable Chesswiz database.}
dict set ::knowledge::Explicit proc_source purpose {Show how a named internal operation is written.}
dict set ::knowledge::Explicit proc_source when {Use this when investigating a problem in an internal operation.}
dict set ::knowledge::Explicit read_variable purpose {Read a named internal setting or group of settings.}
dict set ::knowledge::Explicit read_variable when {When investigating settings during a debugging session.}
dict set ::knowledge::Explicit release_grab purpose {Free the mouse from a window that is preventing clicks elsewhere.}
dict set ::knowledge::Explicit release_grab when {When a window prevents you from clicking the rest of Chesswiz.}
dict set ::knowledge::Explicit run_action when {When capability discovery has identified the operation and the information it needs.}
dict set ::knowledge::Explicit table.player_source purpose {Turn player-information lookup on or off in a player list and refresh the displayed details.}
dict set ::knowledge::Explicit timers purpose {List scheduled tasks and open connections.}
dict set ::knowledge::Explicit timers when {When investigating delayed work or a connection that remains open.}
dict set ::knowledge::Explicit toolbar.configure purpose {View or change the controls and appearance of a selected toolbar.}
dict set ::knowledge::Explicit toolbar.database_switcher.3 purpose {Close the active database.}
dict set ::knowledge::Explicit triage_errors purpose {Group newly recorded problems and create a report for each suspected bug.}
dict set ::knowledge::Explicit ui_state purpose {Show open windows, their sizes and positions, and which window receives typing and mouse clicks.}
dict set ::knowledge::Explicit ui_state when {When investigating window placement or a window that prevents normal interaction.}

# Further prose audit: describe the result, rather than an internal workflow.
dict set ::knowledge::Explicit app-quit purpose {Close Chesswiz after checking whether your work needs saving.}
dict set ::knowledge::Explicit c10.optimize purpose {Choose widths that fit the selected table's contents.}
dict set ::knowledge::Explicit c11.classify_comment purpose {Label the selected comment by the kind of annotation it contains.}
dict set ::knowledge::Explicit c12.import_game purpose {Open the window for importing a game from PGN text.}
dict set ::knowledge::Explicit c12.save.replace_moves purpose {Save the selected game tab by replacing its stored moves.}
dict set ::knowledge::Explicit c3.merge purpose {Open choices for combining the selected database game with another game.}
dict set ::knowledge::Explicit c4.download_games purpose {Open game downloads for the active database.}
dict set ::knowledge::Explicit c4.search.current purpose {Search the database using the current game.}
dict set ::knowledge::Explicit database_trend purpose {Summarize the active database's opening trends, results and most frequently played openings.}
dict set ::knowledge::Explicit game-replace-moves purpose {Open saving options to replace the current game's stored moves.}
dict set ::knowledge::Explicit game.explain purpose {Explain the current game's opening, style of play and result in the Report pane.}
dict set ::knowledge::Explicit list_issues purpose {List recorded bugs, showing the newest reports first.}
dict set ::knowledge::Explicit loop_health purpose {Show how long Chesswiz stopped responding and when those delays occurred.}
dict set ::knowledge::Explicit media_state purpose {Show the current media file, playback progress, duration and volume.}
dict set ::knowledge::Explicit menu.analysis.analyze purpose {Start engine analysis of the board position.}
dict set ::knowledge::Explicit menu.analysis.annotate purpose {Start or stop automatic engine annotation of the game.}
dict set ::knowledge::Explicit menu.db.maintenance.compact purpose {Remove deleted games and reclaim space in the current database.}
dict set ::knowledge::Explicit menu.db.maintenance.strip_moves purpose {Remove the current game's moves.}
dict set ::knowledge::Explicit menu.db.player.update purpose {Open the rating-data update window.}
dict set ::knowledge::Explicit menu.game.paste_tab purpose {Paste a copied game into the selected game tab.}
dict set ::knowledge::Explicit menu.help.bug purpose {Open a form to report a problem with Chesswiz.}
dict set ::knowledge::Explicit menu.help.feature purpose {Open a form to suggest an improvement to Chesswiz.}
dict set ::knowledge::Explicit run_action purpose {Run a Chesswiz operation found by capability discovery.}
dict set ::knowledge::Explicit run_job when {When preparation or review needs several supported operations in sequence.}
dict set ::knowledge::Explicit save_pattern purpose {Save the last position search and its accepted examples under a short name.}
dict set ::knowledge::Explicit notation.display purpose {Set the arrangement of game text or choose which move details to show.}
dict set ::knowledge::Explicit find_capability purpose {Find the Chesswiz operations that can perform a task.}
dict set ::knowledge::Explicit find_capability when {When you know your task but need to find which operations can perform it.}
dict set ::knowledge::Explicit menu.analysis.compare_engines purpose {Open or use the comparison of chess engines.}
dict set ::knowledge::Explicit menu.analysis.review_engine purpose {Choose the chess engine used for game review.}
dict set ::knowledge::Explicit menu.tools.iccf purpose {View or change correspondence-server settings.}
dict set ::knowledge::Explicit menu.training.training_set purpose {Choose positions from database games for a training set.}
dict set ::knowledge::Explicit tool_log purpose {List the recent operations the assistant attempted and their results.}
dict set ::knowledge::Explicit classifier_status purpose {Show which service chooses actions for simple requests and whether it is responding.}
dict set ::knowledge::Explicit board3d.pieces purpose {Choose how the pieces look on the three-dimensional board.}
dict set ::knowledge::Explicit playercard.trace when {When investigating the appearance or information in an open player card.}

# User help spells out game formats, positions and opening classifications.
dict set ::knowledge::Explicit c12.import_game purpose {Open the window for importing a game from portable game notation text.}
dict set ::knowledge::Explicit database_summary purpose {Summarize the active database: number of games and players, overall results, and the most played openings (opening classification) with their scores.}
dict set ::knowledge::Explicit engine_evaluate purpose {Ask the chess engine directly (no analysis pane needed) for the best moves in a position and their scores: the current board or a supplied position description.}
dict set ::knowledge::Explicit export_database purpose {Export games from a database to a portable game notation file.}
dict set ::knowledge::Explicit export_database examples {{export my games to portable game notation} {save these games as a portable game notation file}}
dict set ::knowledge::Explicit import_games purpose {Import games from a portable game notation file into a database.}
dict set ::knowledge::Explicit import_games when {Use this when you have games in a portable game notation file and want them in Chesswiz.}
dict set ::knowledge::Explicit import_games examples {{import a portable game notation file into my database} {add these portable game notation games to my database}}
dict set ::knowledge::Explicit menu.db.reports.eco purpose {Open the opening preparation statistics (opening classification) of the database.}
dict set ::knowledge::Explicit menu.db.reports.eco examples {{Show game results grouped by opening} {Review this database by opening classification}}
dict set ::knowledge::Explicit menu.edit.preferences.pgn purpose {Open the portable game notation export options.}
dict set ::knowledge::Explicit menu.edit.preferences.pgn examples {{How do I use ‘portable game notation export options’?} {Help me use ‘portable game notation export options’}}
dict set ::knowledge::Explicit menu.file.export.pgn purpose {Export the database or the listed games as portable game notation.}
dict set ::knowledge::Explicit menu.file.export.pgn examples {{Export my game collection as readable game text} {Save the listed games in portable game notation}}
dict set ::knowledge::Explicit menu.file.import.pgn purpose {Import portable game notation files into the database.}
dict set ::knowledge::Explicit menu.file.import.pgn examples {{Add games from a portable game notation file} {Import the games saved in a text file}}
dict set ::knowledge::Explicit opening_score purpose {Results of an opening in the active database, by opening classification code: 'B90' (one code), 'B9' (B90-B99), 'B' (B00-B99) or a range 'B90-B99'.}
dict set ::knowledge::Explicit set_position when {Use this when you want to enter a position from a book, diagram or a board-position description.}
dict set ::knowledge::Explicit set_position examples {{set up a position from a diagram in a book} {Set up the board from this position description}}
dict set ::knowledge::Explicit similar_games purpose {Find the games of the active database that share the most opening half-moves with one game and narrate why they are alike.}
dict set ::knowledge::Explicit toolbar.editor_game.1 when {Use this when you have a game copied as portable game notation text.}
dict set ::knowledge::Explicit c4.new.scid examples {{Create a database in Chesswiz's own format} {Start an editable game collection}}
dict set ::knowledge::Explicit c4.reports.opening examples {{Show the opening report for this database} {Review this collection by opening}}
dict set ::knowledge::Explicit eval_tcl examples {{Run a debugging instruction} {Evaluate an internal debugging command}}
dict set ::knowledge::Explicit menu.db.maintenance.convert examples {{Convert this collection to Chesswiz format} {Make an editable copy of this database}}
dict set ::knowledge::Explicit menu.game.paste_tab examples {{Paste the copied game into another tab} {Open a copied game in a new tab}}
dict set ::knowledge::Explicit menu.view.layout.pane examples {{Change the pane arrangement} {Show pane layout choices}}
dict set ::knowledge::Explicit menu.view.theme examples {{Choose another appearance theme} {Change the colors of the controls}}
dict set ::knowledge::Explicit release_grab examples {{Free the mouse from the stuck window} {Release a window that blocks other clicks}}
dict set ::knowledge::Explicit toolbar.database_switcher.3 examples {{Close the database shown in the switcher} {Stop working with the active collection}}

# Complete, plain seeds for long technical tool descriptions.
dict set ::knowledge::Explicit download_games purpose {Download games from a supported internet source into the active database.}
dict set ::knowledge::Explicit factcheck_annotations purpose {Check stored game comments against the positions they describe.}
dict set ::knowledge::Explicit novelty_label purpose {Check whether a move is known in the available master games.}
dict set ::knowledge::Explicit run_job purpose {Prepare for an opponent, review your games, check your repertoire or create training positions in a series of steps.}
dict set ::knowledge::Explicit classifier_status examples {{Which service chooses actions for my requests?} {Is the action-choosing service responding?}}

dict set ::knowledge::Explicit maintenance_report purpose {Open the database overview, duplicate-game report or opening coverage report.}
