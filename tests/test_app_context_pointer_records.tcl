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
proc ::scidb::test::pointer::click {w {x {}} {y {}}} {
    if {$x eq {}} {set x [expr {[winfo width $w]/2}]}
    if {$y eq {}} {set y [expr {[winfo height $w]/2}]}
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
    # Target the move itself: the widget center can be blank notation.
    set range [::application::pgn::FindRange $w [::scidb::game::position key] [::scidb::game::current]]
    if {![llength $range]} {error {current move has no text range}}
    $w see [lindex $range 0]
    update
    lassign [$w bbox [lindex $range 0]] x y width height
    if {"m:move" ni [$w tag names @$x,$y]} {error {pointer must be over a move}}
    ::scidb::test::pointer::click $w $x $y
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
::application::switchTab database
update
tcltest::test context-native-column-menu {physical header click leaves the C10 popup mapped without building a game-row menu} -body {
    set manager $::application::database::Vars(games).twm
    set scroll [set ::application::database::games::${manager}::Priv(table)]
    set table [::scrolledtable::table $scroll]
    ::scidb::test::pointer::click $table.t 80 10
    set mapped 0
    foreach child [winfo children $table] {
        if {[string match *.__table_menu_02763278918911__* $child] && [winfo ismapped $child]} {set mapped 1}
    }
    list $mapped [winfo exists $table.menu]
} -cleanup {
    catch {::tk::MenuUnpost {}}
    foreach child [winfo children $table] {
        if {[winfo class $child] eq "Menu"} {catch {grab release $child};destroy $child}
    }
} -result {1 0}
tcltest::test context-native-database-record {physical database symbol click passes that database to Ask even over icon or text} -body {
    set switcher $::application::database::Vars(switcher)
    set canvas $switcher.content
    set id [set ::database::switcher::${switcher}::Vars(id:$base)]
    lassign [$canvas bbox input$id] x1 y1 x2 y2
    set x [expr {int(($x1+$x2)/2-[$canvas canvasx 0])}]
    set y [expr {int(($y1+$y2)/2-[$canvas canvasy 0])}]
    ::scidb::test::pointer::click $canvas $x $y
    $canvas.__menu__ invoke 0
    list [dict keys $::scidb::test::pointer::record] [dict get $::scidb::test::pointer::record base]
} -cleanup {
    catch {::tk::MenuUnpost $canvas.__menu__}
    catch {grab release $canvas.__menu__}
    catch {destroy $canvas.__menu__}
} -result [list base $base]
rename ::ai::egress::ContextDecide {}
rename ::ai::egress::pointerSavedDecide ::ai::egress::ContextDecide
set ::context::AssistantSink $savedSink
::tcltest::cleanupTests
