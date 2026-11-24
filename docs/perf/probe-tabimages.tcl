::application::database::openBase .application $::BSCI no
update; ::application::switchTab board; update
set out {}
foreach round {1 2 3 4} {
	set before [image names]
	foreach t {1 2 3 4 5 6 7 8 9 10} { ::application::switchTab database; update; ::application::switchTab information; update; ::application::switchTab board; update }
	set new {}
	foreach i [image names] { if {$i ni $before} { lappend new $i } }
	lappend out "round $round: +[llength $new] images [lrange $new 0 4]"
}
foreach r {1 2 3} { wm geometry .application [expr {1000+$r*150}]x[expr {760+$r*60}]; update; after 500; update }
set before [image names]
foreach r {1 2 3} { wm geometry .application [expr {1000+$r*150}]x[expr {760+$r*60}]; update; after 500; update }
set new {}; foreach i [image names] { if {$i ni $before} { lappend new $i } }
lappend out "repeat resizes: +[llength $new] [lrange $new 0 6]"
join $out \n
