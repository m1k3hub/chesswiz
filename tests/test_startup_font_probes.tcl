# Headless startup regression: HTML fallback probes must not grow with the
# number of preferred families. Run: tclsh tests/test_startup_font_probes.tcl
package require tcltest
set fd [open [file join [file dirname [info script]] .. tcl fonts.tcl]]
set source [read $fd]
close $fd
set start [string first {proc textFonts {}} $source]
set script {}
foreach line [split [string range $source $start end] \n] {
    append script $line \n
    if {[info complete $script]} {break}
}
namespace eval ::fontProbe {
    variable DefaultTextFamilies {Inter Roboto TkTextFont}
    variable calls {}
    variable delay 0
    proc getFontFamilyName {family} {
        lappend ::fontProbe::calls $family
        if {$::fontProbe::delay} {after $::fontProbe::delay}
        switch -- $family {
            Inter {return Inter}
            Roboto {return Roboto}
            TkTextFont {return System}
            default {return Fallback}
        }
    }
}
namespace eval ::fontProbe $script

tcltest::test startup-font-probes-1 {fallback order remains identical} -body {
    ::fontProbe::textFonts
} -result {Inter Fallback Roboto System}

tcltest::test startup-font-probes-2 {each generic fallback is resolved once} -body {
    foreach name {Sans-Serif {Sans Serif} Helvetica} {
        if {[llength [lsearch -all -exact $::fontProbe::calls $name]] != 1} {return 0}
    }
    return 1
} -result 1

tcltest::test startup-font-probes-3 {subsequent requests reuse the family list} -body {
    set before $::fontProbe::calls
    ::fontProbe::textFonts
    expr {$before eq $::fontProbe::calls}
} -result 1

tcltest::test startup-font-probes-4 {startup font probing stays within a tolerant budget} -setup {
    unset -nocomplain ::fontProbe::TextFamilies_
    set ::fontProbe::delay 20
} -body {
    # Controlled slow font service: six probes cost 120 ms; the old repeated
    # fallbacks cost 240 ms. Allow 80 ms for scheduler variation.
    set start [clock milliseconds]
    ::fontProbe::textFonts
    expr {[clock milliseconds] - $start < 200}
} -cleanup {
    set ::fontProbe::delay 0
} -result 1

tcltest::cleanupTests
