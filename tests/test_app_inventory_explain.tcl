package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::gameexplain {
    variable messages {}
    proc wait {} {
        set deadline [expr {[clock milliseconds]+10000}]
        while {[::application::ai::busy?]} {
            update
            if {[clock milliseconds]>$deadline} {error {explanation did not finish}}
            after 10
        }
        update
    }
}

tcltest::test inventory-game-explain {typed and native menu actions explain the real loaded PGN through checked generation into the report} -setup {
    ::scidb::test::actions::ready
    ::knowledge::Ensure
    set pgn [::scidb::test::actions::fixture]
    ::knowledge::RunAction open_database [list path $pgn]
    ::knowledge::RunAction open_game {number 1}
    set before [::scidb::game::toPGN original]
    set beforeFen [::scidb::pos::fen]
    set oldConfig [array get ::application::ai::Config]
    set notice $::application::ai::Settings(cloudNotice)
    set ::application::ai::Settings(cloudNotice) 1
    set ::application::ai::Config(provider) ollama
    set ::application::ai::Config(model) deepseek-v4.1-flash:cloud
    rename ::ai::provider::chatAsync ::ai::provider::chatAsync_gameexplain_saved
    proc ::ai::provider::chatAsync {messages tools callback} {
        lappend ::scidb::test::gameexplain::messages $messages
        after 0 [list {*}$callback [dict create ok 1 message [dict create role assistant content {A generated game explanation for practice.}]]]
        return generated-test-response
    }
    set ::scidb::test::gameexplain::messages {}
} -body {
    set reply [::knowledge::RunAction game.explain {}]
    ::scidb::test::gameexplain::wait
    set typedTitle $::application::report::Priv(title)
    set typedHtml [dict get $::application::report::Priv(data) html]
    set bar [::application::pgn::gamebar]
    menu .explainprobe -tearoff 0
    set id [expr {$::gamebar::Specs(size:$bar) == 1 ? $::gamebar::Specs(selected:$bar) : -1}]
    ::gamebar::BuildMenu $bar $id {} .explainprobe
    set found -1
    for {set i 0} {$i <= [.explainprobe index end]} {incr i} {
        if {[.explainprobe type $i] eq "command" && [.explainprobe entrycget $i -command] eq {::action::run game.explain}} {set found $i; break}
    }
    if {$found < 0} {error {native game-bar menu did not expose game.explain}}
    .explainprobe invoke $found
    ::scidb::test::gameexplain::wait
    set sameContext 1
    foreach messages $::scidb::test::gameexplain::messages {
        set prompt [dict get [lindex $messages 1] content]
        if {[string first [string trim $before] $prompt] < 0 || [string first {opening, the character of the play and the result} $prompt] < 0} {set sameContext 0}
    }
    list [expr {$reply eq {Game explanation requested.}}] [llength $::scidb::test::gameexplain::messages] $sameContext \
        [expr {$typedTitle eq {Explain game (grounded)}}] \
        [expr {[string first {A generated game explanation for practice.} $typedHtml] >= 0}] \
        [expr {[dict get $::application::report::Priv(data) html] eq $typedHtml}] \
        [winfo exists $::application::report::Priv(html)] \
        [expr {$before eq [::scidb::game::toPGN original]}] [expr {$beforeFen eq [::scidb::pos::fen]}] \
        [string match error:* [::knowledge::RunAction game.explain {unexpected value}]]
} -cleanup {
    catch {destroy .explainprobe}
    rename ::ai::provider::chatAsync {}
    rename ::ai::provider::chatAsync_gameexplain_saved ::ai::provider::chatAsync
    array set ::application::ai::Config $oldConfig
    set ::application::ai::Settings(cloudNotice) $notice
} -result {1 2 1 1 1 1 1 1 1 1}

tcltest::cleanupTests
