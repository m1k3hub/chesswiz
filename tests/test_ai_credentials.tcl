# Run with tkchesswiz (or tclsh for abstraction tests).
package require Tcl 8.6
if {![llength [info commands winfo]]} { package provide Tk 8.6 }
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl app-ai.tcl]
set failures 0
proc check {name value} {
    if {$value} { puts "PASS: $name" } else { puts "FAIL: $name"; incr ::failures }
}
set dir [file join $root tests tmp-app d9 keys-[pid]]
namespace eval ::scidb::dir {}
set ::scidb::dir::user $dir
# Force the Linux backend without changing the interpreter's platform.
rename ::application::ai::CredentialStore ::application::ai::RealCredentialStore
proc ::application::ai::CredentialStore {} {return 0}
::application::ai::setKey openai { test-key }
check file-created [file exists [::application::ai::KeyFile]]
set ::application::ai::Keys {}
::application::ai::loadKeys
check file-roundtrip [expr {[::application::ai::key openai] eq "test-key"}]
::application::ai::setKey openai {}
::application::ai::loadKeys
check file-delete [expr {[::application::ai::key openai] eq ""}]
if {$::tcl_platform(platform) eq "unix"} {
    check private-permissions [expr {([file attributes [::application::ai::KeyFile] -permissions] & 0777) == 0600}]
}
# Mock the OS backend to verify migration and failure preservation.
namespace eval ::scidb::sys {}
proc ::scidb::sys::credentialMock {op service account args} {
    if {$::reject} {error "store locked"}
    switch $op {
        get {return [expr {[dict exists $::vault $account] ? [dict get $::vault $account] : ""}]}
        set {dict set ::vault $account [lindex $args 0]}
        delete {dict unset ::vault $account}
    }
}
if {[llength [info commands ::scidb::sys::credential]]} {rename ::scidb::sys::credential ::scidb::sys::nativeCredential}
interp alias {} ::scidb::sys::credential {} ::scidb::sys::credentialMock
proc ::application::ai::CredentialStore {} {return 1}
set vault [dict create openai newer]; set reject 0
::application::ai::WriteKeyFile {openai old anthropic legacy}
set reject 1
check migration-failure [catch {::application::ai::loadKeys}]
check plaintext-retained [file exists [::application::ai::KeyFile]]
set reject 0
::application::ai::loadKeys
check migrated [expr {[dict get $vault anthropic] eq "legacy"}]
check existing-preserved [expr {[::application::ai::key openai] eq "newer"}]
check plaintext-removed [expr {![file exists [::application::ai::KeyFile]]}]
set ::application::ai::Keys {}
::application::ai::loadKeys
check store-reload [expr {[::application::ai::key anthropic] eq "legacy"}]
set reject 1
check save-failure [catch {::application::ai::setKey anthropic rejected}]
check memory-preserved [expr {[::application::ai::key anthropic] eq "legacy"}]
set reject 0
::application::ai::setKey anthropic replacement
check stored [expr {[dict get $vault anthropic] eq "replacement"}]
::application::ai::setKey anthropic {}
check deleted [expr {![dict exists $vault anthropic]}]
file delete -force $dir
puts "CREDENTIAL-FAILURES: $failures"
exit [expr {$failures != 0}]
