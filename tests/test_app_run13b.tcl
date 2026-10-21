# ======================================================================
# Scidb App Test - Run 13b tester bugs (Windows, 1920x1080, 200%)
# ======================================================================
# 1. ::util::place passed negative/too large positions through on Windows:
#    the Overview opened with its title bar at y=-41, Search by Material off
#    the left edge. Tested with the win32 branch forced.
# 2. A path with spaces, '&' and an umlaut: clicking the Recently used entry
#    removed it silently; dropped text split such a path into words
#    ("Cannot open file C:/cwexplore/data/Pfad"); the context menu Remove
#    did nothing; the single-instance hand-off used the system code page.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::run13b {
	variable dir [file join $::scidb::test::app::testDir tmp-app run13b "Pfad mit Leerzeichen & \u00dcmlaut"]
	variable pgn [file join $dir "Schachspiele \u00dcbung.pgn"]

	proc makePgn {} {
		variable dir
		variable pgn
		file mkdir $dir
		set fh [open $pgn w]
		fconfigure $fh -encoding utf-8
		puts $fh "\[Event \"R13b\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 1-0\n"
		close $fh
	}

	# force the Windows branch of ::util::place::geometry
	proc fakeWin32 {on} {
		if {$on} {
			proc ::util::place::tk {args} {
				if {$args eq "windowingsystem"} { return win32 }
				return [uplevel 1 ::tk $args]
			}
		} else {
			catch { rename ::util::place::tk {} }
		}
	}

	# an html node stub for information::Mouse1Up: "<node> attribute -default {} id"
	proc node {args} {
		if {[lindex $args end] eq "id"} { return 0 }
		return {}
	}

	proc recentIndex {file} {
		return [lsearch -exact -index 1 $::application::database::RecentFiles $file]
	}

	proc closeBase {} {
		variable pgn
		catch { ::application::database::closeBase .application $pgn }
		update
	}
}

# --- 1. window placement ------------------------------------------------

tcltest::test run13b-clamp {the clamp keeps a window inside the screen range} -body {
	list \
		[::util::place::clamp +-41 1000 0 1080] \
		[::util::place::clamp +-300 400 0 1920] \
		[::util::place::clamp +1700 400 0 1920] \
		[::util::place::clamp +100 400 0 1920] \
		[::util::place::clamp -0 2000 0 1920] \
		[::util::place::clamp -0 400 0 1920] \
		[::util::place::clamp +10 400 50 1920]
} -result {+0 +0 +1520 +100 +0 -0 +50}

tcltest::test run13b-win32-center {Windows: a window taller than the screen is not placed above it} -setup {
	set t [toplevel .run13bTall]
	wm withdraw $t
	frame $t.f -width 300 -height [expr {[winfo screenheight .] + 200}]
	pack $t.f
	::scidb::test::run13b::fakeWin32 1
} -body {
	lassign [::util::place::geometry $t -position center] x y
	scan $y %d y0
	scan $x %d x0
	list [expr {$y0 >= [lindex [winfo workarea $t] 1]}] [expr {$x0 >= 0}] [string index $y 0]
} -cleanup {
	::scidb::test::run13b::fakeWin32 0
	destroy $t
} -result {1 1 +}

tcltest::test run13b-win32-at {Windows: an "at" position beyond the screen is moved onto it} -setup {
	set t [toplevel .run13bAt]
	wm withdraw $t
	frame $t.f -width 400 -height 300
	pack $t.f
	::scidb::test::run13b::fakeWin32 1
} -body {
	lassign [::util::place::geometry $t -position at -x 5000 -y 5000] x y
	lassign [winfo extents $t] el er et eb
	lassign [winfo workarea $t] sx sy sw sh
	list [expr {$x eq "+[expr {$sx + $sw - [winfo reqwidth $t] - $el - $er}]"}] \
		[expr {$y eq "+[expr {$sy + $sh - [winfo reqheight $t] - $et - $eb}]"}]
} -cleanup {
	::scidb::test::run13b::fakeWin32 0
	destroy $t
} -result {1 1}

