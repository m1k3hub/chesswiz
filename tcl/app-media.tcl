# ======================================================================
# Media Viewer Panel — embedded image/audio/video playback in scidb
# ======================================================================
# Displays media entries (pictures, audio, video, streams) associated
# with the currently loaded game.  Images render inline via Tk photo;
# audio/video play embedded via the tkvlc package (libVLC bound to a
# Tk frame's window ID).
#
# If tkvlc (and thus libVLC) is not available, falls back to xdg-open
# (external player).
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
set NoPlayer			"No media player found (tkvlc or xdg-open)"

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
	vlc_handle	{}
	vlc_loaded	0
	inprocess	0
	checkid		{}
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
	# or a tkvlc video window.
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
		# No per-game media (.scm) — try the gallery (.cbm or .scm gallery)
		set gallery {}
		catch { set gallery [::scidb::db::mediaGallery $base $variant] }
		if {[llength $gallery]} {
			set Priv(statusbar) "Media gallery (not game-specific)"
			set n 0
			foreach entry $gallery {
				lassign $entry path type title mediaId
				set typeLabel [TypeLabel $type]
				$tree insert {} end -id item$n -values [list $typeLabel $title $path]
				incr n
			}
			return
		}
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
	if {![llength $sel]} {
		MediaDebug "PlaySelected: no selection"
		set Priv(statusbar) "Select a media entry first."
		return
	}

	set values [$tree item [lindex $sel 0] -values]
	if {[llength $values] < 3} {
		MediaDebug "PlaySelected: unexpected values [list $values]"
		return
	}

	lassign $values typeLabel title path
	if {![string length $path]} {
		MediaDebug "PlaySelected: empty path (inline media), title=[list $title]"
		set Priv(statusbar) "Cannot play '$title': media is stored inline (not yet extractable)."
		return
	}

	MediaDebug "PlaySelected: type=[list $typeLabel] path=[list $path] typeNum=[ClassifyFile $path]"

	set type [ClassifyFile $path]

	Stop

	if {$type == 1} {
		# Picture — display inline via Tk photo
		ShowImage $path
	} else {
		# Audio/video — embed via tkvlc or launch external
		PlayMedia $path
	}
}


# Append a diagnostic line to /tmp/scidb-media-debug.log (and stderr) so
# playback failures are traceable without a debugger.
proc application::media::MediaDebug {msg} {
	catch {
		set fd [open /tmp/scidb-media-debug.log a]
		puts $fd "[clock format [clock seconds]] [pid] $msg"
		close $fd
	}
	puts stderr "scidb-media: $msg"
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


# Try to load the tkvlc package (once).  Returns 1 if available, 0 otherwise.
proc application::media::LoadVlc {} {
	variable Priv

	if {$Priv(vlc_loaded)} {
		return [expr {$Priv(vlc_handle) ne ""}]
	}
	set Priv(vlc_loaded) 1

	if {![catch { package require tkvlc } msg]} {
		MediaDebug "LoadVlc: tkvlc loaded"
		return 1
	}

	MediaDebug "LoadVlc: package require tkvlc failed: $msg"
	return 0
}


proc application::media::PlayMedia {path} {
	variable Priv
	variable mc

	if {![file exists $path]} {
		MediaDebug "PlayMedia: file not found: $path"
		set Priv(statusbar) "File not found: $path"
		return
	}

	# Prefer the tkvlc backend (embedded, in-window playback via libVLC).
	if {[LoadVlc]} {
		MediaDebug "PlayMedia: tkvlc available, trying in-process"
		if {[PlayInProcess $path]} {
			return
		}
		MediaDebug "PlayMedia: tkvlc failed, falling back to external player"
	}

	# Fallback: xdg-open / open / start
	LaunchExternal $path
}


# Play a media file using the tkvlc (libVLC) backend.
# Video is embedded into the viewer canvas by passing its X11 window ID
# to ::tkvlc::init.  Returns 1 on success, 0 if tkvlc is unavailable or
# failed, so the caller can fall back to an external player.
proc application::media::PlayInProcess {path} {
	variable Priv
	variable mc

	set canvas $Priv(viewer).canvas

	# Destroy any previous tkvlc handle so we start fresh.
	DestroyVlcHandle

	# Realize the canvas so winfo id returns a valid window id.
	update idletasks
	set wid [winfo id $canvas]
	MediaDebug "PlayInProcess: canvas=$canvas wid=$wid"

	# Clear canvas (tkvlc renders directly into the window, but clear
	# any leftover photo image from a previous picture display).
	$canvas delete all

	# Initialise a new tkvlc handle bound to the canvas window id.
	set handle "scidb_vlc"
	if {[catch { ::tkvlc::init $handle $wid } msg]} {
		MediaDebug "PlayInProcess: ::tkvlc::init failed: $msg"
		set Priv(statusbar) "tkvlc initialization failed; trying external player."
		return 0
	}

	set Priv(vlc_handle) $handle

	# Open the file (use native path for Windows compatibility).
	set native [file nativename $path]
	if {[catch { $handle open $native } msg]} {
		MediaDebug "PlayInProcess: $handle open failed: $msg"
		DestroyVlcHandle
		return 0
	}

	# Start playback.
	if {[catch { $handle play } msg]} {
		MediaDebug "PlayInProcess: $handle play failed: $msg"
		DestroyVlcHandle
		return 0
	}

	set Priv(inprocess) 1
	set Priv(statusbar) "Playing: $path"
	MediaDebug "PlayInProcess: playback started for $path"

	# Check shortly after that playback actually started (media decoded).
	catch { after cancel $Priv(checkid) }
	set Priv(checkid) [after 800 [namespace code [list CheckDecode $path]]]
	return 1
}


# Verify a just-started tkvlc playback actually started.  An unsupported
# or corrupt file will report an error state, so surface a clear error
# rather than leaving the panel silently blank.
proc application::media::CheckDecode {path} {
	variable Priv

	if {!$Priv(inprocess) || $Priv(vlc_handle) eq ""} { return }

	set handle $Priv(vlc_handle)

	set state ""
	catch { set state [$handle state] }
	MediaDebug "CheckDecode: state=$state"

	if {$state eq "error" || $state eq "idle"} {
		MediaDebug "CheckDecode: state=$state -> cannot play [list $path]"
		DestroyVlcHandle
		set Priv(inprocess) 0
		set Priv(statusbar) "Cannot play: unsupported or corrupt media file."
	}
}


# Destroy the current tkvlc handle and release libVLC resources.
proc application::media::DestroyVlcHandle {} {
	variable Priv

	set handle $Priv(vlc_handle)
	if {$handle ne ""} {
		catch { $handle stop }
		catch { $handle destroy }
	}
	set Priv(vlc_handle) ""
	set Priv(inprocess) 0
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

	catch { after cancel $Priv(checkid) }
	set Priv(checkid) {}

	# Stop and release tkvlc playback.
	if {$Priv(inprocess) || $Priv(vlc_handle) ne ""} {
		DestroyVlcHandle
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
		.cms { return 4 }   ;# ChessBase Media System stream (video ref)
		default { return 0 }
	}
}


proc application::media::activate {w flag} {
	# Stop playback when the panel is unmapped/hidden so media does not
	# keep playing (or keep its video window) once the panel is gone.
	if {!$flag} {
		Stop
	}
}


proc application::media::setActive {flag} {
	# Stop and fully release the player when the panel loses focus (e.g. a
	# modal dialog grabs input), so libVLC is not rendering into the Tk
	# window during the dialog's window management.
	if {$flag eq "no"} {
		Stop
	}
}


# Called when the media pane frame is destroyed (bound in application.tcl).
# Fully release the player so libVLC never outlives its embedding window.
proc application::media::closed {frame} {
	Stop
}

# vi:set ts=3 sw=3:
