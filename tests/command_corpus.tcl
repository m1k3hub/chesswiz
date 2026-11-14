# ======================================================================
# Command-style corpus derived from tests/assistant_corpus.tcl
# (docs/features/COMMAND_LINE_PLAN.md §3 & §4).
#
# InScopeCommandCorpus:
#   id job original_request command_text expected_id expected_action expected_args
#
# OutOfScopeCorpusIds:
#   id reason (per docs/features/COMMAND_LINE_PLAN.md §3 "Requests deliberately left out")
# ======================================================================

set InScopeCommandCorpus {
	db-summary J1 {What's in this database?}
		{database summary} 4 database_summary {}
	db-open-list J1 {Which databases are open?}
		{list open databases} 5 list_open_databases {}
	db-duplicates J1 {Are there duplicate games in here?}
		{find duplicates} 11 maintenance_report {tab duplicates}
	db-export J1 {Export the games in the list as a PDF.}
		{export list as pdf to /tmp/corpus-export.pdf} 8 command.export {scope list format pdf filename /tmp/corpus-export.pdf}
	db-download J1 {Get this week's TWIC games.}
		{download twic} 9 command.twic {}
	db-workingset J1 {Keep the games in the list as a separate database.}
		{save list as new database WorkingSet} 10 save_working_set {name WorkingSet}

	find-player-wins J2 {Show me Kasparov's wins with White.}
		{find games player Kasparov wins white} 15 search_games {player {Kasparov, Garry} result win color white}
	find-years J2 {Games from 2015 to 2018 rated over 2600.}
		{find games from 2015 to 2018 min elo 2600} 15 search_games {from 2015 to 2018 min_elo 2600}
	find-eco J2 {Najdorf games in this database.}
		{find games opening Najdorf} 15 search_games {eco B9*}
	find-event J2 {Games from the Karvina 5th tournament.}
		{find games event Karvina} 15 search_games {event {Karvina 5th}}
	find-both-elo J2 {Games where both players are rated 2600 or more.}
		{find games both elo 2600} 15 search_games {both_min_elo 2600}
	find-endgames-opening J2 {All endgames that arise from the London System.}
		{find games opening London System motif endgame} 15 search_games {eco D02* pattern endgame}
	open-last-game J6 {Open Carlsen's last game.}
		{open last game of Carlsen} 17 open_game {player {Carlsen, Magnus}}
	event-story J10 {Tell me the story of the Biel tournament.}
		{event story Biel} 46 open_view {kind event_report event Biel}
	annotate-range J7 {Analyse moves 20 to 30 of this game.}
		{analyse moves 20 to 30} 38 annotate_game {prose 0 from_move 20 to_move 30}
	engine-best J7 {What does Stockfish say is the best move here?}
		{best move with Stockfish} 36 command.best {engine Stockfish}
	engine-check J7 {Is Nf5 a good move in this position?}
		{check move Nf3} 37 engine_check_move {move Nf3}
	tablebase-endgame J7 {Is this king and pawn endgame a win? Use the tablebase.}
		{tablebase} 39 tablebase {}
	pane-dock J1 {Dock the tree window.}
		{dock tree} 50 pane {action dock pane tree}
	find-draws J2 {All draws since 2020.}
		{find games draws from 2020} 15 search_games {result 1/2-1/2 from 2020}
	find-similar-games J2 {Find games like the one on the board.}
		{games like this one} 18 command.similar {}

	pos-fork J3 {Find games where a knight forks king and queen.}
		{find motif knight fork} 19 search_games {pattern knight_fork}
	pos-smothered J3 {Smothered mates, please.}
		{find motif smothered mate} 19 search_games {pattern smothered_mate}
	pos-rook7 J3 {Games with a rook on the seventh rank.}
		{find motif rook on the seventh} 19 search_games {pattern rook_seventh}
	pos-greek J3 {Find a Greek gift sacrifice on h7.}
		{find motif greek gift} 19 search_games {pattern greek_gift}
	pos-underprom J3 {Show me underpromotions.}
		{find motif underpromotion} 19 search_games {pattern underpromotion}
	pos-iqp J3 {Positions with an isolated queen's pawn.}
		{find motif isolated queen's pawn} 19 search_games {pattern isolated_queen_pawn}
	pos-oppbishops J3 {Endgames with opposite-coloured bishops.}
		{find motif opposite-coloured bishops} 19 search_games {pattern opposite_bishops}
	pos-like-board J3 {Find positions like this one.}
		{find positions like the board} 20 find_similar {aspects {pawns material pieces} mode all}
	pos-structure J3 {Games with the same pawn structure as on the board.}
		{find positions like the board pawn structure only} 20 find_similar {aspects pawns mode all}
	pos-structure-loose J3 {Similar pawn structures, one pawn may differ.}
		{find positions like the board pawn structure only one pawn may differ} 20 find_similar {aspects pawns tolerance 1 mode all}
	pos-backrank J3 {Back-rank mates in this database.}
		{find motif back-rank mate} 19 search_games {pattern back_rank_mate}
	pos-lucena J3 {Show me Lucena positions.}
		{find motif lucena} 19 search_games {pattern lucena}
	pos-carlsbad J3 {Games with the Carlsbad pawn structure.}
		{find motif carlsbad} 19 search_games {pattern carlsbad}
	pos-outpost J3 {Knight outposts in my games.}
		{find games player Thomas motif knight outpost} 15 search_games {player {Thomas, Michael} pattern knight_outpost}
	pos-skewer J3 {Find skewers in this database.}
		{find motif skewer} 19 search_games {pattern skewer}
	pos-hedgehog J3 {Hedgehog structures since 2015.}
		{find motif hedgehog from 2015} 19 search_games {pattern hedgehog from 2015}
	pos-gun J3 {Has anyone set up Alekhine's gun here?}
		{find motif alekhine's gun} 19 search_games {pattern alekhines_gun}
	pos-philidor J3 {Rook endings where the defender holds the Philidor position.}
		{find motif philidor position} 19 search_games {pattern philidor_position}
	pos-badbishop J3 {Games where someone was stuck with a bad bishop.}
		{find motif bad bishop} 19 search_games {pattern bad_bishop}
	pos-pawnfork J3 {Show me pawn forks from 2020 on.}
		{find motif pawn fork from 2020} 19 search_games {pattern pawn_fork from 2020}

	open-najdorf J4 {Set up the Najdorf after 6.Bg5.}
		{set up Najdorf after 6.Bg5} 22 command.setup {opening *Najdorf* after 6.Bg5}
	open-tree J4 {What is played in this position?}
		{opening tree} 23 pane {action show pane tree}
	open-score J4 {How does White score in the Sicilian?}
		{score of Sicilian} 24 opening_score {eco B*}
	open-report J4 {Open the opening report for this position.}
		{opening report} 25 open_view {kind opening_report}
	open-trend J4 {Which openings are getting more popular here?}
		{opening trends} 26 command.trends {}
	open-rep-check J4 {Check my repertoire against my games.}
		{repertoire check against my games} 27 repertoire_check {}
	open-rep-add J4 {Add this line to my repertoire.}
		{repertoire add this line} 27 add_to_repertoire {}

	prep-brief J5 {Prepare me for my game against Corti, Horacio. He plays black.}
		{prepare against Corti i have white} 28 opponent_brief {prose 0 download 0 name {Corti, Horacio} colour black}
	prep-lines J5 {What does Corti play as White, and where is he weak?}
		{prepare against Corti i have black} 28 opponent_brief {prose 0 download 0 name {Corti, Horacio} colour white}
	prep-report J5 {Open Corti's prep report.}
		{player Corti prep report} 30 open_view {kind prep_report name {Corti, Horacio}}
	prep-stats J5 {How does Corti score?}
		{player Corti stats} 30 player_stats {name {Corti, Horacio}}
	prep-structures J5 {Which pawn structures does Corti reach, and how does he score in them?}
		{player Corti structures} 30 structure_profile {player {Corti, Horacio}}

	me-remember J6 {By the way, I'm Anna Musterfrau.}
		{i am Musterfrau} 31 remember_me {name {Musterfrau, Anna}}
	me-review J6 {Review my last 10 games.}
		{review my last 10 games} 32 command.review {games 10 player {Thomas, Michael}}
	me-record J6 {How did I score?}
		{my score} 32 command.my_score {player {Thomas, Michael}}
	me-annotate J6 {Annotate the game on the board with the engine.}
		{annotate game} 38 annotate_game {prose 0}
	me-current J6 {Which game is on the board?}
		{which game is on the board} 34 current_game {}

	eng-start J7 {Start the engine on this position.}
		{start Stockfish} 35 start_engine {engine Stockfish}
	eng-lines J7 {What does the engine say here?}
		{best move} 36 command.best {}
	eng-list J7 {Which engines do I have?}
		{list engines} 41 list_engines {}

	train-set J8 {Make me tactics puzzles from my games.}
		{puzzles from my games} 44 command.training {source {my games} player {Thomas, Michael}}
	train-mates J8 {Puzzles with checkmates from this database.}
		{puzzles from this database motif checkmate} 44 command.training {source {this database} pattern checkmate}

	play-card J10 {Show Carlsen's player card.}
		{player card Carlsen} 29 open_view {kind player_card name {Carlsen, Magnus}}
	play-cross J10 {Show the crosstable of Karvina 5th.}
		{crosstable Karvina} 45 open_view {kind crosstable event {Karvina 5th}}

	game-open J2 {Open game 12 after Black's 20th move.}
		{open game 12 at move 20 black} 16 open_game {number 12 move 20 after black}
	board-new J7 {Start a new game.}
		{new game} 43 new_game {}
	board-tab J1 {Go to the database tab.}
		{go to database} 49 command.tab {tab database}

	db-overview J1 {Give me an overview of this collection.}
		{database overview} 4 database_summary {}
	db-clear J1 {Show all games again, remove the filter.}
		{show all games} 6 clear_search {}
	db-material J1 {I want to search by material myself.}
		{search by material} 21 open_search {kind material}
	db-export-pgn J1 {Save these games as a PGN file.}
		{export list as pgn to /tmp/corpus-export.pgn} 8 command.export {scope list format pgn filename /tmp/corpus-export.pgn}
	find-carlsen-black J2 {Carlsen's losses with Black.}
		{find games player Carlsen losses black} 15 search_games {player {Carlsen, Magnus} result loss color black}
	find-2700 J2 {Only games where both players are above 2700.}
		{find games both elo 2700} 15 search_games {both_min_elo 2700}
	find-kid J2 {All King's Indian games.}
		{find games opening King's Indian} 15 search_games {eco E[6-9]*}
	find-like-5 J2 {Which games resemble game 5?}
		{games like game 5} 18 command.similar {number 5}
	game-like-board J2 {Are there games like the one I'm looking at?}
		{games like this one} 18 command.similar {}
	pos-bridge J3 {Building a bridge in rook endings: find examples.}
		{find motif building a bridge} 19 search_games {pattern lucena}
	pos-d5-knight J3 {Knights on d5 that can't be chased away.}
		{find motif knight outpost} 19 search_games {pattern knight_outpost}
	open-kid-score J4 {What's White's score against the King's Indian here?}
		{score of King's Indian} 24 opening_score {eco E[6-9]*}
	open-player-eco J4 {How does Kasparov do in the Sicilian?}
		{score of Sicilian for Kasparov} 24 opening_score {eco B* player {Kasparov, Garry}}
	board-dragon J4 {Put the Dragon on the board after 9.Bc4.}
		{set up Sicilian, Dragon after 9.Bc4} 22 command.setup {opening *Dragon* after 9.Bc4}
	prep-card J5 {Pull up Caruana's player card.}
		{player card Caruana} 29 open_view {kind player_card name {Caruana, Fabiano}}
	prep-white J5 {I play Corti next round and I have White. Prepare me.}
		{prepare against Corti i have white} 28 opponent_brief {prose 0 download 0 name {Corti, Horacio} colour black}
	me-plan J6 {Make me a study plan from my recent games.}
		{study plan from my games} 33 command.study {player {Thomas, Michael}}
	eng-stop J7 {Stop the engine.}
		{stop Stockfish} 35 command.stop {engine Stockfish}
	eng-threads J7 {Let Stockfish use 8 threads.}
		{set Stockfish threads 8} 40 start_engine {engine Stockfish threads 8}
	train-forks J8 {Give me knight fork puzzles.}
		{puzzles from this database motif knight fork} 44 command.training {source {this database} pattern knight_fork}
	play-trend J10 {What's trending in openings lately?}
		{opening trends} 26 command.trends {}

	db-compact J1 {Compact my database.}
		{compact Main} 12 command.compact {database Main}
	db-shrink J1 {Clean up the deleted games and shrink the file.}
		{compact database Main} 12 command.compact {database Main}
	db-convert J1 {Convert this database to Scidb's format.}
		{convert Main to sci} 13 command.convert {database Main format sci}
	db-maintenance J1 {Show me the maintenance report.}
		{maintenance report} 14 maintenance_report {tab overview}
	db-import J1 {Import /home/user/twic1650.pgn into this database.}
		{import /tmp/corpus-import.pgn into Main} 7 command.import {files /tmp/corpus-import.pgn database Main}
}

# Every remaining id in tests/assistant_corpus.tcl is explicitly out of scope per
# docs/features/COMMAND_LINE_PLAN.md §3 ("Requests deliberately left out") and §6 ("Language"):
set OutOfScopeCorpusIds {
	find-show        {conversation memory / implicit reference ("Put those games in the game list")}
	pos-qsac         {arbitrary custom position outside the 40-pattern index}
	open-prep        {opening preparation dialog not in the 50-command table}
	me-explain       {generation ("Ask a question" mode: "Explain the position on the board")}
	play-events      {event_types query not in the 50-command table}
	game-open-match  {conversation memory ("Show me the second position you found")}
	check-results    {check_results audit not in the 50-command table}
	factcheck        {generation ("Ask a question" mode: "Check the annotations of this game")}
	ask-back         {conversation memory ("Open that one")}
	pos-german       {German language (Plan §6: English first, German later from the same tables)}
	pos-windmill     {arbitrary custom tactic outside the 40-pattern index}
	me-annotate-plain {free-form style generation ("no fancy words")}
	db-eco-coverage  {openings coverage tab not in the 50-command table}
	corr-my-move     {correspondence chess (J12)}
	corr-open        {correspondence chess (J12)}
	media-lesson     {media lessons (J9)}
	media-play       {media lessons (J9)}
}
