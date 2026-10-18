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
set Expand		"Swap video and board"

} ;# namespace mc

array set Options {
	enabled 1
	size 0.34
	margin 6
	minWidth 160
}

# swapped: the video fills the pane and the board is the small window
variable Swapped 0
variable Shown 0
variable Audio 0
variable Aspect [expr {16.0/9}]
variable LayingOut 0
variable Watched {}

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
	ttk::button $w.expand -text "⤢" -width 2 -takefocus 0 -command [namespace code swap]
	catch { ::tooltip::tooltip $w.expand [namespace current]::mc::Expand }
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
}


proc ::mediainset::Show {} {
	variable Shown
	set Shown 1
	Layout
}


proc ::mediainset::hide {} {
	variable Shown
	variable Swapped

	set pane [Pane]
	set Shown 0
	Unwatch
	if {$pane eq ""} {
		# During <Destroy> the board may already have gone away.
		set ::application::board::ReserveSide {}
		set ::application::board::ReservePixels 0
		return
	}
	::application::board::setReserve {} 0
	if {[winfo exists $pane.mediainset]} { place forget $pane.mediainset }
	if {$Swapped} {
		set Swapped 0
		RestoreBoard $pane
	}
}


proc ::mediainset::swap {} {
	variable Swapped
	variable Shown

	if {!$Shown} { return }
	set Swapped [expr {!$Swapped}]
	Layout
}


proc ::mediainset::swapped? {} {
	variable Swapped
	return $Swapped
}


# The visible board presentation; the 2D canvas is unmapped in 3D mode.
proc ::mediainset::BoardView {} {
	upvar #0 ::application::board::Vars vars
	if {$vars(3d) && [winfo exists $vars(3dwin)]} { return $vars(3dwin) }
	return $vars(widget:frame)
}

# Place in board-pane coordinates. Only setReserve's minimum-square refusal
# permits an overlay. The eight-pixel frame margin is 2*(border + highlight).
proc ::mediainset::Layout {} {
	variable Options
	variable Swapped
	variable Shown
	variable Audio
	variable Aspect
	variable LayingOut

	set pane [Pane]
	if {$pane eq "" || !$Shown || $LayingOut} { return }
	set w $pane.mediainset
	if {![winfo exists $w]} { return }
	set LayingOut 1
	try {
		Watch
		set view [BoardView]
		set s $Options(size)
		set cw [expr {[winfo reqwidth $w.controls] + 8}]
		set ch [expr {[winfo reqheight $w.controls] + 8}]
		if {$Swapped && $Audio} {
			::application::board::setReserve {} 0
			RestoreBoard $pane
			place $w -in $pane -x -6 -y -6 -relx 1 -rely 1 -anchor se \
				-width $cw -height $ch -relwidth {} -relheight {}
			raise $w
		} elseif {$Swapped} {
			::application::board::setReserve {} 0
			place $w -in $pane -x 0 -y 0 -relx 0 -rely 0 -anchor nw \
				-relwidth 1 -relheight 1 -width {} -height {}
			pack forget $view
			place $view -in $pane -relx 1 -rely 1 -x -6 -y -6 -anchor se \
				-relwidth $s -relheight $s -width {} -height {}
			raise $view
		} else {
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
				} else {
					# Only panes unable to fit a 160px video at the minimum
					# board square size use the existing corner overlay.
					set side {}
					set iw [expr {max(168, int($height*$s*$Aspect)+8)}]
					set ih [expr {int(round(($iw-8)/$Aspect))+$ch}]
				}
			}
			set pixels [expr {$side eq "right" ? $iw : $ih}]
			if {$side ne "" && [::application::board::setReserve $side $pixels]} {
				lassign [::application::board::reserveRect] x y rw rh
				set x [expr {$x + [winfo x $view] + ($rw - $iw)/2}]
				set y [expr {$y + [winfo y $view] + ($rh - $ih)/2}]
				place $w -in $pane -x $x -y $y -width $iw -height $ih \
					-relx 0 -rely 0 -anchor nw -relwidth {} -relheight {}
			} else {
				::application::board::setReserve {} 0
				# Keep the usable transport, fitting the video to the pane.
				set iw [expr {min($iw, max(1, [winfo width $pane] - 12))}]
				set ih [expr {$Audio ? $ch : int(round(($iw - 8)/$Aspect)) + $ch}]
				place $w -in $pane -x -6 -y -6 -relx 1 -rely 1 -anchor se \
					-width $iw -height $ih -relwidth {} -relheight {}
			}
			raise $w
		}
		if {[winfo exists $pane.mediaButton]} { raise $pane.mediaButton }
	} finally {
		set LayingOut 0
	}
}


# Plan the final 2D reserve before the board paints a resized extent. The
# afterRebuild hook still places the inset; it need not repaint an obsolete
# board size first. 3D uses its realized frame/Configure path instead.
proc ::mediainset::reserveForLayout {width height} {
	variable Shown
	variable Swapped
	variable Audio
	if {!$Shown || $Swapped || $::application::board::Vars(3d)} { return {} }
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
	foreach side {right bottom} {
		set minimumHeight [expr {int(round(160/$Aspect))+$controlsHeight}]
		set px [expr {$side eq "right" ? $minimum : $minimumHeight}]
		set squareAtMinimum [::application::board::reserveSquare $side $px $width $height]
		if {$squareAtMinimum < $::application::board::MinimumReserveSquare} { continue }
		set desired [expr {$side eq "right" ? int($height*$Options(size)*$Aspect)+8 : int($width*0.66)}]
		set lo $minimum
		set hi [expr {min(max($minimum,$Options(minWidth)+8,$desired), $width, int(($height-$controlsHeight)*$Aspect)+8)}]
		set candidate {}
		while {$lo <= $hi} {
			set iw [expr {($lo+$hi)/2}]
			set ih [expr {int(round(($iw-8)/$Aspect))+$controlsHeight}]
			set px [expr {$side eq "right" ? $iw : $ih}]
			set square [::application::board::reserveSquare $side $px $width $height]
			if {$square >= $squareAtMinimum} {
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
	if {!$LayingOut} { Relayout }
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

proc ::mediainset::RefreshMediaButton {} {
	set pane [Pane]
	if {$pane eq ""} { return }
	set w $pane.mediaButton
	if {![winfo exists $w]} {
		ttk::menubutton $w -text Media -menu $w.menu
		menu $w.menu -tearoff 0 -postcommand [list ::mediainset::PopulateMenu $w.menu]
	}
	if {[llength [Entries]]} {
		place $w -relx 1 -x -4 -y 4 -anchor ne
		if {[winfo manager $pane.c] eq "pack"} { pack configure $pane.c -pady [list [expr {[winfo reqheight $w] + 8}] 0] }
		raise $w
	} else {
		place forget $w
		if {[winfo manager $pane.c] eq "pack"} { pack configure $pane.c -pady 0 }
	}
	RefreshControls
	Relayout
}

proc ::mediainset::PopulateMenu {menu} {
	$menu delete 0 end
	foreach entry [Entries] {
		lassign $entry row type title path index
		$menu add command -label "$title ($type)" -command [list ::mediainset::Choose $row]
	}
	$menu add separator
	$menu add command -label "Open stream..." -command [list ::application::media::OpenStream [Pane]]
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
