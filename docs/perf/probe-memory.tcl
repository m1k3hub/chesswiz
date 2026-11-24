# Memory/leak probe: RSS, image, widget and after counts around repeated actions.
proc ::Mrss {} { set f [open /proc/self/status]; set d [read $f]; close $f; regexp {VmRSS:\s+(\d+)} $d -> kb; return [expr {$kb/1024}] }
proc ::Mwidgets {} { set n 0; set q [list .]; while {[llength $q]} { set q [lassign $q w]; incr n; lappend q {*}[winfo children $w] }; return $n }
proc ::Msnap {label} { lappend ::MOUT [format "%-28s rss=%4d MB images=%5d widgets=%5d afters=%3d" $label [::Mrss] [llength [image names]] [::Mwidgets] [llength [after info]]] }
set ::MOUT {}
::application::database::openBase .application $::BSCI no
update; ::application::switchTab board; update
::Msnap start
for {set i 0} {$i < 50} {incr i} {
	::game::new .application -base $::BSCI -variant Normal -view 0 -number [expr {$i*97}]
	update
	set gb $::application::pgn::Vars(gamebar)
	foreach p [::game::usedPositions?] { catch { ::gamebar::remove $gb $p; ::game::release $p } }
	update
}
::Msnap "after 50 game loads"
foreach t {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25} { ::application::switchTab database; update; ::application::switchTab board; update }
::Msnap "after 50 tab switches"
::application::database::closeBase .application $::BSCI; update
for {set i 0} {$i < 10} {incr i} { ::application::database::openBase .application $::BSCI no; update; ::application::database::closeBase .application $::BSCI; update }
::Msnap "after 10 open/close 100k"
foreach sz {900x700 1300x900 1100x800 1600x950 1000x750 1400x850 1200x820 1700x1000} { wm geometry .application $sz; update; after 400; update }
::Msnap "after 8 window resizes"
join $::MOUT \n
