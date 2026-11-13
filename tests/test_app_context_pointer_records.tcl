package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::pointer {}
proc ::scidb::test::pointer::receive {record} {set ::scidb::test::pointer::record $record}
proc ::scidb::test::pointer::findPgn {w} {
    if {[winfo viewable $w] && [string match *PopupMenu* [bind $w <ButtonPress-3>]]} {return $w}
    foreach child [winfo children $w] {set found [findPgn $child];if {$found ne {}} {return $found}}
    return {}
}
proc ::scidb::test::pointer::click {w} {
    set x [expr {[winfo width $w]/2}]
    set y [expr {[winfo height $w]/2}]
    event generate $w <Motion> -warp 1 -x $x -y $y
    update
    if {$w eq [::board::diagram::canvas $::application::board::board]} {
        set ::scidb::test::pointer::square [::board::diagram::getSquare $::application::board::board [winfo pointerx $w] [winfo pointery $w]]
    }
    event generate $w <ButtonPress-3> -time [expr {[clock milliseconds] & 0x7fffffff}] -x $x -y $y
    event generate $w <ButtonRelease-3> -time [expr {[clock milliseconds] & 0x7fffffff}] -x $x -y $y
    update
}
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after black}
update
set savedSink $::context::AssistantSink
set ::context::AssistantSink ::scidb::test::pointer::receive
rename ::ai::egress::ContextDecide ::ai::egress::pointerSavedDecide
proc ::ai::egress::ContextDecide {record callback} {{*}$callback {ok 1 label send confidence 1 source rules}}
tcltest::test context-native-square-record {right clicking the board canvas passes the actual square and FEN to Ask} -body {
    set board $::application::board::board
    set canvas [::board::diagram::canvas $board]
    ::scidb::test::pointer::click $canvas
    set sq $::scidb::test::pointer::square
    set expected [dict create square [lindex $::board::diagram::squareIndex $sq] fen [::scidb::game::query fen]]
    $canvas.popup_menu invoke 0
    list [expr {$sq>=0}] [expr {$::scidb::test::pointer::record eq $expected}]
} -cleanup {
    catch {::tk::MenuUnpost $canvas.popup_menu}
    catch {grab release $canvas.popup_menu}
    catch {destroy $canvas.popup_menu}
} -result {1 1}
tcltest::test context-native-move-record {right clicking the notation passes the actual SAN and same move as implicit Ask} -body {
    set frame $::application::pgn::Vars(frame)
    set w [::scidb::test::pointer::findPgn $frame]
    ::scidb::test::pointer::click $w
    set expected [::scidb::game::query move [::scidb::game::position key]]
    $frame.__menu__ invoke 0
    set record $::scidb::test::pointer::record
    list [expr {$expected ne {}}] [expr {[dict get $record san] eq $expected}] \
        [expr {[dict get [::context::CurrentObject C2] san] eq $expected}] \
        [lsort [dict keys $record]]
} -cleanup {
    catch {::tk::MenuUnpost $frame.__menu__}
    catch {grab release $frame.__menu__}
    catch {destroy $frame.__menu__}
} -result {1 1 1 {base index ply san variant}}
rename ::ai::egress::ContextDecide {}
rename ::ai::egress::pointerSavedDecide ::ai::egress::ContextDecide
set ::context::AssistantSink $savedSink
::tcltest::cleanupTests