tcltest::test run13b-win32-left {Windows: "left" of a parent at the left edge stays on screen} -setup {
	set t [toplevel .run13bLeft]
	wm withdraw $t
	frame $t.f -width 600 -height 300
	pack $t.f
	set g [wm geometry .application]
	wm geometry .application 500x400+0+0
	update
	::scidb::test::run13b::fakeWin32 1
} -body {
	lassign [::util::place::geometry $t -parent .application -position left-or-right] x y
	scan $x %d x0
	scan $y %d y0
	list [expr {$x0 >= 0}] [expr {$y0 >= 0}]
} -cleanup {
	::scidb::test::run13b::fakeWin32 0
	destroy $t
	wm geometry .application $g
} -result {1 1}

tcltest::test run13b-overview-win32 {Windows: the Overview window opens with its title bar on screen} -setup {
	::scidb::test::run13b::makePgn
	set base [file join $::scidb::test::app::testDir tmp-app run13b-ovw-[pid].pgn]
	file copy -force $::scidb::test::run13b::pgn $base
	::scidb::db::open $base {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::scidb::test::run13b::fakeWin32 1
} -body {
	set info [::scidb::db::get gameInfo 0 0 $base Normal]
	set dlg [winfo toplevel [::overview::open .application $base Normal $info 0 0]]
	update
	lassign [::util::place::geometry $dlg -position center] x y
	scan $y %d y0
	list [expr {$y0 >= 0}] [expr {[winfo rooty $dlg] >= 0}]
} -cleanup {
	::scidb::test::run13b::fakeWin32 0
	catch { destroy $dlg }
	catch { ::scidb::db::close $base }
	catch { file delete $base }
} -result {1 1}

# --- 2. recent databases, paths with spaces, '&' and umlauts -------------

tcltest::test run13b-recent-click {Recently used: clicking a path with spaces, '&' and an umlaut opens it} -setup {
	::scidb::test::run13b::makePgn
	set pgn $::scidb::test::run13b::pgn
	::application::database::openBase .application $pgn no -readonly 1
	::scidb::test::run13b::closeBase
} -body {
	set before [expr {[::scidb::test::run13b::recentIndex $pgn] >= 0}]
	# what the Information page shows as entry 0, and what a click opens
	set shown [lindex [::application::database::recentFiles] 0 1]
	::application::information::Mouse1Up [list ::scidb::test::run13b::node]
	update
	list $before [expr {[file normalize $shown] eq $pgn}] [::scidb::db::get open? $pgn] \
		[expr {[::scidb::test::run13b::recentIndex $pgn] >= 0}]
} -cleanup {
	::scidb::test::run13b::closeBase
} -result {1 1 1 1}

tcltest::test run13b-recent-roundtrip {the recent list survives the options file} -setup {
	::scidb::test::run13b::makePgn
	set pgn $::scidb::test::run13b::pgn
	::application::database::openBase .application $pgn no -readonly 1
	::scidb::test::run13b::closeBase
	set saved $::application::database::RecentFiles
	set f [file join $::scidb::test::app::testDir tmp-app run13b-options-[pid].tcl]
} -body {
	set ch [open $f w]
	fconfigure $ch -encoding utf-8
	::options::writeList $ch ::application::database::RecentFiles
	close $ch
	set ::application::database::RecentFiles {}
	::load::source $f -encoding utf-8 -throw 1
	expr {[::scidb::test::run13b::recentIndex $pgn] >= 0}
} -cleanup {
	set ::application::database::RecentFiles $saved
	file delete $f
} -result 1

tcltest::test run13b-drop-text {dropped text with a path with spaces is one file, not words} -setup {
	::scidb::test::run13b::makePgn
	set pgn $::scidb::test::run13b::pgn
} -body {
	list [::fsbox::parseUriList $pgn] [llength [::fsbox::parseUriList "$pgn\r\n$pgn\r\n"]]
} -result [list [list $::scidb::test::run13b::pgn $::scidb::test::run13b::pgn] 4]

tcltest::test run13b-drop-list {a dropped Tcl list of paths still works} -setup {
	::scidb::test::run13b::makePgn
	set pgn $::scidb::test::run13b::pgn
} -body {
	llength [::fsbox::parseUriList [list $pgn $pgn]]
} -result 4

tcltest::test run13b-recent-remove {Recently used: the context menu's Remove removes the entry} -setup {
	::scidb::test::run13b::makePgn
	set pgn $::scidb::test::run13b::pgn
	::application::database::openBase .application $pgn no -readonly 1
	::scidb::test::run13b::closeBase
} -body {
	set k [lsearch -exact -index 1 [::application::database::recentFiles] \
		[lindex [::application::database::recentFiles] 0 1]]
	::application::information::RemoveRecentFile $k
	update
	::scidb::test::run13b::recentIndex $pgn
} -result -1

tcltest::test run13b-missing-logged {a recent file that is gone is logged, not dropped silently} -setup {
	set missing [file join $::scidb::test::run13b::dir "Gel\u00f6scht & weg.pgn"]
	catch { file delete $missing }
	set saved $::application::database::RecentFiles
	set ::application::database::RecentFiles [linsert $saved 0 [list PGNFile $missing utf-8 1]]
	rename ::dialog::error ::scidb::test::run13b::_dialogError
	proc ::dialog::error {args} { return ok }
} -body {
	::application::database::openBase .application $missing no
	set t $::log::Log.top.text
	list [expr {[string first $missing [$t get 1.0 end]] >= 0}] \
		[::scidb::test::run13b::recentIndex $missing]
} -cleanup {
	rename ::dialog::error {}
	rename ::scidb::test::run13b::_dialogError ::dialog::error
	set ::application::database::RecentFiles $saved
	catch { wm withdraw $::log::Log }
} -result {1 -1}

tcltest::test run13b-handoff-utf8 {a second instance hands over the path in UTF-8} -setup {
	set pgn $::scidb::test::run13b::pgn
	set ::scidb::test::run13b::got {}
	set server [socket -server {apply {{chan addr port} {
		fconfigure $chan -encoding utf-8
		set ::scidb::test::run13b::got [gets $chan]
		close $chan
	}}} -myaddr 127.0.0.1 0]
	set port [lindex [fconfigure $server -sockname] 2]
	set saveArgv $::argv
	set saveArgc $::argc
	set ::argv [list $pgn]
	set ::argc 1
	set sysenc [encoding system]
} -body {
	# the Windows code page cannot hold every character of a path
	encoding system iso8859-1
	set pgn2 "${pgn}\u0141"
	set ::argv [list $pgn2]
	catch { ::remote::SendPath $port }
	encoding system $sysenc
	set n 0
	while {$::scidb::test::run13b::got eq "" && [incr n] < 200} { after 10; update }
	expr {[lindex $::scidb::test::run13b::got 0] eq $pgn2}
} -cleanup {
	encoding system $sysenc
	close $server
	set ::argv $saveArgv
	set ::argc $saveArgc
} -result 1

# --- 3. menu steps replay through action ids ----------------------------

tcltest::test run13b-menu-by-id {menu steps are action ids and replay by id} -setup {
	catch { destroy .application.infoDialog }
	catch { destroy .run13bMenu }
} -body {
	menu .run13bMenu -tearoff 0
	::menu::BuildDropdown .run13bMenu
	set ids {
		menu.game.paste_clip menu.game.paste_tab
		menu.game.merge_clip menu.game.merge_tab
		menu.game.history.recent
		menu.view.panes.board menu.view.panes.players
		menu.analysis.engine_toggle
	}
	set unresolved {}
	foreach id $ids {
		if {[catch { ::action::get $id }]} { lappend unresolved $id }
	}
	set labels [::action::labels dropdown]
	set labelIds {}
	foreach row $labels { lappend labelIds [lindex $row 0] }
	set listed [expr {"menu.analysis.engine_toggle" in $labelIds}]
	# Replay one posted menu row by id, as the laptop instructions do.
	if {[tk windowingsystem] eq "aqua"} {
		# The native About panel is not a Tk infoDialog. Observe the real
		# panel API without replacing the action or its handler.
		set ::run13bNativeAbout 0
		set aboutTrace [list apply {{args} {set ::run13bNativeAbout 1}}]
		trace add execution ::tk::mac::standardAboutPanel enter $aboutTrace
		try {
			set ran [::action::run menu.help.about]
			update
			set opened $::run13bNativeAbout
		} finally {
			trace remove execution ::tk::mac::standardAboutPanel enter $aboutTrace
		}
	} else {
		set ran [::action::run menu.help.about]
		update
		set opened [winfo exists .application.infoDialog]
	}
	catch { destroy .application.infoDialog }
	destroy .run13bMenu
	list $unresolved $listed $opened
} -result {{} 1 1}

tcltest::cleanupTests
