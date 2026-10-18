# ======================================================================
# Scidb App Test Suite - name fixes (step 5 of the player data plan):
# propose canonical names from linked rating-list entries, preview with
# checkboxes, apply on a copy of a database, undo.
# ======================================================================
# A player linked to an entry of the rating lists has that entry's
# spelling as its canonical name. Where the database spells it
# differently, the fix is proposed and applied only on confirmation.
# Renaming touches no game -- the games keep pointing at their player
# -- and is written only when the database is saved.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::nfix {}
set ::scidb::test::nfix::Dir [file join [file dirname [file normalize [info script]]] tmp-app nfix-[pid]]
file mkdir $::scidb::test::nfix::Dir
set ::scidb::test::nfix::Pgn [file join $::scidb::test::nfix::Dir fixes.pgn]

# ----------------------------------------------------------------------
# Setup: a FIDE list, a database with misspelled names, link them
# ----------------------------------------------------------------------

proc ::scidb::test::nfix::nop {args} { return 0 }

proc ::scidb::test::nfix::fideHeader {} {
	return "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
}

proc ::scidb::test::nfix::fideRow {id name fed sex std born} {
	format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" \
		$id $name $fed $sex "" "" "" "" $std 0 10 0 0 10 0 0 10 $born ""
}

# Create the rating list
set chan [open [file join $::scidb::test::nfix::Dir fide-nfix.txt] w]
puts $chan [::scidb::test::nfix::fideHeader]
puts $chan [::scidb::test::nfix::fideRow 999400001 {Correctname, Alpha} RUS M 2600 1980]
puts $chan [::scidb::test::nfix::fideRow 999400002 {Correctname, Beta} ENG F 2300 1990]
puts $chan [::scidb::test::nfix::fideRow 999400003 {Alreadyok, Gamma} GER M 2400 1975]
close $chan

::scidb::app::load fide [file join $::scidb::test::nfix::Dir fide-nfix.txt]
::scidb::app::load done

# Create a database with names that differ from the rating list
set chan [open $::scidb::test::nfix::Pgn w]
set n 0
foreach {white elo} {
	{Correctname, A} 2590
	{Correctname, Alph} 2600
	{Wrongspell, Beta} 2290
	{Alreadyok, Gamma} 2400
} {
	puts $chan "\[Event \"N\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
	puts $chan "\[White \"$white\"\]\n\[Black \"Opponent, Plain\"\]\n\[Result \"1-0\"\]"
	if {$elo} { puts $chan "\[WhiteElo \"$elo\"\]" }
	puts $chan "\n1. e4 e5 1-0\n"
}
close $chan

::scidb::db::open $::scidb::test::nfix::Pgn ::scidb::test::nfix::nop {} ::scidb::test::nfix::nop {}

# Link the players first (required for name proposals)
::scidb::db::linkPlayers $::scidb::test::nfix::Pgn Normal


# ----------------------------------------------------------------------
# Test: name proposals are generated correctly
# ----------------------------------------------------------------------

tcltest::test nfix-proposals {proposals are generated for linked names that differ} -body {
	set rows [::playerdata::NameProposals $::scidb::test::nfix::Pgn]

	# Collect old->new pairs
	set pairs {}
	foreach row $rows {
		lassign $row variant index old new games source tick
		lappend pairs [list $old $new $tick]
	}

	# Sort for stable comparison
	set pairs [lsort $pairs]

	# At minimum, "Correctname, A" should propose "Correctname, Alpha" (linked,
	# same surname, ticked). Other spellings may or may not link depending on
	# the algorithm's confidence.
	set foundA [lsearch -index 0 $pairs {Correctname, A}]
	set foundOk [lsearch -index 0 $pairs {Alreadyok, Gamma}]

	list [expr {$foundA >= 0 ? 1 : 0}] [expr {$foundOk < 0 ? 1 : 0}] [llength $pairs]
} -result {1 1 1}


# ----------------------------------------------------------------------
# Test: IsCanonicalName validation
# ----------------------------------------------------------------------

tcltest::test nfix-canonical-name {IsCanonicalName accepts valid names and rejects placeholders} -body {
	list \
		[::playerdata::IsCanonicalName {Carlsen, Magnus}] \
		[::playerdata::IsCanonicalName {Short, N}] \
		[::playerdata::IsCanonicalName {Unknown, Player}] \
		[::playerdata::IsCanonicalName {N, N}] \
		[::playerdata::IsCanonicalName {-, -}] \
		[::playerdata::IsCanonicalName {NoComma}] \
		[::playerdata::IsCanonicalName {A, B}]
} -result {1 0 0 0 0 0 0}


# ----------------------------------------------------------------------
# Test: FormatSource produces readable labels
# ----------------------------------------------------------------------

tcltest::test nfix-format-source {identity strings become readable labels} -body {
	list \
		[::playerdata::FormatSource {fide:1503014}] \
		[::playerdata::FormatSource {dsb:10614-1081}] \
		[::playerdata::FormatSource {ecf:100011B}] \
		[::playerdata::FormatSource {iccf:241018}]
} -result {{FIDE 1503014} {DWZ 10614-1081} {ECF 100011B} {ICCF 241018}}


# ----------------------------------------------------------------------
# Test: renamePlayers C++ command
# ----------------------------------------------------------------------

