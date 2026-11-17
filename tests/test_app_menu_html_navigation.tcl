package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_html_popup_support.tcl
::scidb::test::actions::ready
::scidb::test::actions::fixture

# Inspect actual mapped menus, including disabled commands invoked directly
# through the registry (Tk itself refuses to invoke disabled entries).
proc ::scidb::test::htmlpop::navigation {rows surface mapping} {
    set commands {}
    foreach row $rows {
        set command [lindex $row 4]
        set operation [lindex [split [lindex $command 1] .] end]
        if {[lindex $command 1] ne "html.$surface.$operation" || ![dict exists $mapping $operation]} continue
        set button [dict get $mapping $operation]
        set disabled [expr {[$button cget -state] eq "disabled"}]
        if {([lindex $row 2] eq "disabled") != $disabled} {error "menu/button state differs: $row $button"}
        set state [::menu::state [lindex $command 1] {} [lindex $command 2]]
        if {[dict get $state enabled] == $disabled} {error "action/button state differs: $command $button"}
        if {$disabled && ![string match error:* [uplevel #0 $command]]} {error "disabled navigation accepted: $command"}
        dict set commands $operation $command
    }
    if {[dict size $commands] != [dict size $mapping]} {error "navigation rows missing: $commands"}
    return $commands
}

tcltest::test menu-html-navigation-tournament {first/last event mapped rows and dispatch follow real buttons in both directions} -body {
    set base [::scidb::test::htmlpop::tournamentBase]
    set f [open $base]; set pgn [read $f]; close $f
    set path [file join $::env(HOME) navigation-events.pgn]
    set f [open $path w]
    puts $f $pgn
    puts $f [string map {{Generated Popup Tournament} {Generated Second Tournament}} $pgn]
    puts $f [string map {{Generated Popup Tournament} {Generated Third Tournament}} $pgn]
    close $f
    ::action::run open_database [dict create path $path]
    ::crosstable::open .application $path Normal 0 0 event
    update
    set dlg $::crosstable::Reuse
    set indices {}
    foreach direction {next next previous previous} expected {0 1 2 1} {
        set rows [::scidb::test::htmlpop::capture tournament.navigation [list ::crosstable::PopupMenu $dlg]]
        set commands [::scidb::test::htmlpop::navigation $rows crosstable [dict create previous $dlg.previous next $dlg.next]]
        set index [set ::crosstable::${dlg}::Vars(index)]
        if {$index != $expected} {error "expected event $expected, got $index"}
        lappend indices $index
        set before [set ::crosstable::${dlg}::Vars(output:html)]
        set reply [uplevel #0 [dict get $commands $direction]]
        if {[string match error:* $reply]} {error $reply}
        update
        if {$before eq [set ::crosstable::${dlg}::Vars(output:html)]} {error {event navigation did not redraw the table}}
        # Reuse the original command at a boundary: dispatch must recheck
        # the current state rather than trusting the earlier menu snapshot.
        if {$expected == 1} {
            set reply [uplevel #0 [dict get $commands $direction]]
            if {![string match error:* $reply]} {error "stale boundary command accepted"}
        }
    }
    lappend indices [set ::crosstable::${dlg}::Vars(index)]
} -cleanup {catch {destroy $dlg}} -result {0 1 2 1 0}

tcltest::test menu-html-navigation-overview {overview first/last aliases follow Previous/Next buttons and refuse direct boundary dispatch} -body {
    set base [::scidb::test::htmlpop::tournamentBase]
    set info [::scidb::db::get gameInfo 0 0 $base Normal]
    set nb [::overview::open .application $base Normal $info 0 0]
    set dlg [winfo toplevel $nb]
    update
    set indices {}
    foreach direction {last first} {
        set rows [::scidb::test::htmlpop::capture overview.navigation [list ::overview::PopupMenu $nb]]
        set commands [::scidb::test::htmlpop::navigation $rows overview [dict create prev $dlg.previous first $dlg.previous next $dlg.next last $dlg.next]]
        lappend indices [set ::overview::${nb}::Vars(index)]
        set reply [uplevel #0 [dict get $commands $direction]]
        if {[string match error:* $reply]} {error $reply}
        update
    }
    list [lindex $indices 0] [expr {[lindex $indices 1] == [::scidb::view::count games $base Normal 0]-1}] [set ::overview::${nb}::Vars(index)]
} -cleanup {catch {destroy $dlg}} -result {0 1 0}

tcltest::test menu-html-navigation-help {Help history and topic availability follow their native buttons} -body {
    set dlg [::help::open .application Ask-Field]
    update
    set html $::help::Priv(html)
    event generate [$html drawable] <Motion> -warp 1 -x 30 -y 30
    update
    set rows [::scidb::test::htmlpop::capture help.navigation [list event generate [$html drawable] <ButtonPress-3> -x 30 -y 30]]
    set buttons {}
    foreach op {prev next back forward} {dict set buttons $op $::help::Priv(button:$op)}
    dict size [::scidb::test::htmlpop::navigation $rows help $buttons]
} -cleanup {catch {::help::Destroy}} -result 4

::scidb::test::actions::release
tcltest::cleanupTests
