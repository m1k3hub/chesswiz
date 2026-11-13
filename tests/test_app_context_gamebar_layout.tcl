package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::gamebarLayout {}
proc ::scidb::test::gamebarLayout::choose {index} {
    catch {destroy .layoutChoices}
    menu .layoutChoices -tearoff 0
    set object [::context::CurrentObject C9]
    ::context::CascadePrefix c9.layout .layoutChoices $object
    set command [.layoutChoices entrycget $index -command]
    if {[lrange $command 0 1] ne {::action::run c9.layout}} {error {choice bypasses registry}}
    set reply [.layoutChoices invoke $index]
    update
    if {$reply ne {completed c9.layout}} {error $reply}
    destroy .layoutChoices
}
tcltest::test context-gamebar-layout-effects {all three Layout choices run baseline callbacks and change native canvas items in both directions} -setup {
    set saved [array get ::gamebar::Options]
    ::menu::gameNew .application
    ::scidb::game::import [::scidb::game::current] {1. e4 e5 *} {} {} -encoding utf-8 -variation 0
    ::menu::gameNew .application
    update
    set gb $::application::pgn::Vars(gamebar)
    set selected $::gamebar::Specs(selected:$gb)
    set ::gamebar::Options(separateColumn) 0
    set ::gamebar::Options(selectedAtBottom) 0
    set ::gamebar::Options(separateLines) 0
    ::gamebar::ShowSeparateColumn $gb
    ::gamebar::ShowAtSeparateLines $gb
    ::gamebar::ShowAtBottom $gb
    ::application::openPane editor
    set twm [::application::twm board]
    focus -force [$twm leaf editor]
    update
} -body {
    set out {}
    foreach expected {1 0} {
        ::scidb::test::gamebarLayout::choose 0
        lappend out [expr {[::gamebar::UseSeparateColumn $gb] == $expected}]
        lappend out [expr {([$gb itemcget white-1 -state] eq "normal") == $expected}]
    }
    foreach expected {1 0} {
        ::scidb::test::gamebarLayout::choose 1
        lappend out [expr {([$gb itemcget digit$selected -state] eq "normal") == $expected}]
    }
    foreach expected {1 0} {
        ::scidb::test::gamebarLayout::choose 2
        lappend out [expr {([$gb itemcget hyphen$selected -state] eq "hidden") == $expected}]
    }
    set out
} -cleanup {
    array set ::gamebar::Options $saved
    ::gamebar::ShowSeparateColumn $gb
    ::gamebar::ShowAtSeparateLines $gb
    ::gamebar::ShowAtBottom $gb
    catch {destroy .layoutChoices}
} -result {1 1 1 1 1 1 1 1}
tcltest::test context-gamebar-layout-guard {active separate header disables the native bottom choice and rejects its direct invocation} -setup {
    set saved $::gamebar::Options(separateColumn)
    set ::gamebar::Options(separateColumn) 1
    menu .layoutChoices -tearoff 0
    ::context::CascadePrefix c9.layout .layoutChoices [::context::CurrentObject C9]
} -body {
    set command [.layoutChoices entrycget 1 -command]
    list [.layoutChoices entrycget 1 -state] [string match error:* [{*}$command]]
} -cleanup {
    set ::gamebar::Options(separateColumn) $saved
    destroy .layoutChoices
} -result {disabled 1}
::tcltest::cleanupTests
