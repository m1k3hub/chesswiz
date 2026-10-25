package require tcltest 2.5
source [file join [file dirname [info script]] menu_handler_check.tcl]
tcltest::test menu-handlers-audit {registered handlers and dispatcher calls exist and have valid arity} -body {
    ::handlercheck::audit
} -result {}

namespace eval ::scidb::test::handlers { variable called {} }
# Keep the callee's actual signature: wrong argument counts still fail.
proc ::scidb::test::handlers::stub {cmd} {
    set params {}
    foreach arg [info args $cmd] {
        if {[info default $cmd $arg val]} { lappend params [list $arg $val] } else { lappend params $arg }
    }
    rename $cmd ${cmd}__saved
    proc $cmd $params [list set ::scidb::test::handlers::called $cmd]
}
proc ::scidb::test::handlers::unstub {cmd} {
    rename $cmd {}
    rename ${cmd}__saved $cmd
}
foreach {id target} {
    menu.analysis.analyze ::application::analysis::AnalyzeCurrentPosition
    menu.db.reports.eco ::application::database::ShowEcoStats
    menu.db.reports.opening ::application::database::ShowOpeningReport
    menu.game.copy ::gamebar::CopyThisGameToClipbase
} {
    tcltest::test menu-handler-target-$id {action reaches the intended feature with its real signature} -setup {
        ::scidb::test::handlers::stub $target
        set ::scidb::test::handlers::called {}
    } -body {
        ::action::run $id
        set ::scidb::test::handlers::called
    } -cleanup {
        ::scidb::test::handlers::unstub $target
    } -result $target
}

tcltest::test menu-handler-filetypes {absent filetypes module hides the row} -body {
    expr {[::menu::ModulePresent filetypes] || ![dict get [::menu::state menu.tools.file_types] visible]}
} -result 1

# Modal dialogs are closed from their event loop. Record their existence first.
proc ::scidb::test::handlers::closeDialog {dlg} {
    if {[winfo exists $dlg]} {
        set ::scidb::test::handlers::seen 1
        destroy $dlg
    } else {
        set ::scidb::test::handlers::timer [after 20 [list ::scidb::test::handlers::closeDialog $dlg]]
    }
}
foreach id {menu.view.layout.save menu.view.layout.save_as menu.view.layout.manage} {
    tcltest::test menu-handler-dialog-$id {layout action opens the real dialog and releases its grab} -setup {
        set savedGeometry [wm geometry .application]
        wm geometry .application 1400x900
        # Startup queues an idle switchTab to its initial tab; run it first so
        # it cannot select that tab again after ours.
        update
        ::application::switchTab board
        update
        set twm [::menu::CurrentTWM]
        set suffix [expr {$id eq "menu.view.layout.manage" ? "layout" : "save"}]
        set dlg $twm.$suffix
        set ::scidb::test::handlers::seen 0
        set ::scidb::test::handlers::timer [after 20 [list ::scidb::test::handlers::closeDialog $dlg]]
    } -body {
        set result [::action::run $id]
        update
        if {[winfo exists $dlg]} { ::scidb::test::handlers::closeDialog $dlg }
        list $::scidb::test::handlers::seen [string match {error:*} $result] [grab current]
    } -cleanup {
        after cancel $::scidb::test::handlers::timer
        catch {destroy $dlg}
        wm geometry .application $savedGeometry
    } -result {1 0 {}}
}

tcltest::test menu-handler-position-presets {position preset action opens the populated preset menu} -body {
    after 50 {catch { .application.shufflepopup unpost }; catch {grab release .application.shufflepopup}}
    ::action::run menu.board.start.setup
    list [winfo exists .application.shufflepopup] [expr {[.application.shufflepopup index end] > 0}]
} -cleanup {
    catch {destroy .application.shufflepopup}
} -result {1 1}

tcltest::test menu-handler-guess-empty {Guess the Move explains the missing game} -setup {
    ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
    rename ::dialog::info ::dialog::info__saved
    proc ::dialog::info {args} {set ::scidb::test::handlers::message [dict get $args -message]}
    set ::scidb::test::handlers::message {}
} -body {
    ::action::run menu.training.guess
    set ::scidb::test::handlers::message
} -cleanup {
    rename ::dialog::info {}
    rename ::dialog::info__saved ::dialog::info
} -result $::guessmove::mc::NoMoves

tcltest::test menu-handler-guess-window {Guess the Move opens a window with a loaded line} -setup {
    ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
    ::move::addMove menu e4
    ::scidb::game::go -1 start
    update
} -body {
    set result [::action::run menu.training.guess]
    update
    list [string match {error:*} $result] [winfo ismapped .application.__guessmove__]
} -cleanup {
    ::guessmove::stop
} -result {0 1}


# Native Windows and macOS must never query the X11 -zoomed attribute.
tcltest::test menu-handler-native-zoom {placement reads native maximized state without an X11 attribute} -setup {
    rename ::tk ::tk__zoom_saved
    rename ::wm ::wm__zoom_saved
    proc ::tk {op args} {
        if {$op eq "windowingsystem"} {return win32}
        uplevel 1 [list ::tk__zoom_saved $op {*}$args]
    }
    proc ::wm {op args} {
        if {$op eq "attributes"} {error {bad attribute "-zoomed"}}
        if {$op eq "state"} {return zoomed}
        uplevel 1 [list ::wm__zoom_saved $op {*}$args]
    }
} -body {
    ::util::place::windowZoomed .application
} -cleanup {
    rename ::tk {}; rename ::tk__zoom_saved ::tk
    rename ::wm {}; rename ::wm__zoom_saved ::wm
} -result 1

tcltest::test menu-handler-close {Close Game releases the current game tab} -setup {
    ::menu::gameNew .application Normal
    set bar $::application::pgn::Vars(gamebar)
    set pos [::gamebar::selected $bar]
    set before [::gamebar::size $bar]
} -body {
    set result [::action::run menu.game.close]
    list [string match {error:*} $result] [expr {[::gamebar::size $bar] == $before - 1}] \
        [expr {[lsearch -exact [::gamebar::getIdList $bar] $pos] < 0}]
} -result {0 1 1}


foreach {id target object} {
    c5.insights ::insights::show {parent .application base testbase variant Normal index 7}
    c8.save_line ::context::SaveTreeLine {parent .application variant Normal move e4}
} {
    tcltest::test menu-handler-context-$id {context action reaches a real feature with valid arguments} -setup {
        ::scidb::test::handlers::stub $target
        set ::scidb::test::handlers::called {}
    } -body {
        ::context::Command $id $object
        set ::scidb::test::handlers::called
    } -cleanup {
        ::scidb::test::handlers::unstub $target
    } -result $target
}

tcltest::test menu-handler-save-clipbase {Save Changes on clipbase has no dialog and no error} -body {
    set result [::application::database::SaveChanges .application $::scidb::clipbaseName]
    list $result [winfo exists .application.save]
} -result {{} 0}

tcltest::test menu-handler-comment-symbols {real symbol builder populates the C11 cascade} -setup {
    menu .handlerSymbols -tearoff 0
    text .handlerText
} -body {
    list [::context::CascadePrefix c11.insert_symbol .handlerSymbols {widget .handlerText}] \
        [expr {[.handlerSymbols index end] >= 0}]
} -cleanup {
    destroy .handlerSymbols .handlerText
} -result {1 1}

tcltest::cleanupTests
