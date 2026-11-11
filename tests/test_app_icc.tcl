# Full ICC flows, only against the included loopback fixture.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
source [file join [file dirname [info script]] icc_fake_server.tcl]
namespace eval ::scidb::test::icc { variable savedOptions [array get ::icc::Options] }
proc ::scidb::test::icc::Connect {{handle {}} {mode guest}} {
    array set ::icc::Options {minutes 5 increment 0 rated 0 color auto}
    set port [::icc::fake::Start $mode]
    set ::icc::Options(host) 127.0.0.1
    set ::icc::Options(port) $port
    set ::icc::Options(handle) $handle
    ::icc::open .application
    set ::icc::Priv(dlg:password) transient-secret
    ::icc::ConnectFromDialog
    ::scidb::test::wait::until {$::icc::Priv(loggedIn) || $::icc::Priv(state) eq "offline"}
}
proc ::scidb::test::icc::Release {} {
    ::icc::Close
    ::icc::fake::Stop
    foreach key [array names ::online::window::Tabs icc:*] { ::online::window::closeTab $key }
}
proc ::scidb::test::icc::Until {script} { ::scidb::test::wait::until $script }

tcltest::test icc-guest-lobby {assigned name, seek updates, incoming challenges and chat} -body {
    ::scidb::test::icc::Connect
    ::scidb::test::icc::Until {[dict size $::icc::Seeks] == 2 && $::icc::Priv(match) eq "Challenger"}
    ::scidb::test::icc::Until {[string first {Channel welcome.} [join $::icc::Priv(textLines)]] >= 0}
    set first [list $::icc::Priv(handle) [$::icc::Priv(widget:tree) children {}] \
        [$::icc::Priv(widget:rated) instate disabled]]
    set ::icc::Priv(dlg:minutes) 3
    set ::icc::Priv(dlg:increment) 2
    set ::icc::Priv(dlg:rated) 1
    ::icc::Seek
    ::icc::Unseek
    ::icc::Challenge Somebody 5 2 unrated white
    ::icc::AcceptMatch
    ::icc::DeclineMatch
    ::icc::Tell Admin hello
    ::icc::Tell 4 hello
    ::icc::Send removematch
    ::scidb::test::icc::Until {$::icc::Priv(match) eq ""}
    set ok 1
    foreach cmd {{seek 3 2 unrated} unseek {match Somebody 5 2 unrated white} \
        {accept Challenger} {decline Challenger} {tell Admin hello} {tell 4 hello}} {
        if {$cmd ni $::icc::fake::received} { set ok 0 }
    }
    list $first $ok [expr {[string first {Channel welcome.} [join $::icc::Priv(textLines)]] >= 0}] \
        $::icc::Priv(loginPassword) $::icc::Priv(dlg:password)
} -cleanup { ::scidb::test::icc::Release } -result {{guest1234 {6 8} 1} 1 1 {} {}}

tcltest::test icc-registered {registered password is transient and full seek words are used} -body {
    ::scidb::test::icc::Connect TestPlayer registeredAccept
    set ::icc::Priv(dlg:rated) 1
    set ::icc::Priv(dlg:color) $::icc::mc::Black
    ::icc::Seek
    ::scidb::test::icc::Until {{seek 5 0 rated black} in $::icc::fake::received}
    list $::icc::Priv(handle) $::icc::Priv(guest) \
        [expr {{transient-secret} in $::icc::fake::received}] \
        [expr {[string first transient-secret [join $::icc::Priv(textLines)]] < 0}] \
        $::icc::Priv(loginPassword) $::icc::Priv(dlg:password)
} -cleanup { ::scidb::test::icc::Release } -result {TestPlayer 0 1 1 {} {}}

tcltest::test icc-password-rejected {rejection clears credentials and closes transport} -body {
    ::scidb::test::icc::Connect TestPlayer registeredReject
    list $::icc::Priv(state) $::icc::Priv(loginPassword) $::icc::Priv(dlg:password) $::icc::Priv(socket)
} -cleanup { ::scidb::test::icc::Release } -result {offline {} {} {}}

tcltest::test icc-play {moves, rejected optimistic move, clocks and stored ICC result} -body {
    ::scidb::test::icc::Connect
    ::scidb::test::icc::Until {[dict exists $::icc::Seeks 6]}
    ::icc::Play 6
    ::scidb::test::icc::Until {$::icc::Priv(active)}
    set start [lindex [::online::view::fen $::icc::Priv(view)] 0]
    set accepted [::icc::UserMove e4]
    ::scidb::test::icc::Until {[::icc::BoardPly] == 2}
    ::icc::Send clock
    ::scidb::test::icc::Until {$::icc::Priv(clock:b) == 120000}
    set clocks [list $::icc::Priv(clock:w) $::icc::Priv(clock:b)]
    ::icc::UserMove Nf3
    ::scidb::test::icc::Until {$::icc::fake::nf3 == 1 && $::icc::Priv(pendingMove) eq ""}
    set rollback [list [::icc::BoardPly] $::icc::Priv(relation)]
    ::icc::UserMove Nf3
    ::scidb::test::icc::Until {$::icc::Priv(state) eq "over"}
    list $start $accepted $clocks $rollback [::icc::BoardPly] \
        [expr {[string first {[Site "chessclub.com"]} $::icc::Priv(finalPgn)] >= 0}] \
        [expr {[string first {[Result "1-0"]} $::icc::Priv(finalPgn)] >= 0}]
} -cleanup { ::scidb::test::icc::Release } -result {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR 1 {123456 120000} {2 1} 4 1 1}

