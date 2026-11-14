# Hand-written commands and independent expected registry calls (plan ids 1-50).
set CommandCases {
 1 {open database /tmp/command-fixture.pgn} open_database {path /tmp/command-fixture.pgn}
 2 {switch to Main} command.database.select {database Main}
 3 {close database Other} command.database.close {database Other}
 4 {database overview} database_summary {}
 5 {list open databases} list_open_databases {}
 6 {clear filter} clear_search {}
 7 {import /tmp/command-fixture.pgn into Main} command.import {files /tmp/command-fixture.pgn database Main}
 8 {export list as pdf to /tmp/command-output.pdf} command.export {scope list format pdf filename /tmp/command-output.pdf}
 9 {download twic 1650} command.twic {issue 1650}
 10 {save list as new database Tactics} save_working_set {name Tactics}
 11 {find duplicates} maintenance_report {tab duplicates}
 12 {compact Main} command.compact {database Main}
 13 {convert Main to sci} command.convert {database Main format sci}
 14 {maintenance report} maintenance_report {tab overview}
 15 {find kasp wins wh} search_games {player {Kasparov, Garry} result win color white}
 16 {open game 12 at move 20 black} open_game {number 12 move 20 after black}
 17 {open last game of Carlsen} open_game {player {Carlsen, Magnus}}
 18 {like game 5} command.similar {number 5}
 19 {find motif knight fork from 2020} search_games {pattern knight_fork from 2020}
 20 {find positions like the board pawn structure only one pawn may differ} find_similar {aspects pawns tolerance 1 mode all}
 21 {search by material} open_search {kind material}
 22 {set up Najdorf after 6.Bg5} command.setup {opening Najdorf after 6.Bg5}
 23 {opening tree} pane {action show pane tree}
 24 {score of Sicilian for Kasparov} opening_score {eco B player {Kasparov, Garry}}
 25 {opening report} open_view {kind opening_report}
 26 {opening trends} command.trends {}
 27 {repertoire add this line} add_to_repertoire {}
 28 {prepare against Corti i have white} opponent_brief {prose 0 download 0 name {Corti, Horacio} colour black}
 29 {player card Caruana} open_view {kind player_card name {Caruana, Fabiano}}
 30 {Corti stats} player_stats {name {Corti, Horacio}}
 31 {i am Thomas} remember_me {name {Thomas, Michael}}
 32 {review my last 10 games} command.review {games 10 player {Thomas, Michael}}
 33 {study plan from my games} command.study {player {Thomas, Michael}}
 34 {which game is on the board} current_game {}
 35 {start Stockfish} start_engine {engine Stockfish}
 36 {best move with Stockfish} command.best {engine Stockfish}
 37 {check move e4} engine_check_move {move e4}
 38 {analyse moves 20 to 30} annotate_game {prose 0 from_move 20 to_move 30}
 39 {tablebase} tablebase {}
 40 {set Stockfish threads 8} start_engine {engine Stockfish threads 8}
 41 {list engines} list_engines {}
 42 {play Stockfish 3+2 as black} command.play {engine Stockfish time_control 3+2 color black}
 43 {new game} new_game {}
 44 {puzzles from my games motif knight fork} command.training {source {my games} pattern knight_fork player {Thomas, Michael}}
 45 {crosstable Karvina} open_view {kind crosstable event {Karvina 5th}}
 46 {event story Biel} open_view {kind event_report event Biel}
 47 {run double round robin of 4 engines 3+2 opening London} command.tournament {system {double round robin} engine_count 4 time_control 3+2 opening {London System}}
 48 {tournament director} td.workspace {}
 49 {go to database} command.tab {tab database}
 50 {dock tree} pane {action dock pane tree}
}
