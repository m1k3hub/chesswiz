# ======================================================================
# Scidb App Test - Run 14 tester bugs (Windows laptop)
# ======================================================================
# 1. Player card: Latest/Highest Elo came from an old dictionary entry
#    (1907/1950) below the games' own range (2767-2771); the title was
#    blank while the games say GM.
# 3. Advanced Search was 1943 px wide on a 1920 px screen at 200%.
# 2. F1 in Game Overview found no English page; F1 in Advanced Search
#    opened the general overview.
# ======================================================================
package require tcltest 2.5
namespace eval ::scidb::test::run14 {}

proc ::scidb::test::run14::card {name} {
	set base /tmp/claude-1000/twic/twic1600.sci
	if {![::scidb::db::get open? $base]} { ::application::database::openBase .application $base yes -readonly 1 }
	set n [::scidb::db::count games $base Normal]
	for {set g 0} {$g < $n} {incr g} {
		set info [::scidb::db::fetch whitePlayerInfo $g $base Normal -card -ratings {Any Any}]
		if {[lindex $info 0] eq $name} { break }
	}
	# the preamble exactly as the card builds it
	set fh [open [file join $::scidb::test::app::testDir .. .. .. .. tcl player-card.tcl]]; set src [read $fh]; close $fh
	regexp {set preamble ("[^"]*")} $src -> preamble
	set preamble [string map [list {$name} $name] $preamble]
	set preamble [namespace eval ::playercard [list subst [string range $preamble 1 end-1]]]
	set r [::scidb::db::playerCard [file join $::scidb::dir::share scripts] player-card.eXt \
		$preamble $base Normal $g white]
	return [lindex $r 0]
}

tcltest::test run14-card {the card's highest Elo is not below the games' range, and the title comes from the games} -body {
	set html [::scidb::test::run14::card "Abdusattorov, Nodirbek"]
	regsub -all {<[^>]*>} $html " " text
	regexp {Latest\s+(\d+)} $text -> latest
	regexp {Highest\s+(\d+)} $text -> highest
	regexp {Maximal\s+(\d+)} $text -> maximal
	list [regexp {GM} $text] [expr {$highest >= $maximal && $highest >= $latest && $latest > 2600}]
} -result {1 1}

tcltest::test run14-help {the English help has pages for Game Overview and Advanced Search} -body {
	set d [file join $::scidb::test::app::testDir .. .. .. .. tcl help en]
	list [file exists $d/Game-Overview.html] [file exists $d/Advanced-Search.html]
} -result {1 1}

tcltest::test run14-advanced-width {Advanced Search fits a 1920 px screen at 200% (with room for wider Windows fonts)} -body {
	set base /tmp/claude-1000/twic/twic1600.sci
	if {![::scidb::db::get open? $base]} { ::application::database::openBase .application $base yes -readonly 1 }
	set ns ::application::database
	set dlg [${ns}::AdvancedDialogName $base Normal]
	catch { destroy $dlg }
	set scaling [tk scaling]
	tk scaling [expr {2*96/72.0}]
	${ns}::OpenAdvancedSearch .application $base Normal
	update
	set w [winfo reqwidth $dlg]
	if {[info exists ::env(RUN14_SHOT)]} { ::util::execSafe import -window [winfo id $dlg] $::env(RUN14_SHOT) }
	destroy $dlg
	tk scaling $scaling
	puts "advanced search width at 200%: $w"
	# 1596 here was 1943 on the laptop: Windows fonts are wider
	expr {$w <= 1400}
} -result 1

tcltest::cleanupTests
