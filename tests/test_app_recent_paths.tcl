# ======================================================================
# Scidb App Test - recently used databases, and a read-only Maintenance
# ======================================================================
# G13 (REPORT.md:668): clicking a Recently used entry removed it and
# opened nothing, with nothing logged. The row id in the page is an index
# into the list as it was when the page was drawn, but it was used to
# index the list as it is now (one entry opened or removed while the page
# stays visible and the click opens, or removes, another database). The
# recent list also compared paths as strings, so a spelling difference -
# drive letter case on Windows, separators, "x/../x", a link, an options
# file written by an older build - left the entry unmatched: Remove did
# nothing and opening the file again stored a second entry for it. And an
# entry was dropped from the history whenever the file could not be read,
# though the file was still there (locked, or no permission).
#
# G23 (REPORT.md:662,670): a .pgn opens read-only and the Maintenance
# cascade was simply disabled; a disabled cascade cannot be opened and Tk
# shows no tooltip on a disabled entry, so nothing said why, nor what to
# do about it.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::recentpaths {
	variable dir [file join $::scidb::test::app::testDir tmp-app recent-paths]
	variable pgn [file join $dir "Spiel \u00dcbung & Pfad.pgn"]
	variable savedRecent {}
	variable savedCi {}

	proc makePgn {file} {
		file mkdir [file dirname $file]
		set fh [open $file w]
		fconfigure $fh -encoding utf-8
		puts $fh "\[Event \"RecentPaths\"\]\n\[Site \"Here\"\]\n\[Date \"2020.01.01\"\]"
		puts $fh "\[Round \"1\"\]\n\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"1-0\"\]"
		puts $fh "\n1. e4 e5 2. Nf3 Nc6 1-0\n"
		close $fh
	}

	# an html node stub for information::Mouse1Up: "<node> attribute -default {} id".
	# The node is used as a single command word, so the id lives in a variable.
	variable nodeId 0

	proc node {id} {
		variable nodeId
		set nodeId $id
		return ::scidb::test::recentpaths::NodeCmd
	}

	proc NodeCmd {args} {
		variable nodeId
		if {[lindex $args end] eq "id"} { return $nodeId }
		return {}
	}

	proc saveRecent {} {
		variable savedRecent
		set savedRecent $::application::database::RecentFiles
		set ::application::database::RecentFiles {}
		set ::application::information::Priv(recent) {}
	}

	proc restoreRecent {} {
		variable savedRecent
		set ::application::database::RecentFiles $savedRecent
		set ::application::information::Priv(recent) {}
	}

	proc addRecent {file} {
		set ::application::database::RecentFiles \
			[linsert $::application::database::RecentFiles 0 [list PGNFile $file utf-8 1]]
	}

	# what the Information page drew: its row ids index this list
	proc buildPage {} {
		set ::application::information::Priv(recent) [::application::database::recentFiles]
	}

	proc recentIndex {file} {
		return [::application::database::FindRecentFile $file]
	}

	proc countRecent {file} {
		set n 0
		foreach entry $::application::database::RecentFiles {
			if {[::platform::sys::sameFile [lindex $entry 1] $file]} { incr n }
		}
		return $n
	}

	proc stubDialog {} {
		variable messages
		set messages {}
		if {[info commands ::dialog::error] ne ""} {
			rename ::dialog::error ::scidb::test::recentpaths::_dialogError
		}
		proc ::dialog::error {args} {
			lappend ::scidb::test::recentpaths::messages $args
			return ok
		}
	}

	proc unstubDialog {} {
		catch { rename ::dialog::error {} }
		if {[info commands ::scidb::test::recentpaths::_dialogError] ne ""} {
			rename ::scidb::test::recentpaths::_dialogError ::dialog::error
		}
	}

	proc dialogText {} {
		variable messages
		set text {}
		foreach call $messages {
			if {[dict exists $call -message]} { append text [dict get $call -message] " " }
		}
		return $text
	}

	proc logText {} {
		set text ""
		catch { set text [$::log::Log.top.text get 1.0 end] }
		return $text
	}

	proc unreadable {file} {
		file attributes $file -permissions 0000
		return [expr {![file readable $file]}]
	}

	proc readableAgain {file} {
		catch { file attributes $file -permissions 0644 }
	}

	proc closeBase {file} {
		catch { ::application::database::closeBase .application $file }
		update idletasks
	}

	# force the Windows/macOS path comparison without being there
	proc forceCaseInsensitive {on} {
		variable savedCi
		if {$on} {
			rename ::platform::sys::caseInsensitivePaths? ::scidb::test::recentpaths::_ci
			proc ::platform::sys::caseInsensitivePaths? {} { return 1 }
		} elseif {[info commands ::scidb::test::recentpaths::_ci] ne ""} {
			rename ::platform::sys::caseInsensitivePaths? {}
			rename ::scidb::test::recentpaths::_ci ::platform::sys::caseInsensitivePaths?
		}
	}

	proc switcher {} { return $::application::database::Vars(switcher) }

	proc popup {base} {
		set switcher [switcher]
		set ::application::database::Vars(ignore-next) 0
		catch { destroy $switcher.__menu__ }
		::application::database::PopupMenu $switcher 0 0 $base
		return $switcher.__menu__
	}

	proc unpopup {} {
		set switcher [switcher]
		catch { $switcher.__menu__ unpost }
		catch { destroy $switcher.__menu__ }
		set ::application::database::Vars(ignore-next) 0
	}

	# index of the Maintenance cascade in the posted database menu
	proc maintenanceIndex {menu} {
		set label [::mc::stripAmpersand $::application::database::mc::FileMaintenance]
		foreach i [range $menu] {
			if {[$menu type $i] ne "cascade"} { continue }
			if {[string first $label [$menu entrycget $i -label]] >= 0} { return $i }
		}
		return -1
	}

	proc range {menu} {
		set last [$menu index end]
		if {![string is integer -strict $last]} { return {} }
		set result {}
		for {set i 0} {$i <= $last} {incr i} { lappend result $i }
		return $result
	}

	proc maintenanceHint {base} {
		set menu [popup $base]
		set i [maintenanceIndex $menu]
		if {$i < 0} { return [list missing - {}] }
		set cascadeState [$menu entrycget $i -state]
		set sub [$menu entrycget $i -menu]
		if {![winfo exists $sub]} { return [list $cascadeState empty {}] }
		if {[$sub index end] eq "none"} { return [list $cascadeState 0 {}] }
		return [list $cascadeState [$sub type 0] [$sub entrycget 0 -label] [$sub entrycget 0 -state]]
	}
}

# --- the path comparison the recent list needs ---------------------------

# Windows ignores the permission bits, so a file there cannot be made
# unreadable; the locked-file test only means something where it can.
proc ::scidb::test::recentpaths::lockSupported {} {
	set probe [file join $::scidb::test::recentpaths::dir lock-probe.pgn]
	::scidb::test::recentpaths::makePgn $probe
	set ok 0
	if {![catch { file attributes $probe -permissions 0000 }]} {
		set ok [expr {![file readable $probe]}]
	}
	catch { file attributes $probe -permissions 0644 }
	catch { file delete $probe }
	return $ok
}

tcltest::testConstraint unreadableFiles [::scidb::test::recentpaths::lockSupported]
# a native popup menu (Windows, macOS) runs its own modal loop until dismissed
tcltest::testConstraint x11 [expr {[tk windowingsystem] eq "x11"}]

tcltest::test recentpaths-same-file {one file written down in different ways is one entry} -setup {
	set d $::scidb::test::recentpaths::dir
	file mkdir $d
	set a [file join $d "Spiel \u00dcbung.pgn"]
	set b [file join $d other.pgn]
	::scidb::test::recentpaths::makePgn $a
	::scidb::test::recentpaths::makePgn $b
	set home $::scidb::dir::home
	set probe [file join $home recent-paths-probe.pgn]
	::scidb::test::recentpaths::makePgn $probe
	set link [file join $d link.pgn]
	set hard [file join $d hard.pgn]
	catch { file delete $link $hard }
	set symlinked [expr {![catch { file link -symbolic $link $a }]}]
	set hardlinked [expr {![catch { file link -hard $hard $a }]}]
	set tilde "~/recent-paths-probe.pgn"
	set tildeResolves [expr {[file normalize $tilde] eq $probe}]
} -body {
	# links are not available everywhere (a Windows build without the
	# privilege to make them, an old Tcl): an unsupported form asserts nothing
	list \
		[::platform::sys::sameFile $a $a] \
		[::platform::sys::sameFile [file join $d . "Spiel \u00dcbung.pgn"] $a] \
		[::platform::sys::sameFile [file join $d .. recent-paths "Spiel \u00dcbung.pgn"] $a] \
		[expr {!$symlinked || [::platform::sys::sameFile $link $a]}] \
		[expr {!$hardlinked || [::platform::sys::sameFile $hard $a]}] \
		[::platform::sys::sameFile $a $b] \
		[expr {!$tildeResolves || [::platform::sys::sameFile $tilde $probe]}] \
		[::platform::sys::sameFile "" $a]
} -cleanup {
	file delete $link $hard
	file delete $probe
} -result {1 1 1 1 1 0 1 0}

