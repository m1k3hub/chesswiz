# ======================================================================
# The Chesswiz Online window: one dashboard for internet play, with a tab
# per server lobby and a tab per game being played or watched
# (docs/features/ONLINE_CLIENT_SPEC.md §5). Server clients add tabs:
#
#   ::online::window::open                   create or raise; returns path
#   ::online::window::tab key title          a frame for a lobby tab
#   ::online::window::gameTab key title backend side   a game view
#   ::online::window::select key
#   ::online::window::title key text
#   ::online::window::closeTab key
#   ::online::window::status text
# ======================================================================

::util::source online-window

namespace eval ::online::window {
namespace eval mc {

set Title		"Chesswiz Online"

}

variable Path .online
variable Tabs
array set Tabs {}
variable Serial 0


proc open {} {
	variable Path
	variable mc
	if {[winfo exists $Path]} {
		wm deiconify $Path
		raise $Path
		# It may have been hidden on a monitor that has since gone away,
		# or while the work area shrank (GAP-004).
		::util::place::fitWindow $Path
		return $Path
	}
	toplevel $Path -class ChesswizOnline
	wm title $Path $mc::Title
	# Open on the main window's monitor, inside that monitor's work area
	# (GAP-005); the display watcher re-clamps it after monitor, work-area
	# and DPI changes.
	lassign [winfo workarea .application] wx wy ww wh
	set width [expr {min(1400, max(320, $ww - 40))}]
	set height [expr {min(900, max(240, $wh - 80))}]
	wm minsize $Path [expr {min(900, $width)}] [expr {min(600, $height)}]
	wm geometry $Path ${width}x${height}+[expr {$wx + ($ww - $width) / 2}]+[expr {$wy + ($wh - $height) / 3}]
	::util::place::fitWindow $Path
	ttk::notebook $Path.tabs
	# each tab reports its own status; a stale one would describe another tab
	bind $Path.tabs <<NotebookTabChanged>> [list [namespace current]::status {}]
	ttk::label $Path.status -anchor w -padding {8 2}
	pack $Path.status -side bottom -fill x
	pack $Path.tabs -fill both -expand yes -padx 4 -pady 4
	# tabs stop their live streams when the window is closed
	wm protocol $Path WM_DELETE_WINDOW [list [namespace current]::Hide]
	return $Path
}


proc Hide {} {
	variable Path
	event generate $Path <<OnlineWindowHidden>>
	wm withdraw $Path
}


proc tab {key title} {
	variable Path
	variable Tabs
	variable Serial
	open
	if {[info exists Tabs($key)] && [winfo exists $Tabs($key)]} { return $Tabs($key) }
	set f [ttk::frame $Path.tabs.t[incr Serial] -padding 8]
	$Path.tabs add $f -text $title
	set Tabs($key) $f
	return $f
}


proc gameTab {key title backend side} {
	variable Path
	variable Tabs
	variable Serial
	open
	if {[info exists Tabs($key)] && [winfo exists $Tabs($key)]} { destroy $Tabs($key) }
	set w $Path.tabs.g[incr Serial]
	::online::view::create $w $backend $side
	$w configure -padding 8
	$Path.tabs add $w -text $title
	$Path.tabs select $w
	set Tabs($key) $w
	return $w
}


proc select {key} {
	variable Path
	variable Tabs
	open
	if {[info exists Tabs($key)] && [winfo exists $Tabs($key)]} { $Path.tabs select $Tabs($key) }
}


proc title {key text} {
	variable Path
	variable Tabs
	if {[info exists Tabs($key)] && [winfo exists $Tabs($key)]} { $Path.tabs tab $Tabs($key) -text $text }
}


proc closeTab {key} {
	variable Tabs
	if {[info exists Tabs($key)]} {
		if {[winfo exists $Tabs($key)]} { destroy $Tabs($key) }
		unset Tabs($key)
	}
}


proc status {text} {
	variable Path
	if {[winfo exists $Path]} { $Path.status configure -text $text }
}

} ;# namespace ::online::window

# vi:set ts=3 sw=3:
