# ======================================================================
# The Ask Scidb request corpus (ASSISTANT_COVERAGE_MAP.md §7, "How it is
# measured"): requests a chess player makes, by job, and what solves them.
# tests/run_assistant_corpus.tcl asks the configured model each one and
# scores whether a fitting tool was called.
#
# Entry: id job request expect
#   expect: {tool ?arg glob ...?} ... -- the request is solved when the
#   model calls one of these tools with those arguments (each arg value
#   matched case-insensitively as a glob); {none} means asking back is the
#   right answer (the request refers to something the conversation does not
#   have). A request that needs the user's name assumes remember_me has
#   "Thomas, Michael".
# ======================================================================

set Corpus {
	db-summary J1 {What's in this database?} {{database_summary}}
	db-open-list J1 {Which databases are open?} {{list_open_databases}}
	db-duplicates J1 {Are there duplicate games in here?} {{open_view kind duplicates}}
	db-export J1 {Export the games in the list as a PDF.} {{export_database}}
	db-download J1 {Get this week's TWIC games.} {{download_games}}
	db-workingset J1 {Keep the games in the list as a separate database.} {{save_working_set}}

	find-player-wins J2 {Show me Kasparov's wins with White.} {{search_games player *kasparov* color white result win}}
	find-years J2 {Games from 2015 to 2018 rated over 2600.} {{search_games from 2015 to 2018 min_elo 2600}}
	find-eco J2 {Najdorf games in this database.} {{search_games eco B9*}}
	find-event J2 {Games from the Karvina 5th tournament.} {{search_games event *karvina*} {open_view kind crosstable}}
	find-draws J2 {All draws since 2020.} {{search_games result *1/2* from 2020*} {search_games result draw from 2020*}}
	find-similar-games J2 {Find games like the one on the board.} {{similar_games} {find_similar}}
	find-show J2 {Put those games in the game list.} {{show_search} {none}}

	pos-fork J3 {Find games where a knight forks king and queen.} {{search_games pattern knight_fork} {cql_help} {find_positions}}
	pos-smothered J3 {Smothered mates, please.} {{search_games pattern smothered_mate} {cql_help} {find_positions}}
	pos-rook7 J3 {Games with a rook on the seventh rank.} {{search_games pattern rook_seventh} {cql_help} {find_positions}}
	pos-greek J3 {Find a Greek gift sacrifice on h7.} {{search_games pattern greek_gift} {cql_help} {find_positions}}
	pos-underprom J3 {Show me underpromotions.} {{search_games pattern underpromotion} {cql_help} {find_positions}}
	pos-iqp J3 {Positions with an isolated queen's pawn.} {{search_games pattern isolated_queen_pawn} {cql_help} {find_positions}}
	pos-oppbishops J3 {Endgames with opposite-coloured bishops.} {{search_games pattern opposite_bishops} {cql_help} {find_positions}}
	pos-like-board J3 {Find positions like this one.} {{find_similar}}
	pos-structure J3 {Games with the same pawn structure as on the board.} {{find_similar}}
	pos-structure-loose J3 {Similar pawn structures, one pawn may differ.} {{find_similar tolerance 1}}
	pos-backrank J3 {Back-rank mates in this database.} {{search_games pattern back_rank_mate} {cql_help} {find_positions}}
	pos-qsac J3 {Games where a queen was taken by a pawn.} {{cql_help} {find_positions}}
	pos-lucena J3 {Show me Lucena positions.} {{search_games pattern lucena}}
	pos-carlsbad J3 {Games with the Carlsbad pawn structure.} {{search_games pattern carlsbad}}
	pos-outpost J3 {Knight outposts in my games.} {{search_games pattern knight_outpost player *thomas*}}
	pos-skewer J3 {Find skewers in this database.} {{search_games pattern skewer}}
	pos-hedgehog J3 {Hedgehog structures since 2015.} {{search_games pattern hedgehog from 2015*}}
	pos-gun J3 {Has anyone set up Alekhine's gun here?} {{search_games pattern alekhines_gun}}

	open-najdorf J4 {Set up the Najdorf after 6.Bg5.} {{set_position moves *bg5*}}
	open-tree J4 {What is played in this position?} {{position_moves}}
	open-score J4 {How does White score in the Sicilian?} {{opening_score eco B*}}
	open-report J4 {Open the opening report for this position.} {{open_view kind opening_report}}
	open-prep J4 {Show me the opening preparation dialog.} {{open_view kind opening_prep}}
	open-trend J4 {Which openings are getting more popular here?} {{database_trend}}
	open-rep-check J4 {Check my repertoire against my games.} {{repertoire_check} {run_job job repertoire}}
	open-rep-add J4 {Add this line to my repertoire.} {{add_to_repertoire} {none}}

	prep-brief J5 {Prepare me for my game against Corti, Horacio. He plays black.} {{run_job job prepare name *corti*} {opponent_brief name *corti*}}
	prep-lines J5 {What does Corti play as White, and where is he weak?} {{prepare_against name *corti*} {run_job job prepare}}
	prep-report J5 {Open Corti's prep report.} {{open_view kind prep_report name *corti*}}
	prep-stats J5 {How does Corti score?} {{player_stats name *corti*}}
	prep-structures J5 {Which pawn structures does Corti reach, and how does he score in them?} {{structure_profile player *corti*}}

	me-remember J6 {By the way, I'm Anna Musterfrau.} {{remember_me name *musterfrau*}}
	me-review J6 {Review my last 10 games.} {{run_job job review} {study_plan player *thomas*}}
	me-record J6 {How did I score?} {{player_stats name *thomas*}}
	me-annotate J6 {Annotate the game on the board with the engine.} {{annotate_game}}
	me-explain J6 {Explain the position on the board.} {{explain_position}}
	me-current J6 {Which game is on the board?} {{current_game}}

	eng-start J7 {Start the engine on this position.} {{start_engine}}
	eng-lines J7 {What does the engine say here?} {{engine_analysis} {start_engine}}
	eng-list J7 {Which engines do I have?} {{list_engines}}

	train-set J8 {Make me tactics puzzles from my games.} {{run_job job train} {training_set player *thomas*}}
	train-mates J8 {Puzzles with checkmates from this database.} {{training_set pattern checkmate}}

	play-card J10 {Show Carlsen's player card.} {{open_view kind player_card name *carlsen*}}
	play-cross J10 {Show the crosstable of Karvina 5th.} {{open_view kind crosstable event *karvina*}}
	play-events J10 {What kinds of time controls are in this database?} {{event_types}}

	game-open J2 {Open game 12 after Black's 20th move.} {{open_game number 12 move 20 after black}}
	game-open-match J3 {Show me the second position you found.} {{open_position index 2} {none}}
	board-new J7 {Start a new game.} {{new_game}}
	board-tab J1 {Go to the database tab.} {{switch_tab tab database}}
	check-results J1 {Find games where the result is wrong.} {{check_results}}
	factcheck J6 {Check the annotations of this game.} {{factcheck_annotations}}
}
