package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
source [file join [file dirname [info script]] app_wait.tcl]

# Native menu tracking needs OS input from outside the Tcl event loop.
# These GUI tests drive Tk's actual menu bindings on X11.
tcltest::testConstraint treeFocusX11 [expr {[tk windowingsystem] eq "x11"}]

namespace eval ::scidb::test::treefocus {
    proc nop {args} {}
    proc setup {} {
        ::scidb::test::wait::ready
        ::application::switchTab board
        variable base [file join $::scidb::test::actions::Dir tree.sci]
        set pgn [::scidb::test::actions::fixture]
        ::scidb::db::open $pgn nop {} nop {}
        ::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
        ::scidb::db::attach $base $base
        ::scidb::db::copy $pgn $base {} nop {} nop {}
        ::scidb::db::save $base nop {}
        ::scidb::db::close $base
        ::scidb::db::close $pgn
        ::application::database::openBase .application $base no
        set reply [::action::run open_game {number 1 move 1 after white}]
        if {[string match -nocase error:* $reply]} {error $reply}
        variable slot [::scidb::game::current]
        variable savedTree [::scidb::tree::get]
        ::scidb::tree::set $base
        variable table $::application::tree::Vars(table)
        variable savedKeep [::table::keepFocus $table]
        variable savedMenus [winfo children $table]
        ::application::tree::DoSearch $table
        ::scidb::test::wait::until {[llength $::application::tree::Vars(data)] > 0 && [winfo viewable $table.t]}
        lassign [$table.t item bbox 0] x y right bottom
        variable rowX [expr {$x + 4}]
        variable rowY [expr {($y + $bottom) / 2}]
        focus -force $::application::board::Vars(widget:frame)
        update
        if {[focus] ne $::application::board::Vars(widget:frame)} {
            error "Fixture did not focus the board: [focus]"
        }
        if {[$table.t cget -takefocus] ne "0"} {error {Fixture needs the Tree's takefocus=0 table}}
    }
    proc cleanup {} {
        variable table
        catch {::tk::MenuUnpost $table.popup_menu}
        variable savedMenus
        foreach child [winfo children $table] {
            if {$child ni $savedMenus && [winfo class $child] eq "Menu"} { destroy $child }
        }
        variable savedKeep
        ::table::keepFocus $table $savedKeep
        variable savedTree
        catch {::scidb::tree::set $savedTree}
        variable base
        variable slot
        ::application::pgn::release $slot
        ::game::release $slot
        catch {::application::database::closeBase .application $base}
        file delete -force $::scidb::test::actions::Dir
        update
    }
}

foreach part {row header} {
foreach dismissal {escape click-away} {
tcltest::test tree-menu-$part-$dismissal-focus {Dismissing a table popup restores its posting table even when takefocus is zero} -constraints treeFocusX11 -setup {
    ::scidb::test::treefocus::setup
} -body {
    set table $::scidb::test::treefocus::table
    set x $::scidb::test::treefocus::rowX
    set y $::scidb::test::treefocus::rowY
    if {$part eq "header"} { set y 2 }
    event generate $table.t <ButtonPress-3> \
        -x $x -y $y
    update
    set menu {}
    foreach child [winfo children $table] {
        if {[winfo class $child] eq "Menu" && [winfo ismapped $child]} { set menu $child }
    }
    if {$menu eq ""} {error {Tree popup did not post}}
    if {($part eq "row") != ($menu eq "$table.popup_menu")} {
        error "Wrong popup for $part: $menu"
    }
    if {$dismissal eq "escape"} {
        event generate $menu <Escape>
    } else {
        event generate $menu <Leave> -x -10 -y -10
        event generate $menu <ButtonPress-1> -x -10 -y -10
        event generate $menu <ButtonRelease-1> -x -10 -y -10
    }
    update
    list [winfo ismapped $menu] [grab current] [expr {[focus] eq "$table.t"}]
} -cleanup {
    ::scidb::test::treefocus::cleanup
} -result {0 {} 1}
}
}

tcltest::cleanupTests
