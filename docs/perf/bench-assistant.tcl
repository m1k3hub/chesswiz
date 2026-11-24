::application::switchTab board; update
set out {}
foreach r {1 2 3} {
	set t0 [clock microseconds]; ::application::assistant::panel::Show; update
	set t1 [clock microseconds]
	set leaves [[::application::twm board] leaves]
	::application::assistant::panel::Hide; update
	lappend out [expr {($t1-$t0)/1000}]
}
list "Show: $out ms" [lsearch -inline $leaves assistant]
