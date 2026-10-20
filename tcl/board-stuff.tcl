# ======================================================================
# Author : $Author$
# Version: $Revision: 1517 $
# Date   : $Date: 2018-09-06 04:47:10 -0400 (Thu, 06 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source board-diagram

namespace eval board {
namespace eval diagram {

namespace export drawBorderlines

namespace import ::tcl::mathfunc::max
namespace import ::tcl::mathfunc::min
namespace import ::tcl::mathfunc::abs
namespace import ::tcl::mathfunc::int
namespace import ::tcl::mathfunc::atan2

array set pieceToLetter {
	wk K  wq Q  wr R  wb B  wn N  wp P
	bk k  bq q  br r  bb b  bn n  bp p
	e .
}

variable squareIndex {
	a1 b1 c1 d1 e1 f1 g1 h1
	a2 b2 c2 d2 e2 f2 g2 h2
	a3 b3 c3 d3 e3 f3 g3 h3
	a4 b4 c4 d4 e4 f4 g4 h4
	a5 b5 c5 d5 e5 f5 g5 h5
	a6 b6 c6 d6 e6 f6 g6 h6
	a7 b7 c7 d7 e7 f7 g7 h7
	a8 b8 c8 d8 e8 f8 g8 h8
}

array set LetterToPiece {
	K wk  Q wq  R wr  B wb  N wn  P wp
	k bk  q bq  r br  b bb  n bn  p bp
 	. e
}

set emptyBoard		"................................................................"
set standardBoard	"RNBQKBNRPPPPPPPP................................pppppppprnbqkbnr"


proc new {w size args} {
	namespace eval [namespace current]::${w} {}
	variable ${w}::Board

	array set opts {
		-relief			raised
		-bordertype		normal
		-bordercolor	{}
		-bordersize		0
		-rotate			0
		-promosign		0
		-targets			{}
		-empty			0
	}
	array set opts $args

	set Board(flip) $opts(-rotate)
	set Board(mark:promoted) $opts(-promosign)
	set Board(show:promoted) 0
	set Board(empty) $opts(-empty)
	set Board(marks) {}
	set Board(alternatives) {}
	set Board(size) $size
	set Board(data) ""
	set Board(promoted) ""
	set Board(drag:square) -1
	set Board(drag:active) 0
	set Board(drag:x) -1
	set Board(drag:y) -1
	set Board(pointer:x) -1
	set Board(pointer:y) -1
	set Board(animate) 1
	set Board(animate,piece) ""
	set Board(targets) $opts(-targets)
	set Board(bordersize) $opts(-bordersize)
	set Board(bordertype) $opts(-bordertype)
	set Board(bordercolor) $opts(-bordercolor)
	set Board(afterid) ""
   set boardSize [expr {8*$size}]
	if {!$opts(-empty)} {
		set Board(afterid) [after 50 [namespace code [list [namespace parent]::setupPieces $size]]]
	}

	set borderSize $Board(bordersize)
	if {$Board(bordertype) == "lines"} {
		set boardSize [expr {$boardSize + 2*$borderSize}]
		set borderSize 0
	}

   tk::frame $w -class Board
   tk::canvas $w.c \
		-width $boardSize \
		-height $boardSize \
		-borderwidth $borderSize \
		-relief $opts(-relief) \
		-takefocus 0 \
		;
   grid $w.c -column 0 -row 0

	$w.c xview moveto 0
	$w.c yview moveto 0

   [namespace parent]::registerSize $size
   [namespace parent]::setupSquares $size

   Build $w
	::bind $w.c <Destroy> [namespace code [list Destroy $w]]

   return $w
}


proc setPromoSign {w method} {
	variable ${w}::Board

	if {$method ne $Board(mark:promoted)} {
		set oldMethod $Board(mark:promoted)
		MakePromoImage $w $method
		set Board(mark:promoted) $method
		foreach sq $Board(promoted) {
			$w.c delete promoted:$sq
			drawPromoted $w $sq
		}
	}
}


proc showPromoted {w flag} {
	variable ${w}::Board
	set Board(show:promoted) $flag
}


proc showPromoted? {w} {
	variable ${w}::Board
	return $Board(show:promoted)
}


proc setTargets {w args} {
	variable ${w}::Board
	set Board(targets) $args
}


proc resize {w size args} {
   variable ${w}::Board

	array set opts [list -bordersize $Board(bordersize)]
	array set opts $args

	after cancel $Board(afterid)

	set oldSize $Board(size)
	set boardSize [expr {8*$size}]
	set borderSize $opts(-bordersize)

	if {$Board(bordertype) == "lines"} {
		set boardSize [expr {$boardSize + 2*$borderSize}]
		set borderSize 0
	}

	set Board(bordersize) $opts(-bordersize)

	$w.c configure -width $boardSize -height $boardSize -borderwidth $borderSize
	$w.c xview moveto 0
	$w.c yview moveto 0

	if {$size != $Board(size)} {
		DeleteImages $w
		::board::registerSize $size
		::board::setupSquares $size

		if {!$Board(empty)} {
			set Board(afterid) [after 50 [namespace code [list [namespace parent]::setupPieces $size]]]
		}
		set Board(size) $size
	}

	rebuild $w

	if {$oldSize != $Board(size)} {
		::board::unregisterSize $oldSize
	}
}


proc alignBoard {w {background {}}} {
	grid rowconfigure $w {1} -minsize 1
	if {[llength $background]} { $w configure -background $background }
}


proc bind {w args} {
	if {[llength $args] == 2} {
		::bind $w.c {*}$args
	} else {
		lassign $args sq event action

		if {$sq eq "all"} {
			for {set i 0} {$i < 64} {incr i} {
				$w.c bind input:$i $event [string map [list "%q" $i] $action]
			}
		} else {
			$w.c bind input:$sq $event [string map [list "%q" $sq] $action]
		}
	}
}


proc update {w {board {}} {promoted {}}} {
	variable ${w}::Board
	variable emptyBoard
	variable standardBoard

	set oldBoard $Board(data)
	set redraw 0

	switch -- $board {
		empty {
			set board $emptyBoard
		}

		standard {
			set board $standardBoard
		}

		flip - mirror {
			if {$board eq "mirror"} {
				set b [string reverse $oldBoard]
			} else {
				set b $oldBoard
			}
			set board ""
			set f 56
			set t 63
			while {$f >= 0} {
				append board [string range $b $f $t]
				incr f -8
				incr t -8
			}
		}

		default {
			if {[string length $board] == 0} {
				set board $Board(data)
				set promoted $Board(promoted)
				if {[string length $board] == 0} {
					set board $standardBoard
				}
				if {!$Board(empty)} { set redraw 1 }
			}
		}
	}

	set Board(data) $board

	if {$redraw || $Board(data) ne $oldBoard} {
		set size $Board(size)
		CancelAnimation $w

		# Remove all marks (incl. arrows) from the board:
		if {!$redraw} {
			set Board(marks) {}
			set Board(alternatives) {}
		}
		$w.c delete mark

		# Draw each square:
		for {set sq 0} {$sq < 64} {incr sq} {
			$w.c itemconfigure selected:$sq -state hidden
			$w.c itemconfigure suggested:$sq -state hidden
			set piece [string index $board $sq]
			if {$redraw || $piece ne [string index $oldBoard $sq]} {
				DrawPiece $w $sq $piece
			}
		}

		# Redraw marks and arrows:
		DrawAllMarks $w
		DrawAllAlternatives $w
	}

	if {$redraw || $Board(promoted) ne $promoted} {
		foreach sq $Board(promoted) {
			if {$sq ni $promoted} { $w.c delete promoted:$sq }
		}
		set Board(promoted) {}
		foreach sq $promoted {
			DrawPromoted $w $sq
			raisePiece $w $sq
		}
		RaiseInput $w
	}

	return $board
}


proc animate {w flag} {
	variable ${w}::Board
	set Board(animate) $flag
}


proc move {w list} {
	variable [namespace parent]::effects
	variable ${w}::Board

	CancelAnimation $w

	lassign $list color squareFrom squareTo squareCaptured \
		pieceFrom pieceTo pieceCaptured pieceHolding rookFrom rookTo forward

	if {$pieceTo eq " "} {
		if {$pieceFrom eq " "} { return } ;# null move
		set pieceTo "."
	}

	set Board(data) [string replace $Board(data) $squareFrom $squareFrom .]

	if {$rookFrom >= 0} {
		set Board(data) [string replace $Board(data) $rookFrom $rookFrom .]
		set Board(data) [string replace $Board(data) $rookTo $rookTo [expr {$color eq "w" ? "R" : "r"}]]
	}

	set Board(data) [string replace $Board(data) $squareTo $squareTo $pieceTo]

	if {$squareCaptured != -1 && $squareCaptured != $squareTo} {
		set Board(data) [string replace $Board(data) $squareCaptured $squareCaptured $pieceCaptured]
	}

	if {$Board(show:promoted) && $pieceFrom != $pieceTo && $squareFrom != $squareTo} {
		if {!$forward} {
			removePromoted $w $squareFrom
		} elseif {$squareFrom ni $Board(promoted)} {
			# the moving piece is a promoted piece
			lappend Board(promoted) $squareFrom
		}
	}

	if {!$Board(animate) || $effects(animation) <= 0} {
		DoMove $w $list
	} elseif {$squareFrom eq $squareTo && $rookFrom == -1} {
		variable LetterToPiece
		# use fading effect because we cannot animate
		set animation $effects(animation)
		set after [max 5 [expr {round($animation/127.0)}]]
		set Board(animate,start) [clock milliseconds]
		set Board(animate,end) [expr {$Board(animate,start) + $animation} ]
		set Board(animate,after) $after
		set Board(animate,move) $list
		set Board(animate,to) $squareTo
		set Board(animate,time) $animation
		set Board(animate,piece) ""
		if {$pieceFrom eq " "} {
			set Board(animate,opacity) 10
			DrawFadingPiece $w $squareTo $LetterToPiece($pieceTo) +1
		} else {
			set Board(animate,opacity) 254
			DrawFadingPiece $w $squareTo $LetterToPiece($pieceFrom) -1
		}
	} else {
		if {$pieceFrom != $pieceTo && [string match {[Pp]} $pieceTo]} {
			DrawPiece $w $squareFrom $pieceTo
		}

		set animation $effects(animation)
		set after [max 1 [expr {round($animation/200.0)}]]

		# Start the animation:
		if {$squareFrom != $squareTo} {
			set Board(animate,from) $squareFrom
			set Board(animate,to) $squareTo
			set Board(animate,rookFrom) $rookFrom
			raisePiece $w $squareFrom

#			if {$rookFrom >= 0} {
#				# castling w/ moving king and w/ moving rook
#				set animation [expr {$animation/2.0}]
#			}
		} elseif {$rookFrom >= 0} {
			# castling w/o moving king, move rook instead
			set Board(animate,from) $rookFrom
			set Board(animate,to) $rookTo
			set Board(animate,rookFrom) -1
			raisePiece $w $squareFrom
		} else {
			# castling w/o moving king and w/o rook
			# TODO: probably we should animate a piece swap twice times
			return
		}

		set Board(animate,start) [clock milliseconds]
		set Board(animate,end) [expr {$Board(animate,start) + $animation} ]
		set Board(animate,after) $after
		set Board(animate,move) $list
		set Board(animate,rookTo) $rookTo
		set Board(animate,time) $animation

		AnimateMove $w
	}
}


proc rotate {w} {
	variable ${w}::Board

	set Board(flip) [expr {!$Board(flip)}]
	rebuild $w
}


proc rotated? {w} {
	variable ${w}::Board
	return $Board(flip)
}


proc rebuild {w} {
	Build $w
	SetupBorders $w
	update $w
}


proc size {w} {
	variable ${w}::Board
	return $Board(size)
}


proc bordersize {w} {
	variable ${w}::Board
	return $Board(bordersize)
}


proc canvas {w} {
	return $w.c
}


# Current 64-character board string (row 0 == rank 8), as drawn.
proc data {w} {
	variable ${w}::Board
	return $Board(data)
}


proc hilite {w i which} {
	variable [namespace parent]::hilite
	variable ${w}::Board

	if {$i < 0 || $i > 63} { return }

	if {$which eq "off"} {
		$w.c itemconfigure selected:$i -state hidden
		$w.c itemconfigure suggested:$i -state hidden
	} else {
		$w.c itemconfigure $which:$i -state normal
		$w.c raise $which:$i
		$w.c raise suggested:$i
		raisePiece $w
		RaiseInput $w
	}
}


proc hilited {w which} {
	return [set ${w}::Board($which)]
}


proc clearMarks {w} {
	variable ${w}::Board

	set Board(marks) {}
	set Board(alternative) {}
	$w.c delete mark
}


proc clearAlternatives {w} {
	variable ${w}::Board

	set Board(alternative) {}
	$w.c delete alternative
	$w.c delete click
}


proc updateMarks {w marks} {
	variable ${w}::Board

	set Board(marks) $marks
	set Board(alternatives) {}
	$w.c delete mark
	DrawAllMarks $w
}


proc drawPromoted {w square} {
	DrawPromoted $w $square
	raisePiece $w $square
	RaiseInput $w
}


proc removePromoted {w square} {
	variable ${w}::Board

	$w.c delete promoted:$square

	if {[set i [lsearch -exact $Board(promoted) $square]] >= 0} {
		set Board(promoted) [lreplace $Board(promoted) $i $i]
	}
}


proc removeAllPromoted {w} {
	variable ${w}::Board

	$w.c delete promoted
	set Board(promoted) {}
}


proc promotedSquares {w} {
	variable ${w}::Board
	return $Board(promoted)
}


proc piece {w sq} {
	variable ${w}::Board
	variable LetterToPiece

	set p [string index $Board(data) $sq]
	if {$p eq " "} { return "e" }
	return $LetterToPiece([string index $Board(data) $sq])
}


proc square {name} {
	variable squareIndex
	return [lsearch -exact $squareIndex $name]
}


proc getSquare {w x y} {
	variable ${w}::Board

	if {[winfo containing $x $y] ne "$w.c"} { return -1 }

	set x [expr {int(($x - [winfo rootx $w.c])/$Board(size))}]
	set y [expr {int(($y - [winfo rooty $w.c])/$Board(size))}]

	if {$x < 0 || $y < 0 || $x > 7 || $y > 7} { return -1 }

	set sq [expr {(7 - $y)*8 + $x}]
	return [expr {$Board(flip) ? 63 - $sq : $sq}]
}


proc finishDrag {w} {
	variable ${w}::Board
	variable squareIndex

	if {$Board(drag:active)} {
		if {$Board(drag:square) != -1} {
			set sq [getSquare $w $Board(pointer:x) $Board(pointer:y)]
			lassign [$w.c coords square:$sq] x y
			if {[llength $x]} {
				# hack: for any reason the mark will not be moved with 'drag-target'
				$w.c coords promoted:$Board(drag:square) $x $y
				$w.c coords drag-target $x $y
				$w.c raise drag-target
			}
		}

		foreach t $Board(targets) { $t delete drag-target }
		$w.c dtag promoted:$Board(drag:square) drag-target
		$w.c dtag piece:$Board(drag:square) drag-target
	}

	set Board(drag:active) 0
}


proc cancelDrag {w} {
	variable ${w}::Board
	set Board(drag:square) -1
}


proc dragTarget {w} {
	variable ${w}::Board
	return [getSquare $w $Board(pointer:x) $Board(pointer:y)]
}


proc setDragSquare {w {sq -1}} {
	variable ${w}::Board

	set oldSq $Board(drag:square)

	if {$oldSq != -1} {
		DrawPiece $w $oldSq [string index $Board(data) $oldSq]
	}

	if {$sq != -1} {
		set x [expr {[winfo pointerx $w] - [winfo rootx $w.c] - $Board(size)/2}]
		set y [expr {[winfo pointery $w] - [winfo rooty $w.c] - $Board(size)/2}]

		lassign [$w.c coords square:$sq] x0 y0

		set Board(drag:x) [expr {$x - $x0}]
		set Board(drag:y) [expr {$y - $y0}]
	}

	set Board(drag:square) $sq
	set Board(drag:active) 0

	foreach t $Board(targets) { $t delete drag-target }
	$w.c dtag drag-target drag-target
}


proc raisePiece {w {square ""}} {
	variable ${w}::Board

	if {[string length $square] == 0} {
		if {$Board(mark:promoted) eq "disk"} { $w.c raise promoted }
		$w.c raise piece
		if {$Board(mark:promoted) in {bullet star}} { $w.c raise promoted }
	} else {
		if {$Board(mark:promoted) eq "disk"} { $w.c raise promoted:$square }
		$w.c raise piece:$square
		if {$Board(mark:promoted) in {bullet star}} { $w.c raise promoted:$square }
	}
}


proc isDragged? {w} {
	variable ${w}::Board
	return $Board(drag:active)
}


proc dragSquare {w} {
	variable ${w}::Board
	return $Board(drag:square)
}


proc dragPiece {w x y} {
	variable ${w}::Board

	set sq $Board(drag:square)
	if {$sq == -1} { return }

	set Board(pointer:x) $x
	set Board(pointer:y) $y

	set xc [expr {$x - [winfo rootx $w.c] - $Board(size)/2}]
	set yc [expr {$y - [winfo rooty $w.c] - $Board(size)/2}]

	if {!$Board(drag:active)} {
		lassign [$w.c coords square:$sq] x0 y0
		if {abs($x0 - $xc) > 5 || abs($y0 - $yc) > 5} {
			set Board(drag:active) 1
			$w.c addtag drag-target withtag promoted:$sq
			$w.c addtag drag-target withtag piece:$sq

			if {[llength $Board(targets)]} {
				set piece [piece $w $sq]
				set img photo_Piece($piece,$Board(size))
				foreach t $Board(targets) {
					$t create image 0 0 -image $img -tag drag-target -anchor center
				}
			}
		}
	}

	if {$Board(drag:x) != -1 && $Board(drag:y) != -1} {
		set dx $Board(drag:x)
		set dy $Board(drag:y)
	} else {
		lassign {0 0} dx dy
	}

	set x0 [expr {$xc - $dx}]
	set y0 [expr {$yc - $dy}]

	$w.c coords promoted:$sq $x0 $y0
	$w.c coords piece:$sq $x0 $y0
	$w.c raise drag-target

	if {[llength $Board(targets)]} {
		foreach t $Board(targets) {
			set x1 [expr {$x - [winfo rootx $t] - $dx}]
			set y1 [expr {$y - [winfo rooty $t] - $dy}]
			$t coords drag-target $x1 $y1
		}
	}
}


proc setPiece {w sq piece} {
	variable ${w}::Board

	set Board(data) [string replace $Board(data) $sq $sq $piece]
	DrawPiece $w $sq $piece
	return $Board(data)
}


proc setSign {w square} {
	variable [namespace parent]::square::style
	variable ${w}::Board

	makeHiliteRect $w.c sign $square $Board(size) {*}[$w.c coords square:$square] $style(hilite,selected)

	RaiseSign $w
	raisePiece $w
	RaiseInput $w
}


proc eraseSign {w square} {
	$w.c delete sign:$square
}


proc makeHiliteRect {canv which tag size x1 y1 {color {}}} {
	variable [namespace parent]::square::style
	variable [namespace parent]::hilite

	set x1 [int $x1]
	set y1 [int $y1]
	set x2 [expr {$x1 + $size}]
	set y2 [expr {$y1 + $size}]

	incr x1 [int $style(borderline,gap)]
	incr y1 [int $style(borderline,gap)]

	if {[llength $color] == 0} {
		set outline $hilite($which)
		set color $style(hilite,$which)
		set tags [list hilite rect $which:$tag]
		set state hidden
	} else {
		set outline 0
		set tags [list mark rect $which:$tag]
		set state normal
		incr x1
		incr y1
		incr x2 -1
		incr y2 -1
	}

	if {$outline > 0} {
		set inc1 $outline
		set inc2 $outline
		if {$inc1 % 2} {
			incr inc1 -1
			incr inc2
		}
		set inc1 [expr {$inc1/2}]
		set inc2 [expr {$inc2/2}]
		incr x1 $inc1; incr x2 -$inc2
		incr y1 $inc1; incr y2 -$inc2
		$canv create rectangle $x1 $y1 $x2 $y2 \
			-tags $tags -width $outline -outline $color -state $state
	} else {
		incr x1 [abs $outline]
		incr y1 [abs $outline]
		incr x2 $outline
		incr y2 $outline
		$canv create rectangle $x1 $y1 $x2 $y2 -tags $tags -width 0 -fill $color -state $state
	}

	return $which:$tag
}


proc drawBorderlines {border wd {ht 0}} {
	if {$ht <= 0} { set ht $wd }

	foreach n {0 1 2} {
		set hl photo_Borderline(hl$n:$border)
		set vl photo_Borderline(vl$n:$border)
		set hd photo_Borderline(hd$n:$border)
		set vd photo_Borderline(vd$n:$border)

		catch { image delete $hl }
		catch { image delete $vl }
		catch { image delete $hd }
		catch { image delete $vd }

		image create photo $hl -width [expr {$wd - 2*$n - 1}] -height 1
		image create photo $vl -width 1 -height [expr {$ht - 2*$n - 2}]
		image create photo $hd -width [expr {$wd - 2*$n}] -height 1
		image create photo $vd -width 1 -height [expr {$ht - 2*$n - 1}]

		$hl copy photo_Borderline(horz,lite,$n)
		$vl copy photo_Borderline(vert,lite,$n)
		$hd copy photo_Borderline(horz,dark,$n)
		$vd copy photo_Borderline(vert,dark,$n)

		$border create image $n $n -anchor nw -image $hl -tag shadow
		$border create image $n [expr {$n + 1}] -anchor nw -image $vl -tag shadow
		$border create image $n [expr {$ht - $n - 1}] -anchor nw -image $hd -tag shadow
		$border create image [expr {$wd - $n - 1}] $n -anchor nw -image $vd -tag shadow
	}
}


proc drawText {canv squareSize color x y text} {
	if {$text eq "-"} { set text "\u2212" }
	set size [expr {int(double($squareSize)*0.6 + 0.5)}]
	if {$squareSize % 2} { incr size }
	set x0 [expr {$x + $squareSize/2}]
	set y0 [expr {$y + $squareSize/2}]
	scan [::colors::getActualColor $color] "\#%2x%2x%2x" r g b
	set luma	[expr {$r*0.2125 + $g*0.7154 + $b*0.0721}]
	set font [list [font configure TkFixedFont -family] $size bold]
	set x1 [expr {$x0 + 1}]
	set y1 [expr {$y0 + 1}]
	set tags {mark text}
	if {$luma < 50} {
		$canv create text $x0 $y0 -fill white  -font $font -text $text -anchor center -tags $tags
		$canv create text $x1 $y1 -fill $color -font $font -text $text -anchor center -tags $tags
	} else {
		$canv create text $x1 $y1 -fill black  -font $font -text $text -anchor center -tags $tags
		$canv create text $x0 $y0 -fill $color -font $font -text $text -anchor center -tags $tags
	}
}


proc drawFull {canv squareSize color x y {tag tag}} {
	makeHiliteRect $canv rect $tag $squareSize $x $y $color
}


proc drawSquare {canv squareSize color x y} {
	SetImage $canv $squareSize $x $y [MakeSquare $squareSize $color]
}


proc drawCircle {canv squareSize color x y} {
	SetImage $canv $squareSize $x $y [MakeCircle $squareSize $color]
}


proc drawDisk {canv squareSize color x y} {
	SetImage $canv $squareSize $x $y [MakeDisk $squareSize $color]
}


proc drawAlternative {w from to color cmd} {
	variable ${w}::Board

	if {$from == $to} { return }

	set i [llength $Board(alternatives)]
	lappend Board(alternatives) [list $from $to $color $i]

	set size $Board(size)
	set rows [expr {$to/8 - $from/8}]
	set cols [expr {$to%8 - $from%8}]
	set img [DrawArrow $w $from $to $color $i]
	set cmdEnter [namespace code [list HiliteArrow $w $rows $cols $color $i click]]
	set cmdLeave [namespace code [list HiliteArrow $w $rows $cols $color $i alternative]]

	$w.c bind alt:$i <ButtonPress-1> $cmd
	$w.c bind alt:$i <Enter> $cmdEnter
	$w.c bind alt:$i <Leave> $cmdLeave
	$w.c raise click
}


proc RaiseInput {w} {
	$w.c raise text
	$w.c raise arrow
	$w.c raise alternative
	$w.c raise input
	$w.c raise click
}


proc RaiseSign {w} {
	$w.c raise rect
	$w.c raise mark
	$w.c raise hilite
	$w.c raise sign
}


proc HiliteArrow {w rows cols color index type} {
	variable ${w}::Board

	set size $Board(size)

	if {![info exists Board(image,$type,$rows,$cols,$size,$color)]} {
		if {$type eq "click"} { set hilite [::colors::makeHiliteColor $color] } else { set hilite $color }
		set Board(image,$type,$rows,$cols,$size,$color) [MakeArrow $size $rows $cols $hilite click]
	}

	$w.c itemconfigure alternative:$index -image $Board(image,$type,$rows,$cols,$size,$color)
}


proc DrawPiece {w sq piece} {
	variable LetterToPiece
	variable ${w}::Board

	set piece $LetterToPiece($piece)
	set promoted [$w.c find withtag promoted:$sq]
	$w.c delete piece:$sq promoted:$sq

	if {$piece ne "e"} {
		$w.c create image {*}[$w.c coords square:$sq] \
			-image photo_Piece($piece,$Board(size)) \
			-anchor nw \
			-tags [list piece piece:$sq] \
			;
		if {[string length $promoted]} { DrawPromoted $w $sq }
		RaiseInput $w
	}
}



proc DrawPromoted {w square} {
	variable ${w}::Board

	if {$Board(mark:promoted) ne "none" && [string length [$w.c find withtag promoted:$square]] == 0} {
		lassign [$w.c coords square:$square] x y
		set tags [list promoted promoted:$square]
		set img [MakePromoImage $w]
		$w.c create image $x $y -anchor nw -image $img -tags $tags
	}

	if {$square ni $Board(promoted)} { lappend Board(promoted) $square }
}


proc Build {w} {
	variable ${w}::Board

	set size $Board(size)
	set flip $Board(flip)
	set offs [expr {$Board(bordertype) == "lines" ? $Board(bordersize) : 0}]

	for {set i 0} {$i < 64} {incr i} {
		set row [expr {$i/8}]
		set col [expr {$i%8}]
		set x [expr {$col*$size + $offs}]
		set y [expr {(7 - $row)*$size + $offs}]
		set k [expr {$flip ? 63 - $i : $i}]
		set color [expr {($row + $col) % 2 ? "lite" : "dark"}]
		$w.c delete square:$k selected:$k suggested:$k input:$k
		$w.c create image $x $y -anchor nw -image photo_Square($color,$size) -tag square:$k
		$w.c create rectangle $x $y [expr {$x + $size}] [expr {$y + $size}] \
			-tag mark:$k -width 0 -state hidden
		makeHiliteRect $w.c selected $k $size $x $y
		makeHiliteRect $w.c suggested $k $size $x $y
		$w.c create rectangle $x $y [expr {$x + $size}] [expr {$y + $size}] \
			-tags [list input input:$k] \
			-outline {} \
			;
	}
}


proc SetupBorders {w} {
	variable ${w}::Board

	$w.c delete borderline
	if {$Board(bordertype) ne "lines"} { return }
	set borderSize $Board(bordersize)
	set boardSize [expr {8*$Board(size) + 2*$borderSize}]
	set bordercolor $Board(bordercolor)
	if {[string length $bordercolor] == 0} { set bordercolor #4f4f4f }

	for {set i 0; set bs [expr {$boardSize - 1}]} {$i < $borderSize} {incr i; decr bs} {
		$w.c create line $i $bs $boardSize $bs -width 1 -fill $bordercolor -tag borderline
		$w.c create line $bs [expr {$i + 1}] $bs $boardSize -width 1 -fill $bordercolor -tag borderline
	}
}


# The diagram is going away: the widget is destroyed, its per-widget namespace
# holds everything the diagram knows about it, and every deferred script still
# holding the widget path has to die with the widget (see AnimateMove and
# DrawFadingPiece).
#
# A move animation is scheduled a few milliseconds apart and reads the Board
# array through `variable ${w}::Board`: a pane hidden while a piece is still
# fading fired that timer into the namespace deleted below and surfaced as
# "can't access ...::Board: parent namespace doesn't exist" in ::scidb::bgerror.
# Cancelling here stops the next tick; the callbacks' own namespace-exists
# guard stops a tick that is already queued in the event loop, which
# `after cancel` can no longer reach.
proc Destroy {w} {
	# <Destroy> can arrive more than once for the same widget (the binding
	# carries this path), so do not resurrect a namespace already deleted.
	if {![namespace exists $w]} { return }
	variable ${w}::Board

	after cancel $Board(afterid)
	if {[info exists Board(animate,afterid)]} {
		after cancel $Board(animate,afterid)
		unset Board(animate,afterid)
	}
	DeleteImages $w
	[namespace parent]::unregisterSize $Board(size)
	namespace delete [namespace current]::${w}
}


proc DeleteImages {w} {
	variable ${w}::Board

	if {[string length $Board(animate,piece)]} {
		image delete $Board(animate,piece)
		set Board(animate,piece) ""
	}

	foreach name [array names Board -glob image,*] {
		image delete $Board($name)
	}

	array unset Board image,*
}


proc DoMove {w list} {
	variable ${w}::Board

	lassign $list color squareFrom squareTo squareCaptured \
		pieceFrom pieceTo pieceCaptured pieceHolding rookFrom rookTo forward

	if {$Board(show:promoted) && $forward && $squareCaptured != -1} {
		# we have to remove a possible promotion mark
		removePromoted $w $squareCaptured
	}

	if {$squareFrom != $squareTo} {
		DrawPiece $w $squareFrom .
	}

	if {$rookFrom != $rookTo} {
		DrawPiece $w $rookFrom .
		DrawPiece $w $rookTo [expr {$color eq "w" ? "R" : "r"}]
	}

	if {$pieceTo ne " "} {
		DrawPiece $w $squareTo $pieceTo
	}

	if {$squareCaptured != -1 && $squareCaptured != $squareTo} {
		DrawPiece $w $squareCaptured $pieceCaptured
	}

	if {$Board(show:promoted)} {
		if {	$squareFrom in $Board(promoted)
			|| (	$pieceFrom != $pieceTo
				&& $pieceTo ne " "
				&& [string match {[Pp]} $pieceFrom])} {
			# 1. move promotion marker to new piece position, or
			# 2. mark newly promoted piece
			removePromoted $w $squareFrom
			DrawPromoted $w $squareTo
			raisePiece $w $squareTo
		}

		if {	!$forward
			&& $pieceCaptured != $pieceHolding
			&& $pieceCaptured != "."
			&& [string match {[Pp]} $pieceHolding]
			&& ![string match {[Pp]} $pieceCaptured]} {
			# take back capture of promoted piece
			DrawPromoted $w $squareFrom
			raisePiece $w $squareFrom
		}
	}

	RaiseInput $w
}


proc DrawFadingPiece {w sq piece dir} {
	# Same guard as AnimateMove: this runs from an `after` script holding the
	# widget path, and the widget (with its namespace) may already be gone.
	if {![namespace exists $w]} { return }
	variable ${w}::Board
	variable pieceToLetter

	if {![winfo exists $w.c]} { return }

	set end $Board(animate,end)
	set now [clock milliseconds]

	if {$now >= $end || ($dir == 1 ? $Board(animate,opacity) >= 255 : $Board(animate,opacity) < 10)} {
		if {$dir == 1} {
			DrawPiece $w $sq $pieceToLetter($piece)
		} else {
			$w.c delete piece:$sq
		}
		unset Board(animate,afterid)
	} else {
		set to $Board(animate,to)
		set start $Board(animate,start)

		if {[string length $Board(animate,piece)] == 0} {
			set img photo_Piece($piece,$Board(size))
			set Board(animate,piece) \
				[image create photo -width [image width $img] -height [image height $img]]
			$w.c delete piece:$sq
			$w.c create image {*}[$w.c coords square:$sq] \
				-image $Board(animate,piece) -anchor nw -tag piece:$sq
			raisePiece $w $sq
			RaiseInput $w
		}

		::scidb::tk::image disable \
			photo_Piece($piece,$Board(size)) \
			$Board(animate,piece) \
			[expr {round($Board(animate,opacity))}] \
			;

		# Compute next alpha value:
		set ratio [expr {double($now - $start)/double($end - $start)}]
		if {$dir == 1} {
			set Board(animate,opacity) [expr {10 + $ratio*244}]
		} else {
			set Board(animate,opacity) [expr {255 - $ratio*244}]
		}

		# Schedule another animation update in a few milliseconds:
		set Board(animate,afterid) \
			[after $Board(animate,after) [namespace code [list DrawFadingPiece $w $sq $piece $dir]]]
	}
}


proc AnimateMove {w} {
	if {![namespace exists $w]} { return }
	variable ${w}::Board

	if {![winfo exists $w.c]} { return }

	set end $Board(animate,end)
	set now [clock milliseconds]

	if {$now >= $end} {
		if {$Board(animate,rookFrom) < 0} {
			DoMove $w $Board(animate,move)
			unset Board(animate,afterid)
			return
		}

		# place king at right place
		$w.c coords piece:$Board(animate,from) {*}[$w.c coords square:$Board(animate,to)]

		# start rook animation (in case of castling)
		set Board(animate,start) $now
		set Board(animate,from) $Board(animate,rookFrom)
		set Board(animate,to) $Board(animate,rookTo)
		set Board(animate,end) [expr {$Board(animate,end) + $Board(animate,time)} ]
		set Board(animate,rookFrom) -1
		set Board(animate,rookTo) -1
		raisePiece $w $Board(animate,from)
	} else {
		set from $Board(animate,from)
		set to $Board(animate,to)
		set start $Board(animate,start)

		# Compute where the moving piece should be displayed and move it:
		set ratio [expr {double($now - $start)/double($end - $start)}]
		lassign [$w.c coords square:$from] fromX fromY
		lassign [$w.c coords square:$to] toX toY
		set x [expr {$fromX + round(($toX - $fromX)*$ratio)}]
		set y [expr {$fromY + round(($toY - $fromY)*$ratio)}]
		$w.c coords promoted:$from $x $y
		$w.c coords piece:$from $x $y
	}

	# Schedule another animation update in a few milliseconds:
	set Board(animate,afterid) [after $Board(animate,after) [namespace code [list AnimateMove $w]]]
}


proc CancelAnimation {w} {
	variable ${w}::Board

	if {[string length $Board(animate,piece)]} {
		image delete $Board(animate,piece)
		set Board(animate,piece) ""
	}

	if {[info exists Board(animate,afterid)]} {
		after cancel $Board(animate,afterid)
		unset Board(animate,afterid)
		DoMove $w $Board(animate,move)
	}
}


proc DrawAllMarks {w} {
	variable ${w}::Board

	foreach mark $Board(marks) {
		lassign [split $mark ,] cmd type sq sq2 color
		set square [square $sq]
		switch $type {
			full		{ DrawFull $w $square $color }
			square	{ DrawSquare $w $square $color ;# Scid does not use 'square' }
			arrow		{ DrawArrow $w $square [square $sq2] $color }
			circle	{ DrawCircle $w $square $color }
			disk		{ DrawDisk $w $square $color }
			default	{ DrawText $w $type $square $color }
		}
	}

	RaiseSign $w
	raisePiece $w
	RaiseInput $w
}


proc DrawAllAlternatives {w} {
	variable ${w}::Board

	foreach alt $Board(alternatives) { DrawArrow $w {*}$alt }
	$w.c raise alternative
	$w.c raise click
}


proc DrawText {w text square color} {
	drawText $w.c [set ${w}::Board(size)] $color {*}[$w.c coords square:$square] $text
}


proc DrawFull {w square color} {
	drawFull $w.c [set ${w}::Board(size)] $color {*}[$w.c coords square:$square] $square
}


proc SetImage {canv squareSize x y img {tags {}}} {
	set size [image width $img]
	set x [expr {$x + ($squareSize - $size)/2}]
	set y [expr {$y + ($squareSize - $size)/2}]
	$canv create image $x $y -anchor nw -image $img -tags [list mark {*}$tags]
}


proc MakeSquare {squareSize color} {
	variable Rectangle

	set size [expr {int(double($squareSize)*0.8 + 0.5)}]
	if {($squareSize % 2) != ($size % 2)} { incr size }
	set img [image create photo -width $size -height $size]
	set svg [string map [list \#c# $color] $Rectangle]
	::scidb::tk::image create svg $img
	::scidb::tk::image alpha 0.8 $img -composite overlay
	return $img
}


proc DrawSquare {w square color {tags {}}} {
	variable ${w}::Board

	if {![info exists Board(image,square,$Board(size),$color)]} {
		set Board(image,square,$Board(size),$color) [MakeSquare $Board(size) $color]
	}

	SetImage $w.c $Board(size) {*}[$w.c coords square:$square] \
		$Board(image,square,$Board(size),$color) $tags
}


proc MakePromoImage {w {method ""}} {
	variable ${w}::Board

	if {[string length $method] == 0} { set method $Board(mark:promoted) }
	set size $Board(size)
	set create 0

	if {[info exists Board(image,marker)]} {
		set img $Board(image,marker)
		if {$method eq "none"} {
			image delete $Board(image,marker)
			unset Board(image,marker)
			return
		}
		set create [expr {$method ne $Board(mark:promoted)}]
	} else {
		set img [image create photo -width $size -height $size]
		set Board(image,marker) $img
		set create 1
	}

	if {$create} {
		$img blank

		switch $method {
			bullet {
				$img copy $::board::icon::12x12::marker -to 2 [expr {$size - 14}] 14 [expr {$size - 2}]
			}
			star {
				set s [expr {($size*2)/5}]
				if {$s % 2 == 0} { incr s }
				set star [image create photo -width $s -height $s]
				::scidb::tk::image create [namespace current]::Star $star
				set x1 [expr {($size - $s)/2}]
				set y1 [expr {$size - $s - 2}]
				$img copy $star -to $x1 $y1 [expr {$x1 + $s}] [expr {$y1 + $s}]
			}
			disk {
				variable Disk
				set tmp [image create photo -width [image width $Disk] -height [image height $Disk]]
				::scidb::tk::image copy $Disk $tmp
				::scidb::tk::image colorize orange 0.7 $tmp
				::scidb::tk::image copy $tmp $img
				image delete $tmp
				#::scidb::tk::image alpha 0.9 $img -composite overlay
			}
		}
	}

	return $img
}


proc MakeCircle {squareSize color} {
	variable Circle

	set size [expr {int(double($squareSize)*0.8 + 0.5)}]
	if {($squareSize % 2) != ($size % 2)} { incr size }
	set tmp [image create photo -width [image width $Circle] -height [image height $Circle]]
	$tmp copy $Circle
	::scidb::tk::image colorize $color 0.7 $tmp
	set img [image create photo -width $size -height $size]
	::scidb::tk::image copy $tmp $img
	::scidb::tk::image alpha 0.8 $img -composite overlay
	image delete $tmp
	return $img
}


proc DrawCircle {w square color} {
	variable ${w}::Board

	if {![info exists Board(image,circle,$Board(size),$color)]} {
		set Board(image,circle,$Board(size),$color) [MakeCircle $Board(size) $color]
	}
	SetImage $w.c $Board(size) {*}[$w.c coords square:$square] $Board(image,circle,$Board(size),$color)
}


proc MakeDisk {squareSize color} {
	variable Disk

	set size [expr {int(double($squareSize)*0.8 + 0.5)}]
	if {($squareSize % 2) != ($size % 2)} { incr size }
	set tmp [image create photo -width [image width $Disk] -height [image height $Disk]]
	$tmp copy $Disk
	::scidb::tk::image colorize $color 0.7 $tmp
	set img [image create photo -width $size -height $size]
	::scidb::tk::image copy $tmp $img
	::scidb::tk::image alpha 0.8 $img -composite overlay
	image delete $tmp
	return $img
}


proc DrawDisk {w square color} {
	variable ${w}::Board

	if {![info exists Board(image,disk,$Board(size),$color)]} {
		set Board(image,disk,$Board(size),$color) [MakeDisk $Board(size) $color]
	}
	SetImage $w.c $Board(size) {*}[$w.c coords square:$square] $Board(image,disk,$Board(size),$color)
}


proc DrawArrow {w from to color {index -1}} {
	variable ${w}::Board

	if {$from == $to} { return }

	if {$index >= 0} { set type alternative } else { set type arrow }

	set size $Board(size)
	set sizh [expr {$size/2}]
	set sizq [expr {$size/4}]
	set rows [expr {$to/8 - $from/8}]
	set cols [expr {$to%8 - $from%8}]

	if {$Board(flip)} {
		set cols [expr {-$cols}]
		set rows [expr {-$rows}]
	}

	if {![info exists Board(image,$type,$rows,$cols,$size,$color)]} {
		set Board(image,$type,$rows,$cols,$size,$color) [MakeArrow $size $rows $cols $color $type]
	}

	lassign [$w.c coords square:$from] x1 y1
	lassign [$w.c coords square:$to  ] x2 y2
	set x0 [expr {int(min($x1, $x2))}]
	set y0 [expr {int(min($y1, $y2))}]
	if {$cols} { incr x0 $sizh }
	if {$rows} { incr y0 $sizh }

	set img $Board(image,$type,$rows,$cols,$size,$color)
	set tags [list mark $type]

	incr x0 [expr {-([image width  $img] - [expr {max(1, [abs $cols])*$size}])/2}]
	incr y0 [expr {-([image height $img] - [expr {max(1, [abs $rows])*$size}])/2}]

	if {$type eq "alternative"} {
		set iw [image width  $img]
		set ih [image height $img]
		set ah [expr {min(33.0/$size, max(0.5, 12.0/$size))}]	;# arrowhead width (= ah*size)
		set as [expr {int(0.5*$ah*$size + 0.5)}]

		set opts [list -tags [list mark click alt:$index] -width 4 -outline {} -fill {}]

		if {$cols == 0 || $rows == 0} {
			if {$cols == 0} {
				set dw [expr {max(0,($iw - $as)/2 - 2)}]
				set x1 [expr {$x0 + $dw}]
				set x2 [expr {$x0 + $iw - $dw}]
				set y1 $y0
				set y2 [expr {$y0 + $ih}]
			} else {
				set dh [expr {max(0,($ih - $as)/2 - 2)}]
				set x1 $x0
				set x2 [expr {$x0 + $iw}]
				set y1 [expr {$y0 + $dh}]
				set y2 [expr {$y0 + $ih - $dh}]
			}
			$w.c create rectangle $x1 $y1 $x2 $y2 {*}$opts
		} else {
			if {($rows > 0) == ($cols > 0)} {
				set x1 [expr {$x0 + $iw}]
				set y1 [expr {$y0 + $as}]
				set x2 [expr {$x0 + $iw - $as}]
				set y2 $y0
				set x3 $x0
				set y3 [expr {$y0 + $ih - $as}]
				set x4 [expr {$x0 + $as}]
				set y4 [expr {$y0 + $ih}]
			} else {
				set x1 $x0
				set y1 [expr {$y0 + $as}]
				set x2 [expr {$x0 + $as}]
				set y2 $y0
				set x3 [expr {$x0 + $iw}]
				set y3 [expr {$y0 + $ih - $as}]
				set x4 [expr {$x0 + $iw - $as}]
				set y4 [expr {$y0 + $ih}]
			}
			$w.c create polygon $x1 $y1 $x2 $y2 $x3 $y3 $x4 $y4 {*}$opts
		}

		lappend tags alternative:$index
	}

	$w.c create image $x0 $y0 -anchor nw -image $img -tags $tags
}


proc MakeArrow {size rows cols color type} {
	set ncols [abs $cols]
	set nrows [abs $rows]
	set length [expr {$size*(max($nrows,$ncols)) - $size/4}]

	set rot [geometry::rad2deg [atan2 $cols $rows]]
	set deg $rot
	if {$deg <   0.0} { set deg [expr {$deg + 360.0}] }
	if {$deg > 180.0} { set deg [expr {$deg - 180.0}] }
	if {$deg >  90.0} { set deg [expr {$deg -  90.0}] }
	if {$deg >  45.0} { set deg [expr {90.0 -  $deg}] }
	set scalef [expr {1.0/cos([geometry::deg2rad $deg])}]

	###########################
	#                         #
	#   ^   ^       x         #
	#   |   |      / \        #
	#   |  hh     /   \       #
	#   |   |    /     \      #
	#  th   v   +-+   +-+     #
	#   |   ^     |   |       #
	#   |   |     |   |       #
	#   |  sh     |   |       #
	#   |   |     |   |       #
	#   v   v     +---+       #
	#             <--->   sw  #
	#           <-------> hw  #
	#                         #
	###########################
	switch $type {
		arrow {
			set ah [expr {min(22.0/$size, max(0.3, 8.0/$size))}]	;# arrowhead width (= ah*size)
			set op 0.8	;# opacity
			set as 0.4	;# arrow shaft ratio (shaft width = as*width)
		}
		alternative {
			set ah [expr {min(33.0/$size, max(0.45, 12.0/$size))}]	;# arrowhead width (= ah*size)
			set op 0.75	;# opacity
			set as 0.5	;# arrow shaft ratio (shaft width = as*width)
		}
		click {
			set ah [expr {min(33.0/$size, max(0.45, 12.0/$size))}]	;# arrowhead width (= ah*size)
			set op 1.0	;# opacity
			set as 0.5	;# arrow shaft ratio (shaft width = as*width)
		}
	}
	set sf 1.0	;# stroke width factor
	set ar 0.6	;# arrow head ratio (height = ar*width)

	# we do a small correction to reduce an optical illusion
	if {$rows == 0 || $cols == 0} { set as [expr {1.05*$as}] }

	set hw 100.0
	set sw [expr {$hw*$as}]
	set hh [expr {$ar*$hw}]
	set th [expr {($length*$scalef*$hw)/($size*$ah)}]
	set sh [expr {$th - $hh}]

	set strokeWidth [expr {0.05*$hw*$sf}]
	set opacity $op

	set p(0,x) 0					; set p(0,y) -$hh
	set p(1,x) [expr {-$hw/2}]	; set p(1,y) 0
	set p(2,x) [expr {-$sw/2}]	; set p(2,y) 0
	set p(3,x) [expr {-$sw/2}]	; set p(3,y) $sh
	set p(4,x) [expr {+$sw/2}]	; set p(4,y) $sh
	set p(5,x) [expr {+$sw/2}]	; set p(5,y) 0
	set p(6,x) [expr {+$hw/2}]	; set p(6,y) 0

	set offs [expr {1.4142135624*($hh + $strokeWidth)}]
	for {set i 0} {$i < 7} {incr i} { set p($i,y) [expr {$p($i,y) + $offs}] }

	set delta [expr {(0.4*$hw)/$strokeWidth}]
	set q01 [geometry::translation $p(0,x) $p(0,y) $p(1,x) $p(1,y) +$delta $delta]
	set q06 [geometry::translation $p(0,x) $p(0,y) $p(6,x) $p(6,y) -$delta $delta]
	set q12 [list $p(1,x) [expr {$p(1,y) - $delta}] $p(2,x) [expr {$p(2,y) - $delta}]]
	set q56 [list $p(5,x) [expr {$p(5,y) - $delta}] $p(6,x) [expr {$p(6,y) - $delta}]]

	lassign [geometry::intersection $q01 $q06] q(0,x) q(0,y)
	lassign [geometry::intersection $q01 $q12] q(1,x) q(1,y)
	set q(2,x) [expr {$p(3,x) + $delta}]; set q(2,y) [expr {$p(2,y) - $delta}]
	set q(3,x) [expr {$p(3,x) + $delta}]; set q(3,y) [expr {$p(3,y) - $delta}]
	set q(4,x) [expr {$p(4,x) - $delta}]; set q(4,y) [expr {$p(4,y) - $delta}]
	set q(5,x) [expr {$p(5,x) - $delta}]; set q(5,y) [expr {$p(5,y) - $delta}]
	lassign [geometry::intersection $q06 $q56] q(6,x) q(6,y)

	scan [::colors::getActualColor $color] "\#%2x%2x%2x" r g b
	set lite [list $r $g $b]
	lassign [::colors::rgb2hsv {*}$lite] h s v
	set dark [::colors::hsv2rgb $h $s [expr {min(1.0,$v*0.70)}]]
	set lite [format "#%02x%02x%02x" {*}$lite]
	set dark [format "#%02x%02x%02x" {*}$dark]

	if {$type eq "arrow"} {
		set edge [::colors::hsv2rgb $h $s [expr {min(1.0,$v*0.15)}]]
		set edge [format "#%02x%02x%02x" {*}$edge]
	} else {
		set edge #000000
	}

	append svg "<svg>"
	append svg "<defs>"
	append svg "<linearGradient id=\"linearGradient1683\">"
	append svg "<stop offset=\"0.0000000\" style=\"stop-color:$lite;stop-opacity:$opacity\"/>"
	append svg "<stop offset=\"1.0000000\" style=\"stop-color:$dark;stop-opacity:$opacity\"/>"
	append svg "</linearGradient>"
	append svg "<linearGradient id=\"linearGradient1694\">"
	append svg "<stop offset=\"0\" style=\"stop-color:#ffffff;stop-opacity:[expr {0.3*$opacity}]\"/>"
	append svg "<stop offset=\"1\" style=\"stop-color:#ffffff;stop-opacity:0.0\"/>"
	append svg "</linearGradient>"
	append svg "<linearGradient id=\"down-top-1683\" x1=\"0%\" y1=\"100%\" x2=\"0%\" y2=\"0%\" "
	append svg "xlink:href=\"#linearGradient1683\"/>"
	append svg "<linearGradient id=\"top-down-1694\" x1=\"0%\" y1=\"0%\" x2=\"0%\" y2=\"100%\" "
	append svg "xlink:href=\"#linearGradient1694\"/>"
	append svg "</defs>"
	append svg "<g>"
	append svg "<path d=\""
	append svg "M $p(0,x),$p(0,y)"
	append svg "L $p(1,x),$p(1,y)"
	append svg "L $p(2,x),$p(2,y)"
	append svg "L $p(3,x),$p(3,y)"
	append svg "L $p(4,x),$p(4,y)"
	append svg "L $p(5,x),$p(5,y)"
	append svg "L $p(6,x),$p(6,y)"
	append svg "z\" style=\""
	append svg "fill:url(#down-top-1683);fill-opacity:$opacity;stroke:$edge;"
	append svg "stroke-width:$strokeWidth;stroke-linecap:butt;stroke-linejoin:round;"
	append svg "stroke-miterlimit:[expr {$strokeWidth/2.0}];stroke-opacity:$opacity"
	append svg "\"/>"
	append svg "<path d=\""
	append svg "M $q(0,x),$q(0,y)"
	append svg "L $q(1,x),$q(1,y)"
	append svg "L $q(2,x),$q(2,y)"
	append svg "L $q(3,x),$q(3,y)"
	append svg "L $q(4,x),$q(4,y)"
	append svg "L $q(5,x),$q(5,y)"
	append svg "L $q(6,x),$q(6,y)"
	append svg "z\" style=\""
	append svg "fill:url(#top-down-1694);fill-opacity:$opacity;stroke:none;"
	append svg "stroke-width:$strokeWidth;stroke-linecap:butt;stroke-linejoin:round;"
	append svg "stroke-miterlimit:[expr {$strokeWidth/2.0}];stroke-opacity:$opacity"
	append svg "\"/>"
	append svg "</g>"
	append svg "</svg>"

	set img [image create photo -width $length -height $length]
	# NOTE: for any reason the resulting arrow is not anti-aliased
	::scidb::tk::image create svg $img -scale $scalef -rotate $rot

	if {$ncols != $nrows} {
		set w [expr {min($length, int(1.2*max(1, $ncols)*$size + 0.5))}]
		set h [expr {min($length, int(1.2*max(1, $nrows)*$size + 0.5))}]
		set x [expr {($length - $w)/2}]
		set y [expr {($length - $h)/2}]
		set fin [image create photo -width $w -height $h]
		$fin copy $img -from $x $y [expr {$x + $w}] [expr {$y + $h}]
		image delete $img
		set img $fin
	}

	return $img
}

namespace eval geometry {

namespace import ::tcl::mathfunc::atan2

proc rad2deg {a} { return [expr {$a*57.29577951308232311}] }
proc deg2rad {a} { return [expr {$a*0.01745329251994329509}] }
proc signum  {x} { return [expr {$x < 0 ? -1 : ($x > 0 ? +1 : 0)}] }


proc translation {x1 y1 x2 y2 dx dy} {
	set rot [atan2 [expr {abs($x2 - $x1)}] [expr {abs($y2 - $y1)}]]
	set vx [expr {cos($rot)*$dx}]
	set vy [expr {sin($rot)*$dy}]
	set x1 [expr {$x1 + $vx}]
	set y1 [expr {$y1 + $vy}]
	set x2 [expr {$x2 + $vx}]
	set y2 [expr {$y2 + $vy}]
	return [list $x1 $y1 $x2 $y2]
}


proc intersection {slope1 slope2} {
	lassign $slope1 px py qx qy
	lassign $slope2 ux uy vx vy

	set a1 [expr {$qy - $py}]
	set b1 [expr {$px - $qx}]
	set c1 [expr {$qx*$py - $px*$qy}]
	set r3 [expr {$a1*$ux + $b1*$uy + $c1}]
	set r4 [expr {$a1*$vx + $b1*$vy + $c1}]
	set a2 [expr {$vy - $uy}]
	set b2 [expr {$ux - $vx}]
	set c2 [expr {$vx*$uy - $ux*$vy}]
	set dm [expr {$a1*$b2 - $a2*$b1}]
	set of [expr {abs($dm)/2.0}]
	set x0 [expr {$b1*$c2 - $b2*$c1}]
	set y0 [expr {$a2*$c1 - $a1*$c2}]
	set x1 [expr {($x0 + [signum $x0]*$of)/$dm}]
	set y1 [expr {($y0 + [signum $y0]*$of)/$dm}]

	return [list $x1 $y1]
}

} ;# namespace geometry

set Circle [image create photo -data {
	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
}]

set Disk [image create photo -data {
	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
	QtGjIQAAAABJRU5ErkJggg==
}]

# NOTE: an alternative for Rectangle
#set Square [image create photo -data {
#iVBORw0KGgoAAAANSUhEUgAAAJYAAACWCAYAAAA8AXHiAAAAR3RFWHRMaWNlbnNlAE9yaWdpbmFs
#IENoZXNzd2l6IGFydHdvcmssIDIwMjYuIEdQTC0yLjAtb3ItbGF0ZXI7IHNlZSBDT1BZSU5HLoC6
#vgkAAAP4SURBVHic7djBahtXFIfxc+/MqLFEvElpGvIEjrNulW3A9BmyDWiTUugLlJJ3KG7IItss
#An2ABJqtu7dTyD44TjGKNZFc5o7u6WYC3RQ8qf/Icr4faCNx0RH6uHNngruHEIKbWfHm8OjB5ubV
#+4OyvDUYVJWZBQP+mzdNSk3bvprN6ic3b1zfNbNl11Sw53t71+5s3346Gg13Vj0p1td8vnhxcLB/
#bzweH8fJZFJ9s7X9rIuqzTn7qgfEeumaaUej4c7W1vazyaNJFQ6P/vr+66++/CXn3MYYy1UPifX1
#saG37979EObzxf5wuLHVfRZXOhnWXTYzWyxO/wxN0zRVVVWrngiXR0opBXfnTIVzx6UPEoQFCcKC
#xKc8XsjdC5+PaD03IQ7vkOizY2Uzi6enf/+xXLa/L90qc3auSy1YLIKloijvbmxc+da6Bs601s8u
#ubsfT6cPpT8GF87xdPrw3w2cRe8zVlEUw25daWbt+f8MXCClmbUndT38lIX9uOcQQuvuFkIgrEvs
#43/8/uSk95GHxw2QICxIEBYkCAsShAUJwoIEYUGCsCBBWJAgLEgQFiQICxKEBQnCggRhQYKwIEFY
#kCAsSBAWJAgLEoQFCcKCBGFBgrAgQViQICxIEBYkCAsShAUJwoIEYUGCsCBBWJAgLEgQFiQICxKE
#BQnCggRhQYKwIEFYkCAsSBAWJAgLEoQFCcKCBGFBgrAgQViQICxIEBYkCAsShAUJwoIEYUGCsCBB
#WJAgLEgQFiQICxKEBQnCggRhQYKwIEFYkCAsSBAWJAgLEoQFCcKCBGFBgrAgQViQICxIEBYkCAsS
#hAUJwoIEYUGCsCBBWJAgLEgQFiQICxKEBQnCggRhQYKwIEFYkCAsSBAWJAgLEoQFCcKCBGFBgrAg
#QViQICxIEBYkCAsShAUJwoIEYUGCsCBBWJAgLEgQFiQICxKEBQnCggRhQYKwIEFYkCAsSBAWJAgL
#EoQFCcKCBGFBouy9IoTo7qWZle5+/hPhIind3U7quvcG1Dus5XK5CCG0Ztb2XYu105qZHU+ni74L
#+4QVzcw2vrjyXV3X1dKtMrfc9wuxRoLFIlgqivJu986Zd67gXM8g0P+MZZa7Fz4f0Xre6LFjQYLH
#DZAgLEgQFiRiSm1a9RC4XFJqU0wpvTbu9HA+spnllNLrOPsw/9XMYs6ZsPC/dA3F9x/qR/Hnn357
#PKvnL2OMpZm1OWceP6CXrpk2xljW9fzlj7u7j0MIwZ7v7V27s3376Wg03Fn1kFhf8/nixcHB/r3x
#eHwc3D2EENzMijeHRw82N6/eH5TlrcGgqswsrHpYXGjeNCk1bftqNquf3LxxfdfMlu4e/gFtYHKA
#MG4AAgAAAABJRU5ErkJggg==
#}]

# fdff00 605a00
# ff8100 602e00
set Star "
<svg width=\"300px\" height=\"275px\" viewBox=\"0 0 300 275\"
     xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\">
  <polygon fill=\"#ff8100\" stroke=\"#602e00\" stroke-width=\"15\" 
            points=\"150,25  179,111 269,111 197,165
                    223,251  150,200 77,251  103,165
                    31,111 121,111\" />
</svg>
"

# TODO: use rounded rect (we need a SVG extension for this task)
set Rectangle "
<svg>
  <defs>
    <linearGradient
       id=\"linearGradient2190\">
      <stop
         style=\"stop-color:#ffffff;stop-opacity:1\"
         offset=\"0\" />
      <stop
         style=\"stop-color:#ffffff;stop-opacity:0\"
         offset=\"1\" />
    </linearGradient>
    <linearGradient
       x1=\"-78.461533\"
       y1=\"-59.999996\"
       x2=\"100\"
       y2=\"212.30769\"
       id=\"linearGradient2196\"
       xlink:href=\"#linearGradient2190\"
       gradientUnits=\"userSpaceOnUse\"
       gradientTransform=\"matrix(1,0,0,0.857142,0,1.42858)\" />
  </defs>
  <g>
    <rect
       width=\"252\" height=\"252\" x=\"6\" y=\"6\"
       style=\"opacity:1;color:#000000;fill:#000000;fill-opacity:0.50196078;fill-rule:evenodd;stroke:none;stroke-width:1.39999998;stroke-linecap:butt;stroke-linejoin:miter;marker:none;marker-start:none;marker-mid:none;marker-end:none;stroke-miterlimit:4;stroke-opacity:1\" />
    <rect
       width=\"250\" height=\"250\" x=\"5\" y=\"5\"
       style=\"opacity:1;color:#000000;fill:#c#;fill-opacity:1;fill-rule:evenodd;stroke:none;stroke-width:1.39999998;stroke-linecap:butt;stroke-linejoin:miter;marker:none;marker-start:none;marker-mid:none;marker-end:none;stroke-miterlimit:4;troke-opacity:1\" />
    <rect
       width=\"240\" height=\"240\" x=\"10\" y=\"10\"
       style=\"opacity:1;color:#000000;fill:url(#linearGradient2196);fill-opacity:1;fill-rule:evenodd;stroke:none;stroke-width:1.39999998;stroke-linecap:butt;stroke-linejoin:miter;marker:none;marker-start:none;marker-mid:none;marker-end:none;stroke-miterlimit:4;stroke-opacity:1\" />
  </g>
</svg>
"
} ;# namespace diagram
} ;# namespace board

# vi:set ts=3 sw=3:
