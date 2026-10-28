package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::secondary {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} { error $result }
        return $result
    }
}
tcltest::test secondary-browser-size {native browser resize changes the actual board and rejects missing browsers} -setup {
    ::scidb::test::actions::ready
    set pgn [::scidb::test::actions::fixture]
    ::scidb::test::secondary::call open_database path $pgn
    set base [::scidb::db::get name]
    ::browser::open .application $base Normal {} 0 0
    update
} -body {
    set positions {}
    foreach ns [namespace children ::browser] {
        set pos [namespace tail $ns]
        if {[string is integer -strict $pos] && [info exists ${ns}::Vars(board)]} { lappend positions $pos }
    }
    set position [lindex $positions 0]
    upvar #0 ::browser::${position}::Vars vars
    set windows [wm stackorder .]
    set display [::scidb::test::secondary::call browser.display position $position columns 1 notation san]
    if {[dict get $display columns] != 1 || [dict get $display notation] ne "san" || [wm stackorder .] ne $windows} {error "browser style did not apply directly"}
    if {![string match error:* [::knowledge::RunAction browser.display [list position $position notation Invalid]]]} {error "invalid notation accepted"}
    set before $vars(board:size)
    set small [::scidb::test::secondary::call browser.size position $position mode min]
    set large [::scidb::test::secondary::call browser.size position $position mode +5]
    set maximum [::scidb::test::secondary::call browser.size position $position mode max]
    set reduced [::scidb::test::secondary::call browser.size position $position mode -5]
    list [expr {$large>$small}] [expr {$maximum>=$large}] [expr {$reduced<$maximum}] \
        [string match error:* [::knowledge::RunAction browser.size {position 999 mode min}]]
} -cleanup {
    if {[info exists vars(board)]} { destroy [winfo toplevel $vars(board)] }
} -result {1 1 1 1}

tcltest::test secondary-gamebar {native game-bar controls apply idempotently without opening windows} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::secondary::call new_game
    set old [array get ::gamebar::Options]
    set windows [wm stackorder .]
} -body {
    set first [::scidb::test::secondary::call gamebar.display alignment center separate_header 1 active_bottom 1 separate_lines 1]
    set repeat [::scidb::test::secondary::call gamebar.display alignment center separate_header 1 active_bottom 1 separate_lines 1]
    set second [::scidb::test::secondary::call gamebar.display alignment left separate_header 0 active_bottom 0 separate_lines 0]
    list $first [expr {$repeat eq $first}] $second [expr {[wm stackorder .] eq $windows}] \
        [string match error:* [::knowledge::RunAction gamebar.display {gamebar .absent}]]
} -cleanup {array set ::gamebar::Options $old} -result {{alignment center separate_header 1 active_bottom 1 separate_lines 1} 1 {alignment left separate_header 0 active_bottom 0 separate_lines 0} 1 1}

tcltest::test secondary-toolbar {native toolbar visibility, float, docking, sizing, alignment and expansion} -setup {
    ::scidb::test::actions::ready
    toplevel .secondarytoolbar
    wm geometry .secondarytoolbar 600x300
    ::toolbar::setup .secondarytoolbar -id secondary-test
    set tb [::toolbar::toolbar .secondarytoolbar -id generated -hide 1 -title Generated]
    ::toolbar::add $tb button -text Generated
    update
} -body {
    set listed [::scidb::test::secondary::call toolbar.configure]
    set states {}
    foreach state {hide show flat show float show} {
        ::scidb::test::secondary::call toolbar.configure toolbar $tb state $state
        update
        lappend states $::toolbar::Specs(state:$tb)
    }
    set sides {}
    foreach side {bottom left right top} {
        lappend sides [dict get [::scidb::test::secondary::call toolbar.configure toolbar $tb side $side] side]
        update
    }
    set sizes {}
    foreach size {small medium large default} {
        lappend sizes [dict get [::scidb::test::secondary::call toolbar.configure toolbar $tb icons $size] icons]
    }
    set alignments {}
    foreach alignment {right center left} {
        lappend alignments [dict get [::scidb::test::secondary::call toolbar.frame toolbar $tb alignment $alignment expand 1] alignment]
    }
    list [expr {$tb in $listed}] $states $sides $sizes $alignments \
        [string match error:* [::knowledge::RunAction toolbar.configure {toolbar .absent state show}]]
} -cleanup {update; destroy .secondarytoolbar; update} -result {1 {hide show flat show float float} {bottom left right top} {small medium large default} {right center left} 1}

tcltest::test secondary-database {native description/type settings and recent removal bypass dialogs and preserve files} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) secondarydb]
    file mkdir $dir
    set base [file join $dir generated.sci]
    set windows [wm stackorder .]
} -body {
    ::scidb::test::secondary::call menu.file.new.normal filename $base
    set description [::scidb::test::secondary::call database.description base $base description {Generated description}]
    set read [::scidb::test::secondary::call database.description base $base]
    set types {}
    foreach type {Openings OpeningsWhite OpeningsBlack} {
        ::scidb::test::secondary::call database.repertoire_type base $base type $type
        lappend types [::scidb::db::get type $base]
    }
    set removed [::scidb::test::secondary::call database.recent_remove path $base]
    set repeat [::scidb::test::secondary::call database.recent_remove path $base]
    list $description $read [llength [lsort -unique $types]] [dict get $removed removed] [dict get $repeat removed] \
        [file exists $base] [::scidb::db::get open? $base] [expr {[wm stackorder .] eq $windows}] \
        [string match error:* [::knowledge::RunAction database.description {base absent description Nope}]]
} -cleanup {
    catch {::application::database::closeBase .application $base}
    file delete -force $dir
} -result {{Generated description} {Generated description} 3 1 0 1 1 1 1}

tcltest::test secondary-game-lock {native locking protects a game and permits explicit unlock} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::secondary::call new_game
    set slot [::scidb::game::current]
    ::scidb::game::modified $slot false
    set bar [::application::pgn::gamebar]
} -body {
    set locked [::scidb::test::secondary::call gamebar.lock slot $slot locked 1]
    set repeat [::scidb::test::secondary::call gamebar.lock slot $slot locked 1]
    set unlocked [::scidb::test::secondary::call gamebar.lock slot $slot locked 0]
    list $locked $repeat $unlocked [string match error:* [::knowledge::RunAction gamebar.lock {slot 999 locked 1}]]
} -result {1 1 0 1}

tcltest::test secondary-picker {real picker navigation, history, layouts, hidden files and persistent bookmark operations} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) picker]
    file mkdir [file join $dir child]
    set f [open [file join $dir .hidden] w]; puts $f hidden; close $f
    set oldBookmarks $::fsbox::bookmarks::Bookmarks(user)
    set oldLayout $::fsbox::Options(show:layout)
    toplevel .secondarypicker
    ::fsbox::fsbox .secondarypicker.picker open -initialdir $dir
    pack .secondarypicker.picker -fill both -expand 1
    update
    set w .secondarypicker.picker
} -body {
    set listed [::scidb::test::secondary::call files.picker]
    ::scidb::test::secondary::call files.picker widget $w operation directory path [file join $dir child]
    set back [::scidb::test::secondary::call files.picker widget $w operation back]
    set forward [::scidb::test::secondary::call files.picker widget $w operation forward]
    ::scidb::test::secondary::call files.picker widget $w operation directory path $dir
    set layouts {}
    foreach layout {list details list} {
        set result [::scidb::test::secondary::call files.picker widget $w operation layout layout $layout]
        upvar #0 ::fsbox::${w}::Vars vars
        lappend layouts [dict get $result layout] [$vars(widget:list:file) cget -showheader]
    }
    ::scidb::test::secondary::call files.picker widget $w operation hidden show 1
    set shown [lsearch -glob $vars(list:file) *hidden*]
    ::scidb::test::secondary::call files.picker widget $w operation hidden show 0
    set absent [lsearch -glob $vars(list:file) *hidden*]
    set add [::scidb::test::secondary::call files.bookmark operation add folder $dir name Generated]
    set again [::scidb::test::secondary::call files.bookmark operation add folder $dir name Generated]
    set renamed [::scidb::test::secondary::call files.bookmark operation rename folder $dir name Renamed]
    set removed [::scidb::test::secondary::call files.bookmark operation remove folder $dir]
    list [expr {$w in $listed}] [expr {[dict get $back folder] eq $dir}] \
        [expr {[dict get $forward folder] eq [file join $dir child]}] $layouts [expr {$shown>=0 && $absent<0}] \
        [expr {$add eq $again}] [lindex [lsearch -inline -index 0 $renamed $dir] 1] \
        [expr {[lsearch -index 0 $removed $dir]<0}] \
        [string match error:* [::knowledge::RunAction files.picker {widget .missing operation back}]]
} -cleanup {
    set ::fsbox::bookmarks::Bookmarks(user) $oldBookmarks
    set ::fsbox::Options(show:layout) $oldLayout
    destroy .secondarypicker
    file delete -force $dir
} -result {1 1 1 {list 0 details 1 list 0} 1 1 Renamed 1 1}

tcltest::cleanupTests
