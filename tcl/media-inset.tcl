# ======================================================================
# Video inside the board window.
#
# While a video plays, it can be shown inside the board pane, in a small
# window at the board's bottom-right, instead of in the Media pane. The
# small window's expand button swaps size and place with the board: the
# video fills the pane and the board becomes the small window; pressing
# it again swaps back.
#
# The media panel asks for its video surface through ::mediainset::surface
# (app-media.tcl PlayInProcess); mpv draws into that canvas's native
# window, so swapping only moves and resizes windows and the video keeps
# playing. Turning the option on or off during playback restarts the
# video on the other surface at the same time.
#
#   ::mediainset::surface $fallback   -> the canvas to play video on
#   ::mediainset::hide                 when playback stops
#   ::mediainset::swap                 the expand button
# ======================================================================

::util::source media-inset

namespace eval ::mediainset {
namespace eval mc {

set ShowInBoard	"Show Video in the Board Window"
# Button faces: the inset's size control names its state (Expand vs Restore).
set Expand		"⤢"
set Restore		"⤡"
# Button tooltips mention both the state and the double-click gesture.
set ExpandTip	"Expand (double-click the video to expand)"
set RestoreTip	"Restore (double-click the video to restore)"
# Hovering the video names the double-click gesture for the current state.
set VideoExpand	"Double-click to expand"
set VideoRestore	"Double-click to restore"
# Live tooltip texts, registered with the tooltip module and switched by state.
set ExpandTooltip	"Expand (double-click the video to expand)"
set VideoTooltip	"Double-click to expand"

} ;# namespace mc

array set Options {
	enabled 1
	size 0.34
	margin 6
	minWidth 160
}

# Gap between the inset frame and the pane edge when the video fills the pane,
# and the inset for the small board overlay inside the video's own frame.
variable FrameMargin 6
variable BoardGap 10

# swapped: the video fills the pane and the board is the small window
variable Swapped 0
variable Shown 0
variable Audio 0
variable Aspect [expr {16.0/9}]
variable LayingOut 0
variable Held 0
variable HeldPlace {}
variable Watched {}
# A dialog too large for every strip outside the board pane can still be
# kept off the video: the inset moves (and shrinks) within the pane. The
# list is {paneX paneY width height}; DodgeFor names the owning dialog so a
# close puts the inset back. VAL-DLG-013.
variable Dodge {}
variable DodgeFor {}
# A dialog that cannot keep its usable size beside the current strip may
# make the inset move to the other side of the pane and shrink there. The
# list is {side pixels}; SqueezeFor names the owning dialog.
variable Squeeze {}
variable SqueezeFor {}
# Last resort: the inset leaves the reserved strip entirely and parks in a
# free margin of the pane, without covering the board. Detach is
# {paneX paneY width height}; DetachFor names the owning dialog.
variable Detach {}
variable DetachFor {}
# Sashes captured when the video fills the pane, restored by the same-size
# swap back so a resize while expanded cannot leave the board pane at its
# minimum (MED-009: restore returns the prior placement and sizes).
variable SwapSashes {}

} ;# namespace mediainset


# The board pane and its canvas, or "" when the board is not built.
proc ::mediainset::Pane {} {
	if {[catch { set canv $::application::board::Vars(widget:frame) }] || ![winfo exists $canv]} {
		return ""
	}
	return [winfo parent $canv]
}


# The canvas the video is drawn on: the inset's when the option is on and
# the board exists, otherwise <fallback> (the Media pane's viewer).
proc ::mediainset::surface {fallback} {
	variable Options

	set pane [Pane]
	if {!$Options(enabled) || $pane eq ""} {
		hide
		return $fallback
	}
	set w $pane.mediainset
	if {![winfo exists $w]} { Build $w }
	AudioOnly 0
	Show
	# mpv embeds into the canvas's native window, which must be mapped: a
	# window created just now is not until the server has answered
	if {![SurfaceReady $w]} {
		# an unmapped canvas (the pane is hidden, or still 1x1 before its
		# first layout) has no usable native window for the backend to bind
		# to: play on the Media pane's viewer instead
		hide
		return $fallback
	}
	# the events handled above may have stopped an earlier playback
	Show
	return $w.video
}


# Map $w.video through the event loop; 1 when it is on screen with a real
# size, 0 when after about half a second it is still unmapped or 1x1 (the
# pane cannot show it). The backends bind the canvas's native window: an
# unmapped or 1x1 canvas is a native window nothing can ever render into.
proc ::mediainset::SurfaceReady {w} {
	update idletasks
	for {set i 0} {$i < 20} {incr i} {
		if {![winfo exists $w.video]} { return 0 }
		if {[winfo ismapped $w.video]
			&& [winfo width $w.video] > 1 && [winfo height $w.video] > 1} { return 1 }
		update
		after 25
	}
	return 0
}


proc ::mediainset::Build {w} {

	# a visible frame, so the video reads as a window of its own over or beside the board
	tk::frame $w -background black -borderwidth 3 -relief ridge \
		-highlightthickness 1 -highlightbackground #7a7a7a -highlightcolor #7a7a7a
	canvas $w.video -background black -highlightthickness 0 -borderwidth 0
	ttk::frame $w.controls
	ttk::button $w.controls.play -text "▶" -width 2 -command ::application::media::TogglePlayback
	ttk::button $w.controls.prev -text "|‹" -width 2 -command {::application::media::ChapterStep -1}
	ttk::button $w.controls.next -text "›|" -width 2 -command {::application::media::ChapterStep 1}
	ttk::button $w.controls.stop -text Stop -width 4 -command ::application::media::Stop
	ttk::button $w.expand -text $::mediainset::mc::Expand -width 2 -takefocus 0 -command [namespace code swap]
	catch { ::tooltip::tooltip $w.expand [namespace current]::mc::ExpandTooltip }
	ttk::button $w.controls.stream -text "Open stream..." -command [list ::application::media::OpenStream $w]
	ttk::label $w.controls.time -textvariable ::application::media::Priv(seeklabel)
	ttk::scale $w.controls.seek -orient horizontal -from 0 -to 1000 -value 0 -length 45
	bind $w.controls.seek <ButtonPress-1> {+set ::application::media::Priv(seekgrab) 1}
	bind $w.controls.seek <ButtonRelease-1> +[list ::application::media::SeekRelease $w.controls.seek]
	bind $w.controls.seek <KeyRelease> {
		if {%K in {Left Right Up Down Prior Next Home End}} {
			::application::media::SeekRelease %W
		}
	}
	# Compact rows keep the transport usable in a 160px video strip.
	pack $w.controls -side bottom -fill x
	grid $w.controls.play $w.controls.prev $w.controls.next $w.controls.stop -sticky ew
	grid $w.expand -in $w.controls -row 2 -column 4
	grid $w.controls.stream -row 2 -column 0 -columnspan 4 -sticky ew
	grid $w.controls.seek -row 1 -column 0 -columnspan 3 -sticky ew
	grid $w.controls.time -row 1 -column 3 -columnspan 2 -sticky ew
	grid columnconfigure $w.controls 0 -weight 1
	pack $w.video -side top -fill both -expand yes
	bind $w <space> {::application::media::TogglePlayback; break}
	bindtags $w.video [linsert [bindtags $w.video] 1 $w]
	bind $w.video <Button-1> [list focus $w]
	# Include the frame binding for focusable transport children, too.
	foreach child [winfo children $w.controls] {
		bindtags $child [linsert [bindtags $child] 1 $w]
	}
	bind $w <Destroy> [list ::mediainset::Teardown $w %W]
	RefreshControls
	# double-click on the video swaps as well
	bind $w.video <Double-Button-1> [namespace code swap]
	# Escape while the inset has focus restores the previous placement
	bind $w <Escape> [namespace code Escape]
	# hovering the video names the double-click gesture for the current state
	catch { ::tooltip::tooltip $w.video [namespace current]::mc::VideoTooltip }
}


proc ::mediainset::Show {} {
	variable Shown
	set Shown 1
	Layout
}


proc ::mediainset::hide {} {
	variable Shown
	variable Swapped
	variable Dodge
	variable DodgeFor
	variable Squeeze
	variable SqueezeFor
	variable Detach
	variable DetachFor

	set pane [Pane]
	set Shown 0
	set ::mediainset::HeldPlace {}
	set Dodge {}
	set DodgeFor {}
	set Squeeze {}
	set SqueezeFor {}
	set Detach {}
	set DetachFor {}
	Unwatch
	if {$pane eq ""} {
		# During <Destroy> the board may already have gone away.
		set ::application::board::ReserveSide {}
		set ::application::board::ReservePixels 0
		set ::application::board::ReserveKind auto
		return
	}
	::application::board::setReserve {} 0
	FrameView 0
	if {[winfo exists $pane.mediainset]} { place forget $pane.mediainset }
	if {$Swapped} {
		set Swapped 0
		RestoreBoard $pane
	}
	# Stopping or hiding the video changes the protected area and releases
	# the strip it owned. Re-plan every open dialog against the regrown
	# board; without this it stays at its squeezed position (VAL-DLG-014d).
	if {[llength [info commands ::util::place::besideVideoChanged]]} {
		catch { ::util::place::besideVideoChanged }
	}
}


proc ::mediainset::swap {} {
	variable Swapped
	variable Shown
	variable SwapSashes

	if {!$Shown} { return }
	set was $Swapped
	set Swapped [expr {!$Swapped}]
	if {$Swapped && !$was} {
		# Snapshot the pane arrangement before the board is unpacked: while
		# the video fills the pane a window resize can squeeze the board
		# pane to its minimum, and the restore must put the user's
		# arrangement back (MED-009 after resize/fullscreen).
		set SwapSashes {}
		if {![catch { set t [::application::twm] }] && $t ne ""} {
			set top [winfo toplevel $t]
			set SwapSashes [list [list [winfo width $top] [winfo height $top]] \
				[::application::focuszoom::Snapshot $t] [PaneSizes $t]]
		}
	}
	Layout
	if {!$Swapped && $was && [llength $SwapSashes] == 3} {
		set t {}
		if {![catch { set t [::application::twm] }] && $t ne "" && [winfo exists $t]} {
			set top [winfo toplevel $t]
		}
		lassign $SwapSashes size snapshot sizes
		# Only at the size the snapshot belongs to: after a resize the old
		# coordinates would clamp the panes to their minima for good (the
		# same rule focuszoom uses for its own baseline).
		if {$t ne "" && [list [winfo width $top] [winfo height $top]] eq $size} {
			RestoreSashes $t $snapshot $sizes
		}
		set SwapSashes {}
	}
}


# A layout reload between the two swaps (the tall reflow a portrait
# fullscreen takes) rebuilds the panedwindows under new paths, in the same
# traversal order. Pair the recorded snapshot with the live panedwindows;
# returns {} when the structures no longer correspond, so a stale snapshot
# can never place a sash on the wrong pane.
proc ::mediainset::MapSnapshot {snapshot live} {
	if {[llength $live] != [llength $snapshot]} { return {} }
	set mapped {}
	foreach {oldPw oldCoords} $snapshot {newPw newCoords} $live {
		if {[llength $newCoords] != [llength $oldCoords]} { return {} }
		lappend mapped $newPw $oldCoords
	}
	return $mapped
}


# Put the recorded arrangement back. A pane may have been squeezed below its
# -minsize at the old window size (Tk shrinks panes on a window resize
# without moving a sash), so relax that minimum to the recorded size first,
# by pane order (the paths change with the reload too); otherwise Tk clamps
# the sash a few pixels short and the restore silently fails.
proc ::mediainset::RestoreSashes {twm snapshot sizes} {
	set live [::application::focuszoom::Snapshot $twm]
	set mapped [MapSnapshot $snapshot $live]
	if {![llength $mapped]} { return 0 }
	# Already in force: nothing to place. Restoring would pump the event
	# loop (focuszoom::Restore), and an unrelated model update (the media
	# Stop path) would then hide the inset this swap is putting back.
	set same 1
	foreach {pw coords} $mapped {nowPw nowCoords} $live {
		if {$coords ne $nowCoords} { set same 0; break }
	}
	if {$same} { return 0 }
	set livePw {}
	foreach {pw coords} $live { lappend livePw $pw }
	array set index {}
	set i 0
	foreach {oldPw coords} $snapshot { set index($oldPw) $i; incr i }
	array set ordinal {}
	foreach {w p sz} $sizes {
		if {![info exists index($w)]} { continue }
		set newPw [lindex $livePw $index($w)]
		set n [expr {[info exists ordinal($w)] ? [incr ordinal($w)] : [set ordinal($w) 0]}]
		if {![winfo exists $newPw] || $n >= [llength [$newPw panes]]} { continue }
		set newPane [lindex [$newPw panes] $n]
		if {[$newPw panecget $newPane -minsize] > $sz} {
			$newPw paneconfigure $newPane -minsize $sz
		}
	}
	::application::focuszoom::Restore $twm $mapped
	return 1
}


# Pane sizes at the moment of the expand snapshot, flattened as
# {panedwindow pane size ...}. focuszoom::Snapshot records only sash
# coordinates, which Tk refuses when a pane is below its -minsize.
proc ::mediainset::PaneSizes {twm} {
	set result {}
	set queue [winfo children $twm]
	while {[llength $queue]} {
		set queue [lassign $queue w]
		lappend queue {*}[winfo children $w]
		if {![string match *Panedwindow [winfo class $w]]} { continue }
		set dim [expr {[$w cget -orient] eq "horizontal" ? "width" : "height"}]
		foreach p [$w panes] { lappend result $w $p [winfo $dim $p] }
	}
	return $result
}


proc ::mediainset::swapped? {} {
	variable Swapped
	return $Swapped
}


# Escape while the inset has focus restores the video and board to their
# previous placement. It is a no-op when the inset is not swapped, so the
# key stays available to whatever else owns it.
proc ::mediainset::Escape {} {
	variable Swapped
	if {!$Swapped} { return }
	swap
	return -code break
}


# The size control names its state: Expand (⤢) in the normal strip/corner
# layout, Restore (⤡) once the video fills the pane. The tooltips follow the
# state too, so they always name the gesture a click or double-click performs.
proc ::mediainset::RefreshSwapControl {} {
	variable Swapped
	set pane [Pane]
	if {$pane eq ""} { return }
	set w $pane.mediainset
	if {![winfo exists $w.expand]} { return }
	if {$Swapped} {
		$w.expand configure -text $::mediainset::mc::Restore
		set ::mediainset::mc::ExpandTooltip $::mediainset::mc::RestoreTip
		set ::mediainset::mc::VideoTooltip $::mediainset::mc::VideoRestore
	} else {
		$w.expand configure -text $::mediainset::mc::Expand
		set ::mediainset::mc::ExpandTooltip $::mediainset::mc::ExpandTip
		set ::mediainset::mc::VideoTooltip $::mediainset::mc::VideoExpand
	}
}


# Give the small board overlay a visible frame while the video fills the pane,
# so it reads as a window rather than a borderless fragment on the video. The
# board view's own highlight ring is used for both the 2D canvas and the 3D
# frame; its original options are restored when the board returns to the pane.
proc ::mediainset::FrameView {on} {
	variable ViewFrame
	set view [BoardView]
	if {$view eq "" || ![winfo exists $view]} { return }
	if {$on} {
		if {![info exists ViewFrame] || [dict get $ViewFrame path] ne $view} {
			set ViewFrame [dict create path $view \
				thickness [$view cget -highlightthickness] \
				background [$view cget -highlightbackground] \
				color [$view cget -highlightcolor]]
		}
		$view configure -highlightthickness 3 \
			-highlightbackground #7a7a7a -highlightcolor #7a7a7a
	} elseif {[info exists ViewFrame]} {
		if {[winfo exists $view] && [dict get $ViewFrame path] eq $view} {
			$view configure -highlightthickness [dict get $ViewFrame thickness] \
				-highlightbackground [dict get $ViewFrame background] \
				-highlightcolor [dict get $ViewFrame color]
		}
		unset ViewFrame
	}
}


# The visible board presentation; the 2D canvas is unmapped in 3D mode.
proc ::mediainset::BoardView {} {
	upvar #0 ::application::board::Vars vars
	if {$vars(3d) && [winfo exists $vars(3dwin)]} { return $vars(3dwin) }
	return $vars(widget:frame)
}

# BRD-004 arithmetic at the current tk scaling. A strip is feasible when
# its minimum extent can carry a video at least 160 px wide (the frame adds
# 8 px) and the board renderer accepts the reserve. The reserve is accepted
# when it costs the board no square, even below the fixed floor; only a
# reserve that really shrinks the drawn square is refused. reserveSquare
# therefore returns 0 exactly when the strip is unusable, and True here
# means no strip fits at all, the only condition for the corner overlay.
proc ::mediainset::Brd004Fallback {width height controlsHeight} {
	variable Aspect
	set minimumWidth 168
	set minimumHeight [expr {int(round(160/$Aspect)) + $controlsHeight}]
	set right [::application::board::reserveSquare right $minimumWidth $width $height]
	set bottom [::application::board::reserveSquare bottom $minimumHeight $width $height]
	return [expr {$right <= 0 && $bottom <= 0}]
}


# Place in board-pane coordinates. Only ComputeLayout's shrinking-reserve
# refusal permits an overlay. The eight-pixel frame margin is
# 2*(border + highlight).
proc ::mediainset::Layout {} {
	variable Options
	variable Swapped
	variable Shown
	variable Audio
	variable Aspect
	variable LayingOut
	variable FrameMargin
	variable BoardGap
	variable Dodge
	variable DodgeFor
	variable Squeeze
	variable SqueezeFor
	variable Detach
	variable DetachFor
	variable HeldPlace

	set pane [Pane]
	if {$pane eq "" || !$Shown || $LayingOut} { return }
	set w $pane.mediainset
	if {![winfo exists $w]} { return }
	set LayingOut 1
	try {
		Watch
		RefreshSwapControl
		set view [BoardView]
		set s $Options(size)
		set cw [expr {[winfo reqwidth $w.controls] + 8}]
		set ch [expr {[winfo reqheight $w.controls] + 8}]
		if {$Detach ne {} && (!$Swapped)
			&& (![winfo exists $DetachFor] || ![winfo ismapped $DetachFor])} {
			set Detach {}
			set DetachFor {}
		}
		if {$Detach ne {} && !$Swapped} {
			# Parked in a free margin: no strip is reserved for it.
			::application::board::setReserve {} 0
			FrameView 0
			RestoreBoard $pane
			lassign $Detach dx dy dw dh
			PlaceInset $w $pane $dx $dy $dw $dh
			raise $w
		} elseif {$Swapped && $Audio} {
			::application::board::setReserve {} 0
			FrameView 0
			RestoreBoard $pane
			set HeldPlace {}
			place $w -in $pane -x -$FrameMargin -y -$FrameMargin -relx 1 -rely 1 -anchor se \
				-width $cw -height $ch -relwidth {} -relheight {}
			raise $w
		} elseif {$Swapped} {
			::application::board::setReserve {} 0
			# Inset the video by its own frame margin rather than placing it
			# flush at 0,0: the ridge + highlight frame stays fully visible.
			set HeldPlace {}
			place $w -in $pane -x $FrameMargin -y $FrameMargin -relx 0 -rely 0 -anchor nw \
				-relwidth 1 -relheight 1 -width [expr {-2*$FrameMargin}] -height [expr {-2*$FrameMargin}]
			pack forget $view
			FrameView 1
			# Keep the small board away from the inset's transport cluster at
			# the pane's bottom-right. The top-left corner is free (the Media
			# button lives at the top-right), so the board never covers the
			# Expand/Restore control and the controls never cover board squares.
			place $view -in $pane -relx 0 -rely 0 -x $BoardGap -y $BoardGap -anchor nw \
				-relwidth $s -relheight $s -width {} -height {}
			raise $view
		} else {
			FrameView 0
			RestoreBoard $pane
			# Reconstruct the full slot from the VISIBLE 3D frame and its
			# reserve padding, rather than consulting the hidden 2D canvas.
			set width [winfo width $view]
			set height [winfo height $view]
			if {$::application::board::Vars(3d)} {
				switch $::application::board::ReserveSide {
					right - left { incr width $::application::board::ReservePixels }
					bottom { incr height $::application::board::ReservePixels }
				}
			}
			set side [expr {$width > $height ? "right" : "bottom"}]
			set iw $cw
			set ih $ch
			if {!$Audio} {
				set choice [FitStrip $width $height $ch]
				if {[llength $choice]} {
					lassign $choice side iw ih
				} elseif {[Brd004Fallback $width $height $ch]} {
					# BRD-004: no strip can carry a >=160 px video while
					# keeping the documented minimum square at this scaling,
					# so the board keeps its size and the inset overlays it.
					set side {}
					set iw [expr {max(168, int($height*$s*$Aspect)+8)}]
					set ih [expr {int(round(($iw-8)/$Aspect))+$ch}]
				} else {
					# The arithmetic says a minimum strip is feasible even
					# though FitStrip returned nothing (e.g. a transient
					# canvas): reserve that strip instead of covering the
					# board, so the overlay is never taken outside BRD-004.
					if {[::application::board::reserveSquare right 168 $width $height] \
						> 0} {
						set side right
						set iw 168
						set ih [expr {int(round(($iw-8)/$Aspect))+$ch}]
					} else {
						set side bottom
						set ih [expr {int(round(160/$Aspect))+$ch}]
						set iw [expr {int(round(($ih-$ch)*$Aspect))+8}]
					}
				}
			}
			# A dialog can ask the inset to yield its strip: move to
			# the other side and shrink to the documented minimum so the
			# dialog keeps every control at its requested size.
			set maxBoard 0
			if {$Squeeze ne {} && !$Audio} {
				if {![winfo exists $SqueezeFor]} {
					set Squeeze {}
					set SqueezeFor {}
				} else {
					lassign $Squeeze side iw maxBoard
					set ih [expr {int(round(($iw-8)/$Aspect))+$ch}]
				}
			}
			set pixels [expr {$side eq "right" || $side eq "left" ? $iw : $ih}]
			# A squeeze is the video yielding its strip to a dialog: it may
			# shrink the board, unlike the ordinary strip chosen by FitStrip.
			set kind [expr {$Squeeze ne {} && !$Audio ? "squeeze" : "auto"}]
			set mb [expr {$Squeeze ne {} && !$Audio && [string is integer -strict $maxBoard] ? $maxBoard : 0}]
			if {$side ne "" && [::application::board::setReserve $side $pixels $kind $mb]} {
				lassign [::application::board::reserveRect] x y rw rh
				set x [expr {$x + [winfo x $view] + ($rw - $iw)/2}]
				set y [expr {$y + [winfo y $view] + ($rh - $ih)/2}]
				PlaceInset $w $pane $x $y $iw $ih
			} else {
				::application::board::setReserve {} 0
				# Keep the usable transport, fitting the video to the pane.
				set iw [expr {min($iw, max(1, [winfo width $pane] - 12))}]
				set ih [expr {$Audio ? $ch : int(round(($iw - 8)/$Aspect)) + $ch}]
				set HeldPlace {}
				place $w -in $pane -x -6 -y -6 -relx 1 -rely 1 -anchor se \
					-width $iw -height $ih -relwidth {} -relheight {}
			}
			raise $w
		}
		# A dialog too large for the strips outside the pane may have made
		# the inset move inside the pane; keep that position across rebuilds
		# until the dialog closes or the media stops.
		if {$Dodge ne {}} {
			if {![winfo exists $DodgeFor]} {
				set Dodge {}
				set DodgeFor {}
			} else {
				lassign $Dodge dx dy dw dh
				PlaceInset $w $pane $dx $dy $dw $dh
				raise $w
			}
		}
		if {[winfo exists $pane.mediaButton]} { raise $pane.mediaButton }
	} finally {
		set LayingOut 0
	}
	if {[llength [info commands ::util::place::besideVideoChanged]]} {
		catch { ::util::place::besideVideoChanged }
	}
}


# Plan the final 2D reserve before the board paints a resized extent. The
# afterRebuild hook still places the inset; it need not repaint an obsolete
# board size first. 3D uses its realized frame/Configure path instead.
proc ::mediainset::reserveForLayout {width height} {
	variable Shown
	variable Swapped
	variable Audio
	variable Squeeze
	variable Detach
	if {!$Shown || $Swapped || $::application::board::Vars(3d)} { return {} }
	# A dialog asked the inset to move to the other side; the board rebuild
	# hook must keep that strip instead of re-planning the normal one.
	if {$Squeeze ne {} && !$Audio} {
		variable SqueezeFor
		lassign $Squeeze side strip oldCap
		if {$side eq "left" && [winfo exists $SqueezeFor]
			&& [winfo ismapped $SqueezeFor]} {
			# Tighten the dialog's cap before painting the new main extent.
			# Waiting for the placement pass paints the obsolete larger
			# board first, then immediately paints the tightened cap again.
			lassign [::util::place::besideMainArea $SqueezeFor] sx sy sw sh
			lassign [::util::place::besideDialogExtents $SqueezeFor] sl sr st sb
			lassign [wm minsize $SqueezeFor] mw mh
			lassign [wm maxsize $SqueezeFor] xw xh
			set needW [expr {min($xw,max($mw,[winfo reqwidth $SqueezeFor]))}]
			set needH [expr {min($xh,max($mh,[winfo reqheight $SqueezeFor]))}]
			set frame $::application::board::Vars(widget:frame)
			set cap [expr {$sx+$sw-[winfo rootx $frame]-$needW-$sl-$sr-12-$strip}]
			if {$cap > 0 && ($oldCap <= 0 || $cap < $oldCap)
				&& [::util::place::besideBorderRoom left $strip squeeze $cap \
					[list $sx $sy $sw $sh] [expr {$sl+$sr}] [expr {$st+$sb}] 12 $needW $needH]} {
				set Squeeze [list $side $strip $cap]
			}
		}
		return $Squeeze
	}
	if {$Detach ne {} && !$Audio} { return [list {} 0] }
	set w [Pane].mediainset
	if {![winfo exists $w.controls]} { return {} }
	set ch [expr {[winfo reqheight $w.controls]+8}]
	if {$Audio} {
		set side [expr {$width > $height ? "right" : "bottom"}]
		set pixels [expr {$side eq "right" ? [winfo reqwidth $w.controls]+8 : $ch}]
	} else {
		set choice [FitStrip $width $height $ch]
		if {![llength $choice]} { return [list {} 0] }
		lassign $choice side iw ih
		set pixels [expr {$side eq "right" ? $iw : $ih}]
	}
	return [list $side $pixels]
}


