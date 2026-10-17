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
	minWidth 200
}

# swapped: the video fills the pane and the board is the small window
variable Swapped 0
variable Shown 0
variable Audio 0

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
	update idletasks
	for {set i 0} {$i < 20 && ![winfo ismapped $w.video]} {incr i} {
		update
		if {![winfo ismapped $w.video]} { after 25 }
	}
	# the events handled above may have stopped an earlier playback
	Show
	return $w.video
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
	ttk::scale $w.controls.seek -orient horizontal -from 0 -to 1000 -value 0
	bind $w.controls.seek <ButtonPress-1> {+set ::application::media::Priv(seekgrab) 1}
	bind $w.controls.seek <ButtonRelease-1> +[list ::application::media::SeekRelease $w.controls.seek]
	bind $w.controls.seek <KeyRelease> {
		if {%K in {Left Right Up Down Prior Next Home End}} {
			::application::media::SeekRelease %W
		}
	}
	# Two compact rows keep the transport usable in a narrow board margin.
	pack $w.controls -side bottom -fill x
	grid $w.controls.play $w.controls.prev $w.controls.next $w.controls.stop $w.controls.stream -sticky ew
	grid $w.expand -in $w.controls -row 0 -column 5
	grid $w.controls.seek -row 1 -column 0 -columnspan 4 -sticky ew
	grid $w.controls.time -row 1 -column 4 -columnspan 2 -sticky ew
	grid columnconfigure $w.controls 0 -weight 1
	pack $w.video -side top -fill both -expand yes
	bind $w <space> {::application::media::TogglePlayback; break}
	bind $w.video <Button-1> [list focus $w]
	# Include the frame binding for focusable transport children, too.
	foreach child [winfo children $w.controls] {
		bindtags $child [linsert [bindtags $child] 1 $w]
	}
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
	if {$pane eq ""} { return }
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


# Place the video and the board for the current mode.
proc ::mediainset::Layout {} {
	variable Options
	variable Swapped
	variable Shown

	set pane [Pane]
	if {$pane eq "" || !$Shown} { return }
	set w $pane.mediainset
	set canv $pane.c
	variable Audio
	set s $Options(size)
	set controlWidth [expr {[winfo reqwidth $w.controls] + 8}]

	if {$Swapped} {
		place $w -in $pane -x 0 -y 0 -relx 0 -rely 0 -anchor nw -relwidth 1 -relheight 1 \
			-width {} -height {}
		pack forget $canv
		place $canv -in $pane -relx 1.0 -rely 1.0 -x -6 -y -6 -anchor se \
			-relwidth $s -relheight $s
		raise $canv
	} else {
		RestoreBoard $pane
		set free [FreeRect $canv [expr {[winfo reqheight $w.controls] + 8}] $controlWidth]
		if {[llength $free]} {
			# beside the board: the largest free margin of the pane, 16:9
			lassign $free x y fw fh
			set x [expr {$x + [winfo x $canv]}]
			set y [expr {$y + [winfo y $canv]}]
			place $w -in $pane -x $x -y $y -width $fw -height $fh \
				-relx 0 -rely 0 -anchor nw -relwidth {} -relheight {}
		} else {
			# no margin can hold a usable video: the board's bottom-right corner
			set extra [expr {max(0, min($controlWidth, [winfo width $pane] - 12) - int([winfo width $pane]*$s))}]
			place $w -in $pane -x -6 -y -6 -relx 1.0 -rely 1.0 -anchor se \
				-width $extra -height {} -relwidth $s -relheight $s
		}
		raise $w
	}
	if {$Audio} {
		place $w -relheight 0 -height [expr {[winfo reqheight $w.controls] + 8}]
	}
	if {[winfo exists $pane.mediaButton]} { raise $pane.mediaButton }
	Watch $canv
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


# Lay out again when the pane or the board changes size (the board is
# rebuilt after idle, so wait for that).
proc ::mediainset::Watch {canv} {
	variable Watched
	if {[info exists Watched($canv)]} { return }
	set Watched($canv) 1
	bind $canv <Configure> {+ after cancel ::mediainset::Relayout; after 120 ::mediainset::Relayout }
}


proc ::mediainset::Relayout {} {
	variable Shown
	variable Swapped
	if {$Shown && !$Swapped} { Layout }
}


proc ::mediainset::RestoreBoard {pane} {
	set canv $pane.c
	if {[winfo manager $canv] eq "place"} {
		place forget $canv
		pack $canv -fill both -expand yes
		if {[winfo exists $pane.mediaButton] && [winfo manager $pane.mediaButton] eq "place"} {
			pack configure $canv -pady [list [expr {[winfo reqheight $pane.mediaButton] + 8}] 0]
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
	lassign [$tree item $row -values] type title path index
	if {$type eq $::application::media::mc::SectionReports} {
		::application::media::ViewReport $index
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
	set chapters 0
	foreach entry [Entries] {
		if {[lindex $entry 1] in [list $::application::media::mc::TypeAudio \
			$::application::media::mc::TypeVideo $::application::media::mc::TypeStream]} { incr chapters }
	}
	if {$chapters > 1} {
		grid $w.prev; grid $w.next
	} else {
		grid remove $w.prev; grid remove $w.next
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