tcltest::test nfix-rename-cmd {renamePlayers renames and reports skipped} -setup {
	# Work on a copy so other tests are not affected
	set copy [file join $::scidb::test::nfix::Dir fixes-copy.pgn]
	file copy -force $::scidb::test::nfix::Pgn $copy
	::scidb::db::open $copy ::scidb::test::nfix::nop {} ::scidb::test::nfix::nop {}
	::scidb::db::linkPlayers $copy Normal
} -body {
	# Find the index of "Correctname, A" in the copy
	set links [::scidb::db::playerLinks $copy Normal]
	set idx -1
	set i 0
	foreach link $links {
		if {[lindex $link 0] eq {Correctname, A}} { set idx $i; break }
		incr i
	}
	if {$idx < 0} { return "not-found" }

	# Rename it
	set result [::scidb::db::renamePlayers $copy Normal [list $idx {Correctname, Alpha}]]

	# Check the new name is there
	set afterLinks [::scidb::db::playerLinks $copy Normal]
	set newName [lindex [lsearch -inline -index 0 $afterLinks {Correctname, Alpha}] 0]

	list [dict get $result renamed] $newName
} -cleanup {
	catch { ::scidb::db::close $copy }
	file delete -force $copy
} -result {1 {Correctname, Alpha}}


tcltest::test nfix-rename-skip-duplicate {renamePlayers skips when target name already exists} -setup {
	set copy [file join $::scidb::test::nfix::Dir fixes-dup.pgn]
	file copy -force $::scidb::test::nfix::Pgn $copy
	::scidb::db::open $copy ::scidb::test::nfix::nop {} ::scidb::test::nfix::nop {}
} -body {
	# Try to rename a player to "Opponent, Plain" which already exists
	set links [::scidb::db::playerLinks $copy Normal]
	set idx -1
	set i 0
	foreach link $links {
		if {[lindex $link 0] eq {Alreadyok, Gamma}} { set idx $i; break }
		incr i
	}
	if {$idx < 0} { return "not-found" }

	set result [::scidb::db::renamePlayers $copy Normal [list $idx {Opponent, Plain}]]

	list [dict get $result renamed] [llength [dict get $result skipped]] \
		[lindex [lindex [dict get $result skipped] 0] 2]
} -cleanup {
	catch { ::scidb::db::close $copy }
	file delete -force $copy
} -result {0 1 {the database has a player of that name}}


# ----------------------------------------------------------------------
# Test: Folded and Surname helpers
# ----------------------------------------------------------------------

tcltest::test nfix-folded {German diacritics are folded correctly} -body {
	list \
		[::playerdata::Folded {Müller}] \
		[::playerdata::Folded {Schröder}] \
		[::playerdata::Folded {Weiß}] \
		[::playerdata::Folded {Café}]
} -result {mueller schroeder weiss cafe}


tcltest::test nfix-surname {surname extraction and folding} -body {
	list \
		[::playerdata::Surname {Müller, Hans}] \
		[::playerdata::Surname {de la Villa, John}]
} -result {mueller {de la villa}}


# ----------------------------------------------------------------------
# Test: revert (undo) works
# ----------------------------------------------------------------------

tcltest::test nfix-revert {undo restores the original names} -setup {
	set copy [file join $::scidb::test::nfix::Dir fixes-undo.pgn]
	file copy -force $::scidb::test::nfix::Pgn $copy
	::scidb::db::open $copy ::scidb::test::nfix::nop {} ::scidb::test::nfix::nop {}
	::scidb::db::linkPlayers $copy Normal

	# Record original names
	set beforeLinks [::scidb::db::playerLinks $copy Normal]
	set origNames [lmap l $beforeLinks { if {[lindex $l 0] eq "Opponent, Plain"} continue; lindex $l 0 }]
} -body {
	# Get proposals and apply all
	set ::playerdata::NameFix(base) $copy
	set rows [::playerdata::NameProposals $copy]
	set ::playerdata::NameFix(rows) $rows
	for {set i 0} {$i < [llength $rows]} {incr i} {
		set ::playerdata::NameFix(tick,$i) [lindex [lindex $rows $i] 6]
	}

	# Apply (need a dummy parent window - use empty string, dialog will fail silently)
	# Instead, apply directly via the C++ command
	set byVariant {}
	set undo {}
	set i 0
	foreach row $rows {
		lassign $row variant index old new games source tick
		if {$::playerdata::NameFix(tick,$i)} {
			dict lappend byVariant $variant $index $new
			lappend undo [list $variant $new $old]
		}
		incr i
	}

	set renamed 0
	foreach variant [dict keys $byVariant] {
		set r [::scidb::db::renamePlayers $copy $variant [dict get $byVariant $variant]]
		incr renamed [dict get $r renamed]
	}

	# Now undo: look up the new names' indices and rename back
	set afterLinks [::scidb::db::playerLinks $copy Normal]
	set undos 0
	foreach item $undo {
		lassign $item variant new old
		set j 0
		foreach link $afterLinks {
			if {[lindex $link 0] eq $new} {
				set r [::scidb::db::renamePlayers $copy $variant [list $j $old]]
				incr undos [dict get $r renamed]
				break
			}
			incr j
		}
	}

	# Check names are back
	set finalLinks [::scidb::db::playerLinks $copy Normal]
	set finalNames [lmap l $finalLinks { if {[lindex $l 0] eq "Opponent, Plain"} continue; lindex $l 0 }]

	# The key check: names are restored to their original values
	list [expr {$renamed > 0 ? 1 : 0}] [expr {$undos > 0 ? 1 : 0}] \
		[expr {[lsort $finalNames] eq [lsort $origNames] ? 1 : 0}]
} -cleanup {
	catch { ::scidb::db::close $copy }
	file delete -force $copy
	unset -nocomplain ::playerdata::NameFix
} -result {1 1 1}


# ----------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------

catch { ::scidb::db::close $::scidb::test::nfix::Pgn }
catch { file delete -force $::scidb::test::nfix::Dir }
rename ::scidb::test::nfix::nop {}

tcltest::cleanupTests
