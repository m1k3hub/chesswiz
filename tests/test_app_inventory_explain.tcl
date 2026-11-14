package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::gameexplain {
    variable messages {}
    proc wait {} {
        set deadline [expr {[clock milliseconds]+10000}]
        update
        while {[::application::ai::busy?] || $::application::assistant::Priv(busy)} {
            update
            if {[clock milliseconds]>$deadline} {error {explanation did not finish}}
            after 10
        }
        update
    }
}

tcltest::test inventory-game-explain {typed action and native game-tab Ask submission explain the real loaded PGN through checked generation into the report} -setup {
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
    set oldProvider [array get ::ai::provider::Config]
    set oldRoute $::application::assistant::RouteMode
    set ::application::assistant::RouteMode off
    set ::application::ai::Config(provider) ollama
    ::ai::provider::configure -name ollama
    rename ::ai::decide ::ai::decide_gameexplain_saved
    proc ::ai::decide {feature state question callback args} {
        after 0 [list {*}$callback {ok 1 label public confidence 1 source classifier}]
    }
    set ::application::ai::Config(model) deepseek-v4.1-flash:cloud
    rename ::ai::provider::chatAsync ::ai::provider::chatAsync_gameexplain_saved
    proc ::ai::provider::chatAsync {messages tools callback} {
        if {[lrange $callback 0 2] eq {::namespace inscope ::application::assistant}} {
            incr ::scidb::test::gameexplain::plannerCalls
            if {$::scidb::test::gameexplain::plannerCalls == 1} {
                set message [dict create role assistant content {} tool_calls [list \
                    [dict create function [dict create name run_action arguments {id game.explain}]]]]
            } else {
                set message [dict create role assistant content {}]
            }
        } else {
            lappend ::scidb::test::gameexplain::messages $messages
            set message [dict create role assistant content {A generated game explanation for practice.}]
        }
        after 0 [list {*}$callback [dict create ok 1 message $message]]
        return generated-test-response
    }
    set ::scidb::test::gameexplain::messages {}
    set ::scidb::test::gameexplain::plannerCalls 0
} -body {
    set reply [::knowledge::RunAction game.explain {}]
    ::scidb::test::gameexplain::wait
    set typedTitle $::application::report::Priv(title)
    set typedHtml [dict get $::application::report::Priv(data) html]
    set bar [::application::pgn::gamebar]
    menu .explainprobe -tearoff 0
    set id [expr {$::gamebar::Specs(size:$bar) == 1 ? $::gamebar::Specs(selected:$bar) : -1}]
    ::gamebar::BuildMenu $bar $id {} .explainprobe
    # The approved C12 menu replaced the old direct explanation row with
    # context.ask. Exercise that real route, then submit an explicit request.
    set found -1
    for {set i 0} {$i <= [.explainprobe index end]} {incr i} {
        if {[.explainprobe type $i] ne "command"} {continue}
        set command [.explainprobe entrycget $i -command]
        if {[lrange $command 0 1] eq {::action::run context.ask}} {
            set args [lindex $command 2]
            if {[dict get $args cid] ne "C12" || [dict get $args object gameSlot] != [::scidb::game::current]} {
                error {native game-bar Ask has the wrong game context}
            }
            set found $i
            break
        }
    }
    if {$found < 0} {error {native game-bar menu did not expose context.ask}}
    .explainprobe invoke $found
    .explainprobe unpost
    ::scidb::test::gameexplain::wait
    set entry $::application::assistant::Priv(entry)
    if {[string first "gameSlot=[::scidb::game::current]" [$entry get]] < 0} {
        error {native game-bar Ask did not populate the selected game context}
    }
    if {[llength $::scidb::test::gameexplain::messages] != 1} {
        error "opening Ask explanation count=[llength $::scidb::test::gameexplain::messages] plannerCalls=$::scidb::test::gameexplain::plannerCalls; expected one typed explanation before Enter"
    }
    $entry delete 0 end
    $entry insert 0 {Explain this game.}
    focus -force $entry
    event generate $entry <Return>
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
    rename ::ai::decide {}
    rename ::ai::decide_gameexplain_saved ::ai::decide
    array set ::ai::provider::Config $oldProvider
    set ::application::assistant::RouteMode $oldRoute
    array set ::application::ai::Config $oldConfig
    set ::application::ai::Settings(cloudNotice) $notice
} -result {1 2 1 1 1 1 1 1 1 1}

tcltest::cleanupTests
