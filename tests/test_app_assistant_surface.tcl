package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::surface {}
proc ::scidb::test::surface::init {} {
    ::scidb::test::actions::ready
    # Transcript checks explicitly invoke the pane, including when startup is disabled.
    ::application::assistant::show
    ::application::assistant::clear
    array set ::application::assistant::Priv {
        observer {} busy 1 turnTools 0 turnResults {} internalReplies {} turnRefusal {}
        prohibitedAnalysis 0 resultFacts {} lastFacts {} lastRequest {show the moves pane}
        messages {{role user content {show the moves pane}}}
    }
}

tcltest::test surface-internal-results {lookup protocol stays internal even with empty final prose} -setup {
    ::scidb::test::surface::init
} -body {
    set raw {CAPABILITY editor: runnable yes; arguments {}; do not paste this plan}
    ::application::assistant::ToolReply find_capability $raw
    set protocol [dict get [lindex $::application::assistant::Priv(messages) end] content]
    set widget $::application::assistant::Priv(text)
    set before [$widget get 1.0 end]
    ::application::assistant::Finish [dict create ok 1 message {content {}}] 1
    list [expr {$protocol eq $raw}] [string match *CAPABILITY* $before] \
        [string match *CAPABILITY* [$widget get 1.0 end]]
} -result {1 0 0}

tcltest::test surface-wrapped-plan-internal {generic action wrappers preserve planning-result provenance} -setup {
    ::scidb::test::surface::init
} -body {
    set raw [::application::assistant::runTool run_action {id run_job arguments {job prepare name {Generated Player}}}]
    if {![string match {*call these tools in order*} $raw]} {error "planning tool did not run: $raw"}
    ::application::assistant::ToolReply run_action $raw
    ::application::assistant::Finish [dict create ok 1 message {content {Here is the plan.}}] 1
    set visible [$::application::assistant::Priv(text) get 1.0 end]
    list [string match {*call these tools in order*} $visible] [string match {*plan of the job*} $visible] \
        [string match {*player_stats*} $visible]
} -result {0 0 0}

tcltest::test surface-tool-log-hides-plans {diagnostic history cannot expose direct or wrapped planning payloads} -setup {
    ::scidb::test::surface::init
    set savedLog $::application::assistant::ToolLog
    set ::application::assistant::ToolLog {}
} -body {
    ::application::assistant::runTool find_capability {request {show the moves pane}}
    ::application::assistant::runTool run_action {id run_job arguments {job prepare name {Generated Player}}}
    set raw [::application::assistant::runTool tool_log {count 10}]
    ::application::assistant::ToolReply tool_log $raw
    ::application::assistant::Finish [dict create ok 1 message [dict create content $raw]] 1
    set visible [$::application::assistant::Priv(text) get 1.0 end]
    list [string match *CAPABILITY* $visible] [string match {*call these tools*} $visible] \
        [string match {*Chesswiz cannot do that*} $visible]
} -cleanup {
    set ::application::assistant::ToolLog $savedLog
} -result {0 0 1}

tcltest::test surface-outcome-survives-refusal {successful real action receipts replace false refusal or ungrounded prose} -setup {
    ::scidb::test::surface::init
} -body {
    set result {}
    foreach prose {{Chesswiz cannot do that.} {The pane is shown with 998877 moves.} {}} {
        set ::application::assistant::Priv(busy) 1
        set receipt [::application::assistant::runTool pane {action show pane editor}]
        ::application::assistant::ToolReply pane $receipt
        ::application::assistant::Finish [dict create ok 1 message [dict create content $prose]] 1
        set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
        lappend result [expr {[string first $receipt $final] >= 0 && ![string match {*cannot do that*} $final]}]
    }
    set result
} -result {1 1 1}

tcltest::test surface-empty-action-outcome {an executed action with an empty return cannot end in refusal} -setup {
    ::scidb::test::surface::init
} -body {
    set raw [::application::assistant::runTool board-flip {}]
    ::application::assistant::ToolReply board-flip $raw
    ::application::assistant::OnReplyImpl 1 [dict create ok 1 message {content {Chesswiz cannot do that.}}]
    set text [dict get [lindex $::application::assistant::Priv(messages) end] content]
    list [expr {$raw eq ""}] [string match {*Flip Board*} $text] [string match {*cannot do that*} $text]
} -cleanup {
    ::application::assistant::runTool board-flip {}
} -result {1 1 0}

