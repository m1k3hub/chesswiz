# A player's highest rating is never lower than the Elo recorded in that
# player's games: the shipped player dictionary is from 2013 and used to
# override newer, higher game ratings.
package require tcltest 2.5

tcltest::test player-highest-not-below-games {the player list never shows less than the games' Elo} -body {
	set b [file join $::scidb::dir::share sample "Sample games.sci"]
	if {![file exists $b]} { return "no sample database" }
	if {[catch {::scidb::view::count players $b Normal 0}]} {
		::scidb::db::load $b {apply {args {return 0}}} {} -readonly 1
	}
	# highest Elo per player name, from the game headers
	set best [dict create]
	set n [::scidb::db::count games $b Normal]
	for {set i 0} {$i < $n} {incr i} {
		set info [::scidb::db::get gameInfo $i -1 $b Normal]
		foreach {name elo} [list [lindex $info 1] [lindex $info 3] [lindex $info 10] [lindex $info 12]] {
			if {![string is integer -strict $elo] || $elo <= 0} { continue }
			if {![dict exists $best $name] || [dict get $best $name] < $elo} { dict set best $name $elo }
		}
	}
	set low {}
	set p [::scidb::view::count players $b Normal 0]
	for {set i 0} {$i < $p} {incr i} {
		set info [scidb::db::get playerInfo $i 0 $b Normal -ratings {Elo DWZ} -federation Country -usebase 0]
		set name [lindex $info 0]
		if {[lindex $info 4 2] ne "Elo" || ![dict exists $best $name]} { continue }
		set top [dict get $best $name]
		if {abs([lindex $info 4 0]) < $top} { lappend low $i }
		# latest from a stale dictionary: hundreds of points below the games
		set latest [expr {abs([lindex $info 4 1])}]
		if {$latest > 0 && $latest < $top - 300} { lappend low $i }
	}
	list [expr {[dict size $best] > 100}] [llength $low]
} -result {1 0}

tcltest::cleanupTests
