# Warm-cache transitions: no menu::state call or manual invalidation between reads.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
namespace eval ::scidb::test::asklive {}
proc ::scidb::test::asklive::has {id} {
    expr {$id in [lmap row [::action::labels asklist] {lindex $row 0}]}
}

foreach {variable id value} {
    DonateURLs menu.help.donate {PayPal https://example.org/donate}
    BugTracker menu.help.bug https://example.org/bug
    FeatureRequestTracker menu.help.feature https://example.org/feature
} {
    tcltest::test ask-live-url-$variable {Help URL changes update a warm Ask list in both directions} -setup {
        set saved [set ::menu::$variable]
        set ::menu::$variable $value
    } -body {
        set before [::scidb::test::asklive::has $id]
        set ::menu::$variable {}
        set absent [::scidb::test::asklive::has $id]
        set ::menu::$variable $value
        list $before $absent [::scidb::test::asklive::has $id]
    } -cleanup {
        set ::menu::$variable $saved
    } -result {1 0 1}
}

foreach {kind command id} {
    module ::ai::brief::ask menu.training.brief
    alias ::application::ai::explainSelection menu.analysis.explain.move
} {
    tcltest::test ask-live-command-$kind {actual module and alias entry points update warm rows} -setup {
        ::application::ai::configure -provider stub -model {}
        ::action::run open_database [list path [::scidb::test::actions::fixture]]
        ::scidb::test::askscope::NoGame
    } -body {
        set before [::scidb::test::asklive::has $id]
        rename $command ${command}__asklive
        set absent [::scidb::test::asklive::has $id]
        rename ${command}__asklive $command
        list $before $absent [::scidb::test::asklive::has $id]
    } -cleanup {
        if {[llength [info commands ${command}__asklive]]} {rename ${command}__asklive $command}
    } -result {1 0 1}
}

tcltest::test ask-live-key {setKey changes readiness without changing provider or model} -setup {
    ::scidb::test::askscope::NoGame
    set savedKeys $::application::ai::Keys
    set savedConfig [array get ::application::ai::Config]
    set hadEnv [info exists ::env(ANTHROPIC_API_KEY)]
    if {$hadEnv} {set savedEnv $::env(ANTHROPIC_API_KEY)}
    set ::env(ANTHROPIC_API_KEY) {}
    # Isolate OS credential persistence, not readiness, setKey or the registry.
    rename ::application::ai::CredentialStore ::application::ai::CredentialStore__asklive
    proc ::application::ai::CredentialStore {} {return 0}
    ::application::ai::configure -provider anthropic -model claude-test
    ::application::ai::setKey anthropic {}
} -body {
    set before [::scidb::test::asklive::has menu.analysis.explain.position]
    ::application::ai::setKey anthropic test-only-not-a-credential
    set ready [::scidb::test::asklive::has menu.analysis.explain.position]
    ::application::ai::setKey anthropic {}
    list $before $ready [::scidb::test::asklive::has menu.analysis.explain.position]
} -cleanup {
    set ::application::ai::Keys $savedKeys
    array set ::application::ai::Config $savedConfig
    ::ai::provider::configure -keys $savedKeys
    rename ::application::ai::CredentialStore {}
    rename ::application::ai::CredentialStore__asklive ::application::ai::CredentialStore
    if {$hadEnv} {set ::env(ANTHROPIC_API_KEY) $savedEnv} else {unset ::env(ANTHROPIC_API_KEY)}
} -result {0 1 0}

tcltest::test ask-live-media {playback state changes update the real media.stop predicate} -setup {
    set saved $::application::media::Priv(inprocess)
} -body {
    set states {}
    foreach playing {0 1 0} {
        set ::application::media::Priv(inprocess) $playing
        lappend states [::scidb::test::asklive::has media.stop]
    }
    set states
} -cleanup {
    set ::application::media::Priv(inprocess) $saved
} -result {0 1 0}

tcltest::test ask-live-new-predicate {new predicates need no cache-specific mutation hooks} -setup {
    set ::scidb::test::asklive::flag 1
    ::action::register test.asklive [dict create label {Live test} handler list what {} object {} doc {} enabled {set ::scidb::test::asklive::flag}]
} -body {
    set states {}
    foreach value {1 0 1} {
        set ::scidb::test::asklive::flag $value
        lappend states [::scidb::test::asklive::has test.asklive]
    }
    set states
} -cleanup {
    dict unset ::action::Registry test.asklive
    unset ::scidb::test::asklive::flag
} -result {1 0 1}

tcltest::test ask-live-cache-check {debug self-check detects an inconsistent cached row set} -body {
    ::action::labels asklist
    ::action::labels asklist
    set savedRows $::action::AskCachedRows
    set ::action::AskCachedRows {}
    set ::action::AskCacheCheck 1
    set code [catch {::action::labels asklist} message]
    list $code $message
} -cleanup {
    set ::action::AskCachedRows $savedRows
    unset ::action::AskCacheCheck
    ::action::InvalidateAskRows
} -result {1 {Ask cache disagrees with live menu state}}

::tcltest::cleanupTests
