# Real app/API persistence regression; CW_PERSIST_PHASE=seed/restore runs in
# separate processes with the same isolated HOME via the evidence rerun script.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::persist {}
proc ::scidb::test::persist::Save {} {
    ::options::startTransaction
    ::options::saveOptionsFile
    ::options::endTransaction
}
proc ::scidb::test::persist::Score {count {early 0}} {
    ::lichess::puzzles::StartStorm
    for {set i 0} {$i < $count} {incr i} {
        ::scidb::test::wait::until {$::lichess::puzzles::Priv(state) eq "solving"}
        if {![::lichess::puzzles::CheckUserMove e2e4 0]} {error "fixture move rejected"}
        # Wait for the next genuine API response, not the previous solved state.
        ::scidb::test::wait::until {$::lichess::puzzles::Priv(state) eq "solving"}
    }
    if {$early} {::lichess::puzzles::StopStorm} else {
        ::scidb::test::wait::until {!$::lichess::puzzles::Priv(stormActive)} 15000
    }
    list $::lichess::puzzles::Priv(stormScore) $::lichess::Options(stormBest)
}
set ::scidb::test::persist::base $::lichess::api::Base
set ::lichess::api::Base [::lichess::fake::Start]
set ::lichess::api::BackoffUntil 0
::lichess::fake::Set stormPuzzle 1
# A fake-only in-memory credential; never read or write the user's token store.
rename ::lichess::api::TokenLoad ::scidb::test::persist::OriginalTokenLoad
proc ::lichess::api::TokenLoad {} {return fixture_persistence}
set ::lichess::fake::Token fixture_persistence
set phase [expr {[info exists ::env(CW_PERSIST_PHASE)] ? $::env(CW_PERSIST_PHASE) : "seed"}]
if {$phase eq "seed"} {
    tcltest::test persist-seed {select/watch/follow via real API and save completed best} -body {
        ::lichess::tv::open
        ::scidb::test::wait::until {$::lichess::tv::Priv(selectedChannel) eq "Best" && $::lichess::tv::Priv(roundId) eq "round1"}
        ::lichess::tv::WatchSelectedChannel
        ::lichess::tv::FollowBroadcastRound
        ::lichess::tv::StopStream
        ::lichess::puzzles::open
        set ::lichess::Options(stormBest) 0
        set ::lichess::puzzles::StormDuration 8
        set scores [list [::scidb::test::persist::Score 12] [::scidb::test::persist::Score 7] [::scidb::test::persist::Score 12] [::scidb::test::persist::Score 20 1]]
        ::scidb::test::persist::Save
        puts "Storm score/best sequence: $scores"
        set scores
    } -result {{12 12} {7 12} {12 12} {20 12}}
} else {
    tcltest::test persist-restart {options loaded by app startup; preselection never starts streams} -body {
        set loaded [list $::lichess::Options(tvChannel) $::lichess::Options(broadcastRound) $::lichess::Options(stormBest)]
        ::lichess::tv::open
        ::scidb::test::wait::until {[llength $::lichess::tv::Priv(channels)] && [llength $::lichess::tv::Priv(broadcasts)]}
        update
        set selections [list [$::lichess::tv::Priv(widget:channels) selection] [$::lichess::tv::Priv(widget:broadcasts) selection]]
        set streams [lsearch -all -inline -regexp [lmap r [::lichess::fake::Requests] {dict get $r path}] {feed|stream}]
        if {[info exists ::env(CW_PERSIST_EVIDENCE)]} {
            exec import -window [winfo id [winfo toplevel $::lichess::tv::Priv(tab)]] [file join $::env(CW_PERSIST_EVIDENCE) preselection.png]
        }
        ::lichess::puzzles::open
        list $loaded $selections $streams $::lichess::puzzles::Priv(stormBestText)
    } -result {{Best round1 12} {Best round1} {} {Best Storm: 12}}
}
tcltest::test persist-stale {server drops saved channel and round; empty default without streaming} -body {
    ::lichess::tv::open
    ::lichess::fake::Set dropTvChannel Best
    ::lichess::fake::Set dropBroadcastRound round1
    ::lichess::tv::RefreshChannels
    ::lichess::tv::RefreshBroadcasts
    ::scidb::test::wait::until {$::lichess::tv::Priv(channels) eq "" && $::lichess::tv::Priv(roundId) eq ""}
    list $::lichess::Options(tvChannel) $::lichess::Options(broadcastRound) $::lichess::tv::Priv(streamHandle)
} -result {{} {} {}}
set ::scidb::test::persist::bestBeforeCorrupt $::lichess::Options(stormBest)
tcltest::test persist-corrupt {arbitrary saved values fall back safely on offered rows} -body {
    set ::lichess::Options(tvChannel) "\{\[invalid channel"
    set ::lichess::Options(broadcastRound) "\{\[invalid round"
    set ::lichess::Options(stormBest) "garbage"
    ::lichess::fake::Set dropTvChannel {}
    ::lichess::fake::Set dropBroadcastRound {}
    ::lichess::tv::RefreshChannels
    ::lichess::tv::RefreshBroadcasts
    ::scidb::test::wait::until {$::lichess::Options(tvChannel) eq "Best" && $::lichess::Options(broadcastRound) eq "round1"}
    ::lichess::puzzles::UpdateStormBest
    list $::lichess::tv::Priv(selectedChannel) $::lichess::tv::Priv(roundId) $::lichess::Options(stormBest)
} -result {Best round1 0}
# Preserve the seed/restore record for the next app process.
set ::lichess::Options(tvChannel) Best
set ::lichess::Options(broadcastRound) round1
set ::lichess::Options(stormBest) $::scidb::test::persist::bestBeforeCorrupt
::scidb::test::persist::Save
::lichess::puzzles::StopStorm
foreach tab {lichess-tv lichess-puzzles} {catch {::online::window::closeTab $tab}}
::lichess::fake::Stop
rename ::lichess::api::TokenLoad {}
rename ::scidb::test::persist::OriginalTokenLoad ::lichess::api::TokenLoad
set ::lichess::api::Base $::scidb::test::persist::base
set ::lichess::puzzles::StormDuration 180
tcltest::cleanupTests
