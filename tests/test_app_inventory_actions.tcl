package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::inventory {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} { error $result }
        return $result
    }
}
tcltest::test inventory-trial {explicit trial state is idempotent and stopping restores the original position} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventory::call new_game
    set original [::scidb::pos::fen]
    set windows [wm stackorder .]
} -body {
    set start [::scidb::test::inventory::call game.trial enabled 1]
    set repeat [::scidb::test::inventory::call game.trial enabled 1]
    ::scidb::game::move e4
    ::scidb::game::position forward
    set moved [expr {[::scidb::pos::fen] ne $original}]
    set stop [::scidb::test::inventory::call game.trial enabled 0]
    ::scidb::test::inventory::call game.trial enabled 0
    list [dict get $start enabled] [dict get $repeat enabled] $moved [dict get $stop enabled] \
        [expr {[::scidb::pos::fen] eq $original}] [expr {[wm stackorder .] eq $windows}]
} -cleanup {
    if {[::game::trialMode?]} { ::game::flipTrialMode }
} -result {1 1 1 0 1 1}

tcltest::test inventory-3d {typed camera/theme/pieces change the native renderer, without a chooser} -setup {
    ::scidb::test::actions::ready
    set old [array get ::board3d::State]
    ::board3d::openViewer .application
    update
    set windows [wm stackorder .]
} -body {
    foreach view {white black side top} {
        ::scidb::test::inventory::call board3d.camera view $view
        lappend views $::board3d::State(view)
    }
    set themes [::scidb::test::inventory::call board3d.theme]
    set theme [lindex $themes 0]
    set selected [::scidb::test::inventory::call board3d.theme name $theme]
    foreach style {realistic3d vector photos glyphs} {
        lappend styles [::scidb::test::inventory::call board3d.pieces style $style]
    }
    update
    list $views $styles [expr {$selected eq $theme}] \
        [expr {[llength [.application.__board3d__.canvas find withtag tile]]>=64}] \
        [expr {[wm stackorder .] eq $windows}] \
        [string match error:* [::knowledge::RunAction board3d.theme {name MissingGeneratedTheme}]] \
        [string match error:* [::knowledge::RunAction board3d.camera {view arbitrary}]]
} -cleanup {
    catch {destroy .application.__board3d__}
    array set ::board3d::State $old
    unset -nocomplain views styles
} -result {{white black side top} {realistic3d vector photos glyphs} 1 1 1 1 1}

tcltest::test inventory-column {column sizing calls the real table API and rejects absent targets} -setup {
    ::scidb::test::actions::ready
    toplevel .inventorytable
    ::table::table .inventorytable.table
    ::table::addcol .inventorytable.table generated -text {Generated column heading} -width 200
    pack .inventorytable.table -fill both -expand 1
    update
} -body {
    set results {}
    foreach operation {optimize fit shrink expand} {
        lappend results [catch {::scidb::test::inventory::call table.column_size table .inventorytable.table column generated operation $operation} message]
        if {[lindex $results end]} {puts "COLUMN ERROR: $message"}
    }
    list $results \
        [string match error:* [::knowledge::RunAction table.column_size {table .absent column generated operation fit}]] \
        [string match error:* [::knowledge::RunAction table.column_size {table .inventorytable.table column absent operation fit}]]
} -cleanup {destroy .inventorytable} -result {{0 0 0 0} 1 1}

tcltest::test inventory-transpose {transpose uses a trial copy and stopping restores the real original} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventory::call new_game
    ::scidb::game::move e4
    ::scidb::game::position forward
    set original [::scidb::pos::fen]
} -body {
    set transposed [::scidb::test::inventory::call game.transpose]
    ::scidb::test::inventory::call game.trial enabled 0
    list [dict get $transposed enabled] [expr {[dict get $transposed fen] ne $original}] [expr {[::scidb::pos::fen] eq $original}]
} -cleanup {
    if {[::game::trialMode?]} {::game::flipTrialMode}
} -result {1 1 1}

tcltest::test inventory-variation {the operator reorders a real variation and keeps its branch position} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventory::call new_game
    ::scidb::game::import [::scidb::game::current] {1. e4 e5 (1... c5) (1... e6) *} {} {} -encoding utf-8 -variation 0
    ::scidb::game::go start
    ::scidb::game::position forward
} -body {
    set before [::scidb::game::next moves [::scidb::game::current] -ascii]
    ::scidb::test::inventory::call game.variation_first number 2
    set after [::scidb::game::next moves [::scidb::game::current] -ascii]
    list [expr {$before ne $after}] [::scidb::game::variation count] [string match error:* [::knowledge::RunAction game.variation_first {number -1}]]
} -result {1 2 1}

tcltest::test inventory-tournament {typed configuration renders a real tournament table and exports HTML without a chooser} -setup {
    ::scidb::test::actions::ready
    set pgn [::scidb::test::actions::fixture]
    ::scidb::test::inventory::call open_database path $pgn
    set base [::scidb::db::get name]
    ::crosstable::open .application $base Normal 0 0 game
    update
    set dlg $::crosstable::Reuse
    set oldOptions [array get ::crosstable::Options]
    set file [file join $::env(HOME) tournament.html]
    file delete -force $file
    set windows [wm stackorder .]
} -body {
    set options [::scidb::test::inventory::call tournament.table padding 6 spacing 0 pyramid 1 rating 0 performance 0 tiebreak 0 winDrawLoss 1 opponent 0]
    set rendered [set ::crosstable::${dlg}::Vars(output:html)]
    ::scidb::test::inventory::call tournament.table operation export filename $file
    set f [open $file];set text [read $f];close $f
    set blocked [::knowledge::RunAction tournament.table [list operation export filename $file]]
    set invalid [::knowledge::RunAction tournament.table {padding 7}]
    list [dict get $options fmt:padding] [dict get $options show:rating] \
        [expr {[string length $rendered]>100}] [string match {*Generated*} $text] \
        [expr {[wm stackorder .] eq $windows}] [string match error:* $blocked] [string match error:* $invalid]
} -cleanup {
    array set ::crosstable::Options $oldOptions
    catch {$dlg.close invoke}
    file delete -force $file
} -result {6 0 1 1 1 1 1}

