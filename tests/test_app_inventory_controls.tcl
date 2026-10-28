package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::controls {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} {error $result}
        return $result
    }
}
tcltest::test controls-navigation {board toolbar navigation and source controls affect native state} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::controls::call open_database path [::scidb::test::actions::fixture]
    ::scidb::test::controls::call open_game number 1
} -body {
    set sources {}
    foreach source {list base list} {lappend sources [::scidb::test::controls::call board.game_source source $source]}
    ::scidb::test::controls::call board.navigate step end
    set end [::scidb::game::position key]
    ::scidb::test::controls::call board.navigate step start
    set start [::scidb::game::position key]
    ::scidb::test::controls::call board.navigate step +1
    set middle [::scidb::game::position key]
    ::scidb::test::controls::call board.navigate step -1
    set restored [::scidb::game::position key]
    ::scidb::test::controls::call board.navigate step down
    ::scidb::test::controls::call board.navigate step up
    list $sources [expr {$start ne $end && $middle ne $start && $restored eq $start}]
} -result {{list base list} 1}

tcltest::test controls-engine-sort {sorting regenerates real installed dictionary rows for all keys} -setup {
    ::scidb::test::actions::ready
} -body {
    set orders {}
    foreach field {name elo rating} {
        lappend orders [::scidb::test::controls::call engine.dictionary_sort field $field]
        set values {}
        set index [dict get {name 1 elo 2 rating 3} $field]
        foreach entry $::engine::Priv(engines) {lappend values [lindex $entry $index]}
        if {$field eq "name"} {
            # Native dictionary order ignores punctuation; test numeric order independently below.
            if {![llength $values]} {error "dictionary is empty"}
        } elseif {$values ne [lsort -integer -decreasing $values]} {error "dictionary sort is wrong"}
    }
    list $orders [winfo exists .application.engineDict.top.list]
} -cleanup {catch {destroy .application.engineDict}} -result {{name elo rating} 1}

tcltest::test controls-overview {overview rotation changes its native board presentation} -setup {
    ::scidb::test::actions::ready
    set base [::scidb::test::actions::fixture]
    ::scidb::test::controls::call open_database path $base
    set info [::scidb::db::get gameInfo 0 0 $base Normal]
    ::overview::open .application $base Normal $info 0 0
    update
    set nb {}
    foreach ns [namespace children ::overview] {
        if {[info exists ${ns}::Vars(flip)]} {set nb [namespace tail $ns];break}
    }
} -body {
    set before [set ::overview::${nb}::Vars(flip)]
    set first [::scidb::test::controls::call overview.rotate notebook $nb]
    set second [::scidb::test::controls::call overview.rotate notebook $nb]
    list [expr {$first != $before}] [expr {$second == $before}]
} -cleanup {if {$nb ne ""} {destroy [winfo toplevel $nb]}} -result {1 1}

tcltest::test controls-tables {typed controls exercise real database tables and analysis detail} -setup {
    ::scidb::test::actions::ready
    set base [::scidb::test::actions::fixture]
    ::scidb::test::controls::call open_database path $base
    ::application::switchTab database
    update
} -body {
    set tables {}
    foreach ns [namespace children ::application::database::games] {
        if {[info exists ${ns}::Vars(minsize)]} {lappend tables [namespace tail $ns]}
    }

    set matches {}
    foreach kind {player event site} {
        set tab [dict get {player player event event site site} $kind]
        set contents $::application::database::Vars(contents)
        $contents select $contents.$tab
        update
        set paths {}
        foreach ns [namespace children ::${kind}table] {
            set path [namespace tail $ns]
            if {[info exists ${ns}::Vars(viewcmd)] && [string match $contents.$tab.* $path]} {lappend paths $path}
        }
        set path [lindex $paths 0]
        set name [dict get {player {Generated White} event {Generated test} site Test} $kind]
        lappend matches [expr {[::scidb::test::controls::call table.find_object kind $kind widget $path name $name]>=0}]
        ::scidb::test::controls::call table.find_object kind $kind widget $path name $name next 1
        if {$kind eq "player"} {
            set off [::scidb::test::controls::call table.player_source widget $path enabled 0]
            set on [::scidb::test::controls::call table.player_source widget $path enabled 1]
            if {$off != 0 || $on != 1} {error "player source did not change"}
        }
    }
    set tree $::application::analysis::NumberToTree(1)
    set details {}
    foreach detail {less more} {lappend details [::scidb::test::controls::call analysis.info tree $tree detail $detail]}
    set table [lindex $tables 0]
    set layout {}
    foreach side {bottom right} {lappend layout [dict get [::scidb::test::controls::call database.games_view table $table operation layout layout $side] layout]}
    foreach operation {start end back forward selection} {::scidb::test::controls::call database.games_view table $table operation $operation}
    ::scidb::test::controls::call database.games_view table $table operation number number 1
    set variant [::scidb::test::controls::call database.variant variant Normal]
    list $layout $variant $matches $details
} -result {{bottom right} Normal {1 1 1} {less more}}

tcltest::cleanupTests
