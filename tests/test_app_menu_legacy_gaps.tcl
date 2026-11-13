# Native effects for the baseline features restored by decision Addendum 3.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::gaps {
    variable dir [file join $::scidb::test::actions::Dir legacy-gaps]
    variable timer {}
    variable observed {}
    variable failure {}
}
proc ::scidb::test::gaps::nop {args} {}
proc ::scidb::test::gaps::base {} {
    variable dir
    file mkdir $dir
    set pgn [file join $dir generated.pgn]
    set ch [open $pgn w]
    for {set n 1} {$n <= 2} {incr n} {
        puts $ch "\[Event \"Generated $n\"\]\n\[Site \"Test\"\]\n\[Date \"2026.11.13\"\]\n\[Round \"$n\"\]\n\[White \"White$n\"\]\n\[Black \"Black$n\"\]\n\[Result \"*\"\]\n\[RemoveMe \"extra$n\"\]\n\[KeepMe \"keep$n\"\]\n\n1. e4 {\[%eval 0.25\] \[%clk 0:05:00\] \[%cclk P28DT12H30M\] \[%cemt P2DT4H30M\]} e5 *\n"
    }
    close $ch
    ::scidb::db::open $pgn [namespace current]::nop {} [namespace current]::nop {}
    set base [file join $dir generated.sci]
    ::application::database::newBase .application Normal $base
    ::scidb::db::copy $pgn $base {} [namespace current]::nop {} [namespace current]::nop {}
    ::scidb::db::close $pgn
    ::scidb::db::save $base [namespace current]::nop {}
    ::application::database::closeBase .application $base
    ::application::database::openBase .application $base no
    ::application::database::refreshBase $base
    update
    return $base
}
proc ::scidb::test::gaps::closeBase {base} {
    catch {::game::closeAll .application $base Normal}
    catch {::application::database::closeBase .application $base}
    catch {::scidb::db::close $base}
    variable dir
    file delete -force $dir
}
# Inspect the real modal window and operate its real controls. Never stub the
# registry, dialogs, progress runner, or database engine.
proc ::scidb::test::gaps::choose {dlg mode deadline} {
    variable timer
    variable observed
    variable failure
    if {![winfo exists $dlg] || [grab current] ne $dlg} {
        if {[clock milliseconds] < $deadline} {
            set timer [after 20 [list [namespace current]::choose $dlg $mode $deadline]]
        } else {
            set failure "dialog did not appear: $dlg"
        }
        return
    }
    if {[catch {
        lappend observed [file tail $dlg] [wm title $dlg]
        switch $mode {
            icon {
                set old $::application::database::Vars(icon)
                set ::application::database::Vars(icon) [expr {$old == 0 ? 1 : 0}]
                $dlg.ok invoke
            }
            info {
                foreach attr $::application::database::MoveInfoAttrs {
                    set ::application::database::Vars(moveInfo:$attr) 0
                }
                $dlg.top.evaluation invoke
                $dlg.ok invoke
            }
            tags {
                if {[$dlg.ok cget -state] ne "disabled"} {error {empty selection must disable OK}}
                $dlg.top.bRemoveMe invoke
                $dlg.ok invoke
            }
            defaults {$dlg.ok invoke}
            cancel {$dlg.cancel invoke}
        }
    } err opts]} {
        set failure [dict get $opts -errorinfo]
        catch {destroy $dlg}
    }
}
proc ::scidb::test::gaps::invoke {id dlg mode} {
    variable observed {}
    variable failure {}
    variable timer
    set timer [after 20 [list [namespace current]::choose $dlg $mode [expr {[clock milliseconds]+5000}]]]
    set result [::action::run $id]
    after cancel $timer
    if {$failure ne {}} {error $failure}
    if {![llength $observed]} {error "no native dialog observed for $id: $result"}
    if {[string match error:* $result]} {error $result}
    update
}
proc ::scidb::test::gaps::games {base} {
    set result {}
    for {set n 0} {$n < 2} {incr n} {
        set slot [::game::new .application -base $base -variant Normal -number $n]
        lappend result [::scidb::game::toPGN original -position $slot -flags 9470975]
        ::application::pgn::release $slot
        ::game::release $slot
    }
    ::application::database::refreshBase $base
    return $result
}

