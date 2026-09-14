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
{farther squares come first: a8 (sq56) precedes a1 (sq0) from the white view} -body {
	b3dEval {
		::board3d::configure yaw 0 pitch 35 distance 12
		::board3d::fit 800 800
		set order [::board3d::orderedSquares]
		expr {[lsearch -integer $order 0] > [lsearch -integer $order 56]}
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
		if {$::board3d::State(yaw) != 0 || $::board3d::State(pitch) != 56} { set ok 0 }
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

# Record the actual renderer commands without requiring a display server.
# This catches accidental depth values passed as polygon coordinates.
b3dEval {
	proc winfo {args} { return 0 }
	proc captureCanvas {operation args} {
		if {$operation eq "delete"} { set ::items {}; return }
		lappend ::items $args
	}
}

tcltest::test board3d-render-quads {all views emit 64 bounded quads, labels and correctly indexed hits} -body {
	b3dEval {
		set StateBackup [array get ::board3d::State]
		set ::board3d::State(board) [::board3d::NormalizeBoard empty]
		set ::board3d::State(marks) {0 red 63 green}
		set ::board3d::State(selected) 7
		foreach view {white black side top} {
			::board3d::preset $view
			::board3d::fit 900 728
			::board3d::DrawScene captureCanvas
			set tiles 0
			set labels {}
			foreach item $::items {
				set type [lindex $item 0]
				set split 1
				while {[string is double -strict [lindex $item $split]]} { incr split }
				set coords [lrange $item 1 [expr {$split-1}]]
				set opts [dict create {*}[lrange $item $split end]]
				if {$type eq "polygon"} {
					if {[llength $coords] != 8} { error "$view: non-quad $coords" }
					foreach {x y} $coords {
						if {!($x >= 0 && $x <= 900 && $y >= 32 && $y <= 728)} {
							error "$view: out-of-bounds quad $coords"
						}
					}
				}
				if {"tile" in [dict get $opts -tags]} { incr tiles }
				if {"coord" in [dict get $opts -tags]} {
					lassign $coords x y
					if {$x < 8 || $x > 892 || $y < 40 || $y > 720} { error "clipped label" }
					lappend labels [dict get $opts -text]
				}
			}
			if {$tiles != 64 || [lsort $labels] ne [lsort {a b c d e f g h 1 2 3 4 5 6 7 8}]} {
				error "$view: missing tiles or labels"
			}
			for {set sq 0} {$sq < 64} {incr sq} {
				lassign [::board3d::squareCenter $sq] x y
				lassign [::board3d::projectPlane $x $y] sx sy
				if {[::board3d::squareAt $sx $sy] != $sq} { error "incorrect hit" }
			}
		}
		array set ::board3d::State $StateBackup
		set result ok
	}
} -result ok

tcltest::test board3d-top-square {top is a square grid with a1 dark at bottom-left} -body {
	b3dEval {
		::board3d::preset top
		::board3d::fit 900 728
		lassign [::board3d::projectPlane -4 -4] left bottom
		lassign [::board3d::projectPlane 4 4] right top
		lassign [::board3d::squareCenter 0] x y
		::board3d::DrawScene captureCanvas
		set firstTile [lindex $::items 5]
		expr {abs(($right-$left)-($bottom-$top)) < 1e-8
			&& $right > $left && $bottom > $top && $x == -3.5 && $y == -3.5
			&& [lindex $firstTile 10] eq $::board3d::State(darkColor)}
	}
} -result 1

tcltest::test board3d-themes-and-styles {theme and pieceStyle configuration works properly} -body {
	b3dEval {
		set res {}
		::board3d::setTheme "Rosewood & Boxwood"
		lappend res $::board3d::State(theme) $::board3d::State(darkColor)
		::board3d::setPieceStyle "realistic3d"
		lappend res $::board3d::State(pieceStyle)
		::board3d::setPieceStyle "vector"
		lappend res $::board3d::State(pieceStyle)
		::board3d::setPieceStyle "photos"
		lappend res $::board3d::State(pieceStyle)
		::board3d::setTheme "Classic Woodcraft"
		lappend res $::board3d::State(theme)
		set res
	}
} -result [list "Rosewood & Boxwood" "#8b2500" "realistic3d" "vector" "photos" "Classic Woodcraft"]

tcltest::test board3d-vector-piece-render {vector piece draws baize felt base, polygons, and finials} -body {
	b3dEval {
		::board3d::preset white
		::board3d::fit 800 600
		set ::items {}
		::board3d::DrawVectorPiece captureCanvas "wk" 400 300 35 0.8 0.6
		set hasFelt 0
		set hasCross 0
		foreach item $::items {
			set type [lindex $item 0]
			set split 1
			while {[string is double -strict [lindex $item $split]]} { incr split }
			set opts [dict create {*}[lrange $item $split end]]
			if {[dict exists $opts -fill]} {
				if {[dict get $opts -fill] eq "#2d5a37"} { set hasFelt 1 }
				if {[dict get $opts -fill] eq "#fff5ea" && $type eq "rectangle"} { set hasCross 1 }
			}
		}
		list $hasFelt $hasCross [expr {[llength $::items] > 10}]
	}
} -result {1 1 1}

tcltest::test board3d-pick-fallback {pickSquare falls back to the canvas projection without a hardware view} -body {
	b3dEval {
		set ::board3d::State(useOpenGL) 1
		::board3d::preset white
		::board3d::fit 800 600
		set bad {}
		for {set sq 0} {$sq < 64} {incr sq} {
			lassign [::board3d::squareCenter $sq] x y
			lassign [::board3d::projectPlane $x $y] sx sy
			if {[::board3d::pickSquare $sx $sy] != $sq} { lappend bad $sq }
		}
		set bad
	}
} -result {}

tcltest::test board3d-webgl-helpers {WebGL URL and JSON body are well formed} -body {
	b3dEval {
		join [list \
			[::board3d::WebGLUrl] \
			[::board3d::WebGLBoardJson "rnbq"] \
			[::board3d::WebGLBoardJson {a"b\c}]] "\n"
	}
} -result {http://127.0.0.1:8899
{"board": "rnbq"}
{"board": "a\"b\\c"}}

tcltest::test board3d-libroot {assets resolve from the load-time module root} -body {
	# [info script] is empty in menu/toolbar callbacks, so runtime path
	# resolution must go through the load-time-captured LibRoot
	b3dEval {
		set root $::board3d::LibRoot
		list \
			[expr {[file pathtype $root] eq "absolute"}] \
			[file exists [file join $root web3d server.py]] \
			[file exists [file join $root web3d index.html]] \
			[file exists [file join $root img pieces_3d wk.png]]
	}
} -result {1 1 1 1}

tcltest::test board3d-marks-parse {game mark strings normalize into internal and GL forms} -body {
	b3dEval {
		lassign [::board3d::NormalizeMarks [list \
			"add,full,d4,,green" \
			"add,arrow,d1,d4,red" \
			"add,circle,g1,,blue" \
			"add,disk,e4,,yellow" \
			"junk" \
			"add,arrow,x9,d4,red"]] result gl
		# d4 = 27, d1 = 3, g1 = 6, e4 = 28; junk/x9 are skipped;
		# headless has no winfo, so colors fall back to white
		list [llength $result] \
			[lindex $result 0] [lindex $result 1] \
			[lindex $result 2] [lindex $result 3] \
			[lrange $gl 0 5] [expr {[llength $gl] % 6}] [llength $gl]
	}
} -result {4 {full 27 -1 green} {arrow 3 27 red} {circle 6 -1 blue} {disk 28 -1 yellow} {f 27 -1 1.0 1.0 1.0} 0 24}

interp delete b3d
tcltest::cleanupTests
