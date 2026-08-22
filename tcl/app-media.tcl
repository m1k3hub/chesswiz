# ======================================================================
# Media Viewer Panel — embedded image/audio/video playback in scidb
# ======================================================================
# Displays media entries (pictures, audio, video, streams) associated
# with the currently loaded game.  Images render inline via Tk photo;
# audio/video play embedded via mpv --wid=<tk-window-id>.
#
# If mpv is not found, falls back to xdg-open (external player).
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
set Play				"Play"
set Stop				"Stop"
set OpenError		"Cannot open media file: %s"
set NoPlayer			"No media player found (mpv or xdg-open)"

} ;# namespace mc

array set Priv {
	position		-1
	base			{}
	variant		{}
	index			-1
	afterid		{}
	tree			{}
	statusbar		{}
	viewer			{}
	viewerimg		{}
	mpv_pid		0
	mpv_wid		{}
}

} ;# namespace media
} ;# namespace application


proc application::media::build {twm frame width height} {
	variable Priv
	variable mc

	set tree $frame.tree
	set viewer $frame.viewer
	set status $frame.status
	set ctrl $frame.ctrl

	# Media list (treeview with columns: type, title, path)
	ttk::treeview $tree \
		-columns {type title path} \
		-displaycolumns {type title path} \
		-show headings \
		-selectmode browse \
		-height 6 \
		;
	$tree heading type -text $mc::ColumnType
	$tree heading title -text $mc::ColumnTitle
	$tree heading path  -text $mc::ColumnPath
	$tree column type  -width 70  -anchor center
	$tree column title -width 180 -anchor w
	$tree column path  -width 200 -anchor w

	# Control buttons
	ttk::frame $ctrl
	ttk::button $ctrl.play -text $mc::Play -command [namespace code [list PlaySelected $tree]]
	ttk::button $ctrl.stop -text $mc::Stop -command [namespace code Stop]
	pack $ctrl.play -side left -padx 2
	pack $ctrl.stop -side left -padx 2

	# Embedded viewer area — a frame that holds either an image label
	# or an mpv video window.
	ttk::frame $viewer -relief sunken -borderwidth 1
	canvas $viewer.canvas -bg black -highlightthickness 0
	pack $viewer.canvas -fill both -expand yes

	# Status bar
	ttk::label $status -textvariable [namespace current]::Priv(statusbar) \
		-anchor w -relief sunken -borderwidth 1

	grid $tree   -row 1 -column 1 -sticky nsew
	grid $ctrl   -row 2 -column 1 -sticky ew
	grid $viewer -row 3 -column 1 -sticky nsew
	grid $status -row 4 -column 1 -sticky ew
	grid rowconfigure $frame 3 -weight 1
	grid columnconfigure $frame 1 -weight 1

	bind $tree <Double-Button-1> [namespace code [list PlaySelected $tree]]
	bind $tree <<TreeviewSelect>> [namespace code [list SelectionChanged $tree]]

	set Priv(tree) $tree
	set Priv(viewer) $viewer
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
	if {$base ne $Priv(base)} {
		after cancel $Priv(afterid)
		set Priv(afterid) [after 1 [namespace code [list Update $Priv(position)]]]
	}
}


proc application::media::Update {position} {
	variable Priv
	variable mc

	set Priv(position) $position
	set tree $Priv(tree)

	# Stop any playing media
	Stop

	# Clear previous entries
	foreach item [$tree children {}] { $tree delete $item }

	if {$position < 0 || $position == 9} {
		set Priv(base) {}
		set Priv(variant) {}
		set Priv(index) -1
		set Priv(statusbar) $mc::NoDatabase
		return
	}

	lassign [::scidb::game::link? $position] base variant index
	set Priv(base) $base
	set Priv(variant) $variant
	set Priv(index) $index

	if {$base eq "" || $index < 0} {
		set Priv(statusbar) $mc::NoMedia
		return
	}

	set entries {}
	catch { set entries [::scidb::db::mediaFiles $base $variant $index] }

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


proc application::media::PlaySelected {tree} {
	variable Priv

	set sel [$tree selection]
	if {![llength $sel]} return

	set values [$tree item [lindex $sel 0] -values]
	if {[llength $values] < 3} return

	lassign $values typeLabel title path
	if {![string length $path]} return

	# Find the type (numeric) from the entries
	set type 0
	foreach entry [$tree children {}] {
		set vals [$tree item $entry -values]
		if {[lindex $vals 2] eq $path} {
			# The typeLabel is the first column; we need the numeric type
			# Re-query mediaFiles to get it
			break
		}
	}

	# Determine type by file extension
	set type [ClassifyFile $path]

	Stop

	if {$type == 1} {
		# Picture — display inline via Tk photo
		ShowImage $path
	} else {
		# Audio/video — embed mpv or launch external
		PlayMedia $path
	}
}


proc application::media::ShowImage {path} {
	variable Priv
	variable mc

	set canvas $Priv(viewer).canvas

	# Clear previous content
	$canvas delete all

	if {![file exists $path]} {
		set Priv(statusbar) "File not found: $path"
		return
	}

	catch {
		image create photo Priv(img) -file $path
	}

	if {[catch { image create photo Priv(img) -file $path }]} {
		set Priv(statusbar) "Cannot load image: $path"
		return
	}

	# Get image dimensions and fit within canvas
	set imgW [image width Priv(img)]
	set imgH [image height Priv(img)]
	set canW [winfo width $canvas]
	set canH [winfo height $canvas]
	if {$canW < 10} { set canW 300 }
	if {$canH < 10} { set canH 200 }

	# Scale to fit
	set scale [expr {min(1.0, min(double($canW)/$imgW, double($canH)/$imgH))}]
	set dstW [expr {int($imgW * $scale)}]
	set dstH [expr {int($imgH * $scale)}]

	# Create a resized image
	if {$scale < 1.0} {
		catch { image delete Priv(imgscaled) }
		image create photo Priv(imgscaled)
		# Tk doesn't have a native resize; use the subsample approach
		set sx [expr {int(1.0/$scale)}]
		catch { Priv(imgscaled) copy Priv(img) -subsample $sx $sx }
		$canvas create image [expr {$canW/2}] [expr {$canH/2}] -image Priv(imgscaled) -anchor center
	} else {
		$canvas create image [expr {$canW/2}] [expr {$canH/2}] -image Priv(img) -anchor center
	}

	set Priv(statusbar) "$path (${imgW}x${imgH})"
}


proc application::media::PlayMedia {path} {
	variable Priv
	variable mc

	if {![file exists $path]} {
		set Priv(statusbar) "File not found: $path"
		return
	}

	# Try mpv with --wid embedding first
	set mpv [auto_execok mpv]
	if {[string length $mpv]} {
		# Get the canvas window ID for embedding
		set canvas $Priv(viewer).canvas
		set wid [winfo id $canvas]

		# Clear canvas
		$canvas delete all

		# Launch mpv embedded in the canvas
		set cmd [list $mpv --wid=$wid --no-terminal --no-osd-bar --force-window=no \
				--keep-open=yes --vo=gpu --audio-display=no $path]
		set Priv(mpv_pid) [exec {*}$cmd &]

		set Priv(statusbar) "Playing: $path"
		return
	}

	# Fallback: xdg-open / open / start
	LaunchExternal $path
}


proc application::media::LaunchExternal {path} {
	variable mc

	switch -- [tk windowingsystem] {
		"aqua" {
			catch { exec open $path & }
		}
		"win32" {
			if {$::tcl_platform(os) eq "Windows NT"} {
				catch { exec $::env(COMSPEC) /c start "" $path & }
			} else {
				catch { exec start "" $path & }
			}
		}
		"x11" {
			set opener [auto_execok xdg-open]
			if {[string length $opener]} {
				catch { exec $opener $path & }
			} else {
				tk_messageBox -icon error -type ok -message [format $mc::OpenError $path]
			}
		}
	}
}


proc application::media::Stop {} {
	variable Priv

	# Stop mpv if running
	if {$Priv(mpv_pid) != 0} {
		catch { exec kill $Priv(mpv_pid) }
		set Priv(mpv_pid) 0
	}

	# Clear canvas
	if {[winfo exists $Priv(viewer).canvas]} {
		$Priv(viewer).canvas delete all
	}
}


proc application::media::TypeLabel {type} {
	variable mc
	switch -- $type {
		1 { return $mc::TypePicture }
		2 { return $mc::TypeAudio }
		3 { return $mc::TypeVideo }
		4 { return $mc::TypeStream }
		default { return $mc::TypeNone }
	}
}


proc application::media::ClassifyFile {path} {
	set ext [string tolower [file extension $path]]
	switch -- $ext {
		.jpg - .jpeg - .png - .bmp - .gif { return 1 }
		.mp3 - .wav - .ogg - .flac { return 2 }
		.mp4 - .avi - .wmv - .mkv - .webm - .mpg - .mpeg { return 3 }
		.m3u8 - .pls { return 4 }
		default { return 0 }
	}
}


proc application::media::activate {w flag} {
}


proc application::media::setActive {flag} {
}

# vi:set ts=3 sw=3:

