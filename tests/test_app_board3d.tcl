# ======================================================================
# Scidb App Test — 3D board viewer (tcl/board-3d.tcl)
#
# Checks the viewer toplevel, the renderer output on a real canvas and the
# position-sync entry point used by application::board::update.  The pure
# math is covered headless by tests/test_board3d.tcl.
# ======================================================================

package require tcltest 2.5

proc b3dAppCanvas {} { return .application.__board3d__.canvas }

# Pump events until `w` reports the wanted size (or any real size when
# none is given).  A fixed `after 50` races the X server under load:
# the window may still be 1x1 or at its old geometry when we sample it.
proc b3dWaitSize {w {width 0} {height 0} {ms 3000}} {
	set deadline [expr {[clock milliseconds] + $ms}]
	while {[clock milliseconds] < $deadline} {
		update
		if {![winfo exists $w]} { return 0 }
		set ww [winfo width $w]
		set wh [winfo height $w]
		if {$width > 0 ? ($ww == $width && $wh == $height) : ($ww > 1 && $wh > 1)} { return 1 }
		after 20
	}
	return 0
}

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
	update idletasks
	update
	::board3d::preset white
	# re-fit with the now-real canvas size; the DoResize coalescing timer
	# may not have fired yet at this point
	::board3d::refresh
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
		b3dWaitSize $t
		set gsq -1
		if {[winfo width $t] > 1 && [winfo height $t] > 1} {
			set gsq [::scidb::tk::glboard_pick $t \
				[expr {[winfo width $t]/2}] [expr {[winfo height $t]/2}] \
				$::board3d::State(yaw) $::board3d::State(pitch) $::board3d::State(distance)]
		}
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
	set t [set ::board3d::Priv(togl)]
	set errs {}
	foreach script [list \
		[list ::board3d::OnConfigure $canv 640 480] \
		[list ::board3d::OnPress $canv 100 100] \
		[list ::board3d::OnMotion $canv 110 105] \
		[list ::board3d::OnPress $canv 100 100 pan] \
		[list ::board3d::OnRelease $canv] \
		[list ::board3d::viewerZoom 1] \
		[list ::board3d::viewerZoom -1] \
		[list ::board3d::viewerRotate 15] \
		[list ::board3d::viewerTilt 5] \
		[list ::board3d::viewerPreset side] \
	] {
		if {[catch { uplevel #0 $script } e]} { lappend errs [list $script $e] }
	}
	# the same handlers must also accept a togl window
	if {$t ne "" && [winfo exists $t]} {
		foreach script [list \
			[list ::board3d::OnPress $t 100 100] \
			[list ::board3d::OnMotion $t 110 105] \
			[list ::board3d::OnPress $t 100 100 pan] \
			[list ::board3d::OnRelease $t] \
		] {
			if {[catch { uplevel #0 $script } e]} { lappend errs [list $script $e] }
		}
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

# Embedded hardware 3D in the main board pane: needs Togl
set embedOK 0
catch { set embedOK [::board3d::LoadToglLib] }
tcltest::testConstraint embed3d $embedOK

tcltest::test board3d-embed-pane {hardware 3D embeds into the main board pane} -constraints embed3d -body {
	# the board page must be the visible tab, like in a real session
	catch { .application.nb select .application.nb.board }
	update idletasks
	update
	set res {}
	set originalPack [pack info $::application::board::Vars(widget:frame)]
	set originalOrder [pack slaves [winfo parent $::application::board::Vars(widget:frame)]]
	# switch through the same path the menu checkbutton takes
	set ::board3d::State(embed) 1
	::board3d::toggleEmbed
	update idletasks
	update
	set t $::board3d::Priv(embed,togl)
	lappend res [expr {$::board3d::State(embed) == 1}] \
		[expr {[winfo exists $t] && [winfo ismapped $t]}] \
		[expr {![winfo ismapped $::application::board::Vars(widget:frame)]}]
	# a position change renders into the embedded view
	::board3d::PositionChanged "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
	set rc [catch { ::scidb::tk::glboard_render $t $::board3d::State(board) \
		$::board3d::State(yaw) $::board3d::State(pitch) \
		$::board3d::State(distance) $::board3d::State(selected) } out]
	lappend res [expr {!$rc && $out == 1}]
	# click pick resolves through the embedded view's own projection
	set sq [::scidb::tk::glboard_pick $t \
		[expr {[winfo width $t]/2}] [expr {[winfo height $t]/2}] \
		$::board3d::State(yaw) $::board3d::State(pitch) $::board3d::State(distance)]
	lappend res [expr {$sq >= 0 && $sq < 64}]
	# and back to the 2D board
	set ::board3d::State(embed) 0
	::board3d::toggleEmbed
	update
	lappend res [expr {$::board3d::State(embed) == 0 \
		&& [winfo ismapped $::application::board::Vars(widget:frame)]}]
	lappend res [expr {$originalPack eq [pack info $::application::board::Vars(widget:frame)]}] \
		[expr {$originalOrder eq [pack slaves [winfo parent $::application::board::Vars(widget:frame)]]}]
	set res
} -result {1 1 1 1 1 1 1 1}

# 3D move input: dragging a piece in the embedded pane plays a move on the
# current game through the application's move machinery.

# The centre of the pixels whose pick is $sq: {x y}, or {} when none. With
# perspective a pixel column runs through several files, so no column is
# safe: the scan covers the whole view.
proc b3dFindPoint {t sq} {
	set xs 0; set ys 0; set n 0
	for {set y 0} {$y < [winfo height $t]} {incr y 3} {
		for {set x 0} {$x < [winfo width $t]} {incr x 3} {
			if {[::scidb::tk::glboard_pick $t $x $y $::board3d::State(yaw) \
					$::board3d::State(pitch) $::board3d::State(distance)] == $sq} {
				incr xs $x; incr ys $y; incr n
			}
		}
	}
	if {$n == 0} { return {} }
	return [list [expr {$xs / $n}] [expr {$ys / $n}]]
}


tcltest::test board3d-3d-move-input {dragging pieces in the embedded 3D pane makes moves} -constraints embed3d -body {
	catch { .application.nb select .application.nb.board }
	set ::board3d::State(embed) 1
	::board3d::toggleEmbed
	update idletasks
	update
	# resync the mirror with the game position (previous tests pushed
	# synthetic boards through PositionChanged)
	::board3d::PositionChanged [::board::diagram::data $::application::board::board]
	set t $::board3d::Priv(embed,togl)

	set res {}
	set e2 [b3dFindPoint $t 12]		;# white pawn
	set e4 [b3dFindPoint $t 28]		;# legal pawn push
	set e5 [b3dFindPoint $t 36]		;# illegal for a pawn
	if {![llength $e2] || ![llength $e4] || ![llength $e5]} { error "pick scan failed to find e2/e4/e5" }
	lassign $e2 x12 y12
	lassign $e4 x28 y28
	lassign $e5 x36 y36

	# 1) drag e2-e4
	event generate $t <ButtonPress-1> -x $x12 -y $y12
	event generate $t <B1-Motion> -x [expr {($x12+$x28)/2}] -y [expr {($y12+$y28)/2}]
	event generate $t <B1-Motion> -x $x28 -y [expr {$y28-2}]
	event generate $t <ButtonRelease-1> -x $x28 -y $y28
	update
	set data [::board::diagram::data $::application::board::board]
	lappend res [expr {[string index $data 12] eq "." && [string index $data 28] eq "P"}]

	# 2) click-click: press/release e2, press e4
	catch { ::application::board::goto -1 }
	update
	event generate $t <ButtonPress-1> -x $x12 -y $y12
	event generate $t <ButtonRelease-1> -x $x12 -y $y12
	event generate $t <ButtonPress-1> -x $x28 -y $y28
	event generate $t <ButtonRelease-1> -x $x28 -y $y28
	update
	set data [::board::diagram::data $::application::board::board]
	lappend res [expr {[string index $data 12] eq "." && [string index $data 28] eq "P"}]

	# 3) illegal drag e2-e5 is rejected
	catch { ::application::board::goto -1 }
	update
	event generate $t <ButtonPress-1> -x $x12 -y $y12
	event generate $t <B1-Motion> -x $x36 -y $y36
	event generate $t <ButtonRelease-1> -x $x36 -y $y36
	update
	set data [::board::diagram::data $::application::board::board]
	lappend res [expr {[string index $data 12] eq "P" && [string index $data 36] eq "."}]

	# cleanup: back to the pristine position and the 2D board
	catch { ::application::board::goto -1 }
	set ::board3d::State(embed) 0
	::board3d::toggleEmbed
	update
	set res
} -result {1 1 1}


tcltest::test board3d-marks-rotation {marks render on the 3D views and rotation syncs the camera} -constraints embed3d -body {
	# canvas viewer marks (full, arrow, circle, disk)
	::board3d::openViewer .application
	::board3d::toggleOpenGL 0
	update idletasks
	update
	set canv [b3dAppCanvas]
	::board3d::preset white
	::board3d::refresh
	update
	::board3d::setMarks [list "add,full,d4,,green" "add,arrow,d1,d4,red" \
		"add,circle,g1,,blue" "add,disk,e4,,yellow" "add,Nf3,g1,,magenta"]
	update
	set res {}
	set fills {} ; set arrows 0 ; set ovals 0 ; set texts {}
	foreach item [$canv find withtag b3d] {
		switch [$canv type $item] {
			polygon { lappend fills [$canv itemcget $item -fill] }
			line { if {[$canv itemcget $item -arrow] eq "last"} { incr arrows } }
			oval { if {[$canv itemcget $item -outline] in {blue yellow}} { incr ovals } }
			text { lappend texts [$canv itemcget $item -text] }
		}
	}
	lappend res [expr {[llength $fills] >= 2 && "green" in $fills}] [expr {$arrows == 1}] \
		[expr {$ovals == 2}] [expr {"Nf3" in $texts}]

	# the embedded GL view renders marks without errors
	catch { .application.nb select .application.nb.board }
	set ::board3d::State(embed) 1
	::board3d::toggleEmbed
	update idletasks
	update
	set t $::board3d::Priv(embed,togl)
	set rc [catch { ::scidb::tk::glboard_render $t $::board3d::State(board) \
		$::board3d::State(yaw) $::board3d::State(pitch) \
		$::board3d::State(distance) -1 -1 -1 0 0 $::board3d::Priv(markGL) } out]
	lappend res [expr {!$rc && $out == 1}]
	# the GL context reports its implementation (renderer/vendor/version)
	set rc [catch { ::scidb::tk::glboard_info $t } info]
	lappend res [expr {!$rc && [llength $info] == 3 && [string length [lindex $info 0]] > 0}]

	# rotating the 2D board re-aims the preset camera
	set yawWhite $::board3d::State(yaw)
	catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
	lappend res [expr {$::board3d::State(view) eq "black" \
		&& $::board3d::State(yaw) != $yawWhite}]
	catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
	lappend res [expr {$::board3d::State(yaw) == $yawWhite \
		&& $::board3d::State(view) eq "white"}]

	# cleanup
	set ::board3d::State(embed) 0
	::board3d::toggleEmbed
	::board3d::setMarks {}
	::board3d::closeViewer
	update
	set res
} -result {1 1 1 1 1 1 1 1}

# count near-black pixels (black pieces are the darkest objects on the
# board top) in a sampled photo
proc b3dDarkPixels {photo} {
	set w [image width $photo]
	set h [image height $photo]
	set count 0
	for {set y 0} {$y < $h} {incr y 3} {
		for {set x 0} {$x < $w} {incr x 3} {
			lassign [$photo get $x $y] r g b
			if {$r < 60 && $g < 45 && $b < 38} { incr count }
		}
	}
	return $count
}

tcltest::test board3d-pieces-both-contexts {pieces render in every GL context} -constraints embed3d -body {
	# display lists are per GL context: the viewer window and the embedded
	# pane are separate contexts, and each must actually draw the pieces
	set ::board3d::State(useOpenGL) 1
	::board3d::openViewer .application
	update idletasks
	update
	set t1 $::board3d::Priv(togl)
	catch { .application.nb select .application.nb.board }
	set ::board3d::State(embed) 1
	::board3d::toggleEmbed
	update idletasks
	update
	set t2 $::board3d::Priv(embed,togl)

	set board [::board3d::NormalizeBoard standard]
	set empty [::board3d::NormalizeBoard empty]
	set yaw $::board3d::State(yaw)
	set pitch $::board3d::State(pitch)
	set dist $::board3d::State(distance)
	image create photo b3dphot1a ; image create photo b3dphot1b
	image create photo b3dphot2a ; image create photo b3dphot2b
	::scidb::tk::glboard_render $t1 $board $yaw $pitch $dist -1 -1 -1 0 0 {} b3dphot1a
	::scidb::tk::glboard_render $t1 $empty $yaw $pitch $dist -1 -1 -1 0 0 {} b3dphot1b
	::scidb::tk::glboard_render $t2 $board $yaw $pitch $dist -1 -1 -1 0 0 {} b3dphot2a
	::scidb::tk::glboard_render $t2 $empty $yaw $pitch $dist -1 -1 -1 0 0 {} b3dphot2b
	set d1 [expr {[b3dDarkPixels b3dphot1a] - [b3dDarkPixels b3dphot1b]}]
	set d2 [expr {[b3dDarkPixels b3dphot2a] - [b3dDarkPixels b3dphot2b]}]
	image delete b3dphot1a b3dphot1b b3dphot2a b3dphot2b

	set ::board3d::State(embed) 0
	::board3d::toggleEmbed
	::board3d::closeViewer
	update
	# the black pieces must be visible in BOTH contexts
	list [expr {$d1 > 50}] [expr {$d2 > 50}]
} -result {1 1}

tcltest::test board3d-fit-pieces {all pieces stay inside portrait and landscape viewports} -constraints embed3d -body {
	toplevel .b3dfit
	set t [::board3d::CreateTogl .b3dfit.gl]
	pack $t -fill both -expand 1
	image create photo b3dfitphoto
	set ok 1
	foreach {width height} {300 600 720 300 480 480} {
		wm geometry .b3dfit ${width}x${height}+0+0
		b3dWaitSize $t $width $height
		foreach yaw {0 45 180} {
			::scidb::tk::glboard_render $t [::board3d::NormalizeBoard standard] $yaw 56 12 -1 -1 -1 0 0 {} b3dfitphoto
			if {[image width b3dfitphoto] != $width || [image height b3dfitphoto] != $height} { error "capture size [image width b3dfitphoto]x[image height b3dfitphoto], expected ${width}x${height}" }
			set bg [b3dfitphoto get 0 0]
			# No board or piece may touch the viewport edge at fitted zoom.
			for {set x 0} {$x < $width} {incr x 3} {
				if {[b3dfitphoto get $x 0] ne $bg || [b3dfitphoto get $x [expr {$height-1}]] ne $bg} { error "vertical clipping at $x in ${width}x${height}, yaw $yaw" }
			}
			for {set y 0} {$y < $height} {incr y 3} {
				if {[b3dfitphoto get 0 $y] ne $bg || [b3dfitphoto get [expr {$width-1}] $y] ne $bg} { error "horizontal clipping at $y in ${width}x${height}, yaw $yaw" }
			}
			# Ensure this is a rendered position, not an empty background.
			if {[b3dfitphoto get [expr {$width/2}] [expr {$height/2}]] eq $bg} { error "empty frame in ${width}x${height}, yaw $yaw" }
			set sq [::scidb::tk::glboard_pick $t [expr {$width/2}] [expr {$height/2}] $yaw 56 12]
			if {$sq < 0 || $sq > 63} { error "center pick missed in ${width}x${height}, yaw $yaw" }
		}
	}
	set ok
} -cleanup {
	catch {image delete b3dfitphoto}
	catch {destroy .b3dfit}
} -result 1

tcltest::test board3d-independent-redraw {simultaneous view resizes each retain a repaint} -constraints embed3d -body {
	toplevel .b3dresize
	set a [::board3d::CreateTogl .b3dresize.a]
	set b [::board3d::CreateTogl .b3dresize.b]
	::board3d::OnConfigure $a 300 400
	set first $::board3d::Priv(resize,$a)
	::board3d::OnConfigure $b 500 300
	set second $::board3d::Priv(resize,$b)
	set ok [expr {[lsearch -exact [after info] $first] >= 0 && [lsearch -exact [after info] $second] >= 0}]
	destroy .b3dresize
	expr {$ok && [lsearch -exact [after info] $first] < 0 && [lsearch -exact [after info] $second] < 0}
} -result 1

# WebGL viewer: in-process Tcl server.
tcltest::testConstraint webgl [expr {![catch { package require http }]}]

tcltest::test board3d-app-webgl {WebGL server starts, serves and syncs the board} -constraints webgl -body {
	set ::env(SCIDB_WEB3D_NO_BROWSER) 1
	set rc [::board3d::openWebGLViewer]
	if {$rc != 1} { error "WebGL server did not come up" }
	set board "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"
	::board3d::PositionChanged $board
	set data ""
	# the GET can race the just-started server (connection refused or stale
	# board); retry for up to ~3 s
	for {set i 0} {$i < 10} {incr i} {
		if {![catch { ::http::geturl [::board3d::WebGLUrl]/api/board -timeout 3000 } tok]} {
			set data [::http::data $tok]
			::http::cleanup $tok
			if {[string match "*\"board\": \"$board\"*" $data]} { break }
		}
		after 300
	}
	set match [string match "*\"board\": \"$board\"*" $data]
	# and a position change syncs to the server without errors
	set sync [::board3d::PositionChanged [::board3d::NormalizeBoard empty]]
	list $match [expr {[string length $sync] == 64}]
} -result {1 1}

::board3d::WebGLStopServer
unset -nocomplain ::env(SCIDB_WEB3D_NO_BROWSER)

tcltest::cleanupTests
