# Headless HTTPS plumbing regressions; no GUI, credentials or network.
package require tcltest 2.5
namespace import ::tcltest::*
set root [file normalize [file join [file dirname [info script]] ..]]
source $root/tcl/contrib/http.tcl
source $root/tcl/sys-platform.tcl
source $root/tcl/ai-provider.tcl

# Load UI-free procedures from the actual modules without their UI startup.
proc loadProc {path name} {
    set f [open $path]; set text [read $f]; close $f
    set start [string first "proc $name " $text]
    if {$start < 0} { error "missing procedure $name" }
    set code ""
    foreach line [split [string range $text $start end] \n] {
        append code $line \n
        if {[info complete $code]} { uplevel #0 $code; return }
    }
    error "incomplete procedure $name"
}
namespace eval ::application::download {}
namespace eval ::iccf::xfcc {}
loadProc $root/tcl/app-download-games.tcl ::application::download::Tls
# XFCC procedures are defined inside their namespace.
set xfccNamespace ::iccf::xfcc
namespace eval ::iccf::xfcc::mc {}
loadProc $root/tcl/iccf-xfcc.tcl initTls
rename ::initTls ${xfccNamespace}::initTls

# The companion Python runner supplies a local TLS echo server and CA.
# Ordinary unit runs require neither TLS nor network access.
set localTls [expr {[info exists ::env(HTTPS_TEST_PORT)]}]
testConstraint localTls $localTls
test https-local-post {download then AI POST uses real TLS with correct SNI and UTF-8 bytes} -constraints localTls -body {
    package require tls
    ::tls::init -cafile $::env(HTTPS_TEST_CA) -require 1
    set url https://localhost:$::env(HTTPS_TEST_PORT)/post
    ::application::download::Tls unrelated.example
    set body {"message":"é ♔"}
    set tok [::ai::provider::request $url $body]
    set result [list [::http::status $tok] [::http::ncode $tok] [::ai::provider::body $tok]]
    ::http::cleanup $tok
    ::http::unregister https
    ::application::download::Tls unrelated.example
    set tok [::http::geturl $url -timeout 5000]
    lappend result [::http::status $tok] [::http::ncode $tok]
    ::http::cleanup $tok
    set result
} -result [list ok 200 {"message":"é ♔"} ok 200]

test https-local-large-post {request bodies above 64 KB go through the Windows blocking writer} -constraints localTls -body {
    ::platform::sys::tlsRegister
    ::platform::sys::BlockingHttpWrite
    set body "\"[string repeat x 200000]\""
    set tok [::ai::provider::request https://localhost:$::env(HTTPS_TEST_PORT)/post $body]
    set result [list [::http::status $tok] [::http::ncode $tok] [string length [::ai::provider::body $tok]]]
    ::http::cleanup $tok
    set result
} -result {ok 200 200002}

if {[catch {package present tls}]} { package provide tls 1.7.22 }
namespace eval ::tls {}
proc ::tls::socket {args} { set ::socketArgs $args; return fakeSocket }
proc ::tls::init {args} {}
rename ::http::geturl ::http::realGeturl
proc ::http::geturl {url args} {
    if {![info exists ::http::urlTypes(https)]} { ::error {Unsupported URL type "https"} }
    regexp {^https://([^/:]+)} $url -> host
    set handler [lindex $::http::urlTypes(https) 1]
    {*}$handler -async -myaddr 127.0.0.1 $host 443
    set ::requestArgs $args
    return testToken
}

test https-cross-host {download registration must not pin the AI POST SNI} -body {
    ::ai::provider::request https://api.example/chat {}
    ::application::download::Tls downloads.example
    ::ai::provider::request https://api.example/chat {"message":"é"}
    ::application::download::Tls downloads.example
    ::ai::provider::request https://api.example/chat {"message":"é"}
    list $::socketArgs [dict get $::requestArgs -query]
} -result [list {-servername api.example -async -myaddr 127.0.0.1 api.example 443} [encoding convertto utf-8 {"message":"é"}]]

test https-provider-recovery {AI must recover a removed HTTPS entry despite a previous request} -body {
    ::ai::provider::request https://api.example/chat {}
    ::http::unregister https
    ::ai::provider::request https://api.example/chat {}
} -result testToken

test https-download-recovery {same download host must recover a removed handler} -body {
    ::application::download::Tls downloads.example
    catch {::http::unregister https}
    ::application::download::Tls downloads.example
    info exists ::http::urlTypes(https)
} -result 1

test https-xfcc-recovery {already initialized ICCF must restore the shared handler} -body {
    set ${xfccNamespace}::Config(initialized) 1
    set ${xfccNamespace}::Config(host) iccf.example
    catch {::http::unregister https}
    ${xfccNamespace}::initTls
    set ::http::urlTypes(https)
} -result {443 ::platform::sys::tlsSocket}

test https-iccf-cross-host {ICCF registration cannot pin subsequent AI SNI} -body {
    ${xfccNamespace}::initTls
    ::ai::provider::request https://api.example/chat {}
    set ::socketArgs
} -result {-servername api.example -async -myaddr 127.0.0.1 api.example 443}

if {[catch {package present json}]} { package provide json 1.0 }
set ::ai::provider::Config(keys) {fireworks test-key}
test https-models-recovery {async cloud model GET restores HTTPS after removal} -body {
    catch {::http::unregister https}
    ::ai::provider::modelsAsync fireworks {list}
    set ::socketArgs
} -result {-servername api.fireworks.ai -async -myaddr 127.0.0.1 api.fireworks.ai 443}

namespace eval ::application::assistant {
    variable TablebaseUrl https://tablebase.lichess.ovh/standard
    proc Later {} { return tablebaseToken }
}
loadProc $root/tcl/app-assistant.tcl ::application::assistant::DoTablebase
test https-tablebase-recovery {tablebase lookup restores HTTPS after removal} -body {
    catch {::http::unregister https}
    ::application::assistant::DoTablebase {8/8/8/8/8/8/4k3/7K w - - 0 1}
    set ::socketArgs
} -result {-servername tablebase.lichess.ovh -async -myaddr 127.0.0.1 tablebase.lichess.ovh 443}

namespace eval ::web {}
loadProc $root/tcl/utils/web.tcl GetURL
rename ::GetURL ::web::GetURL
test https-web-recovery {web download restores HTTPS before every retry} -body {
    catch {::http::unregister https}
    ::web::GetURL . https://web.example/file -timeouts {1000 3000} -failedcmd {}
    set ::socketArgs
} -result {-servername web.example -async -myaddr 127.0.0.1 web.example 443}

test https-resource {resourcing bundled HTTP preserves HTTPS registration} -body {
    ::http::register https 443 ::platform::sys::tlsSocket
    source $root/tcl/contrib/http.tcl
    package require http 2.7
    set ::http::urlTypes(https)
} -result {443 ::platform::sys::tlsSocket}

test https-reset {resetting a request closes its socket but preserves protocol registration} -body {
    lassign [chan pipe] readEnd writeEnd
    array set ::http::httpsResetToken [list status ok sock $readEnd -keepalive 0]
    ::http::reset ::http::httpsResetToken
    ::http::cleanup ::http::httpsResetToken
    close $writeEnd
    set ::http::urlTypes(https)
} -result {443 ::platform::sys::tlsSocket}

set failed $::tcltest::numTests(Failed)
cleanupTests
exit [expr {$failed != 0}]
