# ======================================================================
# Scidb App Test Suite -- G27: toolbar button icons are keyed
# ======================================================================
# Windows run 117: after opening an empty PGN the first button of the board
# toolbar (.application.nb.board.board.__tb__board-tools.__tbw__1, a Button
# with -image image462) showed a solid black square instead of the engine
# icon.  Tk 8.6 has no RGBA renderer on Windows (tkImgPhInstance.c defines
# TK_CAN_RENDER_RGBA for X11 only), so a photo with partial transparency is
# composited against a copy of the screen read back from the widget; where
# that read-back fails - the window is not visible yet, which is the case for
# the first toolbar painted while the application starts up - Tk leaves black
# behind.  A photo whose alpha is only 0 or 255 is drawn with a clip mask
# instead, which reads nothing back on any platform, so toolbar::KeyIcon
# keys the icons of every toolbar button (see tcl/widgets/toolbar.tcl).
#
# The tests below check the invariant that makes the black square impossible:
# no toolbar button draws a photo with partial transparency, and the reported
# button's image is a real icon (non-empty, more than one colour).
#
# "Partial transparency" is detected without private APIs: a photo is copied
# over an opaque background, and every pixel that is not fully transparent
# must come out unchanged - i.e. its alpha is 255.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::tbicon {
	variable opened {}
}

proc ::scidb::test::tbicon::ignore {args} { return 0 }

proc ::scidb::test::tbicon::isPhoto {img} {
	if {[llength $img] != 1} { return 0 }
	if {[catch {image type $img} type]} { return 0 }
	return [expr {$type eq "photo"}]
}

# The pixels that are visible (not fully transparent) but not opaque: their
# value changes when the photo is drawn on a background it did not come with,
# which is exactly what Tk has to read the screen for.
proc ::scidb::test::tbicon::partiallyTransparent {img} {
	set width [image width $img]
	set height [image height $img]
	set background [image create photo -width $width -height $height]
	$background put black -to 0 0 $width $height
	$background copy $img -to 0 0 $width $height
	set partial {}

	for {set y 0} {$y < $height} {incr y} {
		for {set x 0} {$x < $width} {incr x} {
			if {[$img transparency get $x $y]} { continue }
			if {[$background get $x $y] ne [$img get $x $y]} {
				lappend partial [list $x $y [$img get $x $y] [$background get $x $y]]
			}
		}
	}

	image delete $background
	return $partial
}

# width height colours opaque transparent
proc ::scidb::test::tbicon::shape {img} {
	set width [image width $img]
	set height [image height $img]
	set colours {}
	set opaque 0
	set transparent 0

	for {set y 0} {$y < $height} {incr y} {
		for {set x 0} {$x < $width} {incr x} {
			if {[$img transparency get $x $y]} {
				incr transparent
			} else {
				incr opaque
				lappend colours [$img get $x $y]
			}
		}
	}

	return [list $width $height [llength [lsort -unique $colours]] $opaque $transparent]
}

proc ::scidb::test::tbicon::openEmpty {} {
	variable opened
	foreach file $opened { catch { ::scidb::db::close $file } }
	set opened {}
	set dir [file join [::tcltest::temporaryDirectory] g27b]
	file mkdir $dir
	set file [file join $dir empty.pgn]
	set fh [open $file w]
	close $fh
	::scidb::db::open $file ::scidb::test::tbicon::ignore {} ::scidb::test::tbicon::ignore {}
	catch { ::application::switchTab board }
	update idletasks
	update
	lappend opened $file
	return $file
}

proc ::scidb::test::tbicon::closeAll {} {
	foreach file $::scidb::test::tbicon::opened {
		catch { ::scidb::db::close $file }
	}
	set ::scidb::test::tbicon::opened {}
	catch { file delete -force [file join [::tcltest::temporaryDirectory] g27b] }
}

# The toolbar button this bug was reported on: the first entry of the board's
# tools toolbar (the engine setup button).
proc ::scidb::test::tbicon::engineButton {} {
	set toolbar .application.nb.board.board.__tb__board-tools
	if {![winfo exists $toolbar]} { return "" }
	foreach child [winfo children $toolbar] {
		if {[string match {*__tbw__*} $child]} { return $child }
	}
	return ""
}

proc ::scidb::test::tbicon::walkButtons {w accName} {
	upvar 1 $accName acc
	foreach child [winfo children $w] {
		if {[string match {__tbw__*} [winfo name $child]]} {
			if {![catch { set image [$child cget -image] }] && [llength $image]} {
				lappend acc $child
			}
		}
		::scidb::test::tbicon::walkButtons $child acc
	}
	return $acc
}

tcltest::test tbicon-keyalpha-unit {keyalpha keeps a colour only where the icon is at least half opaque} -setup {
	set img [image create photo -data {
		iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAQklEQVR4nCXJoRlAUAAGwHtI
		MtUOqmoVo6i24TODDQxhAekXXD0QEpbQNSKFDXfbD0/507Xvx4lSkqSqm2qc5hfrB6DEFNYo
		00rAAAAAAElFTkSuQmCC
	}]
	# the alpha values are 0 255 100 20 / 255 140 60 0 / 255 200 127 128 /
	# 255 1 250 126: 127 is below the threshold, 128 is on it
} -body {
	::scidb::tk::image keyalpha #efefef $img

	set got {}
	set transparent {}
	for {set y 0} {$y < 4} {incr y} {
		for {set x 0} {$x < 4} {incr x} {
			lappend got [$img get $x $y]
			lappend transparent [$img transparency get $x $y]
		}
	}

	# alpha 100 and 20 fall below the threshold: the pixel is dropped, its
	# colour may stay; alpha 140 and 255 stay and are composited with the
	# background, so the icon keeps its antialiased edge colours
	set expected {
		{0 0 0} {255 0 0} {255 0 0} {255 0 0}
		{0 255 0} {108 248 108} {0 255 0} {10 20 30}
		{0 0 255} {52 52 252} {180 180 180} {209 209 209}
		{255 255 255} {1 2 3} {54 64 73} {50 60 70}
	}
	set transparentExpected {1 0 1 1  0 0 1 1  0 0 1 0  0 1 0 1}
	# compare canonical lists: the literals above are spread over lines
	list \
		[expr {[list {*}$got] eq [list {*}$expected]}] \
		[expr {[list {*}$transparent] eq [list {*}$transparentExpected]}]
} -cleanup {
	catch { image delete $img }
} -result {1 1}

tcltest::test tbicon-engine-button-image {the first board toolbar button draws its icon, not an empty or uniform photo} -setup {
	::scidb::test::tbicon::openEmpty
} -body {
	set button [::scidb::test::tbicon::engineButton]
	if {$button eq ""} { return "no first button under __tb__board-tools" }

	set image [$button cget -image]
	if {[llength $image] == 0} { return "button $button has no image" }
	if {![::scidb::test::tbicon::isPhoto $image]} { return "$image is no photo image" }

	lassign [::scidb::test::tbicon::shape $image] width height colours opaque transparent
	if {$width < 16 || $height < 16} { return "image $image is only ${width}x${height}" }
	if {$colours < 2} { return "image $image is one colour only" }
	if {$opaque == 0} { return "image $image draws nothing" }
	if {$transparent == 0} { return "image $image has no transparency" }

	# this is what makes the black square impossible on Windows
	set partial [::scidb::test::tbicon::partiallyTransparent $image]
	if {[llength $partial]} {
		return "image $image has [llength $partial] partially transparent pixels: [lrange $partial 0 3]"
	}

	return ok
} -cleanup {
	::scidb::test::tbicon::closeAll
} -result ok

tcltest::test tbicon-engine-button-disabled {the disabled image of that button is keyed as well} -setup {
	::scidb::test::tbicon::openEmpty
} -body {
	set button [::scidb::test::tbicon::engineButton]
	if {$button eq ""} { return "no first button under __tb__board-tools" }

	::toolbar::childconfigure $button -state disabled
	update idletasks
	set disabled [$button cget -image]

	::toolbar::childconfigure $button -state normal
	update idletasks
	set normal [$button cget -image]

	list \
		[expr {$disabled ne $normal}] \
		[expr {[llength [::scidb::test::tbicon::partiallyTransparent $disabled]] == 0}] \
		[expr {[llength [::scidb::test::tbicon::partiallyTransparent $normal]] == 0}]
} -cleanup {
	::scidb::test::tbicon::closeAll
} -result {1 1 1}

tcltest::test tbicon-all-toolbar-buttons {no toolbar button of the application draws a partially transparent photo} -setup {
	::scidb::test::tbicon::openEmpty
} -body {
	set buttons {}
	::scidb::test::tbicon::walkButtons .application buttons

	set checked 0
	set bad {}
	foreach button $buttons {
		set image [$button cget -image]
		if {![::scidb::test::tbicon::isPhoto $image]} { continue }
		incr checked
		set partial [::scidb::test::tbicon::partiallyTransparent $image]
		if {[llength $partial]} {
			lappend bad "$button $image ([llength $partial] pixels)"
		}
	}

	if {$checked < 10} { return "only $checked toolbar buttons found" }
	if {[llength $bad]} { return "partially transparent: [lrange $bad 0 4]" }
	expr {$checked >= 10}
} -cleanup {
	::scidb::test::tbicon::closeAll
} -result 1

tcltest::cleanupTests
