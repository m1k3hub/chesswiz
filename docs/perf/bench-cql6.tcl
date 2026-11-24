# CQL6 search timing on ::BSCI for each script in ::BQ (3 runs). Reports ms and hit count.
::application::database::openBase .application $::BSCI no
update
set out {}
foreach q $::BQ {
	set times {}
	for {set r 0} {$r < 3} {incr r} {
		set ::done 0
		set t0 [clock microseconds]
		::scidb::cql6::search $::BSCI Normal $q -threads 8 -variations 0 -paged 1 \
			-command {apply {{args} { set ::CQR [lindex $args end]; set ::done 1 }}}
		vwait ::done
		lappend times [expr {([clock microseconds] - $t0)/1000}]
		set hits [dict get $::CQR count]
		catch {::scidb::cql6::release [dict get $::CQR results]}
	}
	lappend out "[lsort -integer $times] ms hits=$hits :: $q"
}
::application::database::closeBase .application $::BSCI
join $out \n
