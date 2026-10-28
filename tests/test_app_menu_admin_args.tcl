package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::adminargs {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} {error $result}
        return $result
    }
    proc until {script} {
        set end [expr {[clock milliseconds]+20000}]
        while {![uplevel 1 [list expr $script]]} {
            if {[clock milliseconds]>$end} {error "timeout: $script"}
            update;after 10
        }
    }
    proc accept {args} {return 1}
}
tcltest::test admin-args-persistence {real UCI install, edit fields, logo/folder, usage reset and confirmed removal persist} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    set confirm $::action::ConfirmHook
    set ::action::ConfirmHook ::scidb::test::adminargs::accept
    file delete -force [file join $::env(HOME) engine-data] [file join $::env(HOME) moved-engine-data]
    set photo [file join $::env(HOME) logo.png]
    set image [image create photo -width 2 -height 2]
    $image put blue -to 0 0 2 2
    $image write $photo -format png
    image delete $image
} -body {
    set name [::scidb::test::adminargs::call menu.analysis.engines operation add filename [::scidb::test::actions::engineProgram]]
    set dir [file join $::env(HOME) engine-data]
    set entry [::scidb::test::adminargs::call menu.analysis.engines operation update engine $name name {Generated Admin} directory $dir logo $photo webpage http://127.0.0.1/ email generated@example.invalid]
    set marker [file join $dir generated-engine-data.txt]
    set f [open $marker w];puts $f generated-data;close $f
    set movedDir [file join $::env(HOME) moved-engine-data]
    ::scidb::test::adminargs::call menu.analysis.engines operation update engine {Generated Admin} directory $movedDir
    if {[file exists $dir] || ![file exists [file join $movedDir generated-engine-data.txt]]} {error "native directory move semantics were not preserved"}
    set dir $movedDir
    set cleared [::scidb::test::adminargs::call menu.analysis.engines operation clear_usage engine {Generated Admin}]
    set ::engine::Engines {}
    source $::scidb::file::engines
    set persisted [lindex $::engine::Engines [::engine::FindIndex {Generated Admin}]]
    set observed [list [file isdirectory $dir] [dict get $persisted Logo] [dict get $persisted Url] [dict get $cleared Frequency]]
    ::scidb::test::adminargs::call menu.analysis.engines operation delete engine {Generated Admin}
    set ::engine::Engines {}
    source $::scidb::file::engines
    list [expr {$name ne ""}] [lindex $observed 0] [expr {[lindex $observed 1] eq $photo}] \
        [lrange $observed 2 3] [::engine::FindIndex {Generated Admin}] [winfo exists .application.adminEngines]
} -cleanup {
    set ::action::ConfirmHook $confirm
    set ::engine::Engines $engines
    ::engine::SaveEngineList
} -result {1 1 1 {http://127.0.0.1/ 0} -1 0}

tcltest::test admin-args-comparison {two real native analysis engines produce lines, stop and close without chooser} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    set name [::engine::install [::scidb::test::actions::engineProgram]]
    set copy [lindex $::engine::Engines [::engine::FindIndex $name]]
    dict set copy Name {Generated Comparison}
    lappend ::engine::Engines $copy
} -body {
    ::scidb::test::adminargs::call menu.analysis.compare_engines operation start engines [list $name {Generated Comparison}] seconds 30
    ::scidb::test::adminargs::until {[llength [::application::analysis::ComparisonLines]]==2 && [llength [lindex [::application::analysis::ComparisonLines] 0 2]]>0 && [llength [lindex [::application::analysis::ComparisonLines] 1 2]]>0}
    set lines [::application::analysis::ComparisonLines]
    ::scidb::test::adminargs::call menu.analysis.compare_engines operation stop
    set stopped 1
    foreach entry $lines {if {[::engine::active? [lindex $entry 1]]} {set stopped 0}}
    set used [lindex $::engine::Engines [::engine::FindIndex $name]]
    set reset [::scidb::test::adminargs::call menu.analysis.engines operation clear_usage engine $name]
    if {[dict get $used Frequency] < 1 || [dict get $used LastUsed] < 1 || [dict get $reset Frequency] != 0 || [dict get $reset LastUsed] != 0} {error "real engine usage was not cleared"}
    ::scidb::test::adminargs::call menu.analysis.compare_engines operation close
    list [llength $lines] $stopped $::application::analysis::compare::Vars(after) $::application::analysis::compare::Vars(engines) [winfo exists .compareEngines]
} -cleanup {
    ::application::analysis::CloseComparison
    set ::engine::Engines $engines
    ::engine::SaveEngineList
} -result {2 1 {} {} 0}

proc ::scidb::test::adminargs::closeAdmin {{tries 100}} {
    if {![winfo exists .application.adminEngines] || ![winfo viewable .application.adminEngines]} {
        if {$tries>0} {after 30 [list ::scidb::test::adminargs::closeAdmin [expr {$tries-1}]]}
        return
    }
    set code [catch {
        set ::engine::Data(Name) {Generated Unsaved Name}
        set refused [::knowledge::RunAction menu.analysis.engines {operation close discard 0}]
        set retained [winfo exists .application.adminEngines]
        call menu.analysis.engines operation close discard 1
        list 1 [string match {error:*unsaved engine fields*} $refused] $retained [winfo exists .application.adminEngines]
    } result]
    set ::scidb::test::adminargs::closeResult [list $code $result]
    catch {destroy .application.adminEngines}
}
tcltest::test admin-args-close-discard {explicit close arguments handle real unsaved administration fields without a question} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    ::engine::install [::scidb::test::actions::engineProgram]
    set ::scidb::test::adminargs::closeResult {}
} -body {
    after 30 ::scidb::test::adminargs::closeAdmin
    ::scidb::test::adminargs::call menu.analysis.engines
    lassign $::scidb::test::adminargs::closeResult code result
    if {$code ne "0"} {error "close test callback failed: $result"}
    return $result
} -cleanup {
    catch {destroy .application.adminEngines}
    set ::engine::Engines $engines
    ::engine::SaveEngineList
} -result {1 1 1 0}
tcltest::cleanupTests