tcltest::test inventory-display {board and notation options take explicit values and persist without new windows} -setup {
    ::scidb::test::actions::ready
    set boardOld [::scidb::test::inventory::call board.display]
    set notationOld [::scidb::test::inventory::call notation.display]
    set symbolsOld $::database::switcher::Options(iconsize)
    set windows [wm stackorder .]
} -body {
    set good 1
    foreach position {hidden bottom top right left} {
        set result [::scidb::test::inventory::call board.display sliding $position]
        if {[dict get $result sliding] ne $position} {set good 0}
    }
    foreach ms {0 1500 2000 2500 3000 3500 4000 4500 5000} {
        set result [::scidb::test::inventory::call board.display annotation_ms $ms]
        if {[dict get $result annotation_ms] != $ms} {set good 0}
    }
    foreach mark {none bullet star disk} {
        set result [::scidb::test::inventory::call board.display promoted $mark]
        if {[dict get $result promoted] ne $mark} {set good 0}
    }
    foreach value {0 1} {
        set result [::scidb::test::inventory::call notation.display columns $value moveinfo $value]
        if {$result ne [list columns $value moveinfo $value]} {set good 0}
    }
    foreach pixels {24 32 48} {
        if {[::scidb::test::inventory::call database.symbol_size pixels $pixels] != $pixels} {set good 0}
    }
    update
    list $good [expr {[wm stackorder .] eq $windows}] \
        [string match error:* [::knowledge::RunAction board.display {annotation_ms -1}]]
} -cleanup {
    ::scidb::test::inventory::call board.display {*}$boardOld
    ::scidb::test::inventory::call notation.display {*}$notationOld
    set ::database::switcher::Options(iconsize) $symbolsOld
} -result {1 1 1}

tcltest::test inventory-language {language toggle reaches native display state and rejects an unknown language} -setup {
    ::scidb::test::actions::ready
    set oldLanguages $::application::pgn::Vars(lang:active:en)
} -body {
    set a [::scidb::test::inventory::call notation.language language en]
    set b [::scidb::test::inventory::call notation.language language en]
    list [dict get $a language] [dict get $b language] [expr {[dict get $a enabled] != $oldLanguages && [dict get $b enabled] == $oldLanguages}] \
        [string match error:* [::knowledge::RunAction notation.language {language not-a-language}]]
} -cleanup {set ::application::pgn::Vars(lang:active:en) $oldLanguages} -result {en en 1 1}

tcltest::test inventory-undo {undo and redo change the actual game while focus is elsewhere} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventory::call new_game
    set original [::scidb::pos::fen]
    ::scidb::game::move e4
    ::scidb::game::position forward
    set moved [::scidb::pos::fen]
} -body {
    ::scidb::test::inventory::call game.undo operation undo
    set undone [::scidb::pos::fen]
    ::scidb::test::inventory::call game.undo operation redo
    list [expr {$original ne $moved}] [expr {$undone eq $original}] [expr {[::scidb::pos::fen] eq $moved}]
} -result {1 1 1}

tcltest::test inventory-tournament-controls {refresh/reset regenerate native HTML; trace windows and narration retain real event facts} -setup {
    ::scidb::test::actions::ready
    set pgn [::scidb::test::actions::fixture]
    ::scidb::test::inventory::call open_database path $pgn
    set base [::scidb::db::get name]
    ::crosstable::open .application $base Normal 0 0 game
    update
    set dlg $::crosstable::Reuse
    set oldOptions [array get ::crosstable::Options]
    rename ::ai::trend::narrate ::ai::trend::inventoryRealNarrate
    proc ::ai::trend::narrate {parent facts args} {set ::scidb::test::inventory::narration $facts}
} -body {
    set ::crosstable::${dlg}::Vars(output:html) SENTINEL
    ::scidb::test::inventory::call tournament.table operation refresh
    set refreshed [expr {[set ::crosstable::${dlg}::Vars(output:html)] ne "SENTINEL"}]
    set ::crosstable::${dlg}::Vars(output:html) SENTINEL
    ::scidb::test::inventory::call tournament.table operation reset
    set reset [expr {[set ::crosstable::${dlg}::Vars(output:html)] ne "SENTINEL"}]
    ::scidb::test::inventory::call tournament.table trace_html 1 trace_log 1
    update
    set traces [list [winfo exists $dlg.html] [winfo exists $dlg.log]]
    ::scidb::test::inventory::call tournament.table trace_html 0 trace_log 0
    update
    set closed [expr {![winfo exists $dlg.html] && ![winfo exists $dlg.log]}]
    set block [::scidb::test::inventory::call tournament.table operation narrate]
    list $refreshed $reset $traces $closed \
        [dict get $::scidb::test::inventory::narration games] \
        [string match {*Generated test*} $block] \
        [string match error:* [::knowledge::RunAction tournament.table {operation next window .absent}]]
} -cleanup {
    rename ::ai::trend::narrate {}
    rename ::ai::trend::inventoryRealNarrate ::ai::trend::narrate
    array set ::crosstable::Options $oldOptions
    catch {$dlg.close invoke}
} -result {1 1 {1 1} 1 1 1 1}

tcltest::cleanupTests
