# ======================================================================
# 3D chessboard renderer and viewer.
#
# See docs/BOARD_3D_DESIGN.md.  The module has three layers:
#
#   * pure math  — orbit camera, perspective projection, unprojection and
#                  square hit-testing (no Tk calls, unit-tested headless);
#   * renderer   — draws a perspective board slab, shaded tiles, coordinate
#                  labels, marks and depth-scaled piece billboards on a Tk
#                  canvas;
#   * viewer     — a toplevel with orbit/tilt/zoom bindings and presets that
#                  mirrors the current board position.
#
# The main board pushes its 64-character board string through
# ::board3d::PositionChanged (see application::board::update).
# ======================================================================

::util::source board-3d

namespace eval ::board3d {

namespace export configure defaults preset setBoard setMarks setSelected \
	fit projectPoint projectPlane unproject squareAt squareCenter depthOf \
	orderedSquares render refresh openViewer closeViewer isOpen

variable State
array set State {
	yaw          0
	pitch        34
	distance     12.0
	thickness    0.30
	margin       18
	pieceHeight  1.10
	gap          0.045
	lightColor   #f0d9b5
	darkColor    #b58863
	woodColor    #6b4a2b
	coordColor   #f6ead6
	shadowColor  #1a1208
	showCoords   1
	showShadow   1
	selected     -1
	marks        {}
	board        ""
	view         white
	width        640
	height       640
	focal        1.0
	cx           320
	cy           320
	camX 0 camY 0 camZ 0
	fx 0 fy 0 fz 0
	rx 1 ry 0 rz 0
	ux 0 uy 0 uz 0
	usePhotos    -1
	pieceSize    0
}

variable Priv
array set Priv {
	window     {}
	canvas     {}
	parent     {}
	cacheCount 0
	afterid    {}
}

variable StandardBoard "RNBQKBNRPPPPPPPP................................pppppppprnbqkbnr"
variable EmptyBoard    "................................................................"

# board letter -> piece identifier used by the piece sets
variable LetterToPiece
array set LetterToPiece {
	K wk  Q wq  R wr  B wb  N wn  P wp
	k bk  q bq  r br  b bb  n bn  p bp
	e e
}

# Unicode fallback glyphs (white solid then black)
variable Glyph
array set Glyph {
	wk \u2654 wq \u2655 wr \u2656 wb \u2657 wn \u2658 wp \u2659
	bk \u265A bq \u265B br \u265C bb \u265D bn \u265E bp \u265F
}

} ;# namespace board3d


# ======================================================================
# small vector helpers (numbers, not lists, for speed)
# ======================================================================

proc ::board3d::deg2rad {a} { return [expr {$a*0.017453292519943295}] }


proc ::board3d::NormalizeBoard {board} {
	variable StandardBoard
	variable EmptyBoard

	if {[string length $board] == 64} { return $board }
	switch -exact -- $board {
		standard - default { return $StandardBoard }
		empty              { return $EmptyBoard }
	}
	return $StandardBoard
}


# ======================================================================
# camera
# ======================================================================

# Recompute the camera position and orthonormal view basis from the
# current yaw/pitch/distance.  The camera always looks at the origin.
proc ::board3d::UpdateCamera {} {
	variable State

	set yaw   [deg2rad $State(yaw)]
	set pitch [deg2rad $State(pitch)]
	set d     $State(distance)
	if {$d < 2.0} { set d 2.0 }

	set State(camX) [expr {$d*cos($pitch)*sin($yaw)}]
	set State(camY) [expr {-$d*cos($pitch)*cos($yaw)}]
	set State(camZ) [expr {$d*sin($pitch)}]

	# forward points from the camera at the origin
	set fx [expr {-$State(camX)/$d}]
	set fy [expr {-$State(camY)/$d}]
	set fz [expr {-$State(camZ)/$d}]

	# Derive right from yaw directly: forward x worldUp degenerates
	# at the straight-down pole, but this basis remains well-defined.
	set rx [expr {cos($yaw)}]
	set ry [expr {sin($yaw)}]
	set rl [expr {sqrt($rx*$rx + $ry*$ry)}]
	if {$rl < 1e-9} { set rx 1.0 ; set ry 0.0 ; set rl 1.0 }
	set rx [expr {$rx/$rl}]
	set ry [expr {$ry/$rl}]
	set rz 0.0

	# up = right x forward
	set ux [expr {$ry*$fz - $rz*$fy}]
	set uy [expr {$rz*$fx - $rx*$fz}]
	set uz [expr {$rx*$fy - $ry*$fx}]

	lassign [list $fx $fy $fz] State(fx) State(fy) State(fz)
	lassign [list $rx $ry $rz] State(rx) State(ry) State(rz)
	lassign [list $ux $uy $uz] State(ux) State(uy) State(uz)
}


# Raw projection with focal == 1: returns {ux uy depth}, where the final
# screen point is {cx + focal*ux, cy - focal*uy}.  ux/uy are linear in the
# focal length (depth does not depend on it), which is what makes the
# auto-fit exact.
proc ::board3d::ProjectRaw {x y z} {
	variable State

	set vx [expr {$x - $State(camX)}]
	set vy [expr {$y - $State(camY)}]
	set vz [expr {$z - $State(camZ)}]

	set xc [expr {$vx*$State(rx) + $vy*$State(ry) + $vz*$State(rz)}]
	set yc [expr {$vx*$State(ux) + $vy*$State(uy) + $vz*$State(uz)}]
	set zc [expr {$vx*$State(fx) + $vy*$State(fy) + $vz*$State(fz)}]

	if {$zc < 0.05} { set zc 0.05 }
	return [list [expr {$xc/$zc}] [expr {$yc/$zc}] $zc]
}


# Fit the projection to a canvas and cache focal/centre.  Returns
# {focal cx cy}.  Safe to call for any size; margin is in pixels.
proc ::board3d::fit {width height {margin 0}} {
	variable State

	if {$width  < 16} { set width  16 }
	if {$height < 16} { set height 16 }
	if {$margin <= 0} { set margin $State(margin) }

	UpdateCamera

	# extreme slab points: four top corners + four bottom corners
	set t $State(thickness)
	set pts {}
	foreach x {-4.4 4.4} {
		foreach y {-4.4 4.4} {
			lappend pts [list $x $y 0]
			lappend pts [list $x $y [expr {-$t}]]
		}
	}

	set minOx  1e18 ; set maxOx -1e18
	set minOy  1e18 ; set maxOy -1e18
	foreach p $pts {
		lassign $p x y z
		lassign [ProjectRaw $x $y $z] ux uy zc
		set ox $ux
		set oy [expr {-$uy}]
		if {$ox < $minOx} { set minOx $ox }
		if {$ox > $maxOx} { set maxOx $ox }
		if {$oy < $minOy} { set minOy $oy }
		if {$oy > $maxOy} { set maxOy $oy }
	}

	set availW [expr {double($width  - 2*$margin)}]
	set availH [expr {double($height - 2*$margin - 32)}]
	if {$availW < 8} { set availW 8 }
	if {$availH < 8} { set availH 8 }

	set spanX [expr {double($maxOx - $minOx)}]
	set spanY [expr {double($maxOy - $minOy)}]
	if {$spanX < 1e-9} { set spanX 1e-9 }
	if {$spanY < 1e-9} { set spanY 1e-9 }

	set focal [expr {min($availW/$spanX, $availH/$spanY)}]

	set State(focal) $focal
	set State(cx) [expr {$width/2.0  - $focal*($minOx + $maxOx)/2.0}]
	set State(cy) [expr {($height + 32)/2.0 - $focal*($minOy + $maxOy)/2.0}]
	set State(width)  $width
	set State(height) $height

	return [list $focal $State(cx) $State(cy)]
}


# Project a world point through the fitted camera -> {sx sy depth}.
proc ::board3d::projectPoint {x y z} {
	variable State

	lassign [ProjectRaw $x $y $z] ux uy zc
	return [list [expr {$State(cx) + $State(focal)*$ux}] \
				 [expr {$State(cy) - $State(focal)*$uy}] $zc]
}


proc ::board3d::projectPlane {x y} {
	return [projectPoint $x $y 0]
}


# Canvas polygons accept screen pairs, never the projection depth.
proc ::board3d::ScreenPoint {x y {z 0}} {
	return [lrange [projectPoint $x $y $z] 0 1]
}


# Unproject a screen point onto the board plane z = 0.
# Returns {x y} or {} when the ray is parallel to / behind the plane.
proc ::board3d::unproject {sx sy} {
	variable State

	if {$State(focal) == 0} { return {} }

	set ux [expr {($sx - $State(cx))/$State(focal)}]
	set uy [expr {($State(cy) - $sy)/$State(focal)}]

	set rx [expr {$State(rx)*$ux + $State(ux)*$uy + $State(fx)}]
	set ry [expr {$State(ry)*$ux + $State(uy)*$uy + $State(fy)}]
	set rz [expr {$State(rz)*$ux + $State(uz)*$uy + $State(fz)}]

	if {abs($rz) < 1e-9} { return {} }

	set t [expr {-$State(camZ)/$rz}]
	if {$t <= 0} { return {} }

	return [list [expr {$State(camX) + $t*$rx}] [expr {$State(camY) + $t*$ry}]]
}


# ======================================================================
# square geometry
# ======================================================================

# Board-string row 0 is rank 1: square 0 is a1, nearest the white camera.
proc ::board3d::squareCenter {sq} {
	set row  [expr {$sq/8}]
	set file [expr {$sq%8}]
	set rank $row
	return [list [expr {$file - 3.5}] [expr {$rank - 3.5}]]
}


proc ::board3d::SquareFromWorld {x y} {
	set file [expr {int(floor($x + 4.0))}]
	set rank [expr {int(floor($y + 4.0))}]
	if {$file < 0} { set file 0 } elseif {$file > 7} { set file 7 }
	if {$rank < 0} { set rank 0 } elseif {$rank > 7} { set rank 7 }
	return [expr {$rank*8 + $file}]
}


proc ::board3d::squareAt {sx sy} {
	set p [unproject $sx $sy]
	if {[llength $p] == 0} { return -1 }
	lassign $p x y
	if {$x < -4.0 || $x > 4.0 || $y < -4.0 || $y > 4.0} { return -1 }
	return [SquareFromWorld $x $y]
}


proc ::board3d::depthOf {sq} {
	lassign [squareCenter $sq] x y
	return [lindex [ProjectRaw $x $y 0] 2]
}


proc ::board3d::orderedSquares {} {
	set pairs {}
	for {set sq 0} {$sq < 64} {incr sq} {
		lappend pairs [list [depthOf $sq] $sq]
	}
	set result {}
	foreach pair [lsort -index 0 -real -decreasing $pairs] {
		lappend result [lindex $pair 1]
	}
	return $result
}


# ======================================================================
# parameters
# ======================================================================

proc ::board3d::defaults {} {
	variable State
	array set State {
		yaw 0 pitch 34 distance 12.0 thickness 0.30
		pieceHeight 1.10 gap 0.045
		showCoords 1 showShadow 1
		selected -1 marks {}
		view white
	}
}


proc ::board3d::configure {args} {
	variable State
	foreach {key value} $args {
		switch -exact -- $key {
			yaw         { set State(yaw) [expr {double($value)}] }
			pitch       { set State(pitch) [expr {double($value)}] }
			distance    { set State(distance) [expr {double($value)}] }
			thickness   { set State(thickness) [expr {double($value)}] }
			pieceHeight { set State(pieceHeight) [expr {double($value)}] }
			gap         { set State(gap) [expr {double($value)}] }
			lightColor  { set State(lightColor) $value }
			darkColor   { set State(darkColor) $value }
			woodColor   { set State(woodColor) $value }
			coordColor  { set State(coordColor) $value }
			showCoords  { set State(showCoords) [expr {$value ? 1 : 0}] }
			showShadow  { set State(showShadow) [expr {$value ? 1 : 0}] }
			default {
				return -code error "board3d::configure: unknown option $key"
			}
		}
	}
	ClampPitch
	return
}


proc ::board3d::ClampPitch {} {
	variable State
	if {$State(pitch) >  90} { set State(pitch)  90 }
	if {$State(pitch) < -89} { set State(pitch) -89 }
}


