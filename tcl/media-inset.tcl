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
}

# swapped: the video fills the pane and the board is the small window
variable Swapped 0
variable Shown 0

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
	variable mc

	tk::frame $w -background black -borderwidth 1 -relief solid
	canvas $w.video -background black -highlightthickness 0 -borderwidth 0
	ttk::button $w.expand -text "⤢" -width 2 -takefocus 0 \
		-command [namespace code swap]
	catch { ::tooltip::tooltip $w.expand [namespace current]::mc::Expand }
	place $w.video -x 0 -y 0 -relwidth 1 -relheight 1
	place $w.expand -relx 0 -rely 0 -anchor nw -x 2 -y 2
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
	set s $Options(size)

	if {$Swapped} {
		place $w -in $pane -x 0 -y 0 -relx 0 -rely 0 -anchor nw -relwidth 1 -relheight 1
		pack forget $canv
		place $canv -in $pane -relx 1.0 -rely 1.0 -x -6 -y -6 -anchor se \
			-relwidth $s -relheight $s
		raise $canv
	} else {
		RestoreBoard $pane
		place $w -in $pane -relx 1.0 -rely 1.0 -x -6 -y -6 -anchor se \
			-relwidth $s -relheight $s
		raise $w
	}
}


proc ::mediainset::RestoreBoard {pane} {
	set canv $pane.c
	if {[winfo manager $canv] eq "place"} {
		place forget $canv
		pack $canv -fill both -expand yes
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

# vi:set ts=3 sw=3:
