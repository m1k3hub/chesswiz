# Open the notation display setup dialog and Cancel it, 3 runs (long game loaded).
::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update; ::application::switchTab board; update
::game::new .application -base $::BPGN -variant Normal -view 0 -number $::BGAME
update
set out {}
foreach r {1 2 3} {
	set ::t0 [clock microseconds]
	after 1 {proc _p {} {
		set d [lindex [lsearch -all -inline [winfo children .application] *pgnSetup*] 0]
		if {$d ne "" && [winfo ismapped $d]} {
			update idletasks; set ::t1 [clock microseconds]; $d.cancel invoke
		} else { after 5 _p }
	}; _p}
	::application::pgn::ConfigureEditor; update
	set t2 [clock microseconds]
	lappend out [format "open %.0f cancel %.0f" [expr {($::t1-$::t0)/1000.0}] [expr {($t2-$::t1)/1000.0}]]
}
join $out "; "