proc ::board3d::preset {name} {
	variable State
	ClampPitch
	switch -exact -- $name {
		white { configure yaw 0   pitch 34 distance 12.0 ; set State(view) white }
		black { configure yaw 180 pitch 34 distance 12.0 ; set State(view) black }
		side  { configure yaw 90  pitch 44 distance 12.0 ; set State(view) side }
		top   { configure yaw 0   pitch 90 distance 12.0 ; set State(view) top }
		free  { set State(view) free }
		default {
			return -code error "board3d::preset: unknown view '$name'"
		}
	}
	return $State(view)
}


proc ::board3d::setBoard {board} {
	variable State
	set State(board) [NormalizeBoard $board]
	refresh
	return $State(board)
}


proc ::board3d::setMarks {marks} {
	variable State
	set State(marks) $marks
	refresh
}


proc ::board3d::setSelected {sq} {
	variable State
	set State(selected) $sq
	refresh
}


# ======================================================================
# colours
# ======================================================================

# Apply a multiplicative shade to a #rrggbb colour.  Non-hex colours are
# returned unchanged.
proc ::board3d::Shade {color factor} {
	if {![regexp {^#([0-9a-fA-F]{6})$} $color -> hex]} { return $color }
	set r [expr {round(([scan [string range $hex 0 1] %x])*$factor)}]
	set g [expr {round(([scan [string range $hex 2 3] %x])*$factor)}]
	set b [expr {round(([scan [string range $hex 4 5] %x])*$factor)}]
	foreach v {r g b} {
		if {[set $v] < 0}   { set $v 0 }
		if {[set $v] > 255} { set $v 255 }
	}
	return [format "#%02x%02x%02x" $r $g $b]
}


# Use the board theme's square colours when available so the 3D board
# matches the configured 2D board.
proc ::board3d::ThemeColors {} {
	variable State
	foreach {var which} {lightColor lite darkColor dark} {
		if {[llength [info commands ::board::square::style]] == 0
			&& [llength [info vars ::board::square::style]] == 0} { break }
		if {[catch { set c [set ::board::square::style($which,solid)] }]} { continue }
		if {[string length $c] && [regexp {^#[0-9a-fA-F]{6}$} $c]} {
			set State($var) $c
		}
	}
}


# ======================================================================
# piece image assets
# ======================================================================

proc ::board3d::InitPieceAssets {} {
	variable State
	variable Priv

	if {$State(usePhotos) >= 0} { return $State(usePhotos) }

	set State(usePhotos) 0
	if {[llength [info commands ::scidb::tk::image]] == 0} { return 0 }
	if {[llength [info commands ::board::registerPieceSize]] == 0} { return 0 }

	set size 96
	if {[catch {
		::board::registerPieceSize $size
		::board::setupPieces $size
	}]} {
		catch { ::board::unregisterPieceSize $size }
		return 0
	}

	if {[lsearch -exact [image names] "photo_Piece(wk,$size)"] >= 0} {
		set State(pieceSize) $size
		set State(usePhotos) 1
	}
	return $State(usePhotos)
}


# Return a canvas-ready image scaled to $height pixels, or {} when the
# piece photos are unavailable.
proc ::board3d::PieceImage {piece height} {
	variable State
	variable Priv

	if {$height < 4} { set height 4 }
	if {$height > 600} { set height 600 }
	set key "piece,$piece,[expr {round($height)}]"
	if {[info exists Priv($key)]} { return $Priv($key) }

	if {![InitPieceAssets]} { return {} }

	set h [expr {round($height)}]
	set name "photo_Board3D_${piece}_[incr Priv(cacheCount)]"
	set src "photo_Piece($piece,$State(pieceSize))"
	if {[catch {
		image create photo $name -width $h -height $h
		::scidb::tk::image copy $src $name
	}]} {
		catch { image delete $name }
		return {}
	}
	set Priv($key) $name
	return $name
}


proc ::board3d::ClearPieceImages {} {
	variable Priv
	foreach key [array names Priv -glob piece,*] {
		catch { image delete $Priv($key) }
		unset Priv($key)
	}
	set Priv(cacheCount) 0
}


# ======================================================================
# renderer
# ======================================================================

proc ::board3d::render {canv {board ""}} {
	variable State

	if {[string length $board]} {
		set State(board) [NormalizeBoard $board]
	}
	if {$State(board) eq ""} { set State(board) [NormalizeBoard standard] }

	if {[winfo exists $canv]} {
		set w [winfo width  $canv]
		set h [winfo height $canv]
		if {$w < 16} { set w 16 }
		if {$h < 16} { set h 16 }
	} else {
		set w $State(width)
		set h $State(height)
	}

	fit $w $h
	DrawScene $canv
	return
}


proc ::board3d::refresh {} {
	variable Priv
	if {$Priv(canvas) ne "" && [winfo exists $Priv(canvas)]} {
		render $Priv(canvas)
	}
}


proc ::board3d::DrawScene {canv} {
	variable State

	$canv delete b3d

	DrawSlabSides $canv

	# board top surface (wood) then inset tiles far to near
	set top [concat \
		[ScreenPoint -4.4 -4.4] [ScreenPoint 4.4 -4.4] \
		[ScreenPoint 4.4 4.4]  [ScreenPoint -4.4 4.4]]
	$canv create polygon {*}$top -fill $State(woodColor) -outline #aa8154 -tags b3d

	DrawTiles $canv
	DrawMarks $canv
	DrawPieces $canv
	if {$State(showCoords)} { DrawCoords $canv }

	DrawHud $canv
}


proc ::board3d::DrawSlabSides {canv} {
	variable State

	set t $State(thickness)
	set base [Shade $State(woodColor) 0.7]

	# light direction for the four side faces: front brightest
	set faces {
		{ {{-4.4 -4.4 0} {4.4 -4.4 0} {4.4 -4.4 -T} {-4.4 -4.4 -T}} 0.80 }
		{ {{4.4 4.4 0} {-4.4 4.4 0} {-4.4 4.4 -T} {4.4 4.4 -T}}     0.55 }
		{ {{-4.4 4.4 0} {-4.4 -4.4 0} {-4.4 -4.4 -T} {-4.4 4.4 -T}} 0.68 }
		{ {{4.4 -4.4 0} {4.4 4.4 0} {4.4 4.4 -T} {4.4 -4.4 -T}}     0.62 }
	}

	foreach face $faces {
		lassign $face corners factor
		set pts {}
		foreach c $corners {
			lassign $c x y z
			if {$z eq "-T"} { set z [expr {-$t}] }
			lappend pts {*}[ScreenPoint $x $y $z]
		}
		$canv create polygon {*}$pts \
			-fill [Shade $base $factor] -outline {} -tags b3d
	}
}


proc ::board3d::DrawTiles {canv} {
	variable State

	set gap $State(gap)
	foreach sq [orderedSquares] {
		set row  [expr {$sq/8}]
		set file [expr {$sq%8}]
		set rank $row
		set x0 [expr {$file - 4.0 + $gap}]
		set x1 [expr {$file - 3.0 - $gap}]
		set y0 [expr {$rank - 4.0 + $gap}]
		set y1 [expr {$rank - 3.0 - $gap}]

		# same lite/dark assignment the 2D renderer uses
		if {($row + $file) % 2} { set color $State(lightColor) } else { set color $State(darkColor) }

		set pts [concat \
			[ScreenPoint $x0 $y0] [ScreenPoint $x1 $y0] \
			[ScreenPoint $x1 $y1] [ScreenPoint $x0 $y1]]
		$canv create polygon {*}$pts -fill $color -outline {} -tags [list b3d tile]
	}
}


proc ::board3d::DrawCoords {canv} {
	variable State

	set files {a b c d e f g h}
	set off 0.22
	for {set f 0} {$f < 8} {incr f} {
		set x [expr {$f - 3.5}]
		set letter [lindex $files $f]
		foreach y [list [expr {$State(camY) > 0.001 ? 4.0 + $off : -4.0 - $off}]] {
			lassign [ScreenPoint $x $y] sx sy
			$canv create text $sx $sy -text $letter -anchor center \
				-fill $State(coordColor) -font {TkDefaultFont -12 bold} -tags {b3d coord}
		}
	}
	for {set r 0} {$r < 8} {incr r} {
		set y [expr {$r - 3.5}]
		set label [expr {$r + 1}]
		foreach x [list [expr {$State(camX) > 0.001 ? 4.0 + $off : -4.0 - $off}]] {
			lassign [ScreenPoint $x $y] sx sy
			$canv create text $sx $sy -text $label -anchor center \
				-fill $State(coordColor) -font {TkDefaultFont -12 bold} -tags {b3d coord}
		}
	}
}


proc ::board3d::DrawMarks {canv} {
	variable State
	set gap $State(gap)

	foreach {sq color} [concat $State(marks) [MarksFromSelection]] {
		if {$sq < 0 || $sq > 63} { continue }
		set row  [expr {$sq/8}]
		set file [expr {$sq%8}]
		set rank $row
		set x0 [expr {$file - 4.0 + $gap}]
		set x1 [expr {$file - 3.0 - $gap}]
		set y0 [expr {$rank - 4.0 + $gap}]
		set y1 [expr {$rank - 3.0 - $gap}]
		set pts [concat \
			[ScreenPoint $x0 $y0] [ScreenPoint $x1 $y0] \
			[ScreenPoint $x1 $y1] [ScreenPoint $x0 $y1]]
		$canv create polygon {*}$pts -fill $color -stipple gray50 \
			-outline {} -tags b3d
	}
}


proc ::board3d::MarksFromSelection {} {
	variable State
	if {$State(selected) < 0} { return {} }
	return [list $State(selected) #3d7fd0]
}


proc ::board3d::DrawPieces {canv} {
	variable State
	variable LetterToPiece

	set board $State(board)
	if {[string length $board] != 64} { return }

	foreach sq [orderedSquares] {
		set letter [string index $board $sq]
		if {$letter eq "." || $letter eq " "} { continue }
		# tolerate unexpected characters (malformed/variant board strings) so
		# the render path can never raise a background error
		if {![info exists LetterToPiece($letter)]} { continue }
		set piece $LetterToPiece($letter)
		if {$piece eq "e"} { continue }

		lassign [squareCenter $sq] x y
		lassign [projectPlane $x $y] bx by zb
		# Keep a billboard within the projected row spacing. At the pole
		# physical vertical height projects to zero, so use ground scale.
		set scale [expr {$State(focal)/$zb}]
		set height [expr {$scale * min(0.76, 0.80*abs(sin([deg2rad $State(pitch)]))) * min(1.0, $State(pieceHeight)/1.10)}]

		# ground shadow
		if {$State(showShadow)} {
			set half [expr {$height*0.40}]
			set rh   [expr {$half*0.35}]
			set bxShadow [expr {$bx + $scale*0.08}]
			set byShadow [expr {$by + $height*0.35}]
			$canv create oval [expr {$bxShadow - $half}] [expr {$byShadow - $rh}] \
				[expr {$bxShadow + $half}] [expr {$byShadow + $rh}] \
				-fill #65513d -outline {} -tags b3d
		}
		if {$height < 6} { continue }

		set img [PieceImage $piece $height]
		if {$img ne ""} {
			$canv create image $bx $by -image $img -anchor center -tags {b3d piece}
		} else {
			DrawGlyph $canv $piece $bx $by $height
		}
	}
}


proc ::board3d::DrawGlyph {canv piece bx by height} {
	variable Glyph
	variable State

	set glyph $Glyph($piece)
	set size [expr {-int($height*0.90)}]
	if {$size > -6} { return }
	set white [string index $piece 0]

	if {$white eq "w"} {
		$canv create text [expr {$bx + 1}] [expr {$by + 1}] -text $glyph \
			-anchor center -fill #202020 -font [list "DejaVu Sans" $size] -tags b3d
		$canv create text $bx $by -text $glyph \
			-anchor center -fill #ffffff -font [list "DejaVu Sans" $size] -tags b3d
	} else {
		$canv create text $bx $by -text $glyph \
			-anchor center -fill #101010 -font [list "DejaVu Sans" $size] -tags b3d
	}
}


proc ::board3d::DrawHud {canv} {
	variable State
	variable Priv
	foreach view {white black side top} {
		set button "$Priv(window).bar.$view"
		if {[winfo exists $button]} {
			$button state [expr {$view eq $State(view) ? "pressed" : "!pressed"}]
		}
	}
	$canv create rectangle 0 0 $State(width) 32 -fill #101418 -outline {} -tags b3d
	set text "$State(view) view \u2014 drag to orbit, wheel to zoom"
	$canv create text 10 8 -text $text -anchor nw -fill #d8d8d8 \
		-font {TkDefaultFont 9} -tags b3d
}


# ======================================================================
# viewer window
# ======================================================================

proc ::board3d::isOpen {} {
	variable Priv
	return [expr {$Priv(window) ne "" && [winfo exists $Priv(window)]}]
}


proc ::board3d::openViewer {parent} {
	variable Priv
	variable State

	if {[isOpen]} {
		raise $Priv(window)
		focus $Priv(window)
		return $Priv(window)
	}

	if {[llength [info commands toplevel]] == 0} {
		return -code error "board3d::openViewer: Tk is not available"
	}

	set dlg "$parent.__board3d__"
	set Priv(parent) $parent
	set Priv(window) $dlg

	toplevel $dlg -class Scidb
	wm title $dlg "3D Board"
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code closeViewer]
	wm minsize $dlg 220 200

	set bar [ttk::frame $dlg.bar]
	pack $bar -side bottom -fill x
	foreach {label view} {White white Black black Side side Top top} {
		ttk::button $bar.$view -text $label -width 6 \
			-command [namespace code [list viewerPreset $view]]
		pack $bar.$view -side left -padx 1 -pady 2
	}
	ttk::button $bar.rotl -text "\u21ba" -width 3 \
		-command [namespace code [list viewerRotate -15]]
	ttk::button $bar.rotr -text "\u21bb" -width 3 \
		-command [namespace code [list viewerRotate 15]]
	ttk::button $bar.reset -text "Reset" \
		-command [namespace code [list viewerPreset white]]
	pack $bar.rotl $bar.rotr $bar.reset -side left -padx 1 -pady 2

	set canv [tk::canvas $dlg.canvas -borderwidth 0 -highlightthickness 0 \
		-background #101418 -takefocus 1]
	pack $canv -side top -fill both -expand yes
	set Priv(canvas) $canv

	set State(board) [CurrentBoard]

	::bind $canv <Configure>      [namespace code [list OnConfigure %W %w %h]]
	::bind $canv <ButtonPress-1>  [namespace code [list OnPress %x %y]]
	::bind $canv <B1-Motion>      [namespace code [list OnMotion %x %y]]
	::bind $canv <ButtonRelease-1> [namespace code OnRelease]
	::bind $canv <ButtonPress-3>  [namespace code [list OnPress %x %y pan]]
	::bind $canv <B3-Motion>      [namespace code [list OnMotion %x %y]]
	::bind $canv <Button-4>       [namespace code [list viewerZoom 1]]
	::bind $canv <Button-5>       [namespace code [list viewerZoom -1]]
	::bind $canv <MouseWheel>     [namespace code [list viewerZoom %D]]
	::bind $canv <Left>           [namespace code [list viewerRotate -15]]
	::bind $canv <Right>          [namespace code [list viewerRotate 15]]
	::bind $canv <Up>             [namespace code [list viewerTilt 5]]
	::bind $canv <Down>           [namespace code [list viewerTilt -5]]
	::bind $canv <Home>           [namespace code [list viewerPreset white]]
	::bind $dlg  <Escape>         [namespace code closeViewer]

	# ::util::place only sets the position; force a size too.  A toplevel
	# that is mapped without an explicit size, while carrying a <Configure>
	# binding, makes `update idletasks` spin (no window manager under Xvfb).
	lassign [::util::place $dlg -parent $parent -position center] px py
	set sx [format "%+d" [expr {int($px)}]]
	set sy [format "%+d" [expr {int($py)}]]
	wm geometry $dlg "720x560${sx}${sy}"
	wm deiconify $dlg
	focus $dlg
	after idle [namespace code [list InitialDraw $canv]]
	return $dlg
}


proc ::board3d::InitialDraw {canv} {
	if {![winfo exists $canv]} { return }
	render $canv
}


proc ::board3d::closeViewer {} {
	variable Priv
	variable State

	if {[llength [info commands after]]} { after cancel $Priv(afterid) }
	if {$Priv(window) ne "" && [winfo exists $Priv(window)]} {
		destroy $Priv(window)
	}
	set Priv(window) {}
	set Priv(canvas) {}
	ClearPieceImages
	# release the piece-size registration acquired by InitPieceAssets
	if {$State(usePhotos) && $State(pieceSize) > 0} {
		catch { ::board::unregisterPieceSize $State(pieceSize) }
	}
	set State(usePhotos) -1
	set State(pieceSize) 0
	set State(selected) -1
	return
}


proc ::board3d::PositionChanged {board} {
	variable State
	set State(board) [NormalizeBoard $board]
	refresh
	return $State(board)
}


# current board string, taken from the live 2D board when available
proc ::board3d::CurrentBoard {} {
	variable StandardBoard
	if {[llength [info commands ::board::diagram::data]]} {
		if {[catch {
			set w $::application::board::board
			if {$w ne ""} { return [::board::diagram::data $w] }
		}]} { return $StandardBoard }
	}
	return $StandardBoard
}


# ======================================================================
# interaction
# ======================================================================

proc ::board3d::OnConfigure {win width height} {
	variable Priv
	variable State

	# Ignore no-op configures and coalesce resize storms with a timer (an
	# `after idle` reschedule here can spin inside `update idletasks`).
	if {$width == $State(width) && $height == $State(height)} { return }
	if {[llength [info commands after]]} { after cancel $Priv(afterid) }
	set Priv(afterid) [after 16 [namespace code [list DoResize $win]]]
	return
}


proc ::board3d::DoResize {win} {
	if {![winfo exists $win]} { return }
	render $win
}


proc ::board3d::OnPress {sx sy {mode orbit}} {
	variable Priv
	set Priv(drag,mode) $mode
	set Priv(drag,x) $sx
	set Priv(drag,y) $sy
	set Priv(drag,moved) 0
	return
}


proc ::board3d::OnMotion {sx sy} {
	variable Priv
	variable State

	if {![info exists Priv(drag,x)]} { return }
	set dx [expr {$sx - $Priv(drag,x)}]
	set dy [expr {$sy - $Priv(drag,y)}]
	set Priv(drag,x) $sx
	set Priv(drag,y) $sy
	if {abs($dx) + abs($dy) > 1} { set Priv(drag,moved) 1 }

	if {$Priv(drag,mode) eq "pan"} {
		# panning is intentionally not implemented; keep the drag a no-op
		return
	}
	set State(yaw)   [expr {$State(yaw) - $dx*0.5}]
	set State(pitch) [expr {$State(pitch) + $dy*0.4}]
	ClampPitch
	set State(view) free
	refresh
	return
}


proc ::board3d::OnRelease {} {
	variable Priv
	variable State

	if {[info exists Priv(drag,moved)] && !$Priv(drag,moved)
		&& $Priv(drag,mode) eq "orbit"} {
		set sq [squareAt $Priv(drag,x) $Priv(drag,y)]
		set State(selected) $sq
		refresh
	}
	unset -nocomplain Priv(drag,x) Priv(drag,y) Priv(drag,mode) Priv(drag,moved)
	return
}


proc ::board3d::viewerRotate {deg} {
	variable State
	set State(yaw) [expr {$State(yaw) + $deg}]
	set State(view) free
	refresh
	return
}


proc ::board3d::viewerTilt {deg} {
	variable State
	set State(pitch) [expr {$State(pitch) + $deg}]
	ClampPitch
	set State(view) free
	refresh
	return
}


proc ::board3d::viewerZoom {steps} {
	variable State
	if {![string is integer -strict $steps]} { return }
	# wheel events report +/-120 on Windows/macOS, +/-(1..5) on X11
	if {abs($steps) >= 100} { set steps [expr {$steps/120}] }
	set State(distance) [expr {$State(distance) - $steps*0.8}]
	if {$State(distance) < 6.0} { set State(distance) 6.0 }
	if {$State(distance) > 40.0} { set State(distance) 40.0 }
	refresh
	return
}


proc ::board3d::viewerPreset {name} {
	preset $name
	refresh
	return
}

# vi:set ts=3 sw=3:
