package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::transferargs {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} {error $result}
        return $result
    }
    proc until {script} {
        set end [expr {[clock milliseconds]+15000}]
        while {![uplevel 1 [list expr $script]]} {
            if {[clock milliseconds]>$end} {error "timeout: $script"}
            update;after 10
        }
    }
    # A real loopback HTTP server; production HTTP, SOAP and XML parsing run unchanged.
    proc accept {chan address port} {
        fconfigure $chan -blocking 0 -translation binary -buffering none
        set ::scidb::test::transferargs::request($chan) {}
        fileevent $chan readable [list ::scidb::test::transferargs::serve $chan]
    }
    proc serve {chan} {
        variable request
        append request($chan) [read $chan]
        if {[eof $chan]} {close $chan;unset request($chan);return}
        set end [string first "\r\n\r\n" $request($chan)]
        if {$end < 0} {return}
        set length 0
        regexp -nocase {content-length: ([0-9]+)} $request($chan) _ length
        if {[string length $request($chan)] < $end+4+$length} {return}
        set ::scidb::test::transferargs::lastRequest $request($chan)
        set body {<soap:Envelope><soap:Body><GetMyGamesResponse><XfccGame><id>42</id><white>Generated White</white><black>Generated Black</black><result>Ongoing</result><myTurn>true</myTurn><moves>e4 e5</moves></XfccGame></GetMyGamesResponse></soap:Body></soap:Envelope>}
        if {[string match {GET *} $request($chan)]} {
            set target [lindex [split $request($chan) " "] 1]
            if {[string match */twic $target]} {
                set body {<a href="zips/twic2345g.zip">Generated TWIC fixture</a>}
            } elseif {[string match *.zip $target]} {
                set f [open $::env(C2E_TWIC_ZIP) rb];set body [read $f];close $f
            } elseif {[string match */archives $target]} {
                set body {{"archives":["https://api.chess.com/pub/player/generated/games/2026/01"]}}
            } else {
                set f [open [::scidb::test::actions::fixture] rb];set body [read $f];close $f
            }
        }
        puts -nonewline $chan "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: [string length $body]\r\nConnection: close\r\n\r\n$body"
        fileevent $chan readable {}
        close $chan
        unset request($chan)
    }
}
tcltest::test transfer-args-private-card {real card fields, identity, photo and deletion persist without the form} -setup {
    ::scidb::test::actions::ready
    set cards [::playercard::privateCards]
    set me $::application::ai::Settings(me)
    set photo [file join $::env(HOME) generated.png]
    set img [image create photo -width 2 -height 2]
    $img put red -to 0 0 2 2
    $img write $photo -format png
    image delete $img
} -body {
    ::scidb::test::transferargs::call menu.tools.player_card operation save name {Generated One} Birthday 2000.01.02 Me 1 photo $photo Score1 2100 Rating1 Elo
    ::scidb::test::transferargs::call menu.tools.player_card operation save name {Generated Two} Me 1
    unset ::playercard::Private
    set persisted [::scidb::test::transferargs::call menu.tools.player_card operation get name {Generated One}]
    set identity [::playercard::myCard]
    set photoExists [file exists [::playercard::PhotoPath {Generated One}]]
    ::scidb::test::transferargs::call menu.tools.player_card operation delete name {Generated Two}
    unset ::playercard::Private
    set deleted [::playercard::privateCard {Generated Two}]
    set noCollector [expr {![winfo exists .application.setupPrivateCard]}]
    ::scidb::test::transferargs::call menu.tools.player_card
    set opened [winfo exists .application.setupPrivateCard]
    ::scidb::test::transferargs::call menu.tools.player_card operation close
    list [dict get $persisted Birthday] [dict get $persisted Score1] [dict get $persisted Me] $identity $photoExists $deleted $noCollector $opened [winfo exists .application.setupPrivateCard]
} -cleanup {
    ::playercard::SavePrivate $cards
    set ::application::ai::Settings(me) $me
    file delete $photo [::playercard::PhotoPath {Generated One}]
} -result {2000.01.02 2100 0 {Generated Two} 1 {} 1 1 0}

tcltest::test transfer-args-correspondence {real offline SOAP request and response; native database refresh/open accept arguments} -setup {
    ::scidb::test::actions::ready
    set config [array get ::iccf::xfcc::Config]
    set server [socket -server ::scidb::test::transferargs::accept -myaddr 127.0.0.1 0]
    set port [lindex [fconfigure $server -sockname] 2]
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
} -body {
    ::scidb::test::transferargs::call menu.tools.iccf operation save username generated-user password generated-secret endpoint http://127.0.0.1:$port/xfcc
    set games [::scidb::test::transferargs::call menu.tools.correspondence operation sync]
    set rows [::scidb::test::transferargs::call menu.tools.correspondence operation refresh]
    ::scidb::test::transferargs::call menu.tools.correspondence operation open number 1
    list [llength $games] [dict get [lindex $games 0] id] \
        [string match *GetMyGames* $::scidb::test::transferargs::lastRequest] \
        [string match *generated-user* $::scidb::test::transferargs::lastRequest] \
        [llength [dict get $rows games]] [::scidb::game::query length] [winfo exists .application.corrGames]
} -cleanup {
    close $server
    array set ::iccf::xfcc::Config $config
} -result {1 42 1 1 0 4 0}

tcltest::test transfer-args-download {file transport executes real fetch queue and PGN import; cancellation stops pending queue} -setup {
    ::scidb::test::actions::ready
    set source [::scidb::test::actions::fixture]
    set base $::scidb::clipbaseName
    set before [::scidb::db::count games $base Normal]
} -body {
    ::scidb::test::transferargs::call menu.tools.download operation start source url url file://$source base $base
    ::scidb::test::transferargs::until {!$::application::download::Priv(running) && $::menu::DownloadResult ne ""}
    set result $::menu::DownloadResult
    set count [::scidb::db::count games $base Normal]
    ::scidb::test::transferargs::call menu.tools.download operation start source url url file://$source base $base
    ::scidb::test::transferargs::call menu.tools.download operation cancel
    ::scidb::test::transferargs::until {!$::application::download::Priv(running)}
    list [dict get $result ok] [expr {$count>$before}] $::application::download::Priv(cancel) [winfo exists .application.__download__]
} -result {1 1 1 0}

tcltest::test transfer-args-training {typed options reach real native candidate search and job state without a chooser} -setup {
    ::scidb::test::actions::ready
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
    set config [array get ::ai::engine::Config]
    ::ai::engine::configure -engine [::scidb::test::actions::engineProgram]
    set file [file join $::env(HOME) training.pgn]
} -body {
    set reply [::scidb::test::transferargs::call menu.training.training_set operation start max 1 scan 1 depth 1 filename $file]
    set state [list $::ai::cql::Priv(max) $::ai::cql::Priv(depth) $::ai::cql::Priv(file)]
    ::scidb::test::transferargs::call menu.training.training_set operation cancel
    ::scidb::test::transferargs::until {!$::ai::cql::Priv(running)}
    list [expr {$reply eq $file}] [lrange $state 0 1] [expr {[lindex $state 2] eq $file}] $::ai::cql::Priv(running)
} -cleanup {
    ::ai::engine::shutdown
    array set ::ai::engine::Config $config
} -result {1 {1 1} 1 0}

tcltest::test transfer-args-all-download-modes {local HTTP transport runs every native source builder, fetch, archive and import; broadcast timer cancels} -setup {
    ::scidb::test::actions::ready
    package require http
    set server [socket -server ::scidb::test::transferargs::accept -myaddr 127.0.0.1 0]
    set ::scidb::test::transferargs::port [lindex [fconfigure $server -sockname] 2]
    rename ::http::geturl ::http::c2eRealGeturl
    # Replace only transport addressing; native source selection, URL building,
    # HTTP implementation, response parsing, unzip and database import are real.
    proc ::http::geturl {url args} {
        return [::http::c2eRealGeturl http://127.0.0.1:$::scidb::test::transferargs::port/$url {*}$args]
    }
    set ::env(C2E_TWIC_ZIP) [file join $::env(HOME) twic-fixture.zip]
    exec python3 -c {import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'twic-fixture.pgn'); z.close()} $::env(C2E_TWIC_ZIP) [::scidb::test::actions::fixture]
} -body {
    set results {}
    foreach spec {
        {source twic issues 1}
        {source lichess lichess abcdefgh}
        {source study studies abcdefgh}
        {source broadcast broadcast https://lichess.org/broadcast/generated/round/abcdefgh}
        {source player site Lichess player Generated months 1}
        {source player site Chess.com player Generated months 1}
        {source url url https://example.invalid/generated.pgn}
    } {
        set base $::scidb::clipbaseName
        ::scidb::db::clear $base Normal
        set before [::scidb::db::count games $base Normal]
        ::scidb::test::transferargs::call menu.tools.download operation start base $base {*}$spec
        ::scidb::test::transferargs::until {$::menu::DownloadResult ne "" && !$::application::download::Priv(running)}
        set count [::scidb::db::count games $base Normal]
        lappend results [dict get $::menu::DownloadResult ok] [expr {$count>$before}]
    }
    ::scidb::test::transferargs::call menu.tools.download operation start base $base source broadcast broadcast https://lichess.org/broadcast/generated/round/abcdefgh refresh 1
    if {[catch {::scidb::test::transferargs::until {$::application::download::Priv(bcTimer) ne ""}} err]} {
        error "$err state=[array get ::application::download::Priv] result=$::menu::DownloadResult"
    }
    set timer $::application::download::Priv(bcTimer)
    ::scidb::test::transferargs::call menu.tools.download operation cancel
    list $results [expr {$timer ne ""}] $::application::download::Priv(bcTimer) $::application::download::Priv(bcActive)
} -cleanup {
    ::application::download::Close
    rename ::http::geturl {}
    rename ::http::c2eRealGeturl ::http::geturl
    close $server
    file delete $::env(C2E_TWIC_ZIP)
    unset ::env(C2E_TWIC_ZIP)
} -result {{1 1 1 1 1 1 1 1 1 1 1 1 1 1} 1 {} 0}
tcltest::cleanupTests
