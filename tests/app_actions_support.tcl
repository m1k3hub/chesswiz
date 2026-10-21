# Shared fixtures for the assistant reachability and real-UI tests.
namespace eval ::scidb::test::actions {
    variable Dir [file join [file dirname [file normalize [info script]]] tmp-app actions_[pid]]
    # The engine writes only capturable en-passant squares; after 1.e4 it is "-".
    variable Fen {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1}

    proc engineProgram {} {
        if {[info exists ::env(SCIDB_TEST_ENGINE)]} {return $::env(SCIDB_TEST_ENGINE)}
        # Aqua bundles ship the engine with Resources, not /usr/games.
        if {[tk windowingsystem] eq "aqua"} {
            set program [file join $::scidb::dir::share engines stockfish-chesswiz]
            if {[file executable $program]} {return $program}
        }
        return /usr/games/stockfish
    }

    proc ready {} {
        # application::open is called by the bundle, but TwmReady/Startup2
        # run from the event queue. Tests must wait for the actual widgets.
        set deadline [expr {[clock milliseconds] + 10000}]
        while {!$::application::Vars(ready)} {
            update
            if {[clock milliseconds] > $deadline} { error "main window did not finish startup" }
            after 10
        }
        after 10
        update
        catch {destroy .tipoftheday}
        ::application::switchTab board
        # Each real-action probe owns one process: clear the previous
        # search's positions so a probe cannot inherit another's result.
        catch { set ::application::assistant::LastFind {} }
        catch { set ::application::assistant::LastPositions {} }
        update
        if {![winfo viewable .application.nb.board]} { error "main board is not mapped" }
        if {![winfo exists $::application::board::board]} { error "board was not built" }
    }

    proc fixture {} {
        variable Dir
        file mkdir $Dir
        set path [file join $Dir generated.pgn]
        if {[file exists $path]} { return $path }
        set ch [open $path w]
        puts $ch {[Event "Generated test"]
[Site "Test"]
[Date "2026.01.01"]
[Round "1"]
[White "Generated White"]
[Black "Generated Black"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 *}
        close $ch
        return $path
    }

    # Only metadata: no process is started by the handler reachability tests.
    proc stubEngine {} {
        set ::engine::Engines [list [dict merge $::engine::EmptyEngine {
            Name {Generated Engine} Protocol UCI Features:UCI {analyze true}
            Profiles:UCI {Default {{Skill spin 1 1 0 20}}}
        }]]
    }

    proc sampleArgs {name} {
        variable Fen
        set path [fixture]
        package require json
        set schema [::json::json2dict [dict get [::action::get $name] schema]]
        set result {}
        if {[dict exists $schema required]} {
            foreach key [dict get $schema required] {
                set prop [dict get $schema properties $key]
                if {[dict exists $prop enum]} {
                    set value [lindex [dict get $prop enum] 0]
                } else {
                    switch [dict get $prop type] {
                        integer - number { set value 1 }
                        boolean { set value 0 }
                        array { set value {Generated} }
                        default { set value Generated }
                    }
                }
                dict set result $key $value
            }
        }
        # Real, valid arguments, including cross-field constraints. Do not fill
        # optional properties with arbitrary strings: omitted means default.
        switch $name {
            pane { set result {action dock pane board} }
            open_database - transcribe_media { set result [list path $path] }
            import_games { set result [list files [list $path]] }
            add_engine { set result [list path [info nameofexecutable]] }
            search_games { set result {player {Generated White}} }
            set_position { set result [list fen $Fen] }
            open_game { set result {number 1 move 1 after white} }
            opening_score { set result {eco A00} }
            open_view { set result {kind player_card name {Generated White}} }
            find_positions { set result {request {initial position} cql {cql() initial}} }
            engine_options - remove_engine { set result {engine {Generated Engine}} }
            start_engine { set result {engine {Generated Engine}} }
            set_engine_option { set result {engine {Generated Engine} option Skill value 1} }
            handoff_issue {
                set issue [::application::triage::Dir issues 00000001.md]
                file mkdir [file dirname $issue]
                set ch [open $issue w]
                puts $ch {# Generated test issue}
                close $ch
                set result {issue 00000001}
            }
            novelty_label { set result [list fen $Fen san e5] }
            engine_check_move { set result {move e4} }
            run_job { set result {job prepare name {Generated White}} }
            annotate_game { set result {prose false depth 4 max_plies 1} }
            opponent_brief { set result {name {Generated White} prose false download 0} }
            diagnose_import { set result {codes {InvalidMove}} }
        }
        return $result
    }

    # Exact unavailable-state contracts, tested in a fresh application.
    # These are assertions about real product replies, not skipped handlers.
    variable RealGates {
        repertoire_check {error: no repertoire is open: open a database of type Openings, Openings White or Openings Black}
        add_to_repertoire {error: no writable repertoire database is open. Open one, or mark a database as one: Database tab > right-click it > Maintenance > Mark As > Openings}
        find_positions {error: call cql_help first and write the script from its reference and examples; then call find_positions again}
        save_pattern {error: there is no position search to save; call find_positions first}
        save_working_set {error: the game list shows no games}
        tablebase {error: the tablebases cover at most 7 pieces; this position has 32}
        stop_engine {error: no engine is running}
    }

    # Product preconditions for isolated probes: only generated games and a
    # real UCI executable. Do not replace any action or UI callback here.
    proc prepareReal {name argv} {
        if {$name in {similar_games player_stats prepare_against search_games open_view open_game
                      opponent_brief study_plan structure_profile event_types training_set run_job
                      explain_game_result annotate_game clear_search show_search open_position}} {
            set base [fixture]
            ::application::assistant::runTool open_database [list path $base]
            ::application::assistant::runTool open_game {number 1}
            foreach key {name player} {
                if {[dict exists $argv $key] && [dict get $argv $key] eq "Generated"} {
                    dict set argv $key {Generated White}
                }
            }
        }
        if {$name in {engine_options start_engine set_engine_option remove_engine add_engine}} {
            set program [engineProgram]
            if {![file executable $program]} { error "real UCI engine unavailable: $program" }
            if {$name eq "add_engine"} { return [list path $program] }
            set reply [::application::assistant::runTool add_engine [list path $program]]
            if {[string match "error:*" $reply]} { error $reply }
            # install may return an existing entry when the executable was
            # already known; select by its command, rather than list order.
            set installed {}
            foreach entry $::engine::Engines {
                if {[dict get $entry Command] eq [file normalize $program]} {
                    set installed [dict get $entry Name]
                    break
                }
            }
            if {$installed eq ""} { error "installed engine not found" }
            dict set argv engine $installed
            if {$name eq "set_engine_option"} {
                lassign [::engine::profileOptions $installed] protocol kind offered
                if {$kind ne "options" || ![llength $offered]} { error "engine has no editable options" }
                lassign [lindex $offered 0] option type value
                set argv [dict replace $argv option $option value $value]
            }
            if {$name eq "start_engine"} { set argv [dict merge $argv {lines 1 threads 1 hash 16}] }
        }
        if {$name eq "clear_search"} {
            ::application::assistant::runTool search_games {player {Generated White} color black}
            ::application::assistant::runTool show_search {}
            if {[::scidb::view::count games [fixture] Normal 0] != 0} { error "search fixture did not restrict the view" }
        }
        if {$name eq "show_search"} {
            ::application::assistant::runTool search_games {player {Generated White}}
            ::application::switchTab board
        }
        if {$name eq "open_position"} {
            ::application::assistant::runTool cql_help {}
            ::application::assistant::runTool find_positions {request {initial position} cql {cql() initial}}
            waitUntil {[llength $::application::assistant::LastPositions] > 0}
            ::scidb::game::go end
        }
        if {$name eq "annotate_game"} {
            # Include routine engine verdicts so this generated line must get
            # a comment. Classification and writing still use the real engine.
            set ::ai::annotate::Settings(classes) {Best Excellent Good Inaccuracy Mistake Blunder}
            ::scidb::game::modified [::scidb::game::current] false
        }
        if {$name eq "import_games"} {
            variable ImportBase [::scidb::db::get name]
            variable ImportBefore [::scidb::db::count games $ImportBase Normal]
        }
        if {$name in {explain_position opponent_brief study_plan}} {
            ::application::ai::showReport .application {Before action} {<p>Before action</p>}
        }
        if {$name eq "study_plan"} { return {} }
        if {$name eq "correspondence_games"} { return {action open} }
        return $argv
    }

    proc yes {args} { return 1 }

    # Network actions must not make the suite depend on the internet. The
    # handler path (confirmation, token, completion) is still exercised; the
    # transport fails immediately, exactly as it does offline.
    proc stubDownload {} {
        if {[llength [info commands ::scidb::test::actions::realDownloadGet]] == 0} {
            rename ::application::download::Get ::scidb::test::actions::realDownloadGet
        }
        proc ::application::download::Get {url done} {
            after 0 [list {*}$done [list ok 0 error {network disabled by the test suite} code 0]]
        }
    }
    proc unstubDownload {} {
        if {[llength [info commands ::scidb::test::actions::realDownloadGet]]} {
            catch { rename ::application::download::Get {} }
            rename ::scidb::test::actions::realDownloadGet ::application::download::Get
        }
    }
    proc boardMatches {fen} {
        set expected [::scidb::board::fenToBoard [lindex $fen 0]]
        expr {[::scidb::pos::fen] eq $fen &&
              [::board::diagram::data $::application::board::board] eq $expected}
    }
    proc waitUntil {condition {ms 10000}} {
        set deadline [expr {[clock milliseconds] + $ms}]
        while {![uplevel 1 [list expr $condition]]} {
            if {[clock milliseconds] >= $deadline} { error "timed out waiting for $condition" }
            set ::scidb::test::actions::tick 0
            after 20 {set ::scidb::test::actions::tick 1}
            vwait ::scidb::test::actions::tick
        }
    }
}

# Oracles run after the real handler, including event-queue work where the
# action is asynchronous. Never infer mutation from a successful reply.
proc ::scidb::test::actions::assertReal {name} {
    update
    switch $name {
        clear_search {
            set base [fixture]
            if {[::scidb::view::count games $base Normal 0] != [::scidb::db::count games $base Normal]} { error "clear_search left a restricted view" }
        }
        show_search {
            if {[.application.nb select] ne ".application.nb.database" || ![winfo viewable .application.nb.database]} { error "search results tab is not visible" }
            if {[::scidb::view::count games [fixture] Normal 0] != 1} { error "wrong search result count" }
        }
        open_position {
            if {![boardMatches $::ai::setup::Start]} { error "matched initial position was not loaded" }
            if {[llength [::scidb::game::query mainline]] != 4} { error "wrong game opened" }
        }
        annotate_game {
            waitUntil {![::ai::annotate::running?]} 20000
            if {![::scidb::game::query modified?] || $::ai::annotate::Priv(written) < 1} { error "annotation wrote no comment" }
        }
        import_games {
            variable ImportBase
            variable ImportBefore
            waitUntil {[::scidb::db::count games $ImportBase Normal] > $ImportBefore}
        }
        explain_position - opponent_brief - study_plan {
            set expected [dict get {
                explain_position {AI assessment*}
                opponent_brief {AI: opponent brief}
                study_plan {AI: study plan}
            } $name]
            waitUntil {[string match $expected $::application::report::Priv(title)]}
            set pane $::application::report::Priv(window)
            if {![winfo viewable $pane] || [dict get $::application::report::Priv(data) html] eq ""} { error "report pane has no visible content" }
        }
    }
    return 1
}

proc ::scidb::test::actions::cleanup {} {
    variable Dir
    # The caller closes generated databases before deleting their files.
    foreach pos [::game::usedPositions?] {
        ::application::pgn::release $pos
        ::game::release $pos
    }
    if {[file exists [file join $Dir generated.pgn]] && [::scidb::db::get open? [file join $Dir generated.pgn]]} {
        ::application::database::closeBase .application [file join $Dir generated.pgn]
    }
    file delete -force $Dir
}
