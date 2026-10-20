# ======================================================================
# Database discovery — system-wide scan for chess database files
# ======================================================================
# A chess database is spread over several files: a Scidb/Scid index plus
# its game/name companions, a ChessBase .cbh plus its .cbg/.cba/...
# satellites.  Discovery lists only the *primary* (index/header) file of
# each database, recognised by extension and confirmed by magic bytes
# where the format has a stable signature, so companions are never
# offered as databases of their own.
#
# The scan is incremental: the walker consumes a small directory budget
# per event-loop tick, so the UI stays responsive and the scan can be
# cancelled.  The pure classification/walk helpers are UI-free and are
# covered by tests/test_database_discover.tcl.
# ======================================================================

::util::source database-discover

namespace eval ::application::database::discover {
namespace eval mc {

set Title				"Discover Databases"
set Roots				"Search locations"
set AddRoot			"Add..."
set RemoveRoot		"Remove"
set Options			"Options"
set MaxDepth			"Maximum depth"
set IncludePgn		"Include PGN and game-notation files"
set Start				"Start scan"
set Stop				"Stop"
set Rescan			"Rescan"
set Found				"Databases found"
set Filter				"Filter databases"
set FilterCount		"%d of %d"
set ColumnType		"Type"
set ColumnName		"Name"
set ColumnGames		"Games"
set ColumnSize		"Size"
set ColumnPath		"Folder"
set AddSelected		"Add to switcher"
set OpenSelected		"Open"
set Close				"Close"
set NoRoots			"No search locations selected."
set NoneFound		"No chess databases found."
set Scanning			"Scanning \u2026 %d folders, %d databases"
set Scanned			"%d folders scanned, %d databases found."
set Stopped			"Scan stopped: %d folders, %d databases."
set Added			"Added %d database(s) to the switcher."
set AlreadyAdded	"Already in the switcher: %d."
set SelectFirst		"Select a database first."
set ScanningBusy	"A scan is already running."

} ;# namespace mc

variable Priv

# A discovery result is a 5-element list:
#   {ext format-label path size games}
# games is -1 when unknown (PGN/archive) or unreadable.
array set Priv {
	parent			{}
	dialog			{}
	scanning			0
	cancel			0
	queue				{}
	qhead				0
	visit				{}
	seen				{}
	results			{}
	dirs				0
	maxdepth			6
	includePgn		1
	progressCmd		{}
	doneCmd			{}
	after				{}
	filter			{}
	filterAfter		{}
	statusBase		{}
	roots				{}
}

} ;# namespace ::application::database::discover


# ----------------------------------------------------------------------
# File-type knowledge (pure; no I/O beyond the header probe)
# ----------------------------------------------------------------------

# Primary database extensions -> {format-label family}.  The family is
# only a coarse grouping for the dialog; the authoritative database type
# is resolved by openBase() when the file is opened.
proc ::application::database::discover::formats {} {
	return [dict create \
		sci		[list "Scidb database"		scidb] \
		si4		[list "Scid database (v4)"	scid] \
		si3		[list "Scid database (v3)"	scid] \
		cbh		[list "ChessBase database"	chessbase] \
		cbf		[list "ChessBase DOS"		chessbase] \
		cbv		[list "ChessBase archive"	chessbase] \
		2cbh		[list "ChessBase 2"		chessbase] \
		scv		[list "Scidb archive"		archive] \
		pgn		[list "PGN game file"		pgn] \
		bpgn		[list "BPGN game file"		bpgn]]
}

# Multi-part suffixes that file extension alone cannot express.
proc ::application::database::discover::_ext {path} {
	set name [file tail $path]
	foreach multi {pgn.gz bpgn.gz} {
		if {[string match -nocase "*.$multi" $name]} { return [string tolower $multi] }
	}
	return [string tolower [string trimleft [file extension $name] .]]
}

proc ::application::database::discover::_starts {data prefix} {
	return [string equal -length [string length $prefix] $data $prefix]
}

# Read the leading bytes of a candidate file (empty on failure).
proc ::application::database::discover::_header {path} {
	# NOTE: ::open - this namespace defines an `open` dialog entry point
	# that would otherwise shadow Tcl's built-in channel command.
	if {[catch { set fh [::open $path rb] }]} { return {} }
	fconfigure $fh -translation binary
	set data [read $fh 16]
	close $fh
	return $data
}

# Confirm a binary format against its on-disk signature.  Formats whose
# header is not stable (ChessBase satellites/archives) are accepted on
# the extension alone - a wrongly-named file fails cleanly on open.
proc ::application::database::discover::_confirm {path ext} {
	switch -- $ext {
		sci		{ return [_starts [_header $path] "Scidb.i"] }
		si4		{ return [_starts [_header $path] "Scid.si4"] }
		si3		{ return [_starts [_header $path] "Scid.si3"] }
		scv		{ return [_starts [_header $path] "iveArch"] }
	}
	return 1
}

# Classify a path as a chess database.  Returns {} for anything that is
# not a primary database file, otherwise {ext label path size games}.
proc ::application::database::discover::classify {path {includePgn 1}} {
	if {![file isfile $path]} { return {} }

	set ext [_ext $path]
	if {![dict exists [formats] $ext]} { return {} }

	switch -- $ext {
		pgn - pgn.gz - bpgn - bpgn.gz {
			if {!$includePgn} { return {} }
			if {[file size $path] == 0} { return {} }
		}
		default {
			if {![_confirm $path $ext]} { return {} }
		}
	}

	set label [lindex [dict get [formats] $ext] 0]
	return [list $ext $label $path [file size $path] [_games $path $ext]]
}

# Game count for the formats whose header carries it (Scidb/Scid/
# ChessBase); -1 when unknown or unreadable.
proc ::application::database::discover::_games {path ext} {
	switch -- $ext {
		pgn - pgn.gz - bpgn - bpgn.gz - scv { return -1 }
	}
	if {[catch { set n [::scidb::misc::size $path] }]} { return -1 }
	if {![string is integer -strict $n]} { return -1 }
	return $n
}

# Default scan roots: the user's home and standard XDG folders plus the
# usual removable-media mount points.  Only existing directories are
# returned.
proc ::application::database::discover::defaultRoots {} {
	set roots {}

	set home $::scidb::dir::home
	if {[file isdirectory $home]} { lappend roots $home }
	foreach sub {Documents Desktop Downloads} {
		set dir [file join $home $sub]
		if {[file isdirectory $dir]} { lappend roots $dir }
	}
	if {[file isdirectory [file join $home .local share]]} {
		lappend roots [file join $home .local share]
	}

	set user ""
	if {[info exists ::env(USER)]} { set user $::env(USER) }
	foreach dir [list \
		[expr {[string length $user] ? "/media/$user" : ""}] \
		[expr {[string length $user] ? "/run/media/$user" : ""}] \
		/media /mnt] {
		if {[string length $dir] && [file isdirectory $dir]} { lappend roots $dir }
	}

	return [lsort -unique $roots]
}

# Directories that must never be walked (pseudo-filesystems, VCS and
# package caches, trash).
proc ::application::database::discover::_denied {dir} {
	set tail [file tail $dir]
	if {$tail in {.git .svn .hg node_modules .cache .Trash Trash}} { return 1 }
	foreach prefix {/proc /sys /dev /lost+found /var/cache /var/lib/docker /snap} {
		if {$dir eq $prefix || [string match "$prefix/*" $dir]} { return 1 }
	}
	return 0
}


# ----------------------------------------------------------------------
# Walker (queue based; used synchronously by tests, incrementally by the
# dialog)
# ----------------------------------------------------------------------

proc ::application::database::discover::_begin {roots maxdepth includePgn} {
	variable Priv

	set Priv(queue) {}
	foreach root $roots {
		if {[file isdirectory $root]} {
			lappend Priv(queue) [list [file normalize $root] 0]
		}
	}
	set Priv(qhead) 0
	set Priv(visit) {}
	set Priv(seen) {}
	set Priv(results) {}
	set Priv(dirs) 0
	set Priv(maxdepth) $maxdepth
	set Priv(includePgn) $includePgn
	set Priv(cancel) 0
	set Priv(scanning) 1
}

# Pick up the next queued directory: apply the denylist and the
# seen-set, then list the folder.  An empty or skipped folder leaves
# Priv(visit) empty.  The listing itself stays a single glob; the
# per-entry work (stat, header probe, game count) is chunked by _step.
proc ::application::database::discover::_openVisit {dir depth} {
	variable Priv

	if {[_denied $dir]} { return }
	set real [file normalize $dir]
	if {[dict exists $Priv(seen) $real]} { return }
	dict set Priv(seen) $real 1
	incr Priv(dirs)

	set entries {}
	catch { set entries [glob -nocomplain -directory $dir -types {d f} *] }
	catch { lappend entries {*}[glob -nocomplain -directory $dir -types {d f} .*] }
	if {![llength $entries]} { return }
	set Priv(visit) [list $dir $depth $entries 0]
}

# Classify one listed entry: sub-directories are queued, databases are
# appended to the results.
proc ::application::database::discover::_visitEntry {dir depth entry} {
	variable Priv

	set tail [file tail $entry]
	if {$tail eq "." || $tail eq ".."} { return }
	# a file can vanish between glob and here (browser caches, temp files)
	if {[catch { file type $entry } type] || $type eq "link"} { return }

	if {[file isdirectory $entry]} {
		if {$depth < $Priv(maxdepth)} {
			lappend Priv(queue) [list $entry [expr {$depth + 1}]]
		}
	} else {
		if {[catch { classify $entry $Priv(includePgn) } entryInfo]} { return }
		if {[llength $entryInfo]} { lappend Priv(results) $entryInfo }
	}
}

# Consume up to $budget directories.  Returns 1 while work remains.
# Visits at most <budget> folders, and with <ms> also stops after that many
# milliseconds: listing folders can be slow (Windows: 150 folders took 10-20 s
# with a virus scanner), and the dialog must stay responsive.  The time check
# also interrupts a single folder's entry list -- one full folder must never
# be processed in one go, or a folder that scans slowly still freezes the UI.
# An interrupted visit resumes at the next entry on the next tick.
proc ::application::database::discover::_step {budget {ms 0}} {
	variable Priv

	set deadline [expr {$ms > 0 ? [clock milliseconds] + $ms : 0}]
	while {1} {
		if {![llength $Priv(visit)]} {
			if {$Priv(qhead) >= [llength $Priv(queue)]} { return 0 }
			if {$budget <= 0} { return 1 }
			lassign [lindex $Priv(queue) $Priv(qhead)] dir depth
			incr Priv(qhead)
			incr budget -1
			_openVisit $dir $depth
			continue
		}

		if {$deadline && [clock milliseconds] >= $deadline} { return 1 }

		lassign $Priv(visit) dir depth entries next
		set entry [lindex $entries $next]
		incr next
		if {$next >= [llength $entries]} {
			set Priv(visit) {}
		} else {
			set Priv(visit) [list $dir $depth $entries $next]
		}
		_visitEntry $dir $depth $entry
	}
}

# Synchronous scan (tests, small trees).  Returns the result list.
proc ::application::database::discover::scanSync {roots {maxdepth 6} {includePgn 1}} {
	variable Priv

	_begin $roots $maxdepth $includePgn
	while {[_step 1000000]} {}
	set Priv(scanning) 0
	return $Priv(results)
}


# ----------------------------------------------------------------------
# Incremental scan for the dialog
# ----------------------------------------------------------------------

proc ::application::database::discover::start {roots maxdepth includePgn progressCmd doneCmd} {
	variable Priv

	if {$Priv(scanning)} { return 0 }
	_begin $roots $maxdepth $includePgn
	set Priv(progressCmd) $progressCmd
	set Priv(doneCmd) $doneCmd
	_tick
	return 1
}

proc ::application::database::discover::stop {} {
	variable Priv
	if {$Priv(scanning)} { set Priv(cancel) 1 }
}

proc ::application::database::discover::scanning? {} {
	variable Priv
	return $Priv(scanning)
}

proc ::application::database::discover::results {} {
	variable Priv
	return $Priv(results)
}

proc ::application::database::discover::_tick {} {
	variable Priv

	if {!$Priv(scanning)} { return }
	if {$Priv(cancel)} { _finish ; return }

	set more [_step 150 50]
	if {[llength $Priv(progressCmd)]} {
		uplevel #0 $Priv(progressCmd) [list $Priv(dirs) [llength $Priv(results)]]
	}

	if {$more} {
		set Priv(after) [after 1 [namespace current]::_tick]
	} else {
		_finish
	}
}

proc ::application::database::discover::_finish {} {
	variable Priv

	catch { after cancel $Priv(after) }
	set Priv(after) {}
	set Priv(scanning) 0
	set Priv(cancel) 0
	if {[llength $Priv(doneCmd)]} {
		uplevel #0 $Priv(doneCmd) [list $Priv(results)]
	}
}


# ----------------------------------------------------------------------
# Dialog
# ----------------------------------------------------------------------

proc ::application::database::discover::open {parent} {
	variable Priv
	variable mc

	if {[winfo exists $Priv(dialog)]} {
		raise $Priv(dialog)
		focus $Priv(dialog)
		return
	}

	set Priv(parent) $parent
	set dlg $parent.__discover__
	set Priv(dialog) $dlg

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	# --- search locations --------------------------------------------
	set left [ttk::labelframe $top.roots -text $mc::Roots]
	pack $left -side left -fill both -expand yes
	listbox $left.list -height 7 -selectmode extended -exportselection no
	ttk::scrollbar $left.vs -orient vertical -command [list $left.list yview]
	$left.list configure -yscrollcommand [list $left.vs set]
	pack $left.list -side left -fill both -expand yes -padx {2 0} -pady 2
	pack $left.vs -side right -fill y -pady 2

	set lbtns [ttk::frame $left.buttons]
	pack $lbtns -side bottom -fill x -pady {0 2}
	ttk::button $lbtns.add -text $mc::AddRoot -command [namespace code AddRoot]
	ttk::button $lbtns.remove -text $mc::RemoveRoot -command [namespace code RemoveRoot]
	pack $lbtns.add $lbtns.remove -side left -padx 2

	# --- options ------------------------------------------------------
	set right [ttk::labelframe $top.options -text $mc::Options]
	pack $right -side left -fill both -expand yes -padx [list $::theme::padx 0]
	set depth [ttk::frame $right.depth]
	pack $depth -fill x -pady 2
	ttk::label $depth.label -text $mc::MaxDepth
	spinbox $depth.spin -from 1 -to 64 -width 4 -textvariable \
		[namespace current]::Priv(maxdepth)
	pack $depth.label -side left
	pack $depth.spin -side left -padx 4
	ttk::checkbutton $right.pgn -text $mc::IncludePgn -variable \
		[namespace current]::Priv(includePgn)
	pack $right.pgn -fill x -pady 2

	set actions [ttk::frame $right.actions]
	pack $actions -fill x -pady {6 2}
	ttk::button $actions.start -text $mc::Start -command [namespace code StartScan]
	pack $actions.start -fill x

	set Priv(progress) [ttk::progressbar $right.progress -mode determinate \
		-maximum 100 -value 0]
	pack $Priv(progress) -fill x -pady 2
	ttk::label $right.status -textvariable [namespace current]::Priv(status) \
		-anchor w -justify left -wraplength 260
	pack $right.status -fill x

	# --- results ------------------------------------------------------
	set res [ttk::labelframe $dlg.results -text $mc::Found]
	pack $res -fill both -expand yes -padx $::theme::padx -pady [list 0 $::theme::pady]
	set Priv(filter) ""
	set filter [ttk::frame $res.filter]
	ttk::label $filter.label -text $mc::Filter
	searchentry $filter.entry -textvariable [namespace current]::Priv(filter) \
		-mode enter -usehistory 0 -buttons {erase}
	pack $filter.label -side left -padx 2
	pack $filter.entry -side left -fill x -expand yes
	pack $filter -side top -fill x -pady 2
	trace add variable Priv(filter) write [namespace code _filterChanged]
	bind $filter.entry.e <Escape> "[namespace code [list ClearFilter $filter.entry]]; break"
	ttk::treeview $res.tree \
		-columns {name games size path} \
		-displaycolumns {name games size path} \
		-show {tree headings} \
		-selectmode extended \
		-height 12
	$res.tree heading #0 -text $mc::ColumnType
	$res.tree heading name -text $mc::ColumnName
	$res.tree heading games -text $mc::ColumnGames
	$res.tree heading size -text $mc::ColumnSize
	$res.tree heading path -text $mc::ColumnPath
	$res.tree column #0 -width 150 -stretch false
	$res.tree column name -width 200
	$res.tree column games -width 60 -anchor e -stretch false
	$res.tree column size -width 70 -anchor e -stretch false
	$res.tree column path -width 320
	ttk::scrollbar $res.vs -orient vertical -command [list $res.tree yview]
	$res.tree configure -yscrollcommand [list $res.vs set]
	pack $res.tree -side left -fill both -expand yes
	pack $res.vs -side right -fill y
	bind $res.tree <Double-Button-1> [namespace code OpenSelected]
	bind $res.tree <Return> [namespace code OpenSelected]

	set Priv(tree) $res.tree

	# --- buttons ------------------------------------------------------
	::widget::dialogButtons $dlg {{ok {} {}} {cancel {} {}}}
	$dlg.ok configure -text $mc::OpenSelected -command [namespace code OpenSelected]
	$dlg.cancel configure -text $mc::Close -command [namespace code Close]
	ttk::button $dlg.add -text $mc::AddSelected -command [namespace code AddSelected]
	::widget::dialogButtonsPack $dlg.add -side right

	set Priv(statusBase) ""
	_populate $Priv(results)

	foreach root [defaultRoots] {
		$left.list insert end $root
	}

	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $dlg
	return $dlg
}


