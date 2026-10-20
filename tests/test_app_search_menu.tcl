# The searches are reachable from the drop-down (Database > Search) and the
# database toolbar, not only from the database's Maintenance submenu; each
# entry is a registry action that opens its window. Decision 003: the
# drop-down no longer has a top-level Search cascade or an .mSearch widget.
package require tcltest 2.5

proc ::scidb::test::searchMenuTops {{w .}} {
	set r {}
	foreach c [winfo children $w] {
		if {[winfo toplevel $c] eq $c} { lappend r $c }
		lappend r {*}[::scidb::test::searchMenuTops $c]
	}
	return $r
}

tcltest::test search-menu {Database > Search entries are registry actions that open the searches} -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app search-menu]
	file mkdir $dir
	set src [file join $dir s.pgn]
	set fh [open $src w]
	for {set i 1} {$i <= 4} {incr i} { puts $fh "\[Event \"S\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n" }
	close $fh
	::scidb::db::open $src {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::scidb::db::switch $src Normal
} -body {
	catch { destroy .searchMenuTest }
	menu .searchMenuTest
	::menu::BuildDropdown .searchMenuTest
	set ids {
		menu.db.search.plain
		menu.db.search.advanced
		menu.db.search.material
		menu.db.search.rating
		menu.db.search.duplicates
		menu.db.search.query
	}
	set labels {}
	foreach id $ids {
		set rec [::action::get $id]
		lappend labels [dict get $rec label] normal
	}
	set opened {}
	foreach id $ids {
		set before [::scidb::test::searchMenuTops]
		set rc [catch {::action::invoke $id {}} err]
		update
		set new [lmap w [::scidb::test::searchMenuTops] {
			if {$w in $before || ![winfo ismapped $w]} continue
			set w
		}]
		lappend opened [list $rc [expr {[llength $new] > 0}]]
		foreach w $new { catch {destroy $w} }
	}
	list $labels $opened
} -cleanup {
	catch {destroy .searchMenuTest}
} -result {{Plain-Language… normal Advanced… normal Material… normal Rating… normal Duplicates… normal {Query Editor…} normal} {{0 1} {0 1} {0 1} {0 1} {0 1} {0 1}}}

tcltest::cleanupTests