tcltest::test surface-discovery-not-success {planning and failed handlers cannot authorize a success receipt} -setup {
    ::scidb::test::surface::init
} -body {
    ::application::assistant::runTool find_capability {request {show the moves pane}}
    ::application::assistant::runTool run_job {job prepare name {Generated Player}}
    ::application::assistant::runTool missing_action {}
    ::application::assistant::RecordToolOutcome run_action ok {CAPABILITY internal} {id find_capability}
    list [::application::assistant::ExecutedReply] $::application::assistant::Priv(turnResults)
} -result {{} {}}

tcltest::test surface-pane-show-idempotent {capability action and pane show preserve the live game, cursor and notation} -setup {
    ::scidb::test::surface::init
    ::ai::setup::position -moves {1.e4 e5 2.Nf3 Nc6}
    update
} -body {
    set slot [::scidb::game::current]
    set fen [::scidb::pos::fen]
    set bar [::application::pgn::gamebar]
    set text $::application::pgn::Vars(pgn:$slot)
    set notation [$text get 1.0 end]
    for {set i 0} {$i < 3} {incr i} {
        ::application::assistant::runTool run_action {id menu.view.panes.editor}
        ::application::assistant::runTool pane {action show pane editor}
    }
    list [expr {$slot == [::scidb::game::current]}] [expr {$fen eq [::scidb::pos::fen]}] \
        [expr {$bar eq [::application::pgn::gamebar]}] [expr {$notation eq [$text get 1.0 end]}]
} -result {1 1 1 1}

tcltest::test surface-editor-rebuild {explicit hide/reopen rebuilds gamebar before another new position} -setup {
    ::scidb::test::surface::init
    ::ai::setup::position -moves {1.e4 e5 2.Nf3 Nc6}
    update
} -body {
    set slot [::scidb::game::current]
    set fen [::scidb::pos::fen]
    ::application::assistant::runTool pane {action hide pane editor}
    ::application::assistant::runTool pane {action show pane editor}
    update
    set preserved [expr {$slot == [::scidb::game::current] && $fen eq [::scidb::pos::fen]}]
    set index [::gamebar::getIndex [::application::pgn::gamebar] $slot]
    set notation [$::application::pgn::Vars(pgn:$slot) get 1.0 end]
    if {[string first e4 $notation] < 0} {error "rebuilt notation lost the existing moves: [list $notation]"}
    set savedMessages $::application::assistant::Priv(messages)
    set ::application::assistant::Priv(messages) [list [dict create role user content {Set up 1.Nf3 d5}]]
    set reply [::application::assistant::runTool set_position {moves {1.Nf3 d5}}]
    set ::application::assistant::Priv(messages) $savedMessages
    list $preserved [expr {$index >= 0}] [string match error:* $reply] \
        [string match {*5N2*} [::scidb::pos::fen]]
} -result {1 1 0 1}

tcltest::test surface-startup-tip {automatic tips do not cover the board or steal Ask focus with assistant enabled} -setup {
    ::scidb::test::surface::init
} -body {
    set saved $::tips::Options(mode)
    set ::tips::Options(mode) periodicallyWhenNew
    ::application::assistant::panel::SetEnabled 1
    ::tips::show .application
    after 250 {set ::scidb::test::surface::wait 1}
    vwait ::scidb::test::surface::wait
    ::application::ask::StartupFocus
    list [winfo exists .tipoftheday] [expr {[focus] eq $::application::ask::Priv(entry)}]
} -cleanup {
    set ::tips::Options(mode) $saved
} -result {0 1}

tcltest::test surface-startup-respects-user-focus {deferred startup focus leaves a user's dialog entry alone} -setup {
    ::scidb::test::surface::init
    toplevel .surfaceDialog
    ttk::entry .surfaceDialog.entry
    pack .surfaceDialog.entry
    update
    focus -force .surfaceDialog.entry
} -body {
    ::application::assistant::panel::StartupFocus
    expr {[focus] eq ".surfaceDialog.entry"}
} -cleanup {
    destroy .surfaceDialog
} -result 1

foreach slot [::game::usedPositions?] {
    ::application::pgn::release $slot
    ::game::release $slot
}
set ::application::assistant::Priv(busy) 0
tcltest::cleanupTests
