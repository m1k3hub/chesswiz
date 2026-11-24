# Board resize timing: cycle between 4 window sizes (cached sizes after the first round).
::application::switchTab board; update
set out {}
foreach round {1 2 3} {
	set t0 [clock microseconds]
	foreach g {1100x760 1500x900 1250x820 1700x980} {
		wm geometry .application $g
		update
		while {[llength [after info]] && [lsearch -glob [lmap a [after info] {lindex [after info $a] 0}] *RebuildBoard*] >= 0} { after 10; update }
		update
	}
	lappend out "round $round: [expr {([clock microseconds]-$t0)/4000}] ms/resize"
}
join $out "; "
