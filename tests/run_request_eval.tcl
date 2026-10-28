# ======================================================================
# Request evaluation (VAL-KNOW-008, VAL-AI-012)
# Corpus v2, 2026-10-25: append three print requests to cover the missing
# export/print area, authorized by W3-eval-r2. All existing items unchanged.
#
# Runs tests/fixtures/request-eval.jsonl through the real application under
# Xvfb. Each line is one request:
#
#   id          stable item id
#   area        feature area (databases, games, board, search, trees,
#               engines, play, players, export, media, layout, knowledge)
#   request     the user's words ("@CLUB@", "@PGN@" and "@MAIN@" stand for
#               the fixture paths the runner creates)
#   predicate   Tcl evaluated against real app state after the turn
#   actions     acceptable action/tool ids (also auto-approved)
#   setup       optional Tcl run before the request (dialogs are closed by
#               the runner first)
#   multi       1 for a request that needs two or more steps
#   loose       1 for a deliberately loose/typo'd request
#   ambiguous   1 when one clarifying question is allowed
#
# The model is the configured provider/model (SCIDB_AI_PROVIDER /
# SCIDB_AI_MODEL); SCIDB_AI_REPLAY=<file> replays a recorded transport
# instead of calling it (used for a provider whose live quota is gone).
# SCIDB_AI_RECORD=<file> records every chat reply for such a replay.
#
#   HOME=<fresh dir> SCIDB_AI_PROVIDER=fireworks SCIDB_AI_MODEL=... \
#     SCIDB_AI_CLASSIFIER=typesafe SCIDB_AI_ROUTE=active \
#     xvfb-run -a src/tkchesswiz tests/run_request_eval.tcl [-match GLOB]
#
# A report goes to tests/tmp-app/request-eval/report.txt and per-item
# logs to items/<id>.txt.
# ======================================================================

set argvCopy $argv
set argv {--single-process}
set argc 1
set root [file normalize [file join [file dirname [info script]] ..]]
namespace eval ::RequestEval {}
set ::RequestEval::Verbose 0
set ::RequestEval::Root $root
set ::RequestEval::Work [expr {
    [info exists ::env(SCIDB_EVAL_WORK)] && $::env(SCIDB_EVAL_WORK) ne ""
        ? $::env(SCIDB_EVAL_WORK)
        : [file join $root tests tmp-app request-eval]}]
file mkdir $::RequestEval::Work
file mkdir [file join $::RequestEval::Work items]
set ::env(SCIDB_ERROR_LOG) [file join $::RequestEval::Work errors.log]
set ::RequestEval::SkipDone 0
# the corpus has its own model class; no System One triage
set ::env(SCIDB_AI_TRIAGE) 0

source -encoding utf-8 [file join $root tcl chesswiz]
# A fresh user directory is a first run, whose language chooser waits for a
# click; the evaluation is not one. Startup2 has not run yet (it is a timer).
set ::scidb::dir::setup 0
set ::application::sample::Removed 1
update
fconfigure stdout -buffering line

namespace eval ::RequestEval {
    variable Calls {}
    variable Current {}
    variable Approve {}
    variable PlanCalls {}
    variable Destructive {
        import_games download_games update_player_data compact_database
        convert_database save_working_set save_pattern add_to_repertoire
        game.paste game-save game-replace app-quit new_game
    }
    variable Routed 0
    variable RoutedId ""
    variable Seen {}
    variable Watching 0
    variable Known {}
    variable Start {.application}
    variable Pending {}
    variable Events {}
}

set ::RequestEval::Match *
# model: ask the assistant; gold: run the item's reference script instead
# (checks the predicate can be met); null: do nothing (checks the predicate
# is not already true). gold and null never call a model.
set ::RequestEval::Mode model
set ::RequestEval::Opened {}
set corpus [file join [file dirname [info script]] fixtures request-eval.jsonl]
set replayFile ""
set recordFile ""
for {set i 0} {$i < [llength $argvCopy]} {incr i} {
    set key [lindex $argvCopy $i]
    switch -- $key {
        -verbose  { set ::RequestEval::Verbose 1 }
        -match    { incr i; set ::RequestEval::Match [lindex $argvCopy $i] }
        -corpus   { incr i; set corpus [lindex $argvCopy $i] }
        -replay   { incr i; set replayFile [lindex $argvCopy $i] }
        -record   { incr i; set recordFile [lindex $argvCopy $i] }
        -skip-done { set ::RequestEval::SkipDone 1 }
        -mode     { incr i; set ::RequestEval::Mode [lindex $argvCopy $i] }
    }
}
if {[info exists ::env(SCIDB_AI_REPLAY)]} { set replayFile $::env(SCIDB_AI_REPLAY) }
if {[info exists ::env(SCIDB_AI_RECORD)]} { set recordFile $::env(SCIDB_AI_RECORD) }

package require json
source [file join $root tests eval_harness_support.tcl]
::EvalHarness::Install

