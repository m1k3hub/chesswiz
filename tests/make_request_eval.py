#!/usr/bin/env python3
# Generates tests/fixtures/request-eval.jsonl (VAL-KNOW-008 held-out corpus).
# Written from the feature inventory (docs/menu PROPOSAL areas) on 2026-10-21
# before any model run; the earlier 89-item set became request-dev.jsonl.
import json, sys
I = []
def item(id, area, request, predicate, actions, gold, setup=None, multi=0, loose=0):
    d = {"id": id, "area": area, "request": request, "predicate": predicate,
         "actions": actions, "gold": gold}
    if setup: d["setup"] = setup
    if multi: d["multi"] = 1
    if loose: d["loose"] = 1
    I.append(d)

RA = ["run_action"]
OPEN_CLUB = "::application::database::openBase .application @CLUB@ yes -encoding $::encoding::autoEncoding -switchToBase 1"
FILTER = "gold_call search_games {%s}; gold_call show_search"

# --- databases -------------------------------------------------------------
item("dbh-open", "databases", "Open my club database, it's the file @CLUB@.",
     "ev_db_is @CLUB@", ["open_database", "menu.file.open"] + RA,
     "gold_call open_database [list path @CLUB@]")
item("dbh-close", "databases", "Close this database, I'm done with it.",
     "expr {![ev_open @CLUB@] && [ev_open @MAIN@]}", ["menu.file.close"] + RA,
     "gold_run menu.file.close", setup=OPEN_CLUB)
item("dbh-switch", "databases", "go back to the main database",
     "ev_db_is @MAIN@", ["open_database", "menu.file.open", "switch_tab"] + RA,
     "gold_call open_database [list path @MAIN@]", setup=OPEN_CLUB, loose=1)
item("dbh-props", "databases", "Show the properties of the current database.",
     "ev_opened prop", ["menu.db.properties", "database_properties", "open_view"] + RA,
     "gold_run menu.db.properties")
item("dbh-discover", "databases", "look for chess databses on my computer",
     "ev_opened discover", ["discover_databases", "menu.db.discover"] + RA,
     "gold_call discover_databases", loose=1)
item("dbh-readonly", "databases", "Make this database read-only so I can't change it by accident.",
     "::scidb::db::get readonly? @MAIN@", ["menu.db.readonly"] + RA,
     "gold_run menu.db.readonly")
item("dbh-open-load", "databases", "Open @CLUB@ and load its third game.",
     "expr {[ev_db_is @CLUB@] && [ev_gameno] == 3}",
     ["open_database", "open_game", "menu.file.open", "menu.game.load_number"] + RA,
     "gold_call open_database [list path @CLUB@]; gold_call open_game {number 3}", multi=1)
item("dbh-close-tab", "databases", "Close the club database and then show me the database tab.",
     "expr {![ev_open @CLUB@] && [ev_tab] eq {database}}", ["menu.file.close", "switch_tab"] + RA,
     "gold_run menu.file.close; gold_call switch_tab {tab database}", setup=OPEN_CLUB, multi=1)

# --- games / PGN editing ---------------------------------------------------
item("gameh-load100", "games", "Load game 100.",
     "expr {[ev_gameno] == 100}", ["open_game", "menu.game.load_number"] + RA,
     "gold_call open_game {number 100}")
item("gameh-first", "games", "Go to the first game of the database.",
     "expr {[ev_gameno] == 1}", ["open_game", "game-first"] + RA,
     "gold_run game-first")
item("gameh-prev", "games", "show me the previous game",
     "expr {[ev_gameno] == 9}", ["open_game", "game-prev"] + RA,
     "gold_run game-prev", loose=1)
item("gameh-new", "games", "I want a blank game so I can enter moves.",
     "expr {[ev_moves] == 0 && [ev_tag White] in {{} ?}}", ["new_game", "game-new"] + RA,
     "gold_call new_game")
item("gameh-truncate", "games", "Delete all the moves after this point in the game.",
     "expr {[ev_gameno] == 10 && [ev_ply] == 12 && [ev_moves] == 12}", ["c2.strip.truncate"] + RA,
     "gold_run c2.strip.truncate")
