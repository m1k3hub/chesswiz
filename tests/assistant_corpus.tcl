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
#   have); looking first with read-only tools is fine (ReadOnly in the
#   runner). A request that needs the user's name assumes remember_me has
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
	find-both-elo J2 {Games where both players are rated 2600 or more.} {{search_games both_min_elo 2600}}
	find-endgames-opening J2 {All endgames that arise from the London System.} {{search_games eco * pattern endgame} {find_positions}}
	open-last-game J6 {Open Carlsen's last game.} {{open_game player *carlsen*}}
	event-story J10 {Tell me the story of the Biel tournament.} {{open_view kind event_report event *biel*}}
	annotate-range J7 {Analyse moves 20 to 30 of this game.} {{annotate_game from_move 20 to_move 30}}
	engine-best J7 {What does Stockfish say is the best move here?} {{engine_evaluate} {engine_analysis} {start_engine}}
	engine-check J7 {Is Nf5 a good move in this position?} {{engine_check_move move Nf5}}
	tablebase-endgame J7 {Is this king and pawn endgame a win? Use the tablebase.} {{tablebase}}
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
	pos-philidor J3 {Rook endings where the defender holds the Philidor position.} {{search_games pattern philidor_position}}
	pos-badbishop J3 {Games where someone was stuck with a bad bishop.} {{search_games pattern bad_bishop}}
	pos-pawnfork J3 {Show me pawn forks from 2020 on.} {{search_games pattern pawn_fork from 2020*}}

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

	db-overview J1 {Give me an overview of this collection.} {{database_summary}}
	db-clear J1 {Show all games again, remove the filter.} {{clear_search}}
	db-material J1 {I want to search by material myself.} {{open_search kind material}}
	db-export-pgn J1 {Save these games as a PGN file.} {{export_database} {save_working_set}}
	ask-back J1 {Open that one.} {{none} {open_game} {open_position}}
	find-carlsen-black J2 {Carlsen's losses with Black.} {{search_games player *carlsen* color black result loss}}
	find-2700 J2 {Only games where both players are above 2700.} {{search_games both_min_elo 27*}}
	find-kid J2 {All King's Indian games.} {{search_games eco E6*} {search_games eco E[6-9]*}}
	find-like-5 J2 {Which games resemble game 5?} {{similar_games number 5}}
	game-like-board J2 {Are there games like the one I'm looking at?} {{similar_games} {find_similar}}
	pos-german J3 {Finde Partien mit einem erstickten Matt.} {{search_games pattern smothered_mate}}
	pos-bridge J3 {Building a bridge in rook endings: find examples.} {{search_games pattern lucena}}
	pos-d5-knight J3 {Knights on d5 that can't be chased away.} {{search_games pattern knight_outpost} {cql_help} {find_positions}}
	pos-windmill J3 {Find a windmill combination.} {{cql_help} {find_positions}}
	open-kid-score J4 {What's White's score against the King's Indian here?} {{opening_score eco E*}}
	open-player-eco J4 {How does Kasparov do in the Sicilian?} {{opening_score eco B* player *kasparov*}}
	board-dragon J4 {Put the Dragon on the board after 9.Bc4.} {{set_position moves *bc4*}}
	prep-card J5 {Pull up Caruana's player card.} {{open_view kind player_card name *caruana*}}
	prep-white J5 {I play Corti next round and I have White. Prepare me.} {{run_job job prepare name *corti*} {opponent_brief name *corti*} {prepare_against name *corti*}}
	me-plan J6 {Make me a study plan from my recent games.} {{run_job job review} {study_plan player *thomas*}}
	me-annotate-plain J6 {Comment this game quickly, no fancy words.} {{annotate_game}}
	eng-stop J7 {Stop the engine.} {{stop_engine}}
	eng-threads J7 {Let Stockfish use 8 threads.} {{set_engine_option option *thread* value 8} {start_engine threads 8}}
	train-forks J8 {Give me knight fork puzzles.} {{training_set pattern knight_fork} {run_job job train}}
	play-trend J10 {What's trending in openings lately?} {{database_trend}}
}