# ----------------------------------------------------------------------
# Fixtures: a writable copy of the sample database, a second database and
# a two-game PGN for the import request.
# ----------------------------------------------------------------------
proc ::RequestEval::MakeFixtures {} {
    variable Work
    variable MainDb
    variable ClubDb
    variable PgnFile
    set src [expr {[info exists ::env(SCIDB_EVAL_DB)] && $::env(SCIDB_EVAL_DB) ne ""
        ? $::env(SCIDB_EVAL_DB)
        : [file join $::RequestEval::Root share sample "Sample games.sci"]}]
    if {![file exists $src]} { error "evaluation database not found: $src" }
    # Scidb databases may be multi-file: copy the companions too
    set stem [file rootname $src]
    foreach ext {sci scg scn si4} {
        set from "$stem.$ext"
        if {[file exists $from]} {
            file copy -force $from [file join $Work "main.$ext"]
            file copy -force $from [file join $Work "Club games.$ext"]
        }
    }
    set MainDb [file join $Work main.sci]
    set ClubDb [file join $Work "Club games.sci"]
    set PgnFile [file join $Work extra.pgn]
    set f [open $PgnFile w]
    fconfigure $f -translation lf
    puts $f {[Event "Evaluation Import"]
[Site "Test"]
[Date "2026.10.20"]
[Round "1"]
[White "Alpha, One"]
[Black "Beta, Two"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0}

    puts $f {[Event "Evaluation Import"]
[Site "Test"]
[Date "2026.10.20"]
[Round "2"]
[White "Gamma, Three"]
[Black "Delta, Four"]
[Result "0-1"]

1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. cxd5 exd5 0-1}
    close $f
}

# ----------------------------------------------------------------------
# State helpers for predicates. They read the running application, never
# the assistant's text.
# ----------------------------------------------------------------------
proc ev_db {} { ::scidb::db::get name }
proc ev_db_is {path} { expr {[file normalize [ev_db]] eq [file normalize $path]} }
proc ev_open {path} { expr {[::scidb::db::get open? $path] ? 1 : 0} }
proc ev_games {} { ::scidb::db::count games [::scidb::db::get name] [::application::database::currentVariant] }
proc ev_games_in {base} { ::scidb::db::count games $base Normal }
proc ev_fen {} { ::scidb::pos::fen }
proc ev_ply {} { ::scidb::game::ply }
proc ev_mainline {} { llength [::scidb::game::query mainline] }
proc ev_tab {} { lindex [split [.application.nb select] .] end }
proc ev_pane {uid} {
    set found 0
    catch {
        set twm [::application::twm board]
        if {$uid in [$twm leaves]} { set found 1 }
    }
    return $found
}
proc ev_floating {uid} {
    set found 0
    catch {
        set twm [::application::twm board]
        foreach w [::scidb::tk::twm floats $twm] {
            foreach leaf [::scidb::tk::twm leaves $twm $w] {
                # numbered panes (analysis:1) match their base name
                if {$leaf eq $uid || [string match $uid:* $leaf]} { set found 1 }
            }
        }
    }
    return $found
}
proc ev_dialog {path} { expr {[winfo exists $path] ? 1 : 0} }
proc ev_dialog_glob {pat} {
    foreach w [winfo children .] { if {[string match $pat $w]} { return 1 } }
    return 0
}
proc ev_search_count {} { ::scidb::view::count games [::scidb::db::get name] [::application::database::currentVariant] 0 }
proc ev_total_games {} { ::scidb::db::count games [::scidb::db::get name] [::application::database::currentVariant] }
proc ev_engine_running {} { llength [::application::analysis::Running] }
proc ev_flipped {} { expr {[::application::board::rotated?] ? 1 : 0} }
proc ev_fullscreen {} { expr {[::menu::fullscreen?] ? 1 : 0} }
proc ev_called {args} {
    foreach c $::RequestEval::Calls {
        if {[dict get $c outcome] in {error declined}} continue
        foreach pat $args {
            if {[string match $pat [dict get $c name]]} { return 1 }
        }
    }
    return 0
}
proc ev_called_ok {name} {
    foreach c $::RequestEval::Calls {
        if {[dict get $c name] eq $name && [dict get $c outcome] eq "ok"} { return 1 }
    }
    return 0
}
proc ev_call_count {name} {
    set n 0
    foreach c $::RequestEval::Calls {
        if {[dict get $c name] eq $name && [dict get $c outcome] ne "declined"} { incr n }
    }
    return $n
}
# A run_action call that named a registry action id.
proc ev_ran_action {id} {
    foreach c $::RequestEval::Calls {
        if {[dict get $c name] ne "run_action"} continue
        if {[dict get $c outcome] in {error declined}} continue
        set a [dict get $c args]
        if {[dict exists $a id] && [dict get $a id] eq $id} { return 1 }
        if {[dict exists $a arguments] && [dict exists $a arguments id] \
            && [dict get $a arguments id] eq $id} { return 1 }
    }
    return 0
}
# A tool call whose named argument has a value.
proc ev_called_with {name key value} {
    foreach c $::RequestEval::Calls {
        if {[dict get $c name] ne $name} continue
        if {[dict get $c outcome] in {error declined}} continue
        set a [dict get $c args]
        if {[dict exists $a $key] && [dict get $a $key] eq $value} { return 1 }
    }
    return 0
}
proc ::RequestEval::Observer {args} {
    lappend ::RequestEval::Events $args
    if {$::RequestEval::Verbose} { puts stderr "EVENT $args"; flush stderr }
}
proc ::RequestEval::Trace {msg} { if {$::RequestEval::Verbose} { puts stderr "TRACE $msg"; flush stderr } }
proc ev_messages_empty {} { expr {[llength $::application::assistant::Priv(messages)] ? 0 : 1} }
# Modal dialogs block their caller in tkwait, so the runner closes them as
# soon as they appear and remembers that they were shown.
proc ev_seen {name} {
    set name [string trimleft $name .]
    foreach key [dict keys $::RequestEval::Seen] {
        if {[string match $name $key] || [string match *$name* $key]} { return 1 }
    }
    return 0
}
proc ::RequestEval::WatchDialogs {} {
    # reschedule first: an error in one pass must not end the watch
    after 300 ::RequestEval::WatchDialogs
    if {[catch { WatchDialogsOnce } e]} { ::RequestEval::Trace "watch: $e" ; puts stderr "WATCH ERROR $e" }
}
proc ::RequestEval::WatchDialogsOnce {} {
    variable Seen
    # Toplevels the evaluation itself opens. The assistant's own __name__
    # dialogs are modal (the plan waits for the user to close them), so the
    # runner closes them at once and records that they were shown.
    #
    # This loop never stops: a dialog that a late reply opens after a turn
    # has ended would otherwise block the next item forever, because the
    # tool handler waits on it inside the modal event loop.
    set windows {}
    foreach parent {. .application} {
        foreach w [winfo children $parent] { lappend windows $w }
    }
    catch { foreach w [wm stackorder .] { lappend windows $w } }
    if {$::RequestEval::Watching} { ::RequestEval::NoteOpened $windows }
    foreach w $windows {
        if {$w in {. .application}} continue
        set tail [lindex [split $w .] end]
        set hit 0
        foreach pat {
                     export print assistantPreferences __comment__ playengine
                     __discover__ __card__* __mediastream__ __filedialog* playerprep_*
                     *prep_report* *prep* openingReport *__report__ *properties*
                     prop_*
        } {
            if {[string match $pat $tail]} { set hit 1 }
        }
        if {[string match .__* $tail]} { set hit 1 }
        # Any other toplevel this turn opened is a dialog too (a modal one
        # would block the turn), unless it is a floating pane of the board.
        if {!$hit && $::RequestEval::Watching && $w ni $::RequestEval::Start && $tail ne "progress"
         && [winfo exists $w] && [winfo ismapped $w] && ![::RequestEval::IsFloat $w]} {
            set hit 1
        }
        # A player card can be given a name of its own; fall back to the
        # window manager title for the dialogs that are never a board pane.
        if {!$hit && [catch { wm title $w } title] == 0
         && [regexp -nocase {player card|properties|export|print|prepare|discover|stream|archive|save as|open file} $title]} {
            set hit 1
        }
        # close a dialog only 1.5 s after it was first seen mapped: it is
        # built by then, so closing cannot break the code still filling it
        if {$hit && (![winfo exists $w] || ![winfo ismapped $w])} { set hit 0 }
        if {$hit} {
            if {![dict exists $::RequestEval::Pending $w]} {
                dict set ::RequestEval::Pending $w [clock milliseconds]
            }
            if {[clock milliseconds] - [dict get $::RequestEval::Pending $w] < 1500} { set hit 0 }
        }
        if {!$hit} continue
        if {[catch { winfo toplevel $w } top]} continue
        if {$top ne $w} continue
        dict set Seen $tail 1
        CancelDialog $w
    }
}

proc ::RequestEval::Sha256 {path} {
    if {![catch { exec sha256sum $path } r]} { return [lindex $r 0] }
    if {![catch { package require sha256 } ] || ![catch { package require sha2 }]} {
        catch { return [::sha2::sha256 -hex -filename $path] }
    }
    if {![catch { exec certutil -hashfile [file nativename $path] SHA256 } r]} {
        return [string tolower [string map {" " ""} [lindex [split $r \n] 1]]]
    }
    return unknown
}
proc ::RequestEval::IsFloat {w} {
    set twm ""
    catch { set twm [::application::twm board] }
    if {$twm eq ""} { return 0 }
    set floats {}
    catch { set floats [::scidb::tk::twm floats $twm] }
    foreach f $floats { if {$w eq $f || [string match $f.* $w] || [string match $w.* $f]} { return 1 } }
    # a float's toplevel holds a twm leaf
    if {[catch { winfo children $w } kids]} { return 0 }
    foreach k $kids { if {[string match *__frame__* $k] || [string match *twm* $k]} { return 1 } }
    return 0
}
proc ::RequestEval::Toplevels {} {
    set out {}
    foreach parent {. .application} {
        foreach w [winfo children $parent] {
            if {[catch { winfo toplevel $w } top] || $top ne $w} continue
            lappend out $w
        }
    }
    catch { foreach w [wm stackorder .] { if {$w ni $out} { lappend out $w } } }
    return $out
}
proc ::RequestEval::NoteOpened {windows} {
    variable Opened
    variable Known
    foreach w [concat $windows [Toplevels]] {
        if {$w in {. .application} || $w in $Known} continue
        if {![winfo exists $w] || [catch { winfo toplevel $w } top] || $top ne $w} continue
        set tail [lindex [split $w .] end]
        if {[string match __tooltip__* $tail] || [string match __highlight__* $tail] || $tail eq "popdown"} continue
        if {![winfo ismapped $w]} continue
        set title ""
        catch { set title [wm title $w] }
        lappend Opened $w $title
        lappend Known $w
    }
}
bind Toplevel <Map> {+catch { if {$::RequestEval::Watching} { ::RequestEval::NoteOpened [list %W] } }}

# Destroying a dialog that waits in vwait for its reply leaves the caller
# blocked in that vwait for the rest of the session. Answer the wait first
# (the file box and the message box have different variables), give the
# waiting code a pass through the event loop, then destroy what is left.
proc ::RequestEval::CancelDialog {w} {
    if {$::RequestEval::Watching && [winfo exists $w] && $w ni $::RequestEval::Known} {
        set title ""; catch { set title [wm title $w] }
        lappend ::RequestEval::Opened $w $title
        lappend ::RequestEval::Known $w
    }
    catch { set ::dialog::Reply($w) {} }
    if {[namespace exists ::fsbox] && [info exists ::fsbox::Priv(dialog)]
     && $::fsbox::Priv(dialog) eq $w} {
        foreach name [array names ::fsbox::Priv *:$w:result] {
            catch { set ::fsbox::Priv($name) {} }
        }
    }
    update
    catch { destroy $w }
}
# The game header tag of the board game.
proc ev_tag {tag} {
    set pos [::scidb::game::current]
    foreach pair [::scidb::game::tags $pos] {
        if {[lindex $pair 0] eq $tag} { return [lindex $pair 1] }
    }
    return ""
}
# The player whose turn it is on the board ('white'/'black').
proc ev_turn {} { expr {[::scidb::game::ply] % 2 ? "black" : "white"} }
# Any toplevel whose name matches, for the reports/dialogs whose window
# names carry an index or the database name.
proc ev_window {pat} {
    foreach key [dict keys $::RequestEval::Seen] {
        if {[string match $pat $key] || [string match $pat .application/$key]} { return 1 }
    }
    foreach w [wm stackorder .] {
        if {[string match $pat $w]} { return 1 }
    }
    foreach w [winfo children .] {
        if {[string match $pat $w]} { return 1 }
    }
    return 0
}
proc ev_comment {text} {
    expr {[string first $text [::scidb::game::toPGN modified]] >= 0}
}
proc ev_pgn_has {text} {
    expr {[string first $text [::scidb::game::toPGN modified]] >= 0}
}

# --- state probes added for the held-out corpus (2026-10-21) -----------
# The database game number (1-based) of the game on the board, 0 for a
# game that is not linked to a database.
proc ev_gameno {} {
    lassign [::scidb::game::link? [::scidb::game::current]] base variant index
    if {$index eq "" || $index < 0} { return 0 }
    return [expr {$index + 1}]
}
# The database the board game came from.
proc ev_game_base {} {
    lindex [::scidb::game::link? [::scidb::game::current]] 0
}
proc ev_player_in_game {pat} {
    expr {[string match -nocase *$pat* [ev_tag White]] || [string match -nocase *$pat* [ev_tag Black]]}
}
proc ev_moves {} { ::scidb::game::query length }
proc ev_game_count_open {} { ::gamebar::size [::application::pgn::gamebar] }
# The game list (view 0) is narrowed, and every game in it has a header tag
# matching a glob ("*" tag "Player" means White or Black). Reads the tags of
# the listed games from the database.
proc ev_filter_tags {base variant} {
    set out {}
    set n [::scidb::view::count games $base $variant 0]
    for {set row 0} {$row < $n} {incr row} {
        set number [::scidb::db::get gameNumber $base $variant $row 0]
        set tags {}
        foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
        lappend out $tags
    }
    return $out
}
proc ev_filter_all {tag pat} {
    set base [::scidb::db::get name]
    set variant [::application::database::currentVariant]
    set n [::scidb::view::count games $base $variant 0]
    if {$n == 0 || $n == [::scidb::db::count games $base $variant]} { return 0 }
    foreach tags [ev_filter_tags $base $variant] {
        set hit 0
        foreach t [expr {$tag eq "Player" ? {White Black} : [list $tag]}] {
            if {[dict exists $tags $t] && [string match -nocase $pat [dict get $tags $t]]} { set hit 1 }
        }
        if {!$hit} { return 0 }
    }
    return 1
}
# A toplevel whose path or title matches the regexp appeared during the turn.
proc ev_opened {re} {
    foreach {w title} $::RequestEval::Opened {
        if {[regexp -nocase -- $re $w] || [regexp -nocase -- $re $title]} { return 1 }
    }
    return 0
}
# Real print-module output, independent of tool names and assistant wording.
# Setup snapshots existing files so an earlier item cannot satisfy this one.
proc ev_printed {} {
    foreach pdf [glob -nocomplain -directory [::print::TempDir] *.pdf] {
        if {$pdf in $::RequestEval::PrintBefore || [file size $pdf] < 100} continue
        set f [open $pdf rb]
        set header [read $f 5]
        close $f
        if {$header eq "%PDF-"} { return 1 }
    }
    return 0
}

# Reference steps for -mode gold: run a registry action as an approved click.
proc gold_run {id {cargs {}}} {
    set ::RequestEval::Current [list $id $cargs]
    set r [::action::run $id $cargs]
    if {[string match error:* $r]} { error "$id: $r" }
    update
    return $r
}
# A tool call through the assistant's own tool layer (validator, defaults).
proc gold_call {name {cargs {}}} {
    set ::RequestEval::Current [list $name $cargs]
    lassign [::application::assistant::RealRunTool $name $cargs {}] outcome asked reply
    if {$outcome ne "ok"} { error "$name: $outcome $reply" }
    update
    return $reply
}
proc gold_tool {name args} {
    set r [::application::assistant::$name {*}$args]
    if {[string match error:* $r]} { error "$name: $r" }
    update
    return $r
}
proc ev_pane_shown {suffix} { ::menu::PaneChecked $suffix }
proc ev_pane_hide {suffix} { if {[::menu::PaneChecked $suffix]} { ::menu::TogglePaneId $suffix }; update }
proc ev_pane_show {suffix} { if {![::menu::PaneChecked $suffix]} { ::menu::TogglePaneId $suffix }; update }
proc ev_zoomed {uid} {
    set twm [::application::twm board]
    set z [$twm zoomed]
    expr {$z ne "" && $z eq [$twm leaf $uid]}
}
proc ev_fontsize {} { expr {abs([font configure TkDefaultFont -size])} }
# The number of lines (MultiPV) of the first running engine.
proc ev_engine_lines {} {
    set n [lindex [::application::analysis::Running] 0]
    if {$n eq ""} { return 0 }
    namespace upvar ::application::analysis::$n Options Options
    expr {$Options(engine:singlePV) ? 1 : $Options(engine:multiPV)}
}
proc ev_me {} { set ::application::ai::Settings(me) }

# ----------------------------------------------------------------------
# Instrumentation: tool calls, approvals, routing and the model transport.
# ----------------------------------------------------------------------
rename ::application::assistant::RunTool ::application::assistant::RealRunTool
proc ::application::assistant::RunTool {name cargs {approval {}}} {
    set ::RequestEval::Current [list $name $cargs]
    ::RequestEval::Trace "tool in $name $cargs"
    lassign [::application::assistant::RealRunTool $name $cargs $approval] outcome asked reply
    ::RequestEval::Trace "tool out $name $outcome"
    lappend ::RequestEval::Calls [dict create name $name args $cargs \
        outcome $outcome asked $asked reply $reply]
    return [list $outcome $asked $reply]
}

rename ::application::assistant::PlanNeedsConfirm ::application::assistant::RealPlanNeedsConfirm
proc ::application::assistant::PlanNeedsConfirm {calls} {
    set ::RequestEval::PlanCalls $calls
    return [::application::assistant::RealPlanNeedsConfirm $calls]
}
proc ::RequestEval::NeedsGate {name} {
    if {![dict exists $::action::Registry $name]} { return 0 }
    set rec [::action::get $name]
    expr {[dict get $rec confirm] || [dict get $rec bulk]}
}
proc ::RequestEval::Approved {name} {
    return [expr {$name in $::RequestEval::Approve}]
}
proc ::RequestEval::Confirm {what} {
    lassign $::RequestEval::Current name
    return [::RequestEval::Approved $name]
}
proc ::RequestEval::PlanConfirm {what} {
    foreach call $::RequestEval::PlanCalls {
        set name [dict get $call function name]
        if {[::RequestEval::NeedsGate $name] && ![::RequestEval::Approved $name]} { return 0 }
    }
    return 1
}

rename ::application::assistant::DeliverRouted ::application::assistant::RealDeliverRouted
proc ::application::assistant::DeliverRouted {name cargs round} {
    incr ::RequestEval::Routed
    set ::RequestEval::RoutedId $name
    return [::application::assistant::RealDeliverRouted $name $cargs $round]
}

# --- recorded transport (used only when a live provider is impossible) ---
set ::RequestEval::Replay {}
set ::RequestEval::ReplayIndex 0
set ::RequestEval::Record {}
if {$replayFile ne ""} {
    set f [open $replayFile r]; fconfigure $f -encoding utf-8
    set ::RequestEval::Replay [::json::json2dict [read $f]]; close $f
}
# A model that is down must fail its item, never be answered by the
# app's backup model: backups are off and every call's model is logged.
array set ::application::ai::Settings {backup1 {} backup2 {}}
set ::RequestEval::Models {}
set ::RequestEval::LastCall 0
rename ::ai::provider::chatAsync ::ai::provider::RealChatAsync
proc ::ai::provider::chatAsync {messages tools script} {
    lappend ::RequestEval::Models "$::ai::provider::Config(name)/[::ai::provider::model]"
    # SCIDB_EVAL_PACE_MS: least time between two model calls (free tiers)
    if {[info exists ::env(SCIDB_EVAL_PACE_MS)]} {
        set wait [expr {$::env(SCIDB_EVAL_PACE_MS) - ([clock milliseconds] - $::RequestEval::LastCall)}]
        if {$wait > 0} { after $wait }
    }
    set ::RequestEval::LastCall [clock milliseconds]
    if {[dict size $::RequestEval::Replay]} {
        set item $::RequestEval::Item
        set i $::RequestEval::ReplayIndex
        incr ::RequestEval::ReplayIndex
        if {![dict exists $::RequestEval::Replay $item $i]} {
            after 0 [list {*}$script [list ok 0 error "no recorded reply for $item call $i" down 0]]
            return
        }
        set result [dict get $::RequestEval::Replay $item $i]
        after 0 [list ::RequestEval::ChatResult $::EvalHarness::Ticket $script $result]
        return
    }
    set wrapped [list ::RequestEval::ChatResult $::EvalHarness::Ticket $script]
    ::ai::provider::RealChatAsync $messages $tools $wrapped
}
proc ::RequestEval::ChatResult {ticket script result} {
    if {!$::EvalHarness::Active || $ticket != $::EvalHarness::Ticket} { return }
    set result [::EvalHarness::TransportResult $result]
    if {$::RequestEval::RecordFile ne ""} {
        dict lappend ::RequestEval::Record $::RequestEval::Item $result
    }
    uplevel #0 [list {*}$script $result]
}
set ::RequestEval::RecordFile $recordFile

# ----------------------------------------------------------------------
# One item.
# ----------------------------------------------------------------------
# Wait until the assistant is idle; nested dialog waits still run the after
# callbacks, so WatchDialogs keeps closing modal windows meanwhile.
proc ::RequestEval::WaitIdle {{ms 15000}} {
    set t 0
    while {[set ::application::assistant::Priv(busy)] && $t < $ms} {
        update
        after 20
        incr t 20
    }
    update
    return [expr {![set ::application::assistant::Priv(busy)]}]
}

# Wait for the current turn, but on the wall clock: a late tool reply may
# raise the busy flag again after any one-shot timer has fired, and a
# provider socket may never answer. Returns 1 when the turn ended, 0 on
# timeout; a timeout releases the flag so the run can go on.
proc ::RequestEval::WaitBusy {ms} {
    set end [expr {[clock milliseconds] + $ms}]
    while {[set ::application::assistant::Priv(busy)]} {
        if {[clock milliseconds] >= $end} {
            set ::application::assistant::Priv(busy) 0
            update
            return 0
        }
        update
        after 50
    }
    update
    return 1
}

# Between items every toplevel other than the main window is stale: dialogs
# left open, a report window, a player card. Floating panes are docked first
# and then destroyed, so the next item starts from the same layout.
proc ::RequestEval::CloseAllAuxWindows {} {
    catch {
        set twm [::application::twm board]
        foreach w [::scidb::tk::twm floats $twm] { catch { ::twm::Dock $twm $w } }
    }
    foreach parent {. .application} {
        foreach w [winfo children $parent] {
            if {$w eq ".application"} continue
            set tail [lindex [split $w .] end]
            if {[string match __tooltip__* $tail] || [string match __highlight__* $tail]
             || $tail eq "popdown"} continue
            if {[catch { winfo toplevel $w } top]} continue
            if {$top ne $w} continue
            dict set ::RequestEval::Seen $tail 1
            CancelDialog $w
        }
    }
    # popups that hang off a canvas deep in the tree are not direct children
    catch {
        foreach w [wm stackorder .] {
            if {$w in {. .application}} continue
            set tail [lindex [split $w .] end]
            if {[string match __tooltip__* $tail] || [string match __highlight__* $tail]
             || $tail eq "popdown"} continue
            dict set ::RequestEval::Seen $tail 1
            CancelDialog $w
        }
    }
    update
}

proc ::RequestEval::Reset {} {
    variable Calls {}
    variable Current {}
    variable PlanCalls {}
    variable Routed 0
    variable RoutedId ""
    variable Seen {}
    variable MainDb
    variable Base
    variable Variant

    set ::RequestEval::Watching 1
    catch { ::application::assistant::clear }
    WaitIdle
    foreach n [::application::analysis::Running] { catch { ::application::analysis::stopEngine $n } }
    catch { ::application::switchTab board }
    catch { ::application::database::switchToBase $MainDb }
    catch { ::scidb::view::search $MainDb $Variant 0 reset none }
    CloseAllAuxWindows
    if {[catch { ::application::board::rotated? } r] || $r} {
        catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
    }
    catch { if {[::menu::fullscreen?]} { ::menu::setFullscreen 0 } }
    catch { [::application::twm board] zoom "" }
    # only the main database stays open, writable
    foreach base [list $::RequestEval::ClubDb] {
        if {![::scidb::db::get open? $base]} continue
        catch { ::scidb::db::set modified $base 0 }
        catch { ::application::database::closeBase .application $base }
    }
    catch { ::application::database::switchToBase $MainDb }
    catch { if {[::scidb::db::get readonly? $MainDb]} { ::scidb::db::set readonly $MainDb 0 } }
    set ::application::ai::Settings(me) {Thomas, Michael}
    # close every game through its game bar, so an edited game cannot carry
    # over and the bar keeps no orphaned item
    catch {
        set gb [::application::pgn::gamebar]
        foreach id [::gamebar::getIdList $gb] {
            catch { ::scidb::game::modified $id false }
            catch { ::gamebar::remove $gb $id }
        }
    }
    update
    ::game::new .application -base $MainDb -variant $Variant -number 9
    set plies [::scidb::game::query mainline]
    if {[llength $plies] > 11} { catch { ::scidb::game::go key [lindex $plies 11 0] } }
    update
}

proc ::RequestEval::RunItem {item} {
    set ::RequestEval::ReplayIndex 0
    return [::EvalHarness::RunItem ::RequestEval $item]
}

proc ::RequestEval::RunAttempt {item} {
    variable Calls
    variable Approve

    set id [dict get $item id]
    set request [string map [list @MAIN@ $::RequestEval::MainDb \
        @CLUB@ $::RequestEval::ClubDb @PGN@ $::RequestEval::PgnFile] \
        [dict get $item request]]
    set ::RequestEval::Item $id
    set ::RequestEval::Models {}
    array set ::application::ai::Settings {backup1 {} backup2 {}}
    set Approve [expr {[dict exists $item actions] ? [dict get $item actions] : {}}]
    set ::application::assistant::Priv(confirm) ::RequestEval::Confirm
    set ::application::assistant::Priv(reqconfirm) ::RequestEval::PlanConfirm

    Reset
    set smapGold [list @MAIN@ [list $::RequestEval::MainDb] \
        @CLUB@ [list $::RequestEval::ClubDb] @PGN@ [list $::RequestEval::PgnFile]]
    if {[dict exists $item setup]} {
        set smap [list @MAIN@ [list $::RequestEval::MainDb] \
            @CLUB@ [list $::RequestEval::ClubDb] @PGN@ [list $::RequestEval::PgnFile]]
        if {[catch { uplevel #0 [string map $smap [dict get $item setup]] } e]} {
            set setupError [expr {$e eq "" ? "setup raised an error without a message" : $e}]
        }
    }
    update

    # A previous item can still be finishing (a late tool reply, a plan
    # step). Never start a request into a busy assistant: its messages would
    # be attributed to this item.
    WaitIdle 30000
    set before [llength $::application::assistant::Priv(messages)]
    set started [clock milliseconds]
    set ::RequestEval::Events {}
    ::RequestEval::Trace "ask $id confirm=$::application::assistant::Priv(confirm) reqconfirm=$::application::assistant::Priv(reqconfirm)"
    set ::RequestEval::Opened {}
    set ::RequestEval::Pending {}
    set ::RequestEval::Start [lmap w [::RequestEval::Toplevels] { expr {[winfo ismapped $w] ? $w : [continue]} }]
    set ::RequestEval::Known [lmap w [::RequestEval::Toplevels] { expr {[winfo ismapped $w] ? $w : [continue]} }]
    switch -- $::RequestEval::Mode {
        model { set askStarted [::application::assistant::ask $request -observer ::RequestEval::Observer] }
        gold {
            set askStarted 1
            set gold [string map $smapGold [expr {[dict exists $item gold] ? [dict get $item gold] : "error {no gold script}"}]]
            if {[catch { uplevel #0 $gold } e]} { set setupError "gold: $e" }
            after 500 {set ::RequestEval::GoldWait 1}; vwait ::RequestEval::GoldWait
        }
        null { set askStarted 1 }
    }
    if {!$askStarted} {
        set ::RequestEval::Watching 0
        set seconds [expr {([clock milliseconds] - $started) / 1000.0}]
        set log [file join $::RequestEval::Work items $id.txt]
        set f [open $log w]; fconfigure $f -encoding utf-8
        puts $f "id: $id"
        puts $f "error: the assistant was still busy; the request was not started"
        close $f
        return [dict create id $id area [dict get $item area] ok 0 \
            predicate 0 destruct 1 clarify 1 seconds $seconds calls {} \
            questions 0 said "" multi [expr {[dict exists $item multi] && [dict get $item multi]}] \
            loose [expr {[dict exists $item loose] && [dict get $item loose]}]]
    }
    set turnEnded [WaitBusy 300000]
    if {!$turnEnded} { set ::EvalHarness::Failure {turn timeout} }
    WaitIdle 5000
    ::RequestEval::Trace "ask returned $id ended=$turnEnded"
    set seconds [expr {([clock milliseconds] - $started) / 1000.0}]
    set ::RequestEval::Watching 0

    # assistant messages added by this turn
    set messages [lrange $::application::assistant::Priv(messages) $before end]
    set said ""
    set questions 0
    foreach m $messages {
        if {[dict get $m role] ne "assistant" || ![dict exists $m content]} continue
        set text [string trim [dict get $m content]]
        if {$text eq ""} continue
        set said $text
        if {[regexp {\?\s*$} $text]} { incr questions }
    }

    ::RequestEval::NoteOpened {}
    set predicateOK 0
    set predicateError ""
    set qmap [list @MAIN@ [list $::RequestEval::MainDb] \
        @CLUB@ [list $::RequestEval::ClubDb] @PGN@ [list $::RequestEval::PgnFile]]
    set predicate [string map $qmap [dict get $item predicate]]
    if {[catch { uplevel #0 $predicate } r]} {
        set predicateError $r
    } else {
        set predicateOK [expr {$r ? 1 : 0}]
    }

    # no wrong destructive action ran
    set bad {}
    foreach c $Calls {
        if {[dict get $c outcome] in {error declined}} continue
        set name [dict get $c name]
        if {$name in $::RequestEval::Destructive && $name ni $Approve} { lappend bad $name }
    }
    set destructOK [expr {[llength $bad] ? 0 : 1}]

    set clarifyOK 1
    if {[dict exists $item ambiguous] && [dict get $item ambiguous]} {
        set clarifyOK [expr {$questions <= 1}]
    }

    # A setup that failed did not put the app in the state the item means
    # to test, so the item cannot pass (and the failure must be visible).
    set setupOK [expr {![info exists setupError]}]
    set ok [expr {$predicateOK && $destructOK && $clarifyOK && $setupOK && $turnEnded}]

    set log [file join $::RequestEval::Work items $id.txt]
    set f [open $log w]; fconfigure $f -encoding utf-8
    puts $f "id: $id"
    puts $f "mode: $::RequestEval::Mode"
    puts $f "area: [dict get $item area]"
    puts $f "request: $request"
    puts $f "multi: [expr {[dict exists $item multi] && [dict get $item multi]}]"
    puts $f "loose: [expr {[dict exists $item loose] && [dict get $item loose]}]"
    puts $f "provider: $::ai::provider::Config(name) [::ai::provider::model]"
    puts $f "models called: [lsort -unique $::RequestEval::Models] ([llength $::RequestEval::Models] calls)"
    puts $f "route mode: $::application::assistant::RouteMode routed=$::RequestEval::Routed id=$::RequestEval::RoutedId"
    puts $f "setup result: $setupOK [expr {[info exists setupError] ? $setupError : ""}]"
    puts $f "predicate: $predicate"
    puts $f "predicate result: $predicateOK $predicateError"
    puts $f "destructive audit: $destructOK bad=[list $bad]"
    puts $f "clarifying questions: $questions (ok $clarifyOK)"
    puts $f "turn ended: $turnEnded"
    puts $f "seconds: [format %.1f $seconds]"
    puts $f "calls:"
    foreach c $Calls {
        puts $f "  [dict get $c name] [dict get $c args] -> [dict get $c outcome]"
        regsub -all {\s+} [dict get $c reply] { } reply
        puts $f "    [string range $reply 0 400]"
    }
    puts $f "opened: $::RequestEval::Opened"
    puts $f "state: db=[ev_db] game=[ev_gameno] ply=[ev_ply] tab=[ev_tab] filter=[catch {ev_search_count} x; set x]/[catch {ev_total_games} y; set y] engines=[catch {ev_engine_running} z; set z]"
    puts $f "events: $::RequestEval::Events"
    puts $f "reply: $said"
    close $f

    return [dict create id $id area [dict get $item area] ok $ok \
        predicate $predicateOK destruct $destructOK clarify $clarifyOK setup $setupOK \
        seconds $seconds calls $Calls questions $questions said $said \
        multi [expr {[dict exists $item multi] && [dict get $item multi]}] \
        loose [expr {[dict exists $item loose] && [dict get $item loose]}]]
}

# ----------------------------------------------------------------------
# Main.
# ----------------------------------------------------------------------
# Rebuild an item's result from its finished log, for a restarted run that
# must not ask the same cloud model the same request twice.
proc ::RequestEval::DoneResult {item} {
    set id [dict get $item id]
    set log [file join $::RequestEval::Work items $id.txt]
    if {![file exists $log]} { return "" }
    set f [open $log]; fconfigure $f -encoding utf-8
    set data [read $f]; close $f
    if {![regexp {predicate result: ([01])} $data -> pred]} { return "" }
    if {![regexp {destructive audit: ([01])} $data -> destruct]} { return "" }
    if {![regexp {clarifying questions: [0-9]+ \(ok ([01])\)} $data -> clarify]} { return "" }
    if {![regexp {setup result: ([01])} $data -> setup]} { return "" }
    set ended 1
    catch { regexp {turn ended: ([01])} $data -> ended }
    set seconds 0.0
    catch { regexp {seconds: ([0-9.]+)} $data -> seconds }
    set calls {}
    foreach line [split $data \n] {
        if {[regexp {^  (\S+) (.*) -> (\S+)$} $line -> name args outcome]} {
            lappend calls [dict create name $name args $args outcome $outcome reply ""]
        }
    }
    set ok [expr {$pred && $destruct && $clarify && $setup && $ended}]
    return [dict create id $id area [dict get $item area] ok $ok \
        predicate $pred destruct $destruct clarify $clarify setup $setup \
        seconds $seconds calls $calls questions 0 said "" \
        multi [expr {[dict exists $item multi] && [dict get $item multi]}] \
        loose [expr {[dict exists $item loose] && [dict get $item loose]}]]
}

proc ::RequestEval::Main {} {
    variable MainDb
    variable Variant Normal

    ::RequestEval::Trace "main start provider=$::ai::provider::Config(name) model=[::ai::provider::model]"
    set ::action::ConfirmHook ::RequestEval::Confirm
    set ::action::BulkHook ::RequestEval::Confirm
    set ::application::ai::Config(provider) $::ai::provider::Config(name)
    set ::application::ai::Config(model) [::ai::provider::model]
    ::RequestEval::Trace "fixtures"
    MakeFixtures
    ::RequestEval::Trace "openBase"
    set ok [::application::database::openBase .application $MainDb yes \
        -encoding $::encoding::autoEncoding -switchToBase 1]
    if {!$ok} { error "cannot open $MainDb" }
    ::RequestEval::Trace "opened" 
    # ActiveBase is the application's own (the active database); Reset makes
    # the main database active before every item.
    # a real engine for the analysis items
    ::RequestEval::Trace "engines [llength $::engine::Engines]"
    if {![llength $::engine::Engines]} {
        ::scidb::file::engines [file join $::RequestEval::Work engines.dat]
        set ::engine::Engines {}
    }
    ::RequestEval::Trace "after file engines [llength $::engine::Engines]"
    ::RequestEval::Trace "after add engine (bundled only)"
    ::RequestEval::Trace "game new"
    ::game::new .application -base $MainDb -variant Normal -number 9
    ::RequestEval::Trace "game done"
    set plies [::scidb::game::query mainline]
    if {[llength $plies] > 11} { catch { ::scidb::game::go key [lindex $plies 11 0] } }
    update

    after 250 ::RequestEval::WatchDialogs
    set f [open $::RequestEval::Corpus r]; fconfigure $f -encoding utf-8
    set lines [split [read $f] \n]; close $f

    set report [open [file join $::RequestEval::Work report.txt] w]
    fconfigure $report -encoding utf-8
    puts $report "# request evaluation"
    puts $report "# provider: $::ai::provider::Config(name) [::ai::provider::model]"
    puts $report "# route mode: $::application::assistant::RouteMode"
    puts $report "# corpus: $::RequestEval::Corpus sha256 [::RequestEval::Sha256 $::RequestEval::Corpus]"
    puts $report "# mode: $::RequestEval::Mode"
    puts $report [format "%-4s %-12s %-24s %6s %5s %s" RESULT AREA ID SEC MULTI CALLS]
    flush $report
    set total 0; set good 0
    set mTotal 0; set mGood 0
    set lTotal 0; set lGood 0
    array set areaTotal {}
    array set areaGood {}
    set failed {}
    foreach line $lines {
        if {[string trim $line] eq ""} continue
        set item [::json::json2dict $line]
        set id [dict get $item id]
        set matched 0
        foreach m [split $::RequestEval::Match ,] {
            if {[string match $m $id]} { set matched 1; break }
        }
        if {!$matched} continue
        set r ""
        if {$::RequestEval::SkipDone} { set r [DoneResult $item] }
        if {$r eq ""} {
            if {[catch { RunItem $item } r]} {
                puts $report [format "ERR  %-12s %-24s %s" [dict get $item area] $id $r]
                continue
            }
        }
        incr total; incr good [dict get $r ok]
        set area [dict get $item area]
        if {![info exists areaTotal($area)]} { set areaTotal($area) 0; set areaGood($area) 0 }
        incr areaTotal($area); incr areaGood($area) [dict get $r ok]
        if {[dict get $r multi]} { incr mTotal; incr mGood [dict get $r ok] }
        if {[dict get $r loose]} { incr lTotal; incr lGood [dict get $r ok] }
        set callnames [join [lmap c [dict get $r calls] { set n [dict get $c name]; if {[dict get $c outcome] in {error declined}} { set n "$n!" }; set n }] ,]
        puts $report [format "%-4s %-12s %-24s %6.1f %5s %s" \
            [expr {[dict get $r ok] ? "ok" : "MISS"}] $area $id \
            [dict get $r seconds] [expr {[dict get $r multi] ? "m" : ""}] $callnames]
        flush $report
        if {![dict get $r ok]} { lappend failed $id }
    }
    puts $report ""
    foreach area [lsort [array names areaTotal]] {
        puts $report [format "AREA %-12s %d/%d" $area $areaGood($area) $areaTotal($area)]
    }
    puts $report [format "MULTI %d/%d" $mGood $mTotal]
    puts $report [format "LOOSE %d/%d" $lGood $lTotal]
    puts $report [format "TOTAL %d/%d (%.0f%%) provider=%s/%s route=%s" \
        $good $total [expr {$total ? 100.0 * $good / $total : 0}] \
        $::ai::provider::Config(name) [::ai::provider::model] \
        $::application::assistant::RouteMode]
    if {[llength $failed]} { puts $report "FAILED: [join $failed { }]" }
    close $report
    if {$::RequestEval::RecordFile ne ""} {
        set f [open $::RequestEval::RecordFile w]; fconfigure $f -encoding utf-8
        puts $f [::json::dict2json $::RequestEval::Record]; close $f
    }
    puts [format "TOTAL %d/%d (%.0f%%) MULTI %d/%d LOOSE %d/%d provider=%s/%s route=%s" \
        $good $total [expr {$total ? 100.0 * $good / $total : 0}] $mGood $mTotal $lGood $lTotal \
        $::ai::provider::Config(name) [::ai::provider::model] \
        $::application::assistant::RouteMode]
    exit 0
}

set ::RequestEval::Corpus $corpus
if {[info exists ::env(SCIDB_EVAL_HOOK)] && $::env(SCIDB_EVAL_HOOK) ne ""} { source $::env(SCIDB_EVAL_HOOK) }
::RequestEval::Main
