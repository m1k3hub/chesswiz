# ======================================================================
# Headless tests for the 3D board math core (tcl/board-3d.tcl).
#
# The renderer and viewer need Tk and are covered by
# tests/test_app_board3d.tcl; the camera, projection, unprojection and
# hit-testing are pure Tcl and tested here.
# ======================================================================

package require tcltest 2.5

set board3dSource [file normalize [file join [file dirname [info script]] .. tcl board-3d.tcl]]
interp create b3d
b3d eval {namespace eval util {proc source {args} {}}}
b3d eval [list source $board3dSource]

proc b3dEval {script} { b3d eval $script }


tcltest::test board3d-camera-basis-orthonormal \
	{camera basis is orthonormal for a range of angles} -body {
	b3dEval {
		set bad {}
		foreach yaw {0 30 90 180 270 -45} {
			foreach pitch {-40 0 34 70 88} {
				::board3d::configure yaw $yaw pitch $pitch distance 12
				::board3d::fit 640 480
				set f [list $::board3d::State(fx) $::board3d::State(fy) $::board3d::State(fz)]
				set r [list $::board3d::State(rx) $::board3d::State(ry) $::board3d::State(rz)]
				set u [list $::board3d::State(ux) $::board3d::State(uy) $::board3d::State(uz)]
				set lenX [expr {sqrt([lindex $r 0]**2 + [lindex $r 1]**2 + [lindex $r 2]**2)}]
				set lenU [expr {sqrt([lindex $u 0]**2 + [lindex $u 1]**2 + [lindex $u 2]**2)}]
				set dotFR [expr {[lindex $f 0]*[lindex $r 0] + [lindex $f 1]*[lindex $r 1] + [lindex $f 2]*[lindex $r 2]}]
				set dotFU [expr {[lindex $f 0]*[lindex $u 0] + [lindex $f 1]*[lindex $u 1] + [lindex $f 2]*[lindex $u 2]}]
				set dotRU [expr {[lindex $r 0]*[lindex $u 0] + [lindex $r 1]*[lindex $u 1] + [lindex $r 2]*[lindex $u 2]}]
				if {abs($lenX-1) > 1e-9 || abs($lenU-1) > 1e-9
					|| abs($dotFR) > 1e-9 || abs($dotFU) > 1e-9 || abs($dotRU) > 1e-9} {
					lappend bad [list $yaw $pitch]
				}
			}
		}
		set bad
	}
} -result {}


tcltest::test board3d-project-unproject-roundtrip \
	{projecting a plane point and unprojecting it returns the point} -body {
	b3dEval {
		::board3d::configure yaw 25 pitch 40 distance 12
		::board3d::fit 800 600
		set worst 0.0
		foreach x {-3.5 -1.25 0 2.75 3.5} {
			foreach y {-3.5 -0.5 0 1.75 3.5} {
				lassign [::board3d::projectPlane $x $y] sx sy
				lassign [::board3d::unproject $sx $sy] ux uy
				set d [expr {max(abs($ux-$x), abs($uy-$y))}]
				if {$d > $worst} { set worst $d }
			}
		}
		expr {$worst < 1e-6}
	}
} -result 1


tcltest::test board3d-square-center-hit \
	{squareAt returns every square from its own projected centre} -body {
	b3dEval {
		set bad {}
		foreach view {white black side top} {
			::board3d::preset $view
			::board3d::fit 900 700
			for {set sq 0} {$sq < 64} {incr sq} {
				lassign [::board3d::squareCenter $sq] x y
				lassign [::board3d::projectPlane $x $y] sx sy
				set got [::board3d::squareAt $sx $sy]
				if {$got != $sq} { lappend bad [list $view $sq $got] }
			}
		}
		set bad
	}
} -result {}


tcltest::test board3d-square-outside \
	{points outside the board project to no square} -body {
	b3dEval {
		::board3d::preset white
		::board3d::fit 800 600
		list [::board3d::squareAt 1 1] [::board3d::squareAt 799 599] \
			[::board3d::squareAt -50 -50]
	}
} -result {-1 -1 -1}


tcltest::test board3d-depth-order \
	{depth ordering is a permutation of 0..63} -body {
	b3dEval {
		::board3d::configure yaw 0 pitch 35 distance 12
		::board3d::fit 800 800
		set sorted [lsort -integer [::board3d::orderedSquares]]
		set allok 1
		for {set i 0} {$i < 64} {incr i} {
			if {[lindex $sorted $i] != $i} { set allok 0 }
		}
		set allok
	}
} -result 1


tcltest::test board3d-depth-monotone \
{farther squares come first: a8 precedes a1 from the white view} -body {
	b3dEval {
		::board3d::configure yaw 0 pitch 35 distance 12
		::board3d::fit 800 800
		set order [::board3d::orderedSquares]
		expr {[lsearch -integer $order 0] < [lsearch -integer $order 56]}
	}
} -result 1


tcltest::test board3d-fit-contains-board \
{fit keeps the whole projected slab inside the canvas} -body {
	b3dEval {
		set ok 1
		foreach view {white black side top} {
			::board3d::preset $view
			set w 640 ; set h 480
			::board3d::fit $w $h 12
			set t $::board3d::State(thickness)
			foreach x {-4 4} {
				foreach y {-4 4} {
					foreach z [list 0 [expr {-$t}]] {
						lassign [::board3d::projectPoint $x $y $z] sx sy
						if {$sx < -0.5 || $sx > $w+0.5 || $sy < -0.5 || $sy > $h+0.5} { set ok 0 }
					}
				}
			}
		}
		set ok
	}
} -result 1


tcltest::test board3d-presets \
{view presets set sane camera parameters} -body {
	b3dEval {
		set ok 1
		::board3d::preset white
		if {$::board3d::State(yaw) != 0 || $::board3d::State(pitch) != 34} { set ok 0 }
		::board3d::preset black
		if {$::board3d::State(yaw) != 180} { set ok 0 }
		::board3d::preset side
		if {$::board3d::State(yaw) != 90} { set ok 0 }
		::board3d::preset top
		if {$::board3d::State(pitch) < 80} { set ok 0 }
		if {$::board3d::State(distance) < 6} { set ok 0 }
		set ok
	}
} -result 1


tcltest::test board3d-configure-unknown \
{configure rejects unknown options} -body {
	catch { b3dEval {::board3d::configure bogus 1} } msg
	set msg
} -match glob -result {*unknown option bogus*}


tcltest::test board3d-normalize \
{board keywords and short strings normalize to 64 characters} -body {
	b3dEval {
		list [string length [::board3d::NormalizeBoard standard]] \
			[string length [::board3d::NormalizeBoard empty]] \
			[string length [::board3d::NormalizeBoard {}]] \
			[regexp {^R} [::board3d::NormalizeBoard standard]]
	}
} -result {64 64 64 1}

interp delete b3d
tcltest::cleanupTests
