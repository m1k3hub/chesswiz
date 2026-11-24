::application::database::openBase .application $::BSCI no
update
::application::switchTab database; update
set tbl ""
set q [winfo children .application.nb.database]
while {[llength $q] && $tbl eq ""} { set q [lassign $q w]; if {[string match *games*.table $w]} { set tbl $w } else { lappend q {*}[winfo children $w] } }
set out {}
foreach {col dir} {white ascending eco ascending date descending number cancel} {
	set times {}
	foreach r {1 2 3} {
		::gamestable::SortColumn $tbl number cancel; update
		set t0 [clock microseconds]
		::gamestable::SortColumn $tbl $col $dir; update
		lappend times [expr {([clock microseconds]-$t0)/1000}]
	}
	lappend out "$col $dir: [lsort -integer $times] ms"
}
join $out \n
