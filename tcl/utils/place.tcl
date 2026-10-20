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
# A dialog the user dragged away from its planned rectangle is left alone
# unless that move puts it over the board.
variable BesideDelay		260
variable BesideTimer		{}
variable BesideDialogs		{}
variable BesideState
variable BesideReplacements	0
variable BesideBoardBound	{}


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


# Pure placement plan. Geometry is {outerX outerY clientWidth clientHeight};
# workarea is {x y width height}, extents {left right top bottom}.
# Prefer right, left, below at the current size, then at the requested content
# size (the 2026-10-18 minsize decision). VAL-DLG-004: if neither size fits,
# choose the least actual board intersection of the three CLAMPED outer
# rectangles, including the frame. Ties retain right/left/below order.
proc besidePlan {bx by bw bh dw dh workarea {extents {16 0 40 0}} {gap 12} {requested {}}} {
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
	return [dict create geometry [dict get $candidates $bestSide] \
		rule [expr {$bestArea == 0 ? $bestSide : "no-room"}] side $bestSide \
		overlap $bestArea candidates $candidates areas $areas \
		resized [expr {$cw != $dw || $ch != $dh}]]
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
	return [list [winfo rootx $board] [winfo rooty $board] \
		[winfo width $board] [winfo height $board]]
}

proc besideRect {w} {
	return [list [winfo rootx $w] [winfo rooty $w] \
		[winfo width $w] [winfo height $w]]
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

	if {![llength $BesideDialogs]} { return }
	if {$BesideTimer ne {}} { after cancel $BesideTimer }
	if {$delay eq ""} { set delay $BesideDelay }
	set BesideTimer [after $delay [namespace code besideSettle]]
}

# Every input that can invalidate a placement with an unchanged board.
proc besideContext {dlg} {
	set cls [winfo class $dlg]
	set extents {0 0 0 0}
	if {$cls ni {Menu OptionMenu} && ![wm overrideredirect $dlg]} {
	 set extents [winfo extents $dlg]
	}
	return [list [winfo workarea $dlg] $extents \
	 [list [winfo reqwidth $dlg] [winfo reqheight $dlg]] \
	 [wm minsize $dlg] [wm maxsize $dlg]]
}
proc besideOuterRect {dlg} {
	lassign [besideRect $dlg] x y w h
	lassign [lindex [besideContext $dlg] 1] l r t b
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
proc besideCapture {dlg} {
	variable BesideState
	if {![winfo exists $dlg] || ![winfo ismapped $dlg]} { return }
	set BesideState($dlg,last) [besideRect $dlg]
	set BesideState($dlg,board) [besideBoardRect]
	set BesideState($dlg,context) [besideContext $dlg]
	set BesideState($dlg,user) 0
}

proc besideRegistryAdd {dlg parent} {
	variable BesideDialogs
	variable BesideState
	variable BesideBoardBound

	set BesideState($dlg,parent) $parent
	if {$dlg ni $BesideDialogs} { lappend BesideDialogs $dlg }

	if {[catch { set board $::application::board::board }]} { set board {} }
	if {$board ne {} && [winfo exists $board] && $BesideBoardBound ne $board} {
		bind $board <Configure> +[namespace code besideSchedule]
		set BesideBoardBound $board
	}

	# The WM applies wm geometry asynchronously (and callers deiconify after
	# besideBoard returns), so record the produced rectangle on idle rather
	# than reading a half-applied one and mistaking it for a user move.
	set BesideState($dlg,last) {}
	set BesideState($dlg,board) [besideBoardRect]
	set BesideState($dlg,context) [besideContext $dlg]
	set BesideState($dlg,user) 0
	after idle [namespace code [list besideCapture $dlg]]
}

proc besideRegistryRemove {dlg} {
	variable BesideDialogs
	variable BesideState
	set i [lsearch -exact $BesideDialogs $dlg]
	if {$i >= 0} { set BesideDialogs [lreplace $BesideDialogs $i $i] }
	array unset BesideState ${dlg},*
}

proc besideSettle {} {
	variable BesideTimer
	variable BesideDialogs
	variable BesideState
	variable BesideReplacements

	set BesideTimer {}
	set boardRect [besideBoardRect]
	if {$boardRect eq {}} { return }
	# A reflow freezes the twm while it loads; placing against an
	# intermediate rectangle would be visible. Wait for the load to finish.
	if {[info exists ::application::Vars(loading)] && $::application::Vars(loading)} {
		besideSchedule 80
		return
	}

	set replan {}
	foreach dlg $BesideDialogs {
		if {![winfo exists $dlg]} { besideRegistryRemove $dlg; continue }
		if {![winfo ismapped $dlg]} { continue }
		set current [besideRect $dlg]
		set context [besideContext $dlg]
		set unchanged [expr {$boardRect eq $BesideState($dlg,board)
			&& $context eq $BesideState($dlg,context)}]
		if {![info exists BesideState($dlg,last)] || $BesideState($dlg,last) eq {}} {
			# Waiting for the idle capture of the rectangle the placement
			# produced: not a user move. If a placement input changed in
			# between, fall through and re-plan.
			if {$unchanged} {
				set BesideState($dlg,last) $current
				set BesideState($dlg,user) 0
				continue
			}
			set BesideState($dlg,user) 0
		} elseif {[besideRectDiffers $current $BesideState($dlg,last)]} {
			# Content growth changes client size without a user resize.
			if {[lindex $context 2] eq [lindex $BesideState($dlg,context) 2]
				|| [besideRectDiffers [concat [lrange $current 0 1] {0 0}] \
					[concat [lrange $BesideState($dlg,last) 0 1] {0 0}]]} {
				set BesideState($dlg,user) 1
			}
		}
		if {$BesideState($dlg,user)} {
			# Respect user placement while its whole frame remains usable.
			set outer [besideOuterRect $dlg]
			if {[besideOverlap $outer $boardRect] == 0
				&& [besideInside $outer [lindex $context 0]]} { continue }
		} elseif {$unchanged} {
			# No placement input changed.
			continue
		}
		lappend replan $dlg
	}

	foreach dlg $replan {
		if {[catch { besideBoard $dlg $BesideState($dlg,parent) }]} { continue }
		incr BesideReplacements
	}
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
# VAL-DLG-005: content larger than the work area already needs a size cap.
# In that case cap into a free right/left/below strip first, retaining at least
# 320x160 client pixels (or the smaller natural request). Ordinary content keeps
# its requested size, so labels/buttons are not silently clipped. If no strip
# accommodates that usable floor, retain the work-area cap and use no-room:
# overlap is allowed only at the minimum measured intersection of the three
# clamped candidates, never more than the plan's recorded minimum area.
proc besideBoard {dlg {parent ""}} {
	variable BesideRequests
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
	update idletasks
	lassign [wm minsize $dlg] mw mh
	lassign [wm maxsize $dlg] maxw maxh
	set rw [winfo reqwidth $dlg]
	set rh [winfo reqheight $dlg]
	set dw [expr {min($maxw, max($rw, $mw))}]
	set dh [expr {min($maxh, max($rh, $mh))}]
	set bx [winfo rootx $board]
	set by [winfo rooty $board]
	set bw [winfo width $board]
	set bh [winfo height $board]
	set workarea [winfo workarea $dlg]
	set cls [winfo class $dlg]
	if {$cls eq "Menu" || $cls eq "OptionMenu" || [wm overrideredirect $dlg]} {
		set extents {0 0 0 0}
	} else {
		set extents [winfo extents $dlg]
	}
	set plan [besidePlan $bx $by $bw $bh $dw $dh $workarea $extents 12 [list $rw $rh]]
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el+$er}]
	set fh [expr {$et+$eb}]
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
	besideRegistryAdd $dlg $parent
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
