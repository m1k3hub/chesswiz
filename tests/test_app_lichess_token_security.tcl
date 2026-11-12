# SEC-001: real token storage, real loopback authentication and options output.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::security {}
tcltest::test lichess-token-security {real token store is private; UI and options never retain credential} -setup {
    set ::scidb::test::security::base $::lichess::api::Base
    set ::lichess::api::Base [::lichess::fake::Start]
    set ::lichess::api::BackoffUntil 0
    set ::lichess::fake::Token [::lichess::testToken]
} -body {
    ::lichess::open .application
    set ::lichess::Priv(dlg:token) [::lichess::testToken]
    ::lichess::UseToken
    ::scidb::test::wait::until {$::lichess::Priv(state) eq "lobby" && $::lichess::Priv(username) ne ""}
    set stored [expr {[::lichess::api::TokenLoad] eq [::lichess::testToken]}]
    set private [expr {([file attributes [::lichess::api::TokenFile] -permissions] & 0777) == 0600}]
    set cleared [expr {$::lichess::Priv(dlg:token) eq ""}]
    set absent [expr {[string first [::lichess::testToken] [array get ::lichess::Priv]] < 0}]
    ::options::startTransaction
    ::options::saveOptionsFile
    ::options::endTransaction
    if {[info exists ::env(CW_TOKEN_EVIDENCE)]} {
        exec import -window [winfo id [winfo toplevel $::lichess::Priv(widget:signin)]] [file join $::env(CW_TOKEN_EVIDENCE) signed-in.png]
    }
    # Keep the store until the shell scanner has checked the one allowed file.
    list $stored $private $cleared $absent
} -cleanup {
    ::lichess::Close
    ::lichess::fake::Stop
    set ::lichess::api::Base $::scidb::test::security::base
} -result {1 1 1 1}
tcltest::cleanupTests
