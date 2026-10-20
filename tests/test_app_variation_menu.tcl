package require tcltest 2.5

namespace eval ::variationMenuTest {
	variable selected 0
	variable timer {}
	variable timedOut 0
}

proc ::variationMenuTest::setup {suggested} {
	update
	catch { destroy .tipoftheday }
	::menu::gameNew .application
	set slot [::scidb::game::current]
	::scidb::game::import $slot {[Event "Variation menu"]
[Site "?"]
[Date "2026.10.15"]
[Round "?"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 2. Nf3 *} {} {} -encoding utf-8 -variation 0
	::scidb::game::go start
	::application::board::goto 1
	::application::switchTab board
	set ::board::hilite(show-suggested) $suggested
	set ::move::Options(askToReplaceMoves) 1
	set ::move::Options(addVarWithoutAsking) 0
	::move::reset
	::move::enable
	update
}

proc ::variationMenuTest::point {square} {
	set b $::application::board::board
	lassign [$b.c coords square:$square] x y
	set size [set ::board::diagram::${b}::Board(size)]
	list [expr {int([winfo rootx $b.c] + $x + $size/2)}] \
		[expr {int([winfo rooty $b.c] + $y + $size/2)}]
}

proc ::variationMenuTest::choose {} {
	variable timer
	variable selected
	set m $::application::board::board.popup_confirm
	if {[winfo exists $m] && [winfo ismapped $m]} {
		for {set i 0} {$i <= [$m index end]} {incr i} {
			if {[$m type $i] eq "command" && [string trim [$m entrycget $i -label]] eq $::move::mc::Action(variation)} {
				set selected 1
				set y [expr {[$m yposition $i] + 4}]
				event generate $m <Motion> -warp 1 -x 8 -y $y
				event generate $m <ButtonPress-1> -x 8 -y $y
				event generate $m <ButtonRelease-1> -x 8 -y $y
				return
			}
		}
	}
	set timer [after 20 [namespace code choose]]
}

proc ::variationMenuTest::play {mode} {
	variable timer
	variable selected 0
	variable timedOut 0
	set b $::application::board::board
	set from [::board::diagram::square b7]
	set to [::board::diagram::square b5]
	lassign [point $from] x y
	set timer [after 20 [namespace code choose]]
	set watchdog [after 2000 {
		set ::variationMenuTest::timedOut 1
		set ::move::_wait 0
	}]
	event generate $b.c <Motion> -warp 1 -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
	update
	event generate $b.c <ButtonPress-1> -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
	if {$mode eq "click"} {
		event generate $b.c <ButtonRelease-1> -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
	}
	if {$mode ne "suggested"} {
		lassign [point $to] x y
		event generate $b.c <Motion> -warp 1 -state [expr {$mode eq "drag" ? 256 : 0}] -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
		if {$mode eq "click"} {
			event generate $b.c <ButtonPress-1> -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
		}
	} else {
		# A click on a piece only selects it; the suggested move is played by
		# clicking its target square (move.tcl pressSquare contract).
		lassign [point [::board::diagram::square b6]] x y
	}
	event generate $b.c <ButtonRelease-1> -x [expr {$x - [winfo rootx $b.c]}] -y [expr {$y - [winfo rooty $b.c]}]
	after cancel $timer
	after cancel $watchdog
	if {$timedOut} { error "board/menu interaction timed out" }
	update
	set move [::scidb::game::query move]
	::scidb::game::go start
	::application::board::goto 1
	list $selected $move [::scidb::game::next moves -ascii]
}

set ::variationMenuTest::savedHilite $::board::hilite(show-suggested)
set ::variationMenuTest::savedOptions [array get ::move::Options]
foreach {mode suggested result} {
	click 0 {1 b5 {e5 b5}}
	drag 1 {1 b5 {e5 b5}}
	suggested 1 {1 b6 {e5 b6}}
} {
	tcltest::test variation-menu-$mode {board action and popup command create a variation} -setup {
		::variationMenuTest::setup $suggested
	} -body {
		::variationMenuTest::play $mode
	} -cleanup {
		catch { ::tk::MenuUnpost $::application::board::board.popup_confirm }
		::move::reset
		update
	} -result $result
}
set ::board::hilite(show-suggested) $::variationMenuTest::savedHilite
array set ::move::Options $::variationMenuTest::savedOptions

tcltest::cleanupTests