proc ::application::database::discover::_roots {} {
	variable Priv

	set dlg $Priv(dialog)
	if {![winfo exists $dlg.top.roots.list]} { return {} }
	# The list itself is the set of search locations; the Remove button
	# deletes the selected entries (selection is not a filter).
	return [$dlg.top.roots.list get 0 end]
}


proc ::application::database::discover::AddRoot {} {
	variable Priv
	variable mc

	set dlg $Priv(dialog)
	set result [::dialog::chooseDir \
		-parent $dlg \
		-checkexistence yes \
		-geometry last \
	]
	if {![llength $result]} { return }
	set dir [lindex $result 0]
	set list $dlg.top.roots.list
	if {[lsearch -exact [$list get 0 end] $dir] < 0} {
		$list insert end $dir
		$list see end
	}
}


proc ::application::database::discover::RemoveRoot {} {
	variable Priv

	set dlg $Priv(dialog)
	set list $dlg.top.roots.list
	foreach idx [lreverse [$list curselection]] {
		$list delete $idx
	}
}


proc ::application::database::discover::StartScan {} {
	variable Priv
	variable mc

	if {$Priv(scanning)} {
		set Priv(status) $mc::ScanningBusy
		return
	}

	set roots [_roots]
	if {![llength $roots]} {
		set Priv(status) $mc::NoRoots
		return
	}

	$Priv(tree) delete [$Priv(tree) children {}]
	$Priv(progress) configure -value 0
	set Priv(status) [format $mc::Scanning 0 0]
	$Priv(dialog).top.options.actions.start configure \
		-text $mc::Stop -command [namespace code StopScan]

	start $roots $Priv(maxdepth) $Priv(includePgn) \
		[namespace code _progress] [namespace code _done]
}


proc ::application::database::discover::StopScan {} {
	variable Priv
	variable mc

	stop
	set Priv(statusBase) [format $mc::Stopped $Priv(dirs) [llength $Priv(results)]]
	_populate $Priv(results)
	$Priv(dialog).top.options.actions.start configure \
		-text $mc::Start -command [namespace code StartScan]
}


proc ::application::database::discover::Rescan {} {
	StartScan
}


proc ::application::database::discover::_progress {dirs found} {
	variable Priv
	variable mc

	if {![winfo exists $Priv(dialog)]} { return }
	set Priv(statusBase) [format $mc::Scanning $dirs $found]
	_populate $Priv(results)
	# The exact total is unknown; nudge the bar so it visibly moves.
	set value [expr {[$Priv(progress) cget -value] + 2}]
	if {$value > 95} { set value 95 }
	$Priv(progress) configure -value $value
}


proc ::application::database::discover::_done {results} {
	variable Priv
	variable mc

	if {![winfo exists $Priv(dialog)]} { return }
	$Priv(progress) configure -value 100
	set Priv(statusBase) [format $mc::Scanned $Priv(dirs) [llength $results]]
	_populate $results
	$Priv(dialog).top.options.actions.start configure \
		-text $mc::Start -command [namespace code StartScan]
}


# Literal, case-insensitive AND matching across the database's full path.
proc ::application::database::discover::filterResults {results text} {
	set words [regexp -all -inline {\S+} [string tolower $text]]
	set visible {}
	foreach entry $results {
		set path [string tolower [lindex $entry 2]]
		set matches 1
		foreach word $words {
			if {[string first $word $path] < 0} { set matches 0; break }
		}
		if {$matches} { lappend visible $entry }
	}
	return $visible
}

proc ::application::database::discover::_filterChanged {args} {
	variable Priv
	after cancel $Priv(filterAfter)
	set Priv(filterAfter) [after 150 [namespace code ApplyFilter]]
}

proc ::application::database::discover::ApplyFilter {} {
	variable Priv
	set Priv(filterAfter) {}
	if {[winfo exists $Priv(dialog)]} { _populate $Priv(results) }
}

proc ::application::database::discover::ClearFilter {entry} {
	variable Priv
	$entry delete 0 end
	set Priv(filter) ""
	after cancel $Priv(filterAfter)
	ApplyFilter
}

proc ::application::database::discover::_populate {results} {
	variable Priv
	variable mc

	set tree $Priv(tree)
	set visible [filterResults $results $Priv(filter)]
	set Priv(status) "$Priv(statusBase) [format $mc::FilterCount [llength $visible] [llength $results]]"
	set paths {}
	foreach entry $visible { lappend paths [lindex $entry 2] }
	foreach item [$tree children {}] {
		if {$item ni $paths} { $tree delete [list $item] }
	}
	foreach entry $visible {
		lassign $entry ext label path size games
		if {[$tree exists $path]} { continue }
		set icon {}
		catch { set icon [::dialog::fsbox::fileIcon .$ext] }
		set gameText [expr {$games >= 0 ? $games : "\u2013"}]
		set args [list -text $label -values \
			[list [file tail $path] $gameText [_size $size] [file dirname $path]]]
		if {[string length $icon]} { lappend args -image $icon }
		$tree insert {} end -id $path {*}$args
	}
	$tree children {} $paths
}


proc ::application::database::discover::_size {bytes} {
	if {$bytes < 1024} { return "${bytes} B" }
	if {$bytes < 1024 * 1024} { return "[format %.1f [expr {$bytes / 1024.0}]] KiB" }
	if {$bytes < 1024 * 1024 * 1024} {
		return "[format %.1f [expr {$bytes / (1024.0 * 1024)}]] MiB"
	}
	return "[format %.2f [expr {$bytes / (1024.0 * 1024 * 1024)}]] GiB"
}


# Recover the full path of a result row: the visible "Folder" column is
# the parent directory, the tree text is the type label and the name
# column is the file name.
proc ::application::database::discover::_pathOf {item} {
	variable Priv

	set values [$Priv(tree) item $item -values]
	if {[llength $values] < 4} { return {} }
	return [file join [lindex $values 3] [lindex $values 0]]
}


proc ::application::database::discover::_selection {} {
	variable Priv
	variable mc

	set tree $Priv(tree)
	set files {}
	foreach item [$tree selection] {
		set path [_pathOf $item]
		if {[string length $path]} { lappend files $path }
	}
	return $files
}


proc ::application::database::discover::OpenSelected {} {
	variable Priv
	variable mc

	set files [_selection]
	if {![llength $files]} {
		set Priv(status) $mc::SelectFirst
		return
	}
	set parent $Priv(parent)
	set first 1
	foreach file $files {
		# Only the first is switched to; the rest are loaded alongside.
		set switchTo [expr {$first ? 1 : 0}]
		::application::database::openBase $parent $file yes \
			-encoding $::encoding::autoEncoding -switchToBase $switchTo
		set first 0
	}
}


proc ::application::database::discover::AddSelected {} {
	variable Priv
	variable mc

	set files [_selection]
	if {![llength $files]} {
		set Priv(status) $mc::SelectFirst
		return
	}

	set switcher [::application::database::switcherWidget]
	set added 0
	set present 0
	foreach file $files {
		if {[string length $switcher] && [$switcher contains? $file]} {
			incr present
			continue
		}
		# Opening with -switchToBase 0 resolves the real database type
		# and registers the base without changing the current one.
		if {[::application::database::openBase $Priv(parent) $file no \
			-encoding $::encoding::autoEncoding -switchToBase 0]} {
			incr added
		}
	}

	set msg [format $mc::Added $added]
	if {$present} { append msg " " [format $mc::AlreadyAdded $present] }
	set Priv(status) $msg
}


proc ::application::database::discover::Close {} {
	variable Priv

	stop
	after cancel $Priv(filterAfter)
	set Priv(filterAfter) {}
	trace remove variable Priv(filter) write [namespace code _filterChanged]
	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}

# vi:set ts=3 sw=3:
