# Database > Maintenance > Convert copies every game into a new .sci database
# (the copy and save commands need their progress and log callbacks).
package require tcltest 2.5
tcltest::test convert {Convert database copies every game into a new .sci} -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app convert]
	file delete -force $dir; file mkdir $dir
	set src [file join $dir src.pgn]
	set fh [open $src w]
	for {set i 1} {$i <= 7} {incr i} { puts $fh "\[Event \"C\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 1-0\n" }
	close $fh
	::scidb::db::open $src {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	set dst [file join $dir out.sci]
	rename ::dialog::question ::zq; proc ::dialog::question args { return no }
	rename ::dialog::saveFile ::zs; proc ::dialog::saveFile args [list return [list $dst utf-8]]
	rename ::dialog::info ::zi; proc ::dialog::info args { set ::zinfo $args }
} -body {
	set rc [catch {::application::database::ConvertDatabase .application $src Normal} r]
	list $rc [file exists $dst] [string match "*7*" $::zinfo]
} -cleanup {
	rename ::dialog::question {}; rename ::zq ::dialog::question
	rename ::dialog::saveFile {}; rename ::zs ::dialog::saveFile
	rename ::dialog::info {}; rename ::zi ::dialog::info
} -result {0 1 1}
tcltest::cleanupTests
