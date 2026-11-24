::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update; ::application::switchTab board; update
set out {}
foreach t [list [::application::reflow::boardTwm] {*}[lsearch -all -inline [winfo children .application.nb.database] *]] {
	set q [list $t]; set cls {}
	while {[llength $q]} { set q [lassign $q w]; lappend q {*}[winfo children $w]
		if {[string match *Panedwindow [winfo class $w]]} {
			set p $w; set chain {}
			while {$p ne $t && $p ne "."} { set p [winfo parent $p]; lappend chain [winfo class $p] }
			lappend out "$w <- $chain"
		}
		dict incr cls [winfo class $w]
	}
}
lappend out [dict get [dict create {*}$cls] Frame]
join $out \n
