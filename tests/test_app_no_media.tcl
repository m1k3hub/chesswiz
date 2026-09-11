package require tcltest 2.5

tcltest::test media-runtime {media modules are loaded together} -body {
    list [namespace exists ::application::media] \
        [namespace exists ::media::sync] \
        [namespace exists ::media::lesson] \
        [namespace exists ::media::decoder]
} -result {1 1 1 1}

tcltest::test media-layout {media pane has options, priority and a default layout entry} -body {
    list [info exists ::application::PaneOptions(media)] \
        [info exists ::application::Prios(media)] \
        [string match {*frame media*} $::application::BoardLayout]
} -result {1 1 1}

tcltest::test media-withdrawn-layout {media cannot be offered by the board layout} -body {
    list [info exists ::application::PaneOptions(gamemedia)] \
        [info exists ::application::Prios(gamemedia)] \
        [string match *gamemedia* $::application::BoardLayout]
} -result {0 0 0}

tcltest::cleanupTests
