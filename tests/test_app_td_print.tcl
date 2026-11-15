package require tcltest 2.5

namespace eval ::tdPrint { variable counter 0 }
proc ::tdPrint::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency pr[incr counter]]]
}

tcltest::test td-print-pairings-standings-crosstable {td.print generates pairings, standings and crosstable in HTML, text and PDF formats} -body {
    set path [file join $::env(HOME) print.tdj]
    ::tdPrint::call $path create {name {Print Open} players {Alpha Beta Gamma Delta} system swiss rounds 2 start 1}
    ::tdPrint::call $path enter_result {pairing r1b0 result 1-0 category played}
    ::tdPrint::call $path enter_result {pairing r1b1 result 1/2-1/2 category played}
    set pFile [file join $::env(HOME) pairings.html]
    set sFile [file join $::env(HOME) standings.txt]
    set cFile [file join $::env(HOME) crosstable.pdf]
    set pRes [::td::actions::Print [dict create path $path view pairings format html round 1 filename $pFile overwrite 1]]
    set sRes [::td::actions::Print [dict create path $path view standings format text filename $sFile overwrite 1]]
    set cRes [::td::actions::Print [dict create path $path view crosstable format pdf filename $cFile overwrite 1]]
    set f [open $cFile rb]; set pdfBytes [read $f 8]; close $f
    list [file exists $pFile] [string match "*Round 1 Pairings*" [dict get $pRes content]] \
        [file exists $sFile] [string match "*Alpha*" [dict get $sRes text]] \
        [file exists $cFile] [string match "%PDF-1.4*" $pdfBytes]
} -result {1 1 1 1 1 1}

tcltest::cleanupTests
