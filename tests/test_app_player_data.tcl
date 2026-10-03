# ======================================================================
# Scidb App Test Suite - the player data from FIDE (tcl/player-data.tcl,
# Player::parseFideFoaRating, ::scidb::app::filterFideList)
# ======================================================================
# FIDE's current combined list (players_list_foa.txt) is read by its header,
# players new since the shipped list of 2012 are added, FIDE's spelling and
# federation win, and the update filters, installs and loads it. The rows
# are invented players in FIDE's exact layout; nothing is downloaded.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5
namespace eval ::scidb::test::pdata {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app pdata-[pid]]
	variable Header "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
	variable Saved {}
}
proc ::scidb::test::pdata::nop {args} { return 0 }
# One row in FIDE's columns.
proc ::scidb::test::pdata::row {id name fed sex tit wtit std rapid blitz born flag} {
	format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
		$id $name $fed $sex $tit $wtit "" "" $std 0 10 $rapid 0 10 $blitz 0 10 $born $flag
}
proc ::scidb::test::pdata::foaList {file rows} {
	variable Header
	set chan [open $file w]
	fconfigure $chan -translation crlf
	puts $chan $Header
	foreach r $rows { puts $chan [row {*}$r] }
	close $chan
	return $file
}
# The dictionary's view of <names> through a PGN that names them.
proc ::scidb::test::pdata::info {names} {
	variable Dir
	set pgn [file join $Dir players.pgn]
	set fh [open $pgn w]
	set n 0
	foreach {w b} [concat $names [expr {[llength $names] % 2 ? {Nobody, X} : {}}]] {
		puts $fh "\[Event \"P\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"[incr n]\"\]\n\[White \"$w\"\]\n\[Black \"$b\"\]\n\[Result \"*\"\]\n\n1. e4 *\n"
	}
	close $fh
	::scidb::db::open $pgn nop {} nop {}
	set out {}
	set i 0
	foreach name $names {
		set info [::scidb::db::playerInfo $pgn Normal [expr {$i / 2}] [expr {$i % 2 ? "black" : "white"}]]
		lappend out [list [lindex $info 0] [lindex $info 1] [lindex $info 7] [lindex $info 8] [lindex $info 11] [lindex [lindex $info 4] 1]]
		incr i
	}
	::scidb::db::close $pgn
	return $out
}
proc ::scidb::test::pdata::saveUser {} {
	variable Saved
	set Saved {}
	foreach f [list [::playerdata::fideFile] [file join [::playerdata::Dir] fide-players.info]] {
		if {[file exists $f]} { file rename -force $f $f.pdata-saved; lappend Saved $f }
	}
}
proc ::scidb::test::pdata::restoreUser {} {
	variable Saved
	catch { file delete [::playerdata::fideFile] [file join [::playerdata::Dir] fide-players.info] }
	foreach f $Saved { file rename -force $f.pdata-saved $f }
	set Saved {}
}
file mkdir $::scidb::test::pdata::Dir

tcltest::test pdata-parse {the current layout: new players added, below 1800 only when titled} -body {
	set file [::scidb::test::pdata::foaList [file join $::scidb::test::pdata::Dir a.txt] {
		{999000101 {Newcomer, Testy} NED M GM {} 2612 2590 2601 2001 {}}
		{999000102 {Clubwoman, Tessa} BEL F {} WCM 1700 0 0 1999 w}
		{999000103 {Lowrated, Tim} LUX M {} {} 1500 1600 1550 1980 {}}
		{999000104 {Rapidonly, Ruth} SUI F {} {} 0 1950 0 1995 wi}
	}]
	::scidb::app::load fide $file
	::scidb::app::load done
	::scidb::test::pdata::info {{Newcomer, Testy} {Clubwoman, Tessa} {Lowrated, Tim} {Rapidonly, Ruth}}
} -result {{{Newcomer, Testy} 999000101 NED GM 2001 2612} {{Clubwoman, Tessa} 999000102 BEL WCM 1999 1700} {{Lowrated, Tim} {} {} {} {} 0} {{Rapidonly, Ruth} 999000104 SUI {} 1995 0}}

