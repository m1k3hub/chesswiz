# ======================================================================
# Scidb App Test Suite - linking a database's player names to the rating
# lists (Player::findVariant, ::scidb::db::linkPlayers, playerSpellings,
# the assistant's ResolvePlayer and BuildQuery)
# ======================================================================
# A name is linked only where the evidence agrees: a dropped patronymic or
# initial on a rare surname; initials, a numbered namesake or a dropped
# given name only when the games' Elo agrees; homonyms told apart by Elo.
# Everything else stays unlinked. The entries are invented.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5
namespace eval ::scidb::test::plink {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app plink-[pid]]
	variable Pgn [file join $Dir links.pgn]
}
# the spelling check of the working tree, not of the installed app
source [file join [file dirname [file normalize [info script]]] .. tcl player-data.tcl]
proc ::scidb::test::plink::nop {args} { return 0 }
proc ::scidb::test::plink::row {id name fed sex std born} {
	format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
		$id $name $fed $sex "" "" "" "" $std 0 10 0 0 10 0 0 10 $born ""
}
file mkdir $::scidb::test::plink::Dir
# the rating-list entries
set chan [open [file join $::scidb::test::plink::Dir list.txt] w]
puts $chan "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
foreach r {
	{999000601 {Linkalpha, Vladimir} RUS M 2600 1980}
	{999000602 {Linkalpha, Victor} RUS M 2200 1985}
	{999000603 {Namesakey, John} ENG M 2400 1970}
	{999000604 {Namesakey, John} USA M 1900 1990}
	{999000605 {Uniquerare, Anna} RUS F 2300 1975}
	{999000606 {Translit, Mikhail} LAT M 2600 1936}
	{999000607 {Translit, Sergey} LAT M 2600 1960}
	{999000608 {Translit, Maxim} LAT M 2550 1970}
} { puts $chan [::scidb::test::plink::row {*}$r] }
close $chan
::scidb::app::load fide [file join $::scidb::test::plink::Dir list.txt]
::scidb::app::load done
# the database: one game per name, with the Elo the games give
set chan [open $::scidb::test::plink::Pgn w]
set n 0
foreach {white elo} {
	{Linkalpha, V} 2590
	{Linkalpha, Vi} 0
	{Namesakey, John} 2390
	{Uniquerare, Anna Petrovna} 0
	{Uniquerare, Anna Maria} 0
	{Uniquerare, Anna} 2300
	{Linkalpha, Vladimir2} 0
	{Linkalpha, Vladimir3} 2610
	{Weirdo, Name:Other} 0
	{Translit, Mihail} 2610
	{Translit, Mihail X} 1800
} {
	puts $chan "\[Event \"L\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
	puts $chan "\[White \"$white\"\]\n\[Black \"Opponent, Plain\"\]\n\[Result \"1-0\"\]"
	if {$elo} { puts $chan "\[WhiteElo \"$elo\"\]" }
	puts $chan "\n1. e4 e5 1-0\n"
}
close $chan
::scidb::db::open $::scidb::test::plink::Pgn ::scidb::test::plink::nop {} ::scidb::test::plink::nop {}

proc ::scidb::test::plink::links {} {
	set out {}
	foreach row [::scidb::db::playerLinks $::scidb::test::plink::Pgn Normal] {
		lassign $row name games linked fide elo fed entry
		if {$name eq "Opponent, Plain"} continue
		dict set out $name [expr {$linked ? $fide : "-"}]
	}
	return $out
}

tcltest::test plink-link {only the names the evidence identifies are linked} -body {
	set before [::scidb::test::plink::links]
	set result [::scidb::db::linkPlayers $::scidb::test::plink::Pgn Normal]
	set after [::scidb::test::plink::links]
	list [dict get $before {Linkalpha, V}] \
		[lmap name [lsort [dict keys $after]] { list $name [dict get $after $name] }] \
		[lsort [dict get $result ambiguous]]
} -result {- {{{Linkalpha, V} 999000601} {{Linkalpha, Vi} -} {{Linkalpha, Vladimir2} -} {{Linkalpha, Vladimir3} 999000601} {{Namesakey, John} 999000603} {{Translit, Mihail} -} {{Translit, Mihail X} -} {{Uniquerare, Anna} 999000605} {{Uniquerare, Anna Maria} -} {{Uniquerare, Anna Petrovna} 999000605} {{Weirdo, Name:Other} -}} {{Linkalpha, Vi} {Linkalpha, Vladimir2} {Uniquerare, Anna Maria}}}

tcltest::test plink-again {linking twice changes nothing} -body {
	dict get [::scidb::db::linkPlayers $::scidb::test::plink::Pgn Normal] linked
} -result 0

tcltest::test plink-spellings {the spellings of one player are found together; others are not} -body {
	set rows [::scidb::db::findPlayers $::scidb::test::plink::Pgn Normal uniquerare 11]
	set annas [lmap r $rows { if {[lindex $r 4] ne "fide:999000605"} continue; lindex $r 1 }]
	set index [lindex [lsearch -inline -index 1 $rows {Uniquerare, Anna}] 0]
	list [lsort $annas] [lsort [::scidb::db::playerSpellings $::scidb::test::plink::Pgn Normal $index]]
} -result {{{Uniquerare, Anna} {Uniquerare, Anna Petrovna}} {{Uniquerare, Anna} {Uniquerare, Anna Petrovna}}}

tcltest::test plink-search {a search for a player takes every spelling; a different person stays apart} -body {
	set c [dict get [::application::assistant::CheckArgs search_games {player {Uniquerare, Anna}}] criteria]
	lassign [::application::assistant::BuildQuery $::scidb::test::plink::Pgn Normal $c] query summary
	set view [::scidb::view::new $::scidb::test::plink::Pgn Normal unused unused unused unused master slave]
	::scidb::view::search $::scidb::test::plink::Pgn Normal $view null none $query
	set count [::scidb::view::count games $::scidb::test::plink::Pgn Normal $view]
	::scidb::view::close $::scidb::test::plink::Pgn Normal $view
	list $count $summary [lindex [::application::assistant::ResolvePlayer $::scidb::test::plink::Pgn Normal {Linkalpha, Vladimir3}] 1]
} -result {2 {games of Uniquerare, Anna (also as Uniquerare, Anna Petrovna)} {Linkalpha, Vladimir3}}

tcltest::test plink-spelling-candidates {other spellings: same surname, agreeing initials and rating} -body {
	lmap row [::scidb::db::spellingCandidates $::scidb::test::plink::Pgn Normal] {
		lassign $row index name elo cands
		list $name $elo [lsort [lmap c $cands { lindex $c 1 }]]
	}
} -result {{{Translit, Mihail} 2610 {{Translit, Maxim} {Translit, Mikhail}}}}

tcltest::test plink-spelling-check {a name is linked when exactly one entry reaches the threshold, after confirmation} -setup {
	::scidb::db::linkPlayers $::scidb::test::plink::Pgn Normal
	rename ::ai::systemone::evaluateAsync ::scidb::test::plink::evaluateAsync
	proc ::ai::systemone::evaluateAsync {state questions script} {
		set answers {}
		dict for {id q} $questions {
			set p [expr {[string match {*"Translit, Mikhail"*} [dict get $q instructions]] ? 0.96 : 0.2}]
			dict set answers $id [dict create type noul noul $p]
		}
		after 0 [list {*}$script [list ok 1 answers $answers]]
	}
} -body {
	set ::scidb::test::plink::result {}
	::playerdata::spellingCheck $::scidb::test::plink::Pgn -done {set ::scidb::test::plink::result}
	vwait ::scidb::test::plink::result
	set props [dict get $::scidb::test::plink::result proposals]
	set before [dict get [::scidb::test::plink::links] {Translit, Mihail}]
	set n [::playerdata::applySpellings $::scidb::test::plink::Pgn $props]
	list [lmap p $props { lrange $p 2 4 }] $before $n [dict get [::scidb::test::plink::links] {Translit, Mihail}] \
		[::playerdata::applySpellings $::scidb::test::plink::Pgn $props]
} -cleanup {
	rename ::ai::systemone::evaluateAsync {}
	rename ::scidb::test::plink::evaluateAsync ::ai::systemone::evaluateAsync
} -result {{{{Translit, Mihail} 999000606 {Translit, Mikhail}}} - 1 999000606 0}

catch { ::scidb::db::close $::scidb::test::plink::Pgn }
catch { file delete -force $::scidb::test::plink::Dir }
tcltest::cleanupTests
