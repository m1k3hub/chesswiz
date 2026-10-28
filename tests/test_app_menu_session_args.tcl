package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::sessionargs {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} { error $result }
        return $result
    }
    proc until {script} {
        set end [expr {[clock milliseconds]+15000}]
        while {![uplevel 1 [list expr $script]]} {
            if {[clock milliseconds]>$end} {error "timeout: $script"}
            update
            after 10
        }
    }
    proc engine {} {
        set name {Generated session engine}
        set ::engine::Engines [list [dict merge $::engine::EmptyEngine [list Name $name \
            Command [::scidb::test::actions::engineProgram] Protocol UCI \
            Features:UCI {analyze true}]]]
        return $name
    }
}
tcltest::test session-args-review-engine {selection uses native validation; invalid selection preserves preference} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    set name [::scidb::test::sessionargs::engine]
    set choice $::ai::engine::Options(engine)
} -body {
    set selected [::scidb::test::sessionargs::call menu.analysis.review_engine operation select engine $name]
    set invalid [::knowledge::RunAction menu.analysis.review_engine {operation select engine nonexistent}]
    set f [open [file join $::env(HOME) review-options.tcl] w]
    ::ai::engine::WriteOptions $f
    close $f
    set f [open [file join $::env(HOME) review-options.tcl]]
    set persisted [read $f];close $f
    list [dict get $selected engine] [string match error:* $invalid] \
        [expr {$::ai::engine::Options(engine) eq $name}] \
        [expr {[string first $name $persisted]>=0}] [winfo exists .application.__aiengine__]
} -cleanup {
    ::ai::engine::choose $choice
    set ::engine::Engines $engines
} -result {{Generated session engine} 1 1 1 0}

tcltest::test session-args-iccf {save credentials through real config writer; reply omits credentials} -setup {
    ::scidb::test::actions::ready
    set config [array get ::iccf::xfcc::Config]
} -body {
    set saved [::scidb::test::sessionargs::call menu.tools.iccf operation save username generated-user password generated-secret endpoint http://127.0.0.1:19876/xfcc]
    set path [file join $::env(HOME) iccf-options.tcl]
    set f [open $path w];::iccf::xfcc::WriteConfig $f;close $f
    set ::iccf::xfcc::Config(username) {}
    set ::iccf::xfcc::Config(password) {}
    source $path
    list [dict get $saved configured] [string match *generated-secret* $saved] \
        $::iccf::xfcc::Config(username) $::iccf::xfcc::Config(password) \
        [winfo exists .application.iccfSettings]
} -cleanup {
    array set ::iccf::xfcc::Config $config
} -result {1 0 generated-user generated-secret 0}

tcltest::test session-args-review-cancel {cancel a real scheduled review; no forged running state} -setup {
    ::scidb::test::actions::ready
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
    ::application::assistant::runTool open_game {number 1}
    set config [array get ::ai::engine::Config]
    ::ai::engine::configure -engine [::scidb::test::actions::engineProgram]
} -body {
    set started [::scidb::test::sessionargs::call menu.analysis.game_review operation start depth 1]
    set running [dict get [::scidb::test::sessionargs::call menu.analysis.game_review operation status] running]
    set cancelled [::scidb::test::sessionargs::call menu.analysis.game_review operation cancel]
    ::scidb::test::sessionargs::until {!$::gamereview::Priv(running)}
    list $started $running $cancelled $::gamereview::Priv(cancel) $::gamereview::Priv(index)
} -cleanup {
    ::ai::engine::shutdown
    array set ::ai::engine::Config $config
    catch {destroy .application.__gamereview__}
} -result {1 1 1 1 0}

tcltest::test session-args-play {real UCI reply, draw decline, takeback, resignation and pipe cleanup through public operator} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    set name [::scidb::test::sessionargs::engine]
} -body {
    set started [::scidb::test::sessionargs::call menu.training.play_engine operation start engine $name color white minutes 0 movetime 30]
    set draw [::scidb::test::sessionargs::call menu.training.play_engine operation offer_draw]
    set declined [expr {$::playengine::Priv(phase) eq "user" && [dict get $draw status] eq [format $::playengine::mc::Declined $name]}]
    ::scidb::test::sessionargs::call menu.training.play_engine operation move move e4
    ::scidb::test::sessionargs::until {$::playengine::Priv(phase) eq "user" && [::scidb::game::query length]>=2}
    set moved [::scidb::game::query length]
    ::scidb::test::sessionargs::call menu.training.play_engine operation takeback
    set taken [::scidb::game::query length]
    ::scidb::test::sessionargs::call menu.training.play_engine operation resign
    set resigned [expr {$::playengine::Priv(phase) eq "over" && [expr {[string first {[Result "0-1"]} [::scidb::game::toPGN modified]] >= 0}]}]
    ::scidb::test::sessionargs::call menu.training.play_engine operation close
    list $started $declined [expr {$moved>=2}] $taken $resigned $::playengine::Priv(active) [winfo exists .application.playengine]
} -cleanup {
    ::playengine::Close
    set ::engine::Engines $engines
} -result {1 1 1 0 1 0 0}

tcltest::test session-args-match {two real engine pipes start a match and close cancels timers and children} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    set name [::scidb::test::sessionargs::engine]
} -body {
    set started [::scidb::test::sessionargs::call menu.training.engine_match operation start engines [list $name $name] minutes 0 movetime 30 tablebase 0]
    ::scidb::test::sessionargs::until {[::scidb::game::query length]>=2}
    set moved [::scidb::game::query length]
    set closed [::scidb::test::sessionargs::call menu.training.engine_match operation close]
    list $started [expr {$moved>=2}] [dict get $closed running] [winfo exists .application.enginematch]
} -cleanup {
    ::enginematch::Close
    set ::engine::Engines $engines
} -result {1 1 0 0}

tcltest::test session-args-collectors {omitted operation opens actual native collectors; explicit close/cancel completes them} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    ::scidb::test::sessionargs::engine
} -body {
    set result {}
    foreach {id window closeid closeargs} {
        menu.training.play_engine .application.playengine menu.training.play_engine {operation close}
        menu.training.engine_match .application.enginematch menu.training.engine_match {operation close}
        menu.analysis.review_engine .application.__aiengine__ view.dialog.close {dialog review_engine}
        menu.tools.iccf .application.iccfSettings view.dialog.close {dialog iccf}
        menu.tools.download .application.__download__ menu.tools.download {operation cancel}
    } {
        ::scidb::test::sessionargs::call $id
        lappend result [winfo exists $window]
        ::scidb::test::sessionargs::call $closeid {*}$closeargs
        lappend result [winfo exists $window]
    }
    return $result
} -cleanup {
    ::playengine::Close
    ::enginematch::Close
    ::application::download::Close
    set ::engine::Engines $engines
} -result {1 0 1 0 1 0 1 0 1 0}
tcltest::cleanupTests
