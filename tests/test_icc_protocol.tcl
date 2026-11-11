# Standalone: no Tk display, socket or application required.
package require tcltest 2.5
if {![llength [info commands ::icc::fields]]} {
    package provide Tk 8.6
    namespace eval ::util { proc source {args} {} }
    namespace eval ::options { proc hookWriter {args} {} }
    set root [file dirname [file dirname [file normalize [info script]]]]
    source [file join $root tcl ics.tcl]
    source [file join $root tcl icc.tcl]
}

tcltest::test icc-fields-plain {empty strings and Tcl metacharacters stay literal} -body {
    ::icc::fields {31 Sender {} {hello $env(HOME) [exit]; back\slash} 1}
} -result {31 Sender {} {hello $env(HOME) [exit]; back\slash} 1}
tcltest::test icc-fields-control {control-Y strings preserve braces and UTF8} -body {
    ::icc::fields "31 Sender {} \x19\{caf\xc3\xa9 \{nested\}\x19\} 1"
} -result {31 Sender {} {café {nested}} 1}
tcltest::test icc-fields-invalid {unterminated strings fail without evaluation} -body {
    catch {::icc::fields "31 Sender \{"}
} -result 1
tcltest::test icc-fragments {every byte boundary preserves complete frames} -body {
    set stream "hello\n\x19(31 A {} \x19\{hi there\x19\} 1\x19)\x19\[12 me\nreply\x19\]\n"
    set expected [list [list text hello] [list datagram "31 A {} \x19\{hi there\x19\} 1"] [list reply "12 me\nreply"] [list text {}]]
    set correct 1
    for {set i 0} {$i <= [string length $stream]} {incr i} {
        set b [string range $stream 0 [expr {$i-1}]]
        set got [::icc::extractFrames b]
        append b [string range $stream $i end]
        set got [concat $got [::icc::extractFrames b]]
        if {$got ne $expected || $b ne ""} { set correct 0 }
    }
    set correct
} -result 1
tcltest::test icc-frame-bound {bounded drain keeps remaining frames} -body {
    set b [string repeat "\x19(0 guest {}\x19)" 5]
    list [llength [::icc::extractFrames b 2]] [llength [::icc::extractFrames b 2]] [llength [::icc::extractFrames b]] $b
} -result {2 2 1 {}}
tcltest::test icc-settings {all required bits set, index order begins at zero} -body {
    set b [::icc::settings]
    set ok 1
    foreach id {0 15 16 17 18 19 20 24 25 26 27 28 29 30 31 33 34 36 43 50 51 56 101} {
        if {[string index $b $id] ne "1"} { set ok 0 }
    }
    list [string length $b] $ok [string index $b 1]
} -result {102 1 0}
tcltest::test icc-seek {ICC seek layout and variant filtering} -body {
    set a [::icc::parseSeek {6 Opponent {} 1500 0 0 blitz 5 2 0 ? 0 9999 1 0 {}}]
    list [dict get $a name] [dict get $a time] [dict get $a inc] [dict get $a rated] \
        [::icc::parseSeek {7 Wild {} 1500 0 1 blitz 5 2 0 ? 0 9999 1 0 {}}] \
        [::icc::parseSeek {6 bad}]
} -result {Opponent 5 2 u {} {}}
tcltest::test icc-style-fallback {ICC uses the existing FICS pure board helpers} -body {
    set s [::ics::parseStyle12 {<12> rnbqkbnr pppppppp -------- -------- -------- -------- PPPPPPPP RNBQKBNR W -1 1 1 1 1 0 42 Guest Opponent 1 5 0 39 39 300000 300000 1 none (0:00) none 0 1 0}]
    list [dict get $s board] [dict get $s ply]
} -result {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR 0}
namespace eval ::icc::test { variable sent {}; variable ended {} }
foreach name {Send ShowView Status RefreshSeeks Chat EndGame RejectMove UpdateGameButtons DialogExists ViewExists} {
    rename ::icc::$name ::icc::test::real$name
}
proc ::icc::Send {line} { lappend ::icc::test::sent $line; return 1 }
proc ::icc::ShowView {args} {}
proc ::icc::Status {text} { set ::icc::Priv(statusText) $text }
proc ::icc::RefreshSeeks {} {}
proc ::icc::Chat {who text} { set ::icc::test::chat [list $who $text] }
proc ::icc::EndGame {result reason} { set ::icc::test::ended [list $result $reason] }
proc ::icc::RejectMove {why turn} { set ::icc::test::rejected [list $why $turn] }
proc ::icc::UpdateGameButtons {} {}
proc ::icc::DialogExists {} { return 0 }
proc ::icc::ViewExists {} { return 0 }

tcltest::test icc-login-wire {guest and registered login, transient password and WHO_AM_I} -body {
    set ::icc::test::sent {}
    set ::icc::Priv(guest) 1
    ::icc::AnswerPrompt {login: }
    set first [lindex $::icc::test::sent 0]
    set ::icc::Priv(guest) 0
    set ::icc::Priv(loginHandle) TestPlayer
    ::icc::AnswerPrompt {login: }
    set ::icc::Priv(loginPassword) secret
    set ::icc::Priv(dlg:password) secret
    ::icc::AnswerPrompt {password: }
    set ::icc::Priv(loggedIn) 0
    ::icc::HandleDatagram {0 TestPlayer {}}
    list [string match {level2settings=* guest} $first] \
        [string match {level2settings=* TestPlayer} [lindex $::icc::test::sent 1]] \
        [lindex $::icc::test::sent 2] $::icc::Priv(loginPassword) $::icc::Priv(dlg:password) \
        $::icc::Priv(handle) $::icc::Priv(state) \
        [expr {{set style 12} in $::icc::test::sent}]
} -result {1 1 secret {} {} TestPlayer lobby 1}
tcltest::test icc-live-seek-removal {datagrams insert, filter variants and remove indexes} -body {
    set ::icc::Seeks {}
    ::icc::HandleDatagram {50 6 Opponent {} 1500 0 0 blitz 5 2 0 ? 0 9999 1 0 {}}
    ::icc::HandleDatagram {50 7 Wild {} 1500 0 8 blitz 5 2 0 ? 0 9999 1 0 {}}
    set first [dict keys $::icc::Seeks]
    ::icc::HandleDatagram {51 6}
    list $first [dict size $::icc::Seeks]
} -result {6 0}
tcltest::test icc-personal-channel {separate tell field offsets} -body {
    ::icc::HandleDatagram {31 Sender {} {personal hello} 1}
    set first $::icc::test::chat
    ::icc::HandleDatagram {28 4 Sender {} {channel hello} 1}
    list $first $::icc::test::chat
} -result {{Sender {personal hello}} {Sender(4) {channel hello}}}
tcltest::test icc-challenges {incoming match, accept, decline and removal} -body {
    set ::icc::test::sent {}
    ::icc::HandleDatagram {29 Challenger 1600 {} Me 1500 {} 0 blitz 0 0 5 2 5 2 ?}
    ::icc::AcceptMatch
    ::icc::DeclineMatch
    ::icc::HandleDatagram {30 Challenger}
    list $::icc::test::sent $::icc::Priv(match) [dict size $::icc::Matches]
} -result {{{accept Challenger} {decline Challenger}} {} 0}
tcltest::test icc-game-metadata {start data and snapshot request; score is not result code} -body {
    set ::icc::test::sent {}
    ::icc::HandleDatagram {15 42 Me Opponent 0 blitz 0 5 2 5 2}
    set ::icc::Priv(gameNumber) 42
    ::icc::HandleDatagram {16 42 0 Res 1-0 {Opponent resigns}}
    list [dict get $::icc::Priv(gameInfo) white] [dict get $::icc::Priv(gameInfo) increment] \
        $::icc::test::sent $::icc::test::ended
} -result {Me 2 refresh {1-0 {Opponent resigns}}}
tcltest::test icc-wrong-game {result and illegal move for another board are ignored} -body {
    set ::icc::test::ended {}
    set ::icc::test::rejected {}
    ::icc::HandleDatagram {16 99 0 Res 0-1 {Other game}}
    ::icc::HandleDatagram {26 99 e4 {Illegal move}}
    ::icc::HandleDatagram {26 42 e4 {Illegal move}}
    list $::icc::test::ended $::icc::test::rejected
} -result {{} {{Illegal move} 1}}
tcltest::test icc-millisecond-clocks {inactive side clock update does not stop the active clock} -body {
    set ::icc::Priv(active) 1
    set ::icc::Priv(state) playing
    ::icc::HandleDatagram {56 42 W 123456 1}
    ::icc::HandleDatagram {56 42 B 120000 0}
    list $::icc::Priv(clock:w) $::icc::Priv(clock:b) $::icc::Priv(clockStm) $::icc::Priv(ticking)
} -result {123456 120000 w 1}
tcltest::test icc-malformed {bad clock, missing fields, invalid score cannot change game state} -body {
    set ::icc::test::ended {}
    ::icc::HandleDatagram {56 42 W nope 1}
    ::icc::HandleDatagram {16 42 0 Res nope {bad score}}
    ::icc::HandleDatagram {50 1}
    list $::icc::Priv(clock:w) $::icc::test::ended
} -result {123456 {}}
tcltest::test icc-offers {opponent offers use the opponent color offsets} -body {
    set ::icc::Priv(userSide) w
    ::icc::HandleDatagram {34 42 0 1 0 0 0 0 0 0}
    set draw $::icc::Priv(offer)
    ::icc::HandleDatagram {34 42 0 0 0 0 0 0 0 1}
    list $draw $::icc::Priv(offer)
} -result {draw takeback}

foreach name {Send ShowView Status RefreshSeeks Chat EndGame RejectMove UpdateGameButtons DialogExists ViewExists} {
    rename ::icc::$name {}
    rename ::icc::test::real$name ::icc::$name
}
tcltest::test icc-mock-wire {scripted mock emits valid ICC frames and style12 without opening sockets} -body {
    source [file join [file dirname [info script]] icc_fake_server.tcl]
    rename ::icc::fake::Write ::icc::fake::SocketWrite
    proc ::icc::fake::Write {text} { append ::icc::test::wire $text }
    set ::icc::test::wire {}
    set ::icc::fake::state login
    ::icc::fake::Handle "level2settings=[::icc::settings] guest"
    foreach cmd {{play 6} e4 Nf3 Nf3 {observe 21} next mismatch unobserve clock offers {tell Admin hello} {tell 4 hello}} {
        ::icc::fake::Handle $cmd
    }
    set ids {}
    set styles 0
    foreach event [::icc::extractFrames ::icc::test::wire 1000] {
        lassign $event kind payload
        if {$kind eq "datagram"} {
            lappend ids [lindex [::icc::fields $payload] 0]
        } elseif {$kind eq "text" && [string match {<12> *} $payload]} {
            if {[::ics::parseStyle12 [::ics::cleanLine $payload]] eq ""} { error {invalid mock style12} }
            incr styles
        }
    }
    list $styles [expr {26 in $ids && 16 in $ids && 56 in $ids && 18 in $ids && 19 in $ids}] $::icc::test::wire
} -cleanup {
    rename ::icc::fake::Write {}
    rename ::icc::fake::SocketWrite ::icc::fake::Write
    ::icc::fake::Stop
} -result {8 1 {}}
tcltest::cleanupTests
