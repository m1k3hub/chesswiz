# Open each PGN in ::VFILES (copies), delete game N/2 and save: the save copies
# untouched games by their recorded byte offsets.
set rep {}
foreach f $::VFILES {
	::application::database::openBase .application $f no
	update
	set n [::scidb::db::count games $f Normal]
	::scidb::db::set delete [expr {$n/2}] -1 $f Normal 1
	if {[catch {::scidb::db::save $f ::BProg {}} e]} { lappend rep "save error $f: $e" }
	::application::database::CloseBase .application $f
	lappend rep "[file tail $f] n=$n"
}
join $rep \n
