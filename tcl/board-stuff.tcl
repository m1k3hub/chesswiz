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


proc Destroy {w} {
	variable ${w}::Board

	after cancel $Board(afterid)
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
	53gKAAAAAElFTkSuQmCC
}]

set Disk [image create photo -data {
	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
	AAAASUVORK5CYII=
}]

# NOTE: an alternative for Rectangle
#set Square [image create photo -data {
#iVBORw0KGgoAAAANSUhEUgAAAJYAAACWCAYAAAA8AXHiAAAAR3RFWHRMaWNlbnNlAE9yaWdpbmFs
#IENoZXNzd2l6IGFydHdvcmssIDIwMjYuIEdQTC0yLjAtb3ItbGF0ZXI7IHNlZSBDT1BZSU5HLoC6
#vgkAAAJPSURBVHic7dlBattAGIDRkfGq5E7NugfK+do7ZVfjv4vatHSTyOSjTvIeGFuLwRLzMRqk
#bWZmwRs7/O8T4GMSFglhkRAWCWGREBYJYZEQFglhkTjeMOZ8+fB5HNbORWjzSofCnhXrvH5X+2Ot
#9f3y28r1sV3n+HGt9XX9aeBl83o/L99P2WVwl2bm6Z8GXnTLHuvhMu641jq98TVwX65z/HDLwL3O
#27adZmZt2yasD+w6xzOze8vjcQMJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglh
#kRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQ
#FglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJ
#YZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGR
#EBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAW
#CWGREBYJYZEQFglhkRAWCWGREBYJYZEQFglhkRAWieMNYw4zc1xrHWfmrc+H+3Kd490L0C1hPW/b
#dlprnW4Yy/tyWmutmXneO3BPWNdqv83Ml8vxee8f8q5c5/jxr+NX2cb9jMAtt8LzslJ9Noe1c59l
#xSLhcQMJYZEQFglhkRAWCWGREBYJYZEQFolfTmKrJraTcqMAAAAASUVORK5CYII=
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
