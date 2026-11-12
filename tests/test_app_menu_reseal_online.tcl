# Training > Online and the post-2026-10-28 registry additions (REG-011).
# The real menu, Ask list, registry and knowledge pack are exercised here.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::onlineMenu {
    variable ids {menu.training.play_online menu.training.play_lichess
        menu.training.lichess_social menu.training.lichess_tv
        menu.training.lichess_events menu.training.lichess_puzzles menu.training.stream}
    set ids [lrange $ids 0 end]
    variable modules {ics lichess lichess_social lichess_tv lichess_events lichess_puzzles stream_overlay}
    variable calls {}
    proc record {args} { lappend ::scidb::test::onlineMenu::calls $args }
    proc build {} {
        catch {destroy .reseal}
        menu .reseal -tearoff 0
        ::menu::BuildDropdown .reseal
        set training [.reseal entrycget 6 -menu]
        ::menu::FillTop Training $training
        return $training
    }
    proc cascade {menu label} {
        set end [$menu index end]
        if {$end in {none {}}} {return {}}
        for {set i 0} {$i <= $end} {incr i} {
            if {[$menu type $i] eq {cascade}
                && [string trim [$menu entrycget $i -label]] eq $label} {
                set sub [$menu entrycget $i -menu]
                uplevel #0 [$sub cget -postcommand]
                return $sub
            }
        }
        return {}
    }
    proc commands {menu} {
        set ids {}
        set end [$menu index end]
        if {$end in {none {}}} {return {}}
        for {set i 0} {$i <= $end} {incr i} {
            if {[$menu type $i] ne {command}} {continue}
            set cmd [$menu entrycget $i -command]
            if {![regexp {^::action::run (\S+)$} $cmd -> id]} {error "unregistered row: $cmd"}
            lappend ids $id
        }
        return $ids
    }
    proc askids {} { lmap row [::action::labels asklist] {lindex $row 0} }
}

tcltest::test reseal-online-menu-paths {seven stable ids move together; engine training stays directly under Training} -body {
    ::menu::SwitchLanguage en
    set training [::scidb::test::onlineMenu::build]
    set online [::scidb::test::onlineMenu::cascade $training Online]
    set local [::scidb::test::onlineMenu::commands $training]
    list [::scidb::test::onlineMenu::commands $online] \
        [expr {"menu.training.play_engine" in $local && "menu.training.engine_match" in $local}] \
        [expr {"menu.training.play_online" ni $local}]
} -cleanup {destroy .reseal} -result [list $::scidb::test::onlineMenu::ids 1 1]

tcltest::test reseal-online-absent {an unavailable Online cascade disappears; Ask and direct dispatch enforce the same guards} -setup {
    set saved $::capability::Overrides
    foreach module $::scidb::test::onlineMenu::modules {::capability::Override $module 0}
} -body {
    set training [::scidb::test::onlineMenu::build]
    set leaked {}
    set ask [::scidb::test::onlineMenu::askids]
    foreach id $::scidb::test::onlineMenu::ids {
        set state [::menu::state $id]
        if {[dict get $state visible] || [dict get $state enabled]
            || $id in $ask || ![string match error:* [::action::run $id]]} {lappend leaked $id}
    }
    list [::scidb::test::onlineMenu::cascade $training Online] $leaked
} -cleanup {
    set ::capability::Overrides $saved
    destroy .reseal
} -result {{} {}}

tcltest::test reseal-online-partial {one available module keeps only its own Online row and Ask action} -setup {
    set saved $::capability::Overrides
    foreach module $::scidb::test::onlineMenu::modules {::capability::Override $module 0}
    ::capability::Override lichess_tv 1
} -body {
    set training [::scidb::test::onlineMenu::build]
    set sub [::scidb::test::onlineMenu::cascade $training Online]
    list [::scidb::test::onlineMenu::commands $sub] \
        [expr {"menu.training.lichess_tv" in [::scidb::test::onlineMenu::askids]}]
} -cleanup {
    set ::capability::Overrides $saved
    destroy .reseal
} -result {menu.training.lichess_tv 1}

tcltest::test reseal-online-translations {Online and all seven moved labels have live translations in five languages} -setup {
    set share $::scidb::dir::share
    set lang $::mc::langID
    set ::scidb::dir::share [file normalize [file join [file dirname [info script]] .. tcl]]
} -body {
    ::menu::SwitchLanguage en
    set english [lmap name {Online PlayOnline PlayLichess LichessSocial LichessTv LichessEvents LichessPuzzles StreamOverlay} {::menu::MC $name}]
    set bad {}
    foreach code {de es it hu sv} {
        ::menu::SwitchLanguage $code
        foreach name {Online PlayOnline PlayLichess LichessSocial LichessTv LichessEvents LichessPuzzles StreamOverlay} en $english {
            set value [::menu::MC $name]
            if {$value eq {} || $value eq $en} {lappend bad [list $code $name $value]}
        }
        set training [::scidb::test::onlineMenu::build]
        set sub [::scidb::test::onlineMenu::cascade $training [::menu::MC Online]]
        if {$sub eq {} || [::scidb::test::onlineMenu::commands $sub] ne $::scidb::test::onlineMenu::ids} {
            lappend bad [list $code missing-submenu]
        }
    }
    set bad
} -cleanup {
    ::menu::SwitchLanguage $lang
    set ::scidb::dir::share $share
    catch {destroy .reseal}
} -result {}

