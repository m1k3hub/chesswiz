# ======================================================================
# Scidb App Test Suite - national rating lists (step 4 of the player data
# plan): DWZ, ECF and ICCF parser/converter, installed-list round trip,
# linking gain from national-only entries.
# ======================================================================
# The federations' downloads are converted into a list of Chesswiz' own
# format (::scidb::app::filterRatingList), which startup reads instead
# of the shipped list (::scidb::app::load installed). The tests use
# hand-made sample files that mimic the current download formats; no
# network traffic.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::rlists {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app rlists-[pid]]
	file mkdir $Dir
}

# ----------------------------------------------------------------------
# Helper: read a whole file (global scope for test bodies)
# ----------------------------------------------------------------------

proc readFile {path} {
	set chan [open $path]
	set text [read $chan]
	close $chan
	return $text
}

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

# A FIDE-format header for a small list that ::scidb::app::load fide reads.
proc ::scidb::test::rlists::fideHeader {} {
	return "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
}

proc ::scidb::test::rlists::fideRow {id name fed sex std born} {
	format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
		$id $name $fed $sex "" "" "" "" $std 0 10 0 0 10 0 0 10 $born ""
}

# ----------------------------------------------------------------------
# Test: DWZ converter (current CSV format, cp1252, quoted fields)
# ----------------------------------------------------------------------

tcltest::test rlists-dwz-convert {DWZ CSV download is converted to installed format} -setup {
	set dwzCsv [file join $::scidb::test::rlists::Dir dwz-test.csv]
	set out [file join $::scidb::test::rlists::Dir dwz-out.txt]

	# A small DSB CSV in the current format (cp1252, quoted name field)
	set chan [open $dwzCsv wb]
	puts -nonewline $chan [encoding convertto cp1252 \
		"ID,ZPS,Mitgliedsnummer,Status,\"Name,Vorname\",Geschlecht,Spielberechtigung,Geburtsjahr,\"Letzte Auswertung\",DWZ,Index,FIDE-Elozahl,FIDE-Titel,FIDE-ID,FIDE-Land,Vorname,Nachname,FIDE-Frauentitel,FIDE-Elozahl-Schnellschach,FIDE-Elozahl-Blitz\n"]
	puts -nonewline $chan [encoding convertto cp1252 \
		"NU4073762,10614,1081,P,\"Müller,Hans\",M,,1990,202517,2400,12,2500,GM,1503014,NOR,Hans,Müller,,,\n"]
	puts -nonewline $chan [encoding convertto cp1252 \
		"NU4073763,10614,1082,A,\"Schmidt,Peter\",M,,1985,202517,1900,8,,,,Peter,Schmidt,,,\n"]
	puts -nonewline $chan [encoding convertto cp1252 \
		"NU4073764,10614,1083,A,\"Weiß,Anna\",W,,2000,202517,1700,5,,,,Anna,Weiß,,,\n"]
	close $chan

	set result [::scidb::app::filterRatingList dwz $dwzCsv $out 1800]
} -body {
	lassign $result read kept

	# read 3 rows, kept 2 (Müller has GM+FIDE, Schmidt has DWZ>=1800; Weiß below threshold)
	list $read $kept \
		[expr {[file readable $out] ? "yes" : "no"}] \
		[string match "#chesswiz-rating-list*" [readFile $out]]
} -cleanup {
	file delete -force $dwzCsv $out
} -result {3 2 yes 1}


