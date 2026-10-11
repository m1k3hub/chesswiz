# Tiny tkchesswiz script: uses a dedicated test service, no application keys.
set out [open [file join [file dirname [info script]] native-result.txt] w]
set code [catch {
    set cmd ::scidb::sys::credential
    set service Chesswiz-D9-test
    set account "roundtrip-[pid]-\u00e9"
    if {$::tcl_platform(platform) ne "windows" && $::tcl_platform(os) ne "Darwin"} {
        if {![catch {$cmd get $service $account} result options] || $result ne "unavailable"} {error "Linux availability contract"}
    } else {
        try {
            $cmd delete $service $account
            if {[$cmd get $service $account] ne ""} {error "missing credential"}
            $cmd set $service $account "test-\u00e9\u4e2d"
            if {[$cmd get $service $account] ne "test-\u00e9\u4e2d"} {error "roundtrip"}
            $cmd set $service $account replacement
            if {[$cmd get $service $account] ne "replacement"} {error "update"}
        } finally {$cmd delete $service $account}
        if {[$cmd get $service $account] ne ""} {error "delete"}
        $cmd delete $service $account
    }
} result options]
puts $out "NATIVE-CREDENTIAL-FAILURES: $code"
if {$code} {puts $out $result; puts $out [dict get $options -errorinfo]}
close $out
exit $code