tcltest::test reseal-donate-dispatch {Donate rows dispatch by stable id to the configured destination} -setup {
    rename ::web::open ::scidb::test::onlineMenu::savedWeb
    proc ::web::open {parent url args} {::scidb::test::onlineMenu::record $url}
    set ::scidb::test::onlineMenu::calls {}
    set urls $::menu::DonateURLs
} -body {
    set button $::application::Vars(donate)
    set dm [winfo parent $button].donate_menu
    $dm invoke 0
    $dm invoke 1
    set ask [::scidb::test::onlineMenu::askids]
    set present [expr {"menu.help.donate" in $ask && "menu.help.donate_paypal" in $ask && "menu.help.donate_kofi" in $ask}]
    set ::menu::DonateURLs {}
    set denied [string match error:* [::action::run menu.help.donate_paypal]]
    list [$button cget -command] $present $::scidb::test::onlineMenu::calls $denied \
        [expr {"menu.help.donate" ni [::scidb::test::onlineMenu::askids]}]
} -cleanup {
    set ::menu::DonateURLs $urls
    rename ::web::open {}
    rename ::scidb::test::onlineMenu::savedWeb ::web::open
} -result [list {::action::run menu.help.donate} 1 [list [list https://paypal.me/MGThomas] [list https://ko-fi.com/michaelthomas13477]] 1 1]

tcltest::test reseal-online-controls {real game controls, Ask and generic assistant dispatch share selected-tab state} -setup {
    set view [::online::window::gameTab reseal:game {Generated test game} ::scidb::test::onlineMenu::record w]
    set ::scidb::test::onlineMenu::calls {}
    ::online::view::actions $view {resign 1 draw 1 takeback 1 abort 1 claim 1}
    update
} -body {
    set before [set ::online::view::${view}::V(flip)]
    $view.side.actions.flip invoke
    set flipped [expr {$before != [set ::online::view::${view}::V(flip)]}]
    ::knowledge::RunAction toolbar.online.draw {}
    set ask [::scidb::test::onlineMenu::askids]
    set available [expr {"toolbar.online.draw" in $ask && "toolbar.online.flip" in $ask}]
    ::online::view::actions $view {}
    set blocked [string match error:* [::knowledge::RunAction toolbar.online.draw {}]]
    ::online::view::offer $view {Draw offered}
    set offers [expr {"toolbar.online.accept" in [::scidb::test::onlineMenu::askids]}]
    ::online::view::offer $view {}
    set nooffer [expr {"toolbar.online.accept" ni [::scidb::test::onlineMenu::askids]}]
    ::online::view::spectator $view
    set nochat [expr {"toolbar.online.chat" ni [::scidb::test::onlineMenu::askids]}]
    list $flipped $available $blocked $offers $nooffer $nochat $::scidb::test::onlineMenu::calls
} -cleanup {
    ::online::window::closeTab reseal:game
    catch {wm withdraw .online}
} -result {1 1 1 1 1 1 draw}

tcltest::test reseal-registry-knowledge {every post-baseline action has knowledge and assistant exposure through its tool or run_action} -body {
    ::knowledge::Ensure
    set ids [concat $::scidb::test::onlineMenu::ids \
        {menu.help.support menu.help.donate menu.help.donate_paypal menu.help.donate_kofi
        view.focus_follows_size opening_line engine_play set_position} \
        [lsearch -all -inline -glob [::action::list] toolbar.online.*]]
    set bad {}
    foreach id $ids {
        set rec [::action::get $id]
        set k [::knowledge::For $id en]
        if {([dict get $rec ai] ne "1" && ![dict get $rec operator])
            || [dict get $k purpose] eq {} || [dict get $k when] eq {}
            || [llength [dict get $k examples]] < 2 || $id ni [::knowledge::PackIds]} {lappend bad $id}
    }
    set bad
} -result {}

tcltest::test reseal-icc-removed {no removed client remains in capabilities, registry or assistant tools} -body {
    set text "[dict keys $::capability::Modules] [::action::list] [dict keys $::application::assistant::Actions]"
    regexp -nocase {\micc\M|play_icc|::icc::|Internet Chess Club} $text
} -result 0

tcltest::cleanupTests
