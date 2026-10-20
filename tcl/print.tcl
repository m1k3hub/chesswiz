# ======================================================================
# ::print -- Print and Print Preview for the current game
#
# Renders the current game as a formatted document with diagrams using
# the native PDF export path (::scidb::game::printPdf / PdfWriter) and
# hands the PDF to the platform's native print or preview mechanism:
#   - Linux:   preview opens the system viewer (xdg-open); print sends
#              to CUPS (lp / lpr) when available, falling back to the
#              system PDF viewer when no print spooler is installed.
#   - Windows: preview opens the default PDF viewer; print invokes the
#              ShellExecute "print" verb via Windows Script Host
#              (falling back to preview on failure).
#   - macOS:   both preview and print open the PDF in Preview (`open`),
#              which provides the native macOS print preview & dialog.
# ======================================================================

::util::source print

namespace eval ::print {
namespace eval mc {

set Print				"&Print..."
set PrintPreview		"Print Pre&view..."
set NoGameToPrint		"No game to print."
set PrintFailed		"Failed to print game: %s"
set CannotOpenViewer	"Cannot open PDF viewer for '%s'."

} ;# namespace mc

variable Counter 0

# Windows VBScript helper for ShellExecute "print" verb.
# tkchesswiz.exe is a GUI-subsystem binary, so wscript //nologo //B is
# used rather than console tools (see ::platform::sys::WinScript).
variable WinPrintVbs {Set sh = CreateObject("Shell.Application")
sh.ShellExecute WScript.Arguments(0), "", "", "print", 1
}

proc Noop {args} {}

# Resolve an executable on PATH. Separated so headless tests can stub it.
proc FindExecutable {name} {
	return [auto_execok $name]
}

# Execute an external command. Separated so headless tests can stub it.
proc RunCommand {cmdList {async 1}} {
	if {$async} {
		exec {*}$cmdList &
	} else {
		::util::execSafe {*}$cmdList
	}
	return 1
}

# Return the scratch directory used for temporary print PDFs.
proc TempDir {} {
	if {[info exists ::scidb::dir::temp] && $::scidb::dir::temp ne ""} {
		set dir [file join $::scidb::dir::temp print]
	} else {
		set base /tmp
		foreach var {TMPDIR TEMP TMP} {
			if {[info exists ::env($var)] && [file isdirectory $::env($var)]} {
				set base [file normalize $::env($var)]
				break
			}
		}
		set dir [file join $base chesswiz-[pid] print]
	}
	file mkdir $dir
	return $dir
}

# Sanitize a filename stem for safe temporary PDF creation.
proc SanitizeStem {text} {
	regsub -all {[^A-Za-z0-9._-]+} $text "_" clean
	set clean [string trim $clean "_."]
	if {$clean eq ""} {
		set clean "game"
	}
	return [string range $clean 0 60]
}

# Export the game at $position (or the current game when position == -1)
# to a formatted PDF file with embedded figurines and diagrams.
# Returns the normalized path to the generated PDF file.
proc exportPdf {{position -1} {pdfFile ""}} {
	variable Counter
	variable ::scidb::scratchbaseName

	if {$position < 0} {
		set position [::scidb::game::current]
	}
	if {$position < 0} {
		error $mc::NoGameToPrint
	}

	lassign [::scidb::game::sink? $position] base variant index
	set mainVariant [::util::toMainVariant $variant]
	if {$mainVariant eq "" || $mainVariant eq "Undetermined"} {
		set mainVariant Normal
	}

	set isModified [::scidb::game::query $position modified?]
	set useDirectDb [expr {
		$base ne ""
		&& $base ne $scratchbaseName
		&& !$isModified
		&& $index >= 0
		&& [::scidb::db::get open? $base $mainVariant]
	}]

	if {$pdfFile eq ""} {
		incr Counter
		set stem "game-${Counter}"
		if {$useDirectDb} {
			set w ""
			set b ""
			catch {
				set wInfo [::scidb::db::fetch whitePlayerInfo $index $base $mainVariant]
				set bInfo [::scidb::db::fetch blackPlayerInfo $index $base $mainVariant]
				set w [lindex [split [lindex $wInfo 0] ","] 0]
				set b [lindex [split [lindex $bInfo 0] ","] 0]
			}
			if {$w ne "" || $b ne ""} {
				set stem [SanitizeStem "${w}-${b}-${Counter}"]
			}
		}
		set pdfFile [file normalize [file join [TempDir] "${stem}.pdf"]]
	} else {
		set pdfFile [file normalize $pdfFile]
		file mkdir [file dirname $pdfFile]
	}

	if {$useDirectDb} {
		::scidb::game::printPdf $base $mainVariant $index $pdfFile 63
	} else {
		# Game is in Scratchbase or has unsaved in-memory edits:
		# export the active game slot to a temporary PGN, open it as a
		# transient database, print to PDF via PdfWriter, and close it.
		set tmpPgn [file normalize [file join [TempDir] "tmp-[pid]-[clock microseconds]-${Counter}.pgn"]]
		set pgnFlags [expr {[llength [info procs ::export::getPgnFlags]] ? [::export::getPgnFlags] : 63}]
		set languages [::scidb::game::query langSet $position]
		try {
			::scidb::game::export $tmpPgn \
				-position $position \
				-flags $pgnFlags \
				-mode create \
				-encoding utf-8 \
				-languages $languages \
				;
			::scidb::db::open $tmpPgn [namespace current]::Noop {} [namespace current]::Noop {}
			try {
				set dbVariants [::scidb::db::get variants $tmpPgn]
				set exportVar [expr {$mainVariant in $dbVariants ? $mainVariant : [lindex $dbVariants 0]}]
				if {$exportVar eq ""} { set exportVar Normal }
				::scidb::game::printPdf $tmpPgn $exportVar 0 $pdfFile 63
			} finally {
				catch { ::scidb::db::close $tmpPgn }
			}
		} finally {
			catch { file delete -force $tmpPgn }
		}
	}

	return $pdfFile
}

# Launch the platform PDF viewer for print preview.
proc OpenViewer {pdfFile} {
	if {$::tcl_platform(platform) eq "windows"} {
		set start [FindExecutable start]
		if {$start eq {}} {
			if {[info exists ::env(COMSPEC)]} {
				set start [list $::env(COMSPEC) /c start]
			} else {
				set start [list cmd.exe /c start]
			}
		}
		RunCommand [list {*}$start "" [file nativename $pdfFile]] 1
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		set openCmd [FindExecutable open]
		if {$openCmd eq {}} { set openCmd [list open] }
		RunCommand [list {*}$openCmd $pdfFile] 1
	} else {
		set xdg [FindExecutable xdg-open]
		if {$xdg eq {}} { set xdg [list xdg-open] }
		RunCommand [list {*}$xdg $pdfFile] 1
	}
}

# Print Preview: generate PDF for the current game and open in the
# platform's native viewer (Preview on macOS, default PDF viewer on
# Windows, xdg-open on Linux). Returns the generated PDF path.
proc preview {{parent .application} {position -1}} {
	if {[catch { exportPdf $position } pdfFile opts]} {
		if {[llength [info commands ::dialog::error]] && [winfo exists $parent]} {
			::dialog::error -parent $parent -message [format $mc::PrintFailed $pdfFile]
		} else {
			return -options $opts $pdfFile
		}
		return ""
	}
	if {[catch { OpenViewer $pdfFile } err opts]} {
		if {[llength [info commands ::dialog::error]] && [winfo exists $parent]} {
			::dialog::error -parent $parent -message [format $mc::CannotOpenViewer $pdfFile] -detail $err
		} else {
			return -options $opts $err
		}
		return ""
	}
	return $pdfFile
}

# Print current game:
#   - Windows: ShellExecute "print" verb via wscript (falls back to viewer)
#   - macOS:   open PDF in Preview (which provides the native print dialog)
#   - Linux:   send PDF to lp (or lpr) if available; otherwise open in
#              system PDF viewer via xdg-open so the user can print from it.
# Returns the generated PDF path.
proc game {{parent .application} {position -1}} {
	variable WinPrintVbs

	if {[catch { exportPdf $position } pdfFile opts]} {
		if {[llength [info commands ::dialog::error]] && [winfo exists $parent]} {
			::dialog::error -parent $parent -message [format $mc::PrintFailed $pdfFile]
		} else {
			return -options $opts $pdfFile
		}
		return ""
	}

	if {$::tcl_platform(platform) eq "windows"} {
		set vbs [::platform::sys::WinScript print $WinPrintVbs]
		set cmd [list wscript //nologo //B [file nativename $vbs] [file nativename $pdfFile]]
		if {[catch { RunCommand $cmd 1 }]} {
			OpenViewer $pdfFile
		}
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		OpenViewer $pdfFile
	} else {
		set lp [FindExecutable lp]
		if {$lp ne {}} {
			RunCommand [list {*}$lp $pdfFile] 0
		} else {
			set lpr [FindExecutable lpr]
			if {$lpr ne {}} {
				RunCommand [list {*}$lpr $pdfFile] 0
			} else {
				OpenViewer $pdfFile
			}
		}
	}

	return $pdfFile
}

} ;# namespace ::print

# vi:set ts=3 sw=3:
