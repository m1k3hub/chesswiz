# ======================================================================
# Scidb App Test — Print & Print Preview (tcl/print.tcl)
# ======================================================================
# Verifies Gap G14 resolution:
#   - ::print::game and ::print::preview exist
#   - Exporting the current game produces a valid, non-empty PDF
#   - Decompressed PDF text streams contain both players' names
#   - ::print::preview invokes xdg-open on Linux with the PDF path
#   - ::print::game invokes lp on Linux when available, and falls back
#     to xdg-open when lp/lpr are absent
#   - Modified/scratch games also render full player names and moves
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::appprint {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-app print-test-[pid]]
variable capturedCalls {}
variable fakeLpPath ""
variable origRunCommand ""
variable origFindExecutable ""

proc setup {} {
	variable tmpDir
	file mkdir $tmpDir
}

proc tempPath {stem ext} {
	variable tmpDir
	return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

proc makePgn {white black} {
	set path [tempPath print-game pgn]
	set fh [open $path w]
	fconfigure $fh -encoding utf-8
	puts $fh {[Event "New York International"]}
	puts $fh {[Site "New York"]}
	puts $fh {[Date "1924.03.23"]}
	puts $fh {[Round "6"]}
	puts $fh "\[White \"$white\"\]"
	puts $fh "\[Black \"$black\"\]"
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. d4 e6 2. Nf3 f5 3. c4 Nf6 4. Bg5 Be7 5. Nc3 O-O 6. e3 b6 7. Bd3 Bb7 8. O-O Qe8 1-0}
	close $fh
	return $path
}

proc log {args} {}
proc progress {args} {}

proc readPdf {path} {
	set fh [open $path r]
	fconfigure $fh -translation binary
	set data [read $fh]
	close $fh
	return $data
}

proc pdfHeader {path} {
	string range [readPdf $path] 0 7
}

proc streamText {path} {
	set data [readPdf $path]
	set out {}
	set pos 0
	while {[set s [string first "stream" $data $pos]] >= 0} {
		if {$s >= 3 && [string range $data [expr {$s - 3}] [expr {$s - 1}]] eq "end"} {
			set pos [expr {$s + 6}]
			continue
		}
		set b [expr {$s + 6}]
		if {[string index $data $b] eq "\r"} { incr b }
		if {[string index $data $b] eq "\n"} { incr b }
		set e [string first "endstream" $data $b]
		if {$e < 0} { break }
		catch { append out [zlib decompress [string range $data $b [expr {$e - 1}]]] }
		set pos [expr {$e + 9}]
	}
	return $out
}

proc installStubs {{lpPath "/usr/bin/lp"}} {
	variable capturedCalls {}
	variable fakeLpPath $lpPath
	variable origRunCommand
	variable origFindExecutable

	if {[llength [info procs ::print::RunCommand]] && $origRunCommand eq ""} {
		set origRunCommand [list [info args ::print::RunCommand] [info body ::print::RunCommand]]
	}
	if {[llength [info procs ::print::FindExecutable]] && $origFindExecutable eq ""} {
		set origFindExecutable [list [info args ::print::FindExecutable] [info body ::print::FindExecutable]]
	}

	proc ::print::RunCommand {cmdList {async 1}} {
		lappend ::scidb::test::appprint::capturedCalls [list $cmdList $async]
		return 1
	}

	proc ::print::FindExecutable {name} {
		if {$name eq "lp"} {
			return $::scidb::test::appprint::fakeLpPath
		}
		if {$name eq "lpr"} {
			return ""
		}
		if {$name eq "xdg-open"} {
			return "/usr/bin/xdg-open"
		}
		return [auto_execok $name]
	}
}

proc restoreStubs {} {
	variable origRunCommand
	variable origFindExecutable
	if {$origRunCommand ne ""} {
		lassign $origRunCommand argList body
		proc ::print::RunCommand $argList $body
		set origRunCommand ""
	}
	if {$origFindExecutable ne ""} {
		lassign $origFindExecutable argList body
		proc ::print::FindExecutable $argList $body
		set origFindExecutable ""
	}
}

setup

# Let the application's deferred startup timers settle and cancel any
# lingering background timers before running tests, so checkCleanup sees
# a clean after-queue.
update
foreach _id [after info] { catch { after cancel $_id } }

tcltest::test print-procs-exist {::print::game and ::print::preview exist} -body {
	list \
		[expr {[llength [info procs ::print::game]] == 1}] \
		[expr {[llength [info procs ::print::preview]] == 1}]
} -result {1 1}

tcltest::test print-preview-database-game {::print::preview generates PDF with players' names and invokes xdg-open} -setup {
	set pgn [makePgn "Capablanca, Jose Raul" "Tartakower, Saviely"]
	::scidb::db::open $pgn ::scidb::test::appprint::log log ::scidb::test::appprint::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $pgn Normal 0
	installStubs "/usr/bin/lp"
} -body {
	set pdf [::print::preview .application $pos]
	set exists [file isfile $pdf]
	set nonEmpty [expr {$exists && [file size $pdf] > 0}]
	set hdr [expr {$exists ? [pdfHeader $pdf] : ""}]
	set text [expr {$exists ? [streamText $pdf] : ""}]
	regsub -all {\s+} $text " " text
	set hasWhite [string match "*Capablanca, Jose Raul*" $text]
	set hasBlack [string match "*Tartakower, Saviely*" $text]
	lassign [lindex $::scidb::test::appprint::capturedCalls 0] cmdList async
	set cmdHead [file tail [lindex $cmdList 0]]
	set cmdArg [lindex $cmdList 1]
	list \
		$exists \
		$nonEmpty \
		[string match "%PDF-1.*" $hdr] \
		$hasWhite \
		$hasBlack \
		[llength $::scidb::test::appprint::capturedCalls] \
		$cmdHead \
		[expr {$cmdArg eq $pdf}]
} -cleanup {
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
	catch { ::scidb::db::close $pgn }
} -result {1 1 1 1 1 1 xdg-open 1}

tcltest::test print-game-linux-lp {::print::game invokes lp on Linux when lp is available and PDF has players' names} -setup {
	set pgn [makePgn "Morphy, Paul" "Anderssen, Adolf"]
	::scidb::db::open $pgn ::scidb::test::appprint::log log ::scidb::test::appprint::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $pgn Normal 0
	installStubs "/usr/bin/lp"
} -body {
	set pdf [::print::game .application $pos]
	set exists [file isfile $pdf]
	set nonEmpty [expr {$exists && [file size $pdf] > 0}]
	set text [expr {$exists ? [streamText $pdf] : ""}]
	regsub -all {\s+} $text " " text
	set hasWhite [string match "*Morphy, Paul*" $text]
	set hasBlack [string match "*Anderssen, Adolf*" $text]
	lassign [lindex $::scidb::test::appprint::capturedCalls 0] cmdList async
	set cmdHead [file tail [lindex $cmdList 0]]
	set cmdArg [lindex $cmdList end]
	list \
		$exists \
		$nonEmpty \
		$hasWhite \
		$hasBlack \
		[llength $::scidb::test::appprint::capturedCalls] \
		$cmdHead \
		[expr {$cmdArg eq $pdf}]
} -cleanup {
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
	catch { ::scidb::db::close $pgn }
} -result {1 1 1 1 1 lp 1}

tcltest::test print-game-linux-fallback-viewer {::print::game falls back to xdg-open when lp/lpr are unavailable} -setup {
	set pgn [makePgn "Kasparov, Garry" "Karpov, Anatoly"]
	::scidb::db::open $pgn ::scidb::test::appprint::log log ::scidb::test::appprint::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $pgn Normal 0
	installStubs ""
} -body {
	set pdf [::print::game .application $pos]
	set text [streamText $pdf]
	regsub -all {\s+} $text " " text
	lassign [lindex $::scidb::test::appprint::capturedCalls 0] cmdList async
	set cmdHead [file tail [lindex $cmdList 0]]
	set cmdArg [lindex $cmdList 1]
	list \
		[expr {[file size $pdf] > 0}] \
		[string match "*Kasparov, Garry*" $text] \
		[string match "*Karpov, Anatoly*" $text] \
		$cmdHead \
		[expr {$cmdArg eq $pdf}]
} -cleanup {
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
	catch { ::scidb::db::close $pgn }
} -result {1 1 1 xdg-open 1}

