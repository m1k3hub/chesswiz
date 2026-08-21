# ======================================================================
# Media Viewer Panel — shows .scm companion media for the current game
# ======================================================================
# Displays media entries (pictures, audio, video, streams) associated
# with the currently loaded game via the database's optional .scm
# companion manifest.  Double-click opens the file with the OS default
# application.  Inline base64 payloads are decoded to a temp file.
# ======================================================================

::util::source application-media

namespace eval application {
namespace eval media {
namespace eval mc {

set Title				"Media"
set NoMedia			"No media for this game."
set NoDatabase		"Open a database to see media."
set ColumnType		"Type"
set ColumnTitle		"Title"
set ColumnPath		"Path"
set TypePicture		"Picture"
set TypeAudio		"Audio"
set TypeVideo		"Video"
set TypeStream		"Stream"
set TypeNone			"Unknown"
set OpenError		"Cannot open media file: %s"

} ;# namespace mc

array set Priv {
	position		-1
	base			{}
	variant		{}
	index			-1
	afterid		{}
	tree			{}
	statusbar		{}
}

} ;# namespace media
} ;# namespace application


proc application::media::build {twm frame width height} {
	variable Priv

	set tree $frame.tree
	set status $frame.status

	ttk::treeview $tree \
		-columns {type title path} \
		-displaycolumns {type title path} \
		-show headings \
		-selectmode browse \
		;
	$tree heading type -text $mc::ColumnType
	$tree heading title -text $mc::ColumnTitle
	$tree heading path  -text $mc::ColumnPath
	$tree column type  -width 80  -anchor center
	$tree column title -width 200 -anchor w
	$tree column path  -width 300 -anchor w

	# Status bar
	ttk::label $status -textvariable [namespace current]::Priv(statusbar) \
		-anchor w -relief sunken -borderwidth 1

	grid $tree   -row 1 -column 1 -sticky nsew
	grid $status -row 2 -column 1 -sticky ew
	grid rowconfigure $frame 1 -weight 1
	grid columnconfigure $frame 1 -weight 1

	bind $tree <Double-Button-1> [namespace code [list Open $tree]]
	bind $tree <<TreeviewSelect>> [namespace code [list SelectionChanged $tree]]

	set Priv(tree) $tree
	set Priv(statusbar) $mc::NoDatabase

	# React to game switches
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	::scidb::db::subscribe databaseSwitch [namespace current]::DatabaseSwitched

	return $frame
}


proc application::media::GameSwitched {oldPos newPos} {
	variable Priv

	after cancel $Priv(afterid)
	set Priv(afterid) [after 1 [namespace code [list Update $newPos]]]
}


proc application::media::DatabaseSwitched {base variant} {
	variable Priv

	# If the current game belongs to a different base, the gameSwitch
	# event will handle it.  Just refresh in case media changed.
	if {$base ne $Priv(base)} {
		after cancel $Priv(afterid)
		set Priv(afterid) [after 1 [namespace code [list Update $Priv(position)]]]
	}
}


proc application::media::Update {position} {
	variable Priv

	set Priv(position) $position
	set tree $Priv(tree)

	# Clear previous entries
	foreach item [$tree children {}] {
		$tree delete $item
	}

	if {$position < 0 || $position == 9} {
		set Priv(base) {}
		set Priv(variant) {}
		set Priv(index) -1
		set Priv(statusbar) $mc::NoDatabase
		return
	}

	# Get the loaded game's database/variant/index
	lassign [::scidb::game::link? $position] base variant index
	set Priv(base) $base
	set Priv(variant) $variant
	set Priv(index) $index

	if {$base eq "" || $index < 0} {
		set Priv(statusbar) $mc::NoMedia
		return
	}

	# Query media files for this game
	set entries {}
	catch {
		set entries [::scidb::db::mediaFiles $base $variant $index]
	}

	if {![llength $entries]} {
		set Priv(statusbar) $mc::NoMedia
		return
	}

	set n 0
	foreach entry $entries {
		lassign $entry path type title mediaId inline
		set typeLabel [TypeLabel $type]
		$tree insert {} end -id item$n -values [list $typeLabel $title $path]
		incr n
	}

	set Priv(statusbar) {}
}


proc application::media::SelectionChanged {tree} {
	variable Priv

	set sel [$tree selection]
	if {![llength $sel]} return

	set values [$tree item [lindex $sel 0] -values]
	if {[llength $values] >= 3} {
		set Priv(statusbar) [lindex $values 2]
	}
}


proc application::media::Open {tree} {
	variable Priv

	set sel [$tree selection]
	if {![llength $sel]} return

	set values [$tree item [lindex $sel 0] -values]
	if {[llength $values] < 3} return

	lassign $values typeLabel title path

	if {![string length $path]} return

	# Resolve relative paths against the database media directory.
	# mediaFiles already returns resolved paths, so we can use directly.
	set resolved $path

	if {![file exists $resolved]} {
		# Could be an inline base64 payload or a relative path that
		# wasn't resolved.  Try as-is.
		if {![catch {file normalize $resolved} normalized]} {
			set resolved $normalized
		}
	}

	LaunchFile $resolved
}


proc application::media::LaunchFile {path} {
	if {![string length $path]} return

	switch -- [tk windowingsystem] {
		"aqua" {
			catch {exec open [list $path] &}
		}
		"win32" {
			if {$::tcl_platform(os) eq "Windows NT"} {
				catch {exec $::env(COMSPEC) /c start "" [list $path] &}
			} else {
				catch {exec start "" [list $path] &}
			}
		}
		"x11" {
			set opener [auto_execok xdg-open]
			if {[string length $opener]} {
				catch {exec $opener [list $path] &}
			} else {
				# Fallback: try common openers
				foreach cmd {gio gnome-open kde-open} {
					if {[string length [auto_execok $cmd]]} {
						catch {exec $cmd [list $path] &}
						return
					}
				}
				tk_messageBox -icon error -type ok \
					-message [format $mc::OpenError $path]
			}
		}
	}
}


proc application::media::TypeLabel {type} {
	switch -- $type {
		1 { return $mc::TypePicture }
		2 { return $mc::TypeAudio }
		3 { return $mc::TypeVideo }
		4 { return $mc::TypeStream }
		default { return $mc::TypeNone }
	}
}


proc application::media::activate {flag} {
	# Called when the pane is shown/hidden.  Could be used to defer
	# updates when the pane is not visible.
}


proc application::media::setActive {flag} {
	# Focus management stub.
}

# vi:set ts=3 sw=3:
