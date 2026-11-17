# A loaded game's style must retain the font chosen for its notation pane.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
set fontBase [::scidb::test::actions::fixture]
::action::run open_database [dict create path $fontBase]
::action::run open_game {number 1}
set fontTwm [::application::twm board]
set fontFrame [$fontTwm leaf editor]
proc paneFontActiveText {} {
    return $::application::pgn::Vars(pgn:[::scidb::game::current])
}
proc paneFontOtherText {w} {
    foreach child [winfo children $w] {
        if {[winfo class $child] eq "Text"} {return $child}
        set found [paneFontOtherText $child]
        if {$found ne {}} {return $found}
    }
    return {}
}
set otherText [paneFontOtherText [$fontTwm leaf analysis:1]]
set otherSize [font actual [$otherText cget -font] -size]
set initialSize [font actual [[paneFontActiveText] cget -font] -size]
::context::PaneFont [dict create paneUid editor frame $fontFrame] +1
set selectedSize [font actual [[paneFontActiveText] cget -font] -size]
tcltest::test pane-font-game-reload {loading a game retains actual notation size and leaves the other pane alone} -body {
    ::action::run open_game {number 1}
    update
    list [expr {$selectedSize == $initialSize+1}] \
        [font actual [[paneFontActiveText] cget -font] -size] \
        [expr {[font actual [$otherText cget -font] -size] == $otherSize}]
} -result [list 1 $selectedSize 1]
tcltest::test pane-font-style-refresh {notation style refresh retains widget and tag fonts in this pane} -body {
    set w [paneFontActiveText]
    set tagSize [font actual [$w tag cget main -font] -size]
    ::application::pgn::refresh
    update
    list [font actual [$w cget -font] -size] \
        [expr {[font actual [$w tag cget main -font] -size] == $tagSize}] \
        [expr {[font actual [$otherText cget -font] -size] == $otherSize}]
} -result [list $selectedSize 1 1]
::context::PaneFont [dict create paneUid editor frame $fontFrame] reset
unset -nocomplain ::font::Options(pane:editor:size)
::scidb::test::actions::cleanup
::scidb::test::actions::release
::tcltest::cleanupTests
