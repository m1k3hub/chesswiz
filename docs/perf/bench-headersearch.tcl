# Header searches on ::BSCI (3 runs each): ms and match count.
::application::database::openBase .application $::BSCI no
update
set db $::BSCI
set v [::scidb::view::new $db Normal unused unused unused unused master slave]
set out {}
foreach q $::BQ {
	set times {}
	foreach r {1 2 3} {
		set t0 [clock microseconds]
		::scidb::view::search $db Normal $v null none $q
		lappend times [expr {([clock microseconds]-$t0)/1000.0}]
	}
	lappend out "[lsort -real $times] ms n=[::scidb::view::count games $db Normal $v] :: $q"
}
::scidb::view::close $db Normal $v
join $out \n