tcltest::test recentpaths-windows-case {Windows: the drive letter's case is not part of the file name} -setup {
	set d $::scidb::test::recentpaths::dir
	file mkdir $d
	set a [file join $d lower.pgn]
	set upper [file join $d "Lower.PGN"]
	set second [file join $d "CASE.pgn"]
	set third [file join $d "case.pgn"]
	catch { file delete $a $second $third }
	::scidb::test::recentpaths::makePgn $a
	::scidb::test::recentpaths::makePgn $second
	::scidb::test::recentpaths::makePgn $third
	# different sizes, so "one file or two" can be read off the disk
	set fh [open $third a]
	puts $fh "\[Extra \"$third\"\]"
	close $fh
	set distinct [expr {[file size $second] != [file size $third]}]
	::scidb::test::recentpaths::forceCaseInsensitive 1
} -body {
	# the same name in another case: one file. Two files that differ only
	# in case are two files even then (a case-sensitive volume on a Mac).
	list \
		[::platform::sys::sameFile $upper $a] \
		[expr {[::platform::sys::sameFile $second $third] == !$distinct}]
} -cleanup {
	::scidb::test::recentpaths::forceCaseInsensitive 0
	file delete $a $second $third
} -result {1 1}

tcltest::test recentpaths-case-volume {two names that differ in case follow the volume, not the code} -setup {
	set d $::scidb::test::recentpaths::dir
	set a [file join $d case-sense.pgn]
	set b [file join $d CASE-SENSE.pgn]
	catch { file delete $a $b }
	::scidb::test::recentpaths::makePgn $a
	::scidb::test::recentpaths::makePgn $b
	set fh [open $b a]
	puts $fh "\[Extra \"$b\"\]"
	close $fh
	set distinct [expr {[file size $a] != [file size $b]}]
} -body {
	# APFS may be case-insensitive; assert identity against the measured
	# volume behavior rather than requiring two distinct files.
	expr {[::platform::sys::sameFile $a $b] == !$distinct}
} -cleanup {
	file delete $a $b
} -result 1

# --- G13: the recent list finds the entry it is given --------------------

tcltest::test recentpaths-find-spelling {a recent entry is found whatever its spelling} -setup {
	::scidb::test::recentpaths::saveRecent
	set pgn $::scidb::test::recentpaths::pgn
	set d $::scidb::test::recentpaths::dir
	::scidb::test::recentpaths::makePgn $pgn
	::scidb::test::recentpaths::addRecent [file join $d ".." recent-paths "Spiel \u00dcbung & Pfad.pgn"]
} -body {
	set found [::scidb::test::recentpaths::recentIndex $pgn]
	::application::database::removeRecentFile $pgn
	list $found [::scidb::test::recentpaths::recentIndex $pgn]
} -cleanup {
	::scidb::test::recentpaths::restoreRecent
} -result {0 -1}

tcltest::test recentpaths-open-spelling {opening a recent file again does not add a second entry} -setup {
	::scidb::test::recentpaths::saveRecent
	set pgn $::scidb::test::recentpaths::pgn
	set d $::scidb::test::recentpaths::dir
	::scidb::test::recentpaths::makePgn $pgn
	::scidb::test::recentpaths::addRecent [file join $d ".." recent-paths "Spiel \u00dcbung & Pfad.pgn"]
	::scidb::test::recentpaths::buildPage
} -body {
	::application::information::Mouse1Up [list [::scidb::test::recentpaths::node 0]]
	update idletasks
	list \
		[::scidb::db::get open? $pgn] \
		[::scidb::test::recentpaths::countRecent $pgn] \
		[::scidb::test::recentpaths::recentIndex $pgn]
} -cleanup {
	::scidb::test::recentpaths::closeBase $::scidb::test::recentpaths::pgn
	::scidb::test::recentpaths::restoreRecent
} -result {1 1 0}

tcltest::test recentpaths-click-missing {a recent entry whose file is gone is removed with a message} -setup {
	::scidb::test::recentpaths::saveRecent
	::scidb::test::recentpaths::stubDialog
	set gone [file join $::scidb::test::recentpaths::dir "Gel\u00f6scht & weg.pgn"]
	catch { file delete $gone }
	::scidb::test::recentpaths::addRecent $gone
	::scidb::test::recentpaths::buildPage
} -body {
	::application::information::Mouse1Up [list [::scidb::test::recentpaths::node 0]]
	update idletasks
	list \
		[::scidb::test::recentpaths::recentIndex $gone] \
		[expr {[string first "Cannot open file" [::scidb::test::recentpaths::dialogText]] >= 0}] \
		[expr {[string first $gone [::scidb::test::recentpaths::logText]] >= 0}]
} -cleanup {
	::scidb::test::recentpaths::unstubDialog
	::scidb::test::recentpaths::restoreRecent
} -result {-1 1 1}

tcltest::test recentpaths-click-locked {a recent file that exists but cannot be read keeps its entry} -constraints unreadableFiles -setup {
	::scidb::test::recentpaths::saveRecent
	::scidb::test::recentpaths::stubDialog
	set pgn [file join $::scidb::test::recentpaths::dir "Gesperrt.pgn"]
	::scidb::test::recentpaths::makePgn $pgn
	::scidb::test::recentpaths::addRecent $pgn
	::scidb::test::recentpaths::buildPage
	set locked [::scidb::test::recentpaths::unreadable $pgn]
} -body {
	::application::information::Mouse1Up [list [::scidb::test::recentpaths::node 0]]
	update idletasks
	list \
		$locked \
		[::scidb::test::recentpaths::recentIndex $pgn] \
		[::scidb::db::get open? $pgn] \
		[expr {[string first "Cannot read file" [::scidb::test::recentpaths::dialogText]] >= 0}]
} -cleanup {
	::scidb::test::recentpaths::readableAgain $pgn
	::scidb::test::recentpaths::unstubDialog
	::scidb::test::recentpaths::restoreRecent
} -result {1 0 0 1}

tcltest::test recentpaths-stale-row {a row clicked after the list moved opens the row that was shown} -setup {
	::scidb::test::recentpaths::saveRecent
	set d $::scidb::test::recentpaths::dir
	set first [file join $d first.pgn]
	set second [file join $d second.pgn]
	::scidb::test::recentpaths::makePgn $first
	::scidb::test::recentpaths::makePgn $second
	# the page lists first, second; meanwhile second was opened and the
	# live history now lists second first
	::scidb::test::recentpaths::addRecent $second
	::scidb::test::recentpaths::addRecent $first
	::scidb::test::recentpaths::buildPage
	set ::application::database::RecentFiles \
		[list [list PGNFile $second utf-8 1] [list PGNFile $first utf-8 1]]
} -body {
	# row 1 is what the user saw (second), not row 1 of the live list
	::application::information::Mouse1Up [list [::scidb::test::recentpaths::node 1]]
	update idletasks
	list [::scidb::db::get open? $second] [::scidb::db::get open? $first]
} -cleanup {
	::scidb::test::recentpaths::closeBase $second
	::scidb::test::recentpaths::closeBase $first
	::scidb::test::recentpaths::restoreRecent
} -result {1 0}

tcltest::test recentpaths-stale-removed {clicking a row the page no longer has says so} -setup {
	::scidb::test::recentpaths::saveRecent
	set d $::scidb::test::recentpaths::dir
	set only [file join $d only.pgn]
	set other [file join $d other-row.pgn]
	::scidb::test::recentpaths::makePgn $only
	::scidb::test::recentpaths::makePgn $other
	::scidb::test::recentpaths::addRecent $only
	::scidb::test::recentpaths::addRecent $other
	# the page was drawn with one row; the history has two now
	set ::application::information::Priv(recent) [list [list PGNFile $other utf-8 1]]
} -body {
	set rc [catch {
		::application::information::Mouse1Up [list [::scidb::test::recentpaths::node 1]]
		update idletasks
	} err]
	list $rc [::scidb::db::get open? $only] [::scidb::db::get open? $other] \
		[expr {[string first "no longer in the list" [::scidb::test::recentpaths::logText]] >= 0}]
} -cleanup {
	::scidb::test::recentpaths::closeBase $only
	::scidb::test::recentpaths::closeBase $other
	::scidb::test::recentpaths::restoreRecent
} -result {0 0 0 1}

tcltest::test recentpaths-context-remove {the context menu removes the row that was shown} -setup {
	::scidb::test::recentpaths::saveRecent
	set d $::scidb::test::recentpaths::dir
	set a [file join $d menu-a.pgn]
	set b [file join $d menu-b.pgn]
	::scidb::test::recentpaths::makePgn $a
	::scidb::test::recentpaths::makePgn $b
	::scidb::test::recentpaths::addRecent $b
	::scidb::test::recentpaths::addRecent $a
	::scidb::test::recentpaths::buildPage
	# a has gone from the history while the page still shows the two rows it
	# was drawn with.  information::update re-snapshots the page while it is
	# mapped, so the rows the menu was built for are kept explicitly here:
	# the click below carries the id of the drawn page, not of the live list.
	set shown $::application::information::Priv(recent)
	::application::database::removeRecentFile $a
	set ::application::information::Priv(recent) $shown
} -body {
	# row 1 (b) is removed by the context menu; a is already gone
	::application::information::RemoveRecentFile 1
	update idletasks
	list [::scidb::test::recentpaths::recentIndex $b] [::scidb::test::recentpaths::recentIndex $a]
} -cleanup {
	::scidb::test::recentpaths::restoreRecent
} -result {-1 -1}

