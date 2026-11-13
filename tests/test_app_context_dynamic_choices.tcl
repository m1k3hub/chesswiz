package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::choices {}
proc ::scidb::test::choices::invoke {id object {index 0}} {
    catch {destroy .dynamicChoices}
    menu .dynamicChoices -tearoff 0
    ::context::CascadePrefix $id .dynamicChoices $object
    set command [.dynamicChoices entrycget $index -command]
    if {[lrange $command 0 1] ne [list ::action::run $id]} {error {choice bypasses registry}}
    set reply [.dynamicChoices invoke $index]
    destroy .dynamicChoices
    if {[string match error:* $reply]} {error $reply}
    update
    return $reply
}
tcltest::test context-notation-choices-effects {notation style, move information and language choices update the native editor settings} -setup {
    ::menu::gameNew .application
    ::scidb::game::import [::scidb::game::current] {1. e4 e5 *} {} {} -encoding utf-8 -variation 0
    update
    set twm [::application::twm board]
    set object [dict create paneUid editor twm $twm frame [$twm leaf editor]]
    set savedStyle $::pgn::editor::Options(style:move)
    set savedInfo $::pgn::setup::ShowMoveInfo(eval)
    set savedLang $::application::pgn::Vars(lang:active:xx)
} -body {
    set out {}
    foreach id {c9.not.move_notation c9.not.move_info c9.not.language} {
        set reply [::action::run $id [dict create object $object]]
        lappend out [expr {$reply eq "opened choices"}]
        catch {grab release .contextChoices_paneCascade}
        catch {destroy .contextChoices_paneCascade}
        ::scidb::test::choices::invoke $id $object
    }
    lappend out [expr {$::pgn::editor::Options(style:move) eq [lindex $::notation::moveStyles 0]}]
    lappend out [expr {$::pgn::setup::ShowMoveInfo(eval) != $savedInfo}]
    lappend out [expr {$::application::pgn::Vars(lang:active:xx) != $savedLang}]
    set out
} -cleanup {
    set ::pgn::editor::Options(style:move) $savedStyle
    set ::pgn::setup::ShowMoveInfo(eval) $savedInfo
    set ::application::pgn::Vars(lang:active:xx) $savedLang
    ::application::pgn::Refresh style:move
} -result {1 1 1 1 1 1}
tcltest::test context-player-web-choices {native player web choices preserve their URL through the registry} -setup {
    rename ::web::open ::scidb::test::choices::webOpen
    proc ::web::open {parent url} {set ::scidb::test::choices::url $url}
    # The native builder always offers its name-based player search link.
    set object {kind player name {Generated, Player} base generated}
    menu .webChoices -tearoff 0
    ::context::CascadePrefix c5.player_url .webChoices $object
} -body {
    set count 0
    for {set i 0} {$i <= [.webChoices index end]} {incr i} {
        if {[.webChoices type $i] ne "command" || [.webChoices entrycget $i -state] ne "normal"} continue
        set call [.webChoices entrycget $i -command]
        set expected [dict get [dict get [lindex $call 2] object] webUrl]
        .webChoices invoke $i
        if {$::scidb::test::choices::url ne $expected} {error {wrong URL}}
        incr count
    }
    expr {$count > 0}
} -cleanup {
    destroy .webChoices
    rename ::web::open {}
    rename ::scidb::test::choices::webOpen ::web::open
} -result 1
proc ::scidb::test::choices::commentChecks {} {
    set w $::comment::Vars(widget:text:en).text
    ::comment::SetupComment en {{str {Generated annotation}}} 1
    $w tag add sel begin end
    set object [dict create widget $w base generated index 0 ply 1]
    tcltest::test context-comment-format-effect {Format applies bold to the native comment selection} -body {
        ::scidb::test::choices::invoke c11.format $object
        expr {[llength [$w tag ranges bold]] > 0}
    } -result 1
    ::comment::EditAltered $w
    ::comment::NewLanguage de
    ::comment::SwitchLanguage en
    tcltest::test context-comment-copy-effect {Copy Text copies only the selected language slot to the chosen destination} -body {
        ::scidb::test::choices::invoke c11.copy_text $object 1
        expr {$::comment::Vars(content:de) eq $::comment::Vars(content:en) && $::comment::Vars(content:de) ne {}}
    } -result 1
    tcltest::test context-comment-switch-effect {Switch Language selects the actual native language editor} -body {
        ::scidb::test::choices::invoke c11.switch_language $object 1
        list $::comment::Vars(lang) [winfo exists $::comment::Vars(widget:text:de).text]
    } -result {de 1}
    ::application::ai::configure -provider stub -model {}
    ::ai::provider::configure -name stub -model {}
    rename ::application::ai::generate ::scidb::test::choices::generate
    proc ::application::ai::generate {parent title progress fen args} {
        set observer [lindex $args [expr {[lsearch -exact $args -observer]+1}]]
        {*}$observer [dict create ok 1 text {Generated French translation}]
    }
    tcltest::test context-comment-translation-effect {Translate Comment reaches the native observer and populates the chosen language editor} -body {
        ::scidb::test::choices::invoke c11.translate_comment $object 2
        list $::comment::Vars(lang) [string trim [$::comment::Vars(widget:text:fr).text get 1.0 end]]
    } -cleanup {
        rename ::application::ai::generate {}
        rename ::scidb::test::choices::generate ::application::ai::generate
    } -result {fr {Generated French translation}}
    destroy $::comment::Vars(dialog)
}
::scidb::game::update addcomment [::scidb::game::position key] after {Generated annotation}
after 700 ::scidb::test::choices::commentChecks
::comment::open .application after en
::tcltest::cleanupTests
