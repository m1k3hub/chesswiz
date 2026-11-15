# English command grammar. Stable numeric ids correspond to COMMAND_LINE_PLAN.md.
# @name is a typed slot; {? ...} is an optional group; @criteria is a search tail.
# Variants share an id, but may select a different fixed registry action.
namespace eval ::commandline {
 variable Table {
  {1 open_database {} {{open database @path}}}
  {2 command.database.select {} {{switch to @database} {select database @database}}}
  {3 command.database.close {} {{close database @database}}}
  {4 database_summary {} {{database summary} {database overview}}}
  {5 list_open_databases {} {{list open databases}}}
  {6 clear_search {} {{show all games} {clear filter}}}
  {7 command.import {} {{import @file {? into @database}}}}
  {8 command.export {} {{export @scope as @format to @output}}}
  {9 command.twic {} {{download twic {? @issue}}}}
  {10 save_working_set {} {{save list as new database @name}}}
  {11 maintenance_report {tab duplicates} {{find duplicates}}}
  {12 command.compact {} {{compact @database} {compact database @database}}}
  {13 command.convert {} {{convert @database to @dbformat}}}
  {14 maintenance_report {tab overview} {{maintenance report}}}
  {15 command.find {} {{find games @criteria} {find @criteria}}}
  {16 open_game {} {{open game @number {? at move @move_number {? @after}}}}}
  {17 open_game {} {{open last game of @player}}}
  {18 command.similar {} {{games like this one} {games like game @number} {like game @number}}}
  {19 command.find {} {{find motif @pattern {? from @from}}}}
  {20 find_similar {aspects {pawns material pieces} mode all} {{find positions like the board}}}
  {20 find_similar {aspects pawns mode all} {{find positions like the board pawn structure only} {find pawn structure}}}
  {20 find_similar {aspects pawns tolerance 1 mode all} {{find positions like the board pawn structure only one pawn may differ}}}
  {21 open_search {kind material} {{search by material}}}
  {22 command.setup {} {{set up @opening {? after @opening_move}}}}
  {23 pane {action show pane tree} {{opening tree}}}
  {24 opening_score {} {{score of @eco {? for @player}}}}
  {25 open_view {kind opening_report} {{opening report}}}
  {26 open_view {kind trend} {{opening trends}}}
  {27 add_to_repertoire {} {{repertoire add this line}}}
  {27 repertoire_check {} {{repertoire check against my games}}}
  {28 opponent_brief {prose 0 download 0} {{prepare against @opponent {? i have @colour}} {prepare against @opponent {? as @colour}}}}
  {29 open_view {kind player_card} {{player card @person}}}
  {30 command.player_stats {} {{player @person stats} {@person stats}}}
  {30 command.structure_profile {} {{player @player structures} {@player structures}}}
  {30 open_view {kind prep_report} {{player @person prep report} {@person prep report}}}
  {31 remember_me {} {{i am @person}}}
  {32 command.review {} {{review my last @games games}}}
  {32 command.my_score {} {{my score}}}
  {33 command.study {} {{study plan from my games}}}
  {34 current_game {} {{which game is on the board} {current game}}}
  {35 start_engine {} {{start @engine} {start engine @engine}}}
  {35 command.stop {} {{stop @engine} {stop engine @engine}}}
  {36 command.best {} {{best move {? with @engine}}}}
  {37 engine_check_move {} {{check move @move}}}
  {38 annotate_game {prose 0} {{analyse moves @from_move to @to_move} {analyze moves @from_move to @to_move} {annotate game}}}
  {39 tablebase {} {{tablebase}}}
  {40 command.set_threads {} {{set @engine threads @threads}}}
  {41 list_engines {} {{list engines}}}
  {42 command.play {} {{play @engine {? @time_control} {? as @color}}}}
  {43 new_game {} {{new game}}}
  {44 command.training {} {{puzzles from @training_source {? motif @pattern}}}}
  {45 open_view {kind crosstable} {{crosstable @event}}}
  {46 open_view {kind event_report} {{event story @event}}}
  {47 command.tournament {} {{run @system of @engine_count engines {? @time_control} {? opening @opening}}}}
  {48 td.workspace {} {{tournament director}}}
  {49 command.tab {} {{go to @tab}}}
  {50 pane {} {{@pane_action @pane}}}
  {51 command.open_result {} {{open result @result_index}}}
 }
 variable Types {
  path inputfile file pgnfile output outputfile name filename
  database database player player person player opponent player event event site site
  opening opening eco eco pattern motif engine engine pane pane tab tab
  number integer move_number integer games integer issue integer threads integer
  from_move integer to_move integer engine_count integer from year to year
  min_elo rating both_min_elo rating move move opening_move opening_move
  colour color color color after color result result scope scope format format
  dbformat dbformat training_source training_source time_control time_control system system
  pane_action pane_action result_index result_index
 }
 variable Keys {person name opponent name move_number move colour colour file files output filename dbformat format training_source source opening_move after pane_action action}
 variable Enums {
  color {white black} result {win loss draw} scope {list database}
  format {pgn pdf html} dbformat {sci} training_source {{my games} {this database}}
  system {{round robin} {double round robin}} pane_action {dock undock maximise}
 }
}
