# The game row menu's sort submenus name the clicked column.
package require tcltest 2.5

tcltest::test c3-sort-rows-name-column {Sort Ascending > Date, not > Ascending} -body {
	set object [dict create base b variant Normal index 1 column date \
		sortable 1 path .ctxlist view 0]
	set m .c3sorttest
	catch { destroy $m }
	menu $m -tearoff 0
	::context::Build C3 $m $object
	set out {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		if {[$m type $i] ne "cascade"} { continue }
		set label [string trim [$m entrycget $i -label]]
		if {![string match Sort* $label]} { continue }
		lappend out [string trim [[$m entrycget $i -menu] entrycget 0 -label]]
	}
	destroy $m
	set out
} -result {Date Date Date}

tcltest::cleanupTests