tcltest::test icc-observe {game list, observation, read-only moves, snapshot resync and unobserve} -body {
    ::scidb::test::icc::Connect
    ::icc::Watch
    ::icc::Observe 21
    ::scidb::test::icc::Until {$::icc::Priv(active) && $::icc::Priv(observing)}
    set before [::icc::BoardPly]
    set refused [::icc::UserMove Qg4]
    ::icc::Send next
    ::scidb::test::icc::Until {[::icc::BoardPly] == 51}
    ::icc::Send mismatch
    ::scidb::test::icc::Until {[::icc::BoardPly] == 52}
    set resync [llength [::online::view::ucis $::icc::Priv(view)]]
    ::icc::BackToLobby
    ::scidb::test::icc::Until {"unobserve" in $::icc::fake::received}
    list $before $refused $resync $::icc::Priv(state) [expr {"games" in $::icc::fake::received}]
} -cleanup { ::scidb::test::icc::Release } -result {50 0 0 lobby 1}

tcltest::test icc-game-controls {draw/takeback offers, accept/decline, adjourn and analyse handoff} -body {
    ::scidb::test::icc::Connect
    ::scidb::test::icc::Until {[dict exists $::icc::Seeks 6]}
    ::icc::Play 6
    ::scidb::test::icc::Until {$::icc::Priv(active)}
    ::icc::Send offers
    ::scidb::test::icc::Until {$::icc::Priv(offer) eq "takeback"}
    ::icc::ViewAction accept
    ::icc::OfferDraw
    ::icc::ViewAction takeback
    ::icc::Send offers
    ::scidb::test::icc::Until {$::icc::Priv(offer) eq "takeback"}
    ::icc::ViewAction decline
    ::icc::Adjourn
    ::scidb::test::icc::Until {$::icc::Priv(state) eq "over"}
    ::icc::Analyse
    set ok 1
    foreach cmd {accept draw {takeback 1} decline adjourn} {
        if {$cmd ni $::icc::fake::received} { set ok 0 }
    }
    list $ok [expr {[string first {[Result "*"]} $::icc::Priv(finalPgn)] >= 0}]
} -cleanup { ::scidb::test::icc::Release } -result {1 1}

tcltest::test icc-menu {ICC is in the Training menu next to the other servers and opens its lobby} -body {
    if {![info exists ::menu::DropdownTree] || ![llength $::menu::DropdownTree]} { ::menu::DefineTree }
    set ids {}
    foreach top $::menu::DropdownTree {
        if {[lindex $top 1] eq "Training"} {
            foreach row [lindex $top 3] { lappend ids [lindex $row 1] }
        }
    }
    set tab [::action::invoke menu.training.play_icc]
    set ok [string match .online* $tab]
    ::icc::Close
    list [expr {[lsearch -exact $ids menu.training.play_icc] == [lsearch -exact $ids menu.training.play_lichess]+1}] \
        [llength [lsearch -all -exact $ids menu.training.play_icc]] $ok
} -result {1 1 1}

foreach {command result} {Resign 0-1 Abort *} {
    tcltest::test icc-end-$command {game termination commands and stored result} -body [format {
        ::scidb::test::icc::Connect
        ::scidb::test::icc::Until {[dict exists $::icc::Seeks 6]}
        ::icc::Play 6
        ::scidb::test::icc::Until {$::icc::Priv(active)}
        ::icc::%s
        ::scidb::test::icc::Until {$::icc::Priv(state) eq "over"}
        expr {[string first {[Result "%s"]} $::icc::Priv(finalPgn)] >= 0}
    } $command $result] -cleanup { ::scidb::test::icc::Release } -result 1
}

tcltest::test icc-raw-command {raw entry and examine handoff commands} -body {
    ::scidb::test::icc::Connect
    set ::icc::Priv(dlg:raw) {tell Admin hello}
    ::icc::SendRaw
    ::icc::Send examine
    ::scidb::test::icc::Until {"examine" in $::icc::fake::received}
    list $::icc::Priv(dlg:raw) [expr {{tell Admin hello} in $::icc::fake::received}]
} -cleanup { ::scidb::test::icc::Release } -result {{} 1}

array set ::icc::Options $::scidb::test::icc::savedOptions
tcltest::cleanupTests
