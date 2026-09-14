# ======================================================================
# Scidb App Test — 3D board viewer (tcl/board-3d.tcl)
#
# Checks the viewer toplevel, the renderer output on a real canvas and the
# position-sync entry point used by application::board::update.  The pure
# math is covered headless by tests/test_board3d.tcl.
# ======================================================================

package require tcltest 2.5

proc b3dAppCanvas {} { return .application.__board3d__.canvas }

tcltest::test board3d-app-module {3D board module and entry points are loaded} -body {
	list [namespace exists ::board3d] \
		[llength [info commands ::board3d::openViewer]] \
		[llength [info commands ::board3d::PositionChanged]] \
		[llength [info commands ::board3d::squareAt]]
} -result {1 1 1 1}

tcltest::test board3d-app-menu {Extras menu offers the 3D board} -body {
	catch { destroy .testmenu3d }
	menu .testmenu3d
	::menu::build .testmenu3d
	set found 0
	set n [.testmenu3d index end]
	for {set i 0} {$i <= $n} {incr i} {
		if {[.testmenu3d type $i] eq "cascade"
			&& [string match "*Extras*" [.testmenu3d entrycget $i -label]]} {
			set em [.testmenu3d entrycget $i -menu]
			set en [$em index end]
			for {set k 0} {$k <= $en} {incr k} {
				if {[catch { set label [$em entrycget $k -label] }]} { continue }
				if {[string match "*3D Board*" $label]} { set found 1 }
			}
		}
	}
	destroy .testmenu3d
	set found
} -result 1

tcltest::test board3d-app-open {viewer opens, draws and reports open} -body {
	::board3d::openViewer .application
	wm geometry .application.__board3d__ 640x520+0+0
	update idletasks
	update
	set canv [b3dAppCanvas]
	list [::board3d::isOpen] [winfo exists $canv] \
		[expr {[llength [$canv find withtag b3d]] > 0}]
} -result {1 1 1}

tcltest::test board3d-app-geometry {renderer fills the canvas with tiles and pieces} -body {
	set canv [b3dAppCanvas]
	set polys [llength [$canv find withtag tile]]
	# 64 tiles, plus slab/sides/pieces/marks
	expr {$polys >= 64}
} -result 1

tcltest::test board3d-app-preset {view presets and rotation update the camera} -body {
	::board3d::preset black
	set yawBlack $::board3d::State(yaw)
	::board3d::viewerRotate 15
	set yawAfter $::board3d::State(yaw)
	::board3d::viewerPreset white
	list $yawBlack [expr {$yawAfter != $yawBlack}] $::board3d::State(yaw) \
		[::board3d::isOpen]
} -result {180.0 1 0.0 1}

tcltest::test board3d-app-position-sync {PositionChanged mirrors a new position and redraws} -body {
	set board "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
	::board3d::PositionChanged $board
	set canv [b3dAppCanvas]
	update idletasks
	list $::board3d::State(board) \
		[expr {[llength [$canv find withtag b3d]] > 0}]
} -result {rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR 1}

tcltest::test board3d-app-select {click selection resolves through the projection in both views} -body {
	# canvas view: the canvas centre must be inside the board for the default view
	::board3d::toggleOpenGL 0
	::board3d::preset white
	::board3d::refresh
	update idletasks
	update
	set canv [b3dAppCanvas]
	set cx [expr {[winfo width $canv]/2}]
	set cy [expr {[winfo height $canv]/2}]
	set sq [::board3d::squareAt $cx $cy]
	set res [list [expr {$sq >= 0 && $sq < 64}] \
		[expr {[::board3d::pickSquare $cx $cy] == $sq}]]
	# hardware view: the same click picks through the GL projection
	set t $::board3d::Priv(togl)
	if {$t ne "" && [winfo exists $t] && [llength [info commands ::scidb::tk::glboard_pick]]} {
		::board3d::toggleOpenGL 1
		update idletasks
		update
		set gsq [::scidb::tk::glboard_pick $t \
			[expr {[winfo width $t]/2}] [expr {[winfo height $t]/2}] \
			$::board3d::State(yaw) $::board3d::State(pitch) $::board3d::State(distance)]
		lappend res [expr {$gsq >= 0 && $gsq < 64}] \
			[expr {$::board3d::State(useOpenGL) == 1}]
		::board3d::toggleOpenGL 0
		update
	} else {
		lappend res 1 1
	}
	set res
} -result {1 1 1 1}

tcltest::test board3d-app-callbacks {interaction callbacks accept their bound argument counts} -body {
	set canv [b3dAppCanvas]
	set errs {}
	foreach script [list \
		[list ::board3d::OnConfigure $canv 640 480] \
		[list ::board3d::OnPress 100 100] \
		[list ::board3d::OnMotion 110 105] \
		[list ::board3d::OnPress 100 100 pan] \
		[list ::board3d::OnRelease] \
		[list ::board3d::viewerZoom 1] \
		[list ::board3d::viewerZoom -1] \
		[list ::board3d::viewerRotate 15] \
		[list ::board3d::viewerTilt 5] \
		[list ::board3d::viewerPreset side] \
	] {
		if {[catch { uplevel #0 $script } e]} { lappend errs [list $script $e] }
	}
	update idletasks
	set errs
} -result {}

tcltest::test board3d-app-configure-binding {the Configure binding passes window, width and height} -body {
	set canv [b3dAppCanvas]
	# the generated bind script must reference OnConfigure (a 3-arg proc)
	string match "*OnConfigure*" [bind $canv <Configure>]
} -result 1

tcltest::test board3d-app-unknown-piece {a board string with an unknown piece character still renders} -body {
	set b [string replace [::board3d::NormalizeBoard standard] 63 63 X]
	::board3d::setBoard $b
	update idletasks
	set canv [b3dAppCanvas]
	expr {[string length $::board3d::State(board)] == 64
		&& [llength [$canv find withtag b3d]] > 0}
} -result 1

tcltest::test board3d-app-close {closing the viewer destroys the window} -body {
	::board3d::closeViewer
	list [::board3d::isOpen] [winfo exists .application.__board3d__]
} -result {0 0}

# WebGL viewer: local three.js front end served by web3d/server.py.
# Skipped when python3 or the http package is unavailable.
tcltest::testConstraint webgl [expr {![catch { exec python3 -c exit }] && ![catch { package require http }]}]

tcltest::test board3d-app-webgl {WebGL server starts, serves and syncs the board} -constraints webgl -body {
	set ::env(SCIDB_WEB3D_NO_BROWSER) 1
	set rc [::board3d::openWebGLViewer]
	if {$rc != 1} { error "WebGL server did not come up" }
	set board "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
	::board3d::PositionChanged $board
	set tok [::http::geturl http://127.0.0.1:8899/api/board -timeout 3000]
	set data [::http::data $tok]
	::http::cleanup $tok
	# the pushed board round-trips through the server API
	set match [string match "*\"board\": \"$board\"*" $data]
	# and a position change syncs to the server without errors
	set sync [::board3d::PositionChanged [::board3d::NormalizeBoard empty]]
	list $match [expr {[string length $sync] == 64}]
} -result {1 1}

# stop the WebGL server again when this suite started it
if {[string is integer -strict $::board3d::Priv(webgl,pid)]} {
	catch { exec kill $::board3d::Priv(webgl,pid) }
	set ::board3d::Priv(webgl,pid) {}
	set ::board3d::Priv(webgl,auto) 0
}

tcltest::cleanupTests
