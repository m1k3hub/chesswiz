package require tcltest 2.5

tcltest::test media-withdrawn-runtime {experimental media modules are not loaded} -body {
    list [namespace exists ::application::media] \
        [namespace exists ::media::sync] \
        [namespace exists ::media::lesson] \
        [namespace exists ::media::decoder]
} -result {0 0 0 0}

tcltest::test media-withdrawn-layout {media cannot be offered by the board layout} -body {
    list [info exists ::application::PaneOptions(gamemedia)] \
        [info exists ::application::Prios(gamemedia)] \
        [string match *gamemedia* $::application::BoardLayout]
} -result {0 0 0}

tcltest::cleanupTests