item("gameh-goodmove", "games", "Mark the move just played as a good move.",
     "expr {[ev_gameno] == 10 && [lsearch -regexp [::scidb::game::query annotation] {^(\\$)?1$|^!$}] >= 0}",
     ["annot-good-move"] + RA, "gold_run annot-good-move")
item("gameh-andreikin", "games", "andreikins latest game on the board pls",
     "expr {[ev_player_in_game Andreikin] && [ev_gameno] > 0}", ["open_game", "search_games", "show_search"] + RA,
     "gold_call open_game {player Andreikin}", loose=1)
item("gameh-caruana-first", "games", "Find Caruana's games and load the first one in the list.",
     "expr {[ev_player_in_game Caruana] && [ev_gameno] > 0}",
     ["search_games", "show_search", "open_game"] + RA,
     FILTER % "player Caruana" + "; gold_call open_game [list number [expr {[::scidb::db::get gameNumber [ev_db] Normal 0 0] + 1}]]", multi=1)
item("gameh-load-end", "games", "Open game 12 and jump to its final position.",
     "expr {[ev_gameno] == 12 && [ev_ply] == [ev_moves] && [ev_moves] > 0}",
     ["open_game", "nav-end"] + RA,
     "gold_call open_game {number 12}; gold_run nav-end", multi=1)
item("gameh-load-truncate", "games", "Load game 20, go to White's 10th move and cut off everything after it.",
     "expr {[ev_gameno] == 20 && [ev_moves] == 19 && [ev_ply] == 19}",
     ["open_game", "c2.strip.truncate"] + RA,
     "gold_call open_game {number 20 move 10}; ::scidb::game::go key [lindex [::scidb::game::query mainline] 18 0]; gold_run c2.strip.truncate", multi=1)
item("gameh-new-moves", "games", "Start a new game and play 1.e4 c5 on it.",
     "expr {[ev_moves] == 2 && [lrange [ev_fen] 0 1] eq {rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w}}",
     ["new_game", "set_position", "game-new"] + RA,
     "gold_call new_game; gold_call set_position {moves {1.e4 c5}}", multi=1)

# --- board / position setup ------------------------------------------------
item("boardh-moves", "board", "Set up the position after 1.d4 Nf6 2.c4 e6 3.Nc3 Bb4.",
     "expr {[lindex [ev_fen] 0] eq {rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR}}",
     ["set_position"] + RA, "gold_call set_position {moves {1.d4 Nf6 2.c4 e6 3.Nc3 Bb4}}")
item("boardh-fen", "board", "Put this position on the board: 8/8/8/4k3/8/8/4P3/4K3 w - - 0 1",
     "expr {[lindex [ev_fen] 0] eq {8/8/8/4k3/8/8/4P3/4K3} && [lindex [ev_fen] 1] eq {w}}",
     ["set_position", "menu.board.setup"] + RA, "gold_call set_position {fen {8/8/8/4k3/8/8/4P3/4K3 w - - 0 1}}")
item("boardh-flip", "board", "turn the board around", "ev_flipped",
     ["board-flip", "c1.flip_board"] + RA, "gold_run board-flip", loose=1)
item("boardh-end", "board", "Go to the end of the game.",
     "expr {[ev_gameno] == 10 && [ev_ply] == [ev_moves]}", ["nav-end"] + RA, "gold_run nav-end")
item("boardh-start", "board", "Back to the start of the game, please.",
     "expr {[ev_gameno] == 10 && [ev_ply] == 0}", ["nav-start"] + RA, "gold_run nav-start")
item("boardh-back", "board", "Take back one move.",
     "expr {[ev_gameno] == 10 && [ev_ply] == 11}", ["nav-back"] + RA, "gold_run nav-back")
item("boardh-black8", "board", "Jump to Black's 8th move in this game.",
     "expr {[ev_gameno] == 10 && [ev_ply] == 16}", ["open_game"] + RA,
     "::scidb::game::go key [lindex [::scidb::game::query mainline] 15 0]")
item("boardh-flip-end", "board", "Flip the board and go to the final position.",
     "expr {[ev_flipped] && [ev_ply] == [ev_moves] && [ev_gameno] == 10}",
     ["board-flip", "nav-end"] + RA, "gold_run board-flip; gold_run nav-end", multi=1)
item("boardh-load-flip", "board", "Load game 50 and look at it from Black's side.",
     "expr {[ev_flipped] && [ev_gameno] == 50}", ["open_game", "board-flip"] + RA,
     "gold_call open_game {number 50}; gold_run board-flip", multi=1)

# --- search / filters ------------------------------------------------------
item("searchh-player", "search", "Show only Bortnyk's games in the game list.",
     "ev_filter_all Player *Bortnyk*", ["search_games", "show_search"] + RA,
     FILTER % "player Bortnyk")
item("searchh-eco", "search", "List the games that opened with ECO code B12.",
     "ev_filter_all ECO B12", ["search_games", "show_search"] + RA, FILTER % "eco B12")
item("searchh-event", "search", "Filter the game list to the Atyrau Chess Masters Open.",
     "ev_filter_all Event *Atyrau*", ["search_games", "show_search"] + RA, FILTER % "event Atyrau")
item("searchh-clear", "search", "Show all the games again.",
     "expr {[ev_search_count] == [ev_total_games]}", ["clear_search"] + RA,
     "gold_call clear_search", setup=FILTER % "player Caruana")
item("searchh-sarana-black", "search", "Show the games Sarana won with Black.",
     "expr {[ev_filter_all Black *Sarana*] && [ev_filter_all Result 0-1]}",
     ["search_games", "show_search"] + RA, FILTER % "player Sarana color black result win")
item("searchh-loose", "search", "maghsoodloo games??",
     "ev_filter_all Player *Maghsoodloo*", ["search_games", "show_search"] + RA,
     FILTER % "player Maghsoodloo", loose=1)
item("searchh-material", "search", "Open the material search.",
     "ev_opened material", ["open_search", "menu.db.search.material"] + RA, "gold_run menu.db.search.material")
item("searchh-dupes", "search", "Look for duplicate games in this database.",
     "ev_opened {duplic|maintenance}", ["open_view", "menu.db.search.duplicates", "maintenance_report"] + RA,
     "gold_run menu.db.search.duplicates")
item("searchh-tab-event", "search", "Go to the database tab and show only the games from the 41st ECC Open.",
     "expr {[ev_tab] eq {database} && [ev_filter_all Event *ECC*]}", ["switch_tab", "search_games", "show_search"] + RA,
     FILTER % "event {41st ECC Open}" + "; gold_call switch_tab {tab database}", multi=1)
item("searchh-event-load", "search", "Show the games from the FISU World Uni Classical and open the first one.",
     "expr {[ev_filter_all Event *Classical*] && [string match *Classical* [ev_tag Event]] && [ev_gameno] > 0}",
     ["search_games", "show_search", "open_game"] + RA,
     FILTER % "event {FISU World Uni Classical}" + "; gold_call open_game [list number [expr {[::scidb::db::get gameNumber [ev_db] Normal 0 0] + 1}]]", multi=1)

# --- trees / openings ------------------------------------------------------
item("treeh-show", "trees", "Show the opening tree.", "ev_pane_shown tree",
     ["menu.view.panes.tree", "pane"] + RA, "gold_run menu.view.panes.tree", setup="ev_pane_hide tree")
item("treeh-explorer", "trees", "Open the opening explorer.", "ev_pane_shown explorer",
     ["menu.view.panes.explorer", "menu.analysis.explorer", "pane"] + RA, "gold_run menu.view.panes.explorer",
     setup="ev_pane_hide explorer")
item("treeh-float", "trees", "Put the tree in a separate window.", "ev_floating tree",
     ["pane"] + RA, "gold_call pane {action undock pane tree}", setup="ev_pane_show tree")
item("treeh-report", "trees", "Make an opening report for this position.", "ev_opened report|opening",
     ["open_view", "menu.db.reports.opening"] + RA, "gold_run menu.db.reports.opening")
item("treeh-eco", "trees", "Show ECO statistics for this database.", "ev_opened {eco|opening prep}",
     ["open_view", "menu.db.reports.eco"] + RA, "gold_run menu.db.reports.eco")
item("treeh-moves-tree", "trees", "Set up 1.e4 e6 and show me the opening tree for it.",
     "expr {[lindex [ev_fen] 0] eq {rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR} && [ev_pane_shown tree]}",
     ["set_position", "menu.view.panes.tree", "pane"] + RA,
     "gold_call set_position {moves {1.e4 e6}}; gold_run menu.view.panes.tree", setup="ev_pane_hide tree", multi=1)
item("treeh-both", "trees", "show the tree and the explorer", "expr {[ev_pane_shown tree] && [ev_pane_shown explorer]}",
     ["menu.view.panes.tree", "menu.view.panes.explorer", "pane"] + RA,
     "gold_run menu.view.panes.tree; gold_run menu.view.panes.explorer",
     setup="ev_pane_hide tree; ev_pane_hide explorer", multi=1, loose=1)

# --- engines / analysis ----------------------------------------------------
item("engh-start", "engines", "Analyse this position with the engine.", "expr {[ev_engine_running] > 0}",
     ["start_engine", "menu.analysis.engine_toggle", "menu.analysis.analyze"] + RA,
     "gold_call start_engine")
item("engh-stop", "engines", "turn the engine off", "expr {[ev_engine_running] == 0}",
     ["stop_engine", "menu.analysis.engine_toggle"] + RA, "gold_call stop_engine",
     setup="::application::assistant::RunTool start_engine {}", loose=1)
item("engh-lines", "engines", "Start the engine and show three lines.",
     "expr {[ev_engine_running] > 0 && [ev_engine_lines] == 3}", ["start_engine"] + RA,
     "gold_call start_engine {lines 3}")
item("engh-pos-start", "engines", "Set up 1.e4 e5 2.Nf3 Nc6 3.Bb5 and start the engine on it.",
     "expr {[lindex [ev_fen] 0] eq {r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R} && [ev_engine_running] > 0}",
     ["set_position", "start_engine"] + RA,
     "gold_call set_position {moves {1.e4 e5 2.Nf3 Nc6 3.Bb5}}; gold_call start_engine", multi=1)
item("engh-console", "engines", "Open the engine console.", "ev_opened console",
     ["menu.tools.engine_console"] + RA, "gold_run menu.tools.engine_console")
item("engh-prefs", "engines", "Open the engine settings.", "ev_opened engine",
     ["menu.edit.preferences.engines", "menu.analysis.engines", "engine_options"] + RA, "gold_run menu.analysis.engines")
item("engh-pane", "engines", "Put the engine analysis pane in its own window.", "ev_floating analysis",
     ["pane"] + RA, "gold_call pane {action undock pane analysis}")
item("engh-flip-start", "engines", "Flip the board and start analysing.",
     "expr {[ev_flipped] && [ev_engine_running] > 0}", ["board-flip", "start_engine"] + RA,
     "gold_run board-flip; gold_call start_engine", multi=1)
item("engh-load-start", "engines", "Load Caruana's most recent game and start the engine.",
     "expr {[ev_player_in_game Caruana] && [ev_engine_running] > 0}", ["open_game", "start_engine"] + RA,
     "gold_call open_game {player Caruana}; gold_call start_engine", multi=1)

# --- play vs engine / training ---------------------------------------------
item("playh-engine", "play", "I'd like to play a game against the computer.", "ev_opened play|engine",
     ["menu.training.play_engine"] + RA, "gold_run menu.training.play_engine")
item("playh-tactics", "play", "Open the tactics trainer.", "ev_opened tactic",
     ["menu.training.tactics"] + RA, "gold_run menu.training.tactics")
item("playh-endgame", "play", "Let me practise some endgames.", "ev_opened endgame",
     ["menu.training.endgame"] + RA, "gold_run menu.training.endgame")
item("playh-repertoire", "play", "Train my opening repertoire.", "ev_opened repertoire",
     ["menu.training.repertoire"] + RA, "gold_run menu.training.repertoire")
item("playh-match", "play", "Set up a match between two engines.", "ev_opened match",
     ["menu.training.engine_match"] + RA, "gold_run menu.training.engine_match")
item("playh-corr", "play", "show my correspondence games", "ev_opened correspond",
     ["menu.tools.correspondence", "correspondence_games"] + RA, "gold_run menu.tools.correspondence", loose=1)

# --- players / ratings -----------------------------------------------------
item("playerh-card", "players", "Show the player card for Caruana.", "ev_opened card|Caruana",
     ["open_view", "menu.tools.player_card"] + RA, "gold_call open_view {kind player_card name Caruana}")
item("playerh-dict", "players", "Open the player dictionary.", "ev_opened dictionary|player",
     ["menu.tools.player_dictionary"] + RA, "gold_run menu.tools.player_dictionary")
item("playerh-me", "players", "My name is Michael Thomas, please remember that.",
     "expr {[string match -nocase *thomas* [ev_me]] && [string match -nocase *michael* [ev_me]]}",
     ["remember_me"] + RA, "gold_call remember_me {name {Thomas, Michael}}",
     setup="set ::application::ai::Settings(me) {}")
item("playerh-xiong", "players", "Show Xiong's games with White and open his player card.",
     "expr {[ev_filter_all White *Xiong*] && [ev_opened card|Xiong]}",
     ["search_games", "show_search", "open_view", "menu.tools.player_card"] + RA,
     FILTER % "player Xiong color white" + "; gold_call open_view {kind player_card name Xiong}", multi=1)
item("playerh-private", "players", "Let me edit my own private player card.",
     "ev_opened player", ["menu.edit.preferences.player"] + RA, "gold_run menu.edit.preferences.player")
item("playerh-brief", "players", "Open the opponent brief.", "ev_opened brief",
     ["menu.training.brief", "opponent_brief"] + RA, "gold_run menu.training.brief")
item("playerh-load-card", "players", "whos pakleza? load one of his games and show his card",
     "expr {[ev_player_in_game Pakleza] && [ev_opened card|Pakleza]}",
     ["open_game", "open_view", "search_games", "show_search", "menu.tools.player_card"] + RA,
     "gold_call open_game {player Pakleza}; gold_call open_view {kind player_card name Pakleza}", multi=1, loose=1)

# --- export / print --------------------------------------------------------
item("exph-pgn", "export", "Export the database as PGN.", "ev_opened export",
     ["export_database", "menu.file.export.pgn"] + RA, "gold_run menu.file.export.pgn")
item("exph-html", "export", "Make an HTML report of the database.", "ev_opened export|html",
     ["export_database", "menu.file.export.html"] + RA, "gold_run menu.file.export.html")
item("exph-filtered", "export", "Filter to Caruana's games and export just those.",
     "expr {[ev_filter_all Player *Caruana*] && [ev_opened export]}",
     ["search_games", "show_search", "export_database", "menu.file.export.pgn"] + RA,
     FILTER % "player Caruana" + "; gold_run menu.file.export.pgn", multi=1)
item("exph-archive", "export", "Create an archive of this database.", "ev_opened archive",
     ["menu.file.archive_create", "menu.file.export.archive"] + RA, "gold_run menu.file.archive_create")
item("exph-pgnopts", "export", "Open the PGN export options.", "ev_opened pgn|export|option",
     ["menu.edit.preferences.pgn"] + RA, "gold_run menu.edit.preferences.pgn")
item("exph-game", "export", "Load game 30 and export it.",
     "expr {[ev_gameno] == 30 && [ev_opened export]}", ["open_game", "game-export", "export_database"] + RA,
     "gold_call open_game {number 30}; gold_run game-export", multi=1)

# --- import / broadcast / media --------------------------------------------
SETN = "set ::EV(n) [ev_games_in @MAIN@]"
item("imph-pgn", "media", "Import @PGN@ into this database.",
     "expr {[ev_games_in @MAIN@] == $::EV(n) + 2}", ["import_games", "menu.file.import.pgn"] + RA,
     "gold_call import_games [list files [list @PGN@]]", setup=SETN)
item("imph-club", "media", "Open @CLUB@ and import @PGN@ into it.",
     "expr {[ev_db_is @CLUB@] && [ev_games_in @CLUB@] == $::EV(c) + 2}",
     ["open_database", "import_games", "menu.file.open", "menu.file.import.pgn"] + RA,
     "gold_call open_database [list path @CLUB@]; gold_call import_games [list files [list @PGN@]]",
     setup=OPEN_CLUB + "; set ::EV(c) [ev_games_in @CLUB@]; ::application::database::closeBase .application @CLUB@", multi=1)
item("imph-import-filter", "media", "Import @PGN@ and then show only the games from the Evaluation Import event.",
     "expr {[ev_games_in @MAIN@] == $::EV(n) + 2 && [ev_filter_all Event {Evaluation Import}]}",
     ["import_games", "search_games", "show_search"] + RA,
     "gold_call import_games [list files [list @PGN@]]; " + FILTER % "event {Evaluation Import}", setup=SETN, multi=1)
item("mediah-pane", "media", "Show the media pane.", "ev_pane_shown media",
     ["menu.view.panes.media", "pane"] + RA, "gold_run menu.view.panes.media", setup="ev_pane_hide media")
item("mediah-stream", "media", "I want to watch a live stream.", "ev_opened stream",
     ["open_stream"] + RA, "gold_call run_action {id open_stream}")
item("mediah-download", "media", "Download games from the internet.", "ev_opened download",
     ["menu.tools.download"] + RA, "gold_run menu.tools.download")
item("mediah-import-dlg", "media", "Open the import dialog.", "ev_opened import",
     ["menu.tools.import_games", "menu.file.import.pgn"] + RA, "gold_run menu.tools.import_games")

# --- layout / panes / settings ---------------------------------------------
item("layh-dbtab", "layout", "Show the database tab.", "expr {[ev_tab] eq {database}}",
     ["switch_tab"] + RA, "gold_call switch_tab {tab database}")
item("layh-board", "layout", "go back to the board", "expr {[ev_tab] eq {board}}",
     ["switch_tab"] + RA, "gold_call switch_tab {tab board}", setup="::application::switchTab database", loose=1)
item("layh-full", "layout", "Make the window fullscreen.", "ev_fullscreen",
     ["app-fullscreen"] + RA, "gold_run app-fullscreen")
item("layh-unfull", "layout", "Leave full screen mode.", "expr {![ev_fullscreen]}",
     ["app-fullscreen"] + RA, "gold_run app-fullscreen", setup="::menu::setFullscreen 1")
item("layh-font", "layout", "make the text bigger plz", "expr {[ev_fontsize] > $::EV(f)}",
     ["menu.view.font_inc"] + RA, "gold_run menu.view.font_inc", setup="set ::EV(f) [ev_fontsize]", loose=1)
item("layh-keys", "layout", "Open the keyboard shortcut settings.", "ev_opened key",
     ["menu.edit.keyboard"] + RA, "gold_run menu.edit.keyboard")
item("layh-maxboard", "layout", "Maximise the board.", "ev_zoomed board",
     ["pane", "c9.maximise"] + RA, "gold_call pane {action maximise pane board}")
item("layh-asstprefs", "layout", "Open the assistant preferences.", "ev_opened assist|prefer",
     ["app.preferences.assistant"] + RA, "gold_run app.preferences.assistant")
item("layh-tab-full", "layout", "Switch to the database tab and go full screen.",
     "expr {[ev_tab] eq {database} && [ev_fullscreen]}", ["switch_tab", "app-fullscreen"] + RA,
     "gold_call switch_tab {tab database}; gold_run app-fullscreen", multi=1)
item("layh-float-dock", "layout", "Dock the tree window back into the main window and maximise the board.",
     "expr {[ev_pane_shown tree] && ![ev_floating tree] && [ev_zoomed board]}", ["pane"] + RA,
     "gold_call pane {action dock pane tree}; gold_call pane {action maximise pane board}",
     setup="ev_pane_show tree; ::application::assistant::DoPane undock tree", multi=1)
item("layh-hide-tree", "layout", "hide teh tree pane", "expr {![ev_pane_shown tree]}",
     ["menu.view.panes.tree", "pane"] + RA, "gold_run menu.view.panes.tree", setup="ev_pane_show tree", loose=1)

with open(sys.argv[1], "w") as f:
    for d in I:
        f.write(json.dumps(d) + "\n")
areas = sorted(set(d["area"] for d in I))
print(len(I), "items;", sum(d.get("multi", 0) for d in I), "multi;", sum(d.get("loose", 0) for d in I), "loose;",
      {a: sum(1 for d in I if d["area"] == a) for a in areas})
