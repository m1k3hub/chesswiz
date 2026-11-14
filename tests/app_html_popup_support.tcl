# Native popup census shared by REG-002 and effect regressions.
namespace eval ::scidb::test::htmlpop {variable rows {};variable mapped {};variable timer {};variable done 0}
proc ::scidb::test::htmlpop::descendants {w} {
    set result [list $w]
    foreach child [winfo children $w] {lappend result {*}[descendants $child]}
    return $result
}
proc ::scidb::test::htmlpop::walk {menu surface} {
    variable rows
    if {[$menu index end] in {{} none}} {return}
    for {set i 0} {$i <= [$menu index end]} {incr i} {
        set type [$menu type $i]
        if {$type eq "cascade"} {walk [$menu entrycget $i -menu] $surface;continue}
        if {$type ni {command radiobutton checkbutton}} {continue}
        set command [$menu entrycget $i -command]
        # Header rows are decorative and explicitly styled as headers.
        if {$command eq {} && $type eq "command"
            && [$menu entrycget $i -font] eq $::table::options(menu:headerfont)} {continue}
        lappend rows [list $surface $type [$menu entrycget $i -state] [$menu entrycget $i -label] $command]
    }
}
proc ::scidb::test::htmlpop::inspect {surface} {
    variable mapped
    variable done
    foreach w [descendants .] {
        if {[winfo class $w] eq "Menu" && [winfo ismapped $w]} {
            lappend mapped $w
            walk $w $surface
        }
    }
    foreach w $mapped {catch {::tk::MenuUnpost $w};catch {$w unpost}}
    catch {grab release [grab current]}
    set done 1
}
proc ::scidb::test::htmlpop::capture {surface script} {
    variable rows {};variable mapped {};variable done 0;variable timer
    set timer [after 200 [list [namespace current]::inspect $surface]]
    set code [catch {uplevel 1 $script} result options]
    if {!$done && !$code} {vwait [namespace current]::done}
    after cancel $timer
    if {$code} {return -options $options $result}
    if {![llength $mapped]} {error "$surface did not post a native menu"}
    puts [list HTML_DRAWABLE_CENSUS surface $surface mapped $mapped rows [llength $rows] exemptions 0]
    foreach row $rows {
        set cmd [lindex $row 4]
        if {[lindex $cmd 0] ne "::action::run"} {error "raw $surface row: $row"}
        ::action::get [lindex $cmd 1]
        puts [list HTML_DRAWABLE_ROW {*}$row]
    }
    return $rows
}
proc ::scidb::test::htmlpop::click {target} {
    event generate $target <Motion> -warp 1 -x 30 -y 30
    update
    event generate $target <ButtonPress-3> -x 30 -y 30
}
proc ::scidb::test::htmlpop::card {base} {
    set dlg [::playercard::show $base Normal 0 white]
    update
    if {$dlg eq {}} {
        foreach w [winfo children .application] {
            if {[string match .application.__card__* $w] && [winfo exists $w.content]} {set dlg $w;break}
        }
    }
    return $dlg
}
proc ::scidb::test::htmlpop::cardRows {base {developer 0}} {
    set dlg [card $base]
    set old $::application::assistant::Priv(debug)
    set ::application::assistant::Priv(debug) $developer
    try {
        set rows [capture playercard.html [list click [winfo parent [$dlg.content drawable]]]]
        set key {}
        foreach row $rows {
            if {[lindex [lindex $row 4] 1] eq "html.playercard.web"} {
                set key [dict get [lindex [lindex $row 4] 2] key];break
            }
        }
        if {$key eq {}} {error "card web rows missing"}
        set drawable [capture playercard.drawable [list ::playercard::PopupMenu $key]]
        return [list $dlg $rows $drawable $key]
    } finally {set ::application::assistant::Priv(debug) $old}
}
proc ::scidb::test::htmlpop::secondaryRows {base} {
    set result {}
    ::application::switchTab information
    update
    lappend result {*}[capture info {::application::information::Mouse3Down}]
    set tips [::tips::open .application]
    update
    try {
        lappend result {*}[capture tips [list click [winfo parent [$::tips::Priv(html) drawable]]]]
    } finally {destroy $tips}
    set help [::help::open .application Ask-Field]
    update
    try {
        lappend result {*}[capture help [list click [$::help::Priv(html) drawable]]]
        # The contents tree is a separate drawable branch of the same binding.
        set tree $::help::Priv(contents:tree)
        if {![winfo viewable $tree]} {::help::ToggleIndex;update}
        [winfo parent $tree] select $tree
        update
        lappend result {*}[capture help.tree [list click $tree.f.t]]
    } finally {::help::Destroy}
    set info [::scidb::db::get gameInfo 0 0 $base Normal]
    set nb [::overview::open .application $base Normal $info 0 0]
    update
    try {
        lappend result {*}[capture overview [list ::overview::PopupMenu $nb]]
    } finally {destroy [winfo toplevel $nb]}
    ::crosstable::open .application $base Normal 0 0 game
    update
    set dlg $::crosstable::Reuse
    try {
        lappend result {*}[capture crosstable.drawable [list ::crosstable::PopupMenu $dlg]]
        set html [set ::crosstable::${dlg}::Vars(html)]
        lappend result {*}[capture crosstable.html [list click [winfo parent [$html drawable]]]]
        foreach attr {rank game} {
            set nodes [$html search "\[$attr\]"]
            if {![llength $nodes]} {error "tournament $attr nodes missing"}
            lappend result {*}[capture crosstable.$attr [list ::crosstable::Mouse3Down $dlg [list [lindex $nodes 0]]]]
        }
    } finally {destroy $dlg}
    lappend result {*}[mergeRows]
    return $result
}
proc ::scidb::test::htmlpop::tournamentBase {} {
    set path [file join $::scidb::test::actions::Dir popup-tournament.pgn]
    if {![file exists $path]} {
        set f [open $path w]
        set names {{Generated White} {Generated Black} {Generated Gamma} {Generated Delta} {Generated Epsilon} {Generated Zeta}}
        set round 0
        foreach pair {{0 1} {0 2} {1 2} {1 3} {2 3} {3 4} {4 5} {0 3} {4 2}} {
            lassign $pair w b
            incr round
            puts $f "\[Event \"Generated Popup Tournament\"\]\n\[Site \"Generated\"\]\n\[Date \"2026.01.01\"\]\n\[Round \"$round\"\]\n\[White \"[lindex $names $w]\"\]\n\[Black \"[lindex $names $b]\"\]\n\[WhiteElo \"2400\"\]\n\[BlackElo \"2300\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n"
        }
        close $f
    }
    ::action::run open_database [dict create path $path]
    return $path
}
proc ::scidb::test::htmlpop::mergeRows {} {
    set base [tournamentBase]
    ::action::run open_game {number 1}
    ::merge::openDialog .application [::scidb::game::current] [list $base Normal -1 1]
    update
    try {
        return [capture merge {::merge::PopupMenu .mergeDialog}]
    } finally {destroy .mergeDialog;update}
}
