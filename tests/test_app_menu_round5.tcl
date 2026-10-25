# Round 5 handler tests. Also runnable with plain tclsh: real procedure bodies
# run in an isolated interpreter, with only UI/database/engine boundaries stubbed.
package require tcltest 2.5
namespace eval ::scidb::test::r5 { variable definitions {} }
proc ::scidb::test::r5::extract {script {ns ::}} {
    variable definitions
    set buf {}
    foreach line [split $script \n] {
        append buf $line \n
        if {![info complete $buf]} continue
        set s [string trim $buf]; set buf {}
        if {$s eq {} || [string index $s 0] eq "#" || [catch {llength $s}]} continue
        if {[lindex $s 0] eq "namespace" && [lindex $s 1] eq "eval"} {
            set name [lindex $s 2]
            if {![string match ::* $name]} {set name ${ns}::$name}
            extract [lindex $s 3] $name
        } elseif {[lindex $s 0] eq "proc" && [llength $s] == 4} {
            set name [lindex $s 1]
            if {![string match ::* $name]} {set name ${ns}::$name}
            lappend definitions [list namespace eval [namespace qualifiers $name] {}] \
                [list proc $name [lindex $s 2] [lindex $s 3]]
        }
    }
}
set r5root [file dirname [file dirname [file normalize [info script]]]]
if {[info exists ::env(R5_SOURCE_ROOT)]} {set r5root $::env(R5_SOURCE_ROOT)}
foreach f {actions eventtable app-pgn context game dropdown menu info gametable app-analysis app-board app-assistant-offers app-twm app-database-search-nl app-database-openingprep} {
    set fd [open [file join $r5root tcl $f.tcl]]
    ::scidb::test::r5::extract [read $fd]
    close $fd
}
proc ::scidb::test::r5::run {script} {
    variable definitions
    set ip [interp create]
    try {
        foreach definition $definitions {interp eval $ip $definition}
        interp eval $ip {
            namespace eval ::scidb::db {}
            namespace eval ::scidb::game {}
            namespace eval ::scidb::engine {}
            namespace eval ::application::pgn {}
            namespace eval ::web {}
            namespace eval ::widget {}
            namespace eval ::debuglog {}
            namespace eval ::board {}
            namespace eval ::log {}
            namespace eval ::application::database::mc {}
            proc ::log::error {args} {set ::reported $args}
            namespace eval ::engine {}
            proc ::debuglog::log {args} {set ::logged $args}
            proc ::menu::CurrentBase {} {return selectedBase}
            proc ::scidb::db::get {what args} {
                switch $what {readonly? {return [expr {[lindex $args 0] eq "readonlyBase"}]} variant? {return Normal} deleted? {return 0}}
            }
            proc ::engine::active? {n} {expr {$n == 2}}
            proc ::engine::id {n} {return 42}
            proc ::scidb::game::switch {pos} {set ::switched $pos}
            proc ::application::pgn::saveGame {mode {base ""}} {set ::saved [list $mode $base]}
            proc ::application::pgn::historyChanged {} {}
        }
        return [interp eval $ip $script]
    } finally {interp delete $ip}
}
foreach id {c3.delete c3.flags c3.flag.1 c3.flag.2 c3.flag.3 c3.flag.4 c3.flag.5 c3.flag.6 c3.flag.7 c3.flag.8 c3.flag.9 c3.flag.10 c3.flag.11 c3.flag.12 c3.flag.13 c3.flag.14 c3.flag.15 c3.flag.16 c3.flag.17 c3.flag.18 c3.flag.19 c4.import.pgn} {
    tcltest::test r5-writable-$id {predicate uses the object base, not the selected database} -body {
        ::scidb::test::r5::run [format {
            list [::context::ObjectRule %s {base readonlyBase}] [::context::ObjectRule %s {base writableBase}]
        } $id $id]
    } -result {{1 0} {1 1}}
}
# Evaluate rules, not just their command construction.
tcltest::test r5-writable-values {read-only objects disable mutations; writable objects enable them} -body {
    ::scidb::test::r5::run {
        list [::context::ObjectRule c3.delete {base readonlyBase}] \
            [::context::ObjectRule c3.flag.19 {base writableBase}] \
            [::context::ObjectRule c4.import.pgn {base readonlyBase}]
    }
} -result {{1 0} {1 1} {1 0}}
tcltest::test r5-delete-error {delete failure is reported and busy cursor released} -body {
    ::scidb::test::r5::run {
        proc ::widget::busyCursor {state} {lappend ::busy $state}
        proc ::scidb::db::set {args} {error {Database is read-only}}
        set result [::context::Invoke c3.delete {base readonlyBase index 3}]
        list $result $::busy [string match {*Database is read-only*} $::reported]
    }
} -result {{error: Database is read-only} {on off} 1}
foreach {action mode} {replace replace replace_moves moves new add} {
    tcltest::test r5-tab-save-$action {save selects the clicked tab and derives its linked database} -body {
        ::scidb::test::r5::run [format {
            ::context::Command c12.save.%s {parent .bar id 4 gameSlot 4}
            list $::switched $::saved
        } $action]
    } -result [list 4 [list $mode {}]]
}
tcltest::test r5-tab-history {remove matches the tab source key rather than a nonexistent popup field} -body {
    ::scidb::test::r5::run {
        set ::game::List [list [list {} {} {} {} {other pgn 5 Normal}] [list {} {} {} {} {base pgn 7 Normal}]]
        set ::game::History {{{tags} {base pgn 7 Normal} crc utf-8} {{other} {other pgn 5 Normal} crc utf-8}}
        ::context::Command c12.remove_history {parent .bar id 1 gameSlot 1}
        list [llength $::game::History] [lindex $::game::History 0 1] [::game::historyIndex -1]
    }
} -result {1 {other pgn 5 Normal} -1}
tcltest::test r5-ask-context {context help reaches the offers namespace} -body {
    ::scidb::test::r5::run {
        proc ::application::assistant::offers::askAbout {text} {set ::asked $text}
        set text [::application::assistant::askContext {pane board}]
        list [expr {$text eq $::asked}] $text
    }
} -result {1 {What can I do here? (pane=board)}}
tcltest::test r5-search-destroy {child destruction retains search state; parent destruction clears it} -body {
    ::scidb::test::r5::run {
        set ::application::database::PlainSearchData(.search,job) {}
        ::application::database::PlainDestroyed .search .search.child
        set child [info exists ::application::database::PlainSearchData(.search,job)]
        ::application::database::PlainDestroyed .search .search
        list $child [array names ::application::database::PlainSearchData .search,*]
    }
} -result {1 {}}
tcltest::test r5-history-recent {recent opens a history entry rather than treating a path as a slot} -body {
    ::scidb::test::r5::run {
        set ::game::History {{tags {/tmp/game.pgn pgn 5 Normal} crc utf-8}}
        proc ::game::openGame {parent index} {set ::opened [list $parent $index]}
        ::menu::Do menu.game.history.recent
        set ::opened
    }
} -result {.application 0}
tcltest::test r5-layout-fresh {manage can inspect a layout before any saved snapshot exists} -body {
    ::scidb::test::r5::run {
        set ::application::Vars(.twm:id) board
        set ::application::Vars(board:layout:variant) normal
        proc ::application::twm::inspectLayout {twm} {return liveLayout}
        ::application::twm::savedLayout .twm
    }
} -result liveLayout
tcltest::test r5-docked-topmost {docked panes disable floating-only operations and direct invocation is harmless} -body {
    ::scidb::test::r5::run {
        proc ::menu::PaneFloating {uid twm} {return 0}
        list [::context::ObjectRule c9.stay_on_top {paneUid board twm .twm}] \
            [::context::Command c9.stay_on_top {paneUid board twm .twm frame .frame}]
    }
} -result {{1 0} {}}
tcltest::test r5-board-hidden {updates after hiding the board never access deleted diagram state} -body {
    ::scidb::test::r5::run {
        set ::application::board::board .destroyed
        proc winfo {op w} {return 0}
        proc ::application::board::goto {step} {return $step}
        list [::application::board::update 1 set position {}] [::application::board::updateMarks {}] \
            [::application::board::Goto +1]
    }
} -result {{} {} +1}
foreach id {c6.pause_resume c6.opponents_view c6.lock_engine c6.best_first c6.add_move c6.add_sequence c6.add_line c6.add_all c6.add_merge c6.add_include c6.insert_comment c6.pin_repertoire c9.analysis.opponents} {
    tcltest::test r5-engine-predicate-$id {only the object's own live engine enables a row} -body {
        ::scidb::test::r5::run [format {
            list [::context::ObjectRule %s {number 1 engine 42}] [::context::ObjectRule %s {number 2 engine -1}]
        } $id $id]
    } -result {{1 0} {1 1}}
}
tcltest::test r5-engine-idle {pause and opponent view safely reject an engine that has not started} -body {
    ::scidb::test::r5::run {
        namespace eval ::application::analysis::.tree {variable Vars; set Vars(number) 1}
        list [::application::analysis::Pause .tree] [::application::analysis::restartAnalysis 1] \
            [::context::Command c6.opponents_view {number 1 tree .tree}]
    }
} -result {{} {} {}}
foreach {where expected} {atend seq middle line} {
    tcltest::test r5-sequence-$where {sequence appends only at a line end and preserves a middle continuation as a variation} -body {
        ::scidb::test::r5::run [format {
            namespace eval ::application::analysis::.tree {variable Vars; set Vars(number) 2}
            proc ::application::pgn::ensureScratchGame {} {return 0}
            proc ::scidb::engine::snapshot {id args} {
                if {![llength $args]} {return %s}
                set ::inserted [list $id {*}$args]
            }
            ::context::Command c6.add_sequence {number 2 tree .tree lineId 0}
            set ::inserted
        } $where]
    } -result [list 42 $expected 0]
}
foreach id {c5.open_switcher c5.save_working_set} {
    tcltest::test r5-player-filter-$id {both player result actions pass the native OR query grammar and close the view} -body {
        ::scidb::test::r5::run [format {
            namespace eval ::scidb::view {}
            proc ::scidb::view::new {args} {return 8}
            proc ::scidb::view::search {base variant view a b query} {
                if {[lindex $query 0] ne "OR"} {error {usage error}}
                set ::query $query
            }
            proc ::scidb::view::close {args} {set ::closed $args}
            proc ::application::database::OpenFilteredViewInSwitcher {args} {}
            proc ::application::database::SaveFilteredViewAsWorkingSet {args} {}
            ::context::Command %s {base test variant Normal kind player name {A Player}}
            list $::query $::closed
        } $id]
    } -result {{OR {playername white {A Player}} {playername black {A Player}}} {test Normal 8}}
}
tcltest::test r5-site-url {a city never opens a browser; an actual URL does} -body {
    ::scidb::test::r5::run {
        proc ::gamestable::GetSite {args} {return $::site}
        proc ::web::isWebLink {url} {string match https://* $url}
        proc ::web::open {parent url} {set ::opened $url}
        set object {parent .application path .games base test variant Normal view 0 index 1}
        set ::site Budva
        set city [::context::ObjectRule c3.open_url $object]
        ::context::Command c3.open_url $object
        set unvisited [expr {![info exists ::opened]}]
        set ::site https://example.org/game
        ::context::Command c3.open_url $object
        list $city $unvisited $::opened
    }
} -result {{0 1} 1 https://example.org/game}
tcltest::test r5-support-site {support action is assistant-visible and opens the configured site} -body {
    ::scidb::test::r5::run {
        set ::action::Registry {}; set ::action::ConfirmHook {}; set ::action::BulkHook {}
        set ::menu::DropdownOrder 0
        proc ::menu::MC {name} {return $name}
        ::menu::DefineTree
        ::menu::RegisterTree
        proc ::web::open {parent url} {set ::opened [list $parent $url]}
        set ::menu::SupportURL https://chesswizapp.com/support.html
        ::action::run menu.help.support
        set first $::opened
        set ::menu::SupportURL https://example.org/support
        ::action::run menu.help.support
        list [dict get [::action::get menu.help.support] ai] $first $::opened
    }
} -result {1 {.application https://chesswizapp.com/support.html} {.application https://example.org/support}}
tcltest::test r5-support-no-url {an empty support setting opens no browser} -body {
    ::scidb::test::r5::run {
        set ::menu::SupportURL {}
        proc ::web::open {args} {error {unexpected browser}}
        ::menu::Do menu.help.support
    }
} -result {}
tcltest::test r5-about-support {About uses the same setting as the Help action} -body {
    ::scidb::test::r5::run {
        set ::menu::SupportURL https://example.org/support
        proc ::web::open {parent url} {set ::opened [list $parent $url]}
        proc supportNode {method args} {
            if {$method eq "attribute"} {return chesswiz:support}
        }
        ::info::Mouse1Up .about supportNode
        set ::opened
    }
} -result {.about https://example.org/support}
tcltest::test r5-contact-no-url {unconfigured contact actions cannot open upstream trackers} -body {
    ::scidb::test::r5::run {
        set ::menu::BugTracker {}; set ::menu::FeatureRequestTracker {}
        proc ::web::open {args} {error {unexpected browser}}
        list [::menu::Do menu.help.bug] [::menu::Do menu.help.feature]
    }
} -result {{} {}}
tcltest::test r5-contact-site {contact actions open the Chesswiz feedback page} -body {
    ::scidb::test::r5::run {
        set ::menu::BugTracker https://chesswizapp.com/feedback.html#bug
        set ::menu::FeatureRequestTracker https://chesswizapp.com/feedback.html#feature
        set ::opened {}
        proc ::web::open {parent url} {lappend ::opened $url}
        ::menu::Do menu.help.bug; ::menu::Do menu.help.feature
        set ::opened
    }
} -result {https://chesswizapp.com/feedback.html#bug https://chesswizapp.com/feedback.html#feature}
tcltest::test r5-eco-no-conversion {ECO statistics reach the report without optional conversion advice} -body {
    ::scidb::test::r5::run {
        proc ::application::database::RecommendSciWorkflow {args} {error {unexpected conversion prompt}}
        proc ::application::database::OpeningPrepDialogName {file variant} {error report-dialog-reached}
        catch {::application::database::OpenOpeningPrepReport .application test.pgn Normal} result
        set result
    }
} -result report-dialog-reached

# Round 6: exercise the real C2/C9 handlers and context builders without a
# display. Native modal dismissal leaves an existing, unmapped menu; X11
# returns while it is still mapped. Neither path may depend on destruction.
foreach {cid handler} {C2 {::application::pgn::PopupMenu .notation 0} C9 {::application::twm::Menu .pane .frame 10 20}} {
    foreach modal {0 1} {
        tcltest::test r6-reopen-$cid-$modal {dismissed popups rebuild; posted popups reject duplicate clicks} -body {
            ::scidb::test::r5::run [list apply {{handler modal} {
                namespace eval ::annotation::mc {}
                namespace eval ::notation {}
                namespace eval ::context::mc {variable WhatCanIDo Help}
                set ::context::Counter 0
                set ::created 0
                set ::posts {}
                set ::modal $modal
                proc ::context::Rows {cid object} {return [lrepeat 32 ask]}
                proc ::context::HasObject {cid object} {return 1}
                proc ::scidb::game::link? {position} {return {base Normal 0}}
                proc ::scidb::game::ply {} {return 1}
                proc .pane {args} {return board}
                proc bind {args} {}
                proc wm {args} {}
                proc winfo {op w} {
                    switch $op {
                        exists {return [info exists ::entries($w)]}
                        ismapped {return $::mapped($w)}
                        pointerxy {return {10 20}}
                        default {error "unexpected winfo $op"}
                    }
                }
                proc menu {w args} {
                    if {[info exists ::entries($w)]} {error {menu already exists}}
                    set ::entries($w) 0
                    set ::mapped($w) 0
                    incr ::created
                    interp alias {} $w {} menuOp $w
                }
                proc menuOp {w op args} {
                    switch $op {
                        add {incr ::entries($w)}
                        unpost {set ::mapped($w) 0}
                        default {error "unexpected menu operation $op"}
                    }
                }
                proc destroy {w} {
                    unset ::entries($w) ::mapped($w)
                    rename $w {}
                }
                proc tk_popup {w args} {
                    set ::mapped($w) 1
                    lappend ::posts [list $::created $::entries($w)]
                    if {$::modal} {$w unpost}
                }
                {*}$handler
                set w [expr {[lindex $handler 0] eq "::application::pgn::PopupMenu" ? ".notation.__menu__" : ".pane.__menu__"}]
                if {!$modal} {
                    # The X11-style immediate return must not destroy a live popup.
                    {*}$handler
                    if {$::created != 1 || [llength $::posts] != 1} {error {duplicate popup}}
                    $w unpost
                }
                if {![winfo exists $w] || [winfo ismapped $w]} {error {dismissal fixture failed}}
                {*}$handler
                set ::posts
            }} $handler $modal]
        } -result {{1 32} {2 32}}
    }
}

# Round 7: execute the actual command emitted by AddRow, through the registry.
tcltest::test r7-c6-menu-object {all C6 leaves validate the wrapped live object} -body {
    ::scidb::test::r5::run {
        set ::action::Registry {}; set ::action::ConfirmHook {}; set ::action::BulkHook {}
        set ::context::Predicates {}
        ::context::Declare
        set ::seen {}
        proc ::context::Invoke {id object} {lappend ::seen [list $id $object]}
        proc .menu {op type args} {
            set ::command [dict get $args -command]
            set ::rowState [dict get $args -state]
        }
        set object {number 2 tree .tree engine 42 lineId 0 pv {e4 e5}}
        set failures {}
        foreach id [array names ::context::Labels c6.*] {
            if {$id in {c6.multiple_variations c6.lines_per_variation}} continue
            ::context::AddRow .menu $id $object
            if {$::rowState ne "normal"} {lappend failures [list $id disabled]}
            set result [uplevel #0 $::command]
            update idletasks
            if {[string match error:* $result] || [lindex $::seen end] ne [list $id $object]} {
                lappend failures [list $id $result]
            }
        }
        set failures
    }
} -result {}
tcltest::test r7-explain-line {C6 calls the existing explanation feature with the clicked PV and FEN} -body {
    ::scidb::test::r5::run {
        namespace eval ::application::ai {}
        namespace eval ::scidb::pos {}
        proc ::scidb::pos::fen {} {return positionFen}
        proc ::application::ai::explainLine {args} {set ::explained $args}
        ::context::Command c6.explain_line {number 2 parent .app pv {e4 e5}}
        set ::explained
    }
} -result {.app {e4 e5} positionFen}

foreach id {c5.event_table c5.event_url c6.explain_line} {
    tcltest::test r7-popup-defer-$id {menu callbacks return before dialog or AI work starts} -body {
        ::scidb::test::r5::run [list apply {{id} {
            set ::posted 1; set ::called {}
            proc ::action::Dispatch {id args approval} {
                if {$::posted} {error {handler reentered native popup tracking}}
                set ::called [::list $id [lindex $args 0]]
            }
            set object {base test variant Normal view 7 index 3 pv {e4 e5} number 2}
            ::action::run $id [dict create object $object defer idle]
            set deferred [expr {$::called eq {}}]
            set ::posted 0
            update idletasks
            list $deferred [expr {$::called eq [list $id [list object $object]]}]
        }} $id]
    } -result {1 1}
}
tcltest::test r7-event-table {tournament table receives the clicked event and view} -body {
    ::scidb::test::r5::run {
        namespace eval ::crosstable {}
        proc ::crosstable::open {args} {set ::opened $args}
        ::context::Command c5.event_table {parent .events base db variant Normal index 3 view 7}
        set ::opened
    }
} -result {.events db Normal 3 7 event}
tcltest::test r7-event-url {event URL reaches the browser only for a real link} -body {
    ::scidb::test::r5::run {
        proc ::eventtable::GetSite {args} {set ::siteArgs $args; return $::site}
        proc ::web::isWebLink {url} {string match https://* $url}
        proc ::web::open {parent url} {set ::opened [list $parent $url]}
        set object {parent .events base db variant Normal index 3 view 7}
        set ::site London
        ::context::Command c5.event_url $object
        set city [info exists ::opened]
        set ::site https://example.org/tournament
        ::context::Command c5.event_url $object
        list $city $::siteArgs $::opened
    }
} -result {0 {db Normal 7 3} {.events https://example.org/tournament}}
tcltest::test r7-engine-expired {registry rejects a menu object after its engine stops} -body {
    ::scidb::test::r5::run {
        set ::action::Registry {}; set ::action::ConfirmHook {}; set ::action::BulkHook {}
        set ::context::Predicates {}
        ::context::Declare
        proc ::context::Invoke {args} {error {must not run}}
        ::action::run c6.pause_resume {object {number 1 tree .tree engine 42}}
    }
} -result {error: action 'c6.pause_resume' is not available here}

tcltest::test r7-live-engine-handlers {real menu commands change MultiPV and pause/resume the clicked pane} -body {
    ::scidb::test::r5::run {
        set ::action::Registry {}; set ::action::ConfirmHook {}; set ::action::BulkHook {}
        set ::context::Predicates {}; ::context::Declare
        namespace eval ::application::analysis::.tree {
            variable Vars
            array set Vars {number 2 engine:pause 0 engine:stopped 0 after:id {}}
        }
        namespace eval ::application::analysis::2 {
            variable Options
            array set Options {engine:singlePV 1 engine:multiPV 1 engine:bestFirst 1}
        }
        proc ::application::analysis::MultiPV {number} {
            return $::application::analysis::2::Options(engine:multiPV)
        }
        proc ::application::analysis::Layout {tree} {}
        proc ::scidb::engine::multiPV {id n} {set ::multi [list $id $n]}
        proc ::engine::pause {number} {lappend ::transitions [list pause $number]}
        proc ::engine::resume {number} {lappend ::transitions [list resume $number]}
        proc .menu {op type args} {set ::command [dict get $args -command]}
        set object {number 2 tree .tree engine 42 lineId 0 pv {e4 e5}}
        foreach id {c6.multi.3 c6.pause_resume c6.pause_resume} {
            ::context::AddRow .menu $id $object
            uplevel #0 $::command
            update idletasks
        }
        list $::multi $::transitions [set ::application::analysis::.tree::Vars(engine:pause)]
    }
} -result {{42 3} {{pause 2} {resume 2}} 0}

# UI lifecycle coverage for the orchestrator; no Xvfb is started by this file.
if {[llength [info commands winfo]]} {
    tcltest::test r5-plain-close {destroying the search dialog cleans its state without a late dlg substitution} -body {
        set dlg [::application::database::OpenPlainSearch .application [::menu::CurrentBase] [::menu::CurrentVariant]]
        set script [string map [list %W $dlg] [bind $dlg <Destroy>]]
        # Run the binding synchronously so background errors cannot evade tcltest.
        uplevel #0 $script
        destroy $dlg
        expr {![llength [array names ::application::database::PlainSearchData $dlg,*]]}
    } -result 1
    tcltest::test r5-hide-navigate {hiding the board leaves navigation and refresh usable} -setup {
        ::application::switchTab board
        update
        set wasShown [::menu::PaneChecked board]
        if {!$wasShown} {::menu::Do menu.view.panes.board; update}
    } -body {
        ::menu::Do menu.view.panes.board
        update
        set hidden [expr {![winfo exists $::application::board::board]}]
        set results {}
        foreach id {nav-start nav-forward nav-back nav-end} {
            lappend results [string match {error:*} [::action::run $id]]
        }
        ::scidb::game::refresh [::scidb::game::current]
        list $hidden $results
    } -cleanup {
        if {[::menu::PaneChecked board] != $wasShown} {::menu::Do menu.view.panes.board}
        update
    } -result {1 {0 0 0 0}}

    set r5idleTrees {}
    foreach n [array names ::application::analysis::NumberToTree] {
        if {![::engine::active? $n]} {lappend r5idleTrees $::application::analysis::NumberToTree($n)}
    }
    tcltest::testConstraint r5IdlePane [expr {[llength $r5idleTrees] > 0}]
    tcltest::test r5-idle-toolbar {an unstarted analysis pane disables pause, lock and opponent controls} -constraints r5IdlePane -body {
        set states {}
        foreach tree $r5idleTrees {
            upvar #0 ::application::analysis::${tree}::Vars vars
            foreach key {pause lock opponent} {
                lappend states [::toolbar::childcget $vars(widget:button:$key) -state]
            }
        }
        expr {[lsearch -not -exact $states disabled] < 0}
    } -result 1

    proc ::scidb::test::r5::waitForPV {number} {
        set deadline [expr {[clock milliseconds] + 20000}]
        while {[clock milliseconds] < $deadline} {
            set id [::engine::id $number]
            if {$id >= 0 && [::scidb::engine::bound? $id] && ![::scidb::engine::empty? $id 0]} {return}
            after 50 {set ::scidb::test::r5::tick 1}
            vwait ::scidb::test::r5::tick
        }
        error "engine $number did not produce a PV"
    }
    tcltest::testConstraint r5Engine [expr {[llength $::engine::Engines] > 0}]
    tcltest::test r5-live-sequence {real engine sequence appends at the end and inserts a variation in the middle} -constraints r5Engine -setup {
        set previous [::scidb::game::current]
        set runningBefore [::application::analysis::Running]
        set pos [::game::new .application -variant Normal]
        if {$pos < 0} {error "could not allocate test game"}
        ::application::switchTab board
        ::application::assistant::runTool start_engine {lines 1 threads 1 hash 16}
        set number [lindex [::application::analysis::Running] 0]
        if {$number eq ""} {error "engine did not start"}
        ::scidb::test::r5::waitForPV $number
        set tree $::application::analysis::NumberToTree($number)
        set object [dict create number $number tree $tree lineId 0]
    } -body {
        ::context::Command c6.add_sequence $object
        set appended [expr {[::scidb::game::query length] > 0}]
        ::scidb::game::go -1 start
        ::scidb::test::r5::waitForPV $number
        set before [::scidb::game::variation count]
        ::context::Command c6.add_sequence $object
        list $appended [expr {[::scidb::game::variation count] > $before}]
    } -cleanup {
        foreach n [::application::analysis::Running] {
            if {$n ni $runningBefore} {::application::analysis::stopEngine $n}
        }
        if {$pos >= 0} {::application::pgn::release $pos; ::game::release $pos}
        if {$previous >= 0} {::scidb::game::switch $previous}
    } -result {1 1}

    foreach id {menu.help.bug menu.help.feature} {
        tcltest::test r5-shown-$id {configured tracker shows the contact row} -body {
            dict get [::menu::state $id] visible
        } -result 1
    }
}
tcltest::cleanupTests
