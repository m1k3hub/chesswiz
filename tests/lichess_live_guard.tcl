# Test-only live smoke policy and runner; inert until Install is called.
namespace eval ::scidb::test::live {
    variable Installed 0
    variable Out [file normalize tests/tmp-app/lichess-hardening/VAL-LICHESS-LIVE-001]
    file mkdir $Out
}

proc ::scidb::test::live::Deny {} {
    incr ::scidb::test::live::Violations
    error "Live smoke request guard aborted" {} {LICHESS LIVE GUARD}
}

# Exact comparisons deliberately reject queries, escapes, suffixes, alternate
# origins and arbitrary game IDs. This is a policy lookup, not a semantic task.
proc ::scidb::test::live::Check {method path form} {
    variable AccountOK
    variable Game
    if {$::scidb::test::live::Violations} { Deny }
    if {$method eq "GET" && $form eq {} && $path in {
        /api/account /api/tv/channels /api/puzzle/daily /api/broadcast/top
    }} { return }
    if {!$AccountOK} { Deny }
    if {$method eq "POST" && $path eq "/api/challenge/ai" &&
        $form eq [::http::formatQuery level 1 clock.limit 600 clock.increment 0 color white]} { return }
    if {$Game ne {} && $form eq {}} {
        if {$method eq "GET" && $path eq "/api/board/game/stream/$Game"} { return }
        if {$method eq "POST" && $path eq "/api/board/game/$Game/resign"} { return }
    }
    Deny
}

proc ::scidb::test::live::Install {origin} {
    variable Origin $origin
    variable AccountOK 0
    variable Bot 0
    variable Game {}
    variable Created 0
    variable Violations 0
    variable Wire {}
    variable StatusLogged {}
    variable AiWire 0
    variable Log {}
    variable Handle {}
    variable FirstState 0
    variable SavedBase $::lichess::api::Base
    variable SavedMode $::lichess::api::Mode
    variable SavedBackoff $::lichess::api::BackoffUntil
    # Pending requests from other tabs must never leak into the smoke run.
    if {[dict size $::lichess::api::Requests]} { error "Close existing Lichess requests before smoke test" }
    set ::lichess::api::Base $origin
    set ::lichess::api::BackoffUntil 0
    ::lichess::api::mode board
    set ::scidb::test::live::Installed 1
    rename ::lichess::api::Request ::lichess::api::LiveOriginalRequest
    proc ::lichess::api::Request {method path form cmd args} {
        ::scidb::test::live::Check $method $path $form
        if {$path eq "/api/challenge/ai"} {
            if {$::scidb::test::live::Created} { ::scidb::test::live::Deny }
            set ::scidb::test::live::Created 1
        }
        LiveOriginalRequest $method $path $form \
            [list ::scidb::test::live::Reply $method $path $cmd] {*}$args
    }
    # Guard the actual wire as well as API creation: covers retries, changed
    # Base, pending URLs, direct app HTTP calls and attempted redirect follows.
    rename ::http::geturl ::http::LiveOriginalGeturl
    proc ::http::geturl {url args} {
        ::scidb::test::live::WireRequest $url {*}$args
    }
}

proc ::scidb::test::live::WireRequest {url args} {
    variable Origin
    variable Wire
    set prefix "$Origin/"
    if {![string equal -length [string length $prefix] $url $prefix]} { Deny }
    set path [string range $url [string length $Origin] end]
    set method {}
    set hasQuery 0
    set form {}
    set callback {}
    set handler {}
    set opts {}
    foreach {key value} $args {
        switch -- $key {
            -method { set method $value }
            -query { set form $value; set hasQuery 1 }
            -querychannel { Deny }
            -command { set callback $value; continue }
            -handler { set handler $value; continue }
        }
        lappend opts $key $value
    }
    if {$method eq {}} { set method [expr {$hasQuery ? "POST" : "GET"}] }
    Check $method $path $form
    if {$path eq "/api/challenge/ai" && [incr ::scidb::test::live::AiWire] > 1} { Deny }
    set attempt [llength $Wire]
    lappend Wire [list $method $path]
    puts "REQUEST $method $path status=pending"
    if {$handler ne {}} {
        lappend opts -handler [list ::scidb::test::live::WireRead $attempt $method $path $handler]
    }
    ::http::LiveOriginalGeturl $url {*}$opts \
        -command [list ::scidb::test::live::WireDone $attempt $method $path $callback]
}

proc ::scidb::test::live::LogStatus {attempt method path h} {
    variable StatusLogged
    variable Log
    if {[dict exists $StatusLogged $attempt]} { return }
    dict set StatusLogged $attempt 1
    set status [::http::ncode $h]
    if {![string is integer -strict $status]} { set status 0 }
    lappend Log [list $method $path $status]
    puts "RESPONSE $method $path status=$status"
}

proc ::scidb::test::live::WireDone {attempt method path callback h} {
    LogStatus $attempt $method $path $h
    if {$callback ne {}} { uplevel #0 [list {*}$callback $h] }
}
proc ::scidb::test::live::WireRead {attempt method path callback sock h} {
    # close() intentionally suppresses the completion callback. Record HTTP
    # status on the first stream read, before the first-state callback closes it.
    LogStatus $attempt $method $path $h
    uplevel #0 [list {*}$callback $sock $h]
}

proc ::scidb::test::live::Reply {method path callback reply} {
    variable AccountOK
    variable Bot
    variable Game
    if {$path eq "/api/account"} {
        set AccountOK 0
        if {[dict get $reply ok] && [dict exists $reply data id]} {
            set d [dict get $reply data]
            set Bot [expr {[dict exists $d title] && [dict get $d title] eq "BOT"}]
            set AccountOK [expr {!$Bot}]
        }
    }
    if {$path eq "/api/challenge/ai" && [dict get $reply ok]} {
        if {[dict exists $reply data id] && [regexp {^[a-zA-Z0-9]{1,32}$} [dict get $reply data id]]} {
            set Game [dict get $reply data id]
        }
    }
    uplevel #0 [list {*}$callback $reply]
}

proc ::scidb::test::live::Call {command args} {
    variable Result
    unset -nocomplain Result
    ::lichess::api::$command {*}$args [list set ::scidb::test::live::Result]
    ::scidb::test::wait::until {[info exists ::scidb::test::live::Result]} 45000
    if {![dict get $Result ok]} { error "Smoke API call failed (response suppressed)" }
    return $Result
}

proc ::scidb::test::live::State {reply} {
    variable FirstState
    variable Handle
    if {[dict exists $reply type] && [dict get $reply type] in {gameFull gameState}} {
        set FirstState 1
        ::lichess::api::close $Handle
        set Handle {}
    }
}

proc ::scidb::test::live::Run {{timeout 45000}} {
    variable AccountOK
    variable Bot
    variable Game
    variable Handle
    variable FirstState
    # Raw Request preserves title; account() intentionally strips that field.
    Call Request GET /api/account {}
    if {$Bot || !$AccountOK} { error "Smoke aborted: requires a verified non-bot account" }
    Call tvChannels
    Call puzzleDaily
    Call broadcastsTop
    Call challengeAi 1 10 0 white
    if {$Game eq {}} { error "Smoke challenge did not return a safe game ID" }
    try {
        set Handle [::lichess::api::streamGame $Game ::scidb::test::live::State]
        ::scidb::test::wait::until {$::scidb::test::live::FirstState} $timeout
    } finally {
        if {$Handle ne {}} { ::lichess::api::close $Handle; set Handle {} }
        # Resign even if the first-state wait fails after game creation.
        Call resign $Game
        puts "RESIGNED game=$Game"
    }
    if {!$FirstState || $::scidb::test::live::Violations} { error "Smoke guard/state check failed" }
    return ok
}

proc ::scidb::test::live::Uninstall {} {
    variable Installed
    if {!$Installed} { return }
    set Installed 0
    foreach id [dict keys $::lichess::api::Requests] { ::lichess::api::close $id }
    update
    foreach {name original} {
        ::lichess::api::Request ::lichess::api::LiveOriginalRequest
        ::http::geturl ::http::LiveOriginalGeturl
    } {
        rename $name {}
        rename $original $name
    }
    set ::lichess::api::Base $::scidb::test::live::SavedBase
    set ::lichess::api::BackoffUntil $::scidb::test::live::SavedBackoff
    ::lichess::api::mode $::scidb::test::live::SavedMode
}

