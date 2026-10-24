# ======================================================================
# Author : $Author$
# Version: $Revision: 1519 $
# Date   : $Date: 2018-09-11 07:41:52 -0400 (Tue, 11 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2013 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

# This implementation is adopted from BWidget/utils.tcl, but heavily
# modified.

# Due to centering problems on windows, see http://wiki.tcl.tk/20773

package provide place 2.0

namespace eval util {

proc place {path args} {
	set geometry [place::geometry $path {*}$args]
	lassign $geometry x y w h
	wm geometry $path "${x}${y}"
	return $geometry
}


namespace eval place {

variable mainWindow	.

variable PlaceList	{	"at" "center" "top-center" "left" "right"
								"above" "below" "above-or-below" "left-or-right" }
variable ShiftLeft	8

# Dialogs currently placed by besideBoard. The board can move or resize
# without the dialog's own requested size changing (window resize, a pure
# window move, wide/tall reflow, fullscreen, pane zoom, a changed media
# reserve), so besideBoard registers each placed dialog and a single
# debounced settle re-plans them against the board's current root rectangle.
# A dialog the user moved or resized is left alone from then on, even over
# the board (VAL-DLG-018C); only a display change that leaves it outside the
# new screen work area re-places it.
variable BesideDelay		80
variable BesideTimer		{}
# A steady stream of events (a playing video's per-frame Configure, a live
# engine clock) would restart a pure trailing debounce forever; the settle
# runs at the latest this long after the first deferred event.
variable BesideMaxWait		120
variable BesideFirst		{}
variable BesideUnmappedRetries	0
variable BesideDialogs		{}
variable BesideState
variable BesideReplacements	0
variable BesideBoardBound	{}
# Per-dialog usable minimum {width height}. Dialogs whose content can reflow or
# scroll may declare a smaller minimum than their natural request; when it fits
# a free strip besideBoard shrinks instead of reserving board room.
variable BesideMinimums
# Strips reserved for dialogs that cannot shrink. Entries are
# {dialog side pixels previousSide previousPixels}, newest last.
variable BesideReserves		{}
# The plan besideBoard last applied to each dialog (evidence and tests).
variable BesideLastPlan
# Per-dialog placement record (VAL-DLG-018A/C): a dict with trigger, rect
# (outer frame), placed_by (planner|user), rule, time and seq. Read it with
# besidePlacement; besidePlacementLog lists every record since the reset.
variable BesideRecords
variable BesideRecordLog		{}
variable BesideRecordSeq		0
# The trigger of the settle currently re-planning; a direct call is "open".
variable BesideTrigger			open
variable BesideParentBound		{}
variable BesideWmTraceBound		0


# Notes:
#  For Windows systems with more than one monitor the available screen area may
#  have negative positions. Geometry settings with negative numbers are used
#  under X to place wrt the right or bottom of the screen. On windows, Tk
#  continues to do this. However, a geometry such as 100x100+-200-100 can be
#  used to place a window onto a secondary monitor. Passing the + gets Tk
#  to pass the remainder unchanged so the Windows manager then handles -200
#  which is a position on the left hand monitor.
#  I've tested this for left, right, above and below the primary monitor.
#  Currently there is no way to ask Tk the extent of the Windows desktop in 
#  a multi monitor system. Nor what the legal co-ordinate range might be.
#
proc geometry {path args} {
	variable PlaceList
	variable ShiftLeft

	array set opts {
		-parent ""
		-position at
		-x 0 -y 0
		-width 0 -height 0
		-type normal
		-shift 0
	}
	array set opts $args

	update idletasks
	set windowingsystem [tk windowingsystem]
	set w $opts(-width)
	set h $opts(-height)
	# This is not correct in every case, sometimes 'reqheight' is too large.
	# But sometimes 'height' is too small, and then we need 'reqheight'.
	# No way to find an optimal solution.
	# Currently only one window (in Scidb) is known where the placement is
	# (mathematically) incorrect: the Tip-of-the-Day window.
	if {$w <= 0} { set w [expr {max([winfo reqwidth  $path], [winfo width  $path])}] }
	if {$h <= 0} { set h [expr {max([winfo reqheight $path], [winfo height $path])}] }
	set isPopup 0
	set frameless 0
	set cls [winfo class $path]
	if {	$cls eq "Menu"
		|| $cls eq "OptionMenu"
		|| $opts(-type) eq "popup"
		|| [wm overrideredirect $path]} {
		set isPopup 1
	}
	if {$isPopup || $opts(-type) eq "frameless"} { set frameless 1 }
	if {$isPopup} {
		set sx 0
		set sy 0
		set sw [winfo screenwidth  $path]
		set sh [winfo screenheight $path]
	} else {
		lassign [winfo workarea $path] sx sy sw sh
	}

	set where $opts(-position)
	if {$where ni $PlaceList} {
		set last [lindex $PlaceList end]
		set list [lreplace $PlaceList end end]
		return -code error "bad position \"$where\": must be [join $list ", "], or $last"
	}
	if {$where eq "at"} {
		set err [catch { set x [expr {int($opts(-x))}]; set y [expr {int($opts(-y))}] }]
		if {$err} {
			return -code error "[namespace current]::geometry: incorrect position"
		}
		if {$isPopup} {
			set x [expr {max($x, $sx)}]
			set y [expr {max($y, $sy)}]
		}
		if {$windowingsystem eq "win32"} {
			# handle windows multi-screen. -100 != +-100
			if {[string index $opts(-x) 0] ne "-"} { set x "+$x" }
			if {[string index $opts(-y) 0] ne "-"} { set y "+$y" }                    
		} else {
			if {$x >= 0} { set x "+$x" }
			if {$y >= 0} { set y "+$y" }
		}
	} else {
		set parent $opts(-parent)
		if {[string length $parent] && ![winfo exists $parent]} {
			return -code error "[namespace current]::geometry: \"$parent\" does not exist"
		}
		if {$frameless} {
			lassign {0 0 0 0} el er et eb
		} else {
			lassign [winfo extents $path] el er et eb
		}
		if {$where eq "top-center"} {
			if {[string length $parent]} {
				# center to parent
				set x0 [expr {[winfo rootx $parent] + $sx + ([winfo width $parent] - ($w + $el + $er))/2}]
			} else {
				# center to screen/desktop
				set x0 [expr {($sw - ($w + $el + $er))/2 - [winfo vrootx $path] - $sx}]
			}
			set x "+$x0"
			set y "+$opts(-shift)"
			if {$windowingsystem ne "win32"} {
				if {$x0 + $w > $sw}	{ set x "-0"; set x0 [expr {$sw - $w}] }
				if {$x0 < 0}			{ set x "+0" }
			}
		} elseif {$where eq "center"} {
			if {[string length $parent]} {
				# center to parent
				set x0 [expr {[winfo rootx $parent] + $sx + ([winfo width  $parent] - ($w + $el + $er))/2}]
				set y0 [expr {[winfo rooty $parent] + $sy + ([winfo height $parent] - ($h + $et + $eb))/2}]
			} else {
				# center to screen/desktop
				set x0 [expr {($sw - ($w + $el + $er))/2 - [winfo vrootx $path] - $sx}]
				set y0 [expr {($sh - ($h + $et + $eb))/2 - [winfo vrooty $path] - $sy}]
			}
			set x "+$x0"
			set y "+$y0"
			if {$windowingsystem ne "win32"} {
				if {$x0 + $w > $sw}	{ set x "-0"; set x0 [expr {$sw - $w}] }
				if {$x0 < 0}			{ set x "+0" }
				if {$y0 + $h > $sh}	{ set y "-0"; set y0 [expr {$sh - $h}] }
				if {$y0 < 0}			{ set y "+0" }
			}
		} else {
			if {[string length $parent] == 0} {
				set x0 [expr {[winfo vrootx $path] + $sx}]
				set y0 [expr {[winfo vrooty $path] + $sy}]
				set x1 [expr {$x0 + $sw}]
				set y1 [expr {$y0 + $sh}]
			} else {
				set x0 [winfo rootx $parent]
				set y0 [winfo rooty $parent]
				set x1 [expr {$x0 + [winfo width  $parent]}]
				set y1 [expr {$y0 + [winfo height $parent]}]
				if {[winfo toplevel $parent] eq $parent} {
					lassign [winfo extents $parent] pl pr pt pb
					set x0 [expr {$x0 - $pl}]
					set x1 [expr {$x1 + $pr}]
					set y0 [expr {$y0 - $pt}]
					set y1 [expr {$y1 + $pb}]
				}
			}
			set offs $opts(-shift)
			if {$where eq "above-or-below"} {
				if {[string length $parent] == 0 || $y0 - $sy >= $sy + $sh - $h} {
					set where "above"
				} else {
					set where "below"
				}
			} elseif {$where eq "left-or-right"} {
				if {[string length $parent] == 0 || $x0 - $sx >= $sx + $sw - $w} {
					set where "left"
				} else {
					set where "right"
				}
			}
			if {$where eq "left" || $where eq "right"} {
				set y "+$y0"
				if {$windowingsystem ne "win32"} {
					if {$y0 + $h > $sh}	{ set y "-0"; set y0 [expr {$sh - $h}] }
					if {$y0 < 0}			{ set y "+0" }
				}
				if {$where eq "left"} {
					# try left, then right if out, then 0 if out
					if {$x0 >= $w + $el + $er + $offs} {
						set x +[expr {$x0 - $w - $el - $er - $offs}]
					} elseif {$x1 + $w + $el + $er + $offs <= $sw} {
						set x +[expr {$x1 + $offs}]
					} else {
						set x "+0"
					}
				} else {
					# try right, then left if out, then 0 if out
					if {$x1 + $w + $el + $er + $offs <= $sw} {
						set x +[expr {$x1 + $offs}]
					} elseif {$x0 >= $w + $el + $er + $offs} {
						set x +[expr {$x0 - $w - $el - $er - $offs}]
					} else {
						set x "-0"
					}
				}
			} else { ;# if {$where eq "below" || $where eq "above"}
				set x "+$x0"
				if {$windowingsystem ne "win32"} {
					if {$x0 + $w > $sw}	{ set x "-0"; set x0 [expr {$sw - $w}] }
					if {$x0 < 0}	      { set x "+0" }
				}
				if {$where eq "above"} {
					# try top, then bottom, then 0
					if {$h + $et + $eb + $offs <= $y0} {
						set y +[expr {$y0 - $h - $et - $eb - $offs}]
					} elseif {$y1 + $h + $et + $eb + $offs <= $sh} {
						set y +[expr {$y1 + $offs}]
					} else {
						set y "+0"
					}
				} else {
					# try bottom, then top, then 0
					if {$y1 + $h + $et + $eb + $offs <= $sh} {
						set y +[expr {$y1 + $offs}]
					} elseif {$y0 >= $h + $et + $eb + $offs} {
						set y +[expr {$y0 - $h - $et - $eb - $offs}]
					} else {
						set y "-0"
					}
				}
			}
		}
	}
	# Keep the window, frame included, inside the visible screen area on
	# every platform: on Windows the branches above pass negative or too
	# large positions through (multi-monitor support), which put the title
	# bar above the screen or the window off its left edge.
	if {$frameless} {
		lassign {0 0 0 0} el er et eb
	} else {
		lassign [winfo extents $path] el er et eb
	}
	# the window manager will not make it larger than its maximal size
	# (overview.tcl FitHeight lowers it for windows taller than the screen)
	lassign {0 0} mw mh
	if {!$isPopup} { catch { lassign [wm maxsize $path] mw mh } }
	set cw [expr {$mw > 0 ? min($w, $mw) : $w}]
	set ch [expr {$mh > 0 ? min($h, $mh) : $h}]
	set x [clamp $x [expr {$cw + $el + $er}] $sx $sw]
	set y [clamp $y [expr {$ch + $et + $eb}] $sy $sh]

	if {$windowingsystem eq "aqua"} {
		# Avoid the native menu bar which sits on top of everything.
		scan $y "%d" y0
		if {0 <= $y0 && $y0 < 22} { set y "+22" }
	}

	return [list $x $y $w $h]
}


# A geometry offset <pos> ("+N", "+-N", or "-N" from the far edge) for a
# window <size> pixels wide/high (frame included), moved into the screen range
# <start> .. <start>+<length>. A window larger than the range goes to <start>.
proc clamp {pos size start length} {
	if {![regexp {^([+-])(-?[0-9]+)$} $pos -> sign n]} { return $pos }
	if {$sign eq "-"} {
		# relative to the right/bottom edge; only too large windows move
		if {$size > $length || $n < 0} { return "+$start" }
		return $pos
	}
	set n [expr {min($n, $start + $length - $size)}]
	set n [expr {max($n, $start)}]
	return "+$n"
}


# Clamp client size and outer-frame position together. Pure arithmetic so this
# also works before mapping, when winfo width/rootx still describe an old size.
# Work area is {x y width height}; extents are {left right top bottom}.
proc clampGeometry {geometry workarea {extents {0 0 0 0}}} {
	if {![regexp {^([0-9]+)x([0-9]+)([+-])(-?[0-9]+)([+-])(-?[0-9]+)$} $geometry -> w h xs x ys y]} {
		return -code error "invalid window geometry: $geometry"
	}
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set w [expr {max(1, min($w, $ww - $el - $er))}]
	set h [expr {max(1, min($h, $wh - $et - $eb))}]
	if {$xs eq "-"} { set x [expr {$wx + $ww - $w - $el - $er - $x}] }
	if {$ys eq "-"} { set y [expr {$wy + $wh - $h - $et - $eb - $y}] }
	set x [expr {max($wx, min($x, $wx + $ww - $w - $el - $er))}]
	set y [expr {max($wy, min($y, $wy + $wh - $h - $et - $eb))}]
	return "${w}x${h}+${x}+${y}"
}

proc fitWindow {path {geometry ""}} {
	if {$geometry eq ""} { set geometry [wm geometry $path] }
	set geometry [clampGeometry $geometry [winfo workarea $path] [winfo extents $path]]
	# Layout minimum sizes can exceed the laptop's current work area.
	lassign [wm minsize $path] mw mh
	regexp {^([0-9]+)x([0-9]+)} $geometry -> w h
	wm minsize $path [expr {min($mw, $w)}] [expr {min($mh, $h)}]
	wm geometry $path $geometry
	return $geometry
}


# The largest dialog that fits in each free strip beside/below the board.
# Values are {maxClientWidth maxClientHeight} for right/left/below. Frames are
# included: the client rectangle plus extents must stay inside the work area.
proc besideStrips {bx by bw bh workarea {extents {16 0 40 0}} {gap 12}} {
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set fh [expr {$et + $eb}]
	set right [expr {$wx + $ww - ($bx + $bw) - $gap - $fw}]
	set left [expr {$bx - $gap - $wx - $fw}]
	set below [expr {$wy + $wh - ($by + $bh) - $gap - $fh}]
	return [dict create \
		right [list $right [expr {$wh - $fh}]] \
		left [list $left [expr {$wh - $fh}]] \
		below [list [expr {$ww - $fw}] $below]]
}

# Fit a dialog into the largest free strip that can hold its usable minimum.
# Used only when no strip holds the requested size. Returns a dictionary
# {side geometry usable} with zero board intersection, or {} when no strip can
# hold the minimum at all. <minimum> is the dialog's usable minimum
# {width height} (each control at least its requested size); empty means shrink
# freely. An unusable strip NEVER competes: a 7 px sliver cannot beat a usable
# taller/narrower strip just because it is smaller. When no strip is usable the
# caller reserves board room instead (besideReserve) or uses the forced plan.
proc besideShrinkPlan {bx by bw bh dw dh workarea extents gap minimum} {
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set fh [expr {$et + $eb}]
	set minw 0
	set minh 0
	if {[llength $minimum]} { lassign $minimum minw minh }
	set strips [besideStrips $bx $by $bw $bh $workarea $extents $gap]
	set best {}
	set bestArea -1
	foreach side {right left below} {
		lassign [dict get $strips $side] maxw maxh
		if {$maxw < 1 || $maxh < 1} { continue }
		# Filter by the minimum usable size before scoring. A strip that
		# cannot hold it is not a shrink candidate at all.
		if {$maxw < $minw || $maxh < $minh} { continue }
		set cw [expr {min($dw, $maxw)}]
		set ch [expr {min($dh, $maxh)}]
		if {$cw < 1 || $ch < 1} { continue }
		switch $side {
			right { set x [expr {$bx + $bw + $gap}]; set y $by }
			left  { set x [expr {$bx - $gap - $cw - $fw}]; set y $by }
			below { set x $bx; set y [expr {$by + $bh + $gap}] }
		}
		set clamped [clampGeometry "${cw}x${ch}+${x}+${y}" $workarea $extents]
		if {![regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} $clamped -> w h x y]} {
			continue
		}
		if {$w < $minw || $h < $minh} { continue }
		set area [expr {
			max(0, min($x + $w + $fw, $bx + $bw) - max($x, $bx)) *
			max(0, min($y + $h + $fh, $by + $bh) - max($y, $by))}]
		if {$area != 0} { continue }
		set size [expr {$w * $h}]
		if {$best eq {} || $size > $bestArea} {
			set best [dict create side $side geometry [list $x $y $w $h] \
				usable 1]
			set bestArea $size
		}
	}
	if {$best eq {}} { return {} }
	dict set best overlap 0
	return $best
}

# Pure placement plan. Geometry is {outerX outerY clientWidth clientHeight};
# workarea is {x y width height}, extents {left right top bottom}.
# Prefer right, left, below at the current size, then at the requested content
# size (the 2026-10-18 minsize decision). VAL-DLG-011/012: when no strip holds
# the requested size, return a shrink plan into the LARGEST strip that can hold
# the dialog's usable minimum; the caller may instead reserve a strip
# (besideBoard does) to keep the requested size. <minimum> is the dialog's
# usable minimum. When no strip holds the minimum the result asks for a reserve
# and carries the largest overlap-free strip as "forced" (never a "shrink", even
# if that strip is below the minimum). Ties retain right/left/below order.
proc besidePlan {bx by bw bh dw dh workarea {extents {16 0 40 0}} {gap 12} {requested {}} {minimum {}}} {
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set fh [expr {$et + $eb}]
	set sizes [list [list $dw $dh]]
	if {[llength $requested]} { lappend sizes $requested }
	foreach size $sizes {
		lassign $size cw ch
		set cw [expr {max(1, min($cw, $ww - $fw))}]
		set ch [expr {max(1, min($ch, $wh - $fh))}]
		set candidates {}
		set areas {}
		set bestArea -1
		foreach {side x y} [list \
			right [expr {$bx + $bw + $gap}] $by \
			left [expr {$bx - $gap - $cw - $fw}] $by \
			below $bx [expr {$by + $bh + $gap}]] {
			set clamped [clampGeometry "${cw}x${ch}+${x}+${y}" $workarea $extents]
			regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} $clamped -> w h x y
			set area [expr {
				max(0, min($x + $w + $fw, $bx + $bw) - max($x, $bx)) *
				max(0, min($y + $h + $fh, $by + $bh) - max($y, $by))}]
			dict set candidates $side [list $x $y $w $h]
			dict set areas $side $area
			if {$bestArea < 0 || $area < $bestArea} {
				set bestArea $area
				set bestSide $side
			}
		}
		if {$bestArea == 0} { break }
	}
	if {$bestArea == 0} {
		return [dict create geometry [dict get $candidates $bestSide] \
			rule $bestSide side $bestSide overlap 0 candidates $candidates \
			areas $areas resized [expr {$cw != $dw || $ch != $dh}]]
	}
	set shrink [besideShrinkPlan $bx $by $bw $bh $dw $dh $workarea $extents $gap $minimum]
	if {[llength $shrink]} {
		return [dict create geometry [dict get $shrink geometry] \
			rule shrink side [dict get $shrink side] overlap 0 candidates $candidates \
			areas $areas resized 1 minimumFits 1 shrink 1]
	}
	# No strip holds the minimum. Ask besideBoard to reserve board room so the
	# dialog keeps a usable size. The largest overlap-free strip is kept as the
	# forced plan in case reserving is impossible (never an overlap allowance
	# and never reported as a shrink).
	set forced [besideShrinkPlan $bx $by $bw $bh $dw $dh $workarea $extents $gap {}]
	set plan [dict create geometry [dict get $candidates $bestSide] \
		rule reserve side $bestSide overlap $bestArea candidates $candidates \
		areas $areas resized [expr {$cw != $dw || $ch != $dh}] needsReserve 1]
	if {[llength $forced]} {
		dict set plan geometry [dict get $forced geometry]
		dict set plan side [dict get $forced side]
		dict set plan overlap 0
		# The forced geometry is the largest strip, even though it is below the
		# minimum: keep it as a fallback, not as an accepted shrink.
		dict set plan forced $forced
	}
	return $plan
}

# VAL-DLG-004 no-room plan at the requested size: the right/left/below
# candidate with the smallest overlap of the drawn board <board> (default: the
# protected rectangle), clamped inside the work area. The protected rectangle
# (board plus inset and earlier dialogs) only breaks ties: the inset dodges a
# dialog, the board cannot (VAL-DLG-016C). Carries every candidate and its
# area as evidence, plus a per-candidate record of board and peer overlap
# (VAL-DLG-017B).
proc besideNoRoomPlan {bx by bw bh rw rh workarea extents gap {peers {}} {board {}}} {
	set plan [besidePlan $bx $by $bw $bh $rw $rh $workarea $extents $gap]
	set candidates [dict get $plan candidates]
	set areas [dict get $plan areas]
	if {[llength $board] == 4} {
		lassign $board ax ay aw ah
		lassign $extents el er et eb
		set boardAreas {}
		dict for {side geometry} $candidates {
			lassign $geometry x y w h
			dict set boardAreas $side [expr {
				max(0, min($x + $w + $el + $er, $ax + $aw) - max($x, $ax)) *
				max(0, min($y + $h + $et + $eb, $ay + $ah) - max($y, $ay))}]
		}
	} else {
		set boardAreas $areas
	}
	set best {}
	foreach side {right left below} {
		if {$best eq {}} { set best $side; continue }
		set a [dict get $boardAreas $side]
		set b [dict get $boardAreas $best]
		if {$a < $b || ($a == $b && [dict get $areas $side] < [dict get $areas $best])} {
			set best $side
		}
	}
	return [dict create geometry [dict get $candidates $best] rule no-room \
		side $best overlap [dict get $areas $best] candidates $candidates \
		areas $areas boardAreas $boardAreas resized 0 minimumFits 0 requestedFits 0 chosen $best \
		record [besideCandidateRecord $candidates $peers $extents $best]]
}

# For each right/left/below candidate: its frame rectangle, its overlap with
# the drawn board, its overlap with the peers' frames, and whether it is the
# chosen one. The validator recomputes the minimum from these raw values.
proc besideCandidateRecord {candidates peers extents chosen} {
	lassign $extents el er et eb
	set board [besideBoardRect]
	set record {}
	foreach side {right left below} {
		lassign [dict get $candidates $side] x y w h
		set outer [list $x $y [expr {$w + $el + $er}] [expr {$h + $et + $eb}]]
		set boardArea [expr {$board eq {} ? 0 : [besideOverlap $outer $board]}]
		set peerArea 0
		foreach other $peers { incr peerArea [besideOverlap $outer [besidePeerRect $other]] }
		dict set record $side [list rect $outer board $boardArea peer $peerArea \
			chosen [expr {$side eq $chosen}]]
	}
	return $record
}

proc besidePosition {bx by bw bh dw dh workarea {extents {16 0 40 0}} {gap 12}} {
	return [dict get [besidePlan $bx $by $bw $bh $dw $dh $workarea $extents $gap] geometry]
}


# Root rectangle {x y width height} of a mapped board, or {} when the board
# cannot be placed against yet.
proc besideBoardRect {} {
	if {[catch { set board $::application::board::board }]} { return {} }
	if {![winfo exists $board] || ![winfo ismapped $board]} { return {} }
	if {[winfo width $board] < 2 || [winfo height $board] < 2} { return {} }
	# The canvas item includes the border and coordinates outside the inner
	# board widget, and the side-to-move/material/holding bars are drawn as
	# part of the board. A dialog must clear the full drawing, not only the
	# 8x8 squares (VAL-DLG-014f). Convert canvas coordinates to root
	# coordinates, accounting for any canvas view offset. Early
	# startup/teardown falls back below.
	if {![catch {
		set frame $::application::board::Vars(widget:frame)
		set boxes {}
		foreach tag {board stm material holdingbar} {
			set box [$frame bbox $tag]
			if {[llength $box] == 4} {lappend boxes $box}
		}
		set bbox {}
		foreach box $boxes {
			if {![llength $bbox]} {set bbox $box; continue}
			lassign $bbox x0 y0 x1 y1
			lassign $box a b c d
			set bbox [list [expr {min($x0,$a)}] [expr {min($y0,$b)}] \
				[expr {max($x1,$c)}] [expr {max($y1,$d)}]]
		}
	}] && [llength $bbox] == 4} {
		lassign $bbox x0 y0 x1 y1
		if {$x1 > $x0 && $y1 > $y0} {
			return [list [expr {[winfo rootx $frame] + $x0 - int([$frame canvasx 0])}] \
				[expr {[winfo rooty $frame] + $y0 - int([$frame canvasy 0])}] \
				[expr {$x1-$x0}] [expr {$y1-$y0}]]
		}
	}
	return [list [winfo rootx $board] [winfo rooty $board] \
		[winfo width $board] [winfo height $board]]
}

proc besideRect {w} {
	return [list [winfo rootx $w] [winfo rooty $w] \
		[winfo width $w] [winfo height $w]]
}

# Root rectangle of the window a dialog is transient for. A window-manager
# move/resize (including maximise/restore) shifts the transient dialog with
# its parent; comparing this rectangle tells settle that a changed dialog
# position is not a user drag (VAL-DLG-014c).
proc besideParentRect {dlg} {
	variable BesideState
	if {![info exists BesideState($dlg,parent)]} { return {} }
	set parent $BesideState($dlg,parent)
	if {$parent eq "" || ![winfo exists $parent]} { return {} }
	set top [winfo toplevel $parent]
	if {![winfo exists $top] || ![winfo ismapped $top]} { return {} }
	return [besideRect $top]
}

# The visible video inset {x y width height}, or {} when media is not playing
# in the board inset (hidden, never shown, or playing in the Media pane).
# VAL-DLG-013: the inset is a protected area exactly like the drawn board.
proc besideVideoRect {} {
	if {![info exists ::mediainset::Shown] || !$::mediainset::Shown} { return {} }
	if {[llength [info commands ::mediainset::Pane]] == 0} { return {} }
	if {[catch { set pane [::mediainset::Pane] }]} { return {} }
	if {$pane eq "" || ![winfo exists $pane.mediainset]} { return {} }
	set w $pane.mediainset
	if {![winfo ismapped $w]} { return {} }
	set rect [expr {[llength [info commands ::mediainset::rect]]
		? [::mediainset::rect] : [besideRect $w]}]
	lassign $rect x y width height
	if {$width < 2 || $height < 2} { return {} }
	return $rect
}

proc besideUnionRect {a b} {
	lassign $a ax ay aw ah
	lassign $b bx by bw bh
	set x [expr {min($ax, $bx)}]
	set y [expr {min($ay, $by)}]
	return [list $x $y [expr {max($ax+$aw, $bx+$bw) - $x}] \
		[expr {max($ay+$ah, $by+$bh) - $y}]]
}

# The rectangle a dialog must stay outside. With a playing video inset this
# is the union of the drawn board and the visible inset, so the strip the
# video owns inside the board pane is not mistaken for free space (GAP-002).
# Without a video it is exactly the drawn board, preserving every other rule.
proc besideProtectedRect {} {
	set board [besideBoardRect]
	if {$board eq {}} { return {} }
	set video [besideVideoRect]
	if {$video eq {}} { return $board }
	return [besideUnionRect $board $video]
}

# Ask the inset to move (or shrink) within its pane so it is not under the
# placed dialog. Returns 1 when it did, 0 when there is nowhere to go.
# What a dialog must stay clear of: the board and the visible inset, plus
# every dialog that took its reserved strip before this one (a later owner
# stacks beyond them; an earlier one keeps its place next to the board).
proc besideObstacleFor {dlg} {
	set rect [besideProtectedRect]
	if {$rect eq {}} { return {} }
	# Every dialog placed before this one keeps its place: the new one is
	# never put under it, and an earlier one is not moved for a later one
	# (VAL-DLG-015b, VAL-DLG-017B).
	variable BesideDialogs
	foreach other $BesideDialogs {
		if {$other eq $dlg} { break }
		if {![winfo exists $other] || ![winfo ismapped $other]} { continue }
		set rect [besideUnionRect $rect [besidePeerRect $other]]
	}
	return $rect
}

# The other placed, mapped dialogs beside the board.
proc besidePeers {dlg} {
	variable BesideDialogs
	set peers {}
	foreach other $BesideDialogs {
		if {$other eq $dlg || ![winfo exists $other] || ![winfo ismapped $other]} { continue }
		lappend peers $other
	}
	return $peers
}

# Record <dlg> as an owner of the live reserve it is placed beside, without
# changing it. Releasing such an entry restores nothing of its own.
proc besideShareReserve {dlg} {
	variable BesideReserves
	besidePruneReserves
	if {[besideOwns $dlg]} { return 0 }
	set side $::application::board::ReserveSide
	set pixels $::application::board::ReservePixels
	set floor $::application::board::MinimumReserveSquare
	lappend BesideReserves [list $dlg $side $pixels $side $pixels $floor $floor \
		$::application::board::ReserveKind]
	return 1
}

# A requested-size place for <dlg> next to an already placed peer (below,
# above, right or left of its frame), clear of the board, the inset and every
# peer, fully inside the work area. Returns a plan or {}.
proc besidePairPlan {dlg peers rw rh workarea extents gap} {
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set fh [expr {$et + $eb}]
	set ow [expr {$rw + $fw}]
	set oh [expr {$rh + $fh}]
	set protected [besideProtectedRect]
	set avoid [list $protected]
	foreach other $peers { lappend avoid [besidePeerRect $other] }
	foreach other $peers {
		lassign [besidePeerRect $other] px py pw ph
		foreach {side x y} [list \
			below $px [expr {$py + $ph + $gap}] \
			below [expr {$px + $pw - $ow}] [expr {$py + $ph + $gap}] \
			above $px [expr {$py - $gap - $oh}] \
			right [expr {$px + $pw + $gap}] $py \
			left [expr {$px - $gap - $ow}] $py] {
			set x [expr {max($wx, min($x, $wx + $ww - $ow))}]
			set y [expr {max($wy, min($y, $wy + $wh - $oh))}]
			set outer [list $x $y $ow $oh]
			if {![besideInside $outer $workarea]} { continue }
			set clear 1
			foreach r $avoid {
				if {[llength $r] == 4 && [besideOverlap $outer $r] > 0} { set clear 0; break }
			}
			if {$clear} {
				return [dict create geometry [list $x $y $rw $rh] rule stack-$side \
					side $side overlap 0 peer $other resized 0]
			}
		}
	}
	# Neither fits beside the other where the peer is: stack both in one
	# column from the top of the work area, moving the peer up.
	if {[llength $peers] != 1} { return {} }
	set other [lindex $peers 0]
	lassign [besidePeerRect $other] px py pw ph
	set top $wy
	lassign $protected bx by bw bh
	# A resize can leave the peer's old column a few pixels inside the
	# newly drawn board/inset. Try moving the entire column to a clear
	# edge, rather than declaring no room at that stale horizontal slot.
	set columns [list [list $px $px] [list [expr {$px+$pw-$ow}] $px]]
	foreach cx [list [expr {$bx+$bw+$gap}] [expr {$bx-$gap-max($ow,$pw)}]] {
		lappend columns [list $cx $cx]
	}
	foreach column $columns {
		lassign $column x peerX
		set x [expr {max($wx, min($x, $wx + $ww - $ow))}]
		set peerX [expr {max($wx, min($peerX, $wx + $ww - $pw))}]
		set moved [list $peerX $top $pw $ph]
		set outer [list $x [expr {$top + $ph + $gap}] $ow $oh]
		if {![besideInside $moved $workarea] || ![besideInside $outer $workarea]} { continue }
		if {[besideOverlap $moved $protected] || [besideOverlap $outer $protected]
			|| [besideOverlap $moved $outer]} { continue }
		return [dict create geometry [list $x [lindex $outer 1] $rw $rh] \
			rule stack-column side below overlap 0 peer $other \
			peerMove [list $peerX $top] resized 0]
	}
	return {}
}

# VAL-DLG-004 for the second dialog of a pair (decision 2026-10-23): the
# requested size at the right/left/below candidate beside the drawn board with
# the smallest board overlap among those whose frame does not overlap a peer
# (never under the first). When every candidate covers a peer the pair cannot
# be placed: the least board plus peer area is applied and the plan is marked
# peerFree 0 so the failure is visible.
proc besidePairNoRoom {dlg peers rw rh workarea extents gap} {
	variable BesideState
	lassign [besideBoardRect] bx by bw bh
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set plan [besideNoRoomPlan $bx $by $bw $bh $rw $rh $workarea $extents $gap]
	set candidates [dict get $plan candidates]
	# Measure where the frame really lands (see the openbox left-edge shift
	# in besideBoard), so the record matches the settled geometry.
	foreach side {right left below} {
		lassign [dict get $candidates $side] x y w h
		if {![info exists BesideState($dlg,extents)]
			&& $x < $wx + $el && $x + $w + $fw + $el <= $wx + $ww} {
			dict set candidates $side [list [expr {$wx + $el}] $y $w $h]
		}
	}
	set record [besideCandidateRecord $candidates $peers $extents {}]
	set best {}
	set bestCost {}
	foreach side {right left below} {
		set r [dict get $record $side]
		set cost [list [expr {[dict get $r peer] > 0}] \
			[expr {[dict get $r board] + [dict get $r peer]}]]
		if {$best eq {} || [lindex $cost 0] < [lindex $bestCost 0]
			|| ([lindex $cost 0] == [lindex $bestCost 0]
				&& [lindex $cost 1] < [lindex $bestCost 1])} {
			set best $side
			set bestCost $cost
		}
	}
	dict set record $best chosen 1
	set areas {}
	foreach side {right left below} { dict set areas $side [dict get $record $side board] }
	dict set plan candidates $candidates
	dict set plan areas $areas
	dict set plan geometry [dict get $candidates $best]
	dict set plan side $best
	dict set plan chosen $best
	dict set plan overlap [dict get $areas $best]
	dict set plan record $record
	dict set plan peerFree [expr {[lindex $bestCost 0] == 0}]
	return $plan
}

proc besideOwns {dlg} {
	variable BesideReserves
	foreach entry $BesideReserves {
		if {[lindex $entry 0] eq $dlg} { return 1 }
	}
	return 0
}

proc besideDodgeVideo {dlg x y w h extents} {
	# A failed squeeze/detach attempt re-lays the inset out at idle time;
	# realise it first or the inset reads as hidden and is left under the
	# dialog (VAL-DLG-016D).
	update idletasks
	set video [besideVideoRect]
	if {$video eq {}} { return 0 }
	lassign $extents el er et eb
	set outer [list $x $y [expr {$w+$el+$er}] [expr {$h+$et+$eb}]]
	if {[besideOverlap $outer $video] == 0} { return 0 }
	if {[llength [info commands ::mediainset::DodgeForDialog]] == 0} { return 0 }
	if {[catch { ::mediainset::DodgeForDialog $dlg $outer } moved]} { return 0 }
	return [expr {$moved == 1}]
}

# A dialog that needs more room than the strips outside the board pane can
# keep its usable size by making the inset move to the other side and shrink
# there (VAL-DLG-013: shrink or move the inset before covering it). The left
# side is tried first: with the inset there the protected area ends at the
# drawn board, leaving the whole work area on its right for the dialog. Tries
# the smallest documented strip on each side; returns the plan or {}.
proc besideVideoSqueeze {dlg dw dh workarea extents gap requested minimum} {
	if {[llength [info commands ::mediainset::SqueezeForDialog]] == 0} { return {} }
	if {[besideVideoRect] eq {}} { return {} }
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el+$er}]
	set fh [expr {$et+$eb}]
	set needW $dw
	set needH $dh
	if {[llength $minimum]} {
		set needW [expr {max($needW, [lindex $minimum 0])}]
		set needH [expr {max($needH, [lindex $minimum 1])}]
	}
	if {$needW + $fw > $ww || $needH + $fh > $wh} { return {} }
	set strip 168
	if {[llength [info commands ::mediainset::MinimumStrip]]} {
		set strip [::mediainset::MinimumStrip]
	}
	set canvX $wx
	if {[info exists ::application::board::Vars(widget:frame)]
		&& [winfo exists $::application::board::Vars(widget:frame)]} {
		set canvX [winfo rootx $::application::board::Vars(widget:frame)]
	}
	set maxBoardWidth [expr {($wx + $ww) - $canvX - $needW - $fw - $gap - $strip}]
	foreach side {left right} {
		set mb [expr {$side eq "left" ? $maxBoardWidth : 0}]
		if {![besideBorderRoom $side $strip squeeze $mb $workarea $fw $fh $gap $needW $needH]} {
			continue
		}
		if {[catch { ::mediainset::SqueezeForDialog $dlg $side $strip $mb } err]} {
			continue
		}
		update idletasks
		lassign [besideProtectedRect] px py pw ph
		if {$pw < 2 || $ph < 2} {
			catch { ::mediainset::ClearSqueeze $dlg }
			continue
		}
		set plan [besidePlan $px $py $pw $ph $dw $dh $workarea $extents $gap \
			$requested $minimum]
		lassign [dict get $plan geometry] _ _ w h
		if {[dict get $plan rule] ni {shrink no-room reserve}
			&& [dict get $plan overlap] == 0 && $w >= $needW && $h >= $needH} {
			return $plan
		}
		# The next side's squeeze replaces this one in a single relayout;
		# clearing in between would rebuild the board once more for nothing.
	}
	catch { ::mediainset::ClearSqueeze $dlg }
	return {}
}

# Last resort when even a squeezed strip cannot hold the dialog's usable
# minimum: release the video's strip and park the inset in a free pane
# margin (shrinking it), then place the dialog beside the smaller obstacle.
proc besideVideoDetach {dlg dw dh workarea extents gap requested minimum} {
	if {[llength [info commands ::mediainset::DetachForDialog]] == 0} { return {} }
	if {[besideVideoRect] eq {}} { return {} }
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el+$er}]
	set fh [expr {$et+$eb}]
	set needW $dw
	set needH $dh
	if {[llength $minimum]} {
		set needW [expr {max($needW, [lindex $minimum 0])}]
		set needH [expr {max($needH, [lindex $minimum 1])}]
	}
	if {$needW + $fw > $ww || $needH + $fh > $wh} { return {} }
	set sides {right left below}
	# Detaching releases the strip: every side is judged beside the
	# unreserved board, so rule all of them out without a relayout.
	if {![besideBorderRoom {} 0 auto 0 $workarea $fw $fh $gap $needW $needH]} {
		return {}
	}
	set tried 0
	while {[llength $sides]} {
		set sides [lassign $sides side]
		set derr [catch { ::mediainset::DetachForDialog $dlg $side $needW $needH \
			$workarea $extents $gap 0 } parked]
		if {$derr} { continue }
		update idletasks
		lassign [besideProtectedRect] px py pw ph
		if {$pw < 2 || $ph < 2} {
			continue
		}
		if {!$tried} {
			# Every side detaches against the same unreserved board: keep only
			# the sides whose strip beside it holds the usable size, rather
			# than paying a board relayout to find out for each one.
			set tried 1
			lassign [besideBoardRect] bx by bw bh
			set fit {}
			foreach s [list $side {*}$sides] {
				switch $s {
					right { set ok [expr {$bx+$bw+$gap+$needW+$fw <= $wx+$ww}] }
					left  { set ok [expr {$bx-$gap-$needW-$fw >= $wx}] }
					below { set ok [expr {$by+$bh+$gap+$needH+$fh <= $wy+$wh}] }
				}
				if {$ok} { lappend fit $s }
			}
			if {$side ni $fit} {
				set sides $fit
				continue
			}
			set sides [lrange $fit 1 end]
		}
		if {!$parked} { continue }
		set plan [besidePlan $px $py $pw $ph $dw $dh $workarea $extents $gap \
			$requested $minimum]
		lassign [dict get $plan geometry] _ _ w h
		if {[dict get $plan rule] eq $side && [dict get $plan overlap] == 0
			&& $w >= $needW && $h >= $needH} {
			return $plan
		}
	}
	# All candidates share the unreserved board. Restore only once after
	# the batch fails, rather than repainting it for each rejected side.
	catch { ::mediainset::ClearDetach $dlg }
	return {}
}

# Let a re-layout of the inset (media start/stop, resize, board rebuild)
# re-place open dialogs: the protected area changed even when the board did
# not.
proc besideVideoChanged {} {
	variable BesideDialogs
	if {[llength $BesideDialogs]} { besideSchedule }
}

# A one-pixel tolerance absorbs WM round-off; anything larger is a move or
# resize we did not make.
proc besideRectDiffers {a b} {
	if {[llength $a] != 4 || [llength $b] != 4} { return 1 }
	foreach x $a y $b {
		if {abs($x - $y) > 1} { return 1 }
	}
	return 0
}

proc besideOverlap {a b} {
	lassign $a ax ay aw ah
	lassign $b bx by bw bh
	return [expr {
		max(0, min($ax + $aw, $bx + $bw) - max($ax, $bx)) *
		max(0, min($ay + $ah, $by + $bh) - max($ay, $by))}]
}

# Coalesce board motion and window/reflow events into a single settle. A
# trailing debounce means a drag or a reflow does not re-place on every
# intermediate rectangle; the last event restarts the timer, so the dialog
# moves at most once per settle.
proc besideSchedule {{delay ""}} {
	variable BesideTimer
	variable BesideDelay
	variable BesideDialogs
	variable BesideMaxWait
	variable BesideFirst

	if {![llength $BesideDialogs]} { return }
	set now [clock milliseconds]
	if {$BesideTimer ne {}} {
		after cancel $BesideTimer
	} else {
		set BesideFirst $now
	}
	# Leave time within the 500 ms deadline for the board and native WM to
	# apply the plan, including when no video inset is present.
	set maxWait $BesideMaxWait
	set defaultDelay $BesideDelay
	if {[besideVideoRect] ne {}} { set maxWait 30; set defaultDelay 10 }
	if {$delay eq ""} { set delay $defaultDelay }
	set delay [expr {max(0, min($delay, $BesideFirst + $maxWait - $now))}]
	set BesideTimer [after $delay [namespace code besideSettle]]
}

# Work-area discovery performs synchronous WM property queries on X11.
# A planning transaction uses one snapshot per window; rectangle arithmetic
# and peer comparisons must not re-query the WM for every intermediate step.
variable BesideMeasureDepth 0
variable BesideBatch 0
variable BesideAreas {}
variable BesideFrames {}
proc besideMeasureBegin {} {
	variable BesideMeasureDepth
	variable BesideAreas
	variable BesideFrames
	if {$BesideMeasureDepth == 0} { set BesideAreas {}; set BesideFrames {} }
	incr BesideMeasureDepth
}
proc besideMeasureEnd {} {
	variable BesideMeasureDepth
	incr BesideMeasureDepth -1
}
proc besideWorkArea {dlg} {
	variable BesideMeasureDepth
	variable BesideAreas
	if {$BesideMeasureDepth == 0} { return [winfo workarea $dlg] }
	if {![dict exists $BesideAreas $dlg]} {
		dict set BesideAreas $dlg [winfo workarea $dlg]
	}
	return [dict get $BesideAreas $dlg]
}

# Native geometry is read once per transaction, never from an estimated
# global decoration size. Empty on platforms without this native query.
proc besideNativeFrame {top} {
	variable BesideMeasureDepth
	variable BesideFrames
	if {$BesideMeasureDepth > 0 && [dict exists $BesideFrames $top]} {
		return [dict get $BesideFrames $top]
	}
	set frame {}
	catch {set frame [::scidb::tk::wm frame $top]}
	if {$BesideMeasureDepth > 0} { dict set BesideFrames $top $frame }
	return $frame
}

# Every input that can invalidate a placement with an unchanged board.
proc besideContext {dlg} {
	set cls [winfo class $dlg]
	set extents {0 0 0 0}
	if {$cls ni {Menu OptionMenu} && ![wm overrideredirect $dlg]} {
	 set extents [winfo extents $dlg]
	}
	variable BesideTopSlack
	variable BesideXBorder
	return [list [besideWorkArea $dlg] $extents \
	 [list [winfo reqwidth $dlg] [winfo reqheight $dlg]] \
	 [wm minsize $dlg] [wm maxsize $dlg] $BesideTopSlack $BesideXBorder \
	 [besideDialogExtents $dlg]]
}
# A peer's frame as the planner last placed it: until the WM has applied that
# request, the window still reports where it was, and a dialog planned in
# the same settle would avoid the old frame and land on the new one.
proc besidePeerRect {dlg} {
	variable BesideState
	if {[info exists BesideState($dlg,planned)] && ![besideAtRequest $dlg]
		&& !([info exists BesideState($dlg,user)] && $BesideState($dlg,user))} {
		return $BesideState($dlg,planned)
	}
	return [besideOuterRect $dlg]
}

proc besideOuterRect {dlg} {
	lassign [besideRect $dlg] x y w h
	set extents {0 0 0 0}
	if {[winfo class $dlg] ni {Menu OptionMenu} && ![wm overrideredirect $dlg]} {
		set extents [besideDialogExtents $dlg]
	}
	lassign $extents l r t b
	return [list [expr {$x-$l}] [expr {$y-$t}] [expr {$w+$l+$r}] [expr {$h+$t+$b}]]
}
proc besideInside {rect area} {
	lassign $rect x y w h
	lassign $area ax ay aw ah
	return [expr {$x >= $ax && $y >= $ay && $x+$w <= $ax+$aw && $y+$h <= $ay+$ah}]
}

# Record the rectangle a placement actually produced. Runs on idle because
# the WM applies wm geometry asynchronously and callers deiconify after
# besideBoard returns.
# Frame extents for planning. Some window managers (openbox) place a dialog's
# client lower than the reported top extent; the difference observed on any
# mapped beside dialog is added so the real frame stays in the work area.
variable BesideTopSlack 0
proc besideDialogExtents {dlg} {
	variable BesideState
	if {[info exists BesideState($dlg,extents)]} {
		return $BesideState($dlg,extents)
	}
	if {[winfo ismapped $dlg] && [llength [info commands ::scidb::tk::wm]]
		&& ![catch {::scidb::tk::wm frameextents $dlg} frame] && [llength $frame] == 4} {
		lassign $frame left right top bottom
		if {min($left,$right,$top,$bottom) >= 0} {
			set BesideState($dlg,extents) [list $left $right $top $bottom]
			# The initial unmapped plan used estimates. Replace it promptly
			# once, then reuse this measurement for every parent re-plan.
			set BesideState($dlg,pendingTrigger) content
			besideSchedule 0
			return $BesideState($dlg,extents)
		}
	}
	variable BesideTopSlack
	variable BesideXBorder
	set extents [winfo extents $dlg]
	if {[winfo ismapped $dlg]} {
		besideLearnSlack $dlg $extents
		if {![windowZoomed $dlg] && [regexp {^[0-9]+x[0-9]+\+(-?[0-9]+)\+} [wm geometry $dlg] -> gx]} {
			besideLearnBorder [lindex $extents 0] [expr {[winfo rootx $dlg] - $gx}]
		}
	}
	lset extents 2 [expr {[lindex $extents 2] + $BesideTopSlack}]
	return $extents
}
# Some window managers (openbox) apply a requested +x to the frame inside its
# X border, so every requested position is that many pixels right of the
# outer frame. The border is the reported left extent minus the client's
# offset from the position wm geometry reports, learned on a normal
# (unmaximized) toplevel; besideBoard plans the parent's frame in those
# request coordinates (VAL-DLG-016C).
variable BesideXBorder 0
proc besideLearnBorder {left inner} {
	variable BesideXBorder
	set border [expr {$left - $inner}]
	if {$border > $BesideXBorder && $border <= 4} {
		set BesideXBorder $border
		besideSchedule
	}
}
proc besideLearnSlack {dlg {extents {}}} {
	variable BesideTopSlack
	if {$extents eq {}} { set extents [winfo extents $dlg] }
	if {![regexp {^[0-9]+x[0-9]+\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $dlg] -> gx gy]} { return }
	set slack [expr {[winfo rooty $dlg] - $gy - [lindex $extents 2]}]
	# Only a few pixels are a decoration mismatch; more is a stale geometry.
	if {$slack > $BesideTopSlack && $slack <= 8} {
		set BesideTopSlack $slack
		besideSchedule
	}
}

proc besideCapture {dlg} {
	variable BesideState
	if {![winfo exists $dlg] || ![winfo ismapped $dlg]} { return }
	besideDialogExtents $dlg
	set BesideState($dlg,last) [besideRect $dlg]
	set BesideState($dlg,board) [besideBoardRect]
	set BesideState($dlg,obstacle) [besideProtectedRect]
	set BesideState($dlg,context) [besideContext $dlg]
	set BesideState($dlg,owner) [besideRect [winfo toplevel $BesideState($dlg,parent)]]
	set BesideState($dlg,parentrect) [besideParentRect $dlg]
	set BesideState($dlg,zoomed) [besideParentZoomed $dlg]
	set BesideState($dlg,user) 0
	besideRecord $dlg planner
}

proc besideRegistryAdd {dlg parent} {
	variable BesideDialogs
	variable BesideState
	variable BesideBoardBound

	set BesideState($dlg,parent) $parent
	if {$dlg ni $BesideDialogs} { lappend BesideDialogs $dlg }
	# A rebuild moves the drawn board inside its canvas without necessarily
	# configuring the inner board widget (notably during Aqua fullscreen).
	# Observe the completed drawing, including after a layout replaces it.
	::application::board::afterRebuild ::util::place::besideBoardRebuilt

	if {[catch { set board $::application::board::board }]} { set board {} }
	if {$board ne {} && [winfo exists $board] && $BesideBoardBound ne $board} {
		bind $board <Configure> +[namespace code besideSchedule]
		bind $board <Map> +[namespace code besideSchedule]
		set BesideBoardBound $board
	}

	# The WM applies wm geometry asynchronously (and callers deiconify after
	# besideBoard returns), so record the produced rectangle on idle rather
	# than reading a half-applied one and mistaking it for a user move.
	set BesideState($dlg,last) {}
	set BesideState($dlg,board) [besideBoardRect]
	set BesideState($dlg,obstacle) [besideProtectedRect]
	set BesideState($dlg,context) [besideContext $dlg]
	set BesideState($dlg,parentrect) [besideParentRect $dlg]
	set BesideState($dlg,user) 0
	set BesideState($dlg,zoomed) [besideParentZoomed $dlg]
	if {![info exists BesideState($dlg,clamps)] || $BesideState($dlg,trigger) ne "clamp"} {
		set BesideState($dlg,clamps) 0
	}
	set BesideState($dlg,owner) [besideRect [winfo toplevel $parent]]
	# A maximize, restore or scripted resize of the main window can leave the
	# board rectangle unchanged (board-only zoom) yet move the work area the
	# dialog must stay inside: observe the toplevel itself (VAL-DLG-018A).
	variable BesideParentBound
	set top [winfo toplevel $parent]
	variable BesideWmTraceBound
	if {!$BesideWmTraceBound} {
		trace add execution ::wm leave [namespace code BesideGeometryCommand]
		set BesideWmTraceBound 1
	}
	unset -nocomplain BesideState($dlg,pendingTrigger)
	if {$top ni $BesideParentBound} {
		bind $top <Configure> +[list ::util::place::BesideParentConfigure $top %W]
		lappend BesideParentBound $top
	}
	after idle [namespace code [list besideCapture $dlg]]
}

# An explicit geometry request can leave the native size unchanged (the
# WM may coalesce it with a restore). It is still a placement trigger, so
# observe successful main-window size requests as well as Configure.
proc BesideGeometryCommand {command code result op} {
	variable BesideDialogs
	variable BesideState
	variable BesideParentBound
	if {$code != 0 || [llength $command] != 4
		|| [lindex $command 1] ne "geometry"
		|| ![regexp {^=?[0-9]+x[0-9]+} [lindex $command 3]]} { return }
	set top [lindex $command 2]
	if {$top ni $BesideParentBound || [besideVideoRect] eq {}} { return }
	if {[info exists ::application::Vars(loading)] && $::application::Vars(loading)} { return }
	if {[info exists ::application::reflow::S(busy)] && $::application::reflow::S(busy)} { return }
	set changed 0
	foreach dlg $BesideDialogs {
		if {![winfo exists $dlg] || ![winfo ismapped $dlg]} { continue }
		if {[winfo toplevel $BesideState($dlg,parent)] ne $top} { continue }
		set BesideState($dlg,pendingTrigger) resize
		set changed 1
	}
	if {$changed} { besideSchedule }
}

proc BesideParentConfigure {top window} {
	if {$window eq $top} { besideSchedule }
}

# -zoomed is an X11 attribute; native Windows/macOS use wm state.
proc windowZoomed {top} {
	if {[tk windowingsystem] ne "x11"} { return [expr {[wm state $top] eq "zoomed"}] }
	if {[catch {wm attributes $top -zoomed} zoomed]} { return 0 }
	return $zoomed
}

proc besideParentZoomed {dlg} {
	variable BesideState
	set top [winfo toplevel $BesideState($dlg,parent)]
	return [windowZoomed $top]
}

# Name the event that invalidated a dialog's placement: maximize, restore,
# resize (the main window changed size), move, board or content.
proc besideTriggerFor {dlg parentRect boardRect} {
	variable BesideState
	if {[info exists BesideState($dlg,zoomed)]} {
		set zoomed [besideParentZoomed $dlg]
		if {$zoomed && !$BesideState($dlg,zoomed)} { return maximize }
		if {!$zoomed && $BesideState($dlg,zoomed)} { return restore }
	}
	if {[info exists BesideState($dlg,pendingTrigger)]} {
		return $BesideState($dlg,pendingTrigger)
	}
	set old {}
	if {[info exists BesideState($dlg,parentrect)]} { set old $BesideState($dlg,parentrect) }
	if {$parentRect ne {} && $old ne {}} {
		if {[lrange $parentRect 2 3] ne [lrange $old 2 3]} { return resize }
		if {[besideRectDiffers $parentRect $old]} { return move }
	}
	if {[info exists BesideState($dlg,board)] && $boardRect ne $BesideState($dlg,board)} {
		return board
	}
	return content
}

# The area a dialog's frame must stay inside: the screen work area clipped to
# the main window's frame (the same area BesideBoardPlan plans against).
proc besideMainArea {dlg} {
	variable BesideState
	set workarea [besideWorkArea $dlg]
	if {![info exists BesideState($dlg,parent)]} { return $workarea }
	set parent $BesideState($dlg,parent)
	if {![winfo exists $parent]} { return $workarea }
	set top [winfo toplevel $parent]
	lassign [winfo extents $top] pel per pet peb
	set px [expr {[winfo rootx $top] - $pel}]
	set py [expr {[winfo rooty $top] - $pet}]
	set pw [expr {[winfo width $top] + $pel + $per}]
	set ph [expr {[winfo height $top] + $pet + $peb}]
	set native [besideNativeFrame $top]
	if {[llength $native] == 4} { lassign $native px py pw ph }
	lassign $workarea wx wy ww wh
	set x0 [expr {max($wx, $px)}]
	set y0 [expr {max($wy, $py)}]
	set x1 [expr {min($wx + $ww, $px + $pw)}]
	set y1 [expr {min($wy + $wh, $py + $ph)}]
	if {$x1 <= $x0 || $y1 <= $y0} { return $workarea }
	return [list $x0 $y0 [expr {$x1 - $x0}] [expr {$y1 - $y0}]]
}

# The dialog's frame is inside the main window's work area, within the few
# pixels the WM's own decoration offsets can account for.
proc besideContained {dlg} {
	variable BesideTopSlack
	variable BesideXBorder
	lassign [besideOuterRect $dlg] x y w h
	lassign [besideMainArea $dlg] ax ay aw ah
	set tx [expr {$BesideXBorder + 2}]
	set ty [expr {$BesideTopSlack + 2}]
	return [expr {$x >= $ax - $tx && $y >= $ay - $ty
		&& $x + $w <= $ax + $aw + $tx && $y + $h <= $ay + $ah + $ty}]
}

# A changed dialog rectangle is a user move or resize: not content growth
# (the requested size is unchanged, or the position moved) and not the WM
# applying the position or size besideBoard requested late.
proc besideUserChange {dlg current context} {
	variable BesideState
	set reqSame [expr {[lindex $context 2] eq [lindex $BesideState($dlg,context) 2]}]
	set last $BesideState($dlg,last)
	set sized [expr {[lrange $current 2 3] ne [lrange $last 2 3]}]
	set moved [besideRectDiffers [concat [lrange $current 0 1] {0 0}] \
		[concat [lrange $last 0 1] {0 0}]]
	set requestedSize {}
	if {[info exists BesideState($dlg,request)]} {
		set requestedSize [lrange $BesideState($dlg,request) 2 3]
	}
	if {$sized && $reqSame && [lrange $current 2 3] ne $requestedSize} { return 1 }
	if {[besideAtRequest $dlg]} { return 0 }
	return [expr {$reqSame || $moved}]
}

# Necessary condition for a squeeze or detach: beside the board this reserve
# would draw (its border alone, a lower bound of the protected area), some
# right/left/below strip of the work area holds the usable size. Without the
# probe (or a canvas) it cannot rule anything out.
proc besideBorderRoom {side px kind maxBoard workarea fw fh gap needW needH} {
	if {![llength [info commands ::application::board::reserveBorder]]} { return 1 }
	if {[catch {
		set frame $::application::board::Vars(widget:frame)
		set squeeze [expr {$kind eq "squeeze" && $side in {left right}}]
		set border [::application::board::reserveBorder $side $px $kind $maxBoard 1 $squeeze]
		if {$squeeze && [llength $border]} { lassign $border border strip }
		set ox [expr {[winfo rootx $frame] - int([$frame canvasx 0])}]
		set oy [expr {[winfo rooty $frame] - int([$frame canvasy 0])}]
	}]} { return 1 }
	if {![llength $border]} { return 0 }
	lassign $border x y bw bh
	set bx [expr {$ox + $x}]
	set by [expr {$oy + $y}]
	if {$squeeze} {
		# A board-only feasibility check mistakes the video's own strip
		# for free room. Include its future centred rectangle, using the
		# same reserve dimensions and aspect as the inset layout, without
		# rendering either speculative layout.
		set video [::mediainset::Pane].mediainset
		lassign $strip rx ry rw rh
		set ih [expr {int(round(($px-8)/$::mediainset::Aspect))
			+ [winfo reqheight $video.controls]+8}]
		set vr [list [expr {$ox+$rx+($rw-$px)/2}] \
			[expr {$oy+$ry+($rh-$ih)/2}] $px $ih]
		lassign [besideUnionRect [list $bx $by $bw $bh] $vr] bx by bw bh
	}
	lassign $workarea wx wy ww wh
	return [expr {$bx + $bw + $gap + $needW + $fw <= $wx + $ww
		|| $bx - $gap - $needW - $fw >= $wx
		|| $by + $bh + $gap + $needH + $fh <= $wy + $wh}]
}

# <dlg> holds a live squeeze; a detached inset takes precedence over it.
proc besideKeepsSqueeze {dlg} {
	if {[catch {
		set squeeze [expr {$::mediainset::SqueezeFor eq $dlg}]
		set other [expr {$::mediainset::DetachFor eq $dlg}]
	}]} { return 0 }
	return [expr {$squeeze && !$other && [besideVideoRect] ne {}}]
}

# A live peer currently owns the inset's squeeze, detach or dodge.
proc besideInsetHeldByPeer {dlg peers} {
	foreach var {SqueezeFor DetachFor DodgeFor} {
		if {[catch { set owner [set ::mediainset::$var] }]} { continue }
		if {$owner ne "" && $owner ne $dlg && $owner in $peers && [winfo exists $owner]} {
			return 1
		}
	}
	return 0
}

# Recheck clearance, or the permitted no-room minimum, against the live board.
proc besideCovered {dlg boardRect} {
	variable BesideLastPlan
	if {![info exists BesideLastPlan($dlg)]} { return 0 }
	set plan $BesideLastPlan($dlg)
	if {[dict exists $plan forced]} { return 0 }
	if {[dict get $plan rule] eq "no-room"} {
		if {![dict exists $plan record]} { return 0 }
		set best {}
		set chosen {}
		set peers [besidePeers $dlg]
		dict for {side candidate} [dict get $plan record] {
			set rect [dict get $candidate rect]
			set blocked 0
			if {[dict exists $plan pair]
				&& (![dict exists $plan first] || ![dict get $plan first])} {
				foreach peer $peers {
					if {[besideOverlap $rect [besidePeerRect $peer]] > 0} {
						set blocked 1
						break
					}
				}
			}
			set area [besideOverlap $rect $boardRect]
			if {[dict get $candidate chosen] && !$blocked} { set chosen $area }
			if {!$blocked && ($best eq {} || $area < $best)} { set best $area }
		}
		# A peer can change the board after this plan was computed. The
		# no-room rule permits only the current peer-free minimum; stale
		# candidate scores are not an overlap exemption.
		return [expr {$best eq {} || $chosen eq {} || $chosen > $best}]
	}
	set outer [besideOuterRect $dlg]
	set video [besideVideoRect]
	return [expr {[besideOverlap $outer $boardRect] > 0
		|| ($video ne {} && [besideOverlap $outer $video] > 0)}]
}

# The WM has applied the position besideBoard last requested.
proc besideAtRequest {dlg} {
	variable BesideState
	if {![info exists BesideState($dlg,request)]} { return 0 }
	lassign $BesideState($dlg,request) rx ry
	if {[info exists BesideState($dlg,extents)]} {
		lassign $BesideState($dlg,extents) left right top bottom
		return [expr {abs([winfo rootx $dlg]-$left-$rx) <= 2
			&& abs([winfo rooty $dlg]-$top-$ry) <= 2}]
	}
	variable BesideXBorder
	variable BesideTopSlack
	# wm geometry can report the new request before the WM has moved the
	# frame. Use the realised client root position, with the learned frame
	# offsets, so peers avoid the new request until it is actually applied.
	lassign [winfo extents $dlg] left right top bottom
	set x [expr {[winfo rootx $dlg]-$left+$BesideXBorder}]
	set y [expr {[winfo rooty $dlg]-$top-$BesideTopSlack}]
	set tx [expr {2 + $BesideXBorder}]
	set ty [expr {2 + $BesideTopSlack}]
	return [expr {abs($x - $rx) <= $tx && abs($y - $ry) <= $ty}]
}

# Write the placement record of <dlg>. A planner record names the trigger of
# the settle that produced it; a user record keeps the user's frame.
proc besideRecord {dlg by {trigger ""} {rect ""}} {
	variable BesideRecords
	variable BesideRecordLog
	variable BesideRecordSeq
	variable BesideState
	variable BesideLastPlan
	if {![winfo exists $dlg]} { return }
	if {$trigger eq ""} {
		set trigger open
		if {[info exists BesideState($dlg,trigger)]} { set trigger $BesideState($dlg,trigger) }
	}
	set rule {}
	if {$by eq "planner" && [info exists BesideLastPlan($dlg)]} {
		set rule [dict get $BesideLastPlan($dlg) rule]
	}
	set record [dict create dialog $dlg trigger $trigger placed_by $by \
		rect [expr {$rect eq "" ? [besideOuterRect $dlg] : $rect}] rule $rule time [clock milliseconds] \
		seq [incr BesideRecordSeq]]
	set BesideRecords($dlg) $record
	lappend BesideRecordLog $record
	if {[llength $BesideRecordLog] > 500} {
		set BesideRecordLog [lrange $BesideRecordLog end-399 end]
	}
}

# The current placement record of <dlg> ({} when it was never placed).
proc besidePlacement {dlg} {
	variable BesideRecords
	if {![info exists BesideRecords($dlg)]} { return {} }
	return $BesideRecords($dlg)
}

proc besidePlacementLog {{since 0}} {
	variable BesideRecordLog
	set out {}
	foreach r $BesideRecordLog {
		if {[dict get $r seq] > $since} { lappend out $r }
	}
	return $out
}

# How <dlg> was placed: planner or user.
proc besidePlacedBy {dlg} {
	variable BesideState
	if {[info exists BesideState($dlg,user)] && $BesideState($dlg,user)} { return user }
	return planner
}

proc besideRegistryRemove {dlg} {
	variable BesideDialogs
	variable BesideState
	set i [lsearch -exact $BesideDialogs $dlg]
	if {$i >= 0} { set BesideDialogs [lreplace $BesideDialogs $i $i] }
	array unset BesideState ${dlg},*
	variable BesideRecords
	unset -nocomplain BesideRecords($dlg)
	variable BesideLastPlan
	unset -nocomplain BesideLastPlan($dlg)
	besideReleaseReserve $dlg
	if {![llength $BesideDialogs]} {
		::application::board::afterRebuild ::util::place::besideBoardRebuilt true
	}
	# Let the inset return to its normal place when the dialog that made it
	# move/shrink goes away (VAL-DLG-013).
	if {[llength [info commands ::mediainset::RestoreAfterDialog]]} {
		catch { ::mediainset::RestoreAfterDialog $dlg }
	}
	if {[llength [info commands ::mediainset::ClearSqueeze]]} {
		catch { ::mediainset::ClearSqueeze $dlg }
	}
}

# Declare the smallest size a dialog can be shrunk to and stay usable. Pass no
# size to clear (and query the current value with no third argument).
proc besideMinSize {dlg {width ""} {height ""}} {
	variable BesideMinimums
	if {$width eq ""} {
		if {[info exists BesideMinimums($dlg)]} { return $BesideMinimums($dlg) }
		return {}
	}
	set BesideMinimums($dlg) [list $width $height]
	return [list $width $height]
}

# Drop recorded reservations that no longer describe the board's live reserve.
# ComputeLayout clears a reserve when a later layout drops below the square
# floor, and the video inset or another feature can take the strip, so an entry
# may outlive the reserve it recorded. Such an entry must never pop the wrong
# stack level on close. Valid entries (window alive and matching the live
# reserve) are kept.
proc besidePruneReserves {} {
	variable BesideReserves
	set activeSide $::application::board::ReserveSide
	set activePixels $::application::board::ReservePixels
	set kept {}
	set owning 0
	set droppedFloor {}
	foreach entry $BesideReserves {
		lassign $entry d sd px ps pp rootFloor af pk
		if {$ps eq $sd && $pp == $px} {
			# A shared entry (besideShareReserve) changed nothing; it follows
			# the live reserve for as long as its dialog is open.
			if {[winfo exists $d]} {
				lappend kept [list $d $activeSide $activePixels $activeSide \
					$activePixels $rootFloor $af $::application::board::ReserveKind]
			}
			continue
		}
		# An entry lower in a grown (stacked) strip is still live.
		set valid [expr {[winfo exists $d] && $activePixels > 0
			&& $sd eq $activeSide && $px <= $activePixels}]
		if {$valid} {
			lappend kept $entry
			incr owning
		} elseif {$droppedFloor eq ""} {
			set droppedFloor $rootFloor
		}
	}
	set BesideReserves $kept
	# A lowered square floor only ever belongs to a dialog reserve: recover the
	# original floor when no valid reservation needs it any more.
	if {!$owning && $droppedFloor ne ""
		&& [info exists ::application::board::MinimumReserveSquare]} {
		set ::application::board::MinimumReserveSquare $droppedFloor
	}
	return $kept
}

# Restore the reserve a dialog owned, without touching another dialog's or the
# video inset's strip. Dialog reserves may temporarily lower the board's
# minimum-square floor (the contract requires the dialog's controls to stay at
# their requested size); the original floor is restored here.
proc besideReleaseReserve {dlg} {
	variable BesideReserves
	set i -1
	for {set k 0} {$k < [llength $BesideReserves]} {incr k} {
		if {[lindex $BesideReserves $k 0] eq $dlg} { set i $k; break }
	}
	if {$i < 0} { return 0 }
	set entry [lindex $BesideReserves $i]
	set BesideReserves [lreplace $BesideReserves $i $i]
	lassign $entry _ side pixels previousSide previousPixels rootFloor activeFloor previousKind
	if {$previousSide eq $side && $previousPixels == $pixels} {
		# A shared entry (besideShareReserve) changed nothing.
		return 1
	}
	set activeSide $::application::board::ReserveSide
	set activePixels $::application::board::ReservePixels
	# Later reservations saved their "previous" state as the strip this entry
	# owns. Rebase those references even when the closing dialog is not the
	# top of the stack, so an out-of-order close cannot leave a later close
	# restoring this dialog's strip (VAL-DLG-014b).
	set out {}
	foreach later $BesideReserves {
		lassign $later d sd px ps pp rf af pk
		if {$ps eq $side && $pp == $pixels} {
			set later [list $d $sd $px $previousSide $previousPixels $rootFloor $af $previousKind]
		}
		lappend out $later
	}
	set BesideReserves $out
	# A stale entry no longer owns the live strip: keep the rebased entries
	# and drop any that no longer match what the board actually reserved,
	# without disturbing whatever reserve is active now.
	if {$activePixels == 0 || $side ne $activeSide || $pixels != $activePixels} {
		besidePruneReserves
		return 1
	}
	if {[llength $BesideReserves] == 0} {
		if {$rootFloor ne ""
			&& [info exists ::application::board::MinimumReserveSquare]} {
			set ::application::board::MinimumReserveSquare $rootFloor
		}
		if {[llength [info commands ::application::board::setReserve]]
			&& [catch { ::application::board::setReserve $previousSide $previousPixels \
				[expr {$previousKind eq "" ? "auto" : $previousKind}] }]} {
			catch { ::application::board::setReserve {} 0 }
		}
	} else {
		# Restore the reserve of the top remaining entry.
		lassign [lindex $BesideReserves end] _ remSide remPixels _ _ _ _ remKind
		if {$remKind eq ""} { set remKind auto }
		catch { ::application::board::setReserve $remSide $remPixels $remKind }
		# Keep the lowest floor required by the reserves that remain.
		set floor {}
		foreach e $BesideReserves {
			lassign $e _ _ _ _ _ _ af
			if {$af ne "" && ($floor eq "" || $af < $floor)} { set floor $af }
		}
		if {$floor ne "" && [info exists ::application::board::MinimumReserveSquare]} {
			set ::application::board::MinimumReserveSquare $floor
		}
	}
	return 1
}

# Undo a reserve attempt that could not produce a usable plan.
proc besideReserveRevert {previousSide previousPixels rootFloor {previousKind auto}} {
	if {$rootFloor ne ""
		&& [info exists ::application::board::MinimumReserveSquare]} {
		set ::application::board::MinimumReserveSquare $rootFloor
	}
	catch { ::application::board::setReserve $previousSide $previousPixels $previousKind }
}

# Make room the way the video inset does: reserve a strip in the board pane so
# the board itself shrinks, then place the dialog in the freed strip at its
# usable size. The reserve is computed ONCE from the dialog's minimum and the
# board pane's current allocation (the canvas width/height does not include the
# reserve; the drawn board shrinks inside it). Reading a frame that already
# includes an applied reserve made each retry ask for more and the second
# reserve fail, so there is exactly one board-accepted setReserve step here.
# Returns the new plan, or {} when reserving is not possible (no board
# renderer, or a strip owned by another feature).
proc besideReserve {dlg bx by bw bh dw dh workarea extents gap {minimum {}}} {
	variable BesideReserves
	if {[llength [info commands ::application::board::setReserve]] == 0
		|| [llength [info commands ::application::board::reserveSquare]] == 0} {
		return {}
	}
	if {[catch { set board $::application::board::board }]
		|| ![winfo exists $board] || ![winfo ismapped $board]} {
		return {}
	}
	# A strip owned by the video inset or another dialog is left alone.
	besidePruneReserves
	set stacked 0
	if {$::application::board::ReservePixels > 0} {
		set owner {}
		foreach entry $BesideReserves { lappend owner [lindex $entry 0] }
		if {$dlg in $owner} {
			besideReleaseReserve $dlg
			update idletasks
			lassign [besideBoardRect] bx by bw bh
		}
		if {$::application::board::ReservePixels > 0} {
			# The video's own strip is never extended for a dialog; another
			# dialog's strip is: this one goes beyond it (VAL-DLG-015b).
			if {![llength $BesideReserves]
				|| $::application::board::ReserveKind ne "dialog"} { return {} }
			set stacked 1
		}
	}
	set previousSide $::application::board::ReserveSide
	set previousPixels $::application::board::ReservePixels
	set previousKind $::application::board::ReserveKind
	if {[catch { set frame $::application::board::Vars(widget:frame) }]
		|| ![winfo exists $frame]} {
		return {}
	}
	set fullWidth [winfo width $frame]
	set fullHeight [winfo height $frame]
	set frameX [winfo rootx $frame]
	set frameY [winfo rooty $frame]
	if {$fullWidth < 2 || $fullHeight < 2} { return {} }
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el + $er}]
	set fh [expr {$et + $eb}]
	# Place at the dialog's usable size: its minimum is a floor, the requested
	# size is the target so no control is clipped.
	set targetW $dw
	set targetH $dh
	if {[llength $minimum]} {
		set targetW [expr {max($targetW, [lindex $minimum 0])}]
		set targetH [expr {max($targetH, [lindex $minimum 1])}]
	}
	if {$targetW + $fw > $ww || $targetH + $fh > $wh} { return {} }
	set rootFloor $::application::board::MinimumReserveSquare
	# reserveSquare uses ComputeLayout, which drops a reserve whose squares
	# fall below the floor. A dialog may legitimately need that much room, so
	# probe with the floor at 1 and decide the lifetime floor after choosing.
	if {$rootFloor > 1} { set ::application::board::MinimumReserveSquare 1 }
	set choices {}
	set sides {right left below}
	if {$stacked} {
		# One reserve side at a time: grow the active strip by what this
		# dialog needs beyond the dialogs already beside the board.
		set activeSide $::application::board::ReserveSide
		set activePixels $::application::board::ReservePixels
		set sides [expr {$activeSide eq "bottom" ? "below" : $activeSide}]
		# The dialogs already in the strip move up to the shrunk board, so
		# this one needs its own full extent on top of the active strip.
		if {$sides eq "below"} {
			set need [expr {$activePixels + $targetH + $fh + $gap}]
			set extent $fullHeight
		} else {
			set need [expr {$activePixels + $targetW + $fw + $gap}]
			set extent $fullWidth
		}
		set sides {}
		if {$need > $activePixels && $need < $extent} {
			set square [::application::board::reserveSquare $activeSide $need \
				$fullWidth $fullHeight dialog]
			if {$square >= 1} {
				lappend choices [list [expr {$activeSide eq "bottom" ? "below" : $activeSide}] $need $square]
			}
		}
	}
	foreach side $sides {
		if {$side eq "below"} {
			set base [expr {$wy + $wh - ($frameY + $fullHeight)}]
			set need [expr {max(0, $targetH + $fh + $gap - $base)}]
			set extent $fullHeight
		} else {
			if {$side eq "right"} {
				set base [expr {$wx + $ww - ($frameX + $fullWidth)}]
			} else {
				set base [expr {$frameX - $wx}]
			}
			set need [expr {max(0, $targetW + $fw + $gap - $base)}]
			set extent $fullWidth
		}
		if {$need < 1} { continue }
		if {$need >= $extent} { continue }
		set boardSide [expr {$side eq "below" ? "bottom" : $side}]
		# A dialog may shrink the board to make room, so probe with the
		# dialog kind rather than the strict ordinary video-strip rule.
		set square [::application::board::reserveSquare $boardSide $need \
			$fullWidth $fullHeight dialog]
		if {$square < 1} { continue }
		lappend choices [list $side $need $square]
	}
	if {![llength $choices]} {
		set ::application::board::MinimumReserveSquare $rootFloor
		return {}
	}
	# Prefer the strip that leaves the largest board; ties keep the smaller
	# reserve and right/left/below order.
	set chosen [lindex $choices 0]
	foreach c [lrange $choices 1 end] {
		if {[lindex $c 2] > [lindex $chosen 2]} {
			set chosen $c
		} elseif {[lindex $c 2] == [lindex $chosen 2]
			&& [lindex $c 1] < [lindex $chosen 1]} {
			set chosen $c
		}
	}
	lassign $chosen side pixels square
	set boardSide [expr {$side eq "below" ? "bottom" : $side}]
	# A dialog may need more room than the video inset's floor allows. Lower
	# the floor only for the lifetime of this reserve and restore it on close,
	# so a later board rebuild does not silently drop the reserved strip.
	set activeFloor [expr {min($rootFloor, max(1, $square))}]
	set ::application::board::MinimumReserveSquare $activeFloor
	if {[catch { ::application::board::setReserve $boardSide $pixels dialog } rv] || !$rv} {
		besideReserveRevert $previousSide $previousPixels $rootFloor $previousKind
		return {}
	}
	update idletasks
	if {$stacked} {
		# The grown strip moved the board; the dialogs already beside it
		# follow it now, so this one is planned beyond where they settle.
		variable BesideState
		foreach entry $BesideReserves {
			set other [lindex $entry 0]
			if {![winfo exists $other] || ![winfo ismapped $other]} { continue }
			set parent .application
			if {[info exists BesideState($other,parent)]} { set parent $BesideState($other,parent) }
			catch { besideBoard $other $parent }
			update idletasks
		}
	}
	lassign [besideObstacleFor $dlg] bx by bw bh
	set requested [list [winfo reqwidth $dlg] [winfo reqheight $dlg]]
	set plan [besidePlan $bx $by $bw $bh $dw $dh $workarea $extents $gap \
		$requested $minimum]
	if {[dict get $plan rule] ni {right left below shrink}
		|| [dict get $plan overlap] > 0} {
		besideReserveRevert $previousSide $previousPixels $rootFloor $previousKind
		return {}
	}
	lassign [dict get $plan geometry] _ _ w h
	if {$w < $targetW || $h < $targetH} {
		besideReserveRevert $previousSide $previousPixels $rootFloor $previousKind
		return {}
	}
	# A shared entry this dialog held is superseded by the reserve it owns now.
	set kept {}
	foreach entry $BesideReserves {
		lassign $entry d sd px ps pp
		if {$d ne $dlg || $ps ne $sd || $pp != $px} { lappend kept $entry }
	}
	set BesideReserves $kept
	lappend BesideReserves [list $dlg $::application::board::ReserveSide \
		$::application::board::ReservePixels $previousSide $previousPixels \
		$rootFloor $activeFloor $previousKind]
	return $plan
}

# The completed board drawing is the first point at which a parent resize
# has a final obstacle. Submit all dialog moves here, before returning to
# timers (notably diagram::resize's deferred setupPieces rasterisation).
# The old debounce yielded to that work and spent the pair's deadline before
# either plan started. Never re-enter a placement or an in-progress reflow.
proc besideBoardRebuilt {} {
	variable BesideDialogs
	variable BesideState
	variable BesideMeasureDepth
	if {$BesideMeasureDepth > 0 || [besideVideoRect] eq {}} {
		besideSchedule
		return
	}
	if {[info exists ::application::reflow::S(busy)] && $::application::reflow::S(busy)} {
		besideSchedule 0
		return
	}
	foreach dlg $BesideDialogs {
		if {![winfo exists $dlg] || ![winfo ismapped $dlg]} { continue }
		set parent [besideParentRect $dlg]
		if {([info exists BesideState($dlg,parentrect)]
			&& [besideRectDiffers $parent $BesideState($dlg,parentrect)])
			|| [besideParentZoomed $dlg] ne $BesideState($dlg,zoomed)
			|| [info exists BesideState($dlg,pendingTrigger)]} {
			besideSettle
			return
		}
	}
	besideSchedule
}

proc besideSettle {} {
	besideMeasureBegin
	try {
		BesideSettle
	} finally {
		besideMeasureEnd
	}
}

proc BesideSettle {} {
	variable BesideTimer
	variable BesideDialogs
	variable BesideState
	variable BesideReplacements

	if {$BesideTimer ne {}} { after cancel $BesideTimer }
	set BesideTimer {}
	variable BesideUnmappedRetries
	# The border can be briefly unmapped between a canvas rebuild and the
	# WM's MapNotify. Do not consume the only resize notification there.
	# Bound the retry when the board was deliberately hidden; Map handles
	# its eventual return without polling an inactive pane indefinitely.
	if {[besideBoardRect] eq {}} {
		if {[incr BesideUnmappedRetries] <= 3} { besideSchedule 30 }
		return
	}
	set BesideUnmappedRetries 0
	# A reflow freezes the twm while it loads; placing against an
	# intermediate rectangle would be visible. Wait for the load to finish.
	if {[info exists ::application::Vars(loading)] && $::application::Vars(loading)} {
		besideSchedule 80
		return
	}
	# Finish the pending main-window reflow before measuring the board.
	# Waiting for another trailing debounce lets Configure bursts postpone
	# placement beyond 500 ms. Both consumers now use the current dimensions
	# in this event-loop turn; cancel the old callback so it cannot reflow
	# the board again after the dialog has settled.
	if {[info exists ::application::reflow::S(afterId)]
		&& $::application::reflow::S(afterId) ne {}} {
		::application::reflow::cancelPending
		::application::reflow::onDebounced [winfo width .application] [winfo height .application]
	}
	if {[besideBoardRect] eq {}} { besideSchedule 30; return }
	# Plan against the coalesced drawing, not the old canvas while its
	# resize is still queued. Otherwise a squeeze forces an intermediate
	# repaint and defeats the board's Configure coalescing.
	if {[info exists ::application::board::Vars(after)]
		&& $::application::board::Vars(after) ne {}
		&& ![catch {after info $::application::board::Vars(after)}]} {
		besideSchedule 15
		return
	}
	# One dialog's re-plan can move the inset or the board under another
	# (a pair's no-room dodge, a peer's reserve). Re-check at once, a few
	# passes, instead of waiting for the next debounced settle, so a
	# maximize/restore converges within its 500 ms (VAL-DLG-018A). Later
	# passes keep the trigger that started the settle.
	set first {}
	set counted {}
	for {set pass 0} {$pass < 3} {incr pass} {
		set replan [BesideSettlePass $first]
		if {![llength $replan]} { break }
		foreach dlg $replan {
			if {![dict exists $first $dlg]} {
				dict set first $dlg $BesideState($dlg,trigger)
			}
			if {$dlg ni $counted} {
				lappend counted $dlg
				incr BesideReplacements
			}
		}
		update idletasks
	}
}

proc BesideSettlePass {first} {
	variable BesideDialogs
	variable BesideState
	variable BesideTrigger
	set boardRect [besideBoardRect]
	if {$boardRect eq {}} { return {} }
	set obstacle [besideProtectedRect]
	set replan {}
	foreach dlg $BesideDialogs {
		if {![winfo exists $dlg]} { besideRegistryRemove $dlg; continue }
		if {![winfo ismapped $dlg]} { continue }
		set current [besideRect $dlg]
		set context [besideContext $dlg]
		set owner [besideRect [winfo toplevel $BesideState($dlg,parent)]]
		set nativeMove 0
		if {[tk windowingsystem] eq "aqua" && $BesideState($dlg,last) ne {}} {
			# Cocoa translates a transient with its owner. This is not a
			# user drag: it must still follow subsequent board reflows.
			lassign $current x y w h
			lassign $BesideState($dlg,last) lx ly lw lh
			lassign $owner ox oy
			lassign $BesideState($dlg,owner) px py
			set nativeMove [expr {$w == $lw && $h == $lh
				&& abs(($x-$lx)-($ox-$px)) <= 1
				&& abs(($y-$ly)-($oy-$py)) <= 1}]
		}
		set parentRect [besideParentRect $dlg]
		# A window-manager move/resize/maximise moves the transient dialog
		# with the main window. Its root position changing is not a user drag.
		set parentMoved [expr {$parentRect ne {}
			&& [info exists BesideState($dlg,parentrect)]
			&& $BesideState($dlg,parentrect) ne {}
			&& [besideRectDiffers $parentRect $BesideState($dlg,parentrect)]}]
		set trigger [besideTriggerFor $dlg $parentRect $boardRect]
		set unchanged [expr {$boardRect eq $BesideState($dlg,board)
			&& $obstacle eq $BesideState($dlg,obstacle)
			&& $context eq $BesideState($dlg,context)
			&& !$parentMoved && $trigger ni {maximize restore}
			&& ![info exists BesideState($dlg,pendingTrigger)]}]
		if {![info exists BesideState($dlg,last)] || $BesideState($dlg,last) eq {}} {
			# Waiting for the idle capture of the rectangle the placement
			# produced: not a user move. If a placement input changed in
			# between, fall through and re-plan.
			if {$unchanged} {
				set BesideState($dlg,last) $current
				set BesideState($dlg,parentrect) $parentRect
				set BesideState($dlg,user) 0
				continue
			}
			set BesideState($dlg,user) 0
		} elseif {!$nativeMove && [besideRectDiffers $current $BesideState($dlg,last)]} {
			if {$parentMoved} {
				# The window moved; update parentrect. Do not treat the dialog
				# shift as user placement, but preserve existing user placement.
				set BesideState($dlg,parentrect) $parentRect
			} elseif {[besideUserChange $dlg $current $context]} {
				# Content growth changes client size without a user resize;
				# the WM applying our own request late is not a user move.
				set BesideState($dlg,user) 1
				besideRecord $dlg user
			}
		}
		if {$BesideState($dlg,user)} {
			# VAL-DLG-018C: a user's own move or resize is an explicit choice;
			# the planner never re-places it, even off the work area (the
			# user's own edge drag can take it there). Only a display change
			# (the screen work area itself changed) that leaves the frame
			# outside the new area brings it back.
			set screen [besideWorkArea $dlg]
			set display [expr {[info exists BesideState($dlg,screen)]
				&& $BesideState($dlg,screen) ne $screen}]
			set BesideState($dlg,screen) $screen
			if {$trigger ne "content"
				|| [besideRectDiffers $current $BesideState($dlg,last)]} {
				besideRecord $dlg user $trigger
			}
			set BesideState($dlg,parentrect) $parentRect
			set BesideState($dlg,zoomed) [besideParentZoomed $dlg]
			set BesideState($dlg,last) $current
			set BesideState($dlg,board) $boardRect
			set BesideState($dlg,obstacle) $obstacle
			set BesideState($dlg,context) $context
			unset -nocomplain BesideState($dlg,pendingTrigger)
			if {!$display || [besideInside [besideOuterRect $dlg] $screen]} { continue }
		} elseif {$unchanged} {
			# No placement input changed. A frame the WM left outside the
			# main window's work area (a restore whose late Configure moved
			# it) is re-clamped, a bounded number of times per placement.
			# Likewise a dialog whose rule allows no overlap but which a
			# peer's no-room plan has since covered with the inset.
			if {([besideContained $dlg] && ![besideCovered $dlg $boardRect])
				|| $BesideState($dlg,clamps) >= 2} { continue }
			incr BesideState($dlg,clamps)
			set trigger clamp
		}
		set BesideState($dlg,trigger) $trigger
		lappend replan $dlg
	}

	variable BesideTrigger
	set done {}
	# Applying the first move queues idle geometry/capture work. Draining
	# it inside the second helper allowed a repaint to split the pair by
	# hundreds of ms. Hold the inset and submit both moves before that drain.
	variable BesideBatch
	incr BesideBatch
	set held [llength [info commands ::mediainset::hold]]
	if {$held} { ::mediainset::hold }
	try {
	foreach dlg $replan {
		set BesideTrigger $BesideState($dlg,trigger)
		if {[dict exists $first $dlg] && $BesideTrigger in {content board}} {
			set BesideTrigger [dict get $first $dlg]
			set BesideState($dlg,trigger) $BesideTrigger
		}
		set failed [catch { besideBoard $dlg $BesideState($dlg,parent) }]
		set BesideTrigger open
		if {$failed} { continue }
		lappend done $dlg
		# Record the rectangle the new placement produced, including the
		# parent's current geometry, after the WM has applied it.
		after idle [namespace code [list besideCapture $dlg]]
	}
	} finally {
		incr BesideBatch -1
		if {$held} { ::mediainset::release }
	}

	# A later dialog's plan runs update idletasks and so the earlier one's
	# idle capture, before it moves the inset (a no-room dodge): the earlier
	# dialog would remember a protected area that no longer exists and the
	# pair would re-plan each other forever. Capture all of them now.
	update idletasks
	foreach dlg $done { besideCapture $dlg }
	return $done
}

# Number of re-placements caused by changed inputs, for tests/evidence. Opening
# a dialog calls besideBoard directly and does not count here.
proc besideReplaceCount {} {
	variable BesideReplacements
	return $BesideReplacements
}

proc besideResetReplaceCount {} {
	variable BesideReplacements
	set BesideReplacements 0
}


# Place <dlg> beside the main board ($::application::board::board) using
# besidePosition and the real work area / frame extents. When the dialog's
# natural size (including wm minsize) cannot fit, retry at its requested size
# and lower minsize accordingly. Leave Tk in charge of size so later content
# can grow; re-plan on requested-size changes to keep the final frame in place.
# Returns the applied plan, or {rule center} when the board is not mapped.
#
# VAL-DLG-011: no placement accepts board overlap. When no free strip holds the
# requested size, besidePlan returns a zero-overlap shrink and besideBoard first
# tries to reserve board room (the same board-reserve mechanism as the video
# inset), keeping the requested size. Only when reserving is impossible does it
# apply the shrink. VAL-DLG-005 still caps content larger than the whole work
# area into a strip, retaining at least 320x160 (or the natural request) when
# possible. The reservation is released on close/unregister.
proc besideBoard {dlg {parent ""}} {
	besideMeasureBegin
	# The plan releases and re-applies the inset's squeeze; the inset must
	# not visibly jump through that transient (VAL-DLG-016D).
	set held [llength [info commands ::mediainset::hold]]
	if {$held} { ::mediainset::hold }
	try {
		return [BesideBoardPlan $dlg $parent]
	} finally {
		besideMeasureEnd
		if {$held} { ::mediainset::release }
	}
}

proc BesideBoardPlan {dlg parent} {
	variable BesideRequests
	# A pending Map/Unmap can be delivered by this drain. Check the board
	# afterwards: testing it first left empty obstacle coordinates on restore.
	# A settle has already measured the completed board. Its helpers submit
	# all moves as one batch; their shared idle drain happens after the loop.
	variable BesideBatch
	if {!$BesideBatch} { update idletasks }
	if {$parent eq ""} {
		set parent [wm transient $dlg]
		if {$parent eq ""} { set parent .application }
	}
	if {[catch { set board $::application::board::board }]
		|| ![winfo exists $board]
		|| ![winfo ismapped $board]} {
		if {[winfo exists $parent]} {
			::util::place $dlg -parent [winfo toplevel $parent] -position center
		} else {
			::util::place $dlg -position center
		}
		return [dict create rule center]
	}
	# VAL-DLG-017B: with two playing dialogs open, each owns the reserve it
	# sits beside; the later one is stacked next to the earlier one.
	set peers [besidePeers $dlg]
	set earlier {}
	foreach other $peers {
		if {[lsearch -exact $::util::place::BesideDialogs $dlg] < 0
			|| [lsearch -exact $::util::place::BesideDialogs $other]
				< [lsearch -exact $::util::place::BesideDialogs $dlg]} {
			lappend earlier $other
		}
	}
	set pair [expr {[llength $earlier] > 0}]
	set follower $pair
	foreach other $peers { besideShareReserve $other }
	lassign [wm minsize $dlg] mw mh
	lassign [wm maxsize $dlg] maxw maxh
	set rw [winfo reqwidth $dlg]
	set rh [winfo reqheight $dlg]
	set dw [expr {min($maxw, max($rw, $mw))}]
	set dh [expr {min($maxh, max($rh, $mh))}]
	set workarea [besideWorkArea $dlg]
	if {[winfo exists $parent]} {
		set pTop [winfo toplevel $parent]
		lassign [winfo extents $pTop] pel per pet peb
		set px [expr {[winfo rootx $pTop] - $pel}]
		set py [expr {[winfo rooty $pTop] - $pet}]
		set pw [expr {[winfo width $pTop] + $pel + $per}]
		set ph [expr {[winfo height $pTop] + $pet + $peb}]
		# Some window managers report top extents smaller than the real
		# title bar, so the frame origin from wm geometry and the one derived
		# from the root position disagree. Keep only the rectangle both agree
		# on, so the dialog frame is inside the main window either way.
		if {[regexp {^[0-9]+x[0-9]+\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $pTop] -> gx gy]} {
			variable BesideXBorder
			if {![windowZoomed $pTop]} {
				besideLearnBorder $pel [expr {[winfo rootx $pTop] - $gx}]
			}
			if {$BesideXBorder > 0 && $gx - $px == $BesideXBorder} {
				# Horizontally the two origins differ by exactly the X border
				# the WM keeps outside a requested +x: the whole frame width is
				# usable in request coordinates, starting at gx (VAL-DLG-016C).
				set px $gx
			}
			set pw [expr {$pw - abs($gx - $px)}]
			set ph [expr {$ph - abs($gy - $py)}]
			set px [expr {max($px, $gx)}]
			set py [expr {max($py, $gy)}]
		}
		set native [besideNativeFrame $pTop]
		if {[llength $native] == 4} { lassign $native px py pw ph }
		lassign $workarea wx wy ww wh
		set x0 [expr {max($wx, $px)}]
		set y0 [expr {max($wy, $py)}]
		set x1 [expr {min($wx + $ww, $px + $pw)}]
		set y1 [expr {min($wy + $wh, $py + $ph)}]
		if {$x1 > $x0 && $y1 > $y0} {
			set workarea [list $x0 $y0 [expr {$x1 - $x0}] [expr {$y1 - $y0}]]
		}
	}
	set cls [winfo class $dlg]
	if {$cls eq "Menu" || $cls eq "OptionMenu" || [wm overrideredirect $dlg]} {
		set extents {0 0 0 0}
	} else {
		set extents [besideDialogExtents $dlg]
	}
	variable BesideMinimums
	set minimum {}
	if {[info exists BesideMinimums($dlg)]} {
		set minimum $BesideMinimums($dlg)
	} else {
		# Without a declared minimum the dialog's content cannot reflow, so
		# its natural request is the smallest usable size (VAL-DLG-016: no
		# control is realised below its requested size; wm minsize may only
		# be lowered down to the request, never below it).
		set minimum [list $rw $rh]
	}
	# A single dialog that squeezed the inset keeps that squeeze when the
	# squeezed layout still holds it at its usable size. Releasing and
	# re-applying it costs two inset/board relayouts per re-plan, which a
	# maximize or restore cannot afford within its settle (VAL-DLG-018A).
	set plan {}
	if {!$pair && [besideKeepsSqueeze $dlg]} {
		# A left squeeze's board cap was computed for the previous main
		# window width. Refresh it directly for this width: releasing the
		# squeeze first would paint the enlarged board only to shrink it
		# again a moment later, costing two synchronous rebuilds. Keep a
		# tighter existing cap when the window grows: it already holds the
		# dialog, and expanding it would add another unnecessary rebuild.
		lassign $::mediainset::Squeeze squeezeSide strip oldCap
		if {$squeezeSide eq "left"} {
			set frame $::application::board::Vars(widget:frame)
			set needW [expr {max($dw, [lindex $minimum 0])}]
			lassign $workarea sx sy sw sh
			lassign $extents sl sr st sb
			set cap [expr {$sx+$sw-[winfo rootx $frame]-$needW-$sl-$sr-12-$strip}]
			if {$cap > 0 && ($oldCap <= 0 || $cap < $oldCap)
				&& [besideBorderRoom left $strip squeeze $cap $workarea \
					[expr {$sl+$sr}] [expr {$st+$sb}] 12 $needW $dh]} {
				::mediainset::SqueezeForDialog $dlg left $strip $cap
				update idletasks
			}
		}
		lassign [besideObstacleFor $dlg] bx by bw bh
		set kept [besidePlan $bx $by $bw $bh $dw $dh $workarea $extents 12 \
			[list $rw $rh] $minimum]
		lassign [dict get $kept geometry] _ _ kw kh
		lassign $minimum needW needH
		set clear 1
		if {[llength $peers]} {
			lassign [dict get $kept geometry] kx ky
			lassign $extents kl kr kt kb
			set outer [list $kx $ky [expr {$kw+$kl+$kr}] [expr {$kh+$kt+$kb}]]
			foreach other $peers {
				if {[besideOverlap $outer [besidePeerRect $other]]} { set clear 0 }
			}
		}
		if {$clear && [dict get $kept rule] ni {shrink no-room reserve}
			&& [dict get $kept overlap] == 0
			&& $kw >= max($dw, $needW) && $kh >= max($dh, $needH)} {
			set plan $kept
		} elseif {[llength $peers]} {
			# Keeping a valid shared strip may require stacking, rather
			# than the single-dialog right/left/below plan. Test that
			# before releasing and rebuilding the very same squeeze.
			set stacked [besidePairPlan $dlg $peers $rw $rh $workarea $extents 12]
			if {![llength $stacked]} {
				set stacked [besidePairNoRoom $dlg $peers $rw $rh $workarea $extents 12]
				if {![dict get $stacked peerFree]} { set stacked {} }
			}
			if {[llength $stacked]} {
				set plan $stacked
				dict set plan pair 1
				set pair 1
			}
		}
	}
	if {![llength $plan]} {
		# A previous placement may have moved the inset out of this dialog's
		# way; put it back before planning so the protected area is the
		# normal one.
		if {[llength [info commands ::mediainset::RestoreAfterDialog]]} {
			catch { ::mediainset::RestoreAfterDialog $dlg }
		}
		if {[llength [info commands ::mediainset::ClearSqueeze]]} {
			catch { ::mediainset::ClearSqueeze $dlg }
		}
		# A foreign inset owner made both operations above no-ops. In a
		# batch there is no new layout to realise, only our peer's queued move.
		if {!$BesideBatch || ![besideInsetHeldByPeer $dlg $peers]} { update idletasks }
		# VAL-DLG-013: with a video playing in the board inset, the protected
		# area is the union of the drawn board and the visible inset. Strips
		# inside the pane that the video owns are therefore not free space.
		lassign [besideObstacleFor $dlg] bx by bw bh
		set plan [besidePlan $bx $by $bw $bh $dw $dh $workarea $extents 12 \
			[list $rw $rh] $minimum]
	}
	# A re-planned earlier dialog avoids the later ones only when its own
	# place would cover one (the board re-flowed under it).
	set onPeer 0
	if {[llength $peers] && [dict get $plan rule] ni {no-room reserve shrink}} {
		lassign [dict get $plan geometry] gx gy gw gh
		lassign [besideDialogExtents $dlg] el er et eb
		set outer [list $gx $gy [expr {$gw+$el+$er}] [expr {$gh+$et+$eb}]]
		foreach other $peers {
			if {[besideOverlap $outer [besidePeerRect $other]]} { set onPeer 1 }
		}
		if {$onPeer} {
			set earlier $peers
			set pair 1
		}
	}
	if {$pair && ($onPeer || [dict get $plan rule] in {no-room reserve shrink})} {
		# Never take the peer's squeeze or reserve away from it: place the
		# pair together, or apply the no-room rule clear of the peer.
		set stacked {}
		if {!$onPeer && $::application::board::ReserveKind eq "dialog"} {
			# The peer reserved a dialog strip: grow it for this one too
			# (VAL-DLG-015b stacking).
			set stacked [besideReserve $dlg $bx $by $bw $bh $dw $dh $workarea \
				$extents 12 $minimum]
		}
		if {![llength $stacked]} {
			set stacked [besidePairPlan $dlg $earlier $rw $rh $workarea $extents 12]
		}
		if {![llength $stacked]} {
			set stacked [besidePairNoRoom $dlg $earlier $rw $rh $workarea $extents 12]
		}
		set plan $stacked
		dict set plan pair 1
	}
	variable BesideState
	if {[dict exists $plan peerMove]
			&& !$BesideState([dict get $plan peer],user)} {
			set other [dict get $plan peer]
			lassign [dict get $plan peerMove] ox oy
			wm geometry $other "+$ox+$oy"
			set BesideState($other,request) [list $ox $oy]
			lassign [besideOuterRect $other] _ _ pw ph
			set BesideState($other,planned) [list $ox $oy $pw $ph]
			set BesideState($other,last) {}
			after idle [namespace code [list besideCapture $other]]
	}
	# The inset is a single window: a peer that already squeezed, detached
	# or dodged it keeps it. Taking it over would move it under that peer,
	# whose re-plan takes it back, and the pair would trade it forever.
	set foreign [besideInsetHeldByPeer $dlg $peers]
	if {$foreign} { dict set plan insetHeld 1 }
	if {[dict get $plan rule] in {no-room reserve shrink} && ![dict exists $plan pair] && !$foreign} {
		set squeezed [besideVideoSqueeze $dlg $dw $dh $workarea $extents 12 \
			[list $rw $rh] $minimum]
		if {[llength $squeezed]} {
			set plan $squeezed
		}
	}
	if {[dict get $plan rule] in {no-room reserve shrink} && ![dict exists $plan pair] && !$foreign} {
		set detached [besideVideoDetach $dlg $dw $dh $workarea $extents 12 \
			[list $rw $rh] $minimum]
		if {[llength $detached]} {
			set plan $detached
		}
	}
	if {[dict get $plan rule] in {no-room reserve} && ![dict exists $plan pair]} {
		set reserved [besideReserve $dlg $bx $by $bw $bh $dw $dh $workarea $extents 12 $minimum]
		if {[llength $reserved]} {
			set plan $reserved
		} elseif {[dict exists $plan forced]} {
			# No strip holds the minimum and no board room can be reserved:
			# keep the largest overlap-free forced strip, but never relabel a
			# below-minimum result as a shrink.
			set forced [dict get $plan forced]
			set plan [dict create geometry [dict get $forced geometry] \
				rule no-room side [dict get $forced side] overlap 0 \
				forced 1 minimumFits 0]
		} else {
			# Nothing positive is left beside the board; this is the genuine
			# no-room case and the caller's overlap is reported as such.
			dict set plan rule no-room
		}
	}
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el+$er}]
	set fh [expr {$et+$eb}]
	# VAL-DLG-016/VAL-DLG-004: a dialog that fits the work area at its
	# requested size is never squeezed below it. When no strip, squeeze,
	# detach or reserve holds that size, the no-room rule applies instead:
	# requested size, clamped inside the work area, minimum overlap over the
	# right/left/below candidates.
	lassign [dict get $plan geometry] _ _ pw ph
	if {($pw < $rw || $ph < $rh) && $rw <= $ww-$fw && $rh <= $wh-$fh
		&& ![info exists BesideMinimums($dlg)] && ![dict exists $plan pair]} {
		set plan [besideNoRoomPlan $bx $by $bw $bh $rw $rh $workarea $extents 12 $peers \
			[besideBoardRect]]
	}
	if {[llength $peers] && ![dict exists $plan pair]} {
		lassign [dict get $plan geometry] gx gy gw gh
		set outer [list $gx $gy [expr {$gw+$fw}] [expr {$gh+$fh}]]
		set covered 0
		foreach other $peers {
			if {[besideOverlap $outer [besidePeerRect $other]]} { set covered 1 }
		}
		if {$covered} {
			set stacked [besidePairPlan $dlg $peers $rw $rh $workarea $extents 12]
			if {![llength $stacked]} {
				set stacked [besidePairNoRoom $dlg $peers $rw $rh $workarea $extents 12]
			}
			set plan $stacked
			dict set plan pair 1
			set pair 1
		}
	}
	# The first dialog keeps the plain three-candidate minimum. Only a
	# later dialog filters out peer-covered candidates (017B decision).
	# The later dialog is re-planned against this request in the same pass.
	if {!$follower && [llength $peers] && [dict get $plan rule] eq "no-room"
		&& ![dict exists $plan forced] && $rw <= $ww-$fw && $rh <= $wh-$fh} {
		lassign [besideProtectedRect] ax ay aw ah
		set plan [besideNoRoomPlan $ax $ay $aw $ah $rw $rh $workarea $extents 12 \
			$peers [besideBoardRect]]
		dict set plan pair 1
	}
	dict set plan first [expr {!$follower}]
	if {[dict get $plan overlap] > 0 && ($rw > $ww-$fw || $rh > $wh-$fh)} {
		set minw [expr {min(320,$rw)}]
		set minh [expr {min(160,$rh)}]
		foreach {aw ah} [list \
			[expr {$wx+$ww-$bx-$bw-12-$fw}] [expr {$wh-$fh}] \
			[expr {$bx-$wx-12-$fw}] [expr {$wh-$fh}] \
			[expr {$ww-$fw}] [expr {$wy+$wh-$by-$bh-12-$fh}]] {
			set cw [expr {min($rw,$aw)}]
			set ch [expr {min($rh,$ah)}]
			if {$cw < $minw || $ch < $minh} { continue }
			set capped [besidePlan $bx $by $bw $bh $cw $ch $workarea $extents]
			if {[dict get $capped overlap] == 0} {
				set plan $capped
				dict set plan resized 1
				break
			}
		}
	}
	lassign [dict get $plan geometry] x y w h
	# openbox applies +x to the client, not the frame: at the left edge of
	# the work area the left border would fall outside it.
	variable BesideState
	if {![info exists BesideState($dlg,extents)] && [dict exists $plan pair]
		&& $x < $wx + $el && $x + $w + $fw + $el <= $wx + $ww} {
		set x [expr {$wx + $el}]
	}
	wm minsize $dlg [expr {min($mw, $w)}] [expr {min($mh, $h)}]
	if {![info exists BesideRequests($dlg)]} {
		bind $dlg <Configure> +[namespace code [list BesideConfigure $dlg $parent]]
		bind $dlg <Destroy> +[namespace code [list BesideDestroy $dlg %W]]
	}
	set BesideRequests($dlg) [list $rw $rh]
	# Clear any old explicit size, including saved geometry. Lowering minsize
	# alone suffices for the requested-size retry. Only content larger than the
	# entire work area needs an explicit cap (VAL-DLG-004).
	wm geometry $dlg ""
	if {$w < $rw || $h < $rh} {
		wm geometry $dlg "${w}x${h}+${x}+${y}"
	} else {
		wm geometry $dlg "+${x}+${y}"
	}
	variable BesideState
	variable BesideTrigger
	set BesideState($dlg,request) [list $x $y]
	if {$w < $rw || $h < $rh} { lappend BesideState($dlg,request) $w $h }
	set BesideState($dlg,planned) [list $x $y [expr {$w+$fw}] [expr {$h+$fh}]]
	set BesideState($dlg,trigger) $BesideTrigger
	# A genuinely tiny work area can still force the frame over the pane.
	# The inset must never be the window that loses: move or shrink it
	# inside the pane first (restored on close/media stop).
	if {!$foreign} { besideDodgeVideo $dlg $x $y $w $h $extents }
	besideRegistryAdd $dlg $parent
	# VAL-DLG-017B: every beside-board call registers a live reserve owner
	# at once, the first dialog of a pair included.
	if {$pair} {
		foreach other $peers { besideShareReserve $other }
	}
	besideShareReserve $dlg
	variable BesideLastPlan
	set BesideLastPlan($dlg) $plan
	# The record exists as soon as the plan is applied; besideCapture
	# replaces its rectangle with the one the WM produced.
	besideRecord $dlg planner "" [list $x $y [expr {$w+$fw}] [expr {$h+$fh}]]
	return $plan
}


# The toplevel bind tag also receives descendants' Configure events. Coalesce
# them, and react only to a changed content request, not to user moves/resizes.
proc BesideConfigure {dlg parent} {
	variable BesideRequests
	variable BesidePending
	if {![info exists BesideRequests($dlg)] || [info exists BesidePending($dlg)]} { return }
	if {$BesideRequests($dlg) eq [list [winfo reqwidth $dlg] [winfo reqheight $dlg]]} {
		# Same content size: this is a move or a user resize. Let the
		# debounced settle notice it (and re-place only if it covers the
		# board); the board motion itself is scheduled from its own hooks.
		besideSchedule
		return
	}
	# A timer avoids re-entering placement from a caller's update idletasks.
	set BesidePending($dlg) [after 0 [namespace code [list BesideReflow $dlg $parent]]]
}

proc BesideReflow {dlg parent} {
	variable BesidePending
	unset BesidePending($dlg)
	if {[winfo exists $dlg]} { besideSchedule }
}

proc BesideDestroy {dlg window} {
	variable BesideRequests
	variable BesidePending
	if {$window ne $dlg} { return }
	unset -nocomplain BesideRequests($dlg)
	if {[info exists BesidePending($dlg)]} {
		after cancel $BesidePending($dlg)
		unset BesidePending($dlg)
	}
	besideRegistryRemove $dlg
}


proc position {path args} {
	lassign [geometry $path {*}$args] x y _ _
	wm geometry $path "${x}${y}"
}


proc size {path args} {
	lassign [geometry $path {*}$args] _ _ w h
	wm geometry $path "${w}x${h}"
}


proc getWmFrameExtents {w} {
	return -code error "[namespace current]::getWmFrameExtents is not implemented"
}


proc getWmWorkArea {w} {
	return -code error "[namespace current]::getWmWorkArea is not implemented"
}

} ;# namespace place
} ;# namespace util


rename winfo __place_winfo_orig

proc winfo {args} {
	if {[llength $args] > 0} {
		set cmd [lindex $args 0]
		if {$cmd eq "extents"} {
			if {[llength $args] < 2} {
				return -code error "wrong # args: should be \"winfo extents window\""
			}
			set extents [::util::place::getWmFrameExtents [lindex $args 1]]
			if {[llength $extents] == 0} { set extents {6 6 30 6} }
			return $extents
		} elseif {[string match workarea* $cmd]} {
			variable util::place::mainWindow
			set window .
			lassign $args cmd window
			if {[winfo exists $mainWindow]} {
				set workarea [::util::place::getWmWorkArea $mainWindow]
			} else {
				set workarea [::util::place::getWmWorkArea $window]
			}
			if {[llength $workarea] == 0} {
				set w [__place_winfo_orig screenwidth $window]
				set h [__place_winfo_orig screenheight $window]
				if {$cmd eq "workarea"} { return [list 0 0 $w $h] }
				set x 0
				set y 0
			} else {
				if {$cmd eq "workarea"} { return $workarea }
				lassign $workarea x y w h
			}
			switch $cmd {
				workareawidth 	{ return $w }
				workareaheight	{ return $h }
				workareax		{ return $x }
				workareay		{ return $y }
			}
		}
	}

	return [uplevel 1 __place_winfo_orig $args]
}

# vi:set ts=3 sw=3:
