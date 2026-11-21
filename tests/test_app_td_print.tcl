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

tcltest::test td-print-f5-multipage-pdf-100-players {F5: 100-player standings and crosstable PDFs paginate across multiple pages without truncating tail players} -body {
    set fixPath [file normalize [file join [file dirname [info script]] fixtures td chessament-tournament-1.trf]]
    set path [file join $::env(HOME) print100.tdj]
    ::tdPrint::call $path import_trf [dict create filename $fixPath system swiss]

    set sPdf [file join $::env(HOME) standings100.pdf]
    set cPdf [file join $::env(HOME) crosstable100.pdf]
    set sRes [::td::actions::Print [dict create path $path view standings format pdf filename $sPdf overwrite 1]]
    set cRes [::td::actions::Print [dict create path $path view crosstable format pdf filename $cPdf overwrite 1]]

    set sContent [dict get $sRes content]
    set cContent [dict get $cRes content]
    set st100 [dict get [::td::store::Read $path] state]
    set rows100 [::td::score::Compute $st100]
    set rank1Player [dict get [lindex $rows100 0] name]
    set rank100Player [dict get [lindex $rows100 end] name]

    set sPageCount 0
    set cPageCount 0
    regexp {/Type /Pages /Kids \[[^\]]+\] /Count ([0-9]+)} $sContent -> sPageCount
    regexp {/Type /Pages /Kids \[[^\]]+\] /Count ([0-9]+)} $cContent -> cPageCount

    set hasRank100InStandingsPdf [expr {[string first $rank100Player $sContent] >= 0}]
    set hasRank100InCrosstablePdf [expr {[string first "| $rank100Player |" $cContent] >= 0 || [string first $rank100Player $cContent] >= 0}]

    # Also validate with external poppler pdftotext if available on host
    set popplerOk 1
    if {[auto_execok pdftotext] ne ""} {
        set extractedTxt [regsub -all {\s+} [exec pdftotext -layout $sPdf -] { }]
        set norm1 [regsub -all {\s+} $rank1Player { }]
        set norm100 [regsub -all {\s+} $rank100Player { }]
        set popplerOk [expr {[string first $norm1 $extractedTxt] >= 0 && [string first $norm100 $extractedTxt] >= 0}]
    }

    list [expr {$sPageCount >= 2}] [expr {$cPageCount >= 2}] $hasRank100InStandingsPdf $hasRank100InCrosstablePdf $popplerOk
} -result {1 1 1 1 1}

tcltest::cleanupTests
