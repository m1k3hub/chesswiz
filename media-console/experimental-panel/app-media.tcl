# ======================================================================
# ARCHIVED EXPERIMENT — not loaded by Scidb; RE reference only.
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
set SyncBoard		"Sync with board"
set ViewReport		"View report"
set OpenExternal		"Open externally"
set Group				"Media"
set SectionReports	"Reports"
set SectionPictures	"Pictures"
set SectionAudio		"Audio"
set SectionVideo		"Video"
set SectionOther		"Other"
set FollowBoard	"Board follows video"

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
	vlc_available	0
	inprocess	0
	checkid		{}
	seekgrab		0
	seeklabel	{}
	seektick		{}
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

	# --- toolbar: playback + document actions -------------------------
	ttk::frame $ctrl
	ttk::button $ctrl.play -text $mc::Play -command [namespace code [list PlaySelected $tree]]
	ttk::button $ctrl.stop -text $mc::Stop -command [namespace code Stop]
	ttk::separator $ctrl.sep -orient vertical
	ttk::button $ctrl.report -text $mc::ViewReport -command [namespace code ViewReport]
	ttk::button $ctrl.external -text $mc::OpenExternal -command [namespace code OpenSelectedExternal]
	pack $ctrl.play -side left -padx 2
	pack $ctrl.stop -side left -padx 2
	pack $ctrl.sep -side left -fill y -padx 4
	pack $ctrl.report -side left -padx 2
	pack $ctrl.external -side left -padx 2

	# --- media list (left) + viewer (right) ----------------------------
	set pw [ttk::panedwindow $frame.pw -orient horizontal]

	ttk::frame $pw.list
	ttk::treeview $tree \
		-columns {type title path} \
		-displaycolumns {type title} \
		-show {tree headings} \
		-selectmode browse \
		-height 6
	$tree heading #0 -text $mc::Group
	$tree heading type -text $mc::ColumnType
	$tree heading title -text $mc::ColumnTitle
	$tree column type -width 70 -anchor center -stretch false
	$tree column title -width 180 -anchor w
	grid $tree   -row 1 -column 1 -sticky nsew -in $pw.list
	grid rowconfigure $pw.list 1 -weight 1
	grid columnconfigure $pw.list 1 -weight 1
	pack propagate $pw.list 0

	ttk::frame $pw.view
	ttk::frame $viewer -relief sunken -borderwidth 1
	canvas $viewer.canvas -bg black -highlightthickness 0
	pack $viewer.canvas -fill both -expand yes
	grid $viewer -row 1 -column 1 -sticky nsew -in $pw.view
	grid rowconfigure $pw.view 1 -weight 1
	grid columnconfigure $pw.view 1 -weight 1

	$pw add $pw.list -weight 3
	$pw add $pw.view -weight 2

	# --- seek bar: video position slider + time readout ---------------
	set seek $frame.seek
	ttk::frame $seek
	ttk::scale $seek.bar -orient horizontal -from 0 -to 1000 -value 0
	ttk::label $seek.time -textvariable [namespace current]::Priv(seeklabel) \
		-width 12 -anchor e
	pack $seek.bar -side left -fill x -expand yes -padx 2
	pack $seek.time -side right -padx 2
	# dragging owns the slider; the actual seek happens on release
	bind $seek.bar <ButtonPress-1> +[namespace code { set Priv(seekgrab) 1 }]
	bind $seek.bar <ButtonRelease-1> +[namespace code SeekRelease]

	# --- status bar ---------------------------------------------------
	ttk::label $status -textvariable [namespace current]::Priv(statusbar) \
		-anchor w -relief sunken -borderwidth 1

	grid $ctrl   -row 1 -column 1 -sticky ew
	grid $pw     -row 2 -column 1 -sticky nsew
	grid $seek   -row 3 -column 1 -sticky ew
	grid $status -row 4 -column 1 -sticky ew
	grid rowconfigure $frame 2 -weight 1
	grid columnconfigure $frame 1 -weight 1

	bind $tree <Double-Button-1> [namespace code [list PlaySelected $tree]]
	bind $tree <<TreeviewSelect>> [namespace code [list SelectionChanged $tree]]

	set Priv(tree) $tree
	MediaDebug "build: pane twm=[list $twm] frame=[list $frame] tree=[list $tree] mapped=[winfo ismapped $tree]"
	set Priv(viewer) $viewer
	set Priv(statusbar) $mc::NoDatabase
	set Priv(ctrl) $ctrl
	set Priv(seekbar) $seek.bar

	# React to game switches
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	::scidb::db::subscribe databaseSwitch [namespace current]::DatabaseSwitched

	# Board-sync wiring (state machine in tcl/app-media-sync.tcl).
	# The coupling is inherent: no options, always bidirectional.
	::media::sync::configure \
		annotate-cmd	[namespace code SyncAnnotate] \
		clearann-cmd	[namespace code SyncClearAnnotations] \
		transport-cmd	[namespace code SyncTransport] \
		boardforward-cmd	[namespace code SyncBoardForward] \
		boardstart-cmd	[namespace code SyncBoardStart] \
		boardlength-cmd	[namespace code SyncBoardLength] \
		boardply-cmd	[namespace code SyncBoardPly] \
		boardgoto-cmd	[namespace code SyncBoardGoto] \
		boardnode-cmd	[namespace code SyncBoardNode]
}


# Section headers of the grouped list (order matters for display).
proc application::media::Sections {} {
	variable mc
	return [list									\
		reports	$mc::SectionReports	\
		picture	$mc::SectionPictures	\
		audio	$mc::SectionAudio		\
		video	$mc::SectionVideo		\
		other	$mc::SectionOther		\
	]
}

# All leaf items of the grouped list (entries, not section headers).
proc application::media::MediaRows {} {
	variable Priv
	set rows {}
	foreach section [$Priv(tree) children {}] {
		foreach item [$Priv(tree) children $section] { lappend rows $item }
	}
	return $rows
}

# Map a media type (numeric id from ::scidb::db::mediaFiles/mediaGallery:
# 0=none 1=picture 2=audio 3=video 4=stream, or a string label) to a
# section key used by Sections().
proc application::media::TypeNumber {type} {
	switch -glob -- $type {
		picture -	audio -	video -	reports -	other	{ return $type }
		1																{ return picture }
		2																{ return audio }
		3																{ return video }
		default													{ return other }
	}
}

# Insert one entry under its type section; returns the item id.
proc application::media::InsertEntry {typeLabel title path index} {
	variable Priv
	set tree $Priv(tree)

	# map the type label to a section
	set typeNum [TypeNumber $typeLabel]
	set section {}
	foreach {key label} [Sections] {
		if {$key eq $typeNum} { set section section_$key ; break }
	}
	if {![string length $section] || ![$tree exists $section]} {
		foreach {key label} [Sections] {
			set id section_$key
			if {![$tree exists $id]} {
				$tree insert {} end -id $id -open true -text $label -values [list {} {} {}]
			}
		}
		set section section_$typeNum
	}

	set n 0
	while {[$tree exists "item$n"]} { incr n }
	if {[catch { $tree insert $section end -id item$n -values [list $typeLabel $title $path $index] } err]} {
		MediaDebug "InsertEntry: FAILED section=$section item=item$n: $err"
	} else {
		MediaDebug "InsertEntry: section=$section item=item$n type=$typeLabel path=[list $path]"
	}
	return item$n
}


proc application::media::GameSwitched {oldPos newPos} {
	variable Priv
	catch { after cancel $Priv(afterid) }
	set Priv(afterid) [after 1 [namespace code [list Update $newPos]]]
}


proc application::media::DatabaseSwitched {base variant} {
	variable Priv
	set Priv(lastBase) $base
	set Priv(lastVariant) $variant
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
		# independent mode - no game on the board: keep the media of the
		# last opened base playable (gallery browsing without a game).
		set Priv(index) -1
		if {[info exists Priv(lastBase)] && [string length $Priv(lastBase)]
			&& [file exists $Priv(lastBase)]} {
			array unset Priv "interactive:played:*"
			set gallery {}
			catch { set gallery [::scidb::db::mediaGallery $Priv(lastBase) $Priv(lastVariant)] }
			if {[llength $gallery]} {
				MediaDebug "Update: independent gallery returned [llength $gallery] entries"
				foreach gentry $gallery {
					lassign $gentry gpath gtype gtitle gmediaId gindex
					InsertEntry $gtype $gtitle $gpath $gindex
				}
				set Priv(base) $Priv(lastBase)
				set Priv(variant) $Priv(lastVariant)
				set Priv(statusbar) "Media gallery - playable without a game"
				ShowEmptyHint "Media gallery\n\nSelect a media entry to play."
				PrebuildLessons
				return
			}
		}
		set Priv(base) {}
		set Priv(variant) {}
		set Priv(statusbar) $mc::NoDatabase
		ShowEmptyHint $mc::NoDatabase
		return
	}

	lassign [::scidb::game::link? $position] base variant index
	set Priv(base) $base
	set Priv(variant) $variant
	set Priv(index) $index
	set Priv(lastBase) $base
	set Priv(lastVariant) $variant
	# database-level interactive manifest applies to every game
	LoadDbInteractive $base
	LoadUserInteractive

	if {$base eq "" || $index < 0} {
		set Priv(statusbar) $mc::NoMedia
		return
	}

	set entries {}
	catch { set entries [::scidb::db::mediaFiles $base $variant $index] }
	MediaDebug "Update: base=[list $base] index=$index mediaFiles=[llength $entries]"
	if {![llength $entries]} {
		# No per-game media (.scm) — try the gallery (.cbm or .scm gallery)
		set gallery {}
		catch { set gallery [::scidb::db::mediaGallery $base $variant] }
		MediaDebug "Update: game gallery fallback returned [llength $gallery] entries"
		if {[llength $gallery]} {
			set Priv(statusbar) "Media gallery (not game-specific)"
			foreach entry $gallery {
				lassign $entry path type title mediaId gameIndex
				InsertEntry $type $title $path [expr {[string is integer -strict $gameIndex] ? $gameIndex : -1}]
			}
			PrebuildLessons
			return
		}
		set Priv(statusbar) $mc::NoMedia
		ShowEmptyHint "No media for this game.\n\nMedia entries appear here when the\ndatabase has an .scm/.cbm media companion."
		return
	}

	foreach entry $entries {
		lassign $entry path type title mediaId inline
		if {[string is true -strict $inline]} { set path {} }	;# base64 payload: not extractable (docs §6)
		InsertEntry $type $title $path $index
	}
	MediaDebug "Update: done tree=[list $tree] rows=[$tree children {}] mapped=[winfo ismapped $tree] viewable=[winfo viewable $tree]"

	# collect interactive-video indexes (.cms; .scm/.smv manifests already
	# loaded database-level) for board-position–keyed playback
	set Priv(interactive) {}
	array unset Priv "interactive:played:*"
	foreach entry $entries {
		lassign $entry path type title mediaId inline
		if {[string equal -nocase [file extension $path] ".cms"]} {
			lappend Priv(interactive) $path
		}
	}

	PrebuildLessons
	set Priv(statusbar) {}
}


# Open the selected entry with the system default application.
proc application::media::OpenSelectedExternal {} {
	variable Priv

	set sel [$Priv(tree) selection]
	if {![llength $sel]} {
		set Priv(statusbar) "Select a media entry first."
		return
	}
	set values [$Priv(tree) item [lindex $sel 0] -values]
	lassign $values typeLabel title path
	if {![string length $path]} { return }
	LaunchExternal $path
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


# View the guiding-text report of the currently loaded game (if it is
# one); the viewer itself reports "not a report entry" otherwise.
proc application::media::ViewReport {} {
	variable Priv

	if {![string length $Priv(base)]
		|| ![string is integer -strict $Priv(index)]
		|| $Priv(index) < 0} {
		return
	}

	catch {
		::application::report::show $Priv(base) $Priv(variant) $Priv(index)
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

	lassign $values typeLabel title path galleryIndex

	# section headers carry no values: ignore silently
	if {![string length $typeLabel] && ![string length $title]} { return }

	if {![string length $path]} {
		MediaDebug "PlaySelected: empty path (inline media), title=[list $title]"
		set Priv(statusbar) "Cannot play '$title': media is stored inline (not yet extractable)."
		return
	}

	set type [ClassifyFile $path]

	# per-game media items carry no explicit index in their values; the
	# owning game is then whichever game is currently on the board
	if {![string is integer -strict $galleryIndex] || $galleryIndex < 0} {
		set galleryIndex $Priv(index)
	}

	# Coupled lesson (video owned by a game): video + game play as ONE
	# unit — neither without the other (PlayLesson). Requires an owning
	# database: gallery rows without one play as plain media below.
	if {$type == 3 && [string length $Priv(base)] && [string is integer -strict $galleryIndex] && $galleryIndex >= 0} {
		Stop
		if {$galleryIndex != $Priv(index)} {
			set v $Priv(variant) ; if {$v eq ""} { set v Normal }
			::game::new .application -base $Priv(base) -variant $v -number $galleryIndex
			# Update() installs the owning game's media/sync state.
			# Queue playback on the same 1ms timer path as Update's own
			# refresh (scheduled earlier by GameSwitched, so FIFO order
			# guarantees Update runs first) - 'after idle' would race it.
			after 1 [namespace code [list PlayLesson $path $galleryIndex]]
			return
		}
		PlayLesson $path $galleryIndex
		return
	}

	if {[string length $Priv(base)] && [string is integer -strict $galleryIndex] && $galleryIndex >= 0
		&& $galleryIndex != $Priv(index)} {
		set v $Priv(variant) ; if {$v eq ""} { set v Normal }
		::game::new .application -base $Priv(base) -variant $v -number $galleryIndex
		# same ordering argument as above (Update refreshes first)
		after 1 [namespace code [list PlayMedia $path]]
		return
	}

	MediaDebug "PlaySelected: type=[list $typeLabel] path=[list $path] typeNum=$type"

	Stop

	if {$type == 1} {
		# Picture — display inline via Tk photo
		ShowImage $path
	} elseif {[string equal -nocase [file extension $path] ".cms"]} {
		# ChessBase interactive-video index — resolve to the actual position-
		# matched clip (or base video); see ResolveIndex.
		if {[catch { ResolveIndex $path [set [namespace current]::Priv(position)] } res]} {
			MediaDebug "ResolveIndex failed: $res"
			set res {}
		}
		lassign $res video interactive startMs endMs
		if {[string length $video]} {
			set Priv(statusbar) [expr {$interactive
				? "Interactive video for current position"
				: "Video: [file tail [file dirname $video]]"}]
			# a position-matched clip is coupled to the current game
			if {$interactive && [string is integer -strict $Priv(index)] && $Priv(index) >= 0} {
				PlayLesson $video $Priv(index) $startMs $endMs
			} else {
				PlayMedia $video $startMs $endMs
			}
		} else {
			MediaDebug "ResolveIndex: no video found for [list $path]"
			set Priv(statusbar) "No video found next to [file tail $path]"
		}
	} else {
		# Audio/video — embed via tkvlc or launch external
		PlayMedia $path
	}
}


# --- interactive video: position-keyed clips -----------------------------

# Normalize a FEN to the comparison key used by interactive video:
# "<board with rank separators '/' as 'z'> <side>", mirroring the FEN-
# seeded clip filenames ChessBase ships (Windows paths cannot contain
# '/'; they use 'z' instead).
proc application::media::FenKey {fen} {
	if {![string length $fen]} { return {} }
	set parts [split [string trim $fen] " "]
	if {[llength $parts] < 2} { return {} }
	return "[join [split [lindex $parts 0] /] z] [lindex $parts 1]"
}


# Parse the interactive-video entries of a ChessBase .cms file (CBM168
# reverse engineering, CBM_FORMAT_DESIGN.md §7). Layout:
# <db>.html/<name>.cms with a sibling <name>/ clip directory holding
#
#   <FEN with '/' as 'z'>x{X}y{Y}v{V}u{U}.wmv   (position-keyed hotspot)
#   <name>*000.wmv                              (base video, globbed)
#
# Returns {baseline entryList}: baseline = default video path ({} if
# none), entryList rows = {fen file start end label fromSq toSq}
# (start/end empty; fen already the raw file-form; a real FEN, not the
# comparison key; fromSq/toSq = algebraic squares of the hotspot move).
proc application::media::CmsEntries {path} {
	set ext [file rootname $path]		;# <db>.html/<name>
	set dir $ext

	if {![file isdirectory $dir] && ![file exists $path]} { return [list baseline {} entries {}] }

	# hotspot entries live in the .cms itself
	set fh [open $path rb]
	set data [read $fh]
	close $fh
	set entries {}
	set pairs [regexp -all -inline -- {([pnbrqkPNBRQKz0-9]+ [bw] - - 0 1)x(\d+)y(\d+)v(\d+)u(\d+)} $data]
	foreach {whole efen x y v u} $pairs {
		set clip [file join $dir "${whole}.wmv"]
		if {[file exists $clip]} {
			set fromSq [CmsSquare $x]
			set toSq [CmsSquare $y]
			lappend entries [list $efen $clip {} {} "hotspot $fromSq-$toSq" $fromSq $toSq]
		}
	}

	# base video
	set base [lindex [glob -nocomplain -directory $dir *000.wmv] 0]
	if {![string length $base]} { set base [lindex [glob -nocomplain -directory $dir *.wmv] 0] }
	if {[string length $base] && ![file exists $base]} { set base {} }

	return [list baseline $base entries $entries]
}


# Convert a .cms x/y selector (file-major 0-based, a1=0, h8=63) to
# algebraic notation. Verified corpus-wide (109/109 legal moves).
proc application::media::CmsSquare {n} {
	set files {a b c d e f g h}
	set f [lindex $files [expr {$n % 8}]]
	set r [expr {$n / 8 + 1}]
	return "$f$r"
}


# Parse interactive-video entries from a scidb media manifest (see
# SCM_FORMAT_DESIGN.md §1.5). Supported keys inside [Interactive "…"]:
#   Fen, Kind (clip|range), Clip, Media, Start, End, Label.
# Clip paths are relative to the manifest's directory; a Kind: range
# entry plays the referenced [Media] id from Start to End seconds.
# Returns {baseline entryList}: baseline = {} (a manifest's base video
# is an ordinary [Media]/[Game] row), entryList rows =
# {fen file start end label}.
proc application::media::SmvEntries {path} {
	if {![file exists $path]} { return [list baseline {} entries {}] }
	set dir [file dirname $path]

	# pass 1: collect sections
	set sections {}
	array set cur {type {} id {} body {}}
	set fh [open $path r]
	while {[gets $fh line] >= 0} {
		set line [string trim $line]
		if {[string match "\#*" $line] || ![string length $line]} { continue }
		if {[regexp {^\[(\w+)\s*(?:"([^"]*)")?\]} $line -> t id]} {
			if {[string length $cur(type)]} { lappend sections [array get cur] }
			array set cur [list type [string tolower $t] id $id body {}]
			continue
		}
		if {$cur(type) ne ""} { append cur(body) $line "\n" }
	}
	close $fh
	if {[string length $cur(type)]} { lappend sections [array get cur] }

	# pass 2: interpret [Media] blocks, then emit interactive entries
	set mp {}
	set entries {}
	array set keyOf {}
	foreach s $sections {
		array unset s_ ; array set s_ $s
		array unset kv
		array set kv {}
		foreach line [split $s_(body) "\n"] {
			if {[regexp {^([\w\.]+)\s*:\s*(.*)$} $line -> k v]} { set kv([string tolower $k]) [string trim $v "\" \t"] }
		}
		switch -- $s_(type) {
			"media" {
				if {[info exists kv(path)]} { set keyOf($s_(id)) [file join $dir $kv(path)] }
				if {[info exists keyOf($s_(id))]} {
					if {![string length $mp]} {
						set mp $keyOf($s_(id))
					} elseif {[info exists kv(type)] && $kv(type) eq "video"} {
						set mp $keyOf($s_(id))
					}
				}
			}
			"interactive" {
				set kind "clip"
				if {[info exists kv(kind)]} { set kind [string tolower $kv(kind)] }
				set f {}
				switch -- $kind {
					"range" {
						if {[info exists kv(media)] && [info exists keyOf($kv(media))]} { set f $keyOf($kv(media)) }
						if {![info exists kv(start)] || ![info exists kv(end)]} { set f {} }
					}
					default {
						if {[info exists kv(clip)]} { set f [file join $dir $kv(clip)] }
					}
				}
				if {[string length $f] && [file exists $f] && [info exists kv(fen)]} {
					lappend entries [list $kv(fen) $f \
						[expr {[info exists kv(start)] ? $kv(start) : ""}] \
						[expr {[info exists kv(end)] ? $kv(end) : ""}] \
						[expr {[info exists kv(label)] ? $kv(label) : ""}]]
				}
			}
		}
	}
	return [list baseline {} entries $entries]
}


# Match a FEN (of the current board position) against the interactive
# entries. Rows are {fen file start end label ?fromSq toSq?}: SmvEntries
# rows are 5-wide, CmsEntries rows carry the hotspot squares as elements
# 5 and 6.
proc application::media::InteractiveMatch {entryList fen} {
	set key [FenKey $fen]
	if {![string length $key]} { return {} }
	foreach e $entryList {
		if {[FenKey [lindex $e 0]] eq $key} {
			return $e
		}
	}
	return {}
}


# Resolve a .cms (or a .scm interactive sibling) to a playable video for
# the given board position: the position-matched clip if the index has
# one, else the base video. Returns {path interactive?} ({} if nothing).
proc application::media::ResolveIndex {path position} {
	array set smv [SmvEntries "[file rootname $path].smv"]
	set entries $smv(entries)
	set base $smv(baseline)

	# position-matched clip?  .smv wins over .cms when both exist
	set fen ""
	if {![info exists ::application::media::Priv(suppress:fen)] && [info commands ::scidb::game::fen] ne "" && $position >= 0 && $position != 9} {
		catch { set fen [::scidb::game::fen $position] }
	}
	set hit {}
	if {[llength $entries] && [string length $fen]} {
		set hit [InteractiveMatch $entries $fen]
	}
	if {[llength $hit]} {
		return [list [lindex $hit 1] 1 [lindex $hit 2] [lindex $hit 3]]
	}
	if {[string length $base]} { return [list $base 0 {} {}] }

	array set cms [CmsEntries $path]
	if {[llength $cms(entries)] && [string length $fen]} {
		set hit [InteractiveMatch $cms(entries) $fen]
		if {[llength $hit]} {
			# carry the hotspot squares (elements 5/6) for the board arrow
			return [list [lindex $hit 1] 1 [lindex $hit 2] [lindex $hit 3] [lindex $hit 5] [lindex $hit 6]]
		}
	}
	if {[string length $cms(baseline)]} { return [list $cms(baseline) 0 {} {}] }
	return {}
}


# Load the database-level media manifest (<rootname>.scm, the scidb
# native companion format; see SCM_FORMAT_DESIGN.md). Its [Interactive]
# entries apply to every game of the database (position-keyed).
proc application::media::LoadDbInteractive {base} {
	variable Priv

	set Priv(dbInteractive) {}
	set scm "[file rootname $base].scm"
	if {![file exists $scm]} { return }
	if {[catch { array set r [SmvEntries $scm] } msg]} {
		MediaDebug "LoadDbInteractive: parse failed: $msg"
		return
	}
	if {[llength $r(entries)]} {
		set Priv(dbInteractive) $r(entries)
		MediaDebug "LoadDbInteractive: [llength $r(entries)] entries from [list $scm]"
	}
}


# Load the user-level interactive media index
# (<user-dir>/media/interactive.scm): hand-authored position-keyed video
# entries that apply in every database — the scidb replacement for
# hand-annotating media onto games.
# Background prebuild: decode lesson timelines once, shortly after the
# media tree is populated, so the first PlayLesson does not pay the
# ffprobe cost.  In-memory cache ([BoardSync] persistence comes later).
proc application::media::PrebuildLessons {} {
	variable Priv

	set n 0
	foreach item [MediaRows] {
		lassign [$Priv(tree) item $item -values] typeLabel title path galleryIndex
		if {![string length $path] || ![file exists $path]} { continue }
		if {[ClassifyFile $path] != 3} { continue }
		after idle [namespace code [list catch [list ::media::lesson::get $path]]]
		incr n
		if {$n >= 8} break
	}
	if {$n} { MediaDebug "PrebuildLessons: scheduled $n lesson(s)" }
}


proc application::media::LoadUserInteractive {} {
	variable Priv

	set Priv(userInteractive) {}
	set path [file join $::scidb::dir::user media interactive.scm]
	if {![file exists $path]} { return }
	if {[catch { array set r [SmvEntries $path] } msg]} {
		MediaDebug "LoadUserInteractive: parse failed: $msg"
		return
	}
	if {[llength $r(entries)]} {
		set Priv(userInteractive) $r(entries)
		MediaDebug "LoadUserInteractive: [llength $r(entries)] entries from [list $path]"
	}
}


# Called from application::board::update after every board change: with
# 'Sync with board' engaged, entering a position that owns an interactive
# clip jumps the media player to that clip (ChessBase interactive-video
# semantics, implemented on scidb's side with a debounce).
proc application::media::BoardUpdated {position} {
	variable Priv

	# Check at notification time: drive() has cleared this flag by the
	# time the deferred seek runs. Do not cancel a pending user seek here.
	if {[::media::sync::driving?]} { return }

	catch { after cancel $Priv(interactiveid) }
	catch { after cancel $Priv(seekid) }
	set haveInter 0
	if {[info exists Priv(interactive)] && [llength $Priv(interactive)]} { set haveInter 1 }
	if {[info exists Priv(userInteractive)] && [llength $Priv(userInteractive)]} { set haveInter 1 }
	if {[info exists Priv(dbInteractive)] && [llength $Priv(dbInteractive)]} { set haveInter 1 }
	set haveMedia [expr { [info exists Priv(inprocess)] && $Priv(inprocess) }]
	if {!$haveInter && !$haveMedia} { return }
	if {$position != $Priv(position) || $position < 0 || $position == 9} { return }

	# bidirectional coupling (1): stepping the board repositions the media
	set Priv(seekid) [after 250 [namespace code [list PlySeek $position]]]
	if {$haveInter} {
		set Priv(interactiveid) [after 150 [namespace code [list InteractiveFollow $position]]]
	}
}


# Deferred body of BoardUpdated: seek the loaded media to the time the
# board's current ply maps to, so pressing play resumes at the board.
# Skipped while follow mode owns the mapping (media playing): the follow
# tick is the master then, and stepping is what it produces itself.
proc application::media::PlySeek {position} {
	variable Priv

	if {$position != $Priv(position)} { return }
	# Ignore board notifications generated by FollowTick itself.  All other
	# board moves are user-driven and must seek the coupled video, including
	# while the video is currently playing.
	if {[info commands ::media::sync::driving?] ne ""
		&& [::media::sync::driving?]} { return }
	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }
	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	set dur 0
	catch { set dur [expr {1000.0 * [$handle duration]}] }
	set ply [SyncBoardPly]

	# tkvlc exposes seconds; the sync timeline and tolerances use ms.
	set t 0.0
	catch { set t [expr {1000.0 * [$handle time]}] }

	# lesson timeline first (exact per-move timecodes), linear fallback
	set target -1
	catch { set target [::media::sync::ms-for-ply $ply] }
	if {$target >= 0} {
		set tol 500.0
	} else {
		set len [SyncBoardLength]
		if {!$dur || $dur <= 0 || $len <= 1} { return }
		set tol [expr {max(1200.0, $dur / 100.0)}]
		set target [expr {double($ply) / double($len - 1) * ($dur - 300.0)}]
	}
	if {abs($target - $t) > $tol} {
		MediaDebug "PlySeek: ply=$ply -> seek to ${target}ms (media at ${t}ms)"
		catch { $handle time [expr {$target / 1000.0}] }
	}
}


# Deferred body of BoardUpdated: resolve the FEN and jump to a matched
# interactive clip. Debounced so dragging through positions does not
# fire per ply; re-entering the same position does not replay.
proc application::media::InteractiveFollow {position} {
	variable Priv

	if {$position != $Priv(position)} { return }
	set fen ""
	if {[info commands ::scidb::game::fen] ne ""} {
		catch { set fen [::scidb::game::fen $position] }
	}
	set key [FenKey $fen]
	if {![string length $key] || [info exists Priv(interactive:played:$key)]} { return }

	# user-level then database-level manifests first (authored
	# interactivity), then any .cms-derived indexes of the loaded game
	set hit {}
	foreach lst [list [info exists Priv(userInteractive)] [info exists Priv(dbInteractive)]] idx_ {userInteractive dbInteractive} {
		if {$lst && [llength $Priv($idx_)]} {
			set hit [InteractiveMatch $Priv($idx_) $fen]
			if {[llength $hit]} { break }
		}
	}
	if {[llength $hit]} {
		lassign $hit _fen file start end label
		set Priv(interactive:played:$key) 1
		set Priv(statusbar) "Interactive video: $label"
		MediaDebug "InteractiveFollow: manifest match [list $label] -> [list $file]"
		# manifest times are seconds; the player expects milliseconds
		PlayMedia $file [expr {$start ne "" && [string is double -strict $start] ? $start*1000.0 : ""}] \
			[expr {$end ne "" && [string is double -strict $end] ? $end*1000.0 : ""}]
		return
	}

	# The database/user manifest may provide interactivity even when the
	# current game has no .cms index.  Do not read the optional array element
	# unless LoadMedia initialized it.
	set idx ""
	if {[info exists Priv(interactive)] && [llength $Priv(interactive)]} {
		set idx [lindex $Priv(interactive) 0]
	}	;# first interactive index of the game
	if {![string length $idx]} { return }

	if {[catch { ResolveIndex $idx $position } res]} { return }
	if {[llength $res] < 4} { return }
	lassign $res video interactive startMs endMs fromSq toSq
	if {$interactive} {
		set Priv(interactive:played:$key) 1
		set Priv(statusbar) "Interactive video for current position"
		MediaDebug "InteractiveFollow: position match ([FenKey $fen]) -> [list $video]"
		PlayMedia $video $startMs $endMs
		# draw the .cms hotspot (from/to squares of the key move); the
		# board's own update path erases it on the next position change
		if {[string length $fromSq] && [string length $toSq]} {
			SyncAnnotate arrow [list $fromSq $toSq hotspot]
		}
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


# Show a centered hint on the viewer canvas when there is nothing to
# play (empty gallery / no media for the game) instead of a bare black
# canvas, which reads as "broken".
proc application::media::ShowEmptyHint {text} {
	variable Priv
	set canvas $Priv(viewer).canvas
	if {![winfo exists $canvas]} { return }
	$canvas delete all
	set w [winfo width $canvas]
	set h [winfo height $canvas]
	if {$w < 10} { set w 300 }
	if {$h < 10} { set h 200 }
	$canvas create text [expr {$w/2}] [expr {$h/2}] \
		-text $text -fill "#606060" -justify center \
		-font {TkDefaultFont 12 bold}
}


proc application::media::ShowImage {path} {
	variable Priv
	variable mc

	# plain media is not board-coupled: clear any stale lesson sync
	::media::sync::load-timeline {}
	::media::sync::load-events {}

	set canvas $Priv(viewer).canvas

	# Clear previous content
	$canvas delete all

	if {![file exists $path]} {
		set Priv(statusbar) "File not found: $path"
		return
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
		set sx [expr {int(ceil(1.0/$scale))}]
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

	# Package-load state is sticky; the vlc_handle is NOT an indicator of
	# package availability (it only exists while a video is playing).
	if {$Priv(vlc_loaded)} {
		return $Priv(vlc_available)
	}
	set Priv(vlc_loaded) 1

	if {![catch { package require tkvlc } msg]} {
		set Priv(vlc_available) 1
		MediaDebug "LoadVlc: tkvlc loaded"
		return 1
	}

	set Priv(vlc_available) 0
	MediaDebug "LoadVlc: package require tkvlc failed: $msg"
	return 0
}


# Play a coupled media lesson — ONE unit of video commentary + game
# moves.  Neither part is playable without the other: the owning game
# must be on the board, the video must embed in-process (no external
# fallback), and the sync timeline/events binding video and board load
# together from the lesson cache (::media::lesson).
proc application::media::PlayLesson {path gameIndex {startMs {}} {endMs {}}} {
	variable Priv

	if {![file exists $path]} {
		MediaDebug "PlayLesson: video missing: [list $path]"
		set Priv(statusbar) "Lesson video missing: [file tail $path]"
		return 0
	}

	# strict coupling: the owning game must be loaded on the board
	if {![string is integer -strict $gameIndex] || $gameIndex < 0} {
		set Priv(statusbar) "Cannot play: this video is coupled to a game (none selected)."
		MediaDebug "PlayLesson: no owning game for [file tail $path]"
		return 0
	}
	if {$gameIndex != $Priv(index)} {
		set Priv(statusbar) "Cannot play: load the owning game first."
		MediaDebug "PlayLesson: game $gameIndex not loaded (current $Priv(index))"
		return 0
	}

	# lesson: built once (script-stream decode), cached by ::media::lesson
	set lesson [::media::lesson::get $path]
	if {![dict get $lesson valid]} {
		set Priv(statusbar) "Lesson not playable: [dict get $lesson reason]"
		MediaDebug "PlayLesson: invalid lesson: [dict get $lesson reason]"
		return 0
	}
	MediaDebug "PlayLesson: [llength [dict get $lesson timeline]] timeline marks, [llength [dict get $lesson events]] events"

	# node-goal resolution table: the sync state machine reports node
	# indexes; the goto delegate maps them back to FENs via this list
	set Priv(lessonPositions) [dict get $lesson positions]

	# transport first: embedded playback only — a lesson never falls
	# back to an external player (that would decouple video from board)
	if {![PlayInProcess $path $startMs $endMs]} {
		set Priv(statusbar) "Lesson requires embedded video playback (tkvlc)."
		MediaDebug "PlayLesson: embedded playback failed for [file tail $path]"
		::media::sync::load-timeline {}
		::media::sync::load-events {}
		return 0
	}

	# media is playing: sync state machine active (drives the board in
	# follow mode; transport coupling reacts to board playback events).
	::media::sync::load-timeline [dict get $lesson timeline]
	::media::sync::load-events [dict get $lesson events]
	::media::sync::onPlaybackStarted
	StartFollowTick
	return 1
}


proc application::media::PlayMedia {path {startMs {}} {endMs {}}} {
	variable Priv
	variable mc

	if {![file exists $path]} {
		MediaDebug "PlayMedia: file not found: $path"
		set Priv(statusbar) "File not found: $path"
		return
	}

	# plain media is not board-coupled: clear any stale lesson sync
	::media::sync::load-timeline {}
	::media::sync::load-events {}

	# Backend: tkvlc (libVLC) is the only in-process multimedia backend.
	if {[LoadVlc]} {
		MediaDebug "in-process playback available (tkvlc)"
		if {[PlayInProcess $path $startMs $endMs]} {
			return
		}
		MediaDebug "in-process playback failed, falling back to external player"
	}

	# An external player has no board position or transport callbacks.  Do
	# not claim to play a game-coupled video independently of its game.
	if {[ClassifyFile $path] == 3} {
		set Priv(statusbar) "Cannot play video with board synchronization: embedded VLC is unavailable."
		MediaDebug "PlayMedia: refusing unsynchronized external video [list $path]"
		return
	}

	# Fallback: xdg-open / open / start
	LaunchExternal $path
}


# Play a media file using the tkvlc (libVLC) backend.
# Video is embedded into the viewer canvas by passing its X11 window ID
# to ::tkvlc::init.  Returns 1 on success, 0 if tkvlc is unavailable or
# failed, so the caller can fall back to an external player.
proc application::media::PlayInProcess {path {startMs {}} {endMs {}}} {
	variable Priv
	variable mc

	# Lessons and decode retries enter here directly, bypassing PlayMedia.
	# Initialize the backend for every entry path (LoadVlc is cached).
	if {![LoadVlc]} { return 0 }

	set Priv(lastMedia) $path
	set Priv(lastStartMs) $startMs
	set Priv(lastEndMs) $endMs
	# reset the decode-retry budget only for a new file; a CheckDecode
	# retry of the same file must keep the counter or it loops forever
	if {![info exists Priv(vlcretrypath)] || $Priv(vlcretrypath) ne $path} {
		set Priv(vlcretry) 0
		set Priv(vlcretrypath) $path
	}

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

	# tkvlc: the in-process transport
	set Priv(statusbar) "tkvlc path"

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

	# Interactive 'range' entries: seek into the video and stop at End.
	catch { after cancel $Priv(rangeid) }	;# a stale stop timer must not kill the new clip
	set Priv(rangeid) {}
	if {![string is double -strict $startMs] || $startMs < 0} { set startMs 0 }
	if {$startMs > 0} {
		catch { $handle time [expr {$startMs / 1000.0}] }
	}
	if {[string is double -strict $endMs] && $endMs > $startMs} {
		set Priv(rangeid) [after [expr {int($endMs - $startMs)}] \
			[namespace code { catch { Stop } }]]
	}

	set Priv(inprocess) 1
	set Priv(statusbar) "Playing: $path"
	MediaDebug "PlayInProcess: playback started for $path"
	StartSeekTick

	# sync timeline/events are loaded by PlayLesson (lesson cache); plain
	# media keeps an empty sync state (linear fallback in drive)

	# Check shortly after that playback actually started (media decoded).
	catch { after cancel $Priv(checkid) }
	set Priv(checkid) [after 800 [namespace code [list CheckDecode $path]]]
	return 1
}


# Load the optional ChessBase script-stream sidecar for a media file:
#
# 	media-console/wmv2timeline.py writes the real per-move timecodes
# 	(one media-ms per line, replay order; decoded with the verified
# 	file-major square conventions).  When present, "board follows
# 	video" follows the actual lesson replay instead of the linear
# 	duration mapping; without it the state machine keeps the linear
# 	fallback.
# Load the optional board-annotation sidecar (one event per line:
# "ms kind payload...").  Loaded alongside the timeline so the sync
# state machine can fire board annotations during playback.
proc application::media::LoadSyncEvents {path} {
	set eventsfile [file rootname $path].events
	if {![file exists $eventsfile]} {
		::media::sync::load-events {}
		MediaDebug "SyncEvents: none for [file tail $path]"
		return
	}
	set events [list]
	if {![catch {open $eventsfile r} fh]} {
		set data [read $fh]
		close $fh
		foreach line [split $data "\n"] {
			set line [string trim $line]
			if {[llength $line] >= 3 && ![string match "#*" $line]} {
				lappend events $line
			}
		}
	}
	::media::sync::load-events $events
	MediaDebug "SyncEvents: [llength $events] loaded from [file tail $eventsfile]"
}


proc application::media::LoadSyncSidecar {path} {
	variable Priv
	set syncfile [file rootname $path].plytimes
	if {![file exists $syncfile]} {
		::media::sync::load-timeline {}
		MediaDebug "SyncSidecar: none for [file tail $path]"
		return
	}
	set marks [list]
	if {![catch {open $syncfile r} fh]} {
		set data [read $fh]
		close $fh
		foreach line [split $data "\n"] {
			set line [string trim $line]
			if {[string is integer -strict $line]} {
				lappend marks $line
			}
		}
	}
	::media::sync::load-timeline $marks
	MediaDebug "SyncSidecar: [llength $marks] timecodes loaded from [file tail $syncfile]"
}


# Verify a just-started tkvlc playback actually started.  An unsupported
# or corrupt file will report an error state, so surface a clear error
# rather than leaving the panel silently blank.
proc application::media::CheckDecode {path} {
	variable Priv

	if {!$Priv(inprocess)} { return }

	if {$Priv(vlc_handle) eq ""} { return }

	set handle $Priv(vlc_handle)

	set state ""
	catch { set state [$handle state] }
	MediaDebug "CheckDecode: state=$state"

	if {$state eq "error" || $state eq "idle" || $state eq "ended"} {
		if {![info exists Priv(vlcretry)] || $Priv(vlcretry) < 1} {
			set Priv(vlcretry) 1
			MediaDebug "CheckDecode: state=$state -> retrying once (demux pre-fill hiccup)"
			# retry via PlayInProcess: PlayMedia would clear a playing
			# lesson's sync timeline/events
			catch { PlayInProcess $Priv(lastMedia) $Priv(lastStartMs) $Priv(lastEndMs) }
			return
		}
	}

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


# ----------------------------------------------------------------------
# Media <-> board synchronization (see tcl/app-media-sync.tcl)
# ----------------------------------------------------------------------

# Transport delegate: play/pause the current tkvlc media.
proc application::media::SyncTransport {what} {
	variable Priv

	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }

	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	switch -- $what {
		play {
			set st ""; catch { set st [$handle state] }
			if {$st eq "paused" || $st eq "ended"} {
				catch { $handle play }
				# a resumed transport must re-arm the follow loop
				StartFollowTick
			}
		}
		pause {
			set st ""; catch { set st [$handle state] }
			if {$st eq "playing"} {
				catch { $handle pause }
			}
		}
	}
}

# Board annotation delegate: receives decoded script events from
# ::media::sync (arrows/marks render future, comments go to the status
# bar).  The kind and data arguments come from ::media::sync::load-events.
# Map a style byte (from the decoded script stream) to a drawable color.
# VISUAL-ORACLE VERDICT (Reader14 on Windows, 2026-09-07, CHESSBASE_MEDIA_RE.md
# "Reader14 on genuine Windows"): script-stream style bytes carry NO colour.
# Style 2 renders green (corridor-verified 51-75%); style 4 rendered green or
# nothing; zero red/yellow/blue overlay pixels in 136 frames across 3 videos.
# Every script annotation renders one green regardless of style/class, so the
# 3/4 entries below are dead data kept only for the .cba classic palette
# (a different record family).  Opcode-04 board-action CLASS values (0x80,
# 0x200, ...) also arrive in the style slot via the lesson events; they never
# match here and fall back to the default green.  Green fallback is correct.
variable SyncColors
array set SyncColors { 2 green 3 yellow 4 red }

# ChessBase .cms interactive-video hotspots use the default arrow color.
array set SyncColors { hotspot green }

proc application::media::SyncAnnotate {kind data} {
	variable Priv
	variable SyncColors

	switch -- $kind {
		arrow {
			lassign $data from to style
			set color "green"
			if {[info exists SyncColors($style)]} {
				set color $SyncColors($style)
			}
			# draw on the active board widget
			set brd [application::media::boardWidget]
			if {$brd eq ""} { return }
			set fromIdx [algebraic_to_index $from]
			set toIdx   [algebraic_to_index $to]
			if {$fromIdx >= 0 && $toIdx >= 0} {
				::board::diagram::drawAlternative $brd $fromIdx $toIdx $color ""
			}
		}
		mark {
			lassign $data square style
			set brd [application::media::boardWidget]
			if {$brd eq ""} { return }
			set sqIdx [algebraic_to_index $square]
			if {$sqIdx >= 0} {
				::board::diagram::hilite $brd $sqIdx "suggested"
			}
		}
		comment {
			if {[llength $data] >= 3} {
				set text [lindex $data 2]
			} else {
				set text [join $data " "]
			}
			set Priv(statusbar) "\u25b6 $text"
		}
		symbol {
			MediaDebug "SyncAnnotate: symbol $data"
		}
	}
}


proc application::media::SyncClearAnnotations {} {
	variable Priv
	set Priv(statusbar) ""

	set brd [application::media::boardWidget]
	if {$brd eq ""} { return }
	::board::diagram::clearMarks $brd

	# remove all transient alternative arrows drawn by the sync layer
	set canv [::board::diagram::canvas $brd]
	if {$canv ne ""} {
		foreach item [$canv find withtag alternative:*] {
			$canv delete $item
		}
	}
}

# Convert an algebraic square ("c4") to its file-major 0-63 index.
proc application::media::algebraic_to_index {sq} {
	if {[string length $sq] < 2} { return -1 }
	set file [scan [string index $sq 0] %c]
	set file [expr {$file - [scan a %c]}]
	set rank [scan [string index $sq 1] %d]
	if {$file < 0 || $file > 7 || $rank < 1 || $rank > 8} { return -1 }
	return [expr {$file * 8 + ($rank - 1)}]
}

# Resolve the active board widget identifier for ::board::diagram calls.
# The board is stored in the application::board namespace (set by build()).
proc application::media::boardWidget {} {
	if {![info exists ::application::board::board]} { return "" }
	set brd $::application::board::board
	if {![winfo exists $brd]} { return "" }
	return $brd
}


# Board delegates for "board follows video" mode.
proc application::media::SyncBoardForward {} {
	catch { ::scidb::game::go -1 1 }
}

proc application::media::SyncBoardStart {} {
	catch { ::scidb::game::go -1 start }
}

proc application::media::SyncBoardLength {} {
	if {[catch { set len [::scidb::game::query -1 length] }]} { return 0 }
	if {![string is integer -strict $len]} { return 0 }
	return $len
}

# Node-goal delegate (lesson v2): jump the board directly to a lesson
# node. The lesson's position list (stored by PlayLesson) maps the node
# index to a Scidb-dialect FEN, and `go -1 position $fen` navigates the
# game tree — mainline AND variations (Game::goToPosition searches the
# whole tree; it never detaches from the game: an unmatched FEN parks at
# the mainline end instead of creating a scratch position).
proc application::media::SyncBoardGoto {node} {
	variable Priv

	if {![info exists Priv(lessonPositions)]} { return }
	set fen [lindex $Priv(lessonPositions) $node]
	if {![string length $fen]} { return }

	# R9: same-node no-op — a seek-bar drag burst across one node must
	# not fire repeated gotos (the sync machine pre-filters, but the
	# game fen also settles this for manual navigation races). Compare
	# board+side only (isEqualZHPosition semantics: counters ignored).
	set cur ""
	catch { set cur [::scidb::game::fen -1] }
	if {[FenKey $cur] eq [FenKey $fen] && [string length $cur]} { return }

	if {[catch { ::scidb::game::go -1 position $fen } err]} {
		MediaDebug "SyncBoardGoto: node=$node failed: $err"
		return
	}

	# statusbar node/ply context + throttled debug trace for goto jumps
	set Priv(statusbar) "Lesson node $node/[expr {[llength $Priv(lessonPositions)] - 1}]"
	set now [clock seconds]
	if {![info exists Priv(gotoDebugAt)] || $now != $Priv(gotoDebugAt)} {
		set Priv(gotoDebugAt) $now
		MediaDebug "SyncBoardGoto: node=$node fen=[list $fen]"
	}
}

# Inverse mapping: the board's current position as a lesson node index
# (-1 when the position is not part of the lesson). Used to re-sync the
# sync machine's goal after manual board navigation (R8).
proc application::media::SyncBoardNode {} {
	variable Priv

	if {![info exists Priv(lessonPositions)]} { return -1 }
	set fen ""
	if {[catch { set fen [::scidb::game::fen -1] }] || ![string length $fen]} { return -1 }
	set idx [lsearch -exact $Priv(lessonPositions) $fen]
	if {$idx < 0} {
		# counters may differ between the game FEN and the lesson FEN
		# (isEqualZHPosition semantics): retry on board+side only
		set key "[lindex [split $fen " "] 0] [lindex [split $fen " "] 1]"
		set i 0
		foreach pos $Priv(lessonPositions) {
			set pkey "[lindex [split $pos " "] 0] [lindex [split $pos " "] 1]"
			if {$pkey eq $key} { set idx $i; break }
			incr i
		}
	}
	return $idx
}

# Same as ::scidb::game::ply but always returns an integer (may be called
# before the scratch game exists).
proc application::media::SyncBoardPly {} {
	if {[catch { set ply [::scidb::game::ply] }]} { return 0 }
	if {![string is integer -strict $ply]} { return 0 }
	return $ply
}

# One tick of "board follows video": map the media position linearly onto
# the game and step the main board accordingly.
proc application::media::FollowTick {} {
	variable Priv

	set Priv(followafter) {}

	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }

	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	set st ""; catch { set st [$handle state] }
	if {$st ne "playing"} {
		# video paused/ended: stop the follow loop; a resumed Transport
		# play restarts it.
		return
	}

	set t 0; set dur 0
	catch { set t [expr {1000.0 * [$handle time]}] }
	catch { set dur [expr {1000.0 * [$handle duration]}] }
	if {$t eq "" || $dur eq ""} { return }

	::media::sync::drive $t $dur

	# reschedule while follow mode stays enabled
	StartFollowTick
}

# --- seek bar -------------------------------------------------------------

proc application::media::FormatMs {ms} {
	set s [expr {int($ms / 1000)}]
	return [format "%d:%02d" [expr {$s / 60}] [expr {$s % 60}]]
}


# Periodic UI tick while media is loaded: track the playback position on
# the slider (unless the user is dragging it) and the time readout.
proc application::media::SeekTick {} {
	variable Priv

	set Priv(seektick) {}
	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }
	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	set t 0; set dur 0
	catch { set t [expr {1000.0 * [$handle time]}] }
	catch { set dur [expr {1000.0 * [$handle duration]}] }
	if {[string is double -strict $t] && [string is double -strict $dur] && $dur > 0} {
		if {!$Priv(seekgrab) && [winfo exists $Priv(seekbar)]} {
			catch { $Priv(seekbar) set [expr {double($t) / $dur * 1000.0}] }
		}
		set Priv(seeklabel) "[FormatMs $t] / [FormatMs $dur]"
	}

	set Priv(seektick) [after 500 [namespace code SeekTick]]
}


proc application::media::StartSeekTick {} {
	variable Priv
	catch { after cancel $Priv(seektick) }
	set Priv(seektick) [after 500 [namespace code SeekTick]]
}


# Slider released: seek the video to the slider position.  Follow mode
# then remaps the board to the new time on the next drive tick, so board
# and video stay one unit.
#
# R9: rapid drag-release bursts are coalesced — only the last target in
# a 200 ms window reaches the player, so follow mode does not chase a
# storm of intermediate positions (the sync machine's same-node no-op
# filters the board side; this filters the media side).
proc application::media::SeekRelease {} {
	variable Priv

	set Priv(seekgrab) 0
	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }
	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	set dur 0
	catch { set dur [$handle duration] }
	if {![string is double -strict $dur] || $dur <= 0} { return }

	set frac [expr {[$Priv(seekbar) get] / 1000.0}]

	# coalesce: replace any pending debounced seek with this one
	catch { after cancel $Priv(seekdebounce) }
	set Priv(seekdebounce) [after 200 [namespace code [list SeekApply $frac $dur]]]
}

# Debounced body of SeekRelease: the actual media seek.
proc application::media::SeekApply {frac dur} {
	variable Priv

	if {![info exists Priv(inprocess)] || !$Priv(inprocess)} { return }
	set handle $Priv(vlc_handle)
	if {$handle eq ""} { return }

	MediaDebug "SeekApply: seek to [expr {int($frac * 100)}]% of ${dur}s"
	catch { $handle time [expr {$frac * $dur}] }
}


proc application::media::StartFollowTick {} {
	variable Priv

	catch { after cancel $Priv(followafter) }
	set Priv(followafter) [after 250 [namespace code FollowTick]]
}

proc application::media::StopFollowTick {} {
	variable Priv

	catch { after cancel $Priv(followafter) }
	set Priv(followafter) {}
}

proc application::media::Stop {} {
	variable Priv

	catch { after cancel $Priv(checkid) }
	catch { after cancel $Priv(rangeid) }
	catch { after cancel $Priv(seekid) }
	catch { after cancel $Priv(interactiveid) }
	catch { after cancel $Priv(seektick) }
	set Priv(checkid) {}
	set Priv(rangeid) {}
	set Priv(seektick) {}
	set Priv(seeklabel) {}
	catch {
		if {[info exists Priv(seekbar)] && [winfo exists $Priv(seekbar)]} {
			$Priv(seekbar) set 0
		}
	}

	if {![info exists Priv(viewer)]} { return }   ;# panel not built yet

	# media no longer playing: reset the sync state machine and timers
	StopFollowTick
	::media::sync::onPlaybackStopped

	# Stop and release tkvlc playback.
	if {[info exists Priv(inprocess)] && $Priv(inprocess)} {
		DestroyVlcHandle
	} elseif {[info exists Priv(vlc_handle)] && $Priv(vlc_handle) ne ""} {
		DestroyVlcHandle
	}

	# Clear canvas
	if {[winfo exists $Priv(viewer).canvas]} {
		$Priv(viewer).canvas delete all
	}
}


proc application::media::ClassifyFile {path} {
	set ext [string tolower [file extension $path]]
	switch -- $ext {
		.jpg - .jpeg - .png - .bmp - .gif { return 1 }
		.mp3 - .wav - .ogg - .flac { return 2 }
		.mp4 - .avi - .wmv - .mkv - .webm - .mpg - .mpeg { return 3 }
		.m3u8 - .pls - .cms {
			# ChessBase Media System stream (video ref)
			return 4
		}
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
	variable Priv
	catch { after cancel $Priv(afterid) }
	set Priv(afterid) {}
	Stop
}

# vi:set ts=3 sw=3:
