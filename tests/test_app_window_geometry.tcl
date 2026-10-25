# Exercise the layout geometry callback that restores the main window.
package require tcltest

namespace eval ::windowGeometryTest {
proc inside {} {
	lassign [winfo workarea .application] wx wy ww wh
	lassign [::scidb::tk::wm frame .application] x y w h
	puts "native-frame=[list $x $y $w $h] workarea=[list $wx $wy $ww $wh] geometry=[wm geometry .application]"
	expr {$x >= $wx && $y >= $wy && $x+$w <= $wx+$ww && $y+$h <= $wy+$wh}
}
proc settle {} {
	set deadline [expr {[clock milliseconds] + 2000}]
	while {[clock milliseconds] < $deadline} {
		update
		after 25
	}
}
}

foreach {name geometry width height} {
	normal 600x400+10+10 600 400
	right-bottom 600x400+1900+1050 600 400
	negative 600x400+-200+-100 600 400
	oversized 4000x3000+1900+1050 4000 3000
} {
	tcltest::test window-geometry-$name {restored layout is inside the work area} -setup {
		::windowGeometryTest::settle
		set saved [wm geometry .application]
		set minsize [wm minsize .application]
		set maxsize [wm maxsize .application]
		wm minsize .application 1 1
		wm geometry .application $geometry
		::windowGeometryTest::settle
	} -body {
		::application::twm::geometry [list $width $height 0 0 0 0]
		::windowGeometryTest::settle
		::windowGeometryTest::inside
	} -cleanup {
		wm minsize .application {*}$minsize
		wm maxsize .application {*}$maxsize
		wm geometry .application $saved
		::windowGeometryTest::settle
	} -result 1
}

tcltest::test window-geometry-keep-size {a fitting restored layout keeps its requested size} -setup {
	::windowGeometryTest::settle
	set saved [wm geometry .application]
	set minsize [wm minsize .application]
	wm minsize .application 1 1
} -body {
	wm geometry .application 600x400+10+10
	::windowGeometryTest::settle
	::application::twm::geometry {600 400 0 0 0 0}
	::windowGeometryTest::settle
	set size [list [winfo width .application] [winfo height .application]]
	wm geometry .application +1900+1050
	::windowGeometryTest::settle
	::application::twm::geometry {600 400 0 0 0 0}
	::windowGeometryTest::settle
	list [expr {$size eq [list [winfo width .application] [winfo height .application]]}] \
		[::windowGeometryTest::inside]
} -cleanup {
	wm minsize .application {*}$minsize
	wm geometry .application $saved
	::windowGeometryTest::settle
} -result {1 1}

tcltest::cleanupTests
