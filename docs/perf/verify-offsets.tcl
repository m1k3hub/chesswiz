# For each PGN in ::VFILES: open directly (offsets path) and import into memory;
# compare game dumps at sample indices. Returns mismatch report.
proc ::BLog {args} {}
proc ::BProg {args} {return 0}
set rep {}
foreach f $::VFILES {
	catch {::scidb::db::close VRef}
	::scidb::db::new VRef Undetermined [::application::database::lookupType Clipbase]
	set n [lindex [::scidb::db::import VRef $f ::BLog {} ::BProg {} -encoding utf-8] 0]
	::application::database::openBase .application $f no
	update
	set bad 0; set checked 0
	foreach i [list 0 1 2 [expr {$n/3}] [expr {$n/2}] [expr {$n-2}] [expr {$n-1}]] {
		if {$i < 0 || $i >= $n} continue
		set a [::scidb::game::dump VRef Normal 0 $i]
		set b [::scidb::game::dump $f Normal 0 $i]
		incr checked
		if {$a ne $b} { incr bad; lappend rep "MISMATCH [file tail $f] #$i: [string range $a 0 80] | [string range $b 0 80]" }
	}
	lappend rep "[file tail $f]: games=$n checked=$checked bad=$bad"
	::application::database::CloseBase .application $f
	::scidb::db::close VRef
}
join $rep \n
