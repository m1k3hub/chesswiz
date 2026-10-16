# The searches are reachable from the Main Menu (Search) and the database toolbar,
# not only from the database's Maintenance submenu; each entry opens its window.
package require tcltest 2.5
tcltest::test search-menu {Main Menu has a Search cascade whose entries open the searches} -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app search-menu]
	file mkdir $dir
	set src [file join $dir s.pgn]
	set fh [open $src w]
	for {set i 1} {$i <= 4} {incr i} { puts $fh "\[Event \"S\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n" }
	close $fh
	::scidb::db::open $src {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::scidb::db::switch $src Normal
	set m .searchMenuTest; menu $m
} -body {
	::menu::build $m
	set labels {}
	for {set i 0} {$i <= [$m.mSearch index end]} {incr i} {
		if {[$m.mSearch type $i] eq "command"} { lappend labels [string trim [$m.mSearch entrycget $i -label]] [$m.mSearch entrycget $i -state] }
	}
	proc ::scidb::test::searchMenuTops {{w .}} { set r {}; foreach c [winfo children $w] { if {[winfo toplevel $c] eq $c} { lappend r $c }; lappend r {*}[::scidb::test::searchMenuTops $c] }; return $r }
	set opened {}
	foreach i {1 2 3 4} prefix {.advanced .material .rating .maintenance} {
		set before [::scidb::test::searchMenuTops]
		set rc [catch {$m.mSearch invoke $i} err]
		update
		set new [lmap w [::scidb::test::searchMenuTops] { if {$w in $before || ![winfo ismapped $w]} continue; set w }]
		lappend opened [list $rc [expr {[lsearch -glob $new $prefix*] >= 0}]]
		foreach w $new { catch {destroy $w} }
	}
	list $labels $opened
} -cleanup { catch {destroy .searchMenuTest} } -result {{{Plain-Language Search...} normal {Advanced Search...} normal {Search by Material...} normal {Search by Rating...} normal {Find Duplicates...} normal {CQL 6.2 Search...} normal {Discover Databases...} normal} {{0 1} {0 1} {0 1} {0 1}}}
tcltest::cleanupTests