tcltest::test rlists-dwz-roundtrip {converted DWZ list is read by the installed parser} -setup {
	set dwzCsv [file join $::scidb::test::rlists::Dir dwz-rt.csv]
	set out [file join $::scidb::test::rlists::Dir dwz-rt.txt]

	set chan [open $dwzCsv wb]
	puts -nonewline $chan [encoding convertto cp1252 \
		"ID,ZPS,Mitgliedsnummer,Status,\"Name,Vorname\",Geschlecht,Spielberechtigung,Geburtsjahr,\"Letzte Auswertung\",DWZ,Index,FIDE-Elozahl,FIDE-Titel,FIDE-ID,FIDE-Land,Vorname,Nachname,FIDE-Frauentitel,FIDE-Elozahl-Schnellschach,FIDE-Elozahl-Blitz\n"]
	puts -nonewline $chan [encoding convertto cp1252 \
		"NU4073762,10614,1081,P,\"Testplayer,Hans\",M,,1990,202517,2400,12,2500,,999111001,GER,Hans,Testplayer,,,\n"]
	close $chan

	::scidb::app::filterRatingList dwz $dwzCsv $out 1800

	# Create a small database with this player
	set pgn [file join $::scidb::test::rlists::Dir dwz-rt.pgn]
	set c [open $pgn w]
	puts $c "\[Event \"T\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]"
	puts $c "\[White \"Testplayer, Hans\"\]\n\[Black \"Opponent, Plain\"\]\n\[Result \"1-0\"\]"
	puts $c "\[WhiteElo \"2400\"\]\n\n1. e4 e5 1-0\n"
	close $c
	proc ::scidb::test::rlists::nop3 {args} { return 0 }
	::scidb::db::open $pgn ::scidb::test::rlists::nop3 {} ::scidb::test::rlists::nop3 {}
} -body {
	# Load the installed list and link
	::scidb::app::load installed $out
	::scidb::app::load done
	set result [::scidb::db::linkPlayers $pgn Normal]

	# Check the player got linked (has a FIDE ID now)
	set links [::scidb::db::playerLinks $pgn Normal]
	set tp [lsearch -inline -index 0 $links {Testplayer, Hans}]
	list [dict get $result linked] [lindex $tp 2] [lindex $tp 3]
} -cleanup {
	catch { ::scidb::db::close $pgn }
	file delete -force $dwzCsv $out [file join $::scidb::test::rlists::Dir dwz-rt.pgn]
	rename ::scidb::test::rlists::nop3 {}
} -result {1 1 999111001}


# ----------------------------------------------------------------------
# Test: ECF converter (current CSV format, UTF-8, header-based columns)
# ----------------------------------------------------------------------

tcltest::test rlists-ecf-convert {ECF CSV download is converted to installed format} -setup {
	set ecfCsv [file join $::scidb::test::rlists::Dir ecf-test.csv]
	set out [file join $::scidb::test::rlists::Dir ecf-out.txt]

	set chan [open $ecfCsv w]
	puts $chan "ECF_code,full_name,member_no,FIDE_no,gender,nation,original_standard,standard_original_category,revised_standard,standard_revised_category,club_code,club_name,title"
	puts $chan "280660F,\"Arthurton, Robert J\",,400111,M,ENG,1850,C,1860,C,CHS001,Chess Club,"
	puts $chan "100011B,\"Bloggs, John\",,0,M,,1500,D,1520,D,,,,"
	puts $chan "300222C,\"Smith, Jane\",,500222,F,WLS,2100,B,2150,B,FUSA,Foreign Club,WGM"
	close $chan

	set result [::scidb::app::filterRatingList ecf $ecfCsv $out 1600]
} -body {
	lassign $result read kept

	# Arthurton (1860 >= 1600), Bloggs (1520 < 1600, no FIDE/title -> dropped), Smith (2150 + WGM)
	list $read $kept \
		[expr {[file readable $out] ? "yes" : "no"}] \
		[string match "#chesswiz-rating-list*kind=ecf*" [readFile $out]]
} -cleanup {
	file delete -force $ecfCsv $out
} -result {3 2 yes 1}


tcltest::test rlists-ecf-federation-fallback {ECF foreign club code sets federation in the installed list} -setup {
	set ecfCsv [file join $::scidb::test::rlists::Dir ecf-fed.csv]
	set out [file join $::scidb::test::rlists::Dir ecf-fed.txt]

	set chan [open $ecfCsv w]
	puts $chan "ECF_code,full_name,member_no,FIDE_no,gender,nation,original_standard,revised_standard,club_code,club_name,title"
	puts $chan "400333D,\"Foreign, Player\",,,M,,1900,1900,FUSA,US Club,"
	close $chan

	::scidb::app::filterRatingList ecf $ecfCsv $out 1600
} -body {
	# Verify the installed list has USA as the federation (from FUSA club code)
	set content [readFile $out]
	# The record line should contain |USA| in the federation field
	set lines [split $content "\n"]
	set recordLine [lindex $lines 2]
	# Format: id|fideID|sex|birthYear|rating|federation|titles|name
	set fields [split $recordLine "|"]
	lindex $fields 5
} -cleanup {
	file delete -force $ecfCsv $out
} -result {USA}


# ----------------------------------------------------------------------
# Test: ICCF converter (semicolon-separated, no header, shape detection)
# ----------------------------------------------------------------------

tcltest::test rlists-iccf-convert {ICCF CSV download is converted to installed format} -setup {
	set iccfCsv [file join $::scidb::test::rlists::Dir iccf-test.csv]
	set out [file join $::scidb::test::rlists::Dir iccf-out.txt]

	set chan [open $iccfCsv w]
	# With place column
	puts $chan "1;241018;ITA;GM;Riccio, Eros;437;2640;120;"
	puts $chan "2;300001;GER;;Mueller, Hans;100;1900;80;"
	# Without place column
	puts $chan "400002;BRA;SIM;Silva, Maria;200;2200;90;F"
	# Below threshold (should be dropped)
	puts $chan "3;500003;FRA;;Dupont, Pierre;50;1500;60;"
	close $chan

	set result [::scidb::app::filterRatingList iccf $iccfCsv $out 1800]
} -body {
	lassign $result read kept

	# Riccio (2640+GM), Mueller (1900>=1800), Silva (2200+SIM); Dupont dropped (1500<1800, no title)
	list $read $kept \
		[expr {[file readable $out] ? "yes" : "no"}] \
		[string match "#chesswiz-rating-list*kind=iccf*" [readFile $out]]
} -cleanup {
	file delete -force $iccfCsv $out
} -result {4 3 yes 1}


tcltest::test rlists-iccf-shape-detection {ICCF CSV without place column is recognized} -setup {
	set iccfCsv [file join $::scidb::test::rlists::Dir iccf-noplace.csv]
	set out [file join $::scidb::test::rlists::Dir iccf-noplace.txt]

	set chan [open $iccfCsv w]
	puts $chan "600001;ENG;IM;Jones, David;300;2350;100;M"
	close $chan

	set result [::scidb::app::filterRatingList iccf $iccfCsv $out 1800]
} -body {
	lassign $result read kept
	list $read $kept
} -cleanup {
	file delete -force $iccfCsv $out
} -result {1 1}


# ----------------------------------------------------------------------
# Test: wrong input is rejected
# ----------------------------------------------------------------------

tcltest::test rlists-wrong-input {converter rejects a file that is not the expected format} -setup {
	set bad [file join $::scidb::test::rlists::Dir bad.csv]
	set out [file join $::scidb::test::rlists::Dir bad-out.txt]

	set chan [open $bad w]
	puts $chan "This is not a rating list"
	puts $chan "Just some random text"
	close $chan
} -body {
	catch { ::scidb::app::filterRatingList dwz $bad $out 1800 } err
	set err
} -cleanup {
	file delete -force $bad $out
} -match glob -result {*not the dwz rating list*}


tcltest::test rlists-wrong-kind {unknown kind is rejected} -body {
	set bad [file join $::scidb::test::rlists::Dir dummy.csv]
	set out [file join $::scidb::test::rlists::Dir dummy-out.txt]
	set chan [open $bad w]; puts $chan "x"; close $chan
	catch { ::scidb::app::filterRatingList uscf $bad $out } err
	file delete -force $bad $out
	set err
} -match glob -result {*not the uscf rating list*}


# ----------------------------------------------------------------------
# Test: installed list header values
# ----------------------------------------------------------------------

tcltest::test rlists-header-values {installed list header carries kind, counts and source} -setup {
	set ecfCsv [file join $::scidb::test::rlists::Dir ecf-hdr.csv]
	set out [file join $::scidb::test::rlists::Dir ecf-hdr.txt]

	set chan [open $ecfCsv w]
	puts $chan "ECF_code,full_name,member_no,FIDE_no,gender,nation,original_standard,revised_standard,club_code,title"
	puts $chan "500444E,\"Header, Test\",,,M,ENG,2000,2000,,GM"
	close $chan

	::scidb::app::filterRatingList ecf $ecfCsv $out 1600
} -body {
	set lines [split [readFile $out] "\n"]
	set h0 [lindex $lines 0]
	set h1 [lindex $lines 1]

	list \
		[string match "#chesswiz-rating-list v1*" $h0] \
		[string match "*kind=ecf*" $h0] \
		[string match "*read=1*" $h0] \
		[string match "*kept=1*" $h0] \
		[string match "#source*" $h1]
} -cleanup {
	file delete -force $ecfCsv $out
} -result {1 1 1 1 1}


# ----------------------------------------------------------------------
# Test: linking gain from national-list evidence
# ----------------------------------------------------------------------

tcltest::test rlists-linking-gain {a national-list-only entry is found in the dictionary and linkable} -setup {
	# A FIDE list with one entry
	set fideList [file join $::scidb::test::rlists::Dir fide-lg.txt]
	set chan [open $fideList w]
	puts $chan [::scidb::test::rlists::fideHeader]
	puts $chan [::scidb::test::rlists::fideRow 999200001 {Nationalonly, Strong} GER M 2500 1985]
	close $chan
	::scidb::app::load fide $fideList

	# An installed DWZ list with the same player (different spelling) plus a
	# second player only the national list has
	set dwzOut [file join $::scidb::test::rlists::Dir dwz-lg.txt]
	set body "#chesswiz-rating-list v1 kind=dwz date=2026-01-01 read=2 kept=2\n#source test\n"
	append body "10614-2001|999200001|M|1985|2500|GER|GM|Nationalonly, Strong\n"
	append body "10614-2002|0|M|1990|2100|GER|-|Dwbonly, Player\n"
	set chan [open $dwzOut w]
	puts -nonewline $chan $body
	close $chan
	::scidb::app::load installed $dwzOut
	::scidb::app::load done

	# A database with a game by a player only the DWZ list has
	set pgn [file join $::scidb::test::rlists::Dir lg.pgn]
	set chan [open $pgn w]
	puts $chan "\[Event \"T\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]"
	puts $chan "\[White \"Dwbonly, Player\"\]\n\[Black \"Opponent, Plain\"\]\n\[Result \"1-0\"\]"
	puts $chan "\[WhiteElo \"2100\"\]\n\n1. e4 e5 1-0\n"
	close $chan

	proc ::scidb::test::rlists::nop {args} { return 0 }
	::scidb::db::open $pgn ::scidb::test::rlists::nop {} ::scidb::test::rlists::nop {}
} -body {
	# After loading the installed list, Dwbonly is already linked via the
	# dictionary (the entry was created when the installed list was loaded).
	# linkPlayers will find nothing new to link.
	set result [::scidb::db::linkPlayers $pgn Normal]
	set links [::scidb::db::playerLinks $pgn Normal]
	set dwb [lsearch -inline -index 0 $links {Dwbonly, Player}]

	# The key point: the player exists in the dictionary and is linked
	list [lindex $dwb 2] [lindex $dwb 3]
} -cleanup {
	catch { ::scidb::db::close $::scidb::test::rlists::Dir/lg.pgn }
	file delete -force $::scidb::test::rlists::Dir/lg.pgn \
		[file join $::scidb::test::rlists::Dir fide-lg.txt] \
		[file join $::scidb::test::rlists::Dir dwz-lg.txt]
	rename ::scidb::test::rlists::nop {}
} -result {1 0}


# ----------------------------------------------------------------------
# Test: identity and findPlayerByIdentity
# ----------------------------------------------------------------------

tcltest::test rlists-identity {spellingCandidates reports identity strings, not bare FIDE IDs} -setup {
	set fideList [file join $::scidb::test::rlists::Dir fide-id.txt]
	set chan [open $fideList w]
	puts $chan [::scidb::test::rlists::fideHeader]
	puts $chan [::scidb::test::rlists::fideRow 999300001 {Identitytest, Alpha} RUS M 2600 1980]
	close $chan
	::scidb::app::load fide $fideList
	::scidb::app::load done

	set pgn [file join $::scidb::test::rlists::Dir id.pgn]
	set chan [open $pgn w]
	puts $chan "\[Event \"T\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]"
	puts $chan "\[White \"Identitytest, A\"\]\n\[Black \"Opponent, Plain\"\]\n\[Result \"1-0\"\]"
	puts $chan "\[WhiteElo \"2590\"\]\n\n1. e4 e5 1-0\n"
	close $chan

	proc ::scidb::test::rlists::nop2 {args} { return 0 }
	::scidb::db::open $pgn ::scidb::test::rlists::nop2 {} ::scidb::test::rlists::nop2 {}
} -body {
	set cands [::scidb::db::spellingCandidates $pgn Normal]
	if {![llength $cands]} { return "no-candidates" }

	# Each candidate row: {index name elo {{identity name federation rating} ...}}
	set first [lindex $cands 0]
	set candList [lindex $first 3]
	set firstCand [lindex $candList 0]
	set identity [lindex $firstCand 0]

	# Should be "fide:999300001", not just "999300001"
	string match "fide:*" $identity
} -cleanup {
	catch { ::scidb::db::close $pgn }
	file delete -force $pgn [file join $::scidb::test::rlists::Dir fide-id.txt]
	rename ::scidb::test::rlists::nop2 {}
} -result {1}


# ----------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------

catch { file delete -force $::scidb::test::rlists::Dir }

tcltest::cleanupTests
