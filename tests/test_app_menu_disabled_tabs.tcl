# Native posting on both tabs and a physical board-only layout. Keep the
# existing every-row walker and its assertions unchanged; sweep all disabled
# rows with real validation/state gates and only the final handler replaced.
package require tcltest 2.5
source tests/test_app_menu_registry_walk.tcl
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
namespace eval ::scidb::test::disabledtabs {variable calls 0}
proc ::scidb::test::disabledtabs::Leaf {args} {incr ::scidb::test::disabledtabs::calls}
proc ::scidb::test::disabledtabs::Sweep {tag} {
    catch {destroy .disabledtabs}
    menu .disabledtabs -tearoff 0
    ::menu::BuildDropdown .disabledtabs
    ::scidb::test::rgw::PostTree .disabledtabs
    set rows {}
    ::scidb::test::rgw::WalkMenu .disabledtabs rows dropdown
    lappend rows {*}[::scidb::test::rgw::WalkContexts]
    ::scidb::test::rgw::Toolbars . rows
    set count 0; set bad {}; set ids {}
    foreach row $rows {
        if {[lindex $row 2] ne "disabled"} {continue}
        set command [lindex $row 4]
        if {![regexp {^::action::run (\S+)} $command -> id]} {continue}
        if {[lindex $row 0] eq "toolbar-binding"} {set command [lindex [split $command "\n;"] 0]}
        set saved [::action::get $id]
        dict set ::action::Registry $id handler ::scidb::test::disabledtabs::Leaf
        set ::scidb::test::disabledtabs::calls 0
        try {
            set code [catch {::action::invoke $id {*}[lrange $command 2 end]} reply]
            update idletasks
            incr count; lappend ids $id
            puts [list DISABLED_TAB $tag surface [lindex $row 0] id $id code $code reply $reply calls $::scidb::test::disabledtabs::calls]
            if {$code || $::scidb::test::disabledtabs::calls} {lappend bad [list $row $code $reply]}
        } finally {dict set ::action::Registry $id $saved}
    }
    destroy .disabledtabs
    puts [list DISABLED_SWEEP $tag rows $count ids [lsort -unique $ids] bad $bad]
    if {!$count || [llength $bad]} {error [list disabled-sweep $tag $count $bad]}
    return ok
}
foreach tab {board database} {
    tcltest::test menu-disabled-all-tabs-$tab {every disabled posted row refuses direct invocation in its native tab state} -body {
        ::application::switchTab $tab
        update
        ::scidb::test::disabledtabs::Sweep $tab
    } -result ok
}
tcltest::test menu-disabled-board-only {Database actions refuse invocation in a physically board-only layout} -body {
    ::application::switchTab board
    update
    set manager [::application::twm board]
    foreach uid [$manager leaves] {
        if {$uid ne "board"} {
            set frame [$manager leaf $uid]
            ::application::reflow::explicitHide $manager $frame
            destroy $frame
        }
    }
    update
    if {[$manager leaves] ne {board}} {error {fixture is not physically board-only}}
    ::action::run menu.view.layout.save_as {name {Generated Board only}}
    ::action::run menu.view.layout.manage {operation load name {Generated Board only}}
    update
    if {![::menu::BoardOnlyLayout]} {error {board-only layout fixture was not active}}
    ::scidb::test::disabledtabs::Sweep board-only
} -result ok
::tcltest::cleanupTests