# The narrowest strip, in the same units FitStrip uses for a side reserve:
# the documented minimum video width plus the eight-pixel frame.
proc ::mediainset::MinimumStrip {} {
	variable Options
	return [expr {$Options(minWidth) + 8}]
}

# Fit each candidate down to the documented minimum VIDEO width (frame
# adds eight pixels). Prefer the side leaving the larger board, with a
# right-side tie break. Grow video only through otherwise unused space,
# preserving that board size. Apply the winning reserve once.
proc ::mediainset::FitStrip {width height controlsHeight} {
	variable Options
	variable Aspect
	set best {}
	set bestSquare 0
	set minimum 168
	# VAL-MED-012: the strip may not cost the drawn board a square. Compare
	# every candidate with the unreserved square, not merely with the fixed
	# floor, so a width-limited band cannot reserve a narrower board.
	set unreserved [::application::board::unreservedSquare $width $height]
	foreach side {right bottom} {
		set minimumHeight [expr {int(round(160/$Aspect))+$controlsHeight}]
		set px [expr {$side eq "right" ? $minimum : $minimumHeight}]
		set squareAtMinimum [::application::board::reserveSquare $side $px $width $height]
		# reserveSquare returns 0 when the strip really shrinks the board.
		# A below-floor square is still fine when the strip leaves it
		# unchanged, which is how a small board keeps its size and shifts.
		if {$squareAtMinimum <= 0 || $squareAtMinimum < $unreserved} { continue }
		set desired [expr {$side eq "right" ? int($height*$Options(size)*$Aspect)+8 : int($width*0.66)}]
		set lo $minimum
		set hi [expr {min(max($minimum,$Options(minWidth)+8,$desired), $width, int(($height-$controlsHeight)*$Aspect)+8)}]
		set candidate {}
		while {$lo <= $hi} {
			set iw [expr {($lo+$hi)/2}]
			set ih [expr {int(round(($iw-8)/$Aspect))+$controlsHeight}]
			set px [expr {$side eq "right" ? $iw : $ih}]
			set square [::application::board::reserveSquare $side $px $width $height]
			if {$square >= $unreserved && $square > 0} {
				set candidate [list $side $iw $ih]
				set candidateSquare $square
				set lo [expr {$iw+1}]
			} else {
				set hi [expr {$iw-1}]
			}
		}
		if {[llength $candidate] && $candidateSquare > $bestSquare} {
			set best $candidate
			set bestSquare $candidateSquare
		}
	}
	return $best
}


# Geometry helpers for keeping the video clear of a dialog.
proc ::mediainset::WidgetRect {w} {
	return [list [winfo rootx $w] [winfo rooty $w] \
		[winfo width $w] [winfo height $w]]
}
proc ::mediainset::Area {a b} {
	lassign $a ax ay aw ah
	lassign $b bx by bw bh
	return [expr {
		max(0, min($ax+$aw, $bx+$bw) - max($ax, $bx)) *
		max(0, min($ay+$ah, $by+$bh) - max($ay, $by))}]
}
proc ::mediainset::BoardRect {} {
	if {[llength [info commands ::util::place::besideBoardRect]]} {
		return [::util::place::besideBoardRect]
	}
	return [WidgetRect [BoardView]]
}

# Move (and if needed shrink) the visible inset to a free part of its own
# pane so <rect> (the dialog's decorated frame) does not cover it. Prefers a
# position that also leaves the drawn board clear; when the inset already
# overlays the board (BRD-004), only the dialog is avoided. Returns 1 when
# the inset was moved, 0 when it is already clear or nowhere is free.
proc ::mediainset::DodgeForDialog {dlg rect} {
	variable Shown
	variable Swapped
	variable Dodge
	variable DodgeFor
	variable Aspect

	if {!$Shown || $Swapped} { return 0 }
	set pane [Pane]
	if {$pane eq ""} { return 0 }
	set w $pane.mediainset
	if {![winfo exists $w] || ![winfo ismapped $w]} { return 0 }
	set video [rect]
	if {[Area $video $rect] == 0} { return 0 }
	set paneRect [WidgetRect $pane]
	set board [BoardRect]
	set boardOverlaid [expr {[Area $video $board] > 0}]
	set ch [expr {[winfo reqheight $w.controls] + 8}]
	set margin 6
	set minWidth 168
	lassign $video - - curW curH
	lassign $paneRect px py pw ph
	set best {}
	set bestScore -1
	# No candidate has been scored yet: an area cost is always >= 0, so a
	# sentinel of -1 can never be beaten and would make this dodge a no-op.
	set bestCost ""
	set iw $curW
	while {$iw >= $minWidth} {
		set ih [expr {int(round(($iw-8)/$Aspect)) + $ch}]
		if {$ih <= $ph - 2*$margin} {
			foreach cx [list [expr {$px+$margin}] [expr {$px+$pw-$iw-$margin}]] {
				foreach cy [list [expr {$py+$margin}] [expr {$py+$ph-$ih-$margin}]] {
					set cand [list $cx $cy $iw $ih]
					if {$cx < $px || $cy < $py
						|| $cx+$iw > $px+$pw || $cy+$ih > $py+$ph} { continue }
					if {[Area $cand $rect] > 0} { continue }
					set cost [expr {$boardOverlaid ? 0 : [Area $cand $board]}]
					set score [expr {$iw*$ih}]
					if {$bestCost eq ""
						|| $cost < $bestCost
						|| ($cost == $bestCost && $score > $bestScore)} {
						set best $cand
						set bestCost $cost
						set bestScore $score
					}
					if {$cost == 0} { set iw 0; break }
				}
				if {$iw == 0} { break }
			}
		}
		incr iw -16
	}
	if {$best eq {}} {
		Relayout
		return 0
	}
	lassign $best cx cy iw ih
	PlaceInset $w $pane [expr {$cx-$px}] [expr {$cy-$py}] $iw $ih
	raise $w
	set Dodge [list [expr {$cx-$px}] [expr {$cy-$py}] $iw $ih]
	set DodgeFor $dlg
	return 1
}

# Shrink/move the inset to <side> so a dialog can keep its usable size on
# the other side of the drawn board. Layout keeps the request until cleared.
proc ::mediainset::SqueezeForDialog {dlg side pixels {maxBoard 0}} {
	variable Shown
	variable Swapped
	variable Squeeze
	variable SqueezeFor
	if {!$Shown || $Swapped || $side ni {left right}} { return 0 }
	if {![string is integer -strict $pixels] || $pixels < 1} { return 0 }
	set pane [Pane]
	if {$pane eq "" || ![winfo exists $pane.mediainset]} { return 0 }
	set Squeeze [list $side $pixels $maxBoard]
	set SqueezeFor $dlg
	Layout
	return 1
}

# A dialog re-plan releases the squeeze, plans against the regrown inset and
# squeezes again. Placing the inset at each step makes it jump to the normal
# strip (often under the dialog) and back within milliseconds. The X server
# drops the embedded mpv window's contents where the dialog covered it, and
# the video is blank until mpv's next repaint. While a re-plan holds the
# inset, Layout records the placement instead (rect reports it); release
# applies only the final one, which is no change when the plan kept it.
proc ::mediainset::hold {} {
	variable Held
	variable HeldPlace
	if {[incr Held] > 1} { return }
	set HeldPlace {}
}

proc ::mediainset::release {} {
	variable Held
	variable HeldPlace
	variable Shown
	if {$Held > 0 && [incr Held -1] > 0} { return }
	set Held 0
	set where $HeldPlace
	set HeldPlace {}
	set pane [Pane]
	if {$where eq {} || !$Shown || $pane eq "" || ![winfo exists $pane.mediainset]} { return }
	PlaceInset $pane.mediainset $pane {*}$where
	raise $pane.mediainset
}

# Place the inset at {x y width height} in its pane, or record that while
# a re-plan holds the visible inset.
proc ::mediainset::PlaceInset {w pane x y width height} {
	variable Held
	variable HeldPlace
	if {$Held > 0 && [winfo ismapped $w]} {
		set HeldPlace [list $x $y $width $height]
		return
	}
	place $w -in $pane -x $x -y $y -width $width -height $height \
		-relx 0 -rely 0 -anchor nw -relwidth {} -relheight {}
}

# The inset's root rectangle {x y width height}, as placed or held.
proc ::mediainset::rect {} {
	variable HeldPlace
	set pane [Pane]
	if {$pane eq "" || ![winfo exists $pane.mediainset]} { return {} }
	if {$HeldPlace ne {}} {
		lassign $HeldPlace x y width height
		return [list [expr {[winfo rootx $pane] + $x}] [expr {[winfo rooty $pane] + $y}] \
			$width $height]
	}
	return [WidgetRect $pane.mediainset]
}

proc ::mediainset::ClearSqueeze {dlg} {
	variable Squeeze
	variable SqueezeFor
	if {$SqueezeFor eq "" || $SqueezeFor ne $dlg} { return 0 }
	set Squeeze {}
	set SqueezeFor {}
	Relayout
	return 1
}

# Last resort for a dialog too large for every strip: release the video's
# reserve and park the inset in a free margin of the pane, shrinking it as
# needed so it covers neither the drawn board nor the dialog placed on
# <side>. <targetW>/<targetH> are the dialog's usable client size.
# A placement batch can leave a failed trial released until its next side;
# it must call ClearDetach if none succeeds. Ordinary callers restore here.
proc ::mediainset::DetachForDialog {dlg side targetW targetH workarea extents gap {restoreOnFailure 1}} {
	variable Shown
	variable Swapped
	variable Detach
	variable DetachFor
	variable Aspect
	if {!$Shown || $Swapped || $side ni {left right below}} { return 0 }
	set pane [Pane]
	if {$pane eq ""} { return 0 }
	set w $pane.mediainset
	if {![winfo exists $w] || ![winfo ismapped $w]} { return 0 }
	# The board reclaims the strip; mark the detach first so the board's own
	# reserve hook does not put it straight back while we measure.
	set DetachFor $dlg
	set Detach {0 0 0 0}
	::application::board::setReserve {} 0
	update idletasks
	set paneRect [WidgetRect $pane]
	set board [BoardRect]
	if {[lindex $board 2] < 2 || [lindex $board 3] < 2} {
		if {$restoreOnFailure} {
			set Detach {}
			set DetachFor {}
			Relayout
		}
		return 0
	}
	lassign $workarea wx wy ww wh
	lassign $extents el er et eb
	set fw [expr {$el+$er}]
	set fh [expr {$et+$eb}]
	set cw [expr {min($targetW, $ww - $fw)}]
	set ch [expr {min($targetH, $wh - $fh)}]
	lassign $board bx by bw bh
	switch $side {
		right { set x [expr {$bx + $bw + $gap}]; set y $by }
		left  { set x [expr {$bx - $gap - $cw - $fw}]; set y $by }
		below { set x $bx; set y [expr {$by + $bh + $gap}] }
	}
	set cx [expr {max($wx, min($x, $wx + $ww - $cw - $fw))}]
	set cy [expr {max($wy, min($y, $wy + $wh - $ch - $fh))}]
	set dialog [list $cx $cy [expr {$cw+$fw}] [expr {$ch+$fh}]]
	# Shrink the inset until a pane corner is free of the board and dialog.
	set controls [expr {[winfo reqheight $w.controls] + 8}]
	set margin 6
	set minWidth 96
	set curW [lindex [rect] 2]
	lassign $paneRect px py pw ph
	set best {}
	set bestScore -1
	set iw $curW
	while {$iw >= $minWidth} {
		set ih [expr {int(round(($iw-8)/$Aspect)) + $controls}]
		if {$ih <= $ph - 2*$margin} {
			foreach x [list [expr {$px+$margin}] [expr {$px+$pw-$iw-$margin}]] {
				foreach y [list [expr {$py+$margin}] [expr {$py+$ph-$ih-$margin}]] {
					set cand [list $x $y $iw $ih]
					if {$x < $px || $y < $py
						|| $x+$iw > $px+$pw || $y+$ih > $py+$ph} { continue }
					if {[Area $cand $dialog] > 0 || [Area $cand $board] > 0} {
						continue
					}
					set score [expr {$iw*$ih}]
					if {$score > $bestScore} {
						set best $cand
						set bestScore $score
					}
				}
			}
			if {$best ne {}} { break }
		}
		incr iw -8
	}
	if {$best eq {}} {
		if {$restoreOnFailure} {
			set Detach {}
			set DetachFor {}
			Relayout
		}
		return 0
	}
	lassign $best x y iw ih
	PlaceInset $w $pane [expr {$x-$px}] [expr {$y-$py}] $iw $ih
	raise $w
	set Detach [list [expr {$x-$px}] [expr {$y-$py}] $iw $ih]
	return 1
}

proc ::mediainset::ClearDetach {dlg} {
	variable Detach
	variable DetachFor
	if {$DetachFor eq "" || $DetachFor ne $dlg} { return 0 }
	set Detach {}
	set DetachFor {}
	Relayout
	return 1
}

# Put the inset back after the dialog that displaced it goes away.
proc ::mediainset::RestoreAfterDialog {dlg} {
	variable Dodge
	variable DodgeFor
	variable Squeeze
	variable SqueezeFor
	variable Detach
	variable DetachFor
	set hit 0
	if {$DodgeFor ne "" && $DodgeFor eq $dlg} {
		set Dodge {}
		set DodgeFor {}
		set hit 1
	}
	if {$SqueezeFor ne "" && $SqueezeFor eq $dlg} {
		set Squeeze {}
		set SqueezeFor {}
		set hit 1
	}
	if {$DetachFor ne "" && $DetachFor eq $dlg} {
		set Detach {}
		set DetachFor {}
		set hit 1
	}
	if {$hit} { Relayout }
	return $hit
}


# The largest 16:9 rectangle {x y width height} that fits in a free margin
# of the board canvas (left, right, above or below the board), centred in
# that margin; "" when none is at least MinWidth wide.
proc ::mediainset::FreeRect {canv {controlsHeight 0} {minimumWidth 0}} {
	variable Options

	set cw [winfo width $canv]
	set ch [winfo height $canv]
	set bb [$canv bbox board]
	if {$cw < 2 || $ch < 2 || [llength $bb] != 4} { return "" }
	lassign $bb x0 y0 x1 y1
	set m $Options(margin)
	# the side-to-move and material decorations sit just outside the board
	set x0 [expr {$x0 - $m}]; set y0 [expr {$y0 - $m}]
	set x1 [expr {$x1 + $m}]; set y1 [expr {$y1 + $m}]
	set best ""
	set bestArea 0
	foreach region [list \
		[list 0 0 $x0 $ch] [list $x1 0 [expr {$cw - $x1}] $ch] \
		[list 0 0 $cw $y0] [list 0 $y1 $cw [expr {$ch - $y1}]] \
	] {
		lassign $region rx ry rw rh
		set rw [expr {$rw - 2*$m}]
		set rh [expr {$rh - 2*$m}]
		if {$rw <= 0 || $rh <= 0} { continue }
		set vw [expr {min($rw, ($rh - $controlsHeight)*16/9)}]
		set vh [expr {$vw*9/16 + $controlsHeight}]
		if {$vw < max($Options(minWidth), $minimumWidth)} { continue }
		if {$vw*$vh > $bestArea} {
			set bestArea [expr {$vw*$vh}]
			set best [list \
				[expr {$rx + $m + ($rw - $vw)/2}] [expr {$ry + $m + ($rh - $vh)/2}] $vw $vh]
		}
	}
	return $best
}


# The board owns resize timing. This hook runs after decorations have their
# final geometry; no independent 120ms timer can race the board rebuild.
proc ::mediainset::Watch {} {
	variable Watched
	set pane [Pane]
	if {$Watched eq $pane} { return }
	Unwatch
	set Watched $pane
	::application::board::afterRebuild ::mediainset::BoardRebuilt
	bind .application <<Fullscreen>> +[list ::mediainset::Fullscreen]
}

proc ::mediainset::Unwatch {} {
	variable Watched
	::application::board::afterRebuild ::mediainset::BoardRebuilt true
	if {[winfo exists .application]} {
		set binding [bind .application <<Fullscreen>>]
		set lines [split $binding "\n"]
		set i [lsearch -exact $lines ::mediainset::Fullscreen]
		if {$i >= 0} { bind .application <<Fullscreen>> [join [lreplace $lines $i $i] "\n"] }
	}
	set Watched {}
}

proc ::mediainset::Teardown {w destroyed} {
	if {$w eq $destroyed} { hide }
}

proc ::mediainset::BoardRebuilt {} {
	variable LayingOut
	variable Pending
	if {!$LayingOut} { Relayout; return }
	# A rebuild inside Layout (e.g. a reflow's layout load reached through
	# an idle update) may have re-planned the reserve; place again after.
	if {![info exists Pending] || $Pending eq ""} {
		set Pending [after idle {set ::mediainset::Pending {}; ::mediainset::Relayout}]
	}
}

proc ::mediainset::Fullscreen {} {
	# Tk/WM may deliver the new extent after <<Fullscreen>>. ConfigureWindow
	# covers that resize too; this path also works when the extent is unchanged.
	after idle ::mediainset::Relayout
}

proc ::mediainset::Relayout {} {
	variable Shown
	if {$Shown} { Layout }
}

proc ::mediainset::RestoreBoard {pane} {
	set view [BoardView]
	if {[winfo manager $view] eq "place"} {
		place forget $view
		pack $view -fill both -expand yes
		if {[winfo exists $pane.mediaButton] && [winfo manager $pane.mediaButton] eq "place"} {
			pack configure $view -pady [list [expr {[winfo reqheight $pane.mediaButton] + 8}] 0]
		}
	}
}


# The board menu's option: during playback, move the video to the other
# surface at the time it has reached.
proc ::mediainset::toggle {} {
	variable Options

	if {!$Options(enabled)} { hide }
	if {[catch { set playing $::application::media::Priv(inprocess) }] || !$playing} { return }
	set path $::application::media::Priv(lastMedia)
	set ms 0
	# mpv reports seconds; PlayInProcess takes milliseconds
	catch { set ms [expr {int([::media::mpv::time] * 1000)}] }
	catch { ::application::media::PlayInProcess $path $ms }
}


proc ::mediainset::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::mediainset::WriteOptions


# Build the persistent model even when the Media pane is absent.
proc ::mediainset::InitMedia {} {
	::application::media::Ensure
	RefreshMediaButton
}

# Entries are the pane's resolved rows: per-game media, gallery and indexes
# all keep their existing ownership and interactive playback handling.
proc ::mediainset::Entries {} {
	set entries {}
	set tree $::application::media::Priv(tree)
	if {![winfo exists $tree]} { return {} }
	foreach row [::application::media::MediaRows] {
		lappend entries [linsert [$tree item $row -values] 0 $row]
	}
	# Authored position-keyed segments need no ordinary mediaFiles row.
	upvar #0 ::application::media::Priv priv
	set fen {}
	if {$priv(position) >= 0 && $priv(position) != 9} {
		catch { set fen [::scidb::game::fen $priv(position)] }
	}
	if {$fen ne ""} {
		foreach source {userInteractive dbInteractive} {
			if {![info exists priv($source)]} { continue }
			set hit [::application::media::InteractiveMatch $priv($source) $fen]
			if {![llength $hit]} { continue }
			lassign $hit key path start end title
			lappend entries [list [list interactive $hit] $::application::media::mc::TypeVideo $title $path $priv(index)]
		}
	}
	return $entries
}

# The board button is the always-visible route to the game's media and to
# "Open stream..." (VAL-MED-008), with or without media or a game. It is a
# plain button posting its own menu, filled before posting: a ttk
# menubutton's -postcommand runs inside the native menu loop on Windows,
# where a script that reads or posts the menu (laptop Run 53/55) blocks
# the event loop until the menu is dismissed.
proc ::mediainset::RefreshMediaButton {} {
	set pane [Pane]
	if {$pane eq ""} { return }
	set w $pane.mediaButton
	if {![winfo exists $w]} {
		ttk::button $w -text Media -command [list ::mediainset::PostMediaMenu $w]
		menu $w.menu -tearoff 0
	}
	PopulateMenu $w.menu
	if {[winfo manager $w] ne "place"} {
		place $w -relx 1 -x -4 -y 4 -anchor ne
	}
	if {[winfo manager $pane.c] eq "pack"} { pack configure $pane.c -pady [list [expr {[winfo reqheight $w] + 8}] 0] }
	raise $w
	RefreshControls
	Relayout
}

# Post below the button after the click has returned to the event loop,
# so no binding is still running while a (possibly modal) menu is up.
proc ::mediainset::PostMediaMenu {w} {
	if {![winfo exists $w.menu]} { return }
	PopulateMenu $w.menu
	after idle [list ::mediainset::PostMenuAt $w]
}

proc ::mediainset::PostMenuAt {w} {
	if {![winfo exists $w.menu] || ![winfo ismapped $w]} { return }
	set x [expr {[winfo rootx $w] + [winfo width $w] - [winfo reqwidth $w.menu]}]
	tk_popup $w.menu [expr {max(0, $x)}] [expr {[winfo rooty $w] + [winfo height $w]}]
}

# Labels in menu order, without touching the menu widget (for scripts).
proc ::mediainset::MediaMenuLabels {} {
	set labels {}
	foreach entry [Entries] {
		lassign $entry row type title
		lappend labels "$title ($type)"
	}
	lappend labels "Open stream..."
	return $labels
}

# The board button always lists the current game's entries and the stream
# command, whether or not an entry is selected in the hidden Media pane.
proc ::mediainset::PopulateMenu {menu} {
	$menu delete 0 end
	set entries {}
	catch { set entries [Entries] }
	foreach entry $entries {
		lassign $entry row type title path index
		$menu add command -label "$title ($type)" -command [list ::mediainset::Choose $row]
	}
	if {[llength $entries]} { $menu add separator }
	$menu add command -label "Open stream..." -command [list ::application::media::OpenStream [Pane]]
}

# C7 is the Media pane's own entry context menu. It is posted on right-click
# over an entry, never by the board's Media button.
proc ::mediainset::EntryMenu {tree x y} {
	if {![winfo exists $tree]} { return }
	set row [$tree identify item $x $y]
	if {$row eq ""} { return }
	lassign [$tree item $row -values] type title path index
	if {$path eq ""} { return }
	if {![llength [info commands ::context::Build]]} { return }

	$tree selection set $row
	set menu $tree.__entryMenu__
	catch { destroy $menu }
	menu $menu -tearoff 0
	catch { wm attributes $menu -type popup_menu }
	set base ""
	catch { set base [::scidb::db::get name] }
	set object [dict create base $base mediaId $index path $path title $title type $type]
	if {![::context::Build C7 $menu $object]} {
		destroy $menu
		return
	}
	bind $menu <<MenuUnpost>> +[list after idle [list catch [list destroy $menu]]]
	tk_popup $menu [expr {[winfo rootx $tree] + $x}] [expr {[winfo rooty $tree] + $y}]
}

proc ::mediainset::Choose {row} {
	if {[lindex $row 0] eq "interactive"} {
		::application::media::PlayInteractiveEntry [lindex $row 1]
		return
	}
	set tree $::application::media::Priv(tree)
	$tree selection set $row
	set ::application::media::Priv(selectedRow) $row
	lassign [$tree item $row -values] type title path index
	if {$type eq $::application::media::mc::SectionReports} {
		if {[file extension $path] in {.html .htm} && [file readable $path]} {
			::application::report::showFile .application $path
		} else {
			::application::media::ViewReport $index
		}
	} elseif {[::application::media::ClassifyFile $path] == 1} {
		# Reuse the picture renderer with a separate viewer surface.
		::application::media::Stop
		set viewer $::application::media::Priv(viewer)
		if {[winfo exists .mediaPicture]} { destroy .mediaPicture }
		toplevel .mediaPicture
		wm title .mediaPicture $title
		canvas .mediaPicture.canvas -width 640 -height 480 -background black
		pack .mediaPicture.canvas -fill both -expand yes
		set ::application::media::Priv(viewer) .mediaPicture
		try { ::application::media::ShowImage $path } finally {
			set ::application::media::Priv(viewer) $viewer
		}
	} elseif {[::application::media::isStreamUrl $path]} {
		::application::media::PlayStream $path
	} else {
		::application::media::PlaySelected $tree
	}
}

proc ::mediainset::RefreshControls {{position {}}} {
	set pane [Pane]
	set w $pane.mediainset.controls
	if {![winfo exists $w]} { return }
	set state $::application::media::Priv(playstate)
	$w.play configure -text [expr {$state eq "playing" ? "Ⅱ" : "▶"}]
	RefreshSwapControl
	if {$position ne "" && !$::application::media::Priv(seekgrab)} { $w.seek set $position }
	set chapters [llength [::media::mpv::chapters]]
	if {$chapters > 1} {
		grid $w.prev; grid $w.next
	} else {
		grid remove $w.prev; grid remove $w.next
	}
}

proc ::mediainset::RefreshAspect {} {
	variable Aspect
	set aspect [::media::mpv::aspect]
	if {[string is double -strict $aspect] && $aspect > 0 && abs($aspect - $Aspect) > 0.001} {
		set Aspect $aspect
		Layout
	}
}

proc ::mediainset::AudioOnly {audio} {
	variable Audio
	set Audio $audio
	set pane [Pane]
	set w $pane.mediainset
	if {![winfo exists $w]} { return }
	if {$audio} { pack forget $w.video } else { pack $w.video -side top -fill both -expand yes }
	Layout
}

# vi:set ts=3 sw=3:
