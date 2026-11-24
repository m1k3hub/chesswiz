proc ::Mrss {} { set f [open /proc/self/status]; set d [read $f]; close $f; regexp {VmRSS:\s+(\d+)} $d -> kb; return [expr {$kb/1024}] }
::application::switchTab board; update
set out {}
lappend out "start images=[llength [image names]] figurines=[llength [lsearch -all [image names] *figurine*]] rss=[::Mrss]"
for {set i 0} {$i < 40} {incr i} {
	wm geometry .application [expr {900 + $i*20}]x[expr {650 + $i*9}]
	update; after 120; update
}
after 500; update
lappend out "after 40 sizes images=[llength [image names]] figurines=[llength [lsearch -all [image names] *figurine*]] rss=[::Mrss]"
for {set i 0} {$i < 40} {incr i} {
	wm geometry .application [expr {900 + $i*20}]x[expr {650 + $i*9}]
	update; after 120; update
}
after 500; update
lappend out "same 40 again images=[llength [image names]] figurines=[llength [lsearch -all [image names] *figurine*]] rss=[::Mrss]"
join $out \n