tcltest::test pdata-current {FIDE's spelling and federation replace older ones; the old spelling still finds the player} -body {
	::scidb::app::load fide [::scidb::test::pdata::foaList [file join $::scidb::test::pdata::Dir b1.txt] {
		{999000201 {Oldspell, Testa} GER F GM {} 2450 0 0 1990 w}
	}]
	::scidb::app::load fide [::scidb::test::pdata::foaList [file join $::scidb::test::pdata::Dir b2.txt] {
		{999000201 {Newspell, Testa} AUT F GM {} 2470 0 0 1990 w}
	}]
	::scidb::app::load done
	::scidb::test::pdata::info {{Oldspell, Testa} {Newspell, Testa}}
} -result {{{Newspell, Testa} 999000201 AUT GM 1990 2470} {{Newspell, Testa} 999000201 AUT GM 1990 2470}}

tcltest::test pdata-filter {the filter keeps the header and the rated or titled players} -body {
	set in [::scidb::test::pdata::foaList [file join $::scidb::test::pdata::Dir c.txt] {
		{999000301 {Keep, Rated} NOR M {} {} 1900 0 0 1990 {}}
		{999000302 {Drop, Low} NOR M {} {} 1200 1300 0 1990 {}}
		{999000303 {Keep, Titled} NOR M FM {} 0 0 0 1990 i}
		{999000304 {Keep, Blitz} NOR M {} {} 0 0 1850 1990 {}}
	}]
	set out [file join $::scidb::test::pdata::Dir c-out.txt]
	set counts [::scidb::app::filterFideList $in $out]
	set chan [open $out]; set lines [split [string trim [read $chan]] \n]; close $chan
	list $counts [llength $lines] [string match "ID Number*SRtng*" [lindex $lines 0]] \
		[lmap l [lrange $lines 1 end] { string trim [string range $l 15 30] }] \
		[catch { ::scidb::app::filterFideList [file join $::scidb::test::pdata::Dir b1.txt].missing $out } e] \
		[catch { ::scidb::app::filterFideList [info script] $out } e2] [string match "*not FIDE*" $e2]
} -result {{4 3} 4 1 {{Keep, Rated} {Keep, Titled} {Keep, Blitz}} 1 1 1}

tcltest::test pdata-update {an update downloads, filters, installs and loads; a failure is reported} -setup {
	::scidb::test::pdata::saveUser
	rename ::application::download::Get ::scidb::test::pdata::RealGet
	set ::scidb::test::pdata::List [::scidb::test::pdata::foaList [file join $::scidb::test::pdata::Dir d.txt] {
		{999000401 {Updated, Uma} DEN F IM WGM 2401 0 0 1993 w}
		{999000402 {Dropped, Dan} DEN M {} {} 1000 0 0 1993 {}}
	}]
	proc ::application::download::Get {url done} {
		set ::scidb::test::pdata::Asked $url
		set chan [::open $::scidb::test::pdata::List rb]; set data [::read $chan]; ::close $chan
		after 0 [list {*}$done [list ok 1 data $data code 200]]
	}
} -body {
	::playerdata::updateFide . -confirm 0 -done {set ::scidb::test::pdata::Done}
	set timer [after 20000 {set ::scidb::test::pdata::Done timeout}]
	vwait ::scidb::test::pdata::Done
	after cancel $timer
	set ok $::scidb::test::pdata::Done
	set installed [file exists [::playerdata::fideFile]]
	set info [::playerdata::fideInfo]
	proc ::application::download::Get {url done} { after 0 [list {*}$done [list ok 0 error {host unreachable} code 0]] }
	::playerdata::updateFide . -confirm 0 -done {set ::scidb::test::pdata::Done}
	vwait ::scidb::test::pdata::Done
	list $::scidb::test::pdata::Asked $ok $installed [dict get $info players] \
		[lindex [::scidb::test::pdata::info {{Updated, Uma}}] 0] $::scidb::test::pdata::Done
} -cleanup {
	rename ::application::download::Get {}
	rename ::scidb::test::pdata::RealGet ::application::download::Get
	::scidb::test::pdata::restoreUser
} -result {https://ratings.fide.com/download/players_list.zip {ok 1 players 1 read 2} 1 1 {{Updated, Uma} 999000401 DEN {IM WGM} 1993 2401} {ok 0 error {host unreachable}}}

tcltest::test pdata-tool {the assistant offers the update and asks first} -body {
	set entry [dict get $::application::assistant::Actions update_player_data]
	list [lindex $entry 0] [::application::assistant::CheckArgs update_player_data {}]
} -result {1 {}}

catch { file delete -force $::scidb::test::pdata::Dir }
tcltest::cleanupTests
