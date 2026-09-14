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
	orderedSquares render refresh openViewer closeViewer isOpen setTheme setPieceStyle openWebGLViewer \
	toggleOpenGL embed unembed toggleEmbed

variable State
array set State {
	yaw          0
	pitch        56
	distance     12.0
	thickness    0.30
	margin       14
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
	theme        "Classic Woodcraft"
	pieceStyle   "realistic3d"
	useOpenGL    1
	embed        0
	suggested    -1
}

variable Priv
array set Priv {
	window     {}
	canvas     {}
	togl       {}
	parent     {}
	cacheCount 0
	afterid    {}
	webgl,pid  {}
	webgl,auto 0
	webgl,error {}
	embed,frame {}
	embed,togl  {}
	embed,error {}
	drag,kind   {}
	drag,from   -1
	drag,wx     0
	drag,wy     0
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

# Built-in handcrafted aesthetic themes
variable Themes
array set Themes {
	"Classic Woodcraft" {
		lightColor  #f0dab5
		darkColor   #b58451
		woodColor   #5c3a1e
		coordColor  #edd8be
		shadowColor #1a1008
	}
	"Rosewood & Boxwood" {
		lightColor  #f4e4c1
		darkColor   #8b2500
		woodColor   #461300
		coordColor  #faebd7
		shadowColor #140804
	}
	"Walnut & Maple" {
		lightColor  #eed9b7
		darkColor   #7d512d
		woodColor   #3d2311
		coordColor  #e8d3b0
		shadowColor #120904
	}
	"Ebony & Ivory" {
		lightColor  #f5f5f0
		darkColor   #2b2b2b
		woodColor   #181818
		coordColor  #e0e0e0
		shadowColor #0a0a0a
	}
	"Tournament Green" {
		lightColor  #ffffdd
		darkColor   #648a5c
		woodColor   #2d4028
		coordColor  #eaeec8
		shadowColor #0c140a
	}
}

	variable WebGLPort 8899

	# Application root, captured at load time.  [info script] is only valid
	# while the module is being sourced; in event callbacks (menu, toolbar)
	# it is empty, so runtime procs must resolve paths through this instead.
	variable LibRoot [file normalize [file dirname [file dirname [info script]]]]

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
		yaw 0 pitch 56 distance 12.0 thickness 0.30
		pieceHeight 1.10 gap 0.045
		showCoords 1 showShadow 1
		selected -1 suggested -1 marks {}
		view white
		theme "Classic Woodcraft"
		pieceStyle "vector"
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
			theme       { setTheme $value }
			pieceStyle  { setPieceStyle $value }
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
		white { configure yaw 0   pitch 56 distance 12.0 ; set State(view) white }
		black { configure yaw 180 pitch 56 distance 12.0 ; set State(view) black }
		side  { configure yaw 90  pitch 56 distance 12.0 ; set State(view) side }
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


# Adopt the configured board theme and derive the slab/frame/shadow
# colours from the dark square, so every theme stays harmonious.  Called
# when the viewer opens and whenever the position changes.
proc ::board3d::setTheme {name} {
	variable State
	variable Themes

	if {[info exists Themes($name)]} {
		set State(theme) $name
		array set State $Themes($name)
	} else {
		set State(theme) "Custom"
	}
	refresh
	return $State(theme)
}

proc ::board3d::setPieceStyle {style} {
	variable State
	switch -exact -- $style {
		realistic3d - vector - photos - glyphs {
			set State(pieceStyle) $style
		}
		default {
			return -code error "board3d::setPieceStyle: unknown style '$style' (expected realistic3d, vector, photos, glyphs)"
		}
	}
	refresh
	return $State(pieceStyle)
}

# Adopt the configured board theme and derive the slab/frame/shadow
# colours from the dark square, so every theme stays harmonious.  Called
# when the viewer opens and whenever the position changes.
proc ::board3d::UpdateColors {} {
	variable State
	variable Themes
	if {[info exists State(theme)] && [info exists Themes($State(theme))]} {
		array set State $Themes($State(theme))
		return
	}
	ThemeColors
	set State(woodColor)   [Shade $State(darkColor) 0.62]
	set State(shadowColor) [Shade $State(woodColor) 0.42]
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


# Return a realistic Blender 3D piece image scaled to $height pixels
proc ::board3d::PieceImage3D {piece height} {
	variable State
	variable Priv
	variable LibRoot

	if {$height < 4} { set height 4 }
	if {$height > 600} { set height 600 }
	set h [expr {round($height)}]
	set key "piece3d,$piece,$h"
	if {[info exists Priv($key)]} { return $Priv($key) }

	# Master 3D piece images loaded from img/pieces_3d/<piece>.png
	set masterKey "master3d,$piece"
	if {![info exists Priv($masterKey)]} {
		set file [file join $LibRoot img pieces_3d "${piece}.png"]
		if {![file exists $file]} {
			set file [file join [pwd] img pieces_3d "${piece}.png"]
		}
		if {![file exists $file]} { return {} }
		if {[catch { image create photo -file $file } master]} {
			return {}
		}
		set Priv($masterKey) $master
	}
	set master $Priv($masterKey)

	set name "photo_Board3D_Real_${piece}_[incr Priv(cacheCount)]"
	if {[catch {
		image create photo $name -width $h -height $h
		if {[llength [info commands ::scidb::tk::image]]} {
			::scidb::tk::image copy $master $name
		} else {
			# Tk standard zoom/subsample fallback
			set origW [image width $master]
			if {$origW > 0 && $h > 0} {
				set factor [expr {double($h) / $origW}]
				if {$factor <= 0.5} {
					set sub [expr {round(1.0 / $factor)}]
					$name copy $master -subsample $sub $sub
				} else {
					$name copy $master
				}
			}
		}
	}]} {
		catch { image delete $name }
		return {}
	}
	set Priv($key) $name
	return $name
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
	foreach key [array names Priv -glob piece3d,*] {
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
	variable State
	if {$State(useOpenGL) && $Priv(togl) ne "" && [winfo exists $Priv(togl)]} {
		renderOpenGL $Priv(togl)
	}
	if {$Priv(embed,togl) ne "" && [winfo exists $Priv(embed,togl)]} {
		renderOpenGL $Priv(embed,togl)
	}
	if {$Priv(canvas) ne "" && [winfo exists $Priv(canvas)]} {
		render $Priv(canvas)
	}
}

proc ::board3d::renderOpenGL {togl {board ""}} {
	variable State
	variable Priv
	if {[string length $board]} {
		set State(board) [NormalizeBoard $board]
	}
	if {$State(board) eq ""} { set State(board) [NormalizeBoard standard] }
	if {[llength [info commands ::scidb::tk::glboard_render]]} {
		catch {
			::scidb::tk::glboard_render $togl $State(board) \
				$State(yaw) $State(pitch) $State(distance) \
				$State(selected) $State(suggested) \
				$Priv(drag,from) $Priv(drag,wx) $Priv(drag,wy)
		}
	}
}


proc ::board3d::DrawScene {canv} {
	variable State

	$canv delete b3d

	# 1. Vertical slab sides (4 faces, items 0..3)
	DrawSlabSides $canv

	# 2. Classic Woodcraft Frame top surface (item 4)
	# Keeping exactly 5 background items preserves test_board3d polygon indexing
	set top [concat \
		[ScreenPoint -4.4 -4.4] [ScreenPoint 4.4 -4.4] \
		[ScreenPoint 4.4 4.4]  [ScreenPoint -4.4 4.4]]
	$canv create polygon {*}$top -fill $State(woodColor) \
		-outline [Shade $State(woodColor) 0.85] -tags b3d

	# 3. Tiles, Marks, Pieces, Coordinates, HUD
	DrawTiles $canv
	DrawMarks $canv
	DrawPieces $canv
	if {$State(showCoords)} { DrawCoords $canv }

	DrawHud $canv
}


proc ::board3d::DrawSlabSides {canv} {
	variable State

	set t $State(thickness)
	set base [Shade $State(woodColor) 0.75]

	# Directional lighting for the four side faces: front brightest
	set faces {
		{ {{-4.4 -4.4 0} {4.4 -4.4 0} {4.4 -4.4 -T} {-4.4 -4.4 -T}} 0.82 }
		{ {{4.4 4.4 0} {-4.4 4.4 0} {-4.4 4.4 -T} {4.4 4.4 -T}}     0.52 }
		{ {{-4.4 4.4 0} {-4.4 -4.4 0} {-4.4 -4.4 -T} {-4.4 4.4 -T}} 0.68 }
		{ {{4.4 -4.4 0} {4.4 4.4 0} {4.4 4.4 -T} {4.4 -4.4 -T}}     0.60 }
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
		set edgeCol [Shade $color 0.88]
		$canv create polygon {*}$pts -fill $color -outline $edgeCol -width 1 -tags [list b3d tile]
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

	set sinp [expr {abs(sin([deg2rad $State(pitch)]))}]
	set cosp [expr {abs(cos([deg2rad $State(pitch)]))}]

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
		set scale [expr {$State(focal)/$zb}]

		# A piece stands on its square: the billboard's base sits on the
		# projected square centre and the body rises towards the far side.
		# The screen height is the physical projection of $pieceHeight,
		# but never more than the screen distance to the row behind, so
		# adjacent ranks never overlap.  Looking straight down (top view)
		# the physical height vanishes; a small floor keeps the piece
		# visible as the disc its top-down silhouette would be.
		set height [expr {$scale * $State(pieceHeight) * $cosp}]
		if {$height < $scale*0.52} { set height [expr {$scale*0.52}] }
		if {$height > $scale*$sinp} { set height [expr {$scale*$sinp}] }
		if {$height < 6} { continue }

		# soft contact shadow, offset a little towards the viewer (the
		# piece sets also bake a drop shadow into the photo, so keep this
		# one faint)
		if {$State(showShadow)} {
			set half [expr {$height*0.38}]
			set rh   [expr {$half*0.30}]
			set sx   [expr {$bx + $scale*0.06}]
			set sy   [expr {$by + $height*0.12}]
			$canv create oval [expr {$sx - $half}] [expr {$sy - $rh}] \
				[expr {$sx + $half}] [expr {$sy + $rh}] \
				-fill $State(shadowColor) -stipple gray50 -outline {} -tags b3d
		}

		# the piece sets bake a drop shadow into the photo below the body
		# (body base ~90% of the image height), so anchor the image a
		# little below the square centre to ground the body on the square
		set base [expr {$by + $height*0.10}]

		# Render piece using requested pieceStyle (realistic3d, vector, photos, or glyphs)
		set rendered 0
		if {$State(pieceStyle) eq "realistic3d"} {
			set img [PieceImage3D $piece $height]
			if {$img ne ""} {
				$canv create image $bx [expr {$by + $height*0.04}] -image $img -anchor s -tags {b3d piece}
				set rendered 1
			}
		}

		if {!$rendered && $State(pieceStyle) eq "vector"} {
			DrawVectorPiece $canv $piece $bx $by $scale $cosp $sinp
			set rendered 1
		} elseif {!$rendered && $State(pieceStyle) eq "photos"} {
			set img [PieceImage $piece $height]
			if {$img ne ""} {
				$canv create image $bx $base -image $img -anchor s -tags {b3d piece}
				set rendered 1
			}
		}

		if {!$rendered} {
			DrawGlyph $canv $piece $bx $base $height
		}
	}
}


# ======================================================================
# 3D Vector Piece Renderer
# ======================================================================

proc ::board3d::DrawVectorPiece {canv piece bx by scale cosp sinp} {
	variable State
	set colorChar [string index $piece 0]
	set pieceType [string index $piece 1]

	# Material palette for Classic Woodcraft pieces
	if {$colorChar eq "w"} {
		set baseBody   #edd6b6
		set highlight  #fff5ea
		set shadowTone #c8a882
		set deepTone   #99734e
		set rimCol     #63472c
	} else {
		set baseBody   #31261e
		set highlight  #5c4b3f
		set shadowTone #201711
		set deepTone   #120d09
		set rimCol     #100b07
	}
	set feltCol #2d5a37

	# Vector piece profile stack: list of {w1 w2 h_bottom h_top}
	# Dimensions are in board units relative to square center
	switch -exact -- $pieceType {
		p {
			# Pawn: pedestal + tiered body + spherical head
			set layers [list \
				[list 0.35 0.32 0.00 0.07] \
				[list 0.30 0.22 0.07 0.18] \
				[list 0.21 0.14 0.18 0.44] \
				[list 0.16 0.18 0.44 0.50] \
				[list 0.20 0.02 0.50 0.72]]
			set finial none
		}
		r {
			# Rook: broad base + columnar tower + battlement crenellations
			set layers [list \
				[list 0.37 0.33 0.00 0.08] \
				[list 0.31 0.24 0.08 0.20] \
				[list 0.23 0.21 0.20 0.60] \
				[list 0.28 0.28 0.60 0.70] \
				[list 0.29 0.29 0.70 0.85]]
			set finial castle
		}
		n {
			# Knight: curved sculpted body + mane & muzzle
			set layers [list \
				[list 0.37 0.33 0.00 0.08] \
				[list 0.31 0.25 0.08 0.22] \
				[list 0.24 0.20 0.22 0.45] \
				[list 0.25 0.28 0.45 0.70] \
				[list 0.22 0.08 0.70 0.88]]
			set finial knight
		}
		b {
			# Bishop: tapered waist + mitre + finial ball
			set layers [list \
				[list 0.37 0.33 0.00 0.08] \
				[list 0.31 0.23 0.08 0.22] \
				[list 0.22 0.15 0.22 0.55] \
				[list 0.20 0.22 0.55 0.65] \
				[list 0.22 0.04 0.65 0.94]]
			set finial ball
		}
		q {
			# Queen: tall elegant profile + coronet
			set layers [list \
				[list 0.38 0.34 0.00 0.08] \
				[list 0.32 0.24 0.08 0.24] \
				[list 0.23 0.16 0.24 0.66] \
				[list 0.22 0.26 0.66 0.76] \
				[list 0.27 0.14 0.76 1.05]]
			set finial coronet
		}
		k {
			# King: stately wide pedestal + tall torso + cross finial
			set layers [list \
				[list 0.39 0.35 0.00 0.08] \
				[list 0.33 0.25 0.08 0.24] \
				[list 0.24 0.17 0.24 0.72] \
				[list 0.24 0.28 0.72 0.82] \
				[list 0.28 0.16 0.82 1.12]]
			set finial cross
		}
		default { return }
	}

	# Green Baize / Felt rim ring grounding the piece on the square
	set feltR [expr {0.37 * $scale}]
	set feltH [expr {$feltR * 0.32 * $cosp}]
	$canv create oval [expr {$bx - $feltR}] [expr {$by - $feltH}] \
		[expr {$bx + $feltR}] [expr {$by + $feltH}] \
		-fill $feltCol -outline [Shade $feltCol 0.6] -width 1 -tags {b3d piece}

	# Draw each 3D revolution segment from base upward
	foreach layer $layers {
		lassign $layer w1 w2 z1 z2
		set r1 [expr {$w1 * $scale}]
		set r2 [expr {$w2 * $scale}]
		set y1 [expr {$by - $z1 * $scale * $cosp}]
		set y2 [expr {$by - $z2 * $scale * $cosp}]
		set ry1 [expr {$r1 * 0.30 * $cosp}]
		set ry2 [expr {$r2 * 0.30 * $cosp}]

		# Main lit quad body for the frustum
		set bodyPts [list \
			[expr {$bx - $r1}] $y1 \
			[expr {$bx + $r1}] $y1 \
			[expr {$bx + $r2}] $y2 \
			[expr {$bx - $r2}] $y2]
		$canv create polygon {*}$bodyPts -fill $baseBody -outline $rimCol -width 1 -tags {b3d piece}

		# Shaded right half (giving strong 3D depth and directional lighting)
		set shadePts [list \
			$bx $y1 \
			[expr {$bx + $r1}] $y1 \
			[expr {$bx + $r2}] $y2 \
			$bx $y2]
		$canv create polygon {*}$shadePts -fill $shadowTone -outline {} -tags {b3d piece}

		# Left specular highlight strip
		set hlPts [list \
			[expr {$bx - $r1 * 0.65}] $y1 \
			[expr {$bx - $r1 * 0.35}] $y1 \
			[expr {$bx - $r2 * 0.35}] $y2 \
			[expr {$bx - $r2 * 0.65}] $y2]
		$canv create polygon {*}$hlPts -fill $highlight -outline {} -tags {b3d piece}

		# Cap ellipse at the top edge of this segment
		$canv create oval [expr {$bx - $r2}] [expr {$y2 - $ry2}] \
			[expr {$bx + $r2}] [expr {$y2 + $ry2}] \
			-fill $baseBody -outline $rimCol -width 1 -tags {b3d piece}
	}

	# Specialized architectural finials
	switch -exact -- $finial {
		cross {
			set topY [expr {$by - 1.15 * $scale * $cosp}]
			set armW [expr {0.08 * $scale}]
			set armH [expr {0.20 * $scale * $cosp}]
			# Cross vertical bar
			$canv create rectangle [expr {$bx - 0.03*$scale}] [expr {$topY - $armH}] \
				[expr {$bx + 0.03*$scale}] $topY \
				-fill $highlight -outline $rimCol -tags {b3d piece}
			# Cross horizontal beam
			$canv create rectangle [expr {$bx - $armW}] [expr {$topY - $armH*0.75}] \
				[expr {$bx + $armW}] [expr {$topY - $armH*0.50}] \
				-fill $highlight -outline $rimCol -tags {b3d piece}
		}
		coronet {
			set topY [expr {$by - 1.08 * $scale * $cosp}]
			# Small crown peak orbs
			foreach ox {-0.12 -0.06 0 0.06 0.12} {
				set obx [expr {$bx + $ox * $scale}]
				set rad [expr {0.035 * $scale}]
				$canv create oval [expr {$obx - $rad}] [expr {$topY - $rad}] \
					[expr {$obx + $rad}] [expr {$topY + $rad}] \
					-fill $highlight -outline $rimCol -tags {b3d piece}
			}
		}
		castle {
			set topY [expr {$by - 0.85 * $scale * $cosp}]
			# Crenellation cutouts
			foreach ox {-0.18 0.0 0.18} {
				set cx [expr {$bx + $ox * $scale}]
				$canv create rectangle [expr {$cx - 0.05*$scale}] [expr {$topY - 0.02*$scale}] \
					[expr {$cx + 0.05*$scale}] [expr {$topY + 0.07*$scale}] \
					-fill $shadowTone -outline $rimCol -tags {b3d piece}
			}
		}
		knight {
			set topY [expr {$by - 0.88 * $scale * $cosp}]
			# Snout/jaw protrusion
			set snoutPts [list \
				[expr {$bx - 0.20*$scale}] [expr {$topY + 0.12*$scale*$cosp}] \
				[expr {$bx - 0.32*$scale}] [expr {$topY + 0.22*$scale*$cosp}] \
				[expr {$bx - 0.16*$scale}] [expr {$topY + 0.32*$scale*$cosp}]]
			$canv create polygon {*}$snoutPts -fill $highlight -outline $rimCol -tags {b3d piece}
			# Mane ridge
			set manePts [list \
				[expr {$bx + 0.12*$scale}] [expr {$topY + 0.05*$scale*$cosp}] \
				[expr {$bx + 0.26*$scale}] [expr {$topY + 0.16*$scale*$cosp}] \
				[expr {$bx + 0.20*$scale}] [expr {$topY + 0.35*$scale*$cosp}]]
			$canv create polygon {*}$manePts -fill $shadowTone -outline $rimCol -tags {b3d piece}
		}
		ball {
			set topY [expr {$by - 0.96 * $scale * $cosp}]
			set rad [expr {0.05 * $scale}]
			$canv create oval [expr {$bx - $rad}] [expr {$topY - $rad}] \
				[expr {$bx + $rad}] [expr {$topY + $rad}] \
				-fill $highlight -outline $rimCol -tags {b3d piece}
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
			-anchor s -fill #202020 -font [list "DejaVu Sans" $size] -tags b3d
		$canv create text $bx $by -text $glyph \
			-anchor s -fill #ffffff -font [list "DejaVu Sans" $size] -tags b3d
	} else {
		$canv create text $bx $by -text $glyph \
			-anchor s -fill #101010 -font [list "DejaVu Sans" $size] -tags b3d
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
	set text "$State(view) view  |  $State(theme)  |  $State(pieceStyle) pieces  \u2014 drag to orbit, wheel to zoom"
	$canv create text 10 8 -text $text -anchor nw -fill #d8d8d8 \
		-font {TkDefaultFont 9} -tags b3d
}


# ======================================================================
# hardware view plumbing (shared by the viewer window and the
# embedded main-window pane)
# ======================================================================

# Load the Togl library (vendored copy first, then system packages).
# Returns true when the `togl` command is available.

proc ::board3d::LoadToglLib {} {
	if {[llength [info commands togl]]} { return 1 }
	variable LibRoot
	set candidates [list \
		[file join $LibRoot lib togl libTogl.so] \
		"/usr/lib/libTogl.so" \
		"/usr/lib/libTogl.so.2.0" \
		"/usr/lib/x86_64-linux-gnu/libTogl.so" \
	]
	foreach cand $candidates {
		if {[file exists $cand]} {
			if {![catch { load $cand Togl }]} { break }
		}
	}
	return [expr {[llength [info commands togl]] > 0}]
}


# Create a Togl widget with the standard interaction bindings (orbit,
# zoom, click-to-select).  When $forward is given (the hidden 2D board
# canvas of an embedded pane), plain key events are forwarded to it so
# game navigation keeps working while the 3D pane has the focus.
# When $movable is true (embedded pane), pressing a piece of the side to
# move starts a 3D drag-and-drop move instead of orbiting; dragging on
# empty squares or using button 3 still orbits.

proc ::board3d::CreateTogl {w {forward {}} {movable 0}} {
	set win [togl $w -width 640 -height 520 -rgba true -double true -depth true]
	if {$movable} {
		::bind $win <ButtonPress-1>  [namespace code [list OnMovePress $win %x %y %s]]
		::bind $win <B1-Motion>      [namespace code [list OnMoveMotion $win %x %y %s]]
		::bind $win <ButtonRelease-1> [namespace code [list OnMoveRelease $win %x %y %s]]
	} else {
		::bind $win <ButtonPress-1>  [namespace code [list OnPress $win %x %y]]
		::bind $win <B1-Motion>      [namespace code [list OnMotion $win %x %y]]
		::bind $win <ButtonRelease-1> [namespace code [list OnRelease $win]]
	}
	# button 3 always orbits (even over movable pieces)
	::bind $win <ButtonPress-3>  [namespace code [list OnPress $win %x %y orbit]]
	::bind $win <B3-Motion>      [namespace code [list OnMotion $win %x %y]]
	::bind $win <Button-4>       [namespace code [list viewerZoom 1]]
	::bind $win <Button-5>       [namespace code [list viewerZoom -1]]
	::bind $win <MouseWheel>    [namespace code [list viewerZoom %D]]
	::bind $win <Configure>      [namespace code [list OnConfigure %W %w %h]]
	if {$forward ne ""} {
		catch { $win configure -takefocus 1 }
		::bind $win <KeyPress>     [namespace code [list ForwardKey $forward %K %s]]
	}
	return $win
}


proc ::board3d::ForwardKey {canv keysym state} {
	# replay plain key events on the hidden 2D board so the game's
	# navigation bindings keep firing while the 3D pane has the focus
	if {![winfo exists $canv]} { return }
	catch { event generate $canv <KeyPress-$keysym> -state $state }
	return
}


# ======================================================================
# 3D move input (embedded pane): drag a piece between picked squares
# ======================================================================

# Is the move machinery currently accepting input?

proc ::board3d::MovesEnabled {} {
	if {[llength [info commands ::move::AddMove]] == 0} { return 0 }
	if {[catch { set ::move::Disabled } disabled]} { return 0 }
	if {$disabled} { return 0 }
	if {[catch { ::scidb::game::query over? } over]} { return 0 }
	if {$over} { return 0 }
	return 1
}


# Pick through the given hardware view, returning the square *and* the
# world coordinates of the ray intersection: {sq wx wy} (sq = -1 when the
# ray misses the playing surface).

proc ::board3d::SquareAtView {win x y} {
	variable State
	if {![llength [info commands ::scidb::tk::glboard_pick]]} { return {-1 0.0 0.0} }
	set res [catch {
		::scidb::tk::glboard_pick $win $x $y \
			$State(yaw) $State(pitch) $State(distance) 1
	} pick]
	if {$res || [llength $pick] != 3} { return {-1 0.0 0.0} }
	lassign $pick sq wx wy
	if {![string is double -strict $wx] || ![string is double -strict $wy]} {
		return {-1 0.0 0.0}
	}
	if {![string is integer -strict $sq] || $sq < 0 || $sq > 63} { set sq -1 }
	return [list $sq $wx $wy]
}


# Does $sq hold a piece of the side to move (and may it be moved)?

proc ::board3d::MovablePieceAt {sq} {
	variable State
	if {$sq < 0} { return 0 }
	if {![MovesEnabled]} { return 0 }
	set piece [string index $State(board) $sq]
	if {$piece eq "." || $piece eq " " || $piece eq ""} { return 0 }
	if {![string is alpha $piece]} { return 0 }
	set color [expr {[string is upper -strict $piece] ? "w" : "b"}]
	if {[catch { set stm [::scidb::pos::stm] }]} { return 0 }
	return [expr {$color eq $stm}]
}


# Is $to a legal target for a piece on $from (with the Shift override)?

proc ::board3d::LegalTarget? {from to state} {
	if {$from < 0 || $to < 0} { return 0 }
	set allowIllegal 0
	catch { set allowIllegal [::util::shiftIsHeldDown? $state] }
	if {[catch { ::scidb::pos::legal? $from $to $allowIllegal } legal]} { return 0 }
	return [expr {$legal ? 1 : 0}]
}


# Make the move through the application's move machinery (legality,
# promotion dialog, sounds, engine updates all come with it).

proc ::board3d::MakeMove {from to state} {
	set allowIllegal 0
	catch { set allowIllegal [::util::shiftIsHeldDown? $state] }
	if {[catch { ::move::AddMove $from $to $allowIllegal } err]} {
		if {[llength [info commands tk_messageBox]]} {
			catch {
				tk_messageBox -parent .application -icon warning -type ok \
					-title "Scidb" \
					-message "The 3D move could not be made:\n\n$err"
			}
		}
	}
	return
}


proc ::board3d::ClearDrag {} {
	variable Priv
	variable State
	set Priv(drag,kind) {}
	set Priv(drag,from) -1
	set Priv(drag,wx) 0
	set Priv(drag,wy) 0
	set State(suggested) -1
	return
}


proc ::board3d::OnMovePress {win x y state} {
	variable Priv
	variable State
	lassign [SquareAtView $win $x $y] sq wx wy

	# click-click completion: a pending selection plus a legal target
	if {$sq >= 0 && $State(selected) != -1 && $sq != $State(selected)} {
		if {[LegalTarget? $State(selected) $sq $state]} {
			set from $State(selected)
			ClearDrag
			set State(selected) -1
			MakeMove $from $sq $state
			refresh
			return
		}
		set State(selected) -1
	}

	# press on a movable piece: start a 3D drag
	if {$sq >= 0 && [MovablePieceAt $sq]} {
		set Priv(drag,kind) move
		set Priv(drag,from) $sq
		set Priv(drag,wx) $wx
		set Priv(drag,wy) $wy
		set State(selected) $sq
		set State(suggested) -1
		refresh
		return
	}

	# press on the selected square toggles the selection off
	if {$sq >= 0 && $sq == $State(selected)} {
		set State(selected) -1
		refresh
		return
	}

	# otherwise: orbit the camera (and drop any stale selection)
	set State(selected) -1
	OnPress $win $x $y orbit
	return
}


proc ::board3d::OnMoveMotion {win x y state} {
	variable Priv
	variable State

	if {$Priv(drag,kind) ne "move"} {
		OnMotion $win $x $y
		return
	}
	lassign [SquareAtView $win $x $y] sq wx wy
	set Priv(drag,wx) $wx
	set Priv(drag,wy) $wy
	set State(suggested) -1
	if {$sq >= 0 && $sq != $Priv(drag,from)} {
		if {[LegalTarget? $Priv(drag,from) $sq $state]} {
			set State(suggested) $sq
		}
	}
	refresh
	return
}


proc ::board3d::OnMoveRelease {win x y state} {
	variable Priv
	variable State

	if {$Priv(drag,kind) ne "move"} {
		OnRelease $win
		return
	}
	set from $Priv(drag,from)
	lassign [SquareAtView $win $x $y] sq wx wy
	ClearDrag
	if {$sq >= 0 && $sq != $from} {
		set State(selected) -1
		MakeMove $from $sq $state
	}
	# releasing on the source square keeps the selection armed for
	# click-click input
	refresh
	return
}


# ======================================================================
# embedded 3D pane in the main board window
# ======================================================================

# Embed the hardware 3D view in the board pane that owns $canvas2d.
# Returns the container frame (to be packed in place of the canvas by
# the caller, which owns the pane geometry), or "" when OpenGL (Togl) is
# not available; the reason is recorded in Priv(embed,error).

proc ::board3d::embed {canvas2d} {
	variable Priv
	variable State
	set Priv(embed,error) ""

	# already embedded (e.g. pane was reactivated)?
	if {$Priv(embed,frame) ne "" && [winfo exists $Priv(embed,frame)]} {
		return $Priv(embed,frame)
	}
	if {![LoadToglLib]} {
		set Priv(embed,error) "OpenGL support (Togl) is not available.\\n\\nInstall libtogl2 (Debian) or place libTogl.so in lib/togl/."
		return ""
	}
	if {![winfo exists $canvas2d]} {
		set Priv(embed,error) "the board pane no longer exists"
		return ""
	}

	set parent [winfo parent $canvas2d]
	set frame [frame $parent.board3dgl -background #101418]
	if {[catch {
		# movable: dragging pieces in the 3D pane makes moves
		set Priv(embed,togl) [CreateTogl $frame.togl $canvas2d 1]
	} err]} {
		catch { destroy $frame }
		set Priv(embed,togl) {}
		set Priv(embed,error) "could not create the OpenGL widget: $err"
		return ""
	}
	pack $Priv(embed,togl) -fill both -expand yes
	set Priv(embed,frame) $frame

	# camera orientation follows the 2D board at embed time
	set rotated 0
	if {[llength [info commands ::board::diagram::rotated?]]
		&& [llength [info commands ::application::board::rotated?]]} {
		catch { set rotated [::application::board::rotated?] }
	}
	preset [expr {$rotated ? "black" : "white"}]
	return $frame
}


# Undo embed; the caller repacks the 2D canvas.  The widget is kept for
# fast re-embedding.

proc ::board3d::unembed {} {
	variable Priv
	ClearDrag
	set Priv(embed,error) ""
	if {$Priv(embed,frame) ne "" && [winfo exists $Priv(embed,frame)]} {
		catch { pack forget $Priv(embed,frame) }
	}
	return
}


# Menu hook: switch the main board pane between 2D and hardware 3D.
# The checkbutton state lives in State(embed).

proc ::board3d::toggleEmbed {} {
	variable State
	if {[llength [info commands ::application::board::show3D]] == 0} { return }
	if {$State(embed)} {
		if {![::application::board::show3D 1]} {
			# embedding failed (no Togl); keep the menu in sync
			set State(embed) 0
		}
	} else {
		::application::board::show3D 0
	}
	return
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
	variable LibRoot

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
		ttk::button $bar.$view -text $label -width 5 \
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

	# Theme selector combobox
	ttk::label $bar.tl -text " Theme:"
	set themeValues [list "Classic Woodcraft" "Rosewood & Boxwood" "Walnut & Maple" "Ebony & Ivory" "Tournament Green"]
	set themeCombo [ttk::combobox $bar.theme -values $themeValues -state readonly -width 16]
	$themeCombo set $State(theme)
	bind $themeCombo <<ComboboxSelected>> [namespace code [list viewerThemeSelected %W]]
	pack $bar.tl $themeCombo -side left -padx 2 -pady 2

	# Piece Style toggle
	ttk::label $bar.sl -text " Pieces:"
	set styleValues [list "realistic3d" "vector" "photos" "glyphs"]
	set styleCombo [ttk::combobox $bar.style -values $styleValues -state readonly -width 11]
	$styleCombo set $State(pieceStyle)
	bind $styleCombo <<ComboboxSelected>> [namespace code [list viewerStyleSelected %W]]
	pack $bar.sl $styleCombo -side left -padx 2 -pady 2

	# Hardware Accelerated OpenGL 3D toggle button
	ttk::button $bar.opengl -text "\u2699 3D Hardware" \
		-command [namespace code toggleOpenGL]
	pack $bar.opengl -side right -padx 6 -pady 2

	# Canvas container frame to support both OpenGL Togl and fallback Tk canvas
	set canv [tk::canvas $dlg.canvas -borderwidth 0 -highlightthickness 0 \
		-background #101418 -takefocus 1]
	set Priv(canvas) $canv

	# Try creating native hardware-accelerated OpenGL Togl viewport
	set toglWin ""
	if {$State(useOpenGL)} {
		if {[LoadToglLib]} {
			catch {
				set toglWin [CreateTogl $dlg.togl]
				set Priv(togl) $toglWin
			}
		}
	}

	if {$Priv(togl) ne "" && [winfo exists $Priv(togl)]} {
		pack $Priv(togl) -side top -fill both -expand yes
		set activeView $Priv(togl)
	} else {
		pack $canv -side top -fill both -expand yes
		set activeView $canv
	}

	set State(board) [CurrentBoard]
	UpdateColors

	foreach w [list $canv $dlg.togl] {
		if {![winfo exists $w]} { continue }
		::bind $w <Configure>      [namespace code [list OnConfigure %W %w %h]]
		::bind $w <ButtonPress-1>  [namespace code [list OnPress %W %x %y]]
		::bind $w <B1-Motion>      [namespace code [list OnMotion %W %x %y]]
		::bind $w <ButtonRelease-1> [namespace code [list OnRelease %W]]
		::bind $w <ButtonPress-3>  [namespace code [list OnPress %W %x %y pan]]
		::bind $w <B3-Motion>      [namespace code [list OnMotion %W %x %y]]
		::bind $w <Button-4>       [namespace code [list viewerZoom 1]]
		::bind $w <Button-5>       [namespace code [list viewerZoom -1]]
		::bind $w <MouseWheel>     [namespace code [list viewerZoom %D]]
		::bind $w <Left>           [namespace code [list viewerRotate -15]]
		::bind $w <Right>          [namespace code [list viewerRotate 15]]
		::bind $w <Up>             [namespace code [list viewerTilt 5]]
		::bind $w <Down>           [namespace code [list viewerTilt -5]]
		::bind $w <Home>           [namespace code [list viewerPreset white]]
	}
	::bind $dlg  <Escape>         [namespace code closeViewer]

	# ::util::place only sets the position; force a size too.
	lassign [::util::place $dlg -parent $parent -position center] px py
	set sx [format "%+d" [expr {int($px)}]]
	set sy [format "%+d" [expr {int($py)}]]
	wm geometry $dlg "720x560${sx}${sy}"
	wm deiconify $dlg
	focus $dlg
	after idle [namespace code [list InitialDraw $canv]]
	return $dlg
}


proc ::board3d::toggleOpenGL {{value {}}} {
	variable State
	variable Priv
	if {$Priv(window) eq "" || ![winfo exists $Priv(window)]} { return }
	if {[string is boolean -strict $value]} {
		set State(useOpenGL) [expr {$value ? 1 : 0}]
	} else {
		set State(useOpenGL) [expr {!$State(useOpenGL)}]
	}
	# the hardware view needs a live Togl widget; otherwise stay on canvas
	set useGL [expr {$State(useOpenGL)
		&& $Priv(togl) ne "" && [winfo exists $Priv(togl)]}]
	if {$Priv(togl) ne "" && [winfo exists $Priv(togl)]} {
		catch { pack forget $Priv(togl) }
	}
	if {$Priv(canvas) ne "" && [winfo exists $Priv(canvas)]} {
		catch { pack forget $Priv(canvas) }
	}
	if {$useGL} {
		pack $Priv(togl) -side top -fill both -expand yes
	} elseif {$Priv(canvas) ne "" && [winfo exists $Priv(canvas)]} {
		pack $Priv(canvas) -side top -fill both -expand yes
	}
	refresh
}


proc ::board3d::InitialDraw {canv} {
	variable Priv
	variable State
	if {$State(useOpenGL) && $Priv(togl) ne "" && [winfo exists $Priv(togl)]} {
		renderOpenGL $Priv(togl)
	}
	if {[winfo exists $canv]} {
		render $canv
	}
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
	set Priv(togl) {}
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
	variable Priv
	set State(board) [NormalizeBoard $board]
	UpdateColors
	refresh
	# keep an open WebGL viewer in sync with the position
	if {$Priv(webgl,auto)} {
		catch { WebGLPost $State(board) }
	}
	return $State(board)
}


# ======================================================================
# WebGL viewer (web3d/): three.js front end served by web3d/server.py.
# The browser polls /api/board, so syncing is a single local POST.
# ======================================================================

proc ::board3d::WebGLUrl {} {
	variable WebGLPort
	return "http://127.0.0.1:$WebGLPort"
}


# minimal JSON body for the board push API (boards are plain ASCII,
# but escape properly anyway)
proc ::board3d::WebGLBoardJson {board} {
	set board [string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $board]
	return "{\"board\": \"$board\"}"
}


proc ::board3d::WebGLServerUp {} {
	variable WebGLPort
	if {[catch { socket 127.0.0.1 $WebGLPort } sock]} { return 0 }
	catch { close $sock }
	return 1
}


proc ::board3d::WebGLStartServer {} {
	variable Priv
	variable LibRoot
	variable WebGLPort
	if {[WebGLServerUp]} { return 1 }
	set server [file join $LibRoot web3d server.py]
	if {![file exists $server]} {
		set Priv(webgl,error) "web3d/server.py not found (expected below '$LibRoot')"
		return 0
	}

	set python ""
	if {![catch { exec python3 -c {import sys} }]} {
		set python python3
	} elseif {![catch { exec python -c {import sys} }]} {
		set python python
	}
	if {$python eq ""} {
		set Priv(webgl,error) "neither python3 nor python was found in PATH"
		return 0
	}

	set tmp /tmp
	if {[info exists ::env(TMPDIR)] && $::env(TMPDIR) ne ""} { set tmp $::env(TMPDIR) }
	set log [file join $tmp scidb-web3d-server.log]
	if {[catch { exec $python $server >& $log & } pid]} {
		set Priv(webgl,error) "could not run '$python $server': $pid"
		return 0
	}
	set Priv(webgl,pid) $pid

	# wait (max ~5s) for the server to accept connections
	for {set i 0} {$i < 50} {incr i} {
		if {[WebGLServerUp]} { return 1 }
		if {[llength [info commands after]]} { after 100 }
	}
	set Priv(webgl,error) "server did not accept connections on port $WebGLPort within 5s (log: $log)"
	return 0
}


proc ::board3d::WebGLPost {board {timeout 2000}} {
	if {[catch { package require http }]} { return 0 }
	set body [WebGLBoardJson $board]
	if {[catch {
		set tok [::http::geturl [WebGLUrl]/api/board \
			-query $body -type "application/json" -timeout $timeout]
		set status [::http::status $tok]
		set ncode  [::http::ncode $tok]
		::http::cleanup $tok
	}]} { return 0 }
	return [expr {$status eq "ok" && $ncode == 200}]
}


proc ::board3d::openWebGLViewer {} {
	variable Priv
	variable WebGLPort
	if {![WebGLStartServer]} {
		if {[llength [info commands tk_messageBox]]} {
			set parent [expr {$Priv(window) ne "" && [winfo exists $Priv(window)] ? $Priv(window) : "."}]
			catch {
				tk_messageBox -parent $parent -icon warning -type ok \
					-title "Scidb" \
					-message "The 3D WebGL server could not be started.\n\n$Priv(webgl,error)"
			}
		}
		return 0
	}
	set board [NormalizeBoard [CurrentBoard]]
	if {![WebGLPost $board]} {
		# something answers on the port but is not our board API
		if {[llength [info commands tk_messageBox]]} {
			set parent [expr {$Priv(window) ne "" && [winfo exists $Priv(window)] ? $Priv(window) : "."}]
			catch {
				tk_messageBox -parent $parent -icon warning -type ok \
					-title "Scidb" \
					-message "A service on port $WebGLPort did not accept the board update.\n\nIs another program using port $WebGLPort?"
			}
		}
		return 0
	}
	set Priv(webgl,auto) 1
	# tests and headless use suppress the browser launch
	if {![info exists ::env(SCIDB_WEB3D_NO_BROWSER)]} {
		set url [WebGLUrl]
		switch -glob -- $::tcl_platform(os) {
			"Linux*" {
				foreach browser {xdg-open firefox chromium chromium-browser google-chrome} {
					if {![catch { exec $browser $url & }]} { return 1 }
				}
			}
			"Darwin" {
				if {![catch { exec open $url & }]} { return 1 }
			}
			default {
				if {$::tcl_platform(platform) eq "windows"} {
					if {![catch { exec start $url & }]} { return 1 }
				}
			}
		}
	}
	return 1
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
	variable Priv
	if {![winfo exists $win]} { return }
	if {$win eq $Priv(togl) || $win eq $Priv(embed,togl)} {
		renderOpenGL $win
	} elseif {$Priv(canvas) ne "" && $win eq $Priv(canvas)} {
		render $win
	}
}


# Resolve a click at view coordinates (x, y) to a board square,
# honouring whichever view received it: the hardware OpenGL views
# (viewer window or embedded main-window pane) pick through their own
# projection (glboard_pick), the canvas view through `squareAt`.

proc ::board3d::pickSquare {x y {win {}}} {
	variable State
	variable Priv
	if {$win ne ""
		&& ($win eq $Priv(togl) || $win eq $Priv(embed,togl))
		&& [winfo exists $win]} {
		if {![llength [info commands ::scidb::tk::glboard_pick]]} { return -1 }
		if {[catch {
			::scidb::tk::glboard_pick $win $x $y \
				$State(yaw) $State(pitch) $State(distance)
		} sq] || ![string is integer -strict $sq]} { return -1 }
		return $sq
	}
	return [squareAt $x $y]
}


proc ::board3d::OnPress {win sx sy {mode orbit}} {
	variable Priv
	set Priv(drag,win) $win
	set Priv(drag,mode) $mode
	set Priv(drag,x) $sx
	set Priv(drag,y) $sy
	set Priv(drag,moved) 0
	return
}


proc ::board3d::OnMotion {win sx sy} {
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


proc ::board3d::OnRelease {win} {
	variable Priv
	variable State

	if {[info exists Priv(drag,moved)] && !$Priv(drag,moved)
		&& $Priv(drag,mode) eq "orbit"} {
		set sq [pickSquare $Priv(drag,x) $Priv(drag,y) $win]
		set State(selected) $sq
		refresh
	}
	unset -nocomplain Priv(drag,x) Priv(drag,y) Priv(drag,mode) Priv(drag,moved) Priv(drag,win)
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


proc ::board3d::viewerThemeSelected {w} {
	set val [$w get]
	if {$val ne ""} { setTheme $val }
}


proc ::board3d::viewerStyleSelected {w} {
	set val [$w get]
	if {$val ne ""} { setPieceStyle $val }
}

# vi:set ts=3 sw=3:
