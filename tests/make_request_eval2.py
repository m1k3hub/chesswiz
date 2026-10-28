#!/usr/bin/env python3
# Generates the second held-out request corpus (VAL-KNOW-008), written on
# 2026-10-21 after the first held-out set (now a dev set) had its baseline
# runs and BEFORE any assistant fix; frozen and self-checked (gold/null)
# before any model sees it.  Usage: make_request_eval2.py OUT.jsonl
import json, sys
I = []
def item(id, area, request, predicate, actions, gold, setup=None, multi=0, loose=0):
    d = {"id": id, "area": area, "request": request, "predicate": predicate,
         "actions": actions, "gold": gold}
    if setup: d["setup"] = setup
    if multi: d["multi"] = 1
    if loose: d["loose"] = 1
    I.append(d)

RA = ["run_action", "find_capability"]
OPEN_CLUB = "::application::database::openBase .application @CLUB@ yes -encoding $::encoding::autoEncoding -switchToBase 1"
FILTER = "gold_call search_games {%s}; gold_call show_search"
FIRST = "gold_call open_game [list number [expr {[::scidb::db::get gameNumber [ev_db] Normal 0 0] + 1}]]"
S = ["search_games", "show_search"]

# --- databases ---------------------------------------------------------------
item("d2-open", "databases", "Open the database file @CLUB@.", "ev_db_is @CLUB@",
     ["open_database", "menu.file.open"] + RA, "gold_call open_database [list path @CLUB@]")
item("d2-switch", "databases", "switch to main db pls", "ev_db_is @MAIN@",
     ["open_database", "menu.file.open"] + RA, "gold_call open_database [list path @MAIN@]", setup=OPEN_CLUB, loose=1)
item("d2-close", "databases", "Close the active database.", "expr {![ev_open @CLUB@] && [ev_open @MAIN@]}",
     ["menu.file.close"] + RA, "gold_run menu.file.close", setup=OPEN_CLUB)
item("d2-props", "databases", "Open the properties of this database.", "ev_opened prop",
     ["menu.db.properties", "database_properties"] + RA, "gold_run menu.db.properties")
item("d2-readonly", "databases", "Protect this database against changes.", "::scidb::db::get readonly? @MAIN@",
     ["menu.db.readonly"] + RA, "gold_run menu.db.readonly")
item("d2-discover", "databases", "Search this computer for chess databases.", "ev_opened discover",
     ["discover_databases", "menu.db.discover"] + RA, "gold_call discover_databases")
item("d2-open-load", "databases", "Open @CLUB@ and put its game 7 on the board.",
     "expr {[ev_db_is @CLUB@] && [ev_gameno] == 7}", ["open_database", "open_game", "menu.file.open"] + RA,
     "gold_call open_database [list path @CLUB@]; gold_call open_game {number 7}", multi=1)
item("d2-open-tab", "databases", "Open @CLUB@ and show me its game list.",
     "expr {[ev_db_is @CLUB@] && [ev_tab] eq {database}}", ["open_database", "switch_tab", "menu.file.open"] + RA,
     "gold_call open_database [list path @CLUB@]; gold_call switch_tab {tab database}", multi=1)

# --- games -------------------------------------------------------------------
item("g2-load", "games", "Put game 250 on the board.", "expr {[ev_gameno] == 250}",
     ["open_game", "menu.game.load_number"] + RA, "gold_call open_game {number 250}")
item("g2-next", "games", "nxt game", "expr {[ev_gameno] == 11}", ["open_game", "game-next"] + RA,
     "gold_run game-next", loose=1)
item("g2-last", "games", "Go to the last game in the database.", "expr {[ev_gameno] == [ev_games_in @MAIN@]}",
     ["open_game", "game-last"] + RA, "gold_run game-last")
item("g2-new", "games", "New game, please.", "expr {[ev_moves] == 0 && [ev_tag White] in {{} ?}}",
     ["new_game", "game-new"] + RA, "gold_call new_game")
item("g2-truncate", "games", "cut off the rest of the game from here", "expr {[ev_gameno] == 10 && [ev_ply] == 12 && [ev_moves] == 12}",
     ["c2.strip.truncate"] + RA, "gold_run c2.strip.truncate", loose=1)
item("g2-recent", "games", "Load Tahmasebi's most recent game.", "expr {[ev_player_in_game Tahmasebi] && [ev_gameno] > 0}",
     ["open_game"] + S + RA, "gold_call open_game {player Tahmasebi}")
item("g2-filter-load", "games", "Find Cieslak's games and open the first one in the list.",
     "expr {[ev_player_in_game Cieslak] && [ev_gameno] > 0}", S + ["open_game"] + RA,
     FILTER % "player Cieslak" + "; " + FIRST, multi=1)
item("g2-load-start", "games", "Open game 75 and go to its starting position.", "expr {[ev_gameno] == 75 && [ev_ply] == 0}",
     ["open_game", "nav-start"] + RA, "gold_call open_game {number 75}; gold_run nav-start", multi=1)
item("g2-new-moves", "games", "Start a new game and enter 1.d4 d5 2.c4.",
     "expr {[ev_moves] == 3 && [lrange [ev_fen] 0 1] eq {rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b}}",
     ["new_game", "set_position", "game-new"] + RA, "gold_call new_game; gold_call set_position {moves {1.d4 d5 2.c4}}", multi=1)
item("g2-load-ply", "games", "Load game 40 and go to the position after Black's 5th move.", "expr {[ev_gameno] == 40 && [ev_ply] == 10}",
     ["open_game"] + RA, "gold_call open_game {number 40}; ::scidb::game::go key [lindex [::scidb::game::query mainline] 9 0]", multi=1)

# --- board -------------------------------------------------------------------
item("b2-moves", "board", "Show me the position after 1.e4 c6 2.d4 d5.",
     "expr {[lindex [ev_fen] 0] eq {rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR}}",
     ["set_position"] + RA, "gold_call set_position {moves {1.e4 c6 2.d4 d5}}")
item("b2-fen", "board", "Set up this FEN: 4k3/8/8/8/8/8/4P3/4K3 b - - 0 1",
     "expr {[lrange [ev_fen] 0 1] eq {4k3/8/8/8/8/8/4P3/4K3 b}}", ["set_position"] + RA,
     "gold_call set_position {fen {4k3/8/8/8/8/8/4P3/4K3 b - - 0 1}}")
item("b2-flip", "board", "Show the board from the other side.", "ev_flipped", ["board-flip"] + RA, "gold_run board-flip")
item("b2-fwd", "board", "Go forward one move.", "expr {[ev_gameno] == 10 && [ev_ply] == 13}", ["nav-forward"] + RA,
     "gold_run nav-forward")
item("b2-white10", "board", "Go to the position after White's 10th move.", "expr {[ev_gameno] == 10 && [ev_ply] == 19}", RA,
     "::scidb::game::go key [lindex [::scidb::game::query mainline] 18 0]")
item("b2-start", "board", "back 2 start", "expr {[ev_gameno] == 10 && [ev_ply] == 0}", ["nav-start"] + RA,
     "gold_run nav-start", loose=1)
item("b2-moves-flip", "board", "Set up 1.c4 e5 and flip the board.",
     "expr {[lindex [ev_fen] 0] eq {rnbqkbnr/pppp1ppp/8/4p3/2P5/8/PP1PPPPP/RNBQKBNR} && [ev_flipped]}",
     ["set_position", "board-flip"] + RA, "gold_call set_position {moves {1.c4 e5}}; gold_run board-flip", multi=1)
item("b2-end-flip", "board", "Jump to the end of the game and turn the board around.",
     "expr {[ev_gameno] == 10 && [ev_ply] == [ev_moves] && [ev_flipped]}", ["nav-end", "board-flip"] + RA,
     "gold_run nav-end; gold_run board-flip", multi=1)

# --- search ------------------------------------------------------------------
item("s2-player", "search", "Filter the game list to Tahmasebi.", "ev_filter_all Player *Tahmasebi*", S + RA,
     FILTER % "player Tahmasebi")
item("s2-eco", "search", "Show only the games with ECO D35.", "ev_filter_all ECO D35", S + RA, FILTER % "eco D35")
item("s2-event", "search", "Only the games from the Amager CA Centenary GM, please.", "ev_filter_all Event {Amager*GM}",
     S + RA, FILTER % "event {Amager CA Centenary GM}")
item("s2-white", "search", "Show Kazakouski's games with the white pieces.", "ev_filter_all White *Kazakouski*", S + RA,
     FILTER % "player Kazakouski color white")
item("s2-draws", "search", "Show Movahed's draws.", "expr {[ev_filter_all Player *Movahed*] && [ev_filter_all Result 1/2-1/2]}",
     S + RA, FILTER % "player Movahed result draw")
item("s2-clear", "search", "unfilter the list", "expr {[ev_search_count] == [ev_total_games]}", ["clear_search"] + RA,
     "gold_call clear_search", setup=FILTER % "player Terry", loose=1)
item("s2-rating", "search", "Open the rating search.", "ev_opened rating", ["open_search", "menu.db.search.rating"] + RA,
     "gold_run menu.db.search.rating")
item("s2-tab", "search", "Show Bulgak's games and switch to the database tab.",
     "expr {[ev_filter_all Player *Bulgak*] && [ev_tab] eq {database}}", S + ["switch_tab"] + RA,
     FILTER % "player Bulgak" + "; gold_call switch_tab {tab database}", multi=1)
item("s2-filter-load", "search", "List the games from the 36th TCh-SLO 2026 and load the first one.",
     "expr {[ev_filter_all Event {36th TCh-SLO*}] && [string match {36th TCh-SLO*} [ev_tag Event]] && [ev_gameno] > 0}",
     S + ["open_game"] + RA, FILTER % "event {36th TCh-SLO 2026}" + "; " + FIRST, multi=1)

# --- trees -------------------------------------------------------------------
item("t2-tree", "trees", "Open the tree pane.", "ev_pane_shown tree", ["menu.view.panes.tree", "pane"] + RA,
     "gold_run menu.view.panes.tree", setup="ev_pane_hide tree")
item("t2-explorer", "trees", "opening explorer pls", "ev_pane_shown explorer",
     ["menu.view.panes.explorer", "menu.analysis.explorer", "pane"] + RA, "gold_run menu.view.panes.explorer",
     setup="ev_pane_hide explorer", loose=1)
item("t2-hide-explorer", "trees", "Close the opening explorer pane.", "expr {![ev_pane_shown explorer]}",
     ["menu.view.panes.explorer", "pane"] + RA, "gold_run menu.view.panes.explorer", setup="ev_pane_show explorer")
item("t2-float-explorer", "trees", "Undock the opening explorer into its own window.", "ev_floating explorer",
     ["pane"] + RA, "gold_call pane {action undock pane explorer}", setup="ev_pane_show explorer")
item("t2-report", "trees", "Open the opening report.", "ev_opened report|opening",
     ["open_view", "menu.db.reports.opening"] + RA, "gold_run menu.db.reports.opening")
item("t2-prep", "trees", "Open the opening preparation statistics of this database.", "ev_opened {eco|opening prep}",
     ["open_view", "menu.db.reports.eco"] + RA, "gold_run menu.db.reports.eco")
item("t2-moves-explorer", "trees", "Play 1.d4 Nf6 2.c4 g6 on the board and open the explorer.",
     "expr {[lindex [ev_fen] 0] eq {rnbqkb1r/pppppp1p/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR} && [ev_pane_shown explorer]}",
     ["set_position", "menu.view.panes.explorer", "pane"] + RA,
     "gold_call set_position {moves {1.d4 Nf6 2.c4 g6}}; gold_run menu.view.panes.explorer",
     setup="ev_pane_hide explorer", multi=1)

# --- engines -----------------------------------------------------------------
item("e2-start", "engines", "Start the engine.", "expr {[ev_engine_running] > 0}",
     ["start_engine", "menu.analysis.engine_toggle"] + RA, "gold_call start_engine")
item("e2-stop", "engines", "stop teh engine", "expr {[ev_engine_running] == 0}",
     ["stop_engine", "menu.analysis.engine_toggle"] + RA, "gold_call stop_engine",
     setup="::application::assistant::RunTool start_engine {}", loose=1)
item("e2-lines", "engines", "Run the engine with five lines.", "expr {[ev_engine_running] > 0 && [ev_engine_lines] == 5}",
     ["start_engine"] + RA, "gold_call start_engine {lines 5}")
item("e2-console", "engines", "Show me the engine console.", "ev_opened console",
     ["menu.tools.engine_console"] + RA, "gold_run menu.tools.engine_console")
item("e2-admin", "engines", "Manage my chess engines.", "ev_opened engine",
     ["menu.analysis.engines", "menu.edit.preferences.engines", "list_engines"] + RA, "gold_run menu.analysis.engines")
item("e2-float", "engines", "Undock the analysis pane.", "ev_floating analysis", ["pane"] + RA,
     "gold_call pane {action undock pane analysis}")
item("e2-load-start", "engines", "Open game 33 and let the engine analyse it.",
     "expr {[ev_gameno] == 33 && [ev_engine_running] > 0}", ["open_game", "start_engine"] + RA,
     "gold_call open_game {number 33}; gold_call start_engine", multi=1)
item("e2-fen-start", "engines", "Set up 8/8/8/8/8/5k2/8/4K2R w K - 0 1 and start an engine on it.",
     "expr {[lrange [ev_fen] 0 1] eq {8/8/8/8/8/5k2/8/4K2R w} && [ev_engine_running] > 0}",
     ["set_position", "start_engine"] + RA,
     "gold_call set_position {fen {8/8/8/8/8/5k2/8/4K2R w K - 0 1}}; gold_call start_engine", multi=1)

# --- play / training ---------------------------------------------------------
item("p2-engine", "play", "Play a game against Stockfish.", "ev_opened play|engine",
     ["menu.training.play_engine"] + RA, "gold_run menu.training.play_engine")
item("p2-tactics", "play", "i wanna do some tactics puzzles", "ev_opened tactic", ["menu.training.tactics"] + RA,
     "gold_run menu.training.tactics", loose=1)
item("p2-endgame", "play", "Open the endgame trainer.", "ev_opened endgame", ["menu.training.endgame"] + RA,
     "gold_run menu.training.endgame")
item("p2-match", "play", "Run a match between engines.", "ev_opened match", ["menu.training.engine_match"] + RA,
     "gold_run menu.training.engine_match")
item("p2-repertoire", "play", "Open the repertoire trainer.", "ev_opened repertoire", ["menu.training.repertoire"] + RA,
     "gold_run menu.training.repertoire")
item("p2-corr", "play", "Open the correspondence games dialog.", "ev_opened correspond",
     ["menu.tools.correspondence", "correspondence_games"] + RA, "gold_run menu.tools.correspondence")

# --- players -----------------------------------------------------------------
item("pl2-card", "players", "Open Tahmasebi's player card.", "ev_opened card|Tahmasebi",
     ["open_view", "menu.tools.player_card"] + RA, "gold_call open_view {kind player_card name Tahmasebi}")
item("pl2-dict", "players", "Show the player dictionary.", "ev_opened dictionary|player",
     ["menu.tools.player_dictionary"] + RA, "gold_run menu.tools.player_dictionary")
item("pl2-me", "players", "Remember that my name is Anna Schmidt.",
     "expr {[string match -nocase *schmidt* [ev_me]] && [string match -nocase *anna* [ev_me]]}",
     ["remember_me"] + RA, "gold_call remember_me {name {Schmidt, Anna}}", setup="set ::application::ai::Settings(me) {}")
item("pl2-private", "players", "Open my private player card settings.", "ev_opened player",
     ["menu.edit.preferences.player"] + RA, "gold_run menu.edit.preferences.player")
item("pl2-brief", "players", "Open the opponent brief tool.", "ev_opened brief",
     ["menu.training.brief", "opponent_brief"] + RA, "gold_run menu.training.brief")
item("pl2-filter-card", "players", "Show Donchenko's games and her player card.",
     "expr {[ev_filter_all Player *Donchenko*] && [ev_opened card|Donchenko]}",
     S + ["open_view", "menu.tools.player_card"] + RA,
     FILTER % "player Donchenko" + "; gold_call open_view {kind player_card name Donchenko}", multi=1)
item("pl2-load-card", "players", "load a bouska game n show his card",
     "expr {[ev_player_in_game Bouska] && [ev_opened card|Bouska]}",
     ["open_game", "open_view", "menu.tools.player_card"] + S + RA,
     "gold_call open_game {player Bouska}; gold_call open_view {kind player_card name Bouska}", multi=1, loose=1)

# --- export ------------------------------------------------------------------
item("x2-pgn", "export", "save db as pgn", "ev_opened export", ["export_database", "menu.file.export.pgn"] + RA,
     "gold_run menu.file.export.pgn", loose=1)
item("x2-html", "export", "Export the games as an HTML report.", "ev_opened export|html",
     ["export_database", "menu.file.export.html"] + RA, "gold_run menu.file.export.html")
item("x2-archive", "export", "Make a portable archive of this database.", "ev_opened archive",
     ["menu.file.archive_create", "menu.file.export.archive"] + RA, "gold_run menu.file.archive_create")
item("x2-pgnopts", "export", "Change the PGN export options.", "ev_opened pgn|export|option",
     ["menu.edit.preferences.pgn"] + RA, "gold_run menu.edit.preferences.pgn")
item("x2-filter-export", "export", "Show Sheehan's games and export them.",
     "expr {[ev_filter_all Player *Sheehan*] && [ev_opened export]}", S + ["export_database", "menu.file.export.pgn"] + RA,
     FILTER % "player Sheehan" + "; gold_run menu.file.export.pgn", multi=1)
item("x2-load-export", "export", "Load game 64 and export that game.", "expr {[ev_gameno] == 64 && [ev_opened export]}",
     ["open_game", "game-export", "export_database"] + RA, "gold_call open_game {number 64}; gold_run game-export", multi=1)

# --- import / media ----------------------------------------------------------
SETN = "set ::EV(n) [ev_games_in @MAIN@]"
item("m2-import", "media", "Add the games from @PGN@ to this database.", "expr {[ev_games_in @MAIN@] == $::EV(n) + 2}",
     ["import_games", "menu.file.import.pgn"] + RA, "gold_call import_games [list files [list @PGN@]]", setup=SETN)
item("m2-import-club", "media", "Import @PGN@ into the database @CLUB@.",
     "expr {[ev_games_in @CLUB@] == $::EV(c) + 2}",
     ["open_database", "import_games", "menu.file.open", "menu.file.import.pgn"] + RA,
     "gold_call open_database [list path @CLUB@]; gold_call import_games [list files [list @PGN@]]",
     setup=OPEN_CLUB + "; set ::EV(c) [ev_games_in @CLUB@]; ::application::database::closeBase .application @CLUB@", multi=1)
item("m2-media", "media", "Open the media pane.", "ev_pane_shown media", ["menu.view.panes.media", "pane"] + RA,
     "gold_run menu.view.panes.media", setup="ev_pane_hide media")
item("m2-hide-media", "media", "hide the media pane", "expr {![ev_pane_shown media]}", ["menu.view.panes.media", "pane"] + RA,
     "gold_run menu.view.panes.media", setup="ev_pane_show media", loose=1)
item("m2-stream", "media", "Open a live broadcast stream.", "ev_opened stream", ["open_stream"] + RA,
     "gold_call run_action {id open_stream}")
item("m2-download", "media", "Get games from the internet.", "ev_opened download", ["menu.tools.download"] + RA,
     "gold_run menu.tools.download")
item("m2-importdlg", "media", "Open the game import window.", "ev_opened import",
     ["menu.tools.import_games", "menu.file.import.pgn"] + RA, "gold_run menu.tools.import_games")

# --- layout / settings -------------------------------------------------------
item("l2-dbtab", "layout", "Show me the database view.", "expr {[ev_tab] eq {database}}", ["switch_tab"] + RA,
     "gold_call switch_tab {tab database}")
item("l2-board", "layout", "Show the board tab.", "expr {[ev_tab] eq {board}}", ["switch_tab"] + RA,
     "gold_call switch_tab {tab board}", setup="::application::switchTab database")
item("l2-full", "layout", "Fullscreen, please.", "ev_fullscreen", ["app-fullscreen"] + RA, "gold_run app-fullscreen")
item("l2-unfull", "layout", "exit fullscreen", "expr {![ev_fullscreen]}", ["app-fullscreen"] + RA,
     "gold_run app-fullscreen", setup="::menu::setFullscreen 1", loose=1)
item("l2-font", "layout", "biger font", "expr {[ev_fontsize] > $::EV(f)}", ["menu.view.font_inc"] + RA,
     "gold_run menu.view.font_inc", setup="set ::EV(f) [ev_fontsize]", loose=1)
item("l2-fontdec", "layout", "Make the text smaller.", "expr {[ev_fontsize] < $::EV(f)}", ["menu.view.font_dec"] + RA,
     "gold_run menu.view.font_dec", setup="::font::changeFontSize +1; update; set ::EV(f) [ev_fontsize]")
item("l2-keys", "layout", "Open the keyboard preferences.", "ev_opened key", ["menu.edit.keyboard"] + RA,
     "gold_run menu.edit.keyboard")
item("l2-max", "layout", "Make the board pane fill the whole window.", "ev_zoomed board", ["pane"] + RA,
     "gold_call pane {action maximise pane board}")
item("l2-restore", "layout", "Restore the normal layout.", "expr {![ev_zoomed board]}", ["pane"] + RA,
     "gold_call pane {action restore pane board}", setup="::application::assistant::RunTool pane {action maximise pane board}")
item("l2-float-max", "layout", "Undock the tree and maximise the board.", "expr {[ev_floating tree] && [ev_zoomed board]}",
     ["pane", "menu.view.panes.tree"] + RA,
     "gold_call pane {action undock pane tree}; gold_call pane {action maximise pane board}", setup="ev_pane_show tree", multi=1)
item("l2-tab-clear", "layout", "Switch to the database tab and clear the filter.",
     "expr {[ev_tab] eq {database} && [ev_search_count] == [ev_total_games]}", ["switch_tab", "clear_search"] + RA,
     "gold_call switch_tab {tab database}; gold_call clear_search", setup=FILTER % "player Ashraf", multi=1)

with open(sys.argv[1], "w") as f:
    for d in I:
        f.write(json.dumps(d) + "\n")
areas = sorted(set(d["area"] for d in I))
print(len(I), "items;", sum(d.get("multi", 0) for d in I), "multi;", sum(d.get("loose", 0) for d in I), "loose;",
      {a: sum(1 for d in I if d["area"] == a) for a in areas})