tcltest::test recentpaths-stale-remove {the context menu removes the row that was shown, not the row at that index} -setup {
	::scidb::test::recentpaths::saveRecent
	set d $::scidb::test::recentpaths::dir
	set a [file join $d menu-a.pgn]
	set b [file join $d menu-b.pgn]
	::scidb::test::recentpaths::makePgn $a
	::scidb::test::recentpaths::makePgn $b
	::scidb::test::recentpaths::addRecent $b
	::scidb::test::recentpaths::addRecent $a
	::scidb::test::recentpaths::buildPage
	# meanwhile b was opened: the live history lists b first
	set ::application::database::RecentFiles \
		[list [list PGNFile $b utf-8 1] [list PGNFile $a utf-8 1]]
} -body {
	# row 0 is a: removing it must not remove b, which is now live row 0
	::application::information::RemoveRecentFile 0
	update idletasks
	list [::scidb::test::recentpaths::recentIndex $a] \
		[::scidb::test::recentpaths::recentIndex $b]
} -cleanup {
	::scidb::test::recentpaths::restoreRecent
} -result {-1 0}

# --- G23: a read-only database says why Maintenance is greyed ------------

tcltest::test maintreadonly-pgn {a read-only PGN explains the greyed Maintenance menu} -constraints x11 -setup {
	set pgn $::scidb::test::recentpaths::pgn
	::scidb::test::recentpaths::makePgn $pgn
	::application::database::openBase .application $pgn no -readonly 1
	update idletasks
} -body {
	lassign [::scidb::test::recentpaths::maintenanceHint $pgn] state type label entryState
	list \
		$state \
		$type \
		[expr {$label eq " $::application::database::mc::MaintenanceReadOnlyPgn"}] \
		$entryState
} -cleanup {
	::scidb::test::recentpaths::unpopup
	::scidb::test::recentpaths::closeBase $::scidb::test::recentpaths::pgn
} -result {normal command 1 disabled}

tcltest::test maintreadonly-other {a read-only database that is not a PGN gets the general hint} -constraints x11 -setup {
	set sci [file join $::scidb::test::recentpaths::dir readonly-probe.sci]
	file delete -force $sci
	::application::database::newBase .application Normal $sci
	update idletasks
	# ToggleReadOnly reads the new state from a variable and sets it
	set ::scidb::test::recentpaths::ro 1
	::application::database::ToggleReadOnly ::scidb::test::recentpaths::ro $sci
} -body {
	lassign [::scidb::test::recentpaths::maintenanceHint $sci] state type label entryState
	list \
		$state \
		$type \
		[expr {$label eq " $::application::database::mc::MaintenanceReadOnly"}] \
		$entryState \
		[::scidb::db::get readonly? $sci]
} -cleanup {
	::scidb::test::recentpaths::unpopup
	::scidb::test::recentpaths::closeBase $sci
	catch { file delete -force $sci }
} -result {normal command 1 disabled 1}

tcltest::test maintreadonly-writable {a writable database has no read-only hint} -constraints x11 -setup {
	set sci [file join $::scidb::test::recentpaths::dir writable-probe.sci]
	file delete -force $sci
	::application::database::newBase .application Normal $sci
	update idletasks
} -body {
	set menu [::scidb::test::recentpaths::popup $sci]
	set i [::scidb::test::recentpaths::maintenanceIndex $menu]
	set sub [$menu entrycget $i -menu]
	set hints {}
	foreach j [::scidb::test::recentpaths::range $sub] {
		set label [$sub entrycget $j -label]
		if {[string first $::application::database::mc::MaintenanceReadOnlyPgn $label] >= 0
			|| [string first $::application::database::mc::MaintenanceReadOnly $label] >= 0} {
			lappend hints $label
		}
	}
	list [$menu entrycget $i -state] [llength $hints] [expr {[$sub index end] ne "none"}]
} -cleanup {
	::scidb::test::recentpaths::unpopup
	::scidb::test::recentpaths::closeBase $sci
	catch { file delete -force $sci }
} -result {normal 0 1}

tcltest::cleanupTests
