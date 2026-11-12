# Shared synthetic credential for loopback fixtures only. Never loads a user token.
namespace eval ::lichess {}
proc ::lichess::testToken {} {
    if {[info exists ::env(CHESSWIZ_LICHESS_TEST_TOKEN)]} {
        set value $::env(CHESSWIZ_LICHESS_TEST_TOKEN)
    } else {
        set value [string cat lip_ 0123456789 abcdefghij]
    }
    if {![regexp {^lip_[A-Za-z0-9]{20}$} $value]} {
        error "Invalid synthetic Lichess credential format"
    }
    return $value
}
