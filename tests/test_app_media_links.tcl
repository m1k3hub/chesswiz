package require tcltest 2.5

# ======================================================================
# Scidb App Test -- the game -> report media mapping is built in the
# background (::scidb::db::mediaLinkReady; LinksReady and LinksBuilt in
# tcl/app-media.tcl). On Mega Database 2010 the build once froze the GUI
# for minutes at every open and game change.
#
# The native test needs a ChessBase base with a .cbm companion:
# SCIDB_CBM_FIXTURE_DIR must hold "Festival Biel 2015.cbh" and its files.
# ======================================================================

set fixtureDir [expr {[info exists ::env(SCIDB_CBM_FIXTURE_DIR)] ? $::env(SCIDB_CBM_FIXTURE_DIR) : ""}]
set biel [file join $fixtureDir "Festival Biel 2015.cbh"]
tcltest::testConstraint cbmFixture [expr {$fixtureDir ne "" && [file exists $biel]}]

namespace eval ::medialinks {}

proc ::medialinks::stubReady {result} {
    rename ::scidb::db::mediaLinkReady ::medialinks::realReady
    proc ::scidb::db::mediaLinkReady {base variant cmd} [list return $result]
}
proc ::medialinks::unstubReady {} {
    rename ::scidb::db::mediaLinkReady {}
    rename ::medialinks::realReady ::scidb::db::mediaLinkReady
}
tcltest::test media-links-command {the readiness command exists} -body {
    llength [info commands ::scidb::db::mediaLinkReady]
} -result 1

tcltest::test media-links-wait {an unbuilt mapping shows the hint and remembers the base} -setup {
    ::medialinks::stubReady 0
    set saved [array get ::application::media::Priv]
} -body {
    list [::application::media::LinksReady /x/base.cbh Normal] \
        $::application::media::Priv(linksBase) \
        $::application::media::Priv(statusbar)
} -cleanup {
    ::medialinks::unstubReady
    array set ::application::media::Priv $saved
} -result {0 {/x/base.cbh Normal} {Indexing media links...}}

tcltest::test media-links-ready {a built mapping lets Update go on} -setup {
    ::medialinks::stubReady 1
    set saved [array get ::application::media::Priv]
    set ::application::media::Priv(linksBase) {}
} -body {
    list [::application::media::LinksReady /x/base.cbh Normal] \
        $::application::media::Priv(linksBase)
} -cleanup {
    ::medialinks::unstubReady
    array set ::application::media::Priv $saved
} -result {1 {}}

tcltest::test media-links-stale {a callback for a base the pane left is ignored} -setup {
    set saved [array get ::application::media::Priv]
    set ::application::media::Priv(linksBase) [list /x/other.cbh Normal]
    set ::application::media::Priv(afterid) {}
} -body {
    ::application::media::LinksBuilt /x/base.cbh Normal 1
    list $::application::media::Priv(linksBase) $::application::media::Priv(afterid)
} -cleanup {
    array set ::application::media::Priv $saved
} -result {{/x/other.cbh Normal} {}}

tcltest::test media-links-built {the awaited callback schedules Update once} -setup {
    set saved [array get ::application::media::Priv]
    set ::application::media::Priv(linksBase) [list /x/base.cbh Normal]
    set ::application::media::Priv(afterid) {}
} -body {
    ::application::media::LinksBuilt /x/base.cbh Normal 1
    set id $::application::media::Priv(afterid)
    set scheduled [expr {$id ne "" && $id in [after info]}]
    after cancel $id
    list $::application::media::Priv(linksBase) $scheduled
} -cleanup {
    array set ::application::media::Priv $saved
} -result {{} 1}

tcltest::test media-links-gone {a build whose base went away does not update} -setup {
    set saved [array get ::application::media::Priv]
    set ::application::media::Priv(linksBase) [list /x/base.cbh Normal]
    set ::application::media::Priv(afterid) {}
} -body {
    ::application::media::LinksBuilt /x/base.cbh Normal 0
    list $::application::media::Priv(linksBase) $::application::media::Priv(afterid)
} -cleanup {
    array set ::application::media::Priv $saved
} -result {{} {}}

tcltest::test media-links-small-base {a small base is mapped at once, as the synchronous build maps it} -constraints cbmFixture -setup {
    ::scidb::db::load $biel {apply {args {return 0}}} {} -encoding auto -readonly yes
} -body {
    set ready [::scidb::db::mediaLinkReady $biel Normal {error "no callback expected"}]
    set gallery [::scidb::db::mediaGallery $biel Normal]
    list $ready [llength $gallery] [::scidb::db::mediaLinkReady $biel Normal {error "no callback expected"}]
} -cleanup {
    ::scidb::db::close $biel
} -result {1 19 1}

rename ::medialinks::stubReady {}
rename ::medialinks::unstubReady {}
namespace delete ::medialinks
tcltest::cleanupTests