tcltest::test print-modified-scratch-game {::print::game exports unsaved/modified game tags and players to PDF} -setup {
	set pos [::scidb::game::current]
	if {![::scidb::game::query $pos open?]} {
		::scidb::game::new $pos
	}
	set pgnText "\[Event \"Scratch Match\"\]\n\[Site \"Local\"\]\n\[Date \"2026.10.20\"\]\n\[Round \"1\"\]\n\[White \"Fischer, Robert James\"\]\n\[Black \"Spassky, Boris V\"\]\n\[Result \"1/2-1/2\"\]\n\n1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 1/2-1/2\n"
	::scidb::game::import $pos $pgnText ::scidb::test::appprint::log log -encoding utf-8
	installStubs "/usr/bin/lp"
} -body {
	set pdf [::print::game .application $pos]
	set text [streamText $pdf]
	regsub -all {\s+} $text " " text
	list \
		[expr {[file size $pdf] > 0}] \
		[string match "*Fischer, Robert James*" $text] \
		[string match "*Spassky, Boris V*" $text]
} -cleanup {
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
} -result {1 1 1}

tcltest::test print-macos-branch {::print::game and ::print::preview use open on macOS} -setup {
	set savedOs $::tcl_platform(os)
	set savedPlatform $::tcl_platform(platform)
	set ::tcl_platform(os) "Darwin"
	set ::tcl_platform(platform) "unix"
	set pgn [makePgn "Alekhine, Alexander" "Euwe, Max"]
	::scidb::db::open $pgn ::scidb::test::appprint::log log ::scidb::test::appprint::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $pgn Normal 0
	installStubs ""
} -body {
	set pdf1 [::print::preview .application $pos]
	set pdf2 [::print::game .application $pos]
	lassign [lindex $::scidb::test::appprint::capturedCalls 0] cmd1 async1
	lassign [lindex $::scidb::test::appprint::capturedCalls 1] cmd2 async2
	list \
		[expr {[file size $pdf1] > 0}] \
		[expr {[file size $pdf2] > 0}] \
		[file tail [lindex $cmd1 0]] \
		[expr {[lindex $cmd1 1] eq $pdf1}] \
		[file tail [lindex $cmd2 0]] \
		[expr {[lindex $cmd2 1] eq $pdf2}]
} -cleanup {
	set ::tcl_platform(os) $savedOs
	set ::tcl_platform(platform) $savedPlatform
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
	catch { ::scidb::db::close $pgn }
} -result {1 1 open 1 open 1}

tcltest::test print-windows-branch {::print::game uses wscript ShellExecute print verb and ::print::preview opens viewer on Windows} -setup {
	set savedOs $::tcl_platform(os)
	set savedPlatform $::tcl_platform(platform)
	set hasTemp [info exists ::env(TEMP)]
	if {$hasTemp} { set savedTemp $::env(TEMP) }
	set ::env(TEMP) $::scidb::test::appprint::tmpDir
	set ::tcl_platform(os) "Windows NT"
	set ::tcl_platform(platform) "windows"
	set pgn [makePgn "Lasker, Emanuel" "Steinitz, Wilhelm"]
	::scidb::db::open $pgn ::scidb::test::appprint::log log ::scidb::test::appprint::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $pgn Normal 0
	installStubs ""
} -body {
	set pdf1 [::print::preview .application $pos]
	set pdf2 [::print::game .application $pos]
	lassign [lindex $::scidb::test::appprint::capturedCalls 0] cmd1 async1
	lassign [lindex $::scidb::test::appprint::capturedCalls 1] cmd2 async2
	list \
		[expr {[file size $pdf1] > 0}] \
		[expr {[file size $pdf2] > 0}] \
		[lindex $cmd2 0] \
		[string match "*chesswiz-print.vbs" [lindex $cmd2 3]] \
		[expr {[lindex $cmd2 4] eq [file nativename $pdf2]}]
} -cleanup {
	if {$hasTemp} {
		set ::env(TEMP) $savedTemp
	} else {
		unset -nocomplain ::env(TEMP)
	}
	unset -nocomplain ::platform::sys::WinScripts(print)
	set ::tcl_platform(os) $savedOs
	set ::tcl_platform(platform) $savedPlatform
	restoreStubs
	catch { ::scidb::game::release $pos }
	catch { ::scidb::game::new $pos }
	catch { ::scidb::db::close $pgn }
} -result {1 1 wscript 1 1}

foreach _id [after info] { catch { after cancel $_id } }

catch { file delete -force $tmpDir }

} ;# namespace ::scidb::test::appprint

::tcltest::cleanupTests
