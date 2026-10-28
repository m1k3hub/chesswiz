package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::finalcallbacks {
    proc call {args} {
        set result [::knowledge::RunAction menu.tools.player_card $args]
        if {[string match error:* $result]} {error $result}
        return $result
    }
}
tcltest::test final-callback-rating-fill {native rating lookup fills empty draft fields only; never saves or opens a form} -setup {
    ::scidb::test::actions::ready
    set cards [::playercard::privateCards]
    set file [file join $::env(HOME) generated-ratings.txt]
    set f [open $file w]
    puts $f {ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag}
    puts $f [format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
        999000901 {Generated, Rating} NED F GM {} {} {} 2412 0 10 0 0 10 0 0 10 2001 {}]
    close $f
    ::scidb::app::load fide $file
    ::scidb::app::load done
} -body {
    set result [::scidb::test::finalcallbacks::call operation rating_fill FideID 999000901 Nation BEL Score1 1999]
    set draft [dict get $result draft]
    set missing [::knowledge::RunAction menu.tools.player_card {operation rating_fill FideID 999000999}]
    set byName [::scidb::test::finalcallbacks::call operation rating_fill name {generated, rating}]
    ::scidb::test::finalcallbacks::call
    ::playercard::SetField .application.setupPrivateCard FideID 999000901
    ::playercard::SetField .application.setupPrivateCard Nation BEL
    ::playercard::SetField .application.setupPrivateCard Score1 1999
    set nativeFilled [::playercard::FillFromLists .application.setupPrivateCard]
    set same [expr {$nativeFilled eq [dict get $result filled]}]
    foreach field $::playercard::PrivateFields {
        if {[::playercard::GetField .application.setupPrivateCard $field] ne [dict get $draft $field]} {set same 0}
    }
    ::scidb::test::finalcallbacks::call operation close
    list $same [dict get $draft Name] [dict get $draft Nation] [dict get $draft Score1] \
        [dict get $draft Birthday] [dict get $draft Title1] [dict get $draft Rating1] \
        [expr {[lsearch -exact [dict get $result filled] Nation]<0}] \
        [dict get [dict get $byName draft] FideID] [string match error:* $missing] \
        [expr {[::playercard::privateCards] eq $cards}] [winfo exists .application.setupPrivateCard]
} -cleanup {file delete $file} -result {1 {Generated, Rating} BEL 1999 2001 GM Elo 1 999000901 1 1 0}

tcltest::test final-callback-new-draft {new clears real form fields/photo without changing saved cards; headless returns blank draft} -setup {
    ::scidb::test::actions::ready
    set cards [::playercard::privateCards]
    set me $::application::ai::Settings(me)
} -body {
    ::scidb::test::finalcallbacks::call operation save name {Generated Saved} Me 1 Score1 2100
    set saved [::playercard::privateCards]
    set blank [::scidb::test::finalcallbacks::call operation new_draft]
    set noForm [expr {![winfo exists .application.setupPrivateCard]}]
    ::scidb::test::finalcallbacks::call
    ::playercard::SetField .application.setupPrivateCard Name {Unsaved Draft}
    ::playercard::SetField .application.setupPrivateCard Score1 2300
    set ::playercard::PhotoSource /generated/unsaved.png
    set ::playercard::Var(Me) 1
    set draft [::scidb::test::finalcallbacks::call operation new_draft]
    set result [list [expr {$blank eq $draft}] $noForm \
        [::playercard::GetField .application.setupPrivateCard Name] \
        [::playercard::GetField .application.setupPrivateCard Score1] \
        $::playercard::Var(Me) $::playercard::PhotoSource \
        [expr {[::playercard::privateCards] eq $saved}] [::playercard::myCard]]
    ::scidb::test::finalcallbacks::call operation close
    set result
} -cleanup {
    catch {destroy .application.setupPrivateCard}
    ::playercard::SavePrivate $cards
    set ::application::ai::Settings(me) $me
} -result {1 1 {} {} 0 {} 1 {Generated Saved}}

tcltest::test final-callback-webpage {registry engine webpage reaches platform URL boundary, not a browser} -setup {
    ::scidb::test::actions::ready
    set engines $::engine::Engines
    lappend ::engine::Engines [dict merge $::engine::EmptyEngine {Name {Generated Web} Url https://example.invalid/generated#engine}]
    rename ::platform::sys::openURL ::platform::sys::finalCallbacksRealOpenURL
    set ::scidb::test::finalcallbacks::urls {}
    proc ::platform::sys::openURL {url} {lappend ::scidb::test::finalcallbacks::urls $url}
} -body {
    set reply [::knowledge::RunAction menu.analysis.engines {operation webpage engine {Generated Web}}]
    if {[string match error:* $reply]} {error $reply}
    set missing [::knowledge::RunAction menu.analysis.engines {operation webpage engine {Missing Generated}}]
    list $::scidb::test::finalcallbacks::urls [string match error:* $missing] [winfo exists .application.adminEngines]
} -cleanup {
    rename ::platform::sys::openURL {}
    rename ::platform::sys::finalCallbacksRealOpenURL ::platform::sys::openURL
    set ::engine::Engines $engines
} -result {https://example.invalid/generated#engine 1 0}
tcltest::cleanupTests