tcltest::test menu-legacy-variation-insert {C2 inserts the existing side line before its parent continuation, undo restores it} -setup {
    ::menu::gameNew .application
    ::scidb::game::import [::scidb::game::current] {1. e4 (1. d4 d5) e5 *} {} {} -encoding utf-8 -variation 0
    ::scidb::game::go start
    ::scidb::game::go variation 0
    ::scidb::game::position forward
    set before [::scidb::game::toPGN modified]
} -body {
    set reply [::action::run c2.add_variation [dict create object [::context::CurrentObject C2]]]
    set after [::scidb::game::toPGN modified]
    ::scidb::game::go start
    set moves {}
    while {![::scidb::game::position atEnd?]} {
        ::scidb::game::position forward
        lappend moves [::scidb::game::query move [::scidb::game::position key]]
    }
    ::scidb::game::execute undo
    list [string match error:* $reply] $moves [expr {$before ne $after}] [expr {$before eq [::scidb::game::toPGN modified]}]
} -cleanup {
    set slot [::scidb::game::current]
    ::application::pgn::release $slot
    ::game::release $slot
} -result {0 {d4 d5 e4 e5} 1 1}

tcltest::test menu-legacy-change-icon {maintenance opens the picker, cancellation preserves type, OK updates saved type} -setup {
    set base [::scidb::test::gaps::base]
    set old [::scidb::db::get type $base]
} -body {
    ::scidb::test::gaps::invoke menu.db.maintenance.change_icon .application.changeIcon cancel
    set cancelled [expr {$old eq [::scidb::db::get type $base]}]
    ::scidb::test::gaps::invoke menu.db.maintenance.change_icon .application.changeIcon icon
    set type [::scidb::db::get type $base]
    set changed [expr {$old ne $type}]
    ::application::database::closeBase .application $base
    ::application::database::openBase .application $base no
    list $cancelled $changed [expr {$type eq [::scidb::db::get type $base]}]
} -cleanup {
    ::scidb::test::gaps::closeBase $base
} -result {1 1 1}

tcltest::test menu-legacy-strip-info {database-wide picker removes chosen evaluations in both games, keeps clocks and moves} -setup {
    set base [::scidb::test::gaps::base]
    set before [::scidb::test::gaps::games $base]
} -body {
    ::scidb::test::gaps::invoke menu.db.maintenance.strip_moves .application.stripMoveInfo cancel
    set result [list [expr {$before eq [::scidb::test::gaps::games $base]}]]
    ::scidb::test::gaps::invoke menu.db.maintenance.strip_moves .application.stripMoveInfo info
    foreach old $before new [::scidb::test::gaps::games $base] {
        lappend result [expr {[string first {[%eval} $old] >= 0 && [string first {[%eval} $new] < 0}] \
            [expr {[string first {[%clk} $new] >= 0 && [string first {[%cclk} $new] >= 0 && [string first {[%cemt} $new] >= 0}] [expr {[string first {e4} $new] >= 0 && [string first {e5} $new] >= 0}]
    }
    ::scidb::test::gaps::invoke menu.db.maintenance.strip_moves .application.stripMoveInfo defaults
    foreach pgn [::scidb::test::gaps::games $base] {
        lappend result [expr {[string first {[%clk} $pgn] < 0 && [string first {[%cclk} $pgn] < 0 && [string first {[%cemt} $pgn] < 0}]
    }
    set result
} -cleanup {
    ::scidb::test::gaps::closeBase $base
} -result {1 1 1 1 1 1 1 1 1}

tcltest::test menu-legacy-strip-tags {database-wide tag picker removes selected extra tag in both games, retains unselected tags} -setup {
    set base [::scidb::test::gaps::base]
    set before [::scidb::test::gaps::games $base]
} -body {
    ::scidb::test::gaps::invoke menu.db.maintenance.strip_tags .application.stripPgnTags cancel
    set result [list [expr {$before eq [::scidb::test::gaps::games $base]}]]
    ::scidb::test::gaps::invoke menu.db.maintenance.strip_tags .application.stripPgnTags tags
    foreach old $before new [::scidb::test::gaps::games $base] {
        lappend result [expr {[string first {[RemoveMe } $old] >= 0 && [string first {[RemoveMe } $new] < 0}] \
            [expr {[string first {[KeepMe } $new] >= 0}] [expr {[string first {e4} $new] >= 0 && [string first {e5} $new] >= 0}]
    }
    set result
} -cleanup {
    ::scidb::test::gaps::closeBase $base
} -result {1 1 1 1 1 1 1}

tcltest::cleanupTests
