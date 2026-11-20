# GAP-001 / GAP-002 (terminal review 6).
#
# The drop-down widget is built once and every cascade is (re)filled from
# live state when it posts.  These probes drive the real posting surface --
# $::application::Vars(menu:entries) -- and mutate product state between two
# posts, so a cached or frozen cascade fails even when a freshly built menu
# would look right.
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready

namespace eval ::mdl {
    variable Native ""
    variable NativePgn ""
    variable EngineNumber ""
    variable EngineName ""
    variable SavedEngines ""
    variable SavedEngineFile ""
    variable EngineFile ""
}

proc ::mdl::nop {args} {return 0}

# The live menu. Never rebuild a private menu for a state assertion: the bug
# this file guards was a cache that survived between posts of this widget.
proc ::mdl::menu {} {
    set m ""
    catch { set m $::application::Vars(menu:entries) }
    if {$m eq "" || ![winfo exists $m]} {
        ::application::BuildSettingsMenu .application.nb.menu_main
        set m $::application::Vars(menu:entries)
    }
    if {$m eq "" || ![winfo exists $m]} { error "the live drop-down was not built" }
    return $m
}

# Posting runs the real -postcommand (what Tk does when the cascade opens)
# and then the native post, so the menu is actually mapped while inspected.
proc ::mdl::Post {menu} {
    if {$menu eq "" || ![winfo exists $menu]} { return }
    set command ""
    catch { set command [$menu cget -postcommand] }
    if {$command ne ""} {
        if {[catch { uplevel #0 $command } err]} {
            error "postcommand of $menu failed: $err"
        }
    }
    if {[tk windowingsystem] eq "x11"} { catch { $menu post 20 20 } }
    update idletasks
}

proc ::mdl::Unpost {menu} {
    if {$menu eq "" || ![winfo exists $menu]} { return }
    catch { $menu unpost }
    catch { ::tk::MenuUnpost $menu }
    catch { grab release $menu }
}

proc ::mdl::Rows {menu} {
    set rows {}
    set last ""
    catch { set last [$menu index end] }
    if {$last eq "" || $last eq "none"} { return $rows }
    for {set i 0} {$i <= $last} {incr i} {
        set type [$menu type $i]
        if {$type eq "separator"} { continue }
        set label ""
        catch { set label [string trim [$menu entrycget $i -label]] }
        set state ""
        catch { set state [$menu entrycget $i -state] }
        set command ""
        catch { set command [$menu entrycget $i -command] }
        lappend rows [list $type $label $state $command]
    }
    return $rows
}

proc ::mdl::Labels {menu} {
    set out {}
    foreach row [::mdl::Rows $menu] { lappend out [lindex $row 1] }
    return $out
}

proc ::mdl::Row {menu label} {
    foreach row [::mdl::Rows $menu] {
        if {[lindex $row 1] eq $label} { return $row }
    }
    return {}
}

proc ::mdl::State {menu label} {
    set row [::mdl::Row $menu $label]
    if {![llength $row]} { return "missing" }
    return [lindex $row 2]
}

proc ::mdl::MCtext {name} {
    return [string trim [lindex [::menu::AmpText [::menu::MC $name]] 0]]
}

proc ::mdl::TopIndex {labelName} {
    set menu [::mdl::menu]
    set want [::mdl::MCtext $labelName]
    set last ""
    catch { set last [$menu index end] }
    for {set i 0} {$i <= $last} {incr i} {
        if {[$menu type $i] ne "cascade"} { continue }
        if {[string trim [$menu entrycget $i -label]] eq $want} { return $i }
    }
    return -1
}

proc ::mdl::TopMenu {labelName} {
    set menu [::mdl::menu]
    set index [::mdl::TopIndex $labelName]
    if {$index < 0} { error "top-level $labelName cascade is missing" }
    return [$menu entrycget $index -menu]
}

proc ::mdl::SubByLabel {menu label} {
    set last ""
    catch { set last [$menu index end] }
    if {$last eq "" || $last eq "none"} { return "" }
    for {set i 0} {$i <= $last} {incr i} {
        if {[$menu type $i] ne "cascade"} { continue }
        if {[string trim [$menu entrycget $i -label]] eq $label} {
            return [$menu entrycget $i -menu]
        }
    }
    return ""
}

# One writable native database per file, created through the real database
# API (the generated PGN fixture is not writable).
proc ::mdl::OpenNative {} {
    variable Native
    variable NativePgn
    if {$Native eq "" || ![file exists $Native]} {
        set NativePgn [::scidb::test::actions::fixture]
        set Native [file rootname $NativePgn].sci
        ::scidb::db::open $NativePgn ::mdl::nop {} ::mdl::nop {}
        ::scidb::db::new $Native Normal [::application::database::lookupType Unspecific]
        ::scidb::db::attach $Native $Native
        ::scidb::db::copy $NativePgn $Native {} ::mdl::nop {} ::mdl::nop {}
        ::scidb::db::save $Native ::mdl::nop {}
        ::scidb::db::close $Native
        ::scidb::db::close $NativePgn
    }
    set open 0
    catch { set open [::scidb::db::get open? $Native] }
    if {!$open} {
        ::action::run open_database [dict create path $Native]
        update
    }
    return $Native
}

proc ::mdl::CloseGame {} {
    catch { ::action::run menu.game.close }
    update
    ::scidb::test::actions::waitUntil {![::menu::GameLoaded]} 10000
}

proc ::mdl::QuestionYes {args} {return yes}

# Close through the posted File row. An open game or unsaved change puts a
# modal question in front of it, and nobody can answer a modal headless, so
# answer "yes" for exactly the duration of the close (the same technique the
# shared release helper uses between files).
proc ::mdl::CloseDatabase {base} {
    catch { ::scidb::db::set readonly $base 0 }
    ::mdl::CloseGame
    set open 0
    catch { set open [::scidb::db::get open? $base] }
    if {!$open} { return }
    set have [expr {[llength [info commands ::dialog::question]] > 0}]
    if {$have} {
        catch { rename ::dialog::question ::mdl::SavedQuestion }
        catch { rename ::mdl::QuestionYes ::dialog::question }
    }
    try {
        catch { ::action::run menu.file.close }
        update
    } finally {
        if {$have} {
            catch { rename ::dialog::question ::mdl::QuestionYes }
            catch { rename ::mdl::SavedQuestion ::dialog::question }
        }
    }
}

proc ::mdl::RestoreBoardFocus {} {
    catch { focus -force $::application::board::board }
    update
}

# A posted cascade is empty when its subtree has no real row. Placeholder
# labels left by the redesign are failures too, not exemptions.
proc ::mdl::WalkAll {menu path problemsVar} {
    upvar 1 $problemsVar problems
    if {$menu eq "" || ![winfo exists $menu]} {
        lappend problems [list missing $path]
        return
    }
    ::mdl::Post $menu
    set rows [::mdl::Rows $menu]
    if {![llength $rows]} { lappend problems [list empty $path] }
    foreach row $rows {
        if {[lindex $row 0] ni {command radiobutton checkbutton}} { continue }
        if {![string match {::action::run *} [string trim [lindex $row 3]]]} {
            lappend problems [list not-registry $path [lindex $row 1] [lindex $row 3]]
        }
    }
    set last ""
    catch { set last [$menu index end] }
    if {$last ne "" && $last ne "none"} {
        for {set i 0} {$i <= $last} {incr i} {
            if {[$menu type $i] ne "cascade"} { continue }
            set label [string trim [$menu entrycget $i -label]]
            if {[string match -nocase {*per toolbar checkbuttons*} $label]} {
                lappend problems [list placeholder $path $label]
                continue
            }
            set sub ""
            catch { set sub [$menu entrycget $i -menu] }
            if {$sub eq "" || ![winfo exists $sub]} {
                lappend problems [list empty-cascade $path $label]
                continue
            }
            ::mdl::WalkAll $sub "$path > $label" problems
        }
    }
    ::mdl::Unpost $menu
}

# ----------------------------------------------------------------------
# GAP-001: visibility/enablement follow live state on every post.
# ----------------------------------------------------------------------

tcltest::test md-live-file-database-open-close {File rows follow database open and close between two posts of the live menu} -setup {
    ::mdl::CloseGame
    set file [::mdl::TopMenu File]
    ::mdl::Post $file
    set before [::mdl::Labels $file]
} -body {
    set base [::mdl::OpenNative]
    ::mdl::Post $file
    set opened [::mdl::Labels $file]
    ::action::run menu.file.close
    update
    ::mdl::Post $file
    set closed [::mdl::Labels $file]
    list \
        [expr {"Close Database" in $before}] \
        [expr {"Close Database" in $opened}] \
        [expr {"Save Changes" in $opened}] \
        [expr {"Import" in $opened}] \
        [expr {"Export" in $opened}] \
        [expr {"Close Database" in $closed}] \
        [expr {"Save Changes" in $closed}] \
        [expr {"Import" in $closed}]
} -result {0 1 1 1 1 0 0 0} -cleanup {
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

tcltest::test md-live-file-readonly {File enablement follows the database's writable flag on each re-post} -setup {
    set base [::mdl::OpenNative]
    set file [::mdl::TopMenu File]
} -body {
    ::scidb::db::set readonly $base 1
    update
    ::mdl::Post $file
    set readonly [list \
        [::mdl::State $file "Save Changes"] \
        [::mdl::State $file "Create Database Archive\u2026"] \
        [::mdl::State $file "Import"] \
        [::mdl::State $file "Export"]]
    ::scidb::db::set readonly $base 0
    update
    ::mdl::Post $file
    set writable [list \
        [::mdl::State $file "Save Changes"] \
        [::mdl::State $file "Create Database Archive\u2026"]]
    list $readonly $writable
} -result {{disabled disabled normal normal} {normal normal}} -cleanup {
    catch {::scidb::db::set readonly $base 0}
}

tcltest::test md-live-game-load-close {Game > Save Game and the game-only groups follow load and close between posts} -setup {
    ::mdl::CloseGame
    set base [::mdl::OpenNative]
    set game [::mdl::TopMenu Game]
    ::mdl::Post $game
    set unloaded [::mdl::Labels $game]
} -body {
    ::action::run open_game {number 1}
    ::scidb::test::actions::waitUntil {[::menu::GameLoaded]} 10000
    ::mdl::Post $game
    set loaded [::mdl::Labels $game]
    set saveMenu [::mdl::SubByLabel $game "Save Game"]
    if {$saveMenu eq ""} {error {loaded game did not post Save Game}}
    ::mdl::Post $saveMenu
    set saveRows [llength [::mdl::Rows $saveMenu]]
    ::mdl::CloseGame
    ::mdl::Post $game
    set closed [::mdl::Labels $game]
    list \
        [expr {"Save Game" in $unloaded}] \
        [expr {"Close Game" in $unloaded}] \
        [expr {"Paste Game" in $unloaded}] \
        [expr {"Save Game" in $loaded}] \
        [expr {"Close Game" in $loaded}] \
        [expr {"Paste Game" in $loaded}] \
        [expr {$saveRows > 0}] \
        [expr {"Save Game" in $closed}] \
        [expr {"Close Game" in $closed}]
} -result {0 0 0 1 1 1 1 0 0} -cleanup {
    ::mdl::CloseGame
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

tcltest::test md-live-engine-label {Analysis posts Start Engine / Stop Engine from the live engine state} -setup {
    set ::mdl::SavedEngines $::engine::Engines
    set ::mdl::SavedEngineFile $::scidb::file::engines
    set ::mdl::EngineFile [file join [tcltest::temporaryDirectory] mdl-engines-[pid].dat]
    set ::engine::Engines {}
    set ::scidb::file::engines $::mdl::EngineFile
    set ::mdl::EngineName [::engine::install [::scidb::test::actions::engineProgram]]
    set analysis [::mdl::TopMenu Analysis]
} -body {
    set ::mdl::EngineNumber [::application::analysis::startEngine $::mdl::EngineName "" {lines 1}]
    ::scidb::test::actions::waitUntil {[llength [::application::analysis::Running]] > 0} 30000
    ::mdl::Post $analysis
    set running [::mdl::Labels $analysis]
    ::application::analysis::stopEngine $::mdl::EngineNumber
    ::scidb::test::actions::waitUntil {[llength [::application::analysis::Running]] == 0} 20000
    ::mdl::Post $analysis
    set stopped [::mdl::Labels $analysis]
    set ::mdl::EngineNumber ""
    list \
        [expr {"Stop Engine" in $running}] \
        [expr {"Start Engine" in $running}] \
        [expr {"Start Engine" in $stopped}] \
        [expr {"Stop Engine" in $stopped}]
} -result {1 0 1 0} -cleanup {
    if {$::mdl::EngineNumber ne ""} {catch {::application::analysis::stopEngine $::mdl::EngineNumber}}
    catch { ::application::analysis::stopEngine $::mdl::EngineName }
    if {$::mdl::EngineName ne ""} {catch { ::engine::kill $::mdl::EngineName }}
    catch { ::engine::log close }
    catch { file delete -force $::mdl::EngineFile }
    catch { set ::engine::Engines $::mdl::SavedEngines }
    catch { set ::scidb::file::engines $::mdl::SavedEngineFile }
    catch { ::options::hookWriter ::engine::WriteEngineOptions engines }
    set ::mdl::EngineNumber ""
    set ::mdl::EngineName ""
}

tcltest::test md-live-edit-focus {Edit rows follow the focused widget between two posts of the live menu} -setup {
    set edit [::mdl::TopMenu Edit]
    ::mdl::RestoreBoardFocus
} -body {
    ::mdl::Post $edit
    set board [::mdl::Labels $edit]
    set entry [::application::ask::Entry]
    if {![winfo exists $entry]} {error "the Ask entry is missing"}
    focus -force $entry
    update
    ::mdl::Post $edit
    set ask [::mdl::Labels $edit]
    list \
        [expr {"Edit annotation" in $board}] \
        [expr {"Edit comment after move" in $board}] \
        [expr {"Select All" in $board}] \
        [expr {"Copy" in $board}] \
        [expr {"Select All" in $ask}] \
        [expr {"Copy" in $ask}] \
        [expr {"Edit annotation" in $ask}] \
        [expr {"Edit comment after move" in $ask}]
} -result {1 1 0 0 1 1 0 0} -cleanup {
    ::mdl::RestoreBoardFocus
}

tcltest::test md-live-board-database-state {Board/Database cascade state is recomputed on every post of the live menu} -setup {
    set menu [::mdl::menu]
    set boardIndex [::mdl::TopIndex Board]
    set dbIndex [::mdl::TopIndex Database]
    if {$boardIndex < 0 || $dbIndex < 0} {error "Board/Database top cascades are missing"}
} -body {
    ::application::switchTab board
    update
    ::mdl::Post $menu
    set onBoard [list [$menu entrycget $boardIndex -state] [$menu entrycget $dbIndex -state]]
    ::application::switchTab database
    update
    ::mdl::Post $menu
    set onDatabase [list [$menu entrycget $boardIndex -state] [$menu entrycget $dbIndex -state]]
    ::application::switchTab board
    update
    ::mdl::Post $menu
    set back [list [$menu entrycget $boardIndex -state] [$menu entrycget $dbIndex -state]]
    list $onBoard $onDatabase $back
} -result {{normal normal} {disabled normal} {normal normal}} -cleanup {
    ::application::switchTab board
    update
}

# ----------------------------------------------------------------------
# GAP-002: every dynamic submenu posts real content.
# ----------------------------------------------------------------------

tcltest::test md-live-every-cascade {with a database and a game loaded every posted cascade carries real rows} -setup {
    set base [::mdl::OpenNative]
    if {![::menu::GameLoaded]} {
        ::action::run open_game {number 1}
        ::scidb::test::actions::waitUntil {[::menu::GameLoaded]} 10000
    }
} -body {
    set problems {}
    ::mdl::WalkAll [::mdl::menu] root problems
    set problems
} -result {} -cleanup {
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

# GAP-002 (terminal review 7): the empty recent list hid the direct
# openBase binding. With a real recent entry, every posted row (Open
# Recent included) must still dispatch through ::action::run.
tcltest::test md-live-populated-recent-rows {a populated recent-files list posts only registry actions and reopens via ::action::run} -setup {
    set base [::mdl::OpenNative]
    if {![::menu::GameLoaded]} {
        ::action::run open_game {number 1}
        ::scidb::test::actions::waitUntil {[::menu::GameLoaded]} 10000
    }
    set recent [::scidb::test::actions::fixture]
    ::action::run open_database [dict create path $recent]
    update
    catch { ::application::database::closeBase .application $recent }
    update
} -body {
    set recentCount [llength $::application::database::RecentFiles]
    set problems {}
    ::mdl::WalkAll [::mdl::menu] root problems
    set nonAction {}
    foreach problem $problems {
        if {[lindex $problem 0] eq "not-registry"} { lappend nonAction $problem }
    }
    # Also verify the toolbar -menucmd path and invoke a posted recent row.
    catch { destroy .mdlToolbarRecent }
    menu .mdlToolbarRecent -tearoff 0
    ::application::database::addRecentlyUsedToMenu .application .mdlToolbarRecent
    set rowCmd [.mdlToolbarRecent entrycget 0 -command]
    set isRecentAction [string match {::action::run menu.file.recent.open *} $rowCmd]
    set switcher [::application::database::switcherWidget]
    set wasOpen [$switcher contains? $recent]
    .mdlToolbarRecent invoke 0
    update
    set isOpen [$switcher contains? $recent]
    destroy .mdlToolbarRecent
    catch { ::application::database::closeBase .application $recent }
    update
    list [expr {$recentCount > 0}] $nonAction $isRecentAction $wasOpen $isOpen
} -result {1 {} 1 0 1} -cleanup {
    catch { destroy .mdlToolbarRecent }
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

tcltest::test md-live-newgame {Game > New Game posts the registered variant rows} -setup {
    set base [::mdl::OpenNative]
    set game [::mdl::TopMenu Game]
    ::mdl::Post $game
    set newGame [::mdl::SubByLabel $game [::mdl::MCtext NewGame]]
} -body {

    if {$newGame eq ""} {error "Game > New Game was not posted"}
    ::mdl::Post $newGame
    set rows [::mdl::Rows $newGame]
    set ids {}
    set bad {}
    foreach row $rows {
        if {[regexp {^::action::run (\S+)$} [lindex $row 3] -> id]} {
            lappend ids $id
            if {![string match game.new.* $id]} {lappend bad $id}
        } else {
            lappend bad [lindex $row 3]
        }
    }
    list [llength $rows] [llength $ids] $bad
} -result {6 6 {}} -cleanup {
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

tcltest::test md-live-repertoire {Save Game > Add to Repertoire / Add Line to Repertoire post real, registered rows} -setup {
    set base [::mdl::OpenNative]
    if {![::menu::GameLoaded]} {
        ::action::run open_game {number 1}
        ::scidb::test::actions::waitUntil {[::menu::GameLoaded]} 10000
    }
    set game [::mdl::TopMenu Game]
    ::mdl::Post $game
    set save [::mdl::SubByLabel $game "Save Game"]
} -body {

    if {$save eq ""} {error {Save Game was not posted}}
    ::mdl::Post $save
    # The workspace can still hold writable opening databases left by an
    # earlier file: with one, the submenu posts a destination command; with
    # several, it posts a nested destination cascade. Both are real rows,
    # so the probe checks content and registry dispatch, not one shape.
    set out {}
    foreach name {{Add to Repertoire} {Add Line to Repertoire}} {
        set sub [::mdl::SubByLabel $save $name]
        if {$sub eq ""} {lappend out [list $name missing]; continue}
        set problems {}
        ::mdl::WalkAll $sub $name problems
        lappend out [list [expr {[llength [::mdl::Rows $sub]] > 0}] [llength $problems]]
    }
    list {*}$out
} -result {{1 0} {1 0}} -cleanup {
    if {[info exists base]} {::mdl::CloseDatabase $base}
}

tcltest::test md-live-board-appearance {annotation timeout and sliding-variation fillers post real registered rows} -setup {
    set board [::mdl::TopMenu Board]
    ::mdl::Post $board
    set appearance [::mdl::SubByLabel $board "Appearance"]
    if {$appearance eq ""} {error "Board > Appearance was not posted"}
    ::mdl::Post $appearance
} -body {

    set out {}
    foreach name {{annotation timeout} {sliding variation pane}} {
        set sub [::mdl::SubByLabel $appearance $name]
        if {$sub eq ""} {lappend out [list $name missing]; continue}
        ::mdl::Post $sub
        set rows [::mdl::Rows $sub]
        set ok 1
        foreach row $rows {
            if {![regexp {^::action::run board\.display } [lindex $row 3]]} {set ok 0}
        }
        lappend out [list [llength $rows] $ok]
    }
    set out
} -result {{9 1} {5 1}}

tcltest::test md-live-toolbars {View > Toolbars posts the real per-toolbar checkbuttons through the registry} -setup {
    set view [::mdl::TopMenu View]
    ::mdl::Post $view
    set toolbars [::mdl::SubByLabel $view [::mdl::MCtext Toolbars]]
} -body {

    if {$toolbars eq ""} {error "View > Toolbars was not posted"}
    ::mdl::Post $toolbars
    set rows [::mdl::Rows $toolbars]
    set expected 0
    foreach parent [::toolbar::activeParents] {
        incr expected [llength $::toolbar::Specs(toolbars:$parent)]
    }
    set ids {}
    set bad {}
    foreach row $rows {
        if {[lindex $row 0] ne "checkbutton"} {lappend bad [list type [lindex $row 0]]}
        if {[regexp {^::action::run (\S+)} [lindex $row 3] -> id]} {
            lappend ids $id
            if {$id ne "toolbar.toggle"} {lappend bad $id}
        } else {
            lappend bad [lindex $row 3]
        }
    }
    list [expr {[llength $rows] > 0}] [expr {[llength $rows] == $expected}] $bad
} -result {1 1 {}}

tcltest::test md-live-promoted-mark {promoted-piece mark posts for a Crazyhouse game and disappears for a normal one} -setup {
    set board [::mdl::TopMenu Board]
    ::mdl::Post $board
    set appearance [::mdl::SubByLabel $board "Appearance"]
    ::mdl::Post $appearance
} -body {

    ::action::run game.new.crazy
    ::scidb::test::actions::waitUntil {[::scidb::game::query variant?] eq "Crazyhouse"} 10000
    ::mdl::Post $appearance
    set promoted [::mdl::SubByLabel $appearance "promoted-piece mark"]
    set posted [expr {$promoted ne ""}]
    set count 0
    set ok 1
    if {$posted} {
        ::mdl::Post $promoted
        set rows [::mdl::Rows $promoted]
        set count [llength $rows]
        foreach row $rows {
            if {![regexp {^::action::run board\.display } [lindex $row 3]]} {set ok 0}
        }
    }
    ::action::run menu.game.close
    update
    ::mdl::Post $appearance
    set hidden [expr {[::mdl::SubByLabel $appearance "promoted-piece mark"] eq ""}]
    list $posted $count $ok $hidden
} -result {1 4 1 1} -cleanup {
    ::mdl::CloseGame
}

::scidb::test::actions::release
::tcltest::cleanupTests
