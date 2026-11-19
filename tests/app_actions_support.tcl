# Shared fixtures for the assistant reachability and real-UI tests.
namespace eval ::scidb::test::actions {
    variable Dir [file join [file dirname [file normalize [info script]]] tmp-app actions_[pid]]
    # The engine writes only capturable en-passant squares; after 1.e4 it is "-".
    variable Fen {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1}
    # The user's engine list at process start. A probe installs its own
    # fixture engine and deletes the program with its scratch directory;
    # release puts the real list (and its options file) back after every
    # file, so no later dialog or menu sees a broken or empty list.
    variable StartupEngines {}
    catch { set StartupEngines $::engine::Engines }

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
        resetDatabasePage
        ::application::switchTab board
        ensureBoardPane
        # Each real-action probe owns one process: clear the previous
        # search's positions so a probe cannot inherit another's result.
        catch { set ::application::assistant::LastFind {} }
        catch { set ::application::assistant::LastPositions {} }
        update
        # Deferred startup data maps the window before every tab has finished
        # its first geometry pass. Wait for the board to become viewable
        # instead of sampling one instant; still fail if it never maps.
        set mapDeadline [expr {[clock milliseconds] + 2000}]
        while {![winfo viewable .application.nb.board] && [clock milliseconds] <= $mapDeadline} {
            after 10
            update
        }
        if {![winfo viewable .application.nb.board]} { error "main board is not mapped" }
        if {![winfo exists $::application::board::board]} { error "board was not built" }
        normalizeMultiwindow [::application::twm board]
    }

    proc ensureBoardPane {} {
        catch {set twm [::application::twm board]} twm
        if {![info exists twm] || [catch {$twm leaf board} leaf]} {return}
        if {[catch {$twm ispane $leaf} isPane]} {return}
        if {$isPane} {return}
        set layout [::application::twm::inspectLayout $twm]
        catch {::application::twm::ChangeState $twm board}
        update
        catch {$twm load [::application::reflow::substTpl $::application::BoardLayout]}
        update
        catch {$twm load $layout}
        update
    }

    # The database module keeps one page per object kind. A caller probe
    # that opens an event/site/player page leaves that page selected, so a
    # later file finds the games table unmapped. Return to the games page.
    proc resetDatabasePage {} {
        if {![info exists ::application::database::Vars(contents)]} {return}
        set contents $::application::database::Vars(contents)
        if {![winfo exists $contents]} {return}
        catch {
            if {[$contents select] ne "$contents.games"} {
                $contents select $contents.games
            }
        }
        update
    }

    # A multiwindow keeps the sizes of its hidden page frames from whatever
    # tab was live before. Menu files share one process, so a save after an
    # earlier file's tab switch would record those stale widths and no longer
    # match the arrangement the load path produces. Align every page with the
    # visible multiwindow so save/load round-trips in a shared process.
    proc normalizeMultiwindow {twm} {
        if {[catch {$twm leaves} leaves]} { return }
        set groups [dict create]
        foreach uid $leaves {
            if {[catch {$twm leaf $uid} frame]} continue
            if {[catch {$twm parent $frame} parent]} continue
            if {[catch {$twm ismultiwindow $parent} is] || !$is} continue
            dict lappend groups $parent $frame
        }
        dict for {parent frames} $groups {
            # The visible page already has the multiwindow's real size; hidden
            # pages keep whatever size they had when the tab was switched.
            set canonical {}
            foreach frame $frames {
                if {[winfo ismapped $frame]} { set canonical $frame; break }
            }
            if {$canonical eq {}} {
                set best -1
                foreach frame $frames {
                    if {[catch {$twm dimension $frame} cdim]} continue
                    lassign $cdim cw ch
                    if {$cw > $best} { set best $cw; set canonical $frame }
                }
            }
            if {$canonical eq {}} continue
            if {[catch {$twm dimension $canonical} dim]} continue
            lassign $dim w h
            foreach frame $frames {
                if {$frame eq $canonical} continue
                if {[catch {$twm dimension $frame} cdim]} continue
                lassign $cdim cw ch
                if {$cw != $w || $ch != $h} {
                    catch {$twm resize $frame $w $h}
                }
            }
        }
        update
    }

    proc fixtureText {} {
        return {[Event "Generated test"]
[Site "Test"]
[Date "2026.01.01"]
[Round "1"]
[White "Generated White"]
[Black "Generated Black"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 *}
    }

    proc fixture {} {
        variable Dir
        file mkdir $Dir
        set path [file join $Dir generated.pgn]
        if {[file exists $path]} { return $path }
        resetFixture
        return $path
    }

    # Some probes append a game to the shared fixture. That is part of their
    # scenario, but menu files share one process: put the canonical single
    # game back when the file is done, or the next file's count is wrong.
    proc resetFixture {} {
        variable Dir
        file mkdir $Dir
        set path [file join $Dir generated.pgn]
        set ch [open $path w]
        puts -nonewline $ch [fixtureText]
        close $ch
    }

    # Restore the process-wide state a real-action probe can change: close
    # the databases it opened and release the game tabs it loaded. Menu test
    # files run in one process, so a file that leaves either behind changes
    # the fixture every later file sees.
    proc release {} {
        # A handler whose id is a child of a context cascade posts a real
        # choices menu and keeps a server-wide grab until someone dismisses
        # it. Nothing can click it in a headless run, so it would outlive the
        # file and block every later file and every child process that shares
        # this display. Destroy the menus a probe posted.
        catch {
            foreach menu [winfo children .] {
                if {![string match .contextChoices_* $menu]} { continue }
                catch { grab release $menu }
                catch { ::tk::MenuUnpost $menu }
                catch { destroy $menu }
            }
            set held [grab current]
            if {$held ne {} && [string match .contextChoices_* $held]} { grab release $held }
        }
        # The app floats Chesswiz Online, a stream window, the tournament
        # director and every undocked pane outside the main window. A file
        # which opened one leaves it mapped, and the next file's "a fresh
        # start shows only the main window" check then sees it, along with the
        # stale tabs and streams it was showing. Withdraw them here; the
        # module that owns one deiconifies its own window when it opens it
        # again.
        catch {
            foreach top [::application::FloatingWindows] {
                catch { wm withdraw $top }
            }
        }
        # An action which fails on purpose (a refused export, a bad file) logs
        # its reason and the log is a real toplevel: left mapped it covers the
        # next file's board and makes its clicks land on the log instead.
        catch { wm withdraw .application.log }
        # A playing dialog left open is a mapped window over the next file's
        # board, and once registered beside it, an input to the dialog
        # planner and to the inset's protected-board check: the next file
        # then plans against a dialog the product would not have. Destroy
        # them; the module which owns one reopens it on demand, exactly as
        # after a fresh start.
        catch {
            foreach dlg $::util::place::BesideDialogs {
                if {[winfo exists $dlg]} { catch { destroy $dlg } }
            }
        }
        # The discovery dialog is a real child of the main window, not a
        # floating top-level, so a file which opens it and only cleans up
        # top-levels leaves it mapped over the board and every later dialog.
        catch {
            if {[winfo exists .application.__discover__]} {
                if {[llength [info commands ::application::database::discover::Close]]} {
                    ::application::database::discover::Close
                } else {
                    destroy .application.__discover__
                }
            }
        }
        # A probe may leave a real engine piping into a pane it closes. Power
        # those down first; otherwise closing the database waits on a reply
        # that will never come.
        catch {
            foreach number [array names ::application::analysis::NumberToTree] {
                if {[::engine::active? $number]} {::engine::kill $number}
            }
        }
        # Killing an engine does not cancel an "is ready" idle callback that
        # was already scheduled. Drain those now, while this file's games are
        # still present: if one runs during the next file's engine start it
        # raises a precondition error inside the native activate command and
        # leaves a stale after# timer id as that command's result.
        catch { update }
        # Trial mode is per game. A probe which entered it and then opened a
        # new game leaves the original game in trial mode while the current
        # one is not; the game in trial mode then cannot be released and the
        # slot leaks into every later file. End it on the slot which owns it.
        foreach position {0 1 2 3 4 5 6 7 8 9} {
            catch {
                if {[::scidb::game::query $position open?]
                 && [::scidb::game::query $position trial]} {
                    set current [::scidb::game::current]
                    ::scidb::game::switch $position
                    if {[::scidb::game::current] == $position} {
                        ::game::flipTrialMode
                    }
                    if {$current != $position && [::scidb::game::query $current open?]} {
                        ::scidb::game::switch $current
                    }
                }
            }
        }
        if {[info exists ::application::database::Vars(switcher)]} {
            set bases [$::application::database::Vars(switcher) bases]
        } else {
            set bases {}
        }
        if {[llength $bases]} {
            set savedReleaseQuestion $::game::Options(askAgain:releaseAll)
            set savedReleaseAnswer $::game::Options(answer:releaseAll)
            set savedCloseQuestion $::game::Options(askAgain:closeAnyway)
            set savedCloseAnswer $::game::Options(answer:closeAnyway)
            set ::game::Options(askAgain:releaseAll) 0
            set ::game::Options(answer:releaseAll) 1
            set ::game::Options(askAgain:closeAnyway) 0
            set ::game::Options(answer:closeAnyway) 1
            # closeBase asks before discarding a modified game or an unsaved
            # PGN. Nobody can click that modal in a headless run, so answer
            # "yes" for the duration of the close only, then restore the real
            # dialog. The forcing above does not suppress the question: the
            # Options only record the checked checkbox and its last answer.
            set savedQuestion ::scidb::test::actions::savedQuestion
            set haveQuestion [expr {[llength [info commands ::dialog::question]] > 0}]
            if {$haveQuestion} {
                rename ::dialog::question $savedQuestion
                proc ::dialog::question {args} { return yes }
            }
            try {
                foreach base $bases {
                    if {$base ne $::scidb::clipbaseName} {
                        catch {::application::database::closeBase .application $base}
                    }
                }
            } finally {
                if {$haveQuestion} {
                    rename ::dialog::question {}
                    rename $savedQuestion ::dialog::question
                }
                set ::game::Options(askAgain:releaseAll) $savedReleaseQuestion
                set ::game::Options(answer:releaseAll) $savedReleaseAnswer
                set ::game::Options(askAgain:closeAnyway) $savedCloseQuestion
                set ::game::Options(answer:closeAnyway) $savedCloseAnswer
            }
        }
        # Release each occupied slot through both layers: gamebar::remove
        # alone leaves ::game::List holding a slot the bar no longer shows,
        # and the next replace fails on that stale index.
        set position 0
        foreach entry [::game::gameList] {
            if {[lindex $entry 0] ne ""} {
                catch {::application::pgn::release $position}
                catch {::game::release $position}
            }
            incr position
        }
        # A probe may release only the native layer, leaving a game bar item
        # without an occupied slot. The next file then reuses that slot id and
        # the canvas rejects the duplicate tags, so drop anything stale.
        catch {
            set gb [::application::pgn::gamebar]
            if {[winfo exists $gb]} {
                set used [::game::usedPositions?]
                foreach id [::gamebar::getIdList $gb] {
                    if {$id ni $used} { ::gamebar::remove $gb $id no }
                }
            }
        }
        # Player cards register dynamic HTML actions. Closing the cards keeps
        # the assistant toolset and later popup walks at the fresh value.
        foreach child [winfo children .application] {
            if {[string match .application.__card__* $child]} {catch {destroy $child}}
        }
        # The embedded 3D widget is cached for a fast re-toggle. Its frame is
        # parented in the layout which created it, so a later file which needs
        # a pristine 2D board must not inherit the cached frame.
        catch {
            set w $::application::board::Vars(3dwin)
            if {$w ne "" && [winfo exists $w]} {
                ::application::board::show3D 0
                destroy $w
                set ::application::board::Vars(3dwin) {}
                set ::board3d::Priv(embed,frame) {}
                set ::board3d::Priv(embed,togl) {}
            }
        }
        # Releasing the games leaves the board on the last position. The next
        # file expects the app to be at the standard start position unless it
        # opens a game of its own, so put the empty scratch game back there.
        if {[info exists ::application::pgn::Vars(gamebar)]
         && [::gamebar::empty? $::application::pgn::Vars(gamebar)]} {
            catch {
                set current [::scidb::game::current]
                if {$current != 9 && [::scidb::game::query 9 open?]} {
                    ::scidb::game::switch 9
                }
                ::scidb::game::clear [set ::game::StartPositionFen]
            }
        }
        # A probe may have replaced the engine list with its own fixture and
        # deleted that program with its scratch directory. Restore the list
        # the process started with (memory and the options file): an empty or
        # broken list shrinks the engine dialogs and breaks the engine menus.
        catch {
            if {$::engine::Engines ne $::scidb::test::actions::StartupEngines} {
                set ::engine::Engines $::scidb::test::actions::StartupEngines
                ::engine::SaveEngineList
            }
        }
        # A file which starts the assistant's position search and leaves it
        # running leaves Tree(token) busy: the next file's position_moves
        # refuses with "a position search is already running", and the stale
        # 60 s timer fires inside an unrelated test. Cancel and clear it.
        catch {
            if {[info exists ::application::assistant::Tree(token)]
             && [string length $::application::assistant::Tree(token)]} {
                if {[info exists ::application::assistant::Tree(timer)]} {
                    catch { after cancel $::application::assistant::Tree(timer) }
                }
                catch {
                    trace remove execution ::application::tree::ConfigSearchButton \
                        enter ::application::assistant::TreeButton
                }
                set ::application::assistant::Tree(token) {}
                set ::application::assistant::Tree(timer) {}
            }
        }
        # Keyboard focus is process state. A probe which leaves it on a board
        # pane gives the next file's menu labels their board meaning (Edit >
        # Copy becomes the annotation command) and sends its keystrokes to the
        # board. The fresh-start focus is the main window.
        catch { focus .application }
        # Closing a base adds it to Open Recent. A later menu walk in the same
        # process must not see fixtures opened by an earlier file.
        catch {::application::database::ClearHistory}
        catch {resetFixture}
        resetDatabasePage
        update
    }

    # Close panes a probe added without touching the ones that were already
    # in the layout. Analysis panes are removed highest-numbered first so
    # DestroyPane's renumbering never leaves a stale uid behind.
    proc closeExtraPanes {initial} {
        set twm ""
        catch {set twm [::application::twm board]}
        if {$twm eq ""} {return}
        set extras {}
        foreach uid [$twm leaves] {
            if {$uid ni $initial} {lappend extras $uid}
        }
        foreach uid [lsort -decreasing $extras] {
            if {[catch {set frame [$twm leaf $uid]} frame] || ![winfo exists $frame]} {continue}
            catch {::application::reflow::explicitHide $twm $frame}
            catch {destroy $frame}
        }
        update
    }

    # Capture the board's pane set, geometry and reflow intent before a test
    # destroys panes or switches to a board-only layout. restoreBoard puts all
    # of it back so the next file in the shared process starts from the same
    # arrangement.
    proc captureBoard {} {
        set twm [::application::twm board]
        set id $::application::Vars($twm:id)
        return [dict create \
            manager $twm id $id leaves [$twm leaves] \
            layout [::application::twm::inspectLayout $twm] \
            override $::application::reflow::S(override) \
            name [::application::twm::currentLayoutName $twm]]
    }

    proc restoreBoard {state} {
        set twm [dict get $state manager]
        if {[catch {::application::twm board} live] || $live ne $twm} {
            set twm $live
        }
        set leaves [dict get $state leaves]
        foreach uid [$twm leaves] {
            if {$uid ni $leaves} {catch {::application::twm::ChangeState $twm $uid}}
        }
        foreach uid $leaves {
            if {$uid ni [$twm leaves]} {catch {::application::openPane $uid}}
        }
        update idletasks
        ensureBoardPane
        # Closing and reopening the board recreates it as a movable frame
        # with an explicit flat header, while startup's BoardLayout pane has
        # no flat attribute. A later Fold would then fold the board itself
        # and leave a stale Extent. Destroy that rebuilt leaf so the layout
        # load below recreates the fixed pane the captured layout describes.
        if {[catch {$twm leaf board} leaf] == 0 && [winfo exists $leaf]
         && [catch {$twm get $leaf flat}] == 0
         && ![layoutHasAttr [dict get $state layout] board flat]} {
            catch {destroy $leaf}
            update
        }
        catch {$twm load [dict get $state layout]}
        update
        normalizeMultiwindow $twm
        # openPane marks every restored pane as an explicit reopen and leaves
        # an empty analysis pane visible at its minimum width. Put the original
        # reflow intent back and let the normal collapse pass capture a fresh
        # snapshot, so a later layout save records the settled arrangement
        # instead of the overflowed one.
        set override [dict get $state override]
        foreach uid [$twm leaves] {
            if {$uid in $override} continue
            catch {::application::reflow::explicitHide $twm [$twm leaf $uid]}
        }
        ::application::reflow::onPaneStateChange
        for {set i 0} {$i < 10} {incr i} {after 20; update}
        set ::application::twm::Options([dict get $state id]:layout:name) [dict get $state name]
        update
    }

    proc layoutHasAttr {layout uid attr} {
        set length [llength $layout]
        for {set i 0} {$i < $length} {} {
            set type [lindex $layout $i]; incr i
            set id [lindex $layout $i]; incr i
            set attrs [lindex $layout $i]; incr i
            if {$id eq $uid && [dict exists $attrs -attrs]
             && [lsearch -exact [dict get $attrs -attrs] $attr] >= 0} {
                return 1
            }
            if {$type ni {pane frame}} {
                if {[layoutHasAttr [lindex $layout $i] $uid $attr]} {return 1}
                incr i
            }
        }
        return 0
    }

    # The main window's fresh-start state. A file that maximises the window
    # to exercise full-screen placement leaves the next file measuring that
    # surface instead of the one a fresh start gives.
    proc rememberStartupWindow {} {
        set ::scidb::test::actions::StartupWindow \
            [list [wm state .application] [wm geometry .application]]
        return $::scidb::test::actions::StartupWindow
    }

    proc restoreStartupWindow {} {
        if {![info exists ::scidb::test::actions::StartupWindow]} { return 0 }
        lassign $::scidb::test::actions::StartupWindow state geometry
        set changed 0
        if {[wm state .application] ne $state} {
            catch { wm state .application $state }
            set changed 1
        }
        if {[wm geometry .application] ne $geometry} {
            catch { wm geometry .application $geometry }
            set changed 1
        }
        if {$changed} {
            update idletasks
            update
        }
        return $changed
    }

    # The arrangement a fresh start leaves: the shipped board layout with the
    # panes it declares, no saved layout and no explicit reopen overrides.
    # Files share one process, so a file which opens panes, maximises a pane
    # or forces panes back open must not decide the arrangement, the window
    # minimum or the board size the files after it start from.
    proc startupArrangement {} {
        set twm [::application::twm board]
        set id $::application::Vars($twm:id)
        return [dict create \
            manager $twm id $id \
            leaves {board editor games dbgames tree analysis:1} \
            layout [::application::reflow::substTpl $::application::BoardLayout] \
            override {} name ""]
    }

    # True when the pane set, the reopen overrides and the pane widgets are
    # still the ones a fresh start has. The layout structure is compared as
    # well when the leaves match, ignoring sash coordinates: a file which
    # reordered panes must not hand its arrangement to the next file either.
    proc arrangementIsStartup {} {
        set state [startupArrangement]
        set twm [dict get $state manager]
        if {[catch {$twm leaves} leaves]} { return 0 }
        if {$leaves ne [dict get $state leaves]} { return 0 }
        if {[llength $::application::reflow::S(override)]} { return 0 }
        # A pane can outlive its widget (a frame closed while the module kept
        # the path). Reopening rebuilds it, so treat that as a changed
        # arrangement instead of handing a dead table to the next file.
        if {[info exists ::application::tree::Vars(table)]
         && ![winfo exists $::application::tree::Vars(table)]} { return 0 }
        if {[catch {set actual [::application::twm::inspectLayout $twm]}]} {
            return 0
        }
        return [expr {
            [layoutPaneOrder $actual] eq [layoutPaneOrder [dict get $state layout]]
        }]
    }

    # The pane sequence of a layout, ignoring panes' options and sash
    # coordinates: the twm's own inspect output spells options differently
    # from the layout template, so the structure is what can be compared.
    # Every node is the triple {type id-or-options body}.
    proc layoutPaneOrder {layout} {
        set order {}
        foreach {type first body} $layout {
            if {$type in {pane frame}} {
                lappend order $first
            } else {
                lappend order {*}[layoutPaneOrder $body]
            }
        }
        return $order
    }

    # Put the startup arrangement back after a file that changed it. Closing
    # and reopening the panes a file left behind also refreshes the module
    # state (a tree table rebuilt in a new frame) that the file's own cleanup
    # may have left pointing at a destroyed widget.
    proc restoreStartupArrangement {} {
        if {[catch {arrangementIsStartup} same]} { return 0 }
        if {$same} { return 0 }
        set state [startupArrangement]
        set twm [dict get $state manager]
        if {[catch {$twm leaves}]} { return 0 }
        # The tree keeps its table widget when the pane is only collapsed, but
        # loses it when the pane was closed. Reopen it first so restoreBoard
        # below rebuilds the module instead of loading a layout with a dead
        # widget inside.
        if {[info exists ::application::tree::Vars(table)]
         && ![winfo exists $::application::tree::Vars(table)]
         && [lsearch -exact [$twm leaves] tree] >= 0} {
            catch {::application::twm::ChangeState $twm tree}
            update
        }
        catch {restoreBoard $state}
        return 1
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
            find_capability { set result {request {review my games}} }
            run_action { set result {id pane arguments {action dock pane board}} }
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
            # its own position: engine_play, probed just before, moves on the board
            engine_check_move { set result {move e4 fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}} }
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
        add_to_repertoire {error: no writable repertoire database is open. Open one, or mark a database as one: Database > Maintenance > Repertoire Type > Openings}
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
    # Best effort: a file that reaches this point must still reach
    # tcltest::cleanupTests even when a prior test left a slot or base in a
    # shape the individual release paths cannot consume. release also closes
    # bases with the release dialogs forced to "yes", so a base cannot stay
    # open on the fixture directory that is deleted immediately afterwards.
    catch { ::scidb::test::actions::release }
    foreach pos [::game::usedPositions?] {
        catch { ::application::pgn::release $pos }
        catch { ::game::release $pos }
    }
    if {[file exists [file join $Dir generated.pgn]] && [::scidb::db::get open? [file join $Dir generated.pgn]]} {
        catch { ::application::database::closeBase .application [file join $Dir generated.pgn] }
    }
    catch { file delete -force $Dir }
}

# Every file that uses these probes shares one process with the next file.
# Drain the process-wide state on every tcltest::cleanupTests, including the
# files that do not call ::scidb::test::actions::cleanup themselves: a stopped
# engine, an open base or a game slot left behind changes the next file's
# fixture, and a deferred engine callback can then fire in the middle of the
# next file's native engine start.
# Keep the original command inside ::tcltest: its body resolves numTests and
# the other test counters as namespace variables there. Renaming it into
# another namespace would rebind those variables and break every following
# file.
if {![info exists ::scidb::test::actions::cleanupHook]} {
    set ::scidb::test::actions::cleanupHook 1
    rename ::tcltest::cleanupTests ::tcltest::cleanupTestsOrig
    proc ::tcltest::cleanupTests {args} {
        # A file that sources another test may deliberately keep its base and
        # slots open across the inner cleanupTests; respect that handoff.
        if {![info exists ::postedKeepOpen]} {
            catch { ::scidb::test::actions::release }
        }
        uplevel 1 [list ::tcltest::cleanupTestsOrig {*}$args]
    }
}
