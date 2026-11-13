# Confirmation parity and structural headings from the reg7 adversarial audit.
package require tcltest
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::reg8 {}

proc ::reg8::call {surface arguments} {
    switch $surface {
        menu {
            .reg8confirm entryconfigure 0 -command [list ::action::run add_engine $arguments]
            return [.reg8confirm invoke 0]
        }
        invoke {return [::action::invoke add_engine $arguments]}
        assistant {return [::application::assistant::runTool add_engine $arguments]}
        router {return [::application::assistant::DeliverRouted add_engine $arguments 0]}
    }
}

foreach surface {menu invoke assistant router} {
    foreach answer {yes no} {
        tcltest::test reg8-confirm-$surface-$answer {exactly one formatted confirmation; decline never reaches handler} -setup {
            set savedPriv [array get ::application::assistant::Priv]
            set ::application::assistant::Priv(reqconfirm) {}
            set ::application::assistant::Priv(confirm) ::application::assistant::ConfirmDialog
            set ::reg8::answer $answer
            set ::reg8::messages {}
            set ::reg8::effects {}
            rename ::dialog::question ::reg8::realQuestion
            proc ::dialog::question {args} {
                lappend ::reg8::messages [dict get $args -message]
                return $::reg8::answer
            }
            rename ::application::assistant::DoAddEngine ::reg8::realAddEngine
            proc ::application::assistant::DoAddEngine {path} {
                lappend ::reg8::effects $path
                return {Engine installed}
            }
            menu .reg8confirm -tearoff 0
            .reg8confirm add command -label AddEngine
        } -body {
            set path [info nameofexecutable]
            set args [list path $path]
            ::reg8::call $surface $args
            set expected [format $::application::assistant::mc::Confirm \
                [format [dict get [::action::get add_engine] what] $path]]
            list [expr {$::reg8::messages eq [list $expected]}] \
                [expr {$::reg8::effects eq [expr {$answer eq "yes" ? [list $path] : {}}]}]
        } -cleanup {
            destroy .reg8confirm
            rename ::dialog::question {}
            rename ::reg8::realQuestion ::dialog::question
            rename ::application::assistant::DoAddEngine {}
            rename ::reg8::realAddEngine ::application::assistant::DoAddEngine
            array unset ::application::assistant::Priv
            array set ::application::assistant::Priv $savedPriv
        } -result {1 1}
    }
}

tcltest::test reg8-invoke-invalid-before-confirm {invalid arguments are rejected without a confirmation dialog} -setup {
    set ::reg8::questions 0
    rename ::dialog::question ::reg8::realQuestion
    proc ::dialog::question {args} {incr ::reg8::questions; return yes}
} -body {
    set reply [::action::invoke add_engine {}]
    list [string match {error:*} $reply] $::reg8::questions
} -cleanup {
    rename ::dialog::question {}
    rename ::reg8::realQuestion ::dialog::question
} -result {1 0}

# All four native callers of the game-tab builder keep its Games heading
# visible but structural, including the named-object prefixes.
::action::run open_database [list path [::scidb::test::actions::fixture]]
::action::run open_game {number 1 move 1 after white}
update
foreach kind {game player event site} {
    tcltest::test reg8-heading-$kind {native Games heading is a disabled structural row, never an empty command} -body {
        set gamebar $::application::pgn::Vars(gamebar)
        set pos [::scidb::game::current]
        switch $kind {
            game {::gamebar::PopupMenu $gamebar $pos}
            player {::gamebar::PopupPlayerMenu $gamebar $pos white}
            event {::gamebar::PopupEventMenu $gamebar $pos}
            site {::gamebar::PopupSiteMenu $gamebar $pos}
        }
        set menu $gamebar.menu
        $menu post 60 60
        update idletasks
        set headings 0
        set emptyCommands {}
        for {set i 0} {$i <= [$menu index end]} {incr i} {
            set type [$menu type $i]
            if {$type eq "separator"} {continue}
            if {[string trim [$menu entrycget $i -label]] eq "Games"} {
                if {$type ne "cascade" || [$menu entrycget $i -state] ne "disabled"} {
                    error "Games is not a disabled structural row: $type"
                }
                incr headings
            }
            if {$type in {command checkbutton radiobutton} && [$menu entrycget $i -command] eq ""} {
                lappend emptyCommands $i
            }
        }
        list $headings $emptyCommands
    } -cleanup {catch {::tk::MenuUnpost $gamebar.menu}; catch {destroy $gamebar.menu}} -result {1 {}}
}
::scidb::test::actions::cleanup
::tcltest::cleanupTests
