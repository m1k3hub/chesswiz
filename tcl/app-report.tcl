# ======================================================================
# ::application::report — ChessBase guiding-text report viewer (HTML)
# ======================================================================
# Displays the guiding-text body of a record as sanitized HTML (the
# scidb HTML profile; see src/html/). The ChessBase constructs are
# already rewritten by ::scidb::db::guidingText before this layer sees
# them:
#
#   CBLink(tag_game,...)    -> <a href="scidb-game:…">  → jump to game
#   CBLink(tag_stream/…,F)  -> <a href="scidb-media:F"> → media player
#   <IMG src="DB.html\f">   -> resolved absolute paths (or flagged)
#
# Rendering uses the vendored Tkhtml 3.1 widget (tcl/widgets/html.tcl).
# Unresolved media references are reported in the status bar — never
# silently dropped (every reference is classified by the sanitizer).
#
# Entry point: ::application::report::show <db> <variant> <gameIndex>.
# ======================================================================

::util::source application-report

package require Tk 8.5

namespace eval application {
namespace eval report {
namespace eval mc {

set Title				"Report"
set Close				"Close"
set NotGuidingText	"The current game is not a report entry."
set HtmlDocument	"HTML Document"
set CannotRead		"Cannot read file: %s"
set Unresolved		"%d media reference(s) unresolved"
set NoMediaFile		"Cannot open media file: %s"
set JumpFailed		"No game matches this report link."
set ExternalHint	"External link opened in browser"
set IgnoredLink	"link ignored: %s"
set OpeningLinked	"Opening linked database: %s"
set LinkedMissing	"Linked database not found: %s"

} ;# namespace mc

array set Priv {
	window		{}
	html			{}
	status		{}
	db			{}
	variant		{}
	index		-1
}

} ;# namespace report
} ;# namespace application


# ----------------------------------------------------------------------
# Entry point: open an arbitrary HTML file as a document (File > Open >
# HTML documents). The file is sanitized through the scidb HTML profile;
# relative references resolve against the file's directory (the semantics
# of a saved web page and its asset folder).
# ======================================================================
proc application::report::showFile {parent file} {
	variable Priv

	if {![file readable $file]} {
		::dialog::info -parent [winfo toplevel $parent] \
			-message [format $mc::CannotRead $file]
		return {}
	}

	set fh [open $file rb]
	fconfigure $fh -encoding binary
	set raw [read $fh]
	close $fh

	set data [::scidb::html::sanitize $raw [file dirname $file]]

	set w [showHtmlData $parent [file tail $file] $data]
	return $w
}


# ----------------------------------------------------------------------
# Shared window builder: displays a sanitized HTML payload.
# ======================================================================
proc application::report::showHtmlData {parent title data} {
	variable Priv
	variable mc

	set w .report

	# file-backed documents have no owning game: drop the game actions
	set Priv(db) {}
	set Priv(variant) {}
	set Priv(index) -1
	set Priv(title) $title
	set Priv(data) $data

	if {[winfo exists $w]} {
		wm title $w "$mc::Title ($title)"
		Load $data
		raise $w
		return $w
	}

	tk::toplevel $w -class Scidb
	wm title $w "$mc::Title ($title)"
	wm transient $w [winfo toplevel $parent]
	wm protocol $w WM_DELETE_WINDOW [namespace code Close]

	# --- the HTML view ------------------------------------------------
	set sw [ttk::frame $w.sw]

	if {[catch {
		html $sw.html -width 700 -height 600 -imagecmd [namespace code Image]
	} err]} {
		tk_messageBox -parent $w -type ok -icon warning \
			-title $mc::Title -message "Tkhtml widget unavailable: $err"
		destroy $w
		return {}
	}

	set inner $sw.html.sub.html

	ttk::scrollbar $sw.sb -command [list $inner yview]
	$inner configure -yscrollcommand [list $sw.sb set]
	pack $sw.sb -side right -fill y
	pack $sw.html -side left -fill both -expand yes
	pack $sw -fill both -expand yes

	# --- status bar ---------------------------------------------------
	set status [ttk::label $w.status -anchor w -relief sunken -borderwidth 1]
	pack $status -side bottom -fill x

	# --- close button -------------------------------------------------
	set btns [ttk::frame $w.btns]
	ttk::button $btns.close -text $mc::Close -command [namespace code Close]
	pack $btns.close -side right -padx 6 -pady 6
	pack $btns -side bottom -fill x

	wm minsize $w 500 400
	::util::place $w -parent $parent -position center

	$inner handler node a [namespace code [list LinkSetup $inner]]
	bind $inner <ButtonRelease-1> [namespace code [list LinkClick $inner %x %y]]

	set Priv(window) $w
	set Priv(html) $sw.html
	set Priv(status) $status

	wm deiconify $w
	update idletasks

	Load $data

	return $w
}


# ----------------------------------------------------------------------
# Entry point: show the guiding-text report of <gameIndex>.
# Returns the window path, or {} when the record is not a report.
# ======================================================================
proc application::report::show {db variant gameIndex {parent .application}} {
	variable Priv
	variable mc

	set data [::scidb::db::guidingText $db $variant $gameIndex]

	if {![dict get $data isGuiding]} {
		::dialog::info -parent [winfo toplevel $parent] \
			-message $mc::NotGuidingText
		return {}
	}

	set w [showHtmlData $parent [file tail $db] $data]

	if {[winfo exists $w]} {
		set Priv(db) $db
		set Priv(variant) $variant
		set Priv(index) $gameIndex
	}

	return $w
}


proc application::report::Close {} {
	variable Priv

	if {![winfo exists $Priv(window)]} { return }

	catch { $Priv(html) clear }
	destroy $Priv(window)
	set Priv(window) {}
	set Priv(html) {}
}


# ----------------------------------------------------------------------
# Load the sanitized report into the widget.
# ======================================================================
proc application::report::Load {data} {
	variable Priv

	if {![winfo exists $Priv(window)]} { return }

	set html [dict get $data html]

	# subcommands go through the per-widget command created by the
	# wrapper (::html <path> would try to CREATE the widget again)
	if {[catch { $Priv(html) parse $html } err]} {
		# never leave the window empty: fall back to plain text
		destroy $Priv(html)
		set txt [tk::text $Priv(window).sw.fallback -wrap word]
		$txt insert end $html
		pack $txt -fill both -expand yes
		$Priv(status) configure -text "parse failed: $err" -foreground darkred
		return
	}

	set note [format "%d media reference(s), %d game anchor(s)" \
		[llength [dict get $data media]] [llength [dict get $data anchors]]]

	if {[dict get $data unresolved] > 0} {
		append note " — [format $mc::Unresolved [dict get $data unresolved]]"
		$Priv(status) configure -text $note -foreground darkred
	} else {
		$Priv(status) configure -text $note -foreground {}
	}
}


# ----------------------------------------------------------------------
# Image loading for Tkhtml (-imagecmd): resolve to a Tk photo, or {}
# (Tkhtml then shows its broken-image placeholder). Unresolved refs are
# relative paths here — they never exist, by construction.
# ======================================================================
proc application::report::Image {file} {
	if {![file exists $file] || [file isdirectory $file]} { return {} }

	if {[catch { set img [image create photo -file $file] }]} { return {} }

	return [list $img [namespace code DeleteImage]]
}


proc application::report::DeleteImage {img} {
	catch { image delete $img }
}


# ----------------------------------------------------------------------
# Link handling. Tkhtml node handlers fire at parse time (not on
# click); the actual dispatch happens in LinkClick via [inner href x y].
# ======================================================================
proc application::report::LinkSetup {w node} {
	# parse-time hook: Tkhtml calls this per <a> node with the widget
	# prepended; dispatch is click-driven (LinkClick), nothing to do here
	return
}


proc application::report::LinkClick {w x y} {
	variable Priv
	variable mc

	set href {}
	catch { set href [$w href $x $y] }

	if {![string length $href]} { return }

	if {[string match scidb-game:* $href]} {
		set fields [split [string range $href 11 end] ,]
		set index -1
		catch { set index [::scidb::db::gameAnchor $Priv(db) $Priv(variant) $fields] }

		if {![string is integer -strict $index] || $index < 0} {
			$Priv(status) configure -text $mc::JumpFailed
			return
		}

		::game::new .application -base $Priv(db) -variant $Priv(variant) -number $index
		return
	}

	if {[string match scidb-media:* $href]} {
		set path [string range $href 12 end]

		if {[file exists $path]} {
			::application::media::PlayMedia $path
		} else {
			$Priv(status) configure -text [format $mc::NoMediaFile $path]
		}
		return
	}

	if {   [string match http://* $href] || [string match https://* $href]
		|| [string match file://* $href]} {
		catch { ::application::media::LaunchExternal $href }
		$Priv(status) configure -text $mc::ExternalHint
		return
	}

	if {[string match scidb-open:* $href]} {
		# cross-database link: the payload names another database of the
		# same release, relative to the report database's directory
		set target [string range $href 11 end]

		if {![string length $Priv(db)]} {
			# file-backed document: no owning release directory
			$Priv(status) configure -text [format $mc::IgnoredLink $href]
			return
		}

		set dir [file dirname $Priv(db)]
		set candidates [list [file join $dir $target]]
		set ext [file extension $target]

		if {![string length $ext]} {
			lappend candidates "$dir/$target.cbh" "$dir/$target.sci"
		} elseif {[string equal -nocase $ext ".cbh"]} {
			lappend candidates "$dir/[file rootname $target].cbg"
		}

		set found {}
		foreach cand $candidates {
			if {[file exists $cand]} { set found $cand; break }
		}

		if {![string length $found]} {
			$Priv(status) configure -text [format $mc::LinkedMissing $target]
			return
		}

		$Priv(status) configure -text [format $mc::OpeningLinked [file tail $found]]
		catch { ::application::database::openBase .application $found yes }
		return
	}

	# anything else: report, never follow silently
	$Priv(status) configure -text [format $mc::IgnoredLink $href]
}

# vi:set ts=3 sw=3:
