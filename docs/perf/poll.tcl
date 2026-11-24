package require Tk; wm withdraw .
set t0 [lindex $argv 0]
while 1 { if {![catch {send Chesswiz {list [winfo ismapped .application] [llength [winfo children .application]]}} r] && [lindex $r 0]} break; after 100 }
puts "mapped at [expr {([clock milliseconds]-$t0)}] ms ($r)"
# wait idle: time a no-op roundtrip
set a [clock milliseconds]; send Chesswiz {update idletasks}; puts "idle rt [expr {[clock milliseconds]-$a}] ms"
exit
