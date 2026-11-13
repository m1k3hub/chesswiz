# Regression coverage for legacy popup behavior now owned by the registry.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::preserve {}
proc ::scidb::test::preserve::unpost {menu} {
    ::tk::MenuUnpost $menu
    update
}

tcltest::test context-preserve-symbol16 {16 pixels remains a persistent operator choice} -setup {
    set saved $::database::switcher::Options(iconsize)
} -body {
    set reply [::action::run database.symbol_size {pixels 16}]
    list $reply $::database::switcher::Options(iconsize)
} -cleanup {
    set ::database::switcher::Options(iconsize) $saved
} -result {16 16}

tcltest::test context-preserve-switcher-help {C4 opens the switcher topic through the real help viewer} -body {
    set reply [::action::run c4.help [dict create object [dict create base $::scidb::clipbaseName parent .application]]]
    update
    list [string match error:* $reply] [winfo exists .help] [file tail $::help::Priv(current:file)]
} -cleanup {
    catch {wm withdraw .help}
} -result {0 1 Database-Switcher.html}

tcltest::test context-preserve-nag {all three NAG groups offer registered choices and change native annotations} -setup {
    ::menu::gameNew .application
    ::move::addMove menu e4
    update
    set object [::context::CurrentObject C2]
} -body {
    set result {}
    foreach {type nag} {prefix 140 infix 1 suffix 14} {
        set id c2.annot.$type
        set reply [::action::run $id [dict create object $object]]
        set m .contextChoices_nag
        lappend result [expr {$reply eq "opened choices" && [winfo ismapped $m]}]
        set found {}
        set pending [list $m]
        while {[llength $pending]} {
            set sub [lindex $pending 0]; set pending [lrange $pending 1 end]
            for {set i 0} {$i <= [$sub index end]} {incr i} {
                if {[$sub type $i] eq "cascade"} {
                    lappend pending [$sub entrycget $i -menu]
                } elseif {[$sub type $i] eq "command"} {
                    set cmd [$sub entrycget $i -command]
                    if {[lrange $cmd 0 1] ne [list ::action::run $id]} {error {NAG bypassed registry}}
                    if {[dict get [lindex $cmd 2] object nag] == $nag} {set found [list $sub $i]}
                }
            }
        }
        if {$found eq {}} {error "missing NAG $nag"}
        lassign $found sub i
        $sub invoke $i
        update
        set group [lsearch -exact {prefix infix suffix} $type]
        lappend result [expr {[format {$%d} $nag] in [lindex [::scidb::game::query annotation] $group]}]
        ::scidb::test::preserve::unpost $m
        destroy $m
        ::action::run $id [dict create object [dict replace $object nag 0]]
        lappend result [expr {[format {$%d} $nag] ni [lindex [::scidb::game::query annotation] $group]}]
    }
    set result
} -cleanup {
    catch {destroy .contextChoices_nag}
} -result {1 1 1 1 1 1 1 1 1}

tcltest::test context-preserve-c6 {a posted engine line snapshots, suspends updates, and replays them on dismissal} -setup {
    ::menu::gameNew .application
    set program [::scidb::test::actions::engineProgram]
    if {![::engine::ProbeNewEngine .application [list Command $program] UCI]} {error {engine probe failed}}
    set engineName {}
    foreach entry $::engine::Engines {if {[dict get $entry Command] eq $program} {set engineName [dict get $entry Name]; break}}
    set reply [::action::run start_engine [dict create engine $engineName threads 1 hash 16 lines 1]]
    if {![regexp {analysis pane (\d+)} $reply -> number]} {error $reply}
    set tree $::application::analysis::NumberToTree($number)
    ::scidb::test::actions::waitUntil {[info exists ::application::analysis::${tree}::Vars(pv:0)] && [set ::application::analysis::${tree}::Vars(pv:0)] ne {}}
    ::application::openPane analysis:$number
    update
    set engine [::engine::id $number]
    ::application::analysis::Pause $tree
    update
    ::scidb::engine::snapshot $engine clear
    upvar #0 ::application::analysis::${tree}::Vars vars
} -body {
    lassign [$tree item bbox Line0 Moves] x y r bottom
    ::application::analysis::PopupMenu $tree $number [expr {$x+4}] [expr {($y+$bottom)/2}]
    update
    set m $tree.__menu__
    set result [list [winfo ismapped $m] $vars(state:suspended) $vars(keep:active) $vars(current:item) [expr {[::scidb::engine::snapshot $engine san 0] ne {}}]]
    set before [$tree item element cget Line0 Moves elemTextFig -text]
    ::application::analysis::Display(pv) $tree 0 0 1 1 1 1 1 0 0 {d4 d5}
    lappend result [expr {[$tree item element cget Line0 Moves elemTextFig -text] eq $before}] [info exists vars(suspended,0)]
    ::scidb::test::preserve::unpost $m
    lappend result $vars(state:suspended) $vars(keep:active) [llength [array names vars suspended,*]]
    lappend result [expr {[$tree item element cget Line0 Moves elemTextFig -text] eq [::font::translate {d4 d5}]}]
    set result
} -cleanup {
    catch {::scidb::test::preserve::unpost $tree.__menu__}
    catch {destroy $tree.__menu__}
    if {$vars(engine:pause)} { ::application::analysis::Pause $tree }
    ::action::run stop_engine
    update
} -result {1 1 1 1 1 1 1 0 0 0 1}

tcltest::test context-preserve-c8 {right click activates the clicked row and unpost restores pointer selection} -setup {
    set base [::scidb::test::actions::fixture]
    ::application::database::openBase .application $base no
    ::action::run open_game {number 1 move 0}
    ::scidb::game::go start
    set savedTree [::scidb::tree::get]
    ::scidb::tree::set $base
    ::application::openPane tree
    set table $::application::tree::Vars(table)
    ::application::tree::DoSearch $table
    ::scidb::test::actions::waitUntil {[llength $::application::tree::Vars(data)] > 0 && [winfo viewable $table.t]}
    update
} -body {
    lassign [$table.t item bbox 0] x y r bottom
    ::table::select $table none
    ::application::tree::PopupMenu $table [expr {[winfo rootx $table.t]+$x+4}] [expr {[winfo rooty $table.t]+($y+$bottom)/2}]
    update
    set m $table.popup_menu
    set active [::table::active $table]
    # Move outside the table while the menu owns pointer tracking. On
    # dismissal doSelection must clear the old row's hover activation.
    event generate .application <Motion> -warp 1 -x 1 -y 1
    ::scidb::test::preserve::unpost $m
    list $active [::table::active $table] [::table::selection $table]
} -cleanup {
    catch {destroy $table.popup_menu}
    ::scidb::tree::set $savedTree
} -result {0 -1 -1}

tcltest::cleanupTests
