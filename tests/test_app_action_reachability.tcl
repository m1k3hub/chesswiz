# Fresh-start operator audit. Run alone through run_app_tests.tcl under Xvfb.
# Each UI case gets its own HOME and process; handlers are never stubbed.
# Aqua native OS dialogs are observed/driven at the Tk-to-OS boundary,
# since they are not windows the mapped-Tk cancellation driver can inspect.
package require tcltest 2.5
namespace eval ::scidb::test::reachability {
    variable file [file normalize [info script]]
    variable root [file dirname [file dirname $file]]
    variable seen {}
    variable baseline {}
    variable inAction 0
    variable nativeInstalled 0
    variable nativeAccept 0
    # Exact exclusions from the UI/dialog probes, not from registry checks.
    variable skips {
        menu.view.panes.players {database pane; unavailable in the board layout}
        menu.view.panes.events {database pane; unavailable in the board layout}
        menu.view.panes.sites {database pane; unavailable in the board layout}
        menu.view.panes.annotators {database pane; unavailable in the board layout}
        menu.view.panes.positions {database pane; unavailable in the board layout}
        menu.tools.file_types {changes operating-system file associations}
        menu.tools.legacy_fonts {installs files}
        menu.tools.voice {starts audio capture}
        menu.training.guess {starts a training session requiring a game}
        menu.training.studyplan {runs an engine job}
        menu.training.training_set {runs a database job}
        menu.training.check_results {runs a database job}
        menu.analysis.analyze {starts an engine job}
        menu.analysis.game_review {starts an engine job}
        menu.analysis.engine_toggle {starts an engine process}
        menu.analysis.explain.position {starts a model job}
        menu.analysis.explain.line {starts a model job}
        menu.analysis.explain.move {starts a model job}
        menu.analysis.explain.comment {starts a model job}
        menu.analysis.factcheck {starts a model job}
        menu.db.player.update {downloads and writes files}
        menu.db.player.names {database maintenance job}
        menu.help.bug {external submission workflow}
        menu.help.feature {external submission workflow}
        view.board3d.webgl {launches an external browser}
    }
    proc ready {} {
        nativeDialogs
        set deadline [expr {[clock milliseconds]+10000}]
        while {!$::application::Vars(ready)} {
            update
            if {[clock milliseconds]>$deadline} { error {startup timed out} }
            after 10
        }
        update
        catch {destroy .tipoftheday}
        update
    }
    proc windows {{w .}} {
        set out {}
        foreach child [winfo children $w] {
            if {[winfo toplevel $child] eq $child} { lappend out $child }
            lappend out {*}[windows $child]
        }
        return $out
    }
    proc snapshot {{w .}} {
        set out {}
        if {[winfo ismapped $w]} { lappend out $w }
        if {[winfo class $w] eq {TNotebook}} {
            lappend out [list $w [$w select]]
        }
        foreach child [winfo children $w] { lappend out {*}[snapshot $child] }
        if {$w eq {.}} {
            foreach suffix {board editor games players events sites annotators positions tree analysis media report assistant explorer} {
                catch {lappend out [list pane $suffix [::menu::PaneChecked $suffix]]}
            }
            foreach name {::font::Options ::board::layout ::board::hilite ::tablebase::Options ::application::board::Options ::application::focuszoom::enabled} {
                if {[array exists $name]} { lappend out [list $name [lsort -stride 2 -index 0 [array get $name]]] }
            }
            foreach name {::application::focuszoom::ratio ::application::focuszoom::pinBoard} {
                if {[info exists $name]} { lappend out [list $name [set $name]] }
            }
            lappend out [list fullscreen [::menu::fullscreen?]]
        }
        return $out
    }
    # Modal dialogs enter nested event loops. Observe first, then cancel via
    # their window-manager close protocol, just as closing the dialog would.
    proc cancelButton {w wanted} {
        foreach c [winfo children $w] {
            if {[winfo class $c] in {TButton Button} && [winfo name $c] in [list $wanted bt-$wanted]} {
                if {[$c cget -state] ne {disabled}} { return $c }
            }
            set button [cancelButton $c $wanted]
            if {$button ne {}} { return $button }
        }
        return {}
    }
    proc cancelDialogs {} {
        variable baseline
        variable seen
        variable inAction
        set current [snapshot]
        if {$current ne $::scidb::test::reachability::before} { set seen $current }
        # A non-modal report can map before its builder/refresh returns.
        # Observe it, but only drive Cancel once a real modal grab is held.
        # Destroying every mapped window after 500 ms interrupted Aqua's
        # slower report construction and turned a successful open into error.
        set modal [grab current]
        if {$modal ne {}} {set modal [winfo toplevel $modal]}
        foreach w [windows] {
            if {$w in $baseline || ![winfo exists $w] || ![winfo ismapped $w]} { continue }
            if {$inAction && $w ne $modal} {continue}
            set command [wm protocol $w WM_DELETE_WINDOW]
            if {[string trim $command] eq {#}} {
                # Question boxes intentionally disable the window close button.
                # Use their real Cancel/No control to leave the nested loop.
                foreach wanted {cancel no ok} {
                    set button [cancelButton $w $wanted]
                    if {$button ne {}} { catch {$button invoke}; break }
                }
            } elseif {$command ne {}} { catch {uplevel #0 $command} } else { catch {destroy $w} }
        }
        after 150 ::scidb::test::reachability::cancelDialogs
    }
    proc nativeDialog {command args} {
        variable seen
        variable nativeAccept
        if {[dict exists $args -parent] && ![winfo exists [dict get $args -parent]]} {
            error "$command requested a missing parent"
        }
        set seen [list native-dialog $command $args]
        if {$command eq "tk_messageBox"} {
            set type [expr {[dict exists $args -type] ? [dict get $args -type] : "ok"}]
            switch -- $type {
                yesno {set reply [expr {$nativeAccept ? "yes" : "no"}]}
                yesnocancel {set reply [expr {$nativeAccept ? "yes" : "cancel"}]}
                okcancel {set reply [expr {$nativeAccept ? "ok" : "cancel"}]}
                retrycancel {set reply cancel}
                abortretryignore {set reply abort}
                ok {set reply ok}
                default {error "unexpected native message-box type: $type"}
            }
            puts "EVIDENCE native-dialog command=$command type=$type response=$reply"
            if {[dict exists $args -icon] && [dict get $args -icon] eq "error"} {
                puts "EVIDENCE native-error message=[dict get $args -message]"
            }
            return $reply
        }
        puts "EVIDENCE native-dialog command=$command response=cancel"
        return {}
    }
    proc nativeAbout {command operation} {
        variable seen [list native-dialog $command]
    }
    proc nativePopup {menu args} {
        variable seen [list native-menu $menu $args]
        # Reuse the object's existing selected-row driver. Cocoa's native
        # tracking loop cannot be driven by the mapped-Tk polling timer.
        if {[lindex $::env(SCIDB_REACHABILITY_CASE) 0] eq "c1.insert_null"} {
            after 0 ::scidb::test::objects::chooseVariation
        } elseif {[lindex $::env(SCIDB_REACHABILITY_CASE) 0] eq "c8.move_actions"} {
            # Cancel at the AppKit handoff; the object probe inspects every
            # real menu command and its selected continuation on both systems.
            event generate $menu <<MenuUnpost>>
        }
    }
    proc nativeDialogs {} {
        variable nativeInstalled
        if {$nativeInstalled || [tk windowingsystem] ne "aqua"
            || ![info exists ::env(SCIDB_REACHABILITY_CASE)]} {return}
        # Each probe owns a process. Keep the OS boundary active through idle
        # callbacks and cleanup too: a Cancel may prompt after the handler
        # has returned. Application handlers and all data assertions stay real.
        foreach command {tk_chooseDirectory tk_getOpenFile tk_getSaveFile tk_messageBox} {
            rename ::$command [namespace current]::saved_$command
            interp alias {} ::$command {} [namespace current]::nativeDialog $command
        }
        # Observe the real, non-modal AppKit About API without replacing it.
        trace add execution ::tk::mac::standardAboutPanel enter [namespace current]::nativeAbout
        if {[lindex $::env(SCIDB_REACHABILITY_CASE) 0] in {c1.insert_null c6.copy_line c8.move_actions}
            && [llength [info commands ::scidb::test::objects::chooseVariation]]} {
            rename ::tk_popup [namespace current]::saved_tk_popup
            interp alias {} ::tk_popup {} [namespace current]::nativePopup
        }
        set nativeInstalled 1
    }
    proc runAction {script} {
        variable inAction
        set inAction 1
        set code [catch {uplevel 1 $script} reply options]
        set inAction 0
        return -options $options $reply
    }
    proc probe {id argv kind} {
        variable baseline [windows]
        variable seen {}
        variable before [snapshot]
        # Preserve the observed modal state even after the close protocol.
        after 500 ::scidb::test::reachability::cancelDialogs
        set reply [runAction [list ::action::run $id $argv]]
        update
        set after [snapshot]
        if {[string match error:* $reply]} { error "$id: $reply" }
        if {$kind eq {query} && [string trim $reply] ne {}} { return 1 }
        if {$before eq $after && ($seen eq {} || $seen eq $before)} {
            error "$id: no observable window, pane, tab or state change (reply: $reply)"
        }
        return 1
    }
    proc finished {pipe home id} {
        variable output
        variable running
        variable bad
        append output($pipe) [read $pipe]
        if {![eof $pipe]} { return }
        fileevent $pipe readable {}
        fconfigure $pipe -blocking 1
        set code [catch {close $pipe} err options]
        if {$code && [dict exists $options -errorcode]} {
            append err " (exit: [dict get $options -errorcode])"
        }
        if {$code || ![string match {*Total Passed: 1*Total Failed: 0*} $output($pipe)]} {
            lappend bad "$id: $output($pipe) $err"
            puts "OFFENDER $id: $output($pipe) $err"
        }
        unset output($pipe)
        file delete -force $home
        incr running -1
    }
    proc runCases {cases} {
        variable file
        variable root
        variable running 0
        variable bad {}
        variable output
        set serial 0
        set limit {timeout 35}
        # macOS has no GNU timeout. Tk also redirects output to its console
        # when a pipeline supplies no terminal, so give each child a PTY.
        if {[tk windowingsystem] eq "aqua"} {
            set limit {/usr/bin/script -q /dev/null perl -e {alarm shift; exec @ARGV} 35}
        }
        foreach case $cases {
            lassign $case id argv kind
            # X11 selections belong to the display, not the process/HOME.
            # Clipboard/import/comment probes must not affect a neighbour's
            # before/after snapshot or selection ownership.
            # The 35 s child watchdog includes native startup and shutdown.
            # Aqua engine discovery/startup must finish before another owned
            # probe starts competing for its native GUI/event-loop service.
            set exclusive [expr {[regexp {^c11\.|\.(copy|cut|paste|import)} $id]
                || ([tk windowingsystem] eq "aqua" && $kind eq "engine")}]
            while {$running >= 3 || ($exclusive && $running)} {
                vwait ::scidb::test::reachability::running
            }
            set home [file join $root tests tmp-app reachability-[pid]-[incr serial]]
            file mkdir $home
            puts "REACHABILITY $id $argv"; flush stdout
            set command [list env HOME=$home SCIDB_REACHABILITY_CASE=$case \
                {*}$limit [info nameofexecutable] [file join $root tests run_app_tests.tcl] \
                -file [file tail $file] -match *-probe]
            set pipe [open [list | {*}$command 2>@1] r]
            fconfigure $pipe -blocking 0
            set output($pipe) {}
            incr running
            fileevent $pipe readable [list ::scidb::test::reachability::finished $pipe $home $id]
            if {$exclusive} {
                while {$running} { vwait ::scidb::test::reachability::running }
            }
        }
        while {$running} { vwait ::scidb::test::reachability::running }
        return $bad
    }
    proc cases {} {
        variable skips
        set cases {}
        # These families only open UI or change reversible display state.
        foreach id [::action::list] {
            if {[dict exists $skips $id]} { continue }
            if {[regexp {^(menu\.(view\.(panes\.|font_|tip)|edit\.|board\.(setup|appearance\.)|analysis\.(engines$|engine_dictionary$|compare_engines$|review_engine$|annotate$|explorer$|tablebase\.)|training\.|tools\.|help\.about$|db\.discover$)|app-(help|log|fullscreen)$|view\.focus_)} $id]} {
                lappend cases [list $id {} ui]
            }
        }
        foreach id {menu.file.open menu.file.new.normal menu.file.new.three menu.file.new.crazy menu.file.new.variants menu.file.import.pgn menu.file.import.db} {
            lappend cases [list $id {} ui]
        }
        foreach tab {board database} { lappend cases [list switch_tab [list tab $tab] ui] }
        foreach kind {advanced material rating} { lappend cases [list open_search [list kind $kind] ui] }
        lappend cases [list pane {action undock pane editor} ui]
        foreach kind {opening_report opening_prep repertoire_report duplicates} {
            lappend cases [list open_view [list kind $kind] ui]
        }
        lappend cases [list correspondence_games {action open} ui]
        lappend cases [list discover_databases {} ui]
        lappend cases [list export_database {} ui]
        foreach tab {overview duplicates openings} {
            lappend cases [list maintenance_report [list tab $tab] ui]
        }
        foreach id {menu.board.set_start_board menu.board.set_start_position menu.file.export.pgn menu.file.export.html menu.file.export.archive} {
            lappend cases [list $id {} ui]
        }
        lappend cases [list view.pane_zoom {} ui]
        lappend cases [list app.preferences.assistant {} ui]
        foreach id {c1.board_setup c4.open_database c4.help c9.board_setup c9.tablebase c9.not.configure c9.assistant.model} {
            lappend cases [list $id [list object [dict create parent .application paneUid board]] ui]
        }
        foreach id {app_state current_game list_open_databases list_engines voice_status classifier_status} {
            lappend cases [list $id {} query]
        }
        return $cases
    }
    proc references {} {
        variable root
        set ids [dict keys $::application::assistant::Actions]
        package require json
        set f [open $root/tests/fixtures/assistant-tools-baseline.json]
        set tools [::json::json2dict [read $f]]; close $f
        foreach tool $tools { lappend ids [dict get $tool name] }
        # The knowledge corpus includes documentation topics as well as
        # actions. Only action aliases and acceptable action answers dispatch.
        set f [open $root/tests/fixtures/know-id-aliases.txt]
        foreach line [split [read $f] \n] {
            if {[string trim $line] eq {} || [string match #* [string trim $line]]} { continue }
            set id [lindex $line 1]
            if {![string match topic:* $id]} { lappend ids $id }
        }
        close $f
        set f [open $root/tests/fixtures/know-eval-dev.jsonl]
        foreach line [split [read $f] \n] {
            if {[string trim $line] eq {}} { continue }
            foreach id [dict get [::json::json2dict $line] acceptable] {
                if {![string match topic:* $id]} { lappend ids $id }
            }
        }
        close $f
        foreach row $::application::keyEditor::Actions { lappend ids [lindex $row 0] }
        # Literal dispatch references cover assistant mappings, toolbar/context
        # commands, help and hints. Parameterised ids are checked via the tables
        # and registry rather than treating Tcl substitutions as literal ids.
        set files [concat [glob -nocomplain $root/tcl/*.tcl] \
            [glob -nocomplain $root/tcl/help/en/*.{txt,html}] \
            [glob -nocomplain $root/docs/ai/*.md] \
            [glob -nocomplain $root/tests/test_app_*.tcl] \
            [glob -nocomplain $root/tests/fixtures/*.{txt,json,tcl}]]
        foreach path $files {
            set f [open $path]; set source [read $f]; close $f
            regsub -all -line {^\s*#.*$} $source {} source
            foreach {all id} [regexp -all -inline {::(?:action::(?:run|get|invoke)|application::assistant::runTool)\s+([a-z][a-z0-9_.-]*)} $source] {
                # Tests deliberately create unknown/test ids to test errors.
                if {[file dirname $path] eq "$root/tests" && ![regexp {^(menu\.|view\.|c[0-9]+\.)} $id]} { continue }
                if {[string index $id end] ne {.}} { lappend ids $id }
            }
        }
        foreach path $files {
            set f [open $path]; set source [read $f]; close $f
            regsub -all -line {^\s*#.*$} $source {} source
            foreach {all id} [regexp -all -inline {(?:^|[\s{\["])((?:menu|view|c[0-9]+)\.[a-z0-9_]+(?:\.[a-z0-9_]+)*)(?=[\s}\]"])} $source] {
                lappend ids $id
            }
        }
        return [lsort -unique $ids]
    }
}
if {[info exists ::env(SCIDB_REACHABILITY_LIBRARY)]} { return }
if {[info exists ::env(SCIDB_REACHABILITY_CASE)]} {
    ::scidb::test::reachability::ready
    lassign $::env(SCIDB_REACHABILITY_CASE) id argv kind
    tcltest::test reachability-probe {real action from independent fresh startup} \
        -body [list ::scidb::test::reachability::probe $id $argv $kind] -result 1
} else {
    ::scidb::test::reachability::ready
    tcltest::test reachability-startup {no drop-down was posted} -body {
        expr {![info exists ::application::Vars(menu:entries)] || ![winfo exists $::application::Vars(menu:entries)]}
    } -result 1
    tcltest::test reachability-registry {every startup registry id resolves} -body {
        set bad {}
        foreach id [::action::list] { if {[catch {::action::get $id}]} {lappend bad $id} }
        puts "REACHABILITY startup registry: [llength [::action::list]] ids"
        set bad
    } -result {}
    tcltest::test reachability-references {referenced ids exist before opening UI} -body {
        set bad {}
        foreach id [::scidb::test::reachability::references] {
            if {[catch {::action::get $id}]} {lappend bad $id}
        }
        set bad
    } -result {}
    tcltest::test reachability-explicit-gates {debug tools and unavailable pane ids resolve and explain their gates} -body {
        set bad {}
        foreach id [::action::list] {
            if {[dict get [::action::get $id] ai] eq {debug}} {
                if {![string match {error:*only available in debug mode*} [::action::run $id]]} { lappend bad $id }
            }
        }
        foreach id {players events sites annotators positions} {
            set id menu.view.panes.$id
            if {![string match {error:*not enabled} [::action::run $id]]} { lappend bad $id }
        }
        set bad
    } -result {}
    tcltest::test reachability-ui {real UI actions each run in a separate fresh HOME/process} -body {
        dict for {id reason} $::scidb::test::reachability::skips { puts "REACHABILITY SKIP $id: $reason" }
        set cases [::scidb::test::reachability::cases]
        puts "REACHABILITY isolated cases: [llength $cases]"
        ::scidb::test::reachability::runCases $cases
    } -result {}
}
tcltest::cleanupTests
