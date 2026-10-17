package require tcltest 2.5

tcltest::test media-runtime {media modules are loaded together} -body {
    list [namespace exists ::application::media] \
        [namespace exists ::media::sync] \
        [namespace exists ::media::lesson] \
        [namespace exists ::media::decoder]
} -result {1 1 1 1}

tcltest::test media-layout {media pane has options and priority, and is omitted from the default layout} -body {
    list [info exists ::application::PaneOptions(media)] \
        [info exists ::application::Prios(media)] \
        [string match {*frame media*} $::application::BoardLayout]
} -result {1 1 0}

tcltest::test media-saved-layout {a saved layout containing the media pane loads and docks it} -setup {
    set twm [::application::twm board]
    set orig [::application::twm::inspectLayout $twm]
} -body {
    set saved [string map {{frame tree} {frame media {-width 400 -height 300 -minwidth 250 -minheight 200 -expand y} frame tree}} $orig]
    $twm load $saved
    update idletasks
    list [$twm isdocked media] [string match {*frame media*} [::application::twm::inspectLayout $twm]]
} -cleanup {
    $twm load $orig
    update idletasks
} -result {1 1}

tcltest::test media-withdrawn-layout {media cannot be offered by the board layout} -body {
    list [info exists ::application::PaneOptions(gamemedia)] \
        [info exists ::application::Prios(gamemedia)] \
        [string match *gamemedia* $::application::BoardLayout]
} -result {0 0 0}

tcltest::test media-pane-label {the media pane has a layout-menu label} -body {
    list [info exists ::application::twm::mc::Pane(media)] \
        [expr {[string length [::application::twm::PaneLabel media]] > 0}]
} -result {1 1}

tcltest::test pane-label-fallback {an unlabeled pane falls back to its uid} -body {
    ::application::twm::PaneLabel no_such_pane_xyz
} -result {no_such_pane_xyz}

tcltest::cleanupTests
